#!/usr/bin/env bash
# Launch project with newest installed Godot (prefers 4.7.1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANDIDATES=(
  "${HOME}/Applications/Godot-4.7.1/Godot_v4.7.1-rc2_linux.x86_64"
  "${HOME}/Applications/Godot-4.7.1/godot"
  "${HOME}/Applications/godot-latest"
  "${HOME}/Applications/Godot-4.7/Godot_v4.7-stable_linux.x86_64"
)
GODOT=""
for c in "${CANDIDATES[@]}"; do
  if [[ -x "$c" ]]; then GODOT="$c"; break; fi
done
if [[ -z "$GODOT" ]]; then
  echo "No Godot binary found under ~/Applications/Godot-4.7*"
  exit 1
fi
echo "Using: $GODOT ($($GODOT --version 2>/dev/null || true))"

# Fresh checkout / stale .godot class cache: GameData used to parse-fail with
# 'Identifier Rx1RhineCrossing not declared' and a blank map until an editor
# import ran (Play MIXED 9750f3d attempt 1). One-time --headless --import when
# the cache is missing or lacks the new class. Autoloads also preload by path.
CACHE="${ROOT}/.godot/global_script_class_cache.cfg"
NEED_IMPORT=0
already_import=0
for a in "$@"; do
  if [[ "$a" == "--import" ]]; then
    already_import=1
    break
  fi
done
if [[ "$already_import" -eq 0 ]]; then
  if [[ ! -f "$CACHE" ]]; then
    NEED_IMPORT=1
  elif ! grep -q 'Rx1RhineCrossing' "$CACHE" 2>/dev/null; then
    NEED_IMPORT=1
  fi
fi
if [[ "$NEED_IMPORT" -eq 1 ]]; then
  echo "run_godot: class cache missing Rx1RhineCrossing — one-time --headless --import"
  "$GODOT" --path "$ROOT" --headless --import --quit
fi

exec "$GODOT" --path "$ROOT" "$@"
