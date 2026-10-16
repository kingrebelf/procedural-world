class_name Materials
## Shared physically based materials, all textured procedurally (seamless noise for
## albedo variation and normal detail) and mapped triplanar so meshes need no UV work.

static var _cache: Dictionary = {}
static var _tex: Dictionary = {}

static func _noise_tex(key: String, freq: float, normal: bool, octaves: int = 5, cellular: bool = false, stretch := Vector2.ONE) -> NoiseTexture2D:
	var k := "%s_%s" % [key, normal]
	if _tex.has(k):
		return _tex[k]
	var n := FastNoiseLite.new()
	n.seed = WHash.str_hash(key) & 0xFFFF
	n.frequency = freq
	n.fractal_octaves = octaves
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	else:
		var g := Gradient.new()
		g.set_color(0, Color(0.72, 0.72, 0.72))
		g.set_color(1, Color(1.0, 1.0, 1.0))
		t.color_ramp = g
	if stretch != Vector2.ONE:
		t.width = int(512 * stretch.x)
		t.height = int(512 * stretch.y)
	_tex[k] = t
	return t

static func _pbr(albedo: Color, rough: float, metal: float, tex: String, freq: float, tri_scale: float, normal_scale: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	if tex != "":
		m.albedo_texture = _noise_tex(tex, freq, false)
		m.normal_enabled = true
		m.normal_texture = _noise_tex(tex, freq, true)
		m.normal_scale = normal_scale
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3.ONE * tri_scale
		m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.3)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	return m

## Procedurally painted foliage atlas: clusters of leaves (or needles) with alpha.
static func _foliage_tex(kind: String) -> ImageTexture:
	var k := "foliage_" + kind
	if _tex.has(k):
		return _tex[k]
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(kind)
	if kind == "needle":
		for n in 220:
			var a := r.randf_range(-0.5, 0.5) + (PI * 0.5 if n % 2 else -PI * 0.5) * 0.0
			var cx := r.randf_range(20, S - 20)
			var cy := r.randf_range(20, S - 20)
			var len := r.randf_range(18, 40)
			var shade := r.randf_range(0.7, 1.15)
			for t in int(len):
				var x := int(cx + cos(a + PI * 0.5) * (t - len * 0.5))
				var y := int(cy + sin(a + PI * 0.5) * (t - len * 0.5))
				for o in 2:
					if x + o >= 0 and x + o < S and y >= 0 and y < S:
						img.set_pixel(x + o, y, Color(0.75 * shade, 0.9 * shade, 0.7 * shade, 1))
	else:
		for n in 70:
			var cx := r.randf_range(24, S - 24)
			var cy := r.randf_range(24, S - 24)
			# Keep the cluster roughly round so card edges never show.
			if Vector2(cx, cy).distance_to(Vector2(S, S) * 0.5) > S * 0.46:
				continue
			var a := r.randf() * TAU
			var lw := r.randf_range(9, 15)
			var lh := lw * r.randf_range(0.45, 0.6)
			var shade := r.randf_range(0.65, 1.15)
			var tint := Color(0.85 * shade, 1.0 * shade, 0.75 * shade, 1)
			var ca := cos(a)
			var sa := sin(a)
			for y in range(int(cy - lw), int(cy + lw)):
				for x in range(int(cx - lw), int(cx + lw)):
					if x < 0 or y < 0 or x >= S or y >= S:
						continue
					var dx := x - cx
					var dy := y - cy
					var u := dx * ca + dy * sa
					var v := -dx * sa + dy * ca
					var e := (u * u) / (lw * lw) + (v * v) / (lh * lh)
					if e <= 1.0:
						var vein := 1.0 - 0.25 * (1.0 - smoothstep(0.0, 1.2, absf(v)))
						img.set_pixel(x, y, tint * Color(vein, vein, vein, 1) * Color(1, 1, 1, 1).lerp(Color(0.8, 0.8, 0.8, 1), e))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[k] = t
	return t

