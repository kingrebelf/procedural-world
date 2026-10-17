class_name Climate
extends RefCounted
## What the weather is doing at a place and time: a pure function of the world seed, the
## game clock and where you stand, so every player on a server sees the same sky without
## anything being sent, and a save reloads into the weather it left.
##
## Weather comes in fronts: big wet and dry spells a day or two long that roll across the
## land on the prevailing wind (so the rain reaches the west of a valley before the east,
## and you can walk out from under it), with showers and thunderstorms dotted through the
## wet spells, morning mist on calm damp mornings, and dust storms when a dry gale blows
## over sand. Temperature falls with height toward the planet's snow line and with the
## night, and decides whether what falls is rain or snow.
##
## Weather (weather.gd) smooths these targets over time and turns them into sky, fog,
## particles, wet ground and sound.

## How fast weather fronts travel over the land, metres per game hour (a game hour is a
## real minute, so about 40 m/s: a jetpack can outrun a front, walking cannot).
const FRONT_SPEED := 2400.0

## How wet each landform's climate is (WorldField.LF_*): dunes and badlands are deserts,
## lakes are damp.
const LF_MOIST := [1.0, 1.1, 1.0, 1.05, 0.95, 1.05, 1.0, 1.15, 0.45, 0.7, 0.6]
## How much each landform's air heats up by day (deserts bake, lakes stay mild).
const LF_WARM := [0.0, 0.0, 0.0, 0.0, -0.5, 0.0, 0.0, -1.0, 7.0, 3.0, 5.0]
## How readily mist forms (valleys, lakes and sinks hold it).
const LF_MIST := [1.0, 1.3, 0.8, 1.3, 0.7, 1.4, 1.0, 1.6, 0.15, 0.5, 0.35]
## How much dust the wind can lift.
const LF_DUST := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.35, 0.8]

var seed := 0
## The way fronts come from (unit, world x/z): each world has its own prevailing wind.
var prevailing := Vector2(1, 0)
var _spell := FastNoiseLite.new() ## wet and dry spells, a day or two each
var _showers := FastNoiseLite.new() ## showers and storm cells a kilometre or two across
var _gale := FastNoiseLite.new() ## dry windy spells
var _warmth := FastNoiseLite.new() ## warm and cold spells
var _veer := FastNoiseLite.new() ## the wind backing and veering round the prevailing way

func _init(world_seed: int) -> void:
	seed = world_seed
	var a := WHash.unit2(world_seed, 3, 9, 401) * TAU
	prevailing = Vector2(cos(a), sin(a))
	var i := 0
	for n in [_spell, _showers, _gale, _warmth, _veer]:
		n.seed = WHash.hash2(world_seed, i, 0, 402) & 0x7FFFFFFF
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 1.0
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 2
		i += 1
	_showers.fractal_octaves = 3

## The game clock in hours (Game.day is in days).
static func hours_of(day: float) -> float:
	return day * 24.0

## Temperature at sea level before height, night and spells: a frozen world (low snow
## line) is cold everywhere.
static func base_temp(snow_line: float) -> float:
	return lerpf(-4.0, 15.0, clampf(snow_line / 50.0, 0.0, 1.0))

## The weather the sky is heading for at (x, z) at game hour `hours`. ground: land height
## there; lf: its landform (WorldField.landform_at); snow_line: the planet's.
## Returns {cover, precip, snow, storm, mist, dust, wind, temp, wind_dir}: all 0..1 but
## temp (degrees C) and wind_dir (unit Vector2, the way the wind blows toward).
func at(hours: float, x: float, z: float, ground: float, lf: int, snow_line: float) -> Dictionary:
	lf = clampi(lf, 0, LF_MOIST.size() - 1)
	# Where the front over you now was an hour ago is upwind: shift the clock by the
	# distance along the prevailing wind.
	var t := hours - (x * prevailing.x + z * prevailing.y) / FRONT_SPEED
	# Wet and dry spells, with a bias toward fair weather.
	var spell := _spell.get_noise_1d(t * 0.03)
	# Showers: patches a kilometre or two across that drift with the front and grow and
	# die over a few hours; they only matter in an unsettled spell.
	var sx := x - prevailing.x * FRONT_SPEED * hours
	var sz := z - prevailing.y * FRONT_SPEED * hours
	var cell := _showers.get_noise_3d(sx * 0.0005, sz * 0.0005, hours * 0.18)
	var unsettled := smoothstep(-0.15, 0.25, spell)
	var hum := clampf(0.42 + spell * 0.85 + cell * 0.55 * unsettled, 0.0, 1.0)
	hum = clampf(hum * LF_MOIST[lf] + (LF_MOIST[lf] - 1.0) * 0.25, 0.0, 1.0)

	# Temperature: falls with height to about -2 at the snow line, colder at night
	# (coldest before dawn, warmest mid-afternoon), warm and cold spells over days.
	var tod := fposmod(hours / 24.0, 1.0)
	var bt := base_temp(snow_line)
	var temp := bt - (bt + 2.0) * clampf(maxf(ground, 0.0) / maxf(snow_line, 1.0), 0.0, 2.5)
	var sunny := 1.0 - smoothstep(0.45, 0.85, hum)
	temp += cos((tod - 0.62) * TAU) * (2.5 + 3.5 * sunny) + LF_WARM[lf] * (0.3 + 0.7 * smoothstep(0.3, 0.6, tod) * (1.0 - smoothstep(0.75, 0.9, tod)))
	temp += _warmth.get_noise_1d(t * 0.012) * 7.0

	var cover := lerpf(0.06, 1.0, smoothstep(0.22, 0.72, hum))
	var precip := smoothstep(0.6, 0.86, hum)
	temp -= precip * 2.5 # rain cools the air
	var snow := smoothstep(1.5, -1.0, temp)
	# Thunderstorms: the wettest cells of a warm spell (snow only rarely thunders).
	var storm := smoothstep(0.8, 0.95, hum) * smoothstep(5.0, 13.0, temp)
	# Wind: fronts and storms are blustery, and now and then a dry gale blows for hours.
	var gale := maxf(_gale.get_noise_1d(t * 0.04 + 50.0), 0.0) * 1.7
	var wind := clampf(0.18 + precip * 0.3 + storm * 0.4 + gale * 0.55 + absf(spell) * 0.12, 0.03, 1.0)
	# Mist: a calm damp morning settles it in the low ground; a damp spell can keep
	# fog banks all day on lakes and in valleys.
	var dawn := smoothstep(0.15, 0.24, tod) * (1.0 - smoothstep(0.3, 0.4, tod)) + (1.0 - smoothstep(0.85, 0.95, tod)) * smoothstep(0.78, 0.86, tod) * 0.4
	var calm := 1.0 - smoothstep(0.2, 0.45, wind)
	var mist := clampf((smoothstep(0.38, 0.62, hum) * dawn * calm + smoothstep(0.55, 0.75, hum) * smoothstep(1.2, 1.5, LF_MIST[lf]) * 0.35 * calm)
		* LF_MIST[lf] * (1.0 - precip * 0.6), 0.0, 1.0)
	# Dust: a strong dry wind over sand and badlands.
	var dust: float = LF_DUST[lf] * smoothstep(0.45, 0.8, wind) * (1.0 - smoothstep(0.3, 0.5, hum))
	cover = maxf(cover, dust * 0.5)
	var ang := _veer.get_noise_1d(t * 0.05 + 300.0) * 1.4
	var wd := prevailing.rotated(ang)
	return {"cover": cover, "precip": precip, "snow": snow, "storm": storm, "mist": mist, "dust": dust,
		"wind": wind, "temp": temp, "wind_dir": wd}
