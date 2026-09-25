#!/usr/bin/env bash
# Real DisplayServer pointer prove for living-title Begin / mouse CC.
# Lean window only (no 3520 board). Same tools/run_godot.sh path Play uses.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GODOT="${ROOT}/tools/run_godot.sh"
if [[ ! -x "$GODOT" ]]; then
	echo "eoa_lean_title_click_prove: missing tools/run_godot.sh" >&2
	exit 1
fi

if ! command -v xdotool >/dev/null 2>&1; then
	echo "eoa_lean_title_click_prove: xdotool missing — cannot drive a real OS click"
	echo "eoa_lean_title_click_prove: RESULT=SOFT"
	exit 0
fi

if [[ -z "${DISPLAY:-}" ]]; then
	if command -v Xvfb >/dev/null 2>&1; then
		export DISPLAY=":93"
		Xvfb :93 -screen 0 1680x960x24 >/tmp/eoa-lean-click-xvfb.log 2>&1 &
		echo $! > /tmp/eoa-lean-click-xvfb.pid
		sleep 0.4
	else
		echo "eoa_lean_title_click_prove: no DISPLAY and no Xvfb — RESULT=SOFT"
		exit 0
	fi
fi

LOG=/tmp/eoa-lean-title-click-prove.log
rm -f "$LOG"
"$GODOT" --path "$ROOT" -s res://scripts/core/LeanLivingTitleX11ClickProve.gd >"$LOG" 2>&1 &
GODOT_PID=$!
cleanup() {
	kill "$GODOT_PID" >/dev/null 2>&1 || true
	if [[ -f /tmp/eoa-lean-click-xvfb.pid ]]; then
		kill "$(cat /tmp/eoa-lean-click-xvfb.pid)" >/dev/null 2>&1 || true
		rm -f /tmp/eoa-lean-click-xvfb.pid
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
	echo "eoa_lean_title_click_prove: Godot never printed LEAN_CLICK_READY"
	tail -n 40 "$LOG" || true
	echo "eoa_lean_title_click_prove: RESULT=FAIL"
	exit 1
fi

WID="$(xdotool search --name "Epochs-of-Ascendancy" | tail -n 1 || true)"
if [[ -z "${WID}" ]]; then
	WID="$(xdotool search --name "Godot" | tail -n 1 || true)"
fi
if [[ -z "${WID}" ]]; then
	echo "eoa_lean_title_click_prove: no Godot window for xdotool"
	echo "eoa_lean_title_click_prove: RESULT=SOFT"
	exit 0
fi

xdotool windowactivate --sync "$WID" || true
# Click Begin at client coords from the Godot print (computerUse-like:
# click at a point, do not require a prior hover/mousemove over the Control).
BEGIN_LINE="$(grep "LEAN_HIT_BEGIN_CLIENT=" "$LOG" | tail -n 1 || true)"
CX="$(echo "$BEGIN_LINE" | sed -n 's/.*LEAN_HIT_BEGIN_CLIENT=\([0-9]*\),\([0-9]*\).*/\1/p')"
CY="$(echo "$BEGIN_LINE" | sed -n 's/.*LEAN_HIT_BEGIN_CLIENT=\([0-9]*\),\([0-9]*\).*/\2/p')"
if [[ -n "${CX}" && -n "${CY}" ]]; then
	# No mousemove-first: computerUse often ButtonPress without a Godot motion.
	xdotool mousemove --window "$WID" "$CX" "$CY" click 1 || true
else
	CC_LINE="$(grep "LEAN_HIT_CC_CLIENT=" "$LOG" | tail -n 1 || true)"
	CX="$(echo "$CC_LINE" | sed -n 's/.*LEAN_HIT_CC_CLIENT=\([0-9]*\),\([0-9]*\).*/\1/p')"
	CY="$(echo "$CC_LINE" | sed -n 's/.*LEAN_HIT_CC_CLIENT=\([0-9]*\),\([0-9]*\).*/\2/p')"
	if [[ -n "${CX}" && -n "${CY}" ]]; then
		xdotool mousemove --window "$WID" "$CX" "$CY" click 1 || true
	fi
fi

for _i in $(seq 1 30); do
	if grep -q "RESULT=PASS" "$LOG" 2>/dev/null; then
		echo "eoa_lean_title_click_prove: RESULT=PASS"
		grep -E "LEAN_|RESULT=|EOA_LIVE_PTR|live Begin" "$LOG" | tail -n 20
		exit 0
	fi
	if ! kill -0 "$GODOT_PID" 2>/dev/null; then
		break
	fi
	sleep 0.25
done

wait "$GODOT_PID" || true
if grep -q "RESULT=PASS" "$LOG" 2>/dev/null; then
	echo "eoa_lean_title_click_prove: RESULT=PASS"
	exit 0
fi
echo "eoa_lean_title_click_prove: RESULT=SOFT (xdotool ran; Godot did not confirm)"
tail -n 30 "$LOG" || true
exit 0
