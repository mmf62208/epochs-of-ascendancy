#!/usr/bin/env bash
# Play F5 IX-1 softpipe hatch. Smoke-only living-title dismiss.
#
# Play computerUse on the full TestScenario driver never delivered OS events
# into this Godot X11 window (tip 6573d01: EOA_LIVE_RAW_PTR=1 title.ready only,
# RAW_KEY=0, PTR=0, ESC=0). This wrapper sets EOA_SMOKE_AUTO_BEGIN=1 so the
# living title closes via handle_live_begin (clock / Search / spine arm).
#
# Does NOT claim product Begin / Esc / mouse CC PASS. Leave those FAIL until
# post-boot EOA_LIVE_RAW_* appears from a real click or key.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export EOA_SMOKE_AUTO_BEGIN=1
echo "EOA_SMOKE_AUTO_BEGIN=1 — living title will auto-dismiss via handle_live_begin"
echo "Product Begin / Esc / mouse CC stay FAIL until post-boot EOA_LIVE_RAW_* appears"
exec "${ROOT}/tools/run_godot.sh" --path . res://scenes/TestScenario.tscn "$@"
