#!/usr/bin/env python3
"""Leaf twig cards for the trees and bushes (RealTree) from Ben's photo cards.

The sources are leaf sprays photographed on black (art/foliage_cards in the project
files, not in the repo). Each is keyed to an alpha mask, its colour bled outward under the
transparent parts so mipmaps don't grow dark fringes, and written as a 1024 px RGBA PNG:

    python3 tools/make_foliage_cards.py /mnt/project-files/art/foliage_cards
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
CARDS = {"leaves.jpg": "oak_twig_card.png", "leaves_autumn.jpg": "autumn_twig_card.png"}
SIZE = 1024


def key(src: Path) -> Image.Image:
    im = Image.open(src).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    peak = a.max(axis=2)
    # Black background: anything brighter than a dim threshold is leaf or twig.
    alpha = np.clip((peak - 0.06) / 0.08, 0.0, 1.0)
    mask = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))
    alpha = np.asarray(mask).astype(np.float32) / 255.0
    # Bleed colour into the background: repeatedly blur the premultiplied colour and
    # divide by the blurred coverage, filling only where there was no leaf.
    col = a * alpha[..., None]
    cov = alpha.copy()
    filled = col.copy()
    have = alpha > 0.5
    for radius in (2, 4, 8, 16, 32, 64):
        bc = np.asarray(Image.fromarray((col * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0
        bw = np.asarray(Image.fromarray((cov * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0
        est = bc / np.maximum(bw[..., None], 1e-3)
        take = (~have) & (bw > 0.01)
        filled[take] = est[take]
        have = have | take
    filled[alpha > 0.5] = a[alpha > 0.5]
    rgba = np.dstack([np.clip(filled, 0, 1), alpha])
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")


def main() -> None:
    src_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "/mnt/project-files/art/foliage_cards")
    for src, dst in CARDS.items():
        key(src_dir / src).save(OUT / dst, optimize=True)
        print("wrote", OUT / dst)


if __name__ == "__main__":
    main()
