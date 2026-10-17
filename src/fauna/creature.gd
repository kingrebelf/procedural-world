class_name Creature
extends Node3D
## A wild animal. Its species (body plan, size, colours, temperament, drops) is rolled
## from a seed by the region's biome, so each region has its own wildlife. Herds are
## derived from the chunk they live in; a creature that is killed is recorded in that
## chunk's snapshot and never comes back.

var sp: int
var era: int
var p: Dictionary
var id: String
var home: Vector3
var manager: Node
var hp := 30.0

var state := "wander"
var _target := Vector3.ZERO
var _think := 0.0
var _phase := 0.0
var _speed := 0.0
var _legs: Array = []
var _wings: Array = []
var _flap := 0.7 ## wing beat amplitude, radians
var _model: Node3D
var _body: AnimatableBody3D
var _bite_cd := 0.0
## Lives in a cave: walks on the cave floor (FaunaManager.cave_floor), stopped by its walls.
var underground := false
var _flash := 0.0
var _alert_t := 0.0 ## how long a wary animal has been watching you
var _graze_clip := "Eating"
var _ground: Callable ## terrain height at (x, z), from the manager each step
var _unstuck := 0.0
## Drawn as a carcass (see Corpses): no hit box, no mind, lying where it fell. `fresh`
## plays the fall; otherwise it is already down.
var as_corpse := false
var held_for := 0.0 ## seconds left caught in a trap (Traps): it cannot move
var fresh := false
var limp := false ## lies as a ragdoll (Corpses lays it), not in its death clip

const NAMES := [
	{"quad": ["Red Deer", "Elk", "Wild Boar", "Grey Wolf", "Hare", "Aurochs", "Red Fox", "Wild Horse", "Wild Donkey"], "bird": ["Crow", "Kestrel", "Swallow"]},
	{"quad": ["Mossback", "Glimmerhart", "Thornhound", "Fae Hare", "Woolly Lumen"], "hexa": ["Lantern Strider"], "bird": ["Glowmoth", "Wisp Finch"]},
	{"quad": ["Dune Runner"], "hexa": ["Rust Crawler", "Hexapod"], "bird": ["Drift Jelly", "Scout Drone"]},
]

## Species drawn with a rigged kit animal (AnimalModel) instead of the procedural body.
const KIT_OF := {"Red Deer": "Deer", "Elk": "Stag", "Grey Wolf": "Wolf", "Aurochs": "Bull", "Red Fox": "Fox",
	"Wild Horse": "Horse", "Wild Donkey": "Donkey", "Mossback": "Bull", "Glimmerhart": "Stag",
	"Thornhound": "Wolf", "Woolly Lumen": "Alpaca", "Dune Runner": "Horse",
	"Rust Crawler": "Alien_Scolitex", "Hexapod": "Alien_Scolitex", "Lantern Strider": "Alien_Scolitex",
	"Drift Jelly": "Alien_Oculichrysalis", "Scout Drone": "Alien_Cyclop",
	"Wild Boar": "Boar", "Hare": "Hare", "Fae Hare": "Hare"}

## Stronghold guards (negative species, -tier): hounds, crypt stalkers and sentry
## crawlers, tougher and harder-biting with each tier.
const GUARD_NAMES := ["Castle Hound", "Crypt Stalker", "Sentry Crawler"]
const GUARD_RANKS := ["", "Veteran ", "Dread ", "Elite ", "Mythic "] ## tiers 4 and 5 guard wonders

