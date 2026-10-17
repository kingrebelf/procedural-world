#!/usr/bin/env python3
"""Makes the macOS export template for the dedicated server.

Godot only exports universal/arm64 macOS builds when the project also imports ETC2/ASTC
textures, which the game doesn't need (a server draws nothing). An x86_64 export only
needs S3TC, but the official template ships just the universal binary. This copies the
template with that universal binary also named as the x86_64 one, so the "macOS Server"
preset exports as x86_64 yet runs natively on both Intel and Apple Silicon Macs.

Usage: make_mac_server_template.py <godot macos.zip> <output zip>
"""
import sys
import zipfile

src, out = sys.argv[1], sys.argv[2]
UNI = "macos_template.app/Contents/MacOS/godot_macos_release.universal"
X64 = "macos_template.app/Contents/MacOS/godot_macos_release.x86_64"
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zo:
    for info in zi.infolist():
        if "debug" in info.filename:
            continue
        data = zi.read(info.filename)
        zo.writestr(info, data)
        if info.filename == UNI:
            alias = zipfile.ZipInfo(X64, info.date_time)
            alias.external_attr = info.external_attr
            alias.compress_type = zipfile.ZIP_DEFLATED
            zo.writestr(alias, data)
print("wrote", out)
