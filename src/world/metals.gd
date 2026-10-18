class_name Metals
## The shared metal look (metal.gdshader). Bare metal reflects most of the light that
## hits it, tinted by the metal; what makes it read as metal is that reflection, so the
## colours here are real reflectances, and what varies is how rough the surface is and
## what sits on it (wear, grime, rust, paint).
##
## Era: medieval metal is forged and handled, never polished to a mirror (iron, wrought,
## steel with worn edges and grime); chrome and polish belong to the sci-fi era.

## kind -> {colour (sRGB reflectance), rough, var, scratch, hammer, brushed, wear, grime,
## rust, rust_col, paint, lift}. Missing keys take DEFAULT's values.
const KINDS := {
	# Worked steel: blades, tools, armour plate. Forged and handled, a satin sheen
	# that blurs the sky (Ben: mirror polish is for the sci-fi era only).
	"steel": {"col": Color(0.74, 0.74, 0.75), "rough": 0.44, "var": 0.24, "scratch": 0.5, "wear": 0.5, "grime": 0.2},
	# Forged iron: hammered, darker, grime in the hollows, a little rust.
	"iron": {"col": Color(0.66, 0.65, 0.63), "rough": 0.56, "var": 0.3, "hammer": 0.5, "wear": 0.65, "grime": 0.35, "rust": 0.05},
	# Blackened wrought iron (hinges, straps, candle stands): dark oxide, bright where handled.
	"wrought": {"col": Color(0.5, 0.49, 0.48), "rough": 0.6, "var": 0.3, "hammer": 0.6, "wear": 0.8, "grime": 0.35, "rust": 0.08},
	# Old iron gone to rust in blotches.
	"rusty": {"col": Color(0.6, 0.58, 0.56), "rough": 0.55, "var": 0.3, "hammer": 0.3, "wear": 0.4, "grime": 0.3, "rust": 0.62},
	"brass": {"col": Color(0.96, 0.85, 0.58), "rough": 0.28, "var": 0.25, "wear": 0.5, "grime": 0.3, "rust": 0.05, "rust_col": Color(0.3, 0.42, 0.33)},
	"bronze": {"col": Color(0.85, 0.65, 0.45), "rough": 0.36, "var": 0.28, "hammer": 0.2, "wear": 0.55, "grime": 0.35, "rust": 0.1, "rust_col": Color(0.3, 0.45, 0.36)},
	# Cast gun bronze left out in the weather: browned, dull, verdigris in the mouldings.
	"gun_bronze": {"col": Color(0.66, 0.5, 0.34), "rough": 0.5, "var": 0.35, "hammer": 0.05, "wear": 0.6, "grime": 0.55, "rust": 0.28, "rust_col": Color(0.3, 0.45, 0.36)},
	"copper": {"col": Color(0.97, 0.74, 0.62), "rough": 0.3, "var": 0.25, "hammer": 0.25, "wear": 0.5, "grime": 0.3, "rust": 0.08, "rust_col": Color(0.33, 0.55, 0.45)},
	"gold": {"col": Color(1.0, 0.85, 0.55), "rough": 0.2, "var": 0.15, "scratch": 0.2, "wear": 0.3, "grime": 0.15},
	"silver": {"col": Color(0.98, 0.97, 0.95), "rough": 0.22, "var": 0.2, "scratch": 0.35, "wear": 0.4, "grime": 0.35, "rust_col": Color(0.2, 0.18, 0.16)},
	# Sci-fi: mirror polish, and brushed alloy.
	"chrome": {"col": Color(0.92, 0.93, 0.94), "rough": 0.05, "var": 0.04, "scratch": 0.1, "wear": 0.0, "grime": 0.05},
	"alloy": {"col": Color(0.85, 0.86, 0.87), "rough": 0.3, "var": 0.15, "scratch": 0.4, "brushed": 1.0, "wear": 0.2, "grime": 0.12},
	# Zinc-coated sheet: the coat's crystals make the roughness blotchy.
	"galvanised": {"col": Color(0.8, 0.81, 0.82), "rough": 0.42, "var": 0.45, "scratch": 0.2, "wear": 0.2, "grime": 0.3},
	# Dark steel and gunmetal (sci-fi frames, machinery, dark fittings).
	"dark_steel": {"col": Color(0.5, 0.51, 0.53), "rough": 0.46, "var": 0.22, "scratch": 0.4, "wear": 0.55, "grime": 0.25},
	# Paint (the vertex colour) over steel, chipped at the edges.
	"painted": {"col": Color(0.75, 0.75, 0.76), "rough": 0.4, "var": 0.2, "wear": 0.6, "grime": 0.3, "paint": 1.0, "paint_rough": 0.45},
	# Any metal coloured by its vertices (items: ingots, coins, fittings, ores' grains).
	"worked": {"col": Color(1, 1, 1), "rough": 0.42, "var": 0.22, "scratch": 0.4, "wear": 0.5, "grime": 0.2, "lift": 1.0},
	"worked_rolled": {"col": Color(1, 1, 1), "rough": 0.38, "var": 0.15, "scratch": 0.4, "brushed": 1.0, "wear": 0.35, "grime": 0.15, "lift": 1.0},
}
const DEFAULT := {"col": Color(1, 1, 1), "rough": 0.4, "var": 0.25, "scratch": 0.3, "hammer": 0.0, "brushed": 0.0,
	"wear": 0.4, "grime": 0.3, "rust": 0.0, "rust_col": Color(0.5, 0.27, 0.13), "paint": 0.0, "paint_rough": 0.5, "lift": 0.0}