static func guard_species(era: int, tier: int) -> Dictionary:
	var p := species(911 + era * 7, era)
	p["name"] = GUARD_RANKS[clampi(tier - 1, 0, GUARD_RANKS.size() - 1)] + GUARD_NAMES[era]
	p["temper"] = "aggressive"
	p["herd"] = 1
	if era == Eras.SCIFI and Eras.theme == "human":
		# Human outposts keep armoured patrol dogs, not alien crawlers.
		p["name"] = GUARD_RANKS[clampi(tier - 1, 0, GUARD_RANKS.size() - 1)] + "Patrol Hound"
		p["plan"] = "quad"
		p["kit"] = "Husky"
		p["kit_scale"] = 1.1 + 0.08 * tier
		p["size"] = AnimalModel.HEIGHT["Husky"] / 1.2 * float(p["kit_scale"])
		p["col"] = Color(0.3, 0.3, 0.32)
		p["col2"] = Color(0.45, 0.45, 0.48)
		p["has_glow"] = false
		p["drops"] = [["hide", 1 + tier], ["circuitry", tier]]
	elif era == Eras.SCIFI:
		p["plan"] = "hexa"
		p["kit"] = "Alien_Scolitex"
		p["kit_scale"] = 1.0 + 0.12 * tier
		p["size"] = AnimalModel.HEIGHT["Alien_Scolitex"] / 1.2 * float(p["kit_scale"])
		p["col"] = Color(0.55, 0.22, 0.12)
		p["col2"] = Color(0.75, 0.3, 0.15)
		p["has_glow"] = true
		p["drops"] = [["alloy_scrap", 2 + tier], ["circuitry", tier]]
	else:
		p["plan"] = "quad"
		p["kit"] = "Wolf"
		p["kit_scale"] = 1.05 + 0.08 * tier
		p["size"] = AnimalModel.HEIGHT["Wolf"] / 1.2 * float(p["kit_scale"])
		p["drops"] = [["raw_meat", 2], ["hide", 1 + tier]]
	p["speed"] = 2.6 + 0.3 * tier
	p["hp"] = (18.0 + float(p["size"]) * 30.0) * (1.0 + 0.9 * tier)
	p["bite_mult"] = 1.0 + 0.5 * tier
	p["guard"] = tier
	return p

## Village livestock (species -200 - kind): cows, horses and dogs that keep to the
## houses they belong to and pay you no mind until you hurt them. [names by era
## (medieval, fantasy), kit, speed, roam radius, drops]
const LIVESTOCK := [
	[["Milk Cow", "Mooncalf"], "Cow", 1.3, 9.0, [["raw_meat", 3], ["hide", 2]]],
	[["Plough Horse", "Moon Mare"], "Horse_White", 1.8, 11.0, [["raw_meat", 2], ["hide", 2]]],
	[["Village Dog", "Hearth Hound"], "Husky", 2.4, 8.0, [["raw_meat", 1], ["hide", 1]]],
	[["Shiba", "Ember Pup"], "ShibaInu", 2.6, 7.0, [["raw_meat", 1], ["hide", 1]]],
]

static func livestock_species(kind: int, era: int) -> Dictionary:
	var l: Array = LIVESTOCK[clampi(kind, 0, LIVESTOCK.size() - 1)]
	var p := species(5101 + kind * 13, era)
	p["name"] = l[0][1 if era == Eras.FANTASY else 0]
	p["kit"] = l[1]
	p["kit_scale"] = 1.0
	p["size"] = AnimalModel.HEIGHT[l[1]] / 1.2
	p["plan"] = "quad"
	p["tint"] = null
	p["has_glow"] = false
	p["horns"] = false
	p["temper"] = "tame"
	p["herd"] = 1
	p["speed"] = l[2]
	p["roam"] = l[3]
	p["hp"] = 18.0 + float(p["size"]) * 30.0
	p["drops"] = l[4]
	p["livestock"] = kind
	return p

## Livestock about a village's houses in this chunk (two or more): cows, a horse, a
## dog or two, near the houses. Deterministic per chunk, like the wild herds.
static func livestock_for(seed: int, chunk: Dictionary) -> Array:
	var out: Array = []
	var houses: Array = []
	for o in chunk.get("objects", []):
		if (KitHouse.has(o["t"]) or o["t"] == "mushroom_house") and not o["st"].get("gone", false):
			houses.append(o)
	if houses.size() < 2:
		return out
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var r := WHash.rng(seed, cx, cz, 702)
	var kinds: Array = [0, 0, 2] if r.randf() < 0.5 else [0, 1, 3]
	if r.randf() < 0.4:
		kinds.append(0)
	for i in kinds.size():
		var h: Dictionary = houses[r.randi() % houses.size()]
		var hp: Vector3 = h["p"]
		var a := r.randf() * TAU
		var d := r.randf_range(5.0, 9.0)
		out.append({"id": "%d_%d_v%d" % [cx, cz, i], "sp": -200 - int(kinds[i]), "era": int(h["e"]),
			"lx": clampf(hp.x + cos(a) * d, 0, 63.9), "lz": clampf(hp.z + sin(a) * d, 0, 63.9)})
	return out

