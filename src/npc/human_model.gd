class_name HumanModel
extends Node3D
## A person built from the CC0 Universal Base Characters (Quaternius): a skinned base body
## dressed by human.gdshader (shirt, trousers, boots, robe, era trims, all per person
## through instance uniforms), a hairstyle bound to the same skeleton, era headgear and a
## work tool in hand, animated with the Universal Animation Library (baked into
## assets/models/anim/humans.res by tools/bake_anims.gd) through HumanAnimator (gaits
## matched to the ground speed, layers) and HumanIK (feet on the ground, looking, leaning).

const DIR := "res://assets/models/people/"
const ANIMS := "res://assets/models/anim/humans.res"
const BODY := {false: "Superhero_Male_FullBody", true: "Superhero_Female_FullBody"}
const HAIR_MALE := ["Hair_SimpleParted", "Hair_Buzzed", "Hair_Long", ""]
const HAIR_FEMALE := ["Hair_Long", "Hair_Buns", "Hair_SimpleParted", "Hair_BuzzedFemale"]
## Dominant skin bone -> body region used by the clothing shader.
const REGION_OF := {"Head": 0, "neck_01": 0, "spine_01": 1, "spine_02": 1, "spine_03": 1, "clavicle": 1,
	"upperarm": 2, "lowerarm": 3, "hand": 4, "pelvis": 5, "root": 5, "thigh": 5, "calf": 6, "foot": 7, "ball": 7}

static var _cache := {}
static var _lib: AnimationLibrary
static var _mats := {}

var skeleton: Skeleton3D
var anim: AnimationTree
var animator: HumanAnimator
var ik: HumanIK
var gestures: BodyLanguage
var _body: MeshInstance3D
var _clothes: MeshInstance3D
var _armour: MeshInstance3D
var _shield: Node3D
var _hair: Array = [] ## hair meshes, hidden under a helmet (beards stay)
var _headgear_node: Node3D
var _fem := false
var _wardrobe: Dictionary ## Outfit.wardrobe(): the cut and colours of this person's clothes
var _current := ""
var _oneshot := false

static func available() -> bool:
	return ResourceLoader.exists(ANIMS) and ResourceLoader.exists(DIR + BODY[false] + ".gltf")

