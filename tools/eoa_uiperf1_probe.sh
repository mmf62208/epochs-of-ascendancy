#!/usr/bin/env bash
# UI-PERF-1 windowed probe. gamescope headless 1280x800. Isolated XDG.
# Not live Play. One Godot. Does not kill a Godot this script did not start.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if pgrep -af '[g]odot' >/dev/null; then
  echo "GODOT_BUSY" >&2
  pgrep -af '[g]odot' >&2
  exit 2
fi
OUT="${1:-${HOME}/uiperf1/evidence/probe.json}"
mkdir -p "$(dirname "$OUT")"
if ! command -v gamescope >/dev/null 2>&1; then
  echo "WindowedUiPerf1Probe: RESULT=FAIL need gamescope" >&2
  exit 1
fi
XDG_DATA_HOME="$(mktemp -d)"
XDG_CONFIG_HOME="$(mktemp -d)"
XDG_CACHE_HOME="$(mktemp -d)"
export XDG_DATA_HOME XDG_CONFIG_HOME XDG_CACHE_HOME
echo "UI_PERF1 xdg_data=$XDG_DATA_HOME out=$OUT" >&2
console="${OUT}.console"
set +e
env -u DISPLAY -u WAYLAND_DISPLAY \
  gamescope --backend headless -W 1280 -H 800 -w 1280 -h 800 -- \
  flock -n "${HOME}/.eoa_godot.lock" "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 \
  -s res://scripts/core/WindowedUiPerf1Probe.gd -- --out "$OUT" >"$console" 2>&1
ec=$?
set -e
cat "$console"
# gamescope can segfault on teardown after the child already printed a result.
if [[ -f "$OUT" ]] && grep -q 'UI_PERF1 RESULT=' "$OUT".log 2>/dev/null; then
  exit 0
fi
exit "$ec"
