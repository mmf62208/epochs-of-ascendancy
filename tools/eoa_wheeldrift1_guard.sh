#!/usr/bin/env bash
# WHEELDRIFT-1 wheel zoom + rim edge-pan hold.
# Headless. xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
#
#   tools/eoa_wheeldrift1_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_WHEELDRIFT1_OUT:-/tmp/eoa-wheeldrift1}"
mkdir -p "$OUT"
unset EOA_SKIP_TITLE || true
SCRIPT="res://scripts/core/HeadlessWheelDrift1Test.gd"
LOG="$OUT/hd.log"
echo "EOA_WHEELDRIFT1_GUARD who=wrapper out=$OUT (NOT live Play)"
set +e
"${ROOT}/tools/run_godot.sh" --headless --path . --resolution 1280x740 -s "$SCRIPT" >"$LOG" 2>&1
code=$?
set -e
if ! grep -q "HeadlessWheelDrift1Test: RESULT=PASS" "$LOG"; then
  echo "WHEELDRIFT-1 hd: RESULT=FAIL (no RESULT=PASS) code=$code log=$LOG"
  tail -n 80 "$LOG" || true
  exit 1
fi
if grep -Eiq "SCRIPT ERROR|SIGSEGV" "$LOG"; then
  echo "WHEELDRIFT-1 hd: RESULT=FAIL (engine error) log=$LOG"
  grep -Ei "SCRIPT ERROR|SIGSEGV" "$LOG" || true
  exit 1
fi
echo "WHEELDRIFT-1 hd: RESULT=PASS"
echo "EOA_WHEELDRIFT1_GUARD RESULT=PASS (NOT live Play)"
exit 0
