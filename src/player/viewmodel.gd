class_name Viewmodel
extends Node3D
## First-person view of what you hold. With the character assets present, your own arms
## (the player's body with everything but the arms cut away) grip the item; otherwise the
## item floats alone. Sway, swing and recoil move the whole rig.

static var _models: Dictionary = {}

var _mesh: MeshInstance3D
var _rest := Vector3(0.32, -0.3, -0.55)
var _swing_t := 1.0
var _swing_len := 0.42 ## seconds the whole swing takes
var _peak := 1.0 ## how far the swing got before coming back (less when it hit something)
var _hold := 0.0 ## seconds left resting against what it hit
var _landed := false
var _hit := {} ## the world "point" and "normal" this swing lands on
var _off_full := Vector3.ZERO ## the drift that brings the edge onto the target
var _tip_pts := PackedVector3Array()
var _tip_of: Mesh ## the mesh _tip_pts were taken from
## Set by the player each frame: the surface the crosshair is on, when it is close
## ("point", "normal"), so the held item rests against it instead of sinking in.
var near := {}
var _recoil := 0.0
var _sway_t := 0.0
var _type := ""
var arms: HumanModel
var look: Dictionary = {} ## the player's appearance (set before adding to the tree)
## Empty hands hang below the view (raised with nothing in them they read as claws);
## they come up into it for a punch or a gesture.
const ARMS_REST := Vector3(0.08, -0.24, 0.04)
## One-handed tools: only the right arm, the fist low and right of the middle, held out a
## little so the whole hand and the handle below it show.
const ARM_REST := Vector3(-0.02, -0.05, -0.1)
const GUN_REST := Vector3(0.1, -0.02, 0.0)
## Binoculars ride lower and nearer the middle, so they read as facing ahead.
const BINO_REST := Vector3(0.0, -0.04, 0.02)
## A crossbow is long and wide: held further out and lower, so the prod sits under the
## sight line and the butt clears the corner of the screen.
const CROSSBOW_REST := Vector3(0.06, -0.06, -0.12)
const TOOL_AIM := Vector3(-0.1, 0.9, -0.85)
## A bow stands out at arm's length, low, its top canted in toward the middle of the view,
## so most of the stave is below the frame and the upper limb crosses it.
const BOW_REST := Vector3(-0.02, -0.1, -0.06)
## Lights carried by a ring or bail, hanging below the fist: the hand is raised and held
## upright so the lamp hangs in front of you, not below the view.
const HANGING := ["hand_lantern", "lamp_kerosene"]
const HANG_REST := Vector3(-0.08, 0.04, -0.3)
## Where the fist holding a lamp sits, from the eye.
const HANG_HAND := Vector3(-0.03, -0.05, -0.4)
const HANG_AIM := Vector3(0.05, 1.0, 0.0)
## Each kind of tool has its own hold. A pick or hammer is held with the handle upright,
## so its point or face leads straight down the view; a spear low and nearly level, its
## point ahead; an axe, sword or anything else leaning forward (TOOL_AIM).
const PICK_AIM := Vector3(-0.15, 1.0, -1.0)
const SPEARS := ["hunting_spear", "bronze_spear", "javelin", "glaive", "halberd", "quarterstaff", "void_lance"]
const SPEAR_AIM := Vector3(-0.08, 0.35, -1.0)
const SPEAR_REST := Vector3(-0.04, 0.0, -0.04)
const PICK_REST := Vector3(-0.04, -0.15, -0.14)
## Tools whose working end is below the hand (a shovel's blade): held the other way up,
## the blade raised ahead, the shaft running down past the wrist.
const BLADE_UP := ["shovel"]
## A bow's riser is gripped by its own thickness, not the string's distance from it.
const BOW_GRIP_R := 0.016
## Where the first-person body stands under the eye.
const ARMS_AT := Vector3(0, -1.55, 0.12)
## A gun held in both hands: the body turned to the right, the left shoulder forward so
## the support hand reaches the fore-end.
const LONG_YAW := -0.5
const LONG_REST := Vector3.ZERO
## The support hand under a fore-end: palm up and a little in, fingers across to the right
## and a little ahead.
const SUPPORT_PALM := Vector3(0.25, 1.0, 0.0)
const SUPPORT_FINGERS := Vector3(1.0, -0.1, -0.45)
## Anything else you carry (food, a bottle, an ingot, a gauge) is held up nearer the middle
## of the view to be looked at: upright in a loose fist, the back of the hand turned out a
## little, and its face (+Z of the model) turned to your eye.
const CARRY_REST := Vector3(-0.07, 0.02, -0.02)
const CARRY_AIM := Vector3(-0.15, 1.0, -0.25)
const CARRY_PALM := Vector3(-1.0, 0.0, 0.2)
## Which way the palm of a hand holding a tool faces: ahead and in toward the middle, the
## way you hold a hammer or a pick ready: thumb on top, knuckles to the right.
const TOOL_PALM := Vector3(-0.6, -0.2, -1.0)
## Where a gun sits in the view (the rig's frame; Viewmodel._hold_gun): the stock's butt
## below and right of the eye, just inboard of the shoulder joint; a pistol's grip out
## ahead below the line of sight (so its barrel reads as pointing ahead, not off toward
## the middle of the view); a heavy gun's grip (stockless, or too big to shoulder at
## rest: HIP) at the hip; a bow's grip ahead, its stave canted left.
const LONG_BUTT := Vector3(0.12, -0.22, 0.16)
## A shouldered gun's barrel is turned in this far toward the middle of the view, so its
## side shows rather than the gun being seen end-on along its barrel.
const LONG_TOE := 0.12
const BUTT_POCKET := Vector3(-0.05, -0.03, -0.03)
const HIP := ["minigun", "rocket_launcher"]
const SHOULDER_AT := Vector3(0.17, -0.21, 0.04)
const PISTOL_GRIP := Vector3(0.0, -0.15, -0.34)
const HEAVY_GRIP := Vector3(0.14, -0.32, -0.2)
const BOW_GRIP := Vector3(0.1, -0.12, -0.38)
const BOW_CANT := 0.3
## A tool's head faces this far left of straight ahead: a pick's point and an axe's edge
## lead the swing, turned just enough to show the head three-quarters on.
const STRIKE_YAW := 0.1
## An axe's edge is turned a little further, so the blade's face shows and it reads as an
## axe rather than a thin spike seen edge-on.
const AXE_YAW := 0.35
## The swing's phases over its time (0..1): wind-up until WIND, the strike until STRIKE
## (full reach), recovery after. BACK: how far the wind-up draws back; CONTACT: the swing
## amount where the edge is brought onto what it was aimed at.
const WIND := 0.26
const STRIKE := 0.44
const BACK := -0.3
const CONTACT := 0.7
const HOLD := 0.07 ## seconds the edge rests in the surface before coming back
## How far the rig may drift to put the edge on the target (metres, camera frame).
const REACH_SIDE := 0.22
const REACH_UP := 0.22
const REACH_DOWN := 0.25
const REACH_OUT := 0.3
const REACH_IN := 0.25
const TIP_POINTS := 320

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	if HumanModel.available() and not look.is_empty():
		arms = HumanModel.new()
		arms.build(look, Eras.MEDIEVAL, "")
		arms.rotation.y = PI
		arms.position = ARMS_AT
		add_child(arms)
		arms.set_arms_only()
		arms.set_riding_camera()
		# Armour you wear shows on your arms and hands too.
		var g := get_node_or_null("/root/Game")
		if g != null:
			arms.wear(g.equipment)
			g.equipment_changed.connect(func(): arms.wear(g.equipment))
		arms.play("pistol_idle")
		# Settle the pose now (skip the cross-fade) so the grip is computed on it.
		arms.advance(0.5)
	position = _rest

