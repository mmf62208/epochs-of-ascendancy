#!/usr/bin/env bash
# EOA full-test machine gates (world_accurate ~3520 post US+RoW sparse).
# Exit 0 only if every required step passes. Soft 30fps FAIL is not a gate.
#
# Usage (from repo root):
#   tools/eoa_full_test_gates.sh
#   tools/eoa_full_test_gates.sh --quick      # pure python, plus HeadlessGarrison1Test when it stays under 30s
#   tools/eoa_full_test_gates.sh --with-perf  # also map-tick perf sample
#   tools/eoa_full_test_gates.sh --log DIR    # write logs under DIR
#
# --quick launches one Godot step, HeadlessGarrison1Test (~16s on this PC).
# Full path calls tools/run_godot.sh, which exits 1 immediately if no binary
# is found (fail-closed; it must not hang).
# NE board/QC needs numpy+Pillow: pip install -r tools/map_generation/requirements.txt
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Prefer a local venv so numpy/Pillow do not require system Python or sudo.
if [[ -x "$ROOT/tools/map_generation/.venv/bin/python" ]]; then
  PYTHON="$ROOT/tools/map_generation/.venv/bin/python"
else
  PYTHON=python3
fi

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
log "python=$PYTHON"

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
# Missing numpy/Pillow used to traceback inside the 167-test dump; fail clearly first.
if ! "$PYTHON" -c "import numpy, PIL" >/dev/null 2>&1; then
  log "FAIL numpy/Pillow missing — NE board QC (test_world_accurate_board + map_accuracy_qc) cannot run"
  log "  install (venv, no sudo): python3 -m venv tools/map_generation/.venv && tools/map_generation/.venv/bin/pip install -r tools/map_generation/requirements.txt"
  log "  or user pip if allowed:  python3 -m pip install --user -r tools/map_generation/requirements.txt"
  fail
fi

