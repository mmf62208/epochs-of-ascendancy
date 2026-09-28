#!/usr/bin/env bash
# WINDOWED RT-1 road-tier pixel + soft-note guard. Smoke harness is not the product.
# Loads TestScenario (world_accurate, same F5 path) via tools/run_godot.sh.
# Never EOA_SKIP_TITLE. Uses EOA_SMOKE_AUTO_BEGIN only to dismiss the living title.
#
#   tools/eoa_rt1_pixel_guard.sh
#   EOA_RT1_PIXEL_OUT=/tmp/eoa-rt1-pixel tools/eoa_rt1_pixel_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_RT1_PIXEL_OUT:-/tmp/eoa-rt1-pixel}"
mkdir -p "$OUT"
export EOA_RT1_PIXEL_OUT="$OUT"
export EOA_SMOKE_AUTO_BEGIN=1
unset EOA_SKIP_TITLE || true
echo "EOA_RT1_PIXEL_GUARD who=wrapper out=$OUT xvfb=1 (NOT product Begin/Esc/clock PASS)"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedRt1RoadTierPixelGuard: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
exec xvfb-run -a -s "-screen 0 1280x720x24" \
  "${ROOT}/tools/run_godot.sh" --path . \
  -s res://scripts/core/WindowedRt1RoadTierPixelGuard.gd "$@"
