#!/usr/bin/env bash
# Live ATLAS-1 Ruhr labels after Begin. Play path: Begin, U (counters OFF), Home, wheel.
# Same boot as Play (TestScenario + EOA_SMOKE_AUTO_BEGIN). Not --headless:
# TestRunner treats DisplayServer=headless as the 50T evidence path.
#   tools/eoa_atlas1_live_ruhr.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_ATLAS1_EVIDENCE:-/tmp/eoa-atlas1-live-ruhr}"
mkdir -p "$OUT"
export EOA_ATLAS1_EVIDENCE="$OUT"
export EOA_SMOKE_AUTO_BEGIN=1
unset EOA_SKIP_TITLE || true
unset EOA_HEADLESS_EVIDENCE || true
unset EOA_RUN_50_TURN_SIM || true
echo "EOA_ATLAS1_LIVE_RUHR who=wrapper out=$OUT"
GODOT=("${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 -s res://scripts/core/HeadlessAtlas1LiveRuhrTest.gd "$@")
if command -v xvfb-run >/dev/null 2>&1; then
  echo "EOA_ATLAS1_LIVE_RUHR who=wrapper xvfb=1"
  exec xvfb-run -a -s "-screen 0 1280x800x24" "${GODOT[@]}"
fi
if [ -n "${DISPLAY:-}" ]; then
  echo "EOA_ATLAS1_LIVE_RUHR who=wrapper xvfb=0 display=$DISPLAY"
  exec "${ROOT}/tools/run_godot.sh" --display-driver x11 --path . --resolution 1280x800 \
    -s res://scripts/core/HeadlessAtlas1LiveRuhrTest.gd "$@"
fi
echo "HeadlessAtlas1LiveRuhrTest: RESULT=FAIL need xvfb-run or DISPLAY" >&2
exit 1
