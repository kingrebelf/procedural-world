#!/usr/bin/env python3
"""Ben's painted UI kit and HUD sheets -> assets/ui.

  python3 tools/prepare_ui_kit.py [kit_dir] [hud_dir]

kit_dir holds the keyed RGBA frames (ui_panel.png, ui_button.png, ...), hud_dir the
sliced 6x5 sheets (status_icons_sliced.png, crosshairs_sliced.png). Each frame is
cropped to its opaque box and scaled to the size UITheme slices it at; the sheets are
scaled to 64 px cells. The sources are not in the repo."""
import sys
from pathlib import Path
from PIL import Image

KIT = Path(sys.argv[1] if len(sys.argv) > 1 else "/mnt/project-files/art/game_ui_kit/keyed")
HUD = Path(sys.argv[2] if len(sys.argv) > 2 else "/mnt/project-files/art/hud_sheets")
OUT = Path(__file__).resolve().parent.parent / "assets" / "ui"

# name -> (width, height) after cropping; None keeps the aspect for that side.
FRAMES = {
    "ui_panel": (484, None),
    "ui_button": (None, 40),
    "ui_button_hover": (None, 40),
    "ui_slot": (96, 96),
    "ui_slot_selected": (96, 96),
    "ui_bar_frame": (None, 32),
    "ui_tooltip": (None, 64),
    "ui_paperdoll": (None, 640),
}

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (w, h) in FRAMES.items():
        im = Image.open(KIT / f"{name}.png").convert("RGBA")
        im = im.crop(im.getbbox())
        if w is None:
            w = round(im.width * h / im.height)
        if h is None:
            h = round(im.height * w / im.width)
        im.resize((w, h), Image.LANCZOS).save(OUT / f"{name}.png", optimize=True)
        print(name, w, h)
    for sheet in ("status_icons", "crosshairs"):
        im = Image.open(HUD / f"{sheet}_sliced.png").convert("RGBA")
        im.resize((384, 320), Image.LANCZOS).save(OUT / f"{sheet}.png", optimize=True)
        print(sheet, 384, 320)

if __name__ == "__main__":
    main()
