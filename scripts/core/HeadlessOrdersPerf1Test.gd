extends SceneTree

## ORDERS-PERF-1. Cold Orders first-open budget, warm reopen, Close/Esc,
## map-select / apply_supply rebuild, depth-catalogue lazy groups (D6),
## frozen apply-id reachability, DesignManager/MapManager cache invalidation.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessOrdersPerf1Test.gd

const PLAYER_TAG := "GER"
const FOREIGN_TAG := "FRA"
const ADD_ID := "aaa_orders_perf1"
const CHANGE_DOMAIN := "naval"
const REMOVE_ID := "aaa_orders_perf1_rm"
const STALE_ID := "aaa_orders_perf1_sl"

const BUDGET_COLD_MS := 3000
const BUDGET_WARM_MS := 500
const BUDGET_CLOSE_MS := 1000
const BUDGET_SELECT_MS := 500
const BUDGET_APPLY_MS := 500
const BUDGET_DEPTH_MS := 1500
const WD_SLACK_MS := 250

## Frozen unfixed-tree apply-button + DAY_PACKAGE_ACTION_IDS union (9ccc83ee OCP).
## Unique `_add_apply_button` literals = 1381; DAY_PACKAGE_ACTION_IDS = 1127; union below.
const SNAPSHOT_ACTION_ID_COUNT := 1451
const SNAPSHOT_ACTION_IDS: PackedStringArray = [
	"advanced_deferred_campaign_close_day", "agenda_actions_day", "agenda_pick_day", "agenda_pulse_ops_day",
	"agent_ai_board_day", "agent_ai_campaign_depth_day", "agent_auto_day", "agent_campaign_day",
	"agent_campaign_depth_day", "agent_campaign_live_day", "agent_campaign_ops_day", "agent_campaign_primary_command_product",
	"agent_campaign_product", "agent_coverage_day", "agent_coverage_joint_day", "agent_dispatch_mutation_day",
	"agent_dispatch_ops_day", "agent_escalation_day", "agent_escalation_ops_day", "agent_hh_close_day",
	"agent_hh_joint_day", "agent_intel_ops_day", "agent_mission_board_primary_command_live", "agent_mission_board_primary_command_product",
	"agent_mission_campaign_day", "agent_mission_ops_day", "agent_mission_path_day", "agent_missions_day",
	"agent_mut_log_day", "agent_order_day", "agent_primary_board_surface", "agent_primary_close",
	"agent_primary_counter_intel", "agent_primary_dispatch", "agent_primary_resolve", "agent_product_board",
	"agent_product_counterplay", "agent_product_dispatch", "agent_response_day", "agent_response_depth_day",
	"ai_difficulty_primary_command_product", "air_convoy_campaign_close_day", "air_convoy_order_close_day", "air_domain_close_day",
	"air_forecast_day", "air_forecast_ops_day", "air_forecast_planning_depth_day", "air_front_close_day",
	"air_front_readiness_day", "air_front_readiness_depth_day", "air_land_campaign_day", "air_land_campaign_depth_day",
	"air_land_joint_day", "air_land_joint_depth_day", "air_land_joint_ops_day", "air_land_order_day",
	"air_land_stage_mutation_day", "air_multi_phase_primary_command_product", "air_multi_phase_theater_close_day", "air_multi_phase_theater_product",
	"air_ops_air_land", "air_ops_campaign_product", "air_ops_sortie", "air_ops_sortie_day",
	"air_ops_sortie_depth_day", "air_ops_weather_gate", "air_sortie_depth_day", "air_sortie_front_ops_day",
	"air_sortie_ready_day", "air_sortie_weather_gate_day", "air_sortie_wx_day", "air_theater_cas_gate",
	"air_theater_cas_gate_day", "air_theater_interdiction", "air_theater_interdiction_day", "air_theater_primary_command_product",
	"air_theater_recon", "air_theater_recon_day", "alliance_board_day", "alliance_coalition_day",
	"alliance_guarantee_day", "alliance_guarantee_network_close_day", "append_log_day", "apply_agent_campaign_product",
	"apply_agent_campaign_sequence", "apply_agent_dispatch", "apply_agent_mission_board_primary_command_live", "apply_agent_primary_board_surface",
	"apply_agent_primary_close", "apply_agent_primary_counter_intel", "apply_agent_primary_dispatch", "apply_agent_primary_resolve",
	"apply_agent_product_board", "apply_agent_product_counterplay", "apply_agent_product_dispatch", "apply_air_multi_phase_theater_close_day",
	"apply_air_multi_phase_theater_product", "apply_air_ops_air_land", "apply_air_ops_sortie", "apply_air_ops_weather_gate",
	"apply_air_theater_cas_gate", "apply_air_theater_interdiction", "apply_air_theater_recon", "apply_alliance_guarantee",
	"apply_assault", "apply_assault_card_day", "apply_audit_live_day", "apply_audit_ops_day",
	"apply_audit_session_day", "apply_autosave_session_ops_day", "apply_balance_combat_supply_close_day", "apply_balance_combat_supply_product",
	"apply_balance_estimate_board", "apply_balance_live_sample", "apply_balance_variance_close", "apply_battle_aar_close_live",
	"apply_battle_aar_persist_live", "apply_campaign_ai_month_board", "apply_campaign_ai_multi_month_close_day", "apply_campaign_ai_multi_month_product",
	"apply_campaign_ai_theater_execute", "apply_campaign_ai_weekly_plan", "apply_combat_agent_joint_close_day", "apply_combat_ops_close",
	"apply_command_journal_close_live", "apply_command_journal_enqueue_live", "apply_command_journal_flush_live", "apply_command_journal_seed_live",
	"apply_command_journal_verify_live", "apply_convoy_escort_ops_day", "apply_convoy_sealane_close_day", "apply_convoy_sealane_joint_day",
	"apply_counterplay", "apply_designer_industry_close_day", "apply_designer_module_board", "apply_designer_module_editor_product",
	"apply_designer_multi_domain_campaign_close_day", "apply_designer_multi_domain_campaign_product", "apply_designer_stats_field_product", "apply_designer_suite_catalog",
	"apply_designer_suite_pick", "apply_designer_suite_product", "apply_designer_suite_seed", "apply_diplomacy_peace_board",
	"apply_diplomacy_peace_campaign_product", "apply_diplomacy_peace_close_day", "apply_diplomacy_peace_leverage", "apply_diplomacy_peace_settle",
	"apply_faction_personality_ai_close_day", "apply_faction_personality_ai_product", "apply_fleet_autonomy_close", "apply_fleet_autonomy_follow",
	"apply_fleet_autonomy_posture", "apply_fleet_autonomy_primary_command_live", "apply_fleet_autonomy_station", "apply_fleet_day_follow_through",
	"apply_fleet_day_posture", "apply_fleet_day_station_escort", "apply_fleet_multi_day_autonomy_product", "apply_fleet_multi_day_sequence",
	"apply_focus", "apply_focus_tree_catalog", "apply_focus_tree_commit", "apply_focus_tree_content_close_day",
	"apply_focus_tree_content_product", "apply_focus_tree_path", "apply_focus_war_commit", "apply_focus_war_path_close_day",
	"apply_focus_war_path_product", "apply_focus_war_path_step", "apply_focus_war_pick", "apply_front_continuity_assault",
	"apply_front_continuity_campaign_close_day", "apply_front_continuity_campaign_product", "apply_front_continuity_combat", "apply_front_continuity_sustain",
	"apply_grand_strategy_cycle_close_day", "apply_grand_strategy_cycle_product", "apply_gs_cycle_execute", "apply_gs_cycle_rank",
	"apply_gs_cycle_scan", "apply_hh_agenda_close_live", "apply_hh_commit", "apply_hh_month_brief",
	"apply_hh_month_trail_board", "apply_hh_multi_month_agenda_product", "apply_hh_multi_month_sequence", "apply_historical_oob_catalog",
	"apply_historical_oob_content_close_day", "apply_historical_oob_content_product", "apply_historical_oob_equip", "apply_historical_oob_seed",
	"apply_inspector_decision_product", "apply_inspector_product_apply", "apply_inspector_product_collapse", "apply_inspector_product_primary",
	"apply_inspector_surface_close_day", "apply_intel_cell_ops", "apply_intel_counter_sweep", "apply_intel_network_counterintel",
	"apply_intel_network_counterplay", "apply_intel_network_coverage", "apply_intelligence_network_close_day", "apply_intelligence_network_product",
	"apply_leader_hq_board", "apply_leader_multi_station", "apply_leader_theater_command_close_day", "apply_leader_theater_command_product",
	"apply_leader_theater_ops", "apply_logistics_supply_close_day", "apply_logistics_supply_readiness", "apply_logistics_supply_route",
	"apply_logistics_supply_sustain", "apply_logistics_supply_theater_product", "apply_manpower_cohort_board", "apply_manpower_cohort_mobilize",
	"apply_manpower_cohort_reserve_close_day", "apply_manpower_laws_training_product", "apply_manpower_training_tick_live", "apply_map_perf_budget_30_live",
	"apply_map_perf_budget_60_live", "apply_map_perf_measured_close_live", "apply_map_perf_sample_frames_live", "apply_medium_honesty_factory_risk_day",
	"apply_medium_honesty_prove_100d", "apply_medium_honesty_prove_60d", "apply_medium_tank_oob_product", "apply_medium_tank_production_honesty_close_day",
	"apply_medium_tank_production_honesty_product", "apply_multi_faction_strategic_ai_product", "apply_multi_front_campaign_ai_close_day", "apply_multi_front_campaign_ai_product",
	"apply_multi_front_execute", "apply_multi_front_plan", "apply_multi_front_weekly", "apply_multi_phase_combat_product",
	"apply_multi_phase_estimate_day", "apply_naval_asw_escort", "apply_naval_carrier_strike", "apply_naval_multi_phase_campaign_product",
	"apply_naval_multi_phase_close_day", "apply_naval_phase_escort", "apply_naval_phase_posture", "apply_naval_phase_strike",
	"apply_naval_search_patrol", "apply_naval_search_strike_close_day", "apply_naval_search_strike_product", "apply_occupation_primary_close",
	"apply_occupation_primary_command_live", "apply_occupation_primary_garrison", "apply_occupation_primary_law", "apply_occupation_primary_mapmode",
	"apply_occupation_primary_rc_pulse", "apply_oob_horizon_100d", "apply_oob_horizon_60d", "apply_peace_conference_primary_command_live",
	"apply_peace_primary_cede", "apply_peace_primary_claim", "apply_peace_primary_close", "apply_peace_primary_open",
	"apply_peace_primary_puppet", "apply_personality_board", "apply_personality_drive", "apply_personality_event",
	"apply_play_session_brief", "apply_play_session_campaign_close_day", "apply_play_session_campaign_product", "apply_play_session_execute",
	"apply_play_session_resolve", "apply_product_ux_command_polish_product", "apply_product_ux_compact_board", "apply_product_ux_hotkeys",
	"apply_product_ux_polish_close_day", "apply_product_ux_top_chips", "apply_production", "apply_queue_agent_live_day",
	"apply_queue_audit_day", "apply_queue_combat_live_day", "apply_queue_focus_live_day", "apply_queue_honesty_joint_day",
	"apply_queue_live_audit", "apply_queue_live_combat", "apply_queue_live_managers_close_day", "apply_queue_live_managers_product",
	"apply_queue_live_production", "apply_queue_production_live_day", "apply_queue_six_leaf_joint_day", "apply_queue_station_live_day",
	"apply_queue_supply_live_day", "apply_research_primary_advance_month", "apply_research_primary_close", "apply_research_primary_enqueue_branch",
	"apply_research_primary_gate_check", "apply_research_primary_open_queue", "apply_research_queue_primary_command_live", "apply_save_browser_campaign_product",
	"apply_save_browser_checkpoint", "apply_save_browser_resume", "apply_save_resume_campaign_close_day", "apply_save_resume_campaign_product",
	"apply_save_resume_checkpoint", "apply_save_resume_resume", "apply_save_resume_save", "apply_save_session_close_day",
	"apply_sealane_health_ops_day", "apply_station", "apply_strategic_ai_campaign_close_day", "apply_strategic_ai_execute",
	"apply_strategic_ai_rank", "apply_strategic_ai_scan", "apply_strategic_war_goal_close_day", "apply_strategic_war_goal_product",
	"apply_stream_alpha_combat", "apply_stream_alpha_hh", "apply_stream_alpha_oob", "apply_stream_alpha_primary_command_live",
	"apply_stream_alpha_save", "apply_supply", "apply_tech_research_campaign_product", "apply_tech_research_catalog",
	"apply_tech_research_close_day", "apply_tech_research_field", "apply_tech_research_priority", "apply_trade_route_ops_day",
	"apply_tutorial_first_session_close_day", "apply_tutorial_first_session_product", "apply_tutorial_session_brief", "apply_tutorial_session_checkpoint",
	"apply_tutorial_session_guide", "apply_war_economy_primary_board", "apply_war_economy_primary_close", "apply_war_economy_primary_convert_to_civ",
	"apply_war_economy_primary_convert_to_war", "apply_war_economy_primary_stockpile_check", "apply_war_goal_board", "apply_war_goal_execute",
	"apply_war_goal_justify", "apply_weather_crisis_campaign_close_day", "apply_weather_crisis_campaign_product", "apply_weather_crisis_forecast",
	"apply_weather_crisis_gate_multi", "apply_weather_crisis_sustain", "apply_weather_theater_crisis", "apply_weather_theater_gate",
	"apply_weather_theater_ops_close_day", "apply_weather_theater_ops_product", "apply_weather_theater_pressure", "apply_world_class_campaign_close_day",
	"apply_world_class_campaign_command_product", "apply_world_class_execute", "apply_world_class_rank", "apply_world_class_scan",
	"assault_card_day", "assault_choke_agent_close_day", "assault_follow_on_day", "assault_follow_ops_day",
	"assault_front_ops_day", "assault_mut_fb_day", "assault_rank_card_day", "assault_rank_day",
	"assault_rank_inspect_day", "assault_rank_ops_day", "assault_readiness_day", "assault_ready_ops_day",
	"assault_ready_surface_day", "assault_stage_mutation_day", "autosave_session_depth_day", "autosave_session_ops_day",
	"autosave_session_primary_command_product", "balance_combat_supply_close_day", "balance_combat_supply_primary_command_product", "balance_combat_supply_product",
	"balance_estimate_board", "balance_estimate_board_day", "balance_live_sample", "balance_live_sample_day",
	"balance_variance_close", "balance_variance_close_day", "basing_choke_ops_day", "basing_fleet_sustain_day",
	"basing_fuel_day", "basing_fuel_loop_day", "basing_fuel_ops_day", "basing_logistics_day",
	"basing_logistics_ops_day", "basing_mission_day", "basing_rates_day", "basing_repair_day",
	"basing_repair_depth_day", "basing_signals_day", "battle_aar_primary_command_product", "best_assault_day",
	"best_assault_live_day", "best_station_day", "best_station_live_day", "campaign_ai_month_board",
	"campaign_ai_month_board_day", "campaign_ai_multi_month_close_day", "campaign_ai_multi_month_primary_command_product", "campaign_ai_multi_month_product",
	"campaign_ai_theater_execute", "campaign_ai_theater_execute_day", "campaign_ai_weekly_plan", "campaign_ai_weekly_plan_day",
	"campaign_alpha_apply_recommended", "campaign_alpha_dead_audit", "campaign_alpha_primary_board", "campaign_alpha_primary_strip_product",
	"campaign_alpha_recommend_next", "campaign_continuity_day", "campaign_crisis_ops_day", "campaign_day_chain_day",
	"campaign_decision_day", "campaign_decision_session_day", "campaign_risk_day", "campaign_risk_live_day",
	"campaign_session_depth_day", "campaign_session_ops_day", "campaign_strip_day", "choke_basing_joint_day",
	"choke_control_ops_day", "choke_sea_close_day", "choke_sea_day", "choke_sea_wx_ops_day",
	"close_loop_day", "close_mutation_day", "coastal_fog_gate_day", "coastal_fog_ops_day",
	"coherence_delta_day", "coherence_intel_day", "cohesion_gate_day", "combat_agent_joint_close_day",
	"combat_ai_phase_depth_day", "combat_air_naval_day", "combat_campaign_day", "combat_campaign_ops_day",
	"combat_depth_strip_day", "combat_engine_depth_primary_command_product", "combat_inspect_stack_day", "combat_intel_estimate_primary_command_product",
	"combat_morale_day", "combat_ops_close", "combat_ops_day", "combat_order_day",
	"combat_order_ops_day", "combat_order_surface_day", "combat_phase_close_day", "combat_phase_ops_day",
	"combat_phase_strip_day", "combat_production_depth_primary_command_product", "combat_production_partial_primary_command_product", "combat_surface_stack_day",
	"combat_urgency_ops_day", "combat_weather_ops_day", "combat_wx_mult_day", "combat_wx_ops_day",
	"command_gate_day", "command_journal_primary_command_product", "command_log_day", "construction_ops_day",
	"convoy_basing_joint_day", "convoy_economy_joint_day", "convoy_escort_campaign_depth_day", "convoy_escort_day",
	"convoy_escort_depth_day", "convoy_escort_ops_day", "convoy_package_day", "convoy_sealane_close_day",
	"convoy_sealane_joint_day", "convoy_sealane_primary_command_product", "convoy_sustain_ops_day", "convoy_trade_joint_day",
	"convoy_wx_ops_day", "convoy_wx_window_day", "counter_ops_board_ops_day", "counter_ops_day",
	"counterintel_board_ops_day", "counterplay_campaign_day", "coverage_ops_day", "daily_agent_auto_day",
	"daily_agent_plan_day", "daily_apply_ops_day", "daily_auto_depth_day", "daily_auto_ops_day",
	"daily_combat_auto_day", "daily_combat_plan_day", "daily_command_ops_day", "daily_fleet_auto_day",
	"daily_fleet_plan_day", "daily_prod_auto_live_day", "daily_prod_plan_day", "daily_supply_auto_day",
	"daily_supply_ops_day", "daily_supply_plan_day", "daily_theater_sustain_day", "daily_theater_tick_day",
	"day_audit_day", "day_budget_apply_day", "day_budget_day", "day_ops_integrated",
	"day_results_flair_day", "daylight_combat_day", "daylight_wx_ops_day", "decision_strip_depth_day",
	"decision_strip_ops_day", "depot_capacity_day", "depot_economy_ops_day", "depot_logistics_day",
	"depot_prod_stack_day", "depot_route_ops_day", "depot_weather_day", "depot_wx_live_day",
	"designer_ai_industry_joint_day", "designer_catalog_all_domains", "designer_catalog_all_domains_day", "designer_catalog_depth_day",
	"designer_depth_primary_command_product", "designer_domain_advanced_day", "designer_domain_air", "designer_domain_balance_day",
	"designer_domain_catalog_day", "designer_domain_land", "designer_domain_live_catalog", "designer_domain_live_close_day",
	"designer_domain_live_pick", "designer_domain_live_product", "designer_domain_live_seed", "designer_domain_naval",
	"designer_domain_pick_day", "designer_domain_seed_day", "designer_domain_space", "designer_equip_campaign_close",
	"designer_equip_campaign_close_day", "designer_field_seed", "designer_field_seed_day", "designer_freeze_design",
	"designer_freeze_design_day", "designer_industry_close_day", "designer_module_board", "designer_module_board_day",
	"designer_module_edit", "designer_module_edit_day", "designer_module_editor_close_day", "designer_module_editor_product",
	"designer_multi_domain_campaign_close_day", "designer_multi_domain_campaign_product", "designer_reliability_gate", "designer_reliability_gate_day",
	"designer_seed_advanced_day", "designer_seed_multi_domain", "designer_seed_multi_domain_day", "designer_seed_production_day",
	"designer_stats_board", "designer_stats_board_day", "designer_stats_field_close_day", "designer_stats_field_product",
	"designer_suite_catalog", "designer_suite_pick", "designer_suite_primary_command_product", "designer_suite_product",
	"designer_suite_seed", "diplomacy_agent_hh_joint_day", "diplomacy_board_advanced_day", "diplomacy_focus_peace_joint_day",
	"diplomacy_leverage_advanced_day", "diplomacy_naval_air_joint_day", "diplomacy_peace_board", "diplomacy_peace_campaign_product",
	"diplomacy_peace_close_day", "diplomacy_peace_leverage", "diplomacy_peace_primary_command_product", "diplomacy_peace_settle",
	"diplomacy_settle_advanced_day", "diplomacy_tech_campaign_close_day", "diplomacy_tech_joint_day", "diplomacy_trade_pressure_day",
	"domain_joint_ops_day", "dual_domain_mutate_day", "economy_civ_board", "economy_civ_board_day",
	"economy_stockpile_sustain", "economy_stockpile_sustain_day", "economy_war_convert", "economy_war_convert_day",
	"equip_horizon_depth_day", "equip_oob_close_day", "equip_stockpile_joint_day", "equipment_flow_symbols_primary_live",
	"escalation_ladder_ops_day", "execute_one_day", "execute_one_live_day", "execute_order_day",
	"execute_prod_live_day", "execution_gate_cont_day", "execution_gate_day", "faction_personality_ai_close_day",
	"faction_personality_primary_command_product", "factory_line_ops_day", "factory_oob_depth_day", "factory_retool_primary_command_product",
	"factory_risk_day", "factory_risk_live_day", "factory_risk_surge_day", "feedback_chain_day",
	"feedback_loop_ops_day", "fleet_ai_campaign_depth_day", "fleet_ai_ops_day", "fleet_ai_task_day",
	"fleet_autonomy", "fleet_autonomy_close_primary", "fleet_autonomy_day", "fleet_autonomy_follow_primary",
	"fleet_autonomy_posture_primary", "fleet_autonomy_primary_command_live", "fleet_autonomy_primary_command_product", "fleet_autonomy_station_primary",
	"fleet_campaign_day", "fleet_day_follow_through", "fleet_day_posture", "fleet_day_station_escort",
	"fleet_hh_combat_close_day", "fleet_multi_day", "fleet_multi_day_autonomy_product", "fleet_multi_day_primary_command_product",
	"fleet_multi_day_sequence", "fleet_multi_theater_ops_day", "fleet_order_day", "fleet_path_stack_day",
	"fleet_patrol_day", "fleet_patrol_strip_day", "fleet_posture_ops_day", "fleet_redeploy_close_day",
	"fleet_redeploy_day", "fleet_redeploy_ops_day", "fleet_station_mut_day", "fleet_station_mutation_day",
	"fleet_station_sustain_day", "fleet_task_group_day", "fleet_task_sustain_day", "fleet_theater_joint_day",
	"fleet_theater_posture_day", "fleet_wx_mission_day", "fleet_wx_ops_day", "fleet_wx_package_day",
	"fleet_wx_sustain_day", "focus_air_effort_joint_day", "focus_commit_execute_advanced_day", "focus_continuity_joint_day",
	"focus_industry_army_joint_day", "focus_intel_leader_close_day", "focus_joint_ops_day", "focus_mut_ops_day",
	"focus_mutation_day", "focus_naval_effort_advanced_day", "focus_order_day", "focus_order_path_day",
	"focus_path_ops_day", "focus_pick_board_advanced_day", "focus_pick_day", "focus_pick_depth_day",
	"focus_priority_ops_day", "focus_tree_catalog", "focus_tree_catalog_day", "focus_tree_commit",
	"focus_tree_commit_day", "focus_tree_content_close_day", "focus_tree_content_product", "focus_tree_path",
	"focus_tree_path_day", "focus_tree_primary_command_product", "focus_war_commit", "focus_war_path_advanced_day",
	"focus_war_path_close_day", "focus_war_path_day", "focus_war_path_depth_day", "focus_war_path_ops_day",
	"focus_war_path_primary_command_product", "focus_war_path_product", "focus_war_path_step", "focus_war_pick",
	"focus_wx_ops_day", "focus_wx_score_day", "fog_air_crisis_day", "follow_on_assault_ops_day",
	"follow_reinforce_close_day", "force_oob_close_day", "force_posture_day", "force_posture_depth_day",
	"force_readiness_day", "force_readiness_depth_day", "force_readiness_ops_day", "force_readiness_session_day",
	"force_ready_surface_day", "force_reinforce_joint_day", "force_supply_close_day", "force_supply_day",
	"force_supply_joint_day", "force_weather_focus_close_day", "formation_equip_depth_day", "formation_ready_depth_day",
	"formation_ready_ops_day", "formation_station_depth_day", "formation_station_ops_day", "foul_combat_ops_day",
	"front_assault_advanced_day", "front_combat_advanced_day", "front_continuity_assault", "front_continuity_campaign_close_day",
	"front_continuity_campaign_product", "front_continuity_combat", "front_continuity_primary_command_product", "front_continuity_sustain",
	"front_economy_joint_day", "front_logistics_joint_day", "front_supply_rank_day", "front_sustain_advanced_day",
	"front_theater_command_joint_day", "front_weather_joint_day", "full_game_campaign_close_day", "gpu_pan_zoom_day",
	"grand_strategy_cycle_close_day", "grand_strategy_cycle_primary_command_product", "grand_strategy_cycle_product", "ground_transition_day",
	"gs_cycle_execute", "gs_cycle_execute_day", "gs_cycle_rank", "gs_cycle_rank_day",
	"gs_cycle_scan", "gs_cycle_scan_day", "hh_agenda_actions_day", "hh_agenda_close",
	"hh_agenda_depth_joint_day", "hh_agenda_ops_day", "hh_agenda_package_day", "hh_agenda_pick_day",
	"hh_agenda_screen_day", "hh_auto_plan_day", "hh_campaign_day", "hh_commit_campaign_day",
	"hh_commit_order_day", "hh_counter_ops_day", "hh_counterplay_day", "hh_counterplay_depth_day",
	"hh_month_brief", "hh_month_quarterly_counter", "hh_month_trail_board", "hh_monthly_day",
	"hh_monthly_ops_day", "hh_multi_month_agenda_product", "hh_multi_month_primary_command_product", "hh_order_path_day",
	"hh_path_stack_day", "hh_player_path", "hh_quarterly_day", "hh_quarterly_ops_day",
	"hh_secondary_trail_day", "hh_trail_counter_day", "hh_trail_ops_day", "historical_oob_catalog",
	"historical_oob_catalog_day", "historical_oob_content_close_day", "historical_oob_content_product", "historical_oob_equip",
	"historical_oob_equip_day", "historical_oob_primary_command_product", "historical_oob_seed", "historical_oob_seed_day",
	"hoi_fullscreen_primary_command_product", "hoi_panel_primary_command_product", "hoi_screen_primary_command_product", "hotseat_session_primary_command_product",
	"incomplete_loop_close_day", "industry_close_loop_day", "industry_design_joint_day", "industry_economy_day",
	"industry_save_close_day", "industry_surge_day", "industry_surge_joint_day", "infra_invest_close_day",
	"infra_invest_ops_day", "infra_project_ops_day", "infra_site_joint_day", "insight_budget_ops_day",
	"insight_strip_depth_day", "inspector_campaign_ops_day", "inspector_decision_depth_day", "inspector_decision_primary_command_product",
	"inspector_decision_product", "inspector_infra_auto_close_day", "inspector_product_apply", "inspector_product_collapse",
	"inspector_product_primary", "inspector_surface_close_day", "integrity_gate_day", "intel_cell_coverage",
	"intel_cell_coverage_day", "intel_cell_network_close_day", "intel_cell_network_product", "intel_cell_ops",
	"intel_cell_ops_day", "intel_counter_close_day", "intel_counter_day", "intel_counter_depth_campaign_day",
	"intel_counter_depth_day", "intel_counter_ops_day", "intel_counter_primary_command_product", "intel_counter_sweep",
	"intel_counter_sweep_day", "intel_counterintel_advanced_day", "intel_counterplay_advanced_day", "intel_coverage_advanced_day",
	"intel_diplomacy_joint_day", "intel_network_counterintel", "intel_network_counterplay", "intel_network_coverage",
	"intel_network_primary_command_product", "intel_response_joint_day", "intel_session_joint_day", "intelligence_network_close_day",
	"intelligence_network_product", "investment_status_ops_day", "joint_campaign_day", "joint_command_day",
	"joint_command_ops_day", "joint_naval_combat_day", "joint_naval_land_day", "joint_ops_loop_day",
	"joint_theater_combat_day", "joint_timeline_day", "joint_timeline_inspect_day", "leader_assign_advanced_day",
	"leader_assign_depth_day", "leader_assign_ops_day", "leader_campaign_assign_day", "leader_campaign_day",
	"leader_command_assign", "leader_command_ops", "leader_command_ops_day", "leader_command_product",
	"leader_command_station", "leader_formation_close_day", "leader_formation_close_depth_day", "leader_formation_joint_day",
	"leader_formation_joint_depth_day", "leader_hq_board", "leader_hq_board_day", "leader_intel_joint_day",
	"leader_intel_theater_close_day", "leader_manpower_joint_day", "leader_multi_station", "leader_multi_station_day",
	"leader_occupation_joint_day", "leader_ops_advanced_day", "leader_station_advanced_day", "leader_station_day",
	"leader_theater_command_close_day", "leader_theater_command_product", "leader_theater_joint_day", "leader_theater_ops",
	"leader_theater_ops_day", "leader_theater_primary_command_product", "leader_weather_day", "leader_weather_depth_day",
	"line_continuity_depth_day", "live_apply_results_day", "live_mut_board_day", "load_slot_slot1",
	"log_strip_day", "logistics_day", "logistics_force_panel_close_day", "logistics_naval_joint_day",
	"logistics_readiness_advanced_day", "logistics_route_advanced_day", "logistics_supply_close_day", "logistics_supply_primary_command_product",
	"logistics_supply_readiness", "logistics_supply_route", "logistics_supply_sustain", "logistics_supply_theater_product",
	"logistics_sustain_advanced_day", "logistics_tech_industry_joint_day", "logistics_theater_close_day", "manpower_cohort_board",
	"manpower_cohort_board_day", "manpower_cohort_mobilize", "manpower_cohort_mobilize_day", "manpower_cohort_reserve",
	"manpower_cohort_reserve_close_day", "manpower_cohort_reserve_day", "manpower_cohort_reserve_product", "manpower_draft_advanced_day",
	"manpower_draft_board", "manpower_economy_joint_day", "manpower_field_advanced_day", "manpower_field_trained",
	"manpower_field_trained_day", "manpower_field_units", "manpower_front_joint_day", "manpower_law_board",
	"manpower_law_board_day", "manpower_law_extensive", "manpower_law_limited", "manpower_law_service_by_requirement",
	"manpower_law_volunteer", "manpower_laws_primary_command_product", "manpower_laws_training_close_day", "manpower_laws_training_product",
	"manpower_reinforce_advanced_day", "manpower_reinforce_lines", "manpower_reinforcement_close_day", "manpower_reinforcement_product",
	"manpower_reserve_active", "manpower_reserve_ready", "manpower_reserve_strategic", "manpower_train_pipeline",
	"manpower_train_pipeline_day", "map_effect_day", "map_effect_ops_day", "map_effect_resolve_day",
	"map_perf_measured_primary_command_product", "map_visible_day", "medium_equip_horizon_ops_day", "medium_equip_ops_day",
	"medium_honesty_100d_day", "medium_honesty_60d_day", "medium_honesty_80d_day", "medium_honesty_economy_joint_day",
	"medium_honesty_factory_risk_day", "medium_honesty_manpower_joint_day", "medium_honesty_prove_100d", "medium_honesty_prove_60d",
	"medium_honesty_prove_80d", "medium_honesty_readiness_joint_day", "medium_honesty_stockpile_day", "medium_honesty_unit_stats_day",
	"medium_horizon_plan_day", "medium_tank_oob_product", "medium_tank_production_honesty_close_day", "medium_tank_production_honesty_product",
	"morale_wx_day", "morale_wx_ops_day", "move_ops_day", "move_path_campaign_day",
	"move_path_day", "move_path_ops_day", "multi_day_theater_depth_day", "multi_domain_auto_ops_day",
	"multi_domain_ops_day", "multi_domain_strip_day", "multi_faction_ai_primary_command_product", "multi_faction_diplo_tech_day",
	"multi_faction_strategic_ai_product", "multi_front_assault_day", "multi_front_campaign_ai_close_day", "multi_front_campaign_ai_product",
	"multi_front_execute", "multi_front_execute_day", "multi_front_plan", "multi_front_plan_day",
	"multi_front_primary_command_product", "multi_front_rank_ops_day", "multi_front_supply_depth_day", "multi_front_supply_ops_day",
	"multi_front_surface_day", "multi_front_weekly", "multi_front_weekly_day", "multi_party_peace_board",
	"multi_party_peace_board_day", "multi_party_peace_campaign_close_day", "multi_party_peace_conference_product", "multi_party_peace_settle",
	"multi_party_peace_settle_day", "multi_party_peace_wargoals", "multi_party_peace_wargoals_day", "multi_phase_combat_day",
	"multi_phase_combat_product", "multi_phase_combat_ui_day", "multi_phase_est_ops_day", "multi_phase_estimate_day",
	"multi_phase_estimate_depth_day", "multi_phase_joint_day", "multi_province_campaign_day", "multi_province_command_day",
	"multi_province_live_day", "multi_province_ops_day", "multi_province_plan_day", "multi_province_rank_depth_day",
	"mut_close_stack_day", "mutation_feedback_day", "mutation_feedback_ops_day", "mutation_gate_apply_day",
	"mutation_gate_day", "mutation_result_day", "mutation_strip_day", "n3_preflight_primary_command_product",
	"naval_air_joint_advanced_day", "naval_asw_escort", "naval_asw_escort_day", "naval_basing_close_day",
	"naval_basing_day", "naval_basing_sustain_day", "naval_campaign_day", "naval_carrier_strike",
	"naval_carrier_strike_day", "naval_escort_phase_advanced_day", "naval_fleet_autonomy_joint_day", "naval_fleet_fuel_advanced_day",
	"naval_interdiction_day", "naval_logistics_depth_day", "naval_multi_phase_campaign_product", "naval_multi_phase_close_day",
	"naval_multi_phase_day", "naval_multi_phase_primary_command_product", "naval_ops_close", "naval_order_day",
	"naval_order_ops_day", "naval_phase_escort", "naval_phase_ops_day", "naval_phase_posture",
	"naval_phase_strike", "naval_posture_advanced_day", "naval_sealane_close_day", "naval_search_patrol",
	"naval_search_patrol_day", "naval_search_strike_close_day", "naval_search_strike_primary_command_product", "naval_search_strike_product",
	"naval_skim_ops_day", "naval_strike_phase_advanced_day", "naval_task_mut_day", "naval_task_mutation_day",
	"next_day_feedback_day", "next_day_feedback_depth_day", "next_day_feedback_session_day", "occupation_control_advanced_day",
	"occupation_control_board", "occupation_control_close_day", "occupation_control_garrison", "occupation_control_integrate",
	"occupation_control_product", "occupation_economy_joint_day", "occupation_front_joint_day", "occupation_garrison_advanced_day",
	"occupation_garrison_heavy", "occupation_garrison_light", "occupation_garrison_standard", "occupation_integrate_advanced_day",
	"occupation_manpower_leader_close_day", "occupation_policy_harsh", "occupation_policy_lenient", "occupation_policy_moderate",
	"occupation_primary_close", "occupation_primary_command_live", "occupation_primary_command_product", "occupation_primary_garrison",
	"occupation_primary_law", "occupation_primary_mapmode", "occupation_primary_rc_pulse", "occupation_resistance_board",
	"occupation_resistance_board_day", "occupation_resistance_close_day", "occupation_resistance_compliance_product", "occupation_resistance_policy",
	"occupation_resistance_policy_day", "occupation_resistance_tick", "occupation_resistance_tick_day", "occupation_revolt_board",
	"occupation_revolt_board_day", "occupation_revolt_garrison", "occupation_revolt_garrison_close_day", "occupation_revolt_garrison_day",
	"occupation_revolt_garrison_product", "occupation_revolt_network_close_day", "occupation_revolt_suppress", "occupation_revolt_suppress_day",
	"oob_assign_ops_day", "oob_equip_continuity_day", "oob_factory_day", "oob_factory_ops_day",
	"oob_fleet_hh_close_day", "oob_horizon_100d", "oob_horizon_60d", "oob_horizon_80d",
	"oob_horizon_joint_day", "oob_leader_ops_day", "oob_line_continuity_day", "ops_dash_continuity_day",
	"ops_dashboard_day", "order_effect_joint_day", "order_execute_day", "order_execute_depth_day",
	"order_execute_session_day", "order_panel_ops_day", "order_panel_session_day", "order_panel_ux_day",
	"order_queue_day", "order_surface_ops_day", "pack_n_content_primary_command_product", "pack_n_era_primary_command_product",
	"pack_n_events_primary_command_product", "pack_n_narrative_primary_command_product", "panel_sections_ops_day", "panel_surface_ops_day",
	"peace_conference_board", "peace_conference_board_day", "peace_conference_campaign_close_day", "peace_conference_demands",
	"peace_conference_demands_day", "peace_conference_primary_command_live", "peace_conference_primary_command_product", "peace_conference_settle",
	"peace_conference_settle_day", "peace_conference_settlement_product", "peace_demand_annex", "peace_demand_occupation_zone",
	"peace_demand_puppet", "peace_demand_reparations", "peace_primary_cede", "peace_primary_claim",
	"peace_primary_close", "peace_primary_open", "peace_primary_puppet", "personality_board_day",
	"personality_drive", "personality_drive_day", "personality_event_day", "phase_approach",
	"phase_disengage", "phase_engage", "phase_estimate_ribbon_day", "phase_product_ops_day",
	"phase_ribbon_day", "phase_ribbon_inspect_day", "phase_ribbon_ops_day", "phase_timeline_stack_day",
	"play_session_advanced_joint_day", "play_session_brief", "play_session_campaign_close_day", "play_session_campaign_product",
	"play_session_execute", "play_session_primary_command_product", "play_session_resolve", "player_surface_day",
	"player_surface_ops_day", "player_surface_session_day", "port_fuel_depth_day", "prod_air_focus_close_day",
	"prod_campaign_ops_day", "prod_campaign_risk_day", "prod_factory_risk_ops_day", "prod_mut_apply_day",
	"prod_weather_crisis_day", "prod_wx_ops_day", "prod_wx_stack_day", "product_chip_ops_day",
	"product_ux_chips_day", "product_ux_command_polish_product", "product_ux_compact_board", "product_ux_compact_day",
	"product_ux_hotkeys", "product_ux_hotkeys_day", "product_ux_polish_close_day", "product_ux_primary_command_product",
	"product_ux_top_chips", "production_auto_day", "production_force_ops_day", "production_honesty_primary_command_product",
	"production_line_bootstrap_day", "production_oob_close_day", "production_oob_depth_day", "production_order_day",
	"production_priority_day", "production_priority_depth_day", "production_priority_ops_day", "production_risk_alert_day",
	"production_risk_day", "production_surge_close_day", "production_surge_day", "province_decision_joint_day",
	"q1_checklist_primary_command_product", "q1_rc_checklist_primary_command_product", "q1_validator_primary_command_product", "readiness_board_ops_day",
	"redeploy_route_day", "redeploy_route_ops_day", "reinforce_step_ops_day", "reinforce_stockpile_depth_day",
	"reinforce_story_primary_live", "reinforced_assault_day", "reinforced_combat_ops_day", "research_primary_advance_month",
	"research_primary_close", "research_primary_enqueue_branch", "research_primary_gate_check", "research_primary_open_queue",
	"research_queue_primary_command_live", "research_queue_primary_command_product", "resource_economy_depth_primary_command_product", "resource_harvest_primary_command_product",
	"resource_open_items_primary_command_product", "resource_production_primary_command_product", "result_feedback_day", "revolt_cascade_risk_day",
	"revolt_network_map_day", "revolt_network_suppress_day", "save_audit_depth_day", "save_audit_ops_day",
	"save_browser_campaign_product", "save_browser_checkpoint", "save_browser_live_day", "save_browser_resume",
	"save_leader_trade_close_day", "save_prod_combat_close_day", "save_resume_campaign_close_day", "save_resume_campaign_product",
	"save_resume_checkpoint", "save_resume_checkpoint_day", "save_resume_depth_day", "save_resume_ops_day",
	"save_resume_primary_command_product", "save_resume_resume", "save_resume_resume_day", "save_resume_save",
	"save_resume_save_day", "save_session_ai_joint_day", "save_session_close_day", "save_session_close_depth_day",
	"save_slot:quicksave", "save_slot_browser_day", "save_slot_depth_day", "save_slot_integrity_ops_day",
	"save_slot_list_day", "save_slot_quicksave", "save_slot_slot1", "save_slot_surface_day",
	"sea_zone_control_ops_day", "sea_zone_mod_ops_day", "sea_zone_trade_day", "sealane_economy_ops_day",
	"sealane_health_day", "sealane_health_depth_day", "sealane_health_ops_day", "sealane_joint_ops_day",
	"sealane_logistics_ops_day", "session_checkpoint_depth_day", "session_checkpoint_ops_day", "session_diplomacy_tech_joint_day",
	"special_site_ops_day", "stockpile_economy_depth_day", "stockpile_growth_ops_day", "stockpile_line_ops_day",
	"stockpile_surge_ops_day", "strategic_ai_budget_depth_day", "strategic_ai_campaign_close_day", "strategic_ai_daily_apply",
	"strategic_ai_daily_board", "strategic_ai_daily_budget", "strategic_ai_daily_campaign_product", "strategic_ai_daily_joint_day",
	"strategic_ai_doctrine_depth_day", "strategic_ai_domain_weight_day", "strategic_ai_execute", "strategic_ai_multi_day_advanced_day",
	"strategic_ai_player_skip_day", "strategic_ai_rank", "strategic_ai_scan", "strategic_ai_urgency_board_day",
	"strategic_continuity_day", "strategic_continuity_depth_day", "strategic_continuity_ops_day", "strategic_strip_depth_day",
	"strategic_strip_ops_day", "strategic_war_goal_close_day", "strategic_war_goal_primary_command_product", "strategic_war_goal_product",
	"stream_alpha_combat_primary", "stream_alpha_hh_primary", "stream_alpha_oob_primary", "stream_alpha_primary_command_live",
	"stream_alpha_primary_command_product", "stream_alpha_primary_packs_product", "stream_alpha_save_primary", "supply_campaign_day",
	"supply_economy_ops_day", "supply_mut_apply_day", "supply_mut_fb_day", "supply_order_day",
	"supply_route_mutation_day", "supply_route_ops_day", "surface_refresh_ops_day", "task_group_day",
	"task_group_posture_ops_day", "tech_ai_research_joint_day", "tech_branch_air", "tech_branch_armor",
	"tech_branch_industry", "tech_branch_infantry", "tech_catalog_advanced_day", "tech_designer_joint_day",
	"tech_field_advanced_day", "tech_industry_focus_joint_day", "tech_oob_fielding_joint_day", "tech_priority_advanced_day",
	"tech_research_campaign_product", "tech_research_catalog", "tech_research_close_day", "tech_research_field",
	"tech_research_primary_command_product", "tech_research_priority", "tech_tree_branches", "tech_tree_branches_day",
	"tech_tree_branching_close_day", "tech_tree_branching_product", "tech_tree_field", "tech_tree_field_day",
	"tech_tree_path", "tech_tree_path_day", "theater_ai_command_joint_day", "theater_ai_session_joint_day",
	"theater_auto_campaign_day", "theater_auto_joint_day", "theater_auto_tick_day", "theater_brief_day",
	"theater_brief_ops_day", "theater_campaign_close_day", "theater_campaign_continuity_day", "theater_campaign_day",
	"theater_campaign_depth_close_day", "theater_command_execute", "theater_command_product", "theater_command_rank",
	"theater_command_scan", "theater_continuity_joint_day", "theater_daily_depth_day", "theater_day_cabinet",
	"theater_hh_commit_day", "theater_hh_path_day", "theater_mutation_day", "theater_naval_inspector_close_day",
	"theater_naval_session_close_day", "theater_order_board_day", "theater_order_day", "theater_prod_auto_day",
	"theater_prod_live_day", "theater_readiness_day", "theater_readiness_ops_day", "theater_report_day",
	"theater_session_ops_day", "theater_tick_ops_day", "tooltip_chip_ops_day", "tooltip_flair_ops_day",
	"trade_chain_day", "trade_chain_ops_day", "trade_power_intel_primary_command_product", "trade_pressure_depth_day",
	"trade_pressure_ops_day", "trade_relations_primary_command_product", "trade_route_ops_day", "trade_sealane_joint_day",
	"trail_counterplay_ops_day", "trail_intel_ops_day", "tutorial_first_session_close_day", "tutorial_first_session_primary_command_product",
	"tutorial_first_session_product", "tutorial_session_brief", "tutorial_session_brief_day", "tutorial_session_checkpoint",
	"tutorial_session_checkpoint_day", "tutorial_session_guide", "tutorial_session_guide_day", "war_cabinet_day",
	"war_cabinet_ops_day", "war_cabinet_pulse_ops_day", "war_economy_allocate", "war_economy_allocate_advanced_day",
	"war_economy_board", "war_economy_board_advanced_day", "war_economy_close_day", "war_economy_close_depth_day",
	"war_economy_conversion_close_day", "war_economy_conversion_product", "war_economy_day", "war_economy_logistics_joint_day",
	"war_economy_mobilization_close_day", "war_economy_mobilization_product", "war_economy_ops_day", "war_economy_primary_command_product",
	"war_economy_sustain", "war_economy_sustain_advanced_day", "war_economy_sustain_day", "war_economy_tech_joint_day",
	"war_goal_alliance_primary_command_product", "war_goal_board", "war_goal_board_day", "war_goal_execute",
	"war_goal_execute_day", "war_goal_justify", "war_goal_justify_day", "war_path_urgency_day",
	"war_path_urgency_depth_day", "war_path_urgency_ops_day", "wartime_trade_ops_day", "weather_campaign_joint_day",
	"weather_combat_brief_day", "weather_crisis_advanced_day", "weather_crisis_brief_day", "weather_crisis_campaign_close_day",
	"weather_crisis_campaign_product", "weather_crisis_close_day", "weather_crisis_day", "weather_crisis_depth_day",
	"weather_crisis_forecast", "weather_crisis_forecast_day", "weather_crisis_gate_multi", "weather_crisis_gate_multi_day",
	"weather_crisis_primary_command_product", "weather_crisis_sustain", "weather_crisis_sustain_day", "weather_economy_force_close_day",
	"weather_economy_intel_close_day", "weather_economy_joint_day", "weather_front_joint_day", "weather_gate_advanced_day",
	"weather_logistics_depth_day", "weather_move_depth_day", "weather_ops_close_day", "weather_ops_close_depth_day",
	"weather_pressure_advanced_day", "weather_pressure_depth_day", "weather_pressure_joint_day", "weather_pressure_ops_day",
	"weather_theater_crisis", "weather_theater_gate", "weather_theater_ops_close_day", "weather_theater_ops_product",
	"weather_theater_pressure", "weather_theater_primary_command_product", "world_class_air_naval_joint_day", "world_class_campaign_close_day",
	"world_class_campaign_command_product", "world_class_execute", "world_class_execute_advanced_day", "world_class_logistics_intel_joint_day",
	"world_class_primary_command_product", "world_class_rank", "world_class_rank_advanced_day", "world_class_scan",
	"world_class_scan_advanced_day", "world_class_session_ai_joint_day", "world_class_theater_command_joint_day",
]