## The boss of wonder kind `kind` (an index into WonderSite.TYPES): negative species
## below -100.
static func boss_species(kind: int, era: int) -> Dictionary:
	var t: String = WonderSite.TYPES[clampi(kind, 0, WonderSite.TYPES.size() - 1)]
	var b: Array = WonderSite.BOSSES[t]
	var p := species(4243 + kind * 17, era)
	p["name"] = b[0]
	p["kit"] = b[1]
	p["kit_scale"] = b[2]
	p["size"] = AnimalModel.HEIGHT[b[1]] / 1.2 * float(b[2])
	p["plan"] = "hexa" if String(b[1]).begins_with("Alien") else "quad"
	p["col"] = b[3]
	p["col2"] = (b[3] as Color).lightened(0.3)
	p["tint"] = b[3]
	p["has_glow"] = b[4]
	p["temper"] = "aggressive"
	p["herd"] = 1
	p["speed"] = 2.5
	# Older worlds have no zones, so their bosses keep the old fixed toughness.
	p["hp"] = WonderSite.BOSS_HP if Eras.themed() else WonderSite.LEGACY_BOSS_HP
	p["bite_mult"] = WonderSite.BOSS_BITE if Eras.themed() else WonderSite.LEGACY_BOSS_BITE
	p["drops"] = b[5]
	p["boss"] = t
	return p

static func species(sp: int, era: int) -> Dictionary:
	if sp <= -200:
		return livestock_species(-sp - 200, era)
	if sp <= -100:
		return boss_species(-sp - 100, era)
	if sp < 0:
		return guard_species(era, -sp)
	var r := RandomNumberGenerator.new()
	r.seed = WHash.combine(sp, 31)
	var plans: Array = [["quad", "quad", "quad", "bird"], ["quad", "hexa", "bird", "bird"], ["hexa", "hexa", "quad", "bird"]][era]
	var plan: String = plans[r.randi() % plans.size()]
	var names: Array = NAMES[era][plan]
	var name: String = names[r.randi() % names.size()]
	var temper := "skittish"
	var tr := r.randf()
	if tr < 0.2:
		temper = "aggressive"
	elif tr < 0.5:
		temper = "neutral"
	if name in ["Grey Wolf", "Thornhound"]:
		temper = "aggressive"
	if name in ["Hare", "Fae Hare", "Red Deer", "Glimmerhart", "Red Fox", "Wild Horse", "Wild Donkey", "Woolly Lumen"]:
		temper = "skittish"
	var size := r.randf_range(0.5, 1.6)
	if name.contains("Hare"):
		size = r.randf_range(0.25, 0.4)
	elif name in ["Elk", "Aurochs", "Mossback"]:
		size = r.randf_range(1.4, 2.2)
	var hue := r.randf()
	var col: Color
	match era:
		Eras.MEDIEVAL: col = Color.from_hsv(r.randf_range(0.04, 0.1), r.randf_range(0.3, 0.7), r.randf_range(0.2, 0.55))
		Eras.FANTASY: col = Color.from_hsv(hue, r.randf_range(0.3, 0.7), r.randf_range(0.3, 0.7))
		_: col = Color.from_hsv(r.randf_range(0.0, 0.15), r.randf_range(0.0, 0.3), r.randf_range(0.3, 0.6))
	var drops: Array = [["raw_meat", r.randi_range(1, 3)], ["hide", 1]]
	if era == Eras.SCIFI and plan != "quad":
		drops = [["alloy_scrap", r.randi_range(1, 3)], ["circuitry", 1]]
	elif era == Eras.FANTASY and plan == "bird":
		drops = [["glowberry", 1], ["aether_crystal", 1]]
	var kit: String = KIT_OF.get(name, "")
	var kit_scale := r.randf_range(0.88, 1.12)
	if kit != "":
		# Body size (bite reach, health) follows the real animal.
		size = AnimalModel.HEIGHT[kit] / 1.2 * kit_scale
	return {
		"kit": kit, "kit_scale": kit_scale,
		"plan": plan, "name": name, "temper": temper, "size": size, "col": col,
		"col2": col.lightened(r.randf_range(0.1, 0.4)), "glow": r.randi() % 12,
		"has_glow": era != Eras.MEDIEVAL and r.randf() < 0.7, "horns": plan == "quad" and r.randf() < 0.4,
		"speed": r.randf_range(1.5, 3.0) * (1.6 if temper == "skittish" else 1.0),
		"hp": 18.0 + size * 30.0, "drops": drops, "herd": r.randi_range(1, 5) if temper != "aggressive" else r.randi_range(1, 3),
		"leg": r.randf_range(0.7, 1.3), "neck": r.randf_range(0.2, 0.9), "alt": r.randf_range(3.0, 14.0),
	}

