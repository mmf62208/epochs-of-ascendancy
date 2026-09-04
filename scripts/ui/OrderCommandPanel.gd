# scripts/ui/OrderCommandPanel.gd
## Theater Command Center — P1 order UX with province bind, multi-section apply (P2–P8), last-result feedback, P9 GPU profile.
class_name OrderCommandPanel
extends Control

@export var country_tag: String = "GER"
@export var province_id: int = 1

var _title: Label
var _status: Label
var _result: Label
var _province_option: OptionButton
var _body: VBoxContainer
var _sections: VBoxContainer
var _log_label: RichTextLabel
var _close_btn: Button
var _refresh_btn: Button
var _province_ids: Array = []
var _last_result: Dictionary = {}
var _map_select_connected: bool = false
## Collapsible day-package sections: section_id -> expanded bool (player toggle sticky).
var _section_expanded: Dictionary = {}
## When set, _add_* helpers attach into this section body instead of root _body.
var _active_body: VBoxContainer = null
## Live day-package routes kept available under collapsible sections (wiring/gates).
## Full catalogue listed so pure wiring tests can assert string presence; runtime
## builds buttons from MapPolishFormatters.order_panel_section_plan.
const DAY_PACKAGE_ACTION_IDS: PackedStringArray = [
	"day_ops_integrated", "theater_day_cabinet", "logistics_day", "war_economy_day",
	"leader_station_day", "air_forecast_day", "reinforced_assault_day", "multi_front_assault_day",
	"joint_command_day", "naval_interdiction_day", "intel_counter_day", "strategic_continuity_day",
	"order_execute_day", "focus_war_path_day", "force_readiness_day", "force_posture_day",
	"theater_readiness_day", "industry_surge_day", "production_surge_day", "depot_capacity_day",
	"joint_campaign_day", "naval_campaign_day", "air_land_joint_day", "weather_crisis_day",
	"ground_transition_day", "fog_air_crisis_day", "agent_campaign_day", "agent_response_day",
	"hh_campaign_day", "combat_campaign_day", "combat_ops_day", "move_path_day",
	"fleet_campaign_day", "fleet_redeploy_day", "fleet_task_group_day", "hh_player_path",
	"hh_agenda_screen_day", "fleet_autonomy_day", "fleet_multi_day_autonomy_product", "fleet_day_posture", "fleet_day_station_escort", "fleet_day_follow_through",
	"medium_tank_oob_product", "oob_horizon_60d", "oob_horizon_80d", "oob_horizon_100d",
	"hh_multi_month_agenda_product", "hh_month_trail_board", "hh_month_brief", "hh_month_quarterly_counter",
	"agent_campaign_product", "agent_product_board", "agent_product_dispatch", "agent_product_counterplay",
	"inspector_decision_product", "inspector_product_primary", "inspector_product_collapse", "inspector_product_apply",
	"theater_command_product", "theater_command_scan", "theater_command_rank", "theater_command_execute",
	"multi_faction_strategic_ai_product", "strategic_ai_scan", "strategic_ai_rank", "strategic_ai_execute",
	"strategic_ai_daily_campaign_product", "strategic_ai_daily_board", "strategic_ai_daily_budget", "strategic_ai_daily_apply",
	"play_session_campaign_product", "play_session_brief", "play_session_execute", "play_session_resolve",
	"air_ops_campaign_product", "air_ops_sortie", "air_ops_weather_gate", "air_ops_air_land",
	"focus_war_path_product", "focus_war_pick", "focus_war_path_step", "focus_war_commit",
	"naval_multi_phase_campaign_product", "naval_phase_posture", "naval_phase_escort", "naval_phase_strike",
	"diplomacy_peace_campaign_product", "diplomacy_peace_board", "diplomacy_peace_leverage", "diplomacy_peace_settle",
	"tech_research_campaign_product", "tech_research_catalog", "tech_research_priority", "tech_research_field",
	"diplomacy_board_advanced_day",
	"diplomacy_leverage_advanced_day",
	"diplomacy_settle_advanced_day",
	"diplomacy_trade_pressure_day",
	"diplomacy_agent_hh_joint_day",
	"diplomacy_focus_peace_joint_day",
	"diplomacy_peace_close_day",
	"tech_catalog_advanced_day",
	"tech_priority_advanced_day",
	"tech_field_advanced_day",
	"tech_designer_joint_day",
	"tech_oob_fielding_joint_day",
	"tech_industry_focus_joint_day",
	"tech_research_close_day",
	"diplomacy_tech_joint_day",
	"tech_ai_research_joint_day",
	"diplomacy_naval_air_joint_day",
	"session_diplomacy_tech_joint_day",
	"multi_faction_diplo_tech_day",
	"diplomacy_tech_campaign_close_day",
"logistics_supply_theater_product", "logistics_supply_route", "logistics_supply_sustain", "logistics_supply_readiness",
"intelligence_network_product", "intel_network_coverage", "intel_network_counterintel", "intel_network_counterplay",
"world_class_campaign_command_product", "world_class_scan", "world_class_rank", "world_class_execute",
	"logistics_route_advanced_day",
	"logistics_sustain_advanced_day",
	"logistics_readiness_advanced_day",
	"logistics_naval_joint_day",
	"logistics_tech_industry_joint_day",
	"logistics_supply_close_day",
	"intel_coverage_advanced_day",
	"intel_counterintel_advanced_day",
	"intel_counterplay_advanced_day",
	"intel_diplomacy_joint_day",
	"intel_session_joint_day",
	"intelligence_network_close_day",
	"world_class_scan_advanced_day",
	"world_class_rank_advanced_day",
	"world_class_execute_advanced_day",
	"world_class_logistics_intel_joint_day",
	"world_class_air_naval_joint_day",
	"world_class_session_ai_joint_day",
	"world_class_theater_command_joint_day",
	"world_class_campaign_close_day",
"war_economy_mobilization_product", "war_economy_board", "war_economy_allocate", "war_economy_sustain",
"weather_theater_ops_product", "weather_theater_pressure", "weather_theater_gate", "weather_theater_crisis",
"front_continuity_campaign_product", "front_continuity_combat", "front_continuity_assault", "front_continuity_sustain",
	"war_economy_board_advanced_day",
	"war_economy_allocate_advanced_day",
	"war_economy_sustain_advanced_day",
	"war_economy_logistics_joint_day",
	"war_economy_tech_joint_day",
	"war_economy_mobilization_close_day",
	"weather_pressure_advanced_day",
	"weather_gate_advanced_day",
	"weather_crisis_advanced_day",
	"weather_front_joint_day",
	"weather_economy_joint_day",
	"weather_theater_ops_close_day",
	"front_combat_advanced_day",
	"front_assault_advanced_day",
	"front_sustain_advanced_day",
	"front_weather_joint_day",
	"front_economy_joint_day",
	"front_logistics_joint_day",
	"front_theater_command_joint_day",
	"front_continuity_campaign_close_day",
"occupation_control_product", "occupation_control_board", "occupation_control_garrison", "occupation_control_integrate",
"manpower_reinforcement_product", "manpower_draft_board", "manpower_reinforce_lines", "manpower_field_units",
"leader_command_product", "leader_command_assign", "leader_command_station", "leader_command_ops",
	"occupation_control_advanced_day",
	"occupation_garrison_advanced_day",
	"occupation_integrate_advanced_day",
	"occupation_front_joint_day",
	"occupation_economy_joint_day",
	"occupation_control_close_day",
	"manpower_draft_advanced_day",
	"manpower_reinforce_advanced_day",
	"manpower_field_advanced_day",
	"manpower_front_joint_day",
	"manpower_economy_joint_day",
	"manpower_reinforcement_close_day",
	"leader_assign_advanced_day",
	"leader_station_advanced_day",
	"leader_ops_advanced_day",
	"leader_occupation_joint_day",
	"leader_manpower_joint_day",
	"leader_intel_joint_day",
	"leader_theater_joint_day",
	"occupation_manpower_leader_close_day",
"medium_tank_production_honesty_product", "medium_honesty_prove_60d", "medium_honesty_prove_80d", "medium_honesty_prove_100d",
	"medium_honesty_60d_day",
	"medium_honesty_80d_day",
	"medium_honesty_100d_day",
	"medium_honesty_unit_stats_day",
	"medium_honesty_factory_risk_day",
	"medium_honesty_stockpile_day",
	"medium_honesty_readiness_joint_day",
	"medium_honesty_manpower_joint_day",
	"medium_honesty_economy_joint_day",
	"medium_tank_production_honesty_close_day",
"apply_queue_live_managers_product", "apply_queue_live_audit", "apply_queue_live_production", "apply_queue_live_combat",
	"apply_queue_audit_day",
	"apply_queue_production_live_day",
	"apply_queue_combat_live_day",
	"apply_queue_supply_live_day",
	"apply_queue_focus_live_day",
	"apply_queue_agent_live_day",
	"apply_queue_station_live_day",
	"apply_queue_six_leaf_joint_day",
	"apply_queue_honesty_joint_day",
	"apply_queue_live_managers_close_day",
"occupation_resistance_compliance_product", "occupation_resistance_board", "occupation_resistance_policy", "occupation_resistance_tick",
"manpower_laws_training_product", "manpower_law_board", "manpower_train_pipeline", "manpower_field_trained",
"peace_conference_settlement_product", "peace_conference_board", "peace_conference_demands", "peace_conference_settle",
	"occupation_resistance_board_day",
	"occupation_resistance_policy_day",
	"occupation_resistance_tick_day",
	"occupation_resistance_close_day",
	"manpower_law_board_day",
	"manpower_train_pipeline_day",
	"manpower_field_trained_day",
	"manpower_laws_training_close_day",
	"peace_conference_board_day",
	"peace_conference_demands_day",
	"peace_conference_settle_day",
	"peace_conference_campaign_close_day",
"product_ux_command_polish_product", "product_ux_compact_board", "product_ux_top_chips", "product_ux_hotkeys",
"campaign_alpha_primary_strip_product", "campaign_alpha_apply_recommended", "campaign_alpha_primary_board", "campaign_alpha_recommend_next", "campaign_alpha_dead_audit",
"combat_ops_close", "hh_agenda_close", "naval_ops_close", "stream_alpha_primary_packs_product",
"stream_alpha_primary_command_product", "stream_alpha_primary_command_live", "apply_stream_alpha_primary_command_live",
"apply_stream_alpha_combat", "apply_stream_alpha_oob", "apply_stream_alpha_save", "apply_stream_alpha_hh",
"stream_alpha_combat_primary", "stream_alpha_oob_primary", "stream_alpha_save_primary", "stream_alpha_hh_primary",
"fleet_autonomy_primary_command_product", "fleet_autonomy_primary_command_live", "apply_fleet_autonomy_primary_command_live",
"apply_fleet_autonomy_posture", "apply_fleet_autonomy_station", "apply_fleet_autonomy_follow", "apply_fleet_autonomy_close",
"fleet_autonomy_posture_primary", "fleet_autonomy_station_primary", "fleet_autonomy_follow_primary", "fleet_autonomy_close_primary",
"peace_conference_primary_command_product", "peace_conference_primary_command_live", "apply_peace_conference_primary_command_live",
"apply_peace_primary_open", "apply_peace_primary_claim", "apply_peace_primary_cede", "apply_peace_primary_puppet", "apply_peace_primary_close",
"peace_primary_open", "peace_primary_claim", "peace_primary_cede", "peace_primary_puppet", "peace_primary_close",
"occupation_primary_command_product", "occupation_primary_command_live", "apply_occupation_primary_command_live",
"apply_occupation_primary_mapmode", "apply_occupation_primary_law", "apply_occupation_primary_garrison", "apply_occupation_primary_rc_pulse", "apply_occupation_primary_close",
"occupation_primary_mapmode", "occupation_primary_law", "occupation_primary_garrison", "occupation_primary_rc_pulse", "occupation_primary_close",
"research_queue_primary_command_product", "research_queue_primary_command_live", "apply_research_queue_primary_command_live",
"apply_research_primary_open_queue", "apply_research_primary_enqueue_branch", "apply_research_primary_gate_check", "apply_research_primary_advance_month", "apply_research_primary_close",
"research_primary_open_queue", "research_primary_enqueue_branch", "research_primary_gate_check", "research_primary_advance_month", "research_primary_close",
"agent_mission_board_primary_command_product", "agent_mission_board_primary_command_live", "apply_agent_mission_board_primary_command_live",
"apply_agent_primary_board_surface", "apply_agent_primary_dispatch", "apply_agent_primary_resolve", "apply_agent_primary_counter_intel", "apply_agent_primary_close",
"agent_primary_board_surface", "agent_primary_dispatch", "agent_primary_resolve", "agent_primary_counter_intel", "agent_primary_close",
"apply_station", "apply_assault", "apply_production",
"designer_domain_live_product", "designer_domain_live_catalog", "designer_domain_live_pick", "designer_domain_live_seed",
"campaign_ai_multi_month_product", "campaign_ai_month_board", "campaign_ai_weekly_plan", "campaign_ai_theater_execute",
	"product_ux_compact_day",
	"product_ux_chips_day",
	"product_ux_hotkeys_day",
	"product_ux_polish_close_day",
	"designer_domain_catalog_day",
	"designer_domain_pick_day",
	"designer_domain_seed_day",
	"designer_domain_live_close_day",
	"campaign_ai_month_board_day",
	"campaign_ai_weekly_plan_day",
	"campaign_ai_theater_execute_day",
	"campaign_ai_multi_month_close_day",
"occupation_revolt_garrison_product", "occupation_revolt_board", "occupation_revolt_garrison", "occupation_revolt_suppress",
"manpower_cohort_reserve_product", "manpower_cohort_board", "manpower_cohort_reserve", "manpower_cohort_mobilize",
"multi_party_peace_conference_product", "multi_party_peace_board", "multi_party_peace_wargoals", "multi_party_peace_settle",
	"occupation_revolt_board_day",
	"occupation_revolt_garrison_day",
	"occupation_revolt_suppress_day",
	"occupation_revolt_garrison_close_day",
	"manpower_cohort_board_day",
	"manpower_cohort_reserve_day",
	"manpower_cohort_mobilize_day",
	"manpower_cohort_reserve_close_day",
	"multi_party_peace_board_day",
	"multi_party_peace_wargoals_day",
	"multi_party_peace_settle_day",
	"multi_party_peace_campaign_close_day",
"historical_oob_content_product", "historical_oob_catalog", "historical_oob_seed", "historical_oob_equip",
"tech_tree_branching_product", "tech_tree_branches", "tech_tree_path", "tech_tree_field",
"save_resume_campaign_product", "save_resume_checkpoint", "save_resume_save", "save_resume_resume",
	"historical_oob_catalog_day",
	"historical_oob_seed_day",
	"historical_oob_equip_day",
	"historical_oob_content_close_day",
	"tech_tree_branches_day",
	"tech_tree_path_day",
	"tech_tree_field_day",
	"tech_tree_branching_close_day",
	"save_resume_checkpoint_day",
	"save_resume_save_day",
	"save_resume_resume_day",
	"save_resume_campaign_close_day",
"tutorial_first_session_product", "tutorial_session_brief", "tutorial_session_guide", "tutorial_session_checkpoint",
"focus_tree_content_product", "focus_tree_catalog", "focus_tree_path", "focus_tree_commit",
"balance_combat_supply_product", "balance_estimate_board", "balance_live_sample", "balance_variance_close",
"air_multi_phase_theater_product", "air_theater_recon", "air_theater_cas_gate", "air_theater_interdiction",
"naval_search_strike_product", "naval_search_patrol", "naval_asw_escort", "naval_carrier_strike",
"war_economy_conversion_product", "economy_civ_board", "economy_war_convert", "economy_stockpile_sustain",
	"air_theater_recon_day",
	"air_theater_cas_gate_day",
	"air_theater_interdiction_day",
	"air_multi_phase_theater_close_day",
	"naval_search_patrol_day",
	"naval_asw_escort_day",
	"naval_carrier_strike_day",
	"naval_search_strike_close_day",
	"economy_civ_board_day",
	"economy_war_convert_day",
	"economy_stockpile_sustain_day",
	"war_economy_conversion_close_day",
"designer_module_editor_product", "designer_module_board", "designer_module_edit", "designer_reliability_gate",
"designer_stats_field_product", "designer_stats_board", "designer_freeze_design", "designer_field_seed",
"designer_multi_domain_campaign_product", "designer_catalog_all_domains", "designer_seed_multi_domain", "designer_equip_campaign_close",
	"designer_module_board_day",
	"designer_module_edit_day",
	"designer_reliability_gate_day",
	"designer_module_editor_close_day",
	"designer_stats_board_day",
	"designer_freeze_design_day",
	"designer_field_seed_day",
	"designer_stats_field_close_day",
	"designer_catalog_all_domains_day",
	"designer_seed_multi_domain_day",
	"designer_equip_campaign_close_day",
	"designer_multi_domain_campaign_close_day",
"weather_crisis_campaign_product", "weather_crisis_forecast", "weather_crisis_gate_multi", "weather_crisis_sustain",
"intel_cell_network_product", "intel_cell_coverage", "intel_cell_ops", "intel_counter_sweep",
"leader_theater_command_product", "leader_hq_board", "leader_multi_station", "leader_theater_ops",
	"weather_crisis_forecast_day",
	"weather_crisis_gate_multi_day",
	"weather_crisis_sustain_day",
	"weather_crisis_campaign_close_day",
	"intel_cell_coverage_day",
	"intel_cell_ops_day",
	"intel_counter_sweep_day",
	"intel_cell_network_close_day",
	"leader_hq_board_day",
	"leader_multi_station_day",
	"leader_theater_ops_day",
	"leader_theater_command_close_day",
"strategic_war_goal_product", "war_goal_board", "war_goal_justify", "war_goal_execute",
"multi_front_campaign_ai_product", "multi_front_plan", "multi_front_weekly", "multi_front_execute",
"grand_strategy_cycle_product", "gs_cycle_scan", "gs_cycle_rank", "gs_cycle_execute",
	"war_goal_board_day",
	"war_goal_justify_day",
	"war_goal_execute_day",
	"strategic_war_goal_close_day",
	"multi_front_plan_day",
	"multi_front_weekly_day",
	"multi_front_execute_day",
	"multi_front_campaign_ai_close_day",
	"gs_cycle_scan_day",
	"gs_cycle_rank_day",
	"gs_cycle_execute_day",
	"grand_strategy_cycle_close_day",




	"tutorial_session_brief_day",
	"tutorial_session_guide_day",
	"tutorial_session_checkpoint_day",
	"tutorial_first_session_close_day",
	"focus_tree_catalog_day",
	"focus_tree_path_day",
	"focus_tree_commit_day",
	"focus_tree_content_close_day",
	"balance_estimate_board_day",
	"balance_live_sample_day",
	"balance_variance_close_day",
	"balance_combat_supply_close_day",
	"focus_pick_board_advanced_day",
	"focus_war_path_advanced_day",
	"focus_commit_execute_advanced_day",
	"focus_naval_effort_advanced_day",
	"focus_industry_army_joint_day",
	"focus_air_effort_joint_day",
	"focus_war_path_close_day",
	"naval_posture_advanced_day",
	"naval_escort_phase_advanced_day",
	"naval_strike_phase_advanced_day",
	"naval_fleet_fuel_advanced_day",
	"naval_fleet_autonomy_joint_day",
	"naval_air_joint_advanced_day",
	"naval_multi_phase_close_day",
	"designer_domain_advanced_day",
	"designer_seed_advanced_day",
	"strategic_ai_multi_day_advanced_day",
	"designer_ai_industry_joint_day",
	"play_session_advanced_joint_day",
	"advanced_deferred_campaign_close_day",
	"designer_suite_product", "designer_suite_catalog", "designer_suite_pick", "designer_suite_seed",
	"designer_domain_land", "designer_domain_naval", "designer_domain_air", "designer_domain_space", "gpu_pan_zoom_day",
	"multi_phase_combat_day", "combat_air_naval_day", "agent_auto_day",
	"multi_phase_combat_product", "phase_approach", "phase_engage", "phase_disengage",
	"focus_pick_day", "production_priority_day", "convoy_escort_day",
	"next_day_feedback_day", "map_effect_day", "theater_brief_day",
	"campaign_decision_day",
	"order_panel_ux_day", "multi_phase_combat_ui_day", "fleet_ai_ops_day",
	"hh_agenda_package_day", "agent_campaign_depth_day", "industry_economy_day",
	"save_slot_browser_day", "save_browser_campaign_product", "save_browser_resume", "save_browser_checkpoint", "basing_logistics_day", "assault_follow_on_day",
	"joint_ops_loop_day",
	"war_cabinet_day", "supply_campaign_day", "force_supply_day", "counter_ops_day",
	"multi_province_live_day", "order_queue_day", "agent_ai_board_day",
	"fleet_order_day", "fleet_theater_posture_day", "campaign_risk_day",
	"sealane_health_day", "convoy_package_day", "theater_campaign_day",
	"production_risk_day", "leader_campaign_day", "basing_repair_day",
	"focus_order_day", "naval_order_day", "air_land_order_day", "theater_order_day",
	"factory_risk_day", "trade_chain_day", "war_path_urgency_day", "combat_morale_day",
	"choke_sea_day", "redeploy_route_day", "theater_report_day", "best_station_day",
	"best_assault_day", "theater_mutation_day",
	"air_ops_sortie_day",
	"agent_escalation_day",
	"agent_coverage_day",
	"combat_order_day",
	"production_order_day",
	"supply_order_day",
	"combat_phase_strip_day",
	"fleet_patrol_day",
	"execute_one_day",
	"daily_fleet_plan_day",
	"daily_combat_plan_day",
	"daily_prod_plan_day",
	"daily_agent_plan_day",
	"daily_supply_plan_day",
	"agent_dispatch_mutation_day",
	"fleet_station_mutation_day",
	"assault_stage_mutation_day",
	"naval_task_mutation_day",
	"air_land_stage_mutation_day",
	"hh_monthly_day",
	"leader_weather_day",
	"oob_factory_day",
	"move_ops_day",
	"fleet_wx_mission_day",
	"player_surface_day",
	"multi_province_plan_day",
	"theater_prod_auto_day",
	"focus_mutation_day",
	"mutation_feedback_day",
	"hh_quarterly_day",
	"depot_weather_day",
	"fleet_patrol_strip_day",
	"close_loop_day",
	"agent_missions_day",
	"supply_route_mutation_day",
	"basing_fuel_day",
	"ops_dashboard_day",
	"daily_theater_tick_day",
	"command_log_day",
	"integrity_gate_day",
	"result_feedback_day",
	"day_budget_day",
	"hh_auto_plan_day",
	"append_log_day",
	"log_strip_day",
	"assault_readiness_day",
	"coherence_delta_day",
	"agent_order_day",
	"execution_gate_day",
	"cohesion_gate_day",
	"command_gate_day",
	"execute_order_day",
	"air_sortie_ready_day",
	"weather_combat_brief_day",
	"day_audit_day",
	"map_visible_day",
	"assault_card_day",
	"save_slot_list_day",
	"multi_phase_estimate_day",
	"campaign_strip_day",
	"mutation_result_day",
	"mutation_strip_day",
	"close_mutation_day",
	"mutation_gate_day",
	"agenda_pick_day",
	"agenda_actions_day",
	"hh_commit_order_day",
	"theater_hh_commit_day",
	"hh_counterplay_day",
	"task_group_day",
	"naval_basing_day",
	"naval_multi_phase_day",
	"coastal_fog_gate_day",
	"phase_ribbon_day",
	"assault_rank_day",
	"joint_timeline_day",
	"daylight_combat_day",
	"production_auto_day",
	"production_risk_alert_day",
	"day_results_flair_day",
	"best_assault_live_day",
	"best_station_live_day",
	"execute_one_live_day",
	"basing_fuel_loop_day",
	"fleet_wx_package_day",
	"convoy_wx_window_day",
	"focus_wx_score_day",
	"morale_wx_day",
	"campaign_risk_live_day",
	"depot_wx_live_day",
	"daily_fleet_auto_day",
	"daily_combat_auto_day",
	"daily_agent_auto_day",
	"daily_supply_auto_day",
	"basing_signals_day",
	"basing_rates_day",
	"combat_wx_mult_day",
	"sea_zone_trade_day",
	"hh_secondary_trail_day",
	"agent_campaign_live_day",
	"live_mut_board_day",
	"feedback_chain_day",
	"mut_close_stack_day",
	"dual_domain_mutate_day",
	"assault_mut_fb_day",
	"agent_mut_log_day",
	"supply_mut_fb_day",
	"combat_surface_stack_day",
	"phase_timeline_stack_day",
	"assault_rank_card_day",
	"joint_naval_land_day",
	"multi_front_surface_day",
	"combat_depth_strip_day",
	"phase_estimate_ribbon_day",
	"fleet_path_stack_day",
	"basing_mission_day",
	"hh_path_stack_day",
	"hh_trail_counter_day",
	"agent_mission_path_day",
	"incomplete_loop_close_day",
	"prod_mut_apply_day",
	"supply_mut_apply_day",
	"execute_prod_live_day",
	"day_budget_apply_day",
	"apply_audit_live_day",
	"live_apply_results_day",
	"mutation_gate_apply_day",
	"daily_prod_auto_live_day",
	"theater_prod_live_day",
	"prod_campaign_risk_day",
	"prod_wx_stack_day",
	"factory_risk_live_day",
	"depot_prod_stack_day",
	"industry_close_loop_day",
	"save_slot_surface_day",
	"save_browser_live_day",
	"campaign_continuity_day",
	"ops_dash_continuity_day",
	"execution_gate_cont_day",
	"industry_save_close_day",
	"fleet_ai_task_day",
	"fleet_wx_ops_day",
	"basing_fuel_ops_day",
	"naval_phase_ops_day",
	"coastal_fog_ops_day",
	"fleet_station_mut_day",
	"naval_task_mut_day",
	"hh_agenda_pick_day",
	"hh_agenda_actions_day",
	"hh_order_path_day",
	"theater_hh_path_day",
	"hh_trail_ops_day",
	"agent_mission_ops_day",
	"agent_campaign_ops_day",
	"combat_inspect_stack_day",
	"phase_ribbon_inspect_day",
	"joint_timeline_inspect_day",
	"assault_rank_inspect_day",
	"combat_campaign_ops_day",
	"fleet_hh_combat_close_day",
	"depot_logistics_day",
	"supply_route_ops_day",
	"move_path_ops_day",
	"multi_province_ops_day",
	"theater_auto_tick_day",
	"daily_supply_ops_day",
	"logistics_theater_close_day",
	"force_readiness_ops_day",
	"oob_factory_ops_day",
	"medium_equip_ops_day",
	"naval_skim_ops_day",
	"basing_logistics_ops_day",
	"production_force_ops_day",
	"force_oob_close_day",
	"player_surface_ops_day",
	"order_panel_ops_day",
	"panel_sections_ops_day",
	"tooltip_flair_ops_day",
	"apply_audit_ops_day",
	"logistics_force_panel_close_day",
	"combat_wx_ops_day",
	"prod_wx_ops_day",
	"air_sortie_wx_day",
	"morale_wx_ops_day",
	"convoy_wx_ops_day",
	"daylight_wx_ops_day",
	"weather_ops_close_day",
	"war_economy_ops_day",
	"prod_campaign_ops_day",
	"focus_wx_ops_day",
	"focus_mut_ops_day",
	"supply_economy_ops_day",
	"depot_economy_ops_day",
	"war_economy_close_day",
	"intel_counter_ops_day",
	"agent_intel_ops_day",
	"hh_counter_ops_day",
	"map_effect_ops_day",
	"coherence_intel_day",
	"weather_economy_intel_close_day",
	"multi_province_campaign_day",
	"theater_auto_campaign_day",
	"daily_command_ops_day",
	"theater_readiness_ops_day",
	"move_path_campaign_day",
	"theater_order_board_day",
	"theater_campaign_close_day",
	"basing_fleet_sustain_day",
	"fleet_wx_sustain_day",
	"convoy_sustain_ops_day",
	"sealane_joint_ops_day",
	"naval_order_ops_day",
	"fleet_station_sustain_day",
	"naval_sealane_close_day",
	"player_surface_session_day",
	"order_panel_session_day",
	"mutation_feedback_ops_day",
	"apply_audit_session_day",
	"decision_strip_ops_day",
	"theater_naval_session_close_day",
	"combat_phase_ops_day",
	"assault_ready_ops_day",
	"combat_order_ops_day",
	"multi_phase_est_ops_day",
	"assault_rank_ops_day",
	"phase_ribbon_ops_day",
	"combat_phase_close_day",
	"agent_mission_campaign_day",
	"agent_dispatch_ops_day",
	"hh_commit_campaign_day",
	"counterplay_campaign_day",
	"hh_agenda_ops_day",
	"agent_hh_joint_day",
	"agent_hh_close_day",
	"joint_theater_combat_day",
	"joint_naval_combat_day",
	"focus_joint_ops_day",
	"joint_command_ops_day",
	"multi_domain_strip_day",
	"combat_agent_joint_close_day",
	"prod_factory_risk_ops_day",
	"medium_equip_horizon_ops_day",
	"production_priority_ops_day",
	"oob_equip_continuity_day",
	"factory_line_ops_day",
	"stockpile_growth_ops_day",
	"production_oob_close_day",
	"air_sortie_front_ops_day",
	"multi_front_rank_ops_day",
	"air_land_joint_ops_day",
	"assault_front_ops_day",
	"air_forecast_ops_day",
	"multi_front_supply_ops_day",
	"air_front_close_day",
	"focus_path_ops_day",
	"war_cabinet_ops_day",
	"strategic_strip_ops_day",
	"focus_priority_ops_day",
	"strategic_continuity_ops_day",
	"prod_air_focus_close_day",
	"save_slot_integrity_ops_day",
	"autosave_session_ops_day",
	"campaign_session_ops_day",
	"save_resume_ops_day",
	"session_checkpoint_ops_day",
	"save_audit_ops_day",
	"save_session_close_day",
	"leader_assign_ops_day",
	"formation_ready_ops_day",
	"oob_assign_ops_day",
	"leader_command_ops_day",
	"formation_station_ops_day",
	"leader_formation_joint_day",
	"leader_formation_close_day",
	"trade_chain_ops_day",
	"convoy_escort_ops_day",
	"sealane_economy_ops_day",
	"trade_route_ops_day",
	"convoy_trade_joint_day",
	"save_leader_trade_close_day",
	"panel_surface_ops_day",
	"tooltip_chip_ops_day",
	"insight_budget_ops_day",
	"order_surface_ops_day",
	"product_chip_ops_day",
	"surface_refresh_ops_day",
	"inspector_surface_close_day",
	"infra_invest_ops_day",
	"special_site_ops_day",
	"construction_ops_day",
	"infra_project_ops_day",
	"investment_status_ops_day",
	"infra_site_joint_day",
	"infra_invest_close_day",
	"daily_auto_ops_day",
	"theater_tick_ops_day",
	"multi_domain_auto_ops_day",
	"daily_apply_ops_day",
	"theater_auto_joint_day",
	"inspector_infra_auto_close_day",
	"follow_on_assault_ops_day",
	"reinforced_combat_ops_day",
	"war_path_urgency_ops_day",
	"assault_follow_ops_day",
	"reinforce_step_ops_day",
	"combat_urgency_ops_day",
	"follow_reinforce_close_day",
	"choke_sea_wx_ops_day",
	"sea_zone_mod_ops_day",
	"basing_choke_ops_day",
	"choke_control_ops_day",
	"sea_zone_control_ops_day",
	"choke_basing_joint_day",
	"choke_sea_close_day",
	"agent_escalation_ops_day",
	"coverage_ops_day",
	"counter_ops_board_ops_day",
	"escalation_ladder_ops_day",
	"agent_coverage_joint_day",
	"assault_choke_agent_close_day",
	"equip_horizon_depth_day",
	"stockpile_line_ops_day",
	"oob_line_continuity_day",
	"factory_oob_depth_day",
	"medium_horizon_plan_day",
	"equip_stockpile_joint_day",
	"equip_oob_close_day",
	"fleet_multi_theater_ops_day",
	"fleet_redeploy_ops_day",
	"task_group_posture_ops_day",
	"fleet_posture_ops_day",
	"redeploy_route_ops_day",
	"fleet_theater_joint_day",
	"fleet_redeploy_close_day",
	"hh_monthly_ops_day",
	"hh_quarterly_ops_day",
	"agenda_pulse_ops_day",
	"trail_counterplay_ops_day",
	"hh_agenda_depth_joint_day",
	"oob_fleet_hh_close_day",
	"force_readiness_depth_day",
	"multi_front_supply_depth_day",
	"depot_route_ops_day",
	"force_posture_depth_day",
	"front_supply_rank_day",
	"force_supply_joint_day",
	"force_supply_close_day",
	"weather_pressure_ops_day",
	"campaign_crisis_ops_day",
	"prod_weather_crisis_day",
	"combat_weather_ops_day",
	"weather_crisis_brief_day",
	"weather_campaign_joint_day",
	"weather_crisis_close_day",
	"focus_war_path_ops_day",
	"strategic_strip_depth_day",
	"strategic_continuity_depth_day",
	"war_cabinet_pulse_ops_day",
	"focus_continuity_joint_day",
	"force_weather_focus_close_day",
	"air_sortie_depth_day",
	"air_land_joint_depth_day",
	"multi_domain_ops_day",
	"air_front_readiness_day",
	"domain_joint_ops_day",
	"air_land_campaign_day",
	"air_domain_close_day",
	"convoy_escort_depth_day",
	"sealane_health_ops_day",
	"trade_pressure_ops_day",
	"convoy_sealane_joint_day",
	"sealane_logistics_ops_day",
	"wartime_trade_ops_day",
	"convoy_sealane_close_day",
	"order_execute_depth_day",
	"map_effect_resolve_day",
	"next_day_feedback_depth_day",
	"order_effect_joint_day",
	"feedback_loop_ops_day",
	"air_convoy_order_close_day",
	"leader_assign_depth_day",
	"formation_ready_depth_day",
	"leader_weather_depth_day",
	"formation_station_depth_day",
	"leader_formation_joint_depth_day",
	"oob_leader_ops_day",
	"leader_formation_close_depth_day",
	"intel_counter_depth_day",
	"hh_counterplay_depth_day",
	"agent_response_depth_day",
	"trail_intel_ops_day",
	"counterintel_board_ops_day",
	"intel_response_joint_day",
	"intel_counter_close_day",
	"theater_daily_depth_day",
	"multi_province_rank_depth_day",
	"daily_auto_depth_day",
	"theater_brief_ops_day",
	"multi_province_command_day",
	"leader_intel_theater_close_day",
	"save_slot_depth_day",
	"autosave_session_depth_day",
	"campaign_session_depth_day",
	"save_resume_depth_day",
	"session_checkpoint_depth_day",
	"save_audit_depth_day",
	"save_session_close_depth_day",
	"factory_risk_surge_day",
	"production_priority_depth_day",
	"stockpile_surge_ops_day",
	"line_continuity_depth_day",
	"industry_surge_joint_day",
	"production_oob_depth_day",
	"production_surge_close_day",
	"multi_phase_estimate_depth_day",
	"assault_ready_surface_day",
	"combat_order_surface_day",
	"phase_product_ops_day",
	"multi_phase_joint_day",
	"save_prod_combat_close_day",
	"naval_basing_sustain_day",
	"port_fuel_depth_day",
	"basing_repair_depth_day",
	"fleet_task_sustain_day",
	"convoy_basing_joint_day",
	"naval_logistics_depth_day",
	"naval_basing_close_day",
	"multi_day_theater_depth_day",
	"theater_campaign_continuity_day",
	"campaign_day_chain_day",
	"theater_session_ops_day",
	"daily_theater_sustain_day",
	"theater_continuity_joint_day",
	"theater_campaign_depth_close_day",
	"inspector_decision_depth_day",
	"decision_strip_depth_day",
	"insight_strip_depth_day",
	"province_decision_joint_day",
	"inspector_campaign_ops_day",
	"theater_naval_inspector_close_day",
	"weather_pressure_depth_day",
	"foul_combat_ops_day",
	"weather_logistics_depth_day",
	"weather_move_depth_day",
	"weather_crisis_depth_day",
	"weather_pressure_joint_day",
	"weather_ops_close_depth_day",
	"trade_pressure_depth_day",
	"sealane_health_depth_day",
	"war_economy_sustain_day",
	"stockpile_economy_depth_day",
	"convoy_economy_joint_day",
	"trade_sealane_joint_day",
	"war_economy_close_depth_day",
	"force_ready_surface_day",
	"formation_equip_depth_day",
	"reinforce_stockpile_depth_day",
	"readiness_board_ops_day",
	"force_reinforce_joint_day",
	"weather_economy_force_close_day",
	"strategic_ai_doctrine_depth_day",
	"strategic_ai_urgency_board_day",
	"strategic_ai_player_skip_day",
	"strategic_ai_budget_depth_day",
	"strategic_ai_domain_weight_day",
	"strategic_ai_daily_joint_day",
	"strategic_ai_campaign_close_day",
	"designer_catalog_depth_day",
	"designer_seed_production_day",
	"designer_domain_balance_day",
	"oob_horizon_joint_day",
	"production_line_bootstrap_day",
	"industry_design_joint_day",
	"designer_industry_close_day",
	"theater_ai_command_joint_day",
	"fleet_ai_campaign_depth_day",
	"agent_ai_campaign_depth_day",
	"combat_ai_phase_depth_day",
	"save_session_ai_joint_day",
	"full_game_campaign_close_day",
	"air_ops_sortie_depth_day",
	"air_forecast_planning_depth_day",
	"air_sortie_weather_gate_day",
	"convoy_escort_campaign_depth_day",
	"air_land_campaign_depth_day",
	"air_front_readiness_depth_day",
	"air_convoy_campaign_close_day",
	"focus_pick_depth_day",
	"focus_order_path_day",
	"focus_war_path_depth_day",
	"war_path_urgency_depth_day",
	"intel_counter_depth_campaign_day",
	"leader_campaign_assign_day",
	"focus_intel_leader_close_day",
	"order_execute_session_day",
	"next_day_feedback_session_day",
	"campaign_decision_session_day",
	"theater_ai_session_joint_day",
	"force_readiness_session_day",
	"play_session_campaign_close_day",
	"apply_supply",
]