var _failures: int = 0
var _wd_thread: Thread = null
var _wd_armed: bool = false
var _wd_fired: bool = false
var _wd_stop: bool = false
var _wd_deadline_msec: int = 0
var _wd_start_msec: int = 0
var _wd_label: String = ""
var _ocp: Node = null


func _init() -> void:
	call_deferred("_start")


func _flush_log() -> void:
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _progress(msg: String) -> void:
	print("  HeadlessOrdersPerf1Test: ", msg)
	_flush_log()


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessOrdersPerf1Test: ", msg)
	_flush_log()


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessOrdersPerf1Test: ", msg)
	_flush_log()


func _join_watchdog() -> void:
	_wd_armed = false
	_wd_stop = true
	if _wd_thread != null and _wd_thread.is_started():
		_wd_thread.wait_to_finish()
	_wd_thread = null


func _emit_result_and_die(ok: bool) -> void:
	print("HeadlessOrdersPerf1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessOrdersPerf1Test: RESULT=", "PASS" if ok else "FAIL")
	print("HeadlessOrdersPerf1Test: RESULT=%s failures=%d" % ["PASS" if ok else "FAIL", _failures])
	_flush_log()
	_join_watchdog()
	quit(0 if ok else 1)


func _watchdog_loop() -> void:
	while not _wd_stop:
		OS.delay_msec(50)
		if _wd_stop:
			break
		if not _wd_armed or _wd_fired:
			continue
		var now: int = Time.get_ticks_msec()
		if now <= _wd_deadline_msec:
			continue
		_wd_fired = true
		_wd_armed = false
		_wd_stop = true
		var waited: int = now - _wd_start_msec
		_failures += 1
		print("  [FAIL] HeadlessOrdersPerf1Test: %s: watchdog %dms (step or process_frame never returned)" % [_wd_label, waited])
		print("HeadlessOrdersPerf1Test: FAIL (failures=", _failures, ")")
		print("HeadlessOrdersPerf1Test: RESULT=FAIL")
		print("HeadlessOrdersPerf1Test: RESULT=FAIL failures=%d" % _failures)
		_flush_log()
		OS.kill(OS.get_process_id())
		return


