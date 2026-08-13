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
exec "$GODOT" --path "$ROOT" "$@"
