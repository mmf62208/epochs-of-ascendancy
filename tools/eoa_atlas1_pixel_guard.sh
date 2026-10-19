#!/usr/bin/env bash
# Windowed ATLAS-1 pixel guard. Not the product Begin / Esc / clock path.
# One fixed orientation. Captures Home / mid / close over the Ruhr and Paris.
#   tools/eoa_atlas1_pixel_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_ATLAS1_PIXEL_OUT:-/tmp/eoa-atlas1-pixel}"
mkdir -p "$OUT"
export EOA_ATLAS1_PIXEL_OUT="$OUT"
export EOA_SMOKE_AUTO_BEGIN=1
unset EOA_SKIP_TITLE || true
echo "EOA_ATLAS1_PIXEL_GUARD who=wrapper out=$OUT (NOT product Begin/Esc/clock PASS)"
GODOT=("${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 -s res://scripts/core/WindowedAtlas1PixelGuard.gd "$@")
if command -v xvfb-run >/dev/null 2>&1; then
  echo "EOA_ATLAS1_PIXEL_GUARD who=wrapper xvfb=1"
  exec xvfb-run -a -s "-screen 0 1280x800x24" "${GODOT[@]}"
fi
if [ -n "${DISPLAY:-}" ]; then
  echo "EOA_ATLAS1_PIXEL_GUARD who=wrapper xvfb=0 display=$DISPLAY plain=1"
  exec "${ROOT}/tools/run_godot.sh" --display-driver x11 --path . --resolution 1280x800 \
    -s res://scripts/core/WindowedAtlas1PixelGuard.gd "$@"
fi
echo "WindowedAtlas1PixelGuard: RESULT=FAIL need xvfb-run or DISPLAY" >&2
exit 1
