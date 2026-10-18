#!/usr/bin/env python3
"""Synthesises the fire sounds (FireSystem) with numpy and encodes them to Ogg Vorbis
with ffmpeg, like tools/synth_ambience.py: all from noise, so ours to license (CC0).

    sfx/fire/crackle.ogg    a burning building's crackle and pop (loops)
    sfx/fire/roar.ogg       the low roar of a big fire drawing air (loops)
    sfx/fire/catch_N.ogg    the soft whoomph of something catching
    sfx/fire/hiss_N.ogg     water on fire: a hiss and sizzle
    sfx/fire/collapse_N.ogg a burnt building falling in: crack, rumble, timbers
    sfx/fire/cannon_N.ogg   a cannon going off: the crack, the boom and its echo

    python3 tools/synth_fire.py assets/audio [only]   (only: write just names starting so)
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 32000
rng = np.random.default_rng(4111)


def band(n, lo, hi, ch=2, circular=True):
    """Band-limited noise of n samples (circular, so it loops), peak 1."""
    out = []
    f = np.fft.rfftfreq(n, 1 / SR)
    for _ in range(ch):
        spec = np.fft.rfft(rng.standard_normal(n))
        g = ((f >= lo) & (f <= hi)).astype(float)
        g = np.convolve(g, np.hanning(64) / np.hanning(64).sum(), mode="same")
        x = np.fft.irfft(spec * g, n)
        out.append(x / (np.abs(x).max() + 1e-9))
    return np.stack(out, 1)


def env_loop(n, k=6, depth=0.5):
    """A smooth random envelope made of whole cycles, so it loops."""
    t = np.arange(n) / n
    m = np.zeros(n)
    for _ in range(k):
        m += np.sin(2 * np.pi * (int(rng.integers(1, 12)) * t + rng.random())) * rng.random()
    m /= np.abs(m).max() + 1e-9
    return 1.0 + depth * m


def place(buf, ev, at, gain=1.0, pan=0.0):
    n = len(buf)
    l, r = np.sqrt(0.5 * (1 - pan)), np.sqrt(0.5 * (1 + pan))
    idx = (at + np.arange(len(ev))) % n
    buf[idx, 0] += ev * gain * l
    buf[idx, 1] += ev * gain * r


def pop(size):
    """One crackle: a click of wood splitting, a short burst of bright noise."""
    n = int(SR * (0.004 + 0.03 * size))
    e = np.exp(-np.linspace(0, 6 + 10 * (1 - size), n))
    x = rng.standard_normal(n)
    # Brighter for small pops, a woody body for the big ones.
    k = max(1, int(1 + size * 6))
    x = np.convolve(x, np.ones(k) / k, mode="same")
    return x * e


def norm(x, peak=0.7):
    return x / (np.abs(x).max() + 1e-9) * peak


def crackle(sec):
    n = int(SR * sec)
    # The steady hiss and flutter of flames.
    bed = band(n, 300, 5000) * 0.10 * env_loop(n, 8, 0.6)[:, None]
    bed += band(n, 60, 400) * 0.18 * env_loop(n, 5, 0.4)[:, None]
    # Pops and crackles, bunched in fits.
    fits = env_loop(n, 7, 0.9)
    i = 0
    while i < n:
        rate = 6 + 30 * max(0.0, fits[i] - 0.4)
        i += int(SR / rate * rng.exponential(1.0)) + 1
        if i >= n:
            break
        s = rng.random() ** 2.2
        place(bed, pop(s), i, 0.25 + 0.75 * s, rng.uniform(-0.8, 0.8))
    return norm(bed, 0.75)


def roar(sec):
    n = int(SR * sec)
    x = band(n, 25, 220) * env_loop(n, 6, 0.5)[:, None]
    x += band(n, 200, 900) * 0.25 * env_loop(n, 9, 0.7)[:, None]
    return norm(x, 0.8)


def catch(var):
    n = int(SR * 1.4)
    t = np.linspace(0, 1, n)
    e = np.minimum(t * 12, 1.0) * np.exp(-t * (3.5 + var))
    x = band(n, 40, 900 + 300 * var, circular=False) * e[:, None]
    x += band(n, 900, 6000, circular=False) * 0.2 * (e ** 2)[:, None]
    for i in range(12 + 4 * var):
        place(x, pop(rng.random() ** 2), int(rng.uniform(0.05, 0.9) * n), 0.3, rng.uniform(-0.6, 0.6))
    return norm(x, 0.7)


def hiss(var):
    n = int(SR * (1.3 + 0.3 * var))
    t = np.linspace(0, 1, n)
    e = np.minimum(t * 40, 1.0) * np.exp(-t * 3.0)
    x = band(n, 2500, 11000, circular=False) * e[:, None]
    # Sizzle: fast crackle as the water boils off.
    for i in range(60):
        place(x, pop(0.05) * 0.6, int((rng.random() ** 1.6) * n * 0.9), 0.4, rng.uniform(-0.7, 0.7))
    return norm(x, 0.6)


def collapse(var):
    n = int(SR * 4.5)
    t = np.linspace(0, 1, n)
    # The crack as it goes, the long rumble of it coming down, then settling.
    x = band(n, 20, 180, circular=False) * (np.minimum(t * 6, 1.0) * np.exp(-t * 2.2))[:, None] * 1.4
    x += band(n, 150, 1600, circular=False) * (np.minimum(t * 9, 1.0) * np.exp(-t * 3.0))[:, None] * 0.5
    place(x, pop(1.0) * 3.0, int(0.01 * n), 1.0, 0.0)
    for i in range(26 + 6 * var):
        at = int((0.1 + rng.random() ** 1.5 * 0.85) * n)
        place(x, pop(0.4 + 0.6 * rng.random()) * 2.0, at, 0.35 + 0.4 * rng.random(), rng.uniform(-0.8, 0.8))
    return norm(x, 0.85)


def cannon(var):
    n = int(SR * 3.6)
    t = np.arange(n) / SR
    # The sharp crack of the charge, a deep boom with a falling thump under it, then the
    # rolling echo back off the land.
    crack = band(n, 800, 9000, circular=False) * np.exp(-t * 60)[:, None]
    boom = band(n, 18, 160, circular=False) * (np.minimum(t * 400, 1.0) * np.exp(-t * (3.0 + 0.6 * var)))[:, None]
    f0 = 52 + 8 * var
    thump = np.sin(2 * np.pi * (f0 * t - 9 * t * t)) * np.exp(-t * 9)
    x = crack * 0.7 + boom * 1.6
    x[:, 0] += thump
    x[:, 1] += thump
    mid = band(n, 120, 1400, circular=False) * np.exp(-t * 7)[:, None] * 0.5
    x += mid
    for d, g in ((0.42 + 0.1 * var, 0.35), (0.95 + 0.15 * var, 0.2), (1.6, 0.1)):
        k = int(d * SR)
        echo = np.zeros_like(x)
        echo[k:] = x[: n - k]
        # Far echoes lose their top.
        for c in range(2):
            echo[:, c] = np.convolve(echo[:, c], np.ones(24) / 24, mode="same")
        x += echo * g * np.array([0.8, 1.0] if var % 2 else [1.0, 0.8])
    return norm(x, 0.95)


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
    root = sys.argv[1] if len(sys.argv) > 1 else "assets/audio"
    only = sys.argv[2] if len(sys.argv) > 2 else ""
    d = os.path.join(root, "sfx", "fire")

    def out(name, make, q):
        # Every sound is made either way, so the noise each one draws stays the same.
        data = make()
        if name.startswith(only):
            write_ogg(os.path.join(d, name), data, q)

    out("crackle.ogg", lambda: crackle(14), 2)
    out("roar.ogg", lambda: roar(12), 1)
    for i in range(3):
        out("catch_%d.ogg" % i, lambda: catch(i), 3)
        out("hiss_%d.ogg" % i, lambda: hiss(i), 3)
    for i in range(2):
        out("collapse_%d.ogg" % i, lambda: collapse(i), 3)
    for i in range(3):
        out("cannon_%d.ogg" % i, lambda: cannon(i), 4)


if __name__ == "__main__":
    main()
