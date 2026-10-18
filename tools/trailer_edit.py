"""Cuts the trailer from the takes tools/trailer.gd rendered, with the title cards
(tools/trailer_titles.py), the music and a little of the game's own sound.

    python3 tools/trailer_edit.py EDL.json TAKES_DIR [--out trailer.mp4] [--cmd edit.cmd] [--run]

The EDL (tools/trailer_edl.json) lists the clips in order (take, the second of the take
to start at, length, and the dissolve into the next), the title cards with their times,
and the music (file, where in it to start, fade out). This writes an ffmpeg filter script
next to the takes and the command that runs it, as a .cmd for Windows (the render station
runs it there, with NVENC) or runs it here with --run (libx264, for checks).
"""
import json
import os
import shlex
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def build(edl, takes, out, nvenc):
    fps = edl.get("fps", 60)
    w, h = edl.get("size", [3840, 2160])
    inputs = []
    lines = []
    clips = edl["clips"]
    # Each clip: its stretch of the take, at the trailer's size and rate.
    for i, c in enumerate(clips):
        inputs += ["-ss", "%.3f" % c.get("in", 0.0), "-t", "%.3f" % (c["len"] + c.get("x", 0.0)),
                   "-i", os.path.join(takes, c["take"] + ".mp4")]
        grade = c.get("grade", "")
        lines.append("[%d:v]scale=%d:%d:flags=lanczos,fps=%d,format=yuv420p10le,setpts=PTS-STARTPTS%s[c%d]"
                     % (i, w, h, fps, ("," + grade) if grade else "", i))
    # Dissolves (or cuts, x = 0) from each clip into the next.
    t = clips[0]["len"]
    prev = "c0"
    for i in range(1, len(clips)):
        x = clips[i - 1].get("x", 0.0)
        kind = clips[i - 1].get("xkind", "fade")
        name = "v%d" % i
        if x > 0:
            lines.append("[%s][c%d]xfade=transition=%s:duration=%.3f:offset=%.3f[%s]" % (prev, i, kind, x, t, name))
        else:
            lines.append("[%s][c%d]concat=n=2:v=1:a=0[%s]" % (prev, i, name))
        t += clips[i]["len"]
        prev = name
    total = t + clips[-1].get("x", 0.0)
    # Title cards, faded in and out over the footage.
    n = len(clips)
    for j, tc in enumerate(edl.get("titles", [])):
        inputs += ["-loop", "1", "-t", "%.3f" % total, "-i", os.path.join(ROOT, "tools", "trailer_titles", tc["card"] + ".png")]
        k = n + j
        fi, fo = tc.get("fade", [0.6, 0.6])
        lines.append("[%d:v]format=rgba,fade=t=in:st=%.3f:d=%.3f:alpha=1,fade=t=out:st=%.3f:d=%.3f:alpha=1,scale=%d:%d[t%d]"
                     % (k, tc["at"], fi, tc["at"] + tc["len"] - fo, fo, w, h, j))
        lines.append("[%s][t%d]overlay=shortest=0:enable='between(t,%.3f,%.3f)'[o%d]" % (prev, j, tc["at"], tc["at"] + tc["len"], j))
        prev = "o%d" % j
    # Fade from and to black.
    fin, fout = edl.get("fade", [0.5, 1.5])
    lines.append("[%s]fade=t=in:st=0:d=%.3f,fade=t=out:st=%.3f:d=%.3f[vout]" % (prev, fin, total - fout, fout))
    # Music, then the game's own sounds laid under it (rain, thunder) at their times.
    m = edl["music"]
    k = n + len(edl.get("titles", []))
    inputs += ["-ss", "%.3f" % m.get("in", 0.0), "-i", m["file"]]
    mixes = ["[%d:a]atrim=0:%.3f,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=%.3f,afade=t=out:st=%.3f:d=%.3f,volume=%.2f[mus]"
             % (k, total, m.get("fade_in", 0.0), total - m.get("fade_out", 3.0), m.get("fade_out", 3.0), m.get("gain", 1.0))]
    labels = ["[mus]"]
    for s, sfx in enumerate(edl.get("sfx", [])):
        path = sfx["file"] if os.path.isabs(sfx["file"]) else os.path.join(ROOT, sfx["file"])
        if not os.path.exists(path):
            print("no sound", path, "- left out")
            continue
        k += 1
        inputs += ["-i", path]
        ms = int(sfx["at"] * 1000)
        mixes.append("[%d:a]atrim=0:%.3f,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.3,afade=t=out:st=%.3f:d=0.6,volume=%.2f,adelay=%d|%d[s%d]"
                     % (k, sfx["len"], max(0.0, sfx["len"] - 0.6), sfx.get("gain", 0.5), ms, ms, s))
        labels.append("[s%d]" % s)
    lines += mixes
    lines.append("%samix=inputs=%d:normalize=0:duration=first,alimiter=limit=0.95[aout]" % ("".join(labels), len(labels)))
    if nvenc:
        enc = ["-c:v", "hevc_nvenc", "-preset", "p7", "-tune", "hq", "-rc", "vbr", "-cq", "17", "-b:v", "0",
               "-maxrate", "120M", "-bufsize", "240M", "-profile:v", "main10", "-pix_fmt", "p010le", "-tag:v", "hvc1"]
    else:
        enc = ["-c:v", "libx264", "-crf", "20", "-preset", "medium", "-pix_fmt", "yuv420p"]
    script = os.path.join(takes, "trailer_filter.txt")
    with open(script, "w") as f:
        f.write(";\n".join(lines) + "\n")
    args = ["ffmpeg", "-y", "-hide_banner"] + inputs + ["-filter_complex_script", script, "-map", "[vout]", "-map", "[aout]"] \
        + enc + ["-c:a", "aac", "-b:a", "320k", "-r", str(fps), "-movflags", "+faststart", out]
    return args, total


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        print(__doc__)
        sys.exit(1)
    edl = json.load(open(a[0]))
    takes = a[1]
    out = a[a.index("--out") + 1] if "--out" in a else os.path.join(takes, "trailer.mp4")
    run = "--run" in a
    args, total = build(edl, takes, out, not run)
    print("trailer: %.1f s" % total)
    if "--cmd" in a:
        with open(a[a.index("--cmd") + 1], "w", newline="\r\n") as f:
            f.write("@echo off\n" + " ".join('"%s"' % x if (" " in x or "'" in x) else x for x in args) + "\n")
    if run:
        os.execvp("ffmpeg", args)
    print(" ".join(shlex.quote(x) for x in args))


if __name__ == "__main__":
    main()
