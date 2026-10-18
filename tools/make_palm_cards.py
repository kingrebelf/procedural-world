#!/usr/bin/env python3
"""Leaf cards for the tropical plants (RealTree palms and bananas), drawn here rather than
photographed: a palm frond (a rachis with its leaflets) and a banana leaf (a broad blade
with a pale midrib, fine parallel veins and the splits the wind tears along them).

Both stand stem down: the stem at the bottom middle of the card, the tip at the top (as
the oak sprays), so RealTree lays them along an arching strip from the crown outward.
Their colours keep to the mean of Ben's photo leaves (about sRGB 0.35, 0.5, 0.22), so
the species tints RealTree gives a crown read the same on every leaf card. Colour bleeds
out under the transparent parts, as make_foliage_cards.py does, so mipmaps don't fringe.

    python3 tools/make_palm_cards.py
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
SS = 2  # supersampling


def bleed(rgb: np.ndarray, alpha: np.ndarray) -> Image.Image:
    col = rgb * alpha[..., None]
    filled = rgb.copy()
    have = alpha > 0.5
    for radius in (2, 4, 8, 16, 32, 64):
        bc = np.asarray(Image.fromarray((col * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0
        bw = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0
        est = bc / np.maximum(bw[..., None], 1e-3)
        take = (~have) & (bw > 0.01)
        filled[take] = est[take]
        have = have | take
    rgba = np.dstack([np.clip(filled, 0, 1), alpha])
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")


def finish(rgb_img: Image.Image, a_img: Image.Image, w: int, h: int) -> Image.Image:
    rgb = np.asarray(rgb_img.resize((w, h), Image.LANCZOS)).astype(np.float32) / 255.0
    a = np.asarray(a_img.resize((w, h), Image.LANCZOS)).astype(np.float32) / 255.0
    # Colour was drawn over black: un-premultiply where the edge is part covered.
    rgb = rgb / np.maximum(a[..., None], 1e-3)
    return bleed(np.clip(rgb, 0, 1), a)


def shade(c, f):
    return tuple(int(max(0, min(255, v * f * 255))) for v in c)


def frond(w: int = 512, h: int = 1024, seed: int = 7) -> Image.Image:
    """A coconut-palm frond seen from above: leaflets in two ranks along the rachis, angled
    toward the tip, longest a little below the middle, a few torn short or missing."""
    rng = np.random.default_rng(seed)
    W, H = w * SS, h * SS
    rgb = Image.new("RGB", (W, H))
    al = Image.new("L", (W, H))
    dr, da = ImageDraw.Draw(rgb), ImageDraw.Draw(al)
    cx = W * 0.5
    base_y, tip_y = H * 0.985, H * 0.012
    first = 0.13  # bare petiole below the first leaflet (share of the length)
    green = (0.33, 0.5, 0.2)
    per_side = 64
    leaflets = []
    for side in (-1, 1):
        for i in range(per_side):
            t = (i + rng.uniform(-0.3, 0.3)) / per_side
            if rng.random() < 0.03:
                continue  # a leaflet lost
            y = base_y - (base_y - tip_y) * (first + (1 - first) * t)
            # Longest a little below the middle, short at the base and tip.
            ln = math.sin(math.pi * (0.1 + 0.88 * t)) ** 0.55 * (0.62 + 0.38 * (1 - t))
            ln *= W * 0.5 * rng.uniform(0.9, 1.04)
            if rng.random() < 0.06:
                ln *= rng.uniform(0.45, 0.75)  # torn short
            ang = math.radians(rng.uniform(-5, 5) + 72 - 26 * t)  # out from the rachis, leaning toward the tip
            leaflets.append((y, side, ln, ang, t))
    # Leaflets nearer the tip lie over the ones below them.
    leaflets.sort(key=lambda l: -l[0])
    for y, side, ln, ang, t in leaflets:
        bw = W * (0.019 + 0.008 * (1 - t)) * rng.uniform(0.85, 1.15)
        droop = rng.uniform(0.1, 0.22)
        n = 14
        pts_l, pts_r, spine = [], [], []
        for k in range(n + 1):
            s = k / n
            a = ang - droop * s * s * 0.5
            # Out from the rachis and up toward the tip.
            px = cx + side * (math.sin(a) * ln * s)
            py = y - math.cos(a) * ln * s - droop * ln * 0.1 * s * s
            spine.append((px, py))
        for k in range(n + 1):
            s = k / n
            x0, y0 = spine[max(k - 1, 0)]
            x1, y1 = spine[min(k + 1, n)]
            dx, dy = x1 - x0, y1 - y0
            ll = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / ll, dx / ll
            hw = bw * 0.5 * min(1.0, s * 6 + 0.35) * (1 - s) ** 0.75
            pts_l.append((spine[k][0] + nx * hw, spine[k][1] + ny * hw))
            pts_r.append((spine[k][0] - nx * hw, spine[k][1] - ny * hw))
        f = rng.uniform(0.78, 1.18) * (0.92 + 0.16 * t)
        col = shade(green, f)
        poly = pts_l + pts_r[::-1]
        dr.polygon(poly, fill=col)
        da.polygon(poly, fill=255)
        # One half of each leaflet in the light, the other a touch darker (the fold).
        dr.polygon(pts_l + spine[::-1], fill=shade(green, f * 0.86))
        # A pale midrib, and now and then a dry brown tip.
        dr.line(spine[:-2], fill=shade((0.55, 0.62, 0.3), f), width=max(1, int(bw * 0.14)))
        if rng.random() < 0.08:
            k0 = int(n * rng.uniform(0.7, 0.85))
            tip = pts_l[k0:] + pts_r[k0:][::-1]
            dr.polygon(tip, fill=shade((0.5, 0.38, 0.2), rng.uniform(0.8, 1.1)))
    # The rachis over the leaflet bases, thick at the stem.
    n = 40
    for k in range(n):
        s0, s1 = k / n, (k + 1) / n
        y0 = base_y - (base_y - tip_y) * s0
        y1 = base_y - (base_y - tip_y) * s1
        wd = W * (0.024 * (1 - s0) ** 1.3 + 0.003)
        dr.polygon([(cx - wd, y0), (cx + wd, y0), (cx + wd * 0.96, y1), (cx - wd * 0.96, y1)], fill=shade((0.6, 0.64, 0.32), 0.9 + 0.1 * s0))
        da.polygon([(cx - wd, y0), (cx + wd, y0), (cx + wd * 0.96, y1), (cx - wd * 0.96, y1)], fill=255)
        dr.line([(cx - wd * 0.3, y0), (cx - wd * 0.3, y1)], fill=shade((0.72, 0.74, 0.42), 1.0), width=max(1, int(wd * 0.4)))
    return finish(rgb, al, w, h)


def banana(w: int = 512, h: int = 1024, seed: int = 11) -> Image.Image:
    """A banana leaf: an oblong blade on a short petiole, a broad pale midrib, fine veins
    sweeping out from it, and splits torn in from the edge along the veins."""
    rng = np.random.default_rng(seed)
    W, H = w * SS, h * SS
    cx = W * 0.5
    y_base, y_blade, y_tip = H * 0.99, H * 0.86, H * 0.02
    green = (0.32, 0.52, 0.19)
    # Blade half-width along its length (0 at the blade's base, 1 at the tip).
    def half(s):
        return W * 0.47 * (min(1.0, s * 7.0) ** 0.6) * (1 - s ** 6) ** 0.5 * (0.9 + 0.1 * math.sin(s * 3.0))
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    s = np.clip((y_blade - yy) / (y_blade - y_tip), 0.0, 1.0)
    hw = np.vectorize(half)(np.linspace(0, 1, 2048)).astype(np.float32)
    hwp = hw[(s * 2047).astype(np.int32)]
    dx = np.abs(xx - cx)
    inside = (dx < hwp) & (yy <= y_blade) & (yy >= y_tip)
    # Veins sweep out and up from the midrib: lines of constant (y + k*|x|).
    k = 0.42
    vein_coord = (yy + dx * k) / (H * 0.006)
    vein = np.abs(np.sin(vein_coord * math.pi)) ** 18
    # Big leaf shading: a gentle gradient across, lighter along the midrib, mottle.
    across = dx / np.maximum(hwp, 1.0)
    mott = np.asarray(Image.fromarray((rng.random((H // 12, W // 12)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)).astype(np.float32) / 255.0
    f = (0.95 + 0.12 * (1 - across) - 0.08 * across ** 4) * (0.95 + 0.1 * mott) * (0.9 + 0.22 * vein)
    side = np.where(xx < cx, 0.92, 1.03)
    rgb = np.stack([green[0] * f * side, green[1] * f * side, green[2] * f * side], axis=-1)
    # Splits: from the edge in toward the midrib along a vein, on both halves.
    alpha = inside.astype(np.float32)
    for i in range(22):
        sy = rng.uniform(0.12, 0.95)
        sd = -1 if rng.random() < 0.5 else 1
        depth = rng.uniform(0.25, 0.92)
        c0 = (y_blade - sy * (y_blade - y_tip) + half(sy) * k) / (H * 0.006)
        c0 = math.floor(c0) + 0.5
        gap = 0.05 + 0.4 * np.clip((across - (1 - depth)) / depth, 0, 1) * rng.uniform(0.5, 1.0)
        cut = (np.abs(vein_coord - c0) < gap) & (across > 1 - depth) & ((xx - cx) * sd > 0)
        alpha[cut] = 0.0
    # Ragged, browned edge.
    edge = (across > 0.9) & inside
    brown = np.array([0.5, 0.42, 0.22], dtype=np.float32)
    mix = np.clip((across - 0.9) * 10.0 * (0.4 + 0.6 * mott), 0, 1)[..., None] * edge[..., None]
    rgb = rgb * (1 - mix * 0.6) + brown * mix * 0.6
    # Midrib and petiole.
    mid_w = W * (0.003 + 0.024 * (1 - s) ** 1.3)
    rib = (dx < mid_w) & (yy >= y_tip + H * 0.06) & (yy <= y_base)
    rib_c = np.array([0.62, 0.68, 0.4], dtype=np.float32) * (0.92 + 0.12 * (1 - dx / np.maximum(mid_w, 1))[..., None])
    rgb = np.where(rib[..., None], rib_c, rgb)
    alpha = np.maximum(alpha, rib.astype(np.float32))
    rgb_img = Image.fromarray((np.clip(rgb * alpha[..., None], 0, 1) * 255).astype(np.uint8))
    a_img = Image.fromarray((alpha * 255).astype(np.uint8))
    return finish(rgb_img, a_img, w, h)


def main() -> None:
    frond().save(OUT / "palm_frond_card.png", optimize=True)
    banana().save(OUT / "banana_leaf_card.png", optimize=True)
    print("wrote", OUT / "palm_frond_card.png", OUT / "banana_leaf_card.png")


if __name__ == "__main__":
    main()
