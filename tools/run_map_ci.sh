#!/usr/bin/env bash
# Map data CI: names (Europe dirs), densify gates, SHIPPED strategic regions, layer sanity.
# Primary: data/provinces_world_full (~1700 full world)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DIR="${1:-data/provinces_world_full}"

echo "=== Map CI for $DIR ==="
echo "Primary play dir: data/provinces_world_full (full world, geometry_space=world)"
echo "Baselines: provinces_full_europe (460) | provinces_grand_theater | provinces_phase1_test"
echo

python3 tools/map_generation/tests/test_island_viability.py
python3 tools/map_generation/tests/test_assign_europe_province_names.py
python3 tools/map_generation/tests/test_densify_province_geometry.py
python3 tools/map_generation/tests/test_rebuild_strategic_regions.py
if [[ -f tools/map_generation/tests/test_world_full_dataset.py ]]; then
  python3 tools/map_generation/tests/test_world_full_dataset.py
fi
if [[ -f tools/map_generation/tests/test_gis_littoral_depth_expand.py ]]; then
  python3 tools/map_generation/tests/test_gis_littoral_depth_expand.py
fi
if [[ -f tools/map_generation/tests/test_ne_full_geometry_align.py ]]; then
  python3 tools/map_generation/tests/test_ne_full_geometry_align.py
fi
if [[ -f tools/map_generation/tests/test_multi_faction_strategic_ai_product.py ]]; then
  python3 tools/map_generation/tests/test_multi_faction_strategic_ai_product.py
fi
if [[ -f tools/map_generation/tests/test_strategic_ai_daily_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_strategic_ai_daily_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_play_session_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_play_session_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_air_ops_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_air_ops_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_focus_war_path_product.py ]]; then
  python3 tools/map_generation/tests/test_focus_war_path_product.py
