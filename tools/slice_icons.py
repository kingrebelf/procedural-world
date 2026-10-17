#!/usr/bin/env python3
"""Cuts a painted icon grid into the game's icon sheet (assets/icons/items.png).

Usage: python3 tools/slice_icons.py <source image> [out.png] [--grid]
(--grid: an even 6x5 grid without labels, e.g. assets/icons/items2.png)

The source is a 6x5 grid in the order of Icons.SHEET_ORDER (src/ui/icons.gd). Each
cell's flat background is keyed out by flood fill from the cell border, the icon is
trimmed, centred and scaled into a regular 128 px cell. ROWS gives each row's top and
the bottom edge above any baked-in label text; adjust it for a differently laid out
source."""
import sys
from collections import deque
from PIL import Image, ImageFilter

COLS = [0, 170, 341, 512, 682, 853, 1024]
ROWS = [(2, [140] * 6), (188, [330] * 6), (386, [540, 540, 545, 545, 540, 545]), (647, [792] * 6), (846, [994] * 6)]
C = 128


def main(src, out, grid=False):
    im = Image.open(src).convert("RGB")
    sx, sy = im.size[0] / 1024.0, im.size[1] / 1024.0
    cols, rows = COLS, ROWS
    if grid:
        # An evenly spaced 6x5 grid with no label text (later sheets).
        cols = [round(i * 1024 / 6) for i in range(7)]
        rows = [(round(r * 1024 / 5) + 10, [round((r + 1) * 1024 / 5) - 10] * 6) for r in range(5)]
    sheet = Image.new("RGBA", (6 * C, len(rows) * C), (0, 0, 0, 0))
    for ri, (y0, ends) in enumerate(rows):
        for ci in range(6):
            box = (int((cols[ci] + 3) * sx), int(y0 * sy), int((cols[ci + 1] - 3) * sx), int(ends[ci] * sy))
            cell = im.crop(box)
            w, h = cell.size
            px = cell.load()
            border = [px[x, 0] for x in range(w)] + [px[0, y] for y in range(h)] + [px[w - 1, y] for y in range(h)]
            border.sort(key=sum)
            bg = border[len(border) // 2]
            alpha = Image.new("L", (w, h), 255)
            ap = alpha.load()
            seen = set()
            edge = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
            # Grid sheets have cells of slightly different greys; each border pixel keys
            # its own shade, as long as that shade is close to the cell's background.
            q = deque((x, y, px[x, y] if grid and sum(abs(px[x, y][i] - bg[i]) for i in range(3)) < 70 else bg) for x, y in edge)
            while q:
                x, y, ref = q.popleft()
                if (x, y) in seen or x < 0 or y < 0 or x >= w or y >= h:
                    continue
                if sum(abs(px[x, y][i] - ref[i]) for i in range(3)) > 40:
                    continue
                seen.add((x, y))
                ap[x, y] = 0
                q.extend([(x + 1, y, ref), (x - 1, y, ref), (x, y + 1, ref), (x, y - 1, ref)])
            if grid:
                # Background enclosed by the item (inside a bow's string) is not reached
                # from the border; clear any other large patch of background colour.
                for sy0 in range(0, h, 6):
                    for sx0 in range(0, w, 6):
                        if (sx0, sy0) in seen or sum(abs(px[sx0, sy0][i] - bg[i]) for i in range(3)) > 24:
                            continue
                        patch = []
                        q = deque([(sx0, sy0)])
                        while q:
                            x, y = q.popleft()
                            if (x, y) in seen or x < 0 or y < 0 or x >= w or y >= h:
                                continue
                            seen.add((x, y))
                            if sum(abs(px[x, y][i] - bg[i]) for i in range(3)) > 30:
                                continue
                            patch.append((x, y))
                            q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
                        if len(patch) > 900:
                            for x, y in patch:
                                ap[x, y] = 0
            alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
            rgba = cell.convert("RGBA")
            rgba.putalpha(alpha)
            bbox = alpha.point(lambda a: 255 if a > 40 else 0).getbbox() or (0, 0, w, h)
            rgba = rgba.crop(bbox)
            s = max(rgba.size)
            sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
            sq.paste(rgba, ((s - rgba.size[0]) // 2, (s - rgba.size[1]) // 2))
            sq = sq.resize((int(C * 0.92), int(C * 0.92)), Image.LANCZOS)
            sheet.paste(sq, (ci * C + (C - sq.size[0]) // 2, ri * C + (C - sq.size[1]) // 2), sq)
    sheet.save(out)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--grid"]
    main(args[0], args[1] if len(args) > 1 else "assets/icons/items.png", "--grid" in sys.argv)