func setup(_id: String, _sp: int, _era: int, at: Vector3, m: Node) -> void:
	id = _id
	sp = _sp
	era = _era
	p = species(sp, era)
	if sp > -200: # wild animals, guards and wonder bosses
		_zone_scale(at)
	home = at
	manager = m
	hp = p["hp"]
	name = "Creature_" + id

## Wild animals and guards grow tougher with the zone level of where they live (themed
## worlds): about +12% health and +4% bite per level, so a level 40 zone's wolves are
## level 40-ish beasts. Livestock stay as they are.
func _zone_scale(at: Vector3) -> void:
	var zl := Eras.zone_level(at.x, at.z)
	p = p.duplicate()
	p["zone"] = zl
	if zl <= 1:
		return
	p["hp"] = float(p["hp"]) * (1.0 + 0.12 * (zl - 1))
	p["bite_mult"] = float(p.get("bite_mult", 1.0)) * (1.0 + 0.04 * (zl - 1))

func _ready() -> void:
	_build()
	if as_corpse:
		_lie_dead()
		return
	_body = AnimatableBody3D.new()
	_body.collision_layer = 2
	_body.collision_mask = 0
	# Follow the model as it walks. With sync_to_physics on, a body under a moving parent
	# stays where it spawned, so shots aimed at the animal passed straight through it.
	_body.sync_to_physics = false
	_body.set_meta("creature", self)
	# Hit box fitted to the whole model (head, body and legs), so a big animal can be hit
	# wherever you swing at it, not only in a small ball at its middle.
	var box := _model_bounds()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = box.size.max(Vector3(0.3, 0.3, 0.3))
	cs.shape = sh
	cs.position = box.get_center()
	_body.add_child(cs)
	add_child(_body)
	global_position = home
	_pick_wander()

## Whether a hit at world point `p` lands on the head: the upper front of the body
## box (animals face +Z as they walk).
func is_head(p: Vector3) -> bool:
	if _body == null or _body.get_child_count() == 0:
		return false
	var cs := _body.get_child(0) as CollisionShape3D
	var size: Vector3 = (cs.shape as BoxShape3D).size
	var l := _body.to_local(p) - cs.position
	return l.z > size.z * 0.18 and l.y > -size.y * 0.05

func label() -> String:
	return p["name"]

## Danger rating shown over the animal: grows with its health and bite.
func level() -> int:
	return Creature.level_of(p)

static func level_of(sp_p: Dictionary) -> int:
	var lv := 1.0 + (float(sp_p["hp"]) - 18.0) / 8.0
	if sp_p["temper"] == "aggressive":
		lv += 2.0
	if not Eras.themed():
		# Older worlds have no zones: rate by toughness, as they always were.
		lv += float(sp_p.get("guard", 0)) * 4.0
		return 60 if sp_p.has("boss") else clampi(int(round(lv)), 1, 60)
	var zone := int(sp_p.get("zone", 1))
	if sp_p.has("boss"):
		# A few levels above the zone it guards.
		return clampi(zone + WonderSite.BOSS_ABOVE, 1, Stats.MAX_LEVEL)
	if sp_p.has("guard"):
		# Guards rate by where they stand: elites a few levels over the zone, not 50.
		return clampi(zone + 1 + int(sp_p["guard"]) / 2, 1, Stats.MAX_LEVEL)
	if sp_p.has("zone") and zone > 1:
		# Its health was scaled up for the zone; rate it by the zone instead.
		lv = float(zone) + (2.0 if sp_p["temper"] == "aggressive" else 0.0)
	return clampi(int(round(lv)), 1, maxi(60, zone + 2))

func bite_damage() -> float:
	return (4.0 + float(p["size"]) * 6.0) * float(p.get("bite_mult", 1.0))

# --- Floating tag: level, name and health -----------------------------------------
var _tag: Node3D
var _tag_label: Label3D
var _tag_bar: MeshInstance3D

## Shows the tag (within `range` metres of the viewer), coloured by danger relative to
## the player's level, with a health bar.
func update_tag(show: bool, player_level: int) -> void:
	if not show:
		if _tag:
			_tag.visible = false
		return
	if _tag == null:
		_build_tag()
	_tag.visible = true
	var lv := level()
	var c := Color(0.75, 1.0, 0.7)
	if p["temper"] == "aggressive":
		c = Color(1.0, 0.45, 0.35) if lv > player_level + 2 else Color(1.0, 0.8, 0.4)
	_tag_label.modulate = c
	_tag_label.text = "Lv %d  %s" % [lv, label()]
	var f := clampf(hp / float(p["hp"]), 0.0, 1.0)
	_tag_bar.scale = Vector3(maxf(f, 0.001), 1, 1)
	_tag_bar.position.x = -(1.0 - f) * 0.45

