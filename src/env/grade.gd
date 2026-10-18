class_name Grade
## A gentle film grade over the whole picture: a 3D colour table that the environment
## applies after tonemapping, in sRGB (Environment.adjustment_color_correction). Shadows
## lean a little cool and highlights a little warm, and the loudest yellow-greens are eased
## toward grey, as a graded film does to foliage. Brightness and the other hues are left
## alone. Settings "film_grade" turns it off.

const SIZE := 33

static var _lut: ImageTexture3D

static func lut() -> ImageTexture3D:
	if _lut != null:
		return _lut
	var images: Array[Image] = []
	for b in SIZE:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		for g in SIZE:
			for r in SIZE:
				img.set_pixel(r, g, grade(Color(r / (SIZE - 1.0), g / (SIZE - 1.0), b / (SIZE - 1.0))))
		images.append(img)
	_lut = ImageTexture3D.new()
	_lut.create(Image.FORMAT_RGB8, SIZE, SIZE, SIZE, false, images)
	return _lut

## One sRGB colour through the grade.
static func grade(c: Color) -> Color:
	var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	var out := c
	# Yellow-greens (hue about 105 degrees, falling off over 45 either side), the more the
	# more saturated they are.
	var green := clampf(1.0 - absf(c.h - 0.29) / 0.125, 0.0, 1.0)
	if green > 0.0:
		out = out.lerp(Color(l, l, l), 0.2 * green * smoothstep(0.25, 0.75, c.s))
	# Split tone.
	var shade := 1.0 - smoothstep(0.0, 0.45, l)
	var high := smoothstep(0.55, 1.0, l)
	out.r += -0.012 * shade + 0.014 * high
	out.g += 0.004 * high
	out.b += 0.02 * shade - 0.016 * high
	return Color(clampf(out.r, 0.0, 1.0), clampf(out.g, 0.0, 1.0), clampf(out.b, 0.0, 1.0))
