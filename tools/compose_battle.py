#!/usr/bin/env python3
"""Composes and renders the game's own orchestral battle music: an original dark
march for horns, trumpets, trombones, tuba, strings, timpani and snare. The notes are
written out below and played through the VS Chamber Orchestra 2 Community Edition
samples (CC0, https://github.com/sgossner/VSCO-2-CE), so the result is ours and CC0
like the rest of the audio. It is not based on any existing piece.

The samples are not in the repo. Clone the library's master branch (the samples) and
its SFZ branch (the key maps), then:

    python3 tools/compose_battle.py VSCO-2-CE/ VSCO-2-CE-sfz/ assets/audio
    python3 tools/compose_battle.py VSCO-2-CE/ VSCO-2-CE-sfz/ assets/audio war_march

Each cue loops seamlessly: the reverb tail and any note ringing past the end wrap
round to the start, and the last bar leads back into the first.
"""
import os
import re
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy.signal import fftconvolve, lfilter, resample_poly

SR = 44100
rng = np.random.default_rng(1977)

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def key_num(s):
    """SFZ key: a number or a name like c#4 (C4 = 60)."""
    s = s.strip()
    if s.lstrip("-").isdigit():
        return int(s)
    m = re.match(r"([a-gA-G])([#b]?)(-?\d+)", s)
    n = NOTE[m.group(1).upper()] + {"#": 1, "b": -1, "": 0}[m.group(2)]
    return n + 12 * (int(m.group(3)) + 1)


def midi(name):
    """'D4' -> 62, 'Bb2' -> 46, 'F#3' -> 54."""
    m = re.match(r"([A-G])([#b]?)(-?\d)", name)
    return NOTE[m.group(1)] + {"#": 1, "b": -1, "": 0}[m.group(2)] + 12 * (int(m.group(3)) + 1)


def read_wav(path):
    with wave.open(path) as w:
        ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width == 2:
        x = np.frombuffer(raw, "<i2").astype(np.float32) / 32768.0
    elif width == 3:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3)
        x = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
        x = np.where(x >= 1 << 23, x - (1 << 24), x).astype(np.float32) / float(1 << 23)
    else:
        x = np.frombuffer(raw, "<i4").astype(np.float32) / float(1 << 31)
    x = x.reshape(-1, ch)
    if ch == 1:
        x = np.repeat(x, 2, axis=1)
    x = x[:, :2]
    if rate != SR:
        x = resample_poly(x, SR, rate, axis=0).astype(np.float32)
    return x


