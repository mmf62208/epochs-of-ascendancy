#!/usr/bin/env bash
# WINDOWED RX-1 live Build Bridge progress guard. Drives the REAL Play path:
#   tools/eoa_play_f5_smoke_auto_begin.sh
#   viewport InputEventMouseButton → MapRenderer._on_build_rhine_bridge_pressed
#   stay-alive still armed; TestRunner pumps TimeManager.advance_real_time
#   (the live hour clock), NOT IDM.advance_daily_projects.
#
# Must FAIL on 1d092a14 (no RX-1 button / no live env) and PASS on the RX-1 tip
# (progress > 0 within ~5 live days, then COMPLETE). RSS from /proc of the
# Godot pid must stay under 3 GB.
#
#   tools/eoa_rx1_bridge_live_progress_guard.sh
#
# Do NOT score product Begin / Esc / 4x / clock PASS. The smoke harness is
# not the product.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -x "${ROOT}/tools/eoa_play_f5_smoke_auto_begin.sh" ]]; then
	echo "eoa_rx1_bridge_live_progress_guard: missing tools/eoa_play_f5_smoke_auto_begin.sh" >&2
	exit 1
fi
if [[ ! -x "${ROOT}/tools/run_godot.sh" ]]; then
	echo "eoa_rx1_bridge_live_progress_guard: missing tools/run_godot.sh" >&2
	exit 1
fi

export EOA_SMOKE_RX1_LIVE_PROGRESS=1
export EOA_SMOKE_FRAME_GUARD=1
RSS_LIMIT_MB="${EOA_LIVE_PROGRESS_RSS_LIMIT_MB:-3072}"
LOG="${EOA_LIVE_PROGRESS_LOG:-/tmp/eoa-rx1-bridge-live-progress.log}"
RSSLOG="${EOA_LIVE_PROGRESS_RSS_LOG:-/tmp/eoa-rx1-bridge-live-progress-rss.log}"
rm -f "$LOG" "$RSSLOG"

