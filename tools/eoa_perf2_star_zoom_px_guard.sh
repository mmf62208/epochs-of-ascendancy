#!/usr/bin/env bash
# PERF-2 star zoom pixel guard. Dummy --headless cannot texture_2d_get.
# xvfb / llvmpipe is NOT live Play.
#
#   tools/eoa_perf2_star_zoom_px_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "HeadlessPerf2StarZoomPxTest: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
exec xvfb-run -a -s "-screen 0 1280x720x24" \
  "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x720 \
  -s res://scripts/core/HeadlessPerf2StarZoomPxTest.gd "$@"