class Instrument:
    """One SFZ patch: regions with key and velocity ranges."""

    def __init__(self, sfz_dir, lib_dir, name, pan=0.0, width=0.5):
        self.regions = []
        self.width = width
        self.lib = lib_dir
        self.gain = 1.0
        self.pan = pan
        self.cache = {}
        text = open(os.path.join(sfz_dir, name), encoding="utf-8", errors="ignore").read()
        text = re.sub(r"//[^\n]*", "", text)
        default_path = ""
        glob, group, region = {}, {}, None
        for tok in re.split(r"(<\w+>)", text):
            tok = tok.strip()
            if not tok:
                continue
            if tok.startswith("<"):
                if region is not None:
                    self._add(region, default_path)
                region = None
                if tok == "<group>":
                    group = {}
                    cur = group
                elif tok == "<region>":
                    region = {}
                    cur = region
                elif tok == "<global>":
                    cur = glob
                else:
                    cur = {}
                continue
            for line in tok.splitlines():
                line = line.strip()
                if "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip()
                if k == "default_path":
                    default_path = v.replace("\\", "/")
                    continue
                if region is not None:
                    region[k] = v
                elif cur is group:
                    group[k] = v
                else:
                    glob[k] = v
            if region is not None:
                region["__inherit"] = {**glob, **group}
        if region is not None:
            self._add(region, default_path)

    def _add(self, r, path):
        o = {**r.pop("__inherit", {}), **r}
        if "sample" not in o:
            return
        if "key" in o:
            o.setdefault("lokey", o["key"])
            o.setdefault("hikey", o["key"])
            o.setdefault("pitch_keycenter", o["key"])
        lo = key_num(o.get("lokey", "0"))
        hi = key_num(o.get("hikey", "127"))
        self.regions.append({
            "file": os.path.join(self.lib, path, o["sample"].replace("\\", "/")),
            "lo": lo, "hi": hi,
            "center": key_num(o.get("pitch_keycenter", str(lo))),
            "lovel": int(o.get("lovel", 0)), "hivel": int(o.get("hivel", 127)),
            "vol": 10 ** (float(o.get("volume", 0)) / 20),
            "tune": float(o.get("tune", 0)) / 100.0,
        })

    def level_to(self, level_db, key):
        """Scales the patch so a velocity-100 note at key peaks (50 ms RMS) at level_db."""
        self.gain = 1.0
        y = self.note(key, 100, None).mean(axis=1)
        w = int(0.05 * SR)
        rms = np.sqrt(np.convolve(y ** 2, np.ones(w) / w, mode="valid").max())
        self.gain = 10 ** (level_db / 20) / max(rms, 1e-6)
        return self

    def pick(self, key, vel):
        ok = [r for r in self.regions if r["lo"] <= key <= r["hi"] and r["lovel"] <= vel <= r["hivel"]]
        if not ok:
            # out of range: the nearest key, then the closest velocity layer
            best = min(abs(min(max(key, r["lo"]), r["hi"]) - key) for r in self.regions)
            near = [r for r in self.regions if abs(min(max(key, r["lo"]), r["hi"]) - key) == best]
            dv = min(abs(min(max(vel, r["lovel"]), r["hivel"]) - vel) for r in near)
            ok = [r for r in near if abs(min(max(vel, r["lovel"]), r["hivel"]) - vel) == dv]
        return ok[rng.integers(len(ok))]

    def sample(self, f):
        if f not in self.cache:
            self.cache[f] = read_wav(f)
        return self.cache[f]

    def note(self, key, vel, dur=None, release=0.35):
        """A rendered note as a (n, 2) array. dur None plays the sample out."""
        r = self.pick(key, vel)
        x = self.sample(r["file"])
        ratio = 2 ** ((key - r["center"] - r["tune"]) / 12)
        want = len(x) / ratio if dur is None else min(len(x) / ratio, (dur + release) * SR)
        n = int(want)
        if n < 16:
            return np.zeros((16, 2), np.float32)
        pos = np.arange(n) * ratio
        y = np.stack([np.interp(pos, np.arange(len(x)), x[:, c]) for c in range(2)], axis=1)
        if dur is not None:
            env = np.ones(n, np.float32)
            a = int(dur * SR)
            if a < n:
                t = np.linspace(0, 1, n - a)
                env[a:] = 0.5 + 0.5 * np.cos(np.pi * t)
            y *= env[:, None]
        y[-64:] *= np.linspace(1, 0, 64)[:, None]
        # narrow the recorded stereo, then place the section on the stage
        mid, side = (y[:, 0] + y[:, 1]) * 0.5, (y[:, 0] - y[:, 1]) * 0.5 * self.width
        y = np.stack([mid + side, mid - side], axis=1)
        g = self.gain * r["vol"] * (vel / 100.0) ** 1.4
        lg, rg = np.cos((self.pan + 1) * np.pi / 4), np.sin((self.pan + 1) * np.pi / 4)
        return (y * g * np.array([lg, rg]) * 1.414).astype(np.float32)


class OneShots(Instrument):
    """Unpitched hits from plain files, picked by loudness."""

    def __init__(self, lib_dir, files, pan=0.0, width=0.5):
        self.lib, self.cache, self.pan, self.width, self.gain = lib_dir, {}, pan, width, 1.0
        self.regions = [{"file": os.path.join(lib_dir, f), "lo": 0, "hi": 127, "center": 60,
                         "lovel": lv, "hivel": hv, "vol": 1.0, "tune": 0.0} for f, lv, hv in files]


class Score:
    def __init__(self, bpm, bars, beats=4):
        self.beat = 60.0 / bpm
        self.bar = self.beat * beats
        self.length = bars * self.bar
        self.buses = {}

    def add(self, bus, inst, bar, beat, key, vel, beats=None, release=0.35, jitter=0.006):
        t = (bar * self.bar + beat * self.beat) + rng.normal(0, jitter)
        v = int(np.clip(vel + rng.normal(0, 4), 1, 127))
        y = inst.note(key, v, None if beats is None else beats * self.beat, release)
        buf = self.buses.setdefault(bus, np.zeros((int((self.length + 12) * SR), 2), np.float32))
        i = max(0, int(t * SR))
        n = min(len(y), len(buf) - i)
        buf[i:i + n] += y[:n]


