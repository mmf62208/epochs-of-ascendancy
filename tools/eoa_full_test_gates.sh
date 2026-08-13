#!/usr/bin/env bash
# EOA full-test machine gates (world_accurate ~3520 post US+RoW sparse).
# Exit 0 only if every required step passes. Soft 30fps FAIL is not a gate.
#
# Usage (from repo root):
#   tools/eoa_full_test_gates.sh
#   tools/eoa_full_test_gates.sh --quick      # pure python only (no Godot)
#   tools/eoa_full_test_gates.sh --with-perf  # also map-tick perf sample
#   tools/eoa_full_test_gates.sh --log DIR    # write logs under DIR
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

QUICK=0
WITH_PERF=0
LOG_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --with-perf) WITH_PERF=1; shift ;;
    --log)
      LOG_DIR="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -n "$LOG_DIR" ]]; then
  mkdir -p "$LOG_DIR"
fi

log() { echo "[eoa-gates] $*"; }

run_step() {
  local name="$1"
  shift
  log "STEP $name"
  if [[ -n "$LOG_DIR" ]]; then
    if "$@" >"$LOG_DIR/${name}.log" 2>&1; then
      log "OK   $name"
      return 0
    else
      log "FAIL $name (see $LOG_DIR/${name}.log)"
      return 1
    fi
  else
    if "$@"; then
      log "OK   $name"
      return 0
    else
      log "FAIL $name"
      return 1
    fi
  fi
}

FAILED=0
fail() { FAILED=1; }

# --- Pure / unit gates (always) ---
run_step unit_board_play_path \
  python3 -m unittest \
    tools.map_generation.tests.test_world_accurate_board \
    tools.map_generation.tests.test_row_sparse_density_product \
    tools.map_generation.tests.test_us_state_province_density_product \
    tools.map_generation.tests.test_world_accurate_capital_pick_product \
    tools.map_generation.tests.test_world_accurate_strategic_and_assault \
    tools.map_generation.tests.test_world_accurate_multi_front_and_deploy \
    tools.map_generation.tests.test_ownership_mapmode_readability_product \
    tools.map_generation.tests.test_map_war_path_surface_product \
    tools.map_generation.tests.test_map_live_border_fronts_surface_product \
    tools.map_generation.tests.test_map_supply_corridor_product \
    tools.map_generation.tests.test_map_supply_hub_brief_product \
    tools.map_generation.tests.test_hoi_full_test_gap_matrix_product \
    tools.map_generation.tests.test_first_session_play_surface_product \
    tools.map_generation.tests.test_first_session_hotkeys_product \
    tools.map_generation.tests.test_first_session_assault_surface_product \
    tools.map_generation.tests.test_order_panel_play_strip_product \
    tools.map_generation.tests.test_interactive_multi_ai_day_product \
    -v || fail

run_step unit_save_path \
  python3 -m unittest \
    tools.map_generation.tests.test_world_accurate_campaign_feel.TestWorldAccurateCampaignD3 \
    tools.map_generation.tests.test_save_browser_campaign_product \
    tools.map_generation.tests.test_save_resume_primary_command_product \
    tools.map_generation.tests.test_autosave_session_primary_command_product \
    -v || fail

run_step map_qc \
  python3 tools/map_generation/scripts/map_accuracy_qc.py \
    --dir data/provinces_world_accurate --min-land-hit 0.90 || fail

run_step hoi_matrix_product \
  python3 -c "
import sys
sys.path.insert(0, 'tools/map_generation/lib')
from hoi_full_test_gap_matrix_product import build_hoi_full_test_gap_matrix_product
p = build_hoi_full_test_gap_matrix_product()
print(p.get('summary'))
assert p.get('ok') is True, p
assert int(p.get('open_p0_n')) == 0, p
print('open_p0_n=0 landed=%s' % p.get('landed_n'))
" || fail

if [[ "$QUICK" -eq 1 ]]; then
  if [[ "$FAILED" -eq 0 ]]; then
    log "ALL PASSED (quick pure-only)"
    exit 0
  fi
  log "FAILED (quick pure-only)"
  exit 1
fi

# --- Godot headless (full) ---
if [[ ! -x tools/run_godot.sh ]]; then
  log "WARN: tools/run_godot.sh missing; skipping Godot steps"
else
  run_step launch_pick \
    tools/run_godot.sh --headless --path . -s res://tools/map_manager_pick_harness_accurate.gd || fail

  if [[ -n "$LOG_DIR" ]] && [[ -f "$LOG_DIR/launch_pick.log" ]]; then
    if grep -q 'SCRIPT ERROR' "$LOG_DIR/launch_pick.log"; then
      log "FAIL launch_pick has SCRIPT ERROR"
      FAILED=1
    fi
    if ! grep -q 'ok=true' "$LOG_DIR/launch_pick.log"; then
      log "FAIL launch_pick missing ok=true"
      FAILED=1
    fi
  fi

  run_step launch_assault \
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMultiFrontAssaultTest.gd || fail

  if [[ -n "$LOG_DIR" ]] && [[ -f "$LOG_DIR/launch_assault.log" ]]; then
    if grep -q 'SCRIPT ERROR' "$LOG_DIR/launch_assault.log"; then
      log "FAIL launch_assault has SCRIPT ERROR"
      FAILED=1
    fi
    if ! grep -q 'PASS (failures=0)' "$LOG_DIR/launch_assault.log"; then
      log "FAIL launch_assault missing PASS (failures=0)"
      FAILED=1
    fi
  fi

  if [[ "$WITH_PERF" -eq 1 ]]; then
    # Perf sample is evidence only — soft 30fps FAIL is OK
    run_step map_perf \
      tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMapPerfTest.gd || log "WARN map_perf non-zero (not a hard gate)"
  fi
fi

if [[ "$FAILED" -eq 0 ]]; then
  log "ALL PASSED (full-test machine bar)"
  exit 0
fi
log "FAILED — see steps above"
exit 1
