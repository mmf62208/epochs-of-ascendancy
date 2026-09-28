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
# Keep January 1936 for the 3x3 matrix — companion past-+6 is implied by AUTO_BEGIN.
export EOA_SMOKE_ADVANCE_PAST_PLUS6=0
unset EOA_SKIP_TITLE || true
echo "EOA_RT1_PIXEL_GUARD who=wrapper out=$OUT xvfb=1 (NOT product Begin/Esc/clock PASS)"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedRt1RoadTierPixelGuard: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
# Sample Godot RSS while the xvfb harness runs (FileAccess /proc can miss).
RSS_LOG="$OUT/rss.txt"
: > "$RSS_LOG"
xvfb-run -a -s "-screen 0 1280x720x24" \
  "${ROOT}/tools/run_godot.sh" --path . \
  -s res://scripts/core/WindowedRt1RoadTierPixelGuard.gd "$@" &
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
  done < <(pgrep -f 'WindowedRt1RoadTierPixelGuard|Godot_v4' 2>/dev/null || true)
  if [ "${child_kb:-0}" -gt "$peak_kb" ]; then
    peak_kb="$child_kb"
  fi
  echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$RSS_LOG"
  sleep 5
done
wait "$GODOT_WRAP"
code=$?
echo "EOA_RT1_PIXEL_GUARD who=wrapper.rss peak_kb=$peak_kb mb=$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}') (NOT product Play)"
echo "peak_kb=$peak_kb" >> "$RSS_LOG"
exit "$code"