func _arm_watchdog(budget_ms: int, label: String) -> void:
	_wd_label = label
	_wd_start_msec = Time.get_ticks_msec()
	_wd_deadline_msec = _wd_start_msec + budget_ms
	_wd_fired = false
	_wd_stop = false
	_wd_armed = true
	if _wd_thread == null:
		_wd_thread = Thread.new()
		_wd_thread.start(_watchdog_loop)


func _disarm_watchdog() -> void:
	_wd_armed = false


func _start() -> void:
	await _run()
	_emit_result_and_die(_failures == 0)


func _sl() -> Node:
	return root.get_node_or_null("SaveLoadManager")


func _tm() -> Node:
	return root.get_node_or_null("TimeManager")


func _dm() -> Node:
	return root.get_node_or_null("DesignManager")


func _mm() -> Node:
	return root.get_node_or_null("MapManager")


func _run() -> void:
	if not _setup_world():
		return
	await _test_a_cold_open()
	await _test_b_warm_reopen()
	await _test_c_close_and_esc()
	await _test_d_select_and_apply()
	await _test_e_depth_catalogue()
	_test_f_action_ids()
	_test_g_cache_invalidation()


func _setup_world() -> bool:
	var sl: Node = _sl()
	if sl == null:
		_fail("SaveLoadManager missing")
		return false
	var bytes: int = _write_heavy_probe(sl, "quicksave", 100, "1936-01-01", "orders-perf1-heavy")
	if bytes < 2500000:
		_fail("heavy probe too small (%d bytes); need mid-campaign ~2.6MB" % bytes)
		return false
	print("  HeadlessOrdersPerf1Test: heavy probe %d bytes" % bytes)
	_flush_log()
	var tm: Node = _tm()
	if tm != null:
		tm.current_year = 1936
		tm.current_month = 1
		tm.current_day = 16
		tm.total_days_elapsed = 15
		if tm.has_method("set_paused"):
			tm.call("set_paused", true)
	var lm: Node = root.get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", PLAYER_TAG)
	_progress("world: 16 Jan 1936 paused, player GER, heavy quicksave")
	return true