## The body mesh with per-vertex region / rest height / |x| in CUSTOM0, built once per sex.
static func _body_mesh(fem: bool, src: MeshInstance3D) -> ArrayMesh:
	var key := "body_%s" % fem
	if _cache.has(key):
		return _cache[key]
	var a := src.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var sk := src.get_node(src.skeleton) as Skeleton3D
	var region_of_bind: Array = []
	for i in src.skin.get_bind_count():
		var bn := String(src.skin.get_bind_name(i))
		if bn == "" and sk:
			bn = sk.get_bone_name(src.skin.get_bind_bone(i))
		var r := 1
		for k in REGION_OF:
			if bn == k or bn.begins_with(k + "_") or (k == "hand" and (bn.begins_with("index") or bn.begins_with("middle") or bn.begins_with("ring") or bn.begins_with("pinky") or bn.begins_with("thumb"))):
				r = REGION_OF[k]
				break
		region_of_bind.append(r)
	var custom := PackedFloat32Array()
	custom.resize(verts.size() * 3)
	for v in verts.size():
		var best := 0
		var bw := -1.0
		for j in per:
			if weights[v * per + j] > bw:
				bw = weights[v * per + j]
				best = bones[v * per + j]
		custom[v * 3] = float(region_of_bind[best]) if best < region_of_bind.size() else 1.0
		custom[v * 3 + 1] = verts[v].y
		custom[v * 3 + 2] = verts[v].x
	a[Mesh.ARRAY_CUSTOM0] = custom
	# The importer packs extra UV and colour sets into the other custom channels (the
	# female body has more than the male); drop them, the shader doesn't use them and
	# their formats would no longer match.
	for ch in [Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		a[ch] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	_cache[key] = m
	return m

static func _body_mat(fem: bool) -> ShaderMaterial:
	var key := "body_%s" % fem
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://src/npc/human.gdshader")
		var g := "female" if fem else "male"
		m.set_shader_parameter("skin_tex", load(DIR + "body_%s_albedo.png" % g))
		m.set_shader_parameter("normal_tex", load(DIR + "body_%s_normal.png" % g))
		m.set_shader_parameter("skin_mean", 0.49 if fem else 0.47)
		m.set_shader_parameter("rough_tex", load(DIR + "body_%s_rough.png" % g))
		m.set_shader_parameter("skin_avg", Vector3(0.667, 0.466, 0.322) if fem else Vector3(0.655, 0.454, 0.316))
		_mats[key] = m
	return _mats[key]

static func _hair_mat(which: int) -> ShaderMaterial:
	var key := "hair_%d" % which
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://src/npc/hair.gdshader")
		m.set_shader_parameter("tex", load(DIR + "hair_%d_albedo.png" % which))
		m.set_shader_parameter("nrm", load(DIR + "hair_%d_normal.png" % which))
		_mats[key] = m
	return _mats[key]

static func _eye_mat() -> StandardMaterial3D:
	if not _mats.has("eye"):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(DIR + "eye_albedo.png")
		m.roughness = 0.2
		_mats["eye"] = m
	return _mats["eye"]

static func library() -> AnimationLibrary:
	if _lib == null:
		_lib = load(ANIMS)
	return _lib

## b: the persisted body record (NPCGen). Returns self for chaining.
func build(b: Dictionary, era: int, job: String) -> HumanModel:
	var fem: bool = b["female"]
	_fem = fem
	var scene: Node3D = (load(DIR + BODY[fem] + ".gltf") as PackedScene).instantiate()
	add_child(scene)
	skeleton = scene.find_children("*", "Skeleton3D", true, false)[0]
	var hair_col: Color = b["hair"]
	for c in skeleton.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		if String(mi.name).to_lower().begins_with("superhero"):
			mi.mesh = _body_mesh(fem, mi)
			mi.material_override = _body_mat(fem)
			_body = mi
		elif mi.name == "Eyes":
			mi.material_override = _eye_mat()
		else:
			mi.material_override = _hair_mat(1)
			mi.set_instance_shader_parameter("hair_col", hair_col)
			_hair.append(mi)
	_dress(b, era, job)
	# Hair, unless a helmet or hood covers it.
	var styles: Array = HAIR_FEMALE if fem else HAIR_MALE
	var style: String = styles[int(b["hair_style"]) % styles.size()]
	if NPCGen.GUARD_JOBS.has(job):
		style = "Hair_Buzzed" if not fem else "Hair_BuzzedFemale"
	_dress_up(era)
	if style != "":
		_add_hair(style, hair_col)
	if not fem and int(b["hair_style"]) % 2 == 1 and era != Eras.SCIFI:
		_add_hair("Hair_Beard", hair_col)
	_headgear(era, job, b)
	_tool(era, job)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	animator = HumanAnimator.new()
	add_child(animator)
	animator.setup(library(), scene, skeleton, self)
	anim = animator.tree
	ik = HumanIK.new()
	skeleton.add_child(ik)
	animator.ik = ik
	gestures = BodyLanguage.new()
	skeleton.add_child(gestures)
	if _gripping:
		gestures.grip_r = GRIP
	_eyelids(b)
	play("idle")
	return self

## Real garments over the painted body (Outfit), in this person's colours.
func _dress_up(era: int) -> void:
	if _body == null or _body.skin == null:
		return
	_clothes = MeshInstance3D.new()
	_clothes.name = "Clothes"
	_clothes.mesh = Outfit.clothes(_fem, _body.mesh, _body.skin, skeleton, _wardrobe["spec"])
	_clothes.skin = _body.skin
	skeleton.add_child(_clothes)
	_clothes.skeleton = NodePath("..")
	_clothes.material_override = Outfit.cloth_material()
	var cols: Dictionary = _wardrobe["cols"]
	var slots := {"shirt_col": Outfit.PART_SHIRT, "pants_col": Outfit.PART_PANTS, "boot_col": Outfit.PART_BOOTS, "skirt_col": Outfit.PART_SKIRT,
		"cape_col": Outfit.PART_CAPE, "vest_col": Outfit.PART_TRIM, "apron_col": Outfit.PART_APRON}
	for k in slots:
		_clothes.set_instance_shader_parameter(k, cols[slots[k]])
	_clothes.set_instance_shader_parameter("accent_col", _body.get_instance_shader_parameter("accent_col"))
	_clothes.set_instance_shader_parameter("era", float(era))
	_clothes.set_instance_shader_parameter("trim", 1.0 if _wardrobe["trim"] else 0.0)

## Shows what this body wears: {slot: item} for any of Game.ARMOR_SLOTS. Armour is
## drawn on the body (Outfit), a shield on the left forearm, and a helmet hides the hair.
func wear(worn: Dictionary) -> void:
	if _body == null or skeleton == null:
		return
	if _armour:
		_armour.queue_free()
		_armour = null
	if _shield:
		_shield.queue_free()
		_shield = null
	var m := Outfit.armour(_fem, _body.mesh, _body.skin, skeleton, worn)
	if m.get_surface_count() > 0:
		_armour = MeshInstance3D.new()
		_armour.name = "Armour"
		_armour.mesh = m
		_armour.skin = _body.skin
		skeleton.add_child(_armour)
		_armour.skeleton = NodePath("..")
		_armour.material_override = Outfit.armor_material()
		var hb := skeleton.find_bone("Head")
		if hb >= 0:
			_armour.set_instance_shader_parameter("visor_y", skeleton.get_bone_global_rest(hb).origin.y + 0.085)
		_armour.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _shadow_only else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if _arms:
			_arms_cut(_armour)
	var helmet: bool = worn.get("head") is Dictionary
	for h in _hair:
		(h as Node3D).visible = not helmet and not _arms
	if _headgear_node:
		_headgear_node.visible = not helmet and not _arms
	if worn.get("shield") is Dictionary:
		_shield = _shield_mesh(worn["shield"])
		for mi in _shield.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _shadow_only else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.visible = not _arms

func _shield_mesh(item: Dictionary) -> Node3D:
	var lk := Outfit.look_of(item)
	var k := MeshKit.new(3)
	var I := Transform3D.IDENTITY
	var col: Color = lk["color"]
	match int(lk["style"]):
		Outfit.STYLE_EXO:
			k.cylinder("panel", I, 0.3, 0.3, 0.02, 6, true, 0.0, 1, col)
			k.cylinder("glow_cyan", I.translated(Vector3(0, 0.012, 0)), 0.22, 0.22, 0.01, 6, true, 0.0, 1, col)
		Outfit.STYLE_CRYSTAL:
			k.cylinder("crystal@2", I, 0.28, 0.28, 0.025, 14, true, 0.0, 1, col)
		Outfit.STYLE_PLATE:
			# Bronze and steel: a beaten metal disc with a raised boss.
			k.cylinder("iron", I, 0.31, 0.31, 0.022, 20, true, 0.0, 1, col)
			k.cylinder("iron", I.translated(Vector3(0, 0.016, 0)), 0.08, 0.06, 0.035, 12, true, 0.0, 1, col.lightened(0.15))
		_:
			k.cylinder("planks", I, 0.3, 0.3, 0.03, 16, true, 0.0, 1, col)
			k.cylinder("iron", I.translated(Vector3(0, 0.018, 0)), 0.07, 0.07, 0.03, 10)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(Materials.get_mat)
	var ba := _bone_attach("lowerarm_l")
	ba.add_child(mi)
	# Strapped to the back of the forearm (up in the rest pose, palms down), face out.
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone("lowerarm_l")).basis.orthonormalized()
	var outward := (rest.inverse() * Vector3.UP).normalized()
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, outward)), outward * 0.07 + Vector3(0, 0.13, 0))
	return ba

