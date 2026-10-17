#!/usr/bin/env bash
# Builds the built-in voice pack into $1 (default build/voices/<platform>): the voice
# server for Linux and Windows, the sherpa-onnx and ONNX Runtime libraries it uses, and the
# Kokoro voice model with the game's voice table (tools/voice_server/make_voices.py).
# Needs: gcc, x86_64-w64-mingw32-gcc (for Windows), python3 with numpy and onnx, curl.
# Downloads are cached in $VOICE_CACHE (default ~/.cache/pw-voices).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="${1:-$ROOT/build/voices}"
CACHE="${VOICE_CACHE:-$HOME/.cache/pw-voices}"
SHERPA=1.13.8
REL=https://github.com/k2-fsa/sherpa-onnx/releases/download
mkdir -p "$CACHE" "$OUT"
fetch() { # url -> cached file, extracted once
  local f="$CACHE/$(basename "$1")"
  if [ ! -f "$f" ]; then
    curl -sSfL --retry 4 -o "$f.part" "$1"
    mv -f "$f.part" "$f"
  fi
  local d="${f%.tar.bz2}"
  [ -d "$d" ] || (cd "$CACHE" && tar xjf "$f")
  echo "$d"
}
LIN="$(fetch "$REL/v$SHERPA/sherpa-onnx-v$SHERPA-linux-x64-shared.tar.bz2")"
WIN="$(fetch "$REL/v$SHERPA/sherpa-onnx-v$SHERPA-win-x64-shared-MT-Release-lib.tar.bz2")"
KOKORO="$(fetch "$REL/tts-models/kokoro-multi-lang-v1_0.tar.bz2")"

# The model and voices, shared by both platforms.
DATA="$OUT/data"
mkdir -p "$DATA"
python3 "$HERE/make_voices.py" "$KOKORO" "$ROOT/assets/voices/catalog.json" "$DATA"

# Linux
L="$OUT/linux"
mkdir -p "$L"
gcc -O2 -o "$L/voice_server" "$HERE/voice_server.c" -I"$LIN/include" -L"$LIN/lib" -lsherpa-onnx-c-api -lpthread -Wl,-rpath,'$ORIGIN'
cp -a "$LIN/lib/libsherpa-onnx-c-api.so" "$LIN/lib/libonnxruntime.so"* "$L/"

# Windows
if command -v x86_64-w64-mingw32-gcc >/dev/null; then
  W="$OUT/windows"
  mkdir -p "$W"
  x86_64-w64-mingw32-gcc -O2 -o "$W/voice_server.exe" "$HERE/voice_server.c" -I"$LIN/include" \
    "$WIN/lib/sherpa-onnx-c-api.dll" -lws2_32 -static-libgcc -mwindows
  cp -a "$WIN/lib/sherpa-onnx-c-api.dll" "$WIN/lib/onnxruntime.dll" "$WIN/lib/onnxruntime_providers_shared.dll" "$W/"
fi
cp "$HERE/LICENSES.txt" "$OUT/"
echo "voice pack in $OUT"