func _write_heavy_probe(sl: Node, slot: String, unix: int, game_date: String, marker: String) -> int:
	## Same mid-campaign-weight fixture (~2.6 MB) as HeadlessAutosave1Test._write_heavy_probe.
	if sl.has_method("_ensure_save_dir"):
		sl.call("_ensure_save_dir")
	var provinces: Array = []
	for i in range(800):
		provinces.append({
			"id": 710000 + i,
			"owner_tag": "GER",
			"controller_tag": "GER",
			"development_level": 4,
			"infrastructure": 6,
			"factories": 2,
			"name": "HeavyProbeProvince_%d" % i,
			"manpower": 12000 + i,
			"victory_points": 1,
		})
	var data: Dictionary = {
		"save_version": 2,
		"metadata": {
			"timestamp_unix": unix,
			"timestamp": "1936-01-01T00:00:00",
			"game_date": game_date,
			"last_played": "1936-01-01T00:00:00",
			"save_kind": str(sl.call("slot_kind", slot)),
			"session_locked": false,
			"player_tag": "GER",
			"marker": marker,
		},
		"land_war": {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}},
		"map": {"provinces": provinces},
	}
	var text: String = JSON.stringify(data)
	var want: int = 2626853
	if text.length() < want:
		data["pad"] = "x".repeat(want - text.length())
		text = JSON.stringify(data)
	var path: String = str(sl.call("get_save_path", slot))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("heavy probe write failed for %s" % slot)
		return 0
	f.store_string(text)
	f.close()
	return text.length()