## Two lids that close for blinks and winks (BodyLanguage drives them).
func _eyelids(b: Dictionary) -> void:
	var eyes: MeshInstance3D = null
	for c in skeleton.get_children():
		if c is MeshInstance3D and c.name == "Eyes":
			eyes = c
	var hb := skeleton.find_bone("Head")
	if eyes == null or hb < 0:
		return
	var box := eyes.mesh.get_aabb()
	var r := box.size.y * 0.5
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = (b["skin"] as Color).darkened(0.12)
	lid_mat.roughness = 0.6
	var sph := SphereMesh.new()
	sph.radius = r * 1.12
	sph.height = r * 2.24
	sph.radial_segments = 10
	sph.rings = 6
	var inv := skeleton.get_bone_global_rest(hb).affine_inverse()
	var ba := _bone_attach("Head")
	for i in 2:
		var x := box.position.x + r if i == 1 else box.end.x - r
		var mi := MeshInstance3D.new()
		mi.mesh = sph
		mi.material_override = lid_mat
		mi.position = inv * Vector3(x, box.get_center().y, box.get_center().z + r * 0.1)
		mi.visible = false
		ba.add_child(mi)
		gestures.eyelids[i] = mi

## Plays a hand or face gesture (BodyLanguage.names()) over the current animation.
func gesture(name: String) -> bool:
	return gestures != null and gestures.play(name)

