#!/usr/bin/env bash
# Builds the Windows and Linux games and the Windows installer.
# Needs: Godot 4.5.1 (as `godot`, or set GODOT), its export templates, and NSIS (makensis).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
VERSION="$(grep -oP 'config/version="\K[^"]+' project.godot)"
rm -rf build && mkdir -p build/windows build/linux
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/ProceduralWorld.exe
"$GODOT" --headless --path . --export-release "Linux" build/linux/ProceduralWorld.x86_64
(cd installer/windows && makensis -V2 -DVERSION="$VERSION" -DSRC_DIR=../../build/windows \
  -DOUT_FILE="../../build/ProceduralWorld-$VERSION-Setup.exe" installer.nsi)
(cd build/windows && zip -q -r "../ProceduralWorld-$VERSION-windows-portable.zip" .)
(cd build/linux && tar czf "../ProceduralWorld-$VERSION-linux-x86_64.tar.gz" .)
ls -la build
