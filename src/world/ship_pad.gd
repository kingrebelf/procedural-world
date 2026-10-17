class_name ShipPad
## Landing pads at sci-fi outposts, each with a ship from the CC0 Ultimate Spaceships
## Pack (Quaternius) set down on its landing struts: one object type per ship
## ("pad_omen" and so on), nose to +z.

const SHIPS := {"pad_bob": "Bob", "pad_challenger": "Challenger", "pad_dispatcher": "Dispatcher",
	"pad_executioner": "Executioner", "pad_imperial": "Imperial", "pad_insurgent": "Insurgent", "pad_omen": "Omen",
	"pad_pancake": "Pancake", "pad_spitfire": "Spitfire", "pad_zenith": "Zenith"}
## The pad's side; ships are scaled down until their longest side fits FIT.
const PAD := 12.0
const FIT := 11.0
## The hull rides this high on its struts.
const STRUTS := 0.9

static func has(t: String) -> bool:
	return SHIPS.has(t)

static func label(t: String) -> String:
	return "Landed %s" % SHIPS[t]

static func pick(r: RandomNumberGenerator) -> String:
	var keys := SHIPS.keys()
	return keys[r.randi() % keys.size()]

## The ship's place on the pad: [scale, offset of the model's origin].
static func _fit(t: String) -> Array:
	var box := KitHouse._model_box("ships/" + SHIPS[t], Transform3D.IDENTITY)
	var s := minf(1.0, FIT / maxf(box.size.x, box.size.z))
	var c := box.get_center()
	return [s, Vector3(-c.x * s, STRUTS - box.position.y * s, -c.z * s), box]

static func build(t: String) -> ArrayMesh:
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var models: Array = []
	var I := Transform3D.IDENTITY
	# The pad: kit floor plates on a base flush with the ground, a landing mark, lights.
	k.box("metal_dark", I.translated(Vector3(0, -0.15, 0)), Vector3(PAD, 0.35, PAD))
	for x in [-4.0, 0.0, 4.0]:
		for z in [-4.0, 0.0, 4.0]:
			models.append(["scifi/Platform_Metal", 0, Vector3(x, 0.0, z), 1.0])
	var mark := Color(0.86, 0.68, 0.16)
	for x in [-1.6, 1.6]:
		k.box("painted", I.translated(Vector3(x, 0.03, 0)), Vector3(0.45, 0.02, 4.4), mark)
	k.box("painted", I.translated(Vector3(0, 0.03, 0)), Vector3(2.8, 0.02, 0.45), mark)
	for x in [-5.4, 5.4]:
		for z in [-5.4, 5.4]:
			models.append(["scifi/Prop_Light_Floor", 0, Vector3(x, 0.05, z), 1.0])
	# The ship on three struts, a fuel line and its cargo set down beside it.
	var fit := _fit(t)
	var s: float = fit[0]
	var at: Vector3 = fit[1]
	var box: AABB = fit[2]
	models.append(["ships/" + SHIPS[t], 0, at, s])
	var hx := box.size.x * s * 0.22
	var hz := box.size.z * s * 0.3
	for p in [Vector3(0, 0, hz), Vector3(-hx, 0, -hz * 0.8), Vector3(hx, 0, -hz * 0.8)]:
		k.cylinder("metal_dark", I.translated(p), 0.09, 0.07, STRUTS + 0.5, 8)
		k.cylinder("metal", I.translated(p), 0.28, 0.24, 0.08, 10)
	models.append(["scifi/Prop_Barrel_Large", 0, Vector3(-PAD * 0.5 + 0.9, 0.02, PAD * 0.5 - 1.0), 1.0])
	models.append(["scifi/Prop_Barrel_Large", 0, Vector3(-PAD * 0.5 + 1.6, 0.02, PAD * 0.5 - 1.0), 1.0])
	models.append(["scifi/Prop_Crate4", 30, Vector3(PAD * 0.5 - 1.2, 0.56, PAD * 0.5 - 1.3), 1.0])
	models.append(["scifi/Prop_Computer", 180, Vector3(0.0, 0.02, PAD * 0.5 - 0.6), 1.0])
	var mesh := BuildCatalog.merge_models(models)
	k.commit(Materials.get_mat, mesh)
	return mesh

## Collision: the hull as a box on its struts, from the pad up; walk round it.
static func shape(t: String) -> Array:
	var fit := _fit(t)
	var s: float = fit[0]
	var box: AABB = fit[2]
	var b := BoxShape3D.new()
	b.size = Vector3(box.size.x * s * 0.8, STRUTS + box.size.y * s, box.size.z * s * 0.85)
	return [b, Vector3(0, b.size.y * 0.5 - KitHouse.SINK, 0)]

## Salvage: what a landed ship gives up when it is cut apart.
const SALVAGE := ["metal", 900.0, [["alloy_plate", 12], ["alloy_scrap", 16], ["circuitry", 8], ["power_cell", 3]]]