func _dress(b: Dictionary, era: int, job: String) -> void:
	_wardrobe = Outfit.wardrobe(b, era, job)
	var sp: Dictionary = _wardrobe["spec"]
	var cols: Dictionary = _wardrobe["cols"]
	var accent := Color(0, 0, 0, 0)
	if era == Eras.SCIFI:
		# Glowing seams are alien fashion; human outposts wear plain work clothes.
		accent = Color(0.3, 0.9, 1.0, 0.0 if Eras.theme == "human" else 1.0)
	# The body under the garments is painted in the same colours, and drawn a little
	# inside them (human.gdshader), so nothing shows through where they bend.
	var shirt: Color = cols[Outfit.PART_SHIRT]
	var pants: Color = cols[Outfit.PART_PANTS]
	var boots: Color = cols[Outfit.PART_BOOTS]
	_body.set_instance_shader_parameter("skin_col", b["skin"])
	_body.set_instance_shader_parameter("shirt_col", Color(shirt.r, shirt.g, shirt.b))
	_body.set_instance_shader_parameter("pants_col", Color(pants.r, pants.g, pants.b))
	_body.set_instance_shader_parameter("boot_col", Color(boots.r, boots.g, boots.b))
	_body.set_instance_shader_parameter("accent_col", accent)
	_body.set_instance_shader_parameter("cut", Vector4(sp["sleeves"], sp["boot_h"], 0.0, 0.0))

func _add_hair(style: String, col: Color) -> void:
	var path := DIR + style + ".gltf"
	if not ResourceLoader.exists(path):
		return
	var src: Node = (load(path) as PackedScene).instantiate()
	for c in src.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var skin := mi.skin
		mi.get_parent().remove_child(mi)
		mi.owner = null
		skeleton.add_child(mi)
		mi.skin = skin
		mi.skeleton = NodePath("..")
		var mat_name := mi.mesh.surface_get_material(0).resource_name if mi.mesh.surface_get_material(0) else ""
		mi.material_override = _hair_mat(2 if mat_name.ends_with("2") else 1)
		mi.set_instance_shader_parameter("hair_col", col)
		if style != "Hair_Beard":
			_hair.append(mi)
	src.free()

func _bone_attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba

func _headgear(era: int, job: String, b: Dictionary) -> void:
	var k := MeshKit.new(7)
	var I := Transform3D.IDENTITY
	# Guards wear real armour instead (NPC.default_gear).
	if era == Eras.MEDIEVAL and job in ["farmer", "hunter", "miller"]:
		k.cylinder("thatch", I.translated(Vector3(0, 0.17, 0)), 0.095, 0.07, 0.09, 10)
		k.cylinder("thatch", I.translated(Vector3(0, 0.15, 0)), 0.22, 0.22, 0.015, 14)
	elif era == Eras.FANTASY and job in ["mystic", "warden", "herbalist"]:
		# A soft felt hat whose point flops over, on a narrow brim.
		var felt: Color = (b["cloth2"] as Color).darkened(0.25)
		k.cylinder("cloth_w", I.translated(Vector3(0, 0.1, -0.02)), 0.17, 0.17, 0.012, 16, true, 0.0, 1, felt)
		k.cylinder("cloth_w", I.translated(Vector3(0, 0.1, -0.02)), 0.115, 0.06, 0.16, 12, true, 0.0, 1, felt)
		k.cylinder("cloth_w", Transform3D(Basis(Vector3.RIGHT, -0.7), Vector3(0, 0.25, -0.02)), 0.06, 0.0, 0.13, 10, true, 0.0, 1, felt)
	else:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(Materials.get_mat)
	_headgear_node = _bone_attach("Head")
	_headgear_node.add_child(mi)

