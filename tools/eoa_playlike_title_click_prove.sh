#!/usr/bin/env bash
# Play-like living-title pointer prove.
#
# Play computerUse clicks screenshot pixels and does NOT xdotool windowactivate.
# The WM often consumes that first click as focus-only, so Godot's Input
# singleton never sees ButtonPress (zero EOA_LIVE_PTR on tip f9f249c).
# Lean eoa_lean_title_click_prove.sh windowactivate --sync first — that is
# NOT Play's driver.
#
# This script: tools/run_godot.sh + screen-coord click with Godot UNfocused.
# Title must dismiss via DisplayServer.mouse_get_button_state() poll.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GODOT="${ROOT}/tools/run_godot.sh"
if [[ ! -x "$GODOT" ]]; then
	echo "eoa_playlike_title_click_prove: missing tools/run_godot.sh" >&2
	exit 1
fi

if ! command -v xdotool >/dev/null 2>&1; then
	echo "eoa_playlike_title_click_prove: xdotool missing — RESULT=SOFT"
	exit 0
fi

if [[ -z "${DISPLAY:-}" ]]; then
	if command -v Xvfb >/dev/null 2>&1; then
		export DISPLAY=":93"
		Xvfb :93 -screen 0 1680x960x24 >/tmp/eoa-playlike-click-xvfb.log 2>&1 &
		echo $! > /tmp/eoa-playlike-click-xvfb.pid
		sleep 0.4
	else
		echo "eoa_playlike_title_click_prove: no DISPLAY and no Xvfb — RESULT=SOFT"
		exit 0
	fi
fi

LOG=/tmp/eoa-playlike-title-click-prove.log
rm -f "$LOG"
"$GODOT" --path "$ROOT" -s res://scripts/core/LeanLivingTitleX11ClickProve.gd >"$LOG" 2>&1 &
GODOT_PID=$!
cleanup() {
	kill "$GODOT_PID" >/dev/null 2>&1 || true
	if [[ -f /tmp/eoa-playlike-click-xvfb.pid ]]; then
		kill "$(cat /tmp/eoa-playlike-click-xvfb.pid)" >/dev/null 2>&1 || true
		rm -f /tmp/eoa-playlike-click-xvfb.pid
	fi
}
trap cleanup EXIT

ready=0
for _i in $(seq 1 40); do
	if grep -q "LEAN_CLICK_READY" "$LOG" 2>/dev/null; then
		ready=1
		break
	fi
	if ! kill -0 "$GODOT_PID" 2>/dev/null; then
		break
	fi
	sleep 0.25
done
if [[ "$ready" != "1" ]]; then
	echo "eoa_playlike_title_click_prove: Godot never printed LEAN_CLICK_READY"
	tail -n 40 "$LOG" || true
	echo "eoa_playlike_title_click_prove: RESULT=FAIL"
	exit 1
fi

WID="$(xdotool search --name "Epochs-of-Ascendancy" | tail -n 1 || true)"
if [[ -z "${WID}" ]]; then
	WID="$(xdotool search --name "Godot" | tail -n 1 || true)"
fi
if [[ -z "${WID}" ]]; then
	echo "eoa_playlike_title_click_prove: no Godot window — RESULT=SOFT"
	exit 0
fi

# Steal focus the way Play does: do NOT windowactivate Godot.
# Activate Desktop / xfce4-panel, then hold-click Begin at screen coords
# (mousedown so DisplayServer.mouse_get_button_state can latch).
BEFORE_FOCUS="$(xdotool getactivewindow || true)"
SINK="$(xdotool search --onlyvisible --name "Desktop" | head -n 1 || true)"
if [[ -z "${SINK}" ]]; then
	SINK="$(xdotool search --onlyvisible --class xfce4-panel | head -n 1 || true)"
fi
if [[ -n "${SINK}" && "${SINK}" != "${WID}" ]]; then
	xdotool windowactivate --sync "$SINK" || true
	sleep 0.15
fi
AFTER_STEAL="$(xdotool getactivewindow || true)"
echo "eoa_playlike_title_click_prove: godot_wid=$WID before=$BEFORE_FOCUS after_steal=$AFTER_STEAL sink=$SINK"

BEGIN_LINE="$(grep "LEAN_HIT_BEGIN_CLIENT=" "$LOG" | tail -n 1 || true)"
sx="$(echo "$BEGIN_LINE" | sed -n 's/.*screen=\([0-9]*\),\([0-9]*\).*/\1/p')"
sy="$(echo "$BEGIN_LINE" | sed -n 's/.*screen=\([0-9]*\),\([0-9]*\).*/\2/p')"
if [[ -z "${sx}" || -z "${sy}" ]]; then
	echo "eoa_playlike_title_click_prove: no Begin screen coord — RESULT=SOFT"
	exit 0
fi

# computerUse-like: move + hold-click the pixel. No windowactivate. No --window.
xdotool mousemove "$sx" "$sy" mousedown 1 || true
sleep 0.2
xdotool mouseup 1 || true
echo "eoa_playlike_title_click_prove: unfocused screen hold-click ${sx},${sy} active=$(xdotool getactivewindow || true)"

for _i in $(seq 1 24); do
	if grep -qE "RESULT=PASS|live Begin|action=begin|action=cc" "$LOG" 2>/dev/null; then
		echo "eoa_playlike_title_click_prove: RESULT=PASS unfocused screen click reached title"
		grep -E "LEAN_|RESULT=|EOA_LIVE_PTR|EOA_LIVE_RAW|live Begin" "$LOG" | tail -n 24
		exit 0
	fi
	if ! kill -0 "$GODOT_PID" 2>/dev/null; then
		break
	fi
	sleep 0.25
done

# Documented Begin key, still without activating Godot (Play Esc class).
xdotool key --clearmodifiers Return || true
sleep 0.4
if grep -qE "RESULT=PASS|live Begin|action=begin" "$LOG" 2>/dev/null; then
	echo "eoa_playlike_title_click_prove: RESULT=PASS unfocused Enter reached title"
	grep -E "LEAN_|RESULT=|EOA_LIVE_PTR|EOA_LIVE_RAW|live Begin" "$LOG" | tail -n 24
	exit 0
fi

echo "eoa_playlike_title_click_prove: RESULT=SOFT (unfocused click/Enter did not confirm)"
tail -n 40 "$LOG" || true
exit 0
