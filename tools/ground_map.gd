extends RefCounted
## The work of probe_ground.gd (see there).

const PX := 4 ## pixels per metre
const N := 3 ## chunks across

static func run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var seed := int(args.get("seed", "4242"))
	var out := String(args.get("out", "user://ground"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	Planets.apply(Planets.get_planet(seed, 0, "human"))
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(seed, true)
	var spots := {}
	if args.has("at"):
		var p := String(args["at"]).split(",")
		spots["at"] = Vector2(float(p[0]), float(p[1]))
	else:
		var want := String(args.get("spots", "meadow,dunes,snow,town,craters")).split(",")
		spots = _find(g, want)
	for name in spots:
		var p: Vector2 = spots[name]
		print("%s at %.0f, %.0f" % [name, p.x, p.y])
		_map(g, p, "%s/%s.png" % [out, name])

## Spots worth looking at near the origin, by the same kind of search the capture tour
## makes: {name: world xz}.
static func _find(g: ChunkGenerator, want: PackedStringArray) -> Dictionary:
	var found := {}
	var rcache := {}
	for i in 30000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (50.0 + i * 2.0)
		if "meadow" in want and not found.has("meadow") and i % 3 == 0:
			# The capture tour's 50_meadow: the same search (its spiral steps 3 m a turn).
			var q := Vector2(cos(i / 3 * 0.37), sin(i / 3 * 0.37)) * (50.0 + i)
			var hq := g.field.height(q.x, q.y)
			var ok := g.field.era_weights(q.x, q.y)[Eras.MEDIEVAL] >= 0.9 and hq >= 3.0
			for k in 8:
				var d := Vector2.from_angle(k * TAU / 8.0)
				ok = ok and absf(g.field.height(q.x + d.x * 6.0, q.y + d.y * 6.0) - hq) < 0.9
				ok = ok and absf(g.field.height(q.x + d.x * 30.0, q.y + d.y * 30.0) - hq) < 4.0
			if ok:
				found["meadow"] = q
		if "rapids" in want and not found.has("rapids") and g.field.river_t(p.x, p.y) < 0.3:
			# A steep reach of river: its level drops fast along it.
			var lv := g.field.river_level(p.x, p.y, rcache)
			if WorldField.river_strength(g.field.height(p.x, p.y), lv) > 0.8 and lv > ChunkGenerator.WATER_LEVEL + 1.0:
				for k in 8:
					var q := p + Vector2.from_angle(k * TAU / 8.0) * 8.0
					if g.field.river_t(q.x, q.y) < 0.4 and absf(g.field.river_level(q.x, q.y, rcache) - lv) > 0.7:
						found["rapids"] = p
						break
		var h := g.field.height(p.x, p.y)
		if h < 3.0:
			continue
		if "terraces" in want and not found.has("terraces") and g.field.landform_weights(p.x, p.y)[WorldField.LF_TERRACES] > 0.95:
			found["terraces"] = p
		if "craters" in want and not found.has("craters") and g.field.landform_weights(p.x, p.y)[WorldField.LF_CRATERS] > 0.95:
			found["craters"] = p
		if "dunes" in want and not found.has("dunes") and g.field.landform_weights(p.x, p.y)[WorldField.LF_DUNES] > 0.95:
			found["dunes"] = p
		if "snow" in want and not found.has("snow") and h > Planets.snow_line - 4.0 and h < Planets.snow_line + 6.0:
			found["snow"] = p
		if "town" in want and not found.has("town"):
			var s := g.settlement_at(int(floor(p.x / ChunkGenerator.SETTLEMENT_CELL)), int(floor(p.y / ChunkGenerator.SETTLEMENT_CELL)))
			if not s.is_empty() and s.has("center"):
				found["town"] = s["center"]
		if found.size() >= want.size():
			break
	return found

static func _map(g: ChunkGenerator, at: Vector2, path: String) -> void:
	var c0 := Vector2i(int(floor(at.x / 64.0)) - 1, int(floor(at.y / 64.0)) - 1)
	var img := Image.create(64 * N * PX, 64 * N * PX, false, Image.FORMAT_RGB8)
	var counts := {}
	for cj in N:
		for ci in N:
			var chunk := g.generate(c0.x + ci, c0.y + cj)
			var cover := GroundCover.build(chunk)
			var ox := ci * 64 * PX
			var oz := cj * 64 * PX
			# Ground: soil tinted by cover (snow white, scree grey, gravel tan, litter brown,
			# bare sand orange), shaded by height.
			for z in 64 * PX:
				for x in 64 * PX:
					var lx := float(x) / PX
					var lz := float(z) / PX
					var cv := GroundCover.at(cover, lx, lz)
					var h := ChunkGenerator.height_at(chunk, lx, lz)
					var col := Color(0.42, 0.36, 0.24)
					col = col.lerp(Color(0.85, 0.6, 0.35), 1.0 - ChunkGenerator.cover_at(chunk, lx, lz))
					col = col.lerp(Color(0.5, 0.25, 0.1), cv.b * 0.6)
					col = col.lerp(Color(0.6, 0.55, 0.45), cv.g)
					col = col.lerp(Color(0.45, 0.45, 0.47), cv.r)
					col = col.lerp(Color(0.95, 0.97, 1.0), cv.a)
					if h < 0.0:
						col = Color(0.15, 0.3, 0.5)
					var shade := 0.85 + 0.15 * sin(h * 1.5)
					img.set_pixel(ox + x, oz + z, col * shade)
			var grass := ChunkNode.build_grass_buffers(chunk, 1.0, cover)
			if chunk.has("biome"):
				var bp := Biome.params(chunk["biome"], Eras.nature(chunk.get("era", 0)))
				var gn := 0
				for key in grass:
					gn += (grass[key] as PackedFloat32Array).size() / 16
				counts["~chunk %d,%d grass_density %.2f lush %+.2f grass/m2" % [ci, cj, bp["grass_density"], bp["lush"]]] = snappedf(gn / 4096.0, 0.01)
			for key in grass:
				var sp := String(key).get_slice("@", 0)
				var buf: PackedFloat32Array = grass[key]
				counts["grass:" + sp] = counts.get("grass:" + sp, 0) + buf.size() / 16
				var gc := Color(0.3, 0.75, 0.2) if not sp.begins_with("flowers") else Color(0.95, 0.5, 0.8)
				if sp == "weed":
					gc = Color(0.2, 0.5, 0.45)
				for i in range(0, buf.size(), 16):
					_dot(img, ox + buf[i + 3] * PX, oz + buf[i + 11] * PX, 0.6, gc)
			var clutter := ChunkNode.build_clutter_buffers(chunk, 1.0, cover)
			for key in clutter:
				var k := String(key)
				if k.begins_with("~"):
					continue
				var buf: PackedFloat32Array = clutter[key]
				var stride := 16 if k.begins_with("stone:") else 12
				var name := k.get_slice("@", 0)
				var col := Color(0.6, 0.6, 0.6)
				if k.begins_with("under#"):
					var form := Flora.under_form(int(k.get_slice("#", 1)), int(k.get_slice("#", 2)))
					name = "under:" + form
					col = {"fern": Color(0.0, 0.35, 0.05), "bush": Color(0.5, 0.55, 0.1), "flowers": Color(1, 0.3, 0.6), "reeds": Color(0.2, 0.9, 0.9)}.get(form, Color(1, 0, 1))
				counts[name] = counts.get(name, 0) + buf.size() / stride
				for i in range(0, buf.size(), stride):
					var sx := Vector3(buf[i], buf[i + 4], buf[i + 8]).length()
					var rad := maxf(sx * PX * (0.5 if k.begins_with("stone:") else 0.6), 1.0)
					if k.begins_with("stone:"):
						col = Color(0.25, 0.25, 0.27)
					_dot(img, ox + buf[i + 3] * PX, oz + buf[i + 11] * PX, rad, col)
			for o in chunk["objects"]:
				var kind := ObjectLibrary.kind(o["t"])
				var p: Vector3 = o["p"]
				var col := Color(1, 1, 0)
				var rad := 3.0
				match kind:
					"tree":
						col = Color(0.05, 0.25, 0.05) if o["t"] == "pine" else Color(0.15, 0.45, 0.1)
						rad = 2.5 * float(o["s"]) * PX * 0.5
					"rock":
						col = Color(0.1, 0.1, 0.12)
						rad = float(o["s"]) * PX
					"marker":
						col = Color(1, 0, 0)
						rad = 5.0
				counts["obj:" + String(o["t"])] = counts.get("obj:" + String(o["t"]), 0) + 1
				_dot(img, ox + p.x * PX, oz + p.z * PX, rad, col)
	img.save_png(path)
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("  %-24s %s" % [k, str(counts[k])])

static func _dot(img: Image, x: float, z: float, r: float, col: Color) -> void:
	var ri := int(ceil(r))
	for dz in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dz * dz > r * r + 0.5:
				continue
			var px := int(x) + dx
			var pz := int(z) + dz
			if px >= 0 and pz >= 0 and px < img.get_width() and pz < img.get_height():
				img.set_pixel(px, pz, col)
