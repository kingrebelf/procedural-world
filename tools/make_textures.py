"""Turns photo texture sources into game textures.

For each source it writes, into assets/textures/:
  <name>_albedo.jpg   colour, cropped to its true repeat period if the image tiles 2x2
  <name>_detail.jpg   greyscale detail (mean 0.72, softened contrast) for materials tinted by vertex colour
  <name>_normal.png   tangent-space normal map from a high-passed luminance height

Fabric sheets (FABRICS) only get <name>_detail.jpg; embroidered_trim keeps its colour.

Usage: python3 tools/make_textures.py SRC_DIR   (expects <name>.jpg files in SRC_DIR,
plus leaves.jpg, a leaf cluster on black, for the foliage card leaves_card.png)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
# name -> normal strength
SOURCES = {
    "grass": 2.0, "dirt": 3.0, "rock": 4.0, "mud": 2.5,
    "bark_oak": 5.0, "bark_birch": 3.0, "cobble": 5.0,
    "planks": 4.0, "thatch": 3.0, "plaster": 3.0, "glowmoss": 2.5, "darksoil": 3.0,
    "reddust": 3.0, "panels": 5.0, "rust": 4.0, "snow": 3.5,
    # From Ben's prompts (2026-10-17): sci-fi ground, stronghold stone.
    "regolith": 2.5, "castle_wall": 5.0, "dungeon_wall": 5.0, "flagstone": 5.0,
    # Ben's wonder surfaces (2026-10-17, art/wonder_materials).
    "titan_stone": 5.0, "titan_stone_glow": 5.0, "worldroot_bark": 5.0, "starfall_glass": 3.5,
    "gate_ring_metal": 3.0, "void_stone": 3.0,
    # Ben's interior and sci-fi sheets (2026-10-17).
    "wood_floor": 4.0, "stone_floor": 5.0, "tapestry": 1.5, "bookshelf": 3.0, "wallpaper": 1.5,
    "hearth_brick": 5.0, "scifi_floor": 4.0, "scifi_panels": 4.0, "scifi_lights": 4.0, "hazard": 3.0,
    "alien_hull": 4.0, "screen": 1.0,
}

# Sources whose glowing parts get an emission map (<name>_emit.jpg): name -> (hue in
# degrees or None for any bright pixel, hue tolerance, value threshold).
EMIT = {
    "titan_stone_glow": (24, 20, 0.78), "worldroot_bark": (165, 45, 0.45),
    "gate_ring_metal": (205, 40, 0.4), "void_stone": (None, 0, 0.62), "starfall_glass": (None, 0, 0.8),
    "scifi_lights": (190, 30, 0.45), "alien_hull": (280, 40, 0.25), "screen": (None, 0, 0.05),
}


# Sources that also need a greyscale version (materials coloured per species or era).
DETAIL = {"rock", "bark_oak", "bark_birch", "planks", "plaster", "panels"}


def true_period(a):
    """A 2x2-repeating source crops to one quadrant, which tiles exactly."""
    h, w, _ = a.shape
    inner = np.abs(a[:, 1:] - a[:, :-1]).mean()
    half_x = np.abs(a[:, : w // 2] - a[:, w // 2 :]).mean()
    half_y = np.abs(a[: h // 2] - a[h // 2 :]).mean()
    if half_x < inner * 0.6 and half_y < inner * 0.6:
        return a[: h // 2, : w // 2]
    return a


def feather_seams(a, band=24):
    """Cross-fades a narrow band at each edge with the opposite edge so wrapping is soft."""
    a = a.copy()
    h, w, _ = a.shape
    for i in range(band):
        t = 0.5 * (1 - i / band)
        l, r = a[:, i].copy(), a[:, w - 1 - i].copy()
        a[:, i] = l * (1 - t) + r * t
        a[:, w - 1 - i] = r * (1 - t) + l * t
        tp, bt = a[i].copy(), a[h - 1 - i].copy()
        a[i] = tp * (1 - t) + bt * t
        a[h - 1 - i] = bt * (1 - t) + tp * t
    return a


def normal_from(lum, strength):
    # High-pass so large lighting gradients baked in the photo don't tilt the surface.
    img = Image.fromarray((lum * 255).astype(np.uint8))
    lum = np.asarray(img.filter(ImageFilter.GaussianBlur(1.6))).astype(float) / 255
    low = np.asarray(img.filter(ImageFilter.GaussianBlur(24))).astype(float) / 255
    h = lum - low
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny, nz = -dx * strength * 8, dy * strength * 8, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / ln, ny / ln, nz / ln], -1)
    return ((n * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)


def main(src_dir):
    OUT.mkdir(parents=True, exist_ok=True)
    for name, strength in SOURCES.items():
        p = Path(src_dir) / f"{name}.jpg"
        if not p.exists():
            print("missing", p)
            continue
        a = np.asarray(Image.open(p).convert("RGB")).astype(float) / 255
        a = feather_seams(true_period(a))
        size = 1024 if a.shape[0] >= 1024 else 512
        img = Image.fromarray((a * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
        img.save(OUT / f"{name}_albedo.jpg", quality=92)
        a = np.asarray(img).astype(float) / 255
        lum = a @ np.array([0.299, 0.587, 0.114])
        det = (0.72 * (1 + (lum / max(lum.mean(), 1e-3) - 1) * 0.6)).clip(0, 1)
        if name in DETAIL:
            Image.fromarray((det * 255).astype(np.uint8)).save(OUT / f"{name}_detail.jpg", quality=92)
        nrm = Image.fromarray(normal_from(lum, strength)).resize((512, 512), Image.LANCZOS)
        nrm.save(OUT / f"{name}_normal.png", optimize=True)
        if name in EMIT:
            Image.fromarray((emission(a, *EMIT[name]) * 255).astype(np.uint8)).save(OUT / f"{name}_emit.jpg", quality=90)
        lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
        print(name, size, "linear mean", lin.reshape(-1, 3).mean(0).round(4))



# Ben's fabric sheets (2026-10-17) for clothes and armour. Clothes are coloured per person,
# so these become greyscale detail (name -> contrast; mail keeps its gaps dark); the gold
# trim keeps its colour. 512 is plenty at character scale.
FABRICS = {"fabric_linen": 0.8, "fabric_wool": 0.9, "fabric_velvet": 0.7, "leather_worn": 0.8, "chainmail": 1.0}


def make_fabrics(src_dir, size=512):
    for name, contrast in FABRICS.items():
        p = Path(src_dir) / f"{name}.jpg"
        if not p.exists():
            print("missing", p)
            continue
        a = np.asarray(Image.open(p).convert("RGB")).astype(float) / 255
        a = feather_seams(true_period(a))
        lum = a @ np.array([0.299, 0.587, 0.114])
        det = (0.72 * (1 + (lum / max(lum.mean(), 1e-3) - 1) * contrast)).clip(0, 1)
        img = Image.fromarray((det * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
        img.save(OUT / f"{name}_detail.jpg", quality=92)
        print(name, "detail")
    p = Path(src_dir) / "embroidered_trim.jpg"
    if p.exists():
        Image.open(p).convert("RGB").resize((size, size), Image.LANCZOS).save(OUT / "embroidered_trim_albedo.jpg", quality=92)
        print("embroidered_trim albedo")


def emission(a, hue, tol, thresh):
    """The glowing parts of a texture in their own colour, black elsewhere: pixels bright
    enough and, when `hue` is given, close enough to that hue and saturated."""
    mx, mn = a.max(-1), a.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    w = np.clip((mx - thresh) / 0.2, 0, 1)
    if hue is not None:
        r, g, b = a[..., 0], a[..., 1], a[..., 2]
        h = np.degrees(np.arctan2(np.sqrt(3) * (g - b), 2 * r - g - b)) % 360
        d = np.abs((h - hue + 180) % 360 - 180)
        w *= np.clip((tol - d) / (tol * 0.5), 0, 1) * np.clip((sat - 0.25) / 0.25, 0, 1)
    return (a * w[..., None]).clip(0, 1)


def box_blur(a, r):
    """Separable box blur with wrap-around, on float arrays."""
    for axis in (0, 1):
        c = np.cumsum(np.concatenate([a.take(range(-r - 1, 0), axis), a, a.take(range(0, r), axis)], axis), axis)
        n = a.shape[axis]
        a = (c.take(range(2 * r + 1, 2 * r + 1 + n), axis) - c.take(range(0, n), axis)) / (2 * r + 1)
    return a


def make_leaf_card(src, out_name="leaves_card.png", size=512):
    """Keys a leaf cluster shot on black into an RGBA foliage card. Colour is mostly
    greyscale (each species tints it) with a little of the photo's own green kept."""
    a = np.asarray(Image.open(src).convert("RGB")).astype(float) / 255
    m = a.max(-1)
    alpha = np.clip((m - 0.07) / 0.08, 0, 1)
    lum = a @ np.array([0.299, 0.587, 0.114])
    mean = lum[alpha > 0.5].mean()
    grey = np.repeat((lum / mean * 0.62)[..., None], 3, -1)
    chroma = a / max(mean, 1e-3) * 0.62 * np.array([1.0, 0.85, 1.1])
    rgb = (grey * 0.75 + chroma * 0.25).clip(0, 1)
    # Bleed leaf colour into the transparent area (coverage-weighted blur, widening until
    # every pixel is filled) so filtering and mipmaps never pull in the black background.
    known = alpha > 0.5
    fill = np.where(known[..., None], rgb, 0.0)
    done = known.copy()
    for radius in (4, 12, 32, 96, 256):
        num = np.dstack([box_blur(rgb[..., c] * known, radius) for c in range(3)])
        den = box_blur(known.astype(float), radius)
        new = (~done) & (den > 1e-4)
        fill[new] = num[new] / den[new][:, None]
        done |= new
    rgb8 = (fill.clip(0, 1) * 255).astype(np.uint8)
    # Resize colour and alpha separately: Pillow premultiplies RGBA when resizing, which
    # would turn the bled colour back to black.
    rgb_s = Image.fromarray(rgb8).resize((size, size), Image.LANCZOS)
    a_s = Image.fromarray((alpha * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
    rgb_s.putalpha(a_s)
    rgb_s.save(OUT / out_name, optimize=True)
    print("leaf card", out_name)


# Ben's effect flipbooks (2026-10-17): 4 x 4 frames on black, drawn additively, so the
# black is see-through and the alpha is dropped. name -> sheet size (fire is seen close up).
FX = {"fire": 1024, "jet": 512, "explosion": 512, "magic": 512}


def make_fx(src_dir):
    out = OUT / "fx"
    out.mkdir(parents=True, exist_ok=True)
    for name, size in FX.items():
        p = Path(src_dir) / f"{name}_flipbook.png"
        if not p.exists():
            print("missing", p)
            continue
        Image.open(p).convert("RGB").resize((size, size), Image.LANCZOS).save(out / f"{name}_flipbook.png", optimize=True)
        print(name, "flipbook", size)


def make_portal(src_dir):
    """The magic flipbook's four fullest frames (its third row) as one strip: a portal
    turns them in its door and cross-fades between them, so it shimmers without pulsing."""
    p = Path(src_dir) / "magic_flipbook.png"
    if not p.exists():
        print("missing", p)
        return
    im = Image.open(p).convert("RGB")
    f = im.width // 4
    im.crop((0, 2 * f, 4 * f, 3 * f)).save(OUT / "fx" / "portal_swirl.png", optimize=True)
    print("portal swirl", 4 * f, "x", f)


if __name__ == "__main__":
    main(sys.argv[1])
    make_fabrics(sys.argv[1])
    make_fx(sys.argv[1])
    make_portal(sys.argv[1])
    if (Path(sys.argv[1]) / "leaves.jpg").exists():
        make_leaf_card(Path(sys.argv[1]) / "leaves.jpg")