## The item as something a hand can hold: tools, weapons and materials as models, anything
## else as its icon on a card.
static func prop_for(t: String, it = null) -> Node3D:
	var n := Node3D.new()
	n.set_meta("item", t)
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
	elif ItemModels.has(t):
		# Materials, parts and gear modelled at their real size (see ItemModels).
		mi.mesh = ItemModels.model(t)
		mi.rotation.y = ItemModels.FACE_YAW
		mi.material_overlay = aura_for(it)
	elif Provisions.has(t):
		mi.mesh = Provisions.model(t)
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
const POINTED := ["pulse_pistol", "pickaxe_plasma", "flashlight", "flashlight_dead", "binoculars"]

## Bows are held like a tool, fist closed round the middle of the stave, not like a gun.
## Every bow model (ToolModels, Firearms, the forged longbow) runs its stave along +Y with
## the riser at its "grip" and the string on the +Z side.
const BOWS := ["shortbow", "longbow", "composite_bow", "royal_bow", "crystal_bow", "eclipse_bow"]

## A long gun whose model marks where a second hand holds it (mesh meta "fore").
static func two_handed(t: String) -> bool:
	var m := model(t) if t != "" else null
	return m != null and m.has_meta("fore")

## Held to be looked at rather than used: not a tool, weapon or light.
static func carried(t: String) -> bool:
	var d := ItemDB.def(t)
	return not d.is_empty() and not d.get("kind", "") in ["tool", "weapon", "light"]

