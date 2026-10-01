#!/usr/bin/env bash
# CRASH-1 halt-march popup guard. Headless + xvfb, 10 repeats each.
# xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
#
#   tools/eoa_crash1_halt_march_guard.sh
#   EOA_CRASH1_OUT=/tmp/eoa-crash1 tools/eoa_crash1_halt_march_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_CRASH1_OUT:-/tmp/eoa-crash1}"
mkdir -p "$OUT"
export EOA_CRASH1_OUT="$OUT"
unset EOA_SKIP_TITLE || true
REPEATS="${EOA_CRASH1_REPEATS:-10}"
SCRIPT="res://scripts/core/HeadlessCrash1HaltMarchPopupTest.gd"
echo "EOA_CRASH1_HALT_MARCH_GUARD who=wrapper out=$OUT repeats=$REPEATS (NOT live Play / NOT Vulkan product)"

run_one() {
  local mode="$1"
  local idx="$2"
  local log="$OUT/${mode}_${idx}.log"
  local code=0
  if [[ "$mode" == "xvfb" ]]; then
    if ! command -v xvfb-run >/dev/null 2>&1; then
      echo "HeadlessCrash1HaltMarchPopupTest: RESULT=FAIL need xvfb-run" >&2
      return 1
    fi
    xvfb-run -a -s "-screen 0 1600x900x24" \
      "${ROOT}/tools/run_godot.sh" --path . -s "$SCRIPT" >"$log" 2>&1 || code=$?
  else
    "${ROOT}/tools/run_godot.sh" --headless --path . -s "$SCRIPT" >"$log" 2>&1 || code=$?
  fi
  if ! grep -q "HeadlessCrash1HaltMarchPopupTest: RESULT=PASS" "$log"; then
    echo "CRASH-1 ${mode} #${idx}: RESULT=FAIL (no RESULT=PASS) code=$code log=$log"
    tail -n 40 "$log" || true
    return 1
  fi
  if grep -Eiq "freed while a signal|object freed while|SIGSEGV|SCRIPT ERROR" "$log"; then
    echo "CRASH-1 ${mode} #${idx}: RESULT=FAIL (engine error) log=$log"
    grep -Ei "freed while a signal|object freed while|SIGSEGV|SCRIPT ERROR" "$log" || true
    return 1
  fi
  echo "CRASH-1 ${mode} #${idx}: RESULT=PASS"
  return 0
}

fail=0
for mode in hd xvfb; do
  i=1
  while [[ "$i" -le "$REPEATS" ]]; do
    if ! run_one "$mode" "$i"; then
      fail=1
    fi
    i=$((i + 1))
  done
done

if [[ "$fail" -ne 0 ]]; then
  echo "EOA_CRASH1_HALT_MARCH_GUARD RESULT=FAIL"
  exit 1
fi
echo "EOA_CRASH1_HALT_MARCH_GUARD RESULT=PASS repeats=$REPEATS hd+xvfb 0 errors (NOT live Play)"
exit 0