run_step unit_board_play_path \
  "$PYTHON" -m unittest \
    tools.map_generation.tests.test_world_accurate_board \
    tools.map_generation.tests.test_row_sparse_density_product \
    tools.map_generation.tests.test_us_state_province_density_product \
    tools.map_generation.tests.test_great_lakes_water_province_product \
    tools.map_generation.tests.test_maginot_land_uniformity_product \
    tools.map_generation.tests.test_gibraltar_island_land_product \
    tools.map_generation.tests.test_seas_coarsen_feed4_product \
    tools.map_generation.tests.test_hong_kong_island_land_product \
    tools.map_generation.tests.test_caribbean_island_sizing_feed6_product \
    tools.map_generation.tests.test_flanders_nord_land_uniformity_product \
    tools.map_generation.tests.test_seas_coarsen_feed8_ligurian_product \
    tools.map_generation.tests.test_se_england_shire_land_uniformity_product \
    tools.map_generation.tests.test_ix1_road_spine_product \
    tools.map_generation.tests.test_rx1_rhine_crossing_product \
    tools.map_generation.tests.test_oldmap_turkey_mask_product \
    tools.map_generation.tests.test_nation_tags1 \
    tools.map_generation.tests.test_gap_china2_geom \
    tools.map_generation.tests.test_gap_ussr_west2 \
    tools.map_generation.tests.test_gap_europe_resid1 \
    tools.map_generation.tests.test_gap_fra1 \
    tools.map_generation.tests.test_world_accurate_capital_pick_product \
    tools.map_generation.tests.test_world_accurate_strategic_and_assault \
    tools.map_generation.tests.test_world_accurate_multi_front_and_deploy \
    tools.map_generation.tests.test_ownership_mapmode_readability_product \
    tools.map_generation.tests.test_map_war_path_surface_product \
    tools.map_generation.tests.test_map_states_mapmode_product \
    tools.map_generation.tests.test_map_mode_toolbar_active_product \
    tools.map_generation.tests.test_map_state_labels_surface_product \
    tools.map_generation.tests.test_map_nation_label_landmass_product \
    tools.map_generation.tests.test_map_live_border_fronts_surface_product \
    tools.map_generation.tests.test_map_supply_corridor_product \
    tools.map_generation.tests.test_map_supply_hub_brief_product \
    tools.map_generation.tests.test_hoi_full_test_gap_matrix_product \
    tools.map_generation.tests.test_first_session_play_surface_product \
    tools.map_generation.tests.test_first_session_hotkeys_product \
    tools.map_generation.tests.test_first_session_readability_product \
    tools.map_generation.tests.test_smoke_pan_esc_product \
    tools.map_generation.tests.test_settle_title_product \
    tools.map_generation.tests.test_agent_portrait_filedialog_product \
    tools.map_generation.tests.test_first_session_assault_surface_product \
    tools.map_generation.tests.test_order_panel_play_strip_product \
    tools.map_generation.tests.test_unit_centric_pick_product \
    tools.map_generation.tests.test_unit_counter_chrome_product \
    tools.map_generation.tests.test_unit_own_land_march_product \
    tools.map_generation.tests.test_unit_multi_day_battle_product \
    tools.map_generation.tests.test_land_battle_bubble_product \
    tools.map_generation.tests.test_unit_card_assign_product \
    tools.map_generation.tests.test_interactive_multi_ai_day_product \
    tools.map_generation.tests.test_land_combat_power_product \
    tools.map_generation.tests.test_land_battle_reinforce_product \
    tools.map_generation.tests.test_land_battle_attrition_product \
    tools.map_generation.tests.test_unit_card_combat_strip_product \
    tools.map_generation.tests.test_unit_card_fill_toe_visibility_product \
    tools.map_generation.tests.test_land_battle_depth_product \
    tools.map_generation.tests.test_land_battle_encircle_product \
    tools.map_generation.tests.test_land_battle_stance_product \
    tools.map_generation.tests.test_play_next_hook_product \
    tools.map_generation.tests.test_map_factory_shortage_surface_product \
    tools.map_generation.tests.test_map_agent_presence_product \
    tools.map_generation.tests.test_land_battle_aar_product \
    tools.map_generation.tests.test_land_battle_ai_init_product \
    tools.map_generation.tests.test_land_war_save_product \
    tools.map_generation.tests.test_land_battle_ai_campaign_product \
    tools.map_generation.tests.test_unit_recovery_replenish_product \
    tools.map_generation.tests.test_living_unit_order_loop_product \
    tools.map_generation.tests.test_designer_field_map_unit_product \
    tools.map_generation.tests.test_unit_design_creator_loop_product \
    tools.map_generation.tests.test_unit_organize_queue_product \
    tools.map_generation.tests.test_unit_living_story_product \
    tools.map_generation.tests.test_unit_composition_combat_product \
    tools.map_generation.tests.test_equipment_flow_product \
    tools.map_generation.tests.test_era_resource_deposits_product \
    tools.map_generation.tests.test_resource_icon_lod \
    tools.map_generation.tests.test_map_resources_mapmode_product \
    tools.map_generation.tests.test_fac1a_airfield_icons \
    -v || fail

run_step unit_save_path \
  "$PYTHON" -m unittest \
    tools.map_generation.tests.test_world_accurate_campaign_feel.TestWorldAccurateCampaignD3 \
    tools.map_generation.tests.test_save_browser_campaign_product \
    tools.map_generation.tests.test_save_resume_primary_command_product \
    tools.map_generation.tests.test_autosave_session_primary_command_product \
    tools.map_generation.tests.test_long_session_save_product \
    tools.map_generation.tests.test_infra_ai_invest_product \
    tools.map_generation.tests.test_calendar_autosave_product \
    tools.map_generation.tests.test_perf4_daily_sim_tick_product \
    -v || fail

run_step map_qc \
  "$PYTHON" tools/map_generation/scripts/map_accuracy_qc.py \
    --dir data/provinces_world_accurate --min-land-hit 0.90 || fail

run_step hoi_matrix_product \
  "$PYTHON" -c "
import sys
sys.path.insert(0, 'tools/map_generation/lib')
from hoi_full_test_gap_matrix_product import build_hoi_full_test_gap_matrix_product
p = build_hoi_full_test_gap_matrix_product()
print(p.get('summary'))
assert p.get('ok') is True, p
assert int(p.get('open_p0_n')) == 0, p
print('open_p0_n=0 landed=%s' % p.get('landed_n'))
" || fail

