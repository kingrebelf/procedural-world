class_name Viewmodel
extends Node3D
## First-person view of what you hold. With the character assets present, your own arms
## (the player's body with everything but the arms cut away) grip the item; otherwise the
## item floats alone. Sway, swing and recoil move the whole rig.

static var _models: Dictionary = {}

var _mesh: MeshInstance3D
var _rest := Vector3(0.32, -0.3, -0.55)
var _swing_t := 1.0
var _recoil := 0.0
var _sway_t := 0.0
var _type := ""
var arms: HumanModel
var look: Dictionary = {} ## the player's appearance (set before adding to the tree)
const ARMS_REST := Vector3(0.08, -0.03, 0.0)
## One-handed tools: only the right arm, further right and lower, the tool leaning in.
const ARM_REST := Vector3(0.14, -0.07, -0.02)
const GUN_REST := Vector3(0.1, -0.02, 0.0)
const TOOL_AIM := Vector3(-0.3, 0.5, -1.0)
## A tool's head faces this far left of straight ahead, so it shows three-quarters on.
const STRIKE_YAW := 0.6

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	if HumanModel.available() and not look.is_empty():
		arms = HumanModel.new()
		arms.build(look, Eras.MEDIEVAL, "")
		arms.rotation.y = PI
		arms.position = Vector3(0, -1.55, 0.12)
		add_child(arms)
		arms.set_arms_only()
		arms.play("pistol_idle")
		# Settle the pose now (skip the cross-fade) so the grip is computed on it.
		arms.anim.advance(0.5)
	position = _rest

## The item as something a hand can hold: tools and weapons as models, anything else as
## its icon on a card.
static func prop_for(t: String, it = null) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	n.add_child(mi)
	var d := ItemDB.def(t)
	if d.get("kind", "") in ["tool", "weapon", "light"] and model(t) != null:
		mi.mesh = model(t)
		mi.material_overlay = aura_for(it)
		if t == "torch":
			mi.add_child(HandLight.torch_fire())
			# Its light burns at the head, so the torch's own shadow would black out the stick.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var q := QuadMesh.new()
		q.size = Vector2(0.2, 0.2)
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_texture = Icons.get_icon(t)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.position = Vector3(0, 0.12, 0)
	return n

static var _aura_shader: Shader