## Tools in hand for jobs that work with one.
func _tool(era: int, job: String) -> void:
	var model := ""
	match job:
		"smith": model = "Sword_Bronze"
		"farmer", "beekeeper", "hydroponics tech": model = "Pickaxe_Bronze"
		"hunter", "warden": model = "Axe_Bronze"
		"guard": model = "Sword_Bronze"
	var path := "res://assets/models/props/%s.gltf" % model
	if model == "" or not ResourceLoader.exists(path):
		return
	var t: Node3D = (load(path) as PackedScene).instantiate()
	_bone_attach("hand_r").add_child(t)
	t.transform = grip_transform(skeleton, t)
	_gripping = true

## How far each finger of a hand holding something curls (BodyLanguage finger order).
const GRIP := [1.0, 0.95, 0.95, 0.95, 0.95]
var _gripping := false

## Where the curled fingers of a gripping right hand leave room for a handle, in the hand's
## own space: the middle of the loop the middle finger makes with the palm, worked out by
## curling it the way BodyLanguage does.
static func fist_hole(sk: Skeleton3D) -> Vector3:
	var hb := sk.find_bone("hand_r")
	var head := sk.find_bone("Head")
	var pelvis := sk.find_bone("pelvis")
	if hb < 0 or head < 0 or pelvis < 0 or sk.find_bone("middle_01_r") < 0:
		return Vector3.INF
	var toward := (sk.get_bone_global_rest(pelvis).origin - sk.get_bone_global_rest(head).origin).normalized()
	var g := sk.get_bone_global_rest(hb)
	var inv := g.affine_inverse()
	var amounts := [0.55, 0.75, 0.6]
	var cur := g
	var pts: Array[Vector3] = []
	for j in 3:
		var b := sk.find_bone("middle_%02d_r" % (j + 1))
		if b < 0:
			break
		var rest := sk.get_bone_global_rest(b)
		var axis := rest.basis.y.normalized().cross(toward)
		var local_axis := (rest.basis.orthonormalized().inverse() * axis.normalized()).normalized()
		var lr := sk.get_bone_rest(b)
		cur = cur * Transform3D(Basis(lr.basis.get_rotation_quaternion() * Quaternion(local_axis, float(GRIP[2]) * amounts[j] * 2.0)), lr.origin)
		pts.append(inv * cur.origin)
	var leaf := sk.find_bone("middle_04_leaf_r")
	if leaf >= 0:
		pts.append(inv * (cur * sk.get_bone_rest(leaf).origin))
	var c := Vector3.ZERO
	for p in pts:
		c += p
	return c / float(pts.size())