func _ready() -> void:
	name = "OrderCommandPanel"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(680, 560)
	offset_left = -340
	offset_top = -280
	offset_right = 340
	offset_bottom = 280
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var tag := str(LeaderManager.get_player_country_tag()).to_upper()
		if not tag.is_empty():
			country_tag = tag
	_build_ui()
	_connect_map_selection()
	# Defer heavy rebuild so the panel paints before catalogue build (avoids freeze on open).
	call_deferred("_deferred_first_refresh")


func _deferred_first_refresh() -> void:
	if not is_inside_tree():
		return
	refresh()


func _exit_tree() -> void:
	if _map_select_connected and typeof(MapManager) != TYPE_NIL:
		if MapManager.province_selected.is_connected(_on_map_province_selected):
			MapManager.province_selected.disconnect(_on_map_province_selected)
	_map_select_connected = false


func _connect_map_selection() -> void:
	if typeof(MapManager) == TYPE_NIL:
		return
	if not MapManager.province_selected.is_connected(_on_map_province_selected):
		MapManager.province_selected.connect(_on_map_province_selected)
		_map_select_connected = true


func _on_map_province_selected(pid: int) -> void:
	if pid < 0:
		return
	province_id = pid
	# Ensure id is in options
	if not _province_ids.has(pid):
		_province_ids.insert(0, pid)
	refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.12, 0.97)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 8
	root.offset_right = -12
	root.offset_bottom = -12
	add_child(root)

	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	_title = Label.new()
	_title.text = "Theater Command Center"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.pressed.connect(refresh)
	title_row.add_child(_refresh_btn)
	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.pressed.connect(queue_free)
	title_row.add_child(_close_btn)

	var prov_row := HBoxContainer.new()
	root.add_child(prov_row)
	var prov_lbl := Label.new()
	prov_lbl.text = "Province:"
	prov_row.add_child(prov_lbl)
	_province_option = OptionButton.new()
	_province_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_province_option.item_selected.connect(_on_province_selected)
	prov_row.add_child(_province_option)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_result)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sections)
	_body = _sections

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.scroll_active = false
	_log_label.custom_minimum_size = Vector2(0, 90)
	root.add_child(_log_label)

	if typeof(RetrowaveTheme) != TYPE_NIL:
		# Static theme helpers (do not call has_method on class_name — Godot 4 parse error).
		RetrowaveTheme.style_title(_title, RetrowaveTheme.CYAN)
		RetrowaveTheme.style_secondary_button(_close_btn)
		RetrowaveTheme.style_secondary_button(_refresh_btn)


func _province_label(pid: int) -> String:
	var pname := ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
		var p = MapManager.get_province(pid)
		if p != null and "name" in p:
			pname = str(p.name).strip_edges()
	if pname.is_empty():
		return "Province #%d" % pid
	return "%s (#%d)" % [pname, pid]


func _on_province_selected(idx: int) -> void:
	if idx < 0 or idx >= _province_ids.size():
		return
	province_id = int(_province_ids[idx])
	_rebuild_all_sections()


func refresh() -> void:
	_province_ids.clear()
	_province_option.clear()
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("collect_live_theater_province_ids"):
		var ids: Array = MapManager.collect_live_theater_province_ids(country_tag, 12)
		for pid in ids:
			_province_ids.append(int(pid))
	if province_id >= 0 and not _province_ids.has(province_id):
		_province_ids.insert(0, province_id)
	if _province_ids.is_empty():
		_province_ids.append(province_id if province_id >= 0 else 1)
	var sel_idx := 0
	for i in range(_province_ids.size()):
		var pid := int(_province_ids[i])
		_province_option.add_item(_province_label(pid), i)
		if pid == province_id:
			sel_idx = i
	province_id = int(_province_ids[sel_idx])
	_province_option.select(sel_idx)
	_status.text = "Country %s · %s · %d live targets" % [
		country_tag, _province_label(province_id), _province_ids.size()
	]
	if _last_result.is_empty():
		_result.text = "Last result: (none yet — apply an action)"
	else:
		_result.text = "Last result: %s → %s" % [
			str(_last_result.get("action_id", "?")),
			"OK" if bool(_last_result.get("ok", false)) else str(_last_result.get("reason", "blocked")),
		]
	_rebuild_all_sections()
	var log_plain := ""
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_command_result_log_plain"):
		log_plain = str(GameData.format_command_result_log_plain(5))
	if log_plain.is_empty():
		_log_label.text = "[color=#8899aa]Command log empty.[/color]"
	else:
		_log_label.text = "[color=#5ec8ff]Command results[/color]\n" + log_plain


func _clear_body() -> void:
	for c in _body.get_children():
		c.queue_free()


func _target_body() -> VBoxContainer:
	return _active_body if _active_body != null else _body


