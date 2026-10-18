class_name HeldScale
## How big things held in the hand really are, so a pickaxe in a villager's fist is a
## pickaxe and not a six-foot pole. Sizes are the item's longest side in metres, as
## modelled and as the hand holds it (HumanModel.hold keeps props at 1:1 whoever holds
## them). tests/run_tests.gd measures every handheld model against this table.

## Real sizes: the longest side's [shortest, longest] in metres, and for heads that
## stick out sideways (picks, hammers) the most the head may span across (x). From real
## tools and weapons: a pick's haft is 0.6-0.9 m with a head under 0.6 m, a builder's
## hammer about 0.33 m with a head under 0.2 m, an arming sword 0.8-1.1 m, a dagger
## 0.25-0.45 m, a spear 2 m, a longbow about a person's height, a musket 1.5 m.
const REAL := {
	"pickaxe_iron": [0.6, 1.0, 0.6], "pickaxe_mythril": [0.6, 1.0, 0.6],
	"pickaxe_stone": [0.6, 1.0, 0.6], "pickaxe_bronze": [0.6, 1.0, 0.6],
	"pickaxe_steel": [0.6, 1.0, 0.6], "pickaxe_miner": [0.6, 1.0, 0.6],
	"pickaxe_plasma": [0.25, 0.6], "axe_iron": [0.6, 0.95], "axe_mythril": [0.6, 0.95],
	"axe_steel": [0.6, 0.95], "axe_lumber": [0.6, 0.95], "axe_stone": [0.4, 0.8],
	"bronze_axe": [0.4, 0.8], "hand_axe": [0.3, 0.5], "tomahawk": [0.35, 0.5],
	"battle_axe": [0.75, 1.4], "executioner_axe": [0.75, 1.4], "chain_axe": [0.5, 1.0],
	"hammer": [0.28, 0.45, 0.2], "war_hammer": [0.5, 1.0, 0.35],
	"sledgehammer": [0.7, 1.0, 0.3], "power_hammer": [0.5, 1.1], "grav_hammer": [0.5, 1.1],
	"worldbreaker": [0.7, 1.6], "torch": [0.4, 0.75], "flashlight": [0.12, 0.35],
	"flashlight_dead": [0.12, 0.35], "hand_lantern": [0.2, 0.4], "lamp_kerosene": [0.2, 0.4],
	"candle": [0.08, 0.3], "binoculars": [0.1, 0.22], "binoculars_digital": [0.1, 0.22],
	"sword_iron": [0.8, 1.1], "sword_runic": [0.8, 1.1], "steel_sword": [0.85, 1.15],
	"knight_sword": [0.9, 1.25], "bronze_sword": [0.5, 0.8], "falchion": [0.6, 0.95],
	"rapier": [0.95, 1.25], "zweihander": [1.3, 1.85], "sabre": [0.85, 1.05],
	"machete": [0.45, 0.7], "combat_machete": [0.45, 0.7], "mono_katana": [0.9, 1.1],
	"chitin_sword": [0.7, 1.1], "psi_blade": [0.4, 0.9], "dagger": [0.25, 0.45],
	"dragonbone_dagger": [0.25, 0.45], "stone_knife": [0.12, 0.3],
	"skinning_knife": [0.15, 0.32], "bowie_knife": [0.25, 0.42], "survival_knife": [0.2, 0.35],
	"vibro_knife": [0.2, 0.4], "bayonet": [0.3, 0.55], "throwing_knives": [0.15, 0.3],
	"phase_daggers": [0.2, 0.45], "mace": [0.5, 0.9], "kings_mace": [0.5, 0.9],
	"morning_star": [0.5, 0.9], "flail": [0.4, 1.0], "wooden_club": [0.4, 0.9],
	"cudgel": [0.4, 0.9], "warpick": [0.5, 0.9], "stun_baton": [0.3, 0.65],
	"plasma_whip": [0.4, 2.5], "spear": [1.8, 2.6], "hunting_spear": [1.6, 2.4],
	"bronze_spear": [1.6, 2.4], "javelin": [1.2, 2.2], "halberd": [1.8, 2.6],
	"glaive": [1.8, 2.6], "quarterstaff": [1.6, 2.4], "void_lance": [1.8, 3.0],
	"ion_scythe": [1.4, 2.0], "nova_staff": [1.5, 2.1], "longbow": [1.5, 2.0],
	"royal_bow": [1.5, 2.0], "shortbow": [0.9, 1.3], "composite_bow": [0.9, 1.4],
	"crystal_bow": [0.9, 1.6], "eclipse_bow": [1.0, 1.7], "crossbow": [0.55, 0.95],
	"crossbow_runic": [0.55, 0.95], "heavy_crossbow": [0.7, 1.2], "sling": [0.3, 1.1],
	"shovel": [0.9, 1.55], "hoe": [1.1, 1.6], "sickle": [0.3, 0.6], "fishing_rod": [1.5, 3.6],
	"saw": [0.4, 0.8], "tongs": [0.3, 0.6], "bucket": [0.25, 0.4], "tinderbox": [0.05, 0.15],
	"quill_ink": [0.12, 0.35], "mortar_pestle": [0.1, 0.25], "cauldron_small": [0.15, 0.4],
	"wrench": [0.2, 0.45], "crowbar": [0.45, 0.95], "hand_drill": [0.25, 0.5],
	"multitool": [0.08, 0.2], "laser_cutter": [0.15, 0.4], "welder": [0.15, 0.4],
	"mining_laser": [0.2, 0.45], "grapple": [0.2, 0.45], "repair_kit": [0.15, 0.45],
	"toolbox_tech": [0.3, 0.55], "flintlock_pistol": [0.3, 0.5], "musket": [1.3, 1.7],
	"blunderbuss": [0.6, 1.0], "revolver_six": [0.22, 0.4], "lever_rifle": [0.9, 1.1],
	"double_shotgun": [0.9, 1.2], "bolt_rifle": [1.0, 1.3], "derringer": [0.1, 0.18],
	"flare_gun": [0.18, 0.32], "harpoon_gun": [0.8, 1.4], "gatling": [0.6, 1.2],
	"elephant_gun": [0.95, 1.25], "pulse_pistol": [0.17, 0.35], "scrap_pistol": [0.17, 0.35],
	"laser_pistol": [0.17, 0.35], "smart_pistol": [0.17, 0.35], "star_pistol": [0.17, 0.35],
	"needle_gun": [0.2, 0.45], "pulse_smg": [0.45, 0.8], "pulse_rifle": [0.7, 1.1],
	"plasma_rifle": [0.7, 1.1], "auto_shotgun": [0.7, 1.1], "rail_rifle": [0.9, 1.3],
	"gauss_rifle": [0.9, 1.3], "precursor_rifle": [0.9, 1.3], "carbine_combat": [0.7, 1.0],
	"sniper_rail": [1.1, 1.6], "minigun": [0.8, 1.3], "flamethrower": [0.7, 1.2],
	"bio_rifle": [0.7, 1.2], "rocket_launcher": [0.9, 1.5], "arc_launcher": [0.6, 1.0],
	"grenade_launcher": [0.6, 1.0], "hive_cannon": [0.6, 1.2], "spore_launcher": [0.55, 1.1],
	"dynamite": [0.15, 0.3], "frag_grenade": [0.07, 0.15], "frag_grenade_mk2": [0.07, 0.15],
	"emp_grenade": [0.1, 0.2], "smoke_grenade": [0.1, 0.2], "incendiary_grenade": [0.1, 0.2], "void_grenade": [0.05, 0.2],
	"acid_pod": [0.05, 0.2], "swarm_hive": [0.05, 0.2], "star_charge": [0.05, 0.2],
	"gravity_well": [0.05, 0.2], "singularity_orb": [0.05, 0.3], "powder_keg": [0.2, 0.45],
	"fire_bottle": [0.2, 0.32], "fire_pot": [0.14, 0.26], "breach_charge": [0.08, 0.3], "flare_chem": [0.12, 0.3],
	"shard_gauntlet": [0.12, 0.4],
}

