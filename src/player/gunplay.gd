class_name Gunplay
extends Node
## Ranged weapons in the player's hands: magazines and reloading, aiming down the sights,
## spread that grows when you move, jump or hold the trigger down and tightens when you
## aim or crouch, recoil that kicks the view up and mostly settles back, and shots that
## fly as projectiles (bolts and arrows drop, energy bolts barely) rather than landing
## the instant you fire. Effects: muzzle flash and light, smoke from black powder, sparks
## or dust where shots land, arrows that stay stuck where they hit.
##
## Sound hooks: `gun_event` fires for "fire", "dry" (empty click), "reload_start",
## "reload_round" (one round or arrow loaded), "reload_end" and "impact" (with what was
## hit in `what`: "creature", "npc", "stone", "wood", "metal", "ground").

signal gun_event(kind: String, type: String, at: Vector3, what: String)

## Handling per weapon. mag: rounds per magazine (energy weapons: shots per power cell,
## so one cell is one magazine). reload: seconds (per round when per_round). recoil:
## degrees the view kicks up per shot. spread: hip-fire cone in degrees. speed: muzzle
## velocity, m/s. drop: share of gravity the shot feels. zoom: view magnification when
## aiming. auto_reload: nock or span the next shot without being asked (bows,
## crossbows). powder: black powder smoke and a bright flash.
const HANDLING := {
	"pulse_pistol": {"mag": 12, "reload": 1.3, "recoil": 1.6, "spread": 1.4, "speed": 160.0, "drop": 0.05, "zoom": 1.3},
	"pulse_smg": {"mag": 45, "reload": 1.8, "recoil": 0.8, "spread": 2.6, "speed": 170.0, "drop": 0.05, "zoom": 1.3},
	"pulse_rifle": {"mag": 30, "reload": 2.1, "recoil": 1.1, "spread": 1.6, "speed": 230.0, "drop": 0.05, "zoom": 1.7},
	"rail_rifle": {"mag": 6, "reload": 2.8, "recoil": 6.5, "spread": 0.8, "speed": 1200.0, "drop": 0.0, "zoom": 4.0, "ads_spread": 0.02},
	"arc_launcher": {"mag": 4, "reload": 2.6, "recoil": 5.0, "spread": 1.2, "speed": 55.0, "drop": 0.6, "zoom": 1.3},
	"scrap_pistol": {"mag": 6, "reload": 0.45, "per_round": true, "recoil": 4.5, "spread": 1.6, "speed": 280.0, "drop": 1.0, "zoom": 1.3, "powder": true},
	"crossbow": {"mag": 1, "reload": 1.7, "recoil": 1.2, "spread": 0.5, "speed": 75.0, "drop": 1.0, "zoom": 1.4, "auto_reload": true},
	"crossbow_runic": {"mag": 5, "reload": 0.5, "per_round": true, "recoil": 0.9, "spread": 0.6, "speed": 95.0, "drop": 0.6, "zoom": 1.4, "auto_reload": true},
	"longbow": {"mag": 1, "reload": 0.7, "recoil": 0.6, "spread": 0.9, "speed": 65.0, "drop": 1.0, "zoom": 1.25, "auto_reload": true},
}
const DEFAULT := {"mag": 10, "reload": 1.6, "recoil": 1.5, "spread": 1.5, "speed": 150.0, "drop": 0.2, "zoom": 1.3}
const MAX_SHOTS := 64
const MAX_STUCK := 24

var player: Player
var ads := 0.0 ## 0 hip fire .. 1 sighted
var bloom := 0.0 ## extra spread (degrees) from sustained fire
var reload_left := 0.0
var reload_total := 0.0
var _reload_uid := -1
var _kick := Vector2.ZERO ## recoil still to apply this burst (pitch, yaw), radians
var _settle := 0.0 ## pitch the view drifts back down by
var _shots: Array = []
var _stuck: Array = []
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

static func handling(t: String) -> Dictionary:
	return HANDLING.get(t, DEFAULT)

