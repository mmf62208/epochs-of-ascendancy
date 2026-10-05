#!/usr/bin/env bash
# CLOSE-1 windowed xvfb check: 1280x740 GER Europe Home world_accurate.
# Open unit card, Close at real BtnClose, warp/move to the top bar ≥20 times.
# xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
#
#   tools/eoa_close1_windowed_check.sh
#   EOA_CLOSE1_LIVE_OUT=/tmp/eoa-close1-live tools/eoa_close1_windowed_check.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_CLOSE1_LIVE_OUT:-/tmp/eoa-close1-live}"
mkdir -p "$OUT"
export EOA_CLOSE1_LIVE_OUT="$OUT"
export EOA_SMOKE_AUTO_BEGIN=1
export EOA_SMOKE_ADVANCE_PAST_PLUS6=0
unset EOA_SKIP_TITLE || true
SCRIPT="res://scripts/core/WindowedClose1CardCloseDragCheck.gd"
echo "EOA_CLOSE1_WINDOWED who=wrapper out=$OUT xvfb=1 screen=1280x740 (NOT live Play)"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedClose1CardCloseDragCheck: RESULT=FAIL need xvfb-run" >&2
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
  done < <(pgrep -f 'WindowedClose1CardCloseDragCheck|Godot_v4' 2>/dev/null || true)
  if [ "${child_kb:-0}" -gt "$peak_kb" ]; then
    peak_kb="$child_kb"
  fi
  echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$RSS_LOG"
  sleep 2
done
wait "$WRAP"
code=$?
mb="$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}')"
echo "EOA_CLOSE1_WINDOWED who=wrapper.rss peak_kb=$peak_kb mb=$mb (NOT live Play)"
if ! grep -q "WindowedClose1CardCloseDragCheck: RESULT=PASS" "$LOG"; then
  echo "CLOSE-1 windowed: RESULT=FAIL code=$code log=$LOG"
  tail -n 80 "$LOG" || true
  exit 1
fi
if grep -Eiq "SCRIPT ERROR|SIGSEGV" "$LOG"; then
  echo "CLOSE-1 windowed: RESULT=FAIL (engine error) log=$LOG"
  grep -Ei "SCRIPT ERROR|SIGSEGV" "$LOG" || true
  exit 1
fi
echo "CLOSE-1 windowed: RESULT=PASS rss_mb=$mb"
exit 0