## Ranked gear shimmers in its ability's colour; Common and Uncommon stay plain.
static func aura_for(it) -> Material:
	if not it is Dictionary or Rarity.of(it) < Rarity.RARE:
		return null
	if _aura_shader == null:
		_aura_shader = load("res://src/player/rarity_aura.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _aura_shader
	m.set_shader_parameter("aura", Rarity.glow(it))
	m.set_shader_parameter("strength", 0.25 + 0.2 * (Rarity.of(it) - Rarity.RARE))
	return m

## Held like a gun: the item points along the view instead of being raised.
const POINTED := ["pulse_pistol", "pickaxe_plasma", "flashlight", "flashlight_dead"]

static func pointed(t: String) -> bool:
	return t in POINTED or ItemDB.def(t).get("ranged", false)

## Kit model, scale, and the colour the bronze metal is re-tinted to (the kit's wood,
## leather and paint stay as they are). Handles run along +Y; guns point along -Z.
## Ranged weapons are built by GunLook.
const KIT := {
	"pickaxe_iron": ["props/Pickaxe_Bronze", 0.58, Color(0.86, 0.88, 0.92)],
	"pickaxe_mythril": ["props/Pickaxe_Bronze", 0.58, Color(0.45, 0.85, 1.0)],
	"axe_iron": ["props/Axe_Bronze", 0.95, Color(0.86, 0.88, 0.92)],
	"axe_mythril": ["props/Axe_Bronze", 0.95, Color(0.45, 0.85, 1.0)],
	"sword_iron": ["props/Sword_Bronze", 0.85, Color(0.9, 0.92, 0.96)],
	"sword_runic": ["props/Sword_Bronze", 0.85, Color(0.6, 0.75, 1.0)],
	"pickaxe_plasma": ["scifi/Pistol_2", 0.34, null],
	"dagger": ["props/Sword_Bronze", 0.5, Color(0.88, 0.9, 0.95)],
	"battle_axe": ["props/Axe_Bronze", 1.15, Color(0.7, 0.72, 0.76)],
}

## Weapons with no kit model, forged from parts: handle along +Y, grip at the origin.
static func _forged(t: String) -> ArrayMesh:
	var k := MeshKit.new(5)
	var I := Transform3D.IDENTITY
	match t:
		"war_hammer":
			k.cylinder("timber", I.translated(Vector3(0, -0.12, 0)), 0.022, 0.02, 0.78, 8)
			k.box("iron", I.translated(Vector3(0, 0.62, 0)), Vector3(0.24, 0.11, 0.11))
			k.box("iron", I.translated(Vector3(0.13, 0.62, 0)), Vector3(0.03, 0.13, 0.13))
			k.box("iron", I.translated(Vector3(-0.13, 0.62, 0)), Vector3(0.03, 0.13, 0.13))
		"mace":
			k.cylinder("timber", I.translated(Vector3(0, -0.12, 0)), 0.02, 0.018, 0.62, 8)
			k.sphere("iron", I.translated(Vector3(0, 0.55, 0)), 0.075, 6, 10)
			for n in 8:
				var a := TAU * n / 8.0
				k.cylinder("iron", Transform3D(Basis(Vector3(-sin(a), 0, cos(a)), PI * 0.5), Vector3(cos(a) * 0.06, 0.55 + (0.03 if n % 2 else -0.03), sin(a) * 0.06)), 0.018, 0.0, 0.07, 5)
			k.sphere("iron", I.translated(Vector3(0, 0.64, 0)), 0.02, 4, 6)
		"spear":
			k.cylinder("timber", I.translated(Vector3(0, -0.6, 0)), 0.018, 0.018, 1.75, 8)
			k.cylinder("iron", I.translated(Vector3(0, 1.15, 0)), 0.03, 0.0, 0.26, 4)
			k.cylinder("iron", I.translated(Vector3(0, 1.1, 0)), 0.022, 0.022, 0.06, 8)
		"longbow":
			var prev := Vector3.ZERO
			for n in 13:
				var f := (n / 12.0) * 2.0 - 1.0
				var p := Vector3(0, f * 0.75, -0.16 * (1.0 - f * f))
				if n > 0:
					var d := p - prev
					var b := Basis(Vector3.UP.cross(d.normalized()).normalized(), Vector3.UP.angle_to(d)) if absf(d.normalized().y) < 0.999 else Basis.IDENTITY
					k.cylinder("timber", Transform3D(b, prev), 0.017, 0.017, d.length(), 6)
				prev = p
			k.cylinder("cloth", I.translated(Vector3(0, -0.75, 0)), 0.003, 0.003, 1.5, 4)
		"flashlight", "flashlight_dead":
			# Pointing ahead like a gun: a dark tube, a flared head, and the lens.
			var ahead := Basis(Vector3(1, 0, 0), -PI * 0.5)
			k.cylinder("metal_dark", Transform3D(ahead, Vector3(0, 0.03, 0.06)), 0.019, 0.019, 0.18, 10)
			k.cylinder("metal", Transform3D(ahead, Vector3(0, 0.03, -0.12)), 0.021, 0.031, 0.06, 10)
			k.cylinder("glow_white" if t == "flashlight" else "metal_dark", Transform3D(ahead, Vector3(0, 0.03, -0.18)), 0.028, 0.028, 0.004, 10)
		_:
			return null
	return k.commit(Materials.get_mat)

static func model(t: String) -> ArrayMesh:
	if _models.has(t):
		return _models[t]
	var out: ArrayMesh = GunLook.model(t) if GunLook.has(t) else null
	if out != null:
		_models[t] = out
		return out
	if KIT.has(t) and ResourceLoader.exists("res://assets/models/%s.gltf" % KIT[t][0]):
		var e: Array = KIT[t]
		var xf := Transform3D.IDENTITY.scaled(Vector3.ONE * e[1])
		if pointed(t):
			# The kit's guns point along +X with the grip at the origin.
			xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) * xf
		elif t.begins_with("axe_") or t == "battle_axe":
			# The kit axe's edge faces -X; turn it to face -Z, the way it swings.
			xf = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO) * xf
		out = kit_mesh(e[0], xf, e[2])
		if t == "pickaxe_plasma":
			# A glowing drill bit where the muzzle was.
			var k := MeshKit.new(3)
			k.cylinder("glow_cyan", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0.035, -0.29)), 0.028, 0.002, 0.14, 8)
			k.cylinder("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0.035, -0.215)), 0.04, 0.034, 0.03, 10)
			_append(out, k.commit(Materials.get_mat))
	elif t == "torch":
		out = HandLight.torch_model()
	elif _forged(t) != null:
		out = _forged(t)
	elif t == "hammer" and ResourceLoader.exists("res://assets/models/props/Pickaxe_Bronze.gltf"):
		# The pickaxe's wooden handle, shortened, with a squared iron head.
		out = kit_mesh("props/Pickaxe_Bronze", Transform3D.IDENTITY.scaled(Vector3(0.6, 0.5, 0.6)), null, true)
		var k := MeshKit.new(3)
		var hy := 0.25
		k.box("metal", Transform3D.IDENTITY.translated(Vector3(0.02, hy, 0)), Vector3(0.17, 0.065, 0.065))
		k.cylinder("metal", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.115, hy, 0)), 0.042, 0.042, 0.05, 10)
		k.box("metal", Transform3D(Basis(Vector3(0, 0, 1), 0.35), Vector3(-0.09, hy + 0.015, 0)), Vector3(0.07, 0.045, 0.05))
		_append(out, k.commit(Materials.get_mat))
	else:
		var def := ItemDB.def(t)
		if def.is_empty():
			return null
		var k := MeshKit.new(3)
		k.box("painted", Transform3D.IDENTITY, Vector3(0.12, 0.12, 0.12), def.get("color", Color.WHITE))
		out = k.commit(Materials.get_mat)
	_models[t] = out
	return out

