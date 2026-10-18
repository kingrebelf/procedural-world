"""Title cards for the trailer (tools/trailer.gd takes, cut by tools/trailer_edit.py).

Writes transparent 3840x2160 PNGs into tools/trailer_titles/ (Cinzel for the titles,
Barlow for the small lines, both OFL, from assets/fonts), each a soft-shadowed line of
text the edit fades in over the footage:
    python3 tools/trailer_titles.py
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tools", "trailer_titles")
W, H = 3840, 2160
CINZEL = os.path.join(ROOT, "assets", "fonts", "Cinzel.ttf")
BARLOW = os.path.join(ROOT, "assets", "fonts", "BarlowSemiCondensed-Medium.ttf")

# name: [(text, font, size, tracking, y as a share of the height)], placement
CARDS = {
    "t1_one_seed": [("ONE SEED", CINZEL, 150, 0.32, 0.47)],
    "t2_whole_world": [("A WHOLE WORLD", CINZEL, 150, 0.32, 0.47)],
    "t3_every_region": [("EVERY MOUNTAIN, RIVER AND TOWN", CINZEL, 96, 0.28, 0.80),
        ("generated as you explore", BARLOW, 64, 0.12, 0.865)],
    "t4_living_water": [("LIVING WATER", CINZEL, 110, 0.3, 0.80),
        ("waves, wakes and rain on every surface", BARLOW, 64, 0.12, 0.865)],
    "t5_weather": [("WEATHER THAT MOVES", CINZEL, 110, 0.3, 0.80),
        ("storms roll in across the land", BARLOW, 64, 0.12, 0.865)],
    "t6_towns": [("TOWNS THAT LIVE", CINZEL, 110, 0.3, 0.80),
        ("markets, crafts and people with their own lives", BARLOW, 64, 0.12, 0.865)],
    "t7_sail": [("SAIL  ·  BUILD  ·  EXPLORE", CINZEL, 120, 0.3, 0.47)],
    "t8_title": [("PROCEDURAL WORLD", CINZEL, 230, 0.22, 0.46),
        ("FREE AND OPEN SOURCE", BARLOW, 70, 0.4, 0.575)],
}


def draw_tracked(d, xy, text, font, tracking, fill):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=font, fill=fill)
        x += font.getlength(ch) + font.size * tracking


def tracked_width(text, font, tracking):
    return sum(font.getlength(ch) for ch in text) + font.size * tracking * (len(text) - 1)


def card(lines):
    text = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(text)
    for t, face, size, tr, yf in lines:
        f = ImageFont.truetype(face, size)
        w = tracked_width(t, f, tr)
        asc, desc = f.getmetrics()
        draw_tracked(d, ((W - w) / 2, H * yf - (asc + desc) / 2), t, f, tr, 255)
    # A wide soft shadow under the letters keeps them readable over bright sky.
    shadow = text.filter(ImageFilter.GaussianBlur(22)).point(lambda v: min(255, int(v * 1.6)))
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    img.paste((0, 0, 0, 255), (0, 0), shadow.point(lambda v: int(v * 0.55)))
    img.paste((246, 238, 224, 255), (0, 0), text)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    for name, lines in CARDS.items():
        if only and name not in only:
            continue
        card(lines).save(os.path.join(OUT, name + ".png"), optimize=True)
        print("wrote", name)


if __name__ == "__main__":
    main()