## Where a held prop goes in the right hand's space, worked out from the hand's own rest
## pose: the shaft runs along the knuckles through the fist (the fingers curl round it,
## GRIP), and the prop is held near the low end of its handle.
## `aim` (hand space, optional) points the prop that way instead, tilted `tilt` of the way
## from the knuckle line, for a first-person hold that reads well on screen.
## `point` (hand space, optional) instead aims the prop's -Z that way, keeping +Y toward
## `aim`: a pistol's barrel follows the view.
static func grip_transform(sk: Skeleton3D, prop: Node3D, scale := 0.8, aim := Vector3.ZERO, tilt := 0.0, point := Vector3.ZERO) -> Transform3D:
	var hb := sk.find_bone("hand_r")
	var bi := sk.find_bone("index_01_r")
	var bp := sk.find_bone("pinky_01_r")
	var bm := sk.find_bone("middle_01_r")
	if hb < 0 or bi < 0 or bp < 0 or bm < 0:
		return Transform3D(Basis.from_euler(Vector3(0, 0, -PI * 0.5)), Vector3(0.08, 0.03, 0.0))
	var inv := sk.get_bone_global_rest(hb).affine_inverse()
	var i := inv * sk.get_bone_global_rest(bi).origin
	var p := inv * sk.get_bone_global_rest(bp).origin
	var m := inv * sk.get_bone_global_rest(bm).origin
	var up := (i - p).normalized()
	if aim != Vector3.ZERO:
		if up.dot(aim) < 0.0:
			up = -up
		up = up.slerp(aim.normalized(), tilt).normalized()
	var fwd := (m - up * m.dot(up)).normalized()
	var side := fwd.cross(up).normalized()
	var center := (i + p) * 0.5 + fwd * 0.035 + side * 0.02
	var hole := fist_hole(sk)
	if hole != Vector3.INF:
		center = hole
	# The prop's handle: its lowest point plus a hand's width, in the prop's own space.
	var box := AABB()
	var first := true
	for mi in prop.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = _rel(prop, mi)
		var b: AABB = xf * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var grip := Vector3(0, box.position.y + minf(0.12, box.size.y * 0.25), 0)
	# A model can say where the fist closes round it (a gun's grip).
	for mi in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh and mesh.has_meta("grip"):
			grip = _rel(prop, mi) * (mesh.get_meta("grip") as Vector3)
	var basis := Basis(fwd * scale, up * scale, fwd.cross(up) * scale)
	if point != Vector3.ZERO:
		var z := -point.normalized()
		var y := (aim - z * aim.dot(z)).normalized()
		basis = Basis(y.cross(z) * scale, y * scale, z * scale)
	return Transform3D(basis, center - basis * grip)

static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf

var _held: Node3D
var _arms := false
var _shadow_only := false