func _refresh_done(ocp: Node) -> bool:
	if ocp == null or not is_instance_valid(ocp) or ocp.is_queued_for_deletion():
		return false
	var status: Variant = ocp.get("_status")
	if status is Label and str((status as Label).text).begins_with("Country"):
		return true
	return false


func _panel_is_closed(ocp: Node) -> bool:
	if ocp == null:
		return true
	if not is_instance_valid(ocp):
		return true
	if ocp.is_queued_for_deletion():
		return true
	if ocp is CanvasItem and not (ocp as CanvasItem).visible:
		return true
	return false


func _pump_frames_until(pred: Callable, budget_ms: int, label: String) -> bool:
	var t0: int = Time.get_ticks_msec()
	if pred.call():
		return true
	while Time.get_ticks_msec() - t0 <= budget_ms:
		var frame_start: int = Time.get_ticks_msec()
		_arm_watchdog(budget_ms + WD_SLACK_MS, label)
		await process_frame
		_disarm_watchdog()
		var frame_ms: int = Time.get_ticks_msec() - frame_start
		if frame_ms > budget_ms:
			_fail("%s: process_frame stalled %dms (budget %dms)" % [label, frame_ms, budget_ms])
			return false
		if pred.call():
			return true
	if pred.call():
		return true
	_fail("%s: still not done after %dms" % [label, Time.get_ticks_msec() - t0])
	return false