def reverb_ir(seconds, damp_hz):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)).astype(np.float32) * np.exp(-6.9 * t / seconds)[:, None]
    a = np.exp(-2 * np.pi * damp_hz / SR)
    ir = lfilter([1 - a], [1, -a], ir, axis=0)
    ir[: int(0.018 * SR)] = 0  # pre-delay
    for d, g in [(0.011, 0.5), (0.019, 0.35), (0.027, 0.3), (0.041, 0.22)]:
        ir[int(d * SR), 0] += g
        ir[int((d + 0.003) * SR), 1] += g
    return ir / np.sqrt((ir ** 2).sum(axis=0).mean())


def master(score, wet_mix, target_lufs_rms=-21.5):
    total = None
    dry = None
    for bus, (buf, wet) in score.mixed.items():
        dry = buf if dry is None else dry + buf
    ir = reverb_ir(2.6, 3800)
    sends = sum(buf * wet for buf, wet in score.mixed.values())
    rev = np.stack([fftconvolve(sends[:, c], ir[:, c])[: len(sends)] for c in range(2)], axis=1)
    total = dry + rev * wet_mix
    # wrap the tail onto the start so the loop is seamless
    n = int(round(score.length * SR))
    out = total[:n].copy()
    tail = total[n:]
    m = min(len(tail), n)
    out[:m] += tail[:m]
    # gentle bus compression, then a soft ceiling
    env = np.sqrt(np.convolve((out ** 2).mean(axis=1), np.ones(2205) / 2205, mode="same")) + 1e-9
    ref = np.percentile(env, 70)
    over = np.maximum(env / ref, 1.0)
    out *= (over ** -0.3)[:, None]
    rms = np.sqrt((out ** 2).mean())
    out *= 10 ** (target_lufs_rms / 20) / rms
    out = np.tanh(out * 1.1) / 1.1
    peak = np.abs(out).max()
    if peak > 0.94:
        out *= 0.94 / peak
    return out


def encode(x, dst, q=3):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, "m.wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", str(q),
                        "-map_metadata", "-1", dst], check=True)


# --- The orchestra -------------------------------------------------------------------

def orchestra(sfz, lib):
    P = "Percussion/"
    o = {
        "horn": Instrument(sfz, lib, "FHornSus.sfz", -0.2),
        "horn_st": Instrument(sfz, lib, "FHornStac.sfz", -0.2),
        "tpt": Instrument(sfz, lib, "TrumpetSus.sfz", 0.25),
        "tpt_st": Instrument(sfz, lib, "TrumpetStac.sfz", 0.25),
        "tbn": Instrument(sfz, lib, "TromboneSus.sfz", 0.4),
        "tbn_st": Instrument(sfz, lib, "TromboneStac.sfz", 0.4),
        "tuba": Instrument(sfz, lib, "TubaSus.sfz", 0.15, 0.15),
        "tuba_st": Instrument(sfz, lib, "TubaStac.sfz", 0.15, 0.15),
        "vc_spic": Instrument(sfz, lib, "CelloEnsSpic.sfz", 0.3),
        "va_spic": Instrument(sfz, lib, "ViolaEnsSpic.sfz", 0.1),
        "cb_spic": Instrument(sfz, lib, "ContrabassSpic.sfz", 0.45),
        "vn_sus": Instrument(sfz, lib, "ViolinEnsSusVib.sfz", -0.4),
        "vn_trem": Instrument(sfz, lib, "ViolinEnsTrem.sfz", -0.4),
        "vc_sus": Instrument(sfz, lib, "CelloEnsSusVib.sfz", 0.3),
        "timp": Instrument(sfz, lib, "Timpani.sfz", 0.0),
        "timp_roll": Instrument(sfz, lib, "TimpaniRolls.sfz", 0.0),
        "snare": OneShots(lib, [(P + "Snare2-HitSN_v1_rr1_Sum.wav", 0, 40), (P + "Snare2-HitSN_v3_rr1_Sum.wav", 41, 70),
                                (P + "Snare2-HitSN_v5_rr1_Sum.wav", 71, 95), (P + "Snare2-HitSN_v7_rr1_Sum.wav", 96, 115),
                                (P + "Snare2-HitSN_v9_rr1_Sum.wav", 116, 127)], -0.15),
        "snare_roll": OneShots(lib, [(P + "Snare2-rollSN_v3_rr1_Sum.wav", 0, 90), (P + "Snare2-rollSN_v5_rr1_Sum.wav", 91, 127)], -0.15),
        "bass_drum": OneShots(lib, [(P + "BDrumNewhit_v3_rr1_Sum.wav", 0, 80), (P + "BDrumNewhit_v5_rr1_Sum.wav", 81, 110),
                                    (P + "BDrumNewhit_v7_rr1_Sum.wav", 111, 127)], 0.05),
        "crash": OneShots(lib, [(P + "cymbal-crash1_mf_rr1.wav", 0, 100), (P + "cymbal-crash1_ff_rr1.wav", 101, 127)], 0.35),
        "swell": OneShots(lib, [(P + "susCymb1-cresc-Short_v1.wav", 0, 127)], -0.3),
        "gong": OneShots(lib, [(P + "gongHit_f.wav", 0, 110), (P + "gongHit_fff.wav", 111, 127)], -0.2),
        "anvil": OneShots(lib, [(P + "Anvil_Hit1_v2_Sum.wav", 0, 100), (P + "Anvil_Hit1_v3_Sum.wav", 101, 127)], 0.5, 0.2),
    }
    for name, (level, key) in LEVELS.items():
        o[name].level_to(level, key)
    return o


