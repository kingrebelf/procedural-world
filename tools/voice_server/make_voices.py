"""Builds the game's voice data from the Kokoro v1.0 release of sherpa-onnx.

    python3 make_voices.py <kokoro-multi-lang-v1_0 dir> <assets/voices/catalog.json> <out dir>

Writes into <out dir>:
  voices.bin      the catalog's voices, each a weighted mix of Kokoro's own voices, in
                  catalog order (the voice number the game asks for is the index)
  model.onnx      Kokoro with its speaker count set to the catalog's
  tokens.txt      Kokoro's phoneme table, plus phonemes the regional accents use that
                  Kokoro lacks, mapped to their nearest sound
  espeak-ng-data  only what English needs
  LICENSE-kokoro.txt
Needs numpy and onnx. Skips work that is already done for the same catalog.
"""
import hashlib, json, os, shutil, sys

import numpy as np

# Speaker names in Kokoro v1.0's voices.bin, in file order.
NAMES = ("af_alloy,af_aoede,af_bella,af_heart,af_jessica,af_kore,af_nicole,af_nova,af_river,af_sarah,af_sky,"
         "am_adam,am_echo,am_eric,am_fenrir,am_liam,am_michael,am_onyx,am_puck,am_santa,bf_alice,bf_emma,"
         "bf_isabella,bf_lily,bm_daniel,bm_fable,bm_george,bm_lewis,ef_dora,em_alex,ff_siwis,hf_alpha,hf_beta,"
         "hm_omega,hm_psi,if_sara,im_nicola,jf_alpha,jf_gongitsune,jf_nezumi,jf_tebukuro,jm_kumo,pf_dora,pm_alex,"
         "pm_santa,zf_xiaobei,zf_xiaoni,zf_xiaoxiao,zf_xiaoyi,zm_yunjian,zm_yunxi,zm_yunxia,zm_yunyang,em_santa").split(",")
# Phonemes eSpeak NG's regional English accents produce that Kokoro has no token for.
EXTRA_TOKENS = {"ʉ": "u"}  # Scottish "you", "school"


def build_voices(src, catalog):
    base = np.fromfile(os.path.join(src, "voices.bin"), dtype=np.float32).reshape(len(NAMES), 510, 256)
    out = np.zeros((len(catalog["voices"]), 510, 256), dtype=np.float32)
    for i, v in enumerate(catalog["voices"]):
        total = sum(v["mix"].values())
        for name, w in v["mix"].items():
            out[i] += base[NAMES.index(name)] * (w / total)
    return out


def patch_model(src, dst, n):
    import onnx
    m = onnx.load(src)
    names = ["v%d" % i for i in range(n)]
    for p in m.metadata_props:
        if p.key == "n_speakers":
            p.value = str(n)
        elif p.key == "id2speaker":
            p.value = ",".join("%d->%s" % (i, x) for i, x in enumerate(names))
        elif p.key == "speaker2id":
            p.value = ",".join("%s->%d" % (x, i) for i, x in enumerate(names))
        elif p.key == "speaker_names":
            p.value = ",".join(names)
    onnx.save(m, dst)


def main():
    src, cat_path, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    catalog = json.load(open(cat_path))
    n = len(catalog["voices"])
    stamp = hashlib.sha1(open(cat_path, "rb").read()).hexdigest()
    stamp_file = os.path.join(out, ".catalog")
    if os.path.exists(stamp_file) and open(stamp_file).read() == stamp and os.path.exists(os.path.join(out, "model.onnx")):
        print("voice data up to date")
        return
    build_voices(src, catalog).tofile(os.path.join(out, "voices.bin"))
    patch_model(os.path.join(src, "model.onnx"), os.path.join(out, "model.onnx"), n)
    lines = open(os.path.join(src, "tokens.txt"), encoding="utf-8").read().splitlines()
    ids = {l.rsplit(" ", 1)[0]: l.rsplit(" ", 1)[1] for l in lines if " " in l.strip() or l.startswith(" ")}
    with open(os.path.join(out, "tokens.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
        for ph, like in EXTRA_TOKENS.items():
            if ph not in ids:
                f.write("%s %s\n" % (ph, ids[like]))
    # eSpeak NG data: the shared phoneme tables and English only.
    ed_src, ed_out = os.path.join(src, "espeak-ng-data"), os.path.join(out, "espeak-ng-data")
    shutil.rmtree(ed_out, ignore_errors=True)
    os.makedirs(os.path.join(ed_out, "lang", "gmw"))
    for f in ("phondata", "phondata-manifest", "phonindex", "phontab", "intonations", "en_dict"):
        if os.path.exists(os.path.join(ed_src, f)):
            shutil.copy(os.path.join(ed_src, f), ed_out)
    for f in os.listdir(os.path.join(ed_src, "lang", "gmw")):
        if f.startswith("en"):
            shutil.copy(os.path.join(ed_src, "lang", "gmw", f), os.path.join(ed_out, "lang", "gmw"))
    if os.path.isdir(os.path.join(ed_src, "voices")):
        shutil.copytree(os.path.join(ed_src, "voices"), os.path.join(ed_out, "voices"))
    shutil.copy(os.path.join(src, "LICENSE"), os.path.join(out, "LICENSE-kokoro.txt"))
    open(stamp_file, "w").write(stamp)
    print("voice data: %d voices in %s" % (n, out))


if __name__ == "__main__":
    main()
