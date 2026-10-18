#!/usr/bin/env python3
"""Cuts Ben's 3x2 icon sheets (one item per square cell on a flat dark background) into
cells and places each in an icon sheet with tools/place_icon.py.

Usage: python3 tools/place_sheets.py <source dir> <cell dir> <sheet>:<first cell>:<src>:<id,id,...> ...
Each argument places the six cells of <source dir>/<src>.png, left to right and top to
bottom, into consecutive cells of assets/icons/<sheet>.png from <first cell> on; a cell
named "-" is cut but not placed. Name the ids in Icons.MORE_SHEETS to match."""
import os
import subprocess
import sys
from PIL import Image

INSET = 0.04 # trim each cell's edge so a neighbour reaching over the line is left out


def main(src_dir, cell_dir, specs):
    os.makedirs(cell_dir, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))
    for spec in specs:
        sheet, first, src, ids = spec.split(":")
        im = Image.open(os.path.join(src_dir, src + ".png")).convert("RGB")
        cw, ch = im.size[0] // 3, im.size[1] // 2
        k = int(first)
        for i, t in enumerate(ids.split(",")):
            x, y = (i % 3) * cw, (i // 3) * ch
            dx, dy = int(cw * INSET), int(ch * INSET)
            out = os.path.join(cell_dir, t + ".png")
            im.crop((x + dx, y + dy, x + cw - dx, y + ch - dy)).save(out)
            if t != "-":
                subprocess.run([sys.executable, os.path.join(here, "place_icon.py"), "assets/icons/%s.png" % sheet, str(k), out], check=True)
                k += 1


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
