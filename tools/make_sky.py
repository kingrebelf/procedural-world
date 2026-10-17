"""Night sky for the sky shader from Ben's night HDRI (Poly Haven dikhololo_night, CC0).

    python3 tools/make_sky.py DIR_WITH_HDRIS

Writes assets/textures/sky/night_stars.jpg: the upper hemisphere (row 0 the zenith, the
last row the horizon, 4096 x 1024 equirectangular, the HDRI's own resolution) with only its stars and the Milky Way
kept: the sky's own glow, the trees on its horizon and the camera's colour noise are taken
out, so the shader's own sky colours show through and the stars are laid over them.
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures" / "sky"


def read_hdr(path):
    with open(path, 'rb') as f:
        data = f.read()
    # Header ends with an empty line, then the resolution line.
    pos = 0
    while True:
        nl = data.index(b'\n', pos)
        line = data[pos:nl]
        pos = nl + 1
        if line == b'':
            break
    nl = data.index(b'\n', pos)
    res = data[pos:nl].split()
    pos = nl + 1
    assert res[0] == b'-Y' and res[2] == b'+X', res
    h, w = int(res[1]), int(res[3])
    buf = np.frombuffer(data, dtype=np.uint8, offset=pos)
    out = np.empty((h, w, 4), dtype=np.uint8)
    i = 0
    for y in range(h):
        if buf[i] == 2 and buf[i + 1] == 2 and (int(buf[i + 2]) << 8 | int(buf[i + 3])) == w:
            i += 4
            for c in range(4):
                x = 0
                row = out[y, :, c]
                while x < w:
                    n = int(buf[i]); i += 1
                    if n > 128:
                        n -= 128
                        row[x:x + n] = buf[i]; i += 1
                    else:
                        row[x:x + n] = buf[i:i + n]; i += n
                    x += n
        else:
            out[y] = buf[i:i + 4 * w].reshape(w, 4); i += 4 * w
    e = out[:, :, 3].astype(np.int32)
    scale = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0).astype(np.float32)
    return out[:, :, :3].astype(np.float32) * scale[:, :, None]


def _box(a, r, axis):
    # Running mean of width 2r+1 along an axis (wrapping across the seam for x).
    c = np.cumsum(np.concatenate([a.take(range(-r - 1, 0), axis=axis, mode='wrap'), a, a.take(range(0, r), axis=axis, mode='wrap')], axis=axis), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = c.take(range(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = c.take(range(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)

def blur(a, r):
    # Three box passes each way approximate a gaussian of sigma ~ r.
    b = max(1, int(r * 0.9))
    out = a
    for _ in range(3):
        out = _box(_box(out, b, 1), b, 0)
    return out


def night_stars(hdr_path):
    img = read_hdr(hdr_path)
    h, w, _ = img.shape
    top = img[: h // 2]  # elevation 90 (row 0) down to 0
    t = top
    k = t.shape[1] / 2048.0  # blur radii below were tuned at 2048 wide
    # Points of light: each pixel above its close surroundings (no halos round bright stars).
    stars = np.clip(t - blur(t, 3 * k), 0, None)
    # The camera's colour noise shows as red, green and blue specks: lift a floor off the
    # points and keep only a little of their colour.
    lum = stars.mean(axis=2, keepdims=True)
    stars = np.clip(lum - np.median(lum) * 8.0, 0, None) * (0.8 + 0.2 * stars / np.maximum(lum, 1e-6))
    # The Milky Way: the band's structure at the scale of its clouds and dust lanes.
    soft = np.minimum(t, blur(t, 4 * k) * 1.3)  # bright stars and planets cut down to their surroundings
    band = np.clip(blur(soft, 2 * k) - blur(soft, 40 * k), 0, None) * 0.6 + np.clip(blur(soft, 8 * k) - blur(soft, 60 * k), 0, None) * 0.6
    layer = stars + band * 1.6
    el = 90.0 - (np.arange(t.shape[0]) + 0.5) / t.shape[0] * 90.0
    # Out above the trees and the town glow low on the horizon, and off the pole's smear.
    fade = np.clip((el - 24.0) / 12.0, 0, 1) * np.clip((88.0 - el) / 4.0, 0, 1)
    fade = fade * fade * (3 - 2 * fade)
    layer *= fade[:, None, None]
    # A gentler curve than plain gamma keeps the faint haze of noise down in the dark.
    ldr = np.clip((layer * 3.0) ** (1 / 1.7), 0, 0.9)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((ldr * 255).astype(np.uint8)).save(OUT / "night_stars.jpg", quality=92)
    print("night stars", ldr.shape)


if __name__ == "__main__":
    night_stars(Path(sys.argv[1]) / "dikhololo_night_4k.hdr")