fi
if [[ -f tools/map_generation/tests/test_naval_multi_phase_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_naval_multi_phase_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_next20_advanced_deferred_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_advanced_deferred_days.py
fi
if [[ -f tools/map_generation/tests/test_diplomacy_peace_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_diplomacy_peace_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_tech_research_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_tech_research_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_next20_diplomacy_tech_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_diplomacy_tech_days.py
fi
if [[ -f tools/map_generation/tests/test_logistics_supply_theater_product.py ]]; then
  python3 tools/map_generation/tests/test_logistics_supply_theater_product.py
fi
if [[ -f tools/map_generation/tests/test_intelligence_network_product.py ]]; then
  python3 tools/map_generation/tests/test_intelligence_network_product.py
fi
if [[ -f tools/map_generation/tests/test_world_class_campaign_command_product.py ]]; then
  python3 tools/map_generation/tests/test_world_class_campaign_command_product.py
fi
if [[ -f tools/map_generation/tests/test_next20_world_class_depth_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_world_class_depth_days.py
fi
if [[ -f tools/map_generation/tests/test_war_economy_mobilization_product.py ]]; then
  python3 tools/map_generation/tests/test_war_economy_mobilization_product.py
fi
if [[ -f tools/map_generation/tests/test_weather_theater_ops_product.py ]]; then
  python3 tools/map_generation/tests/test_weather_theater_ops_product.py
fi
if [[ -f tools/map_generation/tests/test_front_continuity_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_front_continuity_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_next20_economy_weather_front_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_economy_weather_front_days.py
fi
if [[ -f tools/map_generation/tests/test_occupation_control_product.py ]]; then
  python3 tools/map_generation/tests/test_occupation_control_product.py
fi
if [[ -f tools/map_generation/tests/test_manpower_reinforcement_product.py ]]; then
  python3 tools/map_generation/tests/test_manpower_reinforcement_product.py
fi
if [[ -f tools/map_generation/tests/test_leader_command_product.py ]]; then
  python3 tools/map_generation/tests/test_leader_command_product.py
fi
if [[ -f tools/map_generation/tests/test_next20_occupation_manpower_leader_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_occupation_manpower_leader_days.py
fi
if [[ -f tools/map_generation/tests/test_medium_tank_production_honesty_product.py ]]; then
  python3 tools/map_generation/tests/test_medium_tank_production_honesty_product.py
fi
if [[ -f tools/map_generation/tests/test_next10_production_honesty_days.py ]]; then
  python3 tools/map_generation/tests/test_next10_production_honesty_days.py
fi
if [[ -f tools/map_generation/tests/test_apply_queue_live_managers_product.py ]]; then
  python3 tools/map_generation/tests/test_apply_queue_live_managers_product.py
fi
if [[ -f tools/map_generation/tests/test_next10_apply_queue_live_days.py ]]; then
  python3 tools/map_generation/tests/test_next10_apply_queue_live_days.py
fi
if [[ -f tools/map_generation/tests/test_occupation_resistance_compliance_product.py ]]; then
  python3 tools/map_generation/tests/test_occupation_resistance_compliance_product.py
fi
if [[ -f tools/map_generation/tests/test_manpower_laws_training_product.py ]]; then
  python3 tools/map_generation/tests/test_manpower_laws_training_product.py
fi
if [[ -f tools/map_generation/tests/test_peace_conference_settlement_product.py ]]; then
  python3 tools/map_generation/tests/test_peace_conference_settlement_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase2_conquest_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase2_conquest_days.py
fi
if [[ -f tools/map_generation/tests/test_product_ux_command_polish_product.py ]]; then
  python3 tools/map_generation/tests/test_product_ux_command_polish_product.py
fi
if [[ -f tools/map_generation/tests/test_campaign_alpha_primary_strip_product.py ]]; then
  python3 tools/map_generation/tests/test_campaign_alpha_primary_strip_product.py
fi
if [[ -f tools/map_generation/tests/test_stream_alpha_primary_packs_product.py ]]; then
  python3 tools/map_generation/tests/test_stream_alpha_primary_packs_product.py
fi
if [[ -f tools/map_generation/tests/test_stream_alpha_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_stream_alpha_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_stream_alpha_primary_command_routing.py ]]; then
  python3 tools/map_generation/tests/test_stream_alpha_primary_command_routing.py
fi
if [[ -f tools/map_generation/tests/test_fleet_autonomy_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_fleet_autonomy_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_fleet_autonomy_primary_command_routing.py ]]; then
  python3 tools/map_generation/tests/test_fleet_autonomy_primary_command_routing.py
fi
if [[ -f tools/map_generation/tests/test_peace_conference_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_peace_conference_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_peace_conference_primary_command_routing.py ]]; then
  python3 tools/map_generation/tests/test_peace_conference_primary_command_routing.py
fi
if [[ -f tools/map_generation/tests/test_occupation_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_occupation_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_occupation_primary_command_routing.py ]]; then
  python3 tools/map_generation/tests/test_occupation_primary_command_routing.py
fi
if [[ -f tools/map_generation/tests/test_research_queue_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_research_queue_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_research_queue_primary_command_routing.py ]]; then
  python3 tools/map_generation/tests/test_research_queue_primary_command_routing.py
fi
if [[ -f tools/map_generation/tests/test_agent_mission_board_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_agent_mission_board_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_agent_mission_board_primary_command_routing.py ]]; then
  python3 tools/map_generation/tests/test_agent_mission_board_primary_command_routing.py
fi
if [[ -f tools/map_generation/tests/test_war_economy_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_war_economy_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_war_economy_primary_command_routing.py ]]; then
  python3 tools/map_generation/tests/test_war_economy_primary_command_routing.py
fi

if [[ -f tools/map_generation/tests/test_air_theater_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_air_theater_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_battle_aar_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_battle_aar_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_command_journal_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_command_journal_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_c3_c4_n2_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_c3_c4_n2_routing.py
fi

if [[ -f tools/map_generation/tests/test_nuts3_promote_remap_product.py ]]; then
  python3 tools/map_generation/tests/test_nuts3_promote_remap_product.py
fi
if [[ -f tools/map_generation/tests/test_designer_domain_live_product.py ]]; then
  python3 tools/map_generation/tests/test_designer_domain_live_product.py
fi
if [[ -f tools/map_generation/tests/test_campaign_ai_multi_month_product.py ]]; then
  python3 tools/map_generation/tests/test_campaign_ai_multi_month_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase3_depth_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase3_depth_days.py
fi
if [[ -f tools/map_generation/tests/test_occupation_revolt_garrison_product.py ]]; then
  python3 tools/map_generation/tests/test_occupation_revolt_garrison_product.py
fi
if [[ -f tools/map_generation/tests/test_manpower_cohort_reserve_product.py ]]; then
  python3 tools/map_generation/tests/test_manpower_cohort_reserve_product.py
fi
if [[ -f tools/map_generation/tests/test_multi_party_peace_conference_product.py ]]; then
  python3 tools/map_generation/tests/test_multi_party_peace_conference_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase4_depth_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase4_depth_days.py
fi

if [[ -f tools/map_generation/tests/test_historical_oob_content_product.py ]]; then
  python3 tools/map_generation/tests/test_historical_oob_content_product.py
fi
if [[ -f tools/map_generation/tests/test_tech_tree_branching_product.py ]]; then
  python3 tools/map_generation/tests/test_tech_tree_branching_product.py
fi
if [[ -f tools/map_generation/tests/test_save_resume_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_save_resume_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase5_depth_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase5_depth_days.py
fi
if [[ -f tools/map_generation/tests/test_tutorial_first_session_product.py ]]; then
  python3 tools/map_generation/tests/test_tutorial_first_session_product.py
fi
if [[ -f tools/map_generation/tests/test_focus_tree_content_product.py ]]; then
  python3 tools/map_generation/tests/test_focus_tree_content_product.py
fi
if [[ -f tools/map_generation/tests/test_balance_combat_supply_product.py ]]; then
  python3 tools/map_generation/tests/test_balance_combat_supply_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase6_depth_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase6_depth_days.py
fi
if [[ -f tools/map_generation/tests/test_air_multi_phase_theater_product.py ]]; then
  python3 tools/map_generation/tests/test_air_multi_phase_theater_product.py
fi
if [[ -f tools/map_generation/tests/test_naval_search_strike_product.py ]]; then
  python3 tools/map_generation/tests/test_naval_search_strike_product.py
fi
if [[ -f tools/map_generation/tests/test_war_economy_conversion_product.py ]]; then
  python3 tools/map_generation/tests/test_war_economy_conversion_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase7_depth_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase7_depth_days.py
fi
if [[ -f tools/map_generation/tests/test_designer_module_catalog.py ]]; then
  python3 tools/map_generation/tests/test_designer_module_catalog.py
fi
if [[ -f tools/map_generation/tests/test_designer_module_editor_product.py ]]; then
  python3 tools/map_generation/tests/test_designer_module_editor_product.py
fi
if [[ -f tools/map_generation/tests/test_designer_stats_field_product.py ]]; then
  python3 tools/map_generation/tests/test_designer_stats_field_product.py
fi
if [[ -f tools/map_generation/tests/test_designer_multi_domain_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_designer_multi_domain_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase8_designers_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase8_designers_days.py
fi
if [[ -f tools/map_generation/tests/test_weather_crisis_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_weather_crisis_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_intel_cell_network_product.py ]]; then
  python3 tools/map_generation/tests/test_intel_cell_network_product.py
fi
if [[ -f tools/map_generation/tests/test_leader_theater_command_product.py ]]; then
  python3 tools/map_generation/tests/test_leader_theater_command_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase9_cycle_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase9_cycle_days.py
fi
if [[ -f tools/map_generation/tests/test_strategic_war_goal_product.py ]]; then
  python3 tools/map_generation/tests/test_strategic_war_goal_product.py
fi
if [[ -f tools/map_generation/tests/test_multi_front_campaign_ai_product.py ]]; then
  python3 tools/map_generation/tests/test_multi_front_campaign_ai_product.py
fi
if [[ -f tools/map_generation/tests/test_grand_strategy_cycle_product.py ]]; then
  python3 tools/map_generation/tests/test_grand_strategy_cycle_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase10_gs_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase10_gs_days.py
fi
if [[ -f tools/map_generation/tests/test_alliance_guarantee_network_product.py ]]; then
  python3 tools/map_generation/tests/test_alliance_guarantee_network_product.py
fi
if [[ -f tools/map_generation/tests/test_faction_personality_ai_product.py ]]; then
  python3 tools/map_generation/tests/test_faction_personality_ai_product.py
fi
if [[ -f tools/map_generation/tests/test_occupation_revolt_network_product.py ]]; then
  python3 tools/map_generation/tests/test_occupation_revolt_network_product.py
fi
if [[ -f tools/map_generation/tests/test_next12_phase11_depth_days.py ]]; then
  python3 tools/map_generation/tests/test_next12_phase11_depth_days.py
fi
if [[ -f tools/map_generation/tests/test_map_visual_gap_product.py ]]; then
  python3 tools/map_generation/tests/test_map_visual_gap_product.py
fi
if [[ -f tools/map_generation/tests/test_map_visual_regression_fingerprint.py ]]; then
  python3 tools/map_generation/tests/test_map_visual_regression_fingerprint.py
fi
if [[ -f tools/map_generation/tests/test_map_visual_phase23_product.py ]]; then
  python3 tools/map_generation/tests/test_map_visual_phase23_product.py
fi
if [[ -f tools/map_generation/tests/test_designer_suite_product.py ]]; then
  python3 tools/map_generation/tests/test_designer_suite_product.py
fi
if [[ -f tools/map_generation/tests/test_world_hotspots_and_cities.py ]]; then
  python3 tools/map_generation/tests/test_world_hotspots_and_cities.py
fi
if [[ -f tools/map_generation/tests/test_world_hotspot_names_and_layers.py ]]; then
  python3 tools/map_generation/tests/test_world_hotspot_names_and_layers.py
fi
if [[ -f tools/map_generation/tests/test_world_ownership_1936.py ]]; then
  python3 tools/map_generation/tests/test_world_ownership_1936.py
fi
if [[ -f tools/map_generation/tests/test_formation_station_resolver.py ]]; then
  python3 tools/map_generation/tests/test_formation_station_resolver.py
fi
if [[ -f tools/map_generation/tests/test_leader_formation_assigner.py ]]; then
  python3 tools/map_generation/tests/test_leader_formation_assigner.py
fi
if [[ -f tools/map_generation/tests/test_branch_leader_assigner.py ]]; then
  python3 tools/map_generation/tests/test_branch_leader_assigner.py
fi
if [[ -f tools/map_generation/tests/test_industry_bootstrap.py ]]; then
  python3 tools/map_generation/tests/test_industry_bootstrap.py
fi
if [[ -f tools/map_generation/tests/test_production_stockpile.py ]]; then
  python3 tools/map_generation/tests/test_production_stockpile.py
fi
if [[ -f tools/map_generation/tests/test_daily_production_equip.py ]]; then
  python3 tools/map_generation/tests/test_daily_production_equip.py
fi
# Optional Godot-driven stockpile API tests (skip if Godot binary missing)
if [[ -x tools/run_godot.sh ]] && tools/run_godot.sh --version >/dev/null 2>&1; then
  if [[ -f scripts/core/HeadlessFactoryStockpileTest.gd ]]; then
    echo "--- HeadlessFactoryStockpileTest (shipped advance_days + stockpile) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessFactoryStockpileTest.gd
    _stock_rc=$?
    set -e
    if [[ $_stock_rc -ne 0 ]]; then
      echo "FAIL: HeadlessFactoryStockpileTest exit $_stock_rc"
      exit "$_stock_rc"
    fi
    echo "PASS HeadlessFactoryStockpileTest"
  fi
  if [[ -f scripts/core/HeadlessDailyProductionStockpileTest.gd ]]; then
    echo "--- HeadlessDailyProductionStockpileTest (daily_production_tick path) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessDailyProductionStockpileTest.gd
    _daily_rc=$?
    set -e
    if [[ $_daily_rc -ne 0 ]]; then
      echo "FAIL: HeadlessDailyProductionStockpileTest exit $_daily_rc"
      exit "$_daily_rc"
    fi
    echo "PASS HeadlessDailyProductionStockpileTest"
  fi
  if [[ -f scripts/core/HeadlessCombatEquipShortageTest.gd ]]; then
    echo "--- HeadlessCombatEquipShortageTest (combat equip + reinforce stockpile) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCombatEquipShortageTest.gd
    _combat_rc=$?
    set -e
    if [[ $_combat_rc -ne 0 ]]; then
      echo "FAIL: HeadlessCombatEquipShortageTest exit $_combat_rc"
      exit "$_combat_rc"
    fi
    echo "PASS HeadlessCombatEquipShortageTest"
  fi
  if [[ -f scripts/core/HeadlessCombatEquipmentLossTest.gd ]]; then
    echo "--- HeadlessCombatEquipmentLossTest (combat loss → equip write-off → reinforce) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCombatEquipmentLossTest.gd
    _loss_rc=$?
    set -e
    if [[ $_loss_rc -ne 0 ]]; then
      echo "FAIL: HeadlessCombatEquipmentLossTest exit $_loss_rc"
      exit "$_loss_rc"
    fi
    echo "PASS HeadlessCombatEquipmentLossTest"
  fi
  if [[ -f scripts/core/HeadlessCombatEquipCycleTest.gd ]]; then
    echo "--- HeadlessCombatEquipCycleTest (equip→loss→shortage→reinforce) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCombatEquipCycleTest.gd
    _cycle_rc=$?
    set -e
    if [[ $_cycle_rc -ne 0 ]]; then
      echo "FAIL: HeadlessCombatEquipCycleTest exit $_cycle_rc"
      exit "$_cycle_rc"
    fi
    echo "PASS HeadlessCombatEquipCycleTest"
  fi
  if [[ -f scripts/core/HeadlessCombatPowerEquipmentTest.gd ]]; then
    echo "--- HeadlessCombatPowerEquipmentTest (estimate/resolve + fight cycle) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCombatPowerEquipmentTest.gd
    _pwr_rc=$?
    set -e
    if [[ $_pwr_rc -ne 0 ]]; then
      echo "FAIL: HeadlessCombatPowerEquipmentTest exit $_pwr_rc"
      exit "$_pwr_rc"
    fi
    echo "PASS HeadlessCombatPowerEquipmentTest"
  fi
  if [[ -f scripts/core/HeadlessAssaultEstimateEquipmentTest.gd ]]; then
    echo "--- HeadlessAssaultEstimateEquipmentTest (pick/estimate prefers stocked) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAssaultEstimateEquipmentTest.gd
    _assault_rc=$?
    set -e
    if [[ $_assault_rc -ne 0 ]]; then
      echo "FAIL: HeadlessAssaultEstimateEquipmentTest exit $_assault_rc"
      exit "$_assault_rc"
    fi
    echo "PASS HeadlessAssaultEstimateEquipmentTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullAssaultEntryTest.gd ]]; then
    echo "--- HeadlessWorldFullAssaultEntryTest (can_assault+execute on world_full edge) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullAssaultEntryTest.gd
    _wf_rc=$?
    set -e
    if [[ $_wf_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullAssaultEntryTest exit $_wf_rc"
      exit "$_wf_rc"
    fi
    echo "PASS HeadlessWorldFullAssaultEntryTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullAssaultCaptureTest.gd ]]; then
    echo "--- HeadlessWorldFullAssaultCaptureTest (owner flip on attacker win) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullAssaultCaptureTest.gd
    _cap_rc=$?
    set -e
    if [[ $_cap_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullAssaultCaptureTest exit $_cap_rc"
      exit "$_cap_rc"
    fi
    echo "PASS HeadlessWorldFullAssaultCaptureTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureStationTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureStationTest (attacker station on captured province) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureStationTest.gd
    _st_rc=$?
    set -e
    if [[ $_st_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureStationTest exit $_st_rc"
      exit "$_st_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureStationTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureDefenderDisplaceTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureDefenderDisplaceTest (defender leaves captured province) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureDefenderDisplaceTest.gd
    _dd_rc=$?
    set -e
    if [[ $_dd_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureDefenderDisplaceTest exit $_dd_rc"
      exit "$_dd_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureDefenderDisplaceTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureFollowOnAssaultTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureFollowOnAssaultTest (can_assault from captured province) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureFollowOnAssaultTest.gd
    _fo_rc=$?
    set -e
    if [[ $_fo_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureFollowOnAssaultTest exit $_fo_rc"
      exit "$_fo_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureFollowOnAssaultTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureFollowOnExecuteTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureFollowOnExecuteTest (execute from captured province) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureFollowOnExecuteTest.gd
    _foe_rc=$?
    set -e
    if [[ $_foe_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureFollowOnExecuteTest exit $_foe_rc"
      exit "$_foe_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureFollowOnExecuteTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureChainAssaultTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureChainAssaultTest (chain/flank from captured province) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureChainAssaultTest.gd
    _ch_rc=$?
    set -e
    if [[ $_ch_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureChainAssaultTest exit $_ch_rc"
      exit "$_ch_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureChainAssaultTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureFactoryTransferTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureFactoryTransferTest (factory owner on capture) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureFactoryTransferTest.gd
    _ft_rc=$?
    set -e
    if [[ $_ft_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureFactoryTransferTest exit $_ft_rc"
      exit "$_ft_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureFactoryTransferTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureSeizedFactoryProductionTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureSeizedFactoryProductionTest (seized factory → attacker stockpile) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureSeizedFactoryProductionTest.gd
    _sfp_rc=$?
    set -e
    if [[ $_sfp_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureSeizedFactoryProductionTest exit $_sfp_rc"
      exit "$_sfp_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureSeizedFactoryProductionTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureDesignGrantTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureDesignGrantTest (foreign design grant on factory capture) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureDesignGrantTest.gd
    _dg_rc=$?
    set -e
    if [[ $_dg_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureDesignGrantTest exit $_dg_rc"
      exit "$_dg_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureDesignGrantTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest (may-use + produce + field) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest.gd
    _adf_rc=$?
    set -e
    if [[ $_adf_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest exit $_adf_rc"
      exit "$_adf_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest (reinforce + power + equip-loss) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest.gd
    _fdcl_rc=$?
    set -e
    if [[ $_fdcl_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest exit $_fdcl_rc"
      exit "$_fdcl_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureForeignDesignCombatLoopTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureSaveLoadConquestStateTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureSaveLoadConquestStateTest (design + factory + stations saveload) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureSaveLoadConquestStateTest.gd
    _slcs_rc=$?
    set -e
    if [[ $_slcs_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureSaveLoadConquestStateTest exit $_slcs_rc"
      exit "$_slcs_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureSaveLoadConquestStateTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest (map owner + stockpile + equip saveload) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest.gd
    _mse_rc=$?
    set -e
    if [[ $_mse_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest exit $_mse_rc"
      exit "$_mse_rc"
    fi
    echo "PASS HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCapturePostLoadPlayabilityTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCapturePostLoadPlayabilityTest (post-load can_assault + reinforce + combat stats) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadPlayabilityTest.gd
    _plp_rc=$?
    set -e
    if [[ $_plp_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCapturePostLoadPlayabilityTest exit $_plp_rc"
      exit "$_plp_rc"
    fi
    echo "PASS HeadlessWorldFullPostCapturePostLoadPlayabilityTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCapturePostLoadConquestLoopTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCapturePostLoadConquestLoopTest (post-load execute + seized prod + field design) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadConquestLoopTest.gd
    _pcl_rc=$?
    set -e
    if [[ $_pcl_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCapturePostLoadConquestLoopTest exit $_pcl_rc"
      exit "$_pcl_rc"
    fi
    echo "PASS HeadlessWorldFullPostCapturePostLoadConquestLoopTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCapturePostLoadCombatEquipCycleTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCapturePostLoadCombatEquipCycleTest (post-load loss + shortage + re-reinforce) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadCombatEquipCycleTest.gd
    _pcec_rc=$?
    set -e
    if [[ $_pcec_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCapturePostLoadCombatEquipCycleTest exit $_pcec_rc"
      exit "$_pcec_rc"
    fi
    echo "PASS HeadlessWorldFullPostCapturePostLoadCombatEquipCycleTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCapturePostLoadChainAssaultTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCapturePostLoadChainAssaultTest (post-load chain ≥2 + follow-from-captured + daily reinforce) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadChainAssaultTest.gd
    _plca_rc=$?
    set -e
    if [[ $_plca_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCapturePostLoadChainAssaultTest exit $_plca_rc"
      exit "$_plca_rc"
    fi
    echo "PASS HeadlessWorldFullPostCapturePostLoadChainAssaultTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest (post-load second province flip) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest.gd
    _plsf_rc=$?
    set -e
    if [[ $_plsf_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest exit $_plsf_rc"
      exit "$_plsf_rc"
    fi
    echo "PASS HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest"
  fi
  if [[ -f scripts/core/HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest.gd ]]; then
    echo "--- HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest (slot save_game_detailed / load_game_detailed) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest.gd
    _plsl_rc=$?
    set -e
    if [[ $_plsl_rc -ne 0 ]]; then
      echo "FAIL: HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest exit $_plsl_rc"
      exit "$_plsl_rc"
    fi
    echo "PASS HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest"
  fi
fi
if [[ -f tools/map_generation/tests/test_combat_equip_shortage.py ]]; then
  python3 tools/map_generation/tests/test_combat_equip_shortage.py
fi
if [[ -f tools/map_generation/tests/test_combat_equipment_loss.py ]]; then
  python3 tools/map_generation/tests/test_combat_equipment_loss.py
fi
if [[ -f tools/map_generation/tests/test_combat_equip_cycle.py ]]; then
  python3 tools/map_generation/tests/test_combat_equip_cycle.py
fi
if [[ -f tools/map_generation/tests/test_combat_power_equipment.py ]]; then
  python3 tools/map_generation/tests/test_combat_power_equipment.py
fi
if [[ -f tools/map_generation/tests/test_assault_estimate_equipment.py ]]; then
  python3 tools/map_generation/tests/test_assault_estimate_equipment.py
fi
if [[ -f tools/map_generation/tests/test_world_full_assault_entry.py ]]; then
  python3 tools/map_generation/tests/test_world_full_assault_entry.py
fi
if [[ -f tools/map_generation/tests/test_world_full_assault_capture.py ]]; then
  python3 tools/map_generation/tests/test_world_full_assault_capture.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_station.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_station.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_defender_displace.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_defender_displace.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_follow_on_assault.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_follow_on_assault.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_follow_on_execute.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_follow_on_execute.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_chain_assault.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_chain_assault.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_factory_transfer.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_factory_transfer.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_seized_factory_production.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_seized_factory_production.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_design_grant.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_design_grant.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_acquired_design_fielding.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_acquired_design_fielding.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_foreign_design_combat_loop.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_foreign_design_combat_loop.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_saveload_conquest_state.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_saveload_conquest_state.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_saveload_map_stock_equip.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_saveload_map_stock_equip.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_postload_playability.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_postload_playability.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_postload_conquest_loop.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_postload_conquest_loop.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_postload_combat_equip_cycle.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_postload_combat_equip_cycle.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_postload_chain_assault.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_postload_chain_assault.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_postload_second_province_flip.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_postload_second_province_flip.py
fi
if [[ -f tools/map_generation/tests/test_world_full_post_capture_postload_slot_saveload.py ]]; then
  python3 tools/map_generation/tests/test_world_full_post_capture_postload_slot_saveload.py
fi
if [[ -f tools/map_generation/tests/test_map_polish_infra_sites_chokepoints.py ]]; then
  python3 tools/map_generation/tests/test_map_polish_infra_sites_chokepoints.py
fi
if [[ -f tools/map_generation/tests/test_inspector_topline_and_era_sites.py ]]; then
  python3 tools/map_generation/tests/test_inspector_topline_and_era_sites.py
fi
if [[ -f tools/map_generation/tests/test_slot_save_ui_gis_sea_control.py ]]; then
  python3 tools/map_generation/tests/test_slot_save_ui_gis_sea_control.py
fi
if [[ -f tools/map_generation/tests/test_gis_coastline_ingest.py ]]; then
  python3 tools/map_generation/tests/test_gis_coastline_ingest.py
fi
if [[ -f tools/map_generation/tests/test_naval_basing_pilot.py ]]; then
  python3 tools/map_generation/tests/test_naval_basing_pilot.py
fi
if [[ -f tools/map_generation/tests/test_naval_basing_effect.py ]]; then
  python3 tools/map_generation/tests/test_naval_basing_effect.py
fi
if [[ -f tools/map_generation/tests/test_sea_zone_live_effect.py ]]; then
  python3 tools/map_generation/tests/test_sea_zone_live_effect.py
fi
if [[ -f tools/map_generation/tests/test_next10_pilots.py ]]; then
  python3 tools/map_generation/tests/test_next10_pilots.py
fi
if [[ -f tools/map_generation/tests/test_next10_round2_pilots.py ]]; then
  python3 tools/map_generation/tests/test_next10_round2_pilots.py
fi
if [[ -f tools/map_generation/tests/test_next20_pilots.py ]]; then
  python3 tools/map_generation/tests/test_next20_pilots.py
fi
if [[ -f tools/map_generation/tests/test_next20_weather_expand.py ]]; then
  python3 tools/map_generation/tests/test_next20_weather_expand.py
fi
if [[ -f tools/map_generation/tests/test_next20_weather_deepen.py ]]; then
  python3 tools/map_generation/tests/test_next20_weather_deepen.py
fi
if [[ -f tools/map_generation/tests/test_next20_ops_expand.py ]]; then
  python3 tools/map_generation/tests/test_next20_ops_expand.py
fi
if [[ -f tools/map_generation/tests/test_next20_theater_expand.py ]]; then
  python3 tools/map_generation/tests/test_next20_theater_expand.py
fi
if [[ -f tools/map_generation/tests/test_next20_integration.py ]]; then
  python3 tools/map_generation/tests/test_next20_integration.py
fi
if [[ -f tools/map_generation/tests/test_next20_gameplay_loops.py ]]; then
  python3 tools/map_generation/tests/test_next20_gameplay_loops.py
fi
if [[ -f tools/map_generation/tests/test_next20_campaign_cohesion.py ]]; then
  python3 tools/map_generation/tests/test_next20_campaign_cohesion.py
fi
if [[ -f tools/map_generation/tests/test_next20_campaign_execution.py ]]; then
  python3 tools/map_generation/tests/test_next20_campaign_execution.py
fi
if [[ -f tools/map_generation/tests/test_next20_live_mutation.py ]]; then
  python3 tools/map_generation/tests/test_next20_live_mutation.py
fi
if [[ -f tools/map_generation/tests/test_next20_theater_command.py ]]; then
  python3 tools/map_generation/tests/test_next20_theater_command.py
fi
if [[ -f tools/map_generation/tests/test_next20_daily_command.py ]]; then
  python3 tools/map_generation/tests/test_next20_daily_command.py
fi
if [[ -f tools/map_generation/tests/test_next20_ops_depth.py ]]; then
  python3 tools/map_generation/tests/test_next20_ops_depth.py
fi
if [[ -f tools/map_generation/tests/test_next20_priority_systems.py ]]; then
  python3 tools/map_generation/tests/test_next20_priority_systems.py
fi
if [[ -f tools/map_generation/tests/test_next20_product_depth.py ]]; then
  python3 tools/map_generation/tests/test_next20_product_depth.py
fi
if [[ -f tools/map_generation/tests/test_next20_campaign_ops.py ]]; then
  python3 tools/map_generation/tests/test_next20_campaign_ops.py
fi
if [[ -f tools/map_generation/tests/test_next20_day_ops.py ]]; then
  python3 tools/map_generation/tests/test_next20_day_ops.py
fi
if [[ -f tools/map_generation/tests/test_next20_theater_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_theater_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_war_economy_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_war_economy_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_logistics_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_logistics_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_air_forecast_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_air_forecast_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_joint_command_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_joint_command_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_strategic_continuity_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_strategic_continuity_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_force_readiness_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_force_readiness_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_industry_surge_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_industry_surge_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_joint_campaign_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_joint_campaign_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_weather_crisis_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_weather_crisis_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_agent_campaign_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_agent_campaign_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_combat_campaign_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_combat_campaign_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_fleet_campaign_day.py ]]; then
  python3 tools/map_generation/tests/test_next20_fleet_campaign_day.py
fi
if [[ -f tools/map_generation/tests/test_next20_order_panel_ux_depth.py ]]; then
  python3 tools/map_generation/tests/test_next20_order_panel_ux_depth.py
fi
if [[ -f tools/map_generation/tests/test_next20_inspector_product_depth.py ]]; then
  python3 tools/map_generation/tests/test_next20_inspector_product_depth.py
fi
if [[ -f tools/map_generation/tests/test_next20_week2_core_polish.py ]]; then
  python3 tools/map_generation/tests/test_next20_week2_core_polish.py
fi
if [[ -f tools/map_generation/tests/test_next20_week3_naval_hh_depth.py ]]; then
  python3 tools/map_generation/tests/test_next20_week3_naval_hh_depth.py
fi
if [[ -f tools/map_generation/tests/test_next20_week4_polish_depth.py ]]; then
  python3 tools/map_generation/tests/test_next20_week4_polish_depth.py
fi
if [[ -f tools/map_generation/tests/test_next20_next10_depth.py ]]; then
  python3 tools/map_generation/tests/test_next20_next10_depth.py
fi
if [[ -f tools/map_generation/tests/test_next20_priority_depth_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_priority_depth_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_theater_surface_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_theater_surface_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_campaign_surface_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_campaign_surface_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_ops_mutation_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_ops_mutation_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_command_depth_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_command_depth_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_playability_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_playability_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_execution_surface_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_execution_surface_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_live_command_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_live_command_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_world_class_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_world_class_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_incomplete_loops_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_incomplete_loops_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_industry_save_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_industry_save_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_fleet_hh_combat_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_fleet_hh_combat_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_logistics_force_panel_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_logistics_force_panel_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_weather_economy_intel_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_weather_economy_intel_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_theater_naval_session_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_theater_naval_session_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_combat_agent_joint_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_combat_agent_joint_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_prod_air_focus_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_prod_air_focus_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_save_leader_trade_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_save_leader_trade_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_inspector_infra_auto_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_inspector_infra_auto_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_assault_choke_agent_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_assault_choke_agent_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_oob_fleet_hh_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_oob_fleet_hh_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_force_weather_focus_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_force_weather_focus_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_air_convoy_order_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_air_convoy_order_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_leader_intel_theater_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_leader_intel_theater_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_save_prod_combat_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_save_prod_combat_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_naval_theater_inspector_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_naval_theater_inspector_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_weather_economy_force_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_weather_economy_force_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_full_game_campaign_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_full_game_campaign_days.py
fi
if [[ -f tools/map_generation/tests/test_next20_playability_campaign_days.py ]]; then
  python3 tools/map_generation/tests/test_next20_playability_campaign_days.py
fi
if [[ -f tools/map_generation/tests/test_multi_phase_combat_product.py ]]; then
  python3 tools/map_generation/tests/test_multi_phase_combat_product.py
fi
if [[ -f tools/map_generation/tests/test_fleet_multi_day_autonomy_product.py ]]; then
  python3 tools/map_generation/tests/test_fleet_multi_day_autonomy_product.py
fi
if [[ -f tools/map_generation/tests/test_save_browser_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_save_browser_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_medium_tank_oob_product.py ]]; then
  python3 tools/map_generation/tests/test_medium_tank_oob_product.py
fi
if [[ -f tools/map_generation/tests/test_hh_multi_month_agenda_product.py ]]; then
  python3 tools/map_generation/tests/test_hh_multi_month_agenda_product.py
fi
if [[ -f tools/map_generation/tests/test_agent_campaign_product.py ]]; then
  python3 tools/map_generation/tests/test_agent_campaign_product.py
fi
if [[ -f tools/map_generation/tests/test_inspector_theater_command_products.py ]]; then
  python3 tools/map_generation/tests/test_inspector_theater_command_products.py
fi
if [[ -f tools/map_generation/tests/test_hh_third_class_and_chokepoint_contest.py ]]; then
  python3 tools/map_generation/tests/test_hh_third_class_and_chokepoint_contest.py
fi
if [[ -f tools/map_generation/tests/test_map_action_feedback.py ]]; then
  python3 tools/map_generation/tests/test_map_action_feedback.py
fi
if [[ -f tools/map_generation/tests/test_mesh_batch_and_hh_agenda_trail.py ]]; then
  python3 tools/map_generation/tests/test_mesh_batch_and_hh_agenda_trail.py
fi
if [[ -f tools/map_generation/tests/test_sea_zone_modifiers_and_hh_agenda_surface.py ]]; then
  python3 tools/map_generation/tests/test_sea_zone_modifiers_and_hh_agenda_surface.py
fi
if [[ -f tools/map_generation/tests/test_world_map_star_polish.py ]]; then
  python3 tools/map_generation/tests/test_world_map_star_polish.py
fi
if [[ -f tools/map_generation/tests/test_resource_icon_lod.py ]]; then
  python3 tools/map_generation/tests/test_resource_icon_lod.py
fi
if [[ -f tools/map_generation/tests/test_capital_centroid_spotcheck.py ]]; then
  python3 tools/map_generation/tests/test_capital_centroid_spotcheck.py
fi
if [[ -f tools/map_generation/tests/test_sea_zone_theaters.py ]]; then
  python3 tools/map_generation/tests/test_sea_zone_theaters.py
fi
if [[ -f tools/map_generation/tests/test_relabel_strategic_regions.py ]]; then
  python3 tools/map_generation/tests/test_relabel_strategic_regions.py
fi
if [[ -f tools/map_generation/tests/test_map_next_list_debug_damage_hh.py ]]; then
  python3 tools/map_generation/tests/test_map_next_list_debug_damage_hh.py
fi
if [[ -f tools/map_generation/tests/test_eoa_map_flair_hh_counterplay.py ]]; then
  python3 tools/map_generation/tests/test_eoa_map_flair_hh_counterplay.py
fi
# HH dual map signal (primary + secondary / economic_pressure)
if [[ -x tools/run_godot.sh ]] && tools/run_godot.sh --version >/dev/null 2>&1; then
  if [[ -f scripts/core/HeadlessHHMapDualSignalTest.gd ]]; then
    echo "--- HeadlessHHMapDualSignalTest (HH primary+secondary map signals) ---"
    set +e
    tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHHMapDualSignalTest.gd
    _hh_rc=$?
    set -e
    if [[ $_hh_rc -ne 0 ]]; then
      echo "FAIL: HeadlessHHMapDualSignalTest exit $_hh_rc"
      exit "$_hh_rc"
    fi
    echo "PASS HeadlessHHMapDualSignalTest"
  fi
fi

# Name dry-run only on europe dirs (gazetteer Europe-focused)
if [[ "$DIR" == *full_europe* || "$DIR" == *phase1* ]]; then
  python3 tools/map_generation/scripts/assign_europe_province_names.py --dir "$DIR" --dry-run
fi

echo "--- densify dry-run (geometry quality) ---"
python3 tools/map_generation/scripts/densify_province_geometry.py --dir "$DIR" --dry-run --min-vertices 12

echo "--- validate SHIPPED strategic_regions.json (do not re-kmeans with default k) ---"
python3 - <<PY
import json
import sys
from pathlib import Path

sys.path.insert(0, "tools/map_generation/scripts")
from rebuild_strategic_regions import quality_gates  # noqa: E402

d = Path("$DIR")
base = json.loads((d / "provinces_base.json").read_text())["provinces"]
geom = json.loads((d / "provinces_geometry.json").read_text())["provinces"]
reg_payload = json.loads((d / "strategic_regions.json").read_text())
gates = quality_gates(reg_payload, len(geom))
print("shipped regions gates:", gates)
assert gates["full_coverage"], gates
assert gates["no_dup_ids"], gates
assert gates["region_count"] >= 12, gates
assert not gates["empty_regions"], gates
# World-full rebalanced target: max share ≤12%; Europe baselines keep ≤35%
_share_cap = 0.12 if "world_full" in str(d) else 0.35
assert gates["max_region_share"] <= _share_cap + 1e-9, (gates, _share_cap)
if "world_full" in str(d):
    assert gates["min_region_size"] >= 8, gates
print("PASS shipped strategic_regions.json quality gates", "share_cap=", _share_cap)
PY

echo "--- layer id + world/city gates ---"
python3 - <<PY
import json
import math
from pathlib import Path
from collections import Counter

d = Path("$DIR")
base = json.loads((d / "provinces_base.json").read_text())["provinces"]
geom = json.loads((d / "provinces_geometry.json").read_text())["provinces"]
reg = json.loads((d / "strategic_regions.json").read_text())["regions"]
bids = {int(p["id"]) for p in base}
gids = {int(g["id"]) for g in geom}
assert bids == gids, f"base/geom id mismatch {len(bids)} vs {len(gids)}"
rids = set()
for r in reg:
    rids.update(int(x) for x in r["province_ids"])
assert rids == gids, f"regions coverage mismatch {len(rids)} vs {len(gids)}"
sea = sum(1 for p in base if p.get("domain") in ("sea", "strait", "lake"))
print(f"PASS layer id consistency: {len(gids)} provinces, {len(reg)} regions, water={sea} ({sea/len(base):.1%})")

sizes = [len(g.get("points") or []) for g in geom]
assert min(sizes) >= 12 and sum(1 for s in sizes if s == 3) == 0
print(f"PASS geometry verts min={min(sizes)} median={sorted(sizes)[len(sizes)//2]} triangles=0")

if "world_full" in str(d) or "grand_theater" in str(d):
    assert len(base) >= 700, len(base)
    assert all("facility_tier" in p for p in base)
    meta = json.loads((d / "provinces_base.json").read_text()).get("meta") or {}
    if "world_full" in str(d):
        assert meta.get("geometry_space") == "world" or meta.get("geometry_world_native")
        assert len(base) >= 2200
        # City layer near anchors
        city = json.loads((d / "province_city_layer.json").read_text())["provinces"]
        geom_by = {int(g["id"]): g for g in geom}
        far = 0
        nonempty = 0
        for p in base:
            sid = str(p["id"])
            cities = (city.get(sid) or {}).get("cities") or []
            if not cities:
                continue
            nonempty += 1
            g = geom_by[int(sid)]
            if g.get("label_anchor") and len(g["label_anchor"]) >= 2:
                ax, ay = float(g["label_anchor"][0]), float(g["label_anchor"][1])
            else:
                pts = g["points"]
                ax = sum(float(x[0]) for x in pts) / len(pts)
                ay = sum(float(x[1]) for x in pts) / len(pts)
            for ci in cities:
                if math.hypot(float(ci["x"]) - ax, float(ci["y"]) - ay) > 500:
                    far += 1
        assert far == 0, f"{far} cities far from province anchor"
        assert nonempty >= 40, nonempty
        print(f"PASS world city anchors: nonempty={nonempty} far=0")
        # Hotspot names + layer coverage (playability gates)
        import re
        hot = [p for p in base if p.get("hotspot_densify")]
        assert hot, "expected hotspot densify provinces"
        numbered = [p["name"] for p in hot if re.match(r"^.+\s+\d+\s*$", str(p.get("name") or ""))]
        assert not numbered, f"numbered hub labels remain: {numbered[:5]}"
        names = [str(p.get("name") or "").strip().lower() for p in base]
        assert all(names) and len(set(names)) == len(names)
        terr = json.loads((d / "province_terrain_layer.json").read_text())["provinces"]
        assert {str(p["id"]) for p in base} <= set(map(str, terr.keys()))
        res = json.loads((d / "province_resources_layer.json").read_text())["provinces"]
        econ = json.loads((d / "province_economy_layer.json").read_text())["provinces"]
        for p in hot:
            if p.get("domain") in ("sea", "strait", "lake"):
                continue
            sid = str(p["id"])
            re_e = res.get(sid) or {}
            assert isinstance(re_e, dict) and (re_e.get("resources") or re_e.get("primary_resource")), sid
            ec = econ.get(sid) or {}
            assert isinstance(ec, dict) and (
                int(ec.get("population") or 0) > 0
                or float(ec.get("development_level") or 0) > 0
                or (ec.get("resources") or {})
            ), sid
        print(f"PASS hotspot names+layers: hot={len(hot)} terrain={len(terr)}")
        # Political ownership (world_full scenario payload)
        scen_path = Path("data/scenarios/world_full.json")
        if scen_path.exists():
            scen = json.loads(scen_path.read_text())
            assert isinstance(scen.get("provinces"), list) and len(scen["provinces"]) >= 1000
            own_counts = Counter(str(p.get("owner_tag") or "") for p in scen["provinces"])
            assert own_counts.get("", 0) == 0
            for major in ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"):
                assert own_counts.get(major, 0) >= 5, (major, own_counts.get(major, 0))
            land_ids = {int(p["id"]) for p in base if p.get("domain") not in ("sea", "strait", "lake")}
            owned = {int(p["id"]) for p in scen["provinces"] if p.get("owner_tag")}
            cov = len(owned & land_ids) / max(1, len(land_ids))
            assert cov >= 0.95, cov
            print(f"PASS ownership: overrides={len(scen['provinces'])} land_cov={cov:.1%} tags={len(own_counts)}")
    print(f"PASS dataset gates: n={len(base)} facility sample OK")

print(f"PASS map CI complete for {d}")
PY

if [[ -f tools/map_generation/tests/test_ownership_era_tables.py ]]; then
  python3 tools/map_generation/tests/test_ownership_era_tables.py
fi
if [[ -f tools/map_generation/tests/test_map_hierarchy_product.py ]]; then
  python3 tools/map_generation/tests/test_map_hierarchy_product.py
fi

if [[ -f tools/map_generation/tests/test_europe_pilot_densify.py ]]; then
  python3 tools/map_generation/tests/test_europe_pilot_densify.py
fi

if [[ -f tools/map_generation/tests/test_hierarchy_system_product.py ]]; then
  python3 tools/map_generation/tests/test_hierarchy_system_product.py
fi

if [[ -f tools/map_generation/tests/test_membership_era_product.py ]]; then
  python3 tools/map_generation/tests/test_membership_era_product.py
fi

if [[ -f tools/map_generation/tests/test_shared_edge_adjacency_product.py ]]; then
  python3 tools/map_generation/tests/test_shared_edge_adjacency_product.py
fi

if [[ -f tools/map_generation/tests/test_us_pilot_densify.py ]]; then
  python3 tools/map_generation/tests/test_us_pilot_densify.py
fi

if [[ -f tools/map_generation/tests/test_live_membership_mutation_product.py ]]; then
  python3 tools/map_generation/tests/test_live_membership_mutation_product.py
fi

if [[ -f tools/map_generation/tests/test_completion_playability_close_product.py ]]; then
  python3 tools/map_generation/tests/test_completion_playability_close_product.py
fi

if [[ -f tools/map_generation/tests/test_full_designer_duties_product.py ]]; then
  python3 tools/map_generation/tests/test_full_designer_duties_product.py
fi

if [[ -f tools/map_generation/tests/test_session_players_hotseat_product.py ]]; then
  python3 tools/map_generation/tests/test_session_players_hotseat_product.py
fi
if [[ -f tools/map_generation/tests/test_hotseat_turn_banner_product.py ]]; then
  python3 tools/map_generation/tests/test_hotseat_turn_banner_product.py
fi

if [[ -f tools/map_generation/tests/test_multi_faction_ai_daily_depth_product.py ]]; then
  python3 tools/map_generation/tests/test_multi_faction_ai_daily_depth_product.py
fi

if [[ -f tools/map_generation/tests/test_quality_gap_close_product.py ]]; then
  python3 tools/map_generation/tests/test_quality_gap_close_product.py
fi

if [[ -f tools/map_generation/tests/test_nuts3_europe_gis_product.py ]]; then
  python3 tools/map_generation/tests/test_nuts3_europe_gis_product.py
fi

if [[ -f tools/map_generation/tests/test_next20_completion_package_product.py ]]; then
  python3 tools/map_generation/tests/test_next20_completion_package_product.py
fi

if [[ -f tools/map_generation/tests/test_global_density_pilot.py ]]; then
  python3 tools/map_generation/tests/test_global_density_pilot.py
fi
if [[ -f tools/map_generation/tests/test_map_perf_measured_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_map_perf_measured_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_war_goal_alliance_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_war_goal_alliance_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_factory_retool_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_factory_retool_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_m3_di2_p2_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_m3_di2_p2_routing.py
fi
if [[ -f tools/map_generation/tests/test_tutorial_first_session_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_tutorial_first_session_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_multi_faction_ai_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_multi_faction_ai_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_u1_a3_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_u1_a3_g0_routing.py
fi
if [[ -f tools/map_generation/tests/test_weather_theater_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_weather_theater_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_manpower_laws_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_manpower_laws_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_w1_o2_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_w1_o2_g0_routing.py
fi
if [[ -f tools/map_generation/tests/test_focus_tree_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_focus_tree_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_leader_theater_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_leader_theater_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_t2_l2_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_t2_l2_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_intel_network_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_intel_network_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_product_ux_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_product_ux_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_i2_u2_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_i2_u2_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_combat_intel_estimate_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_combat_intel_estimate_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_convoy_sealane_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_convoy_sealane_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_i2b_e2_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_i2b_e2_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_designer_suite_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_designer_suite_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_autosave_session_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_autosave_session_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_d1_s2_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_d1_s2_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_historical_oob_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_historical_oob_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_intel_counter_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_intel_counter_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_x1_i3_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_x1_i3_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_faction_personality_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_faction_personality_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_production_honesty_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_production_honesty_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_a4_p3_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_a4_p3_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_hh_multi_month_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_hh_multi_month_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_logistics_supply_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_logistics_supply_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_hh_log_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_hh_log_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_front_continuity_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_front_continuity_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_designer_depth_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_designer_depth_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_fc_dd_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_fc_dd_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_air_multi_phase_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_air_multi_phase_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_inspector_decision_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_inspector_decision_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_amp_ins_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_amp_ins_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_balance_combat_supply_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_balance_combat_supply_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_fleet_multi_day_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_fleet_multi_day_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_bal_fmd_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_bal_fmd_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_agent_campaign_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_agent_campaign_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_grand_strategy_cycle_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_grand_strategy_cycle_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_acp_gsc_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_acp_gsc_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_world_class_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_world_class_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_multi_front_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_multi_front_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_wcc_mfc_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_wcc_mfc_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_strategic_war_goal_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_strategic_war_goal_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_naval_search_strike_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_naval_search_strike_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_swg_nss_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_swg_nss_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_weather_crisis_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_weather_crisis_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_campaign_ai_multi_month_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_campaign_ai_multi_month_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_wcr_cam_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_wcr_cam_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_tech_research_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_tech_research_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_focus_war_path_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_focus_war_path_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_trc_fwp_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_trc_fwp_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_naval_multi_phase_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_naval_multi_phase_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_diplomacy_peace_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_diplomacy_peace_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_nmp_dpc_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_nmp_dpc_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_save_resume_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_save_resume_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_play_session_primary_command_product.py ]]; then
  python3 tools/map_generation/tests/test_play_session_primary_command_product.py
fi
if [[ -f tools/map_generation/tests/test_sprint_srp_psc_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_srp_psc_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_sprint_occ_pc_cj_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_occ_pc_cj_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_sprint_baa_we_mp_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_baa_we_mp_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_sprint_amb_rq_fp_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_amb_rq_fp_g0_routing.py
fi

if [[ -f tools/map_generation/tests/test_sprint_fa_wga_ic_g0_routing.py ]]; then
  python3 tools/map_generation/tests/test_sprint_fa_wga_ic_g0_routing.py
fi
