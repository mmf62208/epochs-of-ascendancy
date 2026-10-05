#!/usr/bin/env bash
# ORDERS-1 Halt / Hold / Withdraw play-loop guard. Headless (+ xvfb if present).
# xvfb / llvmpipe is NOT live Play. Never EOA_SKIP_TITLE.
#
#   tools/eoa_orders1_guard.sh
#   EOA_ORDERS1_OUT=/tmp/eoa-orders1 tools/eoa_orders1_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_ORDERS1_OUT:-/tmp/eoa-orders1}"
mkdir -p "$OUT"
export EOA_ORDERS1_OUT="$OUT"
unset EOA_SKIP_TITLE || true
REPEATS="${EOA_ORDERS1_REPEATS:-1}"
SCRIPT="res://scripts/core/HeadlessOrders1HaltHoldWithdrawTest.gd"
echo "EOA_ORDERS1_GUARD who=wrapper out=$OUT repeats=$REPEATS (NOT live Play / NOT Vulkan product)"

run_one() {
  local mode="$1"
  local idx="$2"
  local log="$OUT/${mode}_${idx}.log"
  local code=0
  if [[ "$mode" == "xvfb" ]]; then
    if ! command -v xvfb-run >/dev/null 2>&1; then
      echo "HeadlessOrders1HaltHoldWithdrawTest: RESULT=SKIP no xvfb-run"
      return 0
    fi
    xvfb-run -a -s "-screen 0 1280x740x24" \
      "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x740 -s "$SCRIPT" >"$log" 2>&1 || code=$?
  else
    "${ROOT}/tools/run_godot.sh" --headless --path . --resolution 1280x740 -s "$SCRIPT" >"$log" 2>&1 || code=$?
  fi
  if ! grep -q "HeadlessOrders1HaltHoldWithdrawTest: RESULT=PASS" "$log"; then
    echo "ORDERS-1 ${mode} #${idx}: RESULT=FAIL (no RESULT=PASS) code=$code log=$log"
    tail -n 60 "$log" || true
    return 1
  fi
  if grep -Eiq "freed while a signal|object freed while|SIGSEGV|SCRIPT ERROR" "$log"; then
    echo "ORDERS-1 ${mode} #${idx}: RESULT=FAIL (engine error) log=$log"
    grep -Ei "freed while a signal|object freed while|SIGSEGV|SCRIPT ERROR" "$log" || true
    return 1
  fi
  echo "ORDERS-1 ${mode} #${idx}: RESULT=PASS"
  return 0
}

fail=0
if ! run_one "hd" "1"; then
  fail=1
fi
if command -v xvfb-run >/dev/null 2>&1; then
  i=1
  while [[ "$i" -le "$REPEATS" ]]; do
    if ! run_one "xvfb" "$i"; then
      fail=1
    fi
    i=$((i + 1))
  done
fi

if [[ "$fail" -ne 0 ]]; then
  echo "EOA_ORDERS1_GUARD RESULT=FAIL"
  exit 1
fi
echo "EOA_ORDERS1_GUARD RESULT=PASS (NOT live Play)"
exit 0
