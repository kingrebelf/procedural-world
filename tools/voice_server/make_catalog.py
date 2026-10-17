"""Designs the game's voice table (assets/voices/catalog.json). Run once; the result is
committed, and make_voices.py turns it into voice data at build time.

    python3 make_catalog.py <kokoro-multi-lang-v1_0 dir> <whisper base.en dir> <out catalog.json>

Each voice is one of Kokoro's English-speaking voices or a weighted mix of two or three of
the same sex, so every one sounds like a different person. Each is then spoken, measured
for pitch and checked with a speech recogniser: a voice that can't be understood is
dropped. Needs sherpa-onnx, numpy, onnx and jiwer (pip).
"""
import json, os, random, re, subprocess, sys, tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_voices import NAMES, build_voices, patch_model  # noqa: E402

PER_SEX = 64
# Kokoro's voices that speak English, by sex and accent, with how good each sounds on its
# own (Kokoro's grades, A=4 .. D=1): better ones turn up more in mixes.
VOICES = {
    "f": {"gb": {"bf_emma": 3, "bf_isabella": 2, "bf_alice": 1, "bf_lily": 1},
          "us": {"af_heart": 4, "af_bella": 4, "af_nicole": 3, "af_aoede": 2, "af_kore": 2, "af_sarah": 2, "af_nova": 2,
                 "af_sky": 1, "af_alloy": 2, "af_jessica": 1, "af_river": 1},
          "fr": {"ff_siwis": 3}, "in": {"hf_alpha": 2, "hf_beta": 2}, "it": {"if_sara": 2}, "es": {"ef_dora": 1}, "pt": {"pf_dora": 1}},
    "m": {"gb": {"bm_george": 2, "bm_fable": 2, "bm_lewis": 1, "bm_daniel": 1},
          "us": {"am_fenrir": 2, "am_michael": 2, "am_puck": 2, "am_echo": 1, "am_eric": 1, "am_liam": 1, "am_onyx": 1,
                 "am_santa": 1, "am_adam": 1},
          "it": {"im_nicola": 2}, "in": {"hm_omega": 2, "hm_psi": 2}, "es": {"em_alex": 1, "em_santa": 1}, "pt": {"pm_alex": 1, "pm_santa": 1}},
}
TEXTS = ["The baker's cart lost a wheel on the north road this morning.",
         "We haven't had rain in nine days, and the well is running low."]


def pick(rng, pool):
    names = list(pool)
    return rng.choices(names, weights=[pool[n] for n in names])[0]


def design(rng):
    out = []
    for sex, fam in VOICES.items():
        gb, us = fam["gb"], fam["us"]
        foreign = {k: v for k, v in fam.items() if k not in ("gb", "us")}
        mine = []
        for n in gb:
            mine.append({"mix": {n: 1.0}, "accent": "gb"})
        for n, q in us.items():
            if q >= 1 and n != "am_adam":
                mine.append({"mix": {n: 1.0}, "accent": "us"})
        for acc, pool in foreign.items():
            for n in pool:
                mine.append({"mix": {n: 1.0}, "accent": acc})
        seen = {tuple(sorted(v["mix"])) for v in mine}
        plan = ["gb"] * 14 + ["mid"] * 12 + ["us"] * 8 + ["foreign"] * 6 + ["three"] * 6
        rng.shuffle(plan)
        tries = 0
        while len(mine) < PER_SEX and tries < 5000:
            tries += 1
            kind = plan[len(mine) % len(plan)]
            if kind == "gb":
                a, b = pick(rng, gb), pick(rng, {**gb, **{k: v * 0.3 for k, v in us.items()}})
                acc = "gb"
            elif kind == "mid":
                a, b = pick(rng, gb), pick(rng, us)
                acc = "mid"
            elif kind == "us":
                a, b = pick(rng, us), pick(rng, us)
                acc = "us"
            elif kind == "foreign":
                acc = rng.choice(list(foreign))
                a, b = pick(rng, foreign[acc]), pick(rng, {**gb, **us})
            else:
                a, b = pick(rng, gb), pick(rng, us)
                c = pick(rng, {**gb, **us})
                if len({a, b, c}) < 3 or tuple(sorted((a, b, c))) in seen:
                    continue
                w = [rng.uniform(0.2, 0.5) for _ in range(3)]
                s = sum(w)
                mine.append({"mix": {a: round(w[0] / s, 2), b: round(w[1] / s, 2), c: round(w[2] / s, 2)}, "accent": "mid"})
                seen.add(tuple(sorted((a, b, c))))
                continue
            if a == b:
                continue
            w = round(rng.uniform(0.3, 0.7), 2)
            key = tuple(sorted((a, b))) + (round(w, 1),)
            if key in seen:
                continue
            seen.add(key)
            mine.append({"mix": {a: w, b: round(1 - w, 2)}, "accent": acc})
        for v in mine:
            v["sex"] = sex
        out += mine[:PER_SEX]
    return out


