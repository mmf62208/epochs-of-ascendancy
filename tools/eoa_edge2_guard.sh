#!/usr/bin/env bash
# EDGE-2 rim dwell / ramp / Home-zoom cap / left-HUD 6px exemption.
# Headless. xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
#
#   tools/eoa_edge2_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_EDGE2_OUT:-/tmp/eoa-edge2}"
mkdir -p "$OUT"
unset EOA_SKIP_TITLE || true
SCRIPT="res://scripts/core/HeadlessEdge2RimFeelTest.gd"
LOG="$OUT/hd.log"
echo "EOA_EDGE2_GUARD who=wrapper out=$OUT (NOT live Play)"
set +e
"${ROOT}/tools/run_godot.sh" --headless --path . --resolution 1280x740 -s "$SCRIPT" >"$LOG" 2>&1
code=$?
set -e
if ! grep -q "HeadlessEdge2RimFeelTest: RESULT=PASS" "$LOG"; then
  echo "EDGE-2 hd: RESULT=FAIL (no RESULT=PASS) code=$code log=$LOG"
  tail -n 80 "$LOG" || true
  exit 1
fi
if grep -Eiq "SCRIPT ERROR|SIGSEGV" "$LOG"; then
  echo "EDGE-2 hd: RESULT=FAIL (engine error) log=$LOG"
  grep -Ei "SCRIPT ERROR|SIGSEGV" "$LOG" || true
  exit 1
fi
echo "EDGE-2 hd: RESULT=PASS"
echo "EOA_EDGE2_GUARD RESULT=PASS (NOT live Play)"
exit 0
