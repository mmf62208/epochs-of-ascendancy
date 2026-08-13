#!/bin/bash
# scripts/qa/capture_events_50t.sh
# Per strategist restructure for reproducible events/wiring 50T evidence.
# Runs the canonical godot headless RUN_EVENTS_50T cmd TWICE (new timestamped files under implementer/ only).
# Never overwrites events_50t_run1.log etc manually.
# Greps for verif plan reqs: EVENTS WIRING COMPLETE=1, 50T SIM PROGRESS count (x8+ distinct t), organic [NEW EVENTS MONTHLY] + specific PROCESS CALLs from GameData (no injected meta), 0 fatal/crash.
# Usage: ./scripts/qa/capture_events_50t.sh
# Then inspect the new timestamped .log in /tmp/grok-goal-9c49c808a2ad/implementer/ .
# Updates TESTING_PLAN/CURRENT_STATE; run this for events evidence.

set -euo pipefail

SCRATCH="/tmp/grok-goal-9c49c808a2ad/implementer"
mkdir -p "$SCRATCH"

TS=$(date +%Y%m%d_%H%M%S)
LOG1="$SCRATCH/events_50t_${TS}_run1.log"
LOG2="$SCRATCH/events_50t_${TS}_run2.log"

CANONICAL_CMD='org.godotengine.Godot --headless scenes/TestScenario.tscn'

echo "=== capture_events_50t.sh starting (per restructure for real 50T events/wiring) ==="
echo "Env: EOA_WORLD_HYBRID=1 EOA_RUN_EVENTS_50T=1"
echo "Canonical: flatpak run --env=... $CANONICAL_CMD (twice, new timestamped logs only)"
echo "Logs will be: $LOG1 and $LOG2"
echo ""

# Run 1
echo "=== RUN 1 ($TS) ==="
timeout 600s flatpak run --env=EOA_WORLD_HYBRID=1 --env=EOA_RUN_EVENTS_50T=1 $CANONICAL_CMD 2>&1 | cat > "$LOG1" || true
echo "Run1 exit: $?"
wc -l "$LOG1"

# Run 2
echo ""
echo "=== RUN 2 ($TS) ==="
timeout 600s flatpak run --env=EOA_WORLD_HYBRID=1 --env=EOA_RUN_EVENTS_50T=1 $CANONICAL_CMD 2>&1 | cat > "$LOG2" || true
echo "Run2 exit: $?"
wc -l "$LOG2"

echo ""
echo "=== GREP RESULTS (verif plan step2 reqs) ==="
for log in "$LOG1" "$LOG2"; do
  echo "File: $log"
  complete_count=$(grep -c "\[EventsWiringHarness\] INTEGRATED COMPLETE" "$log" 2>/dev/null || true); complete_count=${complete_count:-0}
  progress_count=$(grep -c "\[50T SIM PROGRESS\]" "$log" 2>/dev/null || true); progress_count=${progress_count:-0}
  new_monthly=$(grep -c "\[NEW EVENTS MONTHLY\]" "$log" 2>/dev/null || true); new_monthly=${new_monthly:-0}
  backlash=$(grep -c "\[50T NEW EVENTS BACKLASH\]" "$log" 2>/dev/null || true); backlash=${backlash:-0}
  nuclear_proc=$(grep -c "NUCLEAR BACKLASH PROCESS CALL" "$log" 2>/dev/null || true); nuclear_proc=${nuclear_proc:-0}
  chem_proc=$(grep -c "CHEMICAL WARFARE PROCESS CALL" "$log" 2>/dev/null || true); chem_proc=${chem_proc:-0}
  fatal_count=$(grep -ci "fatal\|error\|crash\|script error\|traceback" "$log" 2>/dev/null || true); fatal_count=${fatal_count:-0}
  echo "  COMPLETE count: $complete_count (req: 1)"
  echo "  [50T SIM PROGRESS] count: $progress_count (req: >=8 distinct for 50d)"
  echo "  [NEW EVENTS MONTHLY] count: $new_monthly (req: >=1 organic from GameData)"
  echo "  [50T NEW EVENTS BACKLASH] count: $backlash (0 expected in slim harness path; meta string from integrated only)"
  echo "  NUCLEAR/CHEM PROCESS CALL counts: $nuclear_proc / $chem_proc (req: >0 for key backlashes)"
  echo "  fatal/crash/error count (case-insens): $fatal_count (req: 0; leaks preexist ok)"
  if [[ $complete_count -ge 1 && $progress_count -ge 8 && $new_monthly -ge 1 && $fatal_count -eq 0 ]]; then
    echo "  STATUS: PASS for this log (harness path core criteria)"
  else
    echo "  STATUS: FAIL (see counts; need real loop t increments + GameData prints + no crash)"
  fi
  echo ""
done

echo "=== Done. Inspect timestamped logs in $SCRATCH for organic markers from single harness path (EventsWiringHarness.run_for_env + real GameData monthly). Do not hand-edit or copy check-only into run1. ==="
echo "To update plan verif: append re-exec observations from these new logs (not old)."

ls -l "$LOG1" "$LOG2" | cat
