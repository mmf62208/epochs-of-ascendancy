#!/usr/bin/env bash
# UI-1 Leaders close + edge pan + no-march-inspector guard.
# Headless + xvfb. xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
#
#   tools/eoa_ui1_guard.sh
#   EOA_UI1_OUT=/tmp/eoa-ui1 tools/eoa_ui1_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_UI1_OUT:-/tmp/eoa-ui1}"
mkdir -p "$OUT"
export EOA_UI1_OUT="$OUT"
unset EOA_SKIP_TITLE || true
SCRIPT="res://scripts/core/HeadlessUi1LeadersEdgePanMarchTest.gd"
echo "EOA_UI1_GUARD who=wrapper out=$OUT (NOT live Play / NOT Vulkan product)"

run_one() {
  local mode="$1"
  local log="$OUT/${mode}.log"
  local rss_log="$OUT/${mode}_rss.txt"
  local code=0
  : > "$rss_log"
  if [[ "$mode" == "xvfb" ]]; then
    if ! command -v xvfb-run >/dev/null 2>&1; then
      echo "HeadlessUi1LeadersEdgePanMarchTest: RESULT=FAIL need xvfb-run" >&2
      return 1
    fi
    xvfb-run -a -s "-screen 0 1280x740x24" \
      "${ROOT}/tools/run_godot.sh" --path . -s "$SCRIPT" >"$log" 2>&1 &
  else
    "${ROOT}/tools/run_godot.sh" --headless --path . -s "$SCRIPT" >"$log" 2>&1 &
  fi
  local wrap=$!
  local peak_kb=0
  while kill -0 "$wrap" 2>/dev/null; do
    local child_kb=0
    while read -r pid; do
      [ -z "$pid" ] && continue
      local kb
      kb="$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
      if [ -n "${kb:-}" ]; then
        child_kb=$((child_kb + kb))
      fi
    done < <(pgrep -f 'HeadlessUi1LeadersEdgePanMarchTest|Godot_v4' 2>/dev/null || true)
    if [ "${child_kb:-0}" -gt "$peak_kb" ]; then
      peak_kb="$child_kb"
    fi
    echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$rss_log"
    sleep 1
  done
  wait "$wrap" || code=$?
  local mb
  mb="$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}')"
  echo "EOA_UI1 who=${mode}.rss peak_kb=$peak_kb mb=$mb (NOT live Play)"
  if ! grep -q "HeadlessUi1LeadersEdgePanMarchTest: RESULT=PASS" "$log"; then
    echo "UI-1 ${mode}: RESULT=FAIL (no RESULT=PASS) code=$code log=$log"
    tail -n 60 "$log" || true
    return 1
  fi
  if grep -Eiq "SCRIPT ERROR|SIGSEGV" "$log"; then
    echo "UI-1 ${mode}: RESULT=FAIL (engine error) log=$log"
    grep -Ei "SCRIPT ERROR|SIGSEGV" "$log" || true
    return 1
  fi
  echo "UI-1 ${mode}: RESULT=PASS rss_mb=$mb"
  return 0
}

fail=0
for mode in hd xvfb; do
  if ! run_one "$mode"; then
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo "EOA_UI1_GUARD RESULT=FAIL"
  exit 1
fi
echo "EOA_UI1_GUARD RESULT=PASS hd+xvfb (NOT live Play)"
exit 0