func _build_tag() -> void:
	_tag = Node3D.new()
	var top := _model_bounds().end.y
	_tag.position = Vector3(0, top + 0.45, 0)
	add_child(_tag)
	# The tag ignores the animal's turning: it is a billboard child.
	_tag_label = Label3D.new()
	_tag_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag_label.fixed_size = true
	_tag_label.pixel_size = 0.0011
	_tag_label.font_size = 26
	_tag_label.outline_size = 8
	_tag_label.no_depth_test = true
	_tag_label.position = Vector3(0, 0.12, 0)
	_tag.add_child(_tag_label)
	var holder := Node3D.new()
	_tag.add_child(holder)
	var back := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.07)
	back.mesh = q
	back.material_override = _bar_mat(Color(0, 0, 0, 0.6))
	holder.add_child(back)
	_tag_bar = MeshInstance3D.new()
	_tag_bar.mesh = q
	_tag_bar.material_override = _bar_mat(Color(0.9, 0.2, 0.15))
	_tag_bar.position.z = 0.001
	back.add_child(_tag_bar)

static func _bar_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = 1 if c.a >= 1.0 else 0
	return m

func _pick_wander() -> void:
	var roam: float = p.get("roam", 22.0)
	for i in 6:
		var a := randf() * TAU
		_target = home + Vector3(cos(a), 0, sin(a)) * randf_range(minf(3.0, roam * 0.3), roam)
		if underground or p["plan"] == "bird" or not blocked(_target.x, _target.z):
			return

## True where a walking animal can't stand: in the sea, a lake or a river, or inside a
## rock, tree trunk or wall. Solid things are found with a ray from head height down to
## just above the ground, so it only sees what has colliders (loaded ground near you).
func blocked(x: float, z: float) -> bool:
	var h: float = _ground.call(x, z) if _ground.is_valid() else NAN
	if is_nan(h):
		return false
	if blocked_wet(x, z):
		return true
	return solid_at(Vector3(x, h, z))

## The way to walk from `pos` heading `dir`: straight on if the ground ahead is clear,
## else the nearest clear bearing to either side, or ZERO if none is. An animal already
## in the water (chased in, or swimming) may keep going until it is out.
func _steer(pos: Vector3, dir: Vector3) -> Vector3:
	var reach := 0.5 + float(p.get("size", 1.0)) * 0.5
	var wet_here := blocked_wet(pos.x, pos.z)
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9]:
		var d: Vector3 = dir.rotated(Vector3.UP, turn)
		var ahead := pos + d * reach
		var h: float = _ground.call(ahead.x, ahead.z) if _ground.is_valid() else NAN
		if is_nan(h):
			return d
		if not wet_here and blocked_wet(ahead.x, ahead.z):
			continue
		if solid_at(Vector3(ahead.x, h, ahead.z)):
			continue
		return d
	return Vector3.ZERO

func blocked_wet(x: float, z: float) -> bool:
	var h: float = _ground.call(x, z) if _ground.is_valid() else NAN
	return not is_nan(h) and (h < Water.LEVEL + 0.15 or h < Water.surface_height(x, z, 0.0) + 0.05)

## Spawned (or pushed) inside a rock or out in the water: move to the nearest clear
## ground within a few metres, and make it the animal's new home.
func _get_unstuck() -> void:
	var at := global_position
	if not blocked(at.x, at.z):
		return
	for r in [1.5, 3.0, 5.0, 8.0, 12.0]:
		for i in 8:
			var a := TAU * (float(i) + 0.5 * float(int(r) % 2)) / 8.0
			var q: Vector3 = at + Vector3(cos(a), 0, sin(a)) * r
			if not blocked(q.x, q.z):
				var h: float = _ground.call(q.x, q.z)
				global_position = Vector3(q.x, h, q.z)
				home = global_position
				_pick_wander()
				return

## Something solid (not another animal or a person) between knee and head height here.
func solid_at(at: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var top := maxf(0.9, float(p.get("size", 1.0)) * 0.9)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, top, 0), at + Vector3(0, 0.3, 0), 1 | 2)
	var space := get_world_3d().direct_space_state
	for i in 4:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return false
		var c: Object = hit["collider"]
		if not (c is CharacterBody3D or (c is Node and (c as Node).has_meta("creature"))):
			return true
		q.exclude = q.exclude + [hit["rid"]]
	return false

