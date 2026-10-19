#!/usr/bin/env bash
# Windowed save/load UI guard. Private display only. Never the live :0 desktop.
# This PC has no Xvfb binary (same as the CL1 end-screen guard). gamescope
# --backend headless owns a private Xwayland and does not open a window on :0.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if pgrep -f 'Godot_v4|godot --headless|godot --path' >/dev/null 2>&1; then
  echo "GODOT_BUSY" >&2
  pgrep -af 'Godot_v4|godot --headless|godot --path' >&2 || true
  exit 2
fi
EVID="${EOA_EVIDENCE_DIR:-}"
if [[ -z "$EVID" ]]; then
  EVID="/tmp/eoa_sr1_evidence"
fi
export EOA_EVIDENCE_DIR="$EVID"
LOG="${EVID}/logs/sr1_ui_guard.log"
mkdir -p "${EVID}/logs" "$EVID"
GODOT=(flock "${HOME}/.eoa_godot.lock" "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 -s res://scripts/core/WindowedSaveReload1UiGuard.gd)
if command -v Xvfb >/dev/null 2>&1; then
  disp=24
  while [[ -e "/tmp/.X11-unix/X${disp}" ]]; do
    disp=$((disp + 1))
  done
  Xvfb ":${disp}" -screen 0 1280x800x24 >/tmp/eoa-sr1-xvfb.log 2>&1 &
  xvfb_pid=$!
  sleep 0.4
  export DISPLAY=":${disp}"
  set +e
  "${GODOT[@]}" >"$LOG" 2>&1
  ec=$?
  set -e
  kill "$xvfb_pid" 2>/dev/null || true
  cat "$LOG"
  exit "$ec"
fi
if ! command -v gamescope >/dev/null 2>&1; then
  echo "WindowedSaveReload1UiGuard: RESULT=FAIL need Xvfb or gamescope" >&2
  exit 1
fi
echo "SR1 ui display=gamescope-headless (Xvfb not installed)" >&2
set +e
env -u DISPLAY -u WAYLAND_DISPLAY \
  gamescope --backend headless -W 1280 -H 800 -w 1280 -h 800 -- "${GODOT[@]}" >"$LOG" 2>&1
ec=$?
set -e
cat "$LOG"
if grep -q "RESULT=PASS" "$LOG" && ! grep -q "SCRIPT ERROR" "$LOG"; then
  exit 0
fi
exit "$ec"
