#!/usr/bin/env python3
"""Puts one painted icon (a single item on a flat dark background, like Ben's uploads)
into a free cell of an icon sheet, keyed and scaled like tools/slice_icons.py does.

Usage: python3 tools/place_icon.py <sheet.png> <cell index> <source image>

The cell index counts across the sheet's 6 columns, in the order the sheet's list in
Icons.MORE_SHEETS (src/ui/icons.gd) gives; name the item there in that cell."""
import sys
from collections import deque
from PIL import Image, ImageFilter

C = 128


def key(src):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()
    border = sorted([px[x, 0] for x in range(w)] + [px[0, y] for y in range(h)], key=sum)
    bg = border[len(border) // 2]
    alpha = Image.new("L", (w, h), 255)
    ap = alpha.load()
    seen = bytearray(w * h)
    q = deque([(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)])
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x]:
            continue
        seen[y * w + x] = 1
        if sum(abs(px[x, y][i] - bg[i]) for i in range(3)) > 30:
            continue
        ap[x, y] = 0
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.2))
    rgba = im.convert("RGBA")
    rgba.putalpha(alpha)
    bbox = alpha.point(lambda a: 255 if a > 40 else 0).getbbox() or (0, 0, w, h)
    rgba = rgba.crop(bbox)
    s = max(rgba.size)
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(rgba, ((s - rgba.size[0]) // 2, (s - rgba.size[1]) // 2))
    return sq.resize((int(C * 0.92), int(C * 0.92)), Image.LANCZOS)


def main(sheet_path, idx, src):
    sheet = Image.open(sheet_path).convert("RGBA")
    x, y = (idx % 6) * C, (idx // 6) * C
    sheet.paste(Image.new("RGBA", (C, C), (0, 0, 0, 0)), (x, y))
    icon = key(src)
    sheet.paste(icon, (x + (C - icon.size[0]) // 2, y + (C - icon.size[1]) // 2), icon)
    sheet.save(sheet_path)


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]), sys.argv[3])
