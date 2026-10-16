"""Paints the conifer foliage card assets/textures/needles_card.png.

A spray of fir sprigs: a twig with dense needles on both sides, angled forward and
shortening towards the tip. Drawn 4x oversized and filtered down so needles stay smooth,
with colour bled into the transparent area so mipmaps never darken the edges. Colour is
a light grey-green: each species tints it with its vertex colour.

Usage: python3 tools/make_needle_card.py
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures" / "needles_card.png"
SIZE = 512
SS = 4
W = SIZE * SS


def box_blur(a, r):
    for axis in (0, 1):
        c = np.cumsum(np.concatenate([a.take(range(-r - 1, 0), axis), a, a.take(range(0, r), axis)], axis), axis)
        n = a.shape[axis]
        a = (c.take(range(2 * r + 1, 2 * r + 1 + n), axis) - c.take(range(0, n), axis)) / (2 * r + 1)
    return a


def sprig(rgb, mask, rnd, start, angle, length, width_scale):
    """A twig from `start` heading `angle`, curving slightly, with needles on both sides."""
    pts = []
    x, y = start
    a = angle
    bend = rnd.uniform(-0.25, 0.25) / length
    steps = int(length / (3 * SS))
    for i in range(steps):
        pts.append((x, y))
        a += bend * 3 * SS
        x += math.cos(a) * 3 * SS
        y += math.sin(a) * 3 * SS
    for i, (px, py) in enumerate(pts):
        t = i / max(1, len(pts) - 1)
        ta = angle + bend * 3 * SS * i
        nl = (17 + rnd.uniform(-3, 3)) * SS * (1.0 - 0.55 * t) * width_scale
        for side in (-1, 1):
            if rnd.random() < 0.08:
                continue
            na = ta + side * rnd.uniform(0.75, 1.05)
            ex = px + math.cos(na) * nl
            ey = py + math.sin(na) * nl
            shade = rnd.uniform(0.72, 1.12) * (0.92 + 0.12 * t)
            col = (int(190 * shade), int(222 * shade), int(176 * shade))
            w = int(round(rnd.uniform(1.6, 2.2) * SS))
            ImageDraw.Draw(rgb).line([(px, py), (ex, ey)], fill=col, width=w)
            ImageDraw.Draw(mask).line([(px, py), (ex, ey)], fill=255, width=w)
    tw = (int(150 * 0.75), int(150 * 0.7), int(120 * 0.6))
    ImageDraw.Draw(rgb).line(pts, fill=tw, width=int(2.4 * SS))
    ImageDraw.Draw(mask).line(pts, fill=255, width=int(2.4 * SS))
    return pts


def main():
    rnd = random.Random(7)
    rgb = Image.new("RGB", (W, W), (0, 0, 0))
    mask = Image.new("L", (W, W), 0)
    # A main branch across the card, slightly drooping, with side sprigs off it.
    c = W / 2
    main_pts = sprig(rgb, mask, rnd, (W * 0.04, c), 0.0, W * 0.9, 1.15)
    for i, (px, py) in enumerate(main_pts):
        if i < 3 or i % 8:
            continue
        t = i / len(main_pts)
        for side in (-1, 1):
            if rnd.random() < 0.15:
                continue
            ang = 0.06 + side * rnd.uniform(0.8, 1.05)
            ln = W * (0.5 - 0.3 * t) * rnd.uniform(0.85, 1.1)
            sprig(rgb, mask, rnd, (px, py), ang, ln, 0.95)
    rgb_a = np.asarray(rgb).astype(float) / 255
    alpha = np.asarray(mask).astype(float) / 255
    known = alpha > 0.5
    fill = np.where(known[..., None], rgb_a, 0.0)
    done = known.copy()
    for radius in (8, 24, 64, 192, 512):
        num = np.dstack([box_blur(rgb_a[..., k] * known, radius) for k in range(3)])
        den = box_blur(known.astype(float), radius)
        new = (~done) & (den > 1e-4)
        fill[new] = num[new] / den[new][:, None]
        done |= new
    out = Image.fromarray((fill.clip(0, 1) * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS)
    out.putalpha(Image.fromarray((alpha * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS))
    out.save(OUT, optimize=True)
    a = np.asarray(out)[..., 3] / 255
    print("needle card", OUT.name, "coverage %.2f" % (a > 0.45).mean())


if __name__ == "__main__":
    main()
