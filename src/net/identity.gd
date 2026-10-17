class_name Identity
extends RefCounted
## Who you are on servers: a display name and a secret token made once per install
## (user://identity.cfg). Servers know you by the token's hash, so nobody can take your
## character by typing your name, and changing your name keeps your save.

const PATH := "user://identity.cfg"
static var override := "" ## tests: a file to use instead

## --identity=<name> plays as someone else (user://identity_<name>.cfg): two copies of
## the game on one computer can then join the same server as two players.
static func path() -> String:
	if override != "":
		return override
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--identity="):
			return "user://identity_%s.cfg" % a.substr(11).validate_filename()
	return PATH

static func load_or_make() -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(path())
	var token := str(cf.get_value("me", "token", ""))
	if token.length() < 32:
		var c := Crypto.new()
		token = c.generate_random_bytes(32).hex_encode()
		cf.set_value("me", "token", token)
		cf.save(path())
	return {"name": str(cf.get_value("me", "name", "")), "token": token}

static func remember_name(n: String) -> void:
	var cf := ConfigFile.new()
	cf.load(path())
	cf.set_value("me", "name", clean_name(n))
	cf.save(path())

## Names are 2-20 characters: letters, digits, spaces and a little punctuation.
static func clean_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		if ch.is_valid_identifier() or ch.is_valid_int() or ch in " -_.'" or ch.unicode_at(0) > 127:
			out += ch
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.substr(0, 20).strip_edges()

static func valid_name(n: String) -> bool:
	var c := clean_name(n)
	return c.length() >= 2 and c == n.strip_edges()

static func token_key(token: String) -> String:
	return token.sha256_text()
