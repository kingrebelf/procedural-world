class_name WHash
## Platform-independent 32-bit integer hashing. All world randomness flows from here,
## so the same seed always produces the same world on every machine.

const MASK := 0xFFFFFFFF

static func mul32(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var lo := a * (b & 0xFFFF)
	var hi := ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & MASK

## lowbias32 by Chris Wellons.
static func h32(x: int) -> int:
	x &= MASK
	x ^= x >> 16
	x = mul32(x, 0x7feb352d)
	x ^= x >> 15
	x = mul32(x, 0x846ca68b)
	x ^= x >> 16
	return x

static func combine(a: int, b: int) -> int:
	return h32((a & MASK) ^ mul32(h32(b), 0x9E3779B1))

static func hash2(seed: int, x: int, z: int, salt: int = 0) -> int:
	return combine(combine(combine(seed, x), z), salt)

## Uniform float in [0, 1).
static func to_unit(h: int) -> float:
	return float(h & 0xFFFFFF) / 16777216.0

static func unit2(seed: int, x: int, z: int, salt: int = 0) -> float:
	return to_unit(hash2(seed, x, z, salt))

## Stable 32-bit hash of a string (FNV-1a), for salts and seeds typed by players.
static func str_hash(s: String) -> int:
	var h := 0x811C9DC5
	for b in s.to_utf8_buffer():
		h ^= b
		h = mul32(h, 0x01000193)
	return h

static func rng(seed: int, x: int, z: int, salt: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash2(seed, x, z, salt)
	r.state = hash2(seed, x, z, salt + 7919)
	return r
