#!/usr/bin/env bash
# RENDER-1 prebuild role map vs fresh L-on compute (per pid, not histogram).
# Tip must PASS. Mutants lon_semantics_off and allow_without_overlay must FAIL
# by per-pid role mismatch (allow_without_overlay is behavioural: unowned
# infra-pressure pids). No self-report flag.
#
#   tools/eoa_render1_prebuild_role.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT=(tools/run_godot.sh --headless --path . --resolution 1280x740
  -s res://scripts/core/HeadlessRender1PrebuildRoleTest.gd)

echo "EOA_RENDER1_PREBUILD_ROLE who=wrapper tip+2 mutants"

echo "EOA_RENDER1_PREBUILD_ROLE who=tip"
if EOA_RENDER1_PREBUILD_MUTANT= "${GODOT[@]}"; then
  echo "EOA_RENDER1_PREBUILD_ROLE who=tip RESULT=PASS"
else
  echo "EOA_RENDER1_PREBUILD_ROLE who=tip RESULT=FAIL (want PASS)"
  exit 1
fi

echo "EOA_RENDER1_PREBUILD_ROLE who=mutant.lon_semantics_off"
if EOA_RENDER1_PREBUILD_MUTANT=lon_semantics_off "${GODOT[@]}"; then
  echo "EOA_RENDER1_PREBUILD_ROLE who=mutant.lon_semantics_off RESULT=PASS (want FAIL)"
  exit 1
else
  echo "EOA_RENDER1_PREBUILD_ROLE who=mutant.lon_semantics_off RESULT=FAIL (killed)"
fi

echo "EOA_RENDER1_PREBUILD_ROLE who=mutant.allow_without_overlay"
if EOA_RENDER1_PREBUILD_MUTANT=allow_without_overlay "${GODOT[@]}"; then
  echo "EOA_RENDER1_PREBUILD_ROLE who=mutant.allow_without_overlay RESULT=PASS (want FAIL)"
  exit 1
else
  echo "EOA_RENDER1_PREBUILD_ROLE who=mutant.allow_without_overlay RESULT=FAIL (killed)"
fi

echo "HeadlessRender1PrebuildRoleTest: RESULT=PASS tip green, both mutants red"
exit 0
