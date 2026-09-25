#!/usr/bin/env bash
# WINDOWED Ix-1 spine frame/RSS guard. Smoke harness, not the product.
#
# Launches the SAME way Play does (tools/eoa_play_f5_smoke_auto_begin.sh),
# then delivers a real InputEventMouseButton to the Build Road Spine button
# through the viewport (MapRenderer.button). After that press, frames must
# keep advancing and RSS must stay under 3 GB for 60 s.
#
#   tools/eoa_ix1_spine_frame_guard.sh
#
# Do NOT score product Begin / Esc / 4x / clock PASS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -x "${ROOT}/tools/eoa_play_f5_smoke_auto_begin.sh" ]]; then
	echo "eoa_ix1_spine_frame_guard: missing tools/eoa_play_f5_smoke_auto_begin.sh" >&2
	exit 1
fi
if [[ ! -x "${ROOT}/tools/run_godot.sh" ]]; then
	echo "eoa_ix1_spine_frame_guard: missing tools/run_godot.sh" >&2
	exit 1
fi

export EOA_SMOKE_FRAME_GUARD=1
export EOA_FRAME_GUARD_SECS="${EOA_FRAME_GUARD_SECS:-60}"
RSS_LIMIT_MB="${EOA_FRAME_GUARD_RSS_LIMIT_MB:-3072}"
LOG="${EOA_FRAME_GUARD_LOG:-/tmp/eoa-ix1-spine-frame-guard.log}"
RSSLOG="${EOA_FRAME_GUARD_RSS_LOG:-/tmp/eoa-ix1-spine-frame-guard-rss.log}"
rm -f "$LOG" "$RSSLOG"

# Play's exact launch. Do not add --path (run_godot.sh already sets it).
CMD=("${ROOT}/tools/eoa_play_f5_smoke_auto_begin.sh")
if [[ -z "${DISPLAY:-}" ]]; then
	if ! command -v xvfb-run >/dev/null 2>&1; then
		echo "eoa_ix1_spine_frame_guard: no DISPLAY and no xvfb-run" >&2
		exit 1
	fi
	xvfb-run -a -s "-screen 0 1280x720x24" "${CMD[@]}" >"$LOG" 2>&1 &
else
	"${CMD[@]}" >"$LOG" 2>&1 &
fi
GPID=$!

PRESS_SEEN=0
PRESS_T0=0
(
	for _i in $(seq 1 $((EOA_FRAME_GUARD_SECS + 300))); do
		CPID="$(pgrep -P "$GPID" -a 2>/dev/null | awk '/Godot/{print $1; exit}' || true)"
		if [[ -z "${CPID:-}" ]]; then
			CPID="$(pgrep -n -f "Godot_v4.7.1" 2>/dev/null || true)"
		fi
		if [[ -n "${CPID:-}" && -r "/proc/${CPID}/status" ]]; then
			rss="$(awk '/VmRSS/{printf "%d", $2/1024}' "/proc/${CPID}/status")"
			echo "$(date +%H:%M:%S) pid=$CPID rss_mb=$rss" >>"$RSSLOG"
			if grep -qE "EOA_SMOKE_SPINE_PROGRESS who=MapRenderer.button|EOA_SMOKE_FRAME_GUARD who=TestRunner.mouse_press" "$LOG" 2>/dev/null; then
				if [[ "$PRESS_SEEN" -eq 0 ]]; then
					PRESS_SEEN=1
					PRESS_T0=$(date +%s)
					echo "$(date +%H:%M:%S) PRESS_SEEN rss_mb=$rss" >>"$RSSLOG"
				fi
			fi
			if [[ "$PRESS_SEEN" -eq 1 && "$rss" -ge "$RSS_LIMIT_MB" ]]; then
				echo "$(date +%H:%M:%S) KILL rss_mb=$rss over_limit=$RSS_LIMIT_MB" >>"$RSSLOG"
				kill -9 "$CPID" 2>/dev/null || true
				kill -9 "$GPID" 2>/dev/null || true
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

echo "==== Godot (EOA_SMOKE_FRAME_GUARD) ===="
grep -E "EOA_SMOKE_FRAME_GUARD|EOA_SMOKE_SPINE_BISECT|EOA_SMOKE_SPINE_START|EOA_SMOKE_SPINE_PROGRESS who=MapRenderer|RESULT=" "$LOG" | tail -n 80 || tail -n 40 "$LOG"
SIDECAR_MAX=0
if [[ -f "$RSSLOG" ]]; then
	echo "==== RSS sidecar (1s) ===="
	cat "$RSSLOG"
	SIDECAR_MAX="$(awk -F= '/rss_mb=[0-9]+/{print $NF}' "$RSSLOG" | sort -n | tail -n 1)"
	SIDECAR_MAX="${SIDECAR_MAX:-0}"
	echo "eoa_ix1_spine_frame_guard: sidecar_max_rss_mb=${SIDECAR_MAX}"
fi
GODOT_PASS=0
if grep -qE "EOA_SMOKE_FRAME_GUARD frames=[0-9]+ rss_mb=[0-9]+ PASS" "$LOG"; then
	GODOT_PASS=1
fi
PRESS_OK=0
if grep -qE "EOA_SMOKE_SPINE_PROGRESS who=MapRenderer.button|EOA_SMOKE_FRAME_GUARD who=TestRunner.mouse_press" "$LOG"; then
	PRESS_OK=1
fi
if [[ "$GODOT_PASS" -eq 1 && "${SIDECAR_MAX}" -lt "$RSS_LIMIT_MB" && "$PRESS_OK" -eq 1 ]]; then
	echo "eoa_ix1_spine_frame_guard: RESULT=PASS sidecar_max_rss_mb=${SIDECAR_MAX} launch=eoa_play_f5_smoke_auto_begin.sh"
	exit 0
fi
echo "eoa_ix1_spine_frame_guard: RESULT=FAIL (exit=$CODE sidecar_max_rss_mb=${SIDECAR_MAX} press=$PRESS_OK godot_pass=$GODOT_PASS launch=eoa_play_f5_smoke_auto_begin.sh)"
exit 1
