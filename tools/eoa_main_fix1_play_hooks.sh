#!/usr/bin/env bash
# Dev-only MAIN-FIX-1 Play hooks. Off by default.
#
# Force a real GER capture of one POL border province through the live
# BattleManager light-capture path (confirms real captures still toast):
#
#   EOA_MAIN_FIX1_FORCE_CAPTURE=1 tools/run_godot.sh --path . res://scenes/TestScenario.tscn
#
# Open the campaign peace sheet and keep the window at least 600s:
#
#   EOA_MAIN_FIX1_PEACE_HOLD_S=600 tools/run_godot.sh --path . res://scenes/TestScenario.tscn
#
# Both flags can be combined. This wrapper only launches TestScenario with
# the flags you pass; it never turns them on by itself.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "${1:-}" == "--force-capture" ]]; then
  export EOA_MAIN_FIX1_FORCE_CAPTURE=1
  shift
fi
if [[ "${1:-}" == "--peace-hold" ]]; then
  export EOA_MAIN_FIX1_PEACE_HOLD_S="${EOA_MAIN_FIX1_PEACE_HOLD_S:-600}"
  shift
fi
if [[ -z "${EOA_MAIN_FIX1_FORCE_CAPTURE:-}" && -z "${EOA_MAIN_FIX1_PEACE_HOLD_S:-}" ]]; then
  echo "eoa_main_fix1_play_hooks: no flag set (off by default)." >&2
  echo "  --force-capture   or EOA_MAIN_FIX1_FORCE_CAPTURE=1" >&2
  echo "  --peace-hold      or EOA_MAIN_FIX1_PEACE_HOLD_S=600" >&2
  exit 2
fi
exec "${ROOT}/tools/run_godot.sh" --path . res://scenes/TestScenario.tscn "$@"