## The held weapon if it is a ranged one, else null.
func held():
	var it = player.held_item()
	if it == null or not ItemDB.def(it["type"]).get("ranged", false):
		return null
	return it

func reloading() -> bool:
	return reload_left > 0.0

func rounds(it) -> int:
	return int(it.get("charge", 0)) if it is Dictionary else 0

## Rounds you could still load: ammo carried times shots per ammo.
func reserve(it) -> int:
	var d := ItemDB.def(it["type"])
	return Game.inventory.count(String(d.get("ammo", ""))) * int(d.get("shots_per_ammo", 1))

func mag_size(t: String) -> int:
	return int(handling(t)["mag"])

## The view's magnification while aiming (1 at the hip).
func zoom() -> float:
	var it = held()
	if it == null:
		return 1.0
	return lerpf(1.0, float(handling(it["type"])["zoom"]), smoothstep(0.0, 1.0, ads))

## Current cone half-angle, degrees.
func spread_deg() -> float:
	var it = held()
	if it == null:
		return 0.0
	var h := handling(it["type"])
	var base := float(h["spread"])
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	var s := base * (1.0 + 1.6 * clampf(hv / Player.SPRINT, 0.0, 1.0) + (2.5 if not player.is_on_floor() else 0.0)) + bloom
	s *= lerpf(1.0, float(h.get("ads_spread", 0.3)), ads)
	if player._crouched:
		s *= 0.75
	return s

func _physics_process(delta: float) -> void:
	if player == null:
		return
	_step_shots(delta)
	var it = held()
	var aiming: bool = it != null and not player.ui_open and Input.is_action_pressed("aim")
	var ads_time := 0.28 if it != null and float(handling(it["type"])["zoom"]) > 1.5 else 0.18
	ads = move_toward(ads, 1.0 if aiming and not reloading() else 0.0, delta / ads_time)
	bloom = move_toward(bloom, 0.0, delta * (6.0 + bloom * 3.0))
	_recoil_step(delta)
	if reloading():
		if it == null or int(it.get("uid", -2)) != _reload_uid:
			_cancel_reload()
		else:
			reload_left -= delta * (1.25 if Rarity.has_affix(it, "swift") else 1.0)
			if reload_left <= 0.0:
				_finish_reload(it)
	if it != null and not player.ui_open and Input.is_action_just_pressed("reload"):
		start_reload(it)

# --- Firing ---------------------------------------------------------------------------

## One pull of the trigger (or one tick of a held trigger on automatic weapons).
func fire(it: Dictionary, d: Dictionary) -> void:
	var t: String = it["type"]
	var h := handling(t)
	if reloading():
		# A revolver or repeater can fire what is already loaded, ending the reload.
		if h.get("per_round", false) and rounds(it) > 0:
			_cancel_reload()
		else:
			return
	if rounds(it) <= 0:
		player._cooldown = 0.35
		if not start_reload(it):
			gun_event.emit("dry", t, player.global_position, "")
			Game.toast.emit("Out of %s" % ItemDB.def(String(d.get("ammo", "")))["name"])
		return
	it["charge"] = rounds(it) - 1
	player._cooldown = float(d.get("cooldown", 0.22))
	var cam := player.camera
	var fwd := -cam.global_transform.basis.z
	var dir := _scatter(fwd, deg_to_rad(spread_deg()))
	var muzzle := player.viewmodel.muzzle() if not player.third_person else cam.global_position + fwd * 0.6
	var shot := {
		"pos": cam.global_position, "vel": dir * float(h["speed"]) + player.velocity * 0.3,
		"drop": float(h["drop"]), "life": float(d.get("range", 60.0)) / float(h["speed"]) + 0.5,
		"left": float(d.get("range", 60.0)) * 1.15, "item": it, "d": d, "type": t,
		# The tracer starts at the muzzle and closes onto the line of sight over 10 m.
		"vis": muzzle - cam.global_position,
	}
	shot["node"] = _shot_visual(t, d)
	if _shots.size() >= MAX_SHOTS:
		_drop_shot(0)
	_shots.append(shot)
	_place_visual(shot)
	_recoil_kick(h)
	bloom = minf(bloom + float(h["recoil"]) * 0.35, float(h["spread"]) * 3.0 + 2.0)
	player.viewmodel.recoil(clampf(float(h["recoil"]) / 3.0, 0.4, 2.0))
	if player.body:
		player.body.play_once("pistol", 0.4)
	_muzzle_fx(t, d, muzzle, fwd)
	gun_event.emit("fire", t, muzzle, "")
	player.used_tool.emit("fire")
	if rounds(it) == 0 and h.get("auto_reload", false):
		start_reload(it)