func step(delta: float, ground: Callable, player_pos: Vector3) -> void:
	_ground = ground
	_bite_cd = maxf(0.0, _bite_cd - delta)
	if held_for > 0.0:
		held_for -= delta
		return
	_think -= delta
	var d := global_position.distance_to(player_pos)
	if _think <= 0.0:
		_think = randf_range(0.4, 1.0)
		var t: String = p["temper"]
		if t == "skittish" and d < 14.0:
			state = "flee"
		elif t == "skittish" and d < 24.0 and state in ["wander", "graze", "alert"] and p["plan"] != "bird":
			# Heads up: it stops and watches you, and bolts if you come closer or linger.
			state = "alert"
			if _alert_t > randf_range(4.0, 9.0):
				state = "flee"
		elif t == "aggressive" and d < 16.0:
			state = "chase"
		elif state == "flee" and d > 26.0 or state == "chase" and d > 30.0 or state == "alert":
			state = "wander"
			_pick_wander()
		elif state == "wander" and randf() < 0.15:
			state = "graze"
			_graze_clip = _pick_graze()
		elif state == "graze" and randf() < 0.3:
			state = "wander"
			_pick_wander()
	_alert_t = _alert_t + delta if state == "alert" else 0.0
	if _kit:
		_kit.ground = ground
		if state in ["alert", "chase"]:
			_kit.look_at_target(player_pos + Vector3.UP * 1.4, 1.0)
		elif state != "flee" and d < 8.0:
			_kit.look_at_target(player_pos + Vector3.UP * 1.4, 0.5)
		else:
			_kit.look_at_target(Vector3.INF)
	var goal := _target
	var want := 0.0
	match state:
		"alert":
			want = 0.0
			goal = player_pos
			var face := atan2(player_pos.x - global_position.x, player_pos.z - global_position.z)
			rotation.y = lerp_angle(rotation.y, face, clampf(delta * 2.5, 0.0, 1.0))
		"wander":
			want = float(p["speed"]) * 0.35
			if Vector2(global_position.x, global_position.z).distance_to(Vector2(_target.x, _target.z)) < 1.0:
				_pick_wander()
		"flee":
			want = float(p["speed"]) * 2.0
			goal = global_position + (global_position - player_pos).normalized() * 10.0
		"chase":
			want = float(p["speed"]) * 1.6
			goal = player_pos
			if d < 1.2 + float(p["size"]) * 0.5:
				want = 0.0
				if _bite_cd <= 0.0:
					_bite_cd = 1.3
					if _kit:
						_kit.play_once("Attack" if _kit.anim.has_animation("Attack") else "Attack_Headbutt")
					manager.creature_bites(self)
	_speed = move_toward(_speed, want, delta * 6.0)
	var pos := global_position
	var dir := Vector3(goal.x - pos.x, 0, goal.z - pos.z)
	var walks: bool = not underground and p["plan"] != "bird"
	if walks:
		_unstuck -= delta
		if _unstuck <= 0.0:
			_unstuck = randf_range(0.8, 1.4)
			_get_unstuck()
			pos = global_position
	if dir.length() > 0.05 and _speed > 0.01:
		dir = dir.normalized()
		if walks:
			dir = _steer(pos, dir)
			if dir == Vector3.ZERO:
				# Hemmed in by rock or water this way: stop and go somewhere else.
				_speed = 0.0
				if state == "wander":
					_pick_wander()
		pos += dir * _speed * delta
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(delta * 5.0, 0.0, 1.0))
	var h: float = manager.call("cave_floor", pos) if underground else ground.call(pos.x, pos.z)
	if is_nan(h):
		# A cave wall (or ground not loaded yet): stay put and wander somewhere else.
		if underground and state == "wander":
			_pick_wander()
		return
	if p["plan"] == "bird":
		var alt: float = p["alt"] * (0.4 if state == "flee" else 1.0)
		pos.y = lerpf(pos.y, maxf(h, Water.LEVEL) + alt + sin(Time.get_ticks_msec() * 0.001 + float(sp % 100)) * 0.6, clampf(delta * 1.5, 0.0, 1.0))
		if state == "wander":
			_speed = maxf(_speed, 2.5)
	else:
		pos.y = maxf(h, Water.LEVEL - 0.6)
	global_position = pos
	_animate(delta)