# Loudest-moment level (dB) of a velocity-100 note at the given key: the mix balance.
LEVELS = {
    "horn": (-12, 62), "horn_st": (-13, 62), "tpt": (-13, 74), "tpt_st": (-14, 74),
    "tbn": (-14, 53), "tbn_st": (-13, 53), "tuba": (-14, 38), "tuba_st": (-14, 38),
    "vc_spic": (-13, 50), "va_spic": (-18, 62), "cb_spic": (-15, 38),
    "vn_sus": (-17, 74), "vn_trem": (-21, 81), "vc_sus": (-17, 50),
    "timp": (-10, 50), "timp_roll": (-15, 45), "snare": (-15, 60), "snare_roll": (-20, 60),
    "bass_drum": (-11, 60), "crash": (-15, 60), "swell": (-19, 60), "gong": (-13, 60), "anvil": (-17, 60),
}


# Chords as (bass root, triad tones above it in semitones)
MINOR, MAJOR = (0, 3, 7), (0, 4, 7)


def chord(name):
    q = MINOR if name.endswith("m") else MAJOR
    return midi(name.rstrip("m") + "2"), q


def mel(s):
    """'D4:1.5 A4:.5 -:1' -> [(key or None, beats)]"""
    out = []
    for tok in s.split():
        n, b = tok.split(":")
        out.append((None if n == "-" else midi(n), float(b)))
    return out


def play_line(sc, bus, inst, bar0, line, vel, shift=0, release=0.4, legato=1.0):
    beat = 0.0
    for key, b in line:
        if key is not None:
            sc.add(bus, inst, bar0, beat, key + shift, vel, b * legato, release)
        beat += b


def ostinato(sc, o, bar, root, vel, octave_up=False):
    """Driving low strings: eighths, accented, with a lift on the last two."""
    pat = [0, 0, 0, 0, 0, 0, 7, 0]
    acc = [1.0, .6, .75, .62, .92, .62, .85, .7]
    for i, (p, a) in enumerate(zip(pat, acc)):
        k = root + 12 + p  # cellos an octave above the bass root
        sc.add("strings", o["vc_spic"], bar, i * 0.5, k, int(vel * a), None)
        sc.add("strings", o["cb_spic"], bar, i * 0.5, k - 12, int(vel * a * 0.9), None)
        if octave_up:
            sc.add("strings", o["va_spic"], bar, i * 0.5, k + 12, int(vel * a * 0.8), None)


def snare_bar(sc, o, bar, vel, fill=False):
    pat = [1, 0, 0, 0, .5, 0, .6, 0, .9, 0, .45, .55, .65, 0, .5, .75]
    if fill:
        pat = [1, 0, .5, .5, .7, 0, .6, .6, .75, .5, .8, .55, .85, .7, .9, 1]
    for i, a in enumerate(pat):
        if a:
            sc.add("perc", o["snare"], bar, i * 0.25, 60, int(vel * a), None, jitter=0.004)