## A direction within `cone` radians of `fwd`, denser towards the middle.
static func _scatter(fwd: Vector3, cone: float) -> Vector3:
	if cone <= 0.0:
		return fwd
	var side := fwd.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(fwd).normalized()
	var r := cone * sqrt(randf()) * (0.6 + 0.4 * randf())
	var a := randf() * TAU
	return (fwd + side * tan(r) * cos(a) + up * tan(r) * sin(a)).normalized()

# --- Reloading ------------------------------------------------------------------------

## True when Reload would load something into the held weapon right now.
func wants_reload() -> bool:
	var it = held()
	return it != null and not reloading() and rounds(it) < mag_size(it["type"]) and reserve(it) > 0

## Starts loading the held weapon. False when there is nothing to load (full, or no ammo).
func start_reload(it) -> bool:
	if it == null or reloading():
		return false
	var t: String = it["type"]
	var h := handling(t)
	if rounds(it) >= mag_size(t):
		return false
	if reserve(it) <= 0:
		return false
	var spa := int(ItemDB.def(t).get("shots_per_ammo", 1))
	if spa > 1 and rounds(it) > 0 and Game.inventory.count(String(ItemDB.def(t)["ammo"])) <= 0:
		return false
	_reload_uid = int(it.get("uid", -1))
	reload_total = float(h["reload"])
	reload_left = reload_total
	player.viewmodel.reload_dip()
	gun_event.emit("reload_start", t, player.global_position, "")
	return true

func _finish_reload(it: Dictionary) -> void:
	var t: String = it["type"]
	var h := handling(t)
	var d := ItemDB.def(t)
	var ammo := String(d.get("ammo", ""))
	var spa := int(d.get("shots_per_ammo", 1))
	reload_left = 0.0
	if spa > 1:
		# A fresh cell: whatever was left in the old one is spent.
		if Game.inventory.remove_type(ammo, 1) > 0:
			it["charge"] = mag_size(t)
	elif h.get("per_round", false):
		if Game.inventory.remove_type(ammo, 1) > 0:
			it["charge"] = rounds(it) + 1
			gun_event.emit("reload_round", t, player.global_position, "")
		if rounds(it) < mag_size(t) and reserve(it) > 0:
			reload_left = reload_total
			return
	else:
		it["charge"] = rounds(it) + Game.inventory.remove_type(ammo, mag_size(t) - rounds(it))
	_reload_uid = -1
	gun_event.emit("reload_end", t, player.global_position, "")

func _cancel_reload() -> void:
	reload_left = 0.0
	_reload_uid = -1

## 0..1 through the current reload (per round: through the current round).
func reload_progress() -> float:
	return 1.0 - reload_left / maxf(reload_total, 0.01) if reloading() else 0.0

# --- Recoil ---------------------------------------------------------------------------

func _recoil_kick(h: Dictionary) -> void:
	var r := deg_to_rad(float(h["recoil"])) * lerpf(1.0, 0.65, ads) * randf_range(0.85, 1.15)
	if player._crouched:
		r *= 0.8
	# Strong arms hold the muzzle down.
	r /= clampf(Game.stats.damage_mult(), 1.0, 1.6)
	_kick += Vector2(r, r * randf_range(-0.35, 0.35))

