#!/usr/bin/env bash
# WINDOWED Ix-1 spine frame/RSS guard. Smoke harness, not the product.
# After a simulated Build Road Spine press, frames must keep advancing and
# RSS must stay under 2 GB for 60 s (override with EOA_FRAME_GUARD_SECS).
#
#   tools/eoa_ix1_spine_frame_guard.sh
#
# Do NOT score product Begin / Esc / 4x / clock PASS. Play launch remains
# tools/eoa_play_f5_smoke_auto_begin.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -x "${ROOT}/tools/run_godot.sh" ]]; then
	echo "eoa_ix1_spine_frame_guard: missing tools/run_godot.sh" >&2
	exit 1
fi

export EOA_FRAME_GUARD_SECS="${EOA_FRAME_GUARD_SECS:-60}"
LOG="${EOA_FRAME_GUARD_LOG:-/tmp/eoa-ix1-spine-frame-guard.log}"
RSSLOG="${EOA_FRAME_GUARD_RSS_LOG:-/tmp/eoa-ix1-spine-frame-guard-rss.log}"
rm -f "$LOG" "$RSSLOG"

# tools/run_godot.sh already passes --path. Do not add a second --path.
CMD=("${ROOT}/tools/run_godot.sh" -s res://scripts/core/WindowedIx1SpineFrameGuard.gd)
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

(
	for _i in $(seq 1 $((EOA_FRAME_GUARD_SECS + 20))); do
		CPID="$(pgrep -P "$GPID" -a 2>/dev/null | awk '/Godot/{print $1; exit}' || true)"
		if [[ -z "${CPID:-}" ]]; then
			CPID="$(pgrep -n -f "Godot_v4.7.1" 2>/dev/null || true)"
		fi
		if [[ -n "${CPID:-}" && -r "/proc/${CPID}/status" ]]; then
			rss="$(awk '/VmRSS/{printf "%d", $2/1024}' "/proc/${CPID}/status")"
			echo "$(date +%H:%M:%S) pid=$CPID rss_mb=$rss" >>"$RSSLOG"
		fi
		if ! kill -0 "$GPID" 2>/dev/null; then
			break
		fi
		sleep 1
	done
) &

set +e
wait "$GPID"
CODE=$?
set -e

echo "==== Godot (EOA_SMOKE_FRAME_GUARD) ===="
grep -E "EOA_SMOKE_FRAME_GUARD|WindowedIx1SpineFrameGuard|RESULT=" "$LOG" || tail -n 40 "$LOG"
if [[ -f "$RSSLOG" ]]; then
	echo "==== RSS sidecar (1s) ===="
	cat "$RSSLOG"
fi
if grep -qE "EOA_SMOKE_FRAME_GUARD frames=[0-9]+ rss_mb=[0-9]+ PASS" "$LOG"; then
	echo "eoa_ix1_spine_frame_guard: RESULT=PASS"
	exit 0
fi
echo "eoa_ix1_spine_frame_guard: RESULT=FAIL (exit=$CODE)"
exit 1