def drums_bar(sc, o, bar, root, vel, fifth=7):
    sc.add("perc", o["bass_drum"], bar, 0, 60, vel, None)
    sc.add("perc", o["bass_drum"], bar, 2, 60, int(vel * 0.8), None)
    timp_key = root + 12 if root + 12 <= 52 else root
    sc.add("perc", o["timp"], bar, 0, timp_key, vel, None)
    sc.add("perc", o["timp"], bar, 2, timp_key + fifth - 12 if timp_key + fifth > 55 else timp_key + fifth, int(vel * 0.75), None)


def brass_chord(sc, o, bar, beat, root, q, beats, vel, stab=False):
    """Trombones in close position above the root, tuba on the root."""
    tb, tu = ("tbn_st", "tuba_st") if stab else ("tbn", "tuba")
    for iv in q:
        sc.add("brass", o[tb], bar, beat, root + 12 + iv, vel, None if stab else beats, 0.5)
    sc.add("brass", o[tu], bar, beat, root, vel, None if stab else beats, 0.5)


def war_march(o):
    """D minor, 104 bpm. Intro (2) - A (8) - A' (8) - B (8): 26 bars."""
    sc = Score(104, 26)
    A_chords = ["Dm", "Dm", "Bb", "A", "Dm", "Gm", "Eb", "A"]
    A_mel = mel("D4:1.5 D4:.5 A4:2 | G4:.75 F4:.25 E4:1 F4:1 D4:1 | Bb4:1.5 A4:.5 G4:1 F4:1 | E4:3 A3:1 |"
                " D4:1.5 D4:.5 A4:2 | Bb4:.75 A4:.25 G4:1 D5:2 | Eb5:1.5 D5:.5 Bb4:1 G4:1 | A4:3 -:1".replace("|", ""))
    B_chords = ["Bb", "F", "Gm", "Eb", "Bb", "C", "A", "A"]
    B_mel = mel("F5:2 D5:1 Bb4:1 C5:2 A4:2 D5:1.5 Bb4:.5 G4:2 G5:3 Eb5:1 F5:1.5 D5:.5 Bb4:1 D5:1 E5:2 G5:2 A5:4 -:4")

    # Intro: gong, timpani roll swelling, ostinato starts, snare joins in bar 2
    sc.add("perc", o["gong"], 0, 0, 60, 120, None)
    sc.add("perc", o["timp_roll"], 0, 0, midi("D3") - 12, 90, 7.5, 0.6)
    sc.add("perc", o["swell"], 1, 0, 60, 100, None)
    ostinato(sc, o, 0, midi("D2"), 84)
    ostinato(sc, o, 1, midi("D2"), 96)
    snare_bar(sc, o, 1, 80, fill=True)
    sc.add("brass", o["horn"], 0, 0, midi("D3"), 70, 8, 0.8)
    sc.add("brass", o["horn"], 0, 0, midi("A3"), 66, 8, 0.8)

    # A: horns carry the tune, trombone stabs on the downbeat, strings drive
    bar0 = 2
    for i, c in enumerate(A_chords):
        root, q = chord(c)
        ostinato(sc, o, bar0 + i, root, 98)
        snare_bar(sc, o, bar0 + i, 86, fill=(i == 7))
        drums_bar(sc, o, bar0 + i, root, 100)
        brass_chord(sc, o, bar0 + i, 0, root, q, 1, 96, stab=True)
        sc.add("strings", o["vn_trem"], bar0 + i, 0, root + 36 + q[2], 70, 4, 0.3)
    play_line(sc, "brass", o["horn"], bar0, A_mel, 110)
    play_line(sc, "brass", o["horn"], bar0, A_mel, 100, shift=-12)
    sc.add("perc", o["crash"], bar0, 0, 60, 105, None)

    # A': full brass, trumpets on top, sustained trombones, violas join the ostinato
    bar0 = 10
    for i, c in enumerate(A_chords):
        root, q = chord(c)
        ostinato(sc, o, bar0 + i, root, 106, octave_up=True)
        snare_bar(sc, o, bar0 + i, 96, fill=(i == 7))
        drums_bar(sc, o, bar0 + i, root, 112)
        brass_chord(sc, o, bar0 + i, 0, root, q, 3.6, 100)
        if i in (3, 7):
            sc.add("perc", o["anvil"], bar0 + i, 3, 60, 100, None)
            sc.add("perc", o["anvil"], bar0 + i, 3.5, 60, 115, None)
    play_line(sc, "brass", o["tpt"], bar0, A_mel, 112, shift=12, legato=0.92)
    play_line(sc, "brass", o["horn"], bar0, A_mel, 116)
    play_line(sc, "strings", o["vn_sus"], bar0, A_mel, 96, shift=12)
    sc.add("perc", o["crash"], bar0, 0, 60, 120, None)
    sc.add("perc", o["gong"], bar0, 0, 60, 100, None)

    # B: the tune climbs in the relative major, then the dominant hangs and breaks
    bar0 = 18
    for i, c in enumerate(B_chords):
        root, q = chord(c)
        if i < 6:
            ostinato(sc, o, bar0 + i, root, 100, octave_up=i >= 4)
            snare_bar(sc, o, bar0 + i, 84 + 3 * i)
            drums_bar(sc, o, bar0 + i, root, 98 + 3 * i)
            brass_chord(sc, o, bar0 + i, 0, root, q, 3.8, 92 + 3 * i)
            sc.add("strings", o["vc_sus"], bar0 + i, 0, root + 12, 90, 4, 0.4)
    play_line(sc, "brass", o["tpt"], bar0, B_mel, 110, legato=0.95)
    play_line(sc, "brass", o["horn"], bar0, B_mel, 108, shift=-12)
    play_line(sc, "strings", o["vn_sus"], bar0, B_mel, 100)
    sc.add("perc", o["crash"], bar0, 0, 60, 110, None)
    # bars 24-25 on A: held brass chord over a timpani roll and snare roll, then
    # hammered A-major stabs that throw it back to the intro
    a_root, a_q = chord("A")
    sc.add("perc", o["timp_roll"], 24, 0, midi("A2"), 110, 3.8, 0.4)
    sc.add("perc", o["snare_roll"], 24, 0, 60, 100, 3.8, 0.3)
    sc.add("perc", o["crash"], 24, 0, 60, 115, None)
    brass_chord(sc, o, 24, 0, a_root, a_q, 3.8, 112)
    for k in (midi("C#5"), midi("E4")):
        sc.add("brass", o["horn"], 24, 0, k, 108, 3.8, 0.4)
    sc.add("strings", o["vn_trem"], 24, 0, midi("E5"), 96, 4, 0.3)
    sc.add("strings", o["vc_sus"], 24, 0, midi("A2"), 100, 4, 0.3)
    for b in (0, 1.5, 2, 3, 3.5):
        v = 120 if b in (0, 3) else 104
        brass_chord(sc, o, 25, b, a_root, a_q, 0.4, v, stab=True)
        sc.add("brass", o["tpt_st"], 25, b, midi("E5"), v, None)
        sc.add("brass", o["horn_st"], 25, b, midi("C#4"), v, None)
        sc.add("strings", o["vc_spic"], 25, b, midi("A2"), v, None)
        sc.add("strings", o["cb_spic"], 25, b, midi("A1"), v, None)
        sc.add("perc", o["timp"], 25, b, midi("A2"), v, None)
        sc.add("perc", o["bass_drum"], 25, b, 60, v - 10, None)
        sc.add("perc", o["snare"], 25, b, 60, v, None)
    return sc


CUES = {"war_march": (war_march, {"strings": 0.5, "brass": 0.45, "perc": 0.3})}


def main():
    lib, sfz, out = sys.argv[1], sys.argv[2], sys.argv[3]
    only = sys.argv[4:]
    o = orchestra(sfz, lib)
    for name, (fn, wets) in CUES.items():
        if only and name not in only:
            continue
        sc = fn(o)
        gains = {"strings": 1.0, "brass": 1.0, "perc": 0.9}
        sc.mixed = {b: (buf * gains[b], wets[b]) for b, buf in sc.buses.items()}
        x = master(sc, 0.9)
        dst = os.path.join(out, "music", name + ".ogg")
        encode(x, dst)
        print(dst, "%.1f s" % (len(x) / SR), os.path.getsize(dst))


if __name__ == "__main__":
    main()