static func _foliage(kind: String, albedo: Color, back: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _foliage_tex(kind)
	m.albedo_color = albedo
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	m.backlight_enabled = true
	m.backlight = back
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func get_mat(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m: BaseMaterial3D
	match name:
		"bark": m = _pbr(Color(0.42, 0.32, 0.24), 0.95, 0.0, "bark", 0.03, 1.2, 1.6)
		"bark_pine": m = _pbr(Color(0.34, 0.24, 0.18), 0.95, 0.0, "bark", 0.03, 1.2, 1.6)
		"leaf":
			m = _pbr(Color(0.30, 0.48, 0.17), 0.85, 0.0, "leaf", 0.08, 0.6, 1.0)
			m.backlight_enabled = true
			m.backlight = Color(0.25, 0.35, 0.05)
		"needle":
			m = _pbr(Color(0.16, 0.30, 0.16), 0.9, 0.0, "leaf", 0.1, 0.8, 1.2)
			m.backlight_enabled = true
			m.backlight = Color(0.1, 0.2, 0.05)
		"stone": m = _pbr(Color(0.56, 0.54, 0.50), 0.88, 0.0, "stone", 0.02, 0.35, 1.4)
		"stone_dark": m = _pbr(Color(0.30, 0.29, 0.30), 0.85, 0.0, "stone", 0.02, 0.35, 1.4)
		"cobble": m = _pbr(Color(0.5, 0.48, 0.45), 0.9, 0.0, "cobble", 0.05, 0.5, 2.0)
		"plaster": m = _pbr(Color(0.86, 0.82, 0.72), 0.9, 0.0, "plaster", 0.04, 0.3, 0.5)
		"timber": m = _pbr(Color(0.36, 0.25, 0.16), 0.8, 0.0, "bark", 0.05, 0.6, 0.8)
		"planks": m = _pbr(Color(0.55, 0.40, 0.26), 0.8, 0.0, "planks", 0.03, 0.5, 0.8)
		"thatch": m = _pbr(Color(0.62, 0.52, 0.30), 0.95, 0.0, "thatch", 0.09, 0.8, 1.8)
		"slate": m = _pbr(Color(0.25, 0.27, 0.32), 0.7, 0.0, "stone", 0.05, 0.6, 1.2)
		"iron": m = _pbr(Color(0.45, 0.45, 0.47), 0.45, 0.9, "metal", 0.04, 1.0, 0.4)
		"rust": m = _pbr(Color(0.55, 0.30, 0.18), 0.8, 0.4, "rust", 0.06, 1.2, 1.0)
		"gold": m = _pbr(Color(1.0, 0.77, 0.34), 0.3, 1.0, "metal", 0.04, 1.0, 0.3)
		"metal": m = _pbr(Color(0.62, 0.64, 0.68), 0.32, 0.95, "metal", 0.03, 0.8, 0.3)
		"metal_dark": m = _pbr(Color(0.18, 0.19, 0.21), 0.4, 0.85, "metal", 0.03, 0.8, 0.3)
		"painted": m = _pbr(Color(1, 1, 1), 0.55, 0.5, "metal", 0.03, 0.8, 0.5)
		"panel": m = _pbr(Color(0.86, 0.88, 0.9), 0.25, 0.3, "plaster", 0.02, 0.4, 0.2)
		"glass":
			m = _pbr(Color(0.15, 0.25, 0.3), 0.05, 0.8, "", 0, 1)
		"cloth": m = _pbr(Color(0.62, 0.20, 0.16), 0.95, 0.0, "cloth", 0.15, 1.0, 0.6)
		"cloth_blue": m = _pbr(Color(0.2, 0.3, 0.6), 0.95, 0.0, "cloth", 0.15, 1.0, 0.6)
		"skin": m = _pbr(Color(0.78, 0.6, 0.48), 0.6, 0.0, "", 0, 1)
		"moss": m = _pbr(Color(0.16, 0.42, 0.38), 0.95, 0.0, "leaf", 0.1, 0.6, 1.2)
		"stem": m = _pbr(Color(0.86, 0.84, 0.76), 0.8, 0.0, "plaster", 0.06, 0.6, 1.0)
		"cap_violet":
			m = _pbr(Color(0.42, 0.18, 0.62), 0.6, 0.0, "cap", 0.05, 0.6, 0.8)
			m.emission_enabled = true
			m.emission = Color(0.4, 0.2, 0.9)
			m.emission_energy_multiplier = 0.25
		"cap_teal":
			m = _pbr(Color(0.10, 0.50, 0.55), 0.6, 0.0, "cap", 0.05, 0.6, 0.8)
			m.emission_enabled = true
			m.emission = Color(0.1, 0.8, 0.8)
			m.emission_energy_multiplier = 0.25
		"crystal":
			m = _pbr(Color(0.45, 0.75, 1.0), 0.08, 0.2, "", 0, 1)
			m.emission_enabled = true
			m.emission = Color(0.35, 0.7, 1.0)
			m.emission_energy_multiplier = 1.4
			m.rim_enabled = true
			m.rim = 0.6
		"crystal_violet":
			m = _pbr(Color(0.7, 0.45, 1.0), 0.08, 0.2, "", 0, 1)
			m.emission_enabled = true
			m.emission = Color(0.65, 0.35, 1.0)
			m.emission_energy_multiplier = 1.4
			m.rim_enabled = true
		"leaf_card": m = _foliage("leaf", Color(0.42, 0.6, 0.22), Color(0.3, 0.42, 0.08))
		"needle_card": m = _foliage("needle", Color(0.22, 0.38, 0.2), Color(0.12, 0.2, 0.05))
		"moss_card": m = _foliage("leaf", Color(0.2, 0.6, 0.55), Color(0.1, 0.5, 0.45))
		"rune_stone": m = _pbr(Color(0.24, 0.26, 0.30), 0.8, 0.0, "stone", 0.02, 0.35, 1.6)
		"glow_cyan": m = _glow(Color(0.2, 0.85, 1.0), 4.0)
		"glow_teal": m = _glow(Color(0.2, 1.0, 0.8), 3.0)
		"glow_violet": m = _glow(Color(0.7, 0.4, 1.0), 3.0)
		"glow_red": m = _glow(Color(1.0, 0.15, 0.1), 5.0)
		"glow_warm": m = _glow(Color(1.0, 0.65, 0.3), 2.5)
		"glow_white": m = _glow(Color(0.95, 0.97, 1.0), 3.0)
		_:
			m = _pbr(Color(1, 0, 1), 0.5, 0.0, "", 0, 1)
	_cache[name] = m
	return m
