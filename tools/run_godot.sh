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
# import ran (Play MIXED 9750f3d attempt 1). Rebuild when the cache is missing
# or any scripts/ class_name is absent. Quiet and idempotent when current.
# Autoloads also preload by path. SHIP_YIELD (inserted after the header comment
# by some gate copies) still runs first and waits for other Godot processes.
CACHE="${ROOT}/.godot/global_script_class_cache.cfg"
NEED_IMPORT=0
already_import=0
for a in "$@"; do
  if [[ "$a" == "--import" ]]; then
    already_import=1
    break
  fi
done

cache_missing_class() {
  local cache_file="$1"
  local scripts_dir="$2"
  if [[ ! -f "$cache_file" ]]; then
    return 0
  fi
  if [[ ! -d "$scripts_dir" ]]; then
    return 1
  fi
  local cache_text
  cache_text="$(<"$cache_file")"
  local cls
  while IFS= read -r cls; do
    [[ -z "$cls" ]] && continue
    case "$cache_text" in
      *"$cls"*) ;;
      *) return 0 ;;
    esac
  done < <(grep -R --include='*.gd' -h -E '^class_name[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$scripts_dir" 2>/dev/null | awk '{print $2}' | sort -u)
  return 1
}

if [[ "$already_import" -eq 0 ]]; then
  if cache_missing_class "$CACHE" "${ROOT}/scripts"; then
    NEED_IMPORT=1
  fi
fi
if [[ "$NEED_IMPORT" -eq 1 ]]; then
  echo "run_godot: class cache stale or missing — one-time --headless --import"
  "$GODOT" --path "$ROOT" --headless --import --quit
fi

exec "$GODOT" --path "$ROOT" "$@"