find_godot_pid() {
	local root_pid="$1"
	local q=("$root_pid")
	local i=0
	while [[ $i -lt ${#q[@]} ]]; do
		local p="${q[$i]}"
		i=$((i + 1))
		if [[ -r "/proc/${p}/comm" ]] && grep -qi godot "/proc/${p}/comm"; then
			echo "$p"
			return 0
		fi
		if [[ -L "/proc/${p}/exe" ]] && readlink "/proc/${p}/exe" 2>/dev/null | grep -qi godot; then
			echo "$p"
			return 0
		fi
		local kids
		kids="$(pgrep -P "$p" 2>/dev/null || true)"
		if [[ -n "$kids" ]]; then
			local k
			for k in $kids; do
				q+=("$k")
			done
		fi
	done
	local p
	for p in /proc/[0-9]*; do
		if [[ -L "$p/exe" ]] && readlink "$p/exe" 2>/dev/null | grep -qi Godot; then
			echo "${p#/proc/}"
			return 0
		fi
	done
	return 1
}

read_rss_mb() {
	local pid="$1"
	if [[ -z "${pid:-}" || ! -r "/proc/${pid}/status" ]]; then
		echo 0
		return
	fi
	awk '/VmRSS/{printf "%d", $2/1024}' "/proc/${pid}/status"
}

CMD=("${ROOT}/tools/eoa_play_f5_smoke_auto_begin.sh")
if [[ -z "${DISPLAY:-}" ]]; then
	if ! command -v xvfb-run >/dev/null 2>&1; then
		echo "eoa_rx1_bridge_live_progress_guard: no DISPLAY and no xvfb-run" >&2
		exit 1
	fi
	xvfb-run -a -s "-screen 0 1280x720x24" "${CMD[@]}" >"$LOG" 2>&1 &
else
	"${CMD[@]}" >"$LOG" 2>&1 &
fi
GPID=$!

PRESS_SEEN=0
GODOT_PID=""
(
	for _i in $(seq 1 900); do
		if [[ -z "${GODOT_PID:-}" ]] || [[ ! -r "/proc/${GODOT_PID}/status" ]]; then
			GODOT_PID="$(find_godot_pid "$GPID" || true)"
		fi
		if [[ -n "${GODOT_PID:-}" && -r "/proc/${GODOT_PID}/status" ]]; then
			rss="$(read_rss_mb "$GODOT_PID")"
			echo "$(date +%H:%M:%S) pid=$GODOT_PID rss_mb=$rss" >>"$RSSLOG"
			if grep -qE "EOA_SMOKE_RX1_PROGRESS who=MapRenderer.button|EOA_SMOKE_RX1_LIVE_PROGRESS who=TestRunner.mouse_press|EOA_SMOKE_RX1_LIVE_PROGRESS who=TestRunner.arm" "$LOG" 2>/dev/null; then
				if [[ "$PRESS_SEEN" -eq 0 ]]; then
					PRESS_SEEN=1
					echo "$(date +%H:%M:%S) PRESS_SEEN rss_mb=$rss" >>"$RSSLOG"
				fi
			fi
			if [[ "$rss" -ge "$RSS_LIMIT_MB" ]]; then
				echo "$(date +%H:%M:%S) KILL rss_mb=$rss over_limit=$RSS_LIMIT_MB" >>"$RSSLOG"
				kill -9 "$GODOT_PID" 2>/dev/null || true
				kill -9 "$GPID" 2>/dev/null || true
				break
			fi
			if grep -qE "EOA_SMOKE_RX1_LIVE_PROGRESS RESULT=" "$LOG" 2>/dev/null; then
				echo "$(date +%H:%M:%S) RESULT_SEEN rss_mb=$rss" >>"$RSSLOG"
				sleep 2
				if kill -0 "$GODOT_PID" 2>/dev/null; then
					kill -9 "$GODOT_PID" 2>/dev/null || true
					kill -9 "$GPID" 2>/dev/null || true
				fi
				break
			fi
		fi
		if ! kill -0 "$GPID" 2>/dev/null; then
			break
		fi
		sleep 1
	done
) &
SIDECAR_PID=$!

set +e
wait "$GPID"
CODE=$?
set -e
wait "$SIDECAR_PID" 2>/dev/null || true

echo "==== Godot (EOA_SMOKE_RX1_LIVE_PROGRESS) ===="
grep -E "EOA_SMOKE_RX1_LIVE_PROGRESS|EOA_SMOKE_RX1_START|EOA_SMOKE_RX1_PROGRESS|EOA_SMOKE_RX1_STATE|EOA_SMOKE_RX1_COMPLETE|RESULT=" "$LOG" | tail -n 120 || tail -n 60 "$LOG"
SIDECAR_MAX=0
SIDECAR_LAST=0
if [[ -f "$RSSLOG" ]]; then
	echo "==== RSS sidecar (/proc Godot pid) ===="
	cat "$RSSLOG"
	SIDECAR_MAX="$(awk -F= '/rss_mb=[0-9]+/{print $NF}' "$RSSLOG" | grep -E '^[0-9]+$' | sort -n | tail -n 1)"
	SIDECAR_LAST="$(awk -F= '/rss_mb=[0-9]+/{print $NF}' "$RSSLOG" | grep -E '^[0-9]+$' | tail -n 1)"
	SIDECAR_MAX="${SIDECAR_MAX:-0}"
	SIDECAR_LAST="${SIDECAR_LAST:-0}"
	echo "eoa_rx1_bridge_live_progress_guard: sidecar_max_rss_mb=${SIDECAR_MAX} sidecar_last_rss_mb=${SIDECAR_LAST}"
fi

PRESS_OK=0
if grep -qE "EOA_SMOKE_RX1_PROGRESS who=MapRenderer.button|EOA_SMOKE_RX1_LIVE_PROGRESS who=TestRunner.mouse_press" "$LOG"; then
	PRESS_OK=1
fi
PROG_OK=0
if grep -qE "EOA_SMOKE_RX1_LIVE_PROGRESS who=TestRunner.tick days=[5-9][0-9]* pct=[1-9]" "$LOG" \
	|| grep -qE "EOA_SMOKE_RX1_PROGRESS who=IDM.advance_daily pid=710413 pct=[1-9]" "$LOG"; then
	PROG_OK=1
fi
COMPLETE_OK=0
if grep -qE "EOA_SMOKE_RX1_LIVE_PROGRESS RESULT=PASS" "$LOG" \
	|| grep -qE "EOA_SMOKE_RX1_COMPLETE" "$LOG"; then
	COMPLETE_OK=1
fi
GODOT_FAIL=0
if grep -qE "EOA_SMOKE_RX1_LIVE_PROGRESS RESULT=FAIL" "$LOG"; then
	GODOT_FAIL=1
fi
RSS_OK=0
if [[ "$SIDECAR_MAX" =~ ^[0-9]+$ ]] && [[ "$SIDECAR_MAX" -gt 0 ]] && [[ "$SIDECAR_MAX" -lt "$RSS_LIMIT_MB" ]]; then
	RSS_OK=1
fi

if [[ "$GODOT_FAIL" -eq 0 && "$PRESS_OK" -eq 1 && "$PROG_OK" -eq 1 && "$COMPLETE_OK" -eq 1 && "$RSS_OK" -eq 1 ]]; then
	echo "eoa_rx1_bridge_live_progress_guard: RESULT=PASS sidecar_max_rss_mb=${SIDECAR_MAX} press=1 progress=1 complete=1 (NOT product Begin/Esc/clock PASS)"
	exit 0
fi
echo "eoa_rx1_bridge_live_progress_guard: RESULT=FAIL (exit=$CODE sidecar_max_rss_mb=${SIDECAR_MAX} press=$PRESS_OK progress=$PROG_OK complete=$COMPLETE_OK rss_ok=$RSS_OK godot_fail=$GODOT_FAIL)"
exit 1