## Scale of the mesh: hand-held items (texture repeats per metre, worn-edge radius) or
## world objects (furniture, boats, buildings).
const ITEM := [6.0, 0.012]
const WORLD := [0.9, 0.08]

static var _cache := {}
static var _tex := {}
static var _lock := Mutex.new()

## The material for `kind` (see KINDS), `rough` < 0 keeping the kind's own roughness.
## `world` picks the world-object scale over the hand-held one. Thread-safe.
static func mat(kind: String, rough := -1.0, world := false, detail := "") -> ShaderMaterial:
	var key := "%s@%.2f@%s@%s" % [kind, rough, world, detail]
	_lock.lock()
	var m: ShaderMaterial = _cache.get(key)
	if m == null:
		m = _make(kind, rough, world, detail)
		_cache[key] = m
	_lock.unlock()
	return m

static func _make(kind: String, rough: float, world: bool, detail: String) -> ShaderMaterial:
	var s: Dictionary = DEFAULT.duplicate()
	s.merge(KINDS.get(kind, KINDS["steel"]), true)
	var m := ShaderMaterial.new()
	m.shader = load("res://src/world/metal.gdshader")
	m.resource_name = "metal_" + kind
	m.set_shader_parameter("base_color", s["col"])
	m.set_shader_parameter("lift", s["lift"])
	m.set_shader_parameter("roughness", rough if rough >= 0.0 else float(s["rough"]))
	m.set_shader_parameter("rough_var", s["var"])
	m.set_shader_parameter("scratches", s["scratch"])
	m.set_shader_parameter("hammer", s["hammer"])
	m.set_shader_parameter("brushed", s["brushed"])
	m.set_shader_parameter("wear", s["wear"])
	m.set_shader_parameter("grime", s["grime"])
	m.set_shader_parameter("rust", s["rust"])
	m.set_shader_parameter("rust_color", s["rust_col"])
	m.set_shader_parameter("paint", s["paint"])
	m.set_shader_parameter("paint_rough", s["paint_rough"])
	var sc: Array = WORLD if world else ITEM
	m.set_shader_parameter("tri_scale", sc[0])
	m.set_shader_parameter("edge_size", sc[1])
	m.set_shader_parameter("noise_tex", _noise("smudge", 0.02, 5, false))
	m.set_shader_parameter("scratch_tex", _noise("scratch", 0.09, 3, false, Vector2(1.0, 0.06)))
	m.set_shader_parameter("dimple_tex", _noise("dimple", 0.03, 1, true))
	if detail != "" and Materials.photo(detail, "detail") != null:
		m.set_shader_parameter("use_detail", true)
		m.set_shader_parameter("detail_tex", Materials.photo(detail, "detail"))
		m.set_shader_parameter("detail_scale", Materials.PHOTO_SCALE.get(detail, 0.5))
		if Materials.photo(detail, "normal") != null:
			m.set_shader_parameter("detail_normal", Materials.photo(detail, "normal"))
	return m

## Seamless noise: "smudge" soft blotches, "scratch" thin streaks (stretched), "dimple"
## the round hollows a hammer leaves (cellular, as a normal map).
static func _noise(key: String, freq: float, octaves: int, dimples: bool, stretch := Vector2.ONE) -> NoiseTexture2D:
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.seed = WHash.str_hash("metal_" + key) & 0xFFFF
	n.frequency = freq
	n.fractal_octaves = octaves
	if dimples:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if stretch != Vector2.ONE:
		# Ridged noise squeezed one way: thin lines, like scratches and polishing marks.
		n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		t.width = int(512 * stretch.x)
		t.height = maxi(int(512 * stretch.y), 32)
	if dimples:
		t.as_normal_map = true
		t.bump_strength = 4.0
	else:
		t.normalize = true
	_tex[key] = t
	return t
