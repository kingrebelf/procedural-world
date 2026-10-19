#!/usr/bin/env python3
"""Copies the sounds the game uses out of Ben's CC0 audio packs into assets/audio,
re-encoded to small Ogg Vorbis (mono for effects). Only what is listed here goes into
the repo. Sources: Kenney audio packs (CC0, kenney.nl) and OpenGameArt CC0 music and
ambience (see assets/audio/CREDITS.md). Run tools/synth_ambience.py for the rest.

    python3 tools/prepare_audio.py /mnt/project-files/free_assets assets/audio
"""
import os
import subprocess
import sys

K = "kenney_audio/%s/Audio/%s.ogg"
IMPACT = lambda n: K % ("impact-sounds", n)
RPG = lambda n: K % ("rpg-audio", n)
UI = lambda n: K % ("interface-sounds", n)
UI2 = lambda n: K % ("ui-audio", n)
SCI = lambda n: K % ("sci-fi-sounds", n)
JING = lambda d, n: "kenney_audio/music-jingles/Audio/%s/%s.ogg" % (d, n)
M = "music_ambience/"


def five(fn, stem):
    return [fn("%s_%03d" % (stem, i)) for i in range(5)]


# dest (under sfx/ or music/) -> list of sources; several sources = random variants
SFX = {
    "step/grass": five(IMPACT, "footstep_grass"),
    "step/stone": five(IMPACT, "footstep_concrete"),
    "step/wood": five(IMPACT, "footstep_wood"),
    "step/snow": five(IMPACT, "footstep_snow"),
    "step/carpet": five(IMPACT, "footstep_carpet"),
    "step/gravel": [RPG("footstep%02d" % i) for i in range(0, 10, 2)],
    "step/metal": five(IMPACT, "impactPlate_light"),
    "hit/wood": five(IMPACT, "impactWood_medium"),
    "hit/stone": five(IMPACT, "impactMining"),
    "hit/metal": five(IMPACT, "impactMetal_medium"),
    "hit/crystal": five(IMPACT, "impactGlass_light"),
    "hit/soft": five(IMPACT, "impactSoft_medium"),
    "hit/flesh": five(IMPACT, "impactPunch_medium"),
    "hit/heavy": five(IMPACT, "impactPunch_heavy"),
    "hit/dig": five(IMPACT, "impactSoft_heavy"),
    "hit/chop": [RPG("chop")],
    "hit/plank": five(IMPACT, "impactPlank_medium"),
    "harvest/rustle": [RPG("cloth%d" % i) for i in range(1, 5)],
    "item/pickup": [RPG("handleSmallLeather"), RPG("handleSmallLeather2")],
    "item/coins": [RPG("handleCoins"), RPG("handleCoins2")],
    "item/equip": [RPG("beltHandle1"), RPG("beltHandle2"), RPG("clothBelt")],
    "item/drop": [RPG("dropLeather")],
    "weapon/laser": five(SCI, "laserSmall"),
    "weapon/laser_big": five(SCI, "laserLarge"),
    "weapon/explosion": five(SCI, "explosionCrunch"),
    "weapon/draw": [RPG("drawKnife1"), RPG("drawKnife2"), RPG("drawKnife3")],
    "ui/click": [UI("click_001"), UI("click_002"), UI("click_003")],
    "ui/hover": [UI2("rollover1"), UI2("rollover2")],
    "ui/open": [UI("open_001")],
    "ui/close": [UI("close_001")],
    "ui/tab": [UI("select_001"), UI("select_002")],
    "ui/toggle": [UI("toggle_001"), UI("toggle_002")],
    "ui/tick": [UI("tick_001"), UI("tick_002")],
    "ui/error": [UI("error_004")],
    "ui/confirm": [UI("confirmation_001")],
    "door/open": [RPG("doorOpen_1"), RPG("doorOpen_2")],
    "door/close": [RPG("doorClose_%d" % i) for i in range(1, 5)],
    "door/slide_open": [SCI("doorOpen_000"), SCI("doorOpen_001")],
    "door/slide_close": [SCI("doorClose_000"), SCI("doorClose_001"), SCI("doorClose_002")],
    "door/lock": [RPG("metalLatch"), RPG("metalClick")],
    "jingle/level_up": [JING("Pizzicato jingles", "jingles_PIZZI10")],
    "jingle/discovery": [JING("Steel jingles", "jingles_STEEL00")],
    "jingle/death": [JING("Pizzicato jingles", "jingles_PIZZI16")],
}
# looping sounds (kept stereo where the source is)
LOOPS = {
    "loop/jetpack": SCI("thrusterFire_000"),
    "loop/engine": SCI("spaceEngineLow_000"),
    "loop/engine_big": SCI("spaceEngineLarge_000"),
}
MUSIC = {
    "music/exploration": M + "Exploration Theme/exploration_theme/Exploration Theme/Exploration Theme.ogg",
    "music/safe_space": M + "Safe Space/safe_space_loop.flac",
    "music/horror": M + "Music Loops/horror/Horror.wav",
    "music/captains_log": M + "Sci-Fi Horror Ambience/Final Captain's Log.mp3",
    "ambience/dungeon": M + "Dungeon Ambience/dungeon_ambient_1.ogg",
}


def enc(src, dst, mono, q, rate):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    args = ["ffmpeg", "-v", "error", "-y", "-i", src]
    if mono:
        args += ["-ac", "1"]
    args += ["-ar", str(rate), "-c:a", "libvorbis", "-q:a", str(q), "-map_metadata", "-1", dst]
    subprocess.run(args, check=True)


def main():
    src, out = sys.argv[1], sys.argv[2]
    total = 0
    for dest, files in SFX.items():
        for i, f in enumerate(files):
            d = os.path.join(out, "sfx", "%s_%d.ogg" % (dest, i))
            enc(os.path.join(src, f), d, True, 3, 44100)
            total += os.path.getsize(d)
    for dest, f in LOOPS.items():
        d = os.path.join(out, "sfx", dest + ".ogg")
        enc(os.path.join(src, f), d, True, 3, 44100)
        total += os.path.getsize(d)
    for dest, f in MUSIC.items():
        d = os.path.join(out, dest + ".ogg")
        enc(os.path.join(src, f), d, False, 2, 44100)
        total += os.path.getsize(d)
        print(d, os.path.getsize(d))
    print("total", total)


if __name__ == "__main__":
    main()
