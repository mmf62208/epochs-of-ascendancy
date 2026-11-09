#!/usr/bin/env bash
# CAMPAIGN-SAVE-1 P1 standing gate: mid-war SaveStateHash identity after a
# fresh-session load, 60-day no-save twin, and mutants that drop marches/wars.
# One Godot, launched only through tools/run_godot.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if pgrep -af '[g]odot|[G]odot' >/dev/null; then
  echo "GODOT_BUSY" >&2
  pgrep -af '[g]odot|[G]odot' >&2
  exit 2
fi
tmp="$(mktemp)"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$(mktemp -d)}"
export EOA_CALENDAR_AUTOSAVE="${EOA_CALENDAR_AUTOSAVE:-0}"
export SR1_DET_MODE="${SR1_DET_MODE:-identity_twin}"
set +e
timeout 900 flock -n "${HOME}/.eoa_godot.lock" \
  "${ROOT}/tools/run_godot.sh" --headless --path . \
  -s res://scripts/core/HeadlessSaveReload1DeterminismTest.gd >"$tmp" 2>&1
ec=$?
set -e
cat "$tmp"
if grep -q "SCRIPT ERROR" "$tmp"; then
  rm -f "$tmp"
  echo "HeadlessSaveReload1DeterminismTest: RESULT=FAIL script error" >&2
  exit 1
fi
if [[ "$ec" -eq 124 ]]; then
  rm -f "$tmp"
  echo "HeadlessSaveReload1DeterminismTest: RESULT=FAIL timeout" >&2
  exit 1
fi
if [[ "$ec" -ne 0 ]]; then
  rm -f "$tmp"
  exit "$ec"
fi
if ! grep -q "RESULT=PASS" "$tmp"; then
  rm -f "$tmp"
  echo "HeadlessSaveReload1DeterminismTest: RESULT=FAIL missing PASS" >&2
  exit 1
fi
if ! grep -q "IDENTITY MATCH" "$tmp"; then
  rm -f "$tmp"
  echo "HeadlessSaveReload1DeterminismTest: RESULT=FAIL missing IDENTITY MATCH" >&2
  exit 1
fi
if [[ "${SR1_SKIP_TWIN:-}" != "1" ]]; then
  if ! grep -q "TRACE_MD5 identity-twin" "$tmp"; then
    rm -f "$tmp"
    echo "HeadlessSaveReload1DeterminismTest: RESULT=FAIL missing 60-day twin" >&2
    exit 1
  fi
  if grep -q "identity-twin trace diverged" "$tmp"; then
    rm -f "$tmp"
    echo "HeadlessSaveReload1DeterminismTest: RESULT=FAIL 60-day twin diverged" >&2
    exit 1
  fi
fi
if [[ "${SR1_SKIP_MUTANT:-}" != "1" ]]; then
  if ! grep -q "MUTANT_FAIL drop_marches" "$tmp"; then
    rm -f "$tmp"
    echo "HeadlessSaveReload1DeterminismTest: RESULT=FAIL mutant drop_marches did not bite" >&2
    exit 1
  fi
  if ! grep -q "MUTANT_FAIL drop_wars" "$tmp"; then
    rm -f "$tmp"
    echo "HeadlessSaveReload1DeterminismTest: RESULT=FAIL mutant drop_wars did not bite" >&2
    exit 1
  fi
fi
rm -f "$tmp"
echo "PASS: campaign-save-1 identity + 60-day twin"
exit 0
