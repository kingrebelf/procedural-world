class_name ServerConfig
extends RefCounted
## A dedicated server's settings: server.cfg next to the executable (or --config=path),
## then command-line flags on top. Options are the gameplay rules players see (Net.option).

const FILE := "server.cfg"
## Bumped whenever the network messages change; client and server must match.
const PROTOCOL := 3

## [options] keys, their defaults, and what the admin console accepts.
const OPTIONS := {
	"time": "normal", ## normal, day (always day) or night (always night)
	"day_minutes": 24.0, ## real minutes per game day
	"pvp": true,
	"xp_mult": 1.0,
	"loot_mult": 1.0,
	"death_penalty": "bag", ## bag (drop your pack where you fell) or keep
	"building": true,
	"alliances": true,
	"max_alliance": 8,
}
const CHOICES := {"time": ["normal", "day", "night"], "death_penalty": ["bag", "keep"]}

var name := "Procedural World Server"
var description := "A persistent procedural world."
var port := 24600
var max_players := 16
var password := ""
var admin_password := ""
var world := "world" ## folder under data_dir/worlds
var seed_text := "" ## for a new world; empty = random
var globe := Globe.DEFAULT ## a new world's planet size (Globe.SIZES)
var data_dir := "" ## where worlds live; empty = next to the executable
var lan_discovery := true
var options: Dictionary = OPTIONS.duplicate()
var path := ""
## [ai]: the language model the server's villagers think and talk with, for players
## whose own game has none set up (same keys as the game's AI settings).
const _AI := preload("res://src/ai/ai_service.gd")
const AI_KEYS := {"provider": "off", "base_url": "", "model": "", "api_key": "", "format": "", "max_rpm": 30}
var ai: Dictionary = AI_KEYS.duplicate()

func ai_on() -> bool:
	return String(ai["provider"]) != "off" and String(ai["base_url"]) != ""

## Reads server.cfg (making a commented one if there is none) and then the flags.
static func load_from(args: PackedStringArray, base_dir: String) -> ServerConfig:
	var c := ServerConfig.new()
	var cfg_path := base_dir.path_join(FILE)
	for a in args:
		if a.begins_with("--config="):
			cfg_path = a.substr(9)
	c.path = cfg_path
	if FileAccess.file_exists(cfg_path):
		c.read_file(cfg_path)
	else:
		DirAccess.make_dir_recursive_absolute(cfg_path.get_base_dir())
		c.write_file(cfg_path)
	c.apply_args(args)
	if c.data_dir == "":
		c.data_dir = base_dir
	return c

