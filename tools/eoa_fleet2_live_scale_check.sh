#!/usr/bin/env bash
# FLEET-2 FIX #5 live-scale check: real world_accurate board, xvfb 1280x740.
# GER start, Europe Home, Channel + North Sea at Home zoom and ~1.5.
# Pixel-assert plate centres. Click all 8 plates at 0.318 / 0.40 / 0.8 / 1.5
# plus East Kent, old ENG chip, GER-nearest gap, Play-listed land/air counters,
# coasts 710374/710380 (own GER or province, never foreign), own AW3 bars
# +46 / corner, and own GER drawn bodies at 0.318 / 0.40.
# xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
#
#   tools/eoa_fleet2_live_scale_check.sh
#   EOA_FLEET2_LIVE_OUT=/tmp/eoa-fleet2-live tools/eoa_fleet2_live_scale_check.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_FLEET2_LIVE_OUT:-/tmp/eoa-fleet2-live}"
mkdir -p "$OUT"
export EOA_FLEET2_LIVE_OUT="$OUT"
export EOA_SMOKE_AUTO_BEGIN=1
export EOA_SMOKE_ADVANCE_PAST_PLUS6=0
unset EOA_SKIP_TITLE || true
SCRIPT="res://scripts/core/WindowedFleet2LiveScaleCheck.gd"
echo "EOA_FLEET2_LIVE_SCALE who=wrapper out=$OUT xvfb=1 screen=1280x740 (NOT live Play)"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedFleet2LiveScaleCheck: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
LOG="$OUT/live.log"
RSS_LOG="$OUT/rss.txt"
: > "$RSS_LOG"
xvfb-run -a -s "-screen 0 1280x740x24" \
  "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x740 -s "$SCRIPT" >"$LOG" 2>&1 &
WRAP=$!
peak_kb=0
while kill -0 "$WRAP" 2>/dev/null; do
  child_kb=0
  while read -r pid; do
    [ -z "$pid" ] && continue
    kb="$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
    if [ -n "${kb:-}" ]; then
      child_kb=$((child_kb + kb))
    fi
  done < <(pgrep -f 'WindowedFleet2LiveScaleCheck|Godot_v4' 2>/dev/null || true)
  if [ "${child_kb:-0}" -gt "$peak_kb" ]; then
    peak_kb="$child_kb"
  fi
  echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$RSS_LOG"
  sleep 2
done
code=0
wait "$WRAP" || code=$?
mb="$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}')"
echo "EOA_FLEET2_LIVE who=xvfb.rss peak_kb=$peak_kb mb=$mb (NOT live Play)"
if ! grep -q "WindowedFleet2LiveScaleCheck: RESULT=PASS" "$LOG"; then
  echo "FLEET-2 live-scale: RESULT=FAIL (no RESULT=PASS) code=$code log=$LOG"
  tail -n 80 "$LOG" || true
  exit 1
fi
if grep -Eiq "SCRIPT ERROR|SIGSEGV" "$LOG"; then
  echo "FLEET-2 live-scale: RESULT=FAIL (engine error) log=$LOG"
  grep -Ei "SCRIPT ERROR|SIGSEGV" "$LOG" || true
  exit 1
fi
echo "FLEET-2 live-scale: RESULT=PASS rss_mb=$mb log=$LOG"
exit 0
