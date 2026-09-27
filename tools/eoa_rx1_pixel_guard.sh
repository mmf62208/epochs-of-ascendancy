#!/usr/bin/env bash
# WINDOWED RX-1 pixel + panel guard. Smoke harness is not the product.
# Loads TestScenario (world_accurate, same F5 path) via tools/run_godot.sh.
# Never EOA_SKIP_TITLE. Uses EOA_SMOKE_AUTO_BEGIN only to dismiss the living title.
#
# 816cdc9 baseline has no Units toggle. The guard hides DemoUnitIcon_*,
# StackBadge, PinFocusPulse, LandBattleBubbleLayer, SelectedFrame by walking
# the tree (_hide_unit_nodes_direct) so units-OFF river/road samples are
# not covered by chips. Tip uses set_unit_counters_visible (view-only).
#
#   tools/eoa_rx1_pixel_guard.sh
#   EOA_RX1_PIXEL_OUT=/tmp/eoa-rx1-pixel tools/eoa_rx1_pixel_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_RX1_PIXEL_OUT:-/tmp/eoa-rx1-pixel}"
mkdir -p "$OUT"
export EOA_RX1_PIXEL_OUT="$OUT"
export EOA_SMOKE_AUTO_BEGIN=1
unset EOA_SKIP_TITLE || true
echo "EOA_RX1_PIXEL_GUARD who=wrapper out=$OUT xvfb=1 (NOT product Begin/Esc/clock PASS)"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedRx1RhinePixelGuard: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi
exec xvfb-run -a -s "-screen 0 1280x720x24" \
  "${ROOT}/tools/run_godot.sh" --path . \
  -s res://scripts/core/WindowedRx1RhinePixelGuard.gd "$@"
