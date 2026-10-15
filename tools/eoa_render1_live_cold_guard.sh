#!/usr/bin/env bash
# WINDOWED RENDER-1 live-boot cold L-on. xvfb is NOT product Play.
# Runs 3/3 (not best-of): Δ(L-on − L-off frame2) ≤ 250 ms and frame2 B/A ≤ 0.75.
#
#   tools/eoa_render1_live_cold_guard.sh
#   EOA_RENDER1_LIVE_OUT=/tmp/eoa-render1-live tools/eoa_render1_live_cold_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_RENDER1_LIVE_OUT:-/tmp/eoa-render1-live}"
mkdir -p "$OUT"
export EOA_RENDER1_LIVE_OUT="$OUT"
echo "EOA_RENDER1_LIVE_COLD who=wrapper out=$OUT xvfb=1 runs=3 (NOT product Play)"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedRender1LiveColdGuard: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
fails=0
run=1
while [ "$run" -le 3 ]; do
  echo "EOA_RENDER1_LIVE_COLD who=wrapper.run=$run"
  if ! xvfb-run -a -s "-screen 0 1280x740x24" \
    "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x740 \
    -s res://scripts/core/WindowedRender1LiveColdGuard.gd "$@"; then
    echo "EOA_RENDER1_LIVE_COLD who=wrapper.run=$run RESULT=FAIL"
    fails=$((fails + 1))
  else
    echo "EOA_RENDER1_LIVE_COLD who=wrapper.run=$run RESULT=PASS"
  fi
  run=$((run + 1))
done
if [ "$fails" -gt 0 ]; then
  echo "WindowedRender1LiveColdGuard: RESULT=FAIL runs_failed=$fails/3"
  exit 1
fi
echo "WindowedRender1LiveColdGuard: RESULT=PASS 3/3"
exit 0