func read_file(p: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(p) != OK:
		push_warning("ServerConfig: cannot read %s" % p)
		return
	name = str(cf.get_value("server", "name", name))
	description = str(cf.get_value("server", "description", description))
	port = int(cf.get_value("server", "port", port))
	max_players = int(cf.get_value("server", "max_players", max_players))
	password = str(cf.get_value("server", "password", password))
	admin_password = str(cf.get_value("server", "admin_password", admin_password))
	world = str(cf.get_value("server", "world", world))
	seed_text = str(cf.get_value("server", "seed", seed_text))
	globe = _globe(str(cf.get_value("server", "globe", globe)))
	data_dir = str(cf.get_value("server", "data_dir", data_dir))
	lan_discovery = bool(cf.get_value("server", "lan_discovery", lan_discovery))
	for k in OPTIONS:
		if cf.has_section_key("options", k):
			set_option(k, str(cf.get_value("options", k)))
	for k in AI_KEYS:
		if cf.has_section_key("ai", k):
			ai[k] = int(cf.get_value("ai", k)) if k == "max_rpm" else str(cf.get_value("ai", k))

## Saves the current settings (the admin console's changes survive a restart).
func write_file(p: String = "") -> bool:
	if p == "":
		p = path
	if p == "":
		return false
	var lines := PackedStringArray([
		"; Procedural World dedicated server settings.",
		"; Command-line flags override these: --name= --description= --port= --max-players=",
		"; --password= --admin-password= --world= --seed= --globe= --data= --set key=value",
		"",
		"[server]",
		"",
		"name=%s" % _q(name),
		"description=%s" % _q(description),
		"port=%d" % port,
		"max_players=%d" % max_players,
		"; Leave empty for an open server.",
		"password=%s" % _q(password),
		"; Players who type 'admin <this>' in their console can run server commands.",
		"admin_password=%s" % _q(admin_password),
		"; World folder under data_dir/worlds; made on first start.",
		"world=%s" % _q(world),
		"; Seed for a new world (number or text); empty = random.",
		"seed=%s" % _q(seed_text),
		"; Planet size for a new world: small, medium or large.",
		"globe=%s" % _q(globe),
		"; Where worlds are kept; empty = next to the server.",
		"data_dir=%s" % _q(data_dir),
		"lan_discovery=%s" % str(lan_discovery).to_lower(),
		"",
		"[options]",
		"",
		"; time: normal, day (always day) or night (always night)",
		"time=%s" % _q(options["time"]),
		"day_minutes=%s" % str(options["day_minutes"]),
		"pvp=%s" % str(options["pvp"]).to_lower(),
		"xp_mult=%s" % str(options["xp_mult"]),
		"loot_mult=%s" % str(options["loot_mult"]),
		"; death_penalty: bag (your pack drops where you fall) or keep",
		"death_penalty=%s" % _q(options["death_penalty"]),
		"building=%s" % str(options["building"]).to_lower(),
		"alliances=%s" % str(options["alliances"]).to_lower(),
		"max_alliance=%d" % int(options["max_alliance"]),
		"",
		"[ai]",
		"",
		"; Villagers' language model on the server, for players whose game has none set up.",
		"; provider: off, ollama, lmstudio, strata, anthropic, openai, openrouter or custom.",
		"provider=%s" % _q(ai["provider"]),
		"; Leave empty for the provider's usual address and model.",
		"base_url=%s" % _q(ai["base_url"]),
		"model=%s" % _q(ai["model"]),
		"api_key=%s" % _q(ai["api_key"]),
		"; Requests a minute across all players.",
		"max_rpm=%d" % int(ai["max_rpm"]),
		"",
	])
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		push_warning("ServerConfig: cannot write %s" % p)
		return false
	f.store_string("\n".join(lines))
	return true

static func _q(s) -> String:
	return '"%s"' % str(s).c_escape()

func apply_args(args: PackedStringArray) -> void:
	var list := Array(args)
	# "--set key=value" may come as two words.
	for i in range(list.size() - 1, -1, -1):
		if list[i] == "--set" and i + 1 < list.size():
			list[i] = "--set=" + str(list[i + 1])
			list.remove_at(i + 1)
	for a: String in list:
		var eq := a.find("=")
		if not a.begins_with("--") or eq < 0:
			continue
		var k := a.substr(2, eq - 2)
		var v := a.substr(eq + 1)
		match k:
			"name": name = v
			"description": description = v
			"port": port = int(v)
			"max-players", "max_players": max_players = int(v)
			"password": password = v
			"admin-password", "admin_password": admin_password = v
			"world": world = v
			"seed": seed_text = v
			"globe": globe = _globe(v)
			"data": data_dir = v
			"lan": lan_discovery = v.to_lower() in ["1", "true", "yes", "on"]
			"set":
				var e2 := v.find("=")
				if e2 > 0:
					var err := set_option(v.substr(0, e2), v.substr(e2 + 1))
					if err != "":
						push_warning(err)
	max_players = clampi(max_players, 1, 256)
	port = clampi(port, 1, 65535)

## Sets an option from text, typed to match its default. Returns "" or what was wrong.
func set_option(k: String, v: String) -> String:
	if not OPTIONS.has(k):
		return "Unknown option %s (options: %s)" % [k, ", ".join(OPTIONS.keys())]
	var d = OPTIONS[k]
	v = v.strip_edges()
	match typeof(d):
		TYPE_BOOL:
			var l := v.to_lower()
			if l in ["1", "true", "yes", "on"]:
				options[k] = true
			elif l in ["0", "false", "no", "off"]:
				options[k] = false
			else:
				return "%s takes on or off" % k
		TYPE_FLOAT:
			if not v.is_valid_float():
				return "%s takes a number" % k
			options[k] = clampf(v.to_float(), 0.01, 1000.0)
		TYPE_INT:
			if not v.is_valid_int():
				return "%s takes a whole number" % k
			options[k] = clampi(v.to_int(), 1, 256)
		_:
			if CHOICES.has(k) and not CHOICES[k].has(v.to_lower()):
				return "%s takes %s" % [k, " or ".join(CHOICES[k])]
			options[k] = v.to_lower() if CHOICES.has(k) else v
	return ""

## What the server browser shows.
func info(players: int) -> Dictionary:
	return {"name": name, "description": description, "players": players, "max_players": max_players,
		"password": password != "", "version": ProjectSettings.get_setting("application/config/version", ""),
		"protocol": PROTOCOL, "options": options.duplicate(), "ai": ai_on()}

## The AI settings (the AI autoload's cfg keys) this server's [ai] section comes to.
func ai_settings() -> Dictionary:
	var pr: Dictionary = _AI.PRESETS.get(String(ai["provider"]), _AI.PRESETS["custom"])
	var out := {"provider": ai["provider"], "format": String(ai["format"]) if String(ai["format"]) != "" else String(pr["format"]),
		"base_url": String(ai["base_url"]) if String(ai["base_url"]) != "" else String(pr["base_url"]),
		"model": String(ai["model"]) if String(ai["model"]) != "" else String(pr["model"]),
		"api_key": ai["api_key"], "max_rpm": int(ai["max_rpm"])}
	return out

static func _globe(v: String) -> String:
	v = v.strip_edges().to_lower()
	return v if Globe.SIZES.has(v) else Globe.DEFAULT