run_step air_physics_p1 \
  "$PYTHON" -m unittest tools.map_generation.tests.test_air_physics_p1_product -v || fail

if [[ "$QUICK" -eq 1 ]]; then
  if pgrep -af '[g]odot|[G]odot|[g]amescope' >/dev/null; then
    log "FAIL headless_garrison1 GODOT_BUSY"
    FAILED=1
  else
    run_step headless_garrison1 env \
      XDG_DATA_HOME="$(mktemp -d)" \
      flock -n "${HOME}/.eoa_godot.lock" \
      tools/run_godot.sh --headless --path . \
      -s res://scripts/core/HeadlessGarrison1Test.gd || fail
  fi
  if [[ "$FAILED" -eq 0 ]]; then
    log "ALL PASSED (quick)"
    exit 0
  fi
  log "FAILED (quick)"
  exit 1
fi

# --- Godot headless (full) ---
if [[ ! -x tools/run_godot.sh ]]; then
  log "WARN: tools/run_godot.sh missing; skipping Godot steps"
else
  run_step launch_pick \
    tools/run_godot.sh --headless -s res://tools/map_manager_pick_harness_accurate.gd || fail

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
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessWorldAccurateMultiFrontAssaultTest.gd || fail

  run_step launch_unit_order \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessWorldAccurateUnitOrderLoopTest.gd || fail

  run_step launch_mv1_march_preview \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessMv1MarchPreviewTest.gd || fail

  run_step launch_oridiom1b_march_cost \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessOrIdiom1bMarchCostTest.gd || fail

  run_step launch_rh1_resource_glyphs \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRh1ResourceGlyphMapModeTest.gd || fail

  run_step launch_fac1a_airfield_icons \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessFac1aAirfieldIconTest.gd || fail

  run_step launch_fac1a_hit_geometry \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessFac1aHitGeometryTest.gd || fail

  run_step launch_fac1a_pan_icons \
    tools/run_godot.sh --headless --resolution 1280x740 -s res://scripts/core/HeadlessFac1aPanIconsTest.gd || fail

  run_step launch_fac1a_hover_cache \
    tools/run_godot.sh --headless --resolution 1280x740 -s res://scripts/core/HeadlessFac1aHoverCacheTest.gd || fail

  run_step launch_perf2_fleet_refresh_budget \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessPerf2FleetRefreshBudgetTest.gd || fail

  run_step launch_perf3_supply_toggle \
    tools/run_godot.sh --headless --resolution 1280x740 -s res://scripts/core/HeadlessPerf3SupplyToggleTest.gd || fail

  run_step launch_perf5_legend_day_tick \
    tools/run_godot.sh --headless --resolution 1280x740 -s res://scripts/core/HeadlessPerf5LegendDayTickTest.gd || fail
  run_step launch_perf5_supply_overlay_fresh \
    tools/run_godot.sh --headless --resolution 1280x740 -s res://scripts/core/HeadlessPerf5SupplyOverlayFreshTest.gd || fail

  run_step launch_render1_supply_ring_mesh \
    tools/run_godot.sh --headless --resolution 1280x740 -s res://scripts/core/HeadlessRender1SupplyRingMeshTest.gd || fail
  run_step launch_render1_prebuild_roles \
    tools/eoa_render1_prebuild_role.sh || fail
  run_step launch_render1_draw_guard \
    tools/eoa_render1_draw_guard.sh || fail
  run_step launch_render1_live_cold \
    tools/eoa_render1_live_cold_guard.sh || fail

  run_step launch_mv1b_input_gate \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessMv1bInputGateTest.gd || fail

  run_step launch_ix1_mandate_gate \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessIx1RoadSpineMandateGateTest.gd || fail

  run_step launch_ix1_day_tick \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessIx1RoadSpineDayTickTest.gd || fail

  run_step launch_perf4_daily_sim_tick \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessPerf4DailySimTickTest.gd || fail

  run_step launch_perf4_interactive_multi_ai \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessPerf4InteractiveMultiAiTest.gd || fail

  run_step launch_perf6_day_roll \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessPerf6DayRollTest.gd || fail

  run_step launch_perf6_starve \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessPerf6StarveTest.gd || fail

  run_step launch_perf6_pace \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessPerf6PaceTest.gd || fail

  # PERF-4 FIX #11: leftover-queue ×7 on the windowed backup clock + deferred
  # day emit. Isolates the live race (TM self-drive before TIB; mark was
  # deferred). Must FAIL on 1cddb51c and PASS on the tip. Also runs inside
  # launch_perf4_live_multi_ai_day.
  run_step launch_perf4_windowed_backup \
    env EOA_PERF4_WINDOWED_BACKUP_ONLY=1 tools/run_godot.sh --headless -s res://scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd || fail

  run_step launch_perf4_live_multi_ai_day \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd || fail

  run_step launch_ix1_live_stay_alive_tick \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessIx1RoadSpineLiveStayAliveTickTest.gd || fail

  run_step launch_ix1_search_go \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessIx1SearchGoInspectorTest.gd || fail

  run_step launch_ix1_title_esc_begin \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessIx1LivingTitleEscBeginTest.gd || fail

  run_step launch_begin1_title_release \
    tools/run_godot.sh --headless --resolution 1280x740 -s res://scripts/core/HeadlessBegin1TitleReleaseFallthroughTest.gd || fail

  run_step launch_input1_close_click \
    tools/run_godot.sh --headless --path . --resolution 1280x740 \
    -s res://scripts/core/HeadlessInput1CloseClickFallthroughTest.gd || fail

  run_step launch_prod1_button_open \
    tools/run_godot.sh --headless --path . --resolution 1280x800 \
    -s res://scripts/core/HeadlessProd1ButtonOpenTest.gd || fail

  run_step launch_ui_polish1 \
    tools/run_godot.sh --headless --path . --resolution 1280x800 \
    -s res://scripts/core/HeadlessUiPolish1Test.gd || fail

  run_step launch_main_fix1_prod_esc \
    tools/run_godot.sh --headless --path . --resolution 1280x800 \
    -s res://scripts/core/HeadlessMainFix1ProdEscTest.gd || fail

  run_step launch_main_fix1_peace_click \
    tools/run_godot.sh --headless --path . --resolution 1280x800 \
    -s res://scripts/core/HeadlessMainFix1PeaceClickTest.gd || fail

  run_step launch_ix1_spine_complete \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessIx1RoadSpineCompleteTest.gd || fail

  run_step launch_rx1_rhine_crossing \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRx1RhineCrossingTest.gd || fail

  run_step launch_rx1_visibility \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRx1RhineVisibilityTest.gd || fail

  run_step launch_vis1_map_readability tools/run_godot.sh --headless --path . --resolution 1280x720 -s res://scripts/core/HeadlessVis1MapReadabilityTest.gd || fail

  run_step launch_vis2_capital_stars_after_l \
    tools/run_godot.sh --headless --path . --resolution 1280x720 \
    -s res://scripts/core/HeadlessVis2CapitalStarsAfterLTest.gd || fail

  # Dummy --headless cannot capture pixels: the .gd prints RESULT=SKIP.
  # The xvfb wrapper still runs the full ink asserts (same class as other
  # xvfb-only pixel checks: SKIP if no xvfb-run, PASS under Xvfb).
  run_step launch_perf2_star_zoom_px \
    tools/run_godot.sh --headless --path . --resolution 1280x720 \
    -s res://scripts/core/HeadlessPerf2StarZoomPxTest.gd || fail

  run_step launch_perf2_star_zoom_px_xvfb \
    tools/eoa_perf2_star_zoom_px_guard.sh || fail

  run_step launch_wheeldrift1 \
    tools/run_godot.sh --headless --path . --resolution 1280x740 \
    -s res://scripts/core/HeadlessWheelDrift1Test.gd || fail

  run_step launch_edge2_rim_feel \
    tools/run_godot.sh --headless --path . --resolution 1280x740 \
    -s res://scripts/core/HeadlessEdge2RimFeelTest.gd || fail

  run_step launch_rt1_road_tier \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRt1RoadTierForEdgeTest.gd || fail

  run_step launch_rt1_edge_filter \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRt1RoadEdgeFilterTest.gd || fail

  run_step launch_rt1_no_rebuild \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRt1RoadNoRebuildTest.gd || fail

  run_step launch_roads1_quiet \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRoads1QuietGuard.gd || fail

  run_step launch_roads1_lithuania_stub \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRoads1LithuaniaStubTest.gd || fail

  run_step launch_roads1_supply_legend_layout \
    tools/run_godot.sh --headless --path . --resolution 1280x800 \
    -s res://scripts/core/HeadlessRoads1SupplyLegendLayoutTest.gd || fail

  run_step launch_hwy1_highway_chain \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessHwy1HighwayChainTest.gd || fail

  run_step launch_hwy3_hub_route \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessHwy3HubRouteTest.gd || fail

  run_step launch_hwy3_live_scenario \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessHwy3LiveScenarioTest.gd || fail

  run_step launch_hwy3_supply_toggle_cache \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessHwy3SupplyToggleCacheTest.gd || fail

  run_step launch_live_lon_probe \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessLiveLonProbe.gd || fail

  run_step launch_hwy3_ruhr_legibility \
    tools/eoa_hwy3_ruhr_legibility_guard.sh || fail

  run_step launch_rx1_panel_state \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRx1RhinePanelStateTest.gd || fail

  run_step launch_rx1_pixel \
    tools/eoa_rx1_pixel_guard.sh || fail

  run_step launch_mv1_pixel \
    tools/eoa_mv1_pixel_guard.sh || fail

  run_step launch_mv1_card_up_input \
    tools/eoa_mv1_card_up_input_guard.sh || fail

  run_step launch_rh1_pixel \
    tools/eoa_rh1_pixel_guard.sh || fail

  run_step launch_fac1a_pixel \
    tools/eoa_fac1a_pixel_guard.sh || fail

  run_step launch_rx1_live_stay_alive_tick \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessRx1RhineLiveStayAliveTickTest.gd || fail

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

  if [[ -n "$LOG_DIR" ]] && [[ -f "$LOG_DIR/launch_unit_order.log" ]]; then
    if grep -q 'SCRIPT ERROR' "$LOG_DIR/launch_unit_order.log"; then
      log "FAIL launch_unit_order has SCRIPT ERROR"
      FAILED=1
    fi
    if ! grep -q 'RESULT=PASS' "$LOG_DIR/launch_unit_order.log"; then
      log "FAIL launch_unit_order missing RESULT=PASS"
      FAILED=1
    fi
  fi

  run_step launch_unit_physics_calibration \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessUnitPhysicsCalibrationTest.gd || fail

  run_step launch_designer_validation \
    tools/run_godot.sh --headless -s res://scripts/core/HeadlessDesignerValidationTest.gd || fail

  run_step launch_nation_tags1 \
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessNationTags1Test.gd || fail

  run_step launch_campaign_loop1_war_gate \
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCampaignLoop1WarGateTest.gd || fail

  run_step launch_campaign_loop1_declare_click \
    tools/run_godot.sh --headless --path . --resolution 1280x800 -s res://scripts/core/HeadlessCampaignLoop1DeclareClickTest.gd || fail

  run_step launch_campaign_loop1_topbar_fit \
    tools/run_godot.sh --headless --path . --resolution 1280x800 -s res://scripts/core/HeadlessCampaignLoop1TopBarFitTest.gd || fail

  run_step launch_campaign_loop1_capitulation \
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCampaignLoop1CapitulationPeaceTest.gd || fail

  run_step launch_campaign_loop1_soak \
    tools/eoa_campaign_loop1_soak.sh || fail

  run_step launch_campaign_loop1_end_screen \
    tools/eoa_campaign_loop1_end_screen_guard.sh || fail

  run_step launch_main_fix1_declare_toast \
    tools/eoa_main_fix1_declare_toast_guard.sh || fail

  if [[ "$WITH_PERF" -eq 1 ]]; then
    # Perf sample is evidence only — soft 30fps FAIL is OK
    run_step map_perf \
      tools/run_godot.sh --headless -s res://scripts/core/HeadlessWorldAccurateMapPerfTest.gd || log "WARN map_perf non-zero (not a hard gate)"
  fi
fi

if [[ "$FAILED" -eq 0 ]]; then
  log "ALL PASSED (full-test machine bar)"
  exit 0
fi
log "FAILED — see steps above"
exit 1