def main():
    import jiwer
    import sherpa_onnx as so

    kokoro, whisper, dst = sys.argv[1:4]
    rng = random.Random(4242)
    voices = design(rng)
    tmp = tempfile.mkdtemp()
    cat = {"voices": voices}
    build_voices(kokoro, cat).tofile(os.path.join(tmp, "voices.bin"))
    patch_model(os.path.join(kokoro, "model.onnx"), os.path.join(tmp, "model.onnx"), len(voices))
    toks = open(os.path.join(kokoro, "tokens.txt"), encoding="utf-8").read() + "ʉ 63\n"
    open(os.path.join(tmp, "tokens.txt"), "w", encoding="utf-8").write(toks)
    tts = so.OfflineTts(so.OfflineTtsConfig(model=so.OfflineTtsModelConfig(kokoro=so.OfflineTtsKokoroModelConfig(
        model=os.path.join(tmp, "model.onnx"), voices=os.path.join(tmp, "voices.bin"), tokens=os.path.join(tmp, "tokens.txt"),
        data_dir=os.path.join(kokoro, "espeak-ng-data"), lang="en"), num_threads=4), max_num_sentences=1))
    asr = so.OfflineRecognizer.from_whisper(encoder=os.path.join(whisper, "base.en-encoder.int8.onnx"),
                                            decoder=os.path.join(whisper, "base.en-decoder.int8.onnx"),
                                            tokens=os.path.join(whisper, "base.en-tokens.txt"), num_threads=4)

    def norm(t):
        return " ".join(re.sub(r"[^a-z' ]", "", t.lower()).split())

    def f0(x, sr=24000):
        fl, out = int(0.04 * sr), []
        for i in range(0, len(x) - fl, fl // 2):
            fr = x[i:i + fl] * np.hanning(fl)
            if np.sqrt((fr ** 2).mean()) < 0.02:
                continue
            ac = np.correlate(fr, fr, "full")[fl - 1:]
            lo, hi = int(sr / 400), int(sr / 60)
            k = lo + int(np.argmax(ac[lo:hi]))
            if ac[k] > 0.35 * ac[0]:
                out.append(sr / k)
        return float(np.median(out)) if out else 0.0

    keep = []
    for i, v in enumerate(voices):
        g = so.GenerationConfig()
        g.sid, g.speed = i, 1.0
        g.extra = {"lang": "en-US" if v["accent"] == "us" else "en"}
        errs, pitch = [], []
        for t in TEXTS:
            a = tts.generate(t, g)
            x = np.array(a.samples, dtype=np.float32)
            st = asr.create_stream()
            st.accept_waveform(a.sample_rate, x)
            asr.decode_stream(st)
            errs.append(jiwer.wer(norm(t), norm(st.result.text)))
            pitch.append(f0(x))
        v["pitch"] = int(round(float(np.median(pitch))))
        v["wer"] = round(float(np.mean(errs)), 3)
        print(i, v, flush=True)
        if v["wer"] <= 0.2:
            keep.append(v)
    for v in keep:
        del v["wer"]
    json.dump({"version": 1, "model": "kokoro-multi-lang-v1_0", "voices": keep}, open(dst, "w"), indent=1)
    print("kept %d of %d voices" % (len(keep), len(voices)))


if __name__ == "__main__":
    main()