func _animate(delta: float) -> void:
	if _kit and _kit.procedural():
		# Idle-only aliens: a scuttling bob when moving, a slow hover for fliers.
		_phase += delta * (2.0 + _speed * 5.0)
		var amt := clampf(_speed / 2.0, 0.0, 1.0)
		_kit.play("Idle", 1.0 + amt)
		if p["plan"] == "bird":
			_kit.position.y = sin(_phase * 0.6) * 0.15
			_kit.rotation.z = sin(_phase * 0.3) * 0.08
		else:
			_kit.position.y = absf(sin(_phase)) * 0.06 * amt
			_kit.rotation.z = sin(_phase) * 0.05 * amt
			_kit.rotation.x = -0.06 * amt
		if _flash > 0.0:
			_flash -= delta
			_kit.position.x = sin(_flash * 80.0) * 0.05
		return
	if _kit:
		# The gait and its pace follow the ground speed (AnimalModel).
		if _speed < 0.15:
			_kit.play(_graze_clip if state == "graze" else ("Idle_2" if state == "alert" and _kit.anim.has_animation("Idle_2") else "Idle"))
		else:
			_kit.play("Walk")
		if _flash > 0.0:
			_flash -= delta
		return
	var sz: float = p["size"]
	_phase += delta * (_speed * 4.0 / maxf(sz, 0.3) + (8.0 if p["plan"] == "bird" else 0.0))
	var amt := clampf(_speed / 2.0, 0.0, 1.2)
	for i in _legs.size():
		var leg: Node3D = _legs[i]
		leg.rotation.x = sin(_phase + (PI if i % 2 == 1 else 0.0) + (PI * 0.5 if i >= 2 else 0.0)) * 0.6 * amt
	for i in _wings.size():
		(_wings[i] as Node3D).rotation.z = (1.0 if i == 0 else -1.0) * sin(_phase) * _flap
	if state == "graze" and _model.get_child_count() > 0:
		_model.rotation.x = lerpf(_model.rotation.x, 0.25, delta * 2.0)
	else:
		_model.rotation.x = lerpf(_model.rotation.x, 0.0, delta * 4.0)
	if _flash > 0.0:
		_flash -= delta
		_model.position.x = sin(_flash * 80.0) * 0.05

## Grazing looks different from one bite to the next: head down eating, or nosing about.
func _pick_graze() -> String:
	if _kit == null:
		return "Eating"
	var opts := ["Eating", "Eating"]
	for n in ["Idle_Headlow", "Idle_2_HeadLow"]:
		if _kit.anim.has_animation(n):
			opts.append(n)
	return opts[randi() % opts.size()]

func hurt(dmg: float) -> bool:
	hp -= dmg
	_flash = 0.25
	if _kit and hp > 0.0:
		_kit.play_once("Idle_HitReact1")
	if p["temper"] != "aggressive":
		state = "flee"
	else:
		state = "chase"
	_think = 2.0
	return hp <= 0.0

## Killed: the live animal goes and its carcass (Corpses) takes its place, falling.
func die() -> void:
	if _body:
		_body.queue_free()
		_body = null
	queue_free()

## A carcass: kit animals hold the last frame of their death; the rest keel over.
func _lie_dead() -> void:
	if _kit and not _kit.procedural():
		if limp:
			_kit.freeze_for_ragdoll()
			return
		_kit.play_once("Death")
		if not fresh and _kit.anim.current_animation != "":
			_kit.anim.seek(_kit.anim.current_animation_length, true)
		return
	var who: Node3D = _kit if _kit else _model
	var down := Vector3(0, 0, PI * 0.5)
	var lift := 0.0
	if _kit == null:
		# Rolled onto its side about the feet, the body would sink half into the ground.
		lift = float(p["size"]) * (0.1 if p["plan"] == "bird" else 0.25)
	if fresh:
		var tw := create_tween().set_parallel()
		tw.tween_property(who, "rotation", down, 0.6)
		tw.tween_property(who, "position:y", lift, 0.6)
	else:
		who.rotation = down
		who.position.y = lift

# --- Model ----------------------------------------------------------------------------

