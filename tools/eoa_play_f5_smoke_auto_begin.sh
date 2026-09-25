#!/usr/bin/env bash
# Play F5 IX-1 softpipe hatch + smoke past-+6. Smoke-only.
#
# Play computerUse on the full TestScenario driver never delivered OS events
# into this Godot X11 window (tip 6573d01: EOA_LIVE_RAW_PTR=1 title.ready only,
# RAW_KEY=0, PTR=0, ESC=0; tip ae78507: hatch PASS, 4x/day still undelivered).
# This wrapper sets EOA_SMOKE_AUTO_BEGIN=1 so the living title closes via
# handle_live_begin, then EOA_SMOKE_ADVANCE_PAST_PLUS6=1 so the real TopInfoBar
# 4x owner + TimeManager chunked advance_real_time (combat deferred; live
# softpipe catch-up when idle frames are scarce) drives past 7 Jan without a
# sync ×48 + combat-flush wedge. After past7 the window stays up (stay-alive:
# drop queued day_ai/battles, pause after ok, gate unit-icon flood) so Search
# Köln → spine can run.
#
# Does NOT claim product Begin / Esc / mouse CC / 4x / clock PASS. Leave those
# FAIL until post-boot EOA_LIVE_RAW_* appears from a real click or key.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export EOA_SMOKE_AUTO_BEGIN=1
export EOA_SMOKE_ADVANCE_PAST_PLUS6=1
echo "EOA_SMOKE_AUTO_BEGIN=1 — living title will auto-dismiss via handle_live_begin"
echo "EOA_SMOKE_ADVANCE_PAST_PLUS6=1 — after hatch, smoke-drive TopInfoBar 4x / chunked advance_real_time past 7 Jan (window-stay + stay-alive)"
echo "Product Begin / Esc / mouse CC / 4x / clock stay FAIL until post-boot EOA_LIVE_RAW_* appears"
exec "${ROOT}/tools/run_godot.sh" --path . res://scenes/TestScenario.tscn "$@"
