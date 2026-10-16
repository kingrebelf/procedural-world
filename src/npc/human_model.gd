class_name HumanModel
extends Node3D
## A person built from the CC0 Universal Base Characters (Quaternius): a skinned base body
## dressed by human.gdshader (shirt, trousers, boots, robe, era trims, all per person
## through instance uniforms), a hairstyle bound to the same skeleton, era headgear and a
## work tool in hand, animated with the Universal Animation Library (baked into
## assets/models/anim/humans.res by tools/bake_anims.gd).

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
var anim: AnimationPlayer
var _body: MeshInstance3D
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
		custom[v * 3 + 2] = absf(verts[v].x)
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
	_dress(b, era, job)
	# Hair, unless a helmet or hood covers it.
	var styles: Array = HAIR_FEMALE if fem else HAIR_MALE
	var style: String = styles[int(b["hair_style"]) % styles.size()]
	if NPCGen.GUARD_JOBS.has(job):
		style = "Hair_Buzzed" if not fem else "Hair_BuzzedFemale"
	if style != "":
		_add_hair(style, hair_col)
	if not fem and int(b["hair_style"]) % 2 == 1 and era != Eras.SCIFI:
		_add_hair("Hair_Beard", hair_col)
	_headgear(era, job, b)
	_tool(era, job)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	anim = AnimationPlayer.new()
	scene.add_child(anim)
	anim.add_animation_library("", library())
	anim.animation_finished.connect(func(_n): _oneshot = false)
	play("idle")
	return self

func _dress(b: Dictionary, era: int, job: String) -> void:
	var cloth: Color = b["cloth"]
	var cloth2: Color = b["cloth2"]
	var boots := Color(0.22, 0.15, 0.1) if era != Eras.SCIFI else Color(0.14, 0.15, 0.17)
	var fem: bool = b["female"]
	var sleeves := 2.0
	var hem := 0.0
	var accent := Color(0, 0, 0, 0)
	match era:
		Eras.MEDIEVAL:
			sleeves = 1.0 if job in ["farmer", "smith", "miller", "hunter"] else 2.0
			if fem or job == "priest":
				hem = 0.12
		Eras.FANTASY:
			hem = 0.45 if job in ["mystic", "scribe", "runecarver", "herbalist"] else 0.0
			if fem:
				hem = maxf(hem, 0.3)
			accent = Color(0.4, 1.0, 0.7, 0.0)
		Eras.SCIFI:
			accent = Color(0.3, 0.9, 1.0, 1.0)
			cloth2 = cloth.darkened(0.25)
	_body.set_instance_shader_parameter("skin_col", b["skin"])
	_body.set_instance_shader_parameter("shirt_col", cloth)
	_body.set_instance_shader_parameter("pants_col", cloth2)
	_body.set_instance_shader_parameter("boot_col", boots)
	_body.set_instance_shader_parameter("accent_col", accent)
	_body.set_instance_shader_parameter("cut", Vector4(sleeves, 0.38 if era != Eras.FANTASY else 0.2, hem, 0.0))

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
	src.free()

func _bone_attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba

func _headgear(era: int, job: String, b: Dictionary) -> void:
	var k := MeshKit.new(7)
	var I := Transform3D.IDENTITY
	if NPCGen.GUARD_JOBS.has(job):
		var mat := "iron" if era == Eras.MEDIEVAL else ("crystal@5" if era == Eras.FANTASY else "panel")
		k.sphere(mat, I.translated(Vector3(0, 0.1, -0.01)) * Transform3D(Basis.from_scale(Vector3(1.0, 0.95, 1.08)), Vector3.ZERO), 0.135, 8, 12, 0.0, 1.0)
		if era == Eras.MEDIEVAL:
			k.box(mat, I.translated(Vector3(0, 0.06, 0.13)), Vector3(0.03, 0.12, 0.02))
	elif era == Eras.MEDIEVAL and job in ["farmer", "hunter", "miller"]:
		k.cylinder("thatch", I.translated(Vector3(0, 0.17, 0)), 0.095, 0.07, 0.09, 10)
		k.cylinder("thatch", I.translated(Vector3(0, 0.15, 0)), 0.22, 0.22, 0.015, 14)
	elif era == Eras.FANTASY and job in ["mystic", "warden", "herbalist"]:
		k.cylinder("cloth_w", I.translated(Vector3(0, 0.12, -0.02)), 0.13, 0.0, 0.3, 10, true, 0.0, 1, b["cloth2"])
	else:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(Materials.get_mat)
	_bone_attach("Head").add_child(mi)

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