## Bounds of every mesh in the model, in this node's space.
func _model_bounds() -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [_model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh:
			var xf: Transform3D = global_transform.affine_inverse() * (n as MeshInstance3D).global_transform
			var b: AABB = xf * n.mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
	return out

func _mesh(parent: Node3D, m: Mesh, c: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, emit := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat(c, emit)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

static var _mats: Dictionary = {}
static func _mat(c: Color, emit: bool) -> StandardMaterial3D:
	var k := c.to_html() + str(emit)
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.75
		if emit:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 2.5
		_mats[k] = m
	return _mats[k]

var _kit: AnimalModel

func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	if AnimalModel.available(p.get("kit", "")):
		# Medieval animals keep the kit's natural coats; others take the species' colours.
		var tint = p.get("tint", null if era == Eras.MEDIEVAL else p["col"])
		var glow = Color.from_hsv(float(p["glow"]) / 12.0, 0.7, 1.0) if p["has_glow"] else null
		_kit = AnimalModel.new().build(p["kit"], p["kit_scale"], tint, glow)
		_model.add_child(_kit)
		return
	var sz: float = p["size"]
	_model.scale = Vector3(sz, sz, sz)
	var c: Color = p["col"]
	var c2: Color = p["col2"]
	var glow := Color.from_hsv(float(p["glow"]) / 12.0, 0.7, 1.0)
	var cap := func(r: float, h: float) -> Mesh:
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 10
		m.rings = 3
		return m
	var sph := func(r: float) -> Mesh:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 10
		m.rings = 6
		return m
	match String(p["plan"]):
		"bird":
			var bm := BirdModel.build(p, era)
			_flap = {"Scout Drone": 0.06, "Drift Jelly": 0.3, "Glowmoth": 0.9}.get(String(p["name"]), 0.7)
			var bmi := MeshInstance3D.new()
			bmi.mesh = bm["body"]
			_model.add_child(bmi)
			var at: Vector3 = bm["wing_at"]
			for side in [-1.0, 1.0]:
				var w := Node3D.new()
				w.position = Vector3(side * at.x, at.y, at.z)
				_model.add_child(w)
				var wmi := MeshInstance3D.new()
				wmi.mesh = bm["wing"]
				# The left wing is the right one mirrored.
				wmi.scale = Vector3(side, 1, 1)
				w.add_child(wmi)
				_wings.append(w)
		_:
			var leg_l: float = 0.55 * float(p["leg"])
			var body_y := leg_l + 0.2
			var hexa: bool = p["plan"] == "hexa"
			_mesh(_model, cap.call(0.28, 1.1), c, Vector3(0, body_y, 0), Vector3(PI * 0.5, 0, 0), Vector3(1, 1, 0.9))
			# Neck and head.
			var nl: float = p["neck"]
			_mesh(_model, cap.call(0.1, nl + 0.2), c, Vector3(0, body_y + nl * 0.4, 0.5), Vector3(-0.6, 0, 0))
			var head := Vector3(0, body_y + nl * 0.75 + 0.05, 0.55 + nl * 0.35)
			_mesh(_model, cap.call(0.12, 0.42), c2, head, Vector3(PI * 0.5 - 0.3, 0, 0))
			for side in [-1.0, 1.0]:
				_mesh(_model, sph.call(0.03), Color(0.05, 0.05, 0.05) if not p["has_glow"] else glow, head + Vector3(side * 0.09, 0.06, 0.08), Vector3.ZERO, Vector3.ONE, p["has_glow"])
				if p["horns"]:
					_mesh(_model, cap.call(0.025, 0.4), Color(0.85, 0.8, 0.7), head + Vector3(side * 0.08, 0.2, -0.05), Vector3(-0.4, 0, side * 0.5))
				else:
					_mesh(_model, cap.call(0.03, 0.14), c, head + Vector3(side * 0.07, 0.14, -0.08), Vector3(-0.3, 0, side * 0.3))
			_mesh(_model, cap.call(0.04, 0.35), c2, Vector3(0, body_y + 0.05, -0.6), Vector3(-2.3, 0, 0))
			var zs: Array = [-0.38, 0.38] if not hexa else [-0.42, 0.0, 0.42]
			for z in zs:
				for side in [-1.0, 1.0]:
					var hip := Node3D.new()
					hip.position = Vector3(side * 0.16 * (1.6 if hexa else 1.0), body_y - 0.05, z)
					_model.add_child(hip)
					var lm: Mesh = cap.call(0.055, leg_l + 0.1)
					_mesh(hip, lm, c.darkened(0.15), Vector3(side * (0.12 if hexa else 0.0), -leg_l * 0.5, 0), Vector3(0, 0, side * (0.45 if hexa else 0.0)))
					_legs.append(hip)
			if p["has_glow"]:
				for i in 4:
					_mesh(_model, sph.call(0.05), glow, Vector3(0.0, body_y + 0.27, -0.3 + i * 0.2), Vector3.ZERO, Vector3.ONE, true)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