func _instantiate_live_ocp(node_name: String) -> Node:
	## LIVE path: same as TopInfoBar._on_orders_pressed, without eoa_skip_first_refresh.
	var packed: PackedScene = load("res://scenes/ui/OrderCommandPanel.tscn") as PackedScene
	if packed == null:
		return null
	var ocp: Node = packed.instantiate()
	ocp.name = node_name
	if "country_tag" in ocp:
		ocp.set("country_tag", PLAYER_TAG)
	return ocp


func _open_live_ocp(budget_ms: int, node_name: String, label: String) -> Node:
	var ocp: Node = _instantiate_live_ocp(node_name)
	if ocp == null:
		_fail("%s: OrderCommandPanel.tscn missing" % label)
		return null
	var t0: int = Time.get_ticks_msec()
	_progress("%s: before add_child" % label)
	_arm_watchdog(budget_ms + WD_SLACK_MS, "%s: add_child" % label)
	root.add_child(ocp)
	_disarm_watchdog()
	_progress("%s: after add_child" % label)
	var ok: bool = await _pump_frames_until(
		func() -> bool: return _refresh_done(ocp),
		budget_ms,
		"%s: first refresh" % label
	)
	var wall: int = Time.get_ticks_msec() - t0
	if not ok:
		return ocp
	if wall > budget_ms:
		_fail("%s: add_child→first refresh %dms (budget %dms)" % [label, wall, budget_ms])
		return ocp
	_pass("%s: first refresh %dms (budget %dms)" % [label, wall, budget_ms])
	return ocp


func _close_ocp(ocp: Node) -> void:
	if ocp == null or not is_instance_valid(ocp):
		return
	if ocp.has_method("_close_panel"):
		ocp.call("_close_panel")
	elif not ocp.is_queued_for_deletion():
		ocp.queue_free()


func _emit_escape(ocp: Node) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.key_label = KEY_ESCAPE
	ev.unicode = 27
	if ocp.has_method("_input"):
		ocp.call("_input", ev)
	if not _panel_is_closed(ocp) and ocp.has_method("_unhandled_input"):
		ocp.call("_unhandled_input", ev)


func _find_button_text_has(n: Node, needle: String) -> Button:
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
		return null
	if n is Button:
		var txt: String = str((n as Button).text)
		if txt.find(needle) >= 0:
			return n as Button
	for c in n.get_children():
		var found: Button = _find_button_text_has(c, needle)
		if found != null:
			return found
	return null


func _section_body_for_header(header: Node) -> Node:
	if header == null:
		return null
	var parent: Node = header.get_parent()
	if parent == null:
		return null
	var idx: int = header.get_index()
	if idx + 1 >= parent.get_child_count():
		return null
	return parent.get_child(idx + 1)


func _first_toggle_button(n: Node) -> Button:
	if n == null or not is_instance_valid(n):
		return null
	if n is Button:
		var txt: String = str((n as Button).text)
		if txt.begins_with("▶ ") or txt.begins_with("▼ "):
			return n as Button
	for c in n.get_children():
		var found: Button = _first_toggle_button(c)
		if found != null:
			return found
	return null


func _count_descendants(n: Node) -> int:
	if n == null:
		return 0
	var total: int = n.get_child_count()
	for c in n.get_children():
		total += _count_descendants(c)
	return total


func _timed_press(btn: BaseButton, budget_ms: int, label: String) -> int:
	if btn == null:
		_fail("%s: button missing" % label)
		return -1
	_arm_watchdog(budget_ms + WD_SLACK_MS, label)
	var t0: int = Time.get_ticks_msec()
	btn.pressed.emit()
	var dt: int = Time.get_ticks_msec() - t0
	_disarm_watchdog()
	if dt > budget_ms:
		_fail("%s: %dms (budget %dms)" % [label, dt, budget_ms])
	return dt


func _timed_call(obj: Object, method: String, args: Array, budget_ms: int, label: String) -> int:
	if obj == null or not obj.has_method(method):
		_fail("%s: %s missing" % [label, method])
		return -1
	_arm_watchdog(budget_ms + WD_SLACK_MS, label)
	var t0: int = Time.get_ticks_msec()
	obj.callv(method, args)
	var dt: int = Time.get_ticks_msec() - t0
	_disarm_watchdog()
	if dt > budget_ms:
		_fail("%s: %dms (budget %dms)" % [label, dt, budget_ms])
	return dt


