#!/usr/bin/env bash
# Builds the Windows and Linux games, the Windows installer, and the dedicated server
# for Linux, Windows and macOS (docs/SERVER.md).
# Needs: Godot 4.5.1 (as `godot`, or set GODOT), its export templates, and NSIS (makensis).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
VERSION="$(grep -oP 'config/version="\K[^"]+' project.godot)"
rm -rf build && mkdir -p build/windows build/linux build/linux-server build/windows-server build/macos-server build/tpl
touch build/.gdignore
TEMPLATES="${GODOT_TEMPLATES:-$HOME/.local/share/godot/export_templates/${GODOT_VERSION:-4.5.1}.stable}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/ProceduralWorld.exe
"$GODOT" --headless --path . --export-release "Linux" build/linux/ProceduralWorld.x86_64
# Built-in natural voices (tools/voice_server): the voice program and model beside each game.
tools/voice_server/build.sh build/voicepack
mkdir -p build/windows/voices/data build/linux/voices/data
cp -a build/voicepack/windows/. build/windows/voices/
cp -a build/voicepack/linux/. build/linux/voices/
cp -a build/voicepack/data/. build/windows/voices/data/
cp -a build/voicepack/data/. build/linux/voices/data/
cp build/voicepack/LICENSES.txt build/windows/voices/
cp build/voicepack/LICENSES.txt build/linux/voices/
(cd installer/windows && makensis -V2 -DVERSION="$VERSION" -DSRC_DIR=../../build/windows \
  -DOUT_FILE="../../build/ProceduralWorld-$VERSION-Setup.exe" installer.nsi)
(cd build/windows && zip -q -r "../ProceduralWorld-$VERSION-windows-portable.zip" .)
(cd build/linux && tar czf "../ProceduralWorld-$VERSION-linux-x86_64.tar.gz" .)

# Dedicated servers: the same game with the "server" feature, plus a launcher, server.cfg
# guide and SERVER.md. server.cfg itself is written on first start.
"$GODOT" --headless --path . --export-release "Linux Server" build/linux-server/ProceduralWorldServer.x86_64
"$GODOT" --headless --path . --export-release "Windows Server" build/windows-server/ProceduralWorldServer.exe
python3 tools/make_mac_server_template.py "$TEMPLATES/macos.zip" build/tpl/macos_server.zip
"$GODOT" --headless --path . --export-release "macOS Server" build/macos-server/ProceduralWorldServer.zip
cp installer/server/start-server.sh docs/SERVER.md build/linux-server/
cp installer/server/start-server.bat docs/SERVER.md build/windows-server/
(cd build/linux-server && tar czf "../ProceduralWorldServer-$VERSION-linux-x86_64.tar.gz" .)
(cd build/windows-server && zip -q -r "../ProceduralWorldServer-$VERSION-windows.zip" .)
# macOS: the export is a zip holding the .app; add the launcher and guide beside it.
mkdir -p build/macos-server/pkg
(cd build/macos-server/pkg && unzip -q ../ProceduralWorldServer.zip && mv "Procedural World.app" "Procedural World Server.app")
cp installer/server/start-server.command docs/SERVER.md build/macos-server/pkg/
chmod +x build/macos-server/pkg/start-server.command
(cd build/macos-server/pkg && zip -q -r -y "../../ProceduralWorldServer-$VERSION-macos.zip" .)
ls -la build
