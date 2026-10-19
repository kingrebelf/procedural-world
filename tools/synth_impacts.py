#!/usr/bin/env python3
"""Builds the blow and hit-marker sounds: Kenney CC0 impact samples layered with
synthesised parts that give them weight and character (a tool's steel ringing on rock,
the bite and hollow knock of an axe in wood, the thump of a blow landing on a body, the
tick, ping and thunk of the hit markers). Five variants each, mono Ogg Vorbis.

    python3 tools/synth_impacts.py /mnt/project-files/free_assets assets/audio

Writes sfx/hit/{wood,stone,metal,flesh,marker,marker_head,marker_kill}_N.ogg.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
IMPACT = "kenney_audio/impact-sounds/Audio/%s_%03d.ogg"
CHOP = "kenney_audio/rpg-audio/Audio/chop.ogg"


def load(src, path):
    """Decodes a sound to mono float at SR."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(src, path), "-ac", "1", "-ar", str(SR),
                          "-f", "f32le", "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def t_of(sec):
    return np.arange(int(sec * SR)) / SR


def band(x, lo, hi):
    """Band-pass by FFT with soft edges."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4) / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * g, n)


def noise(sec, lo, hi, rng):
    return band(rng.standard_normal(int(sec * SR)), lo, hi)


def modes(freqs, decays, gains, sec, rng):
    """A struck body ringing: decaying sines at its modes, each at a random phase."""
    t = t_of(sec)
    out = np.zeros_like(t)
    for f, d, g in zip(freqs, decays, gains):
        out += g * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi)) * np.exp(-t / d)
    return out


def thump(f0, f1, sec, decay):
    """A low knock whose pitch drops as it dies (a body taking a blow)."""
    t = t_of(sec)
    f = f1 + (f0 - f1) * np.exp(-t / (decay * 0.6))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)


def env(x, attack=0.001, decay=0.1):
    t = np.arange(len(x)) / SR
    return x * np.minimum(1.0, t / attack) * np.exp(-t / decay)


def repitch(x, k):
    """Plays x k times faster (higher and shorter)."""
    idx = np.arange(0, len(x) - 1, k)
    return np.interp(idx, np.arange(len(x)), x)


def mix(*parts):
    n = max(len(p[0]) + int(p[2] * SR) if len(p) > 2 else len(p[0]) for p in parts)
    out = np.zeros(n)
    for p in parts:
        x, g = p[0], p[1]
        at = int(p[2] * SR) if len(p) > 2 else 0
        out[at:at + len(x)] += g * x / (np.abs(x).max() + 1e-9)
    return out


def finish(x, peak=0.9, tail=0.004):
    """Normalises, trims the silent end and fades the last few ms."""
    x = x * (peak / (np.abs(x).max() + 1e-9))
    loud = np.nonzero(np.abs(x) > 0.002)[0]
    x = x[:loud[-1] + 1] if len(loud) else x
    k = min(len(x), int(tail * SR))
    x[-k:] *= np.linspace(1, 0, k)
    return x


def crumble(sec, rng, grains=14, lo=900, hi=6000):
    """Grit and chips falling away: sparse short grains of noise."""
    out = np.zeros(int(sec * SR))
    for _ in range(grains):
        g = env(noise(0.03, lo, hi, rng), 0.0005, rng.uniform(0.003, 0.012))
        at = int(rng.uniform(0.01, sec - 0.04) * SR)
        out[at:at + len(g)] += g * rng.uniform(0.2, 1.0) * np.exp(-at / SR / (sec * 0.4))
    return out


def wood(src, i, rng):
    """An axe biting into wood: a sharp bite, the hollow knock of the trunk, splinters."""
    k = 1.0 + (i - 2) * 0.04
    body = repitch(load(src, IMPACT % ("impactWood_heavy", i)), k)
    chop = repitch(load(src, CHOP), 0.92 + 0.05 * i)
    bite = env(noise(0.05, 1800, 7000, rng), 0.0003, 0.006)
    f = rng.uniform(150, 190)
    knock = modes([f, f * 2.6, f * 4.4], [0.09, 0.05, 0.03], [1.0, 0.5, 0.25], 0.4, rng)
    return finish(mix((body, 1.0), (chop, 0.5), (bite, 0.3), (knock, 0.75), (crumble(0.3, rng, 8, 1500, 7000), 0.08, 0.012)))


def stone(src, i, rng):
    """A steel edge on rock: a bright clink of the steel, the dull crack of the rock and
    grit raining off it."""
    rock = load(src, IMPACT % ("impactMining", i))
    f = rng.uniform(2300, 2900)
    clink = modes([f, f * 1.47, f * 2.31, f * 3.07], [0.09, 0.06, 0.04, 0.025], [1.0, 0.6, 0.35, 0.2], 0.4, rng)
    crack = env(noise(0.12, 120, 1500, rng), 0.0005, 0.025)
    tick = env(noise(0.02, 3000, 12000, rng), 0.0002, 0.002)
    return finish(mix((rock, 1.0), (clink, 0.32), (crack, 0.6), (tick, 0.4), (crumble(0.45, rng, 18), 0.22, 0.015)))


def metal(src, i, rng):
    """Steel on metal: a hard clang that rings on."""
    hit = load(src, IMPACT % ("impactMetal_heavy", i))
    f = rng.uniform(420, 560)
    ring = modes([f, f * 2.32, f * 4.25, f * 6.63, f * 9.38], [0.5, 0.32, 0.2, 0.12, 0.07], [0.7, 1.0, 0.6, 0.35, 0.2], 1.0, rng)
    clang = env(noise(0.05, 1500, 9000, rng), 0.0003, 0.008)
    return finish(mix((hit, 1.0), (ring, 0.35), (clang, 0.4)))


def flesh(src, i, rng):
    """A blow landing on a body: a heavy dull thump with a slap on top."""
    punch = load(src, IMPACT % ("impactPunch_heavy", i))
    low = thump(rng.uniform(120, 150), 50, 0.3, 0.09)
    slap = env(noise(0.06, 500, 3500, rng), 0.0005, 0.012)
    return finish(mix((punch, 1.0), (low, 0.8), (slap, 0.3)))


def marker(i, rng):
    """The hit marker: a crisp, dry tick, short enough not to blur into the next."""
    f = rng.uniform(3000, 3400)
    tick = modes([f, f * 1.73], [0.025, 0.014], [1.0, 0.5], 0.14, rng)
    click = env(noise(0.02, 2000, 9000, rng), 0.0002, 0.0025)
    body = env(noise(0.05, 400, 1600, rng), 0.0005, 0.012)
    return finish(mix((tick, 1.0), (click, 0.7), (body, 0.35)), 0.8)


def marker_head(i, rng):
    """A headshot: a bright ringing ping, like a blow on a helmet, over a hard click."""
    f = rng.uniform(1850, 2050)
    ping = modes([f, f * 2.76, f * 5.40, f * 8.93], [0.22, 0.12, 0.06, 0.03], [1.0, 0.55, 0.3, 0.12], 0.6, rng)
    click = env(noise(0.02, 2500, 12000, rng), 0.0002, 0.003)
    knock = thump(700, 380, 0.08, 0.02)
    return finish(mix((ping, 1.0), (click, 0.8), (knock, 0.35)), 0.85)


def marker_kill(i, rng):
    """A kill: a deep, final thunk with a lower ring."""
    low = thump(170, 60, 0.4, 0.12)
    f = rng.uniform(980, 1100)
    ring = modes([f, f * 2.76, f * 5.40], [0.25, 0.12, 0.05], [1.0, 0.4, 0.15], 0.6, rng)
    click = env(noise(0.02, 2000, 9000, rng), 0.0002, 0.003)
    return finish(mix((low, 1.0), (ring, 0.45), (click, 0.6)), 0.85)


def write_ogg(path, data, q=4):
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q), path], check=True)
    os.unlink(tmp)
    print(path, os.path.getsize(path))


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "/mnt/project-files/free_assets"
    out = os.path.join(sys.argv[2] if len(sys.argv) > 2 else "assets/audio", "sfx", "hit")
    rng = np.random.default_rng(4242)
    for i in range(5):
        write_ogg(os.path.join(out, "wood_%d.ogg" % i), wood(src, i, rng))
        write_ogg(os.path.join(out, "stone_%d.ogg" % i), stone(src, i, rng))
        write_ogg(os.path.join(out, "metal_%d.ogg" % i), metal(src, i, rng))
        write_ogg(os.path.join(out, "flesh_%d.ogg" % i), flesh(src, i, rng))
        write_ogg(os.path.join(out, "marker_%d.ogg" % i), marker(i, rng))
        write_ogg(os.path.join(out, "marker_head_%d.ogg" % i), marker_head(i, rng))
        write_ogg(os.path.join(out, "marker_kill_%d.ogg" % i), marker_kill(i, rng))


if __name__ == "__main__":
    main()
