class_name NetPack
## Chunks, settlements and saves on the wire: Godot's binary variant format, zstd
## compressed, with the raw size in front so the receiver can refuse a bomb.

const MAX_SIZE := 8 * 1024 * 1024

static func pack(v) -> PackedByteArray:
	var b := var_to_bytes(v)
	var z := b.compress(FileAccess.COMPRESSION_ZSTD)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, b.size())
	out.append_array(z)
	return out

## Decodes what pack() made; null if it is damaged or too big. Never decodes objects.
static func unpack(b: PackedByteArray):
	if b.size() < 5:
		return null
	var n := b.decode_u32(0)
	if n == 0 or n > MAX_SIZE:
		return null
	var raw := b.slice(4).decompress(n, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != n:
		return null
	return bytes_to_var(raw)
