#!/usr/bin/env bash
# WINDOWED MV-1 card-up real-input guard. xvfb / llvmpipe is NOT live Play.
# Selects the unit by simulated mouse press+release at the counter (normal
# _input / _unhandled_input path). Never sets selected_formation_id.
# FIX #2: inspector + Open-fight open/close, plain-click switch A→B,
# adjacent-in-chip commit, return-to-origin drag, 5 still clicks after drag.
# Never EOA_SKIP_TITLE. Uses EOA_SMOKE_AUTO_BEGIN only to dismiss the title.
#
#   tools/eoa_mv1_card_up_input_guard.sh
#   EOA_MV1_CARD_UP_OUT=/tmp/eoa-mv1-card-up tools/eoa_mv1_card_up_input_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_MV1_CARD_UP_OUT:-/tmp/eoa-mv1-card-up}"
mkdir -p "$OUT"
export EOA_MV1_CARD_UP_OUT="$OUT"
export EOA_SMOKE_AUTO_BEGIN=1
export EOA_SMOKE_ADVANCE_PAST_PLUS6=0
unset EOA_SKIP_TITLE || true
echo "EOA_MV1_CARD_UP_INPUT_GUARD who=wrapper out=$OUT xvfb=1 screen=1600x900 (NOT live Play / NOT Vulkan product)"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedMv1CardUpInputGuard: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
RSS_LOG="$OUT/rss.txt"
: > "$RSS_LOG"
xvfb-run -a -s "-screen 0 1600x900x24" \
  "${ROOT}/tools/run_godot.sh" --path . \
  -s res://scripts/core/WindowedMv1CardUpInputGuard.gd "$@" &
GODOT_WRAP=$!
peak_kb=0
while kill -0 "$GODOT_WRAP" 2>/dev/null; do
  child_kb=0
  while read -r pid; do
    [ -z "$pid" ] && continue
    kb="$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
    if [ -n "${kb:-}" ]; then
      child_kb=$((child_kb + kb))
    fi
  done < <(pgrep -f 'WindowedMv1CardUpInputGuard|Godot_v4' 2>/dev/null || true)
  if [ "${child_kb:-0}" -gt "$peak_kb" ]; then
    peak_kb="$child_kb"
  fi
  echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$RSS_LOG"
  sleep 5
done
wait "$GODOT_WRAP"
code=$?
echo "EOA_MV1_CARD_UP_INPUT_GUARD who=wrapper.rss peak_kb=$peak_kb mb=$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}') (NOT live Play)"
echo "peak_kb=$peak_kb" >> "$RSS_LOG"
exit "$code"
