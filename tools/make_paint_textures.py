"""Draws the painted interior surfaces of sci-fi rooms (space station / hospital look).

Writes into assets/textures/ at 512 px (greyscale detail, mean about 0.72, tinted by the material
colour and vertex colour, plus a tangent-space normal map), each tile 2.4 m square:
  paint_panels_detail.jpg / _normal.png   painted wall panels, 1.2 m wide, a groove
                                          between them and across every 2.4 m
  vinyl_detail.jpg / _normal.png          sheet vinyl laid in 0.6 m tiles, flecked
  ceiling_tiles_detail.jpg / _normal.png  0.6 m acoustic ceiling tiles on a T-bar grid

Usage: python3 tools/make_paint_textures.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
N = 1024  # pixels per 2.4 m tile while drawing (saved at 512)


def blur(a, r):
    """Gaussian blur that wraps round the edges, so the tile stays seamless."""
    k = np.arange(-int(r * 3) - 1, int(r * 3) + 2)
    w = np.exp(-0.5 * (k / r) ** 2)
    w /= w.sum()
    for axis in (0, 1):
        a = sum(wi * np.roll(a, int(ki), axis) for ki, wi in zip(k, w))
    return a


def smooth_noise(rng, cells, octaves=4):
    """Seamless value noise in 0..1, `cells` lattice cells across the tile at the base octave."""
    out = np.zeros((N, N))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * 2 ** o
        lat = rng.random((c, c))
        img = Image.fromarray((lat * 255).astype(np.uint8))
        # Tile 3x3 before resizing so the edges wrap.
        big = Image.fromarray(np.tile(np.asarray(img), (3, 3))).resize((N * 3, N * 3), Image.BICUBIC)
        out += amp * (np.asarray(big)[N:2 * N, N:2 * N] / 255.0)
        total += amp
        amp *= 0.5
    return out / total


def grooves(pos, period, width, soft):
    """0 in a groove, 1 on the face: distance to the nearest line at multiples of `period`."""
    d = np.abs(((pos + period / 2) % period) - period / 2)
    return np.clip((d - width) / soft, 0, 1)


def normal_from(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / ln, ny / ln, nz / ln], -1)
    return ((n * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)


def save(name, detail, height, strength):
    detail = detail * (0.72 / detail.mean())
    img = Image.fromarray((detail.clip(0, 1) * 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS)
    img.save(OUT / f"{name}_detail.jpg", quality=92)
    Image.fromarray(normal_from(height, strength)).resize((512, 512), Image.LANCZOS).save(OUT / f"{name}_normal.png", optimize=True)


def paint_panels(rng):
    y, x = np.mgrid[0:N, 0:N].astype(float)
    px_m = N / 2.4
    face = grooves(x, 1.2 * px_m, 3.0, 2.0) * grooves(y, 2.4 * px_m, 3.0, 2.0)
    # Each panel a hair different in shade, as sprayed panels are.
    shade = np.where(x < N / 2, 1.0, 0.985)
    mottle = 1.0 + (smooth_noise(rng, 3) - 0.5) * 0.04
    peel = 1.0 + (blur(rng.random((N, N)), 1.2) - 0.5) * 0.05
    # A soft lip along each edge where the panel turns into the groove.
    lip = 1.0 - 0.08 * (1.0 - grooves(x, 1.2 * px_m, 2.5, 7.0) * grooves(y, 2.4 * px_m, 2.5, 7.0))
    detail = (0.68 + 0.32 * face) * shade * mottle * peel * lip
    height = face * 1.0 + (peel - 1.0) * 0.6
    save("paint_panels", detail, blur(height, 0.8), 3.0)


def vinyl(rng):
    y, x = np.mgrid[0:N, 0:N].astype(float)
    t = N / 4  # 0.6 m tiles
    face = grooves(x, t, 0.8, 1.2) * grooves(y, t, 0.8, 1.2)
    tile = rng.uniform(0.97, 1.03, (4, 4))
    tone = tile[(y // t).astype(int) % 4, (x // t).astype(int) % 4]
    # Flecks: small light and dark chips through the sheet.
    r = rng.random((N, N))
    fleck = np.where(r > 0.97, 1.25, np.where(r < 0.03, 0.75, 1.0))
    fleck = 1.0 + (blur(fleck, 0.7) - 1.0) * 1.6
    cloud = 1.0 + (smooth_noise(rng, 6) - 0.5) * 0.06
    detail = (0.8 + 0.2 * face) * tone * fleck * cloud
    height = face + (blur(rng.random((N, N)), 2.0) - 0.5) * 0.15
    save("vinyl", detail, blur(height, 0.6), 2.0)


def ceiling_tiles(rng):
    y, x = np.mgrid[0:N, 0:N].astype(float)
    t = N / 4  # 0.6 m tiles
    bar = 1.0 - grooves(x, t, 5.0, 1.0) * grooves(y, t, 5.0, 1.0)  # 1 on the T-bar
    gap = grooves(x, t, 6.5, 2.0) * grooves(y, t, 6.5, 2.0)  # the tile's shadow line by the bar
    # Fissured mineral fibre: worm-like dark pits.
    pits = blur(rng.random((N, N)), 1.5)
    pits = np.clip((0.485 - pits) * 22.0, 0, 1)
    fibre = 1.0 - 0.09 * pits
    detail = np.where(bar > 0.5, 0.95, (0.78 + 0.2 * gap) * fibre)
    height = np.where(bar > 0.5, 0.6, gap * 1.0 - 0.3 * pits)
    save("ceiling_tiles", detail, blur(height, 0.8), 2.5)


if __name__ == "__main__":
    rng = np.random.default_rng(7)
    paint_panels(rng)
    vinyl(rng)
    ceiling_tiles(rng)
