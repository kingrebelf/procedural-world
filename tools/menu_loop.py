"""Cuts the title screen's background loop (assets/video/menu_loop.ogv, played by
src/ui/main_menu.gd) from the trailer's takes: a few calm shots of the world, without
titles or sound, dissolving into each other and from the last back into the first so it
loops without a seam.

    python3 tools/menu_loop.py TAKES_DIR [--out menu_loop.ogv] [--run]

--station writes tools/trailer_cut/loop.cmd, run from the trailer folder on the render
station next to the 4K takes. Godot plays only Ogg Theora, hence the format.
"""
import os
import shlex
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FPS = 30
W, H = 1920, 1080
X = 1.0  ## dissolve, seconds
## (take, second to start at, seconds shown): calm moving shots, no weather or night.
SHOTS = [
    ("fly_rainforest", 1.5, 5.0),
    ("lake_glide", 1.5, 5.0),
    ("town_flyin", 2.0, 5.0),
    ("cog_orbit", 2.0, 5.0),
    ("fly_gorge", 1.5, 5.0),
    ("village_sunset", 2.5, 5.0),
]


def build(takes, out):
    inputs, lines = [], []
    n = len(SHOTS)
    # The first shot starts X seconds in: its first X seconds are what the last shot
    # dissolves into at the end, so the last frame runs straight on into the first.
    for i, (take, at, ln) in enumerate(SHOTS):
        start = at + (X if i == 0 else 0.0)
        inputs += ["-ss", "%.3f" % start, "-t", "%.3f" % (ln + X), "-i", os.path.join(takes, take + ".mp4")]
    take0, at0, _ = SHOTS[0]
    inputs += ["-ss", "%.3f" % at0, "-t", "%.3f" % X, "-i", os.path.join(takes, take0 + ".mp4")]
    for i in range(n + 1):
        lines.append("[%d:v]scale=%d:%d:flags=lanczos,fps=%d,format=yuv420p,setpts=PTS-STARTPTS,settb=1/%d[c%d]" % (i, W, H, FPS, FPS, i))
    t, prev = 0.0, "c0"
    for i in range(1, n + 1):
        t += SHOTS[i - 1][2]
        lines.append("[%s][c%d]xfade=transition=fade:duration=%.3f:offset=%.3f[v%d]" % (prev, i, X, t, i))
        prev = "v%d" % i
    total = t + X
    lines.append("[%s]null[vout]" % prev)
    args = ["ffmpeg", "-y", "-hide_banner"] + inputs + ["-filter_complex", ";".join(lines), "-map", "[vout]", "-an",
            "-c:v", "libtheora", "-b:v", "3000k", "-g", "60", "-r", str(FPS), out]
    return args, total


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        sys.exit(1)
    takes = a[0]
    out = a[a.index("--out") + 1] if "--out" in a else os.path.join(takes, "menu_loop.ogv")
    if "--station" in a:
        takes, out = ".", "menu_loop.ogv"
    args, total = build(takes, out)
    print("loop: %.1f s" % total)
    if "--station" in a:
        cut = os.path.join(ROOT, "tools", "trailer_cut")
        os.makedirs(cut, exist_ok=True)
        with open(os.path.join(cut, "loop.cmd"), "w", newline="\r\n") as f:
            f.write("@echo off\n" + " ".join('"%s"' % x if (" " in x or ";" in x or "[" in x) else x for x in args) + "\n")
    if "--run" in a:
        os.execvp("ffmpeg", args)
    print(" ".join(shlex.quote(x) for x in args))


if __name__ == "__main__":
    main()
