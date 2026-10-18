#!/usr/bin/env python3
"""Synthesises the pop of a log in a fire (FireFx.Pops) with numpy and encodes it to Ogg
Vorbis with ffmpeg, like tools/synth_fire.py: all from noise, so ours to license (CC0).

    sfx/fire/pop_N.ogg   a log popping: a sharp crack of sap bursting, the knock of the
                         wood round it, a few small crackles after and a faint hiss

    python3 tools/synth_fire_pops.py assets/audio
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 32000
rng = np.random.default_rng(5233)


def lowpass(x, k):
    return np.convolve(x, np.ones(k) / k, mode="same") if k > 1 else x


def click(n, decay, k):
    e = np.exp(-np.linspace(0, decay, n))
    return lowpass(rng.standard_normal(n), k) * e


def pop(var):
    n = int(SR * 0.7)
    x = np.zeros(n)
    at = int(SR * 0.01)
    # The crack: a very short bright burst...
    c = click(int(SR * (0.006 + 0.004 * var)), 9.0, 1)
    x[at:at + len(c)] += c * 1.0
    # ...and the knock of the log round it, a damped low thump.
    m = int(SR * 0.09)
    t = np.arange(m) / SR
    f = 140 + 60 * rng.random()
    body = np.sin(2 * np.pi * f * t * (1 - 0.6 * t / t[-1])) * np.exp(-t * 45)
    body += lowpass(rng.standard_normal(m), 12) * np.exp(-t * 60) * 0.6
    x[at:at + m] += body * 0.55
    # A few small crackles after, as the burst sap spits.
    for _ in range(int(2 + rng.integers(0, 4))):
        o = at + int(SR * (0.03 + rng.random() ** 1.6 * 0.4))
        s = click(int(SR * (0.002 + 0.005 * rng.random())), 7.0, int(1 + rng.integers(0, 3)))
        x[o:o + len(s)] += s * (0.12 + 0.25 * rng.random())
    # A faint sizzle of steam from the split.
    h = int(SR * 0.35)
    hs = rng.standard_normal(h) - lowpass(rng.standard_normal(h), 6)
    env = np.exp(-np.linspace(0, 5, h)) * np.minimum(1, np.linspace(0, 8, h))
    x[at:at + h] += hs * env * 0.05
    x /= np.abs(x).max() + 1e-9
    x *= 0.8
    # A touch of width: the right a sample or two late.
    d = int(1 + var)
    return np.stack([x, np.concatenate([np.zeros(d), x[:-d]])], 1)


def write_ogg(path, data, q):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav = tmp.name
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(q), path], check=True)
    os.remove(wav)


def main():
    d = os.path.join(sys.argv[1] if len(sys.argv) > 1 else "assets/audio", "sfx", "fire")
    for i in range(4):
        write_ogg(os.path.join(d, "pop_%d.ogg" % i), pop(i), 4)


if __name__ == "__main__":
    main()