## The kick lands over a few frames (snappy, not a teleport), then most of the climb
## drifts back, so steady fire walks up a little and single shots return to the mark.
func _recoil_step(delta: float) -> void:
	if _kick.length() > 0.00001:
		var f := clampf(delta * 28.0, 0.0, 1.0)
		var step := _kick * f
		_kick -= step
		player._pitch = clampf(player._pitch + step.x, -1.5, 1.5)
		player._yaw += step.y
		_settle += step.x * 0.7
		player._apply_look()
	elif _settle > 0.00001:
		var back := minf(_settle, maxf(_settle * delta * 7.0, delta * 0.02))
		_settle -= back
		player._pitch = clampf(player._pitch - back, -1.5, 1.5)
		player._apply_look()

## Your own mouse pulling down counters the climb, so it isn't given back twice.
func on_look(pitch_delta: float) -> void:
	if pitch_delta < 0.0:
		_settle = maxf(0.0, _settle + pitch_delta)

# --- Flight ---------------------------------------------------------------------------

func _step_shots(delta: float) -> void:
	if _shots.is_empty():
		return
	var space := player.get_world_3d().direct_space_state
	var i := 0
	while i < _shots.size():
		var s: Dictionary = _shots[i]
		var vel: Vector3 = s["vel"]
		vel.y -= _gravity * float(s["drop"]) * delta
		s["vel"] = vel
		var from: Vector3 = s["pos"]
		var to := from + vel * delta
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [player.get_rid()])
		var hit := space.intersect_ray(q)
		s["life"] = float(s["life"]) - delta
		s["left"] = float(s["left"]) - from.distance_to(to)
		if not hit.is_empty():
			s["pos"] = hit["position"]
			_impact(s, hit)
			_drop_shot(i, hit)
			continue
		s["pos"] = to
		s["vis"] = (s["vis"] as Vector3).move_toward(Vector3.ZERO, vel.length() * delta * 0.1)
		_place_visual(s)
		if float(s["life"]) <= 0.0 or float(s["left"]) <= 0.0:
			if s["d"].has("splash"):
				_impact(s, {"position": to})
			_drop_shot(i)
			continue
		i += 1

func _impact(s: Dictionary, hit: Dictionary) -> void:
	var at: Vector3 = hit["position"]
	var what := player.ranged_hit(s["item"], s["d"], hit, at)
	var n: Vector3 = hit.get("normal", -(s["vel"] as Vector3).normalized())
	_impact_fx(String(s["type"]), s["d"], at, n, what)
	gun_event.emit("impact", String(s["type"]), at, what)

func _drop_shot(i: int, hit := {}) -> void:
	var s: Dictionary = _shots[i]
	_shots.remove_at(i)
	var node: Node3D = s.get("node")
	if node == null or not is_instance_valid(node):
		return
	if s.get("arrow", false) and not hit.is_empty() and hit.get("collider") is Object and not (hit["collider"] as Object).has_meta("creature") and not (hit["collider"] as Object).has_meta("npc"):
		# Bolts and arrows stay where they struck, buried a little way in.
		var dir := (s["vel"] as Vector3).normalized()
		node.global_position = (hit["position"] as Vector3) - dir * 0.12
		_stuck.append(node)
		if _stuck.size() > MAX_STUCK:
			var old: Node3D = _stuck.pop_front()
			if is_instance_valid(old):
				old.queue_free()
		get_tree().create_timer(40.0).timeout.connect(func():
			if is_instance_valid(node):
				_stuck.erase(node)
				node.queue_free())
		return
	node.queue_free()

# --- Looks ----------------------------------------------------------------------------

static var _meshes: Dictionary = {}