func _test_a_cold_open() -> void:
	_progress("case (a) cold first open")
	_ocp = await _open_live_ocp(BUDGET_COLD_MS, "OrderCommandPanel", "a: cold")
	if _ocp == null:
		return
	if not _refresh_done(_ocp):
		_fail("a: cold first refresh did not complete within %dms" % BUDGET_COLD_MS)


func _test_b_warm_reopen() -> void:
	_progress("case (b) close then warm second instance")
	if _ocp != null and is_instance_valid(_ocp):
		_close_ocp(_ocp)
		var closed: bool = await _pump_frames_until(
			func() -> bool: return _panel_is_closed(_ocp),
			BUDGET_CLOSE_MS,
			"b: close first instance"
		)
		if not closed:
			_fail("b: first instance did not close before warm open")
	_ocp = await _open_live_ocp(BUDGET_WARM_MS, "OrderCommandPanel_warm", "b: warm")
	if _ocp == null:
		return
	if not _refresh_done(_ocp):
		_fail("b: warm first refresh did not complete within %dms" % BUDGET_WARM_MS)


func _test_c_close_and_esc() -> void:
	_progress("case (c) Close and Esc each ≤1s right after open")
	if _ocp == null or not is_instance_valid(_ocp) or not _refresh_done(_ocp):
		_ocp = await _open_live_ocp(BUDGET_COLD_MS, "OrderCommandPanel_c_close", "c: open for Close")
	if _ocp == null or not is_instance_valid(_ocp):
		_fail("c: no panel for Close")
		return
	var close_btn: Node = _ocp.get("_close_btn")
	if close_btn == null or not (close_btn is BaseButton):
		_fail("c: Close button missing")
	else:
		_progress("c: before Close")
		_arm_watchdog(BUDGET_CLOSE_MS + WD_SLACK_MS, "c: Close")
		(close_btn as BaseButton).pressed.emit()
		_disarm_watchdog()
		var closed: bool = await _pump_frames_until(
			func() -> bool: return _panel_is_closed(_ocp),
			BUDGET_CLOSE_MS,
			"c: Close within 1s"
		)
		if closed:
			_pass("c: Close within 1s")
	var ocp_esc: Node = await _open_live_ocp(BUDGET_COLD_MS, "OrderCommandPanel_c_esc", "c: open for Esc")
	if ocp_esc == null or not is_instance_valid(ocp_esc):
		_fail("c: no panel for Esc")
		return
	_progress("c: before Esc")
	_arm_watchdog(BUDGET_CLOSE_MS + WD_SLACK_MS, "c: Esc")
	_emit_escape(ocp_esc)
	_disarm_watchdog()
	var esc_closed: bool = await _pump_frames_until(
		func() -> bool: return _panel_is_closed(ocp_esc),
		BUDGET_CLOSE_MS,
		"c: Esc within 1s"
	)
	if esc_closed:
		_pass("c: Esc within 1s")
	_ocp = null


func _test_d_select_and_apply() -> void:
	_progress("case (d) map-select and apply_supply rebuild")
	_ocp = await _open_live_ocp(BUDGET_COLD_MS, "OrderCommandPanel_d", "d: open")
	if _ocp == null or not is_instance_valid(_ocp) or not _refresh_done(_ocp):
		_fail("d: panel not open")
		return
	var cur: int = int(_ocp.get("province_id"))
	var other: int = 710173 if cur != 710173 else 710174
	var ids: Variant = _ocp.get("_province_ids")
	if ids is Array:
		for pid_v in ids:
			var pid: int = int(pid_v)
			if pid != cur and pid >= 0:
				other = pid
				break
	_progress("d: before _on_map_province_selected %d" % other)
	var sel_ms: int = _timed_call(_ocp, "_on_map_province_selected", [other], BUDGET_SELECT_MS, "d: map-select")
	if sel_ms >= 0 and sel_ms <= BUDGET_SELECT_MS:
		_pass("d: _on_map_province_selected %dms" % sel_ms)
	_progress("d: before apply_supply")
	_arm_watchdog(BUDGET_APPLY_MS + WD_SLACK_MS, "d: apply_supply")
	var t0: int = Time.get_ticks_msec()
	if _ocp.has_method("_on_action_pressed"):
		_ocp.call("_on_action_pressed", "apply_supply")
	else:
		_fail("d: _on_action_pressed missing")
		_disarm_watchdog()
		return
	_disarm_watchdog()
	var rebuilt: bool = await _pump_frames_until(
		func() -> bool:
			if not _refresh_done(_ocp):
				return false
			var result_n: Variant = _ocp.get("_result")
			if result_n is Label and str((result_n as Label).text).find("apply_supply") >= 0:
				return true
			return false,
		BUDGET_APPLY_MS,
		"d: apply_supply rebuild"
	)
	var apply_ms: int = Time.get_ticks_msec() - t0
	if rebuilt and apply_ms <= BUDGET_APPLY_MS:
		_pass("d: apply_supply rebuild %dms" % apply_ms)
	elif rebuilt:
		_fail("d: apply_supply rebuild %dms (budget %dms)" % [apply_ms, BUDGET_APPLY_MS])


func _test_e_depth_catalogue() -> void:
	_progress("case (e) depth-catalogue group + one subgroup; D6 reopen collapsed")
	if _ocp == null or not is_instance_valid(_ocp) or not _refresh_done(_ocp):
		_ocp = await _open_live_ocp(BUDGET_COLD_MS, "OrderCommandPanel_e", "e: open")
	if _ocp == null or not is_instance_valid(_ocp):
		_fail("e: panel not open")
		return
	var header: Button = _find_button_text_has(_ocp, "Depth catalogue")
	if header == null:
		_fail("e: depth catalogue header missing")
		return
	var expand_ms: int = _timed_press(header, BUDGET_DEPTH_MS, "e: expand depth catalogue")
	if expand_ms >= 0 and expand_ms <= BUDGET_DEPTH_MS:
		_pass("e: expand depth catalogue %dms" % expand_ms)
	var cat_body: Node = _section_body_for_header(header)
	if cat_body == null or cat_body.get_child_count() <= 0:
		_fail("e: depth catalogue rows missing after expand")
		return
	_pass("e: depth catalogue rows=%d" % cat_body.get_child_count())
	var sub: Button = _first_toggle_button(cat_body)
	if sub == null:
		_fail("e: depth sub-group header missing")
		return
	var sub_ms: int = _timed_press(sub, BUDGET_DEPTH_MS, "e: expand depth sub-group")
	if sub_ms >= 0 and sub_ms <= BUDGET_DEPTH_MS:
		_pass("e: expand depth sub-group %dms" % sub_ms)
	var sub_body: Node = _section_body_for_header(sub)
	var sub_rows: int = _count_descendants(sub_body) if sub_body != null else 0
	if sub_body == null or (sub_body.get_child_count() <= 0 and sub_rows <= 0):
		_fail("e: depth sub-group rows missing after expand")
	else:
		_pass("e: depth sub-group rows=%d descendants=%d" % [sub_body.get_child_count(), sub_rows])
	_close_ocp(_ocp)
	var closed: bool = await _pump_frames_until(
		func() -> bool: return _panel_is_closed(_ocp),
		BUDGET_CLOSE_MS,
		"e: close before D6 reopen"
	)
	if not closed:
		_fail("e: panel did not close before D6 reopen")
		return
	var reopened: Node = await _open_live_ocp(BUDGET_COLD_MS, "OrderCommandPanel_e_reopen", "e: D6 reopen")
	if reopened == null or not is_instance_valid(reopened):
		_fail("e: D6 reopen failed")
		return
	var expanded_map: Variant = reopened.get("_section_expanded")
	var remembered: bool = false
	if expanded_map is Dictionary:
		remembered = bool((expanded_map as Dictionary).get("depth_catalogue", false))
	var re_header: Button = _find_button_text_has(reopened, "Depth catalogue")
	var mark_expanded: bool = false
	if re_header != null:
		mark_expanded = str(re_header.text).begins_with("▼")
	if remembered or mark_expanded:
		_fail("e: D6 expanded depth catalogue remembered after reopen")
	else:
		_pass("e: D6 depth catalogue collapsed after reopen")
	_ocp = reopened


func _quoted_in_src(src: String, action_id: String) -> bool:
	return src.find("\"%s\"" % action_id) >= 0


func _test_f_action_ids() -> void:
	_progress("case (f) every unfixed-tree apply-button id still reachable")
	if SNAPSHOT_ACTION_IDS.size() != SNAPSHOT_ACTION_ID_COUNT:
		_fail("f: snapshot const size %d != %d" % [SNAPSHOT_ACTION_IDS.size(), SNAPSHOT_ACTION_ID_COUNT])
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/OrderCommandPanel.gd")
	if src.is_empty():
		_fail("f: OrderCommandPanel.gd unreadable")
		return
	var missing: PackedStringArray = PackedStringArray()
	for action_id in SNAPSHOT_ACTION_IDS:
		if not _quoted_in_src(src, str(action_id)):
			missing.append(str(action_id))
	if missing.size() > 0:
		var shown: int = mini(missing.size(), 12)
		var bits: PackedStringArray = PackedStringArray()
		for i in range(shown):
			bits.append(missing[i])
		_fail("f: %d snapshot action ids missing from OCP source (e.g. %s)" % [
			missing.size(), ", ".join(bits)
		])
		return
	_pass("f: all %d snapshot action ids still in OrderCommandPanel.gd (collapsed or expanded OK)" % SNAPSHOT_ACTION_IDS.size())


func _active_has(dm: Node, tag: String, domain: String, did: String) -> bool:
	if dm == null or not dm.has_method("get_active_designs"):
		return false
	var ids: Variant = dm.call("get_active_designs", tag, domain)
	if ids is Array:
		for x in ids:
			if str(x) == did:
				return true
	return false


