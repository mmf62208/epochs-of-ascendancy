#!/bin/bash
# scripts/qa/compile_clean_gate.sh
# Per strategist rec for compile-clean first (no feature/capture/docs until 0 errors).
# Runs godot --headless --check-only (with common EOA_ envs for consistency).
# Captures to implementer/godot_check_gate_*.log ; greps for SCRIPT ERROR / Compile Error / Parse Error.
# Exits 1 (fail) if any found; 0 only on clean (preexist icon/ship/quit warnings ok if no critical).
# Usage: ./scripts/qa/compile_clean_gate.sh
# Call before any harness/docs/capture work. Re-run after mechanical fixes.
# Never edit this to relax; mechanical fixes only until passes.

set -euo pipefail

SCRATCH="/tmp/grok-goal-9c49c808a2ad/implementer"
mkdir -p "$SCRATCH"

TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRATCH/godot_check_gate_${TS}.log"

CANONICAL='org.godotengine.Godot --headless --check-only scenes/TestScenario.tscn'

echo "=== compile_clean_gate.sh (per rec #1: FAIL on any SCRIPT/COMPILE until 0) ==="
echo "Env: EOA_WORLD_HYBRID=1 EOA_HEADLESS_EVIDENCE=1"
echo "Cmd: flatpak run --env=... $CANONICAL"
echo "Log: $LOG"
echo ""

timeout 120s flatpak run --env=EOA_WORLD_HYBRID=1 --env=EOA_HEADLESS_EVIDENCE=1 $CANONICAL 2>&1 | cat > "$LOG" || true
EXIT=$?
echo "Check exit: $EXIT ; lines: $(wc -l < "$LOG")"

ERROR_COUNT=$(grep -ciE 'SCRIPT ERROR|Compile Error|Parse Error|Failed to compile' "$LOG" 2>/dev/null || true)
echo "Critical errors (SCRIPT/COMPILE/PARSE): $ERROR_COUNT"

if [[ $ERROR_COUNT -gt 0 ]]; then
  echo "GATE FAIL: $ERROR_COUNT critical errors found. See $LOG (top errors below)"
  grep -E 'SCRIPT ERROR|Compile Error|Parse Error' "$LOG" | head -20
  echo "Fix mechanical (no events/harness/docs changes) then re-run gate."
  exit 1
else
  echo "GATE PASS: 0 critical SCRIPT/COMPILE errors (preexist icon/ship/quit warnings may appear but are non-fatal)."
  echo "Now safe for next steps per rec (mechanical fixes done, or proceed to harness collapse if already clean)."
  exit 0
fi
