#!/usr/bin/env bash
# HWY-3 FIX #5 Ruhr live-legibility pixel + label guard.
# Camera Essen (7356, 1606) at z 2.4 and 4.0. Smoke harness is not the product.
#
#   tools/eoa_hwy3_ruhr_legibility_guard.sh
#   EOA_HWY3_RUHR_OUT=/tmp/eoa-hwy3-ruhr tools/eoa_hwy3_ruhr_legibility_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_HWY3_RUHR_OUT:-/tmp/eoa-hwy3-ruhr}"
mkdir -p "$OUT"
export EOA_HWY3_RUHR_OUT="$OUT"
export EOA_SMOKE_AUTO_BEGIN=1
export EOA_SMOKE_ADVANCE_PAST_PLUS6=0
unset EOA_SKIP_TITLE || true
echo "HWY3_RUHR who=wrapper out=$OUT xvfb=1"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedHwy3RuhrLegibilityGuard: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
xvfb-run -a -s "-screen 0 1280x720x24" \
  "${ROOT}/tools/run_godot.sh" --path . \
  -s res://scripts/core/WindowedHwy3RuhrLegibilityGuard.gd "$@"