## What flies: a glowing bolt of energy, a bullet's faint tracer, or a bolt or arrow.
func _shot_visual(t: String, d: Dictionary) -> Node3D:
	var tr := String(d.get("tracer", "glow_cyan"))
	var n := MeshInstance3D.new()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if tr == "bolt":
		n.mesh = _arrow_mesh(t == "longbow")
	else:
		var key := "streak_" + tr
		if not _meshes.has(key):
			var b := BoxMesh.new()
			var thick := 0.012 if tr == "glow_warm" else 0.03
			b.size = Vector3(thick, thick, 1.0)
			b.material = GunLook.mat(tr) if tr != "glow_warm" else Materials.get_mat(tr)
			_meshes[key] = b
		n.mesh = _meshes[key]
	player.get_tree().current_scene.add_child(n)
	return n

static func _arrow_mesh(fletched: bool) -> ArrayMesh:
	var key := "arrow" if fletched else "bolt"
	if _meshes.has(key):
		return _meshes[key]
	var k := MeshKit.new(3)
	var len := 0.75 if fletched else 0.38
	var z := Basis(Vector3(1, 0, 0), -PI * 0.5)
	k.cylinder("gun_ash", Transform3D(z, Vector3(0, 0, len * 0.5)), 0.005, 0.005, len - 0.04, 6)
	k.cylinder("gun_iron", Transform3D(z, Vector3(0, 0, -len * 0.5 + 0.04)), 0.008, 0.0, 0.05, 6)
	for a in 3:
		var r := Basis(Vector3(0, 0, 1), TAU * a / 3.0)
		k.box("cloth" if fletched else "gun_leather", Transform3D(r, r * Vector3(0, 0.012, len * 0.5 - 0.06)), Vector3(0.002, 0.018, 0.1 if fletched else 0.05))
	var m := k.commit(GunLook.mat)
	_meshes[key] = m
	return m

func _place_visual(s: Dictionary) -> void:
	var node: Node3D = s.get("node")
	if node == null or not is_instance_valid(node):
		return
	var vel: Vector3 = s["vel"]
	var dir := vel.normalized()
	var pos: Vector3 = (s["pos"] as Vector3) + (s["vis"] as Vector3)
	if (node as MeshInstance3D).mesh is BoxMesh:
		# A streak trailing behind the shot, stretched with its speed.
		var len := clampf(vel.length() * 0.025, 0.3, 7.0)
		len = maxf(0.05, minf(len, (s["pos"] as Vector3).distance_to(player.camera.global_position) * 0.5))
		node.global_transform = Transform3D(Basis.looking_at(dir), pos - dir * len * 0.5).scaled_local(Vector3(1, 1, len))
	else:
		s["arrow"] = true
		node.global_transform = Transform3D(Basis.looking_at(dir), pos)

static var _fx_shaders: Dictionary = {}
static var _fx_tex: Dictionary = {}

