#!/usr/bin/env bash
# Windowed campaign-loop chrome and end-screen guard.
# Private Xvfb only (xvfb-run -a). Never the live :0 desktop.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if pgrep -af '[g]odot' >/dev/null; then
  echo "GODOT_BUSY" >&2
  pgrep -af '[g]odot' >&2
  exit 2
fi
GODOT=(flock -n "${HOME}/.eoa_godot.lock" "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 -s res://scripts/core/WindowedCampaignLoop1EndScreenGuard.gd "$@")
if command -v xvfb-run >/dev/null 2>&1; then
  exec xvfb-run -a -s "-screen 0 1280x800x24" "${GODOT[@]}"
fi
if ! command -v gamescope >/dev/null 2>&1; then
  echo "WindowedCampaignLoop1EndScreenGuard: RESULT=FAIL need xvfb-run or gamescope" >&2
  exit 1
fi
# This PC has no Xvfb binary and no sudo. gamescope --backend headless
# owns a private Xwayland and does not open a window on the live desktop.
# gamescope can segfault on teardown after the child has already passed.
echo "CL1 chrome display=gamescope-headless (Xvfb not installed)" >&2
tmp="$(mktemp)"
set +e
env -u DISPLAY -u WAYLAND_DISPLAY \
  gamescope --backend headless -W 1280 -H 800 -w 1280 -h 800 -- "${GODOT[@]}" >"$tmp" 2>&1
ec=$?
set -e
cat "$tmp"
if grep -q "RESULT=PASS" "$tmp" && ! grep -q "SCRIPT ERROR" "$tmp"; then
  rm -f "$tmp"
  exit 0
fi
rm -f "$tmp"
exit "$ec"