## Known wrong, with whose model it is (none now). The test fails once one is fixed, so
## it comes off this list.
const OWED := {}

## What isn't in REAL (food, flasks, trinkets, scrolls, kits) by kind: it fits in a hand.
const KIND_MAX := {"instrument": 1.1, "trap": 0.6}
const CARRY_MAX := 0.6

## The [shortest, longest, most across] an item may be, in metres.
static func real(t: String) -> Array:
	var r: Array = REAL.get(t, [])
	if r.is_empty():
		return [0.02, float(KIND_MAX.get(ItemDB.def(t).get("kind", ""), CARRY_MAX)), INF]
	return [r[0], r[1], r[2] if r.size() > 2 else INF]

## Why `prop` (as modelled, held 1:1) isn't the size a real `t` is, or "" if it is.
static func problem(t: String, prop: Node3D) -> String:
	var s := size(prop)
	var r := real(t)
	var l := maxf(s.x, maxf(s.y, s.z))
	if l < float(r[0]) or l > float(r[1]):
		return "%s is %.2f m long, a real one %.2f-%.2f m" % [t, l, r[0], r[1]]
	if s.x > float(r[2]):
		return "%s's head spans %.2f m, a real one at most %.2f m" % [t, s.x, r[2]]
	return ""

## Nothing modelled yet (an icon card, or Viewmodel's painted block): no size to check.
static func unmodelled(prop: Node3D) -> bool:
	if prop.get_child_count() == 0 or not prop.get_child(0) is MeshInstance3D:
		return false
	var m := (prop.get_child(0) as MeshInstance3D).mesh
	return m is QuadMesh or (m != null and m.has_meta("placeholder"))

## The model's box in its own space (x across, y along the handle, z front to back),
## through its child meshes' transforms. Particles and lights don't count.
static func box(prop: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var meshes := prop.find_children("*", "MeshInstance3D", true, false)
	if prop is MeshInstance3D:
		meshes.append(prop)
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := _drawn(m.mesh, _rel(prop, m))
		if b.size == Vector3.ZERO and b.position == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out

## The box round the vertices a mesh's triangles actually use, through `xf` (kit models
## cut down to their wooden parts keep the cut vertices, which get_aabb counts).
static func _drawn(mesh: Mesh, xf: Transform3D) -> AABB:
	if not mesh is ArrayMesh:
		return xf * mesh.get_aabb()
	var out := AABB()
	var first := true
	for si in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx = a[Mesh.ARRAY_INDEX]
		var used: PackedInt32Array = idx if idx is PackedInt32Array and not idx.is_empty() else PackedInt32Array(range(v.size()))
		for i in used:
			var p := xf * v[i]
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out

static func size(prop: Node3D) -> Vector3:
	return box(prop).size

static func longest(prop: Node3D) -> float:
	var s := size(prop)
	return maxf(s.x, maxf(s.y, s.z))

static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf
