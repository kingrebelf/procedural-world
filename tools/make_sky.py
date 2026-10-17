"""Night sky for the sky shader, from Ben's own painted night sky (art/sky_and_planets/sky_night.jpg)
or, failing that, his night HDRI (Poly Haven dikhololo_night, CC0).

    python3 tools/make_sky.py PATH/sky_night.jpg   (and moon.png beside it)
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


def _minf(a, r):
    # Minimum over a (2r+1) square, wrapping across the seam in x.
    out = a.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            sh = np.roll(a, dx, axis=1)
            if dy:
                sh = np.roll(sh, dy, axis=0)
                # Edge rows must not take values wrapped from the far edge.
                if dy > 0:
                    sh[:dy] = a[:dy]
                else:
                    sh[dy:] = a[dy:]
            np.minimum(out, sh, out=out)
    return out


def night_from_art(path):
    """Ben's painted sky (4096 x 2048 equirectangular, a star field and Milky Way on black)
    has soft stars four or five pixels wide and a fine checker dither, which the camera
    magnifies into blobs. So it is taken apart: the glow of the Milky Way is kept, smoothed,
    and each star is found and drawn again as a sharp point of the same colour and
    brightness, widened toward the zenith so it stays round once the map is wrapped
    onto the sky. Then only the upper hemisphere is kept, faded into the haze near the
    horizon."""
    img = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    h, w, _ = img.shape
    lin = img[: h // 2] ** 2.2
    hh = lin.shape[0]
    soft = np.stack([blur(lin[:, :, c], 1) for c in range(3)], axis=2)
    # The glow under the stars: a minimum filter wipes out the points, a blur smooths it.
    glow = np.stack([blur(_minf(soft[:, :, c], 4), 5) for c in range(3)], axis=2)
    res = np.clip(soft - glow, 0, None)
    lum = res @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    # Stars are the local peaks of what stands above the glow.
    peak = lum >= np.maximum.reduce([np.roll(np.roll(lum, dy, 0), dx, 1) for dy in (-2, -1, 0, 1, 2) for dx in (-2, -1, 0, 1, 2)])
    peak &= lum > 0.004
    ys, xs = np.nonzero(peak)
    el = 90.0 - (np.arange(hh) + 0.5) / hh * 90.0
    rng = np.random.default_rng(7)
    found = []
    for y, x in zip(ys, xs):
        if y < 2 or y >= hh - 2:
            continue
        cosl = max(np.cos(np.radians(el[y])), 0.05)
        # Equal-area: the painting is evenly dense per pixel, the sky per steradian.
        if rng.random() > cosl:
            continue
        win = res[y - 2: y + 3, np.arange(x - 2, x + 3) % w]
        found.append((y, x, cosl, win.sum(axis=(0, 1))))
    lums = np.array([f[3] @ np.array([0.2126, 0.7152, 0.0722]) for f in found])
    mid = np.median(lums)
    stars = np.zeros_like(lin)
    for (y, x, cosl, flux), l in zip(found, lums):
        # Spread the magnitudes: the faint many stay faint, the few bright ones stand out.
        flux = flux * 0.3 * (l / mid) ** 0.4
        # A point a little over a pixel wide, stretched across x near the pole.
        sx = 0.6 / cosl
        rx = int(np.ceil(sx * 2.5))
        dx = np.arange(-rx, rx + 1)
        dy = np.arange(-1, 2)
        k = np.exp(-0.5 * (dx[None, :] / sx) ** 2 - 0.5 * (dy[:, None] / 0.6) ** 2)
        k /= k.sum()
        stars[y - 1: y + 2, (x + dx) % w] += k[:, :, None] * flux[None, None, :]
    n = len(found)
    layer = glow * 0.6 + stars
    fade = np.clip((el - 2.0) / 14.0, 0, 1) * np.clip((87.0 - el) / 5.0, 0, 1)
    fade = fade * fade * (3 - 2 * fade)
    out = np.clip(layer * fade[:, None, None], 0, 1) ** (1 / 2.2)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8)).save(OUT / "night_stars.jpg", quality=94)
    print("night stars from art", out.shape, n, "stars")


def moon(path):
    """Ben's moon painting, cropped to the disc and blacked out around it, for the sky
    shader to wrap onto the moon's place in the sky."""
    img = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    lum = img.mean(axis=2)
    ys, xs = np.nonzero(lum > 24)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    r = max(xs.max() - xs.min(), ys.max() - ys.min()) / 2 + 1
    box = (int(cx - r), int(cy - r), int(cx + r), int(cy + r))
    disc = Image.fromarray(img.astype(np.uint8)).crop(box).resize((512, 512), Image.LANCZOS)
    a = np.asarray(disc, dtype=np.float32)
    g = (np.arange(512) + 0.5) / 256.0 - 1.0
    d = np.sqrt(g[None, :] ** 2 + g[:, None] ** 2)
    a *= np.clip((1.0 - d) * 128.0, 0, 1)[:, :, None]
    Image.fromarray(a.astype(np.uint8)).save(OUT / "moon.png")
    print("moon", box)


if __name__ == "__main__":
    src = Path(sys.argv[1])
    if src.suffix.lower() in (".jpg", ".jpeg", ".png"):
        night_from_art(src)
        if (src.parent / "moon.png").exists():
            moon(src.parent / "moon.png")
    else:
        night_stars(src / "dikhololo_night_4k.hdr")