func _catalog_has(cat: Dictionary, domain: String, did: String) -> bool:
	var rows: Variant = cat.get(domain, [])
	if rows is Array:
		for r in rows:
			if r is Dictionary and str((r as Dictionary).get("design_id", "")) == did:
				return true
	return false


func _live_catalog(mm: Node, tag: String) -> Dictionary:
	if mm == null or not mm.has_method("_designer_live_catalog"):
		return {}
	var cat: Variant = mm.call("_designer_live_catalog", tag)
	return cat as Dictionary if cat is Dictionary else {}


func _live_product(mm: Node, pid: int) -> Dictionary:
	if mm == null or not mm.has_method("designer_suite_product_live"):
		return {}
	var prod: Variant = mm.call("designer_suite_product_live", pid)
	return prod as Dictionary if prod is Dictionary else {}


func _in_top6_active(dm: Node, tag: String, domain: String, did: String) -> bool:
	if dm == null or not dm.has_method("get_active_designs"):
		return false
	var ids: Variant = dm.call("get_active_designs", tag, domain)
	if not (ids is Array):
		return false
	var i: int = 0
	for x in ids:
		if i >= 6:
			return false
		if str(x) == did:
			return true
		i += 1
	return false


func _assert_design_visible(dm: Node, mm: Node, pid: int, tag: String, domain: String, did: String, label: String, want: bool) -> void:
	var active_ok: bool = _active_has(dm, tag, domain, did)
	var top6: bool = _in_top6_active(dm, tag, domain, did)
	var cat: Dictionary = _live_catalog(mm, tag)
	var cat_ok: bool = _catalog_has(cat, domain, did)
	var live: Dictionary = _live_product(mm, pid)
	var live_cat: Dictionary = {}
	if live.get("catalog") is Dictionary:
		live_cat = live.get("catalog") as Dictionary
	var live_ok: bool = _catalog_has(live_cat, domain, did)
	var seed: Dictionary = {}
	if mm != null and mm.has_method("apply_designer_suite_step_for_province"):
		var seed_v: Variant = mm.call("apply_designer_suite_step_for_province", pid, "seed_production")
		if seed_v is Dictionary:
			seed = seed_v
	var seed_prod: Dictionary = {}
	if seed.get("product") is Dictionary:
		seed_prod = seed.get("product") as Dictionary
	var seed_cat: Dictionary = {}
	if seed_prod.get("catalog") is Dictionary:
		seed_cat = seed_prod.get("catalog") as Dictionary
	var seed_ok: bool = _catalog_has(seed_cat, domain, did) or active_ok
	if want:
		if not active_ok:
			_fail("%s: get_active_designs(%s,%s) missing %s" % [label, tag, domain, did])
		if top6 and not cat_ok:
			_fail("%s: _designer_live_catalog(%s).%s missing top-6 %s" % [label, tag, domain, did])
		if top6 and not live_ok:
			_fail("%s: designer_suite_product_live catalog.%s missing top-6 %s" % [label, domain, did])
		if not seed_ok:
			_fail("%s: seed_production / get_active_designs missing %s" % [label, did])
		if active_ok and seed_ok and ((not top6) or (cat_ok and live_ok)):
			_pass("%s: catalog + AI production see %s (top6=%s)" % [label, did, str(top6)])
	else:
		if active_ok:
			_fail("%s: get_active_designs(%s,%s) still has %s" % [label, tag, domain, did])
		if cat_ok:
			_fail("%s: _designer_live_catalog(%s).%s still has %s" % [label, tag, domain, did])
		if live_ok:
			_fail("%s: designer_suite_product_live catalog.%s still has %s" % [label, domain, did])
		if not active_ok and not cat_ok and not live_ok:
			_pass("%s: catalog dropped %s" % [label, did])


func _register_custom(dm: Node, tag: String, did: String, domain: String) -> bool:
	if dm == null or not dm.has_method("register_custom_design"):
		_fail("register_custom_design missing")
		return false
	var blob: Dictionary = {
		"id": did,
		"design_id": did,
		"domain": domain,
		"modules": ["land_main", "land_engine"],
		"mobility": "truck",
		"armor_element": "medium_tank",
		"support": "artillery",
		"infantry_bns": 1,
		"tank_bns": 1,
		"visual_archetype": "medium_tank",
	}
	var reg: Variant = dm.call("register_custom_design", tag, blob)
	if not (reg is Dictionary) or not bool((reg as Dictionary).get("ok", false)):
		_fail("register_custom_design %s/%s failed: %s" % [tag, did, str(reg)])
		return false
	return true


func _g_pid() -> int:
	if _ocp != null and is_instance_valid(_ocp):
		return int(_ocp.get("province_id"))
	return 1


func _test_g_cache_invalidation() -> void:
	_progress("case (g) cache invalidation ADD/CHANGE/REMOVE + factory + save/load")
	var dm: Node = _dm()
	var mm: Node = _mm()
	if dm == null or mm == null:
		_fail("g: DesignManager or MapManager missing")
		return
	if not dm.has_method("get_save_data") or not dm.has_method("apply_save_data"):
		_fail("g: DesignManager save/load API missing")
		return
	var before: Dictionary = dm.call("get_save_data")
	var pid: int = _g_pid()

	_progress("g: ADD register_custom_design %s" % ADD_ID)
	if not _register_custom(dm, PLAYER_TAG, ADD_ID, "land"):
		return
	_assert_design_visible(dm, mm, pid, PLAYER_TAG, "land", ADD_ID, "g ADD", true)

	_progress("g: CHANGE re-register %s as %s" % [ADD_ID, CHANGE_DOMAIN])
	if not _register_custom(dm, PLAYER_TAG, ADD_ID, CHANGE_DOMAIN):
		return
	_assert_design_visible(dm, mm, pid, PLAYER_TAG, CHANGE_DOMAIN, ADD_ID, "g CHANGE naval", true)
	if _active_has(dm, PLAYER_TAG, "land", ADD_ID) or _catalog_has(_live_catalog(mm, PLAYER_TAG), "land", ADD_ID):
		_fail("g CHANGE: %s still listed under land after naval re-register" % ADD_ID)
	else:
		_pass("g CHANGE: %s left land catalog" % ADD_ID)

	_progress("g: REMOVE grant then revoke %s" % REMOVE_ID)
	if not _register_custom(dm, FOREIGN_TAG, REMOVE_ID, "land"):
		return
	if dm.has_method("grant_acquired_design"):
		dm.call("grant_acquired_design", PLAYER_TAG, REMOVE_ID, "captured")
	else:
		_fail("g: grant_acquired_design missing")
		return
	_assert_design_visible(dm, mm, pid, PLAYER_TAG, "land", REMOVE_ID, "g REMOVE grant", true)
	if dm.has_method("revoke_acquired_design"):
		dm.call("revoke_acquired_design", PLAYER_TAG, REMOVE_ID)
	else:
		_fail("g: revoke_acquired_design missing")
		return
	_assert_design_visible(dm, mm, pid, PLAYER_TAG, "land", REMOVE_ID, "g REMOVE revoke", false)

	_progress("g: factory sync_production_design")
	var pm: Node = root.get_node_or_null("ProductionManager")
	var fm: Node = root.get_node_or_null("FactoryManager")
	var fac: Object = null
	if pm != null and pm.has_method("get_all_factories_for_country"):
		var factories: Variant = pm.call("get_all_factories_for_country", PLAYER_TAG)
		if factories is Array and not (factories as Array).is_empty():
			fac = (factories as Array)[0]
	if fac == null and fm != null and fm.has_method("create_factory_for_province"):
		var created: Variant = fm.call("create_factory_for_province", pid, PLAYER_TAG)
		if created != null:
			fac = created
	if fac == null or not fac.has_method("sync_production_design"):
		_fail("g: no GER factory for sync_production_design")
	else:
		fac.call("sync_production_design", ADD_ID)
		var in_prod: bool = false
		if "current_production_design" in fac:
			in_prod = str(fac.get("current_production_design")) == ADD_ID
		if not in_prod:
			_fail("g: factory current_production_design is not %s" % ADD_ID)
		var after_sync_active: bool = _active_has(dm, PLAYER_TAG, CHANGE_DOMAIN, ADD_ID)
		var after_sync_top6: bool = _in_top6_active(dm, PLAYER_TAG, CHANGE_DOMAIN, ADD_ID)
		var after_sync_cat: bool = _catalog_has(_live_catalog(mm, PLAYER_TAG), CHANGE_DOMAIN, ADD_ID)
		if after_sync_active and ((not after_sync_top6) or after_sync_cat):
			_pass("g: factory sync_production_design reflected in catalog (top6=%s)" % str(after_sync_top6))
		else:
			_fail("g: in-production %s not in active/catalog (active=%s catalog=%s top6=%s)" % [
				ADD_ID, str(after_sync_active), str(after_sync_cat), str(after_sync_top6)
			])

	_progress("g: save→load apply_save_data must not keep stale entry")
	if not _register_custom(dm, PLAYER_TAG, STALE_ID, "land"):
		return
	dm.call("get_active_designs", PLAYER_TAG, "land")
	mm.call("_designer_live_catalog", PLAYER_TAG)
	mm.call("designer_suite_product_live", pid)
	dm.call("apply_save_data", before)
	if _active_has(dm, PLAYER_TAG, "land", STALE_ID) or _catalog_has(_live_catalog(mm, PLAYER_TAG), "land", STALE_ID):
		_fail("g: apply_save_data left stale %s in active/catalog" % STALE_ID)
	elif _active_has(dm, PLAYER_TAG, "land", ADD_ID) or _catalog_has(_live_catalog(mm, PLAYER_TAG), CHANGE_DOMAIN, ADD_ID):
		_fail("g: apply_save_data left stale %s from ADD/CHANGE" % ADD_ID)
	else:
		_pass("g: apply_save_data has no stale catalog entry")
