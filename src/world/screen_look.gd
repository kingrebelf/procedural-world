class_name ScreenLook
## The look of every lit display: which kind of picture a face shows, in which colours,
## and the faces themselves. The in-world picture is drawn by screen_ui.gdshader (logs
## typing themselves out under the world's clock, live code, gauges, contour maps, a
## boat's heading tape and sonar), and the same palette dresses the terminal window you
## open by using one (TerminalUI), so what you read up close is the screen you walked
## up to: same colours, same kind of layout, the site's name in its header.
##
## Colours go by the room (a lab's teal, an ops tower's blue, a bunker's amber), by
## vessel, and by world: alien worlds shift to violet and run brighter. Human worlds keep
## screens to a real display's brightness, under the bloom threshold.

## What a face shows (the shader's kinds).
const KIND := {"terminal": 0, "monitor": 1, "bulletin": 2, "map": 3, "nav": 4, "notice": 5, "touch": 6}

## Each room's accent (sRGB).
const ROOM := {
	"lab_block": Color(0.38, 0.95, 0.84), "ops_tower": Color(0.48, 0.74, 1.0), "hab_block": Color(0.58, 1.0, 0.58),
	"hab_dome": Color(0.62, 0.9, 1.0), "bunker_keep": Color(1.0, 0.64, 0.3), "bunker_tower": Color(1.0, 0.64, 0.3),
	"bunker": Color(1.0, 0.6, 0.32), "boat": Color(1.0, 0.74, 0.34),
}
const DEFAULT := Color(0.45, 0.95, 0.75)

## Glyphs the shader's font has, in its order (index = 6-bit code).
const CHARS := " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.:-/><_=+#%[]()*!?,|{}'$@"

## Emission strength by world: a lit display on human worlds, brighter on alien ones.
const ENERGY := {"human": 0.85, "alien": 1.6}

## The accent of `room` for a face of `kind`, in sRGB: bulletins run whiter, maps a touch
## cooler, and alien worlds turn every accent towards violet.
static func accent(room: String, kind: String = "terminal") -> Color:
	var c: Color = ROOM.get(room, DEFAULT)
	match kind:
		"bulletin": c = c.lerp(Color.WHITE, 0.22)
		"map": c = c.lerp(Color(0.5, 0.9, 1.0), 0.3)
		"notice": c = c.lerp(Color(1.0, 0.7, 0.4), 0.4)
	if Eras.theme == "alien":
		c = Color.from_hsv(fposmod(c.h + 0.32, 1.0) if c.h < 0.6 else c.h, minf(1.0, c.s * 1.2), c.v)
	return c

## The shader's material (one for every screen; per-room text comes in instance uniforms).
static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/world/shaders/screen_ui.gdshader")
	m.resource_name = "screen_ui"
	m.set_shader_parameter("energy", ENERGY["human"])
	return m

## A face w x h in the xy plane of `xf`, facing +z: a screen of `kind` in `room`'s colours.
## `k`'s "screen_ui" bucket takes it; the face's seed comes from where it stands.
static func face(k: MeshKit, xf: Transform3D, w: float, h: float, kind: String, room: String) -> void:
	k.panel("screen_ui", xf, w, h, Vector2(float(KIND[kind]) + _seed(xf.origin), w / h), _vcol(accent(room, kind), h))

## A round face of radius r in the xz plane of `xf`, facing up (a map table's top).
static func disc(k: MeshKit, xf: Transform3D, r: float, kind: String, room: String) -> void:
	k.disc("screen_ui", xf, r, 32, Vector2(float(KIND[kind]) + _seed(xf.origin), 1.0), _vcol(accent(room, kind), r * 2.0))

## The Quaternius computer's display (Prop_Computer, standing at `xf`): a face over its
## tilted screen, which faces up and forward at 45 degrees.
static func computer(k: MeshKit, xf: Transform3D, room: String) -> void:
	var b := Basis(Vector3.RIGHT, -PI / 4)
	var at := Vector3(0.0, 1.4305, 0.0725) + b * Vector3(0, 0, 0.012)
	face(k, xf * Transform3D(b, at), 0.6, 0.39, "monitor", room)

static func _seed(p: Vector3) -> float:
	return float(absi(hash(p.snapped(Vector3.ONE * 0.01))) % 9973) / 9973.0 * 0.99

## Vertex colour: the accent in linear light, the face's height / 4 m in alpha.
static func _vcol(c: Color, h: float) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(h / 4.0, 0.0, 1.0))

## `text` as the shader's title uniforms: [title_a, title_b], 16 characters each, four of
## 6 bits to a float. Characters the font lacks become spaces.
static func pack(text: String) -> Array:
	var up := text.to_upper()
	var v: Array = [Vector4.ZERO, Vector4.ZERO]
	for i in mini(up.length(), 32):
		var g := maxi(0, CHARS.find(up[i]))
		var vec: Vector4 = v[i / 16]
		var j := (i % 16) / 4
		vec[j] = vec[j] + float(g << (6 * (i % 4)))
		v[i / 16] = vec
	return v

## Sets a mesh instance's screens to read `text` in their headers.
static func set_title(gi: GeometryInstance3D, text: String) -> void:
	var v := pack(text)
	gi.set_instance_shader_parameter("title_a", v[0])
	gi.set_instance_shader_parameter("title_b", v[1])

## The colours of the terminal window for `room`'s `kind` of screen, as UI colours:
## {bg, dim, text, key, warn}.
static func ui_palette(room: String, kind: String) -> Dictionary:
	var a := accent(room, kind)
	var amber := a.r > a.g * 1.2
	return {"bg": Color(a.r * 0.05 + 0.01, a.g * 0.05 + 0.015, a.b * 0.05 + 0.02, 0.97), "dim": Color(a, 0.42),
		"text": a, "key": a.lerp(Color.WHITE, 0.55), "warn": Color(1.0, 0.3, 0.22) if amber else Color(1.0, 0.62, 0.22)}