static func _append(to: ArrayMesh, from: ArrayMesh) -> void:
	for i in from.get_surface_count():
		to.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, from.surface_get_arrays(i))
		to.surface_set_material(to.get_surface_count() - 1, from.surface_get_material(i))

## A kit model flattened into one mesh. `tint` re-colours the parts textured as metal
## (the bronze of the fantasy kit), keeping their shading. `wood_only` keeps only the
## parts that are not metal.
static func kit_mesh(file: String, xf: Transform3D, tint = null, wood_only := false) -> ArrayMesh:
	var scene: Node3D = (load("res://assets/models/%s.gltf" % file) as PackedScene).instantiate()
	var out := ArrayMesh.new()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var mxf: Transform3D = xf * HumanModel._rel(scene, mi)
		var m: Mesh = (mi as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var a: Array = m.surface_get_arrays(si)
			var mat: Material = BuildCatalog._tamed((mi as MeshInstance3D).get_active_material(si))
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var tans = a[Mesh.ARRAY_TANGENT]
			var nb := mxf.basis.inverse().transposed()
			for i in verts.size():
				verts[i] = mxf * verts[i]
				if norms.size() > i:
					norms[i] = (nb * norms[i]).normalized()
			if tans is PackedFloat32Array and tans.size() == verts.size() * 4:
				for i in verts.size():
					var tv := (mxf.basis * Vector3(tans[i * 4], tans[i * 4 + 1], tans[i * 4 + 2])).normalized()
					tans[i * 4] = tv.x
					tans[i * 4 + 1] = tv.y
					tans[i * 4 + 2] = tv.z
				a[Mesh.ARRAY_TANGENT] = tans
			a[Mesh.ARRAY_VERTEX] = verts
			a[Mesh.ARRAY_NORMAL] = norms
			for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
				a[c] = null
			if tint != null or wood_only:
				var metal := _metal_mask(a, mat)
				if tint != null and a[Mesh.ARRAY_COLOR] is PackedColorArray:
					var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
					for i in cols.size():
						if metal[i]:
							# Keep the kit's light and dark metal, in the new colour.
							cols[i] = Color(tint) * clampf(cols[i].r / 0.71, 0.3, 1.2)
							cols[i].a = 1.0
					a[Mesh.ARRAY_COLOR] = cols
				if wood_only and a[Mesh.ARRAY_INDEX] is PackedInt32Array:
					var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
					var keep := PackedInt32Array()
					for i in range(0, idx.size(), 3):
						if not (metal[idx[i]] or metal[idx[i + 1]] or metal[idx[i + 2]]):
							keep.append_array([idx[i], idx[i + 1], idx[i + 2]])
					a[Mesh.ARRAY_INDEX] = keep
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			out.surface_set_material(out.get_surface_count() - 1, mat)
	scene.free()
	return out

static var _tex_cache: Dictionary = {}

## Which vertices sit on the grey (metal) part of the kit's trim texture.
static func _metal_mask(a: Array, mat: Material) -> PackedByteArray:
	var n: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var mask := PackedByteArray()
	mask.resize(n)
	var tex: Texture2D = (mat as BaseMaterial3D).albedo_texture if mat is BaseMaterial3D else null
	var uv = a[Mesh.ARRAY_TEX_UV]
	if tex == null or not (uv is PackedVector2Array):
		return mask
	var img: Image = _tex_cache.get(tex.resource_path)
	if img == null:
		img = tex.get_image()
		if img.is_compressed():
			img.decompress()
		_tex_cache[tex.resource_path] = img
	var size := Vector2(img.get_size())
	for i in n:
		var p := Vector2i((uv[i] * size).posmod(size.x))
		var c := img.get_pixelv(Vector2i(clampi(p.x, 0, img.get_width() - 1), clampi(p.y, 0, img.get_height() - 1)))
		mask[i] = 1 if absf(c.r - c.b) < 0.1 and absf(c.r - c.g) < 0.1 else 0
	return mask

var _item = null

func show_item(t: String, it = null) -> void:
	if t == _type and is_same(it, _item) and t != "":
		return # same thing still in hand (an inventory change elsewhere)
	_type = t
	_item = it
	if arms:
		_mesh.mesh = null
		arms.set_arms_only(t != "")
		_rest = ARMS_REST if t == "" else (GUN_REST if pointed(t) else ARM_REST)
		_hold_later.call_deferred(t)
		return
	_mesh.mesh = model(t) if t != "" else null
	_mesh.material_overlay = aura_for(it)
	if t.begins_with("pulse"):
		_mesh.rotation = Vector3(0, 0, 0)
		_rest = Vector3(0.22, -0.2, -0.45)
	else:
		_mesh.rotation = Vector3(-0.35, 0.25, 0.15)
		_rest = Vector3(0.32, -0.3, -0.55)

## Puts the item in the arms' hand once the pose has been applied this frame.
func _hold_later(t: String) -> void:
	if t != _type or not is_inside_tree():
		return
	await get_tree().process_frame
	if t != _type:
		return
	arms.hold(prop_for(t, _item) if t != "" else null)
	_aim()

## Keeps the held item pointing the right way on screen: tools up and away, guns forward.
func _aim() -> void:
	if arms == null or _type == "":
		return
	# The rig's own frame, so the item swings with the arms.
	var b := global_transform.basis.orthonormalized()
	if pointed(_type):
		arms.reaim(arms.hand_space(b * Vector3.UP), 0.0, arms.hand_space(b * Vector3.FORWARD))
	else:
		arms.reaim(arms.hand_space(b * TOOL_AIM), 0.65)
		# The grip only fixes the handle: turn the head about it so what strikes faces
		# ahead: an axe's edge (local -Z), a pick's point or a hammer's face (local +X).
		var strike := _strike_axis(_type)
		if strike != Vector3.ZERO and arms._held != null and arms._held.get_child_count() > 0:
			var prop := arms._held.get_child(0) as Node3D
			var want := prop.global_basis.inverse() * (b * (Basis(Vector3.UP, STRIKE_YAW) * Vector3.FORWARD))
			want.y = 0.0
			if want.length() > 0.01:
				# About +Y, from the striking axis towards `want`.
				var turn := Vector2(strike.x, -strike.z).angle_to(Vector2(want.x, -want.z))
				prop.basis = prop.basis * Basis(Vector3.UP, turn)

## Which way the business end of a held tool faces in its model (Vector3.ZERO: no turn).
static func _strike_axis(t: String) -> Vector3:
	if t.begins_with("axe_") or t == "battle_axe":
		return Vector3.FORWARD
	if t.begins_with("pickaxe_") and t != "pickaxe_plasma" or t == "hammer":
		return Vector3.RIGHT
	return Vector3.ZERO

func swing() -> void:
	_swing_t = 0.0

## A shot's kick: the gun jumps back and its muzzle climbs, more for heavy weapons.
func recoil(strength := 1.0) -> void:
	_recoil = clampf(strength, 0.3, 2.0)

## Lowers the gun out of view and brings it back up, for a reload.
func reload_dip() -> void:
	_dip_t = 0.0

var ads := 0.0 ## set by Gunplay: 0 hip, 1 looking down the sights
var _dip_t := 1.0
var _ads_off := Vector3.ZERO

## The held item's mesh, wherever it is (the arms' hand, or floating alone).
func _held_mesh() -> MeshInstance3D:
	if arms == null:
		return _mesh if _mesh.mesh != null else null
	if arms._held == null or arms._held.get_child_count() == 0:
		return null
	var prop := arms._held.get_child(0)
	return prop.get_child(0) as MeshInstance3D if prop.get_child_count() > 0 else null

## Where shots leave the barrel: the front of the gun (guns point along -Z), a little
## below the top.
func muzzle() -> Vector3:
	var mi := _held_mesh()
	if mi == null or mi.mesh == null:
		return global_position + global_transform.basis * Vector3(0, -0.05, -0.6)
	var b := mi.mesh.get_aabb()
	return mi.global_transform * Vector3(b.get_center().x, b.position.y + b.size.y * 0.75, b.position.z)

## The point on the gun's top that lines up with the eye when aiming, in the rig's
## own space.
func _sight_local() -> Vector3:
	var mi := _held_mesh()
	if mi == null or mi.mesh == null:
		return Vector3.ZERO
	var b := mi.mesh.get_aabb()
	var top := mi.global_transform * Vector3(b.get_center().x, b.end.y, b.get_center().z)
	return global_transform.affine_inverse() * top

func sway(delta: float, speed: float) -> void:
	var steady := 1.0 - 0.85 * ads
	_sway_t += delta * (1.0 + speed * 6.0)
	_swing_t = minf(1.0, _swing_t + delta * 2.4)
	_recoil = maxf(0.0, _recoil - delta * 8.0)
	_dip_t = minf(1.0, _dip_t + delta * 1.4)
	var s := sin(_swing_t * PI)
	var dip := sin(_dip_t * PI) # down and back up over a reload
	var off := Vector3(sin(_sway_t) * 0.006 * (1.0 + speed * 3.0), absf(cos(_sway_t)) * 0.006 * (1.0 + speed * 3.0), _recoil * 0.06) * Vector3(steady, steady, 1.0)
	# Aiming: slide the rig so the gun's top sits on the line of sight.
	if ads > 0.001 and pointed(_type):
		var sl := _sight_local()
		var want := Vector3(-sl.x - _rest.x, -sl.y - _rest.y - 0.012, 0.06)
		_ads_off = _ads_off.lerp(want, clampf(delta * 20.0, 0.0, 1.0))
	var aim_off := _ads_off * smoothstep(0.0, 1.0, ads)
	if arms:
		# The whole rig swings down and across from just in front of the eyes.
		position = _rest + aim_off + off + Vector3(-0.05 * s, -0.06 * s, -0.12 * s) + Vector3(0, -0.18 * dip, _recoil * 0.04 + 0.05 * dip)
		rotation = Vector3(-0.9 * s + _recoil * (0.12 * steady + 0.03) - 0.5 * dip, 0.25 * s, 0.35 * s + 0.4 * dip)
		_aim()
		return
	position = _rest + aim_off + off + Vector3(-0.12 * s, 0.05 * s, -0.1 * s) + Vector3(0, -0.18 * dip, 0.05 * dip)
	rotation = Vector3(-1.1 * s + _recoil * 0.25 * steady - 0.5 * dip, 0.3 * s, 0.3 * s + 0.4 * dip)

func tracer(world_end: Vector3, mat := "glow_cyan") -> void:
	var from := _mesh.global_position if arms == null else global_position + global_transform.basis * Vector3(0, -0.12, -0.5)
	var start := from + -global_transform.basis.z * 0.25
	var len := start.distance_to(world_end)
	if len < 0.1:
		return
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = len
	cm.radial_segments = 6
	beam.mesh = cm
	if mat == "bolt":
		# A crossbow bolt: a thin dark shaft, not a beam of light.
		cm.top_radius = 0.008
		cm.bottom_radius = 0.008
		mat = "bark"
	beam.material_override = Materials.get_mat(mat)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(beam)
	var mid := (start + world_end) * 0.5
	beam.global_position = mid
	var dir := (world_end - start).normalized()
	beam.global_transform.basis = Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir)) if absf(dir.dot(Vector3.UP)) < 0.999 else Basis()
	var tw := beam.create_tween()
	tw.tween_property(beam, "scale", Vector3(0.1, 1, 0.1), 0.12)
	tw.tween_callback(beam.queue_free)
