#!/usr/bin/env bash
# WINDOWED RH-1 resource-glyph pixel guard. Smoke harness is not the product.
# xvfb / llvmpipe / OpenGL is NOT live Play.
# Never EOA_SKIP_TITLE. Uses EOA_SMOKE_AUTO_BEGIN only to dismiss the living title.
#
#   tools/eoa_rh1_pixel_guard.sh
#   EOA_RH1_PIXEL_OUT=/tmp/eoa-rh1-pixel tools/eoa_rh1_pixel_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_RH1_PIXEL_OUT:-/tmp/eoa-rh1-pixel}"
mkdir -p "$OUT"
export EOA_RH1_PIXEL_OUT="$OUT"
export EOA_SMOKE_AUTO_BEGIN=1
export EOA_SMOKE_ADVANCE_PAST_PLUS6=0
unset EOA_SKIP_TITLE || true
echo "EOA_RH1_PIXEL_GUARD who=wrapper out=$OUT xvfb=1 screen=1600x900 (NOT live Play / NOT Vulkan product)"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedRh1ResourceGlyphPixelGuard: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
RSS_LOG="$OUT/rss.txt"
: > "$RSS_LOG"
xvfb-run -a -s "-screen 0 1600x900x24" \
  "${ROOT}/tools/run_godot.sh" --path . \
  -s res://scripts/core/WindowedRh1ResourceGlyphPixelGuard.gd "$@" &
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
  done < <(pgrep -f 'WindowedRh1ResourceGlyphPixelGuard|Godot_v4' 2>/dev/null || true)
  if [ "${child_kb:-0}" -gt "$peak_kb" ]; then
    peak_kb="$child_kb"
  fi
  echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$RSS_LOG"
  sleep 5
done
wait "$GODOT_WRAP"
code=$?
echo "EOA_RH1_PIXEL_GUARD who=wrapper.rss peak_kb=$peak_kb mb=$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}') (NOT live Play)"
echo "peak_kb=$peak_kb" >> "$RSS_LOG"
if [ "$peak_kb" -ge $((3000 * 1024)) ]; then
  echo "WindowedRh1ResourceGlyphPixelGuard: RESULT=FAIL rss_over_3gb peak_kb=$peak_kb" >&2
  exit 1
fi
exit "$code"
