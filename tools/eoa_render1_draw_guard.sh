#!/usr/bin/env bash
# WINDOWED RENDER-1 draw-call + cold-L guard. xvfb is NOT product Play.
# Engine L-on vs L-off draw delta must be >= mesh_calls (392 on the tip).
# A 0 count is FAIL. No grep fallback. counter_lie is a source edit in the test.
#
#   tools/eoa_render1_draw_guard.sh
#   EOA_RENDER1_DRAW_OUT=/tmp/eoa-render1-draw tools/eoa_render1_draw_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_RENDER1_DRAW_OUT:-/tmp/eoa-render1-draw}"
mkdir -p "$OUT"
export EOA_RENDER1_DRAW_OUT="$OUT"
echo "EOA_RENDER1_DRAW_GUARD who=wrapper out=$OUT xvfb=1 (NOT product Play)"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedRender1DrawGuard: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
RSS_LOG="$OUT/rss.txt"
: > "$RSS_LOG"
xvfb-run -a -s "-screen 0 1280x740x24" \
  "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x740 \
  -s res://scripts/core/WindowedRender1DrawGuard.gd "$@" &
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
  done < <(pgrep -f 'WindowedRender1DrawGuard|Godot_v4' 2>/dev/null || true)
  if [ "${child_kb:-0}" -gt "$peak_kb" ]; then
    peak_kb="$child_kb"
  fi
  echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$RSS_LOG"
  sleep 2
done
wait "$GODOT_WRAP"
code=$?
echo "EOA_RENDER1_DRAW_GUARD who=wrapper.rss peak_kb=$peak_kb mb=$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}') (NOT product Play)"
echo "peak_kb=$peak_kb" >> "$RSS_LOG"
exit "$code"