## Where a held prop goes in the right hand's space, worked out from the hand's own rest
## pose: the shaft runs across the knuckles (index to pinky, as a fist holds a blade up), the fist closes around it
## just past the knuckles, and the prop is held near the low end of its handle.
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
	var up := (p - i).normalized()
	if aim != Vector3.ZERO:
		if up.dot(aim) < 0.0:
			up = -up
		up = up.slerp(aim.normalized(), tilt).normalized()
	var fwd := (m - up * m.dot(up)).normalized()
	var side := fwd.cross(up).normalized()
	var center := (i + p) * 0.5 + fwd * 0.035 + side * 0.02
	# The prop's handle: its lowest point plus a hand's width, in the prop's own space.
	var box := AABB()
	var first := true
	for mi in prop.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = _rel(prop, mi)
		var b: AABB = xf * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var grip_y := box.position.y + minf(0.12, box.size.y * 0.25)
	var basis := Basis(fwd * scale, up * scale, fwd.cross(up) * scale)
	if point != Vector3.ZERO:
		var z := -point.normalized()
		var y := (aim - z * aim.dot(z)).normalized()
		basis = Basis(y.cross(z) * scale, y * scale, z * scale)
	return Transform3D(basis, center - basis * Vector3(0, grip_y, 0))

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
	if prop == null or skeleton == null:
		return
	var ba := _bone_attach("hand_r")
	ba.add_child(prop)
	prop.transform = grip_transform(skeleton, prop, 1.0, aim, tilt, point)
	_held = ba
	for mi in prop.find_children("*", "MeshInstance3D", true, false) + ([prop] if prop is MeshInstance3D else []):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _arms else (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _shadow_only else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

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
	return (pose.basis.inverse() * dir).normalized()

## First-person arms: only the arms and hands are drawn, nothing casts shadows.
func set_arms_only() -> void:
	_arms = true
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if m == _body:
			m.set_instance_shader_parameter("arms_only", 1.0)
		elif not _is_held(m):
			m.visible = false

func _is_held(n: Node) -> bool:
	return _held != null and _held.is_ancestor_of(n)

## Shadow-only body (first person): you see your shadow, not the inside of your head.
func set_shadow_only(on: bool) -> void:
	_shadow_only = on
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## Plays a looping state, cross-fading. Ignored while a one-shot (hit, attack) runs.
func play(state: String, speed := 1.0) -> void:
	if anim == null or _oneshot:
		return
	anim.speed_scale = speed
	if state == _current:
		return
	if not anim.has_animation(state):
		state = "idle"
	_current = state
	anim.play(state, 0.25)

func play_once(state: String) -> void:
	if anim == null or not anim.has_animation(state):
		return
	_oneshot = true
	_current = state
	anim.speed_scale = 1.0
	anim.play(state, 0.1)

func set_flash(v: float) -> void:
	if _body:
		var c: Vector4 = _body.get_instance_shader_parameter("cut")
		c.w = v
		_body.set_instance_shader_parameter("cut", c)

## Head turn toward a world point, applied after the animation each frame.
func look_at_point(p: Vector3, amount: float) -> void:
	if skeleton == null:
		return
	var hb := skeleton.find_bone("Head")
	if hb < 0:
		return
	var local := global_transform.affine_inverse() * p
	var yaw := clampf(atan2(local.x, local.z), -1.0, 1.0) * amount
	var pose := skeleton.get_bone_pose_rotation(hb)
	skeleton.set_bone_pose_rotation(hb, Quaternion(Vector3.UP, yaw) * pose)