## Puts a prop (any Node3D with meshes, handle along +Y) in the right hand, or empties it.
func hold(prop: Node3D, aim := Vector3.ZERO, tilt := 0.0, point := Vector3.ZERO) -> void:
	if _held:
		_held.queue_free()
		_held = null
	if gestures:
		gestures.grip_r = []
	if prop == null or skeleton == null:
		return
	var ba := _bone_attach("hand_r")
	ba.add_child(prop)
	prop.transform = grip_transform(skeleton, prop, 1.0, aim, tilt, point)
	_held = ba
	if gestures:
		gestures.grip_r = GRIP
	for mi in prop.find_children("*", "MeshInstance3D", true, false) + ([prop] if prop is MeshInstance3D else []):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _arms else (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _shadow_only else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

## Turns the right hand (over its animation) so its knuckle line, little finger to index,
## runs along `knuckles` and the back of the hand points the fingers along `fingers`
## (world directions); Vector3.ZERO for both hands it back to the animation.
func aim_hand(knuckles: Vector3, fingers: Vector3) -> void:
	if gestures == null or skeleton == null:
		return
	if knuckles == Vector3.ZERO:
		gestures.hand_r = null
		return
	var hb := skeleton.find_bone("hand_r")
	var bi := skeleton.find_bone("index_01_r")
	var bp := skeleton.find_bone("pinky_01_r")
	var bm := skeleton.find_bone("middle_01_r")
	if hb < 0 or bi < 0 or bp < 0 or bm < 0:
		return
	var g := skeleton.get_bone_global_rest(hb)
	var inv := g.affine_inverse()
	var up := (inv * skeleton.get_bone_global_rest(bi).origin - inv * skeleton.get_bone_global_rest(bp).origin).normalized()
	var m := inv * skeleton.get_bone_global_rest(bm).origin
	var fwd := (m - up * m.dot(up)).normalized()
	var to_sk := skeleton.global_basis.orthonormalized().inverse()
	var u := (to_sk * knuckles).normalized()
	var f := to_sk * fingers
	f = (f - u * f.dot(u)).normalized()
	# (fwd, up) are in the bone's own space: the bone's basis maps them onto (f, u).
	gestures.hand_r = Basis(f, u, f.cross(u)) * Basis(fwd, up, fwd.cross(up)).inverse()

## Re-aims what the hand holds (first person: called every frame so the item keeps
## facing the view whatever the arms' animation does).
func reaim(aim: Vector3, tilt := 0.0, point := Vector3.ZERO) -> void:
	if _held == null or _held.get_child_count() == 0:
		return
	var prop := _held.get_child(0) as Node3D
	prop.transform = grip_transform(skeleton, prop, 1.0, aim, tilt, point)

## A world direction expressed in the right hand's current (animated) space.
func hand_space(dir: Vector3) -> Vector3:
	var hb := skeleton.find_bone("hand_r")
	if hb < 0:
		return dir
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(hb)
	if gestures and gestures.hand_r != null:
		# Turned by aim_hand: the pose read back may predate that turn this frame.
		pose.basis = skeleton.global_basis * (gestures.hand_r as Basis)
	return (pose.basis.inverse() * dir).normalized()

## First-person arms: only the arms and hands are drawn, nothing casts shadows.
## `right_only` hides the left arm (a one-handed tool).
func set_arms_only(right_only := false) -> void:
	_arms = true
	var side := 1.0
	if right_only and skeleton and skeleton.find_bone("hand_r") >= 0:
		side = 2.0 if skeleton.get_bone_global_rest(skeleton.find_bone("hand_r")).origin.x < 0.0 else 3.0
	_side = side
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if m == _body:
			m.set_instance_shader_parameter("arms_only", side)
		elif m == _clothes or m == _armour:
			# The real sleeve and any armour on the arms and hands, cut at the shoulder.
			_arms_cut(m)
		elif not _is_held(m):
			m.visible = false

var _side := 1.0

func _arms_cut(m: MeshInstance3D) -> void:
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.set_instance_shader_parameter("arms_only", _side)
	var bu := skeleton.find_bone("upperarm_l")
	m.set_instance_shader_parameter("arms_x", (absf(skeleton.get_bone_global_rest(bu).origin.x) if bu >= 0 else 0.2) + 0.04)

func _is_held(n: Node) -> bool:
	return _held != null and _held.is_ancestor_of(n)

## Shadow-only body (first person): you see your shadow, not the inside of your head.
func set_shadow_only(on: bool) -> void:
	_shadow_only = on
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## Plays a looping state, cross-fading. Walk, jog and sprint all mean "on the move": the
## gait and its pace follow how fast the body really moves (HumanAnimator), so `speed`
## only sets the pace of other states. Ignored while posed (pose()).
func play(state: String, speed := 1.0) -> void:
	if animator == null or _holding:
		return
	if not anim.has_animation(state) and not state in HumanAnimator.GAITS:
		state = "idle"
	_current = state
	if state == "idle" and not _oneshot:
		_idle_variety()
	else:
		_idle_alt = ""
	animator.set_state(_idle_alt if state == "idle" and _idle_alt != "" else state, speed)

## Plays an action once, then returns to the looping state. `dur` (optional) fits the
## action into that many seconds, sped up at most 2.2x. Looping clips (chopping) are
## played for one cycle, so a single swing never keeps going. On the move it plays over
## the upper body and the legs keep walking.
func play_once(state: String, dur := 0.0) -> void:
	if animator == null or not anim.has_animation(state):
		return
	var a := anim.get_animation(state)
	var speed := clampf(a.length / dur, 1.0, 2.2) if dur > 0.0 else 1.0
	_oneshot = true
	_shot += 1
	var my := _shot
	animator.shot(state, speed)
	if not is_inside_tree():
		return
	get_tree().create_timer(maxf(a.length / speed - 0.05, 0.05), false).timeout.connect(func():
		if my == _shot and is_instance_valid(self):
			if a.loop_mode != Animation.LOOP_NONE:
				animator.end_shot()
			_end_shot())

var _shot := 0
var _holding := false

## Plays an action once and stays in its last pose (playing dead) until release().
## `at_end` skips straight to the final pose (a body found already lying there).
func pose(state: String, at_end := false) -> void:
	if animator == null or not anim.has_animation(state):
		return
	_oneshot = true
	_holding = true
	_current = state
	_shot += 1
	animator.end_shot()
	animator.set_state(state, 1.0, at_end)
	if at_end:
		advance(0.5)

func release() -> void:
	if _holding:
		_holding = false
		animator.set_state("idle")
		_end_shot()

## True while a one-shot action (swing, shot, hit) is playing.
func busy() -> bool:
	return _oneshot

func _end_shot() -> void:
	if _holding:
		return
	_oneshot = false

## Stops animating and holds the pose it is in, for a ragdoll (or a saved pose) to take
## over the bones.
func freeze_for_ragdoll() -> void:
	if animator:
		animator.set_process(false)
		animator.tree.active = false
	if ik:
		ik.active = false
	if gestures:
		gestures.active = false
	_holding = true
	_oneshot = true

## Settles the animation `dt` seconds on at once (a pose wanted this frame).
func advance(dt: float) -> void:
	if animator:
		animator.update(dt)

## A pose for the arms and chest held whatever the legs do ("" for none): a sword or gun
## held ready while running.
func set_upper(state: String) -> void:
	if animator:
		animator.set_upper(state)

## The ground under the feet, for planting them: Callable(x, z) -> height (NAN unknown).
## Without one, feet find the ground with rays (`exclude`: bodies they must not stand on).
func set_ground(ground: Callable, exclude: Array[RID] = []) -> void:
	if ik:
		ik.ground = ground
		ik.ray_exclude = exclude

## Turns head, neck and chest toward world point `p` (INF to stop), `amount` 0..1.
func look_at_target(p: Vector3, amount := 1.0) -> void:
	_look = p
	_look_w = amount if p != Vector3.INF else 0.0
	_apply_look()

var _look := Vector3.INF
var _look_w := 0.0

## Someone or something to look at wins over an idle glance.
func _apply_look() -> void:
	if ik == null:
		return
	if _look_w > 0.0:
		ik.look_target = _look
		ik.look_weight = _look_w
	elif _glance != Vector3.INF:
		ik.look_target = _glance
		ik.look_weight = 0.5
	else:
		ik.look_target = Vector3.INF
		ik.look_weight = 0.0

## First-person arms ride the camera: no walking legs, no level of detail.
func set_riding_camera() -> void:
	if animator:
		animator.locomotion = false
		animator.lod = false
	if ik:
		ik.feet_on = false
		ik.look_on = false
		ik.breathe = false

# --- Idle variety --------------------------------------------------------------------

var _idle_t := 0.0
var _idle_alt := ""
var _idle_alt_t := 0.0
var _glance_t := 0.0
var _glance := Vector3.INF
var _last_idle_ms := 0

## Standing about, people don't loop one idle: now and then they fold their arms, put
## their hands on their hips, or glance at something nearby.
func _idle_variety() -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_idle_ms) / 1000.0, 0.0, 0.5)
	_last_idle_ms = now
	if _idle_t <= 0.0:
		_idle_t = randf_range(6.0, 16.0)
	_idle_t -= dt
	if _idle_alt != "":
		_idle_alt_t -= dt
		if _idle_alt_t <= 0.0:
			_idle_alt = ""
	if _glance != Vector3.INF:
		_glance_t -= dt
		if _glance_t <= 0.0:
			_glance = Vector3.INF
			_apply_look()
	if _idle_t > 0.0:
		return
	var r := randf()
	if r < 0.5:
		# A glance: somewhere off to one side, at about eye height.
		var a := randf_range(-1.1, 1.1)
		var fwd := global_basis.z.normalized()
		var side := fwd.rotated(Vector3.UP, a)
		_glance = global_position + side * randf_range(4.0, 12.0) + Vector3.UP * randf_range(0.6, 2.0)
		_glance_t = randf_range(1.2, 3.0)
		_apply_look()
	elif r < 0.72 and not _gripping and _held == null and anim.has_animation("fold_arms"):
		_idle_alt = "fold_arms"
		_idle_alt_t = randf_range(5.0, 11.0)
	elif r < 0.85 and not _gripping and _held == null:
		gesture("hips")

func set_flash(v: float) -> void:
	if _body:
		var c: Vector4 = _body.get_instance_shader_parameter("cut")
		if is_equal_approx(c.w, v):
			return
		c.w = v
		_body.set_instance_shader_parameter("cut", c)
		for m in [_clothes, _armour]:
			if m:
				m.set_instance_shader_parameter("flash", v)

## Head turn toward a world point (see look_at_target).
func look_at_point(p: Vector3, amount: float) -> void:
	look_at_target(p, amount)
