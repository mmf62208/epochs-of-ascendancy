#!/usr/bin/env bash
# CLOSE-1 / CLOSE-1b stale-drag-after-Close + first-edge leftover guard.
# Headless + xvfb. CLOSE-1b: leftover suppress+GIS + immediate y=0.
# xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
#
#   tools/eoa_close1_guard.sh
#   EOA_CLOSE1_OUT=/tmp/eoa-close1 tools/eoa_close1_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_CLOSE1_OUT:-/tmp/eoa-close1}"
mkdir -p "$OUT"
export EOA_CLOSE1_OUT="$OUT"
unset EOA_SKIP_TITLE || true
SCRIPT="res://scripts/core/HeadlessClose1StaleDragGuardTest.gd"
echo "EOA_CLOSE1_GUARD who=wrapper out=$OUT (NOT live Play / NOT Vulkan product)"

run_one() {
  local mode="$1"
  local log="$OUT/${mode}.log"
  local rss_log="$OUT/${mode}_rss.txt"
  local code=0
  : > "$rss_log"
  if [[ "$mode" == "xvfb" ]]; then
    if ! command -v xvfb-run >/dev/null 2>&1; then
      echo "HeadlessClose1StaleDragGuardTest: RESULT=FAIL need xvfb-run" >&2
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
    done < <(pgrep -f 'HeadlessClose1StaleDragGuardTest|Godot_v4' 2>/dev/null || true)
    if [ "${child_kb:-0}" -gt "$peak_kb" ]; then
      peak_kb="$child_kb"
    fi
    echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$rss_log"
    sleep 1
  done
  wait "$wrap" || code=$?
  local mb
  mb="$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}')"
  echo "EOA_CLOSE1 who=${mode}.rss peak_kb=$peak_kb mb=$mb (NOT live Play)"
  if ! grep -q "HeadlessClose1StaleDragGuardTest: RESULT=PASS" "$log"; then
    echo "CLOSE-1 ${mode}: RESULT=FAIL (no RESULT=PASS) code=$code log=$log"
    tail -n 80 "$log" || true
    return 1
  fi
  if grep -Eiq "SCRIPT ERROR|SIGSEGV" "$log"; then
    echo "CLOSE-1 ${mode}: RESULT=FAIL (engine error) log=$log"
    grep -Ei "SCRIPT ERROR|SIGSEGV" "$log" || true
    return 1
  fi
  echo "CLOSE-1 ${mode}: RESULT=PASS rss_mb=$mb"
  return 0
}

fail=0
for mode in hd xvfb; do
  if ! run_one "$mode"; then
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo "EOA_CLOSE1_GUARD RESULT=FAIL"
  exit 1
fi
echo "EOA_CLOSE1_GUARD RESULT=PASS hd+xvfb (NOT live Play)"
exit 0