static func is_bow(t: String) -> bool:
	return t in BOWS

static func pointed(t: String) -> bool:
	return t in POINTED or ItemDB.def(t).get("ranged", false)

## Kit model, scale, and the colour the bronze metal is re-tinted to (the kit's wood,
## leather and paint stay as they are). Handles run along +Y; guns point along -Z.
## Ranged weapons are built by GunLook.
const KIT := {
	"pickaxe_plasma": ["scifi/Pistol_2", 0.34, null],
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
		"binoculars":
			# Porro-prism field glasses pointing ahead: wide objective barrels in front,
			# boxy prism housings, narrower eyepieces with rubber cups at the back, a
			# centre hinge and focus wheel. The right barrel sits on the origin, so the
			# hand wraps it.
			var ahead := Basis(Vector3(1, 0, 0), -PI * 0.5)
			var o := Vector3(-0.043, 0, 0)
			for sx in [-1.0, 1.0]:
				k.cylinder("rubber", Transform3D(ahead, o + Vector3(sx * 0.043, 0, 0.0)), 0.027, 0.029, 0.075, 14)
				k.cylinder("metal_dark", Transform3D(ahead, o + Vector3(sx * 0.043, 0, -0.075)), 0.03, 0.03, 0.008, 14)
				k.cylinder("glass", Transform3D(ahead, o + Vector3(sx * 0.043, 0, -0.0835)), 0.025, 0.025, 0.002, 14, true)
				k.box("rubber", I.translated(o + Vector3(sx * 0.037, 0.012, 0.025)), Vector3(0.05, 0.05, 0.052))
				k.cylinder("metal_dark", Transform3D(ahead, o + Vector3(sx * 0.031, 0.018, 0.075)), 0.016, 0.016, 0.026, 12)
				k.cylinder("rubber", Transform3D(ahead, o + Vector3(sx * 0.031, 0.018, 0.09)), 0.02, 0.019, 0.015, 12)
				k.cylinder("glass", Transform3D(ahead, o + Vector3(sx * 0.031, 0.018, 0.092)), 0.012, 0.012, 0.002, 10, true)
			k.cylinder("metal_dark", Transform3D(ahead, o + Vector3(0, 0.026, 0.06)), 0.009, 0.009, 0.13, 10)
			k.box("metal_dark", I.translated(o + Vector3(0, 0.024, -0.035)), Vector3(0.05, 0.01, 0.022))
			k.box("metal_dark", I.translated(o + Vector3(0, 0.026, 0.035)), Vector3(0.045, 0.01, 0.02))
			k.cylinder("rubber", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), o + Vector3(0.011, 0.038, 0.012)), 0.011, 0.011, 0.022, 14)
		_:
			return null
	return k.commit(Materials.get_mat)

static func model(t: String) -> ArrayMesh:
	if _models.has(t):
		return _models[t]
	var out: ArrayMesh = GunLook.model(t) if GunLook.has(t) else null
	if out != null:
		if is_bow(t) and not out.has_meta("grip_r"):
			out.set_meta("grip_r", BOW_GRIP_R)
		_models[t] = out
		return out
	if KIT.has(t) and ResourceLoader.exists("res://assets/models/%s.gltf" % KIT[t][0]):
		var e: Array = KIT[t]
		var xf := Transform3D.IDENTITY.scaled(Vector3.ONE * e[1])
		if pointed(t):
			# The kit's guns point along +X with the grip at the origin.
			xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) * xf
		out = kit_mesh(e[0], xf, e[2])
		if t == "pickaxe_plasma":
			# A hardened drill bit where the muzzle was (human tech: nothing glows).
			var k := MeshKit.new(3)
			k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0.035, -0.29)), 0.028, 0.002, 0.14, 8)
			k.cylinder("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0.035, -0.215)), 0.04, 0.034, 0.03, 10)
			_append(out, k.commit(Materials.get_mat))
	elif t == "torch":
		out = HandLight.torch_model()
	elif _forged(t) != null:
		out = _forged(t)
		if t == "longbow":
			out.set_meta("grip", Vector3.ZERO) # held at the middle
	elif ToolModels.has(t):
		out = ToolModels.build(t)
		if is_bow(t):
			out.set_meta("grip_r", BOW_GRIP_R)
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
	if t != "" and ItemDB.def(t).is_empty():
		t = "" # nothing the game knows: empty hands, not a blank card
	if t == _type and is_same(it, _item) and t != "":
		return # same thing still in hand (an inventory change elsewhere)
	_type = t
	_item = it
	if arms:
		_mesh.mesh = null
		arms.aim_hand(Vector3.ZERO, Vector3.ZERO)
		arms.set_arms_only(t != "" and not two_handed(t))
		arms.gestures.relaxed = t == ""
		arms.support(Vector3.ZERO)
		arms.pull_in(Vector3.ZERO)
		# A long gun is held with the body turned a little to the right, the left shoulder
		# forward so the support hand reaches the fore-end.
		arms.rotation.y = PI + (LONG_YAW if two_handed(t) else 0.0)
		arms.position = ARMS_AT
		_rest = ARMS_REST if t == "" else (BINO_REST if ItemDB.def(t).get("zoom", false) else \
			(LONG_REST if two_handed(t) else CARRY_REST if carried(t) else HANG_REST if t in HANGING else SPEAR_REST if t in SPEARS else PICK_REST if _strike_axis(t) == Vector3.RIGHT else BOW_REST if is_bow(t) else ((CROSSBOW_REST if t.begins_with("crossbow") else GUN_REST) if pointed(t) else ARM_REST)))
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
	if carried(_type):
		arms.aim_grip(b * CARRY_AIM, b * CARRY_PALM)
		arms.reaim(Vector3.ZERO)
		_face_eye()
	elif pointed(_type):
		_hold_gun()
		if two_handed(_type):
			_support(b)
	else:
		# The wrist holds the tool up and away with the back of the hand toward you; the
		# fingers stay closed round the handle.
		arms.aim_grip(b * _tool_aim(_type), b * TOOL_PALM)
		if _type in HANGING:
			# Elbow bent and out to the side, the fist in front of the chest, so the
			# lamp hangs clear of the forearm instead of behind it.
			arms.pull_in((get_parent() as Node3D).global_transform * HANG_HAND)
		arms.reaim(Vector3.ZERO)
		# The grip only fixes the handle: turn the head about it so what strikes faces
		# ahead: an axe's edge (local -Z), a pick's point or a hammer's face (local +X).
		var strike := _strike_axis(_type)
		if strike != Vector3.ZERO and arms._held != null and arms._held.get_child_count() > 0:
			var prop := arms._held.get_child(0) as Node3D
			var want := prop.global_basis.orthonormalized().inverse() * (b * (Basis(Vector3.UP, AXE_YAW if strike == Vector3.FORWARD else STRIKE_YAW) * Vector3.FORWARD))
			want.y = 0.0
			if want.length() > 0.01:
				# About +Y, from the striking axis towards `want`.
				var turn := Vector2(strike.x, -strike.z).angle_to(Vector2(want.x, -want.z))
				prop.basis = prop.basis * Basis(Vector3.UP, turn)

## What you hold is drawn as if through its own lens of this vertical field of view, not
## the world camera's: at a wide world view a held tool would shrink and slide off to the
## edge. The rig is scaled across the view (not along it) by the ratio of the two lenses'
## spreads, which is exactly what drawing it at VIEW_FOV would do; depth is untouched.
const VIEW_FOV := 70.0

func _lens() -> void:
	var cam := get_parent() as Camera3D
	if cam == null:
		return
	var fov := deg_to_rad(cam.fov)
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		var vp := get_viewport().get_visible_rect().size
		fov = 2.0 * atan(tan(fov * 0.5) * vp.y / maxf(vp.x, 1.0))
	var k := tan(fov * 0.5) / tan(deg_to_rad(VIEW_FOV) * 0.5)
	scale = Vector3(k, k, 1.0)

## Which way a tool's handle points (the rig's frame) in its hold.
static func _tool_aim(t: String) -> Vector3:
	if t in HANGING:
		return HANG_AIM
	if t in BLADE_UP:
		return -TOOL_AIM
	if t in SPEARS:
		return SPEAR_AIM
	if _strike_axis(t) == Vector3.RIGHT:
		return PICK_AIM
	return TOOL_AIM

## Where _hold_gun put the gun's model this frame (world).
var _gun_xf := Transform3D.IDENTITY

## A gun or bow is placed where it belongs in the view and the hand is put round it, not
## the other way round: a long gun's stock sits in the shoulder with the barrel straight
## down the view, a heavy gun is held low at the hip, a pistol out ahead, a bow ahead and
## canted with its arrow line straight.
func _hold_gun() -> void:
	if arms._held == null or arms._held.get_child_count() == 0:
		return
	var prop := arms._held.get_child(0) as Node3D
	var mi := prop.get_child(0) as MeshInstance3D if prop.get_child_count() > 0 else null
	if mi == null or mi.mesh == null:
		return
	var m := mi.mesh
	# Worked out in the rig's own space (pointing down -Z), so the lens scale (_lens)
	# applies to the gun and the arms alike.
	var gb := Basis.IDENTITY
	var pin: Vector3 = m.get_meta("grip", Vector3.ZERO)
	var at := BOW_GRIP if is_bow(_type) else PISTOL_GRIP
	# Two hands on a gun: the body is turned and the right shoulder back where a stock
	# would sit, so the left shoulder stays out of view.
	var shoulder := LONG_BUTT - BUTT_POCKET if m.has_meta("fore") else SHOULDER_AT
	if is_bow(_type):
		gb = Basis(Vector3.BACK, BOW_CANT)
	elif m.has_meta("butt") and not _type in HIP:
		pin = m.get_meta("butt")
		at = LONG_BUTT
		gb = Basis(Vector3.UP, LONG_TOE)
	elif m.has_meta("fore"):
		at = HEAVY_GRIP
	# The arms come along with the gun: the right shoulder set where this hold puts it, so
	# the hand always reaches.
	arms.global_position += global_transform * shoulder - arms.shoulder_r()
	var xf := global_transform * Transform3D(gb, at - gb * pin)
	_gun_xf = xf
	arms.reaim(Vector3.ZERO)
	arms.set_hand(xf * mi.transform.affine_inverse() * prop.transform.affine_inverse())

## The left hand under a long gun's fore-end: palm up against it, fingers across it to
## the right and curled up its far side, the wrist a hand's length short of the point.
func _support(b: Basis) -> void:
	if arms._held == null or arms._held.get_child_count() == 0:
		return
	var prop := arms._held.get_child(0) as Node3D
	var mi := prop.get_child(0) as MeshInstance3D if prop.get_child_count() > 0 else null
	if mi == null or mi.mesh == null or not mi.mesh.has_meta("fore"):
		return
	var fore: Vector3 = _gun_xf * Vector3(mi.mesh.get_meta("fore"))
	var palm := (b * SUPPORT_PALM).normalized()
	var fingers := (b * SUPPORT_FINGERS).normalized()
	arms.support(fore - fingers * 0.045 - palm * 0.035, fingers, palm)

## Turns a carried item's model about its upright axis so its face (+Z) looks at the eye:
## a jar's label, a gauge's dial, an ingot's stamp, a card's icon.
func _face_eye() -> void:
	if arms._held == null or arms._held.get_child_count() == 0:
		return
	var prop := arms._held.get_child(0) as Node3D
	if prop.get_child_count() == 0:
		return
	var mi := prop.get_child(0) as Node3D
	var eye := (get_parent() as Node3D).global_position if get_parent() is Node3D else global_position
	var to := prop.global_basis.inverse() * (eye - mi.global_position)
	to.y = 0.0
	if to.length() > 0.001:
		mi.rotation.y = atan2(to.x, to.z)

## Which way the business end of a held tool faces in its model (Vector3.ZERO: no turn).
static func _strike_axis(t: String) -> Vector3:
	if is_bow(t):
		return Vector3.FORWARD # the belly ahead, the string toward you
	if t.begins_with("axe_") or t in ["battle_axe", "hand_axe", "bronze_axe", "executioner_axe", "tomahawk", "chain_axe"]:
		return Vector3.FORWARD
	if t.begins_with("pickaxe_") and t != "pickaxe_plasma" or t in ["hammer", "warpick", "sledgehammer", "power_hammer"]:
		return Vector3.RIGHT
	return Vector3.ZERO

## A swing winds back, strikes and recovers. When it is aimed at something (`hit`: the
## world "point" and "normal" the blow lands on) the rig drifts during the wind-up so the
## striking edge comes down on that point, stops on the surface instead of passing
## through, rests there a moment and comes back. Returns the seconds until the blow
## lands, for the impact to show then. `duration` is how long the whole swing takes.
func swing(duration := 0.42, hit := {}) -> float:
	_swing_t = 0.0
	_swing_len = maxf(0.25, duration * 0.92)
	_peak = 1.0
	_hold = 0.0
	_landed = false
	_hit = hit if hit.has("point") and hit.has("normal") else {}
	_off_full = Vector3.ZERO
	_tip_pts = PackedVector3Array()
	_refresh_points()
	var u := sqrt((CONTACT - BACK) / (1.0 - BACK))
	return (WIND + (STRIKE - WIND) * u) * _swing_len

## How far through its arc the swing is at time t (0..1): 0 at rest, BACK at the top of
## the wind-up, 1 at full reach. The strike accelerates into the blow.
func _swing_amount(t: float) -> float:
	if t < WIND:
		var u := t / WIND
		return BACK * (1.0 - (1.0 - u) * (1.0 - u))
	if t < STRIKE:
		var u := (t - WIND) / (STRIKE - WIND)
		return BACK + (1.0 - BACK) * u * u
	return _peak * (1.0 - smoothstep(STRIKE, 1.0, t))

## The rig's swing pose at swing amount s, in the camera's frame (before sway, aiming
## and the drift towards a target).
func _swing_pose(s: float) -> Array:
	if arms:
		# The whole rig swings down and across from just in front of the eyes.
		return [Vector3(-0.05 * s, -0.06 * s, -0.12 * s), Vector3(-0.9 * s, 0.25 * s, 0.35 * s)]
	return [Vector3(-0.12 * s, 0.05 * s, -0.1 * s), Vector3(-1.1 * s, 0.3 * s, 0.3 * s)]

## The held item's vertices (a sample of them) in the rig's own frame. The grip holds
## the item fixed to the rig through a swing, so these stay put while the rig moves.
## Taken again only when the item changes.
func _refresh_points() -> void:
	var mi := _held_mesh()
	var m: Mesh = mi.mesh if mi != null else null
	if m == _tip_of and (m == null or not _tip_pts.is_empty()):
		return
	_tip_of = m
	_tip_pts = PackedVector3Array()
	if m == null:
		return
	var out := _tip_pts
	var rel := global_transform.affine_inverse() * mi.global_transform
	var all := PackedVector3Array()
	for si in mi.mesh.get_surface_count():
		all.append_array(mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
	var step := maxi(1, all.size() / TIP_POINTS)
	for k in range(0, all.size(), step):
		out.append(rel * all[k])
	_tip_pts = out

## The rig's offset that brings the item's leading point onto the target at the moment
## of contact, as far as arms can reach.
func _reach_offset(cam_from_world: Transform3D) -> Vector3:
	var p: Vector3 = cam_from_world * Vector3(_hit["point"])
	var n: Vector3 = (cam_from_world.basis * Vector3(_hit["normal"])).normalized()
	var pose := _swing_pose(CONTACT)
	var rig := Transform3D(Basis.from_euler(pose[1]), _rest + pose[0])
	var best := -INF
	var lead := Vector3.ZERO
	for q in _tip_pts:
		var v := rig * q
		var into := -v.dot(n)
		if into > best:
			best = into
			lead = v
	var off := p - lead
	return Vector3(clampf(off.x, -REACH_SIDE, REACH_SIDE), clampf(off.y, -REACH_DOWN, REACH_UP), clampf(off.z, -REACH_OUT, REACH_IN))

## Keeps the held item out of a surface: pushes the rig back off it, and when the
## strike meets the one it was aimed at, stops the swing there.
func _meet_surface(s: float, surf: Dictionary) -> void:
	var parent := get_parent() as Node3D
	_refresh_points()
	if parent == null or _tip_pts.is_empty():
		return
	var to_world := parent.global_transform * transform
	var p: Vector3 = surf["point"]
	var n: Vector3 = Vector3(surf["normal"]).normalized()
	var least := INF
	for q in _tip_pts:
		least = minf(least, (to_world * q - p).dot(n))
	if least < 0.0:
		position += (parent.global_basis.inverse() * n).normalized() * minf(-least, 0.6)
	# Touching, or as good as (the strike moves several centimetres a frame).
	if surf == _hit and not _landed and _swing_t >= WIND and _swing_t < STRIKE and (least <= 0.01 or s >= CONTACT and least < 0.05):
		_landed = true
		_peak = s
		_swing_t = STRIKE
		_hold = HOLD

## A shot's kick: the gun jumps back and its muzzle climbs, more for heavy weapons.
func recoil(strength := 1.0) -> void:
	_recoil = clampf(strength, 0.3, 2.0)

## Lowers the gun out of view and brings it back up, for a reload.
func reload_dip() -> void:
	_dip_t = 0.0

var ads := 0.0 ## set by Gunplay: 0 hip, 1 looking down the sights
var raise := 0.0 ## set by Player: 0 binoculars lowered, 1 at the eyes
var _raise_off := Vector3.ZERO
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

## Between the binoculars' eyepieces (the back of the model, eyepieces along +Z), in the
## rig's own space.
func _eyepiece_local() -> Vector3:
	var mi := _held_mesh()
	if mi == null or mi.mesh == null:
		return Vector3.ZERO
	var b := mi.mesh.get_aabb()
	var back := mi.global_transform * Vector3(b.get_center().x, b.get_center().y + b.size.y * 0.2, b.end.z)
	return global_transform.affine_inverse() * back

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
	_lens()
	var steady := (1.0 - 0.85 * ads) * (1.0 - raise)
	_sway_t += delta * (1.0 + speed * 6.0)
	if _hold > 0.0:
		_hold -= delta
	else:
		_swing_t = minf(1.0, _swing_t + delta / _swing_len)
	_recoil = maxf(0.0, _recoil - delta * 8.0)
	_dip_t = minf(1.0, _dip_t + delta * 1.4)
	var s := _swing_amount(_swing_t)
	var drift := Vector3.ZERO
	if not _hit.is_empty() and _swing_t < 1.0:
		var parent := get_parent() as Node3D
		if parent != null and not _landed and _swing_t < STRIKE:
			_off_full = _reach_offset(parent.global_transform.affine_inverse())
		drift = _off_full * smoothstep(0.0, WIND, _swing_t) * (1.0 - smoothstep(STRIKE, 1.0, _swing_t))
	var pose := _swing_pose(s)
	var dip := sin(_dip_t * PI) # down and back up over a reload
	var off := Vector3(sin(_sway_t) * 0.006 * (1.0 + speed * 3.0), absf(cos(_sway_t)) * 0.006 * (1.0 + speed * 3.0), _recoil * 0.06) * Vector3(steady, steady, 1.0)
	# Aiming: slide the rig so the gun's top sits on the line of sight.
	if ads > 0.001 and pointed(_type):
		var sl := _sight_local()
		var want := Vector3(-sl.x - _rest.x, -sl.y - _rest.y - 0.012, 0.06)
		_ads_off = _ads_off.lerp(want, clampf(delta * 20.0, 0.0, 1.0))
	var aim_off := _ads_off * smoothstep(0.0, 1.0, ads)
	# Binoculars: lift them until the eyepieces sit just in front of the eyes, then
	# stop drawing them (the HUD shows the twin-circle view instead).
	if raise > 0.001:
		var el := _eyepiece_local()
		var want := Vector3(-el.x - _rest.x, -el.y - _rest.y, -el.z - _rest.z - 0.1)
		_raise_off = _raise_off.lerp(want, clampf(delta * 20.0, 0.0, 1.0))
		aim_off += _raise_off * smoothstep(0.0, 1.0, raise)
	var hide := raise > 0.8
	if arms:
		arms.visible = not hide
	_mesh.visible = not hide
	if arms:
		position = _rest + aim_off + off + pose[0] + drift + Vector3(0, -0.18 * dip, _recoil * 0.04 + 0.05 * dip)
		rotation = pose[1] + Vector3(_recoil * (0.12 * steady + 0.03) - 0.5 * dip, 0.0, 0.4 * dip)
		_aim()
	else:
		position = _rest + aim_off + off + pose[0] + drift + Vector3(0, -0.18 * dip, 0.05 * dip)
		rotation = pose[1] + Vector3(_recoil * 0.25 * steady - 0.5 * dip, 0.0, 0.4 * dip)
	# Guns keep their aim; tools and blades rest against what is in front of them.
	var surf := _hit if not _hit.is_empty() and _swing_t < 1.0 else ({} if pointed(_type) else near)
	if not surf.is_empty() and not hide:
		_meet_surface(s, surf)

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