## A camera-facing flipbook card (4 x 4 frames): additive for fire and sparks, blended
## for smoke. Animate its "frame" instance parameter.
static func _fx_mat(sheet: String, additive: bool) -> ShaderMaterial:
	var key := sheet + str(additive)
	if not _fx_shaders.has(key):
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, %s, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
instance uniform float frame = 0.0;
instance uniform float spin = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
void vertex() {
	float c = cos(spin), s = sin(spin);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc.x, INV_VIEW_MATRIX[1] * sc.y, INV_VIEW_MATRIX[2] * sc.z, MODEL_MATRIX[3]);
	float f = floor(clamp(frame, 0.0, 15.0));
	UV = (UV + vec2(mod(f, 4.0), floor(f / 4.0))) / 4.0;
}
void fragment() {
	vec4 t = texture(tex, UV) * tint;
	ALBEDO = t.rgb;
	ALPHA = %s;
}
""" % ["blend_add" if additive else "blend_mix", "tint.a" if additive else "t.a"]
		var m := ShaderMaterial.new()
		m.shader = sh
		if not _fx_tex.has(sheet):
			_fx_tex[sheet] = load("res://assets/textures/fx/%s_flipbook.png" % sheet) if ResourceLoader.exists("res://assets/textures/fx/%s_flipbook.png" % sheet) else null
		m.set_shader_parameter("tex", _fx_tex[sheet])
		_fx_shaders[key] = m
	return _fx_shaders[key]

func _flipbook(sheet: String, additive: bool, at: Vector3, size: float, dur: float, tint: Color, frames := Vector2(0, 15), rise := Vector3.ZERO, grow := 1.0) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _fx_mat(sheet, additive)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_tree().current_scene.add_child(mi)
	mi.global_position = at
	mi.set_instance_shader_parameter("spin", randf() * TAU)
	mi.set_instance_shader_parameter("tint", tint)
	mi.set_instance_shader_parameter("frame", frames.x)
	var tw := mi.create_tween().set_parallel()
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("frame", v), frames.x, frames.y + 0.99, dur)
	if rise != Vector3.ZERO:
		tw.tween_property(mi, "global_position", at + rise, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if grow != 1.0:
		tw.tween_property(mi, "scale", Vector3.ONE * grow, dur).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(mi.queue_free)

func _flash_light(at: Vector3, col: Color, energy: float, rng: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	player.get_tree().current_scene.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)

func _muzzle_fx(t: String, d: Dictionary, at: Vector3, fwd: Vector3) -> void:
	var tr := String(d.get("tracer", "glow_cyan"))
	if tr == "bolt":
		return
	var h := handling(t)
	if h.get("powder", false):
		_flipbook("sparks", true, at + fwd * 0.05, 0.32, 0.06, Color(1.0, 0.85, 0.6, 1.0), Vector2(3, 5))
		_flash_light(at, Color(1.0, 0.7, 0.4), 3.0, 6.0, 0.07)
		_flipbook("smoke", false, at + fwd * 0.15, 0.25, 1.4, Color(0.8, 0.78, 0.75, 0.55), Vector2(0, 13), fwd * 0.4 + Vector3(0, 0.35, 0), 3.0)
	else:
		var c: Color = GunLook.GLOW.get(tr, Color(0.4, 0.9, 1.0))
		_flipbook("sparks", true, at + fwd * 0.03, 0.18, 0.05, Color(c.r, c.g, c.b, 0.9), Vector2(0, 2))
		_flash_light(at, c, 1.6, 4.0, 0.06)

func _impact_fx(t: String, d: Dictionary, at: Vector3, n: Vector3, what: String) -> void:
	var tr := String(d.get("tracer", "glow_cyan"))
	var out := at + n * 0.05
	if d.has("splash"):
		_flipbook("sparks", true, out, float(d["splash"]) * 0.8, 0.35, Color(0.8, 0.55, 1.0, 1.0), Vector2(2, 13))
		_flipbook("smoke", false, out, 1.5, 2.0, Color(0.55, 0.5, 0.6, 0.6), Vector2(0, 14), Vector3(0, 1.2, 0), 2.5)
		_flash_light(out, Color(0.75, 0.5, 1.0), 6.0, float(d["splash"]) * 2.5, 0.25)
		return
	match what:
		"creature", "npc":
			_flipbook("smoke", false, out, 0.35, 0.5, Color(0.45, 0.05, 0.04, 0.85), Vector2(1, 10), Vector3(0, -0.15, 0), 1.6)
		"stone", "metal":
			if tr != "bolt":
				_flipbook("sparks", true, out, 0.4, 0.22, Color(1, 0.9, 0.7, 1) if not tr.begins_with("glow") or tr == "glow_warm" else GunLook.GLOW.get(tr, Color.WHITE), Vector2(1, 9))
			_flipbook("smoke", false, out, 0.3, 0.8, Color(0.6, 0.58, 0.55, 0.5), Vector2(0, 12), n * 0.3, 2.0)
		_:
			# Earth, wood or leaves: a puff of dust and splinters.
			_flipbook("smoke", false, out, 0.35, 0.9, Color(0.5, 0.42, 0.32, 0.6), Vector2(0, 12), n * 0.35 + Vector3(0, 0.15, 0), 2.2)