func _add_section_title(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	_target_body().add_child(lbl)


func _add_plain_label(text: String, max_len: int = 280) -> void:
	var cl := Label.new()
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var t := text.strip_edges()
	if t.length() > max_len:
		t = t.substr(0, max_len) + "…"
	cl.text = t if not t.is_empty() else "(empty)"
	_target_body().add_child(cl)


func _add_apply_button(label: String, action_id: String, enabled: bool = true) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.text = label
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = "Apply"
	btn.disabled = not enabled
	btn.pressed.connect(_on_action_pressed.bind(action_id))
	row.add_child(btn)
	_target_body().add_child(row)


## Collapsible section: toggle header + body VBox. Returns body for nested content.
func _add_collapsible_section(title: String, section_id: String, start_expanded: bool = true, action_count: int = 0) -> VBoxContainer:
	var sid := section_id.strip_edges()
	if sid.is_empty():
		sid = title.strip_edges().to_lower().replace(" ", "_")
	var expanded := start_expanded
	if _section_expanded.has(sid):
		expanded = bool(_section_expanded[sid])
	else:
		_section_expanded[sid] = expanded
	var header := Button.new()
	var mark := "▼" if expanded else "▶"
	var count_bit := " (%d)" % action_count if action_count > 0 else ""
	header.text = "%s %s%s" % [mark, title, count_bit]
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(header)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.visible = expanded
	_body.add_child(body)
	header.pressed.connect(_on_section_toggle.bind(sid, header, body, title, action_count))
	return body


func _on_section_toggle(section_id: String, header: Button, body: VBoxContainer, title: String, action_count: int) -> void:
	var now := not body.visible
	body.visible = now
	_section_expanded[section_id] = now
	var mark := "▼" if now else "▶"
	var count_bit := " (%d)" % action_count if action_count > 0 else ""
	header.text = "%s %s%s" % [mark, title, count_bit]
	if now:
		_ensure_lazy_section_content(section_id, body)


func _ensure_lazy_section_content(section_id: String, body: VBoxContainer) -> void:
	if body == null:
		return
	if bool(body.get_meta("lazy_filled", false)):
		return
	match section_id:
		"extended_primary":
			_clear_container_children(body)
			_active_body = body
			_fill_extended_primary_packages()
			_active_body = null
			body.set_meta("lazy_filled", true)
		"campaign_depth_majors":
			_clear_container_children(body)
			_active_body = body
			_fill_campaign_depth_majors()
			_active_body = null
			body.set_meta("lazy_filled", true)
		_:
			pass


func _clear_container_children(node: Node) -> void:
	if node == null:
		return
	while node.get_child_count() > 0:
		var c: Node = node.get_child(0)
		node.remove_child(c)
		c.free()


func _rebuild_all_sections() -> void:
	_active_body = null
	_clear_body()
	_rebuild_orders_section()
	_rebuild_combat_section()
	_rebuild_fleet_section()
	_rebuild_hh_section()
	_rebuild_agent_section()
	_rebuild_industry_section()
	_rebuild_saves_section()
	_rebuild_gpu_section()


## Campaign Alpha primary strip — always visible (Tier A playability).
## EOA_PLAY_STRIP: player mode shows Assault/Production/War path only; harness duals in debug.
func _rebuild_campaign_alpha_primary_strip() -> void:
	# Player-first strip (always). Harness dual ribbon only in debug builds.
	_rebuild_play_mode_strip()
	if OS.is_debug_build():
		_rebuild_harness_debug_strip()
	## Extended primary packages — lazy-load on expand (prevents freeze on open).
	var ext_body := _add_collapsible_section(
		"Extended primary packages (expand to load)",
		"extended_primary",
		false,
		0,
	)
	if bool(_section_expanded.get("extended_primary", false)):
		_active_body = ext_body
		_fill_extended_primary_packages()
		_active_body = null
		ext_body.set_meta("lazy_filled", true)
	else:
		_active_body = ext_body
		_add_plain_label("Expand to load Stream α, fleet, research, economy, and more packages.", 200)
		_active_body = null


## EOA_PLAY_STRIP — first-session play actions only (order_panel_play_strip_product).
func _rebuild_play_mode_strip() -> void:
	_add_section_title("— Play commands —")
	_add_plain_label(
		"Assault · Production · Station · Save · WarLoop/Fronts/G on map · Ctrl+click enemy to attack",
		280
	)
	_add_apply_button("[2] Assault", "apply_assault", true)
	_add_play_strip_production_button()
	_add_apply_button("[1] Station forces", "apply_station", true)
	_add_apply_button("[8] Checkpoint save", "save_resume_checkpoint", true)
	var rec: Dictionary = {}
	if typeof(PlayNextHook) != TYPE_NIL:
		var living := "GER"
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
			var pt := str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
			if not pt.is_empty():
				living = pt
		rec = PlayNextHook.recommend(living)
	var rec_hint := str(rec.get("hint", "Unpause a day"))
	var rec_label := "Next: %s" % str(rec.get("label", "Unpause a day"))
	_add_plain_label(rec_hint, 220)
	var rec_btn := Button.new()
	rec_btn.text = rec_label
	rec_btn.focus_mode = Control.FOCUS_NONE
	rec_btn.tooltip_text = rec_hint
	rec_btn.pressed.connect(func() -> void:
		if typeof(PlayNextHook) != TYPE_NIL:
			var out: Dictionary = PlayNextHook.apply(rec)
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug(str(out.get("summary", rec_hint)))
	)
	_target_body().add_child(rec_btn)
	# Map surface shortcuts (toast + MapRenderer when present)
	var map_row := HBoxContainer.new()
	_target_body().add_child(map_row)
	_add_map_surface_button(map_row, "WarLoop (Shift+I)", "show_first_session_war_path")
	_add_map_surface_button(map_row, "Fronts (B)", "show_live_border_fronts")
	_add_map_surface_button(map_row, "Corridor (G)", "highlight_corridor_capital_to_selected")


## Player-mode Production — living factory board, not apply_production dual.
func _add_play_strip_production_button() -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.text = "[3] Production"
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = "Open"
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "Living factory board for the player tag"
	btn.pressed.connect(_open_play_strip_production)
	row.add_child(btn)
	_target_body().add_child(row)


func _open_play_strip_production() -> void:
	var tree := get_tree()
	var bar: Node = null
	if tree != null:
		bar = tree.get_first_node_in_group("top_info_bar")
	if bar != null and bar.has_method("open_living_surface"):
		bar.call("open_living_surface", "production")
		return
	if typeof(PlayNextHook) != TYPE_NIL:
		PlayNextHook.open_living_production()


func _add_map_surface_button(parent: Control, label: String, method_name: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 26)
	btn.pressed.connect(func() -> void:
		_invoke_map_surface(method_name)
	)
	parent.add_child(btn)


func _invoke_map_surface(method_name: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var mr: Node = tree.get_first_node_in_group("map_renderer") if tree.has_method("get_first_node_in_group") else null
	if mr == null and tree.current_scene != null:
		mr = tree.current_scene.find_child("MapRenderer", true, false)
	if mr != null and mr.has_method(method_name):
		mr.call(method_name)
		return
	# Godot 4.7: has_method() is instance-only on class_name; toast_map_debug is static.
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Map surface %s unavailable" % method_name)


## Debug / dual harness residual buttons — not player primary path.
func _rebuild_harness_debug_strip() -> void:
	_add_section_title("— Debug harness (debug build) —")
	var alpha: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_alpha_primary_strip_product_live"):
		alpha = MapManager.campaign_alpha_primary_strip_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		alpha = MapPolishFormatters.campaign_alpha_primary_strip_product(province_id)
	if not alpha.is_empty() and not bool(alpha.get("empty", false)):
		_add_plain_label(str(alpha.get("summary", "")), 200)
	_add_apply_button("Run Stream α packs (C/E/F/G)", "stream_alpha_primary_packs_product", true)
	_add_apply_button("Run Campaign Alpha primary strip", "campaign_alpha_primary_strip_product", true)
	_add_apply_button("Refresh recommended next", "campaign_alpha_recommend_next", true)
	_add_apply_button("Run dead-button audit", "campaign_alpha_dead_audit", true)
	_add_apply_button("[A] Approach", "phase_approach", true)
	_add_apply_button("[E] Engage", "phase_engage", true)
	_add_apply_button("[D] Disengage", "phase_disengage", true)
	_add_apply_button("Advance combat ops (close-live)", "combat_ops_close", true)
	_add_apply_button("HH agenda advance (close-live)", "hh_agenda_close", true)
	_add_apply_button("War goal board", "war_goal_board", true)
	_add_apply_button("Multi-front weekly", "multi_front_weekly", true)
	_add_apply_button("Personality drive", "personality_drive", true)
	_add_apply_button("Naval ops advance (Pack D)", "naval_ops_close", true)
	_add_apply_button("Save checkpoint (product)", "save_browser_checkpoint", true)
	_add_apply_button("Save resume (product)", "save_browser_resume", true)



## Stream α primary player-command package — C1 combat / P1 OOB / S1 save / L1 HH.

## Lazy-filled extended primary command packages (opened on demand).
func _fill_extended_primary_packages() -> void:
	## Stream α primary command package (C1/P1/S1/L1) — always-expanded primary surface
	_rebuild_stream_alpha_primary_command()
	## Fleet autonomy primary command package (C2/A2 F0–F3) — near naval / stream alpha
	_rebuild_fleet_autonomy_primary_command()
	## Di1 peace conference primary command package (open/claim/cede/puppet/close)
	_rebuild_peace_conference_primary_command()
	## O1 occupation primary command package (mapmode/law/garrison/pulse/close)
	_rebuild_occupation_primary_command()
	## T1 research queue primary command package (open→enqueue→gate→advance→close)
	_rebuild_research_queue_primary_command()
	## I1 agent mission board primary command package (board→dispatch→resolve→counter→close)
	_rebuild_agent_mission_board_primary_command()
	## E1 war economy primary command package (board→convert war/civ→stockpile→close)
	_rebuild_war_economy_primary_command()
	_rebuild_air_theater_primary_command()
	_rebuild_battle_aar_primary_command()
	_rebuild_command_journal_primary_command()
	_rebuild_map_perf_measured_primary_command()
	_rebuild_war_goal_alliance_primary_command()
	_rebuild_factory_retool_primary_command()
	_rebuild_tutorial_first_session_primary_command()
	_rebuild_multi_faction_ai_primary_command()
	_rebuild_weather_theater_primary_command()
	_rebuild_manpower_laws_primary_command()
	_rebuild_focus_tree_primary_command()
	_rebuild_leader_theater_primary_command()
	_rebuild_intel_network_primary_command()
	_rebuild_product_ux_primary_command()
	_rebuild_combat_intel_estimate_primary_command()
	_rebuild_convoy_sealane_primary_command()
	_rebuild_designer_suite_primary_command()
	_rebuild_autosave_session_primary_command()
	_rebuild_historical_oob_primary_command()
	_rebuild_intel_counter_primary_command()
	_rebuild_faction_personality_primary_command()
	_rebuild_production_honesty_primary_command()
	_rebuild_hh_multi_month_primary_command()
	_rebuild_logistics_supply_primary_command()
	_rebuild_front_continuity_primary_command()
	_rebuild_designer_depth_primary_command()
	_rebuild_air_multi_phase_primary_command()
	_rebuild_inspector_decision_primary_command()
	_rebuild_balance_combat_supply_primary_command()
	_rebuild_fleet_multi_day_primary_command()
	_rebuild_agent_campaign_primary_command()
	_rebuild_grand_strategy_cycle_primary_command()
	_rebuild_world_class_primary_command()
	_rebuild_multi_front_primary_command()
	_rebuild_strategic_war_goal_primary_command()
	_rebuild_naval_search_strike_primary_command()
	_rebuild_weather_crisis_primary_command()
	_rebuild_campaign_ai_multi_month_primary_command()
	_rebuild_tech_research_primary_command()
	_rebuild_focus_war_path_primary_command()
	_rebuild_naval_multi_phase_primary_command()
	_rebuild_diplomacy_peace_primary_command()
	_rebuild_save_resume_primary_command()
	_rebuild_play_session_primary_command()
	_rebuild_ai_difficulty_primary_command()
	_rebuild_hotseat_session_primary_command()
	_rebuild_pack_n_era_primary_command()
	_rebuild_pack_n_events_primary_command()
	_rebuild_hoi_panel_primary_command()
	_rebuild_q1_validator_primary_command()
	_rebuild_combat_production_partial_primary_command()
	_rebuild_pack_n_narrative_primary_command()
	_rebuild_hoi_screen_primary_command()
	_rebuild_q1_checklist_primary_command()
	_rebuild_combat_production_depth_primary_command()
	_rebuild_n3_preflight_primary_command()
	_rebuild_pack_n_content_primary_command()
	_rebuild_hoi_fullscreen_primary_command()
	_rebuild_q1_rc_checklist_primary_command()
	_rebuild_combat_engine_depth_primary_command()
	_rebuild_resource_production_primary_command()
	_rebuild_resource_harvest_primary_command()
	_rebuild_resource_economy_depth_primary_command()
	_rebuild_resource_open_items_primary_command()
	_rebuild_trade_relations_primary_command()
	_rebuild_trade_power_intel_primary_command()

func _rebuild_stream_alpha_primary_command() -> void:
	_add_section_title("— Stream α primary command (C1/P1/S1/L1) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("stream_alpha_primary_command_product_live"):
		cmd = MapManager.stream_alpha_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.stream_alpha_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("Stream α primary command (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	var majors_ok: Dictionary = cmd.get("majors_ok", {}) if cmd.get("majors_ok") is Dictionary else {}
	_add_plain_label(
		"Majors: C1 combat %s · P1 OOB %s · S1 save %s · L1 HH %s · dead %d"
		% [
			"OK" if bool(majors_ok.get("combat_primary_ribbon", false)) else "—",
			"OK" if bool(majors_ok.get("oob_primary_honesty", false)) else "—",
			"OK" if bool(majors_ok.get("save_primary_browser", false)) else "—",
			"OK" if bool(majors_ok.get("hh_primary_agenda", false)) else "—",
			int(cmd.get("dead_n", 0)),
		],
		280
	)
	_add_apply_button("Run Stream α primary command (full package)", "stream_alpha_primary_command_product", true)
	_add_apply_button("[C1] Combat ribbon advance", "apply_stream_alpha_combat", true)
	_add_apply_button("[P1] Medium OOB honesty", "apply_stream_alpha_oob", true)
	_add_apply_button("[S1] Save browser list", "apply_stream_alpha_save", true)
	_add_apply_button("[L1] HH agenda advance", "apply_stream_alpha_hh", true)
	_add_apply_button("OOB 60d horizon", "apply_oob_horizon_60d", true)
	_add_apply_button("OOB 100d horizon", "apply_oob_horizon_100d", true)
	_add_apply_button("Save resume", "apply_save_browser_resume", true)
	_add_apply_button("Save checkpoint", "apply_save_browser_checkpoint", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_stream_alpha_primary_command_product_plain"):
		var sp := str(GameData.format_stream_alpha_primary_command_product_plain(province_id)).strip_edges()
		if not sp.is_empty():
			_add_plain_label(sp, 240)


## Fleet multi-day autonomy primary command package — C2/A2 F0 posture / F1 station / F2 follow / F3 close.
func _rebuild_fleet_autonomy_primary_command() -> void:
	_add_section_title("— Fleet autonomy primary command (C2/A2 F0–F3) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_autonomy_primary_command_product_live"):
		cmd = MapManager.fleet_autonomy_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.fleet_autonomy_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("Fleet autonomy primary command (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	var majors_ok: Dictionary = cmd.get("majors_ok", {}) if cmd.get("majors_ok") is Dictionary else {}
	_add_plain_label(
		"Majors: F0 posture %s · F1 station %s · F2 follow %s · F3 close %s · dead %d"
		% [
			"OK" if bool(majors_ok.get("fleet_primary_posture", false)) else "—",
			"OK" if bool(majors_ok.get("fleet_primary_station_escort", false)) else "—",
			"OK" if bool(majors_ok.get("fleet_primary_follow_through", false)) else "—",
			"OK" if bool(majors_ok.get("fleet_primary_autonomy_close", false)) else "—",
			int(cmd.get("dead_n", 0)),
		],
		280
	)
	_add_apply_button("Run fleet autonomy primary command (full package)", "fleet_autonomy_primary_command_product", true)
	_add_apply_button("[F0] Day 0 posture / tasking", "apply_fleet_autonomy_posture", true)
	_add_apply_button("[F1] Day 1 station + escort", "apply_fleet_autonomy_station", true)
	_add_apply_button("[F2] Day 2 multi-day follow-through", "apply_fleet_autonomy_follow", true)
	_add_apply_button("[F3] Fleet autonomy close (naval ops)", "apply_fleet_autonomy_close", true)
	_add_apply_button("Fleet multi-day product", "fleet_multi_day_autonomy_product", true)
	_add_apply_button("Fleet multi-day sequence", "fleet_multi_day_sequence", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_fleet_autonomy_primary_command_product_plain"):
		var fp := str(GameData.format_fleet_autonomy_primary_command_product_plain(province_id)).strip_edges()
		if not fp.is_empty():
			_add_plain_label(fp, 240)


## Di1 multi-party peace conference primary command — open / claim / cede / puppet / close.
func _rebuild_peace_conference_primary_command() -> void:
	_add_section_title("— Peace conference primary command (Di1 open→close) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("peace_conference_primary_command_product_live"):
		cmd = MapManager.peace_conference_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.peace_conference_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("Peace conference primary command (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	var majors_ok: Dictionary = cmd.get("majors_ok", {}) if cmd.get("majors_ok") is Dictionary else {}
	_add_plain_label(
		"Majors: open %s · claim %s · cede %s · puppet %s · close %s · dead %d"
		% [
			"OK" if bool(majors_ok.get("peace_primary_open", false)) else "—",
			"OK" if bool(majors_ok.get("peace_primary_claim", false)) else "—",
			"OK" if bool(majors_ok.get("peace_primary_cede", false)) else "—",
			"OK" if bool(majors_ok.get("peace_primary_puppet", false)) else "—",
			"OK" if bool(majors_ok.get("peace_primary_close", false)) else "—",
			int(cmd.get("dead_n", 0)),
		],
		280
	)
	_add_apply_button("Run peace conference primary command (full package)", "peace_conference_primary_command_product", true)
	_add_apply_button("[Di1] Open multi-party board", "apply_peace_primary_open", true)
	_add_apply_button("[Di1] Claim province (annex)", "apply_peace_primary_claim", true)
	_add_apply_button("[Di1] Cede province (occupation zone)", "apply_peace_primary_cede", true)
	_add_apply_button("[Di1] Puppet tag demand", "apply_peace_primary_puppet", true)
	_add_apply_button("[Di1] Close conference settle", "apply_peace_primary_close", true)
	_add_apply_button("Multi-party peace product", "multi_party_peace_conference_product", true)
	_add_apply_button("Peace settlement product", "peace_conference_settlement_product", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_peace_conference_primary_command_product_plain"):
		var pp := str(GameData.format_peace_conference_primary_command_product_plain(province_id)).strip_edges()
		if not pp.is_empty():
			_add_plain_label(pp, 240)


## O1 occupation primary command — mapmode / law / garrison / R+C pulse / close.
func _rebuild_occupation_primary_command() -> void:
	_add_section_title("— Occupation primary command (O1 mapmode→close) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_primary_command_product_live"):
		cmd = MapManager.occupation_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.occupation_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("Occupation primary command (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	var majors_ok: Dictionary = cmd.get("majors_ok", {}) if cmd.get("majors_ok") is Dictionary else {}
	_add_plain_label(
		"Majors: mapmode %s · law %s · garrison %s · pulse %s · close %s · dead %d"
		% [
			"OK" if bool(majors_ok.get("occupation_primary_mapmode", false)) else "—",
			"OK" if bool(majors_ok.get("occupation_primary_law", false)) else "—",
			"OK" if bool(majors_ok.get("occupation_primary_garrison", false)) else "—",
			"OK" if bool(majors_ok.get("occupation_primary_rc_pulse", false)) else "—",
			"OK" if bool(majors_ok.get("occupation_primary_close", false)) else "—",
			int(cmd.get("dead_n", 0)),
		],
		280
	)
	_add_apply_button("Run occupation primary command (full package)", "occupation_primary_command_product", true)
	_add_apply_button("[O1] Mapmode / R+C surface", "apply_occupation_primary_mapmode", true)
	_add_apply_button("[O1] Set occupation law", "apply_occupation_primary_law", true)
	_add_apply_button("[O1] Deploy garrison", "apply_occupation_primary_garrison", true)
	_add_apply_button("[O1] R/C daily pulse", "apply_occupation_primary_rc_pulse", true)
	_add_apply_button("[O1] Occupation package close", "apply_occupation_primary_close", true)
	_add_apply_button("Occupation resistance product", "occupation_resistance_compliance_product", true)
	_add_apply_button("Occupation revolt/garrison product", "occupation_revolt_garrison_product", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_occupation_primary_command_product_plain"):
		var op := str(GameData.format_occupation_primary_command_product_plain(province_id)).strip_edges()
		if not op.is_empty():
			_add_plain_label(op, 240)


## T1 research queue primary command — open queue / enqueue branch / gate / advance month / close.
func _rebuild_research_queue_primary_command() -> void:
	_add_section_title("— Research queue primary command (T1 open→close) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("research_queue_primary_command_product_live"):
		cmd = MapManager.research_queue_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.research_queue_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("Research queue primary command (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	var majors_ok: Dictionary = cmd.get("majors_ok", {}) if cmd.get("majors_ok") is Dictionary else {}
	_add_plain_label(
		"Majors: open %s · enqueue %s · gate %s · advance %s · close %s · dead %d"
		% [
			"OK" if bool(majors_ok.get("research_primary_open_queue", false)) else "—",
			"OK" if bool(majors_ok.get("research_primary_enqueue_branch", false)) else "—",
			"OK" if bool(majors_ok.get("research_primary_gate_check", false)) else "—",
			"OK" if bool(majors_ok.get("research_primary_advance_month", false)) else "—",
			"OK" if bool(majors_ok.get("research_primary_close", false)) else "—",
			int(cmd.get("dead_n", 0)),
		],
		280
	)
	_add_apply_button("Run research queue primary command (full package)", "research_queue_primary_command_product", true)
	_add_apply_button("[T1] Open research queue", "apply_research_primary_open_queue", true)
	_add_apply_button("[T1] Enqueue branch path", "apply_research_primary_enqueue_branch", true)
	_add_apply_button("[T1] Gate check / branch locks", "apply_research_primary_gate_check", true)
	_add_apply_button("[T1] Advance research month", "apply_research_primary_advance_month", true)
	_add_apply_button("[T1] Research queue close", "apply_research_primary_close", true)
	_add_apply_button("Tech research campaign product", "tech_research_campaign_product", true)
	_add_apply_button("Tech tree branching product", "tech_tree_branching_product", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_research_queue_primary_command_product_plain"):
		var rp := str(GameData.format_research_queue_primary_command_product_plain(province_id)).strip_edges()
		if not rp.is_empty():
			_add_plain_label(rp, 240)


## I1 agent mission board primary command — board / dispatch / resolve / counter-intel / close.
func _rebuild_agent_mission_board_primary_command() -> void:
	_add_section_title("— Agent mission board primary command (I1 board→close) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_mission_board_primary_command_product_live"):
		cmd = MapManager.agent_mission_board_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.agent_mission_board_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("Agent mission board primary command (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	var majors_ok: Dictionary = cmd.get("majors_ok", {}) if cmd.get("majors_ok") is Dictionary else {}
	_add_plain_label(
		"Majors: board %s · dispatch %s · resolve %s · counter %s · close %s · dead %d"
		% [
			"OK" if bool(majors_ok.get("agent_primary_board_surface", false)) else "—",
			"OK" if bool(majors_ok.get("agent_primary_dispatch", false)) else "—",
			"OK" if bool(majors_ok.get("agent_primary_resolve", false)) else "—",
			"OK" if bool(majors_ok.get("agent_primary_counter_intel", false)) else "—",
			"OK" if bool(majors_ok.get("agent_primary_close", false)) else "—",
			int(cmd.get("dead_n", 0)),
		],
		280
	)
	_add_apply_button("Run agent mission board primary command (full package)", "agent_mission_board_primary_command_product", true)
	_add_apply_button("[I1] Mission board surface", "apply_agent_primary_board_surface", true)
	_add_apply_button("[I1] Dispatch mission", "apply_agent_primary_dispatch", true)
	_add_apply_button("[I1] Resolve missions", "apply_agent_primary_resolve", true)
	_add_apply_button("[I1] Counter-intel / sweep", "apply_agent_primary_counter_intel", true)
	_add_apply_button("[I1] Mission board close", "apply_agent_primary_close", true)
	_add_apply_button("Agent campaign product", "agent_campaign_product", true)
	_add_apply_button("Intelligence network product", "intelligence_network_product", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_agent_mission_board_primary_command_product_plain"):
		var ap := str(GameData.format_agent_mission_board_primary_command_product_plain(province_id)).strip_edges()
		if not ap.is_empty():
			_add_plain_label(ap, 240)


## E1 war economy primary command — board / convert_to_war / convert_to_civ / stockpile / close.
func _rebuild_war_economy_primary_command() -> void:
	_add_section_title("— War economy primary command (E1 board→close) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_primary_command_product_live"):
		cmd = MapManager.war_economy_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.war_economy_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("War economy primary command (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	var majors_ok: Dictionary = cmd.get("majors_ok", {}) if cmd.get("majors_ok") is Dictionary else {}
	_add_plain_label(
		"Majors: board %s · war %s · civ %s · stockpile %s · close %s · dead %d"
		% [
			"OK" if bool(majors_ok.get("war_economy_primary_board", false)) else "—",
			"OK" if bool(majors_ok.get("war_economy_primary_convert_to_war", false)) else "—",
			"OK" if bool(majors_ok.get("war_economy_primary_convert_to_civ", false)) else "—",
			"OK" if bool(majors_ok.get("war_economy_primary_stockpile_check", false)) else "—",
			"OK" if bool(majors_ok.get("war_economy_primary_close", false)) else "—",
			int(cmd.get("dead_n", 0)),
		],
		280
	)
	_add_apply_button("Run war economy primary command (full package)", "war_economy_primary_command_product", true)
	_add_apply_button("[E1] Civilian / industry board", "apply_war_economy_primary_board", true)
	_add_apply_button("[E1] Convert civilian → war", "apply_war_economy_primary_convert_to_war", true)
	_add_apply_button("[E1] Convert war → civilian", "apply_war_economy_primary_convert_to_civ", true)
	_add_apply_button("[E1] Stockpile multi-month check", "apply_war_economy_primary_stockpile_check", true)
	_add_apply_button("[E1] War economy package close", "apply_war_economy_primary_close", true)
	_add_apply_button("War economy conversion product", "war_economy_conversion_product", true)
	_add_apply_button("War economy mobilization product", "war_economy_mobilization_product", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_war_economy_primary_command_product_plain"):
		var wp := str(GameData.format_war_economy_primary_command_product_plain(province_id)).strip_edges()
		if not wp.is_empty():
			_add_plain_label(wp, 240)


func _unhandled_input(event: InputEvent) -> void:
	## Pack C — keyboard phase advance from selected province (primary path).
	if not visible or not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	## Require Ctrl so we don't steal typing/overlays
	if not ke.ctrl_pressed:
		return
	match ke.keycode:
		KEY_A:
			_on_action_pressed("phase_approach")
			get_viewport().set_input_as_handled()
		KEY_E:
			_on_action_pressed("phase_engage")
			get_viewport().set_input_as_handled()
		KEY_D:
			_on_action_pressed("phase_disengage")
			get_viewport().set_input_as_handled()
		KEY_N:
			_on_action_pressed("combat_ops_close")
			get_viewport().set_input_as_handled()


func _rebuild_orders_section() -> void:
	## Campaign Alpha: always-visible primary strip first (Tier A playability).
	_rebuild_campaign_alpha_primary_strip()
	## Collapse major catalogue noise under one section (routes remain live).
	var depth_body := _add_collapsible_section("Campaign depth (majors · collapsed)", "campaign_depth_majors", false, 0)
	if bool(_section_expanded.get("campaign_depth_majors", false)):
		_active_body = depth_body
		_fill_campaign_depth_majors()
		_active_body = null
		depth_body.set_meta("lazy_filled", true)
	else:
		_active_body = depth_body
		_add_plain_label("Expand to load campaign depth tools (keeps this panel opening instantly).", 200)
		_active_body = null
	# Ensure day-package rows attach to root body, not a nested depth body.
	_active_body = null
	# Collapsible day-package groups from pure/GD section plan (live routes preserved)
	## Campaign Alpha: max_expanded=1 to reduce day-package noise.
	var plan: Dictionary = MapPolishFormatters.order_panel_section_plan(true, 1)
	if plan.is_empty() and typeof(GameData) != TYPE_NIL and GameData.has_method("get_order_panel_section_plan"):
		plan = GameData.get_order_panel_section_plan()
	var sections: Array = plan.get("sections", []) if plan is Dictionary else []
	if sections.is_empty():
		# Fallback flat list if formatter missing
		_add_apply_button("Run integrated day ops", "day_ops_integrated", true)
		_add_apply_button("Run logistics day", "logistics_day", true)
		_add_apply_button("Run combat campaign day", "combat_campaign_day", true)
		_add_apply_button("Run fleet campaign day", "fleet_campaign_day", true)
		_add_apply_button("Run weather crisis day", "weather_crisis_day", true)
		_add_apply_button("Run agent campaign day", "agent_campaign_day", true)
		_add_apply_button("Run HH campaign day", "hh_campaign_day", true)
		_add_apply_button("Run industry surge day", "industry_surge_day", true)
	else:
		if typeof(GameData) != TYPE_NIL and GameData.has_method("format_order_panel_sections_plain"):
			var osp := str(GameData.format_order_panel_sections_plain()).strip_edges()
			if not osp.is_empty():
				_add_plain_label(osp, 180)
		for sec in sections:
			if not (sec is Dictionary):
				continue
			var sid := str(sec.get("id", "sec"))
			var title := str(sec.get("title", sid))
			var start_exp := bool(sec.get("start_expanded", false))
			var acts: Array = sec.get("actions", [])
			var body := _add_collapsible_section(title, sid, start_exp, acts.size())
			_active_body = body
			for a in acts:
				if not (a is Dictionary):
					continue
				var aid := str(a.get("action_id", ""))
				if aid.is_empty():
					continue
				_add_apply_button(str(a.get("label", aid)), aid, bool(a.get("enabled", true)))
			# One plain summary per expanded section only (cognitive load)
			if body.visible:
				_add_section_plain_for_id(sid)
			_active_body = null
	# Core order_panel_actions discoverability (compact)
	var panel: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_panel_actions_for_province"):
		panel = MapManager.order_panel_actions_for_province(province_id)
	var actions: Array = panel.get("actions", []) if panel is Dictionary else []
	if not actions.is_empty():
		var core_body := _add_collapsible_section("Core order actions", "core_orders", false, actions.size())
		_active_body = core_body
		for a in actions:
			if not (a is Dictionary):
				continue
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var order_snip := str(a.get("order", "")).strip_edges()
			if order_snip.length() > 48:
				order_snip = order_snip.substr(0, 48)
			lbl.text = "%s — %s" % [str(a.get("label", "")), order_snip]
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "Apply"
			btn.disabled = not bool(a.get("enabled", true))
			var aid2 := str(a.get("action_id", ""))
			btn.pressed.connect(_on_action_pressed.bind(aid2))
			row.add_child(btn)
			_target_body().add_child(row)
		_active_body = null
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_order_panel_surface_plain"):
		var surf := str(GameData.format_order_panel_surface_plain(province_id)).strip_edges()
		if not surf.is_empty():
			_add_plain_label(surf, 200)



## Lazy-filled campaign depth catalogue (expand section to build).
func _fill_campaign_depth_majors() -> void:
	_add_section_title("— Diplomacy peace campaign (major #16) —")
	var dip: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_peace_campaign_product_live"):
		dip = MapManager.diplomacy_peace_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		dip = MapPolishFormatters.diplomacy_peace_campaign_product(province_id)
	if not dip.is_empty() and not bool(dip.get("empty", false)):
		_add_plain_label(str(dip.get("summary", "")), 280)
		var drec: Dictionary = dip.get("recommendation", {})
		if drec is Dictionary and not str(drec.get("summary", "")).is_empty():
			_add_plain_label(str(drec.get("summary", "")), 220)
		for drow in dip.get("day_rows", []):
			if drow is Dictionary:
				_add_plain_label(str(drow.get("label", "")), 220)
		_add_apply_button("Run diplomacy peace", "diplomacy_peace_campaign_product", true)
		_add_apply_button("Diplo board", "diplomacy_peace_board", true)
		_add_apply_button("Diplo leverage", "diplomacy_peace_leverage", true)
		_add_apply_button("Diplo settle", "diplomacy_peace_settle", true)
	_add_section_title("— Tech research campaign (major #17) —")
	var tech: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_research_campaign_product_live"):
		tech = MapManager.tech_research_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		tech = MapPolishFormatters.tech_research_campaign_product(province_id)
	if not tech.is_empty() and not bool(tech.get("empty", false)):
		_add_plain_label(str(tech.get("summary", "")), 280)
		var trec: Dictionary = tech.get("recommendation", {})
		if trec is Dictionary and not str(trec.get("summary", "")).is_empty():
			_add_plain_label(str(trec.get("summary", "")), 220)
		for trow in tech.get("day_rows", []):
			if trow is Dictionary:
				_add_plain_label(str(trow.get("label", "")), 220)
		_add_apply_button("Run tech research", "tech_research_campaign_product", true)
		_add_apply_button("Tech catalog", "tech_research_catalog", true)
		_add_apply_button("Tech priority", "tech_research_priority", true)
		_add_apply_button("Tech field", "tech_research_field", true)





	_add_section_title("— Apply-queue live managers (major #28) —")
	var aql: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_live_managers_product_live"):
		aql = MapManager.apply_queue_live_managers_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		aql = MapPolishFormatters.apply_queue_live_managers_product(province_id)
	if not aql.is_empty() and not bool(aql.get("empty", false)):
		_add_plain_label(str(aql.get("summary", "")), 280)
		var arec: Dictionary = aql.get("recommendation", {})
		if arec is Dictionary and not str(arec.get("summary", "")).is_empty():
			_add_plain_label(str(arec.get("summary", "")), 220)
		for arow in aql.get("day_rows", []):
			if arow is Dictionary:
				_add_plain_label(str(arow.get("label", "")), 220)
		_add_apply_button("Run apply-queue live managers", "apply_queue_live_managers_product", true)
		_add_apply_button("Audit live leaves", "apply_queue_live_audit", true)
		_add_apply_button("Production/supply live", "apply_queue_live_production", true)
		_add_apply_button("Combat/station live prove", "apply_queue_live_combat", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_apply_queue_live_managers_product_plain"):
		var aqp := str(GameData.format_apply_queue_live_managers_product_plain(province_id)).strip_edges()
		if not aqp.is_empty():
			_add_plain_label(aqp.split("\n")[0], 260)

	_add_section_title("— Product UX command polish (major #32) —")
	var pux: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("product_ux_command_polish_product_live"):
		pux = MapManager.product_ux_command_polish_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		pux = MapPolishFormatters.product_ux_command_polish_product(province_id)
	if not pux.is_empty() and not bool(pux.get("empty", false)):
		_add_plain_label(str(pux.get("summary", "")), 280)
		var pux_rec: Dictionary = pux.get("recommendation", {})
		if pux_rec is Dictionary and not str(pux_rec.get("summary", "")).is_empty():
			_add_plain_label(str(pux_rec.get("summary", "")), 220)
		for prow in pux.get("day_rows", []):
			if prow is Dictionary:
				_add_plain_label(str(prow.get("label", "")), 220)
		_add_apply_button("Run product UX command polish", "product_ux_command_polish_product", true)
		_add_apply_button("Compact section board", "product_ux_compact_board", true)
		_add_apply_button("Top-8 always-on chips", "product_ux_top_chips", true)
		_add_apply_button("Bind primary hotkeys", "product_ux_hotkeys", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_product_ux_command_polish_product_plain"):
		var puxp := str(GameData.format_product_ux_command_polish_product_plain(province_id)).strip_edges()
		if not puxp.is_empty():
			_add_plain_label(puxp.split("\n")[0], 260)

	_add_section_title("— Historical OOB content (major #38) —")
	var hob: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("historical_oob_content_product_live"):
		hob = MapManager.historical_oob_content_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		hob = MapPolishFormatters.historical_oob_content_product(province_id)
	if not hob.is_empty() and not bool(hob.get("empty", false)):
		_add_plain_label(str(hob.get("summary", "")), 280)
		var hob_rec: Dictionary = hob.get("recommendation", {})
		if hob_rec is Dictionary and not str(hob_rec.get("summary", "")).is_empty():
			_add_plain_label(str(hob_rec.get("summary", "")), 220)
		for hrow in hob.get("day_rows", []):
			if hrow is Dictionary:
				_add_plain_label(str(hrow.get("label", "")), 220)
		_add_apply_button("Run historical OOB content", "historical_oob_content_product", true)
		_add_apply_button("OOB catalog", "historical_oob_catalog", true)
		_add_apply_button("Seed national lines", "historical_oob_seed", true)
		_add_apply_button("Equip formations", "historical_oob_equip", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_historical_oob_content_product_plain"):
		var hobp := str(GameData.format_historical_oob_content_product_plain(province_id)).strip_edges()
		if not hobp.is_empty():
			_add_plain_label(hobp.split("\n")[0], 260)

	_add_section_title("— Tech tree branching (major #39) —")
	var ttb: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_tree_branching_product_live"):
		ttb = MapManager.tech_tree_branching_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		ttb = MapPolishFormatters.tech_tree_branching_product(province_id)
	if not ttb.is_empty() and not bool(ttb.get("empty", false)):
		_add_plain_label(str(ttb.get("summary", "")), 280)
		var ttb_rec: Dictionary = ttb.get("recommendation", {})
		if ttb_rec is Dictionary and not str(ttb_rec.get("summary", "")).is_empty():
			_add_plain_label(str(ttb_rec.get("summary", "")), 220)
		for trow in ttb.get("day_rows", []):
			if trow is Dictionary:
				_add_plain_label(str(trow.get("label", "")), 220)
		_add_apply_button("Run tech tree branching", "tech_tree_branching_product", true)
		_add_apply_button("Branch catalog", "tech_tree_branches", true)
		_add_apply_button("Pick research path", "tech_tree_path", true)
		_add_apply_button("Field unlock", "tech_tree_field", true)
		_add_apply_button("Branch armor", "tech_branch_armor", true)
		_add_apply_button("Branch infantry", "tech_branch_infantry", true)
		_add_apply_button("Branch air", "tech_branch_air", true)
		_add_apply_button("Branch industry", "tech_branch_industry", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_tech_tree_branching_product_plain"):
		var ttbp := str(GameData.format_tech_tree_branching_product_plain(province_id)).strip_edges()
		if not ttbp.is_empty():
			_add_plain_label(ttbp.split("\n")[0], 260)

	_add_section_title("— Save/resume campaign (major #40) —")
	var src: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_resume_campaign_product_live"):
		src = MapManager.save_resume_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		src = MapPolishFormatters.save_resume_campaign_product(province_id)
	if not src.is_empty() and not bool(src.get("empty", false)):
		_add_plain_label(str(src.get("summary", "")), 280)
		var src_rec: Dictionary = src.get("recommendation", {})
		if src_rec is Dictionary and not str(src_rec.get("summary", "")).is_empty():
			_add_plain_label(str(src_rec.get("summary", "")), 220)
		for srow in src.get("day_rows", []):
			if srow is Dictionary:
				_add_plain_label(str(srow.get("label", "")), 220)
		_add_apply_button("Run save/resume campaign", "save_resume_campaign_product", true)
		_add_apply_button("Checkpoint board", "save_resume_checkpoint", true)
		_add_apply_button("Write slot save", "save_resume_save", true)
		_add_apply_button("Mid-war resume", "save_resume_resume", true)
		_add_apply_button("Save quicksave", "save_slot_quicksave", true)
		_add_apply_button("Save slot1", "save_slot_slot1", true)
		_add_apply_button("Load slot1", "load_slot_slot1", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_save_resume_campaign_product_plain"):
		var srcp := str(GameData.format_save_resume_campaign_product_plain(province_id)).strip_edges()
		if not srcp.is_empty():
			_add_plain_label(srcp.split("\n")[0], 260)

	_add_section_title("— Tutorial first-session (major #41) —")
	var tut: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tutorial_first_session_product_live"):
		tut = MapManager.tutorial_first_session_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		tut = MapPolishFormatters.tutorial_first_session_product(province_id)
	if not tut.is_empty() and not bool(tut.get("empty", false)):
		_add_plain_label(str(tut.get("summary", "")), 280)
		var tut_rec: Dictionary = tut.get("recommendation", {})
		if tut_rec is Dictionary and not str(tut_rec.get("summary", "")).is_empty():
			_add_plain_label(str(tut_rec.get("summary", "")), 220)
		for trow in tut.get("day_rows", []):
			if trow is Dictionary:
				_add_plain_label(str(trow.get("label", "")), 220)
		_add_apply_button("Run tutorial first-session", "tutorial_first_session_product", true)
		_add_apply_button("Session brief", "tutorial_session_brief", true)
		_add_apply_button("Guided first-week", "tutorial_session_guide", true)
		_add_apply_button("Tutorial checkpoint", "tutorial_session_checkpoint", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_tutorial_first_session_product_plain"):
		var tutp := str(GameData.format_tutorial_first_session_product_plain(province_id)).strip_edges()
		if not tutp.is_empty():
			_add_plain_label(tutp.split("\n")[0], 260)

	_add_section_title("— Focus tree content (major #42) —")
	var ftc: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_tree_content_product_live"):
		ftc = MapManager.focus_tree_content_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		ftc = MapPolishFormatters.focus_tree_content_product(province_id)
	if not ftc.is_empty() and not bool(ftc.get("empty", false)):
		_add_plain_label(str(ftc.get("summary", "")), 280)
		var ftc_rec: Dictionary = ftc.get("recommendation", {})
		if ftc_rec is Dictionary and not str(ftc_rec.get("summary", "")).is_empty():
			_add_plain_label(str(ftc_rec.get("summary", "")), 220)
		for frow in ftc.get("day_rows", []):
			if frow is Dictionary:
				_add_plain_label(str(frow.get("label", "")), 220)
		_add_apply_button("Run focus tree content", "focus_tree_content_product", true)
		_add_apply_button("Focus catalog", "focus_tree_catalog", true)
		_add_apply_button("Pick focus path", "focus_tree_path", true)
		_add_apply_button("Commit focus", "focus_tree_commit", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_focus_tree_content_product_plain"):
		var ftcp := str(GameData.format_focus_tree_content_product_plain(province_id)).strip_edges()
		if not ftcp.is_empty():
			_add_plain_label(ftcp.split("\n")[0], 260)

	_add_section_title("— Balance combat/supply (major #43) —")
	var bal: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("balance_combat_supply_product_live"):
		bal = MapManager.balance_combat_supply_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		bal = MapPolishFormatters.balance_combat_supply_product(province_id)
	if not bal.is_empty() and not bool(bal.get("empty", false)):
		_add_plain_label(str(bal.get("summary", "")), 280)
		var bal_rec: Dictionary = bal.get("recommendation", {})
		if bal_rec is Dictionary and not str(bal_rec.get("summary", "")).is_empty():
			_add_plain_label(str(bal_rec.get("summary", "")), 220)
		for brow in bal.get("day_rows", []):
			if brow is Dictionary:
				_add_plain_label(str(brow.get("label", "")), 220)
		_add_apply_button("Run balance combat/supply", "balance_combat_supply_product", true)
		_add_apply_button("Estimate board", "balance_estimate_board", true)
		_add_apply_button("Live sample", "balance_live_sample", true)
		_add_apply_button("Variance close", "balance_variance_close", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_balance_combat_supply_product_plain"):
		var balp := str(GameData.format_balance_combat_supply_product_plain(province_id)).strip_edges()
		if not balp.is_empty():
			_add_plain_label(balp.split("\n")[0], 260)


	_add_section_title("— Air multi-phase theater (major #44) —")
	var amt: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_multi_phase_theater_product_live"):
		amt = MapManager.air_multi_phase_theater_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		amt = MapPolishFormatters.air_multi_phase_theater_product(province_id)
	if not amt.is_empty() and not bool(amt.get("empty", false)):
		_add_plain_label(str(amt.get("summary", "")), 280)
		var amt_rec: Dictionary = amt.get("recommendation", {})
		if amt_rec is Dictionary and not str(amt_rec.get("summary", "")).is_empty():
			_add_plain_label(str(amt_rec.get("summary", "")), 220)
		for arow in amt.get("day_rows", []):
			if arow is Dictionary:
				_add_plain_label(str(arow.get("label", "")), 220)
		_add_apply_button("Run air multi-phase theater", "air_multi_phase_theater_product", true)
		_add_apply_button("Recon/sortie board", "air_theater_recon", true)
		_add_apply_button("Weather/CAS gate", "air_theater_cas_gate", true)
		_add_apply_button("Interdiction joint", "air_theater_interdiction", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_air_multi_phase_theater_product_plain"):
		var amtp := str(GameData.format_air_multi_phase_theater_product_plain(province_id)).strip_edges()
		if not amtp.is_empty():
			_add_plain_label(amtp.split("\n")[0], 260)

	_add_section_title("— Naval search/strike (major #45) —")
	var nss: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_search_strike_product_live"):
		nss = MapManager.naval_search_strike_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		nss = MapPolishFormatters.naval_search_strike_product(province_id)
	if not nss.is_empty() and not bool(nss.get("empty", false)):
		_add_plain_label(str(nss.get("summary", "")), 280)
		var nss_rec: Dictionary = nss.get("recommendation", {})
		if nss_rec is Dictionary and not str(nss_rec.get("summary", "")).is_empty():
			_add_plain_label(str(nss_rec.get("summary", "")), 220)
		for nrow in nss.get("day_rows", []):
			if nrow is Dictionary:
				_add_plain_label(str(nrow.get("label", "")), 220)
		_add_apply_button("Run naval search/strike", "naval_search_strike_product", true)
		_add_apply_button("Search/patrol board", "naval_search_patrol", true)
		_add_apply_button("ASW/escort phase", "naval_asw_escort", true)
		_add_apply_button("Carrier strike", "naval_carrier_strike", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_naval_search_strike_product_plain"):
		var nssp := str(GameData.format_naval_search_strike_product_plain(province_id)).strip_edges()
		if not nssp.is_empty():
			_add_plain_label(nssp.split("\n")[0], 260)

	_add_section_title("— War economy conversion (major #46) —")
	var wec: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_conversion_product_live"):
		wec = MapManager.war_economy_conversion_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		wec = MapPolishFormatters.war_economy_conversion_product(province_id)
	if not wec.is_empty() and not bool(wec.get("empty", false)):
		_add_plain_label(str(wec.get("summary", "")), 280)
		var wec_rec: Dictionary = wec.get("recommendation", {})
		if wec_rec is Dictionary and not str(wec_rec.get("summary", "")).is_empty():
			_add_plain_label(str(wec_rec.get("summary", "")), 220)
		for wrow in wec.get("day_rows", []):
			if wrow is Dictionary:
				_add_plain_label(str(wrow.get("label", "")), 220)
		_add_apply_button("Run war economy conversion", "war_economy_conversion_product", true)
		_add_apply_button("Civilian/industry board", "economy_civ_board", true)
		_add_apply_button("War conversion", "economy_war_convert", true)
		_add_apply_button("Stockpile sustain", "economy_stockpile_sustain", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_war_economy_conversion_product_plain"):
		var wecp := str(GameData.format_war_economy_conversion_product_plain(province_id)).strip_edges()
		if not wecp.is_empty():
			_add_plain_label(wecp.split("\n")[0], 260)


	_add_section_title("— Designer module editor (major #47) —")
	var dme: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_module_editor_product_live"):
		dme = MapManager.designer_module_editor_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		dme = MapPolishFormatters.designer_module_editor_product(province_id)
	if not dme.is_empty() and not bool(dme.get("empty", false)):
		_add_plain_label(str(dme.get("summary", "")), 280)
		var dme_rec: Dictionary = dme.get("recommendation", {})
		if dme_rec is Dictionary and not str(dme_rec.get("summary", "")).is_empty():
			_add_plain_label(str(dme_rec.get("summary", "")), 220)
		for drow in dme.get("day_rows", []):
			if drow is Dictionary:
				_add_plain_label(str(drow.get("label", "")), 220)
		_add_apply_button("Run designer module editor", "designer_module_editor_product", true)
		_add_apply_button("Module slot board", "designer_module_board", true)
		_add_apply_button("Edit modules", "designer_module_edit", true)
		_add_apply_button("Reliability gate", "designer_reliability_gate", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_designer_module_editor_product_plain"):
		var dmep := str(GameData.format_designer_module_editor_product_plain(province_id)).strip_edges()
		if not dmep.is_empty():
			_add_plain_label(dmep.split("\n")[0], 260)

	_add_section_title("— Designer stats/field (major #48) —")
	var dsf: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_stats_field_product_live"):
		dsf = MapManager.designer_stats_field_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		dsf = MapPolishFormatters.designer_stats_field_product(province_id)
	if not dsf.is_empty() and not bool(dsf.get("empty", false)):
		_add_plain_label(str(dsf.get("summary", "")), 280)
		var dsf_rec: Dictionary = dsf.get("recommendation", {})
		if dsf_rec is Dictionary and not str(dsf_rec.get("summary", "")).is_empty():
			_add_plain_label(str(dsf_rec.get("summary", "")), 220)
		for srow in dsf.get("day_rows", []):
			if srow is Dictionary:
				_add_plain_label(str(srow.get("label", "")), 220)
		_add_apply_button("Run designer stats/field", "designer_stats_field_product", true)
		_add_apply_button("Stats board", "designer_stats_board", true)
		_add_apply_button("Freeze design", "designer_freeze_design", true)
		_add_apply_button("Field seed", "designer_field_seed", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_designer_stats_field_product_plain"):
		var dsfp := str(GameData.format_designer_stats_field_product_plain(province_id)).strip_edges()
		if not dsfp.is_empty():
			_add_plain_label(dsfp.split("\n")[0], 260)

	_add_section_title("— Full designers multi-domain (major #49) —")
	var dmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_multi_domain_campaign_product_live"):
		dmd = MapManager.designer_multi_domain_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		dmd = MapPolishFormatters.designer_multi_domain_campaign_product(province_id)
	if not dmd.is_empty() and not bool(dmd.get("empty", false)):
		_add_plain_label(str(dmd.get("summary", "")), 280)
		var dmd_rec: Dictionary = dmd.get("recommendation", {})
		if dmd_rec is Dictionary and not str(dmd_rec.get("summary", "")).is_empty():
			_add_plain_label(str(dmd_rec.get("summary", "")), 220)
		for mrow in dmd.get("day_rows", []):
			if mrow is Dictionary:
				_add_plain_label(str(mrow.get("label", "")), 220)
		_add_apply_button("Run multi-domain designers", "designer_multi_domain_campaign_product", true)
		_add_apply_button("Catalog all domains", "designer_catalog_all_domains", true)
		_add_apply_button("Seed multi-domain", "designer_seed_multi_domain", true)
		_add_apply_button("Equip campaign close", "designer_equip_campaign_close", true)
		_add_apply_button("Domain: land", "designer_domain_land", true)
		_add_apply_button("Domain: naval", "designer_domain_naval", true)
		_add_apply_button("Domain: air", "designer_domain_air", true)
		_add_apply_button("Domain: space", "designer_domain_space", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_designer_multi_domain_campaign_product_plain"):
		var dmdp := str(GameData.format_designer_multi_domain_campaign_product_plain(province_id)).strip_edges()
		if not dmdp.is_empty():
			_add_plain_label(dmdp.split("\n")[0], 260)


	_add_section_title("— Weather crisis campaign (major #50) —")
	var wcc: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_campaign_product_live"):
		wcc = MapManager.weather_crisis_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		wcc = MapPolishFormatters.weather_crisis_campaign_product(province_id)
	if not wcc.is_empty() and not bool(wcc.get("empty", false)):
		_add_plain_label(str(wcc.get("summary", "")), 280)
		var wcc_rec: Dictionary = wcc.get("recommendation", {})
		if wcc_rec is Dictionary and not str(wcc_rec.get("summary", "")).is_empty():
			_add_plain_label(str(wcc_rec.get("summary", "")), 220)
		for wrow in wcc.get("day_rows", []):
			if wrow is Dictionary:
				_add_plain_label(str(wrow.get("label", "")), 220)
		_add_apply_button("Run weather crisis campaign", "weather_crisis_campaign_product", true)
		_add_apply_button("Forecast pressure", "weather_crisis_forecast", true)
		_add_apply_button("Multi-theater gate", "weather_crisis_gate_multi", true)
		_add_apply_button("Crisis sustain", "weather_crisis_sustain", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_weather_crisis_campaign_product_plain"):
		var wccp := str(GameData.format_weather_crisis_campaign_product_plain(province_id)).strip_edges()
		if not wccp.is_empty():
			_add_plain_label(wccp.split("\n")[0], 260)

	_add_section_title("— Intel cell network (major #51) —")
	var icn: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_cell_network_product_live"):
		icn = MapManager.intel_cell_network_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		icn = MapPolishFormatters.intel_cell_network_product(province_id)
	if not icn.is_empty() and not bool(icn.get("empty", false)):
		_add_plain_label(str(icn.get("summary", "")), 280)
		var icn_rec: Dictionary = icn.get("recommendation", {})
		if icn_rec is Dictionary and not str(icn_rec.get("summary", "")).is_empty():
			_add_plain_label(str(icn_rec.get("summary", "")), 220)
		for irow in icn.get("day_rows", []):
			if irow is Dictionary:
				_add_plain_label(str(irow.get("label", "")), 220)
		_add_apply_button("Run intel cell network", "intel_cell_network_product", true)
		_add_apply_button("Cell coverage", "intel_cell_coverage", true)
		_add_apply_button("Cell ops/recruit", "intel_cell_ops", true)
		_add_apply_button("Counterintel sweep", "intel_counter_sweep", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_intel_cell_network_product_plain"):
		var icnp := str(GameData.format_intel_cell_network_product_plain(province_id)).strip_edges()
		if not icnp.is_empty():
			_add_plain_label(icnp.split("\n")[0], 260)

	_add_section_title("— Leader theater command (major #52) —")
	var ltc: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_theater_command_product_live"):
		ltc = MapManager.leader_theater_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		ltc = MapPolishFormatters.leader_theater_command_product(province_id)
	if not ltc.is_empty() and not bool(ltc.get("empty", false)):
		_add_plain_label(str(ltc.get("summary", "")), 280)
		var ltc_rec: Dictionary = ltc.get("recommendation", {})
		if ltc_rec is Dictionary and not str(ltc_rec.get("summary", "")).is_empty():
			_add_plain_label(str(ltc_rec.get("summary", "")), 220)
		for lrow in ltc.get("day_rows", []):
			if lrow is Dictionary:
				_add_plain_label(str(lrow.get("label", "")), 220)
		_add_apply_button("Run leader theater command", "leader_theater_command_product", true)
		_add_apply_button("HQ assign board", "leader_hq_board", true)
		_add_apply_button("Multi-formation station", "leader_multi_station", true)
		_add_apply_button("Theater command ops", "leader_theater_ops", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_leader_theater_command_product_plain"):
		var ltcp := str(GameData.format_leader_theater_command_product_plain(province_id)).strip_edges()
		if not ltcp.is_empty():
			_add_plain_label(ltcp.split("\n")[0], 260)


	_add_section_title("— Strategic war goals (major #53) —")
	var swg: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_war_goal_product_live"):
		swg = MapManager.strategic_war_goal_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		swg = MapPolishFormatters.strategic_war_goal_product(province_id)
	if not swg.is_empty() and not bool(swg.get("empty", false)):
		_add_plain_label(str(swg.get("summary", "")), 280)
		var swg_rec: Dictionary = swg.get("recommendation", {})
		if swg_rec is Dictionary and not str(swg_rec.get("summary", "")).is_empty():
			_add_plain_label(str(swg_rec.get("summary", "")), 220)
		for srow in swg.get("day_rows", []):
			if srow is Dictionary:
				_add_plain_label(str(srow.get("label", "")), 220)
		_add_apply_button("Run strategic war goals", "strategic_war_goal_product", true)
		_add_apply_button("War-goal board", "war_goal_board", true)
		_add_apply_button("Justify package", "war_goal_justify", true)
		_add_apply_button("Execute push", "war_goal_execute", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_strategic_war_goal_product_plain"):
		var swgp := str(GameData.format_strategic_war_goal_product_plain(province_id)).strip_edges()
		if not swgp.is_empty():
			_add_plain_label(swgp.split("\n")[0], 260)

	_add_section_title("— Multi-front campaign AI (major #54) —")
	var mfa: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_campaign_ai_product_live"):
		mfa = MapManager.multi_front_campaign_ai_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		mfa = MapPolishFormatters.multi_front_campaign_ai_product(province_id)
	if not mfa.is_empty() and not bool(mfa.get("empty", false)):
		_add_plain_label(str(mfa.get("summary", "")), 280)
		var mfa_rec: Dictionary = mfa.get("recommendation", {})
		if mfa_rec is Dictionary and not str(mfa_rec.get("summary", "")).is_empty():
			_add_plain_label(str(mfa_rec.get("summary", "")), 220)
		for mrow in mfa.get("day_rows", []):
			if mrow is Dictionary:
				_add_plain_label(str(mrow.get("label", "")), 220)
		_add_apply_button("Run multi-front campaign AI", "multi_front_campaign_ai_product", true)
		_add_apply_button("Multi-front plan", "multi_front_plan", true)
		_add_apply_button("Weekly AI tick", "multi_front_weekly", true)
		_add_apply_button("Theater execute", "multi_front_execute", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_multi_front_campaign_ai_product_plain"):
		var mfap := str(GameData.format_multi_front_campaign_ai_product_plain(province_id)).strip_edges()
		if not mfap.is_empty():
			_add_plain_label(mfap.split("\n")[0], 260)

	_add_section_title("— Grand strategy cycle (major #55) —")
	var gsc: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("grand_strategy_cycle_product_live"):
		gsc = MapManager.grand_strategy_cycle_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		gsc = MapPolishFormatters.grand_strategy_cycle_product(province_id)
	if not gsc.is_empty() and not bool(gsc.get("empty", false)):
		_add_plain_label(str(gsc.get("summary", "")), 280)
		var gsc_rec: Dictionary = gsc.get("recommendation", {})
		if gsc_rec is Dictionary and not str(gsc_rec.get("summary", "")).is_empty():
			_add_plain_label(str(gsc_rec.get("summary", "")), 220)
		for grow in gsc.get("day_rows", []):
			if grow is Dictionary:
				_add_plain_label(str(grow.get("label", "")), 220)
		_add_apply_button("Run grand strategy cycle", "grand_strategy_cycle_product", true)
		_add_apply_button("Scan domains", "gs_cycle_scan", true)
		_add_apply_button("Rank priorities", "gs_cycle_rank", true)
		_add_apply_button("Execute top package", "gs_cycle_execute", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_grand_strategy_cycle_product_plain"):
		var gscp := str(GameData.format_grand_strategy_cycle_product_plain(province_id)).strip_edges()
		if not gscp.is_empty():
			_add_plain_label(gscp.split("\n")[0], 260)

	_add_section_title("— Occupation revolt/garrison (major #35) —")
	var org: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_revolt_garrison_product_live"):
		org = MapManager.occupation_revolt_garrison_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		org = MapPolishFormatters.occupation_revolt_garrison_product(province_id)
	if not org.is_empty() and not bool(org.get("empty", false)):
		_add_plain_label(str(org.get("summary", "")), 280)
		var org_rec: Dictionary = org.get("recommendation", {})
		if org_rec is Dictionary and not str(org_rec.get("summary", "")).is_empty():
			_add_plain_label(str(org_rec.get("summary", "")), 220)
		for orow in org.get("day_rows", []):
			if orow is Dictionary:
				_add_plain_label(str(orow.get("label", "")), 220)
		_add_apply_button("Run occupation revolt/garrison", "occupation_revolt_garrison_product", true)
		_add_apply_button("Revolt risk board", "occupation_revolt_board", true)
		_add_apply_button("Deploy garrison", "occupation_revolt_garrison", true)
		_add_apply_button("Suppress flashpoint", "occupation_revolt_suppress", true)
		_add_apply_button("Garrison light", "occupation_garrison_light", true)
		_add_apply_button("Garrison standard", "occupation_garrison_standard", true)
		_add_apply_button("Garrison heavy", "occupation_garrison_heavy", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_occupation_revolt_garrison_product_plain"):
		var orgp := str(GameData.format_occupation_revolt_garrison_product_plain(province_id)).strip_edges()
		if not orgp.is_empty():
			_add_plain_label(orgp.split("\n")[0], 260)

	_add_section_title("— Manpower cohort/reserve (major #36) —")
	var mcr: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_cohort_reserve_product_live"):
		mcr = MapManager.manpower_cohort_reserve_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		mcr = MapPolishFormatters.manpower_cohort_reserve_product(province_id)
	if not mcr.is_empty() and not bool(mcr.get("empty", false)):
		_add_plain_label(str(mcr.get("summary", "")), 280)
		var mcr_rec: Dictionary = mcr.get("recommendation", {})
		if mcr_rec is Dictionary and not str(mcr_rec.get("summary", "")).is_empty():
			_add_plain_label(str(mcr_rec.get("summary", "")), 220)
		for mrow in mcr.get("day_rows", []):
			if mrow is Dictionary:
				_add_plain_label(str(mrow.get("label", "")), 220)
		_add_apply_button("Run manpower cohort/reserve", "manpower_cohort_reserve_product", true)
		_add_apply_button("Age-cohort board", "manpower_cohort_board", true)
		_add_apply_button("Assign reserve tiers", "manpower_cohort_reserve", true)
		_add_apply_button("Mobilize field strength", "manpower_cohort_mobilize", true)
		_add_apply_button("Reserve active", "manpower_reserve_active", true)
		_add_apply_button("Reserve ready", "manpower_reserve_ready", true)
		_add_apply_button("Reserve strategic", "manpower_reserve_strategic", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_manpower_cohort_reserve_product_plain"):
		var mcrp := str(GameData.format_manpower_cohort_reserve_product_plain(province_id)).strip_edges()
		if not mcrp.is_empty():
			_add_plain_label(mcrp.split("\n")[0], 260)

	_add_section_title("— Multi-party peace conference (major #37) —")
	var mpp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_party_peace_conference_product_live"):
		mpp = MapManager.multi_party_peace_conference_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		mpp = MapPolishFormatters.multi_party_peace_conference_product(province_id)
	if not mpp.is_empty() and not bool(mpp.get("empty", false)):
		_add_plain_label(str(mpp.get("summary", "")), 280)
		var mpp_rec: Dictionary = mpp.get("recommendation", {})
		if mpp_rec is Dictionary and not str(mpp_rec.get("summary", "")).is_empty():
			_add_plain_label(str(mpp_rec.get("summary", "")), 220)
		for prow in mpp.get("day_rows", []):
			if prow is Dictionary:
				_add_plain_label(str(prow.get("label", "")), 220)
		_add_apply_button("Run multi-party peace conference", "multi_party_peace_conference_product", true)
		_add_apply_button("Multi-party board", "multi_party_peace_board", true)
		_add_apply_button("War-goal packages", "multi_party_peace_wargoals", true)
		_add_apply_button("Multi-party settle", "multi_party_peace_settle", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_multi_party_peace_conference_product_plain"):
		var mppp := str(GameData.format_multi_party_peace_conference_product_plain(province_id)).strip_edges()
		if not mppp.is_empty():
			_add_plain_label(mppp.split("\n")[0], 260)

	_add_section_title("— Designer domain live (major #33) —")
	var ddl: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_domain_live_product_live"):
		ddl = MapManager.designer_domain_live_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		ddl = MapPolishFormatters.designer_domain_live_product(province_id)
	if not ddl.is_empty() and not bool(ddl.get("empty", false)):
		_add_plain_label(str(ddl.get("summary", "")), 280)
		var ddl_rec: Dictionary = ddl.get("recommendation", {})
		if ddl_rec is Dictionary and not str(ddl_rec.get("summary", "")).is_empty():
			_add_plain_label(str(ddl_rec.get("summary", "")), 220)
		for drow in ddl.get("day_rows", []):
			if drow is Dictionary:
				_add_plain_label(str(drow.get("label", "")), 220)
		_add_apply_button("Run designer domain live", "designer_domain_live_product", true)
		_add_apply_button("Domain catalog", "designer_domain_live_catalog", true)
		_add_apply_button("Pick domain design", "designer_domain_live_pick", true)
		_add_apply_button("Seed production line", "designer_domain_live_seed", true)
		_add_apply_button("Domain land", "designer_domain_land", true)
		_add_apply_button("Domain naval", "designer_domain_naval", true)
		_add_apply_button("Domain air", "designer_domain_air", true)
		_add_apply_button("Domain space", "designer_domain_space", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_designer_domain_live_product_plain"):
		var ddlp := str(GameData.format_designer_domain_live_product_plain(province_id)).strip_edges()
		if not ddlp.is_empty():
			_add_plain_label(ddlp.split("\n")[0], 260)

	_add_section_title("— Campaign AI multi-month (major #34) —")
	var cam: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_ai_multi_month_product_live"):
		cam = MapManager.campaign_ai_multi_month_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cam = MapPolishFormatters.campaign_ai_multi_month_product(province_id)
	if not cam.is_empty() and not bool(cam.get("empty", false)):
		_add_plain_label(str(cam.get("summary", "")), 280)
		var cam_rec: Dictionary = cam.get("recommendation", {})
		if cam_rec is Dictionary and not str(cam_rec.get("summary", "")).is_empty():
			_add_plain_label(str(cam_rec.get("summary", "")), 220)
		for crow in cam.get("day_rows", []):
			if crow is Dictionary:
				_add_plain_label(str(crow.get("label", "")), 220)
		_add_apply_button("Run campaign AI multi-month", "campaign_ai_multi_month_product", true)
		_add_apply_button("Month plan board", "campaign_ai_month_board", true)
		_add_apply_button("Weekly AI plan", "campaign_ai_weekly_plan", true)
		_add_apply_button("Theater execute week", "campaign_ai_theater_execute", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_campaign_ai_multi_month_product_plain"):
		var camp := str(GameData.format_campaign_ai_multi_month_product_plain(province_id)).strip_edges()
		if not camp.is_empty():
			_add_plain_label(camp.split("\n")[0], 260)

	_add_section_title("— Occupation resistance/compliance (major #29) —")
	var orc: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_resistance_compliance_product_live"):
		orc = MapManager.occupation_resistance_compliance_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		orc = MapPolishFormatters.occupation_resistance_compliance_product(province_id)
	if not orc.is_empty() and not bool(orc.get("empty", false)):
		_add_plain_label(str(orc.get("summary", "")), 280)
		var orc_rec: Dictionary = orc.get("recommendation", {})
		if orc_rec is Dictionary and not str(orc_rec.get("summary", "")).is_empty():
			_add_plain_label(str(orc_rec.get("summary", "")), 220)
		for orow in orc.get("day_rows", []):
			if orow is Dictionary:
				_add_plain_label(str(orow.get("label", "")), 220)
		_add_apply_button("Run occupation resistance/compliance", "occupation_resistance_compliance_product", true)
		_add_apply_button("Occupation R/C board", "occupation_resistance_board", true)
		_add_apply_button("Occupation policy", "occupation_resistance_policy", true)
		_add_apply_button("Occupation daily tick", "occupation_resistance_tick", true)
		_add_apply_button("Policy harsh", "occupation_policy_harsh", true)
		_add_apply_button("Policy moderate", "occupation_policy_moderate", true)
		_add_apply_button("Policy lenient", "occupation_policy_lenient", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_occupation_resistance_compliance_product_plain"):
		var orp := str(GameData.format_occupation_resistance_compliance_product_plain(province_id)).strip_edges()
		if not orp.is_empty():
			_add_plain_label(orp.split("\n")[0], 260)

	_add_section_title("— Manpower laws/training (major #30) —")
	var mlt: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_laws_training_product_live"):
		mlt = MapManager.manpower_laws_training_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		mlt = MapPolishFormatters.manpower_laws_training_product(province_id)
	if not mlt.is_empty() and not bool(mlt.get("empty", false)):
		_add_plain_label(str(mlt.get("summary", "")), 280)
		var mlt_rec: Dictionary = mlt.get("recommendation", {})
		if mlt_rec is Dictionary and not str(mlt_rec.get("summary", "")).is_empty():
			_add_plain_label(str(mlt_rec.get("summary", "")), 220)
		for mrow in mlt.get("day_rows", []):
			if mrow is Dictionary:
				_add_plain_label(str(mrow.get("label", "")), 220)
		_add_apply_button("Run manpower laws/training", "manpower_laws_training_product", true)
		_add_apply_button("Manpower law board", "manpower_law_board", true)
		_add_apply_button("Training pipeline", "manpower_train_pipeline", true)
		_add_apply_button("Field trained manpower", "manpower_field_trained", true)
		_add_apply_button("Law volunteer", "manpower_law_volunteer", true)
		_add_apply_button("Law limited", "manpower_law_limited", true)
		_add_apply_button("Law extensive", "manpower_law_extensive", true)
		_add_apply_button("Law service by requirement", "manpower_law_service_by_requirement", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_manpower_laws_training_product_plain"):
		var mlp := str(GameData.format_manpower_laws_training_product_plain(province_id)).strip_edges()
		if not mlp.is_empty():
			_add_plain_label(mlp.split("\n")[0], 260)

	_add_section_title("— Peace conference settlement (major #31) —")
	var pcs: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("peace_conference_settlement_product_live"):
		pcs = MapManager.peace_conference_settlement_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		pcs = MapPolishFormatters.peace_conference_settlement_product(province_id)
	if not pcs.is_empty() and not bool(pcs.get("empty", false)):
		_add_plain_label(str(pcs.get("summary", "")), 280)
		var pcs_rec: Dictionary = pcs.get("recommendation", {})
		if pcs_rec is Dictionary and not str(pcs_rec.get("summary", "")).is_empty():
			_add_plain_label(str(pcs_rec.get("summary", "")), 220)
		for prow in pcs.get("day_rows", []):
			if prow is Dictionary:
				_add_plain_label(str(prow.get("label", "")), 220)
		_add_apply_button("Run peace conference settlement", "peace_conference_settlement_product", true)
		_add_apply_button("Peace conference board", "peace_conference_board", true)
		_add_apply_button("Peace demands package", "peace_conference_demands", true)
		_add_apply_button("Apply settlement", "peace_conference_settle", true)
		_add_apply_button("Demand annex", "peace_demand_annex", true)
		_add_apply_button("Demand puppet", "peace_demand_puppet", true)
		_add_apply_button("Demand reparations", "peace_demand_reparations", true)
		_add_apply_button("Demand occupation zone", "peace_demand_occupation_zone", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_peace_conference_settlement_product_plain"):
		var pcp := str(GameData.format_peace_conference_settlement_product_plain(province_id)).strip_edges()
		if not pcp.is_empty():
			_add_plain_label(pcp.split("\n")[0], 260)

	_add_section_title("— Medium-tank production honesty (major #27) —")
	var mth: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_tank_production_honesty_product_live"):
		mth = MapManager.medium_tank_production_honesty_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		mth = MapPolishFormatters.medium_tank_production_honesty_product(province_id)
	if not mth.is_empty() and not bool(mth.get("empty", false)):
		_add_plain_label(str(mth.get("summary", "")), 280)
		var mrec: Dictionary = mth.get("recommendation", {})
		if mrec is Dictionary and not str(mrec.get("summary", "")).is_empty():
			_add_plain_label(str(mrec.get("summary", "")), 220)
		var sheet: Dictionary = mth.get("unit_sheet", {})
		if sheet is Dictionary and not str(sheet.get("summary", "")).is_empty():
			_add_plain_label(str(sheet.get("summary", "")), 240)
		for mrow in mth.get("day_rows", []):
			if mrow is Dictionary:
				_add_plain_label(str(mrow.get("label", "")), 220)
		_add_apply_button("Run medium-tank production honesty", "medium_tank_production_honesty_product", true)
		_add_apply_button("Prove 60d medium seed", "medium_honesty_prove_60d", true)
		_add_apply_button("Prove 80d factory risk", "medium_honesty_prove_80d", true)
		_add_apply_button("Prove 100d complete equip", "medium_honesty_prove_100d", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_medium_tank_production_honesty_product_plain"):
		var mtp := str(GameData.format_medium_tank_production_honesty_product_plain(province_id)).strip_edges()
		if not mtp.is_empty():
			_add_plain_label(mtp.split("\n")[0], 260)

	_add_section_title("— Occupation control (major #24) —")
	var occ: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_control_product_live"):
		occ = MapManager.occupation_control_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		occ = MapPolishFormatters.occupation_control_product(province_id)
	if not occ.is_empty() and not bool(occ.get("empty", false)):
		_add_plain_label(str(occ.get("summary", "")), 280)
		var orec: Dictionary = occ.get("recommendation", {})
		if orec is Dictionary and not str(orec.get("summary", "")).is_empty():
			_add_plain_label(str(orec.get("summary", "")), 220)
		for orow in occ.get("day_rows", []):
			if orow is Dictionary:
				_add_plain_label(str(orow.get("label", "")), 220)
		_add_apply_button("Run occupation control", "occupation_control_product", true)
		_add_apply_button("Occupation control board", "occupation_control_board", true)
		_add_apply_button("Occupation garrison", "occupation_control_garrison", true)
		_add_apply_button("Occupation integrate", "occupation_control_integrate", true)
	_add_section_title("— Manpower reinforcement (major #25) —")
	var mpr: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_reinforcement_product_live"):
		mpr = MapManager.manpower_reinforcement_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		mpr = MapPolishFormatters.manpower_reinforcement_product(province_id)
	if not mpr.is_empty() and not bool(mpr.get("empty", false)):
		_add_plain_label(str(mpr.get("summary", "")), 280)
		var mrec: Dictionary = mpr.get("recommendation", {})
		if mrec is Dictionary and not str(mrec.get("summary", "")).is_empty():
			_add_plain_label(str(mrec.get("summary", "")), 220)
		for mrow in mpr.get("day_rows", []):
			if mrow is Dictionary:
				_add_plain_label(str(mrow.get("label", "")), 220)
		_add_apply_button("Run manpower reinforcement", "manpower_reinforcement_product", true)
		_add_apply_button("Manpower draft board", "manpower_draft_board", true)
		_add_apply_button("Manpower reinforce lines", "manpower_reinforce_lines", true)
		_add_apply_button("Manpower field units", "manpower_field_units", true)
	# RF5: reinforce logistics plain stories (XP dilution · transit · active flow symbols)
	_add_section_title("— Reinforce logistics story (RF5) —")
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("format_reinforce_story_plain"):
		var rst: Dictionary = ProductionManager.format_reinforce_story_plain("USA", {"year": 1939, "distance_km": 400.0, "hops": 2})
		var rplain := str(rst.get("plain", "")).strip_edges()
		if not rplain.is_empty():
			_add_plain_label(rplain, 320)
		for rline in rst.get("lines", []):
			var ls := str(rline).strip_edges()
			if not ls.is_empty() and ls != rplain:
				_add_plain_label(ls, 280)
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("format_equipment_flow_map_strip"):
		var fstrip: Dictionary = ProductionManager.format_equipment_flow_map_strip("USA")
		var splain := str(fstrip.get("plain", "")).strip_edges()
		if not splain.is_empty():
			_add_plain_label(splain, 280)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_reinforce_story_plain"):
		var gsp := str(GameData.format_reinforce_story_plain(province_id)).strip_edges()
		if not gsp.is_empty():
			_add_plain_label(gsp, 300)
	_add_apply_button("Refresh reinforce story", "reinforce_story_primary_live", true)
	_add_apply_button("Equipment flow symbols", "equipment_flow_symbols_primary_live", true)
	_add_section_title("— Leader command (major #26) —")
	var ldp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_command_product_live"):
		ldp = MapManager.leader_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		ldp = MapPolishFormatters.leader_command_product(province_id)
	if not ldp.is_empty() and not bool(ldp.get("empty", false)):
		_add_plain_label(str(ldp.get("summary", "")), 280)
		var lrec: Dictionary = ldp.get("recommendation", {})
		if lrec is Dictionary and not str(lrec.get("summary", "")).is_empty():
			_add_plain_label(str(lrec.get("summary", "")), 220)
		for lrow in ldp.get("day_rows", []):
			if lrow is Dictionary:
				_add_plain_label(str(lrow.get("label", "")), 220)
		_add_apply_button("Run leader command", "leader_command_product", true)
		_add_apply_button("Leader assign", "leader_command_assign", true)
		_add_apply_button("Leader station", "leader_command_station", true)
		_add_apply_button("Leader command ops", "leader_command_ops", true)

	_add_section_title("— War economy mobilization (major #21) —")
	var wep: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_mobilization_product_live"):
		wep = MapManager.war_economy_mobilization_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		wep = MapPolishFormatters.war_economy_mobilization_product(province_id)
	if not wep.is_empty() and not bool(wep.get("empty", false)):
		_add_plain_label(str(wep.get("summary", "")), 280)
		var wrec: Dictionary = wep.get("recommendation", {})
		if wrec is Dictionary and not str(wrec.get("summary", "")).is_empty():
			_add_plain_label(str(wrec.get("summary", "")), 220)
		for wrow in wep.get("day_rows", []):
			if wrow is Dictionary:
				_add_plain_label(str(wrow.get("label", "")), 220)
		_add_apply_button("Run war economy mobilization", "war_economy_mobilization_product", true)
		_add_apply_button("War economy board", "war_economy_board", true)
		_add_apply_button("Allocate production", "war_economy_allocate", true)
		_add_apply_button("Sustain war economy", "war_economy_sustain", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_war_economy_mobilization_product_plain"):
		var wepp := str(GameData.format_war_economy_mobilization_product_plain(province_id)).strip_edges()
		if not wepp.is_empty():
			_add_plain_label(wepp.split("\n")[0], 260)
	_add_section_title("— Weather theater ops (major #22) —")
	var wxp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_theater_ops_product_live"):
		wxp = MapManager.weather_theater_ops_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		wxp = MapPolishFormatters.weather_theater_ops_product(province_id)
	if not wxp.is_empty() and not bool(wxp.get("empty", false)):
		_add_plain_label(str(wxp.get("summary", "")), 280)
		var xrec: Dictionary = wxp.get("recommendation", {})
		if xrec is Dictionary and not str(xrec.get("summary", "")).is_empty():
			_add_plain_label(str(xrec.get("summary", "")), 220)
		for xrow in wxp.get("day_rows", []):
			if xrow is Dictionary:
				_add_plain_label(str(xrow.get("label", "")), 220)
		_add_apply_button("Run weather theater ops", "weather_theater_ops_product", true)
		_add_apply_button("Weather pressure", "weather_theater_pressure", true)
		_add_apply_button("Weather gate", "weather_theater_gate", true)
		_add_apply_button("Weather crisis", "weather_theater_crisis", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_weather_theater_ops_product_plain"):
		var wxpp := str(GameData.format_weather_theater_ops_product_plain(province_id)).strip_edges()
		if not wxpp.is_empty():
			_add_plain_label(wxpp.split("\n")[0], 260)
	_add_section_title("— Front continuity campaign (major #23) —")
	var fcp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_continuity_campaign_product_live"):
		fcp = MapManager.front_continuity_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		fcp = MapPolishFormatters.front_continuity_campaign_product(province_id)
	if not fcp.is_empty() and not bool(fcp.get("empty", false)):
		_add_plain_label(str(fcp.get("summary", "")), 280)
		var frec: Dictionary = fcp.get("recommendation", {})
		if frec is Dictionary and not str(frec.get("summary", "")).is_empty():
			_add_plain_label(str(frec.get("summary", "")), 220)
		for frow in fcp.get("day_rows", []):
			if frow is Dictionary:
				_add_plain_label(str(frow.get("label", "")), 220)
		_add_apply_button("Run front continuity campaign", "front_continuity_campaign_product", true)
		_add_apply_button("Front combat board", "front_continuity_combat", true)
		_add_apply_button("Front assault rank", "front_continuity_assault", true)
		_add_apply_button("Front sustain", "front_continuity_sustain", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_front_continuity_campaign_product_plain"):
		var fcpp := str(GameData.format_front_continuity_campaign_product_plain(province_id)).strip_edges()
		if not fcpp.is_empty():
			_add_plain_label(fcpp.split("\n")[0], 260)

	_add_section_title("— Logistics supply theater (major #18) —")
	var logp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_supply_theater_product_live"):
		logp = MapManager.logistics_supply_theater_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		logp = MapPolishFormatters.logistics_supply_theater_product(province_id)
	if not logp.is_empty() and not bool(logp.get("empty", false)):
		_add_plain_label(str(logp.get("summary", "")), 280)
		var lrec: Dictionary = logp.get("recommendation", {})
		if lrec is Dictionary and not str(lrec.get("summary", "")).is_empty():
			_add_plain_label(str(lrec.get("summary", "")), 220)
		for lrow in logp.get("day_rows", []):
			if lrow is Dictionary:
				_add_plain_label(str(lrow.get("label", "")), 220)
		_add_apply_button("Run logistics supply theater", "logistics_supply_theater_product", true)
		_add_apply_button("Supply route audit", "logistics_supply_route", true)
		_add_apply_button("Supply sustain", "logistics_supply_sustain", true)
		_add_apply_button("Force readiness joint", "logistics_supply_readiness", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_logistics_supply_theater_product_plain"):
		var lp := str(GameData.format_logistics_supply_theater_product_plain(province_id)).strip_edges()
		if not lp.is_empty():
			_add_plain_label(lp.split("\n")[0], 260)
	_add_section_title("— Intelligence network (major #19) —")
	var intp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intelligence_network_product_live"):
		intp = MapManager.intelligence_network_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		intp = MapPolishFormatters.intelligence_network_product(province_id)
	if not intp.is_empty() and not bool(intp.get("empty", false)):
		_add_plain_label(str(intp.get("summary", "")), 280)
		var irec: Dictionary = intp.get("recommendation", {})
		if irec is Dictionary and not str(irec.get("summary", "")).is_empty():
			_add_plain_label(str(irec.get("summary", "")), 220)
		for irow in intp.get("day_rows", []):
			if irow is Dictionary:
				_add_plain_label(str(irow.get("label", "")), 220)
		_add_apply_button("Run intelligence network", "intelligence_network_product", true)
		_add_apply_button("Intel coverage", "intel_network_coverage", true)
		_add_apply_button("Intel counterintel", "intel_network_counterintel", true)
		_add_apply_button("Intel counterplay", "intel_network_counterplay", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_intelligence_network_product_plain"):
		var ip := str(GameData.format_intelligence_network_product_plain(province_id)).strip_edges()
		if not ip.is_empty():
			_add_plain_label(ip.split("\n")[0], 260)
	_add_section_title("— World-class campaign command (major #20) —")
	var wcp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_campaign_command_product_live"):
		wcp = MapManager.world_class_campaign_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		wcp = MapPolishFormatters.world_class_campaign_command_product(province_id)
	if not wcp.is_empty() and not bool(wcp.get("empty", false)):
		_add_plain_label(str(wcp.get("summary", "")), 280)
		var wrec: Dictionary = wcp.get("recommendation", {})
		if wrec is Dictionary and not str(wrec.get("summary", "")).is_empty():
			_add_plain_label(str(wrec.get("summary", "")), 220)
		for wrow in wcp.get("day_rows", []):
			if wrow is Dictionary:
				_add_plain_label(str(wrow.get("label", "")), 220)
		_add_apply_button("Run world-class campaign command", "world_class_campaign_command_product", true)
		_add_apply_button("World-class scan", "world_class_scan", true)
		_add_apply_button("World-class rank", "world_class_rank", true)
		_add_apply_button("World-class execute", "world_class_execute", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_world_class_campaign_command_product_plain"):
		var wp := str(GameData.format_world_class_campaign_command_product_plain(province_id)).strip_edges()
		if not wp.is_empty():
			_add_plain_label(wp.split("\n")[0], 260)

	_add_section_title("— Focus war path product (major #14) —")
	var fwp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_war_path_product_live"):
		fwp = MapManager.focus_war_path_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		fwp = MapPolishFormatters.focus_war_path_product(province_id)
	if not fwp.is_empty() and not bool(fwp.get("empty", false)):
		_add_plain_label(str(fwp.get("summary", "")), 280)
		var frec: Dictionary = fwp.get("recommendation", {})
		if frec is Dictionary and not str(frec.get("summary", "")).is_empty():
			_add_plain_label(str(frec.get("summary", "")), 220)
		for frow in fwp.get("day_rows", []):
			if frow is Dictionary:
				_add_plain_label(str(frow.get("label", "")), 220)
		_add_apply_button("Run focus war path", "focus_war_path_product", true)
		_add_apply_button("Focus pick", "focus_war_pick", true)
		_add_apply_button("War path order", "focus_war_path_step", true)
		_add_apply_button("Focus commit", "focus_war_commit", true)
	_add_section_title("— Naval multi-phase campaign (major #15) —")
	var nmp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_multi_phase_campaign_product_live"):
		nmp = MapManager.naval_multi_phase_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		nmp = MapPolishFormatters.naval_multi_phase_campaign_product(province_id)
	if not nmp.is_empty() and not bool(nmp.get("empty", false)):
		_add_plain_label(str(nmp.get("summary", "")), 280)
		var nrec: Dictionary = nmp.get("recommendation", {})
		if nrec is Dictionary and not str(nrec.get("summary", "")).is_empty():
			_add_plain_label(str(nrec.get("summary", "")), 220)
		for nrow in nmp.get("day_rows", []):
			if nrow is Dictionary:
				_add_plain_label(str(nrow.get("label", "")), 220)
		_add_apply_button("Run naval multi-phase", "naval_multi_phase_campaign_product", true)
		_add_apply_button("Naval posture", "naval_phase_posture", true)
		_add_apply_button("Naval escort", "naval_phase_escort", true)
		_add_apply_button("Naval strike", "naval_phase_strike", true)
	_add_section_title("— Play session campaign (major #12) —")
	var sess: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("play_session_campaign_product_live"):
		sess = MapManager.play_session_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		sess = MapPolishFormatters.play_session_campaign_product(province_id)
	if not sess.is_empty() and not bool(sess.get("empty", false)):
		_add_plain_label(str(sess.get("summary", "")), 280)
		var srec: Dictionary = sess.get("recommendation", {})
		if srec is Dictionary and not str(srec.get("summary", "")).is_empty():
			_add_plain_label(str(srec.get("summary", "")), 220)
		for row in sess.get("day_rows", []):
			if row is Dictionary:
				_add_plain_label(str(row.get("label", "")), 220)
		_add_apply_button("Run play session campaign", "play_session_campaign_product", true)
		_add_apply_button("Session brief", "play_session_brief", true)
		_add_apply_button("Session execute", "play_session_execute", true)
		_add_apply_button("Session resolve", "play_session_resolve", true)
	_add_section_title("— Air ops campaign (major #13) —")
	var airp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_ops_campaign_product_live"):
		airp = MapManager.air_ops_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		airp = MapPolishFormatters.air_ops_campaign_product(province_id)
	if not airp.is_empty() and not bool(airp.get("empty", false)):
		_add_plain_label(str(airp.get("summary", "")), 280)
		var arec: Dictionary = airp.get("recommendation", {})
		if arec is Dictionary and not str(arec.get("summary", "")).is_empty():
			_add_plain_label(str(arec.get("summary", "")), 220)
		for arow in airp.get("day_rows", []):
			if arow is Dictionary:
				_add_plain_label(str(arow.get("label", "")), 220)
		_add_apply_button("Run air ops campaign", "air_ops_campaign_product", true)
		_add_apply_button("Air sortie", "air_ops_sortie", true)
		_add_apply_button("Air weather gate", "air_ops_weather_gate", true)
		_add_apply_button("Air-land joint", "air_ops_air_land", true)
	_add_section_title("— Strategic AI daily campaign (major #11) —")
	var said: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_daily_campaign_product_live"):
		said = MapManager.strategic_ai_daily_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		said = MapPolishFormatters.strategic_ai_daily_campaign_product(province_id)
	if not said.is_empty() and not bool(said.get("empty", false)):
		_add_plain_label(str(said.get("summary", "")), 280)
		var drec: Dictionary = said.get("recommendation", {})
		if drec is Dictionary and not str(drec.get("summary", "")).is_empty():
			_add_plain_label(str(drec.get("summary", "")), 220)
		var bud: Dictionary = said.get("budget", {})
		if bud is Dictionary and not str(bud.get("summary", "")).is_empty():
			_add_plain_label(str(bud.get("summary", "")), 220)
		for row in said.get("day_rows", []):
			if row is Dictionary:
				_add_plain_label(str(row.get("label", "")), 220)
		_add_apply_button("Run strategic AI daily campaign", "strategic_ai_daily_campaign_product", true)
		_add_apply_button("Board multi-faction AI", "strategic_ai_daily_board", true)
		_add_apply_button("Budget AI day actions", "strategic_ai_daily_budget", true)
		_add_apply_button("Apply budgeted AI day", "strategic_ai_daily_apply", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_strategic_ai_daily_campaign_product_plain"):
		var sdp := str(GameData.format_strategic_ai_daily_campaign_product_plain(province_id)).strip_edges()
		if not sdp.is_empty():
			_add_plain_label(sdp.substr(0, mini(320, sdp.length())), 240)
	_add_section_title("— Multi-faction strategic AI (major #9) —")
	var sai: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_faction_strategic_ai_product_live"):
		sai = MapManager.multi_faction_strategic_ai_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		sai = MapPolishFormatters.multi_faction_strategic_ai_product([], province_id)
	if not sai.is_empty() and not bool(sai.get("empty", false)):
		_add_plain_label(str(sai.get("summary", "")), 280)
		var srec: Dictionary = sai.get("recommendation", {})
		if srec is Dictionary and not str(srec.get("summary", "")).is_empty():
			_add_plain_label(str(srec.get("summary", "")), 220)
		for ln in sai.get("board_lines", []):
			_add_plain_label(str(ln), 220)
		_add_apply_button("Run multi-faction strategic AI", "multi_faction_strategic_ai_product", true)
		_add_apply_button("Scan major factions", "strategic_ai_scan", true)
		_add_apply_button("Rank faction priorities", "strategic_ai_rank", true)
		_add_apply_button("Execute top faction AI", "strategic_ai_execute", true)
	_add_section_title("— Theater command product (major #8) —")
	var theater: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_command_product_live"):
		theater = MapManager.theater_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		theater = MapPolishFormatters.theater_command_product(province_id)
	if not theater.is_empty() and not bool(theater.get("empty", false)):
		_add_plain_label(str(theater.get("summary", "")), 280)
		var trec: Dictionary = theater.get("recommendation", {})
		if trec is Dictionary and not str(trec.get("summary", "")).is_empty():
			_add_plain_label(str(trec.get("summary", "")), 220)
		for ln in theater.get("strip_lines", []):
			_add_plain_label(str(ln), 240)
		_add_apply_button("Run theater command product", "theater_command_product", true)
		_add_apply_button("Scan domains", "theater_command_scan", true)
		_add_apply_button("Rank domains", "theater_command_rank", true)
		_add_apply_button("Execute top domain", "theater_command_execute", true)
	_add_section_title("— Inspector decision product (major #7) —")
	var insp: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("inspector_decision_product_live"):
		insp = MapManager.inspector_decision_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		insp = MapPolishFormatters.inspector_decision_product([], province_id)
	if not insp.is_empty() and not bool(insp.get("empty", false)):
		_add_plain_label(str(insp.get("summary", "")), 280)
		var irec: Dictionary = insp.get("recommendation", {})
		if irec is Dictionary and not str(irec.get("summary", "")).is_empty():
			_add_plain_label(str(irec.get("summary", "")), 220)
		_add_apply_button("Run inspector decision product", "inspector_decision_product", true)
		_add_apply_button("Primary decision strip", "inspector_product_primary", true)
		_add_apply_button("Collapse secondary chips", "inspector_product_collapse", true)
		_add_apply_button("Apply recommended decision", "inspector_product_apply", true)
	## End collapsed majors — day packages return to root body.
	_active_body = null
	_add_section_title("— Orders / day packages (collapsible) —")
	# Integrated strip always visible (primary skim)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_day_ops_integrated_plain"):
		var dop := str(GameData.format_day_ops_integrated_plain(country_tag)).strip_edges()
		if not dop.is_empty():
			_add_plain_label(dop, 220)
	# Surface strings for legacy day-package wiring tests + player skim
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_theater_day_command_strip_plain"):
		var strip := str(GameData.format_theater_day_command_strip_plain(province_id)).strip_edges()
		if not strip.is_empty():
			_add_plain_label("Command strip: " + strip, 200)
		else:
			_add_plain_label("Command strip (refresh for live theater day lines)", 120)
	else:
		_add_plain_label("Command strip (theater day command strip)", 100)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_war_economy_day_plain"):
		var we := str(GameData.format_war_economy_day_plain(province_id)).strip_edges()
		if not we.is_empty():
			_add_plain_label(we, 180)
	else:
		_add_plain_label("War economy day package (collapsed under Primary)", 100)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_joint_combat_timeline_plain"):
		var jtl := str(GameData.format_joint_combat_timeline_plain(province_id)).strip_edges()
		if not jtl.is_empty():
			_add_plain_label(jtl, 180)
		else:
			_add_plain_label("Joint combat timeline (live when theater day ready)", 100)
	else:
		_add_plain_label("Joint combat timeline surface", 80)
	# Naval skim + HH player path + medium-horizon equip (Top 5 #3–#5 surfaces)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_naval_campaign_skim_plain"):
		var nsk := str(GameData.format_naval_campaign_skim_plain(province_id)).strip_edges()
		if not nsk.is_empty():
			_add_plain_label(nsk, 200)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_hh_player_path_plain"):
		var hhp := str(GameData.format_hh_player_path_plain(province_id)).strip_edges()
		if not hhp.is_empty():
			_add_plain_label(hhp, 200)
	_add_apply_button("Run HH player path", "hh_player_path", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_medium_horizon_equip_plain"):
		var mhe := str(GameData.format_medium_horizon_equip_plain()).strip_edges()
		if not mhe.is_empty():
			_add_plain_label(mhe, 220)

func _add_section_plain_for_id(section_id: String) -> void:
	## One live plain per expanded group (avoids dumping all day plains).
	if typeof(GameData) == TYPE_NIL:
		return
	match section_id:
		"primary":
			if GameData.has_method("format_theater_day_cabinet_plain"):
				var t := str(GameData.format_theater_day_cabinet_plain(province_id)).strip_edges()
				if not t.is_empty():
					_add_plain_label(t, 200)
			if GameData.has_method("format_logistics_day_plain"):
				var l := str(GameData.format_logistics_day_plain(province_id)).strip_edges()
				if not l.is_empty():
					_add_plain_label(l, 180)
		"combat":
			if GameData.has_method("format_combat_campaign_day_plain"):
				var c := str(GameData.format_combat_campaign_day_plain(province_id)).strip_edges()
				if not c.is_empty():
					_add_plain_label(c, 200)
		"naval":
			if GameData.has_method("format_fleet_campaign_day_plain"):
				var f := str(GameData.format_fleet_campaign_day_plain(province_id)).strip_edges()
				if not f.is_empty():
					_add_plain_label(f, 200)
			if GameData.has_method("format_naval_campaign_skim_plain"):
				var n := str(GameData.format_naval_campaign_skim_plain(province_id)).strip_edges()
				if not n.is_empty():
					_add_plain_label(n, 180)
		"weather":
			if GameData.has_method("format_weather_crisis_day_plain"):
				var w := str(GameData.format_weather_crisis_day_plain(province_id)).strip_edges()
				if not w.is_empty():
					_add_plain_label(w, 200)
		"intel":
			if GameData.has_method("format_agent_campaign_day_plain"):
				var a := str(GameData.format_agent_campaign_day_plain(province_id)).strip_edges()
				if not a.is_empty():
					_add_plain_label(a, 200)
			if GameData.has_method("format_hh_player_path_plain"):
				var h := str(GameData.format_hh_player_path_plain(province_id)).strip_edges()
				if not h.is_empty():
					_add_plain_label(h, 180)
		"industry":
			if GameData.has_method("format_industry_surge_day_plain"):
				var i := str(GameData.format_industry_surge_day_plain(province_id)).strip_edges()
				if not i.is_empty():
					_add_plain_label(i, 200)
			if GameData.has_method("format_medium_horizon_equip_plain"):
				var e := str(GameData.format_medium_horizon_equip_plain()).strip_edges()
				if not e.is_empty():
					_add_plain_label(e, 180)
		_:
			pass


func _rebuild_combat_section() -> void:
	_add_section_title("— Multi-phase combat product (major #1) —")
	var product: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_phase_combat_product_for_province"):
		product = MapManager.multi_phase_combat_product_for_province(province_id)
	elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_phase_combat_ui_for_province"):
		product = MapManager.multi_phase_combat_ui_for_province(province_id)
	if not product.is_empty() and not bool(product.get("empty", false)):
		_add_plain_label(str(product.get("summary", product.get("plain", ""))), 260)
		var rec: Dictionary = product.get("recommendation", {})
		if rec is Dictionary and not rec.is_empty():
			_add_plain_label(str(rec.get("summary", "")), 220)
		var ribbon := str(product.get("ribbon", "")).strip_edges()
		if not ribbon.is_empty():
			_add_plain_label("Ribbon: " + ribbon, 220)
		var phase_rows: Array = product.get("phase_actions", product.get("phase_rows", []))
		for row in phase_rows:
			if row is Dictionary:
				_add_plain_label("  · " + str(row.get("label", "")), 220)
		var ready := bool(product.get("apply_ready", true))
		_add_apply_button("Run multi-phase combat product", "multi_phase_combat_product", true)
		var rec_aid := str(rec.get("action_id", "phase_engage")) if rec is Dictionary else "phase_engage"
		_add_apply_button("Recommended phase action", rec_aid, ready or str(product.get("follow_on", "")) == "disengage")
		_add_apply_button("Approach (soften / supply)", "phase_approach", true)
		_add_apply_button("Engage (stage assault)", "phase_engage", ready)
		_add_apply_button("Disengage (hold / extract)", "phase_disengage", true)
		_add_apply_button("Advance combat ops (close-live)", "combat_ops_close", true)
	else:
		_add_apply_button("Stage multi-phase assault", "apply_assault", true)
		_add_apply_button("Advance combat ops (close-live)", "combat_ops_close", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_multi_phase_combat_product_plain"):
		var pp := str(GameData.format_multi_phase_combat_product_plain(province_id)).strip_edges()
		if not pp.is_empty():
			_add_plain_label(pp.split("\n")[0], 260)
	# Keep joint air-naval / timeline context when available
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_air_naval_joint_for_province"):
		var c: Dictionary = MapManager.combat_air_naval_joint_for_province(province_id)
		if not c.is_empty():
			_add_plain_label(str(c.get("summary", "")), 200)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_combat_timeline_for_province"):
		var jt: Dictionary = MapManager.joint_combat_timeline_for_province(province_id, 0.7)
		_add_plain_label(str(jt.get("summary", "")), 200)


func _rebuild_fleet_section() -> void:
	_add_section_title("— Fleet multi-day autonomy product (major #2) —")
	var country_tag := "GER"
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		country_tag = str(LeaderManager.get_player_country_tag()).to_upper()
	if country_tag.is_empty():
		country_tag = "GER"
	var product: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_multi_day_autonomy_product_for_province"):
		product = MapManager.fleet_multi_day_autonomy_product_for_province(province_id, 0.65)
	elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_autonomy_tick_for_tag"):
		product = MapManager.fleet_autonomy_tick_for_tag(country_tag, 0.7)
	if not product.is_empty() and not bool(product.get("empty", false)):
		_add_plain_label(str(product.get("summary", product.get("plain", ""))), 260)
		var rec: Dictionary = product.get("recommendation", {})
		if rec is Dictionary and not rec.is_empty():
			_add_plain_label(str(rec.get("summary", "")), 220)
		_add_plain_label("Order %s · posture %s" % [str(product.get("chosen_order", "?")), str(product.get("chosen_posture", "?"))], 200)
		var day_rows: Array = product.get("day_rows", [])
		for row in day_rows:
			if row is Dictionary:
				_add_plain_label("  · " + str(row.get("label", "")), 220)
		var ready := bool(product.get("apply_ready", true))
		_add_apply_button("Run fleet multi-day autonomy product", "fleet_multi_day_autonomy_product", true)
		var rec_aid := str(rec.get("action_id", "fleet_day_posture")) if rec is Dictionary else "fleet_day_posture"
		_add_apply_button("Recommended fleet day step", rec_aid, true)
		_add_apply_button("Day 0 posture / tasking", "fleet_day_posture", true)
		_add_apply_button("Day 1 station + escort", "fleet_day_station_escort", true)
		_add_apply_button("Day 2 multi-day follow-through", "fleet_day_follow_through", ready)
		_add_apply_button("Run full multi-day sequence (0→1→2)", "fleet_multi_day_sequence", true)
	else:
		_add_apply_button("Run fleet autonomy tick", "fleet_autonomy", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_fleet_multi_day_autonomy_product_plain"):
		var fp := str(GameData.format_fleet_multi_day_autonomy_product_plain(province_id)).strip_edges()
		if not fp.is_empty():
			_add_plain_label(fp.split("\n")[0], 260)
	# Keep multi-theater context
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_multi_theater_day_for_tag"):
		var f: Dictionary = MapManager.fleet_multi_theater_day_for_tag(country_tag, 0.7, 3)
		if not f.is_empty():
			_add_plain_label(str(f.get("summary", "")), 200)
	_add_apply_button("Run fleet autonomy day", "fleet_autonomy_day", true)
	_add_apply_button("Run fleet multi-day / multi-theater", "fleet_multi_day", true)


func _rebuild_hh_section() -> void:
	_add_section_title("— HH multi-month agenda product (major #5) —")
	var product: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_multi_month_agenda_product_live"):
		product = MapManager.hh_multi_month_agenda_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		var trail0: Array = []
		if typeof(GameData) != TYPE_NIL and GameData.has_method("get_hh_agenda_trail"):
			trail0 = GameData.get_hh_agenda_trail()
		product = MapPolishFormatters.hh_multi_month_agenda_product(trail0, "", province_id)
	if not product.is_empty() and not bool(product.get("empty", false)):
		_add_plain_label(str(product.get("summary", "")), 280)
		var rec: Dictionary = product.get("recommendation", {})
		if rec is Dictionary and not str(rec.get("summary", "")).is_empty():
			_add_plain_label(str(rec.get("summary", "")), 220)
		for row in product.get("day_rows", []):
			if row is Dictionary:
				_add_plain_label(str(row.get("label", "")), 240)
		_add_apply_button("Run HH multi-month agenda product", "hh_multi_month_agenda_product", true)
		_add_apply_button("Month board (trail + filter)", "hh_month_trail_board", true)
		_add_apply_button("Monthly brief", "hh_month_brief", true)
		_add_apply_button("Quarterly counterplay commit", "hh_month_quarterly_counter", true)
	else:
		if typeof(GameData) != TYPE_NIL and GameData.has_method("format_hh_agenda_product_plain"):
			var prod := str(GameData.format_hh_agenda_product_plain()).strip_edges()
			_add_plain_label(prod if not prod.is_empty() else "(empty trail — HH multi-month product empty)")
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_hh_agenda_commitments_plain"):
		var commits := str(GameData.format_hh_agenda_commitments_plain(3)).strip_edges()
		if not commits.is_empty():
			_add_plain_label(commits, 200)
	_add_apply_button("Commit HH agenda", "apply_hh_commit", true)
	_add_apply_button("Apply counter-intel", "apply_counterplay", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_hh_multi_month_agenda_product_plain"):
		var hp := str(GameData.format_hh_multi_month_agenda_product_plain(province_id)).strip_edges()
		if not hp.is_empty():
			_add_plain_label(hp.split("\n")[0], 260)


func _rebuild_agent_section() -> void:
	_add_section_title("— Agent campaign product (major #6) —")
	var product: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_campaign_product_live"):
		product = MapManager.agent_campaign_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		product = MapPolishFormatters.agent_campaign_product([], 5, 0.35, 0.5, province_id)
	if not product.is_empty() and not bool(product.get("empty", false)):
		_add_plain_label(str(product.get("summary", "")), 280)
		var rec: Dictionary = product.get("recommendation", {})
		if rec is Dictionary and not str(rec.get("summary", "")).is_empty():
			_add_plain_label(str(rec.get("summary", "")), 220)
		for row in product.get("day_rows", []):
			if row is Dictionary:
				_add_plain_label(str(row.get("label", "")), 240)
		_add_apply_button("Run agent campaign product", "agent_campaign_product", true)
		_add_apply_button("AI board / mission pick", "agent_product_board", true)
		_add_apply_button("Coverage dispatch", "agent_product_dispatch", true)
		_add_apply_button("Counterplay / escalate", "agent_product_counterplay", true)
	else:
		_add_plain_label("No active signals — agent campaign product empty (demo board still available via apply)")
		_add_apply_button("Run agent campaign product", "agent_campaign_product", true)
	_add_apply_button("Dispatch agent counter-ops", "apply_agent_dispatch", true)
	_add_apply_button("Apply counter-intel", "apply_counterplay", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_agent_campaign_product_plain"):
		var ap := str(GameData.format_agent_campaign_product_plain(province_id)).strip_edges()
		if not ap.is_empty():
			_add_plain_label(ap.split("\n")[0], 260)


func _rebuild_industry_section() -> void:
	_add_section_title("— Medium-tank OOB product (major #3) —")
	var oob: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_tank_oob_product_for_province"):
		oob = MapManager.medium_tank_oob_product_for_province(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		oob = MapPolishFormatters.medium_tank_oob_product(province_id)
	if not oob.is_empty() and not bool(oob.get("empty", false)):
		_add_plain_label(str(oob.get("summary", "")), 280)
		var orec: Dictionary = oob.get("recommendation", {})
		if orec is Dictionary and not str(orec.get("summary", "")).is_empty():
			_add_plain_label(str(orec.get("summary", "")), 220)
		for row in oob.get("day_rows", []):
			if row is Dictionary:
				_add_plain_label(str(row.get("label", "")), 240)
		_add_apply_button("Run medium-tank OOB product", "medium_tank_oob_product", true)
		_add_apply_button("60d horizon (seed/priority)", "oob_horizon_60d", true)
		_add_apply_button("80d horizon (factory risk)", "oob_horizon_80d", true)
		_add_apply_button("100d horizon (equip prove)", "oob_horizon_100d", true)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("industry_economy_depth_for_province"):
		var ind: Dictionary = MapManager.industry_economy_depth_for_province(province_id)
		_add_plain_label(str(ind.get("summary", "")))
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_industry_economy_plain"):
		var ip := str(GameData.format_industry_economy_plain(province_id)).strip_edges()
		if not ip.is_empty():
			_add_plain_label(ip, 180)
	_add_apply_button("Set production priority", "apply_production", true)
	_add_apply_button("Sustain supply route", "apply_supply", true)
	_add_apply_button("Hold industrial focus", "apply_focus", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_medium_tank_oob_product_plain"):
		var op := str(GameData.format_medium_tank_oob_product_plain(province_id)).strip_edges()
		if not op.is_empty():
			_add_plain_label(op.split("\n")[0], 260)
	_add_section_title("— Designer suite product (major #10) —")
	var des: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_suite_product_live"):
		des = MapManager.designer_suite_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		des = MapPolishFormatters.designer_suite_product({}, province_id)
	if not des.is_empty() and not bool(des.get("empty", false)):
		_add_plain_label(str(des.get("summary", "")), 280)
		var drec: Dictionary = des.get("domain_recommendation", {})
		if drec is Dictionary and not str(drec.get("summary", "")).is_empty():
			_add_plain_label(str(drec.get("summary", "")), 220)
		for dr in des.get("domain_rows", []):
			if dr is Dictionary:
				_add_plain_label(str(dr.get("label", "")), 240)
		_add_apply_button("Run designer suite product", "designer_suite_product", true)
		_add_apply_button("Review design catalog", "designer_suite_catalog", true)
		_add_apply_button("Pick domain design", "designer_suite_pick", true)
		_add_apply_button("Seed production line", "designer_suite_seed", true)
		_add_apply_button("Land armor design", "designer_domain_land", true)
		_add_apply_button("Naval hull design", "designer_domain_naval", true)
		_add_apply_button("Air wing design", "designer_domain_air", true)
		_add_apply_button("Space project design", "designer_domain_space", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_designer_suite_product_plain"):
		var dp := str(GameData.format_designer_suite_product_plain(province_id)).strip_edges()
		if not dp.is_empty():
			_add_plain_label(dp.split("\n")[0], 260)


func _rebuild_saves_section() -> void:
	_add_section_title("— Save browser campaign product (major #4) —")
	var product: Dictionary = {}
	if typeof(GameData) != TYPE_NIL and GameData.has_method("save_browser_campaign_product_live"):
		product = GameData.save_browser_campaign_product_live()
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		var rows0: Array = []
		if typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("list_slots_for_ui"):
			rows0 = SaveLoadManager.list_slots_for_ui()
		product = MapPolishFormatters.save_browser_campaign_product(rows0, 8)
	if not product.is_empty() and not bool(product.get("empty", false)):
		_add_plain_label(str(product.get("summary", "")), 280)
		var resume: Dictionary = product.get("resume", {})
		var checkpoint: Dictionary = product.get("checkpoint", {})
		if resume is Dictionary and not bool(resume.get("empty", true)):
			_add_plain_label(str(resume.get("summary", "")), 220)
		if checkpoint is Dictionary:
			_add_plain_label(str(checkpoint.get("summary", "")), 200)
		_add_apply_button("Run save browser campaign product", "save_browser_campaign_product", true)
		var can_resume := resume is Dictionary and not bool(resume.get("empty", true)) and bool(resume.get("can_load", true))
		_add_apply_button("Resume recommended campaign slot", "save_browser_resume", can_resume)
		_add_apply_button("Checkpoint (autosave)", "save_browser_checkpoint", true)
		_add_apply_button("Quicksave", "save_slot:quicksave", true)
	# Live slot rows with Save/Load (real SaveLoadManager APIs via save_slot:/load_slot:)
	var rows: Array = []
	if typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("list_slots_for_ui"):
		rows = SaveLoadManager.list_slots_for_ui()
	var flair_rows: Array = []
	if typeof(MapPolishFormatters) != TYPE_NIL:
		var flair: Dictionary = MapPolishFormatters.save_slot_browser_flair(rows, 8)
		flair_rows = flair.get("rows", []) if flair is Dictionary else []
	var use_rows: Array = flair_rows if not flair_rows.is_empty() else rows
	var shown := 0
	for r in use_rows:
		if not (r is Dictionary):
			continue
		var slot := str(r.get("slot", "")).strip_edges()
		if slot.is_empty():
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = str(r.get("flair_label", r.get("label", slot)))
		row.add_child(lbl)
		var save_btn := Button.new()
		save_btn.text = "Save"
		save_btn.disabled = not bool(r.get("can_save", true))
		save_btn.pressed.connect(_on_action_pressed.bind("save_slot:%s" % slot))
		row.add_child(save_btn)
		var load_btn := Button.new()
		load_btn.text = "Load"
		load_btn.disabled = not bool(r.get("can_load", false))
		load_btn.pressed.connect(_on_action_pressed.bind("load_slot:%s" % slot))
		row.add_child(load_btn)
		_body.add_child(row)
		shown += 1
		if shown >= 8:
			break
	var qs_row := HBoxContainer.new()
	var qs := Button.new()
	qs.text = "Quicksave"
	qs.pressed.connect(_on_quicksave)
	qs_row.add_child(qs)
	var open_slots := Button.new()
	open_slots.text = "Refresh slots"
	open_slots.pressed.connect(refresh)
	qs_row.add_child(open_slots)
	_body.add_child(qs_row)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_save_browser_campaign_product_plain"):
		var sp := str(GameData.format_save_browser_campaign_product_plain()).strip_edges()
		if not sp.is_empty():
			_add_plain_label(sp.split("\n")[0], 260)


func _rebuild_gpu_section() -> void:
	_add_section_title("— GPU / pan-zoom profile (P9) —")
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_gpu_pan_zoom_day_plain"):
		var gpd := str(GameData.format_gpu_pan_zoom_day_plain()).strip_edges()
		if not gpd.is_empty():
			_add_plain_label(gpd, 240)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("gpu_pan_zoom_profile_live"):
		var gp: Dictionary = MapManager.gpu_pan_zoom_profile_live()
		_add_plain_label(str(gp.get("summary", "")))
		var bits: PackedStringArray = []
		if gp.has("zoom"):
			bits.append("zoom %.2f" % float(gp.get("zoom", 0.5)))
		if gp.has("resource_icon_budget"):
			bits.append("icons %d" % int(gp.get("resource_icon_budget", 0)))
		if gp.has("label_budget"):
			bits.append("labels %d" % int(gp.get("label_budget", 0)))
		if gp.has("load"):
			bits.append("load %.0f%%" % (float(gp.get("load", 0.0)) * 100.0))
		if not bits.is_empty():
			_add_plain_label(" · ".join(bits), 200)
		if bool(gp.get("deferred_hard_gate", true)):
			_add_plain_label("(advisory — hard GPU gate deferred)", 120)
	_add_apply_button("Review GPU pan/zoom day", "gpu_pan_zoom_day", true)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_tooltip_sfx_flair_strip_plain"):
		var tss := str(GameData.format_tooltip_sfx_flair_strip_plain(province_id)).strip_edges()
		if not tss.is_empty():
			_add_plain_label(tss, 240)
	_add_plain_label("Tooltip/SFX flair strip (select · invest · assault contracts)", 120)
	_rebuild_next10_section()


func _rebuild_next10_section() -> void:
	_add_section_title("— Next-10 depth —")
	var plain_methods: PackedStringArray = [
		"format_multi_phase_combat_day_plain",
		"format_combat_air_naval_day_plain",
		"format_agent_auto_day_plain",
		"format_focus_pick_day_plain",
		"format_production_priority_day_plain",
		"format_convoy_escort_day_plain",
		"format_next_day_feedback_day_plain",
		"format_map_effect_day_plain",
		"format_theater_brief_day_plain",
		"format_campaign_decision_day_plain",
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 220)
	_add_apply_button("Run multi-phase combat day", "multi_phase_combat_day", true)
	_add_apply_button("Run combat air-naval day", "combat_air_naval_day", true)
	_add_apply_button("Run agent auto day", "agent_auto_day", true)
	_add_apply_button("Run focus pick day", "focus_pick_day", true)
	_add_apply_button("Run production priority day", "production_priority_day", true)
	_add_apply_button("Run convoy escort day", "convoy_escort_day", true)
	_add_apply_button("Run next-day feedback day", "next_day_feedback_day", true)
	_add_apply_button("Run map effect day", "map_effect_day", true)
	_add_apply_button("Run theater brief day", "theater_brief_day", true)
	_add_apply_button("Run campaign decision day", "campaign_decision_day", true)
	_rebuild_priority_depth_section()


func _rebuild_priority_depth_section() -> void:
	_add_section_title("— Next-20 priority depth —")
	var plain_methods: PackedStringArray = [
		"format_order_panel_ux_day_plain",
		"format_multi_phase_combat_ui_day_plain",
		"format_fleet_ai_ops_day_plain",
		"format_hh_agenda_package_day_plain",
		"format_agent_campaign_depth_day_plain",
		"format_industry_economy_day_plain",
		"format_save_slot_browser_day_plain",
		"format_basing_logistics_day_plain",
		"format_assault_follow_on_day_plain",
		"format_joint_ops_loop_day_plain",
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 220)
	_add_apply_button("Run order panel UX day", "order_panel_ux_day", true)
	_add_apply_button("Run multi-phase combat UI day", "multi_phase_combat_ui_day", true)
	_add_apply_button("Run fleet AI ops day", "fleet_ai_ops_day", true)
	_add_apply_button("Run HH agenda package day", "hh_agenda_package_day", true)
	_add_apply_button("Run agent campaign depth day", "agent_campaign_depth_day", true)
	_add_apply_button("Run industry economy day", "industry_economy_day", true)
	_add_apply_button("Run save slot browser day", "save_slot_browser_day", true)
	_add_apply_button("Run basing logistics day", "basing_logistics_day", true)
	_add_apply_button("Run assault follow-on day", "assault_follow_on_day", true)
	_add_apply_button("Run joint ops loop day", "joint_ops_loop_day", true)
	_rebuild_theater_surface_section()


func _rebuild_theater_surface_section() -> void:
	_add_section_title("— Next-30 theater surface —")
	var plain_methods: PackedStringArray = [
		"format_war_cabinet_day_plain",
		"format_supply_campaign_day_plain",
		"format_force_supply_day_plain",
		"format_counter_ops_day_plain",
		"format_multi_province_live_day_plain",
		"format_order_queue_day_plain",
		"format_agent_ai_board_day_plain",
		"format_fleet_order_day_plain",
		"format_fleet_theater_posture_day_plain",
		"format_campaign_risk_day_plain",
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 220)
	_add_apply_button("Run war cabinet day", "war_cabinet_day", true)
	_add_apply_button("Run supply campaign day", "supply_campaign_day", true)
	_add_apply_button("Run force supply day", "force_supply_day", true)
	_add_apply_button("Run counter-ops day", "counter_ops_day", true)
	_add_apply_button("Run multi-province live day", "multi_province_live_day", true)
	_add_apply_button("Run order queue day", "order_queue_day", true)
	_add_apply_button("Run agent AI board day", "agent_ai_board_day", true)
	_add_apply_button("Run fleet order day", "fleet_order_day", true)
	_add_apply_button("Run fleet theater posture day", "fleet_theater_posture_day", true)
	_add_apply_button("Run campaign risk day", "campaign_risk_day", true)
	_rebuild_campaign_surface_section()


func _rebuild_campaign_surface_section() -> void:
	_add_section_title("— Next-40 campaign surface —")
	var plain_methods: PackedStringArray = [
		"format_sealane_health_day_plain",
		"format_convoy_package_day_plain",
		"format_theater_campaign_day_plain",
		"format_production_risk_day_plain",
		"format_leader_campaign_day_plain",
		"format_basing_repair_day_plain",
		"format_focus_order_day_plain",
		"format_naval_order_day_plain",
		"format_air_land_order_day_plain",
		"format_theater_order_day_plain",
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 220)
	_add_apply_button("Run sealane health day", "sealane_health_day", true)
	_add_apply_button("Run convoy package day", "convoy_package_day", true)
	_add_apply_button("Run theater campaign day", "theater_campaign_day", true)
	_add_apply_button("Run production risk day", "production_risk_day", true)
	_add_apply_button("Run leader campaign day", "leader_campaign_day", true)
	_add_apply_button("Run basing repair day", "basing_repair_day", true)
	_add_apply_button("Run focus order day", "focus_order_day", true)
	_add_apply_button("Run naval order day", "naval_order_day", true)
	_add_apply_button("Run air-land order day", "air_land_order_day", true)
	_add_apply_button("Run theater order day", "theater_order_day", true)
	_rebuild_ops_mutation_section()


func _rebuild_ops_mutation_section() -> void:
	_add_section_title("— Next-50 ops/mutation —")
	var plain_methods: PackedStringArray = [
		"format_factory_risk_day_plain",
		"format_trade_chain_day_plain",
		"format_war_path_urgency_day_plain",
		"format_combat_morale_day_plain",
		"format_choke_sea_day_plain",
		"format_redeploy_route_day_plain",
		"format_theater_report_day_plain",
		"format_best_station_day_plain",
		"format_best_assault_day_plain",
		"format_theater_mutation_day_plain",
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 220)
	_add_apply_button("Run factory risk day", "factory_risk_day", true)
	_add_apply_button("Run trade chain day", "trade_chain_day", true)
	_add_apply_button("Run war path urgency day", "war_path_urgency_day", true)
	_add_apply_button("Run combat morale day", "combat_morale_day", true)
	_add_apply_button("Run choke sea day", "choke_sea_day", true)
	_add_apply_button("Run redeploy route day", "redeploy_route_day", true)
	_add_apply_button("Run theater report day", "theater_report_day", true)
	_add_apply_button("Run best station day", "best_station_day", true)
	_add_apply_button("Run best assault day", "best_assault_day", true)
	_add_apply_button("Run theater mutation day", "theater_mutation_day", true)
	_rebuild_command_depth_section()


func _on_action_pressed(action_id: String) -> void:
	## Pack L — lock orders when active hotseat slot is not human.
	if typeof(SessionPlayers) != TYPE_NIL and SessionPlayers.has_method("is_active_human"):
		if not bool(SessionPlayers.is_active_human()):
			_status.text = "Hotseat locked — wait for human turn (End Turn to rotate)"
			_result.text = "Last result: %s → blocked (AI active)" % action_id
			return
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("apply_order_panel_action"):
		_status.text = "Apply failed: GameData.apply_order_panel_action missing"
		return
	var res: Dictionary = GameData.apply_order_panel_action(action_id, province_id)
	var ok := bool(res.get("ok", res.get("success", false)))
	_last_result = {
		"action_id": action_id,
		"ok": ok,
		"reason": str(res.get("reason", res.get("error", ""))),
		"empty": false,
	}
	_status.text = "Applied %s on %s" % [action_id, _province_label(province_id)]
	_result.text = "Last result: %s → %s" % [
		action_id,
		"OK" if ok else str(res.get("reason", res.get("error", "blocked"))),
	]
	# Soft refresh surfaces without rebuilding province list from scratch if save/load
	if action_id.begins_with("load_slot:"):
		refresh()
	else:
		_rebuild_all_sections()
		var log_plain := ""
		if typeof(GameData) != TYPE_NIL and GameData.has_method("format_command_result_log_plain"):
			log_plain = str(GameData.format_command_result_log_plain(5))
		if log_plain.is_empty():
			_log_label.text = "[color=#8899aa]Command log empty.[/color]"
		else:
			_log_label.text = "[color=#5ec8ff]Command results[/color]\n" + log_plain


func _on_quicksave() -> void:
	_on_action_pressed("save_slot:quicksave")

func _rebuild_command_depth_section() -> void:
	_add_section_title("— Next-60 command depth (20) —")
	var plain_methods: PackedStringArray = [
		"format_air_ops_sortie_day_plain",
		"format_agent_escalation_day_plain",
		"format_agent_coverage_day_plain",
		"format_combat_order_day_plain",
		"format_production_order_day_plain",
		"format_supply_order_day_plain",
		"format_combat_phase_strip_day_plain",
		"format_fleet_patrol_day_plain",
		"format_execute_one_day_plain",
		"format_daily_fleet_plan_day_plain",
		"format_daily_combat_plan_day_plain",
		"format_daily_prod_plan_day_plain",
		"format_daily_agent_plan_day_plain",
		"format_daily_supply_plan_day_plain",
		"format_agent_dispatch_mutation_day_plain",
		"format_fleet_station_mutation_day_plain",
		"format_assault_stage_mutation_day_plain",
		"format_naval_task_mutation_day_plain",
		"format_air_land_stage_mutation_day_plain",
		"format_hh_monthly_day_plain",
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run air ops sortie day", "air_ops_sortie_day", true)
	_add_apply_button("Run agent escalation day", "agent_escalation_day", true)
	_add_apply_button("Run agent coverage day", "agent_coverage_day", true)
	_add_apply_button("Run combat order day", "combat_order_day", true)
	_add_apply_button("Run production order day", "production_order_day", true)
	_add_apply_button("Run supply order day", "supply_order_day", true)
	_add_apply_button("Run combat phase strip day", "combat_phase_strip_day", true)
	_add_apply_button("Run fleet patrol day", "fleet_patrol_day", true)
	_add_apply_button("Run execute one day", "execute_one_day", true)
	_add_apply_button("Run daily fleet plan day", "daily_fleet_plan_day", true)
	_add_apply_button("Run daily combat plan day", "daily_combat_plan_day", true)
	_add_apply_button("Run daily prod plan day", "daily_prod_plan_day", true)
	_add_apply_button("Run daily agent plan day", "daily_agent_plan_day", true)
	_add_apply_button("Run daily supply plan day", "daily_supply_plan_day", true)
	_add_apply_button("Run agent dispatch mutation day", "agent_dispatch_mutation_day", true)
	_add_apply_button("Run fleet station mutation day", "fleet_station_mutation_day", true)
	_add_apply_button("Run assault stage mutation day", "assault_stage_mutation_day", true)
	_add_apply_button("Run naval task mutation day", "naval_task_mutation_day", true)
	_add_apply_button("Run air land stage mutation day", "air_land_stage_mutation_day", true)
	_add_apply_button("Run hh monthly day", "hh_monthly_day", true)
	_rebuild_playability_section()

func _rebuild_playability_section() -> void:
	_add_section_title("— Next-70 playability (20) —")
	var plain_methods: PackedStringArray = [
		"format_leader_weather_day_plain",
		"format_oob_factory_day_plain",
		"format_move_ops_day_plain",
		"format_fleet_wx_mission_day_plain",
		"format_player_surface_day_plain",
		"format_multi_province_plan_day_plain",
		"format_theater_prod_auto_day_plain",
		"format_focus_mutation_day_plain",
		"format_mutation_feedback_day_plain",
		"format_hh_quarterly_day_plain",
		"format_depot_weather_day_plain",
		"format_fleet_patrol_strip_day_plain",
		"format_close_loop_day_plain",
		"format_agent_missions_day_plain",
		"format_supply_route_mutation_day_plain",
		"format_basing_fuel_day_plain",
		"format_ops_dashboard_day_plain",
		"format_daily_theater_tick_day_plain",
		"format_command_log_day_plain",
		"format_integrity_gate_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run leader weather day", "leader_weather_day", true)
	_add_apply_button("Run oob factory day", "oob_factory_day", true)
	_add_apply_button("Run move ops day", "move_ops_day", true)
	_add_apply_button("Run fleet wx mission day", "fleet_wx_mission_day", true)
	_add_apply_button("Run player surface day", "player_surface_day", true)
	_add_apply_button("Run multi province plan day", "multi_province_plan_day", true)
	_add_apply_button("Run theater prod auto day", "theater_prod_auto_day", true)
	_add_apply_button("Run focus mutation day", "focus_mutation_day", true)
	_add_apply_button("Run mutation feedback day", "mutation_feedback_day", true)
	_add_apply_button("Run hh quarterly day", "hh_quarterly_day", true)
	_add_apply_button("Run depot weather day", "depot_weather_day", true)
	_add_apply_button("Run fleet patrol strip day", "fleet_patrol_strip_day", true)
	_add_apply_button("Run close loop day", "close_loop_day", true)
	_add_apply_button("Run agent missions day", "agent_missions_day", true)
	_add_apply_button("Run supply route mutation day", "supply_route_mutation_day", true)
	_add_apply_button("Run basing fuel day", "basing_fuel_day", true)
	_add_apply_button("Run ops dashboard day", "ops_dashboard_day", true)
	_add_apply_button("Run daily theater tick day", "daily_theater_tick_day", true)
	_add_apply_button("Run command log day", "command_log_day", true)
	_add_apply_button("Run integrity gate day", "integrity_gate_day", true)
	_rebuild_execution_surface_section()

func _rebuild_execution_surface_section() -> void:
	_add_section_title("— Next-80 execution surface (20) —")
	var plain_methods: PackedStringArray = [
		"format_result_feedback_day_plain",
		"format_day_budget_day_plain",
		"format_hh_auto_plan_day_plain",
		"format_append_log_day_plain",
		"format_log_strip_day_plain",
		"format_assault_readiness_day_plain",
		"format_coherence_delta_day_plain",
		"format_agent_order_day_plain",
		"format_execution_gate_day_plain",
		"format_cohesion_gate_day_plain",
		"format_command_gate_day_plain",
		"format_execute_order_day_plain",
		"format_air_sortie_ready_day_plain",
		"format_weather_combat_brief_day_plain",
		"format_day_audit_day_plain",
		"format_map_visible_day_plain",
		"format_assault_card_day_plain",
		"format_save_slot_list_day_plain",
		"format_multi_phase_estimate_day_plain",
		"format_campaign_strip_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run result feedback day", "result_feedback_day", true)
	_add_apply_button("Run day budget day", "day_budget_day", true)
	_add_apply_button("Run hh auto plan day", "hh_auto_plan_day", true)
	_add_apply_button("Run append log day", "append_log_day", true)
	_add_apply_button("Run log strip day", "log_strip_day", true)
	_add_apply_button("Run assault readiness day", "assault_readiness_day", true)
	_add_apply_button("Run coherence delta day", "coherence_delta_day", true)
	_add_apply_button("Run agent order day", "agent_order_day", true)
	_add_apply_button("Run execution gate day", "execution_gate_day", true)
	_add_apply_button("Run cohesion gate day", "cohesion_gate_day", true)
	_add_apply_button("Run command gate day", "command_gate_day", true)
	_add_apply_button("Run execute order day", "execute_order_day", true)
	_add_apply_button("Run air sortie ready day", "air_sortie_ready_day", true)
	_add_apply_button("Run weather combat brief day", "weather_combat_brief_day", true)
	_add_apply_button("Run day audit day", "day_audit_day", true)
	_add_apply_button("Run map visible day", "map_visible_day", true)
	_add_apply_button("Run assault card day", "assault_card_day", true)
	_add_apply_button("Run save slot list day", "save_slot_list_day", true)
	_add_apply_button("Run multi phase estimate day", "multi_phase_estimate_day", true)
	_add_apply_button("Run campaign strip day", "campaign_strip_day", true)
	_rebuild_live_command_section()

func _rebuild_live_command_section() -> void:
	_add_section_title("— Next-90 live command (20) —")
	var plain_methods: PackedStringArray = [
		"format_mutation_result_day_plain",
		"format_mutation_strip_day_plain",
		"format_close_mutation_day_plain",
		"format_mutation_gate_day_plain",
		"format_agenda_pick_day_plain",
		"format_agenda_actions_day_plain",
		"format_hh_commit_order_day_plain",
		"format_theater_hh_commit_day_plain",
		"format_hh_counterplay_day_plain",
		"format_task_group_day_plain",
		"format_naval_basing_day_plain",
		"format_naval_multi_phase_day_plain",
		"format_coastal_fog_gate_day_plain",
		"format_phase_ribbon_day_plain",
		"format_assault_rank_day_plain",
		"format_joint_timeline_day_plain",
		"format_daylight_combat_day_plain",
		"format_production_auto_day_plain",
		"format_production_risk_alert_day_plain",
		"format_day_results_flair_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run mutation result day", "mutation_result_day", true)
	_add_apply_button("Run mutation strip day", "mutation_strip_day", true)
	_add_apply_button("Run close mutation day", "close_mutation_day", true)
	_add_apply_button("Run mutation gate day", "mutation_gate_day", true)
	_add_apply_button("Run agenda pick day", "agenda_pick_day", true)
	_add_apply_button("Run agenda actions day", "agenda_actions_day", true)
	_add_apply_button("Run hh commit order day", "hh_commit_order_day", true)
	_add_apply_button("Run theater hh commit day", "theater_hh_commit_day", true)
	_add_apply_button("Run hh counterplay day", "hh_counterplay_day", true)
	_add_apply_button("Run task group day", "task_group_day", true)
	_add_apply_button("Run naval basing day", "naval_basing_day", true)
	_add_apply_button("Run naval multi phase day", "naval_multi_phase_day", true)
	_add_apply_button("Run coastal fog gate day", "coastal_fog_gate_day", true)
	_add_apply_button("Run phase ribbon day", "phase_ribbon_day", true)
	_add_apply_button("Run assault rank day", "assault_rank_day", true)
	_add_apply_button("Run joint timeline day", "joint_timeline_day", true)
	_add_apply_button("Run daylight combat day", "daylight_combat_day", true)
	_add_apply_button("Run production auto day", "production_auto_day", true)
	_add_apply_button("Run production risk alert day", "production_risk_alert_day", true)
	_add_apply_button("Run day results flair day", "day_results_flair_day", true)
	_rebuild_world_class_section()

func _rebuild_world_class_section() -> void:
	_add_section_title("— Next-100 world-class (20) —")
	var plain_methods: PackedStringArray = [
		"format_best_assault_live_day_plain",
		"format_best_station_live_day_plain",
		"format_execute_one_live_day_plain",
		"format_basing_fuel_loop_day_plain",
		"format_fleet_wx_package_day_plain",
		"format_convoy_wx_window_day_plain",
		"format_focus_wx_score_day_plain",
		"format_morale_wx_day_plain",
		"format_campaign_risk_live_day_plain",
		"format_depot_wx_live_day_plain",
		"format_daily_fleet_auto_day_plain",
		"format_daily_combat_auto_day_plain",
		"format_daily_agent_auto_day_plain",
		"format_daily_supply_auto_day_plain",
		"format_basing_signals_day_plain",
		"format_basing_rates_day_plain",
		"format_combat_wx_mult_day_plain",
		"format_sea_zone_trade_day_plain",
		"format_hh_secondary_trail_day_plain",
		"format_agent_campaign_live_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run best assault live day", "best_assault_live_day", true)
	_add_apply_button("Run best station live day", "best_station_live_day", true)
	_add_apply_button("Run execute one live day", "execute_one_live_day", true)
	_add_apply_button("Run basing fuel loop day", "basing_fuel_loop_day", true)
	_add_apply_button("Run fleet wx package day", "fleet_wx_package_day", true)
	_add_apply_button("Run convoy wx window day", "convoy_wx_window_day", true)
	_add_apply_button("Run focus wx score day", "focus_wx_score_day", true)
	_add_apply_button("Run morale wx day", "morale_wx_day", true)
	_add_apply_button("Run campaign risk live day", "campaign_risk_live_day", true)
	_add_apply_button("Run depot wx live day", "depot_wx_live_day", true)
	_add_apply_button("Run daily fleet auto day", "daily_fleet_auto_day", true)
	_add_apply_button("Run daily combat auto day", "daily_combat_auto_day", true)
	_add_apply_button("Run daily agent auto day", "daily_agent_auto_day", true)
	_add_apply_button("Run daily supply auto day", "daily_supply_auto_day", true)
	_add_apply_button("Run basing signals day", "basing_signals_day", true)
	_add_apply_button("Run basing rates day", "basing_rates_day", true)
	_add_apply_button("Run combat wx mult day", "combat_wx_mult_day", true)
	_add_apply_button("Run sea zone trade day", "sea_zone_trade_day", true)
	_add_apply_button("Run hh secondary trail day", "hh_secondary_trail_day", true)
	_add_apply_button("Run agent campaign live day", "agent_campaign_live_day", true)
	_rebuild_incomplete_loops_section()

func _rebuild_incomplete_loops_section() -> void:
	_add_section_title("— Next-110 incomplete loops (20) —")
	var plain_methods: PackedStringArray = [
		"format_live_mut_board_day_plain",
		"format_feedback_chain_day_plain",
		"format_mut_close_stack_day_plain",
		"format_dual_domain_mutate_day_plain",
		"format_assault_mut_fb_day_plain",
		"format_agent_mut_log_day_plain",
		"format_supply_mut_fb_day_plain",
		"format_combat_surface_stack_day_plain",
		"format_phase_timeline_stack_day_plain",
		"format_assault_rank_card_day_plain",
		"format_joint_naval_land_day_plain",
		"format_multi_front_surface_day_plain",
		"format_combat_depth_strip_day_plain",
		"format_phase_estimate_ribbon_day_plain",
		"format_fleet_path_stack_day_plain",
		"format_basing_mission_day_plain",
		"format_hh_path_stack_day_plain",
		"format_hh_trail_counter_day_plain",
		"format_agent_mission_path_day_plain",
		"format_incomplete_loop_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run live mut board day", "live_mut_board_day", true)
	_add_apply_button("Run feedback chain day", "feedback_chain_day", true)
	_add_apply_button("Run mut close stack day", "mut_close_stack_day", true)
	_add_apply_button("Run dual domain mutate day", "dual_domain_mutate_day", true)
	_add_apply_button("Run assault mut fb day", "assault_mut_fb_day", true)
	_add_apply_button("Run agent mut log day", "agent_mut_log_day", true)
	_add_apply_button("Run supply mut fb day", "supply_mut_fb_day", true)
	_add_apply_button("Run combat surface stack day", "combat_surface_stack_day", true)
	_add_apply_button("Run phase timeline stack day", "phase_timeline_stack_day", true)
	_add_apply_button("Run assault rank card day", "assault_rank_card_day", true)
	_add_apply_button("Run joint naval land day", "joint_naval_land_day", true)
	_add_apply_button("Run multi front surface day", "multi_front_surface_day", true)
	_add_apply_button("Run combat depth strip day", "combat_depth_strip_day", true)
	_add_apply_button("Run phase estimate ribbon day", "phase_estimate_ribbon_day", true)
	_add_apply_button("Run fleet path stack day", "fleet_path_stack_day", true)
	_add_apply_button("Run basing mission day", "basing_mission_day", true)
	_add_apply_button("Run hh path stack day", "hh_path_stack_day", true)
	_add_apply_button("Run hh trail counter day", "hh_trail_counter_day", true)
	_add_apply_button("Run agent mission path day", "agent_mission_path_day", true)
	_add_apply_button("Run incomplete loop close day", "incomplete_loop_close_day", true)
	_rebuild_industry_save_section()

func _rebuild_industry_save_section() -> void:
	_add_section_title("— Next-120 industry/save (20) —")
	var plain_methods: PackedStringArray = [
		"format_prod_mut_apply_day_plain",
		"format_supply_mut_apply_day_plain",
		"format_execute_prod_live_day_plain",
		"format_day_budget_apply_day_plain",
		"format_apply_audit_live_day_plain",
		"format_live_apply_results_day_plain",
		"format_mutation_gate_apply_day_plain",
		"format_daily_prod_auto_live_day_plain",
		"format_theater_prod_live_day_plain",
		"format_prod_campaign_risk_day_plain",
		"format_prod_wx_stack_day_plain",
		"format_factory_risk_live_day_plain",
		"format_depot_prod_stack_day_plain",
		"format_industry_close_loop_day_plain",
		"format_save_slot_surface_day_plain",
		"format_save_browser_live_day_plain",
		"format_campaign_continuity_day_plain",
		"format_ops_dash_continuity_day_plain",
		"format_execution_gate_cont_day_plain",
		"format_industry_save_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run prod mut apply day", "prod_mut_apply_day", true)
	_add_apply_button("Run supply mut apply day", "supply_mut_apply_day", true)
	_add_apply_button("Run execute prod live day", "execute_prod_live_day", true)
	_add_apply_button("Run day budget apply day", "day_budget_apply_day", true)
	_add_apply_button("Run apply audit live day", "apply_audit_live_day", true)
	_add_apply_button("Run live apply results day", "live_apply_results_day", true)
	_add_apply_button("Run mutation gate apply day", "mutation_gate_apply_day", true)
	_add_apply_button("Run daily prod auto live day", "daily_prod_auto_live_day", true)
	_add_apply_button("Run theater prod live day", "theater_prod_live_day", true)
	_add_apply_button("Run prod campaign risk day", "prod_campaign_risk_day", true)
	_add_apply_button("Run prod wx stack day", "prod_wx_stack_day", true)
	_add_apply_button("Run factory risk live day", "factory_risk_live_day", true)
	_add_apply_button("Run depot prod stack day", "depot_prod_stack_day", true)
	_add_apply_button("Run industry close loop day", "industry_close_loop_day", true)
	_add_apply_button("Run save slot surface day", "save_slot_surface_day", true)
	_add_apply_button("Run save browser live day", "save_browser_live_day", true)
	_add_apply_button("Run campaign continuity day", "campaign_continuity_day", true)
	_add_apply_button("Run ops dash continuity day", "ops_dash_continuity_day", true)
	_add_apply_button("Run execution gate cont day", "execution_gate_cont_day", true)
	_add_apply_button("Run industry save close day", "industry_save_close_day", true)
	_rebuild_fleet_hh_combat_section()

func _rebuild_fleet_hh_combat_section() -> void:
	_add_section_title("— Next-130 fleet/HH/combat (20) —")
	var plain_methods: PackedStringArray = [
		"format_fleet_ai_task_day_plain",
		"format_fleet_wx_ops_day_plain",
		"format_basing_fuel_ops_day_plain",
		"format_naval_phase_ops_day_plain",
		"format_coastal_fog_ops_day_plain",
		"format_fleet_station_mut_day_plain",
		"format_naval_task_mut_day_plain",
		"format_hh_agenda_pick_day_plain",
		"format_hh_agenda_actions_day_plain",
		"format_hh_order_path_day_plain",
		"format_theater_hh_path_day_plain",
		"format_hh_trail_ops_day_plain",
		"format_agent_mission_ops_day_plain",
		"format_agent_campaign_ops_day_plain",
		"format_combat_inspect_stack_day_plain",
		"format_phase_ribbon_inspect_day_plain",
		"format_joint_timeline_inspect_day_plain",
		"format_assault_rank_inspect_day_plain",
		"format_combat_campaign_ops_day_plain",
		"format_fleet_hh_combat_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run fleet ai task day", "fleet_ai_task_day", true)
	_add_apply_button("Run fleet wx ops day", "fleet_wx_ops_day", true)
	_add_apply_button("Run basing fuel ops day", "basing_fuel_ops_day", true)
	_add_apply_button("Run naval phase ops day", "naval_phase_ops_day", true)
	_add_apply_button("Run coastal fog ops day", "coastal_fog_ops_day", true)
	_add_apply_button("Run fleet station mut day", "fleet_station_mut_day", true)
	_add_apply_button("Run naval task mut day", "naval_task_mut_day", true)
	_add_apply_button("Run hh agenda pick day", "hh_agenda_pick_day", true)
	_add_apply_button("Run hh agenda actions day", "hh_agenda_actions_day", true)
	_add_apply_button("Run hh order path day", "hh_order_path_day", true)
	_add_apply_button("Run theater hh path day", "theater_hh_path_day", true)
	_add_apply_button("Run hh trail ops day", "hh_trail_ops_day", true)
	_add_apply_button("Run agent mission ops day", "agent_mission_ops_day", true)
	_add_apply_button("Run agent campaign ops day", "agent_campaign_ops_day", true)
	_add_apply_button("Run combat inspect stack day", "combat_inspect_stack_day", true)
	_add_apply_button("Run phase ribbon inspect day", "phase_ribbon_inspect_day", true)
	_add_apply_button("Run joint timeline inspect day", "joint_timeline_inspect_day", true)
	_add_apply_button("Run assault rank inspect day", "assault_rank_inspect_day", true)
	_add_apply_button("Run combat campaign ops day", "combat_campaign_ops_day", true)
	_add_apply_button("Run fleet hh combat close day", "fleet_hh_combat_close_day", true)
	_rebuild_logistics_force_panel_section()
	_rebuild_weather_economy_intel_section()
	_rebuild_theater_naval_session_section()
	_rebuild_combat_agent_joint_section()
	_rebuild_prod_air_focus_section()
	_rebuild_save_leader_trade_section()
	_rebuild_inspector_infra_auto_section()
	_rebuild_assault_choke_agent_section()
	_rebuild_oob_fleet_hh_section()
	_rebuild_force_weather_focus_section()
	_rebuild_air_convoy_order_section()
	_rebuild_leader_intel_theater_section()
	_rebuild_save_prod_combat_section()
	_rebuild_naval_theater_inspector_section()
	_rebuild_weather_economy_force_section()
	_rebuild_full_game_campaign_section()
	_rebuild_playability_campaign_section()
	_rebuild_advanced_deferred_section()
	_rebuild_diplomacy_tech_section()
	_rebuild_world_class_depth_section()
	_rebuild_economy_weather_front_section()
	_rebuild_occupation_manpower_leader_section()
	_rebuild_production_honesty_section()
	_rebuild_apply_queue_live_section()
	_rebuild_phase2_conquest_section()
	_rebuild_phase3_depth_section()
	_rebuild_phase4_depth_section()
	_rebuild_phase5_depth_section()
	_rebuild_phase6_depth_section()
	_rebuild_phase7_depth_section()
	_rebuild_phase8_designers_section()
	_rebuild_phase9_cycle_section()
	_rebuild_phase10_gs_section()
	_rebuild_phase11_depth_section()

func _rebuild_logistics_force_panel_section() -> void:
	_add_section_title("— Next-140 logistics/force/panel (20) —")
	var plain_methods: PackedStringArray = [
		"format_depot_logistics_day_plain",
		"format_supply_route_ops_day_plain",
		"format_move_path_ops_day_plain",
		"format_multi_province_ops_day_plain",
		"format_theater_auto_tick_day_plain",
		"format_daily_supply_ops_day_plain",
		"format_logistics_theater_close_day_plain",
		"format_force_readiness_ops_day_plain",
		"format_oob_factory_ops_day_plain",
		"format_medium_equip_ops_day_plain",
		"format_naval_skim_ops_day_plain",
		"format_basing_logistics_ops_day_plain",
		"format_production_force_ops_day_plain",
		"format_force_oob_close_day_plain",
		"format_player_surface_ops_day_plain",
		"format_order_panel_ops_day_plain",
		"format_panel_sections_ops_day_plain",
		"format_tooltip_flair_ops_day_plain",
		"format_apply_audit_ops_day_plain",
		"format_logistics_force_panel_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run depot logistics day", "depot_logistics_day", true)
	_add_apply_button("Run supply route ops day", "supply_route_ops_day", true)
	_add_apply_button("Run move path ops day", "move_path_ops_day", true)
	_add_apply_button("Run multi province ops day", "multi_province_ops_day", true)
	_add_apply_button("Run theater auto tick day", "theater_auto_tick_day", true)
	_add_apply_button("Run daily supply ops day", "daily_supply_ops_day", true)
	_add_apply_button("Run logistics theater close day", "logistics_theater_close_day", true)
	_add_apply_button("Run force readiness ops day", "force_readiness_ops_day", true)
	_add_apply_button("Run oob factory ops day", "oob_factory_ops_day", true)
	_add_apply_button("Run medium equip ops day", "medium_equip_ops_day", true)
	_add_apply_button("Run naval skim ops day", "naval_skim_ops_day", true)
	_add_apply_button("Run basing logistics ops day", "basing_logistics_ops_day", true)
	_add_apply_button("Run production force ops day", "production_force_ops_day", true)
	_add_apply_button("Run force oob close day", "force_oob_close_day", true)
	_add_apply_button("Run player surface ops day", "player_surface_ops_day", true)
	_add_apply_button("Run order panel ops day", "order_panel_ops_day", true)
	_add_apply_button("Run panel sections ops day", "panel_sections_ops_day", true)
	_add_apply_button("Run tooltip flair ops day", "tooltip_flair_ops_day", true)
	_add_apply_button("Run apply audit ops day", "apply_audit_ops_day", true)
	_add_apply_button("Run logistics force panel close day", "logistics_force_panel_close_day", true)

func _rebuild_weather_economy_intel_section() -> void:
	_add_section_title("— Next-150 weather/economy/intel (20) —")
	var plain_methods: PackedStringArray = [
		"format_combat_wx_ops_day_plain",
		"format_prod_wx_ops_day_plain",
		"format_air_sortie_wx_day_plain",
		"format_morale_wx_ops_day_plain",
		"format_convoy_wx_ops_day_plain",
		"format_daylight_wx_ops_day_plain",
		"format_weather_ops_close_day_plain",
		"format_war_economy_ops_day_plain",
		"format_prod_campaign_ops_day_plain",
		"format_focus_wx_ops_day_plain",
		"format_focus_mut_ops_day_plain",
		"format_supply_economy_ops_day_plain",
		"format_depot_economy_ops_day_plain",
		"format_war_economy_close_day_plain",
		"format_intel_counter_ops_day_plain",
		"format_agent_intel_ops_day_plain",
		"format_hh_counter_ops_day_plain",
		"format_map_effect_ops_day_plain",
		"format_coherence_intel_day_plain",
		"format_weather_economy_intel_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run combat wx ops day", "combat_wx_ops_day", true)
	_add_apply_button("Run prod wx ops day", "prod_wx_ops_day", true)
	_add_apply_button("Run air sortie wx day", "air_sortie_wx_day", true)
	_add_apply_button("Run morale wx ops day", "morale_wx_ops_day", true)
	_add_apply_button("Run convoy wx ops day", "convoy_wx_ops_day", true)
	_add_apply_button("Run daylight wx ops day", "daylight_wx_ops_day", true)
	_add_apply_button("Run weather ops close day", "weather_ops_close_day", true)
	_add_apply_button("Run war economy ops day", "war_economy_ops_day", true)
	_add_apply_button("Run prod campaign ops day", "prod_campaign_ops_day", true)
	_add_apply_button("Run focus wx ops day", "focus_wx_ops_day", true)
	_add_apply_button("Run focus mut ops day", "focus_mut_ops_day", true)
	_add_apply_button("Run supply economy ops day", "supply_economy_ops_day", true)
	_add_apply_button("Run depot economy ops day", "depot_economy_ops_day", true)
	_add_apply_button("Run war economy close day", "war_economy_close_day", true)
	_add_apply_button("Run intel counter ops day", "intel_counter_ops_day", true)
	_add_apply_button("Run agent intel ops day", "agent_intel_ops_day", true)
	_add_apply_button("Run hh counter ops day", "hh_counter_ops_day", true)
	_add_apply_button("Run map effect ops day", "map_effect_ops_day", true)
	_add_apply_button("Run coherence intel day", "coherence_intel_day", true)
	_add_apply_button("Run weather economy intel close day", "weather_economy_intel_close_day", true)

func _rebuild_theater_naval_session_section() -> void:
	_add_section_title("— Next-160 theater/naval/session (20) —")
	var plain_methods: PackedStringArray = [
		"format_multi_province_campaign_day_plain",
		"format_theater_auto_campaign_day_plain",
		"format_daily_command_ops_day_plain",
		"format_theater_readiness_ops_day_plain",
		"format_move_path_campaign_day_plain",
		"format_theater_order_board_day_plain",
		"format_theater_campaign_close_day_plain",
		"format_basing_fleet_sustain_day_plain",
		"format_fleet_wx_sustain_day_plain",
		"format_convoy_sustain_ops_day_plain",
		"format_sealane_joint_ops_day_plain",
		"format_naval_order_ops_day_plain",
		"format_fleet_station_sustain_day_plain",
		"format_naval_sealane_close_day_plain",
		"format_player_surface_session_day_plain",
		"format_order_panel_session_day_plain",
		"format_mutation_feedback_ops_day_plain",
		"format_apply_audit_session_day_plain",
		"format_decision_strip_ops_day_plain",
		"format_theater_naval_session_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run multi province campaign day", "multi_province_campaign_day", true)
	_add_apply_button("Run theater auto campaign day", "theater_auto_campaign_day", true)
	_add_apply_button("Run daily command ops day", "daily_command_ops_day", true)
	_add_apply_button("Run theater readiness ops day", "theater_readiness_ops_day", true)
	_add_apply_button("Run move path campaign day", "move_path_campaign_day", true)
	_add_apply_button("Run theater order board day", "theater_order_board_day", true)
	_add_apply_button("Run theater campaign close day", "theater_campaign_close_day", true)
	_add_apply_button("Run basing fleet sustain day", "basing_fleet_sustain_day", true)
	_add_apply_button("Run fleet wx sustain day", "fleet_wx_sustain_day", true)
	_add_apply_button("Run convoy sustain ops day", "convoy_sustain_ops_day", true)
	_add_apply_button("Run sealane joint ops day", "sealane_joint_ops_day", true)
	_add_apply_button("Run naval order ops day", "naval_order_ops_day", true)
	_add_apply_button("Run fleet station sustain day", "fleet_station_sustain_day", true)
	_add_apply_button("Run naval sealane close day", "naval_sealane_close_day", true)
	_add_apply_button("Run player surface session day", "player_surface_session_day", true)
	_add_apply_button("Run order panel session day", "order_panel_session_day", true)
	_add_apply_button("Run mutation feedback ops day", "mutation_feedback_ops_day", true)
	_add_apply_button("Run apply audit session day", "apply_audit_session_day", true)
	_add_apply_button("Run decision strip ops day", "decision_strip_ops_day", true)
	_add_apply_button("Run theater naval session close day", "theater_naval_session_close_day", true)

func _rebuild_combat_agent_joint_section() -> void:
	_add_section_title("— Next-170 combat/agent/joint (20) —")
	var plain_methods: PackedStringArray = [
		"format_combat_phase_ops_day_plain",
		"format_assault_ready_ops_day_plain",
		"format_multi_phase_est_ops_day_plain",
		"format_combat_order_ops_day_plain",
		"format_assault_rank_ops_day_plain",
		"format_phase_ribbon_ops_day_plain",
		"format_combat_phase_close_day_plain",
		"format_agent_mission_campaign_day_plain",
		"format_agent_dispatch_ops_day_plain",
		"format_hh_commit_campaign_day_plain",
		"format_counterplay_campaign_day_plain",
		"format_hh_agenda_ops_day_plain",
		"format_agent_hh_joint_day_plain",
		"format_agent_hh_close_day_plain",
		"format_joint_theater_combat_day_plain",
		"format_joint_naval_combat_day_plain",
		"format_focus_joint_ops_day_plain",
		"format_joint_command_ops_day_plain",
		"format_multi_domain_strip_day_plain",
		"format_combat_agent_joint_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run combat phase ops day", "combat_phase_ops_day", true)
	_add_apply_button("Run assault ready ops day", "assault_ready_ops_day", true)
	_add_apply_button("Run multi phase est ops day", "multi_phase_est_ops_day", true)
	_add_apply_button("Run combat order ops day", "combat_order_ops_day", true)
	_add_apply_button("Run assault rank ops day", "assault_rank_ops_day", true)
	_add_apply_button("Run phase ribbon ops day", "phase_ribbon_ops_day", true)
	_add_apply_button("Run combat phase close day", "combat_phase_close_day", true)
	_add_apply_button("Run agent mission campaign day", "agent_mission_campaign_day", true)
	_add_apply_button("Run agent dispatch ops day", "agent_dispatch_ops_day", true)
	_add_apply_button("Run hh commit campaign day", "hh_commit_campaign_day", true)
	_add_apply_button("Run counterplay campaign day", "counterplay_campaign_day", true)
	_add_apply_button("Run hh agenda ops day", "hh_agenda_ops_day", true)
	_add_apply_button("Run agent hh joint day", "agent_hh_joint_day", true)
	_add_apply_button("Run agent hh close day", "agent_hh_close_day", true)
	_add_apply_button("Run joint theater combat day", "joint_theater_combat_day", true)
	_add_apply_button("Run joint naval combat day", "joint_naval_combat_day", true)
	_add_apply_button("Run focus joint ops day", "focus_joint_ops_day", true)
	_add_apply_button("Run joint command ops day", "joint_command_ops_day", true)
	_add_apply_button("Run multi domain strip day", "multi_domain_strip_day", true)
	_add_apply_button("Run combat agent joint close day", "combat_agent_joint_close_day", true)

func _rebuild_prod_air_focus_section() -> void:
	_add_section_title("— Next-180 production/air/focus (20) —")
	var plain_methods: PackedStringArray = [
		"format_prod_factory_risk_ops_day_plain",
		"format_medium_equip_horizon_ops_day_plain",
		"format_production_priority_ops_day_plain",
		"format_oob_equip_continuity_day_plain",
		"format_factory_line_ops_day_plain",
		"format_stockpile_growth_ops_day_plain",
		"format_production_oob_close_day_plain",
		"format_air_sortie_front_ops_day_plain",
		"format_multi_front_rank_ops_day_plain",
		"format_air_land_joint_ops_day_plain",
		"format_assault_front_ops_day_plain",
		"format_air_forecast_ops_day_plain",
		"format_multi_front_supply_ops_day_plain",
		"format_air_front_close_day_plain",
		"format_focus_path_ops_day_plain",
		"format_war_cabinet_ops_day_plain",
		"format_strategic_strip_ops_day_plain",
		"format_focus_priority_ops_day_plain",
		"format_strategic_continuity_ops_day_plain",
		"format_prod_air_focus_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run prod factory risk ops day", "prod_factory_risk_ops_day", true)
	_add_apply_button("Run medium equip horizon ops day", "medium_equip_horizon_ops_day", true)
	_add_apply_button("Run production priority ops day", "production_priority_ops_day", true)
	_add_apply_button("Run oob equip continuity day", "oob_equip_continuity_day", true)
	_add_apply_button("Run factory line ops day", "factory_line_ops_day", true)
	_add_apply_button("Run stockpile growth ops day", "stockpile_growth_ops_day", true)
	_add_apply_button("Run production oob close day", "production_oob_close_day", true)
	_add_apply_button("Run air sortie front ops day", "air_sortie_front_ops_day", true)
	_add_apply_button("Run multi front rank ops day", "multi_front_rank_ops_day", true)
	_add_apply_button("Run air land joint ops day", "air_land_joint_ops_day", true)
	_add_apply_button("Run assault front ops day", "assault_front_ops_day", true)
	_add_apply_button("Run air forecast ops day", "air_forecast_ops_day", true)
	_add_apply_button("Run multi front supply ops day", "multi_front_supply_ops_day", true)
	_add_apply_button("Run air front close day", "air_front_close_day", true)
	_add_apply_button("Run focus path ops day", "focus_path_ops_day", true)
	_add_apply_button("Run war cabinet ops day", "war_cabinet_ops_day", true)
	_add_apply_button("Run strategic strip ops day", "strategic_strip_ops_day", true)
	_add_apply_button("Run focus priority ops day", "focus_priority_ops_day", true)
	_add_apply_button("Run strategic continuity ops day", "strategic_continuity_ops_day", true)
	_add_apply_button("Run prod air focus close day", "prod_air_focus_close_day", true)

func _rebuild_save_leader_trade_section() -> void:
	_add_section_title("— Next-190 save/leader/trade (20) —")
	var plain_methods: PackedStringArray = [
		"format_save_slot_integrity_ops_day_plain",
		"format_autosave_session_ops_day_plain",
		"format_campaign_session_ops_day_plain",
		"format_save_resume_ops_day_plain",
		"format_session_checkpoint_ops_day_plain",
		"format_save_audit_ops_day_plain",
		"format_save_session_close_day_plain",
		"format_leader_assign_ops_day_plain",
		"format_formation_ready_ops_day_plain",
		"format_oob_assign_ops_day_plain",
		"format_leader_command_ops_day_plain",
		"format_formation_station_ops_day_plain",
		"format_leader_formation_joint_day_plain",
		"format_leader_formation_close_day_plain",
		"format_trade_chain_ops_day_plain",
		"format_convoy_escort_ops_day_plain",
		"format_sealane_economy_ops_day_plain",
		"format_trade_route_ops_day_plain",
		"format_convoy_trade_joint_day_plain",
		"format_save_leader_trade_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run save slot integrity ops day", "save_slot_integrity_ops_day", true)
	_add_apply_button("Run autosave session ops day", "autosave_session_ops_day", true)
	_add_apply_button("Run campaign session ops day", "campaign_session_ops_day", true)
	_add_apply_button("Run save resume ops day", "save_resume_ops_day", true)
	_add_apply_button("Run session checkpoint ops day", "session_checkpoint_ops_day", true)
	_add_apply_button("Run save audit ops day", "save_audit_ops_day", true)
	_add_apply_button("Run save session close day", "save_session_close_day", true)
	_add_apply_button("Run leader assign ops day", "leader_assign_ops_day", true)
	_add_apply_button("Run formation ready ops day", "formation_ready_ops_day", true)
	_add_apply_button("Run oob assign ops day", "oob_assign_ops_day", true)
	_add_apply_button("Run leader command ops day", "leader_command_ops_day", true)
	_add_apply_button("Run formation station ops day", "formation_station_ops_day", true)
	_add_apply_button("Run leader formation joint day", "leader_formation_joint_day", true)
	_add_apply_button("Run leader formation close day", "leader_formation_close_day", true)
	_add_apply_button("Run trade chain ops day", "trade_chain_ops_day", true)
	_add_apply_button("Run convoy escort ops day", "convoy_escort_ops_day", true)
	_add_apply_button("Run sealane economy ops day", "sealane_economy_ops_day", true)
	_add_apply_button("Run trade route ops day", "trade_route_ops_day", true)
	_add_apply_button("Run convoy trade joint day", "convoy_trade_joint_day", true)
	_add_apply_button("Run save leader trade close day", "save_leader_trade_close_day", true)

func _rebuild_inspector_infra_auto_section() -> void:
	_add_section_title("— Next-200 inspector/infra/auto (20) —")
	var plain_methods: PackedStringArray = [
		"format_panel_surface_ops_day_plain",
		"format_tooltip_chip_ops_day_plain",
		"format_insight_budget_ops_day_plain",
		"format_order_surface_ops_day_plain",
		"format_product_chip_ops_day_plain",
		"format_surface_refresh_ops_day_plain",
		"format_inspector_surface_close_day_plain",
		"format_infra_invest_ops_day_plain",
		"format_special_site_ops_day_plain",
		"format_construction_ops_day_plain",
		"format_infra_project_ops_day_plain",
		"format_investment_status_ops_day_plain",
		"format_infra_site_joint_day_plain",
		"format_infra_invest_close_day_plain",
		"format_daily_auto_ops_day_plain",
		"format_theater_tick_ops_day_plain",
		"format_multi_domain_auto_ops_day_plain",
		"format_daily_apply_ops_day_plain",
		"format_theater_auto_joint_day_plain",
		"format_inspector_infra_auto_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run panel surface ops day", "panel_surface_ops_day", true)
	_add_apply_button("Run tooltip chip ops day", "tooltip_chip_ops_day", true)
	_add_apply_button("Run insight budget ops day", "insight_budget_ops_day", true)
	_add_apply_button("Run order surface ops day", "order_surface_ops_day", true)
	_add_apply_button("Run product chip ops day", "product_chip_ops_day", true)
	_add_apply_button("Run surface refresh ops day", "surface_refresh_ops_day", true)
	_add_apply_button("Run inspector surface close day", "inspector_surface_close_day", true)
	_add_apply_button("Run infra invest ops day", "infra_invest_ops_day", true)
	_add_apply_button("Run special site ops day", "special_site_ops_day", true)
	_add_apply_button("Run construction ops day", "construction_ops_day", true)
	_add_apply_button("Run infra project ops day", "infra_project_ops_day", true)
	_add_apply_button("Run investment status ops day", "investment_status_ops_day", true)
	_add_apply_button("Run infra site joint day", "infra_site_joint_day", true)
	_add_apply_button("Run infra invest close day", "infra_invest_close_day", true)
	_add_apply_button("Run daily auto ops day", "daily_auto_ops_day", true)
	_add_apply_button("Run theater tick ops day", "theater_tick_ops_day", true)
	_add_apply_button("Run multi domain auto ops day", "multi_domain_auto_ops_day", true)
	_add_apply_button("Run daily apply ops day", "daily_apply_ops_day", true)
	_add_apply_button("Run theater auto joint day", "theater_auto_joint_day", true)
	_add_apply_button("Run inspector infra auto close day", "inspector_infra_auto_close_day", true)

func _rebuild_assault_choke_agent_section() -> void:
	_add_section_title("— Next-210 assault/choke/agent (20) —")
	var plain_methods: PackedStringArray = [
		"format_follow_on_assault_ops_day_plain",
		"format_reinforced_combat_ops_day_plain",
		"format_war_path_urgency_ops_day_plain",
		"format_assault_follow_ops_day_plain",
		"format_reinforce_step_ops_day_plain",
		"format_combat_urgency_ops_day_plain",
		"format_follow_reinforce_close_day_plain",
		"format_choke_sea_wx_ops_day_plain",
		"format_sea_zone_mod_ops_day_plain",
		"format_basing_choke_ops_day_plain",
		"format_choke_control_ops_day_plain",
		"format_sea_zone_control_ops_day_plain",
		"format_choke_basing_joint_day_plain",
		"format_choke_sea_close_day_plain",
		"format_agent_escalation_ops_day_plain",
		"format_coverage_ops_day_plain",
		"format_counter_ops_board_ops_day_plain",
		"format_escalation_ladder_ops_day_plain",
		"format_agent_coverage_joint_day_plain",
		"format_assault_choke_agent_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run follow on assault ops day", "follow_on_assault_ops_day", true)
	_add_apply_button("Run reinforced combat ops day", "reinforced_combat_ops_day", true)
	_add_apply_button("Run war path urgency ops day", "war_path_urgency_ops_day", true)
	_add_apply_button("Run assault follow ops day", "assault_follow_ops_day", true)
	_add_apply_button("Run reinforce step ops day", "reinforce_step_ops_day", true)
	_add_apply_button("Run combat urgency ops day", "combat_urgency_ops_day", true)
	_add_apply_button("Run follow reinforce close day", "follow_reinforce_close_day", true)
	_add_apply_button("Run choke sea wx ops day", "choke_sea_wx_ops_day", true)
	_add_apply_button("Run sea zone mod ops day", "sea_zone_mod_ops_day", true)
	_add_apply_button("Run basing choke ops day", "basing_choke_ops_day", true)
	_add_apply_button("Run choke control ops day", "choke_control_ops_day", true)
	_add_apply_button("Run sea zone control ops day", "sea_zone_control_ops_day", true)
	_add_apply_button("Run choke basing joint day", "choke_basing_joint_day", true)
	_add_apply_button("Run choke sea close day", "choke_sea_close_day", true)
	_add_apply_button("Run agent escalation ops day", "agent_escalation_ops_day", true)
	_add_apply_button("Run coverage ops day", "coverage_ops_day", true)
	_add_apply_button("Run counter ops board ops day", "counter_ops_board_ops_day", true)
	_add_apply_button("Run escalation ladder ops day", "escalation_ladder_ops_day", true)
	_add_apply_button("Run agent coverage joint day", "agent_coverage_joint_day", true)
	_add_apply_button("Run assault choke agent close day", "assault_choke_agent_close_day", true)

func _rebuild_oob_fleet_hh_section() -> void:
	_add_section_title("— Next-220 oob/fleet/hh (20) —")
	var plain_methods: PackedStringArray = [
		"format_equip_horizon_depth_day_plain",
		"format_stockpile_line_ops_day_plain",
		"format_oob_line_continuity_day_plain",
		"format_factory_oob_depth_day_plain",
		"format_medium_horizon_plan_day_plain",
		"format_equip_stockpile_joint_day_plain",
		"format_equip_oob_close_day_plain",
		"format_fleet_multi_theater_ops_day_plain",
		"format_fleet_redeploy_ops_day_plain",
		"format_task_group_posture_ops_day_plain",
		"format_fleet_posture_ops_day_plain",
		"format_redeploy_route_ops_day_plain",
		"format_fleet_theater_joint_day_plain",
		"format_fleet_redeploy_close_day_plain",
		"format_hh_monthly_ops_day_plain",
		"format_hh_quarterly_ops_day_plain",
		"format_agenda_pulse_ops_day_plain",
		"format_trail_counterplay_ops_day_plain",
		"format_hh_agenda_depth_joint_day_plain",
		"format_oob_fleet_hh_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run equip horizon depth day", "equip_horizon_depth_day", true)
	_add_apply_button("Run stockpile line ops day", "stockpile_line_ops_day", true)
	_add_apply_button("Run oob line continuity day", "oob_line_continuity_day", true)
	_add_apply_button("Run factory oob depth day", "factory_oob_depth_day", true)
	_add_apply_button("Run medium horizon plan day", "medium_horizon_plan_day", true)
	_add_apply_button("Run equip stockpile joint day", "equip_stockpile_joint_day", true)
	_add_apply_button("Run equip oob close day", "equip_oob_close_day", true)
	_add_apply_button("Run fleet multi theater ops day", "fleet_multi_theater_ops_day", true)
	_add_apply_button("Run fleet redeploy ops day", "fleet_redeploy_ops_day", true)
	_add_apply_button("Run task group posture ops day", "task_group_posture_ops_day", true)
	_add_apply_button("Run fleet posture ops day", "fleet_posture_ops_day", true)
	_add_apply_button("Run redeploy route ops day", "redeploy_route_ops_day", true)
	_add_apply_button("Run fleet theater joint day", "fleet_theater_joint_day", true)
	_add_apply_button("Run fleet redeploy close day", "fleet_redeploy_close_day", true)
	_add_apply_button("Run hh monthly ops day", "hh_monthly_ops_day", true)
	_add_apply_button("Run hh quarterly ops day", "hh_quarterly_ops_day", true)
	_add_apply_button("Run agenda pulse ops day", "agenda_pulse_ops_day", true)
	_add_apply_button("Run trail counterplay ops day", "trail_counterplay_ops_day", true)
	_add_apply_button("Run hh agenda depth joint day", "hh_agenda_depth_joint_day", true)
	_add_apply_button("Run oob fleet hh close day", "oob_fleet_hh_close_day", true)

func _rebuild_force_weather_focus_section() -> void:
	_add_section_title("— Next-230 force/weather/focus (20) —")
	var plain_methods: PackedStringArray = [
		"format_force_readiness_depth_day_plain",
		"format_multi_front_supply_depth_day_plain",
		"format_depot_route_ops_day_plain",
		"format_force_posture_depth_day_plain",
		"format_front_supply_rank_day_plain",
		"format_force_supply_joint_day_plain",
		"format_force_supply_close_day_plain",
		"format_weather_pressure_ops_day_plain",
		"format_campaign_crisis_ops_day_plain",
		"format_prod_weather_crisis_day_plain",
		"format_combat_weather_ops_day_plain",
		"format_weather_crisis_brief_day_plain",
		"format_weather_campaign_joint_day_plain",
		"format_weather_crisis_close_day_plain",
		"format_focus_war_path_ops_day_plain",
		"format_strategic_strip_depth_day_plain",
		"format_strategic_continuity_depth_day_plain",
		"format_war_cabinet_pulse_ops_day_plain",
		"format_focus_continuity_joint_day_plain",
		"format_force_weather_focus_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run force readiness depth day", "force_readiness_depth_day", true)
	_add_apply_button("Run multi front supply depth day", "multi_front_supply_depth_day", true)
	_add_apply_button("Run depot route ops day", "depot_route_ops_day", true)
	_add_apply_button("Run force posture depth day", "force_posture_depth_day", true)
	_add_apply_button("Run front supply rank day", "front_supply_rank_day", true)
	_add_apply_button("Run force supply joint day", "force_supply_joint_day", true)
	_add_apply_button("Run force supply close day", "force_supply_close_day", true)
	_add_apply_button("Run weather pressure ops day", "weather_pressure_ops_day", true)
	_add_apply_button("Run campaign crisis ops day", "campaign_crisis_ops_day", true)
	_add_apply_button("Run prod weather crisis day", "prod_weather_crisis_day", true)
	_add_apply_button("Run combat weather ops day", "combat_weather_ops_day", true)
	_add_apply_button("Run weather crisis brief day", "weather_crisis_brief_day", true)
	_add_apply_button("Run weather campaign joint day", "weather_campaign_joint_day", true)
	_add_apply_button("Run weather crisis close day", "weather_crisis_close_day", true)
	_add_apply_button("Run focus war path ops day", "focus_war_path_ops_day", true)
	_add_apply_button("Run strategic strip depth day", "strategic_strip_depth_day", true)
	_add_apply_button("Run strategic continuity depth day", "strategic_continuity_depth_day", true)
	_add_apply_button("Run war cabinet pulse ops day", "war_cabinet_pulse_ops_day", true)
	_add_apply_button("Run focus continuity joint day", "focus_continuity_joint_day", true)
	_add_apply_button("Run force weather focus close day", "force_weather_focus_close_day", true)

func _rebuild_air_convoy_order_section() -> void:
	_add_section_title("— Next-240 air/convoy/order (20) —")
	var plain_methods: PackedStringArray = [
		"format_air_sortie_depth_day_plain",
		"format_air_land_joint_depth_day_plain",
		"format_multi_domain_ops_day_plain",
		"format_air_front_readiness_day_plain",
		"format_domain_joint_ops_day_plain",
		"format_air_land_campaign_day_plain",
		"format_air_domain_close_day_plain",
		"format_convoy_escort_depth_day_plain",
		"format_sealane_health_ops_day_plain",
		"format_trade_pressure_ops_day_plain",
		"format_convoy_sealane_joint_day_plain",
		"format_sealane_logistics_ops_day_plain",
		"format_wartime_trade_ops_day_plain",
		"format_convoy_sealane_close_day_plain",
		"format_order_execute_depth_day_plain",
		"format_map_effect_resolve_day_plain",
		"format_next_day_feedback_depth_day_plain",
		"format_order_effect_joint_day_plain",
		"format_feedback_loop_ops_day_plain",
		"format_air_convoy_order_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run air sortie depth day", "air_sortie_depth_day", true)
	_add_apply_button("Run air land joint depth day", "air_land_joint_depth_day", true)
	_add_apply_button("Run multi domain ops day", "multi_domain_ops_day", true)
	_add_apply_button("Run air front readiness day", "air_front_readiness_day", true)
	_add_apply_button("Run domain joint ops day", "domain_joint_ops_day", true)
	_add_apply_button("Run air land campaign day", "air_land_campaign_day", true)
	_add_apply_button("Run air domain close day", "air_domain_close_day", true)
	_add_apply_button("Run convoy escort depth day", "convoy_escort_depth_day", true)
	_add_apply_button("Run sealane health ops day", "sealane_health_ops_day", true)
	_add_apply_button("Run trade pressure ops day", "trade_pressure_ops_day", true)
	_add_apply_button("Run convoy sealane joint day", "convoy_sealane_joint_day", true)
	_add_apply_button("Run sealane logistics ops day", "sealane_logistics_ops_day", true)
	_add_apply_button("Run wartime trade ops day", "wartime_trade_ops_day", true)
	_add_apply_button("Run convoy sealane close day", "convoy_sealane_close_day", true)
	_add_apply_button("Run order execute depth day", "order_execute_depth_day", true)
	_add_apply_button("Run map effect resolve day", "map_effect_resolve_day", true)
	_add_apply_button("Run next day feedback depth day", "next_day_feedback_depth_day", true)
	_add_apply_button("Run order effect joint day", "order_effect_joint_day", true)
	_add_apply_button("Run feedback loop ops day", "feedback_loop_ops_day", true)
	_add_apply_button("Run air convoy order close day", "air_convoy_order_close_day", true)

func _rebuild_leader_intel_theater_section() -> void:
	_add_section_title("— Next-250 leader/intel/theater (20) —")
	var plain_methods: PackedStringArray = [
		"format_leader_assign_depth_day_plain",
		"format_formation_ready_depth_day_plain",
		"format_leader_weather_depth_day_plain",
		"format_formation_station_depth_day_plain",
		"format_leader_formation_joint_depth_day_plain",
		"format_oob_leader_ops_day_plain",
		"format_leader_formation_close_depth_day_plain",
		"format_intel_counter_depth_day_plain",
		"format_hh_counterplay_depth_day_plain",
		"format_agent_response_depth_day_plain",
		"format_trail_intel_ops_day_plain",
		"format_counterintel_board_ops_day_plain",
		"format_intel_response_joint_day_plain",
		"format_intel_counter_close_day_plain",
		"format_theater_daily_depth_day_plain",
		"format_multi_province_rank_depth_day_plain",
		"format_daily_auto_depth_day_plain",
		"format_theater_brief_ops_day_plain",
		"format_multi_province_command_day_plain",
		"format_leader_intel_theater_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run leader assign depth day", "leader_assign_depth_day", true)
	_add_apply_button("Run formation ready depth day", "formation_ready_depth_day", true)
	_add_apply_button("Run leader weather depth day", "leader_weather_depth_day", true)
	_add_apply_button("Run formation station depth day", "formation_station_depth_day", true)
	_add_apply_button("Run leader formation joint depth day", "leader_formation_joint_depth_day", true)
	_add_apply_button("Run oob leader ops day", "oob_leader_ops_day", true)
	_add_apply_button("Run leader formation close depth day", "leader_formation_close_depth_day", true)
	_add_apply_button("Run intel counter depth day", "intel_counter_depth_day", true)
	_add_apply_button("Run hh counterplay depth day", "hh_counterplay_depth_day", true)
	_add_apply_button("Run agent response depth day", "agent_response_depth_day", true)
	_add_apply_button("Run trail intel ops day", "trail_intel_ops_day", true)
	_add_apply_button("Run counterintel board ops day", "counterintel_board_ops_day", true)
	_add_apply_button("Run intel response joint day", "intel_response_joint_day", true)
	_add_apply_button("Run intel counter close day", "intel_counter_close_day", true)
	_add_apply_button("Run theater daily depth day", "theater_daily_depth_day", true)
	_add_apply_button("Run multi province rank depth day", "multi_province_rank_depth_day", true)
	_add_apply_button("Run daily auto depth day", "daily_auto_depth_day", true)
	_add_apply_button("Run theater brief ops day", "theater_brief_ops_day", true)
	_add_apply_button("Run multi province command day", "multi_province_command_day", true)
	_add_apply_button("Run leader intel theater close day", "leader_intel_theater_close_day", true)

func _rebuild_save_prod_combat_section() -> void:
	_add_section_title("— Next-260 save/prod/combat (20) —")
	var plain_methods: PackedStringArray = [
		"format_save_slot_depth_day_plain",
		"format_autosave_session_depth_day_plain",
		"format_campaign_session_depth_day_plain",
		"format_save_resume_depth_day_plain",
		"format_session_checkpoint_depth_day_plain",
		"format_save_audit_depth_day_plain",
		"format_save_session_close_depth_day_plain",
		"format_factory_risk_surge_day_plain",
		"format_production_priority_depth_day_plain",
		"format_stockpile_surge_ops_day_plain",
		"format_line_continuity_depth_day_plain",
		"format_industry_surge_joint_day_plain",
		"format_production_oob_depth_day_plain",
		"format_production_surge_close_day_plain",
		"format_multi_phase_estimate_depth_day_plain",
		"format_assault_ready_surface_day_plain",
		"format_combat_order_surface_day_plain",
		"format_phase_product_ops_day_plain",
		"format_multi_phase_joint_day_plain",
		"format_save_prod_combat_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run save slot depth day", "save_slot_depth_day", true)
	_add_apply_button("Run autosave session depth day", "autosave_session_depth_day", true)
	_add_apply_button("Run campaign session depth day", "campaign_session_depth_day", true)
	_add_apply_button("Run save resume depth day", "save_resume_depth_day", true)
	_add_apply_button("Run session checkpoint depth day", "session_checkpoint_depth_day", true)
	_add_apply_button("Run save audit depth day", "save_audit_depth_day", true)
	_add_apply_button("Run save session close depth day", "save_session_close_depth_day", true)
	_add_apply_button("Run factory risk surge day", "factory_risk_surge_day", true)
	_add_apply_button("Run production priority depth day", "production_priority_depth_day", true)
	_add_apply_button("Run stockpile surge ops day", "stockpile_surge_ops_day", true)
	_add_apply_button("Run line continuity depth day", "line_continuity_depth_day", true)
	_add_apply_button("Run industry surge joint day", "industry_surge_joint_day", true)
	_add_apply_button("Run production oob depth day", "production_oob_depth_day", true)
	_add_apply_button("Run production surge close day", "production_surge_close_day", true)
	_add_apply_button("Run multi phase estimate depth day", "multi_phase_estimate_depth_day", true)
	_add_apply_button("Run assault ready surface day", "assault_ready_surface_day", true)
	_add_apply_button("Run combat order surface day", "combat_order_surface_day", true)
	_add_apply_button("Run phase product ops day", "phase_product_ops_day", true)
	_add_apply_button("Run multi phase joint day", "multi_phase_joint_day", true)
	_add_apply_button("Run save prod combat close day", "save_prod_combat_close_day", true)

func _rebuild_naval_theater_inspector_section() -> void:
	_add_section_title("— Next-270 naval/theater/inspector (20) —")
	var plain_methods: PackedStringArray = [
		"format_naval_basing_sustain_day_plain",
		"format_port_fuel_depth_day_plain",
		"format_basing_repair_depth_day_plain",
		"format_fleet_task_sustain_day_plain",
		"format_convoy_basing_joint_day_plain",
		"format_naval_logistics_depth_day_plain",
		"format_naval_basing_close_day_plain",
		"format_multi_day_theater_depth_day_plain",
		"format_theater_campaign_continuity_day_plain",
		"format_campaign_day_chain_day_plain",
		"format_theater_session_ops_day_plain",
		"format_daily_theater_sustain_day_plain",
		"format_theater_continuity_joint_day_plain",
		"format_theater_campaign_depth_close_day_plain",
		"format_inspector_decision_depth_day_plain",
		"format_decision_strip_depth_day_plain",
		"format_insight_strip_depth_day_plain",
		"format_province_decision_joint_day_plain",
		"format_inspector_campaign_ops_day_plain",
		"format_theater_naval_inspector_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run naval basing sustain day", "naval_basing_sustain_day", true)
	_add_apply_button("Run port fuel depth day", "port_fuel_depth_day", true)
	_add_apply_button("Run basing repair depth day", "basing_repair_depth_day", true)
	_add_apply_button("Run fleet task sustain day", "fleet_task_sustain_day", true)
	_add_apply_button("Run convoy basing joint day", "convoy_basing_joint_day", true)
	_add_apply_button("Run naval logistics depth day", "naval_logistics_depth_day", true)
	_add_apply_button("Run naval basing close day", "naval_basing_close_day", true)
	_add_apply_button("Run multi day theater depth day", "multi_day_theater_depth_day", true)
	_add_apply_button("Run theater campaign continuity day", "theater_campaign_continuity_day", true)
	_add_apply_button("Run campaign day chain day", "campaign_day_chain_day", true)
	_add_apply_button("Run theater session ops day", "theater_session_ops_day", true)
	_add_apply_button("Run daily theater sustain day", "daily_theater_sustain_day", true)
	_add_apply_button("Run theater continuity joint day", "theater_continuity_joint_day", true)
	_add_apply_button("Run theater campaign depth close day", "theater_campaign_depth_close_day", true)
	_add_apply_button("Run inspector decision depth day", "inspector_decision_depth_day", true)
	_add_apply_button("Run decision strip depth day", "decision_strip_depth_day", true)
	_add_apply_button("Run insight strip depth day", "insight_strip_depth_day", true)
	_add_apply_button("Run province decision joint day", "province_decision_joint_day", true)
	_add_apply_button("Run inspector campaign ops day", "inspector_campaign_ops_day", true)
	_add_apply_button("Run theater naval inspector close day", "theater_naval_inspector_close_day", true)

func _rebuild_weather_economy_force_section() -> void:
	_add_section_title("— Next-280 weather/economy/force (20) —")
	var plain_methods: PackedStringArray = [
		"format_weather_pressure_depth_day_plain",
		"format_foul_combat_ops_day_plain",
		"format_weather_logistics_depth_day_plain",
		"format_weather_move_depth_day_plain",
		"format_weather_crisis_depth_day_plain",
		"format_weather_pressure_joint_day_plain",
		"format_weather_ops_close_depth_day_plain",
		"format_trade_pressure_depth_day_plain",
		"format_sealane_health_depth_day_plain",
		"format_war_economy_sustain_day_plain",
		"format_stockpile_economy_depth_day_plain",
		"format_convoy_economy_joint_day_plain",
		"format_trade_sealane_joint_day_plain",
		"format_war_economy_close_depth_day_plain",
		"format_force_ready_surface_day_plain",
		"format_formation_equip_depth_day_plain",
		"format_reinforce_stockpile_depth_day_plain",
		"format_readiness_board_ops_day_plain",
		"format_force_reinforce_joint_day_plain",
		"format_weather_economy_force_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run weather pressure depth day", "weather_pressure_depth_day", true)
	_add_apply_button("Run foul combat ops day", "foul_combat_ops_day", true)
	_add_apply_button("Run weather logistics depth day", "weather_logistics_depth_day", true)
	_add_apply_button("Run weather move depth day", "weather_move_depth_day", true)
	_add_apply_button("Run weather crisis depth day", "weather_crisis_depth_day", true)
	_add_apply_button("Run weather pressure joint day", "weather_pressure_joint_day", true)
	_add_apply_button("Run weather ops close depth day", "weather_ops_close_depth_day", true)
	_add_apply_button("Run trade pressure depth day", "trade_pressure_depth_day", true)
	_add_apply_button("Run sealane health depth day", "sealane_health_depth_day", true)
	_add_apply_button("Run war economy sustain day", "war_economy_sustain_day", true)
	_add_apply_button("Run stockpile economy depth day", "stockpile_economy_depth_day", true)
	_add_apply_button("Run convoy economy joint day", "convoy_economy_joint_day", true)
	_add_apply_button("Run trade sealane joint day", "trade_sealane_joint_day", true)
	_add_apply_button("Run war economy close depth day", "war_economy_close_depth_day", true)
	_add_apply_button("Run force ready surface day", "force_ready_surface_day", true)
	_add_apply_button("Run formation equip depth day", "formation_equip_depth_day", true)
	_add_apply_button("Run reinforce stockpile depth day", "reinforce_stockpile_depth_day", true)
	_add_apply_button("Run readiness board ops day", "readiness_board_ops_day", true)
	_add_apply_button("Run force reinforce joint day", "force_reinforce_joint_day", true)
	_add_apply_button("Run weather economy force close day", "weather_economy_force_close_day", true)


func _rebuild_full_game_campaign_section() -> void:
	_add_section_title("— Next-290 full-game campaign (20) —")
	var plain_methods: PackedStringArray = [
		"format_strategic_ai_doctrine_depth_day_plain",
		"format_strategic_ai_urgency_board_day_plain",
		"format_strategic_ai_player_skip_day_plain",
		"format_strategic_ai_budget_depth_day_plain",
		"format_strategic_ai_domain_weight_day_plain",
		"format_strategic_ai_daily_joint_day_plain",
		"format_strategic_ai_campaign_close_day_plain",
		"format_designer_catalog_depth_day_plain",
		"format_designer_seed_production_day_plain",
		"format_designer_domain_balance_day_plain",
		"format_oob_horizon_joint_day_plain",
		"format_production_line_bootstrap_day_plain",
		"format_industry_design_joint_day_plain",
		"format_designer_industry_close_day_plain",
		"format_theater_ai_command_joint_day_plain",
		"format_fleet_ai_campaign_depth_day_plain",
		"format_agent_ai_campaign_depth_day_plain",
		"format_combat_ai_phase_depth_day_plain",
		"format_save_session_ai_joint_day_plain",
		"format_full_game_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run strategic ai doctrine depth day", "strategic_ai_doctrine_depth_day", true)
	_add_apply_button("Run strategic ai urgency board day", "strategic_ai_urgency_board_day", true)
	_add_apply_button("Run strategic ai player skip day", "strategic_ai_player_skip_day", true)
	_add_apply_button("Run strategic ai budget depth day", "strategic_ai_budget_depth_day", true)
	_add_apply_button("Run strategic ai domain weight day", "strategic_ai_domain_weight_day", true)
	_add_apply_button("Run strategic ai daily joint day", "strategic_ai_daily_joint_day", true)
	_add_apply_button("Run strategic ai campaign close day", "strategic_ai_campaign_close_day", true)
	_add_apply_button("Run designer catalog depth day", "designer_catalog_depth_day", true)
	_add_apply_button("Run designer seed production day", "designer_seed_production_day", true)
	_add_apply_button("Run designer domain balance day", "designer_domain_balance_day", true)
	_add_apply_button("Run oob horizon joint day", "oob_horizon_joint_day", true)
	_add_apply_button("Run production line bootstrap day", "production_line_bootstrap_day", true)
	_add_apply_button("Run industry design joint day", "industry_design_joint_day", true)
	_add_apply_button("Run designer industry close day", "designer_industry_close_day", true)
	_add_apply_button("Run theater ai command joint day", "theater_ai_command_joint_day", true)
	_add_apply_button("Run fleet ai campaign depth day", "fleet_ai_campaign_depth_day", true)
	_add_apply_button("Run agent ai campaign depth day", "agent_ai_campaign_depth_day", true)
	_add_apply_button("Run combat ai phase depth day", "combat_ai_phase_depth_day", true)
	_add_apply_button("Run save session ai joint day", "save_session_ai_joint_day", true)
	_add_apply_button("Run full game campaign close day", "full_game_campaign_close_day", true)


func _rebuild_playability_campaign_section() -> void:
	_add_section_title("— Next-300 playability campaign (20) —")
	var plain_methods: PackedStringArray = [
		"format_air_ops_sortie_depth_day_plain",
		"format_air_forecast_planning_depth_day_plain",
		"format_air_sortie_weather_gate_day_plain",
		"format_convoy_escort_campaign_depth_day_plain",
		"format_air_land_campaign_depth_day_plain",
		"format_air_front_readiness_depth_day_plain",
		"format_air_convoy_campaign_close_day_plain",
		"format_focus_pick_depth_day_plain",
		"format_focus_order_path_day_plain",
		"format_focus_war_path_depth_day_plain",
		"format_war_path_urgency_depth_day_plain",
		"format_intel_counter_depth_campaign_day_plain",
		"format_leader_campaign_assign_day_plain",
		"format_focus_intel_leader_close_day_plain",
		"format_order_execute_session_day_plain",
		"format_next_day_feedback_session_day_plain",
		"format_campaign_decision_session_day_plain",
		"format_theater_ai_session_joint_day_plain",
		"format_force_readiness_session_day_plain",
		"format_play_session_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run air ops sortie depth day", "air_ops_sortie_depth_day", true)
	_add_apply_button("Run air forecast planning depth day", "air_forecast_planning_depth_day", true)
	_add_apply_button("Run air sortie weather gate day", "air_sortie_weather_gate_day", true)
	_add_apply_button("Run convoy escort depth day", "convoy_escort_campaign_depth_day", true)
	_add_apply_button("Run air land campaign depth day", "air_land_campaign_depth_day", true)
	_add_apply_button("Run air front readiness depth day", "air_front_readiness_depth_day", true)
	_add_apply_button("Run air convoy campaign close day", "air_convoy_campaign_close_day", true)
	_add_apply_button("Run focus pick depth day", "focus_pick_depth_day", true)
	_add_apply_button("Run focus order path day", "focus_order_path_day", true)
	_add_apply_button("Run focus war path depth day", "focus_war_path_depth_day", true)
	_add_apply_button("Run war path urgency depth day", "war_path_urgency_depth_day", true)
	_add_apply_button("Run intel counter depth campaign day", "intel_counter_depth_campaign_day", true)
	_add_apply_button("Run leader campaign assign day", "leader_campaign_assign_day", true)
	_add_apply_button("Run focus intel leader close day", "focus_intel_leader_close_day", true)
	_add_apply_button("Run order execute session day", "order_execute_session_day", true)
	_add_apply_button("Run next day feedback session day", "next_day_feedback_session_day", true)
	_add_apply_button("Run campaign decision session day", "campaign_decision_session_day", true)
	_add_apply_button("Run theater ai session joint day", "theater_ai_session_joint_day", true)
	_add_apply_button("Run force readiness session day", "force_readiness_session_day", true)
	_add_apply_button("Run play session campaign close day", "play_session_campaign_close_day", true)


func _rebuild_advanced_deferred_section() -> void:
	_add_section_title("— Next-310 advanced deferred (20) —")
	var plain_methods: PackedStringArray = [
		"format_focus_pick_board_advanced_day_plain",
		"format_focus_war_path_advanced_day_plain",
		"format_focus_commit_execute_advanced_day_plain",
		"format_focus_naval_effort_advanced_day_plain",
		"format_focus_industry_army_joint_day_plain",
		"format_focus_air_effort_joint_day_plain",
		"format_focus_war_path_close_day_plain",
		"format_naval_posture_advanced_day_plain",
		"format_naval_escort_phase_advanced_day_plain",
		"format_naval_strike_phase_advanced_day_plain",
		"format_naval_fleet_fuel_advanced_day_plain",
		"format_naval_fleet_autonomy_joint_day_plain",
		"format_naval_air_joint_advanced_day_plain",
		"format_naval_multi_phase_close_day_plain",
		"format_designer_domain_advanced_day_plain",
		"format_designer_seed_advanced_day_plain",
		"format_strategic_ai_multi_day_advanced_day_plain",
		"format_designer_ai_industry_joint_day_plain",
		"format_play_session_advanced_joint_day_plain",
		"format_advanced_deferred_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run focus pick board advanced day", "focus_pick_board_advanced_day", true)
	_add_apply_button("Run focus war path advanced day", "focus_war_path_advanced_day", true)
	_add_apply_button("Run focus commit execute advanced day", "focus_commit_execute_advanced_day", true)
	_add_apply_button("Run focus naval effort advanced day", "focus_naval_effort_advanced_day", true)
	_add_apply_button("Run focus industry army joint day", "focus_industry_army_joint_day", true)
	_add_apply_button("Run focus air effort joint day", "focus_air_effort_joint_day", true)
	_add_apply_button("Run focus war path close day", "focus_war_path_close_day", true)
	_add_apply_button("Run naval posture advanced day", "naval_posture_advanced_day", true)
	_add_apply_button("Run naval escort phase advanced day", "naval_escort_phase_advanced_day", true)
	_add_apply_button("Run naval strike phase advanced day", "naval_strike_phase_advanced_day", true)
	_add_apply_button("Run naval fleet fuel advanced day", "naval_fleet_fuel_advanced_day", true)
	_add_apply_button("Run naval fleet autonomy joint day", "naval_fleet_autonomy_joint_day", true)
	_add_apply_button("Run naval air joint advanced day", "naval_air_joint_advanced_day", true)
	_add_apply_button("Run naval multi phase close day", "naval_multi_phase_close_day", true)
	_add_apply_button("Run designer domain advanced day", "designer_domain_advanced_day", true)
	_add_apply_button("Run designer seed advanced day", "designer_seed_advanced_day", true)
	_add_apply_button("Run strategic ai multi day advanced day", "strategic_ai_multi_day_advanced_day", true)
	_add_apply_button("Run designer ai industry joint day", "designer_ai_industry_joint_day", true)
	_add_apply_button("Run play session advanced joint day", "play_session_advanced_joint_day", true)
	_add_apply_button("Run advanced deferred campaign close day", "advanced_deferred_campaign_close_day", true)


func _rebuild_diplomacy_tech_section() -> void:
	_add_section_title("— Next-320 diplomacy/tech advanced (20) —")
	var plain_methods: PackedStringArray = [
		"format_diplomacy_board_advanced_day_plain",
		"format_diplomacy_leverage_advanced_day_plain",
		"format_diplomacy_settle_advanced_day_plain",
		"format_diplomacy_trade_pressure_day_plain",
		"format_diplomacy_agent_hh_joint_day_plain",
		"format_diplomacy_focus_peace_joint_day_plain",
		"format_diplomacy_peace_close_day_plain",
		"format_tech_catalog_advanced_day_plain",
		"format_tech_priority_advanced_day_plain",
		"format_tech_field_advanced_day_plain",
		"format_tech_designer_joint_day_plain",
		"format_tech_oob_fielding_joint_day_plain",
		"format_tech_industry_focus_joint_day_plain",
		"format_tech_research_close_day_plain",
		"format_diplomacy_tech_joint_day_plain",
		"format_tech_ai_research_joint_day_plain",
		"format_diplomacy_naval_air_joint_day_plain",
		"format_session_diplomacy_tech_joint_day_plain",
		"format_multi_faction_diplo_tech_day_plain",
		"format_diplomacy_tech_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run diplomacy board advanced day", "diplomacy_board_advanced_day", true)
	_add_apply_button("Run diplomacy leverage advanced day", "diplomacy_leverage_advanced_day", true)
	_add_apply_button("Run diplomacy settle advanced day", "diplomacy_settle_advanced_day", true)
	_add_apply_button("Run diplomacy trade pressure day", "diplomacy_trade_pressure_day", true)
	_add_apply_button("Run diplomacy agent hh joint day", "diplomacy_agent_hh_joint_day", true)
	_add_apply_button("Run diplomacy focus peace joint day", "diplomacy_focus_peace_joint_day", true)
	_add_apply_button("Run diplomacy peace close day", "diplomacy_peace_close_day", true)
	_add_apply_button("Run tech catalog advanced day", "tech_catalog_advanced_day", true)
	_add_apply_button("Run tech priority advanced day", "tech_priority_advanced_day", true)
	_add_apply_button("Run tech field advanced day", "tech_field_advanced_day", true)
	_add_apply_button("Run tech designer joint day", "tech_designer_joint_day", true)
	_add_apply_button("Run tech oob fielding joint day", "tech_oob_fielding_joint_day", true)
	_add_apply_button("Run tech industry focus joint day", "tech_industry_focus_joint_day", true)
	_add_apply_button("Run tech research close day", "tech_research_close_day", true)
	_add_apply_button("Run diplomacy tech joint day", "diplomacy_tech_joint_day", true)
	_add_apply_button("Run tech ai research joint day", "tech_ai_research_joint_day", true)
	_add_apply_button("Run diplomacy naval air joint day", "diplomacy_naval_air_joint_day", true)
	_add_apply_button("Run session diplomacy tech joint day", "session_diplomacy_tech_joint_day", true)
	_add_apply_button("Run multi faction diplo tech day", "multi_faction_diplo_tech_day", true)
	_add_apply_button("Run diplomacy tech campaign close day", "diplomacy_tech_campaign_close_day", true)


func _rebuild_world_class_depth_section() -> void:
	_add_section_title("— Next-330 world-class depth (20) —")
	var plain_methods: PackedStringArray = [
		"format_logistics_route_advanced_day_plain",
		"format_logistics_sustain_advanced_day_plain",
		"format_logistics_readiness_advanced_day_plain",
		"format_logistics_naval_joint_day_plain",
		"format_logistics_tech_industry_joint_day_plain",
		"format_logistics_supply_close_day_plain",
		"format_intel_coverage_advanced_day_plain",
		"format_intel_counterintel_advanced_day_plain",
		"format_intel_counterplay_advanced_day_plain",
		"format_intel_diplomacy_joint_day_plain",
		"format_intel_session_joint_day_plain",
		"format_intelligence_network_close_day_plain",
		"format_world_class_scan_advanced_day_plain",
		"format_world_class_rank_advanced_day_plain",
		"format_world_class_execute_advanced_day_plain",
		"format_world_class_logistics_intel_joint_day_plain",
		"format_world_class_air_naval_joint_day_plain",
		"format_world_class_session_ai_joint_day_plain",
		"format_world_class_theater_command_joint_day_plain",
		"format_world_class_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run logistics route advanced day", "logistics_route_advanced_day", true)
	_add_apply_button("Run logistics sustain advanced day", "logistics_sustain_advanced_day", true)
	_add_apply_button("Run logistics readiness advanced day", "logistics_readiness_advanced_day", true)
	_add_apply_button("Run logistics naval joint day", "logistics_naval_joint_day", true)
	_add_apply_button("Run logistics tech industry joint day", "logistics_tech_industry_joint_day", true)
	_add_apply_button("Run logistics supply close day", "logistics_supply_close_day", true)
	_add_apply_button("Run intel coverage advanced day", "intel_coverage_advanced_day", true)
	_add_apply_button("Run intel counterintel advanced day", "intel_counterintel_advanced_day", true)
	_add_apply_button("Run intel counterplay advanced day", "intel_counterplay_advanced_day", true)
	_add_apply_button("Run intel diplomacy joint day", "intel_diplomacy_joint_day", true)
	_add_apply_button("Run intel session joint day", "intel_session_joint_day", true)
	_add_apply_button("Run intelligence network close day", "intelligence_network_close_day", true)
	_add_apply_button("Run world class scan advanced day", "world_class_scan_advanced_day", true)
	_add_apply_button("Run world class rank advanced day", "world_class_rank_advanced_day", true)
	_add_apply_button("Run world class execute advanced day", "world_class_execute_advanced_day", true)
	_add_apply_button("Run world class logistics intel joint day", "world_class_logistics_intel_joint_day", true)
	_add_apply_button("Run world class air naval joint day", "world_class_air_naval_joint_day", true)
	_add_apply_button("Run world class session ai joint day", "world_class_session_ai_joint_day", true)
	_add_apply_button("Run world class theater command joint day", "world_class_theater_command_joint_day", true)
	_add_apply_button("Run world class campaign close day", "world_class_campaign_close_day", true)

func _rebuild_economy_weather_front_section() -> void:
	_add_section_title("— Next-340 economy/weather/front (20) —")
	var plain_methods: PackedStringArray = [
		"format_war_economy_board_advanced_day_plain",
		"format_war_economy_allocate_advanced_day_plain",
		"format_war_economy_sustain_advanced_day_plain",
		"format_war_economy_logistics_joint_day_plain",
		"format_war_economy_tech_joint_day_plain",
		"format_war_economy_mobilization_close_day_plain",
		"format_weather_pressure_advanced_day_plain",
		"format_weather_gate_advanced_day_plain",
		"format_weather_crisis_advanced_day_plain",
		"format_weather_front_joint_day_plain",
		"format_weather_economy_joint_day_plain",
		"format_weather_theater_ops_close_day_plain",
		"format_front_combat_advanced_day_plain",
		"format_front_assault_advanced_day_plain",
		"format_front_sustain_advanced_day_plain",
		"format_front_weather_joint_day_plain",
		"format_front_economy_joint_day_plain",
		"format_front_logistics_joint_day_plain",
		"format_front_theater_command_joint_day_plain",
		"format_front_continuity_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run war economy board advanced day", "war_economy_board_advanced_day", true)
	_add_apply_button("Run war economy allocate advanced day", "war_economy_allocate_advanced_day", true)
	_add_apply_button("Run war economy sustain advanced day", "war_economy_sustain_advanced_day", true)
	_add_apply_button("Run war economy logistics joint day", "war_economy_logistics_joint_day", true)
	_add_apply_button("Run war economy tech joint day", "war_economy_tech_joint_day", true)
	_add_apply_button("Run war economy mobilization close day", "war_economy_mobilization_close_day", true)
	_add_apply_button("Run weather pressure advanced day", "weather_pressure_advanced_day", true)
	_add_apply_button("Run weather gate advanced day", "weather_gate_advanced_day", true)
	_add_apply_button("Run weather crisis advanced day", "weather_crisis_advanced_day", true)
	_add_apply_button("Run weather front joint day", "weather_front_joint_day", true)
	_add_apply_button("Run weather economy joint day", "weather_economy_joint_day", true)
	_add_apply_button("Run weather theater ops close day", "weather_theater_ops_close_day", true)
	_add_apply_button("Run front combat advanced day", "front_combat_advanced_day", true)
	_add_apply_button("Run front assault advanced day", "front_assault_advanced_day", true)
	_add_apply_button("Run front sustain advanced day", "front_sustain_advanced_day", true)
	_add_apply_button("Run front weather joint day", "front_weather_joint_day", true)
	_add_apply_button("Run front economy joint day", "front_economy_joint_day", true)
	_add_apply_button("Run front logistics joint day", "front_logistics_joint_day", true)
	_add_apply_button("Run front theater command joint day", "front_theater_command_joint_day", true)
	_add_apply_button("Run front continuity campaign close day", "front_continuity_campaign_close_day", true)

func _rebuild_occupation_manpower_leader_section() -> void:
	_add_section_title("— Next-350 occupation/manpower/leader (20) —")
	var plain_methods: PackedStringArray = [
		"format_occupation_control_advanced_day_plain",
		"format_occupation_garrison_advanced_day_plain",
		"format_occupation_integrate_advanced_day_plain",
		"format_occupation_front_joint_day_plain",
		"format_occupation_economy_joint_day_plain",
		"format_occupation_control_close_day_plain",
		"format_manpower_draft_advanced_day_plain",
		"format_manpower_reinforce_advanced_day_plain",
		"format_manpower_field_advanced_day_plain",
		"format_manpower_front_joint_day_plain",
		"format_manpower_economy_joint_day_plain",
		"format_manpower_reinforcement_close_day_plain",
		"format_leader_assign_advanced_day_plain",
		"format_leader_station_advanced_day_plain",
		"format_leader_ops_advanced_day_plain",
		"format_leader_occupation_joint_day_plain",
		"format_leader_manpower_joint_day_plain",
		"format_leader_intel_joint_day_plain",
		"format_leader_theater_joint_day_plain",
		"format_occupation_manpower_leader_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run occupation control advanced day", "occupation_control_advanced_day", true)
	_add_apply_button("Run occupation garrison advanced day", "occupation_garrison_advanced_day", true)
	_add_apply_button("Run occupation integrate advanced day", "occupation_integrate_advanced_day", true)
	_add_apply_button("Run occupation front joint day", "occupation_front_joint_day", true)
	_add_apply_button("Run occupation economy joint day", "occupation_economy_joint_day", true)
	_add_apply_button("Run occupation control close day", "occupation_control_close_day", true)
	_add_apply_button("Run manpower draft advanced day", "manpower_draft_advanced_day", true)
	_add_apply_button("Run manpower reinforce advanced day", "manpower_reinforce_advanced_day", true)
	_add_apply_button("Run manpower field advanced day", "manpower_field_advanced_day", true)
	_add_apply_button("Run manpower front joint day", "manpower_front_joint_day", true)
	_add_apply_button("Run manpower economy joint day", "manpower_economy_joint_day", true)
	_add_apply_button("Run manpower reinforcement close day", "manpower_reinforcement_close_day", true)
	_add_apply_button("Run leader assign advanced day", "leader_assign_advanced_day", true)
	_add_apply_button("Run leader station advanced day", "leader_station_advanced_day", true)
	_add_apply_button("Run leader ops advanced day", "leader_ops_advanced_day", true)
	_add_apply_button("Run leader occupation joint day", "leader_occupation_joint_day", true)
	_add_apply_button("Run leader manpower joint day", "leader_manpower_joint_day", true)
	_add_apply_button("Run leader intel joint day", "leader_intel_joint_day", true)
	_add_apply_button("Run leader theater joint day", "leader_theater_joint_day", true)
	_add_apply_button("Run occupation manpower leader close day", "occupation_manpower_leader_close_day", true)

func _rebuild_production_honesty_section() -> void:
	_add_section_title("— Next-360 medium production honesty (10) —")
	var plain_methods: PackedStringArray = [
		"format_medium_honesty_60d_day_plain",
		"format_medium_honesty_80d_day_plain",
		"format_medium_honesty_100d_day_plain",
		"format_medium_honesty_unit_stats_day_plain",
		"format_medium_honesty_factory_risk_day_plain",
		"format_medium_honesty_stockpile_day_plain",
		"format_medium_honesty_readiness_joint_day_plain",
		"format_medium_honesty_manpower_joint_day_plain",
		"format_medium_honesty_economy_joint_day_plain",
		"format_medium_tank_production_honesty_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run medium honesty 60d day", "medium_honesty_60d_day", true)
	_add_apply_button("Run medium honesty 80d day", "medium_honesty_80d_day", true)
	_add_apply_button("Run medium honesty 100d day", "medium_honesty_100d_day", true)
	_add_apply_button("Run medium honesty unit stats day", "medium_honesty_unit_stats_day", true)
	_add_apply_button("Run medium honesty factory risk day", "medium_honesty_factory_risk_day", true)
	_add_apply_button("Run medium honesty stockpile day", "medium_honesty_stockpile_day", true)
	_add_apply_button("Run medium honesty readiness joint day", "medium_honesty_readiness_joint_day", true)
	_add_apply_button("Run medium honesty manpower joint day", "medium_honesty_manpower_joint_day", true)
	_add_apply_button("Run medium honesty economy joint day", "medium_honesty_economy_joint_day", true)
	_add_apply_button("Run medium tank production honesty close day", "medium_tank_production_honesty_close_day", true)

func _rebuild_apply_queue_live_section() -> void:
	_add_section_title("— Next-370 apply-queue live depth (10) —")
	var plain_methods: PackedStringArray = [
		"format_apply_queue_audit_day_plain",
		"format_apply_queue_production_live_day_plain",
		"format_apply_queue_combat_live_day_plain",
		"format_apply_queue_supply_live_day_plain",
		"format_apply_queue_focus_live_day_plain",
		"format_apply_queue_agent_live_day_plain",
		"format_apply_queue_station_live_day_plain",
		"format_apply_queue_six_leaf_joint_day_plain",
		"format_apply_queue_honesty_joint_day_plain",
		"format_apply_queue_live_managers_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run apply queue audit day", "apply_queue_audit_day", true)
	_add_apply_button("Run apply queue production live day", "apply_queue_production_live_day", true)
	_add_apply_button("Run apply queue combat live day", "apply_queue_combat_live_day", true)
	_add_apply_button("Run apply queue supply live day", "apply_queue_supply_live_day", true)
	_add_apply_button("Run apply queue focus live day", "apply_queue_focus_live_day", true)
	_add_apply_button("Run apply queue agent live day", "apply_queue_agent_live_day", true)
	_add_apply_button("Run apply queue station live day", "apply_queue_station_live_day", true)
	_add_apply_button("Run apply queue six leaf joint day", "apply_queue_six_leaf_joint_day", true)
	_add_apply_button("Run apply queue honesty joint day", "apply_queue_honesty_joint_day", true)
	_add_apply_button("Run apply queue live managers close day", "apply_queue_live_managers_close_day", true)

func _rebuild_phase2_conquest_section() -> void:
	_add_section_title("— Next-380 phase2 conquest depth (12) —")
	var plain_methods: PackedStringArray = [
		"format_occupation_resistance_board_day_plain",
		"format_occupation_resistance_policy_day_plain",
		"format_occupation_resistance_tick_day_plain",
		"format_occupation_resistance_close_day_plain",
		"format_manpower_law_board_day_plain",
		"format_manpower_train_pipeline_day_plain",
		"format_manpower_field_trained_day_plain",
		"format_manpower_laws_training_close_day_plain",
		"format_peace_conference_board_day_plain",
		"format_peace_conference_demands_day_plain",
		"format_peace_conference_settle_day_plain",
		"format_peace_conference_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run occupation resistance board day", "occupation_resistance_board_day", true)
	_add_apply_button("Run occupation resistance policy day", "occupation_resistance_policy_day", true)
	_add_apply_button("Run occupation resistance tick day", "occupation_resistance_tick_day", true)
	_add_apply_button("Run occupation resistance close day", "occupation_resistance_close_day", true)
	_add_apply_button("Run manpower law board day", "manpower_law_board_day", true)
	_add_apply_button("Run manpower train pipeline day", "manpower_train_pipeline_day", true)
	_add_apply_button("Run manpower field trained day", "manpower_field_trained_day", true)
	_add_apply_button("Run manpower laws training close day", "manpower_laws_training_close_day", true)
	_add_apply_button("Run peace conference board day", "peace_conference_board_day", true)
	_add_apply_button("Run peace conference demands day", "peace_conference_demands_day", true)
	_add_apply_button("Run peace conference settle day", "peace_conference_settle_day", true)
	_add_apply_button("Run peace conference campaign close day", "peace_conference_campaign_close_day", true)

func _rebuild_phase3_depth_section() -> void:
	_add_section_title("— Next-390 phase3 depth (12) —")
	var plain_methods: PackedStringArray = [
		"format_product_ux_compact_day_plain",
		"format_product_ux_chips_day_plain",
		"format_product_ux_hotkeys_day_plain",
		"format_product_ux_polish_close_day_plain",
		"format_designer_domain_catalog_day_plain",
		"format_designer_domain_pick_day_plain",
		"format_designer_domain_seed_day_plain",
		"format_designer_domain_live_close_day_plain",
		"format_campaign_ai_month_board_day_plain",
		"format_campaign_ai_weekly_plan_day_plain",
		"format_campaign_ai_theater_execute_day_plain",
		"format_campaign_ai_multi_month_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run product UX compact day", "product_ux_compact_day", true)
	_add_apply_button("Run product UX chips day", "product_ux_chips_day", true)
	_add_apply_button("Run product UX hotkeys day", "product_ux_hotkeys_day", true)
	_add_apply_button("Run product UX polish close day", "product_ux_polish_close_day", true)
	_add_apply_button("Run designer domain catalog day", "designer_domain_catalog_day", true)
	_add_apply_button("Run designer domain pick day", "designer_domain_pick_day", true)
	_add_apply_button("Run designer domain seed day", "designer_domain_seed_day", true)
	_add_apply_button("Run designer domain live close day", "designer_domain_live_close_day", true)
	_add_apply_button("Run campaign AI month board day", "campaign_ai_month_board_day", true)
	_add_apply_button("Run campaign AI weekly plan day", "campaign_ai_weekly_plan_day", true)
	_add_apply_button("Run campaign AI theater execute day", "campaign_ai_theater_execute_day", true)
	_add_apply_button("Run campaign AI multi-month close day", "campaign_ai_multi_month_close_day", true)

func _rebuild_phase4_depth_section() -> void:
	_add_section_title("— Next-400 phase4 depth (12) —")
	var plain_methods: PackedStringArray = [
		"format_occupation_revolt_board_day_plain",
		"format_occupation_revolt_garrison_day_plain",
		"format_occupation_revolt_suppress_day_plain",
		"format_occupation_revolt_garrison_close_day_plain",
		"format_manpower_cohort_board_day_plain",
		"format_manpower_cohort_reserve_day_plain",
		"format_manpower_cohort_mobilize_day_plain",
		"format_manpower_cohort_reserve_close_day_plain",
		"format_multi_party_peace_board_day_plain",
		"format_multi_party_peace_wargoals_day_plain",
		"format_multi_party_peace_settle_day_plain",
		"format_multi_party_peace_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run occupation revolt board day", "occupation_revolt_board_day", true)
	_add_apply_button("Run occupation revolt garrison day", "occupation_revolt_garrison_day", true)
	_add_apply_button("Run occupation revolt suppress day", "occupation_revolt_suppress_day", true)
	_add_apply_button("Run occupation revolt garrison close day", "occupation_revolt_garrison_close_day", true)
	_add_apply_button("Run manpower cohort board day", "manpower_cohort_board_day", true)
	_add_apply_button("Run manpower cohort reserve day", "manpower_cohort_reserve_day", true)
	_add_apply_button("Run manpower cohort mobilize day", "manpower_cohort_mobilize_day", true)
	_add_apply_button("Run manpower cohort reserve close day", "manpower_cohort_reserve_close_day", true)
	_add_apply_button("Run multi-party peace board day", "multi_party_peace_board_day", true)
	_add_apply_button("Run multi-party peace wargoals day", "multi_party_peace_wargoals_day", true)
	_add_apply_button("Run multi-party peace settle day", "multi_party_peace_settle_day", true)
	_add_apply_button("Run multi-party peace campaign close day", "multi_party_peace_campaign_close_day", true)

func _rebuild_phase5_depth_section() -> void:
	_add_section_title("— Next-410 phase5 depth (12) —")
	var plain_methods: PackedStringArray = [
		"format_historical_oob_catalog_day_plain",
		"format_historical_oob_seed_day_plain",
		"format_historical_oob_equip_day_plain",
		"format_historical_oob_content_close_day_plain",
		"format_tech_tree_branches_day_plain",
		"format_tech_tree_path_day_plain",
		"format_tech_tree_field_day_plain",
		"format_tech_tree_branching_close_day_plain",
		"format_save_resume_checkpoint_day_plain",
		"format_save_resume_save_day_plain",
		"format_save_resume_resume_day_plain",
		"format_save_resume_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run historical OOB catalog day", "historical_oob_catalog_day", true)
	_add_apply_button("Run historical OOB seed day", "historical_oob_seed_day", true)
	_add_apply_button("Run historical OOB equip day", "historical_oob_equip_day", true)
	_add_apply_button("Run historical OOB content close day", "historical_oob_content_close_day", true)
	_add_apply_button("Run tech tree branches day", "tech_tree_branches_day", true)
	_add_apply_button("Run tech tree path day", "tech_tree_path_day", true)
	_add_apply_button("Run tech tree field day", "tech_tree_field_day", true)
	_add_apply_button("Run tech tree branching close day", "tech_tree_branching_close_day", true)
	_add_apply_button("Run save resume checkpoint day", "save_resume_checkpoint_day", true)
	_add_apply_button("Run save resume save day", "save_resume_save_day", true)
	_add_apply_button("Run save resume resume day", "save_resume_resume_day", true)
	_add_apply_button("Run save resume campaign close day", "save_resume_campaign_close_day", true)

func _rebuild_phase6_depth_section() -> void:
	_add_section_title("— Next-420 phase6 depth (12) —")
	var plain_methods: PackedStringArray = [
		"format_tutorial_session_brief_day_plain",
		"format_tutorial_session_guide_day_plain",
		"format_tutorial_session_checkpoint_day_plain",
		"format_tutorial_first_session_close_day_plain",
		"format_focus_tree_catalog_day_plain",
		"format_focus_tree_path_day_plain",
		"format_focus_tree_commit_day_plain",
		"format_focus_tree_content_close_day_plain",
		"format_balance_estimate_board_day_plain",
		"format_balance_live_sample_day_plain",
		"format_balance_variance_close_day_plain",
		"format_balance_combat_supply_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var p := str(GameData.call(m, province_id)).strip_edges()
				if not p.is_empty():
					_add_plain_label(p.split("\n")[0], 200)
	_add_apply_button("Run tutorial session brief day", "tutorial_session_brief_day", true)
	_add_apply_button("Run tutorial session guide day", "tutorial_session_guide_day", true)
	_add_apply_button("Run tutorial session checkpoint day", "tutorial_session_checkpoint_day", true)
	_add_apply_button("Run tutorial first session close day", "tutorial_first_session_close_day", true)
	_add_apply_button("Run focus tree catalog day", "focus_tree_catalog_day", true)
	_add_apply_button("Run focus tree path day", "focus_tree_path_day", true)
	_add_apply_button("Run focus tree commit day", "focus_tree_commit_day", true)
	_add_apply_button("Run focus tree content close day", "focus_tree_content_close_day", true)
	_add_apply_button("Run balance estimate board day", "balance_estimate_board_day", true)
	_add_apply_button("Run balance live sample day", "balance_live_sample_day", true)
	_add_apply_button("Run balance variance close day", "balance_variance_close_day", true)
	_add_apply_button("Run balance combat supply close day", "balance_combat_supply_close_day", true)

func _rebuild_phase7_depth_section() -> void:
	_add_section_title("— Next-430 phase7 depth (12) —")
	var plain_methods: PackedStringArray = [
		"format_air_theater_recon_day_plain",
		"format_air_theater_cas_gate_day_plain",
		"format_air_theater_interdiction_day_plain",
		"format_air_multi_phase_theater_close_day_plain",
		"format_naval_search_patrol_day_plain",
		"format_naval_asw_escort_day_plain",
		"format_naval_carrier_strike_day_plain",
		"format_naval_search_strike_close_day_plain",
		"format_economy_civ_board_day_plain",
		"format_economy_war_convert_day_plain",
		"format_economy_stockpile_sustain_day_plain",
		"format_war_economy_conversion_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var pl := str(GameData.call(m, province_id)).strip_edges()
				if not pl.is_empty():
					_add_plain_label(pl.split("\n")[0], 200)
	_add_apply_button("Run air theater recon day", "air_theater_recon_day", true)
	_add_apply_button("Run air theater CAS gate day", "air_theater_cas_gate_day", true)
	_add_apply_button("Run air theater interdiction day", "air_theater_interdiction_day", true)
	_add_apply_button("Run air multi-phase theater close day", "air_multi_phase_theater_close_day", true)
	_add_apply_button("Run naval search patrol day", "naval_search_patrol_day", true)
	_add_apply_button("Run naval ASW escort day", "naval_asw_escort_day", true)
	_add_apply_button("Run naval carrier strike day", "naval_carrier_strike_day", true)
	_add_apply_button("Run naval search strike close day", "naval_search_strike_close_day", true)
	_add_apply_button("Run economy civ board day", "economy_civ_board_day", true)
	_add_apply_button("Run economy war convert day", "economy_war_convert_day", true)
	_add_apply_button("Run economy stockpile sustain day", "economy_stockpile_sustain_day", true)
	_add_apply_button("Run war economy conversion close day", "war_economy_conversion_close_day", true)

func _rebuild_phase8_designers_section() -> void:
	_add_section_title("— Next-440 full designers (12) —")
	var plain_methods: PackedStringArray = [
		"format_designer_module_board_day_plain",
		"format_designer_module_edit_day_plain",
		"format_designer_reliability_gate_day_plain",
		"format_designer_module_editor_close_day_plain",
		"format_designer_stats_board_day_plain",
		"format_designer_freeze_design_day_plain",
		"format_designer_field_seed_day_plain",
		"format_designer_stats_field_close_day_plain",
		"format_designer_catalog_all_domains_day_plain",
		"format_designer_seed_multi_domain_day_plain",
		"format_designer_equip_campaign_close_day_plain",
		"format_designer_multi_domain_campaign_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var pl := str(GameData.call(m, province_id)).strip_edges()
				if not pl.is_empty():
					_add_plain_label(pl.split("\n")[0], 200)
	_add_apply_button("Run designer module board day", "designer_module_board_day", true)
	_add_apply_button("Run designer module edit day", "designer_module_edit_day", true)
	_add_apply_button("Run designer reliability gate day", "designer_reliability_gate_day", true)
	_add_apply_button("Run designer module editor close day", "designer_module_editor_close_day", true)
	_add_apply_button("Run designer stats board day", "designer_stats_board_day", true)
	_add_apply_button("Run designer freeze design day", "designer_freeze_design_day", true)
	_add_apply_button("Run designer field seed day", "designer_field_seed_day", true)
	_add_apply_button("Run designer stats field close day", "designer_stats_field_close_day", true)
	_add_apply_button("Run designer catalog all domains day", "designer_catalog_all_domains_day", true)
	_add_apply_button("Run designer seed multi domain day", "designer_seed_multi_domain_day", true)
	_add_apply_button("Run designer equip campaign close day", "designer_equip_campaign_close_day", true)
	_add_apply_button("Run designer multi domain campaign close day", "designer_multi_domain_campaign_close_day", true)

func _rebuild_phase9_cycle_section() -> void:
	_add_section_title("— Next-450 phase9 cycle (12) —")
	var plain_methods: PackedStringArray = [
		"format_weather_crisis_forecast_day_plain",
		"format_weather_crisis_gate_multi_day_plain",
		"format_weather_crisis_sustain_day_plain",
		"format_weather_crisis_campaign_close_day_plain",
		"format_intel_cell_coverage_day_plain",
		"format_intel_cell_ops_day_plain",
		"format_intel_counter_sweep_day_plain",
		"format_intel_cell_network_close_day_plain",
		"format_leader_hq_board_day_plain",
		"format_leader_multi_station_day_plain",
		"format_leader_theater_ops_day_plain",
		"format_leader_theater_command_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var pl := str(GameData.call(m, province_id)).strip_edges()
				if not pl.is_empty():
					_add_plain_label(pl.split("\n")[0], 200)
	_add_apply_button("Run weather crisis forecast day", "weather_crisis_forecast_day", true)
	_add_apply_button("Run weather crisis gate multi day", "weather_crisis_gate_multi_day", true)
	_add_apply_button("Run weather crisis sustain day", "weather_crisis_sustain_day", true)
	_add_apply_button("Run weather crisis campaign close day", "weather_crisis_campaign_close_day", true)
	_add_apply_button("Run intel cell coverage day", "intel_cell_coverage_day", true)
	_add_apply_button("Run intel cell ops day", "intel_cell_ops_day", true)
	_add_apply_button("Run intel counter sweep day", "intel_counter_sweep_day", true)
	_add_apply_button("Run intel cell network close day", "intel_cell_network_close_day", true)
	_add_apply_button("Run leader HQ board day", "leader_hq_board_day", true)
	_add_apply_button("Run leader multi station day", "leader_multi_station_day", true)
	_add_apply_button("Run leader theater ops day", "leader_theater_ops_day", true)
	_add_apply_button("Run leader theater command close day", "leader_theater_command_close_day", true)

func _rebuild_phase10_gs_section() -> void:
	_add_section_title("— Next-460 phase10 GS (12) —")
	var plain_methods: PackedStringArray = [
		"format_war_goal_board_day_plain",
		"format_war_goal_justify_day_plain",
		"format_war_goal_execute_day_plain",
		"format_strategic_war_goal_close_day_plain",
		"format_multi_front_plan_day_plain",
		"format_multi_front_weekly_day_plain",
		"format_multi_front_execute_day_plain",
		"format_multi_front_campaign_ai_close_day_plain",
		"format_gs_cycle_scan_day_plain",
		"format_gs_cycle_rank_day_plain",
		"format_gs_cycle_execute_day_plain",
		"format_grand_strategy_cycle_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var pl := str(GameData.call(m, province_id)).strip_edges()
				if not pl.is_empty():
					_add_plain_label(pl.split("\n")[0], 200)
	_add_apply_button("Run war goal board day", "war_goal_board_day", true)
	_add_apply_button("Run war goal justify day", "war_goal_justify_day", true)
	_add_apply_button("Run war goal execute day", "war_goal_execute_day", true)
	_add_apply_button("Run strategic war goal close day", "strategic_war_goal_close_day", true)
	_add_apply_button("Run multi front plan day", "multi_front_plan_day", true)
	_add_apply_button("Run multi front weekly day", "multi_front_weekly_day", true)
	_add_apply_button("Run multi front execute day", "multi_front_execute_day", true)
	_add_apply_button("Run multi front campaign AI close day", "multi_front_campaign_ai_close_day", true)
	_add_apply_button("Run GS cycle scan day", "gs_cycle_scan_day", true)
	_add_apply_button("Run GS cycle rank day", "gs_cycle_rank_day", true)
	_add_apply_button("Run GS cycle execute day", "gs_cycle_execute_day", true)
	_add_apply_button("Run grand strategy cycle close day", "grand_strategy_cycle_close_day", true)

func _rebuild_phase11_depth_section() -> void:
	_add_section_title("— Next-470 phase11 depth (12) —")
	_add_section_title("Alliance guarantee network (major #56)")
	_add_section_title("Faction personality AI (major #57)")
	_add_section_title("Occupation revolt network (major #58)")
	var plain_methods: PackedStringArray = [
		"format_alliance_board_day_plain",
		"format_alliance_guarantee_day_plain",
		"format_alliance_coalition_day_plain",
		"format_alliance_guarantee_network_close_day_plain",
		"format_personality_board_day_plain",
		"format_personality_event_day_plain",
		"format_personality_drive_day_plain",
		"format_faction_personality_ai_close_day_plain",
		"format_revolt_network_map_day_plain",
		"format_revolt_cascade_risk_day_plain",
		"format_revolt_network_suppress_day_plain",
		"format_occupation_revolt_network_close_day_plain"
	]
	if typeof(GameData) != TYPE_NIL:
		for m in plain_methods:
			if GameData.has_method(m):
				var pl := str(GameData.call(m, province_id)).strip_edges()
				if not pl.is_empty():
					_add_plain_label(pl.split("\n")[0], 200)
	_add_apply_button("Run alliance board day", "alliance_board_day", true)
	_add_apply_button("Run alliance guarantee day", "alliance_guarantee_day", true)
	_add_apply_button("Run alliance coalition day", "alliance_coalition_day", true)
	_add_apply_button("Run alliance guarantee network close day", "alliance_guarantee_network_close_day", true)
	_add_apply_button("Run personality board day", "personality_board_day", true)
	_add_apply_button("Run personality event day", "personality_event_day", true)
	_add_apply_button("Run personality drive day", "personality_drive_day", true)
	_add_apply_button("Run faction personality AI close day", "faction_personality_ai_close_day", true)
	_add_apply_button("Run revolt network map day", "revolt_network_map_day", true)
	_add_apply_button("Run revolt cascade risk day", "revolt_cascade_risk_day", true)
	_add_apply_button("Run revolt network suppress day", "revolt_network_suppress_day", true)
	_add_apply_button("Run occupation revolt network close day", "occupation_revolt_network_close_day", true)


func _rebuild_air_theater_primary_command() -> void:
	_add_section_title("— Air theater primary command (C3 recon→close) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_theater_primary_command_product_live"):
		cmd = MapManager.air_theater_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.air_theater_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("Air theater primary command (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	_add_apply_button("Run air theater primary (full package)", "air_theater_primary_command_product", true)
	_add_apply_button("[C3] Recon / sortie board", "apply_air_theater_recon", true)
	_add_apply_button("[C3] CAS / weather gate", "apply_air_theater_cas_gate", true)
	_add_apply_button("[C3] Interdiction strike", "apply_air_theater_interdiction", true)
	_add_apply_button("[C3] Air theater close", "apply_air_multi_phase_theater_close_day", true)


func _rebuild_battle_aar_primary_command() -> void:
	_add_section_title("— Battle AAR primary command (C4 open→close) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("battle_aar_primary_command_product_live"):
		cmd = MapManager.battle_aar_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.battle_aar_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("Battle AAR primary command (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	_add_apply_button("Run battle AAR primary (full package)", "battle_aar_primary_command_product", true)
	_add_apply_button("[C4] Open multi-phase board", "apply_multi_phase_combat_product", true)
	_add_apply_button("[C4] Record combat ops close", "apply_combat_ops_close", true)
	_add_apply_button("[C4] Engage phase factors", "phase_engage", true)
	_add_apply_button("[C4] Persist AAR trail", "apply_battle_aar_persist_live", true)
	_add_apply_button("[C4] Close AAR package", "apply_battle_aar_close_live", true)


func _rebuild_command_journal_primary_command() -> void:
	_add_section_title("— Command journal primary (N2 seed→verify) —")
	var cmd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("command_journal_primary_command_product_live"):
		cmd = MapManager.command_journal_primary_command_product_live(province_id)
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		cmd = MapPolishFormatters.command_journal_primary_command_product(province_id)
	if cmd.is_empty() or bool(cmd.get("empty", false)):
		_add_plain_label("Command journal primary (unavailable)", 120)
		return
	_add_plain_label(str(cmd.get("summary", "")), 300)
	_add_apply_button("Run command journal primary (full package)", "command_journal_primary_command_product", true)
	_add_apply_button("[N2] Seed journal", "apply_command_journal_seed_live", true)
	_add_apply_button("[N2] Enqueue batch", "apply_command_journal_enqueue_live", true)
	_add_apply_button("[N2] Flush / replay", "apply_command_journal_flush_live", true)
	_add_apply_button("[N2] Verify seed fingerprint", "apply_command_journal_verify_live", true)
	_add_apply_button("[N2] Close journal package", "apply_command_journal_close_live", true)

func _rebuild_map_perf_measured_primary_command() -> void:
	_add_section_title("— Map perf measured primary (M3 samples→budget) —")
	_add_apply_button("Run map perf measured primary", "map_perf_measured_primary_command_product", true)
	_add_apply_button("[M3] Sample frames (Performance/MapRenderer)", "apply_map_perf_sample_frames_live", true)
	_add_apply_button("[M3] Budget 30fps", "apply_map_perf_budget_30_live", true)
	_add_apply_button("[M3] Budget 60fps", "apply_map_perf_budget_60_live", true)
	_add_apply_button("[M3] Measured close", "apply_map_perf_measured_close_live", true)


func _rebuild_war_goal_alliance_primary_command() -> void:
	_add_section_title("— War goal + alliance primary (Di2) —")
	_add_apply_button("Run war goal alliance primary", "war_goal_alliance_primary_command_product", true)
	_add_apply_button("[Di2] War goal board", "apply_war_goal_board", true)
	_add_apply_button("[Di2] Justify", "apply_war_goal_justify", true)
	_add_apply_button("[Di2] Execute", "apply_war_goal_execute", true)
	_add_apply_button("[Di2] Alliance guarantee", "apply_alliance_guarantee", true)
	_add_apply_button("[Di2] Close package", "apply_strategic_war_goal_close_day", true)


func _rebuild_factory_retool_primary_command() -> void:
	_add_section_title("— Factory retool primary (P2 risk→horizon) —")
	_add_apply_button("Run factory retool primary", "factory_retool_primary_command_product", true)
	_add_apply_button("[P2] Honesty board", "apply_medium_tank_production_honesty_product", true)
	_add_apply_button("[P2] Factory risk", "apply_medium_honesty_factory_risk_day", true)
	_add_apply_button("[P2] Retool horizon 80d", "oob_horizon_80d", true)
	_add_apply_button("[P2] Prove 60d", "apply_medium_honesty_prove_60d", true)
	_add_apply_button("[P2] Close", "apply_medium_tank_production_honesty_close_day", true)

func _rebuild_tutorial_first_session_primary_command() -> void:
	_add_section_title("— Tutorial first-session primary (U1) —")
	_add_apply_button("Run tutorial first-session primary", "tutorial_first_session_primary_command_product", true)
	_add_apply_button("[U1] Brief", "apply_tutorial_session_brief", true)
	_add_apply_button("[U1] Guide", "apply_tutorial_session_guide", true)
	_add_apply_button("[U1] Checkpoint", "apply_tutorial_session_checkpoint", true)
	_add_apply_button("[U1] Product", "apply_tutorial_first_session_product", true)
	_add_apply_button("[U1] Close", "apply_tutorial_first_session_close_day", true)


func _rebuild_multi_faction_ai_primary_command() -> void:
	_add_section_title("— Multi-faction AI primary (A3) —")
	_add_apply_button("Run multi-faction AI primary", "multi_faction_ai_primary_command_product", true)
	_add_apply_button("[A3] Scan factions", "apply_strategic_ai_scan", true)
	_add_apply_button("[A3] Rank priorities", "apply_strategic_ai_rank", true)
	_add_apply_button("[A3] Execute top", "apply_strategic_ai_execute", true)
	_add_apply_button("[A3] Multi-faction product", "apply_multi_faction_strategic_ai_product", true)
	_add_apply_button("[A3] Campaign close", "apply_strategic_ai_campaign_close_day", true)

func _rebuild_weather_theater_primary_command() -> void:
	_add_section_title("— Weather theater primary (W1) —")
	_add_apply_button("Run weather theater primary", "weather_theater_primary_command_product", true)
	_add_apply_button("[W1] Pressure board", "apply_weather_theater_pressure", true)
	_add_apply_button("[W1] Combat/logistics gate", "apply_weather_theater_gate", true)
	_add_apply_button("[W1] Crisis response", "apply_weather_theater_crisis", true)
	_add_apply_button("[W1] Ops product", "apply_weather_theater_ops_product", true)
	_add_apply_button("[W1] Close", "apply_weather_theater_ops_close_day", true)


func _rebuild_manpower_laws_primary_command() -> void:
	_add_section_title("— Manpower laws primary (O2) —")
	_add_apply_button("Run manpower laws primary", "manpower_laws_primary_command_product", true)
	_add_apply_button("[O2] Laws/training product", "apply_manpower_laws_training_product", true)
	_add_apply_button("[O2] Training tick", "apply_manpower_training_tick_live", true)
	_add_apply_button("[O2] Cohort board", "apply_manpower_cohort_board", true)
	_add_apply_button("[O2] Mobilize", "apply_manpower_cohort_mobilize", true)
	_add_apply_button("[O2] Close", "apply_manpower_cohort_reserve_close_day", true)

func _rebuild_focus_tree_primary_command() -> void:
	_add_section_title("— Focus tree primary (T2) —")
	_add_apply_button("Run focus tree primary", "focus_tree_primary_command_product", true)
	_add_apply_button("[T2] Catalog", "apply_focus_tree_catalog", true)
	_add_apply_button("[T2] Path", "apply_focus_tree_path", true)
	_add_apply_button("[T2] Commit", "apply_focus_tree_commit", true)
	_add_apply_button("[T2] Product", "apply_focus_tree_content_product", true)
	_add_apply_button("[T2] Close", "apply_focus_tree_content_close_day", true)


func _rebuild_leader_theater_primary_command() -> void:
	_add_section_title("— Leader theater primary (L2) —")
	_add_apply_button("Run leader theater primary", "leader_theater_primary_command_product", true)
	_add_apply_button("[L2] HQ board", "apply_leader_hq_board", true)
	_add_apply_button("[L2] Multi-station", "apply_leader_multi_station", true)
	_add_apply_button("[L2] Theater ops", "apply_leader_theater_ops", true)
	_add_apply_button("[L2] Product", "apply_leader_theater_command_product", true)
	_add_apply_button("[L2] Close", "apply_leader_theater_command_close_day", true)


func _rebuild_intel_network_primary_command() -> void:
	_add_section_title("— Intel network primary (I2) —")
	_add_apply_button("Run intel network primary", "intel_network_primary_command_product", true)
	_add_apply_button("[I2] Coverage", "apply_intel_network_coverage", true)
	_add_apply_button("[I2] Counterintel", "apply_intel_network_counterintel", true)
	_add_apply_button("[I2] Counterplay", "apply_intel_network_counterplay", true)
	_add_apply_button("[I2] Network product", "apply_intelligence_network_product", true)
	_add_apply_button("[I2] Close", "apply_intelligence_network_close_day", true)


func _rebuild_product_ux_primary_command() -> void:
	_add_section_title("— Product UX primary (U2) —")
	_add_apply_button("Run product UX primary", "product_ux_primary_command_product", true)
	_add_apply_button("[U2] Compact board", "apply_product_ux_compact_board", true)
	_add_apply_button("[U2] Top chips", "apply_product_ux_top_chips", true)
	_add_apply_button("[U2] Hotkeys", "apply_product_ux_hotkeys", true)
	_add_apply_button("[U2] Polish product", "apply_product_ux_command_polish_product", true)
	_add_apply_button("[U2] Close", "apply_product_ux_polish_close_day", true)



func _rebuild_combat_intel_estimate_primary_command() -> void:
	_add_section_title("— Combat intel estimate primary (I2b) —")
	_add_apply_button("Run combat intel estimate primary", "combat_intel_estimate_primary_command_product", true)
	_add_apply_button("[I2b] Multi-phase estimate", "apply_multi_phase_estimate_day", true)
	_add_apply_button("[I2b] Recon coverage", "apply_intel_network_coverage", true)
	_add_apply_button("[I2b] Counter sweep", "apply_intel_counter_sweep", true)
	_add_apply_button("[I2b] Assault card", "apply_assault_card_day", true)
	_add_apply_button("[I2b] Close", "apply_combat_agent_joint_close_day", true)


func _rebuild_convoy_sealane_primary_command() -> void:
	_add_section_title("— Convoy sealane primary (E2) —")
	_add_apply_button("Run convoy sealane primary", "convoy_sealane_primary_command_product", true)
	_add_apply_button("[E2] Convoy escort", "apply_convoy_escort_ops_day", true)
	_add_apply_button("[E2] Sealane health", "apply_sealane_health_ops_day", true)
	_add_apply_button("[E2] Convoy/sealane joint", "apply_convoy_sealane_joint_day", true)
	_add_apply_button("[E2] Trade route", "apply_trade_route_ops_day", true)
	_add_apply_button("[E2] Close", "apply_convoy_sealane_close_day", true)


func _rebuild_designer_suite_primary_command() -> void:
	_add_section_title("— Designer suite primary (D1) —")
	_add_apply_button("Run designer suite primary", "designer_suite_primary_command_product", true)
	_add_apply_button("[D1] Catalog", "apply_designer_suite_catalog", true)
	_add_apply_button("[D1] Pick domain", "apply_designer_suite_pick", true)
	_add_apply_button("[D1] Seed production", "apply_designer_suite_seed", true)
	_add_apply_button("[D1] Suite product", "apply_designer_suite_product", true)
	_add_apply_button("[D1] Close", "apply_designer_industry_close_day", true)


func _rebuild_autosave_session_primary_command() -> void:
	_add_section_title("— Autosave session primary (S2) —")
	_add_apply_button("Run autosave session primary", "autosave_session_primary_command_product", true)
	_add_apply_button("[S2] Save browser", "apply_save_browser_campaign_product", true)
	_add_apply_button("[S2] Autosave session", "apply_autosave_session_ops_day", true)
	_add_apply_button("[S2] Resume", "apply_save_browser_resume", true)
	_add_apply_button("[S2] Checkpoint", "apply_save_browser_checkpoint", true)
	_add_apply_button("[S2] Close", "apply_save_session_close_day", true)


func _rebuild_historical_oob_primary_command() -> void:
	_add_section_title("— Historical OOB primary (X1) —")
	_add_apply_button("Run historical OOB primary", "historical_oob_primary_command_product", true)
	_add_apply_button("[X1] Catalog", "apply_historical_oob_catalog", true)
	_add_apply_button("[X1] Seed lines", "apply_historical_oob_seed", true)
	_add_apply_button("[X1] Equip formations", "apply_historical_oob_equip", true)
	_add_apply_button("[X1] Content product", "apply_historical_oob_content_product", true)
	_add_apply_button("[X1] Close", "apply_historical_oob_content_close_day", true)


func _rebuild_intel_counter_primary_command() -> void:
	_add_section_title("— Intel counter primary (I3) —")
	_add_apply_button("Run intel counter primary", "intel_counter_primary_command_product", true)
	_add_apply_button("[I3] Counterintel", "apply_intel_network_counterintel", true)
	_add_apply_button("[I3] Sweep", "apply_intel_counter_sweep", true)
	_add_apply_button("[I3] Counterplay", "apply_intel_network_counterplay", true)
	_add_apply_button("[I3] Cell ops", "apply_intel_cell_ops", true)
	_add_apply_button("[I3] Close", "apply_intelligence_network_close_day", true)


func _rebuild_faction_personality_primary_command() -> void:
	_add_section_title("— Faction personality primary (A4) —")
	_add_apply_button("Run faction personality primary", "faction_personality_primary_command_product", true)
	_add_apply_button("[A4] Personality board", "apply_personality_board", true)
	_add_apply_button("[A4] Event reaction", "apply_personality_event", true)
	_add_apply_button("[A4] Doctrine drive", "apply_personality_drive", true)
	_add_apply_button("[A4] AI product", "apply_faction_personality_ai_product", true)
	_add_apply_button("[A4] Close", "apply_faction_personality_ai_close_day", true)


func _rebuild_production_honesty_primary_command() -> void:
	_add_section_title("— Production honesty primary (P3) —")
	_add_apply_button("Run production honesty primary", "production_honesty_primary_command_product", true)
	_add_apply_button("[P3] Honesty product", "apply_medium_tank_production_honesty_product", true)
	_add_apply_button("[P3] Prove 60d", "apply_medium_honesty_prove_60d", true)
	_add_apply_button("[P3] Prove 100d", "apply_medium_honesty_prove_100d", true)
	_add_apply_button("[P3] Medium OOB", "apply_medium_tank_oob_product", true)
	_add_apply_button("[P3] Close", "apply_medium_tank_production_honesty_close_day", true)


func _rebuild_hh_multi_month_primary_command() -> void:
	_add_section_title("— HH multi-month primary (L) —")
	_add_apply_button("Run HH multi-month primary", "hh_multi_month_primary_command_product", true)
	_add_apply_button("[HH] Agenda product", "apply_hh_multi_month_agenda_product", true)
	_add_apply_button("[HH] Month trail board", "apply_hh_month_trail_board", true)
	_add_apply_button("[HH] Month brief", "apply_hh_month_brief", true)
	_add_apply_button("[HH] Sequence", "apply_hh_multi_month_sequence", true)
	_add_apply_button("[HH] Close", "apply_hh_agenda_close_live", true)


func _rebuild_logistics_supply_primary_command() -> void:
	_add_section_title("— Logistics supply primary —")
	_add_apply_button("Run logistics supply primary", "logistics_supply_primary_command_product", true)
	_add_apply_button("[LOG] Theater product", "apply_logistics_supply_theater_product", true)
	_add_apply_button("[LOG] Route", "apply_logistics_supply_route", true)
	_add_apply_button("[LOG] Sustain", "apply_logistics_supply_sustain", true)
	_add_apply_button("[LOG] Readiness", "apply_logistics_supply_readiness", true)
	_add_apply_button("[LOG] Close", "apply_logistics_supply_close_day", true)


func _rebuild_front_continuity_primary_command() -> void:
	_add_section_title("— Front continuity primary (C) —")
	_add_apply_button("Run front continuity primary", "front_continuity_primary_command_product", true)
	_add_apply_button("[FC] Campaign product", "apply_front_continuity_campaign_product", true)
	_add_apply_button("[FC] Combat", "apply_front_continuity_combat", true)
	_add_apply_button("[FC] Assault", "apply_front_continuity_assault", true)
	_add_apply_button("[FC] Sustain", "apply_front_continuity_sustain", true)
	_add_apply_button("[FC] Close", "apply_front_continuity_campaign_close_day", true)


func _rebuild_designer_depth_primary_command() -> void:
	_add_section_title("— Designer depth primary (D) —")
	_add_apply_button("Run designer depth primary", "designer_depth_primary_command_product", true)
	_add_apply_button("[DD] Module editor", "apply_designer_module_editor_product", true)
	_add_apply_button("[DD] Module board", "apply_designer_module_board", true)
	_add_apply_button("[DD] Stats field", "apply_designer_stats_field_product", true)
	_add_apply_button("[DD] Multi-domain campaign", "apply_designer_multi_domain_campaign_product", true)
	_add_apply_button("[DD] Close", "apply_designer_multi_domain_campaign_close_day", true)


func _rebuild_air_multi_phase_primary_command() -> void:
	_add_section_title("— Air multi-phase primary (C3) —")
	_add_apply_button("Run air multi-phase primary", "air_multi_phase_primary_command_product", true)
	_add_apply_button("[AMP] Theater product", "apply_air_multi_phase_theater_product", true)
	_add_apply_button("[AMP] Sortie", "apply_air_ops_sortie", true)
	_add_apply_button("[AMP] Weather gate", "apply_air_ops_weather_gate", true)
	_add_apply_button("[AMP] Air-land", "apply_air_ops_air_land", true)
	_add_apply_button("[AMP] Close", "apply_air_multi_phase_theater_close_day", true)


func _rebuild_inspector_decision_primary_command() -> void:
	_add_section_title("— Inspector decision primary —")
	_add_apply_button("Run inspector decision primary", "inspector_decision_primary_command_product", true)
	_add_apply_button("[INS] Decision product", "apply_inspector_decision_product", true)
	_add_apply_button("[INS] Primary", "apply_inspector_product_primary", true)
	_add_apply_button("[INS] Collapse", "apply_inspector_product_collapse", true)
	_add_apply_button("[INS] Apply", "apply_inspector_product_apply", true)
	_add_apply_button("[INS] Close", "apply_inspector_surface_close_day", true)


func _rebuild_balance_combat_supply_primary_command() -> void:
	_add_section_title("— Balance combat/supply primary (Q) —")
	_add_apply_button("Run balance combat/supply primary", "balance_combat_supply_primary_command_product", true)
	_add_apply_button("[BAL] Product", "apply_balance_combat_supply_product", true)
	_add_apply_button("[BAL] Estimate board", "apply_balance_estimate_board", true)
	_add_apply_button("[BAL] Live sample", "apply_balance_live_sample", true)
	_add_apply_button("[BAL] Variance close", "apply_balance_variance_close", true)
	_add_apply_button("[BAL] Close", "apply_balance_combat_supply_close_day", true)


func _rebuild_fleet_multi_day_primary_command() -> void:
	_add_section_title("— Fleet multi-day primary (C2) —")
	_add_apply_button("Run fleet multi-day primary", "fleet_multi_day_primary_command_product", true)
	_add_apply_button("[FMD] Autonomy product", "apply_fleet_multi_day_autonomy_product", true)
	_add_apply_button("[FMD] Posture", "apply_fleet_day_posture", true)
	_add_apply_button("[FMD] Station escort", "apply_fleet_day_station_escort", true)
	_add_apply_button("[FMD] Follow-through", "apply_fleet_day_follow_through", true)
	_add_apply_button("[FMD] Sequence", "apply_fleet_multi_day_sequence", true)


func _rebuild_agent_campaign_primary_command() -> void:
	_add_section_title("— Agent campaign primary (major #6) —")
	_add_apply_button("Run agent campaign primary", "agent_campaign_primary_command_product", true)
	_add_apply_button("[ACP] Board", "apply_agent_product_board", true)
	_add_apply_button("[ACP] Dispatch", "apply_agent_product_dispatch", true)
	_add_apply_button("[ACP] Counterplay", "apply_agent_product_counterplay", true)
	_add_apply_button("[ACP] Sequence", "apply_agent_campaign_sequence", true)
	_add_apply_button("[ACP] Product", "apply_agent_campaign_product", true)


func _rebuild_grand_strategy_cycle_primary_command() -> void:
	_add_section_title("— Grand strategy cycle primary (major #55) —")
	_add_apply_button("Run GS cycle primary", "grand_strategy_cycle_primary_command_product", true)
	_add_apply_button("[GSC] Product", "apply_grand_strategy_cycle_product", true)
	_add_apply_button("[GSC] Scan", "apply_gs_cycle_scan", true)
	_add_apply_button("[GSC] Rank", "apply_gs_cycle_rank", true)
	_add_apply_button("[GSC] Execute", "apply_gs_cycle_execute", true)
	_add_apply_button("[GSC] Close", "apply_grand_strategy_cycle_close_day", true)


func _rebuild_world_class_primary_command() -> void:
	_add_section_title("— World-class campaign primary —")
	_add_apply_button("Run world-class primary", "world_class_primary_command_product", true)
	_add_apply_button("[WCC] Product", "apply_world_class_campaign_command_product", true)
	_add_apply_button("[WCC] Scan", "apply_world_class_scan", true)
	_add_apply_button("[WCC] Rank", "apply_world_class_rank", true)
	_add_apply_button("[WCC] Execute", "apply_world_class_execute", true)
	_add_apply_button("[WCC] Close", "apply_world_class_campaign_close_day", true)


func _rebuild_multi_front_primary_command() -> void:
	_add_section_title("— Multi-front campaign AI primary (major #54) —")
	_add_apply_button("Run multi-front primary", "multi_front_primary_command_product", true)
	_add_apply_button("[MFC] Product", "apply_multi_front_campaign_ai_product", true)
	_add_apply_button("[MFC] Plan", "apply_multi_front_plan", true)
	_add_apply_button("[MFC] Weekly", "apply_multi_front_weekly", true)
	_add_apply_button("[MFC] Execute", "apply_multi_front_execute", true)
	_add_apply_button("[MFC] Close", "apply_multi_front_campaign_ai_close_day", true)


func _rebuild_strategic_war_goal_primary_command() -> void:
	_add_section_title("— Strategic war-goal primary (major #53) —")
	_add_apply_button("Run strategic war-goal primary", "strategic_war_goal_primary_command_product", true)
	_add_apply_button("[SWG] Product", "apply_strategic_war_goal_product", true)
	_add_apply_button("[SWG] Board", "apply_war_goal_board", true)
	_add_apply_button("[SWG] Justify", "apply_war_goal_justify", true)
	_add_apply_button("[SWG] Execute", "apply_war_goal_execute", true)
	_add_apply_button("[SWG] Close", "apply_strategic_war_goal_close_day", true)


func _rebuild_naval_search_strike_primary_command() -> void:
	_add_section_title("— Naval search/strike primary —")
	_add_apply_button("Run naval search/strike primary", "naval_search_strike_primary_command_product", true)
	_add_apply_button("[NSS] Product", "apply_naval_search_strike_product", true)
	_add_apply_button("[NSS] Patrol", "apply_naval_search_patrol", true)
	_add_apply_button("[NSS] ASW escort", "apply_naval_asw_escort", true)
	_add_apply_button("[NSS] Carrier strike", "apply_naval_carrier_strike", true)
	_add_apply_button("[NSS] Close", "apply_naval_search_strike_close_day", true)


func _rebuild_weather_crisis_primary_command() -> void:
	_add_section_title("— Weather crisis primary —")
	_add_apply_button("Run weather crisis primary", "weather_crisis_primary_command_product", true)
	_add_apply_button("[WCR] Product", "apply_weather_crisis_campaign_product", true)
	_add_apply_button("[WCR] Forecast", "apply_weather_crisis_forecast", true)
	_add_apply_button("[WCR] Gate multi", "apply_weather_crisis_gate_multi", true)
	_add_apply_button("[WCR] Sustain", "apply_weather_crisis_sustain", true)
	_add_apply_button("[WCR] Close", "apply_weather_crisis_campaign_close_day", true)


func _rebuild_campaign_ai_multi_month_primary_command() -> void:
	_add_section_title("— Campaign AI multi-month primary —")
	_add_apply_button("Run campaign AI multi-month primary", "campaign_ai_multi_month_primary_command_product", true)
	_add_apply_button("[CAM] Product", "apply_campaign_ai_multi_month_product", true)
	_add_apply_button("[CAM] Month board", "apply_campaign_ai_month_board", true)
	_add_apply_button("[CAM] Weekly plan", "apply_campaign_ai_weekly_plan", true)
	_add_apply_button("[CAM] Theater execute", "apply_campaign_ai_theater_execute", true)
	_add_apply_button("[CAM] Close", "apply_campaign_ai_multi_month_close_day", true)


func _rebuild_tech_research_primary_command() -> void:
	_add_section_title("— Tech research primary —")
	_add_apply_button("Run tech research primary", "tech_research_primary_command_product", true)
	_add_apply_button("[TRC] Product", "apply_tech_research_campaign_product", true)
	_add_apply_button("[TRC] Catalog", "apply_tech_research_catalog", true)
	_add_apply_button("[TRC] Priority", "apply_tech_research_priority", true)
	_add_apply_button("[TRC] Field", "apply_tech_research_field", true)
	_add_apply_button("[TRC] Close", "apply_tech_research_close_day", true)


func _rebuild_focus_war_path_primary_command() -> void:
	_add_section_title("— Focus war-path primary —")
	_add_apply_button("Run focus war-path primary", "focus_war_path_primary_command_product", true)
	_add_apply_button("[FWP] Product", "apply_focus_war_path_product", true)
	_add_apply_button("[FWP] Pick", "apply_focus_war_pick", true)
	_add_apply_button("[FWP] Path step", "apply_focus_war_path_step", true)
	_add_apply_button("[FWP] Commit", "apply_focus_war_commit", true)
	_add_apply_button("[FWP] Close", "apply_focus_war_path_close_day", true)


func _rebuild_naval_multi_phase_primary_command() -> void:
	_add_section_title("— Naval multi-phase primary —")
	_add_apply_button("Run naval multi-phase primary", "naval_multi_phase_primary_command_product", true)
	_add_apply_button("[NMP] Product", "apply_naval_multi_phase_campaign_product", true)
	_add_apply_button("[NMP] Posture", "apply_naval_phase_posture", true)
	_add_apply_button("[NMP] Escort", "apply_naval_phase_escort", true)
	_add_apply_button("[NMP] Strike", "apply_naval_phase_strike", true)
	_add_apply_button("[NMP] Close", "apply_naval_multi_phase_close_day", true)


func _rebuild_diplomacy_peace_primary_command() -> void:
	_add_section_title("— Diplomacy/peace primary —")
	_add_apply_button("Run diplomacy/peace primary", "diplomacy_peace_primary_command_product", true)
	_add_apply_button("[DPC] Product", "apply_diplomacy_peace_campaign_product", true)
	_add_apply_button("[DPC] Board", "apply_diplomacy_peace_board", true)
	_add_apply_button("[DPC] Leverage", "apply_diplomacy_peace_leverage", true)
	_add_apply_button("[DPC] Settle", "apply_diplomacy_peace_settle", true)
	_add_apply_button("[DPC] Close", "apply_diplomacy_peace_close_day", true)


func _rebuild_save_resume_primary_command() -> void:
	_add_section_title("— Save/resume primary —")
	_add_apply_button("Run save/resume primary", "save_resume_primary_command_product", true)
	_add_apply_button("[SRP] Product", "apply_save_resume_campaign_product", true)
	_add_apply_button("[SRP] Checkpoint", "apply_save_resume_checkpoint", true)
	_add_apply_button("[SRP] Save", "apply_save_resume_save", true)
	_add_apply_button("[SRP] Resume", "apply_save_resume_resume", true)
	_add_apply_button("[SRP] Close", "apply_save_resume_campaign_close_day", true)


func _rebuild_play_session_primary_command() -> void:
	_add_section_title("— Play-session primary —")
	_add_apply_button("Run play-session primary", "play_session_primary_command_product", true)
	_add_apply_button("[PSC] Product", "apply_play_session_campaign_product", true)
	_add_apply_button("[PSC] Brief", "apply_play_session_brief", true)
	_add_apply_button("[PSC] Execute", "apply_play_session_execute", true)
	_add_apply_button("[PSC] Resolve", "apply_play_session_resolve", true)
	_add_apply_button("[PSC] Close", "apply_play_session_campaign_close_day", true)


func _rebuild_ai_difficulty_primary_command() -> void:
	_add_apply_button("Run AI difficulty primary (presets)", "ai_difficulty_primary_command_product", true)

func _rebuild_hotseat_session_primary_command() -> void:
	_add_apply_button("Run hotseat session primary", "hotseat_session_primary_command_product", true)


func _rebuild_pack_n_era_primary_command() -> void:
	_add_apply_button("Run Pack N era primary", "pack_n_era_primary_command_product", true)

func _rebuild_pack_n_events_primary_command() -> void:
	_add_apply_button("Run Pack N events/focus primary", "pack_n_events_primary_command_product", true)


func _rebuild_hoi_panel_primary_command() -> void:
	_add_apply_button("Run HOI panel polish primary", "hoi_panel_primary_command_product", true)


func _rebuild_q1_validator_primary_command() -> void:
	_add_apply_button("Run Q1 validator honesty primary", "q1_validator_primary_command_product", true)

func _rebuild_combat_production_partial_primary_command() -> void:
	_add_apply_button("Run combat/production partial primary", "combat_production_partial_primary_command_product", true)


func _rebuild_pack_n_narrative_primary_command() -> void:
	_add_apply_button("Run Pack N narrative primary", "pack_n_narrative_primary_command_product", true)


func _rebuild_hoi_screen_primary_command() -> void:
	_add_apply_button("Run HOI screen depth primary", "hoi_screen_primary_command_product", true)


func _rebuild_q1_checklist_primary_command() -> void:
	_add_apply_button("Run Q1 checklist depth primary", "q1_checklist_primary_command_product", true)


func _rebuild_combat_production_depth_primary_command() -> void:
	_add_apply_button("Run Combat/production depth primary", "combat_production_depth_primary_command_product", true)


func _rebuild_n3_preflight_primary_command() -> void:
	_add_apply_button("Run N3 preflight primary", "n3_preflight_primary_command_product", true)


func _rebuild_pack_n_content_primary_command() -> void:
	_add_apply_button("Run Pack N content depth primary", "pack_n_content_primary_command_product", true)


func _rebuild_hoi_fullscreen_primary_command() -> void:
	_add_apply_button("Run HOI fullscreen surface primary", "hoi_fullscreen_primary_command_product", true)


func _rebuild_q1_rc_checklist_primary_command() -> void:
	_add_apply_button("Run Q1 RC checklist primary", "q1_rc_checklist_primary_command_product", true)


func _rebuild_combat_engine_depth_primary_command() -> void:
	_add_apply_button("Run Combat engine depth primary", "combat_engine_depth_primary_command_product", true)

func _rebuild_resource_production_primary_command() -> void:
	_add_apply_button("Run resource production primary (shortage)", "resource_production_primary_command_product", true)


func _rebuild_resource_harvest_primary_command() -> void:
	_add_apply_button("Run resource harvest primary (plants+tech)", "resource_harvest_primary_command_product", true)


func _rebuild_resource_economy_depth_primary_command() -> void:
	_add_apply_button("Run resource economy depth (food+combat+plants)", "resource_economy_depth_primary_command_product", true)


func _rebuild_resource_open_items_primary_command() -> void:
	_add_apply_button("Run resource open items (plants+endgame+trade)", "resource_open_items_primary_command_product", true)


func _rebuild_trade_relations_primary_command() -> void:
	_add_apply_button("Run trade relations ledger (SUU+CRS+flags)", "trade_relations_primary_command_product", true)


func _rebuild_trade_power_intel_primary_command() -> void:
	_add_apply_button("Run trade power intel (nukes+transit+spy)", "trade_power_intel_primary_command_product", true)
