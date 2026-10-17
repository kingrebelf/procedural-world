#!/usr/bin/env python3
"""Synthesises the game's own ambience loops and a few one-shots (wind, water,
birds, crickets, fantasy chimes, sci-fi hum, swing whoosh, splashes) with numpy and
encodes them to Ogg Vorbis with ffmpeg. Everything here is generated from noise and
sine waves, so it is ours to license (CC0, like the rest of the audio).

Loops are built so they wrap seamlessly: noise beds are shaped in the frequency domain
of one whole loop (circular), modulations use whole cycles per loop, and scattered
events wrap around the end.

    python3 tools/synth_ambience.py assets/audio
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 32000
rng = np.random.default_rng(1729)


def shaped_noise(n, lo, hi, tilt=0.0, ch=2):
    """Band-limited noise of length n (circular, so it loops). tilt < 0 darkens."""
    out = []
    f = np.fft.rfftfreq(n, 1 / SR)
    for _ in range(ch):
        spec = np.fft.rfft(rng.standard_normal(n))
        g = np.zeros_like(f)
        band = (f >= lo) & (f <= hi)
        g[band] = 1.0
        # soft edges
        g = np.convolve(g, np.hanning(64) / np.hanning(64).sum(), mode="same")
        g *= np.where(f > 0, (np.maximum(f, 1) / 1000.0) ** tilt, 0)
        x = np.fft.irfft(spec * g, n)
        out.append(x / (np.abs(x).max() + 1e-9))
    return np.stack(out, 1)


def lfo(n, cycles, phase=0.0):
    t = np.arange(n) / n
    return np.sin(2 * np.pi * (cycles * t + phase))


def slow_mod(n, k=6, depth=1.0):
    """Sum of a few whole-cycle sinusoids: a smooth random envelope that loops."""
    m = np.zeros(n)
    for _ in range(k):
        m += lfo(n, int(rng.integers(1, 9)), rng.random()) * rng.random()
    m /= np.abs(m).max() + 1e-9
    return 1.0 + depth * m


def place(buf, ev, at, gain=1.0, pan=0.0):
    """Adds a mono event into stereo buf at sample `at`, wrapping round the end."""
    n = len(buf)
    l, r = np.sqrt(0.5 * (1 - pan)), np.sqrt(0.5 * (1 + pan))
    idx = (at + np.arange(len(ev))) % n
    np.add.at(buf[:, 0], idx, ev * gain * l)
    np.add.at(buf[:, 1], idx, ev * gain * r)


def norm(x, peak=0.7):
    return x * (peak / (np.abs(x).max() + 1e-9))


def wind(sec, strong=False):
    n = int(sec * SR)
    if strong:
        bed = shaped_noise(n, 60, 2600, tilt=-0.9)
        whistle = shaped_noise(n, 700, 1500, tilt=0.0)
        g = slow_mod(n, 8, 0.75)[:, None]
        g2 = np.clip(slow_mod(n, 6, 1.0) - 0.6, 0, None)[:, None]
        x = bed * g + whistle * g2 * 0.35
    else:
        bed = shaped_noise(n, 40, 1400, tilt=-1.1)
        x = bed * slow_mod(n, 6, 0.6)[:, None]
    return norm(x, 0.6)


def water(sec):
    n = int(sec * SR)
    bed = shaped_noise(n, 150, 5000, tilt=-0.5) * 0.5
    # babble: lots of short resonant bubbles
    bub = np.zeros((n, 2))
    for _ in range(int(sec * 45)):
        f0 = rng.uniform(400, 1800)
        d = rng.uniform(0.01, 0.05)
        t = np.arange(int(d * SR)) / SR
        f = f0 * (1 + 1.8 * t / d)  # rising pitch, like a real bubble
        ev = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / (d * 0.35))
        place(bub, ev, int(rng.integers(n)), rng.uniform(0.05, 0.25), rng.uniform(-0.8, 0.8))
    x = bed * slow_mod(n, 5, 0.25)[:, None] + bub
    return norm(x, 0.6)


def surf(sec, waves=4):
    """Sea shore: swells of broadband noise that break and hiss back out."""
    n = int(sec * SR)
    bed = shaped_noise(n, 60, 7000, tilt=-0.7)
    hiss = shaped_noise(n, 1500, 9000, tilt=-0.2)
    t = np.arange(n) / n
    ph = (t * waves + 0.1 * np.sin(2 * np.pi * 2 * t)) % 1.0
    swell = np.where(ph < 0.55, (ph / 0.55) ** 2, np.exp(-(ph - 0.55) / 0.12))
    wash = np.where(ph < 0.55, 0.0, np.exp(-(ph - 0.6) ** 2 / 0.02))
    x = bed * (0.15 + swell)[:, None] + hiss * (wash * 0.5)[:, None]
    return norm(x, 0.6)


def bird_call(kind):
    """One bird phrase: a few FM chirps or a warble."""
    parts = []
    if kind == 0:  # descending whistles
        for i in range(int(rng.integers(2, 5))):
            d = rng.uniform(0.08, 0.18)
            t = np.arange(int(d * SR)) / SR
            f = rng.uniform(2600, 4200) * (1 - 0.35 * t / d)
            env = np.sin(np.pi * t / d) ** 2
            parts.append(np.sin(2 * np.pi * np.cumsum(f) / SR) * env)
            parts.append(np.zeros(int(rng.uniform(0.04, 0.1) * SR)))
    elif kind == 1:  # trill
        d = rng.uniform(0.4, 0.9)
        t = np.arange(int(d * SR)) / SR
        rate = rng.uniform(18, 30)
        f = rng.uniform(3000, 5000) + 500 * np.sin(2 * np.pi * rate * t)
        env = np.sin(np.pi * t / d) * (0.6 + 0.4 * np.sin(2 * np.pi * rate * t))
        parts.append(np.sin(2 * np.pi * np.cumsum(f) / SR) * env)
    else:  # two-note call (cuckoo-ish, high)
        base = rng.uniform(1500, 2400)
        for f0 in (base * 1.26, base):
            d = rng.uniform(0.18, 0.28)
            t = np.arange(int(d * SR)) / SR
            env = np.minimum(1, t / 0.02) * np.exp(-t / (d * 0.6))
            parts.append((np.sin(2 * np.pi * f0 * t) + 0.2 * np.sin(4 * np.pi * f0 * t)) * env)
            parts.append(np.zeros(int(0.12 * SR)))
    return np.concatenate(parts)


def birds(sec):
    n = int(sec * SR)
    x = np.zeros((n, 2))
    # a handful of "individuals", each with its own call, repeating at its own pace
    for b in range(7):
        kind = b % 3
        call = bird_call(kind)
        pan = rng.uniform(-0.9, 0.9)
        gain = rng.uniform(0.15, 0.5)
        tpos = rng.uniform(0, sec)
        while tpos < sec + 0.0:
            place(x, call * rng.uniform(0.7, 1.0), int(tpos * SR), gain, pan)
            tpos += rng.uniform(2.5, 9.0)
    # a faint leafy breeze under them
    x += shaped_noise(n, 300, 6000, tilt=-0.6) * slow_mod(n, 4, 0.5)[:, None] * 0.03
    return norm(x, 0.55)


def crickets(sec):
    n = int(sec * SR)
    x = np.zeros((n, 2))
    for c in range(6):
        f0 = rng.uniform(3800, 5200)
        pulse_d = 0.012
        t = np.arange(int(pulse_d * SR)) / SR
        pulse = np.sin(2 * np.pi * f0 * t) * np.sin(np.pi * t / pulse_d)
        # a chirp = 3-5 pulses; chirps repeat at a steady per-cricket rate (whole count per loop)
        npulse = int(rng.integers(3, 6))
        chirp = np.concatenate([np.concatenate([pulse, np.zeros(int(0.008 * SR))]) for _ in range(npulse)])
        count = int(sec * rng.uniform(1.2, 2.6))
        pan = rng.uniform(-0.9, 0.9)
        gain = rng.uniform(0.2, 0.6)
        off = rng.integers(n)
        for k in range(count):
            place(x, chirp, int(off + k * n / count), gain * rng.uniform(0.8, 1.0), pan)
    # distant chorus bed
    x += shaped_noise(n, 3500, 5500) * 0.025 * (1 + 0.5 * lfo(n, int(sec * 2)))[:, None]
    x += shaped_noise(n, 40, 600, tilt=-1.0) * 0.05
    return norm(x, 0.5)


PENTA = [0, 2, 4, 7, 9]


def chimes(sec):
    """Fantasy shimmer: soft bell tones on a pentatonic scale over an airy pad."""
    n = int(sec * SR)
    x = np.zeros((n, 2))
    for _ in range(int(sec * 0.9)):
        note = 72 + PENTA[int(rng.integers(5))] + 12 * int(rng.integers(0, 2))
        f0 = 440 * 2 ** ((note - 69) / 12)
        d = rng.uniform(2.0, 4.0)
        t = np.arange(int(d * SR)) / SR
        ev = (np.sin(2 * np.pi * f0 * t) + 0.3 * np.sin(2 * np.pi * f0 * 2.76 * t) * np.exp(-t * 3)
              + 0.15 * np.sin(2 * np.pi * f0 * 5.4 * t) * np.exp(-t * 6))
        ev *= np.minimum(1, t / 0.005) * np.exp(-t / (d * 0.3))
        place(x, ev, int(rng.integers(n)), rng.uniform(0.08, 0.25), rng.uniform(-0.9, 0.9))
    # pad: a few slowly beating sines (whole cycles per loop so it wraps)
    t = np.arange(n) / SR
    for note in (48, 55, 60, 64):
        f = 440 * 2 ** ((note - 69) / 12)
        f = round(f * sec) / sec
        for ch, det in ((0, -1), (1, 1)):
            fd = f + det / sec
            x[:, ch] += 0.05 * np.sin(2 * np.pi * fd * t) * (0.6 + 0.4 * lfo(n, 2, note / 10))
    x += shaped_noise(n, 2000, 9000) * 0.015
    return norm(x, 0.45)


def scifi_hum(sec):
    n = int(sec * SR)
    t = np.arange(n) / SR
    x = np.zeros((n, 2))
    for k, a in ((1, 0.5), (2, 0.25), (3, 0.12), (5, 0.06)):
        f = round(55 * k * sec) / sec
        x[:, 0] += a * np.sin(2 * np.pi * f * t)
        x[:, 1] += a * np.sin(2 * np.pi * (f + 1 / sec) * t + 0.4)
    x *= (0.8 + 0.2 * lfo(n, 3))[:, None]
    x += shaped_noise(n, 80, 900, tilt=-0.8) * 0.25 * slow_mod(n, 4, 0.4)[:, None]
    # occasional distant blips
    for _ in range(int(sec / 3)):
        f0 = rng.choice([880, 1175, 1320, 1760])
        d = 0.09
        tt = np.arange(int(d * SR)) / SR
        ev = np.sin(2 * np.pi * f0 * tt) * np.exp(-tt * 30)
        place(x, ev, int(rng.integers(n)), 0.05, rng.uniform(-0.9, 0.9))
    return norm(x, 0.5)


def whoosh(var):
    d = 0.28 + 0.05 * var
    n = int(d * SR)
    t = np.arange(n) / n
    x = shaped_noise(n, 200, 6000, tilt=-0.4, ch=1)[:, 0]
    # sweep a band-pass by mixing two filtered copies with a moving crossfade
    hi = shaped_noise(n, 1500, 7000, ch=1)[:, 0]
    sweep = np.sin(np.pi * t) ** 2
    y = (x * (1 - t) + hi * t) * sweep * np.exp(-((t - 0.45) ** 2) / 0.05)
    return norm(y, 0.6)


def splash(var):
    d = 0.5 + 0.15 * var
    n = int(d * SR)
    t = np.arange(n) / SR
    x = shaped_noise(n, 300, 7000, tilt=-0.3, ch=1)[:, 0] * np.exp(-t / (0.08 + 0.03 * var))
    bub = np.zeros((n, 2))
    for _ in range(25):
        f0 = rng.uniform(500, 2000)
        dd = rng.uniform(0.01, 0.04)
        tt = np.arange(int(dd * SR)) / SR
        ev = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 2 * tt / dd)) / SR) * np.exp(-tt / (dd * 0.3))
        place(bub, ev, int(rng.uniform(0.02, 0.35) * SR), rng.uniform(0.1, 0.3))
    return norm(x + bub[:, 0], 0.6)


def write_ogg(path, data, q):
    data = np.asarray(data, dtype=np.float64)
    if data.ndim == 1:
        data = data[:, None]
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(pcm.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q), path], check=True)
    os.unlink(tmp)
    print(path, os.path.getsize(path))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/audio"
    amb = os.path.join(out, "ambience")
    write_ogg(os.path.join(amb, "wind.ogg"), wind(24), 1)
    write_ogg(os.path.join(amb, "wind_strong.ogg"), wind(24, True), 1)
    write_ogg(os.path.join(amb, "water.ogg"), water(16), 2)
    write_ogg(os.path.join(amb, "surf.ogg"), surf(28), 1)
    write_ogg(os.path.join(amb, "birds.ogg"), birds(36), 2)
    write_ogg(os.path.join(amb, "crickets.ogg"), crickets(20), 2)
    write_ogg(os.path.join(amb, "fantasy.ogg"), chimes(32), 1)
    write_ogg(os.path.join(amb, "scifi.ogg"), scifi_hum(24), 1)
    sfx = os.path.join(out, "sfx")
    for i in range(3):
        write_ogg(os.path.join(sfx, "swing", "whoosh_%d.ogg" % i), whoosh(i), 3)
        write_ogg(os.path.join(sfx, "water", "splash_%d.ogg" % i), splash(i), 3)


if __name__ == "__main__":
    main()
