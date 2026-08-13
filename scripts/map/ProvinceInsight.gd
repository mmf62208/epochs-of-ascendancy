class_name ProvinceInsight
extends RefCounted

## Formats province hover tooltips, inspector panels, and supply notes from Province + ProvinceEffects.

const PROVINCE_MODIFIER_KEYS: Array[String] = [
	"supply_throughput",
	"local_supply",
	"combat_width",
	"organization_recovery",
	"attrition_reduction",
	"interdiction_resistance",
	"reinforcement_speed",
	"logistics_quality",
	"supply_consumption",
	"attrition",
	"interdiction",
	"logistics",
]

const COLOR_HEADER := "[color=#6eb5ff]"
const COLOR_BASE := "[color=#a8b4c8]"
const COLOR_EFFECTIVE := "[color=#7dffb2]"
const COLOR_NATIONAL := "[color=#e8a0ff]"
const COLOR_WARN := "[color=#ff9a6e]"
const COLOR_MUTED := "[color=#8899aa]"
const COLOR_PROVINCE := "[color=#a8c4e8]"  ## Map chips: align with soft tech / trade readability
const COLOR_DIVIDER := "[color=#4a5568]"
const COLOR_TECH := "[color=#6ec8ff]"

## Maps ProvinceEffects national_modifiers keys to readable labels.
const NATIONAL_KEY_LABELS: Dictionary = {
	"supply_throughput": "Supply throughput",
	"local_supply": "Local supply generation",
	"combat_width": "Combat width",
	"organization_recovery": "Organization recovery",
	"attrition_reduction": "Attrition reduction",
	"interdiction_resistance": "Interdiction resistance",
	"reinforcement_speed": "Reinforcement speed",
	"logistics_quality": "Logistics quality",
	"supply_consumption": "Supply consumption",
}


static func build_compact_hover_tooltip(province: Province) -> String:
	if province == null:
		return ""
	var top: Dictionary = build_inspector_topline(province)
	var lines: PackedStringArray = []
	lines.append(str(top.get("title", province.name)))
	lines.append(str(top.get("owner_line", "Owner: Unowned")))
	var region_line := str(top.get("region_line", ""))
	if not region_line.is_empty():
		lines.append(region_line)
	var sea_line := str(top.get("sea_zone_line", ""))
	if not sea_line.is_empty():
		lines.append(sea_line)
	lines.append(province.terrain.capitalize())
	return "\n".join(lines)


## Top-line inspector identity: name, owner, strategic region, sea zone (when assigned).
## Resolves live MapManager region/sea zone; pure formatting via MapPolishFormatters.
static func build_inspector_topline(province: Province) -> Dictionary:
	if province == null:
		return _MapPolishFormatters.format_inspector_topline("Province", "", "", "")
	var owner := province.owner_tag.strip_edges()
	if owner.is_empty():
		owner = country_tag_for_province(province)
	var region := ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_region_id"):
		var rid: int = province.strategic_region_id if province.strategic_region_id > 0 else MapManager.get_province_region_id(province.id)
		if rid > 0 and MapManager.has_method("get_strategic_region_name"):
			region = str(MapManager.get_strategic_region_name(rid)).strip_edges()
	var sea_zone := ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_sea_zone_name"):
		sea_zone = str(MapManager.get_sea_zone_name(province.id)).strip_edges()
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
		if MapManager.has_strategic_chokepoint(province.id):
			if sea_zone.is_empty():
				sea_zone = "⚓ Naval chokepoint / strait"
			elif "chokepoint" not in sea_zone.to_lower() and "strait" not in sea_zone.to_lower():
				sea_zone = "%s · ⚓ chokepoint" % sea_zone
	return _MapPolishFormatters.format_inspector_topline(province.name, owner, region, sea_zone)


static func build_strategic_hover_tooltip(province: Province) -> String:
	if province == null:
		return ""
	var owner := province.owner_tag.strip_edges()
	if owner.is_empty():
		owner = country_tag_for_province(province)
	var nation := owner
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_country") and not owner.is_empty():
		var country = MapManager.get_country(owner)
		if country is Dictionary and country.has("name"):
			nation = str(country["name"])
	var region := ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_region_id"):
		var rid: int = province.strategic_region_id if province.strategic_region_id > 0 else MapManager.get_province_region_id(province.id)
		if rid > 0:
			region = MapManager.get_strategic_region_name(rid)
	var choke := ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
		if MapManager.has_strategic_chokepoint(province.id):
			choke = "⚓ Naval chokepoint"
	if not choke.is_empty() and not region.is_empty():
		return "%s\n%s · %s\n%s" % [nation, region, province.name, choke]
	if not choke.is_empty():
		return "%s\n%s\n%s" % [nation, province.name, choke]
	if not region.is_empty():
		return "%s\n%s · %s" % [nation, region, province.name]
	return "%s\n%s" % [nation, province.name]


static func build_hover_tooltip(
	province: Province,
	selected_province_id: int = -1,
	other_province: Province = null,
	supply_overlay_active: bool = false,
	hover_supply_role: String = "",
	is_compare_candidate: bool = false,
	is_contested: bool = false,
	has_agent_network: bool = false,
) -> String:
	var report := build_province_report(province, selected_province_id, other_province)
	report["supply_overlay_active"] = supply_overlay_active
	report["selected_province_id"] = selected_province_id
	report["other_province"] = other_province
	report["hover_supply_role"] = hover_supply_role
	report["is_compare_candidate"] = is_compare_candidate
	report["is_contested"] = is_contested or is_province_contested(province)
	report["has_agent_network"] = has_agent_network or has_active_agent_network(province)
	var tag := country_tag_for_province(province)
	var chip_limit := 4
	if supply_overlay_active and province_needs_infrastructure_ui(province):
		chip_limit = 5
	if supply_overlay_active and (
		(bool(report.get("is_contested", false)) and bool(report.get("has_agent_network", false)))
		or (
			province_needs_infrastructure_ui(province)
			and (bool(report.get("is_contested", false)) or bool(report.get("has_agent_network", false)))
		)
	):
		chip_limit = 6
	if (
		province_benefits_country(province, tag)
		and MapTechnologyContext.country_has_map_technology(tag)
	):
		chip_limit = maxi(chip_limit, 6)
	if province != null and typeof(FactoryManager) != TYPE_NIL:
		if FactoryManager.get_factories_in_province(province.id).size() > 0:
			chip_limit = maxi(chip_limit, 7)
			var overlay_busy := supply_overlay_active and (
				bool(report.get("is_contested", false)) and bool(report.get("has_agent_network", false))
			)
			if overlay_busy:
				chip_limit = maxi(chip_limit, 8)
			elif supply_overlay_active and (
				bool(report.get("is_contested", false)) or bool(report.get("has_agent_network", false))
			):
				chip_limit = maxi(chip_limit, 7)
	var chip := build_tooltip_mode_chip_for_state(
		supply_overlay_active,
		other_province != null,
		selected_province_id == province.id,
		hover_supply_role,
		is_compare_candidate,
		bool(report["is_contested"]),
		bool(report["has_agent_network"]),
		tag,
		chip_limit,
		province,
	)
	var body := format_report_tooltip(report)
	var strategic := MapTechnologyContext.build_province_build_strategic_tooltip_bbcode(
		province, tag,
	)
	if not strategic.is_empty():
		body = body + "\n\n" + strategic if not body.is_empty() else strategic
	if chip.is_empty():
		return body
	return chip + "\n" + body


static func build_inspector_text(
	province: Province,
	selected_province_id: int = -1,
) -> String:
	return build_inspector_full_bbcode(province, selected_province_id)


static func build_inspector_full_bbcode(
	province: Province,
	selected_province_id: int = -1,
) -> String:
	var report := build_province_report(province, selected_province_id, null)
	if report.is_empty():
		return ""
	var pe: ProvinceEffects = report["province_effects"]
	var lines: PackedStringArray = []
	# Always lead with name / owner / region / sea zone top-line.
	var topline: Dictionary = build_inspector_topline(province)
	var top_bb := str(topline.get("bbcode", ""))
	if not top_bb.is_empty():
		lines.append(top_bb)
		lines.append("")
	var compare_hdr := build_inspector_compare_header(province, selected_province_id)
	if not compare_hdr.is_empty():
		lines.append(compare_hdr)
		lines.append("")
	var infra_inspector := build_province_infrastructure_card_bbcode(province, false)
	var pressure_inspector := ""
	if not pressure_agent_section_redundant_with_card(province):
		pressure_inspector = build_province_pressure_section_bbcode(
			province, infra_inspector.is_empty(),
		)
	if not infra_inspector.is_empty():
		lines.append(infra_inspector)
	# Always surface special sites + chokepoint even when sabotage card is empty.
	var sites_inspector := build_special_sites_effect_bbcode(province, false)
	if not sites_inspector.is_empty() and (infra_inspector.is_empty() or "Special sites" not in infra_inspector):
		if not infra_inspector.is_empty():
			lines.append("")
		lines.append(sites_inspector)
	var choke_inspector := build_naval_chokepoint_badge_bbcode(province)
	if not choke_inspector.is_empty() and (infra_inspector.is_empty() or "Naval chokepoint" not in infra_inspector):
		lines.append(choke_inspector)
	var sea_zone_line := build_sea_zone_badge_bbcode(province)
	if not sea_zone_line.is_empty():
		lines.append(sea_zone_line)
	var basing_line := build_naval_basing_badge_bbcode(province)
	if not basing_line.is_empty():
		lines.append(basing_line)
	if not pressure_inspector.is_empty():
		if not infra_inspector.is_empty() or not sites_inspector.is_empty():
			lines.append("")
		lines.append(pressure_inspector)
	var tag := str(report.get("country_tag", ""))
	var tech_early_added := false
	var build_elig_added := false
	var inspector_tech := append_technology_section_after_pressure(
		lines, province, tag, infra_inspector, pressure_inspector, false,
	)
	if not inspector_tech.is_empty():
		tech_early_added = true
		lines.append("")
		if not append_build_eligibility_section_after_technology(lines, province, tag, false).is_empty():
			build_elig_added = true
	var dual_glance := build_dual_situation_glance_bbcode(province)
	if not dual_glance.is_empty():
		lines.append("%sSituation: %s[/color]" % [COLOR_HEADER, dual_glance])
	else:
		var nat_header := build_national_situation_one_liner(province, pe, tech_early_added)
		if not nat_header.is_empty():
			lines.append(nat_header)
	var glance := build_province_glance_bbcode(province, pe, 5, not dual_glance.is_empty())
	if not glance.is_empty():
		lines.append("%sAt a glance: %s[/color]" % [COLOR_HEADER, glance])
		lines.append("")
	# Damage/sabotage map classification + HH monthly signal when this province is targeted.
	var dmg_cls := classify_province_map_damage(province)
	if bool(dmg_cls.get("is_damaged", false)):
		lines.append(
			"%s%s Map damage: %s[/color]"
			% [COLOR_WARN, str(dmg_cls.get("marker", "⚠")), str(dmg_cls.get("label", "damaged"))]
		)
	var hh_line := build_hh_map_signal_inspector_line()
	if not hh_line.is_empty():
		var sig_pid := -1
		if typeof(GameData) != TYPE_NIL and GameData.has_method("get_peace_state"):
			var ps_hh: Dictionary = GameData.get_peace_state()
			sig_pid = int(ps_hh.get("hh_last_map_signal", {}).get("province_id", -1))
		if sig_pid == province.id or sig_pid < 0:
			lines.append(hh_line)
	# Multi-month HH agenda trail (player-readable history from GameData store).
	var agenda_bb := build_hh_agenda_trail_inspector_bbcode()
	if not agenda_bb.is_empty():
		lines.append(agenda_bb)
	# Agenda panel pilot (expanded multi-entry UI block from same trail store).
	var agenda_panel := build_hh_agenda_panel_inspector_bbcode()
	if not agenda_panel.is_empty() and agenda_panel != agenda_bb:
		lines.append(agenda_panel)
	# Agenda screen layout pilot (sections) — only when trail non-empty.
	var agenda_screen := build_hh_agenda_screen_inspector_bbcode()
	if not agenda_screen.is_empty():
		lines.append(agenda_screen)
	# Agent counterplay options from last HH map signal (pilot).
	var counter_bb := build_agent_counterplay_inspector_bbcode(province)
	if not counter_bb.is_empty():
		lines.append(counter_bb)
	# Agenda action-pick pilot (empty trail → empty string).
	var agenda_actions := build_hh_agenda_actions_inspector_bbcode()
	if not agenda_actions.is_empty():
		lines.append(agenda_actions)
	# Agent mission priority pilot from last HH signal.
	var mission_bb := build_agent_mission_priority_inspector_bbcode(province)
	if not mission_bb.is_empty():
		lines.append(mission_bb)
	# Operator data-dir banner (world_full default clarity).
	var data_banner := build_scenario_data_dir_banner_bbcode()
	if not data_banner.is_empty():
		lines.append(data_banner)
	# Choke + basing synergy chip when naval-relevant.
	var choke_base := build_choke_basing_synergy_bbcode(province)
	if not choke_base.is_empty():
		lines.append(choke_base)
	# Sealane supply/trade chip for provinces in a sea zone.
	var sealane_chip := build_sealane_route_chip_bbcode(province)
	if not sealane_chip.is_empty():
		lines.append(sealane_chip)
	# Convoy escort need chip for coastal / sea-zone provinces.
	var escort_chip := build_convoy_escort_chip_bbcode(province)
	if not escort_chip.is_empty():
		lines.append(escort_chip)
	# Fleet redeploy posture pilot.
	var posture_chip := build_fleet_posture_chip_bbcode(province)
	if not posture_chip.is_empty():
		lines.append(posture_chip)
	# Weather chip + legend (live WeatherManager path).
	var weather_chip := build_weather_chip_bbcode(province)
	if not weather_chip.is_empty():
		lines.append(weather_chip)
	# Season daylight + forecast + extreme + legend surface chips.
	var season_chip := build_season_daylight_chip_bbcode()
	if not season_chip.is_empty():
		lines.append(season_chip)
	var forecast_chip := build_forecast_chip_bbcode(province)
	var extreme_chip := build_extreme_event_chip_bbcode()
	if not extreme_chip.is_empty():
		lines.append(extreme_chip)
	var weather_legend := build_weather_legend_chip_bbcode()
	if not weather_legend.is_empty():
		lines.append(weather_legend)
	var move_chip := build_move_weather_chip_bbcode(province)
	if not move_chip.is_empty():
		lines.append(move_chip)
	var storm_convoy := build_storm_convoy_chip_bbcode(province)
	if not storm_convoy.is_empty():
		lines.append(storm_convoy)
	var sea_wx := build_sea_weather_supply_chip_bbcode(province)
	if not sea_wx.is_empty():
		lines.append(sea_wx)
	# Fleet theater posture (multi-port summary when coastal).
	var theater_posture := build_fleet_theater_posture_chip_bbcode(province)
	if not theater_posture.is_empty():
		lines.append(theater_posture)
	# Weather phase ribbon (combat UI pilot).
	var wx_ribbon := build_weather_phase_ribbon_chip_bbcode(province)
	if not wx_ribbon.is_empty():
		lines.append(wx_ribbon)
	# HH agenda monthly pulse digest (empty trail → empty).
	var pulse_bb := build_hh_agenda_pulse_inspector_bbcode()
	if not pulse_bb.is_empty():
		lines.append(pulse_bb)
	# HH pulse+actions combined digest.
	var pulse_acts := build_hh_pulse_actions_inspector_bbcode()
	if not pulse_acts.is_empty():
		lines.append(pulse_acts)
	# Agent network response pilot from HH signal.
	var net_resp := build_agent_network_response_bbcode(province)
	if not net_resp.is_empty():
		lines.append(net_resp)
	# Agent network deploy plan chip.
	var deploy_plan := build_agent_network_deploy_bbcode(province)
	if not deploy_plan.is_empty():
		lines.append(deploy_plan)
	# Beyond deepen: redeploy route, combat briefing, monthly brief, coverage, weather ops section.
	var redeploy_chip := build_fleet_redeploy_route_chip_bbcode(province)
	if not redeploy_chip.is_empty():
		lines.append(redeploy_chip)
	var wx_brief := build_weather_combat_briefing_chip_bbcode(province)
	if not wx_brief.is_empty():
		lines.append(wx_brief)
	var monthly_brief := build_hh_monthly_brief_inspector_bbcode()
	if not monthly_brief.is_empty():
		lines.append(monthly_brief)
	var coverage_chip := build_agent_coverage_chip_bbcode()
	if not coverage_chip.is_empty():
		lines.append(coverage_chip)
	var wx_ops := build_inspector_weather_ops_section_bbcode(province)
	if not wx_ops.is_empty():
		lines.append(wx_ops)
	var pressure_chip := build_weather_pressure_chip_bbcode(province)
	if not pressure_chip.is_empty():
		lines.append(pressure_chip)
	var naval_tip := build_naval_wx_tip_chip_bbcode(province)
	if not naval_tip.is_empty():
		lines.append(naval_tip)
	var air_alert := build_air_grounding_alert_chip_bbcode(province)
	if not air_alert.is_empty():
		lines.append(air_alert)
	var freeze_chip := build_freeze_thaw_chip_bbcode(province)
	if not freeze_chip.is_empty():
		lines.append(freeze_chip)
	var infra_wx := build_infra_weather_wear_chip_bbcode(province)
	if not infra_wx.is_empty():
		lines.append(infra_wx)
	var fog_chip := build_coastal_fog_gate_chip_bbcode(province)
	if not fog_chip.is_empty():
		lines.append(fog_chip)
	var joint_chip := build_joint_focus_agent_chip_bbcode()
	if not joint_chip.is_empty():
		lines.append(joint_chip)
	var route_wx := build_supply_route_weather_rank_chip_bbcode(province)
	if not route_wx.is_empty():
		lines.append(route_wx)
	# Beyond ops-expand: task group, multi-front, quarterly, escalation, theater polish.
	var task_group := build_fleet_task_group_chip_bbcode(province)
	if not task_group.is_empty():
		lines.append(task_group)
	var multi_front := build_multi_front_assault_chip_bbcode(province)
	if not multi_front.is_empty():
		lines.append(multi_front)
	var quarterly := build_hh_quarterly_rollup_inspector_bbcode()
	if not quarterly.is_empty():
		lines.append(quarterly)
	var escalation := build_agent_escalation_chip_bbcode()
	if not escalation.is_empty():
		lines.append(escalation)
	var day_risk := build_campaign_day_risk_chip_bbcode(province)
	if not day_risk.is_empty():
		lines.append(day_risk)
	var convoy_win := build_convoy_weather_window_chip_bbcode(province)
	if not convoy_win.is_empty():
		lines.append(convoy_win)
	var prod_alert := build_production_weather_alert_chip_bbcode(province)
	if not prod_alert.is_empty():
		lines.append(prod_alert)
	var sea_naval := build_sea_naval_weather_ops_chip_bbcode(province)
	if not sea_naval.is_empty():
		lines.append(sea_naval)
	var morale_wx := build_combat_morale_weather_chip_bbcode(province)
	if not morale_wx.is_empty():
		lines.append(morale_wx)
	var depot_wx := build_depot_weather_capacity_chip_bbcode(province)
	if not depot_wx.is_empty():
		lines.append(depot_wx)
	var daylight := build_daylight_combat_mod_chip_bbcode()
	if not daylight.is_empty():
		lines.append(daylight)
	var choke_wx := build_choke_weather_synergy_chip_bbcode(province)
	if not choke_wx.is_empty():
		lines.append(choke_wx)
	var focus_wx := build_focus_weather_aware_chip_bbcode(province)
	if not focus_wx.is_empty():
		lines.append(focus_wx)
	var ops_dash := build_ops_dashboard_chip_bbcode(province)
	if not ops_dash.is_empty():
		lines.append(ops_dash)
	# Integrated multi-system packages (beyond theater-expand).
	var fleet_wx := build_fleet_weather_package_chip_bbcode(province)
	if not fleet_wx.is_empty():
		lines.append(fleet_wx)
	var assault_ready := build_assault_readiness_chip_bbcode(province)
	if not assault_ready.is_empty():
		lines.append(assault_ready)
	var counter_ops := build_counter_ops_chip_bbcode()
	if not counter_ops.is_empty():
		lines.append(counter_ops)
	var commits := build_hh_agenda_commits_chip_bbcode()
	if not commits.is_empty():
		lines.append(commits)
	var choke_sea := build_choke_sea_weather_chip_bbcode(province)
	if not choke_sea.is_empty():
		lines.append(choke_sea)
	var trade_chain := build_trade_chain_chip_bbcode(province)
	if not trade_chain.is_empty():
		lines.append(trade_chain)
	var factory_risk := build_factory_risk_chip_bbcode(province)
	if not factory_risk.is_empty():
		lines.append(factory_risk)
	var supply_chain := build_supply_chain_health_chip_bbcode(province)
	if not supply_chain.is_empty():
		lines.append(supply_chain)
	var air_pkg := build_air_ops_package_chip_bbcode(province)
	if not air_pkg.is_empty():
		lines.append(air_pkg)
	# Product-depth day chips: priority-budgeted (cognitive load / Top 5 follow-on).
	_append_budgeted_product_depth_chips(lines, province)
	# Always surface resource/damage + sealane contest skims at operational readability.
	var res_dmg := build_resource_damage_skim_chip_bbcode(province)
	if not res_dmg.is_empty():
		lines.append(res_dmg)
	var sealane_contest := build_sealane_contest_skim_chip_bbcode(province)
	if not sealane_contest.is_empty():
		lines.append(sealane_contest)
	var infra_site := build_infra_site_consistency_chip_bbcode(province)
	if not infra_site.is_empty():
		lines.append(infra_site)
	var hh_screen_day := build_hh_agenda_screen_day_chip_bbcode(province)
	if not hh_screen_day.is_empty():
		lines.append(hh_screen_day)
	var fleet_auto_day := build_fleet_autonomy_day_chip_bbcode(province)
	if not fleet_auto_day.is_empty():
		lines.append(fleet_auto_day)
	var sealane_vis := build_sealane_contest_visual_chip_bbcode(province)
	if not sealane_vis.is_empty():
		lines.append(sealane_vis)
	# Next-10 always-on skims (theater brief · campaign decision · multi-phase)
	var mp_day := build_multi_phase_combat_day_chip_bbcode(province)
	if not mp_day.is_empty():
		lines.append(mp_day)
	var th_brief := build_theater_brief_day_chip_bbcode(province)
	if not th_brief.is_empty():
		lines.append(th_brief)
	var camp_dec := build_campaign_decision_day_chip_bbcode(province)
	if not camp_dec.is_empty():
		lines.append(camp_dec)
	var fleet_ai_day := build_fleet_ai_ops_day_chip_bbcode(province)
	if not fleet_ai_day.is_empty():
		lines.append(fleet_ai_day)
	var ind_econ := build_industry_economy_day_chip_bbcode(province)
	if not ind_econ.is_empty():
		lines.append(ind_econ)
	var joint_ops := build_joint_ops_loop_day_chip_bbcode(province)
	if not joint_ops.is_empty():
		lines.append(joint_ops)
	var war_cab := build_war_cabinet_day_chip_bbcode(province)
	if not war_cab.is_empty():
		lines.append(war_cab)
	var oq_day := build_order_queue_day_chip_bbcode(province)
	if not oq_day.is_empty():
		lines.append(oq_day)
	var risk_day := build_campaign_risk_day_chip_bbcode(province)
	if not risk_day.is_empty():
		lines.append(risk_day)
	var sealane_h := build_sealane_health_day_chip_bbcode(province)
	if not sealane_h.is_empty():
		lines.append(sealane_h)
	var th_camp := build_theater_campaign_day_chip_bbcode(province)
	if not th_camp.is_empty():
		lines.append(th_camp)
	var th_ord := build_theater_order_day_chip_bbcode(province)
	if not th_ord.is_empty():
		lines.append(th_ord)
	var fac_risk := build_factory_risk_day_chip_bbcode(province)
	if not fac_risk.is_empty():
		lines.append(fac_risk)
	var best_as := build_best_assault_day_chip_bbcode(province)
	if not best_as.is_empty():
		lines.append(best_as)
	var th_mut := build_theater_mutation_day_chip_bbcode(province)
	if not th_mut.is_empty():
		lines.append(th_mut)
	var air_sortie := build_air_ops_sortie_day_chip_bbcode(province)
	if not air_sortie.is_empty():
		lines.append(air_sortie)
	var exec_one := build_execute_one_day_chip_bbcode(province)
	if not exec_one.is_empty():
		lines.append(exec_one)
	var hh_mon := build_hh_monthly_day_chip_bbcode(province)
	if not hh_mon.is_empty():
		lines.append(hh_mon)

	# Gameplay loops beyond integration-expand.
	var basing_log := build_basing_logistics_chip_bbcode(province)
	if not basing_log.is_empty():
		lines.append(basing_log)
	var follow_on := build_assault_follow_on_chip_bbcode(province)
	if not follow_on.is_empty():
		lines.append(follow_on)
	var exec_order := build_counter_ops_execute_chip_bbcode()
	if not exec_order.is_empty():
		lines.append(exec_order)
	var agenda_pick := build_agenda_execute_pick_chip_bbcode()
	if not agenda_pick.is_empty():
		lines.append(agenda_pick)
	var move_path := build_move_path_ops_chip_bbcode(province)
	if not move_path.is_empty():
		lines.append(move_path)
	var basing_repair := build_basing_repair_weather_chip_bbcode(province)
	if not basing_repair.is_empty():
		lines.append(basing_repair)
	var sealane := build_sealane_joint_health_chip_bbcode(province)
	if not sealane.is_empty():
		lines.append(sealane)
	var reinforced := build_reinforced_assault_chip_bbcode(province)
	if not reinforced.is_empty():
		lines.append(reinforced)
	var war_path := build_war_path_urgency_chip_bbcode()
	if not war_path.is_empty():
		lines.append(war_path)
	var oob_fac := build_oob_factory_risk_chip_bbcode(province)
	if not oob_fac.is_empty():
		lines.append(oob_fac)
	var force_sup := build_force_supply_posture_chip_bbcode(province)
	if not force_sup.is_empty():
		lines.append(force_sup)
	var leader_wx := build_leader_weather_assign_chip_bbcode(province)
	if not leader_wx.is_empty():
		lines.append(leader_wx)
	var joint_loop := build_joint_ops_loop_strip_chip_bbcode(province)
	var fleet_camp := build_fleet_campaign_chip_bbcode(province)
	var combat_camp := build_combat_campaign_chip_bbcode(province)
	var camp_decision := build_campaign_decision_strip_chip_bbcode(province)
	var fleet_order := build_fleet_order_chip_bbcode(province)
	var combat_order := build_combat_order_chip_bbcode(province)
	var exec_strip := build_execution_decision_strip_chip_bbcode(province)
	var station_mut := build_fleet_station_mutation_chip_bbcode(province)
	var mut_strip := build_mutation_decision_strip_chip_bbcode(province)
	var theater_cmd := build_theater_command_strip_chip_bbcode(province)
	var player_orders := build_player_order_surface_chip_bbcode(province)
	var cmd_log := build_command_result_log_chip_bbcode()
	var day_report := build_theater_day_report_chip_bbcode(province)
	var order_panel := build_order_panel_chip_bbcode(province)
	var war_econ_chip := build_war_economy_day_chip_bbcode(province)
	var logistics_chip := build_logistics_day_chip_bbcode(province)
	var day_strip_chip := build_theater_day_command_strip_chip_bbcode(province)
	if not joint_loop.is_empty():
		lines.append(joint_loop)
	if not war_econ_chip.is_empty():
		lines.append(war_econ_chip)
	if not logistics_chip.is_empty():
		lines.append(logistics_chip)
	if not day_strip_chip.is_empty():
		lines.append(day_strip_chip)
	lines.append("%sModifier breakdown[/color]" % COLOR_HEADER)
	lines.append(_modifier_legend_bbcode())
	lines.append("")
	var situation_sec := build_inspector_situation_section(province)
	if not fleet_camp.is_empty():
		lines.append(fleet_camp)
	if not combat_camp.is_empty():
		lines.append(combat_camp)
	if not camp_decision.is_empty():
		lines.append(camp_decision)
	if not fleet_order.is_empty():
		lines.append(fleet_order)
	if not combat_order.is_empty():
		lines.append(combat_order)
	if not exec_strip.is_empty():
		lines.append(exec_strip)
	if not station_mut.is_empty():
		lines.append(station_mut)
	if not mut_strip.is_empty():
		lines.append(mut_strip)
	if not theater_cmd.is_empty():
		lines.append(theater_cmd)
	if not player_orders.is_empty():
		lines.append(player_orders)
	if not cmd_log.is_empty():
		lines.append(cmd_log)
	if not day_report.is_empty():
		lines.append(day_report)
	if not order_panel.is_empty():
		lines.append(order_panel)

	if not situation_sec.is_empty():
		lines.append(situation_sec)
		lines.append("")
	var tech_sec := build_inspector_technology_section(province, str(report.get("country_tag", "")))
	if not tech_sec.is_empty() and not tech_early_added:
		lines.append(tech_sec)
		lines.append("")
	elif tech_early_added:
		lines.append(
			"%sOpen Technology screen for research slots and build unlocks.[/color]" % COLOR_MUTED
		)
		lines.append("")
	if not build_elig_added:
		var build_sec := build_inspector_build_eligibility_section(
			province, str(report.get("country_tag", "")),
		)
		if not build_sec.is_empty():
			lines.append(build_sec)
			lines.append("")
	lines.append("%s── Logistics & supply ──[/color]" % COLOR_HEADER)
	lines.append(_stat_column_legend_bbcode())
	for row in report.get("logistics_rows", []) as Array:
		lines.append(_bbcode_stat_line_layered(row))
	lines.append(_depot_bbcode_line(province.id))
	var routes := build_routes_through_province_bbcode(province.id, str(report.get("country_tag", "")))
	if not routes.is_empty():
		lines.append(routes)
	var trade_inspector := build_trade_flow_map_section_bbcode(province.id, "", 6)
	if not trade_inspector.is_empty():
		lines.append(trade_inspector)
	lines.append("")
	lines.append(build_inspector_national_section(province, pe))
	lines.append("")
	lines.append("%s── Combat ──[/color]" % COLOR_HEADER)
	lines.append(_stat_column_legend_bbcode())
	for row in report.get("combat_rows", []) as Array:
		lines.append(_bbcode_stat_line_layered(row))
	lines.append(
		"%sMovement cost: %.2f[/color]" % [COLOR_MUTED, float(report.get("movement_cost", 1.0))]
	)
	var battle := str(report.get("battle_block", ""))
	if not battle.is_empty():
		lines.append("")
		lines.append(battle)
	var missions := str(report.get("stationed_formations", ""))
	# Always show the section for gameplay visibility (player can see at a glance which formations have orders/missions here, even if none; useful for planning assaults, naval ops etc.)
	lines.append("")
	lines.append("%sFormations & Missions here: %s[/color]" % [COLOR_TECH, missions])
	return "\n".join(lines)


static func get_province_effects_for(province: Province, country_tag: String = "") -> ProvinceEffects:
	if province == null:
		return null
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = country_tag_for_province(province)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_effects"):
		var via_manager: ProvinceEffects = MapManager.get_province_effects(province.id, tag)
		if via_manager != null:
			return via_manager
	# Last resort fallback ONLY. MapManager.get_province_effects is the single source of truth
	# (combines base dev/infra + national spirits + temporary modifiers).
	# This raw call is deprecated.
	return ProvinceEffects.for_country_province(province, tag)


static func build_at_a_glance_logistics(province: Province) -> String:
	var pe := get_province_effects_for(province)
	return (
		"Effective: throughput ×%.2f · local gen +%.0f%% · interdict resist ×%.2f · reinf ×%.2f"
		% [
			pe.get_effective_throughput_multiplier(),
			pe.get_effective_local_supply_generation() * 100.0,
			pe.get_effective_interdiction_resistance(),
			pe.get_effective_reinforcement_speed(),
		]
	)


static func build_at_a_glance_combat(province: Province) -> String:
	var pe := get_province_effects_for(province)
	return (
		"Effective: width ×%.2f · org recovery ×%.2f · attrition ×%.2f"
		% [
			pe.get_effective_combat_width_multiplier(),
			pe.get_effective_organization_recovery(),
			pe.get_effective_attrition_multiplier(),
		]
	)


static func build_combat_summary_for_inspector(
	province: Province,
	selected_province_id: int = -1,
) -> String:
	var lines: PackedStringArray = []
	lines.append(build_at_a_glance_combat(province))
	var other := _resolve_battle_counterpart(province, selected_province_id)
	if other != null:
		var attacker := province
		var defender := other
		if selected_province_id == province.id:
			attacker = other
			defender = province
		elif selected_province_id == other.id:
			attacker = other
			defender = province
		var preview: Dictionary = get_battle_preview(attacker, defender)
		if not preview.is_empty():
			lines.append(
				"vs %s: engagement width %.1f (%s)"
				% [
					other.name,
					float(preview.get("estimated_effective_width", 0.0)),
					str(preview.get("terrain", "plains")).capitalize(),
				]
			)
			var pe_def := get_province_effects_for(defender)
			if pe_def != null:
				lines.append(
					"Defender modifiers: width ×%.2f · org ×%.2f"
					% [
						pe_def.get_effective_combat_width_multiplier(),
						pe_def.get_effective_organization_recovery(),
					]
				)
	elif selected_province_id >= 0 and selected_province_id != province.id:
		lines.append("Tip: select an adjacent province to see an attack/defense preview.")
	return "\n".join(lines)


static func build_national_rollup_bbcode(pe: ProvinceEffects) -> String:
	if pe == null or pe.national_modifiers.is_empty():
		return "%s── National layer ──[/color]\n%s  None affecting this province.[/color]" % [COLOR_HEADER, COLOR_MUTED]
	var lines: PackedStringArray = []
	lines.append("%s── National layer (combined) ──[/color]" % COLOR_HEADER)
	var keys: Array = pe.national_modifiers.keys()
	keys.sort()
	for key in keys:
		var v := float(pe.national_modifiers[key])
		if absf(v) < 0.0001:
			continue
		var label := str(NATIONAL_KEY_LABELS.get(str(key), str(key).replace("_", " ").capitalize()))
		var value_text := _format_national_value(v)
		var sign_color := COLOR_EFFECTIVE if v > 0 else COLOR_WARN
		if str(key) in ["supply_consumption", "attrition"]:
			sign_color = COLOR_EFFECTIVE if v < 0 else COLOR_WARN
		lines.append("  %s• %s: %s%s[/color]" % [COLOR_NATIONAL, label, sign_color, value_text])
	return "\n".join(lines)


static func build_routes_through_province_bbcode(
	province_id: int,
	country_tag: String = "",
	max_listed: int = 0,
) -> String:
	var sm := _supply_manager()
	if sm == null:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	var player := str(sm.player_tag).strip_edges().to_upper() if sm.get("player_tag") else tag
	var lines: PackedStringArray = []
	var count := 0
	for plan_var in sm.get_all_routes():
		if not (plan_var is SupplyRoutePlan):
			continue
		var plan := plan_var as SupplyRoutePlan
		if province_id not in plan.province_path:
			continue
		count += 1
		var role := "waypoint"
		var role_icon := "○"
		if plan.source_province_id == province_id:
			role = "source"
			role_icon = "⊙"
		elif plan.target_province_id == province_id:
			role = "destination"
			role_icon = "⊛"
		lines.append(
			"  %s%s %s: %s → %s · %s · interdict %.0f%% · reinf ×%.2f[/color]"
			% [
				COLOR_MUTED,
				role_icon,
				role,
				_province_short_name(plan.source_province_id),
				_province_short_name(plan.target_province_id),
				plan.routing_mode,
				plan.interdiction_chance * 100.0,
				plan.reinforcement_modifier,
			]
		)
	if count == 0:
		return ""
	var header := "%s── Supply routes (%d) ──[/color]" % [COLOR_HEADER, count]
	lines.insert(0, header)
	if max_listed > 0 and count > max_listed:
		var trimmed: PackedStringArray = [lines[0]]
		for i in range(1, mini(lines.size(), max_listed + 1)):
			trimmed.append(lines[i])
		trimmed.append("%s  … +%d more route(s)[/color]" % [COLOR_MUTED, count - max_listed])
		return "\n".join(trimmed)
	return "\n".join(lines)


## Strip outer [color] wrapper so chips can merge into one token.
static func _bbcode_inner(text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("[color"):
		var end := t.find("]")
		if end >= 0:
			t = t.substr(end + 1)
	if t.ends_with("[/color]"):
		t = t.substr(0, t.length() - 8)
	return t.strip_edges()


static func _tokens_contain_tech_marker(tokens: PackedStringArray) -> bool:
	for tok in tokens:
		if "📡" in tok or "🔬" in tok:
			return true
	return false


static func _append_radio_chip_if_missing(tokens: PackedStringArray, country_tag: String) -> void:
	if _tokens_contain_tech_marker(tokens):
		return
	var chip := MapTechnologyContext.build_support_radio_compact_chip(country_tag)
	if not chip.is_empty():
		tokens.append(chip)


static func _ensure_technology_chip_in_tokens(
	tokens: PackedStringArray,
	country_tag: String,
	province: Province,
	max_tokens: int,
	prefer_compact: bool,
) -> void:
	if country_tag.is_empty():
		return
	if province != null and not province_benefits_country(province, country_tag):
		if typeof(TechnologyManager) == TYPE_NIL:
			return
		if TechnologyManager.get_active_research_count(country_tag) <= 0:
			return
	var merged := MapTechnologyContext.build_technology_hover_chip(country_tag)
	if merged.is_empty():
		return
	if _tokens_contain_tech_marker(tokens):
		return
	if prefer_compact or tokens.size() < max_tokens:
		tokens.append(merged)


static func _reserve_technology_chip_in_shown(
	shown: PackedStringArray,
	ordered: PackedStringArray,
	max_tokens: int,
	country_tag: String,
) -> void:
	if country_tag.is_empty() or not MapTechnologyContext.country_has_map_technology(country_tag):
		return
	for tok in shown:
		if "📡" in tok or "🔬" in tok:
			return
	var chip := MapTechnologyContext.build_technology_hover_chip(country_tag)
	if chip.is_empty():
		return
	for i in range(ordered.size() - 1, -1, -1):
		var tok := ordered[i]
		if "📡" in tok or "🔬" in tok:
			chip = tok
			break
	if shown.size() < max_tokens:
		shown.append(chip)
		return
	var replace_idx := shown.size() - 1
	while replace_idx >= 0 and ("📅" in shown[replace_idx] or "+%d" in shown[replace_idx]):
		replace_idx -= 1
	if replace_idx < 0:
		replace_idx = shown.size() - 1
	shown[replace_idx] = chip


static func append_technology_section_after_pressure(
	lines: PackedStringArray,
	province: Province,
	country_tag: String,
	infra_block: String,
	pressure_block: String,
	compact: bool,
) -> String:
	var tech := MapTechnologyContext.build_province_technology_tooltip_section(
		province, country_tag, compact,
	)
	if tech.is_empty():
		return ""
	if not infra_block.is_empty() or not pressure_block.is_empty():
		lines.append("")
	lines.append(tech)
	return tech


static func append_build_eligibility_section_after_technology(
	lines: PackedStringArray,
	province: Province,
	country_tag: String,
	compact: bool,
) -> String:
	var block := MapTechnologyContext.build_province_build_eligibility_bbcode(
		province, country_tag, compact,
	)
	if block.is_empty():
		return ""
	if not lines.is_empty():
		lines.append("")
	lines.append(block)
	return block


static func build_inspector_build_eligibility_section(
	province: Province,
	country_tag: String = "",
) -> String:
	return MapTechnologyContext.build_province_build_eligibility_inspector_section(
		province, country_tag,
	)


static func build_tooltip_mode_chip_for_state(
	supply_overlay: bool,
	compare_active: bool,
	is_selected_province: bool,
	supply_role: String = "",
	is_compare_candidate: bool = false,
	is_contested: bool = false,
	has_agent_network: bool = false,
	country_tag: String = "",
	max_tokens: int = 4,
	province: Province = null,
) -> String:
	var tokens: PackedStringArray = []
	if compare_active:
		tokens.append("%s⚔ Compare[/color]" % COLOR_WARN)
	elif is_compare_candidate:
		tokens.append("%s○ Compare neighbor[/color]" % COLOR_WARN)
	elif is_selected_province:
		tokens.append("%s◆ Selected[/color]" % COLOR_HEADER)
	var situation_icon := ""
	var pressure_suffix := ""
	if province != null and agent_applies_daily_pressure(province):
		pressure_suffix = "⛟" if agent_pressure_focus_kind(province) == "disrupt" else "⚙"
	if is_contested and has_agent_network:
		situation_icon = "⚑◎" + pressure_suffix
	elif is_contested:
		situation_icon = "⚑"
	elif has_agent_network:
		situation_icon = "◎" + pressure_suffix
	var pressure_chip_added := false
	var pending_pressure := ""
	if province != null:
		pending_pressure = build_pressure_status_chip_row_bbcode(province)
	if supply_overlay and not situation_icon.is_empty():
		var press_hint := ""
		if not pressure_suffix.is_empty():
			press_hint = " · %s" % ("supply" if pressure_suffix == "⛟" else "infra")
		if not pending_pressure.is_empty():
			tokens.append(
				"%s📦 L · %s · %s%s[/color]"
				% [COLOR_EFFECTIVE, situation_icon, _bbcode_inner(pending_pressure), press_hint]
			)
			pressure_chip_added = true
		else:
			tokens.append("%s📦 L · %s%s[/color]" % [COLOR_EFFECTIVE, situation_icon, press_hint])
	elif supply_overlay:
		if is_contested and not pending_pressure.is_empty():
			tokens.append(
				"%s📦 L · ⚑ · %s[/color]" % [COLOR_EFFECTIVE, _bbcode_inner(pending_pressure)]
			)
			pressure_chip_added = true
		elif is_contested:
			tokens.append("%s📦 L · ⚑[/color]" % COLOR_EFFECTIVE)
		elif not pending_pressure.is_empty():
			tokens.append(
				"%s📦 L · %s[/color]" % [COLOR_EFFECTIVE, _bbcode_inner(pending_pressure)]
			)
			pressure_chip_added = true
		else:
			tokens.append("%s📦 Supply (L)[/color]" % COLOR_EFFECTIVE)
	elif not pressure_suffix.is_empty() and province != null:
		tokens.append(
			"%s%s %s pressure[/color]"
			% [COLOR_WARN, pressure_suffix, "Supply" if pressure_suffix == "⛟" else "Infra"]
		)
	elif situation_icon == "⚑◎":
		tokens.append("%s⚑◎ Contested + agent[/color]" % COLOR_WARN)
	elif situation_icon == "⚑":
		tokens.append("%s⚑ Contested[/color]" % COLOR_WARN)
	elif situation_icon == "◎":
		tokens.append("%s◎ Agent[/color]" % COLOR_NATIONAL)
	if province != null and tokens.size() < max_tokens and pending_pressure.is_empty():
		pending_pressure = build_pressure_status_chip_row_bbcode(province)
	if (
		not pressure_chip_added
		and not pending_pressure.is_empty()
		and tokens.size() < max_tokens
	):
		tokens.append(pending_pressure)
		pressure_chip_added = true
	if not supply_role.is_empty() and tokens.size() < max_tokens:
		var skip_role_label := pressure_chip_added and supply_role in [
			"infra_sabotage", "supply_pressure", "infra_repair", "infra_repair_engineers",
			"infra_duel_even", "depot_sabotage", "engineers_stationed", "engineers_needed",
			"engineers_recommended", "engineers_insufficient", "trade_transit",
		]
		if not skip_role_label:
			tokens.append("%s%s[/color]" % [COLOR_MUTED, _supply_role_label(supply_role)])
	elif (
		supply_overlay
		and province != null
		and province_needs_infrastructure_ui(province)
		and not pressure_chip_added
		and tokens.size() < max_tokens
	):
		var bd := _infra_repair_breakdown(province)
		var outcome_chip := build_pressure_outcome_headline_bbcode(province, bd)
		if not outcome_chip.is_empty():
			tokens.append(outcome_chip)
		elif bool(bd.get("under_infra_sabotage", false)):
			tokens.append("%s⚙ Sabotaged[/color]" % COLOR_WARN)
		elif agent_pressure_focus_kind(province) == "disrupt":
			tokens.append("%s⛟ Supply pressure[/color]" % COLOR_WARN)
		elif float(bd.get("depot_sabotage_level", 0.0)) > 0.12:
			tokens.append("%s⛟ Depot hit[/color]" % COLOR_WARN)
		elif int(bd.get("infrastructure", province.infrastructure)) < 50:
			tokens.append("%s⚙ Repairing[/color]" % COLOR_TECH)
	if (
		supply_overlay
		and province != null
		and tokens.size() < max_tokens
	):
		var bd_chip := _infra_repair_breakdown(province)
		if province_shows_engineer_map_chip(province, bd_chip):
			var assign_chip := build_engineer_map_chip_bbcode(province, bd_chip)
			if not assign_chip.is_empty():
				var has_eng_tok := false
				for tok in tokens:
					if "🔧" in tok or "STATION" in tok or " div" in tok:
						has_eng_tok = true
						break
				if not has_eng_tok:
					tokens.append(assign_chip)
	if (
		supply_overlay
		and province != null
		and tokens.size() < max_tokens
	):
		var tr_chip := build_trade_flow_hover_chip_bbcode(province, country_tag)
		if not tr_chip.is_empty():
			var has_tr := false
			for tok in tokens:
				if _is_trade_flow_hover_chip(tok):
					has_tr = true
					break
			if not has_tr:
				tokens.append(tr_chip)
	if supply_overlay and tokens.size() < max_tokens:
		var skip_date := (
			province != null
			and (
				agent_applies_daily_pressure(province)
				or agent_has_today_pressure_tick(province)
			)
		)
		if not skip_date:
			var date_compact := GameDateDisplay.format_map_date_compact()
			if not date_compact.is_empty():
				tokens.append("%s📅 %s[/color]" % [COLOR_MUTED, date_compact])
	if (
		not supply_overlay
		and province != null
		and agent_has_today_pressure_tick(province)
		and tokens.size() < max_tokens
	):
		tokens.append("%s◎ TODAY[/color]" % COLOR_WARN)
	var pressure_ui := province != null and province_needs_infrastructure_ui(province)
	var multi_busy := pressure_ui or is_contested or has_agent_network
	var defer_tech := multi_busy and not supply_overlay
	var allow_bonus_slot := max_tokens >= 6 and supply_overlay and province != null
	if province != null and tokens.size() < max_tokens:
		var reloc_chip := MapTechnologyContext.build_relocate_prominence_chip(
			province, country_tag,
		)
		if not reloc_chip.is_empty():
			tokens.append(reloc_chip)
		elif tokens.size() < max_tokens:
			var choice_chip := MapTechnologyContext.build_invest_reloc_choice_chip(
				province, country_tag,
			)
			if not choice_chip.is_empty():
				tokens.append(choice_chip)
			elif tokens.size() < max_tokens:
				var split_chip := MapTechnologyContext.build_retool_reloc_split_chip(
					province, country_tag,
				)
				if not split_chip.is_empty():
					tokens.append(split_chip)
	if province != null and tokens.size() < max_tokens:
		var elig_chip := MapTechnologyContext.build_build_eligibility_hover_chip(
			province, country_tag,
		)
		if not elig_chip.is_empty():
			tokens.append(elig_chip)
		if tokens.size() < max_tokens and province.development_level < 5:
			var dev_chip := MapTechnologyContext.build_development_tier_chip(
				province, country_tag,
			)
			if not dev_chip.is_empty():
				var has_dev_tok := false
				for tok in tokens:
					if "📈" in tok or "dev " in tok.to_lower():
						has_dev_tok = true
						break
				if not has_dev_tok:
					tokens.append(dev_chip)
		if tokens.size() < max_tokens:
			var profile_chip := MapTechnologyContext.build_province_production_profile_chip(province)
			if not profile_chip.is_empty():
				var has_profile := false
				for tok in tokens:
					if "✓" in tok or "✗" in tok or "Good:" in tok or "Good for:" in tok:
						has_profile = true
						break
				if not has_profile:
					tokens.append(profile_chip)
	if not country_tag.is_empty() and tokens.size() < max_tokens and not defer_tech:
		var tech_chip := MapTechnologyContext.build_technology_status_chip(country_tag)
		if not tech_chip.is_empty():
			tokens.append(tech_chip)
	if (
		province != null
		and not country_tag.is_empty()
		and province_benefits_country(province, country_tag)
		and MapTechnologyContext.has_support_radio_bonuses(country_tag)
		and tokens.size() < max_tokens
		and not defer_tech
	):
		_append_radio_chip_if_missing(tokens, country_tag)
	if (
		allow_bonus_slot
		and province_benefits_country(province, country_tag)
		and tokens.size() < max_tokens
	):
		_ensure_technology_chip_in_tokens(
			tokens, country_tag, province, max_tokens, true,
		)
	elif multi_busy and tokens.size() < max_tokens and not country_tag.is_empty():
		_ensure_technology_chip_in_tokens(
			tokens, country_tag, province, max_tokens, supply_overlay,
		)
	if tokens.is_empty():
		return ""
	if tokens.size() <= max_tokens:
		return "  ·  ".join(tokens)
	var priority: Array[String] = []
	var rest: Array[String] = []
	for tok in tokens:
		if (
			"SABOTAGE" in tok
			or "SAB WIN" in tok
			or "REP WIN" in tok
			or "REPAIR" in tok
			or "RECOVERING" in tok
			or "WINNING" in tok
			or "SUPPLY" in tok
			or "DEPOT" in tok
			or "📦 L" in tok
			or "✓" in tok
			or "✗" in tok
			or "⚑" in tok
			or "◎" in tok
			or "Compare" in tok
			or "Selected" in tok
			or "📡" in tok
			or "🔬" in tok
			or "🔧" in tok
			or "URGENT" in tok
			or "weak" in tok
			or "STATION" in tok
			or "div" in tok
			or "🔒" in tok
			or "locked" in tok
			or "📉" in tok
			or "🏔" in tok
			or "🏭" in tok
			or "tier" in tok.to_lower()
			or "lock[/color]" in tok
			or "↗" in tok
			or "Good:" in tok
			or "Good for:" in tok
			or "Weak:" in tok
			or "Weak for:" in tok
			or "Grow dev" in tok
			or "↻" in tok
			or "INVEST" in tok
			or "RELOCATE" in tok
			or "Recommended" in tok
			or "Split strategy" in tok
			or "★" in tok
			or "○" in tok
			or "unlock" in tok.to_lower()
			or _is_trade_flow_hover_chip(tok)
		):
			priority.append(tok)
		else:
			rest.append(tok)
	var ordered: PackedStringArray = []
	for tok in priority:
		ordered.append(tok)
	for tok in rest:
		ordered.append(tok)
	var shown: PackedStringArray = []
	for i in range(mini(ordered.size(), max_tokens)):
		shown.append(ordered[i])
	if ordered.size() > max_tokens:
		shown.append("%s+%d[/color]" % [COLOR_MUTED, ordered.size() - max_tokens])
	_reserve_technology_chip_in_shown(shown, ordered, max_tokens, country_tag)
	_reserve_relocate_chip_in_shown(shown, ordered, max_tokens, province, country_tag)
	_reserve_invest_reloc_choice_chip_in_shown(shown, ordered, max_tokens, province, country_tag)
	_reserve_retool_split_chip_in_shown(shown, ordered, max_tokens, province, country_tag)
	_reserve_build_eligibility_chip_in_shown(shown, ordered, max_tokens, province, country_tag)
	_reserve_development_tier_chip_in_shown(shown, ordered, max_tokens, province, country_tag)
	_reserve_production_profile_chip_in_shown(shown, ordered, max_tokens, province)
	_reserve_trade_flow_chip_in_shown(shown, ordered, max_tokens, province, country_tag)
	_reserve_engineer_assignment_chip_in_shown(shown, ordered, max_tokens, province)
	return "  ·  ".join(shown)


static func _reserve_relocate_chip_in_shown(
	shown: PackedStringArray,
	ordered: PackedStringArray,
	max_tokens: int,
	province: Province,
	country_tag: String,
) -> void:
	if province == null:
		return
	var chip := MapTechnologyContext.build_relocate_prominence_chip(province, country_tag)
	if chip.is_empty():
		return
	for tok in shown:
		if "↗" in tok:
			return
	for i in range(ordered.size() - 1, -1, -1):
		if "↗" in ordered[i]:
			chip = ordered[i]
			break
	if shown.size() < max_tokens:
		shown.append(chip)
	elif shown.size() > 0:
		var replace_idx := shown.size() - 1
		while replace_idx >= 0 and (
			"📅" in shown[replace_idx]
			or "+%d" in shown[replace_idx]
			or "Compare" in shown[replace_idx]
			or "Selected" in shown[replace_idx]
			or "🔧" in shown[replace_idx]
			or ("📡" in shown[replace_idx] and "↗" in chip)
			or ("🔬" in shown[replace_idx] and "↗" in chip)
		):
			replace_idx -= 1
		if replace_idx < 0:
			replace_idx = 0
		shown[replace_idx] = chip


static func _reserve_invest_reloc_choice_chip_in_shown(
	shown: PackedStringArray,
	ordered: PackedStringArray,
	max_tokens: int,
	province: Province,
	country_tag: String,
) -> void:
	if province == null:
		return
	var chip := MapTechnologyContext.build_invest_reloc_choice_chip(province, country_tag)
	if chip.is_empty():
		return
	for tok in shown:
		if "★" in tok and ("Invest" in tok or "RELOCATE" in tok or "Split" in tok or "↗" in tok):
			return
	for i in range(ordered.size() - 1, -1, -1):
		if "★" in ordered[i] and "Recommended" in ordered[i]:
			chip = ordered[i]
			break
	if shown.size() < max_tokens:
		shown.append(chip)
	elif shown.size() > 0 and "↗" not in str(shown[0]):
		shown[0] = chip


static func _reserve_retool_split_chip_in_shown(
	shown: PackedStringArray,
	ordered: PackedStringArray,
	max_tokens: int,
	province: Province,
	country_tag: String,
) -> void:
	if province == null:
		return
	var chip := MapTechnologyContext.build_retool_reloc_split_chip(province, country_tag)
	if chip.is_empty():
		return
	for tok in shown:
		if "↻" in tok and "↗" in tok:
			return
	if shown.size() < max_tokens:
		shown.append(chip)
	elif shown.size() > 0 and "↗" not in str(shown[shown.size() - 1]):
		shown[shown.size() - 1] = chip


static func _reserve_production_profile_chip_in_shown(
	shown: PackedStringArray,
	ordered: PackedStringArray,
	max_tokens: int,
	province: Province,
) -> void:
	if province == null:
		return
	var chip := MapTechnologyContext.build_province_production_profile_chip(province)
	if chip.is_empty():
		return
	for tok in shown:
		if "✓" in tok or "✗" in tok or "Good:" in tok or "Good for:" in tok:
			return
	for i in range(ordered.size() - 1, -1, -1):
		if "✓" in ordered[i] or "✗" in ordered[i]:
			chip = ordered[i]
			break
	if shown.size() < max_tokens:
		shown.append(chip)
	elif shown.size() > 0:
		var replace_idx := shown.size() - 1
		while replace_idx >= 0 and (
			"📅" in shown[replace_idx]
			or "+%d" in shown[replace_idx]
			or "Compare" in shown[replace_idx]
			or "Selected" in shown[replace_idx]
			or ("📡" in shown[replace_idx] and "↗" not in chip)
		):
			replace_idx -= 1
		if replace_idx >= 0:
			shown[replace_idx] = chip


static func _reserve_development_tier_chip_in_shown(
	shown: PackedStringArray,
	ordered: PackedStringArray,
	max_tokens: int,
	province: Province,
	country_tag: String,
) -> void:
	if province == null or province.development_level >= 5:
		return
	var chip := MapTechnologyContext.build_development_tier_chip(province, country_tag)
	if chip.is_empty():
		return
	for tok in shown:
		if "📈" in tok:
			return
	if shown.size() < max_tokens:
		shown.append(chip)
	elif shown.size() > 0:
		var replace_idx := shown.size() - 1
		while replace_idx >= 0 and ("📅" in shown[replace_idx] or "+%d" in shown[replace_idx]):
			replace_idx -= 1
		if replace_idx >= 0:
			shown[replace_idx] = chip


static func _reserve_build_eligibility_chip_in_shown(
	shown: PackedStringArray,
	ordered: PackedStringArray,
	max_tokens: int,
	province: Province,
	country_tag: String,
) -> void:
	if province == null:
		return
	var snap := MapTechnologyContext.collect_province_build_eligibility(province, country_tag)
	var has_locked := not (snap.get("locked_lines", []) as Array).is_empty()
	var chip := MapTechnologyContext.build_build_eligibility_hover_chip(province, country_tag)
	if chip.is_empty():
		return
	var is_warn := (
		"lock" in chip.to_lower()
		or "📉" in chip
		or "🏔" in chip
		or "🔒" in chip
	)
	if not is_warn and "OK" in chip and not has_locked:
		return
	for tok in shown:
		if (
			"🔒" in tok
			or "lock[/color]" in tok
			or "📉" in tok
			or "🏔" in tok
			or "↗" in tok
			or "Good:" in tok
		):
			return
	for i in range(ordered.size() - 1, -1, -1):
		var tok := ordered[i]
		if (
			"🔒" in tok
			or "📉" in tok
			or "🏔" in tok
			or "lock[/color]" in tok
			or "↗" in tok
			or "Good:" in tok
		):
			chip = tok
			break
	if shown.size() < max_tokens:
		shown.append(chip)
	elif shown.size() > 0:
		var replace_idx := shown.size() - 1
		while replace_idx >= 0 and (
			"📅" in shown[replace_idx]
			or "+%d" in shown[replace_idx]
			or "Compare" in shown[replace_idx]
			or "Selected" in shown[replace_idx]
			or ("📡" in shown[replace_idx] and is_warn)
			or ("🔬" in shown[replace_idx] and is_warn)
		):
			replace_idx -= 1
		if replace_idx < 0:
			replace_idx = shown.size() - 1
		shown[replace_idx] = chip


static func _reserve_engineer_assignment_chip_in_shown(
	shown: PackedStringArray,
	ordered: PackedStringArray,
	max_tokens: int,
	province: Province,
) -> void:
	if province == null:
		return
	var bd := _infra_repair_breakdown(province)
	if not province_shows_engineer_map_chip(province, bd):
		return
	for tok in shown:
		if "🔧" in tok:
			return
	var chip := build_engineer_map_chip_bbcode(province, bd)
	if chip.is_empty():
		return
	for i in range(ordered.size() - 1, -1, -1):
		var tok := ordered[i]
		if "🔧" in tok:
			chip = tok
			break
	if shown.size() < max_tokens:
		shown.append(chip)
	elif shown.size() > 0:
		var replace_idx := shown.size() - 1
		while replace_idx >= 0 and (
			"📅" in shown[replace_idx]
			or "+%d" in shown[replace_idx]
			or "Compare" in shown[replace_idx]
			or ("📡" in shown[replace_idx] and "🔧" not in shown[replace_idx])
		):
			replace_idx -= 1
		if replace_idx < 0:
			replace_idx = shown.size() - 1
		shown[replace_idx] = chip


static func _reserve_trade_flow_chip_in_shown(
	shown: PackedStringArray,
	ordered: PackedStringArray,
	max_tokens: int,
	province: Province,
	country_tag: String,
) -> void:
	if province == null or typeof(TradeManager) == TYPE_NIL:
		return
	var chip := build_trade_flow_hover_chip_bbcode(province, country_tag)
	if chip.is_empty():
		return
	var listed := false
	for tok in ordered:
		if _is_trade_flow_hover_chip(tok):
			listed = true
			break
	if not listed:
		return
	for tok in shown:
		if _is_trade_flow_hover_chip(tok):
			return
	for i in range(ordered.size() - 1, -1, -1):
		if _is_trade_flow_hover_chip(ordered[i]):
			chip = ordered[i]
			break
	if shown.size() < max_tokens:
		shown.append(chip)
	elif shown.size() > 0:
		var replace_idx := shown.size() - 1
		while replace_idx >= 0 and (
			"📅" in shown[replace_idx]
			or "+%d" in shown[replace_idx]
			or "Compare" in shown[replace_idx]
			or ("📡" in shown[replace_idx] and "trade" not in shown[replace_idx])
		):
			replace_idx -= 1
		if replace_idx < 0:
			replace_idx = shown.size() - 1
		shown[replace_idx] = chip


static func _supply_role_label(role: String) -> String:
	match role:
		"active":
			return "◆ supply selected"
		"preview":
			return "~ reroute preview"
		"route":
			return "— supply route"
		"hub":
			return "◇ depot hub"
		"infra_sabotage":
			return "⚙ ring: sabotage winning"
		"supply_pressure":
			return "⛟ ring: supply pressure"
		"trade_transit":
			return "◇ soft ring: trade corridor"
		"infra_repair":
			return "⚙ ring: repair winning"
		"infra_repair_engineers":
			return "⚙ repair winning · 🔧 engineers"
		"infra_duel_even":
			return "⚙ ring: duel even"
		"depot_sabotage":
			return "⛟ ring: depot hit"
		"engineers_stationed":
			return "🔧 engineers on station"
		"engineers_needed":
			return "🔧 engineers URGENT (sabotage winning)"
		"engineers_recommended":
			return "🔧 engineers recommended"
		"engineers_insufficient":
			return "🔧 engineers weak (add more)"
		_:
			return role


static func build_supply_role_hint_bbcode(province_id: int, role: String) -> String:
	if role.is_empty():
		return ""
	return "%sMap role: %s %s[/color]" % [COLOR_MUTED, _supply_role_icon(role), _supply_role_label(role)]


static func _supply_role_icon(role: String) -> String:
	match role:
		"active":
			return "◆"
		"preview":
			return "~"
		"route":
			return "—"
		"hub":
			return "◇"
		"infra_sabotage":
			return "⚙"
		"supply_pressure":
			return "⛟"
		"trade_transit":
			return "◇"
		"infra_repair":
			return "⚙"
		"infra_repair_engineers":
			return "⚙🔧"
		"infra_duel_even":
			return "⚙"
		"depot_sabotage":
			return "⛟"
		"engineers_stationed":
			return "🔧"
		"engineers_needed":
			return "🔧!"
		"engineers_recommended":
			return "🔧◎"
		"engineers_insufficient":
			return "🔧+"
		_:
			return "·"


static func build_inspector_conflict_section(province: Province) -> String:
	if not is_province_contested(province):
		return ""
	var lines: PackedStringArray = []
	lines.append("%s── Conflict / control ──[/color]" % COLOR_HEADER)
	# Regional strategic control indicator (full region ownership gives powerful bonuses)
	var rid: int = 0
	if MapManager.has_method("get_province_region_id"):
		rid = MapManager.get_province_region_id(province.id)
	if rid > 0:
		var rname: String = MapManager.get_strategic_region_name(rid)
		var fully: bool = MapManager.is_strategic_region_fully_controlled(rid, province.owner_tag)
		var ctrl_line: String = "Region: %s" % rname
		if fully:
			ctrl_line += "  [b][color=#4ade80]FULLY CONTROLLED[/color][/b] (+regional bonuses active)"
			# Population pride callout
			var bonuses := MapManager.get_active_regional_control_bonuses(province.owner_tag)
			if float(bonuses.get("regional_pride", 0.0)) > 0.0:
				ctrl_line += "  [i]Local population proud & united[/i]"
			# Show a couple more active flavorful bonuses for the full region(s)
			var extra := []
			if float(bonuses.get("factory_output", 0.0)) > 0.0: extra.append("factory +%.0f%%" % (float(bonuses["factory_output"])*100))
			if float(bonuses.get("manpower_recovery", 0.0)) > 0.0: extra.append("manpower +%.0f%%" % (float(bonuses["manpower_recovery"])*100))
			if extra.size() > 0:
				ctrl_line += "  [" + ", ".join(extra) + "]"
		lines.append(ctrl_line)

	# NEW inspector fields for pop/manpower (phase1): nat pop -> labor (prod bonus) + recruits/pool; feeds width/reinf/strain. Local factories benefit from it. See F10 recruit/pop buttons + TopInfoBar/Policy.
	if province.owner_tag and typeof(GameData) != TYPE_NIL:
		var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
		var nat_pop: float = float(ps.get("population", {}).get(province.owner_tag, 0.0))
		var rec: int = GameData.get_available_recruits(province.owner_tag) if GameData.has_method("get_available_recruits") else 0
		var wbonus: float = GameData.get_national_manpower_width_bonus(province.owner_tag) if GameData.has_method("get_national_manpower_width_bonus") else 0.0
		var labor: float = 1.0
		if nat_pop > 0.0:
			labor = clampf(1.0 + (nat_pop / 100000000.0) * 0.2, 1.0, 1.5)
		lines.append("👥 Pop/Manpower (econ/war): nat=%.1fM rec=%d labor×%.2f width+%.0f%% (drives prod+recruit+width+reinf; recruit strains coh)" % [nat_pop / 1000000.0, rec, labor, wbonus * 100.0])
		if typeof(FactoryManager) != TYPE_NIL and FactoryManager.get_factories_in_province(province.id).size() > 0:
			lines.append("  (local factories here use pop labor bonus for output; click for lines + advance time to produce)")

	# Terrain from layers inference (real DEM/veg data for accurate highlands etc.)
	if MapManager.has_method("get_province_terrain"):
		var terr := MapManager.get_province_terrain(province.id)
		if terr.has("terrain") and terr.get("source", "") == "real_layers_inference":
			var tline := "Terrain (inferred from elev/veg layers): %s (move x%.2f)" % [str(terr.get("terrain", "plains")).capitalize(), float(terr.get("movement_cost", 1.0))]
			if terr.get("snow_potential", 0.0) > 0.1:
				tline += " snow_potential %.2f (white bits in winter)" % float(terr.get("snow_potential", 0.0))
			lines.append(tline)
	# Demo applied sample river subdiv children (live mutate test from sample, with carried terrain/river_aware from layers inference)
	if MapManager.has_method("get_demo_subdiv_children"):
		var demos: Array = MapManager.get_demo_subdiv_children(province.id)
		if demos and demos.size() > 0:
			var dline := "Demo river-cross subdiv (sample apply): "
			var parts: Array = []
			for d in demos.slice(0, min(5, demos.size())):
				var t := str(d.get("terrain", "?")).capitalize()
				var r := " (river)" if d.get("river_aware") else ""
				parts.append("%s%s" % [t, r])
			dline += ", ".join(parts)
			if demos.size() > 5:
				dline += " ..."
			lines.append(dline)
	# Naval orders visibility for sea provinces (player can see fleets + current orders like CONVOY_DUTY, S&D, MINELAY, ASW in sea zones)
	if province.is_sea and typeof(LeaderManager) != TYPE_NIL:
		var naval_info: Array = []
		for tag in ["USA", "GER", "SOV", "ENG", "FRA"]:  # demo tags with test fleets
			for f in LeaderManager.get_formations_for_country(tag):
				if f and f.get_category() == "naval" and f.stationed_province_id == province.id:
					naval_info.append("%s:%s" % [tag, f.current_naval_order])
		if naval_info.size() > 0:
			lines.append("Naval in sea (orders): " + ", ".join(naval_info))
	# River natural border note (layers/demo) - shows defense/supply bonus in effects/combat
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_river_border") and MapManager.has_river_border(province.id):
		lines.append("River natural border (demo/layers): +supply/defense (see effects, BM assaults)")
	lines.append(build_conflict_status_bbcode(province))
	lines.append(
		"%sMap: diagonal stripes mark owner ≠ controller provinces.[/color]" % COLOR_MUTED
	)
	return "\n".join(lines)


static func build_overlay_layers_summary_bbcode(
	supply_overlay_active: bool = false,
	contested_count: int = -1,
	agent_network_count: int = -1,
	player_tag: String = "",
) -> String:
	var n_contested := contested_count if contested_count >= 0 else count_contested_provinces()
	var n_agent := agent_network_count if agent_network_count >= 0 else count_agent_networks({}, player_tag)
	var layers: PackedStringArray = []
	if n_contested > 0:
		layers.append("%s▨ %d contested[/color]" % [COLOR_WARN, n_contested])
	if n_agent > 0:
		layers.append("%s◎ %d agent[/color]" % [COLOR_NATIONAL, n_agent])
	if supply_overlay_active:
		layers.append("%s● supply fill[/color]" % COLOR_EFFECTIVE)
	var tech_preview: Dictionary = MapTechnologyContext.get_build_mode_preview(player_tag)
	if bool(tech_preview.get("active", false)):
		layers.append("%s🔬 build (planned)[/color]" % COLOR_TECH)
	if layers.is_empty():
		return ""
	var stack := " → ".join(layers)
	if n_contested > 0 and n_agent > 0 and supply_overlay_active:
		stack += "  %s(all three on)[/color]" % COLOR_MUTED
	var footer := "[color=#8899aa]· pulsing outlines on top[/color]"
	var tech_line := str(tech_preview.get("legend_line", ""))
	if not tech_line.is_empty():
		footer = tech_line + "  " + footer
	return "[color=#8899aa]Layers:[/color] " + stack + "  " + footer


static func province_benefits_country(province: Province, country_tag: String) -> bool:
	return _province_matches_country(province, country_tag)


static func build_layers_symbol_key_bbcode(
	supply_overlay_active: bool = false,
	contested_count: int = -1,
	agent_network_count: int = -1,
	dual_situation_count: int = -1,
	country_tag: String = "",
) -> String:
	var n_contested := contested_count if contested_count >= 0 else count_contested_provinces()
	var n_agent := agent_network_count if agent_network_count >= 0 else count_agent_networks({})
	var n_dual := dual_situation_count if dual_situation_count >= 0 else count_dual_situation_provinces()
	if n_contested <= 0 and n_agent <= 0 and not supply_overlay_active:
		return ""
	var key := "[color=#8899aa]▨ contested · ◎ agent · ⛟/⚙ pressure (tint · bars · tooltip)"
	if supply_overlay_active:
		key += " · ● L fill · rings: red/amber/orange/teal"
		if not country_tag.is_empty() and MapTechnologyContext.has_support_radio_bonuses(country_tag):
			key += " · 📡 cyan tint on your provinces"
	if n_dual > 0:
		key += " · ⚑◎ both"
	var pressure := build_agent_pressure_legend_fragment(country_tag)
	if not pressure.is_empty():
		key += " · " + pressure
	if not country_tag.is_empty() and MapTechnologyContext.has_support_radio_bonuses(country_tag):
		key += " · 📡 Support/Radio"
	return key + "[/color]"


static func build_compact_layers_summary_bbcode(
	supply_overlay_active: bool = false,
	contested_count: int = -1,
	agent_network_count: int = -1,
	dual_situation_count: int = -1,
	country_tag: String = "",
	include_symbol_key: bool = true,
) -> String:
	var n_contested := contested_count if contested_count >= 0 else count_contested_provinces()
	var n_agent := agent_network_count if agent_network_count >= 0 else count_agent_networks({})
	var n_dual := dual_situation_count if dual_situation_count >= 0 else count_dual_situation_provinces()
	var parts: PackedStringArray = []
	if n_contested > 0:
		parts.append("%s▨%d[/color]" % [COLOR_WARN, n_contested])
	if n_agent > 0:
		parts.append("%s◎%d[/color]" % [COLOR_NATIONAL, n_agent])
		var pressure_counts := build_agent_pressure_legend_fragment(country_tag)
		if not pressure_counts.is_empty():
			parts.append(pressure_counts)
	if supply_overlay_active:
		parts.append("%s●L[/color]" % COLOR_EFFECTIVE)
	if not country_tag.is_empty() and MapTechnologyContext.has_support_radio_bonuses(country_tag):
		parts.append("%s📡[/color]" % COLOR_TECH)
	if parts.is_empty():
		return ""
	var line := "  ·  ".join(parts)
	if n_dual > 0:
		line += "  %s⚑◎×%d[/color]" % [COLOR_WARN, n_dual]
	line += "  %s↑ outlines[/color]" % COLOR_MUTED
	var out := "%sLayers:[/color] %s" % [COLOR_MUTED, line]
	if include_symbol_key:
		var key := build_layers_symbol_key_bbcode(
			supply_overlay_active, n_contested, n_agent, n_dual, country_tag,
		)
		if not key.is_empty():
			out += "\n" + key
	return out


static func build_compact_layers_counts_line(
	supply_overlay_active: bool = false,
	contested_count: int = -1,
	agent_network_count: int = -1,
	dual_situation_count: int = -1,
	country_tag: String = "",
) -> String:
	var full := build_compact_layers_summary_bbcode(
		supply_overlay_active, contested_count, agent_network_count, dual_situation_count, country_tag, false,
	)
	if full.is_empty():
		return ""
	var prefix := "%sLayers:[/color] " % COLOR_MUTED
	if full.begins_with(prefix):
		return full.substr(prefix.length(), full.length())
	return full


static func build_supply_multi_overlay_block_bbcode(
	contested_count: int,
	agent_network_count: int,
	dual_situation_count: int,
	player_tag: String,
) -> String:
	var counts := build_compact_layers_counts_line(
		true, contested_count, agent_network_count, dual_situation_count, player_tag,
	)
	if counts.is_empty():
		return "%s📦 Supply overlay (L)[/color]" % COLOR_EFFECTIVE
	var header := "%s📦 L[/color] · %s" % [COLOR_EFFECTIVE, counts]
	if (
		not player_tag.is_empty()
		and MapTechnologyContext.has_support_radio_bonuses(player_tag)
		and (contested_count > 0 or agent_network_count > 0)
	):
		header += "\n%s📡 Support/Radio — planning/recon on your routes (hover owned provinces).[/color]" % COLOR_TECH
	var pressure_frag := build_agent_pressure_legend_fragment(player_tag)
	if not pressure_frag.is_empty() and agent_network_count > 0:
		header += "\n%sDaily pressure: %s[/color]" % [COLOR_MUTED, pressure_frag]
	return header


static func build_map_supply_mode_hint_plain(
	contested_count: int = -1,
	agent_network_count: int = -1,
	dual_count: int = -1,
	selected_province_id: int = -1,
	country_tag: String = "",
) -> String:
	var n_c := contested_count if contested_count >= 0 else count_contested_provinces()
	var n_a := agent_network_count if agent_network_count >= 0 else count_agent_networks({})
	var n_d := dual_count if dual_count >= 0 else count_dual_situation_provinces()
	var bits: PackedStringArray = ["📦 Supply overlay (L)"]
	if n_c > 0:
		bits.append("⚑ %d contested" % n_c)
	if n_a > 0:
		bits.append("◎ %d agent" % n_a)
	if n_d > 0:
		bits.append("⚑◎ %d both" % n_d)
	if selected_province_id >= 0:
		bits.append("⚔ compare via ○ neighbors")
	if not country_tag.is_empty() and MapTechnologyContext.has_support_radio_bonuses(country_tag):
		bits.append("📡 Support/Radio on routes")
	bits.append("🔧 engineers on L rings")
	bits.append("🏭 build locks on factory provinces (📉 dev · 🏔 terrain · 🔒 tech)")
	var date_compact := GameDateDisplay.format_map_date_compact()
	if not date_compact.is_empty():
		bits.append("📅 %s" % date_compact)
	return " · ".join(bits)


static func build_inspector_technology_section(province: Province, country_tag: String = "") -> String:
	return MapTechnologyContext.build_province_technology_inspector_section(province, country_tag)


static func build_province_situation_tags(province: Province) -> String:
	if province == null:
		return ""
	var tags: PackedStringArray = []
	if is_province_contested(province) and has_active_agent_network(province):
		var dual_badge := ""
		if agent_applies_daily_pressure(province):
			dual_badge = "⛟" if agent_pressure_focus_kind(province) == "disrupt" else "⚙"
			if agent_has_today_pressure_tick(province):
				dual_badge += "·"
		tags.append("%s⚑◎%s[/color]" % [COLOR_WARN, dual_badge])
	elif is_province_contested(province):
		tags.append("%s⚑[/color]" % COLOR_WARN)
	elif has_active_agent_network(province):
		if agent_applies_daily_pressure(province):
			var badge := "⛟" if agent_pressure_focus_kind(province) == "disrupt" else "⚙"
			if agent_has_today_pressure_tick(province):
				badge += "·"
			tags.append("%s◎%s[/color]" % [COLOR_WARN, badge])
		else:
			tags.append("%s◎[/color]" % COLOR_NATIONAL)
	elif province.infrastructure < 50 and province_needs_infrastructure_ui(province):
		var bd := _infra_repair_breakdown(province)
		if not bool(bd.get("under_infra_sabotage", false)):
			tags.append("%s⚙ recovering[/color]" % COLOR_TECH)
	var tag := country_tag_for_province(province)
	if not tag.is_empty() and _province_matches_country(province, tag):
		var researching := (
			typeof(TechnologyManager) != TYPE_NIL
			and TechnologyManager.get_active_research_count(tag) > 0
		)
		var radio := MapTechnologyContext.has_support_radio_bonuses(tag)
		if researching and radio:
			tags.append("%s🔬📡[/color]" % COLOR_TECH)
		elif researching:
			tags.append("%s🔬[/color]" % COLOR_TECH)
		elif radio:
			var chip := MapTechnologyContext.build_support_radio_compact_chip(tag)
			tags.append(chip if not chip.is_empty() else "%s📡[/color]" % COLOR_TECH)
		var bd_tag := _infra_repair_breakdown(province)
		if has_engineers_stationed(bd_tag):
			var eng_n := float(bd_tag.get("engineer_brigades", 0.0))
			tags.append("%s🔧%.1f[/color]" % [COLOR_TECH, eng_n])
		elif province_shows_engineer_assignment_chip(province, bd_tag):
			var lvl := get_engineer_guidance_level(province, bd_tag)
			if lvl == "critical":
				tags.append("%s🔧![/color]" % COLOR_WARN)
			elif lvl == "present_insufficient":
				tags.append("%s🔧weak[/color]" % COLOR_WARN)
			elif lvl == "recommended":
				tags.append("%s🔧assign[/color]" % COLOR_TECH)
	return "".join(tags)


static func _province_matches_country(province: Province, country_tag: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	var owner := province.owner_tag.strip_edges().to_upper()
	var ctrl := province.controller_tag.strip_edges().to_upper()
	if ctrl.is_empty():
		ctrl = owner
	return owner == tag or ctrl == tag


static func build_compare_situation_note(attacker: Province, defender: Province) -> String:
	var parts: PackedStringArray = []
	var a_tags := build_province_situation_tags(attacker)
	var d_tags := build_province_situation_tags(defender)
	if not a_tags.is_empty():
		parts.append("%sAttacker %s: %s[/color]" % [COLOR_MUTED, attacker.name, a_tags])
	if not d_tags.is_empty():
		parts.append("%sDefender %s: %s[/color]" % [COLOR_MUTED, defender.name, d_tags])
	var prod_note := _compare_production_tech_note(attacker, defender)
	if not prod_note.is_empty():
		parts.append(prod_note)
	if parts.is_empty():
		return ""
	return "\n".join(parts)


static func _compare_production_tech_note(attacker: Province, defender: Province) -> String:
	var notes: PackedStringArray = []
	var a_prod := MapTechnologyContext.build_province_production_tech_bbcode(
		attacker, country_tag_for_province(attacker),
	)
	var d_prod := MapTechnologyContext.build_province_production_tech_bbcode(
		defender, country_tag_for_province(defender),
	)
	if not a_prod.is_empty():
		notes.append("%sAttacker: %s[/color]" % [COLOR_MUTED, a_prod])
	if not d_prod.is_empty():
		notes.append("%sDefender: %s[/color]" % [COLOR_MUTED, d_prod])
	return "\n".join(notes)


static func count_dual_situation_provinces(provinces: Dictionary = {}) -> int:
	var n := 0
	var source := provinces
	if source.is_empty() and typeof(MapManager) != TYPE_NIL:
		source = MapManager.get_all_provinces()
	for pid_var in source.keys():
		var p: Province = source[pid_var] as Province
		if p != null and is_province_contested(p) and has_active_agent_network(p):
			n += 1
	return n


static func build_supply_overlay_quick_key_bbcode(
	contested_count: int = -1,
	agent_network_count: int = -1,
	dual_count: int = -1,
	country_tag: String = "",
) -> String:
	var n_contested := contested_count if contested_count >= 0 else count_contested_provinces()
	var n_agent := agent_network_count if agent_network_count >= 0 else count_agent_networks({})
	var n_dual := dual_count if dual_count >= 0 else count_dual_situation_provinces()
	if n_contested <= 0 and n_agent <= 0:
		var tail := COLOR_EFFECTIVE + "●[/color] depot fill · pulsing outlines"
		return "[color=#8899aa]Quick key (L):[/color] " + tail
	var parts := (
		COLOR_WARN
		+ "▨[/color] stripes → "
		+ COLOR_NATIONAL
		+ "◎[/color] rings → "
		+ COLOR_EFFECTIVE
		+ "●[/color] fill"
	)
	var tail := " · outlines on top"
	if n_dual > 0:
		tail += " · " + COLOR_WARN + "⚑◎[/color] %d both" % n_dual
	if not country_tag.is_empty() and MapTechnologyContext.has_support_radio_bonuses(country_tag):
		tail += " · " + COLOR_TECH + "📡[/color] Support/Radio active"
	return "[color=#8899aa]Quick key (L):[/color] " + parts + tail


static func build_supply_legend_bbcode(
	selected_province_id: int = -1,
	compare_candidate_count: int = 0,
	hover_province_id: int = -1,
	hover_supply_role: String = "",
	contested_count: int = -1,
	agent_network_count: int = -1,
	player_tag: String = "",
	dual_situation_count: int = -1,
	time_pulse_bbcode: String = "",
	time_pulse_kind: String = "",
) -> String:
	var lines: PackedStringArray = []
	var n_contested := contested_count if contested_count >= 0 else count_contested_provinces()
	var n_agent := agent_network_count if agent_network_count >= 0 else count_agent_networks({}, player_tag)
	var n_dual := dual_situation_count if dual_situation_count >= 0 else count_dual_situation_provinces()
	var multi_overlay := n_contested > 0 and n_agent > 0
	var date_footer := GameDateDisplay.build_map_date_footer_bbcode(time_pulse_bbcode, time_pulse_kind)
	if multi_overlay:
		var header := build_supply_multi_overlay_block_bbcode(n_contested, n_agent, n_dual, player_tag)
		header += (
			"\n[color=#8899aa]Hover chips (max 6):[/color] "
			+ "merged [color=#9eb8d8]📦 L · verdict[/color] when crowded · "
			+ "[color=#ff6666]⬇ sabotage[/color] / [color=#5ae6b8]⬆ repair[/color] winner shown"
		)
		if time_pulse_kind != "day" and not date_footer.is_empty() and date_footer.find("📅") < 0:
			var glance := GameDateDisplay.build_map_date_glance_bbcode(true, true)
			if not glance.is_empty():
				header += "  " + glance
		lines.append(header)
		var sym_key := build_layers_symbol_key_bbcode(true, n_contested, n_agent, n_dual, player_tag)
		if not sym_key.is_empty() or not date_footer.is_empty():
			if time_pulse_kind == "day" and not date_footer.is_empty():
				lines.append(sym_key + "  " + date_footer if not sym_key.is_empty() else date_footer)
			elif not sym_key.is_empty() and not date_footer.is_empty():
				lines.append(sym_key)
				lines.append(date_footer)
			elif not sym_key.is_empty():
				lines.append(sym_key)
			else:
				lines.append(date_footer)
		date_footer = ""
	else:
		var quick := build_supply_overlay_quick_key_bbcode(n_contested, n_agent, n_dual, player_tag)
		if not quick.is_empty():
			lines.append(quick)
			lines.append("")
		var compact := build_compact_layers_summary_bbcode(
			true, n_contested, n_agent, n_dual, player_tag, true,
		)
		if not compact.is_empty():
			lines.append(compact)
	if not multi_overlay:
		lines.append("")
		var stack := build_overlay_layers_summary_bbcode(true, n_contested, n_agent, player_tag)
		if not stack.is_empty():
			lines.append(stack)
			lines.append("")
		var conflict_line := build_conflict_legend_line(n_contested)
		var agent_line := build_agent_legend_line(agent_network_count, player_tag)
		if not conflict_line.is_empty():
			lines.append(conflict_line)
		if not agent_line.is_empty():
			lines.append(agent_line)
		if n_contested > 0 or n_agent > 0:
			lines.append(
				"[color=#8899aa]Hover: brighter stripes/rings · outlines pulse above layers[/color]"
			)
	elif n_dual > 0:
		lines.append(
			"%s⚑◎ %d: blended outline · hover tooltip accent · %s▨ stripes + %s◎ rings[/color]"
			% [COLOR_WARN, n_dual, COLOR_WARN, COLOR_NATIONAL]
		)
	if not date_footer.is_empty():
		lines.append(date_footer)
	var tech_legend := str(MapTechnologyContext.get_build_mode_preview(player_tag).get("legend_line", ""))
	if multi_overlay and not player_tag.is_empty() and MapTechnologyContext.has_support_radio_bonuses(player_tag):
		tech_legend = ""
	if not tech_legend.is_empty():
		lines.append(tech_legend)
	lines.append(
		"[color=#9eb8d8]L on[/color]  "
		+ "[color=#8899aa]● fill[/color] "
		+ "[color=#7dffb2]high[/color]/[color=#e8c04a]mid[/color]/[color=#ff9a6e]low[/color]  "
		+ "[color=#8899aa]◇ hub · — military route · ~ preview · ◆ selected · soft gold ◇ = trade corridor[/color]"
	)
	lines.append(
		"[color=#8899aa]Base map[/color]: "
		+ "terrain shading + brighter fill -> higher development — eased while L tint is active"
	)
	lines.append(
		"  [color=#ff4d48][b]⚙ red · fast pulse[/b][/color] = sabotage winning (chip damage > repair)"
	)
	lines.append(
		"  [color=#5ae6b8][b]⚙ teal · slow pulse[/b][/color] = repair winning (repair beats chips)"
	)
	lines.append(
		"  [color=#e8a030]⚙ amber blend[/color] = even / stalemate  ·  "
		+ "[color=#ff9428]⛟ orange[/color] = supply disruption  ·  "
		+ "[color=#e8a030]⛟ amber[/color] = depot throughput hit"
	)
	lines.append("[color=#8899aa]L fill tint[/color] (under depot color — matches ring winner):")
	lines.append(
		"  [color=#ff6666][b]rose[/b][/color] = sabotage  ·  "
		+ "[color=#5ae6b8][b]teal[/b][/color] = repair/recovering  ·  "
		+ "[color=#ff9428]amber[/color] = supply pressure"
	)
	lines.append(
		"  [color=#8899aa]Hover tooltip: verdict + NET/day + duel bar · chips max 6[/color]"
	)
	lines.append(
		"[color=#8899aa]◎ agent rings[/color] — focus tint; "
		+ "3 mini bars under sabotage = infra / repair / chip duel"
	)
	if not player_tag.is_empty() and MapTechnologyContext.has_support_radio_bonuses(player_tag):
		lines.append(
			"  [color=#6ec8ff]📡 cyan tint[/color] = your province with Support/Radio (planning/recon on routes)"
		)
	lines.append(
		"[color=#8899aa]Hover chips: [/color]"
		+ "[color=#ff6666]⬇ SABOTAGE WINNING[/color] · "
		+ "[color=#5ae6b8]⬆ REPAIR WINNING[/color] · "
		+ "[color=#5ae6b8]⬆ RECOVERING[/color] · "
		+ "[color=#ff9428]⬇ SUPPLY[/color]  "
		+ "(chips: SAB WIN / REP WIN · meter −N or +N/day)"
	)
	lines.append(
		"[color=#8899aa]Tech chips: [/color]"
		+ "[color=#6ec8ff]📡[/color] Support/Radio (planning/recon on routes) · "
		+ "[color=#6ec8ff]🔬[/color] active research — reserved in crowded overlays"
	)
	lines.append(
		"[color=#8899aa]Engineers: [/color]"
		+ "[color=#5ae6b8]🔧[/color] = brigades boosting repair · "
		+ "[color=#ff9a6e]🔧 URGENT[/color] = sabotage winning · "
		+ "[color=#6ec8ff]🔧 assign[/color] = recommended · "
		+ "[color=#ffb85a]🔧 weak[/color] = present but insufficient · "
		+ "Shift+click moves an engineer division · inspector Deploy cycles divisions"
	)
	lines.append(
		"[color=#8899aa]Build: [/color]"
		+ "[color=#ffb85a]📉[/color] dev tier · "
		+ "[color=#ffb85a]🏔[/color] terrain · "
		+ "[color=#ffb85a]🔒[/color] tech · "
		+ "[color=#ffb85a]🏭[/color] factory · "
		+ "[color=#ffb85a]↗ Name[/color] = recommended relocate province · "
		+ "chips stay visible on L / agent / contested overlays"
	)
	lines.append(
		"[color=#8899aa]Action: [/color]"
		+ "clear [color=#a78bfa]◎[/color] agent network to stop infra chips · "
		+ "restore depots via routes & Support/Radio"
	)
	if selected_province_id >= 0:
		var sel_name := _province_short_name(selected_province_id)
		lines.append(
			"[color=#8899aa]⚔ [/color][color=#ffb85a]○[/color][color=#8899aa] faint = adjacent to %s (%d) · bold orange = active compare[/color]"
			% [sel_name, compare_candidate_count]
		)
	else:
		lines.append(
			"[color=#8899aa]Select a province · hover adjacent neighbor for combat preview[/color]"
		)
	if hover_province_id >= 0:
		var hover_line := ""
		if not hover_supply_role.is_empty():
			hover_line = (
				"[color=#8899aa]Hover: %s %s (%s)"
				% [_supply_role_icon(hover_supply_role), _province_short_name(hover_province_id), _supply_role_label(hover_supply_role)]
			)
		else:
			hover_line = "[color=#8899aa]Hover: %s" % _province_short_name(hover_province_id)
		var fill := depot_fill_ratio(hover_province_id)
		if fill >= 0.0:
			hover_line += " · depot %d%%" % int(round(fill * 100.0))
		var hp := _province_by_id(hover_province_id)
		if hp != null:
			var dual := build_dual_situation_glance_bbcode(hp)
			if not dual.is_empty():
				hover_line += " · " + dual
			elif is_province_contested(hp):
				hover_line += " · %s⚑ contested[/color]" % COLOR_WARN
			elif has_active_agent_network(hp):
				var ab := ""
				if agent_applies_daily_pressure(hp):
					ab = "⛟" if agent_pressure_focus_kind(hp) == "disrupt" else "⚙"
				hover_line += " · %s◎%s agent[/color]" % [COLOR_NATIONAL, ab]
			if province_needs_infrastructure_ui(hp):
				var hp_bd := _infra_repair_breakdown(hp)
				var outcome_short := build_sabotage_verdict_inline_bbcode(hp, hp_bd)
				if not outcome_short.is_empty():
					hover_line += " · " + outcome_short
			elif agent_applies_daily_pressure(hp):
				var compact_rec := build_province_pressure_recovery_compact(hp)
				if not compact_rec.is_empty():
					hover_line += " · %s%s[/color]" % [COLOR_WARN, compact_rec]
		hover_line += "[/color]"
		lines.append(hover_line)
	return "\n".join(lines)


static func build_map_compare_hint_plain(
	selected_province_id: int,
	candidate_count: int,
	hover_province_id: int = -1,
	hover_is_candidate: bool = false,
) -> String:
	if selected_province_id < 0:
		return ""
	var name := _province_short_name(selected_province_id)
	if hover_is_candidate and hover_province_id >= 0:
		var hover_p := _province_by_id(hover_province_id)
		var extra := ""
		if hover_p != null:
			if is_province_contested(hover_p) and has_active_agent_network(hover_p):
				extra += " · ⚑◎ contested + agent"
			elif is_province_contested(hover_p):
				extra += " · ⚑ contested"
			elif has_active_agent_network(hover_p):
				extra += " · ◎ agent"
		return (
			"⚔ %s selected — hovering %s (○ neighbor)%s · click to lock compare"
			% [name, _province_short_name(hover_province_id), extra]
		)
	return (
		"⚔ %s selected — hover ○-outlined neighbor (%d) for combat preview"
		% [name, candidate_count]
	)


static func build_supply_overlay_bbcode(
	plan: SupplyRoutePlan,
	province: Province,
	player_tag: String,
	top_depots_text: String = "",
) -> String:
	var lines: PackedStringArray = []
	var title := "⟳ Reroute preview" if plan.is_player_override else "⛟ Supply route"
	lines.append("%s%s[/color]" % [COLOR_HEADER, title])
	if plan.path_length() > 0:
		lines.append(
			"%s⛟ %s → %s · %s · %d hops[/color]"
			% [
				COLOR_MUTED,
				_province_short_name(plan.source_province_id),
				_province_short_name(plan.target_province_id),
				plan.routing_mode,
				plan.path_length(),
			]
		)
	lines.append(
		"%sRoute effect: reinf ×%.2f · interdiction %.0f%% · %.1f days[/color]"
		% [
			COLOR_MUTED,
			plan.reinforcement_modifier,
			plan.interdiction_chance * 100.0,
			plan.total_days,
		]
	)
	for line in plan.summary_lines():
		lines.append("%s%s[/color]" % [COLOR_MUTED, line])
	if plan.path_length() > 0:
		var path_names := PackedStringArray()
		for pid_var in plan.province_path:
			path_names.append(_province_short_name(int(pid_var)))
		lines.append("%sPath: %s[/color]" % [COLOR_MUTED, " → ".join(path_names)])
	for line in build_route_modifier_lines(plan.province_path, player_tag):
		if line.begins_with("["):
			lines.append(line)
		else:
			lines.append("%s%s[/color]" % [COLOR_MUTED, line])
	if province != null:
		lines.append("")
		lines.append("%s── Hub modifiers (%s) ──[/color]" % [COLOR_HEADER, province.name])
		if is_province_contested(province):
			lines.append(build_conflict_status_bbcode(province))
		var pe := get_province_effects_for(province, player_tag)
		lines.append(build_compact_effective_summary(pe))
		var supply_line := build_supply_logistics_one_liner(pe, player_tag)
		if not supply_line.is_empty():
			lines.append(supply_line)
		lines.append(_depot_bbcode_line(province.id))
		lines.append(_stat_column_legend_bbcode())
		for row in _logistics_rows(pe):
			lines.append(_bbcode_stat_line_layered(row))
		var badge := build_national_sources_badge(province)
		if not badge.is_empty():
			lines.append(badge)
			var sources := build_national_sources_grouped_compact(province, 3)
			if not sources.is_empty():
				lines.append(sources)
	if not top_depots_text.is_empty():
		lines.append("")
		lines.append("%s%s[/color]" % [COLOR_HEADER, top_depots_text])
	return "\n".join(lines)


static func build_info_logistics_text(province: Province) -> String:
	var tag := country_tag_for_province(province)
	var pe := get_province_effects_for(province, tag)  # MapManager preferred path
	var lines: PackedStringArray = []
	lines.append("Infrastructure: %d  ·  Development: %d" % [province.infrastructure, province.development_level])
	for row in _logistics_rows(pe):
		lines.append(_plain_stat_line(row))
	lines.append(_depot_summary_line(province.id))
	if province.resolve_has_port():
		lines.append("Coastal access: yes")
	return "\n".join(lines)


static func build_info_combat_text(
	province: Province,
	selected_province_id: int = -1,
) -> String:
	var tag := country_tag_for_province(province)
	var pe := get_province_effects_for(province, tag)   # MapManager preferred
	var lines: PackedStringArray = []
	for row in _combat_rows(pe):
		lines.append(_plain_stat_line(row))
	lines.append(_terrain_width_line(province.terrain))
	var other := _resolve_battle_counterpart(province, selected_province_id)
	lines.append("")
	if other != null:
		lines.append(_battle_preview_block(province, other, selected_province_id))
	else:
		lines.append(_local_battle_block(province))
	return "\n".join(lines)


static func build_national_effects_bbcode(province: Province) -> String:
	var tag := country_tag_for_province(province)
	if tag.is_empty():
		return "%sNo controlling country — national modifiers unavailable.[/color]" % COLOR_MUTED
	var lines: PackedStringArray = []
	lines.append("%sNational effects (%s)[/color]" % [COLOR_HEADER, tag])
	for line in _national_spirit_lines(tag):
		lines.append(line)
	for line in _temporary_effect_lines(tag):
		lines.append(line)
	var agent_line := _agent_network_line(province.id, tag)
	if not agent_line.is_empty():
		lines.append(agent_line)
	if lines.size() <= 1:
		lines.append("%s  No province-relevant national modifiers active.[/color]" % COLOR_MUTED)
	return "\n".join(lines)


static func build_route_modifier_lines(path: Array, player_tag: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if path.is_empty() or player_tag.is_empty():
		return lines
	var tag := player_tag.strip_edges().to_upper()
	lines.append("%sRoute province modifiers (national applied):[/color]" % COLOR_HEADER)
	var count := 0
	for pid_var in path:
		var pid := int(pid_var)
		var p := _province_by_id(pid)
		if p == null or country_tag_for_province(p) != tag:
			continue
		var pe: ProvinceEffects = null
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_effects"):
			pe = MapManager.get_province_effects(pid, tag)
		if pe == null:
			pe = get_province_effects_for(p, tag)
		var nat_note := ""
		if not pe.national_modifiers.is_empty():
			var reinf := float(pe.national_modifiers.get("reinforcement_speed", 0.0))
			if absf(reinf) >= 0.0001:
				nat_note = " (nat reinf %+0.0f%%)" % (reinf * 100.0)
		lines.append(
			"%s  %s: reinf ×%.2f · interdict ×%.2f%s[/color]"
			% [
				COLOR_MUTED,
				p.name,
				pe.get_effective_reinforcement_speed(),
				pe.get_effective_interdiction_resistance(),
				nat_note,
			]
		)
		count += 1
		if count >= 6:
			lines.append(
				"%s  … +%d more provinces on path[/color]" % [COLOR_MUTED, path.size() - count]
			)
			break
	return lines


static func depot_fill_ratio(province_id: int) -> float:
	var sm := _supply_manager()
	if sm == null:
		return -1.0
	var depot: ProvinceDepotState = sm.get_depot_state(province_id)
	if depot == null:
		return -1.0
	return depot.fill_ratio()


static func is_province_contested(province: Province) -> bool:
	if province == null:
		return false
	if province.controller_tag.is_empty():
		return false
	return province.owner_tag != province.controller_tag


static func get_active_agent_network(province: Province) -> AgentNetwork:
	if province == null or typeof(AgentManager) == TYPE_NIL:
		return null
	var tag := country_tag_for_province(province)
	var net: AgentNetwork = AgentManager.get_network(province.id)
	if net == null or not net.is_active():
		return null
	if net.controlling_country.strip_edges().to_upper() != tag:
		return null
	return net


static func has_active_agent_network(province: Province) -> bool:
	return get_active_agent_network(province) != null


static func count_agent_networks(provinces: Dictionary = {}, country_tag: String = "") -> int:
	if typeof(AgentManager) == TYPE_NIL:
		return 0
	var tag := country_tag.strip_edges().to_upper()
	if not tag.is_empty():
		var n := 0
		for net in AgentManager.get_networks_for_country(tag):
			if net != null and net.is_active():
				n += 1
		return n
	var total := 0
	for pid_var in provinces.keys():
		var net: AgentNetwork = AgentManager.get_network(int(pid_var))
		if net != null and net.is_active():
			total += 1
	return total


static func agent_applies_daily_pressure(province: Province) -> bool:
	var net := get_active_agent_network(province)
	if net == null or not net.is_active():
		return false
	return net.focus in ["supply_disruption", "infrastructure_sabotage"]


static func get_agent_pressure_fill_tint(province: Province) -> Color:
	if province != null:
		var bd := _infra_repair_breakdown(province)
		if (
			not bd.is_empty()
			and not bool(bd.get("under_infra_sabotage", false))
			and int(bd.get("infrastructure", province.infrastructure)) < 50
		):
			return ProvinceMapVisuals.FILL_INFRA_RECOVERING
	match agent_pressure_focus_kind(province):
		"disrupt":
			return ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE
		"sabotage":
			return ProvinceMapVisuals.FILL_AGENT_SABOTAGE_BASE
		_:
			return Color(0, 0, 0, 0)


static func agent_has_today_pressure_tick(province: Province) -> bool:
	var net := get_active_agent_network(province)
	if net == null:
		return false
	return net.last_daily_note.strip_edges() in ["disrupt", "sabotage", "infra_pressure"]


static func get_agent_pressure_fill_strength(province: Province, supply_overlay_active: bool = false) -> float:
	if not agent_applies_daily_pressure(province):
		return 0.0
	var strength := 0.16 if supply_overlay_active else 0.11
	if agent_has_today_pressure_tick(province):
		strength += 0.05
	if (
		agent_pressure_focus_kind(province) == "sabotage"
		and province != null
		and province.infrastructure <= 20
	):
		strength += 0.03
		var bd := _infra_repair_breakdown(province)
		if bool(bd.get("under_infra_sabotage", false)):
			var chip := estimate_daily_infra_chip_damage(province)
			var rate := float(bd.get("total", 0.0))
			if chip > 0 and float(chip) > rate:
				strength += 0.05
	elif agent_pressure_focus_kind(province) == "disrupt" and supply_overlay_active:
		strength += 0.02
	return strength


static func _infra_repair_breakdown(province: Province) -> Dictionary:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return {}
	return MapManager.get_infrastructure_repair_breakdown(province.id)


static func build_infra_sabotage_source_bbcode(province: Province) -> String:
	var net := get_active_agent_network(province)
	if net == null:
		return ""
	if net.focus != "infrastructure_sabotage" or not net.is_active():
		return ""
	var focus := str(net.focus).replace("_", " ")
	var eff := clampf(net.get_effectiveness(), 0.0, 1.5) * 100.0
	return (
		"%s◎ Source: agent network (%s) · str %.0f · eff %.0f%% · chips infra daily[/color]"
		% [COLOR_WARN, focus, net.strength, eff]
	)


static func build_supply_disruption_source_bbcode(province: Province) -> String:
	var net := get_active_agent_network(province)
	if net == null:
		return ""
	if net.focus != "supply_disruption" or not net.is_active():
		return ""
	var focus := str(net.focus).replace("_", " ")
	var eff := clampf(net.get_effectiveness(), 0.0, 1.5) * 100.0
	return (
		"%s◎ Source: agent network (%s) · str %.0f · eff %.0f%% · drains depot daily[/color]"
		% [COLOR_WARN, focus, net.strength, eff]
	)


static func estimate_daily_infra_chip_damage(province: Province) -> int:
	var net := get_active_agent_network(province)
	if net == null or not net.is_active() or net.focus != "infrastructure_sabotage":
		return 0
	if province == null or province.infrastructure <= 0:
		return 0
	var eff := clampf(net.get_effectiveness(), 0.0, 1.5)
	var damage := int(0.5 + eff * 0.35)
	return maxi(damage, 0)


static func build_infra_progress_meter_bbcode(
	infra: int,
	segments: int = 10,
	sabotage_winning: bool = false,
	net_loss_per_day: int = 0,
	repair_winning: bool = false,
	net_gain_per_day: float = 0.0,
) -> String:
	var filled := clampi(int(round(float(infra) / 50.0 * float(segments))), 0, segments)
	var bar := ""
	for i in segments:
		bar += "█" if i < filled else "░"
	var bar_color := COLOR_TECH if infra >= 35 else (COLOR_WARN if infra <= 15 else COLOR_MUTED)
	if sabotage_winning:
		bar_color = "[color=#ff8888]"
	elif repair_winning:
		bar_color = "[color=#5ae6b8]"
	var suffix := ""
	if sabotage_winning and net_loss_per_day > 0:
		suffix = "  ·  −%d/day" % net_loss_per_day
	elif repair_winning and net_gain_per_day > 0.0:
		suffix = "  ·  +%.1f/day" % net_gain_per_day
	return "%sInfra %s %d/50%s[/color]" % [bar_color, bar, infra, suffix]


## Returns who is winning the daily infra tug-of-war: sabotage | repair | even.
static func _daily_infra_duel_winner(province: Province, bd: Dictionary) -> String:
	var chip := float(estimate_daily_infra_chip_damage(province))
	var rate := float(bd.get("total", 0.0))
	if chip <= 0.0:
		return "repair"
	if chip > rate:
		return "sabotage"
	if rate > chip:
		return "repair"
	return "even"


static func _duel_winner_headline(winner: String, emphasize: bool = false) -> String:
	match winner:
		"sabotage":
			if emphasize:
				return "%s[b]⬇ SABOTAGE WINNING[/b][/color]" % COLOR_WARN
			return "%s⬇ SABOTAGE WINNING[/color]" % COLOR_WARN
		"repair":
			if emphasize:
				return "%s[b]⬆ REPAIR WINNING[/b][/color]" % COLOR_TECH
			return "%s⬆ REPAIR WINNING[/color]" % COLOR_TECH
		"even":
			if emphasize:
				return "%s[b]⚖ EVEN — net ~0[/b][/color]" % COLOR_TECH
			return "%s⚖ EVEN — net ~0[/color]" % COLOR_TECH
		_:
			return ""


static func has_engineers_stationed(bd: Dictionary) -> bool:
	return float(bd.get("engineer_brigades", 0.0)) >= 0.05


static func province_accepts_player_engineers(province: Province, bd: Dictionary) -> bool:
	if province == null or bd.is_empty():
		return false
	var tag := str(bd.get("country_tag", country_tag_for_province(province))).strip_edges().to_upper()
	return not tag.is_empty() and province_benefits_country(province, tag)


static func get_engineer_assignment_snapshot(province: Province) -> Dictionary:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return {}
	return MapManager.get_engineer_assignment_snapshot(province.id)


static func get_engineer_guidance_level(province: Province, bd: Dictionary) -> String:
	if province == null or bd.is_empty():
		return "none"
	if not province_accepts_player_engineers(province, bd):
		return "foreign"
	var snap := get_engineer_assignment_snapshot(province)
	if not snap.is_empty():
		return str(snap.get("guidance_level", "none"))
	var eng_n := float(bd.get("engineer_brigades", 0.0))
	if eng_n >= 0.05:
		return "present"
	if _pressure_status_label(province, bd) == "UNDER SABOTAGE":
		if _daily_infra_duel_winner(province, bd) == "sabotage":
			return "critical"
		return "recommended"
	if int(bd.get("infrastructure", province.infrastructure)) < 45:
		return "recommended"
	return "none"


static func engineer_guidance_level_title(level: String) -> String:
	match level:
		"critical":
			return "Urgent — sabotage winning"
		"recommended":
			return "Recommended — weak repair"
		"present_insufficient":
			return "Present but insufficient"
		"present":
			return "Engineers on station"
		"foreign":
			return "Not your province"
		_:
			return ""


static func province_needs_engineer_assignment(province: Province, bd: Dictionary = {}) -> bool:
	var breakdown := bd if not bd.is_empty() else _infra_repair_breakdown(province)
	var level := get_engineer_guidance_level(province, breakdown)
	return level in ["critical", "recommended", "present_insufficient"]


static func province_shows_engineer_assignment_chip(province: Province, bd: Dictionary = {}) -> bool:
	return province_needs_engineer_assignment(province, bd)


static func province_shows_engineer_map_chip(province: Province, bd: Dictionary = {}) -> bool:
	if province == null:
		return false
	var breakdown := bd if not bd.is_empty() else _infra_repair_breakdown(province)
	if not should_show_engineer_map_ui(province, breakdown):
		return false
	return (
		province_needs_engineer_assignment(province, breakdown)
		or has_engineers_stationed(breakdown)
	)


static func build_engineer_map_chip_bbcode(province: Province, bd: Dictionary) -> String:
	if province == null or bd.is_empty():
		return ""
	var chip := build_engineer_assignment_chip_bbcode(province, bd)
	if chip.is_empty():
		chip = build_engineer_hover_chip_bbcode(province, bd)
	if chip.is_empty() and province_needs_engineer_assignment(province, bd):
		chip = "%s🔧 no engineers[/color]" % COLOR_WARN
	return chip


static func get_engineer_supply_overlay_role(province: Province, bd: Dictionary) -> String:
	## Supply overlay ring role from guidance level (L overlay).
	if province == null or bd.is_empty():
		return ""
	if not province_accepts_player_engineers(province, bd):
		return ""
	var level := get_engineer_guidance_level(province, bd)
	var eng_n := float(bd.get("engineer_brigades", 0.0))
	var under_sab := bool(bd.get("under_infra_sabotage", false))
	match level:
		"critical":
			return "engineers_needed"
		"recommended":
			return "engineers_recommended"
		"present_insufficient":
			return "engineers_insufficient"
		"present":
			if eng_n >= 0.05:
				if under_sab:
					var winner := daily_infra_duel_winner(province, bd)
					if winner == "repair":
						return "infra_repair_engineers"
					if winner == "even":
						return "infra_duel_even"
				return "engineers_stationed"
		_:
			pass
	if under_sab:
		match daily_infra_duel_winner(province, bd):
			"repair":
				return "infra_repair_engineers" if eng_n >= 0.05 else "infra_repair"
			"even":
				return "infra_duel_even"
			_:
				return "infra_sabotage"
	var infra := int(bd.get("infrastructure", province.infrastructure))
	if infra < 45 and float(bd.get("total", 0.0)) > 0.0:
		return "infra_repair_engineers" if eng_n >= 0.05 else "infra_repair"
	if eng_n >= 0.05:
		return "engineers_stationed"
	return ""


static func build_engineer_repair_scenario_bbcode(province: Province, bd: Dictionary, compact: bool = true) -> String:
	if province == null or bd.is_empty() or not province_accepts_player_engineers(province, bd):
		return ""
	var snap := get_engineer_assignment_snapshot(province)
	if snap.is_empty():
		return ""
	var r0 := float(snap.get("rate_at_0_brigades", repair_rate_without_engineers(bd)))
	var r1 := float(snap.get("rate_at_1_brigade", r0))
	var r2 := float(snap.get("rate_at_2_brigades", r1))
	var cur := float(snap.get("repair_total", r0))
	var eng_n := float(snap.get("engineer_brigades", 0.0))
	var chip := int(snap.get("chip_damage_per_day", 0))
	var lines: PackedStringArray = []
	if compact:
		lines.append(
			"%s  Repair/day: [b]0 brg[/b] +%.2f  ·  [b]1 brg[/b] +%.2f  ·  [b]2 brg[/b] +%.2f[/color]"
			% [COLOR_MUTED, r0, r1, r2]
		)
		if chip > 0:
			lines.append(
				"%s  Sabotage chip ~%d/day — need repair > chip to recover infra[/color]"
				% [COLOR_WARN if r0 < float(chip) else COLOR_MUTED, chip]
			)
	else:
		lines.append("%s  Projected repair rate by engineer presence:[/color]" % COLOR_MUTED)
		lines.append("%s    0 brigades: +%.2f/day%s[/color]" % [
			COLOR_MUTED,
			r0,
			"  ← current" if eng_n < 0.05 else "",
		])
		lines.append("%s    1 brigade:  +%.2f/day%s[/color]" % [
			COLOR_TECH,
			r1,
			"  ← current" if eng_n >= 0.45 and eng_n < 1.25 else "",
		])
		lines.append("%s    2 brigades: +%.2f/day%s[/color]" % [
			COLOR_TECH,
			r2,
			"  ← current" if eng_n >= 1.25 else "",
		])
		if eng_n >= 0.05:
			lines.append("%s    Now (%.1f brg): +%.2f/day[/color]" % [COLOR_TECH, eng_n, cur])
	return "\n".join(lines)


static func build_engineer_assignment_guidance_bbcode(
	province: Province,
	bd: Dictionary,
	compact: bool = true,
) -> String:
	if province == null or bd.is_empty():
		return ""
	var level := get_engineer_guidance_level(province, bd)
	if level in ["none", "foreign", "present"]:
		return ""
	var snap := get_engineer_assignment_snapshot(province)
	var chip := int(snap.get("chip_damage_per_day", 0))
	var rate := float(snap.get("repair_total", float(bd.get("total", 0.0))))
	var r1 := float(snap.get("rate_at_1_brigade", rate))
	var r2 := float(snap.get("rate_at_2_brigades", r1))
	var lines: PackedStringArray = []
	lines.append(
		"%s  [b]Guidance: %s[/b][/color]"
		% [_guidance_level_color(level), engineer_guidance_level_title(level)]
	)
	match level:
		"critical":
			if compact:
				lines.append(
					"%s  [b]Critical[/b] = sabotage chips are beating repair today. Station engineers before infra drops further.[/color]"
					% COLOR_MUTED
				)
			else:
				lines.append(
					"%s  [b]Critical[/b] — the daily duel favors sabotage. Without engineers, repair cannot outpace chip damage.[/color]"
					% COLOR_MUTED
				)
			if chip > 0:
				lines.append(
					"%s  Now: repair +%.2f/day vs sabotage ~%d/day — need repair > chip to recover.[/color]"
					% [COLOR_WARN, rate, chip]
				)
				if r1 > float(chip):
					lines.append(
						"%s  +1 brigade projects +%.2f/day (likely flips the duel).[/color]" % [COLOR_TECH, r1]
					)
				else:
					lines.append(
						"%s  +1 brigade → +%.2f/day; +2 → +%.2f/day — may still need more or clear ◎ agents.[/color]"
						% [COLOR_MUTED, r1, r2]
					)
		"recommended":
			if compact:
				lines.append(
					"%s  [b]Recommended[/b] = repair runs but engineers would materially help (low infra or sabotage pressure).[/color]"
					% COLOR_MUTED
				)
			else:
				lines.append(
					"%s  [b]Recommended[/b] — not losing the duel yet, but repair is thin. Assign before sabotage escalates.[/color]"
					% COLOR_MUTED
				)
			if chip > 0:
				lines.append(
					"%s  Sabotage ~%d/day vs repair +%.2f/day — engineers widen the margin.[/color]"
					% [COLOR_MUTED, chip, rate]
				)
			elif int(bd.get("infrastructure", province.infrastructure)) < 45:
				lines.append(
					"%s  Infrastructure below 45 — engineer bonus speeds recovery.[/color]" % COLOR_MUTED
				)
		"present_insufficient":
			var eng_n := float(snap.get("engineer_brigades", float(bd.get("engineer_brigades", 0.0))))
			if compact:
				lines.append(
					"%s  [b]Present but insufficient[/b] = engineers are here but repair still loses (or barely holds) the duel.[/color]"
					% COLOR_MUTED
				)
			else:
				lines.append(
					"%s  [b]Present but insufficient[/b] — %.1f brigade-equiv on station is not enough while sabotage chips remain.[/color]"
					% [COLOR_MUTED, eng_n]
				)
			if chip > 0:
				lines.append(
					"%s  Now +%.2f/day vs chip ~%d/day — add brigades (+2 → +%.2f/day) or break the ◎ network.[/color]"
					% [COLOR_WARN, rate, chip, r2]
				)
			else:
				lines.append(
					"%s  Add brigades or clear agents — current station does not stop pressure.[/color]" % COLOR_MUTED
				)
	var scenario := build_engineer_repair_scenario_bbcode(province, bd, compact)
	if not scenario.is_empty():
		lines.append(scenario)
	if province_accepts_player_engineers(province, bd):
		var assign_hint := "Shift+click deploys nearest engineer division"
		if compact:
			assign_hint += " · inspector button cycles divisions"
		else:
			assign_hint += (
				" on the map (L overlay recommended), or use Deploy engineers in the inspector"
			)
		lines.append("%s  [b]Assign:[/b] %s.[/color]" % [COLOR_MUTED, assign_hint])
		var roster := build_engineer_capable_divisions_hint_bbcode(
			str(bd.get("country_tag", country_tag_for_province(province))), compact,
		)
		if not roster.is_empty():
			lines.append(roster)
	return "\n".join(lines)


static func _guidance_level_color(level: String) -> String:
	match level:
		"critical", "present_insufficient":
			return COLOR_WARN
		"recommended", "present":
			return COLOR_TECH
		_:
			return COLOR_MUTED


static func build_engineer_assignment_chip_bbcode(province: Province, bd: Dictionary) -> String:
	var level := get_engineer_guidance_level(province, bd)
	match level:
		"critical":
			return "%s🔧 URGENT[/color]" % COLOR_WARN
		"recommended":
			return "%s🔧 assign[/color]" % COLOR_TECH
		"present_insufficient":
			return "%s🔧 weak[/color]" % COLOR_WARN
		"present":
			return build_engineer_hover_chip_bbcode(province, bd)
		_:
			return ""


static func _engineer_repair_rate_line(
	label: String,
	before: Dictionary,
	after: Dictionary,
) -> String:
	if before.is_empty() and after.is_empty():
		return ""
	var rate_before := float(before.get("repair_total", 0.0))
	var rate_after := float(after.get("repair_total", 0.0))
	if absf(rate_before - rate_after) < 0.005:
		return ""
	return "%s repair +%.2f→+%.2f/day" % [label, rate_before, rate_after]


static func build_engineer_assignment_toast_message(
	province: Province,
	success: bool,
	level_before: String,
	level_after: String,
	engineer_brigades: float,
	error_text: String = "",
	deploy_result: Dictionary = {},
) -> String:
	if province == null:
		return ""
	if not success:
		if not error_text.is_empty():
			return error_text
		return "Could not deploy engineers to %s" % province.name
	var div_name := str(deploy_result.get("division_name", "")).strip_edges()
	var eng_equiv := float(deploy_result.get("engineer_equiv", 0.0))
	var moved_from := str(deploy_result.get("moved_from_name", "")).strip_edges()
	var title := engineer_guidance_level_title(level_after)
	if title.is_empty():
		title = "Engineers on station"
	var delta := ""
	if level_before != level_after and not level_before.is_empty():
		delta = " (%s → %s)" % [
			engineer_guidance_level_title(level_before),
			engineer_guidance_level_title(level_after),
		]
	var who := "Engineers"
	if not div_name.is_empty():
		who = div_name
	var move_bit := ""
	if not moved_from.is_empty():
		move_bit = " — moved from %s" % moved_from
	var brg_note := "%.1f brg-equiv at province" % engineer_brigades
	if eng_equiv > 0.05 and absf(eng_equiv - engineer_brigades) > 0.05:
		brg_note = "%.1f brg-equiv (division %.1f)" % [engineer_brigades, eng_equiv]
	var base := "✓ %s → %s%s — %s · %s%s" % [
		who, province.name, move_bit, brg_note, title, delta,
	]
	var repair_bits: PackedStringArray = []
	var dest_before: Dictionary = deploy_result.get("destination_before", {}) as Dictionary
	var dest_after: Dictionary = deploy_result.get("destination_after", {}) as Dictionary
	var dest_line := _engineer_repair_rate_line(province.name, dest_before, dest_after)
	if not dest_line.is_empty():
		repair_bits.append(dest_line)
	var origin_name := str(
		(deploy_result.get("origin_before", {}) as Dictionary).get("province_name", moved_from)
	).strip_edges()
	if origin_name.is_empty():
		origin_name = moved_from
	var origin_before: Dictionary = deploy_result.get("origin_before", {}) as Dictionary
	var origin_after: Dictionary = deploy_result.get("origin_after", {}) as Dictionary
	if not origin_name.is_empty():
		var origin_line := _engineer_repair_rate_line(origin_name, origin_before, origin_after)
		if not origin_line.is_empty():
			repair_bits.append(origin_line)
	if repair_bits.is_empty():
		return base
	return "%s · %s" % [base, " · ".join(repair_bits)]


static func build_engineer_divisions_at_province_bbcode(
	province: Province,
	country_tag: String,
	compact: bool = true,
) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = country_tag_for_province(province)
	var divs: Array[Dictionary] = MapManager.get_engineer_divisions_at_province(province.id, tag)
	if divs.is_empty():
		return ""
	var lines: PackedStringArray = []
	if compact:
		var names: PackedStringArray = []
		for entry in divs:
			names.append(str(entry.get("display_name", entry.get("formation_id", "?"))))
		lines.append(
			"%s  🔧 Divisions on station: %s[/color]" % [COLOR_TECH, ", ".join(names)]
		)
	else:
		lines.append("%s  🔧 Engineer divisions in this province[/color]" % COLOR_TECH)
		for entry in divs:
			var eng := float(entry.get("engineer_brigades", 0.0))
			lines.append(
				"%s    · %s (%.1f engineer brg-equiv)[/color]"
				% [COLOR_MUTED, str(entry.get("display_name", "?")), eng]
			)
	return "\n".join(lines)


static func build_engineer_roster_inspector_bbcode(
	country_tag: String,
	highlight_province_id: int = -1,
) -> String:
	if typeof(MapManager) == TYPE_NIL:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return ""
	var divs: Array[Dictionary] = MapManager.get_engineer_capable_divisions(tag)
	if divs.is_empty():
		return "%s  No engineer-capable divisions for %s.[/color]" % [COLOR_WARN, tag]
	var stationed := 0
	var free := 0
	for entry in divs:
		if int(entry.get("stationed_province_id", -1)) < 0:
			free += 1
		else:
			stationed += 1
	var lines: PackedStringArray = []
	lines.append(
		"%s  Engineer divisions — %d total (%d stationed · %d free)[/color]"
		% [COLOR_TECH, divs.size(), stationed, free]
	)
	for entry in divs:
		var label := str(entry.get("display_name", entry.get("formation_id", "?")))
		var pid := int(entry.get("stationed_province_id", -1))
		var eng := float(entry.get("engineer_brigades", 0.0))
		var where := "unassigned"
		if pid >= 0:
			var p: Province = MapManager.get_province(pid)
			where = p.name if p != null else "#%d" % pid
			if pid == highlight_province_id:
				where = "[b]%s[/b] (here)" % where
		lines.append(
			"%s    · %s @ %s (%.1f eng brg)[/color]" % [COLOR_MUTED, label, where, eng]
		)
	lines.append(
		"%s  Shift+click province or Deploy button to move a division (same as movement order).[/color]"
		% COLOR_MUTED
	)
	return "\n".join(lines)


static func build_engineer_capable_divisions_hint_bbcode(country_tag: String, compact: bool = true) -> String:
	if typeof(MapManager) == TYPE_NIL:
		return ""
	var divs: Array[Dictionary] = MapManager.get_engineer_capable_divisions(country_tag)
	if divs.is_empty():
		return "%s  No engineer-capable divisions registered for your country.[/color]" % COLOR_WARN
	var unassigned := 0
	var stationed := 0
	var parts: PackedStringArray = []
	for entry in divs:
		var pid := int(entry.get("stationed_province_id", -1))
		var label := str(entry.get("display_name", "?"))
		if pid < 0:
			unassigned += 1
			if compact and parts.size() < 2:
				parts.append("%s (free)" % label)
		else:
			stationed += 1
			if not compact:
				var p: Province = MapManager.get_province(pid)
				var where := p.name if p != null else "#%d" % pid
				parts.append("%s @ %s" % [label, where])
	if compact:
		if not parts.is_empty():
			return "%s  Divisions: %s · %d/%d stationed (%d free)[/color]" % [
				COLOR_MUTED, " · ".join(parts), stationed, divs.size(), unassigned,
			]
		return "%s  %d engineer divisions (%d stationed · %d free)[/color]" % [
			COLOR_MUTED, divs.size(), stationed, unassigned,
		]
	return "%s  Engineer divisions: %s[/color]" % [COLOR_MUTED, " · ".join(parts)]


static func engineer_repair_share_percent(bd: Dictionary) -> float:
	var total := maxf(0.001, float(bd.get("total", 0.0)))
	return clampf(100.0 * float(bd.get("engineer_bonus", 0.0)) / total, 0.0, 100.0)


static func repair_rate_without_engineers(bd: Dictionary) -> float:
	return maxf(0.01, float(bd.get("total", 0.0)) - float(bd.get("engineer_bonus", 0.0)))


static func should_show_engineer_map_ui(province: Province, bd: Dictionary) -> bool:
	if province == null or bd.is_empty():
		return false
	if has_engineers_stationed(bd):
		return true
	if province_needs_infrastructure_ui(province):
		return _pressure_status_label(province, bd) in ["UNDER SABOTAGE", "RECOVERING", "DEPOT SABOTAGED"]
	return false


static func build_engineer_hover_chip_bbcode(province: Province, bd: Dictionary) -> String:
	if province == null or bd.is_empty() or not has_engineers_stationed(bd):
		return ""
	var eng_n := float(bd.get("engineer_brigades", 0.0))
	var bonus := float(bd.get("engineer_bonus", 0.0))
	var share := int(round(engineer_repair_share_percent(bd)))
	var tag := str(bd.get("country_tag", country_tag_for_province(province)))
	var div_n := 0
	if typeof(MapManager) != TYPE_NIL:
		div_n = MapManager.get_engineer_divisions_at_province(province.id, tag).size()
	if div_n > 0:
		if share >= 8:
			return "%s🔧 %d div · +%.2f/d (%d%%)[/color]" % [COLOR_TECH, div_n, bonus, share]
		return "%s🔧 %d div · +%.2f/d[/color]" % [COLOR_TECH, div_n, bonus]
	return "%s🔧 %.1f eng · +%.2f/d (%d%%)[/color]" % [COLOR_TECH, eng_n, bonus, share]


static func build_engineer_presence_section_bbcode(
	province: Province,
	bd: Dictionary,
	compact: bool = true,
) -> String:
	if province == null or bd.is_empty() or not should_show_engineer_map_ui(province, bd):
		return ""
	var eng_n := float(bd.get("engineer_brigades", 0.0))
	var eng_bonus := float(bd.get("engineer_bonus", 0.0))
	var total := float(bd.get("total", 0.0))
	var without := repair_rate_without_engineers(bd)
	var cap := MapManager.INFRA_REPAIR_ENGINEER_CAP if typeof(MapManager) != TYPE_NIL else 0.28
	var lines: PackedStringArray = []
	lines.append("%s── 🔧 Engineers ──[/color]" % COLOR_HEADER)
	var div_block := build_engineer_divisions_at_province_bbcode(
		province, str(bd.get("country_tag", country_tag_for_province(province))), compact,
	)
	if not div_block.is_empty():
		lines.append(div_block)
	if has_engineers_stationed(bd):
		var share := int(round(engineer_repair_share_percent(bd)))
		if compact:
			lines.append(
				"%s  %.1f brigade-equiv → [b]+%.2f/day[/b] repair (%d%% of +%.2f)[/color]"
				% [COLOR_TECH, eng_n, eng_bonus, share, total]
			)
			lines.append(
				"%s  Without engineers: +%.2f/day → with station: +%.2f/day[/color]"
				% [COLOR_MUTED, without, total]
			)
		else:
			lines.append(
				"%s  [b]%.1f[/b] engineer brigade-equivalent on station[/color]" % [COLOR_TECH, eng_n]
			)
			lines.append(
				"%s  Repair contribution: +%.2f/day (%d%% of total +%.2f/day) · cap ~%.2f from engineers[/color]"
				% [COLOR_MUTED, eng_bonus, share, total, cap]
			)
			lines.append(
				"%s  Rate without engineers: +%.2f/day → current +%.2f/day[/color]"
				% [COLOR_MUTED, without, total]
			)
	else:
		lines.append("%s  No engineer brigades detected in this province.[/color]" % COLOR_WARN)
		lines.append(
			"%s  Repair +%.2f/day — station engineers for up to +%.2f/day bonus (scales with brigades).[/color]"
			% [COLOR_MUTED, total, cap]
		)
		if _pressure_status_label(province, bd) == "UNDER SABOTAGE":
			lines.append(
				"%s  Sabotage duel: engineers often decide whether repair beats daily chip damage.[/color]"
				% COLOR_WARN
			)
	var guidance := build_engineer_assignment_guidance_bbcode(province, bd, compact)
	if not guidance.is_empty():
		lines.append(guidance)
	elif has_engineers_stationed(bd):
		var scenario := build_engineer_repair_scenario_bbcode(province, bd, compact)
		if not scenario.is_empty():
			lines.append(scenario)
		if province_accepts_player_engineers(province, bd):
			lines.append(
				"%s  [b]Assign:[/b] Shift+click province · inspector Deploy cycles divisions.[/color]"
				% COLOR_MUTED
			)
	return "\n".join(lines)


## One-line repair boosts (engineers / stability / technology) when they matter.
static func build_repair_contributions_glance_bbcode(bd: Dictionary) -> String:
	if bd.is_empty():
		return ""
	var parts: PackedStringArray = []
	var eng := float(bd.get("engineer_bonus", 0.0))
	var eng_n := float(bd.get("engineer_brigades", 0.0))
	var stab := float(bd.get("stability_bonus", 0.0))
	var tech := float(bd.get("tech_focus_bonus", 0.0))
	if eng > 0.001:
		var share := int(round(engineer_repair_share_percent(bd)))
		parts.append("🔧 +%.2f (%.1f brg, %d%%)" % [eng, eng_n, share])
	if absf(stab) > 0.001:
		parts.append("stability %+.2f" % stab)
	if tech > 0.001:
		parts.append("tech +%.2f" % tech)
	if parts.is_empty() and float(bd.get("base", 0.0)) > 0.05:
		parts.append("base +%.2f" % float(bd.get("base", 0.0)))
	if parts.is_empty():
		return ""
	var total := float(bd.get("total", 0.0))
	return "%sRepair: %s  →  [b]+%.2f/day[/b][/color]" % [COLOR_TECH, " · ".join(parts), total]


static func build_repair_contributions_glance_for_province(province: Province, bd: Dictionary) -> String:
	var glance := build_repair_contributions_glance_bbcode(bd)
	if province == null or bd.is_empty():
		return glance
	if _pressure_status_label(province, bd) != "UNDER SABOTAGE":
		return glance
	if _daily_infra_duel_winner(province, bd) != "sabotage":
		return glance
	var eng := float(bd.get("engineer_brigades", 0.0))
	if eng > 0.0:
		return glance
	var hint := "%sLosing infra — station engineer brigades to raise repair[/color]" % COLOR_WARN
	if glance.is_empty():
		return hint
	return "%s\n%s" % [glance, hint]


## Public helper for map visuals (duel winner on sabotaged provinces).
static func daily_infra_duel_winner(province: Province, bd: Dictionary) -> String:
	return _daily_infra_duel_winner(province, bd)


## Visual chip vs repair strength (8 segments each) for at-a-glance duel read.
static func build_sabotage_repair_duel_bbcode(
	province: Province,
	bd: Dictionary,
	compact: bool = false,
) -> String:
	if province == null or bd.is_empty():
		return ""
	var status := _pressure_status_label(province, bd)
	var rate := float(bd.get("total", 0.0))
	if status == "RECOVERING":
		var rep_bar := ""
		for i in 8:
			rep_bar += "█"
		return (
			"%sRepair winning: [color=#5ae6b8]%s[/color] +%.1f/day toward infra 50[/color]"
			% [COLOR_TECH, rep_bar, rate]
		)
	if status != "UNDER SABOTAGE":
		return ""
	var chip := float(estimate_daily_infra_chip_damage(province))
	if chip <= 0.0:
		return ""
	var winner := _daily_infra_duel_winner(province, bd)
	var total := maxf(chip + rate, 0.01)
	var sab_slots := clampi(int(round(8.0 * chip / total)), 1, 7)
	var rep_slots := clampi(8 - sab_slots, 1, 7)
	var sab_bar := ""
	var rep_bar := ""
	for i in 8:
		sab_bar += "█" if i < sab_slots else "░"
		rep_bar += "█" if i < rep_slots else "░"
	var line_color := COLOR_WARN if winner == "sabotage" else COLOR_TECH
	var label := (
		"sabotage winning"
		if winner == "sabotage"
		else ("repair winning" if winner == "repair" else "stalemate")
	)
	var tug := ""
	for i in 8:
		if i < sab_slots:
			tug += "[color=#ff6666]█[/color]"
		else:
			tug += "[color=#5ae6b8]█[/color]"
	if compact:
		var win_tag := "⬇" if winner == "sabotage" else ("⬆" if winner == "repair" else "⚖")
		return (
			"%s%s Duel %s: %s  (~%.0f chip vs +%.1f repair/d)[/color]"
			% [line_color, win_tag, label, tug, chip, rate]
		)
	return (
		"%sDuel — %s: [color=#ff6666]%s[/color] chip │ [color=#5ae6b8]%s[/color] repair  "
		+ "│ %s (~%.0f vs +%.1f /day)[/color]"
		% [line_color, label, sab_bar, rep_bar, tug, chip, rate]
	)


static func build_repair_boost_highlight_bbcode(province: Province, bd: Dictionary) -> String:
	if province == null:
		return ""
	return build_repair_contributions_glance_bbcode(bd)


## Single tooltip chip: verdict + net (saves one token in multi-overlay rows).
static func build_pressure_status_chip_row_bbcode(province: Province) -> String:
	if province == null or not province_needs_infrastructure_ui(province):
		return ""
	var bd := _infra_repair_breakdown(province)
	if bd.is_empty():
		return ""
	var status := _pressure_status_label(province, bd)
	var rate := float(bd.get("total", 0.0))
	match status:
		"UNDER SABOTAGE":
			var chip := estimate_daily_infra_chip_damage(province)
			var winner := _daily_infra_duel_winner(province, bd)
			if winner == "sabotage":
				return "%s⬇ SAB WIN · −%d/d[/color]" % [
					COLOR_WARN,
					maxi(1, chip - int(floor(rate))),
				]
			if winner == "repair":
				var eng_n := float(bd.get("engineer_brigades", 0.0))
				if eng_n >= 0.05:
					return "%s⬆ REP WIN · +%.1f/d · 🔧%.0f[/color]" % [COLOR_TECH, rate, eng_n]
				return "%s⬆ REP WIN · +%.1f/d[/color]" % [COLOR_TECH, rate]
			if chip > 0:
				return "%s⚖ EVEN · 0/d[/color]" % COLOR_TECH
			return "%s⬇ SABOTAGE[/color]" % COLOR_WARN
		"RECOVERING":
			var eng_r := float(bd.get("engineer_brigades", 0.0))
			if eng_r >= 0.05:
				return "%s⬆ RECOVERING · +%.1f/d · 🔧%.0f[/color]" % [COLOR_TECH, rate, eng_r]
			return "%s⬆ RECOVERING · +%.1f/d[/color]" % [COLOR_TECH, rate]
		"SUPPLY PRESSURE":
			var fill := depot_fill_ratio(province.id)
			if fill >= 0.0:
				return "%s⬇ SUPPLY · %d%%⛟[/color]" % [
					COLOR_WARN if fill < 0.4 else COLOR_MUTED,
					int(round(fill * 100.0)),
				]
			return "%s⬇ SUPPLY[/color]" % COLOR_WARN
		"DEPOT SABOTAGED":
			return "%s⬇ DEPOT[/color]" % COLOR_WARN
		_:
			return ""


static func _pressure_outcome_plain(province: Province, bd: Dictionary) -> String:
	if province == null or bd.is_empty():
		return ""
	var status := _pressure_status_label(province, bd)
	var rate := float(bd.get("total", 0.0))
	var chip := estimate_daily_infra_chip_damage(province)

	match status:
		"UNDER SABOTAGE":
			var winner := _daily_infra_duel_winner(province, bd)
			if winner == "sabotage":
				return "Sabotage winning ~%d chip/day (net −%d)" % [
					chip,
					maxi(1, chip - int(floor(rate))),
				]
			if winner == "repair":
				return "Repair winning +%.2f/day vs ~%d chip" % [rate, chip]
			if chip > 0:
				return "Even — ~%d chip vs +%.2f repair/day" % [chip, rate]
			return "Infrastructure sabotage active"
		"RECOVERING":
			var eta := int(bd.get("eta_days_to_cap", -1))
			if eta > 0 and eta < 500:
				return "Recovering +%.2f/day · ~%dd to 50" % [rate, eta]
			return "Recovering +%.2f/day" % rate
		"SUPPLY PRESSURE":
			return "Supply disruption draining depot"
		"DEPOT SABOTAGED":
			var depot_sab := float(bd.get("depot_sabotage_level", 0.0))
			return "Depot penalty %.0f%%" % (depot_sab * 100.0)
		_:
			return ""


static func build_infra_net_trend_bbcode(
	province: Province,
	bd: Dictionary,
	status: String,
) -> String:
	if status != "UNDER SABOTAGE" or province == null or bd.is_empty():
		return ""
	var chip := estimate_daily_infra_chip_damage(province)
	if chip <= 0:
		return ""
	var rate := float(bd.get("total", 0.0))
	var winner := _daily_infra_duel_winner(province, bd)
	if winner == "sabotage":
		var loss := chip - int(floor(rate))
		return (
			"%sTrend: sabotage winning — net ~−%d infra/day · clear ◎ network[/color]"
			% [COLOR_WARN, maxi(loss, 1)]
		)
	if winner == "repair":
		return (
			"%sTrend: repair winning — +%.2f/day beats ~%d chip/day[/color]"
			% [COLOR_TECH, rate, chip]
		)
	return (
		"%sTrend: even (~%d chip vs +%.2f repair /day)[/color]" % [COLOR_MUTED, chip, rate]
	)


static func build_pressure_trend_chip_bbcode(province: Province) -> String:
	if province == null or not province_needs_infrastructure_ui(province):
		return ""
	var bd := _infra_repair_breakdown(province)
	if bd.is_empty():
		return ""
	var status := _pressure_status_label(province, bd)
	match status:
		"UNDER SABOTAGE":
			return _duel_winner_headline(_daily_infra_duel_winner(province, bd))
		"RECOVERING":
			return "%s⬆ RECOVERING[/color]" % COLOR_TECH
		"SUPPLY PRESSURE":
			return "%s⬇ SUPPLY[/color]" % COLOR_WARN
		"DEPOT SABOTAGED":
			return "%s⬇ DEPOT[/color]" % COLOR_WARN
		_:
			return ""


## One-line scannable verdict for tooltips and the Sabotage & repair card.
static func build_pressure_outcome_headline_bbcode(province: Province, bd: Dictionary) -> String:
	if province == null or bd.is_empty():
		return ""
	var status := _pressure_status_label(province, bd)
	var rate := float(bd.get("total", 0.0))
	match status:
		"UNDER SABOTAGE":
			return _duel_winner_headline(_daily_infra_duel_winner(province, bd))
		"RECOVERING":
			return "%s⬆ RECOVERING[/color]" % COLOR_TECH
		"SUPPLY PRESSURE":
			return "%s⬇ SUPPLY PRESSURE[/color]" % COLOR_WARN
		"DEPOT SABOTAGED":
			return "%s⬇ DEPOT HIT[/color]" % COLOR_WARN
		_:
			return ""


static func build_net_daily_infra_bbcode(province: Province, bd: Dictionary) -> String:
	if province == null or bd.is_empty():
		return ""
	var status := _pressure_status_label(province, bd)
	var rate := float(bd.get("total", 0.0))
	match status:
		"UNDER SABOTAGE":
			var chip := estimate_daily_infra_chip_damage(province)
			var winner := _daily_infra_duel_winner(province, bd)
			if chip <= 0:
				return "%sNET: repair +%.2f/day · no sabotage chips today[/color]" % [COLOR_TECH, rate]
			if winner == "sabotage":
				var loss := maxi(1, chip - int(floor(rate)))
				return (
					"%s[b]SABOTAGE WINNING[/b] — NET −%d infra/day  (~%d chip − +%.2f repair)[/color]"
					% [COLOR_WARN, loss, chip, rate]
				)
			if winner == "repair":
				return (
					"%s[b]REPAIR WINNING[/b] — NET +%.2f/day beats ~%d chip/day[/color]"
					% [COLOR_TECH, rate, chip]
				)
			return (
				"%s[b]EVEN[/b] — NET ~0 (~%d chip vs +%.2f repair /day)[/color]" % [COLOR_MUTED, chip, rate]
			)
		"RECOVERING":
			var eta := int(bd.get("eta_days_to_cap", -1))
			if eta > 0 and eta < 500:
				return "%sNET: repair +%.2f/day · ~%d days to infra 50[/color]" % [COLOR_TECH, rate, eta]
			return "%sNET: repair +%.2f/day toward infra 50[/color]" % [COLOR_TECH, rate]
		"SUPPLY PRESSURE":
			var fill := depot_fill_ratio(province.id)
			if fill >= 0.0:
				return "%sNET: depot %d%% · daily agent drain on routes[/color]" % [
					COLOR_WARN if fill < 0.4 else COLOR_MUTED,
					int(round(fill * 100.0)),
				]
			return "%sNET: daily supply disruption on this province[/color]" % COLOR_WARN
		"DEPOT SABOTAGED":
			var depot_sab := float(bd.get("depot_sabotage_level", 0.0))
			return "%sNET: depot throughput −%.0f%% · fades ~13%%/day[/color]" % [
				COLOR_WARN if depot_sab > 0.2 else COLOR_MUTED,
				depot_sab * 100.0,
			]
		_:
			return ""


## Ultra-compact net rate for tooltip chip row (e.g. "−2/d", "+1.2/d").
static func build_net_daily_compact_chip_bbcode(province: Province, bd: Dictionary) -> String:
	if province == null or bd.is_empty():
		return ""
	var status := _pressure_status_label(province, bd)
	var rate := float(bd.get("total", 0.0))
	match status:
		"UNDER SABOTAGE":
			var chip := estimate_daily_infra_chip_damage(province)
			var winner := _daily_infra_duel_winner(province, bd)
			if winner == "sabotage":
				return "%s−%d/d[/color]" % [COLOR_WARN, maxi(1, chip - int(floor(rate)))]
			if winner == "repair":
				return "%s+%.1f/d[/color]" % [COLOR_TECH, rate]
			if chip > 0:
				return "%s0/d[/color]" % COLOR_MUTED
			return ""
		"RECOVERING":
			return "%s+%.1f/d[/color]" % [COLOR_TECH, rate]
		"SUPPLY PRESSURE":
			var fill := depot_fill_ratio(province.id)
			if fill >= 0.0:
				return "%s%d%%⛟[/color]" % [COLOR_WARN if fill < 0.4 else COLOR_MUTED, int(round(fill * 100.0))]
			return "%s⛟ drain[/color]" % COLOR_WARN
		"DEPOT SABOTAGED":
			return "%s−depot[/color]" % COLOR_WARN
		_:
			return ""


## Short net phrase for inline verdict (no "Net ≈" prefix).
static func build_net_daily_short_bbcode(province: Province, bd: Dictionary) -> String:
	var status := _pressure_status_label(province, bd)
	var rate := float(bd.get("total", 0.0))
	match status:
		"UNDER SABOTAGE":
			var chip_dmg := estimate_daily_infra_chip_damage(province)
			var winner := _daily_infra_duel_winner(province, bd)
			if winner == "sabotage":
				return "%sNET −%d/day[/color]" % [COLOR_WARN, maxi(1, chip_dmg - int(floor(rate)))]
			if winner == "repair":
				return "%sNET +%.1f/day[/color]" % [COLOR_TECH, rate]
			if chip_dmg > 0:
				return "%sNET ~0/day[/color]" % COLOR_MUTED
			return ""
		"RECOVERING":
			return "%sNET +%.1f/day[/color]" % [COLOR_TECH, rate]
		"SUPPLY PRESSURE":
			var fill := depot_fill_ratio(province.id)
			if fill >= 0.0:
				return "%sNET depot %d%%[/color]" % [
					COLOR_WARN if fill < 0.4 else COLOR_MUTED,
					int(round(fill * 100.0)),
				]
			return "%sNET supply drain[/color]" % COLOR_WARN
		"DEPOT SABOTAGED":
			return "%sNET depot penalty[/color]" % COLOR_WARN
		_:
			return ""


## Single-line verdict for scannable tooltips (headline │ net); optional action line below.
static func build_sabotage_verdict_inline_bbcode(
	province: Province,
	bd: Dictionary,
	with_action: bool = false,
) -> String:
	var status := _pressure_status_label(province, bd)
	var headline := ""
	match status:
		"UNDER SABOTAGE":
			headline = _duel_winner_headline(_daily_infra_duel_winner(province, bd), true)
		"RECOVERING":
			headline = "%s[b]⬆ RECOVERING[/b][/color]" % COLOR_TECH
		"SUPPLY PRESSURE":
			headline = "%s[b]⬇ SUPPLY PRESSURE[/b][/color]" % COLOR_WARN
		"DEPOT SABOTAGED":
			headline = "%s[b]⬇ DEPOT HIT[/b][/color]" % COLOR_WARN
		_:
			headline = build_pressure_outcome_headline_bbcode(province, bd)
	var net_short := build_net_daily_short_bbcode(province, bd)
	var line := ""
	if headline.is_empty():
		line = net_short
	elif net_short.is_empty():
		line = headline
	else:
		line = "%s  │  %s" % [headline, net_short]
	if line.is_empty():
		return ""
	if not with_action:
		return line
	var action := build_sabotage_action_hint_bbcode(province, bd)
	if action.is_empty():
		return line
	return "%s\n%s" % [line, action]


## Combined verdict + net for the Sabotage & repair card.
## compact=true: one scannable line (tooltip); compact=false: inspector block with action.
static func build_sabotage_verdict_block_bbcode(province: Province, bd: Dictionary, compact: bool = false) -> String:
	if compact:
		return build_sabotage_verdict_inline_bbcode(province, bd, true)
	var status := _pressure_status_label(province, bd)
	var headline := ""
	match status:
		"UNDER SABOTAGE":
			headline = _duel_winner_headline(_daily_infra_duel_winner(province, bd), true)
		"RECOVERING":
			headline = "%s[b]⬆ REPAIR WINNING[/b][/color]" % COLOR_TECH
		"SUPPLY PRESSURE":
			headline = "%s[b]⬇ SUPPLY PRESSURE[/b][/color]" % COLOR_WARN
		"DEPOT SABOTAGED":
			headline = "%s[b]⬇ DEPOT HIT[/b][/color]" % COLOR_WARN
		_:
			headline = build_pressure_outcome_headline_bbcode(province, bd)
	var net := build_net_daily_short_bbcode(province, bd)
	if net.is_empty():
		net = build_net_daily_infra_bbcode(province, bd)
	if headline.is_empty():
		return net
	if net.is_empty():
		return headline
	var parts: PackedStringArray = ["%s  │  %s" % [headline, net]]
	var action := build_sabotage_action_hint_bbcode(province, bd)
	if not action.is_empty():
		parts.append(action)
	return "\n".join(parts)


static func build_sabotage_action_hint_bbcode(province: Province, bd: Dictionary) -> String:
	if province == null or bd.is_empty():
		return ""
	var status := _pressure_status_label(province, bd)
	match status:
		"UNDER SABOTAGE":
			match _daily_infra_duel_winner(province, bd):
				"sabotage":
					return "%s→ Clear enemy ◎ network — losing infra daily[/color]" % COLOR_WARN
				"repair":
					return (
						"%s→ Repair winning — keep engineers · clear ◎ to finish recovery[/color]"
						% COLOR_TECH
					)
				_:
					return "%s→ Stalemate — clear ◎ network or add repair to pull ahead[/color]" % COLOR_MUTED
		"SUPPLY PRESSURE":
			return "%s→ Break ◎ network · refill depot via routes & local production[/color]" % COLOR_MUTED
		"RECOVERING":
			return "%s→ Keep engineers on station · stability & tech raise repair rate[/color]" % COLOR_MUTED
		"DEPOT SABOTAGED":
			return "%s→ Counter-intel fades depot penalty · repair pass heals infra[/color]" % COLOR_MUTED
		_:
			return ""


static func build_pressure_outcome_bbcode(province: Province, bd: Dictionary) -> String:
	var headline := build_pressure_outcome_headline_bbcode(province, bd)
	var net := build_net_daily_infra_bbcode(province, bd)
	if headline.is_empty():
		return ""
	if net.is_empty():
		return headline
	return "%s · %s" % [headline, net]


static func _pressure_status_label(province: Province, bd: Dictionary) -> String:
	if bool(bd.get("under_infra_sabotage", false)):
		return "UNDER SABOTAGE"
	if province != null and agent_pressure_focus_kind(province) == "disrupt":
		return "SUPPLY PRESSURE"
	var depot_sab := float(bd.get("depot_sabotage_level", 0.0))
	if depot_sab > 0.12:
		return "DEPOT SABOTAGED"
	var infra := int(bd.get("infrastructure", 0))
	if infra < 50:
		return "RECOVERING"
	return "STABLE"


static func build_infra_repair_breakdown_bbcode(province: Province, detailed: bool = false) -> String:
	var bd := _infra_repair_breakdown(province)
	if bd.is_empty():
		return ""
	var lines: PackedStringArray = []
	var base := float(bd.get("base", 0.0))
	var infra_bonus := float(bd.get("infra_bonus", 0.0))
	var stab := float(bd.get("stability_bonus", 0.0))
	var tech := float(bd.get("tech_focus_bonus", 0.0))
	var eng_bonus := float(bd.get("engineer_bonus", 0.0))
	var eng := float(bd.get("engineer_brigades", 0.0))

	if detailed:
		lines.append(
			"%sRepair rate: base %.2f · pride +%.2f · stability %+.2f · tech +%.2f · engineers +%.2f[/color]"
			% [COLOR_MUTED, base, infra_bonus, stab, tech, eng_bonus]
		)
	else:
		var parts: PackedStringArray = ["base %.2f" % base, "pride +%.2f" % infra_bonus]
		if absf(stab) > 0.001:
			parts.append("stability %+.2f" % stab)
		if tech > 0.001:
			parts.append("technology +%.2f" % tech)
		if eng > 0.0:
			parts.append("engineers +%.2f (%.1f brg)" % [eng_bonus, eng])
		var total := float(bd.get("total", 0.0))
		lines.append(
			"%sContributions: %s  →  +%.2f/day total[/color]"
			% [COLOR_MUTED, " · ".join(parts), total]
		)
	if eng > 0.0 and detailed:
		var share := int(round(engineer_repair_share_percent(bd)))
		lines.append(
			"%s  Engineers: %.1f brg → +%.2f/day (%d%% of repair)[/color]" % [COLOR_TECH, eng, eng_bonus, share]
		)
	return "\n".join(lines)


const _MapPolishFormatters := preload("res://scripts/map/MapPolishFormatters.gd")
const _MapNextListHelpers := preload("res://scripts/map/MapNextListHelpers.gd")


## Live damage/sabotage state → pure classifier for map tint/marker (MapNextListHelpers).
static func build_map_damage_state(province: Province) -> Dictionary:
	if province == null:
		return {}
	var bd := _infra_repair_breakdown(province)
	var site_dmg := 0
	for site in province.special_sites:
		if site != null and site.is_damaged():
			site_dmg += 1
	var proj_sabo := false
	var mgr := _get_infra_mgr_for_insight()
	if mgr != null and mgr.has_method("is_project_sabotaged"):
		proj_sabo = mgr.is_project_sabotaged(province.id)
	return {
		"under_infra_sabotage": bool(bd.get("under_infra_sabotage", false)),
		"depot_sabotage_level": float(bd.get("depot_sabotage_level", 0.0)),
		"site_damaged_count": site_dmg,
		"project_sabotaged": proj_sabo,
		"agent_pressure_kind": agent_pressure_focus_kind(province),
		"infrastructure": int(bd.get("infrastructure", province.infrastructure)),
	}


static func classify_province_map_damage(province: Province) -> Dictionary:
	return _MapNextListHelpers.classify_map_damage(build_map_damage_state(province))


static func build_hh_map_signal_inspector_line() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("get_peace_state"):
		return ""
	var ps: Dictionary = GameData.get_peace_state()
	var sig: Dictionary = ps.get("hh_last_map_signal", {}) if ps is Dictionary else {}
	if sig.is_empty() or not bool(sig.get("active", false)):
		return ""
	return str(sig.get("inspector_line", sig.get("label", "")))


## Agenda screen layout pilot BBCode (Recent / By class sections).
static func build_hh_agenda_screen_inspector_bbcode(max_lines: int = 4) -> String:
	if typeof(GameData) == TYPE_NIL:
		return ""
	var plain := ""
	if GameData.has_method("format_hh_agenda_screen_plain"):
		plain = str(GameData.format_hh_agenda_screen_plain(max_lines)).strip_edges()
	if plain.is_empty():
		return ""
	var out: PackedStringArray = []
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		if t.begins_with("## "):
			out.append("%s── %s ──[/color]" % [COLOR_HEADER, t.substr(3)])
		else:
			out.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out)


## Agenda panel pilot BBCode (title + class count + trail lines).
static func build_hh_agenda_panel_inspector_bbcode(max_lines: int = 4) -> String:
	if typeof(GameData) == TYPE_NIL:
		return ""
	var plain := ""
	if GameData.has_method("format_hh_agenda_panel_plain"):
		plain = str(GameData.format_hh_agenda_panel_plain(max_lines)).strip_edges()
	elif GameData.has_method("format_hh_agenda_trail_plain"):
		plain = str(GameData.format_hh_agenda_trail_plain(max_lines)).strip_edges()
	if plain.is_empty():
		return ""
	var out_lines: PackedStringArray = []
	var first := true
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		if first:
			out_lines.append("%s── ◈ %s ──[/color]" % [COLOR_HEADER, t])
			first = false
		else:
			out_lines.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out_lines)


## Agenda action-pick pilot BBCode (from GameData trail; empty → "").
static func build_hh_agenda_actions_inspector_bbcode(max_actions: int = 3) -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("pick_hh_agenda_actions_plain"):
		return ""
	var plain := str(GameData.pick_hh_agenda_actions_plain(max_actions)).strip_edges()
	if plain.is_empty():
		return ""
	var out: PackedStringArray = []
	out.append("%s── Agenda actions ──[/color]" % COLOR_HEADER)
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		out.append("%s▶ %s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out)


## Agent mission priority pilot from last HH map signal.
static func build_agent_mission_priority_inspector_bbcode(province: Province) -> String:
	if province == null or typeof(GameData) == TYPE_NIL or not GameData.has_method("get_peace_state"):
		return ""
	var ps: Dictionary = GameData.get_peace_state()
	var sig: Dictionary = ps.get("hh_last_map_signal", {}) if ps is Dictionary else {}
	if sig.is_empty() or not bool(sig.get("active", false)):
		return ""
	var sig_pid := int(sig.get("province_id", -1))
	if sig_pid >= 0 and sig_pid != province.id:
		return ""
	var action := str(sig.get("action_class", "")).to_lower()
	if false:
		return ""
	var ranked: Dictionary = MapPolishFormatters.rank_agent_missions(action, 0.6, 0.35, 0.5, 4)
	if bool(ranked.get("empty", true)):
		return ""
	var out: PackedStringArray = []
	out.append("%s── Agent mission priority ──[/color]" % COLOR_HEADER)
	out.append("%s%s[/color]" % [COLOR_MUTED, str(ranked.get("summary", ""))])
	var missions: Array = ranked.get("missions", [])
	for m in missions:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		out.append(
			"%s◇ %s (%.0f)[/color]"
			% [COLOR_MUTED, str(m.get("mission", "")), float(m.get("score", 0.0))]
		)
	return "\n".join(out)


## Operator data-dir banner (world_full default play board clarity).
static func build_scenario_data_dir_banner_bbcode() -> String:
	var scenario := "world_full"
	if typeof(MapPolishFormatters) == TYPE_NIL:
		return ""
	if true:
		var line := str(MapPolishFormatters.format_scenario_data_dir_banner(scenario, ""))
		if line.is_empty():
			return ""
		return "%s%s[/color]" % [COLOR_MUTED, line]
	return ""


## Choke + basing synergy chip for naval-relevant provinces.
static func build_choke_basing_synergy_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	var is_choke := false
	if MapManager.has_method("has_strategic_chokepoint"):
		is_choke = MapManager.has_strategic_chokepoint(province.id)
	var basing: Dictionary = {}
	if MapManager.has_method("get_naval_basing"):
		basing = MapManager.get_naval_basing(province.id)
	var level := str(basing.get("level", "none"))
	if not is_choke and level == "none":
		return ""
	if false:
		return ""
	var score := float(
		MapPolishFormatters.choke_basing_synergy_score(
			is_choke, level, int(basing.get("capacity", 0))
		)
	)
	return (
		"%s⚓ Choke+basing[/color] %s— score %.0f · %s[/color]"
		% [COLOR_TECH if COLOR_TECH else "[color=#5ec8ff]", COLOR_MUTED, score, level]
	)


## Sealane supply/trade chip from friendly sea-zone multipliers.
static func build_sealane_route_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("get_sea_zone_control_for_province"):
		return ""
	var ctrl: Dictionary = MapManager.get_sea_zone_control_for_province(province.id)
	if ctrl.is_empty():
		return ""
	var tag := str(province.owner_tag).strip_edges().to_upper()
	if tag.is_empty():
		tag = "ENG"
	if typeof(MapPolishFormatters) == TYPE_NIL:
		return ""
	var fr: Dictionary = MapPolishFormatters.friendly_sea_zone_multipliers_from_dict(ctrl, tag)
	if not bool(fr.get("applies", false)):
		return ""
	var s := float(fr.get("supply_multiplier", 1.0))
	var t := float(fr.get("trade_multiplier", 1.0))
	var rel := str(fr.get("relation", "neutral"))
	return (
		"%s🌊 Sealanes[/color] %s— %s · supply ×%.2f · trade ×%.2f[/color]"
		% [COLOR_TECH if COLOR_TECH else "[color=#5ec8ff]", COLOR_MUTED, rel, s, t]
	)


## Convoy escort need chip for coastal/sea-zone provinces (uses MapManager pilot).
static func build_convoy_escort_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("plan_convoy_escort_for_path"):
		return ""
	var in_zone := false
	if MapManager.has_method("get_sea_zone_name"):
		in_zone = not str(MapManager.get_sea_zone_name(province.id)).strip_edges().is_empty()
	var coastal := false
	if MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		coastal = dom.begins_with("coast") or dom == "strait"
	if not in_zone and not coastal and not bool(province.is_sea):
		return ""
	var path: Array = [province.id]
	if MapManager.has_method("get_adjacent_provinces"):
		for ap in MapManager.get_adjacent_provinces(province.id):
			path.append(int(ap))
			if path.size() >= 4:
				break
	var plan: Dictionary = MapManager.plan_convoy_escort_for_path(
		path, 40.0, 100.0, str(province.owner_tag)
	)
	if plan.is_empty():
		return ""
	return (
		"%s🛡 Convoy escort[/color] %s— %s[/color]"
		% [COLOR_TECH if COLOR_TECH else "[color=#5ec8ff]", COLOR_MUTED, str(plan.get("summary", ""))]
	)


## Weather chip from WeatherManager (live surface). Pass 9: retrowave ground/storm icon prefix.
static func build_weather_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(WeatherManager) == TYPE_NIL:
		return ""
	var body := ""
	if WeatherManager.has_method("format_province_weather_chip_bbcode"):
		body = str(WeatherManager.format_province_weather_chip_bbcode(province.id)).strip_edges()
	elif WeatherManager.has_method("get_conditions_summary"):
		body = "%s🌤 %s[/color]" % [COLOR_MUTED, str(WeatherManager.get_conditions_summary(province.id))]
	if body.is_empty():
		return ""
	var img := _weather_chip_img_prefix(province)
	if img.is_empty():
		return body
	return "%s %s" % [img, body]


static func _weather_chip_img_prefix(province: Province) -> String:
	if province == null:
		return ""
	var ground := "dry"
	var precip := 0.0
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_province_weather"):
			var w: Variant = WeatherManager.call("get_province_weather", province.id)
			if w is Dictionary:
				ground = str(w.get("ground_state", "dry"))
				precip = float(w.get("precip_intensity", 0.0))
		elif WeatherManager.has_method("get_conditions_summary"):
			var summ := str(WeatherManager.get_conditions_summary(province.id)).to_lower()
			if "storm" in summ:
				ground = "storm"
			elif "snow" in summ or "ice" in summ or "frozen" in summ:
				ground = "snow"
			elif "mud" in summ:
				ground = "mud"
	var WxLib = load("res://scripts/ui/WeatherIconLibrary.gd")
	if WxLib == null:
		return ""
	var key: String = WxLib.key_from_weather(ground, precip)
	return str(WxLib.bbcode_img(key, 16))


## Fleet redeploy posture chip (MapManager + MapPolishFormatters).
static func build_fleet_posture_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("rank_fleet_posture_for_province"):
		return ""
	var coastal := false
	if MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		coastal = dom.begins_with("coast") or dom == "strait" or dom == "sea"
	if not coastal and not bool(province.is_sea):
		return ""
	var ranked: Dictionary = MapManager.rank_fleet_posture_for_province(province.id, 0.85, str(province.owner_tag))
	if ranked.is_empty() or bool(ranked.get("empty", false)):
		return ""
	return (
		"%s🚢 Fleet posture[/color] %s— %s[/color]"
		% [COLOR_TECH, COLOR_MUTED, str(ranked.get("summary", ""))]
	)


## HH monthly agenda pulse digest (empty trail → "").
static func build_hh_agenda_pulse_inspector_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_hh_agenda_pulse_plain"):
		return ""
	var plain := str(GameData.format_hh_agenda_pulse_plain()).strip_edges()
	if plain.is_empty():
		return ""
	var out: PackedStringArray = []
	out.append("%s── Hand pulse ──[/color]" % COLOR_HEADER)
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		out.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out)


## Agent network response pilot (mission deploy after HH signal).
static func build_agent_network_response_bbcode(province: Province) -> String:
	if province == null or typeof(GameData) == TYPE_NIL or not GameData.has_method("get_peace_state"):
		return ""
	var ps: Dictionary = GameData.get_peace_state()
	var sig: Dictionary = ps.get("hh_last_map_signal", {}) if ps is Dictionary else {}
	if sig.is_empty() or not bool(sig.get("active", false)):
		return ""
	if int(sig.get("province_id", -1)) >= 0 and int(sig.get("province_id", -1)) != province.id:
		return ""
	if false:
		return ""
	var ranked: Dictionary = MapPolishFormatters.rank_agent_missions(
		str(sig.get("action_class", "")), 0.65, 0.3, 0.5, 3
	)
	if bool(ranked.get("empty", true)):
		return ""
	return (
		"%s◎ Network response[/color] %s— %s[/color]"
		% [COLOR_HEADER, COLOR_MUTED, str(ranked.get("summary", ""))]
	)


## Season daylight chip (WeatherManager / MapPolishFormatters).
static func build_season_daylight_chip_bbcode() -> String:
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("format_season_daylight_chip_bbcode"):
		return str(WeatherManager.format_season_daylight_chip_bbcode()).strip_edges()
	var month := 1
	if typeof(TimeManager) != TYPE_NIL and "current_month" in TimeManager:
		month = int(TimeManager.current_month)
	var chip: Dictionary = MapPolishFormatters.format_season_daylight_chip(month)
	return str(chip.get("bbcode", "")).strip_edges()


## Next-day forecast chip.
static func build_forecast_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if WeatherManager.has_method("format_province_forecast_chip_bbcode"):
		return str(WeatherManager.format_province_forecast_chip_bbcode(province.id)).strip_edges()
	return ""


## Extreme event severity chip.
static func build_extreme_event_chip_bbcode() -> String:
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("format_extreme_event_chip_bbcode"):
		return str(WeatherManager.format_extreme_event_chip_bbcode()).strip_edges()
	return ""


## Weather legend surface (short header line).
static func build_weather_legend_chip_bbcode() -> String:
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("format_weather_legend_bbcode"):
		var full := str(WeatherManager.format_weather_legend_bbcode()).strip_edges()
		if full.is_empty():
			return ""
		# First line only for inspector density.
		var first := full.split("\n")[0]
		return first
	return ""


## Move cost with weather chip.
static func build_move_weather_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("estimate_move_cost_with_weather"):
		return ""
	var est: Dictionary = MapManager.estimate_move_cost_with_weather(province.id, 1.0, false)
	if est.is_empty():
		return ""
	return str(est.get("bbcode", "")).strip_edges()


## Storm convoy risk chip (coastal / sea).
static func build_storm_convoy_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if not bool(province.is_sea) and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		if not (dom.begins_with("coast") or dom == "strait" or dom == "sea"):
			return ""
	if WeatherManager.has_method("format_storm_convoy_risk_bbcode"):
		return str(WeatherManager.format_storm_convoy_risk_bbcode(province.id)).strip_edges()
	return ""


## Sea×weather supply combined chip for sea-zone provinces.
static func build_sea_weather_supply_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("get_sea_zone_control_for_province"):
		return ""
	var ctrl: Dictionary = MapManager.get_sea_zone_control_for_province(province.id)
	if ctrl.is_empty():
		return ""
	var tag := str(province.owner_tag)
	var sea := 1.0
	var fr: Dictionary = MapPolishFormatters.friendly_sea_zone_multipliers_from_dict(ctrl, tag)
	sea = float(fr.get("supply_multiplier", 1.0))
	var wx := 1.0
	if WeatherManager.has_method("get_supply_weather_multiplier"):
		wx = float(WeatherManager.get_supply_weather_multiplier(province.id))
	var comb: Dictionary = MapPolishFormatters.sea_weather_supply_combined(sea, wx)
	return (
		"%s⚓ Sea×weather[/color] %s— %s[/color]"
		% [COLOR_TECH, COLOR_MUTED, str(comb.get("summary", ""))]
	)


## Fleet theater posture chip (samples nearby coastal ids when available).
static func build_fleet_theater_posture_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("plan_fleet_theater_posture_for_ids"):
		return ""
	var coastal := false
	if MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		coastal = dom.begins_with("coast") or dom == "strait" or dom == "sea"
	if not coastal and not bool(province.is_sea):
		return ""
	var plan: Dictionary = MapManager.plan_fleet_theater_posture_for_ids(
		[province.id], 0.85, str(province.owner_tag)
	)
	if plan.is_empty() or bool(plan.get("empty", false)):
		return ""
	return (
		"%s🚢 Theater fleet[/color] %s— %s[/color]"
		% [COLOR_TECH, COLOR_MUTED, str(plan.get("summary", ""))]
	)


## Weather-aware combat phase ribbon chip.
static func build_weather_phase_ribbon_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(BattleManager) == TYPE_NIL or not BattleManager.has_method("build_weather_phase_ribbon"):
		return ""
	var ribbon: Dictionary = BattleManager.build_weather_phase_ribbon(100.0, 80.0, province.id)
	if ribbon.is_empty() or bool(ribbon.get("empty", false)):
		return ""
	return str(ribbon.get("bbcode", ribbon.get("plain", ""))).strip_edges()


## HH pulse+actions combined digest (empty trail → "").
static func build_hh_pulse_actions_inspector_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_hh_pulse_actions_plain"):
		return ""
	var plain := str(GameData.format_hh_pulse_actions_plain()).strip_edges()
	if plain.is_empty():
		return ""
	var out: PackedStringArray = []
	out.append("%s── Hand pulse+actions ──[/color]" % COLOR_HEADER)
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		out.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out)


## Agent network deploy plan chip (missions → deploy counts).
static func build_agent_network_deploy_bbcode(province: Province) -> String:
	if province == null or typeof(GameData) == TYPE_NIL or not GameData.has_method("get_peace_state"):
		return ""
	var ps: Dictionary = GameData.get_peace_state()
	var sig: Dictionary = ps.get("hh_last_map_signal", {}) if ps is Dictionary else {}
	if sig.is_empty() or not bool(sig.get("active", false)):
		return ""
	if int(sig.get("province_id", -1)) >= 0 and int(sig.get("province_id", -1)) != province.id:
		return ""
	var plan: Dictionary = MapPolishFormatters.format_network_deploy_plan(
		str(sig.get("action_class", "influence")),
		float(sig.get("influence", 0.55)),
		0.3,
		3,
		0.5,
	)
	if bool(plan.get("empty", true)):
		return ""
	return str(plan.get("bbcode", "")).strip_edges()


static func build_fleet_redeploy_route_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("plan_fleet_redeploy_routes_from"):
		return ""
	var coastal := bool(province.is_sea)
	if not coastal and MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		coastal = dom.begins_with("coast") or dom == "strait" or dom == "sea"
	if not coastal:
		return ""
	# Single-dest self-route still exercises ranking with origin basing.
	var plan: Dictionary = MapManager.plan_fleet_redeploy_routes_from(
		province.id, [province.id], 0.85, str(province.owner_tag)
	)
	if plan.is_empty() or bool(plan.get("empty", false)):
		return ""
	return (
		"%s🚢 Redeploy route[/color] %s— %s[/color]"
		% [COLOR_TECH, COLOR_MUTED, str(plan.get("summary", ""))]
	)


static func build_weather_combat_briefing_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(BattleManager) == TYPE_NIL or not BattleManager.has_method("build_weather_combat_briefing"):
		return ""
	var brief: Dictionary = BattleManager.build_weather_combat_briefing(
		100.0, 80.0, province.id, 1.0, str(province.name)
	)
	if brief.is_empty() or bool(brief.get("empty", false)):
		return ""
	return str(brief.get("bbcode", brief.get("headline", ""))).strip_edges()


static func build_hh_monthly_brief_inspector_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_hh_monthly_brief_plain"):
		return ""
	var plain := str(GameData.format_hh_monthly_brief_plain()).strip_edges()
	if plain.is_empty():
		return ""
	var out: PackedStringArray = []
	out.append("%s── Monthly Hand brief ──[/color]" % COLOR_HEADER)
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		out.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out)


static func build_agent_coverage_chip_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_agent_coverage_plan_plain"):
		return ""
	var plain := str(GameData.format_agent_coverage_plan_plain(5)).strip_edges()
	if plain.is_empty():
		return ""
	return "%s◎ Coverage[/color] %s— %s[/color]" % [COLOR_HEADER, COLOR_MUTED, plain]


static func build_inspector_weather_ops_section_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if WeatherManager.has_method("format_inspector_weather_section_bbcode"):
		return str(WeatherManager.format_inspector_weather_section_bbcode(province.id)).strip_edges()
	return ""


static func build_weather_pressure_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if WeatherManager.has_method("format_weather_pressure_chip_bbcode"):
		return str(WeatherManager.format_weather_pressure_chip_bbcode(province.id)).strip_edges()
	return ""


static func build_naval_wx_tip_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if not bool(province.is_sea) and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		if not (dom.begins_with("coast") or dom == "strait" or dom == "sea"):
			return ""
	if WeatherManager.has_method("format_naval_engagement_weather_tip_bbcode"):
		return str(WeatherManager.format_naval_engagement_weather_tip_bbcode(province.id)).strip_edges()
	return ""


static func build_air_grounding_alert_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if WeatherManager.has_method("format_air_grounding_alert_bbcode"):
		return str(WeatherManager.format_air_grounding_alert_bbcode(province.id)).strip_edges()
	return ""


static func build_freeze_thaw_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if WeatherManager.has_method("format_freeze_thaw_chip_bbcode"):
		return str(WeatherManager.format_freeze_thaw_chip_bbcode(province.id)).strip_edges()
	return ""


static func build_infra_weather_wear_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if WeatherManager.has_method("format_infra_weather_wear_bbcode"):
		return str(WeatherManager.format_infra_weather_wear_bbcode(province.id)).strip_edges()
	return ""


static func build_coastal_fog_gate_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if not bool(province.is_sea) and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		if not (dom.begins_with("coast") or dom == "strait" or dom == "sea"):
			return ""
	if WeatherManager.has_method("format_coastal_fog_gate_bbcode"):
		return str(WeatherManager.format_coastal_fog_gate_bbcode(province.id)).strip_edges()
	return ""


static func build_joint_focus_agent_chip_bbcode() -> String:
	var focus: Array = [{"id": "industrial_effort", "score": 70.0}]
	var missions: Array = [{"mission": "counterintel", "score": 85.0}, {"mission": "propaganda", "score": 40.0}]
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_peace_state"):
		var ps: Dictionary = GameData.get_peace_state()
		var sig: Dictionary = ps.get("hh_last_map_signal", {}) if ps is Dictionary else {}
		if not sig.is_empty() and bool(sig.get("active", false)):
			missions = [{"mission": str(sig.get("action_class", "counterintel")) + "_defense", "score": 90.0}]
	var board: Dictionary = MapPolishFormatters.joint_focus_agent_priority(focus, missions, 3)
	if bool(board.get("empty", true)):
		return ""
	return str(board.get("bbcode", "")).strip_edges()


static func build_supply_route_weather_rank_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	var path_wx: Array = [{
		"province_id": province.id,
		"ground_state": "dry",
		"precip_intensity": 0.0,
	}]
	if WeatherManager.has_method("get_supply_weather_multiplier"):
		var sm := float(WeatherManager.get_supply_weather_multiplier(province.id))
		path_wx[0]["precip_intensity"] = clampf((1.0 - sm) * 2.0, 0.0, 1.0)
		if sm < 0.75:
			path_wx[0]["ground_state"] = "mud"
	var ranked: Dictionary = MapPolishFormatters.rank_supply_route_weather_risk(path_wx)
	if bool(ranked.get("empty", true)):
		return ""
	return str(ranked.get("bbcode", ranked.get("summary", ""))).strip_edges()


static func build_fleet_task_group_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("compose_fleet_task_group_for_province"):
		return ""
	var coastal := bool(province.is_sea)
	if not coastal and MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		coastal = dom.begins_with("coast") or dom == "strait" or dom == "sea"
	if not coastal:
		return ""
	var tg: Dictionary = MapManager.compose_fleet_task_group_for_province(
		province.id, 100.0, "patrol", str(province.owner_tag)
	)
	if tg.is_empty() or bool(tg.get("empty", false)):
		return ""
	return str(tg.get("bbcode", tg.get("summary", ""))).strip_edges()


static func build_multi_front_assault_chip_bbcode(province: Province) -> String:
	if province == null or typeof(BattleManager) == TYPE_NIL:
		return ""
	if not BattleManager.has_method("rank_multi_front_assault_targets"):
		return ""
	var targets: Array = [
		{"province_id": province.id, "defender_power": 80.0},
		{"province_id": province.id + 1, "defender_power": 120.0},
	]
	var ranked: Dictionary = BattleManager.rank_multi_front_assault_targets(targets, 100.0, 1.0)
	if ranked.is_empty() or bool(ranked.get("empty", false)):
		return ""
	return str(ranked.get("bbcode", ranked.get("summary", ""))).strip_edges()


static func build_hh_quarterly_rollup_inspector_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_hh_quarterly_rollup_plain"):
		return ""
	var plain := str(GameData.format_hh_quarterly_rollup_plain()).strip_edges()
	if plain.is_empty():
		return ""
	var out: PackedStringArray = []
	out.append("%s── Quarterly Hand ──[/color]" % COLOR_HEADER)
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		out.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out)


static func build_agent_escalation_chip_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_agent_escalation_ladder_plain"):
		return ""
	var plain := str(GameData.format_agent_escalation_ladder_plain()).strip_edges()
	if plain.is_empty():
		return ""
	return "%s◎ Escalation[/color] %s— %s[/color]" % [COLOR_HEADER, COLOR_MUTED, plain]


static func build_campaign_day_risk_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if WeatherManager.has_method("format_campaign_day_risk_bbcode"):
		return str(WeatherManager.format_campaign_day_risk_bbcode(province.id)).strip_edges()
	return ""


static func build_convoy_weather_window_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if not bool(province.is_sea) and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		if not (dom.begins_with("coast") or dom == "strait" or dom == "sea"):
			return ""
	if WeatherManager.has_method("format_convoy_weather_window_bbcode"):
		return str(WeatherManager.format_convoy_weather_window_bbcode(province.id)).strip_edges()
	return ""


static func build_production_weather_alert_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if WeatherManager.has_method("format_production_weather_alert_bbcode"):
		return str(WeatherManager.format_production_weather_alert_bbcode(province.id)).strip_edges()
	return ""


static func build_sea_naval_weather_ops_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("get_sea_zone_control_for_province"):
		return ""
	var ctrl: Dictionary = MapManager.get_sea_zone_control_for_province(province.id)
	if ctrl.is_empty():
		return ""
	var sea := 1.0
	var fr: Dictionary = MapPolishFormatters.friendly_sea_zone_multipliers_from_dict(ctrl, str(province.owner_tag))
	sea = float(fr.get("supply_multiplier", 1.0))
	if WeatherManager.has_method("format_sea_naval_weather_ops_bbcode"):
		return str(WeatherManager.format_sea_naval_weather_ops_bbcode(province.id, sea)).strip_edges()
	return ""


static func build_combat_morale_weather_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if not WeatherManager.has_method("get_combat_morale_weather_mult"):
		return ""
	var m := float(WeatherManager.get_combat_morale_weather_mult(province.id))
	return "%s🛡 Morale wx[/color] %s— ×%.2f[/color]" % [COLOR_HEADER, COLOR_MUTED, m]


static func build_depot_weather_capacity_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	if not WeatherManager.has_method("get_depot_weather_capacity"):
		return ""
	var dep: Dictionary = WeatherManager.get_depot_weather_capacity(province.id, 100.0)
	return str(dep.get("bbcode", dep.get("summary", ""))).strip_edges()


static func build_daylight_combat_mod_chip_bbcode() -> String:
	if typeof(WeatherManager) == TYPE_NIL:
		return ""
	if WeatherManager.has_method("format_daylight_combat_mod_bbcode"):
		return str(WeatherManager.format_daylight_combat_mod_bbcode()).strip_edges()
	return ""


static func build_choke_weather_synergy_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL or typeof(MapManager) == TYPE_NIL:
		return ""
	var is_choke := false
	if MapManager.has_method("has_strategic_chokepoint"):
		is_choke = bool(MapManager.has_strategic_chokepoint(province.id))
	if not is_choke:
		return ""
	if WeatherManager.has_method("format_choke_weather_synergy_bbcode"):
		return str(WeatherManager.format_choke_weather_synergy_bbcode(province.id, true, true)).strip_edges()
	return ""


static func build_focus_weather_aware_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	var wvis := 1.0
	var wprec := 0.0
	var g := "dry"
	# Use pressure via formatter with province weather if available through WM production mult proxy
	if WeatherManager.has_method("get_combat_weather_multiplier"):
		wvis = float(WeatherManager.get_combat_weather_multiplier(province.id))
	var scored: Dictionary = MapPolishFormatters.focus_weather_aware_score(50.0, "industrial_effort", wvis, wprec, g)
	return str(scored.get("bbcode", "")).strip_edges()


static func build_ops_dashboard_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var summaries: Array = []
	var day := build_campaign_day_risk_chip_bbcode(province)
	if not day.is_empty():
		summaries.append(day)
	var tg := build_fleet_task_group_chip_bbcode(province)
	if not tg.is_empty():
		summaries.append(tg)
	var front := build_multi_front_assault_chip_bbcode(province)
	if not front.is_empty():
		summaries.append(front)
	var esc := build_agent_escalation_chip_bbcode()
	if not esc.is_empty():
		summaries.append(esc)
	var dash: Dictionary = MapPolishFormatters.format_ops_dashboard(summaries)
	if bool(dash.get("empty", true)):
		return ""
	return str(dash.get("bbcode", "")).strip_edges()


static func build_fleet_weather_package_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("fleet_weather_mission_package_for_province"):
		return ""
	var coastal := bool(province.is_sea)
	if not coastal and MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		coastal = dom.begins_with("coast") or dom == "strait" or dom == "sea"
	if not coastal:
		return ""
	var pkg: Dictionary = MapManager.fleet_weather_mission_package_for_province(
		province.id, "strike", 100.0, str(province.owner_tag)
	)
	if pkg.is_empty() or bool(pkg.get("empty", false)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", ""))).strip_edges()


static func build_assault_readiness_chip_bbcode(province: Province) -> String:
	if province == null or typeof(BattleManager) == TYPE_NIL:
		return ""
	if not BattleManager.has_method("build_assault_readiness_compose"):
		return ""
	var targets: Array = [{"province_id": province.id, "defender_power": 80.0}]
	var ready: Dictionary = BattleManager.build_assault_readiness_compose(targets, 100.0, 1.0, province.id)
	if ready.is_empty() or bool(ready.get("empty", false)):
		return ""
	return str(ready.get("bbcode", ready.get("summary", ""))).strip_edges()


static func build_counter_ops_chip_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_counter_ops_board_plain"):
		return ""
	var plain := str(GameData.format_counter_ops_board_plain()).strip_edges()
	if plain.is_empty():
		return ""
	return "%s◎ Counter-ops[/color] %s— %s[/color]" % [COLOR_HEADER, COLOR_MUTED, plain]


static func build_hh_agenda_commits_chip_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_hh_agenda_commitments_plain"):
		return ""
	var plain := str(GameData.format_hh_agenda_commitments_plain()).strip_edges()
	if plain.is_empty():
		return ""
	var out: PackedStringArray = []
	out.append("%s── Agenda commits ──[/color]" % COLOR_HEADER)
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		out.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out)


static func build_choke_sea_weather_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("choke_sea_weather_package_for_province"):
		return ""
	var pkg: Dictionary = MapManager.choke_sea_weather_package_for_province(province.id, str(province.owner_tag))
	if pkg.is_empty() or bool(pkg.get("empty", false)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", ""))).strip_edges()


static func build_trade_chain_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var sea := 1.0
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_sea_zone_control_for_province"):
		var ctrl: Dictionary = MapManager.get_sea_zone_control_for_province(province.id)
		if not ctrl.is_empty():
			var fr: Dictionary = MapPolishFormatters.friendly_sea_zone_multipliers_from_dict(ctrl, str(province.owner_tag))
			sea = float(fr.get("trade_multiplier", fr.get("supply_multiplier", 1.0)))
	var precip := 0.0
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_trade_weather_multiplier"):
		var tw := float(WeatherManager.get_trade_weather_multiplier(province.id))
		precip = clampf(1.0 - tw, 0.0, 1.0)
	var chain: Dictionary = MapPolishFormatters.trade_supply_weather_chain(sea, "dry", precip, 0.0)
	return str(chain.get("bbcode", "")).strip_edges()


static func build_factory_risk_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	var temp := 10.0
	var precip := 0.0
	var ground := "dry"
	var vis := 1.0
	if WeatherManager.has_method("get_production_weather_multiplier"):
		var pm := float(WeatherManager.get_production_weather_multiplier(province.id))
		precip = clampf((1.0 - pm) * 2.0, 0.0, 1.0)
		if pm < 0.85:
			temp = -18.0
	if WeatherManager.has_method("get_combat_weather_multiplier"):
		vis = float(WeatherManager.get_combat_weather_multiplier(province.id))
	var risk: Dictionary = MapPolishFormatters.factory_risk_compose(temp, precip, ground, vis, 0.2)
	return str(risk.get("bbcode", "")).strip_edges()


static func build_supply_chain_health_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var sea := 1.0
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_sea_zone_control_for_province"):
		var ctrl: Dictionary = MapManager.get_sea_zone_control_for_province(province.id)
		if not ctrl.is_empty():
			var fr: Dictionary = MapPolishFormatters.friendly_sea_zone_multipliers_from_dict(ctrl, str(province.owner_tag))
			sea = float(fr.get("supply_multiplier", 1.0))
	var ground := "dry"
	var precip := 0.0
	var vis := 1.0
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_supply_weather_multiplier"):
			var sm := float(WeatherManager.get_supply_weather_multiplier(province.id))
			precip = clampf((1.0 - sm) * 2.0, 0.0, 1.0)
			if sm < 0.75:
				ground = "mud"
		if WeatherManager.has_method("get_naval_spot_weather_multiplier"):
			vis = float(WeatherManager.get_naval_spot_weather_multiplier(province.id))
	var chain: Dictionary = MapPolishFormatters.supply_chain_health_compose(100.0, sea, ground, precip, vis, 0.0)
	return str(chain.get("bbcode", "")).strip_edges()


static func build_air_ops_package_chip_bbcode(province: Province) -> String:
	if province == null or typeof(WeatherManager) == TYPE_NIL:
		return ""
	var vis := 1.0
	var precip := 0.0
	if WeatherManager.has_method("get_air_sortie_weather_eff"):
		vis = float(WeatherManager.get_air_sortie_weather_eff(province.id))
		precip = clampf(1.0 - vis, 0.0, 1.0)
	var month := 1
	if typeof(TimeManager) != TYPE_NIL and "current_month" in TimeManager:
		month = int(TimeManager.current_month)
	var pkg: Dictionary = MapPolishFormatters.air_ops_package(vis, precip, 0.2, month)
	return str(pkg.get("bbcode", "")).strip_edges()


## Air-ops day package chip (live WeatherManager → MapPolishFormatters.air_ops_day_package).
static func build_air_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_ops_day_for_province"):
		var day: Dictionary = MapManager.air_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	var vis := 1.0
	var precip := 0.0
	var month := 6
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_air_sortie_weather_eff"):
			vis = float(WeatherManager.get_air_sortie_weather_eff(province.id))
			precip = clampf(1.0 - vis, 0.0, 1.0)
		elif WeatherManager.has_method("get_combat_weather_multiplier"):
			vis = float(WeatherManager.get_combat_weather_multiplier(province.id))
			precip = clampf(1.0 - vis, 0.0, 1.0)
	if typeof(TimeManager) != TYPE_NIL and "current_month" in TimeManager:
		month = int(TimeManager.current_month)
	var pkg: Dictionary = MapPolishFormatters.air_ops_day_package(vis, precip, 0.2, month)
	return str(pkg.get("bbcode", pkg.get("summary", ""))).strip_edges()


## Forecast planning day chip (live weather → MapPolishFormatters.weather_forecast_planning_day).
static func build_forecast_planning_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_forecast_planning_day_for_province"):
		var day: Dictionary = MapManager.weather_forecast_planning_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	var vis := 1.0
	var precip := 0.0
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_combat_weather_multiplier"):
			vis = float(WeatherManager.get_combat_weather_multiplier(province.id))
			precip = clampf(1.0 - vis, 0.0, 1.0)
		if WeatherManager.has_method("get_supply_weather_multiplier"):
			var sm := float(WeatherManager.get_supply_weather_multiplier(province.id))
			precip = maxf(precip, clampf((1.0 - sm) * 2.0, 0.0, 1.0))
	var pkg: Dictionary = MapPolishFormatters.weather_forecast_planning_day(10.0, precip, vis, 0.2, "dry")
	return str(pkg.get("bbcode", pkg.get("summary", ""))).strip_edges()


## Naval interdiction day chip (live MapManager → MapPolishFormatters.naval_interdiction_day).
static func build_naval_interdiction_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_interdiction_day_for_province"):
		var day: Dictionary = MapManager.naval_interdiction_day_for_province(province.id, 80.0)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Joint command day chip (compose naval + intel + air + logistics).
static func build_joint_command_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_command_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.joint_command_day_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Order execute day chip (queue drain budget).
static func build_order_execute_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_execute_day_for_province"):
		var day: Dictionary = MapManager.order_execute_day_for_province(province.id, 3)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Strategic continuity day chip (orders + focus + next-day feedback).
static func build_strategic_continuity_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_continuity_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.strategic_continuity_day_for_tag(tag, province.id, 3)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Force posture day chip.
static func build_force_posture_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_posture_day_for_province"):
		var day: Dictionary = MapManager.force_posture_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Force readiness day chip.
static func build_force_readiness_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_readiness_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.force_readiness_day_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Production surge day chip.
static func build_production_surge_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_surge_day_for_province"):
		var day: Dictionary = MapManager.production_surge_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Industry surge day chip.
static func build_industry_surge_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("industry_surge_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.industry_surge_day_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Naval campaign day chip.
static func build_naval_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_campaign_day_for_province"):
		var day: Dictionary = MapManager.naval_campaign_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Joint campaign day chip.
static func build_joint_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_campaign_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.joint_campaign_day_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Fog/air crisis day chip.
static func build_fog_air_crisis_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fog_air_crisis_day_for_province"):
		var day: Dictionary = MapManager.fog_air_crisis_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Weather crisis day chip.
static func build_weather_crisis_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_day_for_province"):
		var day: Dictionary = MapManager.weather_crisis_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Agent response day chip.
static func build_agent_response_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_response_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.agent_response_day_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Agent campaign day chip.
static func build_agent_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_campaign_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.agent_campaign_day_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Combat ops day chip.
static func build_combat_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_ops_day_for_province"):
		var day: Dictionary = MapManager.combat_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Combat campaign day chip.
static func build_combat_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_campaign_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.combat_campaign_day_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Fleet redeploy day chip.
static func build_fleet_redeploy_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_redeploy_day_for_province"):
		var day: Dictionary = MapManager.fleet_redeploy_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Fleet campaign day chip.
static func build_fleet_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_campaign_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.fleet_campaign_day_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Naval campaign skim chip (Top 5 #3).
static func build_naval_campaign_skim_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_campaign_skim_for_province"):
		var day: Dictionary = MapManager.naval_campaign_skim_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## HH player path chip (Top 5 #4).
static func build_hh_player_path_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_agenda_player_path_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.hh_agenda_player_path_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Resource/damage operational skim chip.
static func build_resource_damage_skim_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("resource_damage_skim_for_province"):
		var day: Dictionary = MapManager.resource_damage_skim_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Sealane contest skim chip.
static func build_sealane_contest_skim_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sealane_contest_skim_for_province"):
		var day: Dictionary = MapManager.sealane_contest_skim_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Infra/special-site consistency chip.
static func build_infra_site_consistency_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("infra_site_consistency_skim_for_province"):
		var day: Dictionary = MapManager.infra_site_consistency_skim_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## HH agenda screen day chip.
static func build_hh_agenda_screen_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_agenda_screen_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.hh_agenda_screen_day_for_tag(tag, province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Fleet autonomy day chip.
static func build_fleet_autonomy_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_autonomy_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.fleet_autonomy_day_for_tag(tag, 0.65, 3)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Sealane contest visual chip.
static func build_sealane_contest_visual_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sealane_contest_visual_for_province"):
		var day: Dictionary = MapManager.sealane_contest_visual_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Next-10 depth chips.
static func build_multi_phase_combat_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_phase_combat_day_for_province"):
		var day: Dictionary = MapManager.multi_phase_combat_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_combat_air_naval_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_air_naval_day_for_province"):
		var day: Dictionary = MapManager.combat_air_naval_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_agent_auto_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_auto_day_live"):
		var day: Dictionary = MapManager.agent_auto_day_live(province.id, 3)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_focus_pick_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_pick_day_live"):
		var day: Dictionary = MapManager.focus_pick_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_production_priority_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_priority_day_for_province"):
		var day: Dictionary = MapManager.production_priority_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_convoy_escort_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_escort_day_for_province"):
		var day: Dictionary = MapManager.convoy_escort_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_next_day_feedback_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("next_day_feedback_day_live"):
		var day: Dictionary = MapManager.next_day_feedback_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_map_effect_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("map_effect_day_for_province"):
		var day: Dictionary = MapManager.map_effect_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_theater_brief_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_brief_day_for_province"):
		var day: Dictionary = MapManager.theater_brief_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_campaign_decision_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_decision_day_live"):
		var day: Dictionary = MapManager.campaign_decision_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Next-20 priority depth chips.
static func build_order_panel_ux_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_panel_ux_day_live"):
		var day: Dictionary = MapManager.order_panel_ux_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_multi_phase_combat_ui_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_phase_combat_ui_day_for_province"):
		var day: Dictionary = MapManager.multi_phase_combat_ui_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_fleet_ai_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_ai_ops_day_for_tag"):
		var tag := str(province.owner_tag)
		var day: Dictionary = MapManager.fleet_ai_ops_day_for_tag(tag, 0.7)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_hh_agenda_package_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_agenda_package_day_live"):
		var day: Dictionary = MapManager.hh_agenda_package_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_agent_campaign_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_campaign_depth_day_live"):
		var day: Dictionary = MapManager.agent_campaign_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_industry_economy_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("industry_economy_day_for_province"):
		var day: Dictionary = MapManager.industry_economy_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_save_slot_browser_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_slot_browser_day_live"):
		var day: Dictionary = MapManager.save_slot_browser_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_basing_logistics_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_logistics_day_for_province"):
		var day: Dictionary = MapManager.basing_logistics_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_assault_follow_on_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_follow_on_day_for_province"):
		var day: Dictionary = MapManager.assault_follow_on_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_joint_ops_loop_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_ops_loop_day_for_province"):
		var day: Dictionary = MapManager.joint_ops_loop_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Next-30 theater surface chips.
static func build_war_cabinet_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_cabinet_day_live"):
		var day: Dictionary = MapManager.war_cabinet_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_supply_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("supply_campaign_day_for_province"):
		var day: Dictionary = MapManager.supply_campaign_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_force_supply_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_supply_day_for_province"):
		var day: Dictionary = MapManager.force_supply_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_counter_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("counter_ops_day_live"):
		var day: Dictionary = MapManager.counter_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_multi_province_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_province_live_day_for_tag"):
		var day: Dictionary = MapManager.multi_province_live_day_for_tag(str(province.owner_tag), province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_order_queue_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_queue_day_live"):
		var day: Dictionary = MapManager.order_queue_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_agent_ai_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_ai_board_day_live"):
		var day: Dictionary = MapManager.agent_ai_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_fleet_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_order_day_for_province"):
		var day: Dictionary = MapManager.fleet_order_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_fleet_theater_posture_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_theater_posture_day_for_tag"):
		var day: Dictionary = MapManager.fleet_theater_posture_day_for_tag(str(province.owner_tag), 0.7)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_campaign_risk_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_risk_day_for_province"):
		var day: Dictionary = MapManager.campaign_risk_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Next-40 campaign surface chips.
static func build_sealane_health_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sealane_health_day_for_province"):
		var day: Dictionary = MapManager.sealane_health_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_convoy_package_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_package_day_for_province"):
		var day: Dictionary = MapManager.convoy_package_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_theater_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_campaign_day_for_province"):
		var day: Dictionary = MapManager.theater_campaign_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_production_risk_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_risk_day_for_province"):
		var day: Dictionary = MapManager.production_risk_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_leader_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_campaign_day_for_province"):
		var day: Dictionary = MapManager.leader_campaign_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_basing_repair_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_repair_day_for_province"):
		var day: Dictionary = MapManager.basing_repair_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_focus_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_order_day_live"):
		var day: Dictionary = MapManager.focus_order_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_naval_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_order_day_for_province"):
		var day: Dictionary = MapManager.naval_order_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_air_land_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_land_order_day_for_province"):
		var day: Dictionary = MapManager.air_land_order_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_theater_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_order_day_for_province"):
		var day: Dictionary = MapManager.theater_order_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


## Next-50 ops/mutation chips.
static func build_factory_risk_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("factory_risk_day_for_province"):
		var day: Dictionary = MapManager.factory_risk_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_trade_chain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("trade_chain_day_for_province"):
		var day: Dictionary = MapManager.trade_chain_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_war_path_urgency_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_path_urgency_day_live"):
		var day: Dictionary = MapManager.war_path_urgency_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_combat_morale_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_morale_day_for_province"):
		var day: Dictionary = MapManager.combat_morale_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_choke_sea_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("choke_sea_day_for_province"):
		var day: Dictionary = MapManager.choke_sea_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_redeploy_route_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("redeploy_route_day_for_province"):
		var day: Dictionary = MapManager.redeploy_route_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_theater_report_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_report_day_for_province"):
		var day: Dictionary = MapManager.theater_report_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_best_station_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("best_station_day_for_province"):
		var day: Dictionary = MapManager.best_station_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_best_assault_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("best_assault_day_for_province"):
		var day: Dictionary = MapManager.best_assault_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_theater_mutation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_mutation_day_for_province"):
		var day: Dictionary = MapManager.theater_mutation_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""



## Next-60 command depth chips.

static func build_air_ops_sortie_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_ops_sortie_day_for_province"):
		var day: Dictionary = MapManager.air_ops_sortie_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_escalation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_escalation_day_live"):
		var day: Dictionary = MapManager.agent_escalation_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_coverage_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_coverage_day_live"):
		var day: Dictionary = MapManager.agent_coverage_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_order_day_for_province"):
		var day: Dictionary = MapManager.combat_order_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_order_day_for_province"):
		var day: Dictionary = MapManager.production_order_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_supply_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("supply_order_day_for_province"):
		var day: Dictionary = MapManager.supply_order_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_phase_strip_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_phase_strip_day_for_province"):
		var day: Dictionary = MapManager.combat_phase_strip_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_patrol_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_patrol_day_for_province"):
		var day: Dictionary = MapManager.fleet_patrol_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_execute_one_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("execute_one_day_live"):
		var day: Dictionary = MapManager.execute_one_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_fleet_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_fleet_plan_day_for_province"):
		var day: Dictionary = MapManager.daily_fleet_plan_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_combat_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_combat_plan_day_for_province"):
		var day: Dictionary = MapManager.daily_combat_plan_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_prod_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_prod_plan_day_for_province"):
		var day: Dictionary = MapManager.daily_prod_plan_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_agent_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_agent_plan_day_live"):
		var day: Dictionary = MapManager.daily_agent_plan_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_supply_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_supply_plan_day_for_province"):
		var day: Dictionary = MapManager.daily_supply_plan_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_dispatch_mutation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_dispatch_mutation_day_live"):
		var day: Dictionary = MapManager.agent_dispatch_mutation_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_station_mutation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_station_mutation_day_for_province"):
		var day: Dictionary = MapManager.fleet_station_mutation_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_stage_mutation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_stage_mutation_day_for_province"):
		var day: Dictionary = MapManager.assault_stage_mutation_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_task_mutation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_task_mutation_day_for_province"):
		var day: Dictionary = MapManager.naval_task_mutation_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_land_stage_mutation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_land_stage_mutation_day_for_province"):
		var day: Dictionary = MapManager.air_land_stage_mutation_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_monthly_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_monthly_day_live"):
		var day: Dictionary = MapManager.hh_monthly_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

## When false (default), inspector skips hundreds of product-depth day chips.
## Those chips were eagerly evaluated on every province select and some paths
## (e.g. apply_queue audit) *mutated* game state — freezing interactive play.
## Enable only for headless harness / deep debug: set true temporarily.
static var enable_product_depth_chips_in_inspector: bool = false


## Collect product-depth day chips and append only the priority budget.
static func _append_budgeted_product_depth_chips(lines: PackedStringArray, province: Province) -> void:
	if province == null:
		return
	# Interactive path: skip (see enable_product_depth_chips_in_inspector).
	if not enable_product_depth_chips_in_inspector:
		return
	var candidates: Array = []
	var pairs: Array = [
		["air_ops_day", build_air_ops_day_chip_bbcode(province)],
		["forecast_day", build_forecast_planning_day_chip_bbcode(province)],
		["naval_interdiction_day", build_naval_interdiction_day_chip_bbcode(province)],
		["joint_command_day", build_joint_command_day_chip_bbcode(province)],
		["order_execute_day", build_order_execute_day_chip_bbcode(province)],
		["strategic_continuity_day", build_strategic_continuity_day_chip_bbcode(province)],
		["force_posture_day", build_force_posture_day_chip_bbcode(province)],
		["force_readiness_day", build_force_readiness_day_chip_bbcode(province)],
		["production_surge_day", build_production_surge_day_chip_bbcode(province)],
		["industry_surge_day", build_industry_surge_day_chip_bbcode(province)],
		["naval_campaign_day", build_naval_campaign_day_chip_bbcode(province)],
		["joint_campaign_day", build_joint_campaign_day_chip_bbcode(province)],
		["fog_air_crisis_day", build_fog_air_crisis_day_chip_bbcode(province)],
		["weather_crisis_day", build_weather_crisis_day_chip_bbcode(province)],
		["agent_response_day", build_agent_response_day_chip_bbcode(province)],
		["agent_campaign_day", build_agent_campaign_day_chip_bbcode(province)],
		["combat_ops_day", build_combat_ops_day_chip_bbcode(province)],
		["combat_campaign_day", build_combat_campaign_day_chip_bbcode(province)],
		["fleet_redeploy_day", build_fleet_redeploy_day_chip_bbcode(province)],
		["fleet_campaign_day", build_fleet_campaign_day_chip_bbcode(province)],
		["naval_skim", build_naval_campaign_skim_chip_bbcode(province)],
		["hh_player_path", build_hh_player_path_chip_bbcode(province)],
		["war_cabinet", build_war_cabinet_chip_bbcode()],
		["campaign_strip", build_campaign_strip_chip_bbcode(province)],
		["convoy_pkg", build_convoy_package_chip_bbcode(province)],
		["theater_ready", build_theater_readiness_chip_bbcode(province)],
		["multi_phase_combat_day", build_multi_phase_combat_day_chip_bbcode(province)],
		["combat_air_naval_day", build_combat_air_naval_day_chip_bbcode(province)],
		["agent_auto_day", build_agent_auto_day_chip_bbcode(province)],
		["focus_pick_day", build_focus_pick_day_chip_bbcode(province)],
		["production_priority_day", build_production_priority_day_chip_bbcode(province)],
		["convoy_escort_day", build_convoy_escort_day_chip_bbcode(province)],
		["next_day_feedback_day", build_next_day_feedback_day_chip_bbcode(province)],
		["map_effect_day", build_map_effect_day_chip_bbcode(province)],
		["theater_brief_day", build_theater_brief_day_chip_bbcode(province)],
		["campaign_decision_day", build_campaign_decision_day_chip_bbcode(province)],
		["order_panel_ux_day", build_order_panel_ux_day_chip_bbcode(province)],
		["multi_phase_combat_ui_day", build_multi_phase_combat_ui_day_chip_bbcode(province)],
		["fleet_ai_ops_day", build_fleet_ai_ops_day_chip_bbcode(province)],
		["hh_agenda_package_day", build_hh_agenda_package_day_chip_bbcode(province)],
		["agent_campaign_depth_day", build_agent_campaign_depth_day_chip_bbcode(province)],
		["industry_economy_day", build_industry_economy_day_chip_bbcode(province)],
		["save_slot_browser_day", build_save_slot_browser_day_chip_bbcode(province)],
		["basing_logistics_day", build_basing_logistics_day_chip_bbcode(province)],
		["assault_follow_on_day", build_assault_follow_on_day_chip_bbcode(province)],
		["joint_ops_loop_day", build_joint_ops_loop_day_chip_bbcode(province)],
		["war_cabinet_day", build_war_cabinet_day_chip_bbcode(province)],
		["supply_campaign_day", build_supply_campaign_day_chip_bbcode(province)],
		["force_supply_day", build_force_supply_day_chip_bbcode(province)],
		["counter_ops_day", build_counter_ops_day_chip_bbcode(province)],
		["multi_province_live_day", build_multi_province_live_day_chip_bbcode(province)],
		["order_queue_day", build_order_queue_day_chip_bbcode(province)],
		["agent_ai_board_day", build_agent_ai_board_day_chip_bbcode(province)],
		["fleet_order_day", build_fleet_order_day_chip_bbcode(province)],
		["fleet_theater_posture_day", build_fleet_theater_posture_day_chip_bbcode(province)],
		["campaign_risk_day", build_campaign_risk_day_chip_bbcode(province)],
		["sealane_health_day", build_sealane_health_day_chip_bbcode(province)],
		["convoy_package_day", build_convoy_package_day_chip_bbcode(province)],
		["theater_campaign_day", build_theater_campaign_day_chip_bbcode(province)],
		["production_risk_day", build_production_risk_day_chip_bbcode(province)],
		["leader_campaign_day", build_leader_campaign_day_chip_bbcode(province)],
		["basing_repair_day", build_basing_repair_day_chip_bbcode(province)],
		["focus_order_day", build_focus_order_day_chip_bbcode(province)],
		["naval_order_day", build_naval_order_day_chip_bbcode(province)],
		["air_land_order_day", build_air_land_order_day_chip_bbcode(province)],
		["theater_order_day", build_theater_order_day_chip_bbcode(province)],
		["factory_risk_day", build_factory_risk_day_chip_bbcode(province)],
		["trade_chain_day", build_trade_chain_day_chip_bbcode(province)],
		["war_path_urgency_day", build_war_path_urgency_day_chip_bbcode(province)],
		["combat_morale_day", build_combat_morale_day_chip_bbcode(province)],
		["choke_sea_day", build_choke_sea_day_chip_bbcode(province)],
		["redeploy_route_day", build_redeploy_route_day_chip_bbcode(province)],
		["theater_report_day", build_theater_report_day_chip_bbcode(province)],
		["best_station_day", build_best_station_day_chip_bbcode(province)],
		["best_assault_day", build_best_assault_day_chip_bbcode(province)],
		["theater_mutation_day", build_theater_mutation_day_chip_bbcode(province)],
		["air_ops_sortie_day", build_air_ops_sortie_day_chip_bbcode(province)],
		["agent_escalation_day", build_agent_escalation_day_chip_bbcode(province)],
		["agent_coverage_day", build_agent_coverage_day_chip_bbcode(province)],
		["combat_order_day", build_combat_order_day_chip_bbcode(province)],
		["production_order_day", build_production_order_day_chip_bbcode(province)],
		["supply_order_day", build_supply_order_day_chip_bbcode(province)],
		["combat_phase_strip_day", build_combat_phase_strip_day_chip_bbcode(province)],
		["fleet_patrol_day", build_fleet_patrol_day_chip_bbcode(province)],
		["execute_one_day", build_execute_one_day_chip_bbcode(province)],
		["daily_fleet_plan_day", build_daily_fleet_plan_day_chip_bbcode(province)],
		["daily_combat_plan_day", build_daily_combat_plan_day_chip_bbcode(province)],
		["daily_prod_plan_day", build_daily_prod_plan_day_chip_bbcode(province)],
		["daily_agent_plan_day", build_daily_agent_plan_day_chip_bbcode(province)],
		["daily_supply_plan_day", build_daily_supply_plan_day_chip_bbcode(province)],
		["agent_dispatch_mutation_day", build_agent_dispatch_mutation_day_chip_bbcode(province)],
		["fleet_station_mutation_day", build_fleet_station_mutation_day_chip_bbcode(province)],
		["assault_stage_mutation_day", build_assault_stage_mutation_day_chip_bbcode(province)],
		["naval_task_mutation_day", build_naval_task_mutation_day_chip_bbcode(province)],
		["air_land_stage_mutation_day", build_air_land_stage_mutation_day_chip_bbcode(province)],
		["hh_monthly_day", build_hh_monthly_day_chip_bbcode(province)],
		["leader_weather_day", build_leader_weather_day_chip_bbcode(province)],
		["oob_factory_day", build_oob_factory_day_chip_bbcode(province)],
		["move_ops_day", build_move_ops_day_chip_bbcode(province)],
		["fleet_wx_mission_day", build_fleet_wx_mission_day_chip_bbcode(province)],
		["player_surface_day", build_player_surface_day_chip_bbcode(province)],
		["multi_province_plan_day", build_multi_province_plan_day_chip_bbcode(province)],
		["theater_prod_auto_day", build_theater_prod_auto_day_chip_bbcode(province)],
		["focus_mutation_day", build_focus_mutation_day_chip_bbcode(province)],
		["mutation_feedback_day", build_mutation_feedback_day_chip_bbcode(province)],
		["hh_quarterly_day", build_hh_quarterly_day_chip_bbcode(province)],
		["depot_weather_day", build_depot_weather_day_chip_bbcode(province)],
		["fleet_patrol_strip_day", build_fleet_patrol_strip_day_chip_bbcode(province)],
		["close_loop_day", build_close_loop_day_chip_bbcode(province)],
		["agent_missions_day", build_agent_missions_day_chip_bbcode(province)],
		["supply_route_mutation_day", build_supply_route_mutation_day_chip_bbcode(province)],
		["basing_fuel_day", build_basing_fuel_day_chip_bbcode(province)],
		["ops_dashboard_day", build_ops_dashboard_day_chip_bbcode(province)],
		["daily_theater_tick_day", build_daily_theater_tick_day_chip_bbcode(province)],
		["command_log_day", build_command_log_day_chip_bbcode(province)],
		["integrity_gate_day", build_integrity_gate_day_chip_bbcode(province)],
		["result_feedback_day", build_result_feedback_day_chip_bbcode(province)],
		["day_budget_day", build_day_budget_day_chip_bbcode(province)],
		["hh_auto_plan_day", build_hh_auto_plan_day_chip_bbcode(province)],
		["append_log_day", build_append_log_day_chip_bbcode(province)],
		["log_strip_day", build_log_strip_day_chip_bbcode(province)],
		["assault_readiness_day", build_assault_readiness_day_chip_bbcode(province)],
		["coherence_delta_day", build_coherence_delta_day_chip_bbcode(province)],
		["agent_order_day", build_agent_order_day_chip_bbcode(province)],
		["execution_gate_day", build_execution_gate_day_chip_bbcode(province)],
		["cohesion_gate_day", build_cohesion_gate_day_chip_bbcode(province)],
		["command_gate_day", build_command_gate_day_chip_bbcode(province)],
		["execute_order_day", build_execute_order_day_chip_bbcode(province)],
		["air_sortie_ready_day", build_air_sortie_ready_day_chip_bbcode(province)],
		["weather_combat_brief_day", build_weather_combat_brief_day_chip_bbcode(province)],
		["day_audit_day", build_day_audit_day_chip_bbcode(province)],
		["map_visible_day", build_map_visible_day_chip_bbcode(province)],
		["assault_card_day", build_assault_card_day_chip_bbcode(province)],
		["save_slot_list_day", build_save_slot_list_day_chip_bbcode(province)],
		["multi_phase_estimate_day", build_multi_phase_estimate_day_chip_bbcode(province)],
		["campaign_strip_day", build_campaign_strip_day_chip_bbcode(province)],
		["mutation_result_day", build_mutation_result_day_chip_bbcode(province)],
		["mutation_strip_day", build_mutation_strip_day_chip_bbcode(province)],
		["close_mutation_day", build_close_mutation_day_chip_bbcode(province)],
		["mutation_gate_day", build_mutation_gate_day_chip_bbcode(province)],
		["agenda_pick_day", build_agenda_pick_day_chip_bbcode(province)],
		["agenda_actions_day", build_agenda_actions_day_chip_bbcode(province)],
		["hh_commit_order_day", build_hh_commit_order_day_chip_bbcode(province)],
		["theater_hh_commit_day", build_theater_hh_commit_day_chip_bbcode(province)],
		["hh_counterplay_day", build_hh_counterplay_day_chip_bbcode(province)],
		["task_group_day", build_task_group_day_chip_bbcode(province)],
		["naval_basing_day", build_naval_basing_day_chip_bbcode(province)],
		["naval_multi_phase_day", build_naval_multi_phase_day_chip_bbcode(province)],
		["coastal_fog_gate_day", build_coastal_fog_gate_day_chip_bbcode(province)],
		["phase_ribbon_day", build_phase_ribbon_day_chip_bbcode(province)],
		["assault_rank_day", build_assault_rank_day_chip_bbcode(province)],
		["joint_timeline_day", build_joint_timeline_day_chip_bbcode(province)],
		["daylight_combat_day", build_daylight_combat_day_chip_bbcode(province)],
		["production_auto_day", build_production_auto_day_chip_bbcode(province)],
		["production_risk_alert_day", build_production_risk_alert_day_chip_bbcode(province)],
		["day_results_flair_day", build_day_results_flair_day_chip_bbcode(province)],
		["best_assault_live_day", build_best_assault_live_day_chip_bbcode(province)],
		["best_station_live_day", build_best_station_live_day_chip_bbcode(province)],
		["execute_one_live_day", build_execute_one_live_day_chip_bbcode(province)],
		["basing_fuel_loop_day", build_basing_fuel_loop_day_chip_bbcode(province)],
		["fleet_wx_package_day", build_fleet_wx_package_day_chip_bbcode(province)],
		["convoy_wx_window_day", build_convoy_wx_window_day_chip_bbcode(province)],
		["focus_wx_score_day", build_focus_wx_score_day_chip_bbcode(province)],
		["morale_wx_day", build_morale_wx_day_chip_bbcode(province)],
		["campaign_risk_live_day", build_campaign_risk_live_day_chip_bbcode(province)],
		["depot_wx_live_day", build_depot_wx_live_day_chip_bbcode(province)],
		["daily_fleet_auto_day", build_daily_fleet_auto_day_chip_bbcode(province)],
		["daily_combat_auto_day", build_daily_combat_auto_day_chip_bbcode(province)],
		["daily_agent_auto_day", build_daily_agent_auto_day_chip_bbcode(province)],
		["daily_supply_auto_day", build_daily_supply_auto_day_chip_bbcode(province)],
		["basing_signals_day", build_basing_signals_day_chip_bbcode(province)],
		["basing_rates_day", build_basing_rates_day_chip_bbcode(province)],
		["combat_wx_mult_day", build_combat_wx_mult_day_chip_bbcode(province)],
		["sea_zone_trade_day", build_sea_zone_trade_day_chip_bbcode(province)],
		["hh_secondary_trail_day", build_hh_secondary_trail_day_chip_bbcode(province)],
		["agent_campaign_live_day", build_agent_campaign_live_day_chip_bbcode(province)],
		["live_mut_board_day", build_live_mut_board_day_chip_bbcode(province)],
		["feedback_chain_day", build_feedback_chain_day_chip_bbcode(province)],
		["mut_close_stack_day", build_mut_close_stack_day_chip_bbcode(province)],
		["dual_domain_mutate_day", build_dual_domain_mutate_day_chip_bbcode(province)],
		["assault_mut_fb_day", build_assault_mut_fb_day_chip_bbcode(province)],
		["agent_mut_log_day", build_agent_mut_log_day_chip_bbcode(province)],
		["supply_mut_fb_day", build_supply_mut_fb_day_chip_bbcode(province)],
		["combat_surface_stack_day", build_combat_surface_stack_day_chip_bbcode(province)],
		["phase_timeline_stack_day", build_phase_timeline_stack_day_chip_bbcode(province)],
		["assault_rank_card_day", build_assault_rank_card_day_chip_bbcode(province)],
		["joint_naval_land_day", build_joint_naval_land_day_chip_bbcode(province)],
		["multi_front_surface_day", build_multi_front_surface_day_chip_bbcode(province)],
		["combat_depth_strip_day", build_combat_depth_strip_day_chip_bbcode(province)],
		["phase_estimate_ribbon_day", build_phase_estimate_ribbon_day_chip_bbcode(province)],
		["fleet_path_stack_day", build_fleet_path_stack_day_chip_bbcode(province)],
		["basing_mission_day", build_basing_mission_day_chip_bbcode(province)],
		["hh_path_stack_day", build_hh_path_stack_day_chip_bbcode(province)],
		["hh_trail_counter_day", build_hh_trail_counter_day_chip_bbcode(province)],
		["agent_mission_path_day", build_agent_mission_path_day_chip_bbcode(province)],
		["incomplete_loop_close_day", build_incomplete_loop_close_day_chip_bbcode(province)],
		["prod_mut_apply_day", build_prod_mut_apply_day_chip_bbcode(province)],
		["supply_mut_apply_day", build_supply_mut_apply_day_chip_bbcode(province)],
		["execute_prod_live_day", build_execute_prod_live_day_chip_bbcode(province)],
		["day_budget_apply_day", build_day_budget_apply_day_chip_bbcode(province)],
		["apply_audit_live_day", build_apply_audit_live_day_chip_bbcode(province)],
		["live_apply_results_day", build_live_apply_results_day_chip_bbcode(province)],
		["mutation_gate_apply_day", build_mutation_gate_apply_day_chip_bbcode(province)],
		["daily_prod_auto_live_day", build_daily_prod_auto_live_day_chip_bbcode(province)],
		["theater_prod_live_day", build_theater_prod_live_day_chip_bbcode(province)],
		["prod_campaign_risk_day", build_prod_campaign_risk_day_chip_bbcode(province)],
		["prod_wx_stack_day", build_prod_wx_stack_day_chip_bbcode(province)],
		["factory_risk_live_day", build_factory_risk_live_day_chip_bbcode(province)],
		["depot_prod_stack_day", build_depot_prod_stack_day_chip_bbcode(province)],
		["industry_close_loop_day", build_industry_close_loop_day_chip_bbcode(province)],
		["save_slot_surface_day", build_save_slot_surface_day_chip_bbcode(province)],
		["save_browser_live_day", build_save_browser_live_day_chip_bbcode(province)],
		["campaign_continuity_day", build_campaign_continuity_day_chip_bbcode(province)],
		["ops_dash_continuity_day", build_ops_dash_continuity_day_chip_bbcode(province)],
		["execution_gate_cont_day", build_execution_gate_cont_day_chip_bbcode(province)],
		["industry_save_close_day", build_industry_save_close_day_chip_bbcode(province)],
		["fleet_ai_task_day", build_fleet_ai_task_day_chip_bbcode(province)],
		["fleet_wx_ops_day", build_fleet_wx_ops_day_chip_bbcode(province)],
		["basing_fuel_ops_day", build_basing_fuel_ops_day_chip_bbcode(province)],
		["naval_phase_ops_day", build_naval_phase_ops_day_chip_bbcode(province)],
		["coastal_fog_ops_day", build_coastal_fog_ops_day_chip_bbcode(province)],
		["fleet_station_mut_day", build_fleet_station_mut_day_chip_bbcode(province)],
		["naval_task_mut_day", build_naval_task_mut_day_chip_bbcode(province)],
		["hh_agenda_pick_day", build_hh_agenda_pick_day_chip_bbcode(province)],
		["hh_agenda_actions_day", build_hh_agenda_actions_day_chip_bbcode(province)],
		["hh_order_path_day", build_hh_order_path_day_chip_bbcode(province)],
		["theater_hh_path_day", build_theater_hh_path_day_chip_bbcode(province)],
		["hh_trail_ops_day", build_hh_trail_ops_day_chip_bbcode(province)],
		["agent_mission_ops_day", build_agent_mission_ops_day_chip_bbcode(province)],
		["agent_campaign_ops_day", build_agent_campaign_ops_day_chip_bbcode(province)],
		["combat_inspect_stack_day", build_combat_inspect_stack_day_chip_bbcode(province)],
		["phase_ribbon_inspect_day", build_phase_ribbon_inspect_day_chip_bbcode(province)],
		["joint_timeline_inspect_day", build_joint_timeline_inspect_day_chip_bbcode(province)],
		["assault_rank_inspect_day", build_assault_rank_inspect_day_chip_bbcode(province)],
		["combat_campaign_ops_day", build_combat_campaign_ops_day_chip_bbcode(province)],
		["fleet_hh_combat_close_day", build_fleet_hh_combat_close_day_chip_bbcode(province)],
		["depot_logistics_day", build_depot_logistics_day_chip_bbcode(province)],
		["supply_route_ops_day", build_supply_route_ops_day_chip_bbcode(province)],
		["move_path_ops_day", build_move_path_ops_day_chip_bbcode(province)],
		["multi_province_ops_day", build_multi_province_ops_day_chip_bbcode(province)],
		["theater_auto_tick_day", build_theater_auto_tick_day_chip_bbcode(province)],
		["daily_supply_ops_day", build_daily_supply_ops_day_chip_bbcode(province)],
		["logistics_theater_close_day", build_logistics_theater_close_day_chip_bbcode(province)],
		["force_readiness_ops_day", build_force_readiness_ops_day_chip_bbcode(province)],
		["oob_factory_ops_day", build_oob_factory_ops_day_chip_bbcode(province)],
		["medium_equip_ops_day", build_medium_equip_ops_day_chip_bbcode(province)],
		["naval_skim_ops_day", build_naval_skim_ops_day_chip_bbcode(province)],
		["basing_logistics_ops_day", build_basing_logistics_ops_day_chip_bbcode(province)],
		["production_force_ops_day", build_production_force_ops_day_chip_bbcode(province)],
		["force_oob_close_day", build_force_oob_close_day_chip_bbcode(province)],
		["player_surface_ops_day", build_player_surface_ops_day_chip_bbcode(province)],
		["order_panel_ops_day", build_order_panel_ops_day_chip_bbcode(province)],
		["panel_sections_ops_day", build_panel_sections_ops_day_chip_bbcode(province)],
		["tooltip_flair_ops_day", build_tooltip_flair_ops_day_chip_bbcode(province)],
		["apply_audit_ops_day", build_apply_audit_ops_day_chip_bbcode(province)],
		["logistics_force_panel_close_day", build_logistics_force_panel_close_day_chip_bbcode(province)],
		["combat_wx_ops_day", build_combat_wx_ops_day_chip_bbcode(province)],
		["prod_wx_ops_day", build_prod_wx_ops_day_chip_bbcode(province)],
		["air_sortie_wx_day", build_air_sortie_wx_day_chip_bbcode(province)],
		["morale_wx_ops_day", build_morale_wx_ops_day_chip_bbcode(province)],
		["convoy_wx_ops_day", build_convoy_wx_ops_day_chip_bbcode(province)],
		["daylight_wx_ops_day", build_daylight_wx_ops_day_chip_bbcode(province)],
		["weather_ops_close_day", build_weather_ops_close_day_chip_bbcode(province)],
		["war_economy_ops_day", build_war_economy_ops_day_chip_bbcode(province)],
		["prod_campaign_ops_day", build_prod_campaign_ops_day_chip_bbcode(province)],
		["focus_wx_ops_day", build_focus_wx_ops_day_chip_bbcode(province)],
		["focus_mut_ops_day", build_focus_mut_ops_day_chip_bbcode(province)],
		["supply_economy_ops_day", build_supply_economy_ops_day_chip_bbcode(province)],
		["depot_economy_ops_day", build_depot_economy_ops_day_chip_bbcode(province)],
		["war_economy_close_day", build_war_economy_close_day_chip_bbcode(province)],
		["intel_counter_ops_day", build_intel_counter_ops_day_chip_bbcode(province)],
		["agent_intel_ops_day", build_agent_intel_ops_day_chip_bbcode(province)],
		["hh_counter_ops_day", build_hh_counter_ops_day_chip_bbcode(province)],
		["map_effect_ops_day", build_map_effect_ops_day_chip_bbcode(province)],
		["coherence_intel_day", build_coherence_intel_day_chip_bbcode(province)],
		["weather_economy_intel_close_day", build_weather_economy_intel_close_day_chip_bbcode(province)],
		["multi_province_campaign_day", build_multi_province_campaign_day_chip_bbcode(province)],
		["theater_auto_campaign_day", build_theater_auto_campaign_day_chip_bbcode(province)],
		["daily_command_ops_day", build_daily_command_ops_day_chip_bbcode(province)],
		["theater_readiness_ops_day", build_theater_readiness_ops_day_chip_bbcode(province)],
		["move_path_campaign_day", build_move_path_campaign_day_chip_bbcode(province)],
		["theater_order_board_day", build_theater_order_board_day_chip_bbcode(province)],
		["theater_campaign_close_day", build_theater_campaign_close_day_chip_bbcode(province)],
		["basing_fleet_sustain_day", build_basing_fleet_sustain_day_chip_bbcode(province)],
		["fleet_wx_sustain_day", build_fleet_wx_sustain_day_chip_bbcode(province)],
		["convoy_sustain_ops_day", build_convoy_sustain_ops_day_chip_bbcode(province)],
		["sealane_joint_ops_day", build_sealane_joint_ops_day_chip_bbcode(province)],
		["naval_order_ops_day", build_naval_order_ops_day_chip_bbcode(province)],
		["fleet_station_sustain_day", build_fleet_station_sustain_day_chip_bbcode(province)],
		["naval_sealane_close_day", build_naval_sealane_close_day_chip_bbcode(province)],
		["player_surface_session_day", build_player_surface_session_day_chip_bbcode(province)],
		["order_panel_session_day", build_order_panel_session_day_chip_bbcode(province)],
		["mutation_feedback_ops_day", build_mutation_feedback_ops_day_chip_bbcode(province)],
		["apply_audit_session_day", build_apply_audit_session_day_chip_bbcode(province)],
		["decision_strip_ops_day", build_decision_strip_ops_day_chip_bbcode(province)],
		["theater_naval_session_close_day", build_theater_naval_session_close_day_chip_bbcode(province)],
		["combat_phase_ops_day", build_combat_phase_ops_day_chip_bbcode(province)],
		["assault_ready_ops_day", build_assault_ready_ops_day_chip_bbcode(province)],
		["multi_phase_est_ops_day", build_multi_phase_est_ops_day_chip_bbcode(province)],
		["combat_order_ops_day", build_combat_order_ops_day_chip_bbcode(province)],
		["assault_rank_ops_day", build_assault_rank_ops_day_chip_bbcode(province)],
		["phase_ribbon_ops_day", build_phase_ribbon_ops_day_chip_bbcode(province)],
		["combat_phase_close_day", build_combat_phase_close_day_chip_bbcode(province)],
		["agent_mission_campaign_day", build_agent_mission_campaign_day_chip_bbcode(province)],
		["agent_dispatch_ops_day", build_agent_dispatch_ops_day_chip_bbcode(province)],
		["hh_commit_campaign_day", build_hh_commit_campaign_day_chip_bbcode(province)],
		["counterplay_campaign_day", build_counterplay_campaign_day_chip_bbcode(province)],
		["hh_agenda_ops_day", build_hh_agenda_ops_day_chip_bbcode(province)],
		["agent_hh_joint_day", build_agent_hh_joint_day_chip_bbcode(province)],
		["agent_hh_close_day", build_agent_hh_close_day_chip_bbcode(province)],
		["joint_theater_combat_day", build_joint_theater_combat_day_chip_bbcode(province)],
		["joint_naval_combat_day", build_joint_naval_combat_day_chip_bbcode(province)],
		["focus_joint_ops_day", build_focus_joint_ops_day_chip_bbcode(province)],
		["joint_command_ops_day", build_joint_command_ops_day_chip_bbcode(province)],
		["multi_domain_strip_day", build_multi_domain_strip_day_chip_bbcode(province)],
		["combat_agent_joint_close_day", build_combat_agent_joint_close_day_chip_bbcode(province)],
		["prod_factory_risk_ops_day", build_prod_factory_risk_ops_day_chip_bbcode(province)],
		["medium_equip_horizon_ops_day", build_medium_equip_horizon_ops_day_chip_bbcode(province)],
		["production_priority_ops_day", build_production_priority_ops_day_chip_bbcode(province)],
		["oob_equip_continuity_day", build_oob_equip_continuity_day_chip_bbcode(province)],
		["factory_line_ops_day", build_factory_line_ops_day_chip_bbcode(province)],
		["stockpile_growth_ops_day", build_stockpile_growth_ops_day_chip_bbcode(province)],
		["production_oob_close_day", build_production_oob_close_day_chip_bbcode(province)],
		["air_sortie_front_ops_day", build_air_sortie_front_ops_day_chip_bbcode(province)],
		["multi_front_rank_ops_day", build_multi_front_rank_ops_day_chip_bbcode(province)],
		["air_land_joint_ops_day", build_air_land_joint_ops_day_chip_bbcode(province)],
		["assault_front_ops_day", build_assault_front_ops_day_chip_bbcode(province)],
		["air_forecast_ops_day", build_air_forecast_ops_day_chip_bbcode(province)],
		["multi_front_supply_ops_day", build_multi_front_supply_ops_day_chip_bbcode(province)],
		["air_front_close_day", build_air_front_close_day_chip_bbcode(province)],
		["focus_path_ops_day", build_focus_path_ops_day_chip_bbcode(province)],
		["war_cabinet_ops_day", build_war_cabinet_ops_day_chip_bbcode(province)],
		["strategic_strip_ops_day", build_strategic_strip_ops_day_chip_bbcode(province)],
		["focus_priority_ops_day", build_focus_priority_ops_day_chip_bbcode(province)],
		["strategic_continuity_ops_day", build_strategic_continuity_ops_day_chip_bbcode(province)],
		["prod_air_focus_close_day", build_prod_air_focus_close_day_chip_bbcode(province)],
		["save_slot_integrity_ops_day", build_save_slot_integrity_ops_day_chip_bbcode(province)],
		["autosave_session_ops_day", build_autosave_session_ops_day_chip_bbcode(province)],
		["campaign_session_ops_day", build_campaign_session_ops_day_chip_bbcode(province)],
		["save_resume_ops_day", build_save_resume_ops_day_chip_bbcode(province)],
		["session_checkpoint_ops_day", build_session_checkpoint_ops_day_chip_bbcode(province)],
		["save_audit_ops_day", build_save_audit_ops_day_chip_bbcode(province)],
		["save_session_close_day", build_save_session_close_day_chip_bbcode(province)],
		["leader_assign_ops_day", build_leader_assign_ops_day_chip_bbcode(province)],
		["formation_ready_ops_day", build_formation_ready_ops_day_chip_bbcode(province)],
		["oob_assign_ops_day", build_oob_assign_ops_day_chip_bbcode(province)],
		["leader_command_ops_day", build_leader_command_ops_day_chip_bbcode(province)],
		["formation_station_ops_day", build_formation_station_ops_day_chip_bbcode(province)],
		["leader_formation_joint_day", build_leader_formation_joint_day_chip_bbcode(province)],
		["leader_formation_close_day", build_leader_formation_close_day_chip_bbcode(province)],
		["trade_chain_ops_day", build_trade_chain_ops_day_chip_bbcode(province)],
		["convoy_escort_ops_day", build_convoy_escort_ops_day_chip_bbcode(province)],
		["sealane_economy_ops_day", build_sealane_economy_ops_day_chip_bbcode(province)],
		["trade_route_ops_day", build_trade_route_ops_day_chip_bbcode(province)],
		["convoy_trade_joint_day", build_convoy_trade_joint_day_chip_bbcode(province)],
		["save_leader_trade_close_day", build_save_leader_trade_close_day_chip_bbcode(province)],
		["panel_surface_ops_day", build_panel_surface_ops_day_chip_bbcode(province)],
		["tooltip_chip_ops_day", build_tooltip_chip_ops_day_chip_bbcode(province)],
		["insight_budget_ops_day", build_insight_budget_ops_day_chip_bbcode(province)],
		["order_surface_ops_day", build_order_surface_ops_day_chip_bbcode(province)],
		["product_chip_ops_day", build_product_chip_ops_day_chip_bbcode(province)],
		["surface_refresh_ops_day", build_surface_refresh_ops_day_chip_bbcode(province)],
		["inspector_surface_close_day", build_inspector_surface_close_day_chip_bbcode(province)],
		["infra_invest_ops_day", build_infra_invest_ops_day_chip_bbcode(province)],
		["special_site_ops_day", build_special_site_ops_day_chip_bbcode(province)],
		["construction_ops_day", build_construction_ops_day_chip_bbcode(province)],
		["infra_project_ops_day", build_infra_project_ops_day_chip_bbcode(province)],
		["investment_status_ops_day", build_investment_status_ops_day_chip_bbcode(province)],
		["infra_site_joint_day", build_infra_site_joint_day_chip_bbcode(province)],
		["infra_invest_close_day", build_infra_invest_close_day_chip_bbcode(province)],
		["daily_auto_ops_day", build_daily_auto_ops_day_chip_bbcode(province)],
		["theater_tick_ops_day", build_theater_tick_ops_day_chip_bbcode(province)],
		["multi_domain_auto_ops_day", build_multi_domain_auto_ops_day_chip_bbcode(province)],
		["daily_apply_ops_day", build_daily_apply_ops_day_chip_bbcode(province)],
		["theater_auto_joint_day", build_theater_auto_joint_day_chip_bbcode(province)],
		["inspector_infra_auto_close_day", build_inspector_infra_auto_close_day_chip_bbcode(province)],
		["follow_on_assault_ops_day", build_follow_on_assault_ops_day_chip_bbcode(province)],
		["reinforced_combat_ops_day", build_reinforced_combat_ops_day_chip_bbcode(province)],
		["war_path_urgency_ops_day", build_war_path_urgency_ops_day_chip_bbcode(province)],
		["assault_follow_ops_day", build_assault_follow_ops_day_chip_bbcode(province)],
		["reinforce_step_ops_day", build_reinforce_step_ops_day_chip_bbcode(province)],
		["combat_urgency_ops_day", build_combat_urgency_ops_day_chip_bbcode(province)],
		["follow_reinforce_close_day", build_follow_reinforce_close_day_chip_bbcode(province)],
		["choke_sea_wx_ops_day", build_choke_sea_wx_ops_day_chip_bbcode(province)],
		["sea_zone_mod_ops_day", build_sea_zone_mod_ops_day_chip_bbcode(province)],
		["basing_choke_ops_day", build_basing_choke_ops_day_chip_bbcode(province)],
		["choke_control_ops_day", build_choke_control_ops_day_chip_bbcode(province)],
		["sea_zone_control_ops_day", build_sea_zone_control_ops_day_chip_bbcode(province)],
		["choke_basing_joint_day", build_choke_basing_joint_day_chip_bbcode(province)],
		["choke_sea_close_day", build_choke_sea_close_day_chip_bbcode(province)],
		["agent_escalation_ops_day", build_agent_escalation_ops_day_chip_bbcode(province)],
		["coverage_ops_day", build_coverage_ops_day_chip_bbcode(province)],
		["counter_ops_board_ops_day", build_counter_ops_board_ops_day_chip_bbcode(province)],
		["escalation_ladder_ops_day", build_escalation_ladder_ops_day_chip_bbcode(province)],
		["agent_coverage_joint_day", build_agent_coverage_joint_day_chip_bbcode(province)],
		["assault_choke_agent_close_day", build_assault_choke_agent_close_day_chip_bbcode(province)],
		["equip_horizon_depth_day", build_equip_horizon_depth_day_chip_bbcode(province)],
		["stockpile_line_ops_day", build_stockpile_line_ops_day_chip_bbcode(province)],
		["oob_line_continuity_day", build_oob_line_continuity_day_chip_bbcode(province)],
		["factory_oob_depth_day", build_factory_oob_depth_day_chip_bbcode(province)],
		["medium_horizon_plan_day", build_medium_horizon_plan_day_chip_bbcode(province)],
		["equip_stockpile_joint_day", build_equip_stockpile_joint_day_chip_bbcode(province)],
		["equip_oob_close_day", build_equip_oob_close_day_chip_bbcode(province)],
		["fleet_multi_theater_ops_day", build_fleet_multi_theater_ops_day_chip_bbcode(province)],
		["fleet_redeploy_ops_day", build_fleet_redeploy_ops_day_chip_bbcode(province)],
		["task_group_posture_ops_day", build_task_group_posture_ops_day_chip_bbcode(province)],
		["fleet_posture_ops_day", build_fleet_posture_ops_day_chip_bbcode(province)],
		["redeploy_route_ops_day", build_redeploy_route_ops_day_chip_bbcode(province)],
		["fleet_theater_joint_day", build_fleet_theater_joint_day_chip_bbcode(province)],
		["fleet_redeploy_close_day", build_fleet_redeploy_close_day_chip_bbcode(province)],
		["hh_monthly_ops_day", build_hh_monthly_ops_day_chip_bbcode(province)],
		["hh_quarterly_ops_day", build_hh_quarterly_ops_day_chip_bbcode(province)],
		["agenda_pulse_ops_day", build_agenda_pulse_ops_day_chip_bbcode(province)],
		["trail_counterplay_ops_day", build_trail_counterplay_ops_day_chip_bbcode(province)],
		["hh_agenda_depth_joint_day", build_hh_agenda_depth_joint_day_chip_bbcode(province)],
		["oob_fleet_hh_close_day", build_oob_fleet_hh_close_day_chip_bbcode(province)],
		["force_readiness_depth_day", build_force_readiness_depth_day_chip_bbcode(province)],
		["multi_front_supply_depth_day", build_multi_front_supply_depth_day_chip_bbcode(province)],
		["depot_route_ops_day", build_depot_route_ops_day_chip_bbcode(province)],
		["force_posture_depth_day", build_force_posture_depth_day_chip_bbcode(province)],
		["front_supply_rank_day", build_front_supply_rank_day_chip_bbcode(province)],
		["force_supply_joint_day", build_force_supply_joint_day_chip_bbcode(province)],
		["force_supply_close_day", build_force_supply_close_day_chip_bbcode(province)],
		["weather_pressure_ops_day", build_weather_pressure_ops_day_chip_bbcode(province)],
		["campaign_crisis_ops_day", build_campaign_crisis_ops_day_chip_bbcode(province)],
		["prod_weather_crisis_day", build_prod_weather_crisis_day_chip_bbcode(province)],
		["combat_weather_ops_day", build_combat_weather_ops_day_chip_bbcode(province)],
		["weather_crisis_brief_day", build_weather_crisis_brief_day_chip_bbcode(province)],
		["weather_campaign_joint_day", build_weather_campaign_joint_day_chip_bbcode(province)],
		["weather_crisis_close_day", build_weather_crisis_close_day_chip_bbcode(province)],
		["focus_war_path_ops_day", build_focus_war_path_ops_day_chip_bbcode(province)],
		["strategic_strip_depth_day", build_strategic_strip_depth_day_chip_bbcode(province)],
		["strategic_continuity_depth_day", build_strategic_continuity_depth_day_chip_bbcode(province)],
		["war_cabinet_pulse_ops_day", build_war_cabinet_pulse_ops_day_chip_bbcode(province)],
		["focus_continuity_joint_day", build_focus_continuity_joint_day_chip_bbcode(province)],
		["force_weather_focus_close_day", build_force_weather_focus_close_day_chip_bbcode(province)],
		["air_sortie_depth_day", build_air_sortie_depth_day_chip_bbcode(province)],
		["air_land_joint_depth_day", build_air_land_joint_depth_day_chip_bbcode(province)],
		["multi_domain_ops_day", build_multi_domain_ops_day_chip_bbcode(province)],
		["air_front_readiness_day", build_air_front_readiness_day_chip_bbcode(province)],
		["domain_joint_ops_day", build_domain_joint_ops_day_chip_bbcode(province)],
		["air_land_campaign_day", build_air_land_campaign_day_chip_bbcode(province)],
		["air_domain_close_day", build_air_domain_close_day_chip_bbcode(province)],
		["convoy_escort_depth_day", build_convoy_escort_depth_day_chip_bbcode(province)],
		["sealane_health_ops_day", build_sealane_health_ops_day_chip_bbcode(province)],
		["trade_pressure_ops_day", build_trade_pressure_ops_day_chip_bbcode(province)],
		["convoy_sealane_joint_day", build_convoy_sealane_joint_day_chip_bbcode(province)],
		["sealane_logistics_ops_day", build_sealane_logistics_ops_day_chip_bbcode(province)],
		["wartime_trade_ops_day", build_wartime_trade_ops_day_chip_bbcode(province)],
		["convoy_sealane_close_day", build_convoy_sealane_close_day_chip_bbcode(province)],
		["order_execute_depth_day", build_order_execute_depth_day_chip_bbcode(province)],
		["map_effect_resolve_day", build_map_effect_resolve_day_chip_bbcode(province)],
		["next_day_feedback_depth_day", build_next_day_feedback_depth_day_chip_bbcode(province)],
		["order_effect_joint_day", build_order_effect_joint_day_chip_bbcode(province)],
		["feedback_loop_ops_day", build_feedback_loop_ops_day_chip_bbcode(province)],
		["air_convoy_order_close_day", build_air_convoy_order_close_day_chip_bbcode(province)],
		["leader_assign_depth_day", build_leader_assign_depth_day_chip_bbcode(province)],
		["formation_ready_depth_day", build_formation_ready_depth_day_chip_bbcode(province)],
		["leader_weather_depth_day", build_leader_weather_depth_day_chip_bbcode(province)],
		["formation_station_depth_day", build_formation_station_depth_day_chip_bbcode(province)],
		["leader_formation_joint_depth_day", build_leader_formation_joint_depth_day_chip_bbcode(province)],
		["oob_leader_ops_day", build_oob_leader_ops_day_chip_bbcode(province)],
		["leader_formation_close_depth_day", build_leader_formation_close_depth_day_chip_bbcode(province)],
		["intel_counter_depth_day", build_intel_counter_depth_day_chip_bbcode(province)],
		["hh_counterplay_depth_day", build_hh_counterplay_depth_day_chip_bbcode(province)],
		["agent_response_depth_day", build_agent_response_depth_day_chip_bbcode(province)],
		["trail_intel_ops_day", build_trail_intel_ops_day_chip_bbcode(province)],
		["counterintel_board_ops_day", build_counterintel_board_ops_day_chip_bbcode(province)],
		["intel_response_joint_day", build_intel_response_joint_day_chip_bbcode(province)],
		["intel_counter_close_day", build_intel_counter_close_day_chip_bbcode(province)],
		["theater_daily_depth_day", build_theater_daily_depth_day_chip_bbcode(province)],
		["multi_province_rank_depth_day", build_multi_province_rank_depth_day_chip_bbcode(province)],
		["daily_auto_depth_day", build_daily_auto_depth_day_chip_bbcode(province)],
		["theater_brief_ops_day", build_theater_brief_ops_day_chip_bbcode(province)],
		["multi_province_command_day", build_multi_province_command_day_chip_bbcode(province)],
		["leader_intel_theater_close_day", build_leader_intel_theater_close_day_chip_bbcode(province)],
		["save_slot_depth_day", build_save_slot_depth_day_chip_bbcode(province)],
		["autosave_session_depth_day", build_autosave_session_depth_day_chip_bbcode(province)],
		["campaign_session_depth_day", build_campaign_session_depth_day_chip_bbcode(province)],
		["save_resume_depth_day", build_save_resume_depth_day_chip_bbcode(province)],
		["session_checkpoint_depth_day", build_session_checkpoint_depth_day_chip_bbcode(province)],
		["save_audit_depth_day", build_save_audit_depth_day_chip_bbcode(province)],
		["save_session_close_depth_day", build_save_session_close_depth_day_chip_bbcode(province)],
		["factory_risk_surge_day", build_factory_risk_surge_day_chip_bbcode(province)],
		["production_priority_depth_day", build_production_priority_depth_day_chip_bbcode(province)],
		["stockpile_surge_ops_day", build_stockpile_surge_ops_day_chip_bbcode(province)],
		["line_continuity_depth_day", build_line_continuity_depth_day_chip_bbcode(province)],
		["industry_surge_joint_day", build_industry_surge_joint_day_chip_bbcode(province)],
		["production_oob_depth_day", build_production_oob_depth_day_chip_bbcode(province)],
		["production_surge_close_day", build_production_surge_close_day_chip_bbcode(province)],
		["multi_phase_estimate_depth_day", build_multi_phase_estimate_depth_day_chip_bbcode(province)],
		["multi_phase_combat_product", build_multi_phase_combat_product_chip_bbcode(province)],
		["fleet_multi_day_autonomy_product", build_fleet_multi_day_autonomy_product_chip_bbcode(province)],
		["save_browser_campaign_product", build_save_browser_campaign_product_chip_bbcode(province)],
		["medium_tank_oob_product", build_medium_tank_oob_product_chip_bbcode(province)],
		["hh_multi_month_agenda_product", build_hh_multi_month_agenda_product_chip_bbcode(province)],
		["agent_campaign_product", build_agent_campaign_product_chip_bbcode(province)],
		["inspector_decision_product", build_inspector_decision_product_chip_bbcode(province)],
		["theater_command_product", build_theater_command_product_chip_bbcode(province)],
		["diplomacy_peace_campaign_product", build_diplomacy_peace_campaign_product_chip_bbcode(province)],
		["tech_research_campaign_product", build_tech_research_campaign_product_chip_bbcode(province)],
		["diplomacy_board_advanced_day", build_diplomacy_board_advanced_day_chip_bbcode(province)],
		["diplomacy_leverage_advanced_day", build_diplomacy_leverage_advanced_day_chip_bbcode(province)],
		["diplomacy_settle_advanced_day", build_diplomacy_settle_advanced_day_chip_bbcode(province)],
		["diplomacy_trade_pressure_day", build_diplomacy_trade_pressure_day_chip_bbcode(province)],
		["diplomacy_agent_hh_joint_day", build_diplomacy_agent_hh_joint_day_chip_bbcode(province)],
		["diplomacy_focus_peace_joint_day", build_diplomacy_focus_peace_joint_day_chip_bbcode(province)],
		["diplomacy_peace_close_day", build_diplomacy_peace_close_day_chip_bbcode(province)],
		["tech_catalog_advanced_day", build_tech_catalog_advanced_day_chip_bbcode(province)],
		["tech_priority_advanced_day", build_tech_priority_advanced_day_chip_bbcode(province)],
		["tech_field_advanced_day", build_tech_field_advanced_day_chip_bbcode(province)],
		["tech_designer_joint_day", build_tech_designer_joint_day_chip_bbcode(province)],
		["tech_oob_fielding_joint_day", build_tech_oob_fielding_joint_day_chip_bbcode(province)],
		["tech_industry_focus_joint_day", build_tech_industry_focus_joint_day_chip_bbcode(province)],
		["tech_research_close_day", build_tech_research_close_day_chip_bbcode(province)],
		["diplomacy_tech_joint_day", build_diplomacy_tech_joint_day_chip_bbcode(province)],
		["tech_ai_research_joint_day", build_tech_ai_research_joint_day_chip_bbcode(province)],
		["diplomacy_naval_air_joint_day", build_diplomacy_naval_air_joint_day_chip_bbcode(province)],
		["session_diplomacy_tech_joint_day", build_session_diplomacy_tech_joint_day_chip_bbcode(province)],
		["multi_faction_diplo_tech_day", build_multi_faction_diplo_tech_day_chip_bbcode(province)],
		["diplomacy_tech_campaign_close_day", build_diplomacy_tech_campaign_close_day_chip_bbcode(province)],
		["logistics_supply_theater_product", build_logistics_supply_theater_product_chip_bbcode(province)],
		["intelligence_network_product", build_intelligence_network_product_chip_bbcode(province)],
		["world_class_campaign_command_product", build_world_class_campaign_command_product_chip_bbcode(province)],
		["logistics_route_advanced_day", build_logistics_route_advanced_day_chip_bbcode(province)],
		["logistics_sustain_advanced_day", build_logistics_sustain_advanced_day_chip_bbcode(province)],
		["logistics_readiness_advanced_day", build_logistics_readiness_advanced_day_chip_bbcode(province)],
		["logistics_naval_joint_day", build_logistics_naval_joint_day_chip_bbcode(province)],
		["logistics_tech_industry_joint_day", build_logistics_tech_industry_joint_day_chip_bbcode(province)],
		["logistics_supply_close_day", build_logistics_supply_close_day_chip_bbcode(province)],
		["intel_coverage_advanced_day", build_intel_coverage_advanced_day_chip_bbcode(province)],
		["intel_counterintel_advanced_day", build_intel_counterintel_advanced_day_chip_bbcode(province)],
		["intel_counterplay_advanced_day", build_intel_counterplay_advanced_day_chip_bbcode(province)],
		["intel_diplomacy_joint_day", build_intel_diplomacy_joint_day_chip_bbcode(province)],
		["intel_session_joint_day", build_intel_session_joint_day_chip_bbcode(province)],
		["intelligence_network_close_day", build_intelligence_network_close_day_chip_bbcode(province)],
		["world_class_scan_advanced_day", build_world_class_scan_advanced_day_chip_bbcode(province)],
		["world_class_rank_advanced_day", build_world_class_rank_advanced_day_chip_bbcode(province)],
		["world_class_execute_advanced_day", build_world_class_execute_advanced_day_chip_bbcode(province)],
		["world_class_logistics_intel_joint_day", build_world_class_logistics_intel_joint_day_chip_bbcode(province)],
		["world_class_air_naval_joint_day", build_world_class_air_naval_joint_day_chip_bbcode(province)],
		["world_class_session_ai_joint_day", build_world_class_session_ai_joint_day_chip_bbcode(province)],
		["world_class_theater_command_joint_day", build_world_class_theater_command_joint_day_chip_bbcode(province)],
		["world_class_campaign_close_day", build_world_class_campaign_close_day_chip_bbcode(province)],
		["war_economy_mobilization_product", build_war_economy_mobilization_product_chip_bbcode(province)],
		["weather_theater_ops_product", build_weather_theater_ops_product_chip_bbcode(province)],
		["front_continuity_campaign_product", build_front_continuity_campaign_product_chip_bbcode(province)],
		["war_economy_board_advanced_day", build_war_economy_board_advanced_day_chip_bbcode(province)],
		["war_economy_allocate_advanced_day", build_war_economy_allocate_advanced_day_chip_bbcode(province)],
		["war_economy_sustain_advanced_day", build_war_economy_sustain_advanced_day_chip_bbcode(province)],
		["war_economy_logistics_joint_day", build_war_economy_logistics_joint_day_chip_bbcode(province)],
		["war_economy_tech_joint_day", build_war_economy_tech_joint_day_chip_bbcode(province)],
		["war_economy_mobilization_close_day", build_war_economy_mobilization_close_day_chip_bbcode(province)],
		["weather_pressure_advanced_day", build_weather_pressure_advanced_day_chip_bbcode(province)],
		["weather_gate_advanced_day", build_weather_gate_advanced_day_chip_bbcode(province)],
		["weather_crisis_advanced_day", build_weather_crisis_advanced_day_chip_bbcode(province)],
		["weather_front_joint_day", build_weather_front_joint_day_chip_bbcode(province)],
		["weather_economy_joint_day", build_weather_economy_joint_day_chip_bbcode(province)],
		["weather_theater_ops_close_day", build_weather_theater_ops_close_day_chip_bbcode(province)],
		["front_combat_advanced_day", build_front_combat_advanced_day_chip_bbcode(province)],
		["front_assault_advanced_day", build_front_assault_advanced_day_chip_bbcode(province)],
		["front_sustain_advanced_day", build_front_sustain_advanced_day_chip_bbcode(province)],
		["front_weather_joint_day", build_front_weather_joint_day_chip_bbcode(province)],
		["front_economy_joint_day", build_front_economy_joint_day_chip_bbcode(province)],
		["front_logistics_joint_day", build_front_logistics_joint_day_chip_bbcode(province)],
		["front_theater_command_joint_day", build_front_theater_command_joint_day_chip_bbcode(province)],
		["front_continuity_campaign_close_day", build_front_continuity_campaign_close_day_chip_bbcode(province)],
		["occupation_control_product", build_occupation_control_product_chip_bbcode(province)],
		["manpower_reinforcement_product", build_manpower_reinforcement_product_chip_bbcode(province)],
		["leader_command_product", build_leader_command_product_chip_bbcode(province)],
		["occupation_control_advanced_day", build_occupation_control_advanced_day_chip_bbcode(province)],
		["occupation_garrison_advanced_day", build_occupation_garrison_advanced_day_chip_bbcode(province)],
		["occupation_integrate_advanced_day", build_occupation_integrate_advanced_day_chip_bbcode(province)],
		["occupation_front_joint_day", build_occupation_front_joint_day_chip_bbcode(province)],
		["occupation_economy_joint_day", build_occupation_economy_joint_day_chip_bbcode(province)],
		["occupation_control_close_day", build_occupation_control_close_day_chip_bbcode(province)],
		["manpower_draft_advanced_day", build_manpower_draft_advanced_day_chip_bbcode(province)],
		["manpower_reinforce_advanced_day", build_manpower_reinforce_advanced_day_chip_bbcode(province)],
		["manpower_field_advanced_day", build_manpower_field_advanced_day_chip_bbcode(province)],
		["manpower_front_joint_day", build_manpower_front_joint_day_chip_bbcode(province)],
		["manpower_economy_joint_day", build_manpower_economy_joint_day_chip_bbcode(province)],
		["manpower_reinforcement_close_day", build_manpower_reinforcement_close_day_chip_bbcode(province)],
		["leader_assign_advanced_day", build_leader_assign_advanced_day_chip_bbcode(province)],
		["leader_station_advanced_day", build_leader_station_advanced_day_chip_bbcode(province)],
		["leader_ops_advanced_day", build_leader_ops_advanced_day_chip_bbcode(province)],
		["leader_occupation_joint_day", build_leader_occupation_joint_day_chip_bbcode(province)],
		["leader_manpower_joint_day", build_leader_manpower_joint_day_chip_bbcode(province)],
		["leader_intel_joint_day", build_leader_intel_joint_day_chip_bbcode(province)],
		["leader_theater_joint_day", build_leader_theater_joint_day_chip_bbcode(province)],
		["occupation_manpower_leader_close_day", build_occupation_manpower_leader_close_day_chip_bbcode(province)],
		["medium_tank_production_honesty_product", build_medium_tank_production_honesty_product_chip_bbcode(province)],
		["medium_honesty_60d_day", build_medium_honesty_60d_day_chip_bbcode(province)],
		["medium_honesty_80d_day", build_medium_honesty_80d_day_chip_bbcode(province)],
		["medium_honesty_100d_day", build_medium_honesty_100d_day_chip_bbcode(province)],
		["medium_honesty_unit_stats_day", build_medium_honesty_unit_stats_day_chip_bbcode(province)],
		["medium_honesty_factory_risk_day", build_medium_honesty_factory_risk_day_chip_bbcode(province)],
		["medium_honesty_stockpile_day", build_medium_honesty_stockpile_day_chip_bbcode(province)],
		["medium_honesty_readiness_joint_day", build_medium_honesty_readiness_joint_day_chip_bbcode(province)],
		["medium_honesty_manpower_joint_day", build_medium_honesty_manpower_joint_day_chip_bbcode(province)],
		["medium_honesty_economy_joint_day", build_medium_honesty_economy_joint_day_chip_bbcode(province)],
		["medium_tank_production_honesty_close_day", build_medium_tank_production_honesty_close_day_chip_bbcode(province)],
		["apply_queue_live_managers_product", build_apply_queue_live_managers_product_chip_bbcode(province)],
		["apply_queue_audit_day", build_apply_queue_audit_day_chip_bbcode(province)],
		["apply_queue_production_live_day", build_apply_queue_production_live_day_chip_bbcode(province)],
		["apply_queue_combat_live_day", build_apply_queue_combat_live_day_chip_bbcode(province)],
		["apply_queue_supply_live_day", build_apply_queue_supply_live_day_chip_bbcode(province)],
		["apply_queue_focus_live_day", build_apply_queue_focus_live_day_chip_bbcode(province)],
		["apply_queue_agent_live_day", build_apply_queue_agent_live_day_chip_bbcode(province)],
		["apply_queue_station_live_day", build_apply_queue_station_live_day_chip_bbcode(province)],
		["apply_queue_six_leaf_joint_day", build_apply_queue_six_leaf_joint_day_chip_bbcode(province)],
		["apply_queue_honesty_joint_day", build_apply_queue_honesty_joint_day_chip_bbcode(province)],
		["apply_queue_live_managers_close_day", build_apply_queue_live_managers_close_day_chip_bbcode(province)],
		["occupation_resistance_compliance_product", build_occupation_resistance_compliance_product_chip_bbcode(province)],
		["manpower_laws_training_product", build_manpower_laws_training_product_chip_bbcode(province)],
		["peace_conference_settlement_product", build_peace_conference_settlement_product_chip_bbcode(province)],
		["occupation_resistance_board_day", build_occupation_resistance_board_day_chip_bbcode(province)],
		["occupation_resistance_policy_day", build_occupation_resistance_policy_day_chip_bbcode(province)],
		["occupation_resistance_tick_day", build_occupation_resistance_tick_day_chip_bbcode(province)],
		["occupation_resistance_close_day", build_occupation_resistance_close_day_chip_bbcode(province)],
		["manpower_law_board_day", build_manpower_law_board_day_chip_bbcode(province)],
		["manpower_train_pipeline_day", build_manpower_train_pipeline_day_chip_bbcode(province)],
		["manpower_field_trained_day", build_manpower_field_trained_day_chip_bbcode(province)],
		["manpower_laws_training_close_day", build_manpower_laws_training_close_day_chip_bbcode(province)],
		["peace_conference_board_day", build_peace_conference_board_day_chip_bbcode(province)],
		["peace_conference_demands_day", build_peace_conference_demands_day_chip_bbcode(province)],
		["peace_conference_settle_day", build_peace_conference_settle_day_chip_bbcode(province)],
		["peace_conference_campaign_close_day", build_peace_conference_campaign_close_day_chip_bbcode(province)],
		["product_ux_command_polish_product", build_product_ux_command_polish_product_chip_bbcode(province)],
		["designer_domain_live_product", build_designer_domain_live_product_chip_bbcode(province)],
		["campaign_ai_multi_month_product", build_campaign_ai_multi_month_product_chip_bbcode(province)],
		["product_ux_compact_day", build_product_ux_compact_day_chip_bbcode(province)],
		["product_ux_chips_day", build_product_ux_chips_day_chip_bbcode(province)],
		["product_ux_hotkeys_day", build_product_ux_hotkeys_day_chip_bbcode(province)],
		["product_ux_polish_close_day", build_product_ux_polish_close_day_chip_bbcode(province)],
		["designer_domain_catalog_day", build_designer_domain_catalog_day_chip_bbcode(province)],
		["designer_domain_pick_day", build_designer_domain_pick_day_chip_bbcode(province)],
		["designer_domain_seed_day", build_designer_domain_seed_day_chip_bbcode(province)],
		["designer_domain_live_close_day", build_designer_domain_live_close_day_chip_bbcode(province)],
		["campaign_ai_month_board_day", build_campaign_ai_month_board_day_chip_bbcode(province)],
		["campaign_ai_weekly_plan_day", build_campaign_ai_weekly_plan_day_chip_bbcode(province)],
		["campaign_ai_theater_execute_day", build_campaign_ai_theater_execute_day_chip_bbcode(province)],
		["campaign_ai_multi_month_close_day", build_campaign_ai_multi_month_close_day_chip_bbcode(province)],
		["occupation_revolt_garrison_product", build_occupation_revolt_garrison_product_chip_bbcode(province)],
		["manpower_cohort_reserve_product", build_manpower_cohort_reserve_product_chip_bbcode(province)],
		["multi_party_peace_conference_product", build_multi_party_peace_conference_product_chip_bbcode(province)],
		["occupation_revolt_board_day", build_occupation_revolt_board_day_chip_bbcode(province)],
		["occupation_revolt_garrison_day", build_occupation_revolt_garrison_day_chip_bbcode(province)],
		["occupation_revolt_suppress_day", build_occupation_revolt_suppress_day_chip_bbcode(province)],
		["occupation_revolt_garrison_close_day", build_occupation_revolt_garrison_close_day_chip_bbcode(province)],
		["manpower_cohort_board_day", build_manpower_cohort_board_day_chip_bbcode(province)],
		["manpower_cohort_reserve_day", build_manpower_cohort_reserve_day_chip_bbcode(province)],
		["manpower_cohort_mobilize_day", build_manpower_cohort_mobilize_day_chip_bbcode(province)],
		["manpower_cohort_reserve_close_day", build_manpower_cohort_reserve_close_day_chip_bbcode(province)],
		["multi_party_peace_board_day", build_multi_party_peace_board_day_chip_bbcode(province)],
		["multi_party_peace_wargoals_day", build_multi_party_peace_wargoals_day_chip_bbcode(province)],
		["multi_party_peace_settle_day", build_multi_party_peace_settle_day_chip_bbcode(province)],
		["multi_party_peace_campaign_close_day", build_multi_party_peace_campaign_close_day_chip_bbcode(province)],
		["historical_oob_content_product", build_historical_oob_content_product_chip_bbcode(province)],
		["tech_tree_branching_product", build_tech_tree_branching_product_chip_bbcode(province)],
		["save_resume_campaign_product", build_save_resume_campaign_product_chip_bbcode(province)],
		["historical_oob_catalog_day", build_historical_oob_catalog_day_chip_bbcode(province)],
		["historical_oob_seed_day", build_historical_oob_seed_day_chip_bbcode(province)],
		["historical_oob_equip_day", build_historical_oob_equip_day_chip_bbcode(province)],
		["historical_oob_content_close_day", build_historical_oob_content_close_day_chip_bbcode(province)],
		["tech_tree_branches_day", build_tech_tree_branches_day_chip_bbcode(province)],
		["tech_tree_path_day", build_tech_tree_path_day_chip_bbcode(province)],
		["tech_tree_field_day", build_tech_tree_field_day_chip_bbcode(province)],
		["tech_tree_branching_close_day", build_tech_tree_branching_close_day_chip_bbcode(province)],
		["save_resume_checkpoint_day", build_save_resume_checkpoint_day_chip_bbcode(province)],
		["save_resume_save_day", build_save_resume_save_day_chip_bbcode(province)],
		["save_resume_resume_day", build_save_resume_resume_day_chip_bbcode(province)],
		["save_resume_campaign_close_day", build_save_resume_campaign_close_day_chip_bbcode(province)],
		["tutorial_first_session_product", build_tutorial_first_session_product_chip_bbcode(province)],
		["focus_tree_content_product", build_focus_tree_content_product_chip_bbcode(province)],
		["balance_combat_supply_product", build_balance_combat_supply_product_chip_bbcode(province)],
		["tutorial_session_brief_day", build_tutorial_session_brief_day_chip_bbcode(province)],
		["tutorial_session_guide_day", build_tutorial_session_guide_day_chip_bbcode(province)],
		["tutorial_session_checkpoint_day", build_tutorial_session_checkpoint_day_chip_bbcode(province)],
		["tutorial_first_session_close_day", build_tutorial_first_session_close_day_chip_bbcode(province)],
		["focus_tree_catalog_day", build_focus_tree_catalog_day_chip_bbcode(province)],
		["focus_tree_path_day", build_focus_tree_path_day_chip_bbcode(province)],
		["focus_tree_commit_day", build_focus_tree_commit_day_chip_bbcode(province)],
		["focus_tree_content_close_day", build_focus_tree_content_close_day_chip_bbcode(province)],
		["balance_estimate_board_day", build_balance_estimate_board_day_chip_bbcode(province)],
		["balance_live_sample_day", build_balance_live_sample_day_chip_bbcode(province)],
		["balance_variance_close_day", build_balance_variance_close_day_chip_bbcode(province)],
		["balance_combat_supply_close_day", build_balance_combat_supply_close_day_chip_bbcode(province)],
		["air_multi_phase_theater_product", build_air_multi_phase_theater_product_chip_bbcode(province)],
		["naval_search_strike_product", build_naval_search_strike_product_chip_bbcode(province)],
		["war_economy_conversion_product", build_war_economy_conversion_product_chip_bbcode(province)],
		["air_theater_recon_day", build_air_theater_recon_day_chip_bbcode(province)],
		["air_theater_cas_gate_day", build_air_theater_cas_gate_day_chip_bbcode(province)],
		["air_theater_interdiction_day", build_air_theater_interdiction_day_chip_bbcode(province)],
		["air_multi_phase_theater_close_day", build_air_multi_phase_theater_close_day_chip_bbcode(province)],
		["naval_search_patrol_day", build_naval_search_patrol_day_chip_bbcode(province)],
		["naval_asw_escort_day", build_naval_asw_escort_day_chip_bbcode(province)],
		["naval_carrier_strike_day", build_naval_carrier_strike_day_chip_bbcode(province)],
		["naval_search_strike_close_day", build_naval_search_strike_close_day_chip_bbcode(province)],
		["economy_civ_board_day", build_economy_civ_board_day_chip_bbcode(province)],
		["economy_war_convert_day", build_economy_war_convert_day_chip_bbcode(province)],
		["economy_stockpile_sustain_day", build_economy_stockpile_sustain_day_chip_bbcode(province)],
		["war_economy_conversion_close_day", build_war_economy_conversion_close_day_chip_bbcode(province)],
		["designer_module_editor_product", build_designer_module_editor_product_chip_bbcode(province)],
		["designer_stats_field_product", build_designer_stats_field_product_chip_bbcode(province)],
		["designer_multi_domain_campaign_product", build_designer_multi_domain_campaign_product_chip_bbcode(province)],
		["designer_module_board_day", build_designer_module_board_day_chip_bbcode(province)],
		["designer_module_edit_day", build_designer_module_edit_day_chip_bbcode(province)],
		["designer_reliability_gate_day", build_designer_reliability_gate_day_chip_bbcode(province)],
		["designer_module_editor_close_day", build_designer_module_editor_close_day_chip_bbcode(province)],
		["designer_stats_board_day", build_designer_stats_board_day_chip_bbcode(province)],
		["designer_freeze_design_day", build_designer_freeze_design_day_chip_bbcode(province)],
		["designer_field_seed_day", build_designer_field_seed_day_chip_bbcode(province)],
		["designer_stats_field_close_day", build_designer_stats_field_close_day_chip_bbcode(province)],
		["designer_catalog_all_domains_day", build_designer_catalog_all_domains_day_chip_bbcode(province)],
		["designer_seed_multi_domain_day", build_designer_seed_multi_domain_day_chip_bbcode(province)],
		["designer_equip_campaign_close_day", build_designer_equip_campaign_close_day_chip_bbcode(province)],
		["designer_multi_domain_campaign_close_day", build_designer_multi_domain_campaign_close_day_chip_bbcode(province)],
		["weather_crisis_campaign_product", build_weather_crisis_campaign_product_chip_bbcode(province)],
		["intel_cell_network_product", build_intel_cell_network_product_chip_bbcode(province)],
		["leader_theater_command_product", build_leader_theater_command_product_chip_bbcode(province)],
		["weather_crisis_forecast_day", build_weather_crisis_forecast_day_chip_bbcode(province)],
		["weather_crisis_gate_multi_day", build_weather_crisis_gate_multi_day_chip_bbcode(province)],
		["weather_crisis_sustain_day", build_weather_crisis_sustain_day_chip_bbcode(province)],
		["weather_crisis_campaign_close_day", build_weather_crisis_campaign_close_day_chip_bbcode(province)],
		["intel_cell_coverage_day", build_intel_cell_coverage_day_chip_bbcode(province)],
		["intel_cell_ops_day", build_intel_cell_ops_day_chip_bbcode(province)],
		["intel_counter_sweep_day", build_intel_counter_sweep_day_chip_bbcode(province)],
		["intel_cell_network_close_day", build_intel_cell_network_close_day_chip_bbcode(province)],
		["leader_hq_board_day", build_leader_hq_board_day_chip_bbcode(province)],
		["leader_multi_station_day", build_leader_multi_station_day_chip_bbcode(province)],
		["leader_theater_ops_day", build_leader_theater_ops_day_chip_bbcode(province)],
		["leader_theater_command_close_day", build_leader_theater_command_close_day_chip_bbcode(province)],
		["strategic_war_goal_product", build_strategic_war_goal_product_chip_bbcode(province)],
		["multi_front_campaign_ai_product", build_multi_front_campaign_ai_product_chip_bbcode(province)],
		["grand_strategy_cycle_product", build_grand_strategy_cycle_product_chip_bbcode(province)],
		["war_goal_board_day", build_war_goal_board_day_chip_bbcode(province)],
		["war_goal_justify_day", build_war_goal_justify_day_chip_bbcode(province)],
		["war_goal_execute_day", build_war_goal_execute_day_chip_bbcode(province)],
		["strategic_war_goal_close_day", build_strategic_war_goal_close_day_chip_bbcode(province)],
		["multi_front_plan_day", build_multi_front_plan_day_chip_bbcode(province)],
		["multi_front_weekly_day", build_multi_front_weekly_day_chip_bbcode(province)],
		["multi_front_execute_day", build_multi_front_execute_day_chip_bbcode(province)],
		["multi_front_campaign_ai_close_day", build_multi_front_campaign_ai_close_day_chip_bbcode(province)],
		["gs_cycle_scan_day", build_gs_cycle_scan_day_chip_bbcode(province)],
		["gs_cycle_rank_day", build_gs_cycle_rank_day_chip_bbcode(province)],
		["gs_cycle_execute_day", build_gs_cycle_execute_day_chip_bbcode(province)],
		["grand_strategy_cycle_close_day", build_grand_strategy_cycle_close_day_chip_bbcode(province)],
		["alliance_guarantee_network_product", build_alliance_guarantee_network_product_chip_bbcode(province)],
		["faction_personality_ai_product", build_faction_personality_ai_product_chip_bbcode(province)],
		["occupation_revolt_network_product", build_occupation_revolt_network_product_chip_bbcode(province)],
		["occupation_visual_feedback", build_occupation_visual_chip_bbcode(province)],
		["alliance_board_day", build_alliance_board_day_chip_bbcode(province)],
		["alliance_guarantee_day", build_alliance_guarantee_day_chip_bbcode(province)],
		["alliance_coalition_day", build_alliance_coalition_day_chip_bbcode(province)],
		["alliance_guarantee_network_close_day", build_alliance_guarantee_network_close_day_chip_bbcode(province)],
		["personality_board_day", build_personality_board_day_chip_bbcode(province)],
		["personality_event_day", build_personality_event_day_chip_bbcode(province)],
		["personality_drive_day", build_personality_drive_day_chip_bbcode(province)],
		["faction_personality_ai_close_day", build_faction_personality_ai_close_day_chip_bbcode(province)],
		["revolt_network_map_day", build_revolt_network_map_day_chip_bbcode(province)],
		["revolt_cascade_risk_day", build_revolt_cascade_risk_day_chip_bbcode(province)],
		["revolt_network_suppress_day", build_revolt_network_suppress_day_chip_bbcode(province)],
		["occupation_revolt_network_close_day", build_occupation_revolt_network_close_day_chip_bbcode(province)],
		["campaign_alpha_primary_strip_product", build_campaign_alpha_primary_strip_product_chip_bbcode(province)],

		["focus_war_path_product", build_focus_war_path_product_chip_bbcode(province)],
		["naval_multi_phase_campaign_product", build_naval_multi_phase_campaign_product_chip_bbcode(province)],
		["focus_pick_board_advanced_day", build_focus_pick_board_advanced_day_chip_bbcode(province)],
		["focus_war_path_advanced_day", build_focus_war_path_advanced_day_chip_bbcode(province)],
		["focus_commit_execute_advanced_day", build_focus_commit_execute_advanced_day_chip_bbcode(province)],
		["focus_naval_effort_advanced_day", build_focus_naval_effort_advanced_day_chip_bbcode(province)],
		["focus_industry_army_joint_day", build_focus_industry_army_joint_day_chip_bbcode(province)],
		["focus_air_effort_joint_day", build_focus_air_effort_joint_day_chip_bbcode(province)],
		["focus_war_path_close_day", build_focus_war_path_close_day_chip_bbcode(province)],
		["naval_posture_advanced_day", build_naval_posture_advanced_day_chip_bbcode(province)],
		["naval_escort_phase_advanced_day", build_naval_escort_phase_advanced_day_chip_bbcode(province)],
		["naval_strike_phase_advanced_day", build_naval_strike_phase_advanced_day_chip_bbcode(province)],
		["naval_fleet_fuel_advanced_day", build_naval_fleet_fuel_advanced_day_chip_bbcode(province)],
		["naval_fleet_autonomy_joint_day", build_naval_fleet_autonomy_joint_day_chip_bbcode(province)],
		["naval_air_joint_advanced_day", build_naval_air_joint_advanced_day_chip_bbcode(province)],
		["naval_multi_phase_close_day", build_naval_multi_phase_close_day_chip_bbcode(province)],
		["designer_domain_advanced_day", build_designer_domain_advanced_day_chip_bbcode(province)],
		["designer_seed_advanced_day", build_designer_seed_advanced_day_chip_bbcode(province)],
		["strategic_ai_multi_day_advanced_day", build_strategic_ai_multi_day_advanced_day_chip_bbcode(province)],
		["designer_ai_industry_joint_day", build_designer_ai_industry_joint_day_chip_bbcode(province)],
		["play_session_advanced_joint_day", build_play_session_advanced_joint_day_chip_bbcode(province)],
		["advanced_deferred_campaign_close_day", build_advanced_deferred_campaign_close_day_chip_bbcode(province)],
		["play_session_campaign_product", build_play_session_campaign_product_chip_bbcode(province)],
		["air_ops_campaign_product", build_air_ops_campaign_product_chip_bbcode(province)],
		["strategic_ai_daily_campaign_product", build_strategic_ai_daily_campaign_product_chip_bbcode(province)],
		["multi_faction_strategic_ai_product", build_multi_faction_strategic_ai_product_chip_bbcode(province)],
		["designer_suite_product", build_designer_suite_product_chip_bbcode(province)],
		["assault_ready_surface_day", build_assault_ready_surface_day_chip_bbcode(province)],
		["combat_order_surface_day", build_combat_order_surface_day_chip_bbcode(province)],
		["phase_product_ops_day", build_phase_product_ops_day_chip_bbcode(province)],
		["multi_phase_joint_day", build_multi_phase_joint_day_chip_bbcode(province)],
		["save_prod_combat_close_day", build_save_prod_combat_close_day_chip_bbcode(province)],
		["naval_basing_sustain_day", build_naval_basing_sustain_day_chip_bbcode(province)],
		["port_fuel_depth_day", build_port_fuel_depth_day_chip_bbcode(province)],
		["basing_repair_depth_day", build_basing_repair_depth_day_chip_bbcode(province)],
		["fleet_task_sustain_day", build_fleet_task_sustain_day_chip_bbcode(province)],
		["convoy_basing_joint_day", build_convoy_basing_joint_day_chip_bbcode(province)],
		["naval_logistics_depth_day", build_naval_logistics_depth_day_chip_bbcode(province)],
		["naval_basing_close_day", build_naval_basing_close_day_chip_bbcode(province)],
		["multi_day_theater_depth_day", build_multi_day_theater_depth_day_chip_bbcode(province)],
		["theater_campaign_continuity_day", build_theater_campaign_continuity_day_chip_bbcode(province)],
		["campaign_day_chain_day", build_campaign_day_chain_day_chip_bbcode(province)],
		["theater_session_ops_day", build_theater_session_ops_day_chip_bbcode(province)],
		["daily_theater_sustain_day", build_daily_theater_sustain_day_chip_bbcode(province)],
		["theater_continuity_joint_day", build_theater_continuity_joint_day_chip_bbcode(province)],
		["theater_campaign_depth_close_day", build_theater_campaign_depth_close_day_chip_bbcode(province)],
		["inspector_decision_depth_day", build_inspector_decision_depth_day_chip_bbcode(province)],
		["decision_strip_depth_day", build_decision_strip_depth_day_chip_bbcode(province)],
		["insight_strip_depth_day", build_insight_strip_depth_day_chip_bbcode(province)],
		["province_decision_joint_day", build_province_decision_joint_day_chip_bbcode(province)],
		["inspector_campaign_ops_day", build_inspector_campaign_ops_day_chip_bbcode(province)],
		["theater_naval_inspector_close_day", build_theater_naval_inspector_close_day_chip_bbcode(province)],
		["weather_pressure_depth_day", build_weather_pressure_depth_day_chip_bbcode(province)],
		["foul_combat_ops_day", build_foul_combat_ops_day_chip_bbcode(province)],
		["weather_logistics_depth_day", build_weather_logistics_depth_day_chip_bbcode(province)],
		["weather_move_depth_day", build_weather_move_depth_day_chip_bbcode(province)],
		["weather_crisis_depth_day", build_weather_crisis_depth_day_chip_bbcode(province)],
		["weather_pressure_joint_day", build_weather_pressure_joint_day_chip_bbcode(province)],
		["weather_ops_close_depth_day", build_weather_ops_close_depth_day_chip_bbcode(province)],
		["trade_pressure_depth_day", build_trade_pressure_depth_day_chip_bbcode(province)],
		["sealane_health_depth_day", build_sealane_health_depth_day_chip_bbcode(province)],
		["war_economy_sustain_day", build_war_economy_sustain_day_chip_bbcode(province)],
		["stockpile_economy_depth_day", build_stockpile_economy_depth_day_chip_bbcode(province)],
		["convoy_economy_joint_day", build_convoy_economy_joint_day_chip_bbcode(province)],
		["trade_sealane_joint_day", build_trade_sealane_joint_day_chip_bbcode(province)],
		["war_economy_close_depth_day", build_war_economy_close_depth_day_chip_bbcode(province)],
		["force_ready_surface_day", build_force_ready_surface_day_chip_bbcode(province)],
		["formation_equip_depth_day", build_formation_equip_depth_day_chip_bbcode(province)],
		["reinforce_stockpile_depth_day", build_reinforce_stockpile_depth_day_chip_bbcode(province)],
		["readiness_board_ops_day", build_readiness_board_ops_day_chip_bbcode(province)],
		["force_reinforce_joint_day", build_force_reinforce_joint_day_chip_bbcode(province)],
		["weather_economy_force_close_day", build_weather_economy_force_close_day_chip_bbcode(province)],
		["strategic_ai_doctrine_depth_day", build_strategic_ai_doctrine_depth_day_chip_bbcode(province)],
		["strategic_ai_urgency_board_day", build_strategic_ai_urgency_board_day_chip_bbcode(province)],
		["strategic_ai_player_skip_day", build_strategic_ai_player_skip_day_chip_bbcode(province)],
		["strategic_ai_budget_depth_day", build_strategic_ai_budget_depth_day_chip_bbcode(province)],
		["strategic_ai_domain_weight_day", build_strategic_ai_domain_weight_day_chip_bbcode(province)],
		["strategic_ai_daily_joint_day", build_strategic_ai_daily_joint_day_chip_bbcode(province)],
		["strategic_ai_campaign_close_day", build_strategic_ai_campaign_close_day_chip_bbcode(province)],
		["designer_catalog_depth_day", build_designer_catalog_depth_day_chip_bbcode(province)],
		["designer_seed_production_day", build_designer_seed_production_day_chip_bbcode(province)],
		["designer_domain_balance_day", build_designer_domain_balance_day_chip_bbcode(province)],
		["oob_horizon_joint_day", build_oob_horizon_joint_day_chip_bbcode(province)],
		["production_line_bootstrap_day", build_production_line_bootstrap_day_chip_bbcode(province)],
		["industry_design_joint_day", build_industry_design_joint_day_chip_bbcode(province)],
		["designer_industry_close_day", build_designer_industry_close_day_chip_bbcode(province)],
		["theater_ai_command_joint_day", build_theater_ai_command_joint_day_chip_bbcode(province)],
		["fleet_ai_campaign_depth_day", build_fleet_ai_campaign_depth_day_chip_bbcode(province)],
		["agent_ai_campaign_depth_day", build_agent_ai_campaign_depth_day_chip_bbcode(province)],
		["combat_ai_phase_depth_day", build_combat_ai_phase_depth_day_chip_bbcode(province)],
		["save_session_ai_joint_day", build_save_session_ai_joint_day_chip_bbcode(province)],
		["full_game_campaign_close_day", build_full_game_campaign_close_day_chip_bbcode(province)],
		["air_ops_sortie_depth_day", build_air_ops_sortie_depth_day_chip_bbcode(province)],
		["air_forecast_planning_depth_day", build_air_forecast_planning_depth_day_chip_bbcode(province)],
		["air_sortie_weather_gate_day", build_air_sortie_weather_gate_day_chip_bbcode(province)],
		["convoy_escort_campaign_depth_day", build_convoy_escort_campaign_depth_day_chip_bbcode(province)],
		["air_land_campaign_depth_day", build_air_land_campaign_depth_day_chip_bbcode(province)],
		["air_front_readiness_depth_day", build_air_front_readiness_depth_day_chip_bbcode(province)],
		["air_convoy_campaign_close_day", build_air_convoy_campaign_close_day_chip_bbcode(province)],
		["focus_pick_depth_day", build_focus_pick_depth_day_chip_bbcode(province)],
		["focus_order_path_day", build_focus_order_path_day_chip_bbcode(province)],
		["focus_war_path_depth_day", build_focus_war_path_depth_day_chip_bbcode(province)],
		["war_path_urgency_depth_day", build_war_path_urgency_depth_day_chip_bbcode(province)],
		["intel_counter_depth_campaign_day", build_intel_counter_depth_campaign_day_chip_bbcode(province)],
		["leader_campaign_assign_day", build_leader_campaign_assign_day_chip_bbcode(province)],
		["focus_intel_leader_close_day", build_focus_intel_leader_close_day_chip_bbcode(province)],
		["order_execute_session_day", build_order_execute_session_day_chip_bbcode(province)],
		["next_day_feedback_session_day", build_next_day_feedback_session_day_chip_bbcode(province)],
		["campaign_decision_session_day", build_campaign_decision_session_day_chip_bbcode(province)],
		["theater_ai_session_joint_day", build_theater_ai_session_joint_day_chip_bbcode(province)],
		["force_readiness_session_day", build_force_readiness_session_day_chip_bbcode(province)],
		["play_session_campaign_close_day", build_play_session_campaign_close_day_chip_bbcode(province)],
	]
	for pair in pairs:
		if not (pair is Array) or pair.size() < 2:
			continue
		var cid := str(pair[0])
		var bb := str(pair[1]).strip_edges()
		if bb.is_empty():
			continue
		candidates.append({"id": cid, "bbcode": bb})
	var budget: Dictionary = MapPolishFormatters.budget_product_depth_chips(candidates, 8, true)
	if budget.is_empty() or not (budget.get("chips") is Array):
		# Fallback: take first 8
		budget = {"chips": candidates.slice(0, mini(8, candidates.size()))}
	for c in budget.get("chips", []):
		if c is Dictionary:
			var text := str(c.get("bbcode", "")).strip_edges()
			if not text.is_empty():
				lines.append(text)


static func build_war_cabinet_chip_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_war_cabinet_board_plain"):
		return ""
	var plain := str(GameData.format_war_cabinet_board_plain()).strip_edges()
	if plain.is_empty():
		return ""
	var out: PackedStringArray = []
	out.append("%s── War cabinet ──[/color]" % COLOR_HEADER)
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		out.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out)


static func build_campaign_strip_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var summaries: Array = []
	var a := build_fleet_weather_package_chip_bbcode(province)
	if not a.is_empty():
		summaries.append(a)
	var b := build_assault_readiness_chip_bbcode(province)
	if not b.is_empty():
		summaries.append(b)
	var c := build_counter_ops_chip_bbcode()
	if not c.is_empty():
		summaries.append(c)
	var d := build_supply_chain_health_chip_bbcode(province)
	if not d.is_empty():
		summaries.append(d)
	var strip: Dictionary = MapPolishFormatters.format_campaign_strip(summaries, 6)
	if bool(strip.get("empty", true)):
		return ""
	return str(strip.get("bbcode", "")).strip_edges()


static func build_convoy_package_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("convoy_package_for_province"):
		return ""
	var coastal := bool(province.is_sea)
	if not coastal and MapManager.has_method("get_province_terrain"):
		var terr: Dictionary = MapManager.get_province_terrain(province.id)
		var dom := str(terr.get("domain", "")).to_lower()
		coastal = dom.begins_with("coast") or dom == "strait" or dom == "sea"
	if not coastal:
		return ""
	var pkg: Dictionary = MapManager.convoy_package_for_province(province.id, 50.0, str(province.owner_tag))
	if pkg.is_empty() or bool(pkg.get("empty", false)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", ""))).strip_edges()


static func build_theater_readiness_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	# Live call site for theater_readiness_board: fleet+wx + assault readiness + day risk.
	var summaries: Array = []
	var fleet_s := build_fleet_weather_package_chip_bbcode(province)
	if not fleet_s.is_empty():
		summaries.append(fleet_s)
	var assault_s := build_assault_readiness_chip_bbcode(province)
	if not assault_s.is_empty():
		summaries.append(assault_s)
	var day_s := build_campaign_day_risk_chip_bbcode(province)
	if not day_s.is_empty():
		summaries.append(day_s)
	if summaries.is_empty():
		return ""
	var board: Dictionary = MapPolishFormatters.theater_readiness_board(summaries)
	if bool(board.get("empty", true)):
		return ""
	return str(board.get("bbcode", board.get("summary", ""))).strip_edges()


static func build_basing_logistics_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("basing_fleet_fuel_logistics_for_province"):
		return ""
	var pkg: Dictionary = MapManager.basing_fleet_fuel_logistics_for_province(
		province.id, 0.45, 100.0, "patrol", str(province.owner_tag)
	)
	if pkg.is_empty() or bool(pkg.get("empty", false)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", ""))).strip_edges()


static func build_assault_follow_on_chip_bbcode(province: Province) -> String:
	if province == null or typeof(BattleManager) == TYPE_NIL:
		return ""
	if not BattleManager.has_method("build_assault_follow_on_loop"):
		return ""
	var targets: Array = [{"province_id": province.id, "defender_power": 80.0}]
	var fo: Dictionary = BattleManager.build_assault_follow_on_loop(targets, 100.0, 1.0, province.id)
	if fo.is_empty() or bool(fo.get("empty", false)):
		return ""
	return str(fo.get("bbcode", fo.get("summary", ""))).strip_edges()


static func build_counter_ops_execute_chip_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_counter_ops_execute_order_plain"):
		return ""
	var plain := str(GameData.format_counter_ops_execute_order_plain()).strip_edges()
	if plain.is_empty():
		return ""
	return "%s◎ Execute[/color] %s— %s[/color]" % [COLOR_HEADER, COLOR_MUTED, plain]


static func build_agenda_execute_pick_chip_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_hh_agenda_execute_pick_plain"):
		return ""
	var plain := str(GameData.format_hh_agenda_execute_pick_plain()).strip_edges()
	if plain.is_empty():
		return ""
	var out: PackedStringArray = []
	out.append("%s── Agenda execute pick ──[/color]" % COLOR_HEADER)
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		out.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out)


static func build_move_path_ops_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("move_path_ops_for_province"):
		return ""
	var supply_h := 1.0
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_supply_weather_multiplier"):
		supply_h = float(WeatherManager.get_supply_weather_multiplier(province.id))
	var mp: Dictionary = MapManager.move_path_ops_for_province(province.id, 1.0, false, supply_h)
	return str(mp.get("bbcode", mp.get("summary", ""))).strip_edges()


static func build_basing_repair_weather_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("basing_repair_weather_for_province"):
		return ""
	var br: Dictionary = MapManager.basing_repair_weather_for_province(province.id)
	if bool(br.get("empty", true)):
		return ""
	return str(br.get("bbcode", br.get("summary", ""))).strip_edges()


static func build_sealane_joint_health_chip_bbcode(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not MapManager.has_method("sealane_joint_health_for_province"):
		return ""
	var sh: Dictionary = MapManager.sealane_joint_health_for_province(province.id, str(province.owner_tag))
	return str(sh.get("bbcode", sh.get("summary", ""))).strip_edges()


static func build_reinforced_assault_chip_bbcode(province: Province) -> String:
	if province == null or typeof(BattleManager) == TYPE_NIL:
		return ""
	if not BattleManager.has_method("build_reinforced_assault_loop"):
		return ""
	var targets: Array = [{"province_id": province.id, "defender_power": 80.0}]
	var ra: Dictionary = BattleManager.build_reinforced_assault_loop(targets, 100.0, 1.0, province.id)
	if ra.is_empty() or bool(ra.get("empty", false)):
		return ""
	return str(ra.get("bbcode", ra.get("summary", ""))).strip_edges()


static func build_war_path_urgency_chip_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_war_path_urgency_plain"):
		return ""
	var plain := str(GameData.format_war_path_urgency_plain()).strip_edges()
	if plain.is_empty():
		return ""
	return "%s◆ War path[/color] %s— %s[/color]" % [COLOR_HEADER, COLOR_MUTED, plain.split("\n")[0]]


static func build_oob_factory_risk_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var temp := 10.0
	var precip := 0.0
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_production_weather_multiplier"):
		var pm := float(WeatherManager.get_production_weather_multiplier(province.id))
		precip = clampf((1.0 - pm) * 2.0, 0.0, 1.0)
		if pm < 0.85:
			temp = -18.0
	var oob: Dictionary = MapPolishFormatters.oob_factory_risk_loop(temp, precip, "dry", 1.0, 0.2, 1.0)
	return str(oob.get("bbcode", "")).strip_edges()


static func build_force_supply_posture_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var supply_h := 1.0
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_supply_weather_multiplier"):
		supply_h = float(WeatherManager.get_supply_weather_multiplier(province.id))
	var vis := 1.0
	var precip := 0.0
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_combat_weather_multiplier"):
		vis = float(WeatherManager.get_combat_weather_multiplier(province.id))
		precip = clampf(1.0 - vis, 0.0, 1.0)
	var fs: Dictionary = MapPolishFormatters.force_supply_posture(50.0, supply_h, vis, precip, "dry", 0.2)
	return str(fs.get("bbcode", "")).strip_edges()


static func build_leader_weather_assign_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var ground := "dry"
	var vis := 1.0
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_supply_weather_multiplier"):
			var sm := float(WeatherManager.get_supply_weather_multiplier(province.id))
			if sm < 0.75:
				ground = "mud"
		if WeatherManager.has_method("get_combat_weather_multiplier"):
			vis = float(WeatherManager.get_combat_weather_multiplier(province.id))
	var lw: Dictionary = MapPolishFormatters.leader_weather_assign(0.7, ground, vis, false)
	return str(lw.get("bbcode", "")).strip_edges()


static func build_joint_ops_loop_strip_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var summaries: Array = []
	var a := build_basing_logistics_chip_bbcode(province)
	if not a.is_empty():
		summaries.append(a)
	var b := build_assault_follow_on_chip_bbcode(province)
	if not b.is_empty():
		summaries.append(b)
	var c := build_agenda_execute_pick_chip_bbcode()
	if not c.is_empty():
		summaries.append(c)
	if summaries.is_empty():
		return ""
	var strip: Dictionary = MapPolishFormatters.joint_ops_loop_strip(summaries)
	if bool(strip.get("empty", true)):
		return ""
	return str(strip.get("bbcode", "")).strip_edges()


## Agent counterplay options pilot from last HH map signal (province-targeted).

static func build_fleet_campaign_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("fleet_campaign_plan_for_province"):
		return ""
	var pkg: Dictionary = MapManager.fleet_campaign_plan_for_province(int(province.id), 0.55, 100.0, "")
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_combat_campaign_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var pkg: Dictionary = MapPolishFormatters.combat_campaign_phase(100.0, 0.85, 1.0, 0.0, 6, false, [])
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_campaign_decision_strip_chip_bbcode(province: Province) -> String:
	var summaries: Array = []
	var a := build_fleet_campaign_chip_bbcode(province)
	if not a.is_empty():
		summaries.append(a.split("\n")[0])
	var b := build_combat_campaign_chip_bbcode(province)
	if not b.is_empty():
		summaries.append(b.split("\n")[0])
	var c := build_joint_ops_loop_strip_chip_bbcode(province)
	if not c.is_empty():
		summaries.append(c.split("\n")[0])
	if summaries.is_empty():
		return ""
	var strip: Dictionary = MapPolishFormatters.campaign_decision_strip(summaries)
	if bool(strip.get("empty", true)):
		return ""
	return str(strip.get("bbcode", strip.get("summary", "")))



static func build_fleet_order_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("fleet_order_execute_for_province"):
		return ""
	var pkg: Dictionary = MapManager.fleet_order_execute_for_province(int(province.id), 0.55, 100.0)
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_combat_order_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("combat_order_execute_for_province"):
		return ""
	var pkg: Dictionary = MapManager.combat_order_execute_for_province(int(province.id), 100.0, 0.85)
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_execution_decision_strip_chip_bbcode(province: Province) -> String:
	var summaries: Array = []
	var a := build_fleet_order_chip_bbcode(province)
	if not a.is_empty():
		summaries.append(a.split("\n")[0])
	var b := build_combat_order_chip_bbcode(province)
	if not b.is_empty():
		summaries.append(b.split("\n")[0])
	var c := build_campaign_decision_strip_chip_bbcode(province)
	if not c.is_empty():
		summaries.append(c.split("\n")[0])
	if summaries.is_empty():
		return ""
	var strip: Dictionary = MapPolishFormatters.execution_decision_strip(summaries)
	if bool(strip.get("empty", true)):
		return ""
	return str(strip.get("bbcode", strip.get("summary", "")))


static func build_map_effect_order_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("fleet_order_execute_for_province"):
		return ""
	var order_pkg: Dictionary = MapManager.fleet_order_execute_for_province(int(province.id), 0.55, 100.0)
	if bool(order_pkg.get("empty", true)):
		return ""
	var effect: Dictionary = MapPolishFormatters.map_effect_resolve(
		str(order_pkg.get("order", "")), int(province.id), float(order_pkg.get("score", 0.5))
	)
	if bool(effect.get("empty", true)):
		return ""
	return str(effect.get("bbcode", effect.get("summary", "")))


static func build_next_day_feedback_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("fleet_order_execute_for_province"):
		return ""
	var a: Dictionary = MapManager.fleet_order_execute_for_province(int(province.id), 0.55, 100.0)
	var b: Dictionary = MapManager.fleet_order_execute_for_province(int(province.id), 0.35, 80.0)
	var fb: Dictionary = MapPolishFormatters.next_day_feedback(
		float(a.get("score", 0.5)), float(b.get("score", 0.4)), str(a.get("order", ""))
	)
	return str(fb.get("bbcode", fb.get("summary", "")))


static func build_execution_integrity_chip_bbcode() -> String:
	var gate: Dictionary = MapPolishFormatters.execution_integrity_gate(1.1, 0.8, 0.2, 1.0)
	return str(gate.get("bbcode", gate.get("summary", "")))



static func build_fleet_station_mutation_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("fleet_station_mutation_for_province"):
		return ""
	var pkg: Dictionary = MapManager.fleet_station_mutation_for_province(int(province.id), "", "", 0.55)
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_mutation_decision_strip_chip_bbcode(province: Province) -> String:
	var summaries: Array = []
	var a := build_fleet_station_mutation_chip_bbcode(province)
	if not a.is_empty():
		summaries.append(a.split("\n")[0])
	var b := build_fleet_order_chip_bbcode(province)
	if not b.is_empty():
		summaries.append(b.split("\n")[0])
	var c := ""
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_mutation_decision_strip_plain"):
		c = str(GameData.format_mutation_decision_strip_plain())
	if not c.is_empty():
		summaries.append(c.split("\n")[0])
	if summaries.is_empty():
		return ""
	var strip: Dictionary = MapPolishFormatters.mutation_decision_strip(summaries)
	if bool(strip.get("empty", true)):
		return ""
	return str(strip.get("bbcode", strip.get("summary", "")))


static func build_production_priority_mutation_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("production_priority_mutation_for_province"):
		return ""
	var pkg: Dictionary = MapManager.production_priority_mutation_for_province(int(province.id), "primary")
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_mutation_integrity_chip_bbcode() -> String:
	var gate: Dictionary = MapPolishFormatters.mutation_integrity_gate(1.1, 0.8, 0.2, 1.1)
	return str(gate.get("bbcode", gate.get("summary", "")))



static func build_theater_command_strip_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("theater_command_surface_for_province"):
		return ""
	var pkg: Dictionary = MapManager.theater_command_surface_for_province(int(province.id))
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_player_order_surface_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("player_order_surface_for_province"):
		return ""
	var pkg: Dictionary = MapManager.player_order_surface_for_province(int(province.id))
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_theater_daily_brief_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("theater_daily_brief_for_province"):
		return ""
	var pkg: Dictionary = MapManager.theater_daily_brief_for_province(int(province.id))
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_order_queue_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("order_queue_for_province"):
		return ""
	var pkg: Dictionary = MapManager.order_queue_for_province(int(province.id))
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_command_integrity_chip_bbcode() -> String:
	var gate: Dictionary = MapPolishFormatters.command_integrity_gate(1.1, 0.8, 0.2, 1.1)
	return str(gate.get("bbcode", gate.get("summary", "")))



static func build_command_result_log_chip_bbcode() -> String:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("format_command_result_log_plain"):
		return ""
	var plain := str(GameData.format_command_result_log_plain(6)).strip_edges()
	if plain.is_empty():
		return ""
	var trail: Array = GameData.get_command_result_log(6) if GameData.has_method("get_command_result_log") else []
	var surf: Dictionary = MapPolishFormatters.format_command_log_surface(trail, 6)
	return str(surf.get("bbcode", plain))


static func build_theater_day_report_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("theater_day_report_for_province"):
		return ""
	var pkg: Dictionary = MapManager.theater_day_report_for_province(int(province.id))
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_daily_apply_integrity_chip_bbcode() -> String:
	var gate: Dictionary = MapPolishFormatters.daily_apply_integrity_gate(1.1, 0.8, 0.2, 1.1)
	return str(gate.get("bbcode", gate.get("summary", "")))



static func build_order_panel_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("order_panel_actions_for_province"):
		return ""
	var pkg: Dictionary = MapManager.order_panel_actions_for_province(int(province.id))
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_war_economy_day_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("war_economy_day_for_province"):
		return ""
	var pkg: Dictionary = MapManager.war_economy_day_for_province(int(province.id))
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_logistics_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if MapManager.has_method("sealane_choke_logistics_day_for_province"):
		var pkg: Dictionary = MapManager.sealane_choke_logistics_day_for_province(int(province.id))
		if not bool(pkg.get("empty", true)):
			return str(pkg.get("bbcode", pkg.get("summary", "")))
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_logistics_day_plain"):
		var plain := str(GameData.format_logistics_day_plain(int(province.id))).strip_edges()
		if not plain.is_empty():
			return "[color=#5ec8ff]Logistics[/color] [color=#8899aa]%s[/color]" % plain.split("\n")[0]
	return ""


static func build_theater_day_command_strip_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("theater_day_command_strip_live"):
		return ""
	var pkg: Dictionary = MapManager.theater_day_command_strip_live(int(province.id), "")
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))




static func build_multi_province_live_chip_bbcode() -> String:
	if not MapManager.has_method("multi_province_live_plan_for_tag"):
		return ""
	var pkg: Dictionary = MapManager.multi_province_live_plan_for_tag("", 4)
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_combat_phase_depth_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("combat_phase_depth_for_province"):
		return ""
	var pkg: Dictionary = MapManager.combat_phase_depth_for_province(int(province.id))
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_fleet_patrol_depth_chip_bbcode() -> String:
	if not MapManager.has_method("fleet_patrol_depth_for_tag"):
		return ""
	var pkg: Dictionary = MapManager.fleet_patrol_depth_for_tag("", 0.7)
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_ops_depth_integrity_chip_bbcode() -> String:
	var gate: Dictionary = MapPolishFormatters.ops_depth_integrity_gate(1.1, 0.8, 0.2, 1.1)
	return str(gate.get("bbcode", gate.get("summary", "")))


static func build_production_campaign_risk_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var temp := 10.0
	var precip := 0.0
	var ground := "dry"
	var vis := 1.0
	var wind := 0.2
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_province_weather"):
		var w: Dictionary = WeatherManager.get_province_weather(int(province.id))
		if w is Dictionary:
			temp = float(w.get("temperature_c", w.get("temp", 10.0)))
			precip = float(w.get("precip_intensity", w.get("precip", 0.0)))
			ground = str(w.get("ground_state", "dry"))
			vis = float(w.get("visibility", 1.0))
			wind = float(w.get("wind", 0.2))
	var pkg: Dictionary = MapPolishFormatters.production_campaign_risk(temp, precip, ground, vis, wind, 1.0)
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_supply_campaign_spine_chip_bbcode(province: Province) -> String:
	if province == null or not MapManager.has_method("supply_campaign_spine_for_province"):
		return ""
	var pkg: Dictionary = MapManager.supply_campaign_spine_for_province(int(province.id), 1.0)
	if bool(pkg.get("empty", true)):
		return ""
	return str(pkg.get("bbcode", pkg.get("summary", "")))


static func build_cohesion_integrity_chip_bbcode() -> String:
	var gate: Dictionary = MapPolishFormatters.cohesion_integrity_gate(1.1, 0.8, 0.2)
	return str(gate.get("bbcode", gate.get("summary", "")))


static func build_agent_counterplay_inspector_bbcode(province: Province) -> String:
	if province == null or typeof(GameData) == TYPE_NIL or not GameData.has_method("get_peace_state"):
		return ""
	var ps: Dictionary = GameData.get_peace_state()
	var sig: Dictionary = ps.get("hh_last_map_signal", {}) if ps is Dictionary else {}
	if sig.is_empty() or not bool(sig.get("active", false)):
		return ""
	var sig_pid := int(sig.get("province_id", -1))
	if sig_pid >= 0 and sig_pid != province.id:
		return ""
	var action := str(sig.get("action_class", "influence")).to_lower()
	var options: PackedStringArray = []
	match action:
		"sabotage":
			options = PackedStringArray([
				"Deploy counter-intel agents",
				"Rush infrastructure repair",
				"Raise province security",
			])
		"economic_pressure":
			options = PackedStringArray([
				"Divert trade routes",
				"Release strategic stockpile",
				"Subsidize local industry",
			])
		"infiltration":
			options = PackedStringArray([
				"Loyalty security sweep",
				"Counter-propaganda campaign",
				"Hunt enemy agents",
			])
		_:
			options = PackedStringArray([
				"Open intelligence investigation",
				"Issue policy response",
			])
	var out: PackedStringArray = []
	out.append("%s── Agent counterplay ──[/color]" % COLOR_HEADER)
	out.append(
		"%sCounterplay vs %s[/color]" % [COLOR_MUTED, action]
	)
	for o in options:
		out.append("%s◇ %s[/color]" % [COLOR_MUTED, o])
	return "\n".join(out)


## Multi-month HH agenda trail from GameData (source of truth: hh_agenda_trail).
static func build_hh_agenda_trail_inspector_bbcode(max_lines: int = 4) -> String:
	if typeof(GameData) == TYPE_NIL:
		return ""
	var plain := ""
	if GameData.has_method("format_hh_agenda_trail_plain"):
		plain = str(GameData.format_hh_agenda_trail_plain(max_lines)).strip_edges()
	elif GameData.has_method("get_hh_agenda_trail"):
		var trail: Array = GameData.get_hh_agenda_trail()
		var bits: PackedStringArray = []
		var start := maxi(0, trail.size() - maxi(1, max_lines))
		for i in range(start, trail.size()):
			var e: Variant = trail[i]
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var s := str((e as Dictionary).get("summary", "")).strip_edges()
			if s.is_empty():
				s = str((e as Dictionary).get("label", ""))
			if not s.is_empty():
				bits.append(s)
		plain = "\n".join(bits)
	if plain.is_empty():
		return ""
	var out_lines: PackedStringArray = []
	out_lines.append("%s── ◈ Hidden Hand agenda (recent) ──[/color]" % COLOR_HEADER)
	for ln in plain.split("\n"):
		var t := str(ln).strip_edges()
		if t.is_empty():
			continue
		out_lines.append("%s%s[/color]" % [COLOR_MUTED, t])
	return "\n".join(out_lines)


static func build_province_infrastructure_card_bbcode(
	province: Province,
	compact: bool = true,
) -> String:
	if not province_needs_infrastructure_ui(province):
		return ""
	var bd := _infra_repair_breakdown(province)
	var tag_early := country_tag_for_province(province)
	# Investment-only path: show project progress/sabo even when repair breakdown is empty.
	if bd.is_empty():
		var invest_only := _build_active_investment_project_line(province, tag_early)
		if invest_only.is_empty():
			return ""
		return "%s── 🚧 Infrastructure project ──[/color]\n%s" % [COLOR_HEADER, invest_only]
	var rate := float(bd.get("total", 0.0))
	var infra := int(bd.get("infrastructure", province.infrastructure))
	var status := _pressure_status_label(province, bd)
	var accent := COLOR_MUTED
	if status in ["UNDER SABOTAGE", "SUPPLY PRESSURE", "DEPOT SABOTAGED"] or infra <= 15:
		accent = COLOR_WARN
	elif status == "RECOVERING":
		accent = COLOR_TECH

	var lines: PackedStringArray = []
	var status_icon := "⛟" if status == "SUPPLY PRESSURE" else "⚙"
	var verdict := build_sabotage_verdict_block_bbcode(province, bd, compact)
	lines.append("%s── %s Sabotage & repair ──[/color]" % [COLOR_HEADER, status_icon])
	if not verdict.is_empty():
		lines.append(verdict)
	var duel := build_sabotage_repair_duel_bbcode(province, bd, compact)
	if not duel.is_empty():
		lines.append(duel)
	var engineer_sec := build_engineer_presence_section_bbcode(province, bd, compact)
	if not engineer_sec.is_empty():
		lines.append(engineer_sec)
	var tag := country_tag_for_province(province)
	if _province_matches_country(province, tag):
		if compact:
			var div_hint := build_engineer_divisions_at_province_bbcode(province, tag, true)
			if not div_hint.is_empty() and div_hint not in engineer_sec:
				lines.append(div_hint)
			var roster_hint := build_engineer_capable_divisions_hint_bbcode(tag, true)
			if (
				not roster_hint.is_empty()
				and engineer_sec.is_empty()
				and province_needs_engineer_assignment(province, bd)
			):
				lines.append(roster_hint)
		else:
			var roster := build_engineer_roster_inspector_bbcode(tag, province.id)
			if not roster.is_empty():
				lines.append(roster)
	var eng_pre := float(bd.get("engineer_brigades", 0.0))
	var stab_pre := float(bd.get("stability_bonus", 0.0))
	var tech_pre := float(bd.get("tech_focus_bonus", 0.0))
	var has_repair_contrib_pre := eng_pre > 0.0 or absf(stab_pre) > 0.001 or tech_pre > 0.001
	if compact and has_repair_contrib_pre and engineer_sec.is_empty():
		var glance_pre := build_repair_contributions_glance_for_province(province, bd)
		if not glance_pre.is_empty():
			lines.append(glance_pre)
	elif compact and status == "UNDER SABOTAGE" and engineer_sec.is_empty():
		var glance_pre := build_repair_contributions_glance_for_province(province, bd)
		if not glance_pre.is_empty():
			lines.append(glance_pre)
	if not compact:
		lines.append("%s%s %s[/color]" % [accent, status_icon, status.replace("_", " ")])

	if status == "SUPPLY PRESSURE":
		var fill := depot_fill_ratio(province.id)
		if fill >= 0.0:
			lines.append(
				"%s⛟ Daily supply disruption · depot stock %d%%[/color]"
				% [COLOR_WARN if fill < 0.4 else COLOR_MUTED, int(round(fill * 100.0))]
			)
		else:
			lines.append("%s⛟ Daily supply disruption on this province[/color]" % COLOR_WARN)
		if _province_matches_country(province, tag):
			var radio_hint := MapTechnologyContext.build_support_recovery_hint_bbcode(tag)
			if not radio_hint.is_empty():
				lines.append(radio_hint)

	if infra < 50 or bool(bd.get("under_infra_sabotage", false)):
		var winner := _daily_infra_duel_winner(province, bd) if status == "UNDER SABOTAGE" else ""
		var sabotage_winning := winner == "sabotage"
		var repair_winning := winner == "repair"
		var net_loss := 0
		var net_gain := 0.0
		if sabotage_winning:
			var chip_d := estimate_daily_infra_chip_damage(province)
			net_loss = maxi(1, chip_d - int(floor(rate)))
		elif repair_winning:
			net_gain = rate
		lines.append(
			build_infra_progress_meter_bbcode(
				infra, 10, sabotage_winning, net_loss, repair_winning, net_gain,
			)
		)

	# === Active provincial investment project (new Phase A integration) ===
	var project_line := _build_active_investment_project_line(province, tag)
	if not project_line.is_empty():
		lines.append(project_line)
		if not compact:
			lines.append(
				"%sInfra %d / 50  ·  Repair rate +%.2f/day[/color]" % [accent, infra, rate]
			)
	elif not compact:
		lines.append("%sInfra %d / 50 (undamaged)[/color]" % [COLOR_MUTED, infra])

	var depot_sab := float(bd.get("depot_sabotage_level", 0.0))
	if depot_sab > 0.05 and status != "SUPPLY PRESSURE":
		lines.append(
			"%s⛟ Depot throughput sabotage %.0f%% (fades ~13%/day)[/color]"
			% [COLOR_WARN if depot_sab > 0.2 else COLOR_MUTED, depot_sab * 100.0]
		)
	elif depot_sab > 0.05 and status == "SUPPLY PRESSURE":
		lines.append(
			"%s⛟ Depot throughput penalty %.0f%% (fades ~13%/day)[/color]"
			% [COLOR_WARN if depot_sab > 0.2 else COLOR_MUTED, depot_sab * 100.0]
		)

	var eta := int(bd.get("eta_days_to_cap", -1))
	if eta > 0 and eta < 500 and infra < 50 and status != "RECOVERING":
		var eta_txt := "~%d days to reach infra 50 at current repair" % eta
		if bool(bd.get("under_infra_sabotage", false)):
			eta_txt += " (if sabotage stops)"
		lines.append("%s%s[/color]" % [COLOR_MUTED, eta_txt])

	var source := build_infra_sabotage_source_bbcode(province)
	if source.is_empty():
		source = build_supply_disruption_source_bbcode(province)
	if not source.is_empty():
		lines.append(source)

	var eng := float(bd.get("engineer_brigades", 0.0))
	var stab := float(bd.get("stability_bonus", 0.0))
	var tech := float(bd.get("tech_focus_bonus", 0.0))
	var has_repair_contrib := eng > 0.0 or absf(stab) > 0.001 or tech > 0.001
	var show_breakdown := not compact and (
		infra < 50
		or bool(bd.get("under_infra_sabotage", false))
		or has_repair_contrib
	)
	var breakdown := build_infra_repair_breakdown_bbcode(province, true)
	if not breakdown.is_empty() and show_breakdown:
		lines.append(breakdown)
	elif not compact and (has_repair_contrib or status == "UNDER SABOTAGE"):
		var glance := build_repair_contributions_glance_for_province(province, bd)
		if not glance.is_empty():
			lines.append(glance)

	if not compact:
		lines.append(
			"%sCounter-intel clears depot sabotage; infra heals via daily repair pass.[/color]"
			% COLOR_MUTED
		)
	return "\n".join(lines)


static func build_province_infra_repair_bbcode(province: Province) -> String:
	return build_province_infrastructure_card_bbcode(province, true)


static func province_needs_infrastructure_ui(province: Province) -> bool:
	if province == null:
		return false
	if agent_applies_daily_pressure(province):
		return true
	if province.infrastructure < 50:
		return true
	# Active provincial investment must surface progress/cancel/sabo even at high infra.
	var mgr := _get_infra_mgr_for_insight()
	if mgr != null and mgr.has_method("has_active_project") and mgr.has_active_project(province.id):
		return true
	if typeof(MapManager) != TYPE_NIL:
		var bd := MapManager.get_infrastructure_repair_breakdown(province.id)
		if float(bd.get("depot_sabotage_level", 0.0)) > 0.05:
			return true
	return false


static func build_province_infrastructure_section_bbcode(province: Province) -> String:
	var base := build_province_infrastructure_card_bbcode(province, false)
	var sites_block := build_special_sites_effect_bbcode(province, false)
	if not sites_block.is_empty():
		if not base.is_empty():
			base += "\n"
		base += sites_block
	var choke := build_naval_chokepoint_badge_bbcode(province)
	if not choke.is_empty():
		if not base.is_empty():
			base += "\n"
		base += choke
	return base


## Hover/inspector: special sites with readable names + effect readout (supply/trade/etc.).
## Delegates pure formatting to MapPolishFormatters (shipped pure helpers).
static func build_special_sites_effect_bbcode(province: Province, compact: bool = true) -> String:
	if province == null or province.special_sites.is_empty():
		return ""
	var lines: PackedStringArray = []
	var ssm = null
	if typeof(SpecialSiteManager) != TYPE_NIL:
		ssm = SpecialSiteManager
	for site in province.special_sites:
		if site == null:
			continue
		var display := str(site.id).replace("_", " ")
		var def: Dictionary = {}
		if ssm != null and ssm.has_method("get_site_definition"):
			def = ssm.get_site_definition(site.id)
			if def.has("name"):
				display = str(def["name"])
		var effects: Dictionary = def.get("effects", {}) if not def.is_empty() else {}
		var state: String = _MapPolishFormatters.site_state_icon(
			site.is_completed(), site.is_under_construction(), site.is_damaged()
		)
		var under_c := site.is_under_construction()
		var bits: PackedStringArray = _MapPolishFormatters.format_site_effect_bits(
			float(site.supply_bonus),
			float(site.trade_capacity),
			effects,
			float(site.construction_progress) if under_c else -1.0,
			int(site.damage_level) if site.is_damaged() else 0,
		)
		var desc := str(def.get("description", "")) if not compact else ""
		lines.append(
			_MapPolishFormatters.format_special_site_line(
				str(site.id), display, int(site.tier), state, bits, compact, desc
			)
		)
	return _MapPolishFormatters.format_special_sites_block(lines, compact)


## Badge when province is a data-driven naval chokepoint / strait (contest state).
static func build_naval_chokepoint_badge_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("has_strategic_chokepoint"):
		return ""
	if not MapManager.has_strategic_chokepoint(province.id):
		return ""
	if MapManager.has_method("get_chokepoint_contest_state"):
		var contest: Dictionary = MapManager.get_chokepoint_contest_state(province.id)
		if not contest.is_empty():
			return _MapPolishFormatters.format_chokepoint_contest_badge(contest)
	var bonus := 1.0
	if MapManager.has_method("get_chokepoint_or_river_supply_bonus"):
		bonus = MapManager.get_chokepoint_or_river_supply_bonus(province.id)
	var owner_tag := ""
	var ctrl_tag := ""
	if "owner_tag" in province:
		owner_tag = str(province.owner_tag)
	if "controller_tag" in province:
		ctrl_tag = str(province.controller_tag)
	if ctrl_tag.is_empty() and MapManager.has_method("get_province_controller"):
		ctrl_tag = str(MapManager.get_province_controller(province.id))
	if owner_tag.is_empty() and MapManager.has_method("get_province_owner"):
		owner_tag = str(MapManager.get_province_owner(province.id))
	return _MapPolishFormatters.format_chokepoint_badge(bonus, ctrl_tag, owner_tag)


## Naval basing pilot badge (anchorage / port / major_base + capacity).
static func build_naval_basing_badge_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) == TYPE_NIL:
		return ""
	var basing: Dictionary = {}
	if MapManager.has_method("get_naval_basing"):
		basing = MapManager.get_naval_basing(province.id)
	elif MapManager.has_method("get_naval_basing_for_province"):
		basing = MapManager.get_naval_basing_for_province(province.id)
	else:
		# Fallback: derive signals locally and call pure formatter
		var domain := ""
		var facility := ""
		var is_coastal := false
		var is_sea := bool(province.is_sea)
		if MapManager.has_method("get_province_terrain"):
			var terr: Dictionary = MapManager.get_province_terrain(province.id)
			domain = str(terr.get("domain", ""))
			facility = str(terr.get("facility_tier", ""))
			var tdom := domain.to_lower()
			is_coastal = tdom == "coastal_land" or tdom == "coastal"
			if tdom == "sea" or tdom == "ocean":
				is_sea = true
		var choke := false
		if MapManager.has_method("has_strategic_chokepoint"):
			choke = MapManager.has_strategic_chokepoint(province.id)
		var in_zone := false
		if MapManager.has_method("get_sea_zone_name"):
			in_zone = not str(MapManager.get_sea_zone_name(province.id)).strip_edges().is_empty()
		var has_port := bool(province.has_port)
		var port_tier := 0
		var shipyard := false
		if province.special_sites != null:
			for site in province.special_sites:
				if site == null or not site.is_completed():
					continue
				if site.site_type == SpecialSite.SiteType.PORT:
					has_port = true
					port_tier = maxi(port_tier, int(site.tier))
				elif site.site_type == SpecialSite.SiteType.NAVAL_SHIPYARD:
					shipyard = true
		basing = _MapPolishFormatters.compute_naval_basing(
			domain,
			is_sea,
			is_coastal,
			has_port,
			port_tier,
			shipyard,
			shipyard,
			choke,
			facility,
			in_zone,
			province.id,
		)
	if basing.is_empty() or not bool(basing.get("is_naval", false)):
		return ""
	return _MapPolishFormatters.format_naval_basing_badge(basing)


## Sea-zone theater label + control stub (unowned / contested / controlled by TAG).
static func build_sea_zone_badge_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_sea_zone_name"):
		return ""
	var zname := str(MapManager.get_sea_zone_name(province.id)).strip_edges()
	if zname.is_empty():
		return ""
	if MapManager.has_method("get_sea_zone_control"):
		var ctrl: Dictionary = MapManager.get_sea_zone_control(zname)
		if not ctrl.is_empty():
			return _MapPolishFormatters.format_sea_zone_control_badge(
				str(ctrl.get("zone", zname)),
				str(ctrl.get("controller", "")),
				bool(ctrl.get("contested", false)),
				bool(ctrl.get("unowned", false)),
			)
	# Fallback: still show strategic modifiers if control API missing but zone known
	if MapManager.has_method("get_sea_zone_strategic_modifiers"):
		var mods: Dictionary = MapManager.get_sea_zone_strategic_modifiers(zname)
		if not mods.is_empty():
			return (
				"[color=#5ec8ff]🌊 Sea zone[/color] [color=#8899aa]%s — %s[/color]"
				% [zname, str(mods.get("summary", "naval theater"))]
			)
	return "[color=#5ec8ff]🌊 Sea zone[/color] [color=#8899aa]%s — naval ops / convoy theater[/color]" % zname


## Shows active "Invest in Infrastructure" project status in hover tooltips and inspector.
## Uses real IDM get_project_status → MapPolishFormatters pure line builder.
static func _build_active_investment_project_line(province: Province, country_tag: String) -> String:
	if province == null:
		return ""
	var mgr := _get_infra_mgr_for_insight()
	if mgr == null or not mgr.has_method("has_active_project"):
		return ""
	if not mgr.has_active_project(province.id):
		return ""

	var st: Dictionary = {}
	if mgr.has_method("get_project_status"):
		st = mgr.get_project_status(province.id)
	if st.is_empty():
		return ""
	return _MapPolishFormatters.format_investment_status_line(st, province.infrastructure)


static func _get_infra_mgr_for_insight() -> Object:
	if typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		return InfrastructureDevelopmentManager
	# Soft fallback
	if Engine.has_singleton("InfrastructureDevelopmentManager"):
		return Engine.get_singleton("InfrastructureDevelopmentManager")
	return null


static func build_supply_pressure_recovery_bbcode(province: Province) -> String:
	if province == null or agent_pressure_focus_kind(province) != "disrupt":
		return ""
	var fill := depot_fill_ratio(province.id)
	if fill < 0.0:
		return (
			"%s⛟ Supply pressure: national debuff + local depot hits each day.[/color]"
			% COLOR_WARN
		)
	var pct := int(round(fill * 100.0))
	var depot_note := "%s⛟ Depot %d%% — daily agent drain; refills via routes & local generation.[/color]" % [
		COLOR_WARN if fill < 0.4 else COLOR_MUTED, pct,
	]
	var tag := country_tag_for_province(province)
	if _province_matches_country(province, tag) and MapTechnologyContext.has_support_radio_bonuses(tag):
		var routes := MapTechnologyContext.build_support_route_summary_plain(tag)
		if not routes.is_empty():
			depot_note += "\n%s📡 %s helps recovery on your routes.[/color]" % [COLOR_TECH, routes]
	return depot_note


static func build_province_pressure_recovery_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var parts: PackedStringArray = []
	var kind := agent_pressure_focus_kind(province)
	if kind == "disrupt":
		var supply_line := build_supply_pressure_recovery_bbcode(province)
		if not supply_line.is_empty():
			parts.append(supply_line)
	if parts.is_empty():
		return ""
	return "\n".join(parts)


static func build_province_pressure_recovery_compact(province: Province) -> String:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return ""
	if not agent_applies_daily_pressure(province):
		return ""
	var bits: PackedStringArray = []
	var kind := agent_pressure_focus_kind(province)
	if kind == "disrupt":
		var fill := depot_fill_ratio(province.id)
		if fill >= 0.0:
			bits.append("depot %d%%" % int(round(fill * 100.0)))
		bits.append("⛟ drain")
	if kind == "sabotage":
		bits.append("infra %d" % province.infrastructure)
		var rate := MapManager.get_infrastructure_repair_rate(province.id)
		if rate > 0.0:
			bits.append("repair +%.2f/d" % rate)
	elif province.infrastructure < 50:
		bits.append("infra %d" % province.infrastructure)
		var rate := MapManager.get_infrastructure_repair_rate(province.id)
		if rate > 0.0:
			bits.append("+%.2f/d" % rate)
	return " · ".join(bits)


static func build_agent_pressure_headline_bbcode(province: Province) -> String:
	if not agent_applies_daily_pressure(province):
		return ""
	match agent_pressure_focus_kind(province):
		"disrupt":
			return "%s⛟ DAILY SUPPLY PRESSURE[/color]" % COLOR_WARN
		"sabotage":
			return "%s⚙ DAILY INFRA SABOTAGE[/color]" % COLOR_WARN
		_:
			return ""


## Organized block for tooltips / inspector (TODAY tick + recovery; no duplicate ACTIVE line).
static func build_province_pressure_section_bbcode(
	province: Province,
	include_headline: bool = true,
) -> String:
	if province == null or not (
		agent_applies_daily_pressure(province)
		or agent_has_daily_activity(province)
	):
		return ""
	var lines: PackedStringArray = []
	if include_headline:
		var head := build_agent_pressure_headline_bbcode(province)
		if not head.is_empty():
			lines.append(head)
	# When Sabotage & repair card is shown, skip redundant "ACTIVE — daily …" line.
	var activity := build_agent_daily_activity_bbcode(province, include_headline, not include_headline)
	if not activity.is_empty():
		if not include_headline and not pressure_agent_section_redundant_with_card(province):
			lines.append("%s── Agent activity ──[/color]" % COLOR_HEADER)
		lines.append(activity)
	if include_headline:
		var recovery := build_province_pressure_recovery_bbcode(province)
		if not recovery.is_empty():
			lines.append(recovery)
	if lines.is_empty():
		return ""
	return "\n".join(lines)


## Skip agent activity block when the Sabotage & repair card already covers today's tick.
static func pressure_agent_section_redundant_with_card(province: Province) -> bool:
	if province == null or not province_needs_infrastructure_ui(province):
		return false
	var activity := build_agent_daily_activity_bbcode(province, false, true)
	if activity.is_empty():
		return true
	var compact_lines := activity.strip_edges().split("\n")
	if compact_lines.is_empty():
		return true
	var only_redundant := true
	for raw_line in compact_lines:
		var line := str(raw_line).to_lower()
		var redundant := (
			("today" in line and (
				"infrastructure" in line
				or "supply disruption" in line
				or "sabotage" in line
				or "infra pressure" in line
			))
			or ("today's effect" in line and "infrastructure chipped" in line)
			or ("today's effect" in line and "auto-repair" in line)
			or ("active —" in line and "daily" in line)
			or ("daily infra sabotage" in line)
			or ("daily supply pressure" in line)
			or ("◎ today" in line)
			or ("sabotage winning" in line)
			or ("repair winning" in line)
		)
		if not redundant:
			only_redundant = false
			break
	return only_redundant


static func build_province_radio_overlay_line_bbcode(province: Province, country_tag: String) -> String:
	if province == null or country_tag.is_empty():
		return ""
	if not MapTechnologyContext.has_support_radio_bonuses(country_tag):
		return ""
	if not _province_matches_country(province, country_tag):
		return ""
	return MapTechnologyContext.build_support_radio_province_block_bbcode(
		province, country_tag, true,
	)


static func agent_pressure_focus_kind(province: Province) -> String:
	var net := get_active_agent_network(province)
	if net == null:
		return ""
	match net.focus:
		"supply_disruption":
			return "disrupt"
		"infrastructure_sabotage":
			return "sabotage"
		_:
			return ""


static func agent_has_daily_activity(province: Province) -> bool:
	var net := get_active_agent_network(province)
	if net == null:
		return false
	if not net.last_daily_note.strip_edges().is_empty():
		return true
	return agent_applies_daily_pressure(province)


static func count_agent_pressure_networks(country_tag: String = "") -> Dictionary:
	var out := {"disrupt": 0, "sabotage": 0}
	if typeof(AgentManager) == TYPE_NIL:
		return out
	var tag := country_tag.strip_edges().to_upper()
	var nets: Array = []
	if not tag.is_empty():
		nets = AgentManager.get_networks_for_country(tag)
	else:
		if typeof(MapManager) == TYPE_NIL:
			return out
		for pid in MapManager.get_all_provinces().keys():
			var net: AgentNetwork = AgentManager.get_network(int(pid))
			if net != null:
				nets.append(net)
	for net in nets:
		if net == null or not net.is_active():
			continue
		if net.focus == "supply_disruption":
			out["disrupt"] += 1
		elif net.focus == "infrastructure_sabotage":
			out["sabotage"] += 1
	return out


static func estimate_agent_map_pressure(province: Province) -> float:
	if province == null or typeof(MapManager) == TYPE_NIL:
		return 0.0
	var pressure := 0.0
	var owner := province.owner_tag
	var ctrl := province.controller_tag
	if owner != ctrl and not ctrl.is_empty():
		pressure += 0.45
	for nid in MapManager.get_adjacent_provinces(province.id, true) as Array:
		var p: Province = MapManager.get_province(int(nid)) as Province
		if p != null and is_province_contested(p):
			pressure += 0.12
	return clampf(pressure, 0.0, 1.0)


static func _agent_daily_note_label(note: String) -> String:
	match note:
		"growth":
			return "network strengthened"
		"recruit":
			return "+operative recruited"
		"intel":
			return "intel gathered"
		"disrupt":
			return "supply disruption applied"
		"sabotage":
			return "infrastructure damaged"
		"infra_pressure":
			return "sabotage focus (infra pressure)"
		"detected":
			return "detection risk"
		_:
			return note.replace("_", " ")


static func build_agent_ongoing_pressure_bbcode(province: Province) -> String:
	var net := get_active_agent_network(province)
	if net == null or not agent_applies_daily_pressure(province):
		return ""
	match net.focus:
		"supply_disruption":
			return (
				"%s⛟ ACTIVE — daily supply pressure (national debuff · depot stock · throughput)[/color]"
				% COLOR_WARN
			)
		"infrastructure_sabotage":
			return (
				"%s⚙ ACTIVE — daily infrastructure sabotage (infra chips while focus holds)[/color]"
				% COLOR_WARN
			)
		_:
			return ""


static func build_agent_daily_effect_detail_bbcode(province: Province) -> String:
	var net := get_active_agent_network(province)
	if net == null or net.last_daily_effect_scalar <= 0.0:
		return ""
	if net.last_daily_effect == "supply_disruption":
		var pct := int(round(net.last_daily_effect_scalar * 1000.0))
		return (
			"%sToday's effect ~%d‰ supply strain · local depot hit[/color]"
			% [COLOR_MUTED, pct]
		)
	if net.last_daily_effect == "infrastructure_sabotage":
		var extra := ""
		if typeof(MapManager) != TYPE_NIL and province != null:
			var rate := MapManager.get_infrastructure_repair_rate(province.id)
			if rate > 0.0:
				extra = " · auto-repair +%.2f/day" % rate
		return (
			"%sToday's effect: infrastructure chipped (movement & supply)%s[/color]"
			% [COLOR_MUTED, extra]
		)
	return ""


static func build_agent_daily_activity_bbcode(
	province: Province,
	include_ongoing: bool = true,
	skip_redundant_effect: bool = false,
) -> String:
	var net := get_active_agent_network(province)
	if net == null:
		return ""
	var lines: PackedStringArray = []
	if include_ongoing:
		var pressure := build_agent_ongoing_pressure_bbcode(province)
		if not pressure.is_empty():
			lines.append(pressure)
	var note := net.last_daily_note.strip_edges()
	if not note.is_empty():
		var accent := COLOR_WARN if note in ["disrupt", "sabotage", "detected", "infra_pressure"] else COLOR_NATIONAL
		lines.append("%s◎ TODAY — %s[/color]" % [accent, _agent_daily_note_label(note)])
	if not skip_redundant_effect:
		var detail := build_agent_daily_effect_detail_bbcode(province)
		if not detail.is_empty():
			lines.append(detail)
	if lines.is_empty():
		return ""
	return "\n".join(lines)


static func build_agent_glance_bbcode(province: Province) -> String:
	var net := get_active_agent_network(province)
	if net == null:
		return ""
	var focus := str(net.focus).replace("_", " ")
	var pressure := estimate_agent_map_pressure(province)
	var eff := net.get_effectiveness() * (1.0 - pressure * 0.55)
	eff = clampf(eff, 0.08, 1.0)
	var line := (
		"%s◎ %s · str %.0f · %d ops · map eff %.0f%%"
		% [COLOR_NATIONAL, focus, net.strength, net.local_operatives, eff * 100.0]
	)
	if pressure >= 0.2:
		line += " · press %.0f%%" % (pressure * 100.0)
	if agent_applies_daily_pressure(province):
		var badge := "⛟" if net.focus == "supply_disruption" else "⚙"
		line += " · %s pressure" % badge
	if not net.last_daily_note.strip_edges().is_empty():
		line += " · %s" % _agent_daily_note_label(net.last_daily_note)
	return line + "[/color]"


static func build_agent_pressure_legend_fragment(country_tag: String = "") -> String:
	var counts := count_agent_pressure_networks(country_tag)
	var parts: PackedStringArray = []
	if counts.get("disrupt", 0) > 0:
		parts.append("%s⛟%d supply[/color]" % [COLOR_WARN, counts["disrupt"]])
	if counts.get("sabotage", 0) > 0:
		parts.append("%s⚙%d infra[/color]" % [COLOR_WARN, counts["sabotage"]])
	if parts.is_empty():
		return ""
	return " · ".join(parts)


static func build_agent_legend_line(agent_count: int = -1, country_tag: String = "") -> String:
	var n := agent_count
	if n < 0:
		n = count_agent_networks({}, country_tag)
	if n <= 0:
		return ""
	var line := (
		"[color=#8899aa]◎ Agents: [/color][color=#a78bfa]○[/color][color=#8899aa] "
		+ "rings = %d active · size = strength · daily pulse[/color]"
		% n
	)
	var pressure := build_agent_pressure_legend_fragment(country_tag)
	if not pressure.is_empty():
		line += "  " + pressure
	if pressure.is_empty():
		line += "  [color=#8899aa]· ⛟ supply · ⚙ infra focus[/color]"
	return line


static func build_inspector_agent_section(province: Province) -> String:
	var net := get_active_agent_network(province)
	if net == null:
		return ""
	var lines: PackedStringArray = []
	lines.append("%s── Agent network ──[/color]" % COLOR_HEADER)
	lines.append(build_agent_glance_bbcode(province))
	var p_tag := country_tag_for_province(province)
	if _province_matches_country(province, p_tag):
		var support := MapTechnologyContext.build_support_radio_inspector_block(p_tag)
		if not support.is_empty():
			lines.append(support)
	var pressure := estimate_agent_map_pressure(province)
	if pressure >= 0.2:
		lines.append(
			"%sEnemy pressure %.0f%% shrinks the ring (contested control / neighbors).[/color]"
			% [COLOR_MUTED, pressure * 100.0]
		)
	var pressure_sec := build_province_pressure_section_bbcode(province, true)
	if not pressure_sec.is_empty():
		lines.append(pressure_sec)
	var radio_line := build_province_radio_overlay_line_bbcode(province, p_tag)
	if not radio_line.is_empty():
		lines.append(radio_line)
	lines.append(
		"%sMap: ring size = effectiveness; ⛟/⚙ glyphs = daily pressure; rings pulse each day.[/color]"
		% COLOR_MUTED
	)
	return "\n".join(lines)


static func count_contested_provinces(provinces: Dictionary = {}) -> int:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_contested_provinces"):
		return MapManager.get_contested_provinces().size()
	var n := 0
	for pid_var in provinces.keys():
		var p: Province = provinces[pid_var] as Province
		if p != null and is_province_contested(p):
			n += 1
	return n


static func build_conflict_status_bbcode(province: Province) -> String:
	if not is_province_contested(province):
		return ""
	var owner := province.owner_tag if not province.owner_tag.is_empty() else "—"
	var ctrl := province.controller_tag
	return (
		"%s⚑ Contested — owner %s · held by %s[/color]"
		% [COLOR_WARN, owner, ctrl]
	)


static func build_control_glance_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var owner := province.owner_tag if not province.owner_tag.is_empty() else "—"
	var region_line := ""
	var rid: int = province.strategic_region_id
	if rid <= 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_region_id"):
		rid = MapManager.get_province_region_id(province.id)
	if rid > 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_strategic_region_name"):
		var rname: String = MapManager.get_strategic_region_name(rid)
		if not rname.is_empty():
			region_line = "  ·  Region: %s" % rname
	if is_province_contested(province):
		return (
			"%sOwner %s%s  ·  %s⚑ Held by %s[/color]"
			% [COLOR_MUTED, owner, region_line, COLOR_WARN, province.controller_tag]
		)
	return "%sOwner: %s%s[/color]" % [COLOR_MUTED, owner, region_line]


static func build_province_glance_bbcode(
	province: Province,
	pe: ProvinceEffects = null,
	max_parts: int = 4,
	omit_contested_agent: bool = false,
	omit_support: bool = false,
) -> String:
	if province == null:
		return ""
	var parts: PackedStringArray = []
	var dual_active := is_province_contested(province) and has_active_agent_network(province)
	if is_province_contested(province) and not (omit_contested_agent and dual_active):
		parts.append(
			"%s⚑ %s holds (owner %s)[/color]"
			% [COLOR_WARN, province.controller_tag, province.owner_tag]
		)
	var fill := depot_fill_ratio(province.id)
	if fill >= 0.0:
		var icon := "✓"
		if fill < 0.35:
			icon = "⚠"
		elif fill < 0.65:
			icon = "◐"
		parts.append("%s%s Depot %d%%[/color]" % [COLOR_MUTED, icon, int(round(fill * 100.0))])
	var agent_line := build_agent_glance_bbcode(province)
	if not agent_line.is_empty() and not (omit_contested_agent and dual_active):
		parts.append(agent_line)
	if province_needs_infrastructure_ui(province) and parts.size() < max_parts:
		var bd := _infra_repair_breakdown(province)
		if bool(bd.get("under_infra_sabotage", false)):
			parts.append("%s⚙ Under sabotage[/color]" % COLOR_WARN)
		elif agent_pressure_focus_kind(province) == "disrupt":
			parts.append("%s⛟ Supply pressure[/color]" % COLOR_WARN)
		elif int(bd.get("infrastructure", province.infrastructure)) < 50:
			var r := float(bd.get("total", 0.0))
			if r > 0.0:
				parts.append("%s⚙ Recovering +%.2f/d[/color]" % [COLOR_TECH, r])
	var tag := country_tag_for_province(province)
	if not tag.is_empty() and typeof(NationalSpiritManager) != TYPE_NIL:
		var spirit_n := _national_spirit_lines(tag).size()
		var temp_n := _temporary_effect_lines(tag).size()
		if spirit_n > 0 or temp_n > 0:
			var nat_parts: PackedStringArray = []
			if spirit_n > 0:
				nat_parts.append("%d◆" % spirit_n)
			if temp_n > 0:
				nat_parts.append("%d⏱" % temp_n)
			parts.append("%sNational %s[/color]" % [COLOR_NATIONAL, " ".join(nat_parts)])
	if pe != null:
		parts.append(
			"%s×%.2f supply · ×%.2f width[/color]"
			% [COLOR_MUTED, pe.get_effective_throughput_multiplier(), pe.get_effective_combat_width_multiplier()]
		)
	var prod := MapTechnologyContext.build_province_production_tech_bbcode(province, tag)
	if not prod.is_empty():
		parts.append(prod)
	var elig_glance := MapTechnologyContext.build_build_eligibility_glance_bbcode(province, tag)
	if not elig_glance.is_empty():
		parts.append(elig_glance)
	if _province_matches_country(province, tag) and not omit_support:
		var support := MapTechnologyContext.build_support_radio_compact_chip(tag)
		if not support.is_empty():
			parts.append(support)
	if parts.is_empty():
		return ""
	return build_province_glance_compact(parts, max_parts)


static func build_province_glance_compact(parts: PackedStringArray, max_parts: int = 4) -> String:
	if parts.is_empty():
		return ""
	if parts.size() <= max_parts:
		return "  ·  ".join(parts)
	var shown: PackedStringArray = []
	for i in range(mini(parts.size(), max_parts)):
		shown.append(parts[i])
	shown.append("%s+%d more[/color]" % [COLOR_MUTED, parts.size() - max_parts])
	return "  ·  ".join(shown)


static func build_dual_situation_glance_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var contested := is_province_contested(province)
	var agent := has_active_agent_network(province)
	if not contested or not agent:
		return ""
	var ctrl := province.controller_tag
	var owner := province.owner_tag if not province.owner_tag.is_empty() else "—"
	var net := get_active_agent_network(province)
	var agent_bit := ""
	if net != null:
		var badge := ""
		if agent_applies_daily_pressure(province):
			badge = "⛟ " if net.focus == "supply_disruption" else "⚙ "
		agent_bit = " · ◎ %s%s str %.0f" % [badge, str(net.focus).replace("_", " "), net.strength]
		if not net.last_daily_note.strip_edges().is_empty():
			agent_bit += " · %s" % _agent_daily_note_label(net.last_daily_note)
	var repair_hint := ""
	if agent_applies_daily_pressure(province) and typeof(MapManager) != TYPE_NIL:
		var rate := MapManager.get_infrastructure_repair_rate(province.id)
		if agent_pressure_focus_kind(province) == "sabotage" and rate > 0.0:
			repair_hint = " · repair +%.2f/d" % rate
	var line := (
		"%s⚑◎ %s holds %s (owner %s)%s%s[/color]"
		% [COLOR_WARN, ctrl, province.name, owner, agent_bit, repair_hint]
	)
	var tag := country_tag_for_province(province)
	if _province_matches_country(province, tag):
		var support := MapTechnologyContext.build_province_support_benefit_bbcode(province, tag)
		if not support.is_empty():
			line += "\n" + support
	return line


static func build_inspector_situation_section(province: Province) -> String:
	if province == null:
		return ""
	var contested := is_province_contested(province)
	var agent := has_active_agent_network(province)
	if not contested and not agent:
		return ""
	var lines: PackedStringArray = []
	if contested and agent:
		lines.append("%s── Situation: contested + agent ──[/color]" % COLOR_HEADER)
		var p_tag := country_tag_for_province(province)
		var pressure_sec := build_province_pressure_section_bbcode(province, true)
		if not pressure_sec.is_empty():
			lines.append(pressure_sec)
		lines.append(build_conflict_status_bbcode(province))
		lines.append(build_agent_glance_bbcode(province))
		var radio_line := build_province_radio_overlay_line_bbcode(province, p_tag)
		if not radio_line.is_empty():
			lines.append(radio_line)
		var nat_badge := build_national_sources_badge(province)
		if not nat_badge.is_empty():
			lines.append("%sNational (same view): %s[/color]" % [COLOR_MUTED, nat_badge])
		if _province_matches_country(province, p_tag):
			var support := MapTechnologyContext.build_support_radio_inspector_block(p_tag)
			if not support.is_empty():
				lines.append(support)
		lines.append(
			"%sMap: ▨ stripes + ◎ ring + supply fill (L); blended hover outline.[/color]" % COLOR_MUTED
		)
	elif contested:
		return build_inspector_conflict_section(province)
	else:
		return build_inspector_agent_section(province)
	return "\n".join(lines)


static func build_conflict_map_hint_plain(contested_count: int = -1) -> String:
	var n := contested_count
	if n < 0:
		n = count_contested_provinces()
	if n <= 0:
		return ""
	return "⚑ %d contested province%s — diagonal stripes on map" % [n, "s" if n != 1 else ""]


static func build_conflict_legend_line(contested_count: int = -1) -> String:
	var n := contested_count
	if n < 0:
		n = count_contested_provinces()
	if n <= 0:
		return ""
	return (
		"[color=#8899aa]⚑ Conflict: [/color][color=#ff7a7a]▨[/color][color=#8899aa] stripes = %d contested (owner ≠ controller)[/color]"
		% n
	)


static func country_tag_for_province(province: Province) -> String:
	if province == null:
		return ""
	if not province.controller_tag.is_empty():
		return province.controller_tag.strip_edges().to_upper()
	return province.owner_tag.strip_edges().to_upper()


static func build_province_report(
	province: Province,
	selected_province_id: int = -1,
	other_province: Province = null,
) -> Dictionary:
	if province == null:
		return {}
	var tag := country_tag_for_province(province)
	var pe: ProvinceEffects = get_province_effects_for(province, tag)
	return {
		"province": province,
		"country_tag": tag,
		"province_effects": pe,
		"logistics_rows": _logistics_rows(pe),
		"combat_rows": _combat_rows(pe),
		"depot_line": _depot_summary_line(province.id),
		"depot_fill": depot_fill_ratio(province.id),
		"movement_cost": province.get_movement_cost(),
		"national_rollup": build_national_rollup_bbcode(pe),
		"national_bbcode": build_national_effects_bbcode(province),
		"routes_bbcode": build_routes_through_province_bbcode(province.id, tag),
		"battle_block": _battle_block_for(province, selected_province_id, other_province),
		"supply_overlay_active": false,
		"stationed_formations": _get_stationed_missions_summary(province.id, tag),
	}


static func format_report_tooltip(report: Dictionary) -> String:
	if report.is_empty():
		return ""
	var p: Province = report["province"]
	var pe: ProvinceEffects = report.get("province_effects") as ProvinceEffects
	var lines: PackedStringArray = []
	var tags := build_province_situation_tags(p)
	var title := "%s%s (#%d)[/color]" % [COLOR_HEADER, p.name, p.id]
	if not tags.is_empty():
		title += " " + tags
	lines.append(title)
	var infra_card := build_province_infrastructure_card_bbcode(p, true)
	var pressure_sec := ""
	if not pressure_agent_section_redundant_with_card(p):
		pressure_sec = build_province_pressure_section_bbcode(p, infra_card.is_empty())
	if not infra_card.is_empty():
		lines.append(infra_card)
	if not pressure_sec.is_empty():
		if not infra_card.is_empty():
			lines.append("")
		lines.append(pressure_sec)
	var tag_early := str(report.get("country_tag", ""))
	var tech_section := append_technology_section_after_pressure(
		lines, p, tag_early, infra_card, pressure_sec, true,
	)
	append_build_eligibility_section_after_technology(lines, p, tag_early, true)
	if infra_card.is_empty():
		var bd_eng := _infra_repair_breakdown(p)
		if should_show_engineer_map_ui(p, bd_eng):
			var eng_block := build_engineer_presence_section_bbcode(p, bd_eng, true)
			if not eng_block.is_empty():
				if not lines.is_empty():
					lines.append("")
				lines.append(eng_block)
	var banner := build_tooltip_context_banner(report)
	if not banner.is_empty():
		lines.append(banner)
	lines.append(build_control_glance_bbcode(p))
	var dual := ""
	if infra_card.is_empty():
		dual = build_dual_situation_glance_bbcode(p)
		if not dual.is_empty():
			lines.append(dual)
	var tag := str(report.get("country_tag", ""))
	var radio_overlay := build_province_radio_overlay_line_bbcode(p, tag)
	var nat_line := build_national_situation_one_liner(p, pe, not tech_section.is_empty())
	if not nat_line.is_empty():
		lines.append(nat_line)
	var dual_has_support := not dual.is_empty() and _province_matches_country(p, tag)
	var omit_support_in_glance := (
		not tech_section.is_empty()
		or (
			MapTechnologyContext.has_support_radio_bonuses(tag)
			and province_benefits_country(p, tag)
			and (not nat_line.is_empty() or dual_has_support or not radio_overlay.is_empty())
		)
	)
	if not tech_section.is_empty() and omit_support_in_glance:
		radio_overlay = ""
	if not radio_overlay.is_empty() and omit_support_in_glance:
		lines.append(radio_overlay)
	var skip_dual_glance := not infra_card.is_empty()
	var glance := build_province_glance_bbcode(p, pe, 4, skip_dual_glance, omit_support_in_glance)
	if not glance.is_empty():
		lines.append(glance)
	# Special sites + chokepoint on hover even when sabotage card is empty.
	if infra_card.is_empty() or "Sites:" not in infra_card:
		var sites_tip := build_special_sites_effect_bbcode(p, true)
		if not sites_tip.is_empty():
			lines.append(sites_tip)
	var choke_tip := build_naval_chokepoint_badge_bbcode(p)
	if not choke_tip.is_empty() and (infra_card.is_empty() or "Naval chokepoint" not in infra_card):
		lines.append(choke_tip)
	var bd_dev := _infra_repair_breakdown(p)
	var dev_extra := ""
	if has_engineers_stationed(bd_dev):
		dev_extra = " · %s🔧 %.1f eng[/color]" % [
			COLOR_TECH,
			float(bd_dev.get("engineer_brigades", 0.0)),
		]
	lines.append(
		"%sDev %d  ·  Infra %d  ·  VP %d  ·  %s%s[/color]"
		% [
			COLOR_MUTED,
			p.development_level,
			p.infrastructure,
			p.victory_points,
			p.terrain.capitalize(),
			dev_extra,
		]
	)
	if not infra_card.is_empty() and has_engineers_stationed(bd_dev):
		lines.append(
			"%sRepair +%.2f/day — engineers add +%.2f (see Sabotage & repair card)[/color]"
			% [
				COLOR_MUTED,
				float(bd_dev.get("total", 0.0)),
				float(bd_dev.get("engineer_bonus", 0.0)),
			]
		)
	if pe != null:
		lines.append(build_compact_effective_summary(pe))
		if bool(report.get("supply_overlay_active", false)):
			var log_line := build_supply_logistics_one_liner(pe, tag)
			if not log_line.is_empty():
				lines.append(log_line)
		elif (
			tech_section.is_empty()
			and MapTechnologyContext.has_support_radio_bonuses(tag)
			and province_benefits_country(p, tag)
			and nat_line.is_empty()
		):
			var radio := MapTechnologyContext.build_support_supply_effect_bbcode(tag)
			if not radio.is_empty():
				lines.append(radio)
	lines.append(_depot_bbcode_line(p.id))
	if not bool(report.get("supply_overlay_active", false)) and typeof(TradeManager) != TYPE_NIL:
		var tn := TradeManager.count_trade_flows_on_map_province(p.id, "")
		if tn > 0:
			var player_t := ""
			if typeof(SupplyManager) != TYPE_NIL:
				player_t = str(SupplyManager.player_tag).strip_edges().to_upper()
			if TradeManager.collect_trade_flow_summaries_for_map_province(p.id, player_t, 1).size() > 0:
				lines.append(
					"%s◇ %d active trade corridor%s · L shows route[/color]"
					% [COLOR_TECH, tn, "s" if tn != 1 else ""]
				)
	if bool(report.get("supply_overlay_active", false)):
		var layer_sum := build_compact_layers_summary_bbcode(
			true,
			count_contested_provinces(),
			count_agent_networks({}, tag),
			count_dual_situation_provinces(),
			tag,
		)
		if not layer_sum.is_empty():
			lines.append(layer_sum)
		lines.append(build_supply_map_hint_bbcode(p.id))
		var tf_line := build_trade_flow_map_section_bbcode(p.id, "", 3)
		if not tf_line.is_empty():
			if not lines.is_empty() and lines[lines.size() - 1] != "":
				lines.append("")
			lines.append(tf_line)
		var role := str(report.get("hover_supply_role", ""))
		if not role.is_empty():
			lines.append(build_supply_role_hint_bbcode(p.id, role))
	var routes := build_routes_through_province_bbcode(
		p.id, str(report.get("country_tag", "")), 2,
	)
	if not routes.is_empty():
		lines.append(routes)
	var all_rows: Array = []
	all_rows.append_array(report.get("logistics_rows", []) as Array)
	all_rows.append_array(report.get("combat_rows", []) as Array)
	var impact := _top_impact_rows(all_rows, 4)
	if not impact.is_empty():
		lines.append("")
		lines.append("%s── Key modifiers ──[/color]" % COLOR_HEADER)
		lines.append(_stat_column_legend_bbcode())
		for row in impact:
			lines.append(_bbcode_stat_line_layered(row))
	var badge := build_national_sources_badge(p)
	if pe != null:
		var nat_impact := build_national_impact_compact(pe, 2)
		if not nat_impact.is_empty():
			lines.append(nat_impact)
	if not badge.is_empty():
		lines.append(badge)
		lines.append(build_national_sources_grouped_compact(p, 2))
	var battle := str(report.get("battle_block", ""))
	if not battle.is_empty():
		lines.append("")
		lines.append(battle)
	lines.append(
		"%sMovement cost: %.2f  ·  Click for full breakdown[/color]"
		% [COLOR_MUTED, float(report.get("movement_cost", 1.0))]
	)
	var date_footer := GameDateDisplay.build_map_date_footer_bbcode()
	if not date_footer.is_empty():
		lines.append(date_footer)
	return "\n".join(lines)


static func format_report_inspector(report: Dictionary, selected_province_id: int = -1) -> String:
	var p: Province = report.get("province") as Province
	if p == null:
		return ""
	return build_inspector_full_bbcode(p, selected_province_id)


# --- Stat rows ---

static func _logistics_rows(pe: ProvinceEffects) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		_make_mult_row("Supply throughput", pe.province.get_supply_throughput_modifier(), pe.get_effective_throughput_multiplier(), pe, "supply_throughput"),
		_make_add_row("Local supply gen", pe.province.get_local_supply_generation_modifier(), pe.get_effective_local_supply_generation(), pe, "local_supply", true),
		_make_mult_row("Interdiction resist", pe.province.get_interdiction_resistance_modifier(), pe.get_effective_interdiction_resistance(), pe, "interdiction_resistance"),
		_make_mult_row("Reinforcement", pe.province.get_reinforcement_speed_modifier(), pe.get_effective_reinforcement_speed(), pe, "reinforcement_speed"),
		_make_score_row("Logistics quality", pe.province.get_logistics_quality(), pe.get_effective_logistics_quality(), pe, "logistics_quality"),
	]
	# Playtest visibility for settlement/relocation (demographic engineering payoff).
	if pe.province and pe.province.settlement_level > 0.01:
		var s := pe.province.settlement_level
		rows.append({
			"label": "Settlement supply bonus",
			"base": pe.province.get_local_supply_generation_modifier(),
			"effective": pe.get_effective_local_supply_generation() + (s * 0.05),
			"note": "+%.0f%% local supply from repopulation/settlement (level %.2f)" % [s * 5 * 100, s]
		})
	return rows


static func _combat_rows(pe: ProvinceEffects) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		_make_mult_row("Combat width", pe.province.get_combat_width_modifier(), pe.get_effective_combat_width_multiplier(), pe, "combat_width"),
		_make_mult_row("Org recovery", pe.province.get_organization_recovery_modifier(), pe.get_effective_organization_recovery(), pe, "organization_recovery"),
		_make_mult_row("Attrition", pe.province.get_attrition_modifier(), pe.get_effective_attrition_multiplier(), pe, "attrition_reduction", true),
	]
	# World-class playtest feedback for demographic/relocation systems: surface settlement explicitly.
	if pe.province and pe.province.settlement_level > 0.01:
		var set_bonus := pe.province.settlement_level
		rows.append({
			"label": "Settlement (repopulation)",
			"base": pe.province.get_organization_recovery_modifier(),  # proxy
			"effective": pe.get_effective_organization_recovery() * (1.0 + set_bonus * 0.04),  # approximate uplift
			"note": "+%.0f%% org / -%.0f%% attrition / + local supply / combat def +%.1f%% from settlement (%.2f)" % [set_bonus * 4 * 100, set_bonus * 3 * 100, pe.province.get_settlement_combat_def_bonus() * 100.0, set_bonus]
		})
	return rows


static func _make_mult_row(
	label: String,
	base: float,
	effective: float,
	pe: ProvinceEffects,
	nat_key: String,
	lower_is_better: bool = false,
) -> Dictionary:
	var nat_v := float(pe.national_modifiers.get(nat_key, 0.0))
	return {
		"label": label,
		"base": base,
		"effective": effective,
		"kind": "mult",
		"nat_key": nat_key,
		"national_value": nat_v,
		"nat_delta": _national_delta_text(pe, nat_key),
		"improved": _is_improved(base, effective, lower_is_better),
	}


static func _make_add_row(
	label: String,
	base: float,
	effective: float,
	pe: ProvinceEffects,
	nat_key: String,
	as_percent: bool = false,
) -> Dictionary:
	var nat_v := float(pe.national_modifiers.get(nat_key, 0.0))
	return {
		"label": label,
		"base": base,
		"effective": effective,
		"kind": "add",
		"as_percent": as_percent,
		"nat_key": nat_key,
		"national_value": nat_v,
		"nat_delta": _national_delta_text(pe, nat_key),
		"improved": effective > base + 0.0001,
	}


static func _make_score_row(
	label: String,
	base: float,
	effective: float,
	pe: ProvinceEffects,
	nat_key: String,
) -> Dictionary:
	var nat_v := float(pe.national_modifiers.get(nat_key, 0.0))
	return {
		"label": label,
		"base": base,
		"effective": effective,
		"kind": "score",
		"nat_key": nat_key,
		"national_value": nat_v,
		"nat_delta": _national_delta_text(pe, nat_key),
		"improved": effective > base + 0.05,
	}


static func _national_delta_text(pe: ProvinceEffects, key: String) -> String:
	var v := float(pe.national_modifiers.get(key, 0.0))
	if absf(v) < 0.0001:
		return ""
	if absf(v) < 1.0:
		return "nat %+0.0f%%" % (v * 100.0)
	return "nat %+0.2f" % v


static func _is_improved(base: float, effective: float, lower_is_better: bool) -> bool:
	if lower_is_better:
		return effective < base - 0.0001
	return effective > base + 0.0001


static func _modifier_legend_bbcode() -> String:
	return (
		"%sLayered stats: %sProvince base[/color] → %sNational[/color] → %sEffective[/color]"
		% [COLOR_MUTED, COLOR_PROVINCE, COLOR_NATIONAL, COLOR_EFFECTIVE]
	)


static func _stat_column_legend_bbcode() -> String:
	return (
		"%sStat  |  %sProvince[/color]  |  %sNational[/color]  |  %sEffective[/color]"
		% [COLOR_MUTED, COLOR_PROVINCE, COLOR_NATIONAL, COLOR_EFFECTIVE]
	)


static func build_tooltip_context_banner(report: Dictionary) -> String:
	var p: Province = report.get("province") as Province
	if p == null:
		return ""
	var parts: PackedStringArray = []
	var sel := int(report.get("selected_province_id", -1))
	var other: Province = report.get("other_province") as Province
	if sel >= 0 and sel == p.id:
		parts.append("%s◇ Hover ○-outlined neighbor for ⚔ preview[/color]" % COLOR_MUTED)
	elif sel >= 0:
		if other != null:
			parts.append("%s⚔ vs %s[/color]" % [COLOR_WARN, other.name])
			parts.append("%s↳ bold orange outline on partner[/color]" % COLOR_MUTED)
		elif bool(report.get("is_compare_candidate", false)):
			var hint := "%s○ Neighbor of %s — click for locked compare[/color]" % [
				COLOR_WARN, _province_short_name(sel),
			]
			if (
				bool(report.get("is_contested", false))
				and bool(report.get("has_agent_network", false))
			):
				var ap := ""
				if agent_applies_daily_pressure(p):
					ap = "⛟" if agent_pressure_focus_kind(p) == "disrupt" else "⚙"
				hint += "  ·  %s⚑◎%s contested + agent[/color]" % [COLOR_WARN, ap]
			elif bool(report.get("is_contested", false)):
				hint += "  ·  %s⚑ contested[/color]" % COLOR_WARN
			elif bool(report.get("has_agent_network", false)):
				var ap := ""
				if agent_applies_daily_pressure(p):
					ap = "⛟ " if agent_pressure_focus_kind(p) == "disrupt" else "⚙ "
				hint += "  ·  %s◎%s agent[/color]" % [COLOR_NATIONAL, ap]
			parts.append(hint)
		else:
			parts.append(build_non_adjacent_compare_hint(p, sel))
	if parts.is_empty():
		return ""
	return "  ·  ".join(parts)


static func build_non_adjacent_compare_hint(hover_province: Province, selected_province_id: int) -> String:
	var neighbor_names := _adjacent_province_names(selected_province_id, 4)
	if neighbor_names.is_empty():
		return "%s◇ Selection not adjacent to this province[/color]" % COLOR_MUTED
	return (
		"%s◇ Not adjacent — hover %s for ⚔ preview[/color]"
		% [COLOR_MUTED, ", ".join(neighbor_names)]
	)


static func _adjacent_province_names(province_id: int, limit: int = 4) -> PackedStringArray:
	var names := PackedStringArray()
	var adj: AdjacencySystem = null
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacency_system"):
		adj = MapManager.get_adjacency_system()
	if adj == null:
		var loader := _scenario_loader()
		if loader != null:
			adj = loader.adjacency
	if adj == null:
		return names
	for nid in adj.get_neighbors(province_id):
		var p := _province_by_id(int(nid))
		if p != null and not p.name.is_empty():
			names.append(p.name)
		if names.size() >= limit:
			break
	return names


static func build_inspector_national_section(province: Province, pe: ProvinceEffects) -> String:
	var lines: PackedStringArray = []
	lines.append("%s── National effects ──[/color]" % COLOR_HEADER)
	lines.append(
		"%s◆ spirits · ⏱ timed · ◎ agents — sources then combined totals[/color]" % COLOR_MUTED
	)
	var badge := build_national_sources_badge(province)
	if not badge.is_empty():
		lines.append(badge)
	if pe != null:
		var impact := build_national_impact_compact(pe, 4)
		if not impact.is_empty():
			lines.append(impact)
	var p_tag := country_tag_for_province(province)
	if _province_matches_country(province, p_tag):
		var support_block := MapTechnologyContext.build_support_radio_inspector_block(p_tag)
		if not support_block.is_empty():
			lines.append(support_block)
	var grouped := build_national_sources_grouped_compact(province, 4)
	if not grouped.is_empty():
		lines.append("%s  Active sources[/color]" % COLOR_MUTED)
		lines.append(grouped)
	if pe != null and not pe.national_modifiers.is_empty():
		lines.append("")
		lines.append(build_national_rollup_bbcode(pe))
	elif badge.is_empty():
		lines.append("%s  No province-relevant national modifiers.[/color]" % COLOR_MUTED)
	return "\n".join(lines)


static func build_supply_logistics_one_liner(pe: ProvinceEffects, country_tag: String = "") -> String:
	if pe == null:
		return ""
	var line := (
		"%s⛟ Supply — throughput ×%.2f · interdict resist ×%.2f · local gen %+.0f%%[/color]"
		% [
			COLOR_MUTED,
			pe.get_effective_throughput_multiplier(),
			pe.get_effective_interdiction_resistance(),
			pe.get_effective_local_supply_generation() * 100.0,
		]
	)
	var radio := MapTechnologyContext.build_support_supply_effect_bbcode(country_tag)
	if not radio.is_empty():
		line += "\n" + radio
	return line


static func build_national_situation_one_liner(
	province: Province,
	pe: ProvinceEffects = null,
	omit_support: bool = false,
) -> String:
	if province == null:
		return ""
	var tag := country_tag_for_province(province)
	var support := ""
	if not omit_support and _province_matches_country(province, tag):
		support = MapTechnologyContext.build_national_support_line_bbcode(tag, true)
	var badge := build_national_sources_badge(province)
	var impact := ""
	if pe != null:
		impact = build_national_impact_compact(pe, 2)
	if badge.is_empty() and impact.is_empty() and support.is_empty():
		return ""
	var parts: PackedStringArray = []
	if not support.is_empty():
		parts.append(support)
	if not badge.is_empty():
		parts.append(badge)
	if not impact.is_empty():
		parts.append(impact)
	return "%sNational: %s[/color]" % [COLOR_NATIONAL, " · ".join(parts)]


static func build_national_impact_compact(pe: ProvinceEffects, max_keys: int = 2) -> String:
	if pe == null or pe.national_modifiers.is_empty():
		return ""
	var scored: Array[Dictionary] = []
	for key in pe.national_modifiers.keys():
		var v := float(pe.national_modifiers[key])
		if absf(v) < 0.0001:
			continue
		scored.append({"key": str(key), "value": v, "abs": absf(v)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("abs", 0.0)) > float(b.get("abs", 0.0))
	)
	if scored.is_empty():
		return ""
	var parts: PackedStringArray = []
	for i in range(mini(scored.size(), max_keys)):
		var entry: Dictionary = scored[i]
		var label := str(NATIONAL_KEY_LABELS.get(entry.get("key", ""), str(entry.get("key", ""))))
		parts.append("%s%s %s[/color]" % [COLOR_NATIONAL, label, _format_national_value(float(entry.get("value", 0.0)))])
	var extra := scored.size() - max_keys
	var suffix := ""
	if extra > 0:
		suffix = "  %s(+%d in inspector)[/color]" % [COLOR_MUTED, extra]
	return "%s◆ National impact: %s%s[/color]" % [COLOR_NATIONAL, " · ".join(parts), suffix]


static func build_compact_effective_summary(pe: ProvinceEffects) -> String:
	if pe == null:
		return ""
	return (
		"%sEffective — supply ×%.2f · reinf ×%.2f · width ×%.2f · org ×%.2f[/color]"
		% [
			COLOR_MUTED,
			pe.get_effective_throughput_multiplier(),
			pe.get_effective_reinforcement_speed(),
			pe.get_effective_combat_width_multiplier(),
			pe.get_effective_organization_recovery(),
		]
	)


static func build_national_sources_badge(province: Province) -> String:
	var tag := country_tag_for_province(province)
	if tag.is_empty():
		return ""
	var spirit_n := _national_spirit_lines(tag).size()
	var temp_n := _temporary_effect_lines(tag).size()
	var has_agent := not _agent_network_line(province.id, tag).is_empty()
	if spirit_n == 0 and temp_n == 0 and not has_agent:
		return "%sNational: no province-relevant effects[/color]" % COLOR_MUTED
	var parts: PackedStringArray = []
	if spirit_n > 0:
		parts.append("%d spirit%s" % [spirit_n, "s" if spirit_n != 1 else ""])
	if temp_n > 0:
		parts.append("%d timed" % temp_n)
	if has_agent:
		parts.append("agent network")
	return "%s◆ National: %s[/color]" % [COLOR_NATIONAL, " · ".join(parts)]


static func build_national_sources_grouped_compact(province: Province, max_per_group: int = 2) -> String:
	var tag := country_tag_for_province(province)
	if tag.is_empty():
		return ""
	var spirits := _national_spirit_lines(tag)
	var temps := _temporary_effect_lines(tag)
	var agent := _agent_network_line(province.id, tag)
	var blocks: PackedStringArray = []
	if not spirits.is_empty():
		blocks.append("%s  ◆ Spirits (%d)[/color]" % [COLOR_NATIONAL, spirits.size()])
		for i in range(mini(spirits.size(), max_per_group)):
			blocks.append(spirits[i])
		if spirits.size() > max_per_group:
			blocks.append("%s    … +%d more[/color]" % [COLOR_MUTED, spirits.size() - max_per_group])
	if not temps.is_empty():
		blocks.append("%s  ⏱ Timed effects (%d)[/color]" % [COLOR_WARN, temps.size()])
		for i in range(mini(temps.size(), max_per_group)):
			blocks.append(temps[i])
		if temps.size() > max_per_group:
			blocks.append("%s    … +%d more[/color]" % [COLOR_MUTED, temps.size() - max_per_group])
	if not agent.is_empty():
		blocks.append("%s  ◎ Agent network[/color]" % COLOR_NATIONAL)
		blocks.append(agent)
	if blocks.is_empty():
		return ""
	return "\n".join(blocks)


static func build_national_sources_compact_limited(province: Province, max_lines: int = 3) -> String:
	var tag := country_tag_for_province(province)
	if tag.is_empty():
		return ""
	var lines: PackedStringArray = []
	for line in _national_spirit_lines(tag):
		lines.append(line)
	for line in _temporary_effect_lines(tag):
		lines.append(line)
	var agent := _agent_network_line(province.id, tag)
	if not agent.is_empty():
		lines.append(agent)
	if lines.is_empty():
		return ""
	var total := lines.size()
	if total > max_lines:
		var kept: PackedStringArray = []
		for i in range(max_lines):
			kept.append(lines[i])
		kept.append("%s  … +%d more in inspector[/color]" % [COLOR_MUTED, total - max_lines])
		return "\n".join(kept)
	return "\n".join(lines)


static func _top_impact_rows(rows: Array, max_count: int = 4) -> Array:
	var scored: Array[Dictionary] = []
	for row_var in rows:
		if typeof(row_var) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_var
		var score := absf(float(row.get("national_value", 0.0)))
		if bool(row.get("improved", false)):
			score += 0.25
		if absf(float(row.get("effective", 1.0)) - float(row.get("base", 1.0))) > 0.05:
			score += 0.15
		scored.append({"row": row, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	var out: Array = []
	for i in range(mini(scored.size(), max_count)):
		out.append(scored[i]["row"])
	return out


static func build_national_sources_compact(province: Province) -> String:
	var tag := country_tag_for_province(province)
	if tag.is_empty():
		return ""
	var lines: PackedStringArray = []
	for line in _national_spirit_lines(tag):
		lines.append(line)
	for line in _temporary_effect_lines(tag):
		lines.append(line)
	var agent := _agent_network_line(province.id, tag)
	if not agent.is_empty():
		lines.append(agent)
	if lines.is_empty():
		return ""
	var header := "%s── Affecting this province ──[/color]" % COLOR_HEADER
	lines.insert(0, header)
	return "\n".join(lines)


static func build_inspector_compare_header(
	province: Province,
	selected_province_id: int = -1,
) -> String:
	if selected_province_id < 0 or selected_province_id == province.id:
		return ""
	var other := _resolve_battle_counterpart(province, selected_province_id)
	if other == null:
		return (
			"%s◇ Province #%d selected — select an adjacent province for combat comparison.[/color]"
			% [COLOR_MUTED, selected_province_id]
		)
	return "%s⚔ Comparing with %s — battle preview below.[/color]" % [COLOR_WARN, other.name]


static func _is_trade_flow_hover_chip(tok: String) -> bool:
	var t := tok.to_lower()
	return "◇" in tok and ("trade" in t or "routes" in t or "×" in tok)


static func build_trade_flow_map_section_bbcode(
	province_id: int,
	viewer_country_tag: String,
	max_entries: int = 3,
) -> String:
	if typeof(TradeManager) == TYPE_NIL:
		return ""
	var tag := viewer_country_tag.strip_edges().to_upper()
	if tag.is_empty():
		var sm := _supply_manager()
		if sm != null:
			tag = str(sm.player_tag).strip_edges().to_upper()
	var total := TradeManager.count_trade_flows_on_map_province(province_id, tag)
	var entries := TradeManager.collect_trade_flow_summaries_for_map_province(
		province_id, tag, clampi(max_entries, 1, 8),
	)
	if entries.is_empty():
		return ""
	var lines: PackedStringArray = []
	lines.append(
		"%sTrade corridors · %d[/color]"
		% [COLOR_HEADER, total],
	)
	for e in entries:
		var role := str(e.get("role", "transit"))
		var from := str(e.get("from", "?"))
		var to := str(e.get("to", "?"))
		var cargo := str(e.get("cargo_line", ""))
		var risk := int(e.get("risk_pct", -1))
		var mode := str(e.get("mode", ""))
		var verb := ""
		match role:
			"export_hub":
				verb = "Export hub → %s" % to
			"export_transit":
				verb = "Transit → %s" % to
			"import_hub":
				verb = "Import hub ← %s" % from
			"import_transit":
				verb = "Transit ← %s" % from
			_:
				if tag == from:
					verb = "Toward %s" % to
				elif tag == to:
					verb = "From %s" % from
				else:
					verb = "%s ⟶ %s" % [from, to]
		var tail := cargo
		if risk >= 6:
			tail += " · ~%d%% route risk" % risk
		if not mode.is_empty() and mode != "land":
			tail += " · %s" % mode
		lines.append("%s  • %s — %s[/color]" % [COLOR_TECH, verb, tail])
	if total > entries.size():
		lines.append("%s  +%d more deal%s[/color]" % [COLOR_MUTED, total - entries.size(), "s" if total - entries.size() != 1 else ""])
	return "\n".join(lines)


static func build_trade_flow_hover_chip_bbcode(province: Province, viewer_country_tag: String) -> String:
	if province == null or typeof(TradeManager) == TYPE_NIL:
		return ""
	var tag := viewer_country_tag.strip_edges().to_upper()
	if tag.is_empty() and typeof(SupplyManager) != TYPE_NIL:
		tag = str(SupplyManager.player_tag).strip_edges().to_upper()
	if tag.is_empty():
		tag = country_tag_for_province(province)
	var n := TradeManager.count_trade_flows_on_map_province(province.id, tag)
	if n <= 0:
		return ""
	# Quieter than primary logistics chips; truncation merge looks for _is_trade_flow_hover_chip.
	if n > 1:
		return "%s◇ trade ×%d[/color]" % [COLOR_PROVINCE, n]
	return "%s◇ trade[/color]" % COLOR_PROVINCE


static func build_supply_map_hint_bbcode(province_id: int) -> String:
	var fill := depot_fill_ratio(province_id)
	var sm := _supply_manager()
	var role := "no depot"
	if fill >= 0.0:
		if fill < 0.35:
			role = "critical depot"
		elif fill < 0.65:
			role = "strained depot"
		else:
			role = "healthy depot"
	var route_note := ""
	var trade_note := ""
	if sm != null:
		for plan_var in sm.get_all_routes():
			if not (plan_var is SupplyRoutePlan):
				continue
			var pl := plan_var as SupplyRoutePlan
			if not province_id in pl.province_path:
				continue
			if pl.represents_trade_flow:
				trade_note = " · trade corridor (gold line)"
			else:
				route_note = " · on military supply route"
	if trade_note.is_empty() and route_note.is_empty() and sm != null and typeof(TradeManager) != TYPE_NIL:
		var ptag := str(sm.player_tag).strip_edges().to_upper()
		if TradeManager.count_trade_flows_on_map_province(province_id, ptag) > 0:
			trade_note = " · trade corridor"
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
				var reg := MapManager.get_active_regional_control_bonuses(ptag)
				if float(reg.get("convoy_efficiency", 0.0)) > 0.0 or float(reg.get("port_capacity", 0.0)) > 0.0 or float(reg.get("naval_range_multiplier", 1.0)) > 1.0:
					trade_note = " · trade corridor (convoy protected + regional bonuses)"
	var route_bits := route_note + trade_note
	var geo := ""
	if typeof(MapManager) != TYPE_NIL:
		var gp: Province = MapManager.get_province(province_id)
		if gp != null:
			var tr := str(gp.terrain).strip_edges()
			if not tr.is_empty():
				geo = " · %s" % tr.capitalize()
	return (
		"%s📦 Tint: %s (%d%%)%s%s  |  ◇ hub  — route  ◆ selected  · ~ preview[/color]"
		% [COLOR_MUTED, role, int(round(maxf(fill, 0.0) * 100.0)), route_bits, geo]
	)


static func _bbcode_stat_line_layered(row: Dictionary) -> String:
	var label := str(row.get("label", ""))
	var nat_val := float(row.get("national_value", 0.0))
	var improved: bool = row.get("improved", false)
	var eff_color := COLOR_EFFECTIVE if improved else COLOR_BASE
	var nat_text := _format_national_value(nat_val)
	if nat_text == "—" and not str(row.get("nat_delta", "")).is_empty():
		nat_text = str(row.get("nat_delta", "")).replace("nat ", "")
	var delta_hint := ""
	if improved:
		delta_hint = " %s▲[/color]" % COLOR_EFFECTIVE
	elif absf(nat_val) >= 0.0001 and not improved:
		delta_hint = " %s▼[/color]" % COLOR_WARN
	return (
		"%s%s[/color]  |  %s%s[/color]  |  %s%s[/color]  |  %s%s[/color]%s"
		% [
			COLOR_BASE,
			label,
			COLOR_PROVINCE,
			_format_base_value(row),
			COLOR_NATIONAL,
			nat_text,
			eff_color,
			_format_effective_value(row),
			delta_hint,
		]
	)


static func _format_base_value(row: Dictionary) -> String:
	match str(row.get("kind", "mult")):
		"add":
			if row.get("as_percent", false):
				return "%+.0f%%" % (float(row.get("base", 0.0)) * 100.0)
			return "%.2f" % float(row.get("base", 0.0))
		"score":
			return "%.0f" % float(row.get("base", 0.0))
		_:
			return "×%.2f" % float(row.get("base", 1.0))


static func _format_effective_value(row: Dictionary) -> String:
	match str(row.get("kind", "mult")):
		"add":
			if row.get("as_percent", false):
				return "%+.0f%%" % (float(row.get("effective", 0.0)) * 100.0)
			return "%.2f" % float(row.get("effective", 0.0))
		"score":
			return "%.0f" % float(row.get("effective", 0.0))
		_:
			return "×%.2f" % float(row.get("effective", 1.0))


static func _format_national_value(value: float) -> String:
	if absf(value) < 0.0001:
		return "—"
	if absf(value) < 1.0:
		return "%+.0f%%" % (value * 100.0)
	return "%+.2f" % value


static func _depot_bbcode_line(province_id: int) -> String:
	var sm := _supply_manager()
	if sm == null:
		return "%sDepot: network not built[/color]" % COLOR_MUTED
	var depot: ProvinceDepotState = sm.get_depot_state(province_id)
	if depot == null:
		return "%sDepot: not a supply hub[/color]" % COLOR_MUTED
	var fill := depot.fill_ratio()
	var pct := int(round(fill * 100.0))
	var color := COLOR_EFFECTIVE
	var status := "adequate"
	var icon := "✓"
	if fill < 0.35:
		color = COLOR_WARN
		status = "critical"
		icon = "⚠"
	elif fill < 0.65:
		color = "[color=#e8c04a]"
		status = "strained"
		icon = "◐"
	return (
		"%s%s Depot [/color]%s%d%% (%s)[/color]%s · %.0f t/day · cap %.0f"
		% [
			COLOR_MUTED,
			icon,
			color,
			pct,
			status,
			COLOR_MUTED,
			depot.throughput_capacity,
			depot.storage_capacity,
		]
	)


static func _province_short_name(province_id: int) -> String:
	var p := _province_by_id(province_id)
	if p != null and not p.name.is_empty():
		return p.name
	return "P%d" % province_id


static func _bbcode_stat_line(row: Dictionary) -> String:
	var label := str(row.get("label", ""))
	var nat := str(row.get("nat_delta", ""))
	var improved: bool = row.get("improved", false)
	var eff_color := COLOR_EFFECTIVE if improved else COLOR_BASE
	match str(row.get("kind", "mult")):
		"add":
			var as_pct: bool = row.get("as_percent", false)
			var b := float(row.get("base", 0.0))
			var e := float(row.get("effective", 0.0))
			if as_pct:
				return "%s%s: %s%+.0f%%[/color] → %s%+.0f%%[/color]%s" % [
					COLOR_BASE, label, COLOR_BASE, b * 100.0, eff_color, e * 100.0,
					_nat_suffix(nat),
				]
			return "%s%s: %s%.2f[/color] → %s%.2f[/color]%s" % [
				COLOR_BASE, label, COLOR_BASE, b, eff_color, e, _nat_suffix(nat),
			]
		"score":
			return "%s%s: %s%.0f[/color] → %s%.0f[/color]%s" % [
				COLOR_BASE, label, COLOR_BASE, row.get("base", 0.0), eff_color, row.get("effective", 0.0),
				_nat_suffix(nat),
			]
		_:
			return "%s%s: %s×%.2f[/color] → %s×%.2f[/color]%s" % [
				COLOR_BASE, label, COLOR_BASE, row.get("base", 1.0), eff_color, row.get("effective", 1.0),
				_nat_suffix(nat),
			]


static func _plain_stat_line(row: Dictionary) -> String:
	var nat := str(row.get("nat_delta", ""))
	match str(row.get("kind", "mult")):
		"add":
			if row.get("as_percent", false):
				return "%s: +%.0f%% → +%.0f%%%s" % [
					row.get("label", ""), float(row.get("base", 0.0)) * 100.0,
					float(row.get("effective", 0.0)) * 100.0, _nat_suffix_plain(nat),
				]
			return "%s: %.2f → %.2f%s" % [
				row.get("label", ""), row.get("base", 0.0), row.get("effective", 0.0), _nat_suffix_plain(nat),
			]
		"score":
			return "%s: %.0f → %.0f%s" % [
				row.get("label", ""), row.get("base", 0.0), row.get("effective", 0.0), _nat_suffix_plain(nat),
			]
		_:
			return "%s: ×%.2f → ×%.2f%s" % [
				row.get("label", ""), row.get("base", 1.0), row.get("effective", 1.0), _nat_suffix_plain(nat),
			]


static func _nat_suffix(nat: String) -> String:
	if nat.is_empty():
		return ""
	return " %s(%s)[/color]" % [COLOR_NATIONAL, nat]


static func _nat_suffix_plain(nat: String) -> String:
	if nat.is_empty():
		return ""
	return " (%s)" % nat


static func _owner_controller_bbcode(province: Province) -> String:
	var owner := province.owner_tag if not province.owner_tag.is_empty() else "—"
	var ctrl := province.controller_tag if not province.controller_tag.is_empty() else owner
	if ctrl == owner:
		return "%sOwner: %s[/color]" % [COLOR_MUTED, owner]
	return "%sOwner: %s  ·  %s⚑ Held by: %s[/color]" % [COLOR_MUTED, owner, COLOR_WARN, ctrl]


static func _battle_block_for(
	province: Province,
	selected_province_id: int,
	other_province: Province,
) -> String:
	if other_province != null and other_province.id != province.id:
		return _battle_preview_block(province, other_province, selected_province_id)
	return _local_battle_block(province)


# --- National sources ---

static func _national_spirit_lines(country_tag: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if typeof(NationalSpiritManager) == TYPE_NIL:
		return lines
	var data := NationalSpiritManager.get_spirits_screen_data(country_tag)
	for spirit in data.permanent_spirits:
		if typeof(spirit) != TYPE_DICTIONARY:
			continue
		var mods := _extract_relevant_modifiers(spirit.get("modifier_details", []))
		if mods.is_empty():
			continue
		lines.append(
			"%s  ◆ Spirit · %s: %s[/color]" % [COLOR_NATIONAL, spirit.get("name", ""), ", ".join(mods)]
		)
	return lines


static func _temporary_effect_lines(country_tag: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if typeof(NationalSpiritManager) == TYPE_NIL:
		return lines
	for row in NationalSpiritManager.get_temporary_effect_rows(country_tag):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var mods := _extract_relevant_modifiers(row.get("modifier_details", []))
		if mods.is_empty():
			continue
		var months := int(row.get("remaining_months", 0))
		lines.append(
			"%s  ⏱ Timed · %s (%dm): %s[/color]"
			% [COLOR_WARN, row.get("source_label", "Effect"), months, ", ".join(mods)]
		)
	return lines


static func _extract_relevant_modifiers(details: Array) -> PackedStringArray:
	var parts := PackedStringArray()
	for raw in details:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var d := raw as Dictionary
		var key := str(d.get("key", "")).to_lower()
		if not _modifier_key_affects_provinces(key):
			continue
		parts.append("%s %s" % [d.get("label", key), d.get("value_text", "")])
	return parts


static func _modifier_key_affects_provinces(key: String) -> bool:
	var k := key.to_lower()
	for rel in PROVINCE_MODIFIER_KEYS:
		if rel in k or k in rel:
			return true
	return false


static func _agent_network_line(province_id: int, country_tag: String) -> String:
	if typeof(AgentManager) == TYPE_NIL:
		return ""
	var net: AgentNetwork = AgentManager.get_network(province_id)
	if net == null or not net.is_active():
		return ""
	if net.controlling_country.strip_edges().to_upper() != country_tag:
		return ""
	return (
		"%s  ◎ Agent network: %s (str %.0f, %d locals)[/color]"
		% [COLOR_NATIONAL, net.focus, net.strength, net.local_operatives]
	)


# --- Battle preview (unchanged logic, bbcode headers) ---

static func get_battle_preview(attacker: Province, defender: Province) -> Dictionary:
	if attacker == null or defender == null:
		return {}
	var terrain := defender.terrain if not defender.terrain.is_empty() else attacker.terrain
	var resolver := CombatResolver.new()
	var rules_width := resolver.get_combat_width_for_battle(attacker.id, defender.id, terrain)
	resolver.free()
	var calc_display := CombatWidthCalculator.new()
	var terrain_mod := calc_display.get_terrain_width_modifier(terrain)
	calc_display.free()
	var prov_mult := (attacker.get_combat_width_modifier() + defender.get_combat_width_modifier()) * 0.5
	var pe_att := get_province_effects_for(attacker)
	var pe_def := get_province_effects_for(defender)
	var att_width := pe_att.get_effective_combat_width_multiplier() if pe_att else 1.0
	var def_width := pe_def.get_effective_combat_width_multiplier() if pe_def else 1.0
	var def_org := pe_def.get_effective_organization_recovery() if pe_def else 1.0

	# Compute key factors for tips (balance: only biggest impact ones; clear player language; compare to HoI4 factor visibility but filtered)
	var att_pow: float = 100.0 + float(attacker.infrastructure) * 3.0 + float(attacker.development_level) * 2.0
	var def_pow: float = 100.0 + float(defender.infrastructure) * 3.0 + float(defender.development_level) * 2.0
	var ratio: float = att_pow / maxf(1.0, att_pow + def_pow)
	var odds: float = clampf(ratio * 100.0, 15.0, 85.0)
	# Live multi-phase assault estimate card pilot (BattleManager).
	var assault_card: Dictionary = {}
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("build_weather_aware_assault_estimate_card"):
		assault_card = BattleManager.build_weather_aware_assault_estimate_card(
			att_pow, def_pow, defender.id, 1.0, str(defender.name)
		)
	elif typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("build_assault_estimate_card"):
		assault_card = BattleManager.build_assault_estimate_card(
			att_pow, def_pow, 1.0, 1.0, str(defender.name)
		)

	# Supply (use depot if available)
	var supply_mod: float = 1.0
	var sm := _supply_manager()
	if sm != null and sm.has_method("get_depot_state"):
		var d: Variant = sm.call("get_depot_state", defender.id)
		if d and d.fill_ratio() < 0.4:
			supply_mod = 0.65

	# Air dominance for large regions: use CombatPresenceRegistry for realistic scale.
	var air_dom: float = 0.5
	var reg := _combat_presence_registry()
	if reg != null and reg.has_method("get_report"):
		var att_tag := "player"
		var rpt: Variant = reg.call("get_report", attacker.id)
		if rpt and rpt.has_method("get_air_dominance_for"):
			air_dom = float(rpt.call("get_air_dominance_for", att_tag))
	var air_supp := air_dom > 0.55
	var enemy_air := air_dom < 0.8  # even at 0.7, enemy can still operate with costs

	# Encircled approx (low supply or isolated)
	var encircled := supply_mod < 0.7 or randf() < 0.1

	# Fort from settlement
	var fort_mod := 1.0 + (defender.settlement_level * 0.25)
	var our_fort := attacker.settlement_level > 0.2

	# Pre-battle espionage/sabotage (high-leverage per combat recs: intel prep, agent sabo on defender readiness/fort/odds; ties to AgentManager depot or province network)
	var sabo_level := 0.0
	if typeof(AgentManager) != TYPE_NIL and AgentManager.has_method("get_depot_state"):
		var ds: Variant = AgentManager.call("get_depot_state", defender.id)
		if ds and "sabotage_level" in ds:
			sabo_level = clampf(float(ds.sabotage_level), 0.0, 0.6)
	elif typeof(AgentManager) != TYPE_NIL and AgentManager.has_method("get_active_missions"):
		# Fallback: light presence if network active (real impl tracks pre-battle missions)
		sabo_level = 0.15 if randf() < 0.25 else 0.0
	if sabo_level > 0.08:
		fort_mod *= (1.0 - sabo_level * 0.4)
		# Also bias power slightly for preview
		def_pow *= (1.0 - sabo_level * 0.2)

	# Night
	var is_night := false
	if typeof(TimeManager) != TYPE_NIL:
		# assume simple
		is_night = (TimeManager.game_hour if TimeManager.has_method("game_hour") else 12) > 20 or (TimeManager.game_hour if TimeManager.has_method("game_hour") else 12) < 6

	# Leader (placeholder)
	var leader_imp := 0.12 if randf() > 0.6 else 0.0

	# Special (amphib, mountain from terrain/special units)
	var special := ""
	if "coast" in terrain or "river" in terrain:
		special = "amphib"
	elif "mountain" in terrain:
		special = "mountain_specialist"
	var counter := randf() < 0.18

	var preview := {
		"terrain": terrain,
		"terrain_width_modifier": terrain_mod,
		"rules_engagement_width": rules_width,
		"province_width_multiplier": prov_mult,
		"estimated_effective_width": rules_width,
		"attacker_width_mult": att_width,
		"defender_width_mult": def_width,
		"defender_org_recovery": def_org,
		"attacker_infra": attacker.infrastructure,
		"defender_infra": defender.infrastructure,
		"attacker_dev": attacker.development_level,
		"defender_dev": defender.development_level,
		"snow_coverage": 0.0,
		"snow_potential": defender.snow_potential,
	}
	# Populate live snow if WM available (for combat preview note)
	if typeof(WeatherManager) != TYPE_NIL:
		var wm = null
		if Engine.has_singleton("WeatherManager"):
			wm = Engine.get_singleton("WeatherManager")
		if wm == null:
			var tree := Engine.get_main_loop() as SceneTree
			if tree and tree.root:
				wm = tree.root.get_node_or_null("/root/WeatherManager")
		if wm and wm.has_method("get_province_snow"):
			preview["snow_coverage"] = float(wm.get_province_snow(defender.id))
	if float(preview.get("snow_coverage", 0.0)) > 0.1 or float(preview.get("snow_potential", 0.0)) > 0.1:
		preview["snow_note"] = "❄ Snow cov %.0f%% (layer pot %.0f%%) - attack/mobility hit" % [float(preview["snow_coverage"])*100, float(preview["snow_potential"])*100]
	preview["odds_attacker_win"] = odds
	# Explicit power fields for map assault toast (was missing → GER 0 vs FRA 0).
	preview["attack_power"] = att_pow
	preview["defense_power"] = def_pow
	# Optional: fold live divisions if BattleManager can list them.
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("get_divisions_at_province"):
		var att_divs: Array = BattleManager.get_divisions_at_province(attacker.id, "")
		var def_divs: Array = BattleManager.get_divisions_at_province(defender.id, "")
		var att_n := att_divs.size()
		var def_n := def_divs.size()
		if att_n > 0:
			preview["attack_power"] = att_pow + float(att_n) * 25.0
			preview["attacker_divisions"] = att_n
		if def_n > 0:
			preview["defense_power"] = def_pow + float(def_n) * 25.0
			preview["defender_divisions"] = def_n
		# Recompute rough odds with division-weighted power.
		var ap2 := float(preview["attack_power"])
		var dp2 := float(preview["defense_power"])
		preview["odds_attacker_win"] = clampf((ap2 / maxf(1.0, ap2 + dp2)) * 100.0, 10.0, 90.0)
	preview["engaged_units_att"] = ["Infantry x4", "Armor x2", "Support x1"]
	preview["engaged_units_def"] = ["Infantry x3", "Fort x1"]
	preview["leaders_att"] = ["Rommel (+15% attack, +org)"]
	preview["leaders_def"] = ["Manstein (+12% def)"]
	preview["air_factors"] = "+10% attacker CAS support" if randf() > 0.5 else ""
	# Air recon from sorties (RECON missions) for intel bonus in preview
	var air_recon_b := 0.0
	var sm_pi := _supply_manager()
	if sm_pi and sm_pi.has_method("get_combat_presence_registry"):
		var reg_pi: Variant = sm_pi.call("get_combat_presence_registry")
		if reg_pi != null and attacker != null and reg_pi.has_method("get_report"):
			var rpt_pi: Variant = reg_pi.call("get_report", attacker.id)
			if rpt_pi != null and rpt_pi.has_method("get_air_recon_bonus"):
				air_recon_b = float(rpt_pi.call("get_air_recon_bonus", "player"))
	if air_recon_b > 0.05:
		preview["air_recon_bonus"] = air_recon_b
		preview["air_factors"] += " +recon intel"
	preview["modifiers"] = ["-8% night attack (weather)", "+22% defending bonus", "+5% terrain advantage"]
	if "marine" in str(preview.get("terrain", "")) or randf() > 0.7:
		preview["modifiers"].append("+12% amphibious (Marines)")
	if "mountain" in str(preview.get("terrain", "")):
		preview["modifiers"].append("+15% mountain specialists")
	if sabo_level > 0.08:
		preview["sabotage_level"] = sabo_level
		preview["modifiers"].append("-%.0f%% defender fort/readiness (pre-battle agent sabotage/intel)" % (sabo_level * 40))
	preview["odds_note"] = "Est. attacker success odds: %.0f%% (power %.1f:%.1f)" % [odds, att_pow, def_pow]
	# Attach multi-phase assault estimate card for inspector/combat surfaces.
	if not assault_card.is_empty():
		preview["assault_estimate_card"] = assault_card
		preview["assault_estimate_plain"] = str(assault_card.get("plain", ""))
		preview["assault_recommendation"] = str(assault_card.get("recommendation", ""))
		if not str(assault_card.get("recommendation", "")).is_empty():
			preview["modifiers"].append(str(assault_card.get("recommendation", "")))
	return preview


static func _local_battle_block(province: Province) -> String:
	var preview := get_battle_preview(province, province)
	var block := _format_preview_header("Local engagement", preview)
	var pe := get_province_effects_for(province)
	if pe != null:
		block += (
			"\n  %sNational/org on defender: width ×%.2f · org ×%.2f[/color]"
			% [
				COLOR_MUTED,
				pe.get_effective_combat_width_multiplier(),
				pe.get_effective_organization_recovery(),
			]
		)
	block += "\n  %sSelect adjacent province for cross-border preview.[/color]" % COLOR_MUTED
	return block


static func _battle_preview_block(
	hovered: Province,
	counterpart: Province,
	selected_province_id: int,
) -> String:
	var attacker := hovered
	var defender := counterpart
	var title := "Battle preview"
	if selected_province_id == hovered.id:
		title = "If attacked from %s" % counterpart.name
		attacker = counterpart
		defender = hovered
	elif selected_province_id == counterpart.id:
		title = "If attacking %s" % hovered.name
		attacker = counterpart
		defender = hovered
	else:
		title = "%s vs %s" % [counterpart.name, hovered.name]
	var preview := get_battle_preview(attacker, defender)
	var block := _format_preview_header("⚔ " + title, preview)
	var situation := build_compare_situation_note(attacker, defender)
	if not situation.is_empty():
		block += "\n" + situation
	# Player-friendly combat hover: ONLY most important factors (biggest impact). Not overwhelming.
	# Clear tips. Click for full AAR/details (future panel shows all).
	var tips: Array[String] = []
	# Dynamic, balanced, clear tips (only most important for hover; full detail in AAR panel). Inspired by HoI4 clear factor tooltips + player agency.
	if preview.get("odds_attacker_win", 50) < 35:
		tips.append("Our forces are heavily outnumbered or outmatched")
	elif preview.get("odds_attacker_win", 50) < 45:
		tips.append("Our forces are outnumbered or disadvantaged")
	if preview.get("encircled", false):
		tips.append("Our forces are encircled (supply cut risk)")
	if float(preview.get("supply_mod", 1.0)) < 0.65:
		tips.append("Our forces are critically out of supply")
	if preview.get("air_superiority", false):
		tips.append("We have air superiority (CAS bonus active)")
	if preview.get("enemy_air", false):
		tips.append("The enemy enjoys air supremacy (harassment penalty)")
	# Air dominance note for large provinces
	if "air_dom" in preview:
		var dom = float(preview.get("air_dom", 0.5))
		if dom > 0.8:
			tips.append("Overwhelming air dominance - enemy ops heavily suppressed at high cost")
		elif dom > 0.55:
			tips.append("Air advantage but region large - enemy can still conduct limited ops (costly)")
	if "amphib" in str(preview.get("special", "")):
		tips.append("Conducting amphibious assault — our units suffer additional organizational loss")
	if preview.get("fort_mod", 1.0) > 1.3:
		tips.append("The enemy is heavily fortified")
	elif preview.get("fort_mod", 1.0) > 1.1:
		tips.append("The enemy is fortified / dug in")
	if preview.get("our_fort", false):
		tips.append("We are fortified / dug in (defensive bonus)")
	if float(preview.get("sabotage_level", 0.0)) > 0.08:
		tips.append("Pre-battle agent sabotage/intel reduced enemy readiness/fort (~%.0f%% effect)" % (float(preview.get("sabotage_level",0.0))*40.0))
	if preview.get("counterattack", false):
		tips.append("The enemy is counterattacking")
	if preview.get("is_night", false):
		tips.append("Night operations — visibility and org penalties apply")
	if preview.get("leader_impact", 0.0) > 0.1:
		tips.append("Leader impact is significant in this battle")
	if "mountain" in str(preview.get("special", "")):
		tips.append("Mountain warfare — specialists have edge")
	if preview.get("space_strike", false):
		tips.append("Orbital strike support active — guided munitions have much greater impacts on troops")
	if preview.get("guided_munitions_bonus", 0.0) > 0.1:
		tips.append("Guided munitions bonus for advanced units (space comms/tech)")
	# Unit specialty factors (from resolver power in live calls or passed; HoI4-style % visible)
	var umf: Dictionary = preview.get("unit_mod_factors", {}) as Dictionary
	if umf:
		if umf.has("marine_amphib_coastal"):
			tips.append("Marine amphibious specialists active (+28% soft in coastal)")
		if umf.has("paratroop_org_risk"):
			tips.append("Paratroop drop in progress — high organizational risk (-18% org)")
		if umf.has("sf_flanking_sabotage"):
			tips.append("Special forces flanking/sabotage bonus (+22% flank, pre-battle defender hit)")
		if umf.has("mountain_terrain_bonus"):
			tips.append("Mountain specialists in favorable terrain (+32% soft)")
		if umf.has("ski_winter_terrain"):
			tips.append("Ski/winter troops dominant in snow (+35% soft)")
		if umf.has("space_orbital_support"):
			tips.append("Space-capable/orbital recon support (+20% + guided precision)")
		if umf.has("guided_munitions_soft"):
			tips.append("Guided munitions active — devastating precision on soft troops (+50% soft impact)")
	tips.append("See full AAR (F10) for unit combat logs (Formation.combat_log: date/province/result/key factors/leader), leader impacts, modifiers with % values, space/air effects")
	if tips.size() > 0:
		block += "\n  %sKey situation: %s[/color]" % [COLOR_MUTED, " · ".join(tips)]
	# Update tips to reference AAR for full specificity (unit logs from Formation, leader, modifiers %, space/air)
	# Accessibility for full AAR (not in hover to avoid overwhelm; click/F10 for deep)
	block += "\n  %s[Press F10 for full AAR] — unit combat logs, leader impacts, full modifiers %% list, space/air effects, tips. Balance: air dominance 4:1+ full suppress; space high precision impact but maintenance costly, not instant win.[/color]" % COLOR_MUTED
	# Most important: odds, key units/leaders if standout, major modifiers.
	if preview.has("odds_attacker_win"):
		block += "\n  %sEstimated success odds: %.0f%% (click for full breakdown) [Press F10 for full AAR][/color]" % [COLOR_EFFECTIVE, float(preview["odds_attacker_win"])]
	return block


static func _format_preview_header(title: String, preview: Dictionary) -> String:
	if preview.is_empty():
		return "%s%s: unavailable[/color]" % [COLOR_HEADER, title]
	var lines: PackedStringArray = []
	lines.append("%s%s[/color]" % [COLOR_HEADER, title])
	lines.append(
		"  %sEngagement width: %.1f[/color]"
		% [COLOR_EFFECTIVE, float(preview.get("estimated_effective_width", preview.get("rules_engagement_width", 0.0)))]
	)
	lines.append(
		"  %s%s ×%.2f · Infra %d vs %d · Dev %d vs %d[/color]"
		% [
			COLOR_MUTED,
			str(preview.get("terrain", "plains")).capitalize(),
			float(preview.get("terrain_width_modifier", 1.0)),
			int(preview.get("attacker_infra", 0)),
			int(preview.get("defender_infra", 0)),
			int(preview.get("attacker_dev", 0)),
			int(preview.get("defender_dev", 0)),
		]
	)
	if preview.has("snow_note"):
		lines.append("  %s%s[/color]" % [COLOR_MUTED, str(preview.get("snow_note", ""))])
	lines.append(
		"  %sAttacker width ×%.2f · Defender width ×%.2f · Defender org ×%.2f[/color]"
		% [
			COLOR_NATIONAL,
			float(preview.get("attacker_width_mult", 1.0)),
			float(preview.get("defender_width_mult", 1.0)),
			float(preview.get("defender_org_recovery", 1.0)),
		]
	)
	return "\n".join(lines)


static func _terrain_width_line(terrain: String) -> String:
	var calc := CombatWidthCalculator.new()
	var mod := calc.get_terrain_width_modifier(terrain)
	calc.free()
	return "Terrain (%s) width mod: ×%.2f" % [terrain.capitalize(), mod]


static func _depot_summary_line(province_id: int) -> String:
	var sm := _supply_manager()
	if sm == null:
		return "Depot: network not built"
	var depot: ProvinceDepotState = sm.get_depot_state(province_id)
	if depot == null:
		return "Depot: not a supply hub"
	var fill := int(round(depot.fill_ratio() * 100.0))
	var status := "adequate"
	if fill < 35:
		status = "critical"
	elif fill < 65:
		status = "strained"
	return "Depot: %d%% full (%s) · %.0f t/day · cap %.0f" % [fill, status, depot.throughput_capacity, depot.storage_capacity]


static func _resolve_battle_counterpart(province: Province, selected_province_id: int) -> Province:
	if selected_province_id < 0 or selected_province_id == province.id:
		return null
	# Prefer MapManager (central authority)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacency_system"):
		var adj := MapManager.get_adjacency_system()
		if adj != null and not adj.are_adjacent(province.id, selected_province_id):
			return null
		var p := MapManager.get_province(selected_province_id)
		if p != null:
			return p
	# Fallback
	var loader := _scenario_loader()
	if loader == null or not loader.provinces.has(selected_province_id):
		return null
	if loader.adjacency != null and not loader.adjacency.are_adjacent(province.id, selected_province_id):
		return null
	return loader.provinces[selected_province_id] as Province


static func _province_by_id(province_id: int) -> Province:
	var p := MapManager.get_province(province_id) if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province") else null
	if p != null:
		return p
	var loader := _scenario_loader()
	if loader != null and loader.provinces.has(province_id):
		return loader.provinces[province_id] as Province
	return null


static func _supply_manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	return tree.root.get_node_or_null("SupplyManager")

static func _combat_presence_registry() -> CombatPresenceRegistry:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	var sm: Node = tree.root.get_node_or_null("SupplyManager")
	if sm != null and sm.has_method("get_combat_presence_registry"):
		return sm.get_combat_presence_registry() as CombatPresenceRegistry
	return null


static func _scenario_loader() -> ScenarioLoader:
	# DEPRECATED — Direct ScenarioLoader access is legacy technical debt.
	# All map code (overlays, tooltips, picking, effects, culling) must use MapManager exclusively.
	# This helper remains only for a couple of internal fallback paths during the transition and will be removed.
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	var node: Node = tree.root.find_child("ScenarioLoader", true, false)
	return node as ScenarioLoader


static func _get_stationed_missions_summary(province_id: int, country_tag: String = "") -> String:
	# Key gameplay UI part: show current naval/air/land missions, intensity, attach for formations in/owning this province.
	# Used in inspector/report for visibility of orders (player can use Debug sub-menu or future full UI to assign).
	if typeof(LeaderManager) == TYPE_NIL:
		return ""
	var parts: Array[String] = []
	for f in LeaderManager.get_formations_for_country(country_tag if country_tag else ""):
		if f == null or f.stationed_province_id != province_id:
			continue
		var cat := f.get_category() if f.has_method("get_category") else ""
		var line := ""
		if cat == "naval" and f.current_naval_order != "":
			line = "Naval: %s (int %.1f)" % [f.current_naval_order, f.mission_intensity]
		elif cat == "air" and f.current_air_mission != "":
			var att := f.attached_air_formation_id if f.attached_air_formation_id != "" else ""
			line = "Air: %s%s (int %.1f)" % [f.current_air_mission, " (attached to ship)" if att else "", f.mission_intensity]
		elif cat == "land" and f.current_land_mission != "":
			line = "Land: %s (int %.1f)" % [f.current_land_mission, f.mission_intensity]
		if line != "":
			parts.append(line)
	return "; ".join(parts) if parts.size() > 0 else "None (assign via F10 Debug missions/orders sub-menu or full formation UI)"

## Next-70 playability chips.

static func build_leader_weather_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_weather_day_for_province"):
		var day: Dictionary = MapManager.leader_weather_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_oob_factory_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("oob_factory_day_for_province"):
		var day: Dictionary = MapManager.oob_factory_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_move_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("move_ops_day_for_province"):
		var day: Dictionary = MapManager.move_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_wx_mission_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_wx_mission_day_for_province"):
		var day: Dictionary = MapManager.fleet_wx_mission_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_player_surface_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("player_surface_day_live"):
		var day: Dictionary = MapManager.player_surface_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_province_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_province_plan_day_for_province"):
		var day: Dictionary = MapManager.multi_province_plan_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_prod_auto_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_prod_auto_day_for_province"):
		var day: Dictionary = MapManager.theater_prod_auto_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_mutation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_mutation_day_for_province"):
		var day: Dictionary = MapManager.focus_mutation_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_mutation_feedback_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("mutation_feedback_day_live"):
		var day: Dictionary = MapManager.mutation_feedback_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_quarterly_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_quarterly_day_live"):
		var day: Dictionary = MapManager.hh_quarterly_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_depot_weather_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("depot_weather_day_for_province"):
		var day: Dictionary = MapManager.depot_weather_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_patrol_strip_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_patrol_strip_day_for_province"):
		var day: Dictionary = MapManager.fleet_patrol_strip_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_close_loop_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("close_loop_day_live"):
		var day: Dictionary = MapManager.close_loop_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_missions_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_missions_day_live"):
		var day: Dictionary = MapManager.agent_missions_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_supply_route_mutation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("supply_route_mutation_day_for_province"):
		var day: Dictionary = MapManager.supply_route_mutation_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_fuel_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_fuel_day_for_province"):
		var day: Dictionary = MapManager.basing_fuel_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_ops_dashboard_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("ops_dashboard_day_for_province"):
		var day: Dictionary = MapManager.ops_dashboard_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_theater_tick_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_theater_tick_day_for_province"):
		var day: Dictionary = MapManager.daily_theater_tick_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_command_log_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("command_log_day_live"):
		var day: Dictionary = MapManager.command_log_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_integrity_gate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("integrity_gate_day_live"):
		var day: Dictionary = MapManager.integrity_gate_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

## Next-80 execution surface chips.

static func build_result_feedback_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("result_feedback_day_live"):
		var day: Dictionary = MapManager.result_feedback_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_day_budget_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("day_budget_day_for_province"):
		var day: Dictionary = MapManager.day_budget_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_auto_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_auto_plan_day_live"):
		var day: Dictionary = MapManager.hh_auto_plan_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_append_log_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("append_log_day_live"):
		var day: Dictionary = MapManager.append_log_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_log_strip_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("log_strip_day_live"):
		var day: Dictionary = MapManager.log_strip_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_readiness_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_readiness_day_for_province"):
		var day: Dictionary = MapManager.assault_readiness_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_coherence_delta_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("coherence_delta_day_for_province"):
		var day: Dictionary = MapManager.coherence_delta_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_order_day_live"):
		var day: Dictionary = MapManager.agent_order_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_execution_gate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("execution_gate_day_live"):
		var day: Dictionary = MapManager.execution_gate_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_cohesion_gate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("cohesion_gate_day_live"):
		var day: Dictionary = MapManager.cohesion_gate_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_command_gate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("command_gate_day_live"):
		var day: Dictionary = MapManager.command_gate_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_execute_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("execute_order_day_for_province"):
		var day: Dictionary = MapManager.execute_order_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_sortie_ready_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_sortie_ready_day_for_province"):
		var day: Dictionary = MapManager.air_sortie_ready_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_combat_brief_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_combat_brief_day_for_province"):
		var day: Dictionary = MapManager.weather_combat_brief_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_day_audit_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("day_audit_day_live"):
		var day: Dictionary = MapManager.day_audit_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_map_visible_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("map_visible_day_for_province"):
		var day: Dictionary = MapManager.map_visible_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_card_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_card_day_for_province"):
		var day: Dictionary = MapManager.assault_card_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_slot_list_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_slot_list_day_for_province"):
		var day: Dictionary = MapManager.save_slot_list_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_phase_estimate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_phase_estimate_day_for_province"):
		var day: Dictionary = MapManager.multi_phase_estimate_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_strip_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_strip_day_for_province"):
		var day: Dictionary = MapManager.campaign_strip_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

## Next-90 live command chips.

static func build_mutation_result_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("mutation_result_day_live"):
		var day: Dictionary = MapManager.mutation_result_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_mutation_strip_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("mutation_strip_day_live"):
		var day: Dictionary = MapManager.mutation_strip_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_close_mutation_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("close_mutation_day_live"):
		var day: Dictionary = MapManager.close_mutation_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_mutation_gate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("mutation_gate_day_live"):
		var day: Dictionary = MapManager.mutation_gate_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agenda_pick_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agenda_pick_day_live"):
		var day: Dictionary = MapManager.agenda_pick_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agenda_actions_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agenda_actions_day_live"):
		var day: Dictionary = MapManager.agenda_actions_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_commit_order_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_commit_order_day_live"):
		var day: Dictionary = MapManager.hh_commit_order_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_hh_commit_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_hh_commit_day_live"):
		var day: Dictionary = MapManager.theater_hh_commit_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_counterplay_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_counterplay_day_live"):
		var day: Dictionary = MapManager.hh_counterplay_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_task_group_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("task_group_day_for_province"):
		var day: Dictionary = MapManager.task_group_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_basing_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_basing_day_for_province"):
		var day: Dictionary = MapManager.naval_basing_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_multi_phase_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_multi_phase_day_for_province"):
		var day: Dictionary = MapManager.naval_multi_phase_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_coastal_fog_gate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("coastal_fog_gate_day_for_province"):
		var day: Dictionary = MapManager.coastal_fog_gate_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_phase_ribbon_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("phase_ribbon_day_for_province"):
		var day: Dictionary = MapManager.phase_ribbon_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_rank_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_rank_day_for_province"):
		var day: Dictionary = MapManager.assault_rank_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_joint_timeline_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_timeline_day_for_province"):
		var day: Dictionary = MapManager.joint_timeline_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daylight_combat_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daylight_combat_day_for_province"):
		var day: Dictionary = MapManager.daylight_combat_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_auto_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_auto_day_for_province"):
		var day: Dictionary = MapManager.production_auto_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_risk_alert_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_risk_alert_day_for_province"):
		var day: Dictionary = MapManager.production_risk_alert_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_day_results_flair_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("day_results_flair_day_live"):
		var day: Dictionary = MapManager.day_results_flair_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

## Next-100 world-class chips.

static func build_best_assault_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("best_assault_live_day_live"):
		var day: Dictionary = MapManager.best_assault_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_best_station_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("best_station_live_day_live"):
		var day: Dictionary = MapManager.best_station_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_execute_one_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("execute_one_live_day_live"):
		var day: Dictionary = MapManager.execute_one_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_fuel_loop_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_fuel_loop_day_for_province"):
		var day: Dictionary = MapManager.basing_fuel_loop_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_wx_package_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_wx_package_day_for_province"):
		var day: Dictionary = MapManager.fleet_wx_package_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_wx_window_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_wx_window_day_for_province"):
		var day: Dictionary = MapManager.convoy_wx_window_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_wx_score_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_wx_score_day_for_province"):
		var day: Dictionary = MapManager.focus_wx_score_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_morale_wx_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("morale_wx_day_for_province"):
		var day: Dictionary = MapManager.morale_wx_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_risk_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_risk_live_day_live"):
		var day: Dictionary = MapManager.campaign_risk_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_depot_wx_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("depot_wx_live_day_for_province"):
		var day: Dictionary = MapManager.depot_wx_live_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_fleet_auto_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_fleet_auto_day_live"):
		var day: Dictionary = MapManager.daily_fleet_auto_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_combat_auto_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_combat_auto_day_live"):
		var day: Dictionary = MapManager.daily_combat_auto_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_agent_auto_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_agent_auto_day_live"):
		var day: Dictionary = MapManager.daily_agent_auto_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_supply_auto_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_supply_auto_day_live"):
		var day: Dictionary = MapManager.daily_supply_auto_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_signals_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_signals_day_for_province"):
		var day: Dictionary = MapManager.basing_signals_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_rates_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_rates_day_for_province"):
		var day: Dictionary = MapManager.basing_rates_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_wx_mult_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_wx_mult_day_for_province"):
		var day: Dictionary = MapManager.combat_wx_mult_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_sea_zone_trade_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sea_zone_trade_day_for_province"):
		var day: Dictionary = MapManager.sea_zone_trade_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_secondary_trail_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_secondary_trail_day_live"):
		var day: Dictionary = MapManager.hh_secondary_trail_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_campaign_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_campaign_live_day_live"):
		var day: Dictionary = MapManager.agent_campaign_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

## Next-110 incomplete loops chips.

static func build_live_mut_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("live_mut_board_day_live"):
		var day: Dictionary = MapManager.live_mut_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_feedback_chain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("feedback_chain_day_live"):
		var day: Dictionary = MapManager.feedback_chain_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_mut_close_stack_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("mut_close_stack_day_live"):
		var day: Dictionary = MapManager.mut_close_stack_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_dual_domain_mutate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("dual_domain_mutate_day_live"):
		var day: Dictionary = MapManager.dual_domain_mutate_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_mut_fb_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_mut_fb_day_live"):
		var day: Dictionary = MapManager.assault_mut_fb_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_mut_log_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_mut_log_day_live"):
		var day: Dictionary = MapManager.agent_mut_log_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_supply_mut_fb_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("supply_mut_fb_day_live"):
		var day: Dictionary = MapManager.supply_mut_fb_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_surface_stack_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_surface_stack_day_for_province"):
		var day: Dictionary = MapManager.combat_surface_stack_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_phase_timeline_stack_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("phase_timeline_stack_day_for_province"):
		var day: Dictionary = MapManager.phase_timeline_stack_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_rank_card_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_rank_card_day_for_province"):
		var day: Dictionary = MapManager.assault_rank_card_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_joint_naval_land_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_naval_land_day_for_province"):
		var day: Dictionary = MapManager.joint_naval_land_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_front_surface_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_surface_day_for_province"):
		var day: Dictionary = MapManager.multi_front_surface_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_depth_strip_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_depth_strip_day_for_province"):
		var day: Dictionary = MapManager.combat_depth_strip_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_phase_estimate_ribbon_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("phase_estimate_ribbon_day_for_province"):
		var day: Dictionary = MapManager.phase_estimate_ribbon_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_path_stack_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_path_stack_day_for_province"):
		var day: Dictionary = MapManager.fleet_path_stack_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_mission_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_mission_day_for_province"):
		var day: Dictionary = MapManager.basing_mission_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_path_stack_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_path_stack_day_live"):
		var day: Dictionary = MapManager.hh_path_stack_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_trail_counter_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_trail_counter_day_live"):
		var day: Dictionary = MapManager.hh_trail_counter_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_mission_path_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_mission_path_day_live"):
		var day: Dictionary = MapManager.agent_mission_path_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_incomplete_loop_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("incomplete_loop_close_day_live"):
		var day: Dictionary = MapManager.incomplete_loop_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

## Next-120 industry/save chips.

static func build_prod_mut_apply_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("prod_mut_apply_day_live"):
		var day: Dictionary = MapManager.prod_mut_apply_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_supply_mut_apply_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("supply_mut_apply_day_live"):
		var day: Dictionary = MapManager.supply_mut_apply_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_execute_prod_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("execute_prod_live_day_live"):
		var day: Dictionary = MapManager.execute_prod_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_day_budget_apply_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("day_budget_apply_day_live"):
		var day: Dictionary = MapManager.day_budget_apply_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_audit_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_audit_live_day_live"):
		var day: Dictionary = MapManager.apply_audit_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_live_apply_results_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("live_apply_results_day_live"):
		var day: Dictionary = MapManager.live_apply_results_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_mutation_gate_apply_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("mutation_gate_apply_day_live"):
		var day: Dictionary = MapManager.mutation_gate_apply_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_prod_auto_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_prod_auto_live_day_live"):
		var day: Dictionary = MapManager.daily_prod_auto_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_prod_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_prod_live_day_live"):
		var day: Dictionary = MapManager.theater_prod_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_prod_campaign_risk_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("prod_campaign_risk_day_for_province"):
		var day: Dictionary = MapManager.prod_campaign_risk_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_prod_wx_stack_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("prod_wx_stack_day_for_province"):
		var day: Dictionary = MapManager.prod_wx_stack_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_factory_risk_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("factory_risk_live_day_for_province"):
		var day: Dictionary = MapManager.factory_risk_live_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_depot_prod_stack_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("depot_prod_stack_day_for_province"):
		var day: Dictionary = MapManager.depot_prod_stack_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_industry_close_loop_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("industry_close_loop_day_for_province"):
		var day: Dictionary = MapManager.industry_close_loop_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_slot_surface_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_slot_surface_day_live"):
		var day: Dictionary = MapManager.save_slot_surface_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_browser_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_browser_live_day_live"):
		var day: Dictionary = MapManager.save_browser_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_continuity_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_continuity_day_live"):
		var day: Dictionary = MapManager.campaign_continuity_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_ops_dash_continuity_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("ops_dash_continuity_day_for_province"):
		var day: Dictionary = MapManager.ops_dash_continuity_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_execution_gate_cont_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("execution_gate_cont_day_live"):
		var day: Dictionary = MapManager.execution_gate_cont_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_industry_save_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("industry_save_close_day_live"):
		var day: Dictionary = MapManager.industry_save_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

## Next-130 fleet/HH/combat chips.

static func build_fleet_ai_task_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_ai_task_day_live"):
		var day: Dictionary = MapManager.fleet_ai_task_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_wx_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_wx_ops_day_live"):
		var day: Dictionary = MapManager.fleet_wx_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_fuel_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_fuel_ops_day_for_province"):
		var day: Dictionary = MapManager.basing_fuel_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_phase_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_phase_ops_day_for_province"):
		var day: Dictionary = MapManager.naval_phase_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_coastal_fog_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("coastal_fog_ops_day_for_province"):
		var day: Dictionary = MapManager.coastal_fog_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_station_mut_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_station_mut_day_live"):
		var day: Dictionary = MapManager.fleet_station_mut_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_task_mut_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_task_mut_day_live"):
		var day: Dictionary = MapManager.naval_task_mut_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_agenda_pick_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_agenda_pick_day_live"):
		var day: Dictionary = MapManager.hh_agenda_pick_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_agenda_actions_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_agenda_actions_day_live"):
		var day: Dictionary = MapManager.hh_agenda_actions_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_order_path_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_order_path_day_live"):
		var day: Dictionary = MapManager.hh_order_path_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_hh_path_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_hh_path_day_live"):
		var day: Dictionary = MapManager.theater_hh_path_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_trail_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_trail_ops_day_live"):
		var day: Dictionary = MapManager.hh_trail_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_mission_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_mission_ops_day_live"):
		var day: Dictionary = MapManager.agent_mission_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_campaign_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_campaign_ops_day_live"):
		var day: Dictionary = MapManager.agent_campaign_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_inspect_stack_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_inspect_stack_day_live"):
		var day: Dictionary = MapManager.combat_inspect_stack_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_phase_ribbon_inspect_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("phase_ribbon_inspect_day_for_province"):
		var day: Dictionary = MapManager.phase_ribbon_inspect_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_joint_timeline_inspect_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_timeline_inspect_day_for_province"):
		var day: Dictionary = MapManager.joint_timeline_inspect_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_rank_inspect_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_rank_inspect_day_for_province"):
		var day: Dictionary = MapManager.assault_rank_inspect_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_campaign_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_campaign_ops_day_for_province"):
		var day: Dictionary = MapManager.combat_campaign_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_hh_combat_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_hh_combat_close_day_live"):
		var day: Dictionary = MapManager.fleet_hh_combat_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

## Next-140 logistics/force/panel chips.

static func build_depot_logistics_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("depot_logistics_day_live"):
		var day: Dictionary = MapManager.depot_logistics_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_supply_route_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("supply_route_ops_day_live"):
		var day: Dictionary = MapManager.supply_route_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_move_path_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("move_path_ops_day_for_province"):
		var day: Dictionary = MapManager.move_path_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_province_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_province_ops_day_for_province"):
		var day: Dictionary = MapManager.multi_province_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_auto_tick_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_auto_tick_day_live"):
		var day: Dictionary = MapManager.theater_auto_tick_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_supply_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_supply_ops_day_for_province"):
		var day: Dictionary = MapManager.daily_supply_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_logistics_theater_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_theater_close_day_for_province"):
		var day: Dictionary = MapManager.logistics_theater_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_readiness_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_readiness_ops_day_live"):
		var day: Dictionary = MapManager.force_readiness_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_oob_factory_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("oob_factory_ops_day_live"):
		var day: Dictionary = MapManager.oob_factory_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_equip_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_equip_ops_day_live"):
		var day: Dictionary = MapManager.medium_equip_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_skim_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_skim_ops_day_for_province"):
		var day: Dictionary = MapManager.naval_skim_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_logistics_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_logistics_ops_day_for_province"):
		var day: Dictionary = MapManager.basing_logistics_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_force_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_force_ops_day_for_province"):
		var day: Dictionary = MapManager.production_force_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_oob_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_oob_close_day_live"):
		var day: Dictionary = MapManager.force_oob_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_player_surface_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("player_surface_ops_day_live"):
		var day: Dictionary = MapManager.player_surface_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_order_panel_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_panel_ops_day_live"):
		var day: Dictionary = MapManager.order_panel_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_panel_sections_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("panel_sections_ops_day_live"):
		var day: Dictionary = MapManager.panel_sections_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tooltip_flair_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tooltip_flair_ops_day_for_province"):
		var day: Dictionary = MapManager.tooltip_flair_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_audit_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_audit_ops_day_for_province"):
		var day: Dictionary = MapManager.apply_audit_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_logistics_force_panel_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_force_panel_close_day_live"):
		var day: Dictionary = MapManager.logistics_force_panel_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_wx_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_wx_ops_day_live"):
		var day: Dictionary = MapManager.combat_wx_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_prod_wx_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("prod_wx_ops_day_live"):
		var day: Dictionary = MapManager.prod_wx_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_sortie_wx_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_sortie_wx_day_for_province"):
		var day: Dictionary = MapManager.air_sortie_wx_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_morale_wx_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("morale_wx_ops_day_for_province"):
		var day: Dictionary = MapManager.morale_wx_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_wx_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_wx_ops_day_live"):
		var day: Dictionary = MapManager.convoy_wx_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daylight_wx_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daylight_wx_ops_day_for_province"):
		var day: Dictionary = MapManager.daylight_wx_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_ops_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_ops_close_day_live"):
		var day: Dictionary = MapManager.weather_ops_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_ops_day_live"):
		var day: Dictionary = MapManager.war_economy_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_prod_campaign_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("prod_campaign_ops_day_for_province"):
		var day: Dictionary = MapManager.prod_campaign_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_wx_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_wx_ops_day_live"):
		var day: Dictionary = MapManager.focus_wx_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_mut_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_mut_ops_day_for_province"):
		var day: Dictionary = MapManager.focus_mut_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_supply_economy_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("supply_economy_ops_day_for_province"):
		var day: Dictionary = MapManager.supply_economy_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_depot_economy_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("depot_economy_ops_day_for_province"):
		var day: Dictionary = MapManager.depot_economy_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_close_day_live"):
		var day: Dictionary = MapManager.war_economy_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_counter_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_counter_ops_day_live"):
		var day: Dictionary = MapManager.intel_counter_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_intel_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_intel_ops_day_live"):
		var day: Dictionary = MapManager.agent_intel_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_counter_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_counter_ops_day_for_province"):
		var day: Dictionary = MapManager.hh_counter_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_map_effect_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("map_effect_ops_day_for_province"):
		var day: Dictionary = MapManager.map_effect_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_coherence_intel_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("coherence_intel_day_for_province"):
		var day: Dictionary = MapManager.coherence_intel_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_economy_intel_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_economy_intel_close_day_live"):
		var day: Dictionary = MapManager.weather_economy_intel_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_province_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_province_campaign_day_live"):
		var day: Dictionary = MapManager.multi_province_campaign_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_auto_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_auto_campaign_day_live"):
		var day: Dictionary = MapManager.theater_auto_campaign_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_command_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_command_ops_day_for_province"):
		var day: Dictionary = MapManager.daily_command_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_readiness_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_readiness_ops_day_live"):
		var day: Dictionary = MapManager.theater_readiness_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_move_path_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("move_path_campaign_day_for_province"):
		var day: Dictionary = MapManager.move_path_campaign_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_order_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_order_board_day_for_province"):
		var day: Dictionary = MapManager.theater_order_board_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_campaign_close_day_live"):
		var day: Dictionary = MapManager.theater_campaign_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_fleet_sustain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_fleet_sustain_day_live"):
		var day: Dictionary = MapManager.basing_fleet_sustain_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_wx_sustain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_wx_sustain_day_for_province"):
		var day: Dictionary = MapManager.fleet_wx_sustain_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_sustain_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_sustain_ops_day_live"):
		var day: Dictionary = MapManager.convoy_sustain_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_sealane_joint_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sealane_joint_ops_day_live"):
		var day: Dictionary = MapManager.sealane_joint_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_order_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_order_ops_day_for_province"):
		var day: Dictionary = MapManager.naval_order_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_station_sustain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_station_sustain_day_for_province"):
		var day: Dictionary = MapManager.fleet_station_sustain_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_sealane_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_sealane_close_day_live"):
		var day: Dictionary = MapManager.naval_sealane_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_player_surface_session_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("player_surface_session_day_live"):
		var day: Dictionary = MapManager.player_surface_session_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_order_panel_session_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_panel_session_day_live"):
		var day: Dictionary = MapManager.order_panel_session_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_mutation_feedback_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("mutation_feedback_ops_day_for_province"):
		var day: Dictionary = MapManager.mutation_feedback_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_audit_session_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_audit_session_day_for_province"):
		var day: Dictionary = MapManager.apply_audit_session_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_decision_strip_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("decision_strip_ops_day_for_province"):
		var day: Dictionary = MapManager.decision_strip_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_naval_session_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_naval_session_close_day_live"):
		var day: Dictionary = MapManager.theater_naval_session_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_phase_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_phase_ops_day_live"):
		var day: Dictionary = MapManager.combat_phase_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_ready_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_ready_ops_day_live"):
		var day: Dictionary = MapManager.assault_ready_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_phase_est_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_phase_est_ops_day_live"):
		var day: Dictionary = MapManager.multi_phase_est_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_order_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_order_ops_day_for_province"):
		var day: Dictionary = MapManager.combat_order_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_rank_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_rank_ops_day_for_province"):
		var day: Dictionary = MapManager.assault_rank_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_phase_ribbon_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("phase_ribbon_ops_day_for_province"):
		var day: Dictionary = MapManager.phase_ribbon_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_phase_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_phase_close_day_live"):
		var day: Dictionary = MapManager.combat_phase_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_mission_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_mission_campaign_day_live"):
		var day: Dictionary = MapManager.agent_mission_campaign_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_dispatch_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_dispatch_ops_day_for_province"):
		var day: Dictionary = MapManager.agent_dispatch_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_commit_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_commit_campaign_day_for_province"):
		var day: Dictionary = MapManager.hh_commit_campaign_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_counterplay_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("counterplay_campaign_day_live"):
		var day: Dictionary = MapManager.counterplay_campaign_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_agenda_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_agenda_ops_day_for_province"):
		var day: Dictionary = MapManager.hh_agenda_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_hh_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_hh_joint_day_for_province"):
		var day: Dictionary = MapManager.agent_hh_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_hh_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_hh_close_day_live"):
		var day: Dictionary = MapManager.agent_hh_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_joint_theater_combat_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_theater_combat_day_live"):
		var day: Dictionary = MapManager.joint_theater_combat_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_joint_naval_combat_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_naval_combat_day_live"):
		var day: Dictionary = MapManager.joint_naval_combat_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_joint_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_joint_ops_day_for_province"):
		var day: Dictionary = MapManager.focus_joint_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_joint_command_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("joint_command_ops_day_live"):
		var day: Dictionary = MapManager.joint_command_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_domain_strip_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_domain_strip_day_for_province"):
		var day: Dictionary = MapManager.multi_domain_strip_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_agent_joint_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_agent_joint_close_day_live"):
		var day: Dictionary = MapManager.combat_agent_joint_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_prod_factory_risk_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("prod_factory_risk_ops_day_live"):
		var day: Dictionary = MapManager.prod_factory_risk_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_equip_horizon_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_equip_horizon_ops_day_live"):
		var day: Dictionary = MapManager.medium_equip_horizon_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_priority_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_priority_ops_day_live"):
		var day: Dictionary = MapManager.production_priority_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_oob_equip_continuity_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("oob_equip_continuity_day_for_province"):
		var day: Dictionary = MapManager.oob_equip_continuity_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_factory_line_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("factory_line_ops_day_for_province"):
		var day: Dictionary = MapManager.factory_line_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_stockpile_growth_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("stockpile_growth_ops_day_for_province"):
		var day: Dictionary = MapManager.stockpile_growth_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_oob_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_oob_close_day_live"):
		var day: Dictionary = MapManager.production_oob_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_sortie_front_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_sortie_front_ops_day_live"):
		var day: Dictionary = MapManager.air_sortie_front_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_front_rank_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_rank_ops_day_live"):
		var day: Dictionary = MapManager.multi_front_rank_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_land_joint_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_land_joint_ops_day_live"):
		var day: Dictionary = MapManager.air_land_joint_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_front_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_front_ops_day_for_province"):
		var day: Dictionary = MapManager.assault_front_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_forecast_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_forecast_ops_day_for_province"):
		var day: Dictionary = MapManager.air_forecast_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_front_supply_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_supply_ops_day_for_province"):
		var day: Dictionary = MapManager.multi_front_supply_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_front_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_front_close_day_live"):
		var day: Dictionary = MapManager.air_front_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_path_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_path_ops_day_live"):
		var day: Dictionary = MapManager.focus_path_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_cabinet_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_cabinet_ops_day_live"):
		var day: Dictionary = MapManager.war_cabinet_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_strip_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_strip_ops_day_for_province"):
		var day: Dictionary = MapManager.strategic_strip_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_priority_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_priority_ops_day_for_province"):
		var day: Dictionary = MapManager.focus_priority_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_continuity_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_continuity_ops_day_for_province"):
		var day: Dictionary = MapManager.strategic_continuity_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_prod_air_focus_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("prod_air_focus_close_day_live"):
		var day: Dictionary = MapManager.prod_air_focus_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_slot_integrity_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_slot_integrity_ops_day_live"):
		var day: Dictionary = MapManager.save_slot_integrity_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_autosave_session_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("autosave_session_ops_day_live"):
		var day: Dictionary = MapManager.autosave_session_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_session_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_session_ops_day_for_province"):
		var day: Dictionary = MapManager.campaign_session_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_resume_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_resume_ops_day_for_province"):
		var day: Dictionary = MapManager.save_resume_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_session_checkpoint_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("session_checkpoint_ops_day_for_province"):
		var day: Dictionary = MapManager.session_checkpoint_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_audit_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_audit_ops_day_for_province"):
		var day: Dictionary = MapManager.save_audit_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_session_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_session_close_day_live"):
		var day: Dictionary = MapManager.save_session_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_assign_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_assign_ops_day_live"):
		var day: Dictionary = MapManager.leader_assign_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_formation_ready_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("formation_ready_ops_day_live"):
		var day: Dictionary = MapManager.formation_ready_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_oob_assign_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("oob_assign_ops_day_for_province"):
		var day: Dictionary = MapManager.oob_assign_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_command_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_command_ops_day_for_province"):
		var day: Dictionary = MapManager.leader_command_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_formation_station_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("formation_station_ops_day_for_province"):
		var day: Dictionary = MapManager.formation_station_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_formation_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_formation_joint_day_for_province"):
		var day: Dictionary = MapManager.leader_formation_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_formation_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_formation_close_day_live"):
		var day: Dictionary = MapManager.leader_formation_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_trade_chain_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("trade_chain_ops_day_live"):
		var day: Dictionary = MapManager.trade_chain_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_escort_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_escort_ops_day_live"):
		var day: Dictionary = MapManager.convoy_escort_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_sealane_economy_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sealane_economy_ops_day_live"):
		var day: Dictionary = MapManager.sealane_economy_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_trade_route_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("trade_route_ops_day_for_province"):
		var day: Dictionary = MapManager.trade_route_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_trade_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_trade_joint_day_for_province"):
		var day: Dictionary = MapManager.convoy_trade_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_leader_trade_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_leader_trade_close_day_live"):
		var day: Dictionary = MapManager.save_leader_trade_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_panel_surface_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("panel_surface_ops_day_live"):
		var day: Dictionary = MapManager.panel_surface_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tooltip_chip_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tooltip_chip_ops_day_live"):
		var day: Dictionary = MapManager.tooltip_chip_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_insight_budget_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("insight_budget_ops_day_live"):
		var day: Dictionary = MapManager.insight_budget_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_order_surface_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_surface_ops_day_for_province"):
		var day: Dictionary = MapManager.order_surface_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_product_chip_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("product_chip_ops_day_for_province"):
		var day: Dictionary = MapManager.product_chip_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_surface_refresh_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("surface_refresh_ops_day_for_province"):
		var day: Dictionary = MapManager.surface_refresh_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_inspector_surface_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("inspector_surface_close_day_live"):
		var day: Dictionary = MapManager.inspector_surface_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_infra_invest_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("infra_invest_ops_day_live"):
		var day: Dictionary = MapManager.infra_invest_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_special_site_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("special_site_ops_day_live"):
		var day: Dictionary = MapManager.special_site_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_construction_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("construction_ops_day_for_province"):
		var day: Dictionary = MapManager.construction_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_infra_project_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("infra_project_ops_day_for_province"):
		var day: Dictionary = MapManager.infra_project_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_investment_status_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("investment_status_ops_day_for_province"):
		var day: Dictionary = MapManager.investment_status_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_infra_site_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("infra_site_joint_day_for_province"):
		var day: Dictionary = MapManager.infra_site_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_infra_invest_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("infra_invest_close_day_live"):
		var day: Dictionary = MapManager.infra_invest_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_auto_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_auto_ops_day_live"):
		var day: Dictionary = MapManager.daily_auto_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_tick_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_tick_ops_day_live"):
		var day: Dictionary = MapManager.theater_tick_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_domain_auto_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_domain_auto_ops_day_for_province"):
		var day: Dictionary = MapManager.multi_domain_auto_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_apply_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_apply_ops_day_live"):
		var day: Dictionary = MapManager.daily_apply_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_auto_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_auto_joint_day_for_province"):
		var day: Dictionary = MapManager.theater_auto_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_inspector_infra_auto_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("inspector_infra_auto_close_day_live"):
		var day: Dictionary = MapManager.inspector_infra_auto_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_follow_on_assault_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("follow_on_assault_ops_day_live"):
		var day: Dictionary = MapManager.follow_on_assault_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_reinforced_combat_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("reinforced_combat_ops_day_live"):
		var day: Dictionary = MapManager.reinforced_combat_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_path_urgency_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_path_urgency_ops_day_live"):
		var day: Dictionary = MapManager.war_path_urgency_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_follow_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_follow_ops_day_for_province"):
		var day: Dictionary = MapManager.assault_follow_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_reinforce_step_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("reinforce_step_ops_day_for_province"):
		var day: Dictionary = MapManager.reinforce_step_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_urgency_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_urgency_ops_day_for_province"):
		var day: Dictionary = MapManager.combat_urgency_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_follow_reinforce_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("follow_reinforce_close_day_live"):
		var day: Dictionary = MapManager.follow_reinforce_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_choke_sea_wx_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("choke_sea_wx_ops_day_live"):
		var day: Dictionary = MapManager.choke_sea_wx_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_sea_zone_mod_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sea_zone_mod_ops_day_for_province"):
		var day: Dictionary = MapManager.sea_zone_mod_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_choke_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_choke_ops_day_live"):
		var day: Dictionary = MapManager.basing_choke_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_choke_control_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("choke_control_ops_day_live"):
		var day: Dictionary = MapManager.choke_control_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_sea_zone_control_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sea_zone_control_ops_day_for_province"):
		var day: Dictionary = MapManager.sea_zone_control_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_choke_basing_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("choke_basing_joint_day_for_province"):
		var day: Dictionary = MapManager.choke_basing_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_choke_sea_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("choke_sea_close_day_live"):
		var day: Dictionary = MapManager.choke_sea_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_escalation_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_escalation_ops_day_live"):
		var day: Dictionary = MapManager.agent_escalation_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_coverage_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("coverage_ops_day_live"):
		var day: Dictionary = MapManager.coverage_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_counter_ops_board_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("counter_ops_board_ops_day_live"):
		var day: Dictionary = MapManager.counter_ops_board_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_escalation_ladder_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("escalation_ladder_ops_day_for_province"):
		var day: Dictionary = MapManager.escalation_ladder_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_coverage_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_coverage_joint_day_for_province"):
		var day: Dictionary = MapManager.agent_coverage_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_choke_agent_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_choke_agent_close_day_live"):
		var day: Dictionary = MapManager.assault_choke_agent_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_equip_horizon_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("equip_horizon_depth_day_live"):
		var day: Dictionary = MapManager.equip_horizon_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_stockpile_line_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("stockpile_line_ops_day_for_province"):
		var day: Dictionary = MapManager.stockpile_line_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_oob_line_continuity_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("oob_line_continuity_day_live"):
		var day: Dictionary = MapManager.oob_line_continuity_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_factory_oob_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("factory_oob_depth_day_for_province"):
		var day: Dictionary = MapManager.factory_oob_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_horizon_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_horizon_plan_day_live"):
		var day: Dictionary = MapManager.medium_horizon_plan_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_equip_stockpile_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("equip_stockpile_joint_day_for_province"):
		var day: Dictionary = MapManager.equip_stockpile_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_equip_oob_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("equip_oob_close_day_live"):
		var day: Dictionary = MapManager.equip_oob_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_multi_theater_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_multi_theater_ops_day_live"):
		var day: Dictionary = MapManager.fleet_multi_theater_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_redeploy_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_redeploy_ops_day_live"):
		var day: Dictionary = MapManager.fleet_redeploy_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_task_group_posture_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("task_group_posture_ops_day_for_province"):
		var day: Dictionary = MapManager.task_group_posture_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_posture_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_posture_ops_day_for_province"):
		var day: Dictionary = MapManager.fleet_posture_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_redeploy_route_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("redeploy_route_ops_day_for_province"):
		var day: Dictionary = MapManager.redeploy_route_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_theater_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_theater_joint_day_for_province"):
		var day: Dictionary = MapManager.fleet_theater_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_redeploy_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_redeploy_close_day_live"):
		var day: Dictionary = MapManager.fleet_redeploy_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_monthly_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_monthly_ops_day_live"):
		var day: Dictionary = MapManager.hh_monthly_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_quarterly_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_quarterly_ops_day_live"):
		var day: Dictionary = MapManager.hh_quarterly_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agenda_pulse_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agenda_pulse_ops_day_live"):
		var day: Dictionary = MapManager.agenda_pulse_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_trail_counterplay_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("trail_counterplay_ops_day_for_province"):
		var day: Dictionary = MapManager.trail_counterplay_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_agenda_depth_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_agenda_depth_joint_day_for_province"):
		var day: Dictionary = MapManager.hh_agenda_depth_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_oob_fleet_hh_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("oob_fleet_hh_close_day_live"):
		var day: Dictionary = MapManager.oob_fleet_hh_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_readiness_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_readiness_depth_day_live"):
		var day: Dictionary = MapManager.force_readiness_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_front_supply_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_supply_depth_day_live"):
		var day: Dictionary = MapManager.multi_front_supply_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_depot_route_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("depot_route_ops_day_for_province"):
		var day: Dictionary = MapManager.depot_route_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_posture_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_posture_depth_day_live"):
		var day: Dictionary = MapManager.force_posture_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_supply_rank_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_supply_rank_day_for_province"):
		var day: Dictionary = MapManager.front_supply_rank_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_supply_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_supply_joint_day_for_province"):
		var day: Dictionary = MapManager.force_supply_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_supply_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_supply_close_day_live"):
		var day: Dictionary = MapManager.force_supply_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_pressure_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_pressure_ops_day_live"):
		var day: Dictionary = MapManager.weather_pressure_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_crisis_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_crisis_ops_day_live"):
		var day: Dictionary = MapManager.campaign_crisis_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_prod_weather_crisis_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("prod_weather_crisis_day_for_province"):
		var day: Dictionary = MapManager.prod_weather_crisis_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_weather_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_weather_ops_day_for_province"):
		var day: Dictionary = MapManager.combat_weather_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_crisis_brief_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_brief_day_for_province"):
		var day: Dictionary = MapManager.weather_crisis_brief_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_campaign_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_campaign_joint_day_for_province"):
		var day: Dictionary = MapManager.weather_campaign_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_crisis_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_close_day_live"):
		var day: Dictionary = MapManager.weather_crisis_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_war_path_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_war_path_ops_day_live"):
		var day: Dictionary = MapManager.focus_war_path_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_strip_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_strip_depth_day_for_province"):
		var day: Dictionary = MapManager.strategic_strip_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_continuity_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_continuity_depth_day_live"):
		var day: Dictionary = MapManager.strategic_continuity_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_cabinet_pulse_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_cabinet_pulse_ops_day_live"):
		var day: Dictionary = MapManager.war_cabinet_pulse_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_continuity_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_continuity_joint_day_for_province"):
		var day: Dictionary = MapManager.focus_continuity_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_weather_focus_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_weather_focus_close_day_live"):
		var day: Dictionary = MapManager.force_weather_focus_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_sortie_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_sortie_depth_day_live"):
		var day: Dictionary = MapManager.air_sortie_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_land_joint_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_land_joint_depth_day_live"):
		var day: Dictionary = MapManager.air_land_joint_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_domain_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_domain_ops_day_live"):
		var day: Dictionary = MapManager.multi_domain_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_front_readiness_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_front_readiness_day_for_province"):
		var day: Dictionary = MapManager.air_front_readiness_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_domain_joint_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("domain_joint_ops_day_for_province"):
		var day: Dictionary = MapManager.domain_joint_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_land_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_land_campaign_day_for_province"):
		var day: Dictionary = MapManager.air_land_campaign_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_domain_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_domain_close_day_live"):
		var day: Dictionary = MapManager.air_domain_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_escort_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_escort_depth_day_live"):
		var day: Dictionary = MapManager.convoy_escort_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_sealane_health_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sealane_health_ops_day_live"):
		var day: Dictionary = MapManager.sealane_health_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_trade_pressure_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("trade_pressure_ops_day_for_province"):
		var day: Dictionary = MapManager.trade_pressure_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_sealane_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_sealane_joint_day_for_province"):
		var day: Dictionary = MapManager.convoy_sealane_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_sealane_logistics_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sealane_logistics_ops_day_for_province"):
		var day: Dictionary = MapManager.sealane_logistics_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_wartime_trade_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("wartime_trade_ops_day_for_province"):
		var day: Dictionary = MapManager.wartime_trade_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_sealane_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_sealane_close_day_live"):
		var day: Dictionary = MapManager.convoy_sealane_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_order_execute_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_execute_depth_day_live"):
		var day: Dictionary = MapManager.order_execute_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_map_effect_resolve_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("map_effect_resolve_day_live"):
		var day: Dictionary = MapManager.map_effect_resolve_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_next_day_feedback_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("next_day_feedback_depth_day_live"):
		var day: Dictionary = MapManager.next_day_feedback_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_order_effect_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_effect_joint_day_for_province"):
		var day: Dictionary = MapManager.order_effect_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_feedback_loop_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("feedback_loop_ops_day_for_province"):
		var day: Dictionary = MapManager.feedback_loop_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_convoy_order_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_convoy_order_close_day_live"):
		var day: Dictionary = MapManager.air_convoy_order_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_assign_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_assign_depth_day_live"):
		var day: Dictionary = MapManager.leader_assign_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_formation_ready_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("formation_ready_depth_day_live"):
		var day: Dictionary = MapManager.formation_ready_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_weather_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_weather_depth_day_for_province"):
		var day: Dictionary = MapManager.leader_weather_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_formation_station_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("formation_station_depth_day_for_province"):
		var day: Dictionary = MapManager.formation_station_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_formation_joint_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_formation_joint_depth_day_live"):
		var day: Dictionary = MapManager.leader_formation_joint_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_oob_leader_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("oob_leader_ops_day_for_province"):
		var day: Dictionary = MapManager.oob_leader_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_formation_close_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_formation_close_depth_day_live"):
		var day: Dictionary = MapManager.leader_formation_close_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_counter_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_counter_depth_day_live"):
		var day: Dictionary = MapManager.intel_counter_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_hh_counterplay_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_counterplay_depth_day_for_province"):
		var day: Dictionary = MapManager.hh_counterplay_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_response_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_response_depth_day_live"):
		var day: Dictionary = MapManager.agent_response_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_trail_intel_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("trail_intel_ops_day_for_province"):
		var day: Dictionary = MapManager.trail_intel_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_counterintel_board_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("counterintel_board_ops_day_for_province"):
		var day: Dictionary = MapManager.counterintel_board_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_response_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_response_joint_day_for_province"):
		var day: Dictionary = MapManager.intel_response_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_counter_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_counter_close_day_live"):
		var day: Dictionary = MapManager.intel_counter_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_daily_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_daily_depth_day_live"):
		var day: Dictionary = MapManager.theater_daily_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_province_rank_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_province_rank_depth_day_live"):
		var day: Dictionary = MapManager.multi_province_rank_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_auto_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_auto_depth_day_for_province"):
		var day: Dictionary = MapManager.daily_auto_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_brief_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_brief_ops_day_for_province"):
		var day: Dictionary = MapManager.theater_brief_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_province_command_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_province_command_day_live"):
		var day: Dictionary = MapManager.multi_province_command_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_intel_theater_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_intel_theater_close_day_live"):
		var day: Dictionary = MapManager.leader_intel_theater_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_slot_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_slot_depth_day_live"):
		var day: Dictionary = MapManager.save_slot_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_autosave_session_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("autosave_session_depth_day_for_province"):
		var day: Dictionary = MapManager.autosave_session_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_session_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_session_depth_day_live"):
		var day: Dictionary = MapManager.campaign_session_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_resume_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_resume_depth_day_for_province"):
		var day: Dictionary = MapManager.save_resume_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_session_checkpoint_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("session_checkpoint_depth_day_for_province"):
		var day: Dictionary = MapManager.session_checkpoint_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_audit_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_audit_depth_day_for_province"):
		var day: Dictionary = MapManager.save_audit_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_session_close_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_session_close_depth_day_live"):
		var day: Dictionary = MapManager.save_session_close_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_factory_risk_surge_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("factory_risk_surge_day_live"):
		var day: Dictionary = MapManager.factory_risk_surge_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_priority_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_priority_depth_day_live"):
		var day: Dictionary = MapManager.production_priority_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_stockpile_surge_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("stockpile_surge_ops_day_for_province"):
		var day: Dictionary = MapManager.stockpile_surge_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_line_continuity_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("line_continuity_depth_day_for_province"):
		var day: Dictionary = MapManager.line_continuity_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_industry_surge_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("industry_surge_joint_day_live"):
		var day: Dictionary = MapManager.industry_surge_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_oob_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_oob_depth_day_for_province"):
		var day: Dictionary = MapManager.production_oob_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_surge_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_surge_close_day_live"):
		var day: Dictionary = MapManager.production_surge_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_phase_estimate_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_phase_estimate_depth_day_live"):
		var day: Dictionary = MapManager.multi_phase_estimate_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_assault_ready_surface_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("assault_ready_surface_day_live"):
		var day: Dictionary = MapManager.assault_ready_surface_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_order_surface_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_order_surface_day_for_province"):
		var day: Dictionary = MapManager.combat_order_surface_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_phase_product_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("phase_product_ops_day_for_province"):
		var day: Dictionary = MapManager.phase_product_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_phase_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_phase_joint_day_live"):
		var day: Dictionary = MapManager.multi_phase_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_prod_combat_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_prod_combat_close_day_live"):
		var day: Dictionary = MapManager.save_prod_combat_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_basing_sustain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_basing_sustain_day_live"):
		var day: Dictionary = MapManager.naval_basing_sustain_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_port_fuel_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("port_fuel_depth_day_live"):
		var day: Dictionary = MapManager.port_fuel_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_basing_repair_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_repair_depth_day_for_province"):
		var day: Dictionary = MapManager.basing_repair_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_task_sustain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_task_sustain_day_live"):
		var day: Dictionary = MapManager.fleet_task_sustain_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_basing_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_basing_joint_day_for_province"):
		var day: Dictionary = MapManager.convoy_basing_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_logistics_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_logistics_depth_day_for_province"):
		var day: Dictionary = MapManager.naval_logistics_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_basing_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_basing_close_day_live"):
		var day: Dictionary = MapManager.naval_basing_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_day_theater_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_day_theater_depth_day_live"):
		var day: Dictionary = MapManager.multi_day_theater_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_campaign_continuity_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_campaign_continuity_day_live"):
		var day: Dictionary = MapManager.theater_campaign_continuity_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_day_chain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_day_chain_day_for_province"):
		var day: Dictionary = MapManager.campaign_day_chain_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_session_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_session_ops_day_for_province"):
		var day: Dictionary = MapManager.theater_session_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_daily_theater_sustain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("daily_theater_sustain_day_for_province"):
		var day: Dictionary = MapManager.daily_theater_sustain_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_continuity_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_continuity_joint_day_live"):
		var day: Dictionary = MapManager.theater_continuity_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_campaign_depth_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_campaign_depth_close_day_live"):
		var day: Dictionary = MapManager.theater_campaign_depth_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_inspector_decision_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("inspector_decision_depth_day_live"):
		var day: Dictionary = MapManager.inspector_decision_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_decision_strip_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("decision_strip_depth_day_live"):
		var day: Dictionary = MapManager.decision_strip_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_insight_strip_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("insight_strip_depth_day_for_province"):
		var day: Dictionary = MapManager.insight_strip_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_province_decision_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("province_decision_joint_day_live"):
		var day: Dictionary = MapManager.province_decision_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_inspector_campaign_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("inspector_campaign_ops_day_for_province"):
		var day: Dictionary = MapManager.inspector_campaign_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_naval_inspector_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_naval_inspector_close_day_live"):
		var day: Dictionary = MapManager.theater_naval_inspector_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_pressure_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_pressure_depth_day_live"):
		var day: Dictionary = MapManager.weather_pressure_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_foul_combat_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("foul_combat_ops_day_live"):
		var day: Dictionary = MapManager.foul_combat_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_logistics_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_logistics_depth_day_for_province"):
		var day: Dictionary = MapManager.weather_logistics_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_move_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_move_depth_day_for_province"):
		var day: Dictionary = MapManager.weather_move_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_crisis_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_depth_day_live"):
		var day: Dictionary = MapManager.weather_crisis_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_pressure_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_pressure_joint_day_for_province"):
		var day: Dictionary = MapManager.weather_pressure_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_ops_close_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_ops_close_depth_day_live"):
		var day: Dictionary = MapManager.weather_ops_close_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_trade_pressure_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("trade_pressure_depth_day_live"):
		var day: Dictionary = MapManager.trade_pressure_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_sealane_health_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("sealane_health_depth_day_for_province"):
		var day: Dictionary = MapManager.sealane_health_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_sustain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_sustain_day_live"):
		var day: Dictionary = MapManager.war_economy_sustain_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_stockpile_economy_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("stockpile_economy_depth_day_for_province"):
		var day: Dictionary = MapManager.stockpile_economy_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_economy_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_economy_joint_day_for_province"):
		var day: Dictionary = MapManager.convoy_economy_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_trade_sealane_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("trade_sealane_joint_day_live"):
		var day: Dictionary = MapManager.trade_sealane_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_close_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_close_depth_day_live"):
		var day: Dictionary = MapManager.war_economy_close_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_ready_surface_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_ready_surface_day_live"):
		var day: Dictionary = MapManager.force_ready_surface_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_formation_equip_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("formation_equip_depth_day_live"):
		var day: Dictionary = MapManager.formation_equip_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_reinforce_stockpile_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("reinforce_stockpile_depth_day_for_province"):
		var day: Dictionary = MapManager.reinforce_stockpile_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_readiness_board_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("readiness_board_ops_day_for_province"):
		var day: Dictionary = MapManager.readiness_board_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_reinforce_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_reinforce_joint_day_live"):
		var day: Dictionary = MapManager.force_reinforce_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_economy_force_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_economy_force_close_day_live"):
		var day: Dictionary = MapManager.weather_economy_force_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_phase_combat_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_phase_combat_product_for_province"):
		var day: Dictionary = MapManager.multi_phase_combat_product_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_fleet_multi_day_autonomy_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_multi_day_autonomy_product_for_province"):
		var day: Dictionary = MapManager.fleet_multi_day_autonomy_product_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_save_browser_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(GameData) != TYPE_NIL and GameData.has_method("save_browser_campaign_product_live"):
		var day: Dictionary = GameData.save_browser_campaign_product_live()
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_medium_tank_oob_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_tank_oob_product_for_province"):
		var day: Dictionary = MapManager.medium_tank_oob_product_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_hh_multi_month_agenda_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("hh_multi_month_agenda_product_live"):
		var day: Dictionary = MapManager.hh_multi_month_agenda_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_agent_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_campaign_product_live"):
		var day: Dictionary = MapManager.agent_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_inspector_decision_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("inspector_decision_product_live"):
		var day: Dictionary = MapManager.inspector_decision_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_theater_command_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_command_product_live"):
		var day: Dictionary = MapManager.theater_command_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_multi_faction_strategic_ai_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_faction_strategic_ai_product_live"):
		var day: Dictionary = MapManager.multi_faction_strategic_ai_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_strategic_ai_daily_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_daily_campaign_product_live"):
		var day: Dictionary = MapManager.strategic_ai_daily_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_designer_suite_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_suite_product_live"):
		var day: Dictionary = MapManager.designer_suite_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_ai_doctrine_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_doctrine_depth_day_live"):
		var day: Dictionary = MapManager.strategic_ai_doctrine_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_ai_urgency_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_urgency_board_day_live"):
		var day: Dictionary = MapManager.strategic_ai_urgency_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_ai_player_skip_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_player_skip_day_for_province"):
		var day: Dictionary = MapManager.strategic_ai_player_skip_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_ai_budget_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_budget_depth_day_live"):
		var day: Dictionary = MapManager.strategic_ai_budget_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_ai_domain_weight_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_domain_weight_day_for_province"):
		var day: Dictionary = MapManager.strategic_ai_domain_weight_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_ai_daily_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_daily_joint_day_for_province"):
		var day: Dictionary = MapManager.strategic_ai_daily_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_ai_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_campaign_close_day_live"):
		var day: Dictionary = MapManager.strategic_ai_campaign_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_catalog_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_catalog_depth_day_live"):
		var day: Dictionary = MapManager.designer_catalog_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_seed_production_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_seed_production_day_live"):
		var day: Dictionary = MapManager.designer_seed_production_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_domain_balance_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_domain_balance_day_for_province"):
		var day: Dictionary = MapManager.designer_domain_balance_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_oob_horizon_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("oob_horizon_joint_day_live"):
		var day: Dictionary = MapManager.oob_horizon_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_production_line_bootstrap_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("production_line_bootstrap_day_for_province"):
		var day: Dictionary = MapManager.production_line_bootstrap_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_industry_design_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("industry_design_joint_day_for_province"):
		var day: Dictionary = MapManager.industry_design_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_industry_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_industry_close_day_live"):
		var day: Dictionary = MapManager.designer_industry_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_ai_command_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_ai_command_joint_day_live"):
		var day: Dictionary = MapManager.theater_ai_command_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_fleet_ai_campaign_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("fleet_ai_campaign_depth_day_live"):
		var day: Dictionary = MapManager.fleet_ai_campaign_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_agent_ai_campaign_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("agent_ai_campaign_depth_day_live"):
		var day: Dictionary = MapManager.agent_ai_campaign_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_combat_ai_phase_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("combat_ai_phase_depth_day_live"):
		var day: Dictionary = MapManager.combat_ai_phase_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_save_session_ai_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_session_ai_joint_day_for_province"):
		var day: Dictionary = MapManager.save_session_ai_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_full_game_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("full_game_campaign_close_day_live"):
		var day: Dictionary = MapManager.full_game_campaign_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_ops_sortie_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_ops_sortie_depth_day_live"):
		var day: Dictionary = MapManager.air_ops_sortie_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_forecast_planning_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_forecast_planning_depth_day_live"):
		var day: Dictionary = MapManager.air_forecast_planning_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_sortie_weather_gate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_sortie_weather_gate_day_for_province"):
		var day: Dictionary = MapManager.air_sortie_weather_gate_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_convoy_escort_campaign_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("convoy_escort_campaign_depth_day_live"):
		var day: Dictionary = MapManager.convoy_escort_campaign_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_land_campaign_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_land_campaign_depth_day_live"):
		var day: Dictionary = MapManager.air_land_campaign_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_front_readiness_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_front_readiness_depth_day_for_province"):
		var day: Dictionary = MapManager.air_front_readiness_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_air_convoy_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_convoy_campaign_close_day_live"):
		var day: Dictionary = MapManager.air_convoy_campaign_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_pick_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_pick_depth_day_live"):
		var day: Dictionary = MapManager.focus_pick_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_order_path_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_order_path_day_live"):
		var day: Dictionary = MapManager.focus_order_path_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_war_path_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_war_path_depth_day_live"):
		var day: Dictionary = MapManager.focus_war_path_depth_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_path_urgency_depth_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_path_urgency_depth_day_for_province"):
		var day: Dictionary = MapManager.war_path_urgency_depth_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_counter_depth_campaign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_counter_depth_campaign_day_for_province"):
		var day: Dictionary = MapManager.intel_counter_depth_campaign_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_campaign_assign_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_campaign_assign_day_for_province"):
		var day: Dictionary = MapManager.leader_campaign_assign_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_intel_leader_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_intel_leader_close_day_live"):
		var day: Dictionary = MapManager.focus_intel_leader_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_order_execute_session_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("order_execute_session_day_live"):
		var day: Dictionary = MapManager.order_execute_session_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_next_day_feedback_session_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("next_day_feedback_session_day_for_province"):
		var day: Dictionary = MapManager.next_day_feedback_session_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_decision_session_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_decision_session_day_live"):
		var day: Dictionary = MapManager.campaign_decision_session_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_theater_ai_session_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("theater_ai_session_joint_day_live"):
		var day: Dictionary = MapManager.theater_ai_session_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_force_readiness_session_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_readiness_session_day_for_province"):
		var day: Dictionary = MapManager.force_readiness_session_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_play_session_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("play_session_campaign_close_day_live"):
		var day: Dictionary = MapManager.play_session_campaign_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_play_session_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("play_session_campaign_product_live"):
		var day: Dictionary = MapManager.play_session_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_air_ops_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_ops_campaign_product_live"):
		var day: Dictionary = MapManager.air_ops_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_war_path_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_war_path_product_live"):
		var day: Dictionary = MapManager.focus_war_path_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_multi_phase_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_multi_phase_campaign_product_live"):
		var day: Dictionary = MapManager.naval_multi_phase_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_pick_board_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_pick_board_advanced_day_live"):
		var day: Dictionary = MapManager.focus_pick_board_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_war_path_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_war_path_advanced_day_live"):
		var day: Dictionary = MapManager.focus_war_path_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_commit_execute_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_commit_execute_advanced_day_live"):
		var day: Dictionary = MapManager.focus_commit_execute_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_naval_effort_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_naval_effort_advanced_day_live"):
		var day: Dictionary = MapManager.focus_naval_effort_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_industry_army_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_industry_army_joint_day_live"):
		var day: Dictionary = MapManager.focus_industry_army_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_air_effort_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_air_effort_joint_day_live"):
		var day: Dictionary = MapManager.focus_air_effort_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_focus_war_path_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_war_path_close_day_live"):
		var day: Dictionary = MapManager.focus_war_path_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_posture_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_posture_advanced_day_live"):
		var day: Dictionary = MapManager.naval_posture_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_escort_phase_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_escort_phase_advanced_day_live"):
		var day: Dictionary = MapManager.naval_escort_phase_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_strike_phase_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_strike_phase_advanced_day_live"):
		var day: Dictionary = MapManager.naval_strike_phase_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_fleet_fuel_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_fleet_fuel_advanced_day_live"):
		var day: Dictionary = MapManager.naval_fleet_fuel_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_fleet_autonomy_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_fleet_autonomy_joint_day_live"):
		var day: Dictionary = MapManager.naval_fleet_autonomy_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_air_joint_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_air_joint_advanced_day_for_province"):
		var day: Dictionary = MapManager.naval_air_joint_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_naval_multi_phase_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_multi_phase_close_day_for_province"):
		var day: Dictionary = MapManager.naval_multi_phase_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_domain_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_domain_advanced_day_for_province"):
		var day: Dictionary = MapManager.designer_domain_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_seed_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_seed_advanced_day_for_province"):
		var day: Dictionary = MapManager.designer_seed_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_ai_multi_day_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_ai_multi_day_advanced_day_for_province"):
		var day: Dictionary = MapManager.strategic_ai_multi_day_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_ai_industry_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_ai_industry_joint_day_for_province"):
		var day: Dictionary = MapManager.designer_ai_industry_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_play_session_advanced_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("play_session_advanced_joint_day_for_province"):
		var day: Dictionary = MapManager.play_session_advanced_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_advanced_deferred_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("advanced_deferred_campaign_close_day_for_province"):
		var day: Dictionary = MapManager.advanced_deferred_campaign_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_peace_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_peace_campaign_product_live"):
		var day: Dictionary = MapManager.diplomacy_peace_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tech_research_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_research_campaign_product_live"):
		var day: Dictionary = MapManager.tech_research_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_board_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_board_advanced_day_live"):
		var day: Dictionary = MapManager.diplomacy_board_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_leverage_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_leverage_advanced_day_live"):
		var day: Dictionary = MapManager.diplomacy_leverage_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_settle_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_settle_advanced_day_live"):
		var day: Dictionary = MapManager.diplomacy_settle_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_trade_pressure_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_trade_pressure_day_live"):
		var day: Dictionary = MapManager.diplomacy_trade_pressure_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_agent_hh_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_agent_hh_joint_day_live"):
		var day: Dictionary = MapManager.diplomacy_agent_hh_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_focus_peace_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_focus_peace_joint_day_live"):
		var day: Dictionary = MapManager.diplomacy_focus_peace_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_peace_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_peace_close_day_live"):
		var day: Dictionary = MapManager.diplomacy_peace_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tech_catalog_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_catalog_advanced_day_live"):
		var day: Dictionary = MapManager.tech_catalog_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tech_priority_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_priority_advanced_day_live"):
		var day: Dictionary = MapManager.tech_priority_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tech_field_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_field_advanced_day_live"):
		var day: Dictionary = MapManager.tech_field_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tech_designer_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_designer_joint_day_live"):
		var day: Dictionary = MapManager.tech_designer_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tech_oob_fielding_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_oob_fielding_joint_day_live"):
		var day: Dictionary = MapManager.tech_oob_fielding_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tech_industry_focus_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_industry_focus_joint_day_for_province"):
		var day: Dictionary = MapManager.tech_industry_focus_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tech_research_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_research_close_day_for_province"):
		var day: Dictionary = MapManager.tech_research_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_tech_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_tech_joint_day_for_province"):
		var day: Dictionary = MapManager.diplomacy_tech_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_tech_ai_research_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_ai_research_joint_day_for_province"):
		var day: Dictionary = MapManager.tech_ai_research_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_naval_air_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_naval_air_joint_day_for_province"):
		var day: Dictionary = MapManager.diplomacy_naval_air_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_session_diplomacy_tech_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("session_diplomacy_tech_joint_day_for_province"):
		var day: Dictionary = MapManager.session_diplomacy_tech_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_faction_diplo_tech_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_faction_diplo_tech_day_for_province"):
		var day: Dictionary = MapManager.multi_faction_diplo_tech_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_diplomacy_tech_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("diplomacy_tech_campaign_close_day_for_province"):
		var day: Dictionary = MapManager.diplomacy_tech_campaign_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_logistics_supply_theater_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_supply_theater_product_live"):
		var day: Dictionary = MapManager.logistics_supply_theater_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intelligence_network_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intelligence_network_product_live"):
		var day: Dictionary = MapManager.intelligence_network_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_world_class_campaign_command_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_campaign_command_product_live"):
		var day: Dictionary = MapManager.world_class_campaign_command_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_logistics_route_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_route_advanced_day_live"):
		var day: Dictionary = MapManager.logistics_route_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_logistics_sustain_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_sustain_advanced_day_live"):
		var day: Dictionary = MapManager.logistics_sustain_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_logistics_readiness_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_readiness_advanced_day_live"):
		var day: Dictionary = MapManager.logistics_readiness_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_logistics_naval_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_naval_joint_day_live"):
		var day: Dictionary = MapManager.logistics_naval_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_logistics_tech_industry_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_tech_industry_joint_day_live"):
		var day: Dictionary = MapManager.logistics_tech_industry_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_logistics_supply_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("logistics_supply_close_day_live"):
		var day: Dictionary = MapManager.logistics_supply_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_coverage_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_coverage_advanced_day_live"):
		var day: Dictionary = MapManager.intel_coverage_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_counterintel_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_counterintel_advanced_day_live"):
		var day: Dictionary = MapManager.intel_counterintel_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_counterplay_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_counterplay_advanced_day_live"):
		var day: Dictionary = MapManager.intel_counterplay_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_diplomacy_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_diplomacy_joint_day_live"):
		var day: Dictionary = MapManager.intel_diplomacy_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_session_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_session_joint_day_live"):
		var day: Dictionary = MapManager.intel_session_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intelligence_network_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intelligence_network_close_day_live"):
		var day: Dictionary = MapManager.intelligence_network_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_world_class_scan_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_scan_advanced_day_for_province"):
		var day: Dictionary = MapManager.world_class_scan_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_world_class_rank_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_rank_advanced_day_for_province"):
		var day: Dictionary = MapManager.world_class_rank_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_world_class_execute_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_execute_advanced_day_for_province"):
		var day: Dictionary = MapManager.world_class_execute_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_world_class_logistics_intel_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_logistics_intel_joint_day_for_province"):
		var day: Dictionary = MapManager.world_class_logistics_intel_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_world_class_air_naval_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_air_naval_joint_day_for_province"):
		var day: Dictionary = MapManager.world_class_air_naval_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_world_class_session_ai_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_session_ai_joint_day_for_province"):
		var day: Dictionary = MapManager.world_class_session_ai_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_world_class_theater_command_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_theater_command_joint_day_for_province"):
		var day: Dictionary = MapManager.world_class_theater_command_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_world_class_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("world_class_campaign_close_day_for_province"):
		var day: Dictionary = MapManager.world_class_campaign_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_mobilization_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_mobilization_product_live"):
		var day: Dictionary = MapManager.war_economy_mobilization_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_theater_ops_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_theater_ops_product_live"):
		var day: Dictionary = MapManager.weather_theater_ops_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_continuity_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_continuity_campaign_product_live"):
		var day: Dictionary = MapManager.front_continuity_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_board_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_board_advanced_day_live"):
		var day: Dictionary = MapManager.war_economy_board_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_allocate_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_allocate_advanced_day_live"):
		var day: Dictionary = MapManager.war_economy_allocate_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_sustain_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_sustain_advanced_day_live"):
		var day: Dictionary = MapManager.war_economy_sustain_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_logistics_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_logistics_joint_day_live"):
		var day: Dictionary = MapManager.war_economy_logistics_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_tech_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_tech_joint_day_live"):
		var day: Dictionary = MapManager.war_economy_tech_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_economy_mobilization_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_mobilization_close_day_live"):
		var day: Dictionary = MapManager.war_economy_mobilization_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_pressure_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_pressure_advanced_day_live"):
		var day: Dictionary = MapManager.weather_pressure_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_gate_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_gate_advanced_day_live"):
		var day: Dictionary = MapManager.weather_gate_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_crisis_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_advanced_day_live"):
		var day: Dictionary = MapManager.weather_crisis_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_front_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_front_joint_day_live"):
		var day: Dictionary = MapManager.weather_front_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_economy_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_economy_joint_day_live"):
		var day: Dictionary = MapManager.weather_economy_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_theater_ops_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_theater_ops_close_day_live"):
		var day: Dictionary = MapManager.weather_theater_ops_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_combat_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_combat_advanced_day_for_province"):
		var day: Dictionary = MapManager.front_combat_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_assault_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_assault_advanced_day_for_province"):
		var day: Dictionary = MapManager.front_assault_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_sustain_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_sustain_advanced_day_for_province"):
		var day: Dictionary = MapManager.front_sustain_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_weather_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_weather_joint_day_for_province"):
		var day: Dictionary = MapManager.front_weather_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_economy_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_economy_joint_day_for_province"):
		var day: Dictionary = MapManager.front_economy_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_logistics_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_logistics_joint_day_for_province"):
		var day: Dictionary = MapManager.front_logistics_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_theater_command_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_theater_command_joint_day_for_province"):
		var day: Dictionary = MapManager.front_theater_command_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_front_continuity_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("front_continuity_campaign_close_day_for_province"):
		var day: Dictionary = MapManager.front_continuity_campaign_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_control_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_control_product_live"):
		var day: Dictionary = MapManager.occupation_control_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_reinforcement_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_reinforcement_product_live"):
		var day: Dictionary = MapManager.manpower_reinforcement_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_command_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_command_product_live"):
		var day: Dictionary = MapManager.leader_command_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_control_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_control_advanced_day_live"):
		var day: Dictionary = MapManager.occupation_control_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_garrison_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_garrison_advanced_day_live"):
		var day: Dictionary = MapManager.occupation_garrison_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_integrate_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_integrate_advanced_day_live"):
		var day: Dictionary = MapManager.occupation_integrate_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_front_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_front_joint_day_live"):
		var day: Dictionary = MapManager.occupation_front_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_economy_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_economy_joint_day_live"):
		var day: Dictionary = MapManager.occupation_economy_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_control_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_control_close_day_live"):
		var day: Dictionary = MapManager.occupation_control_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_draft_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_draft_advanced_day_live"):
		var day: Dictionary = MapManager.manpower_draft_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_reinforce_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_reinforce_advanced_day_live"):
		var day: Dictionary = MapManager.manpower_reinforce_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_field_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_field_advanced_day_live"):
		var day: Dictionary = MapManager.manpower_field_advanced_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_front_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_front_joint_day_live"):
		var day: Dictionary = MapManager.manpower_front_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_economy_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_economy_joint_day_live"):
		var day: Dictionary = MapManager.manpower_economy_joint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_reinforcement_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_reinforcement_close_day_live"):
		var day: Dictionary = MapManager.manpower_reinforcement_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_assign_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_assign_advanced_day_for_province"):
		var day: Dictionary = MapManager.leader_assign_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_station_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_station_advanced_day_for_province"):
		var day: Dictionary = MapManager.leader_station_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_ops_advanced_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_ops_advanced_day_for_province"):
		var day: Dictionary = MapManager.leader_ops_advanced_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_occupation_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_occupation_joint_day_for_province"):
		var day: Dictionary = MapManager.leader_occupation_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_manpower_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_manpower_joint_day_for_province"):
		var day: Dictionary = MapManager.leader_manpower_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_intel_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_intel_joint_day_for_province"):
		var day: Dictionary = MapManager.leader_intel_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_theater_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_theater_joint_day_for_province"):
		var day: Dictionary = MapManager.leader_theater_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_manpower_leader_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_manpower_leader_close_day_for_province"):
		var day: Dictionary = MapManager.occupation_manpower_leader_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_tank_production_honesty_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_tank_production_honesty_product_live"):
		var day: Dictionary = MapManager.medium_tank_production_honesty_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_honesty_60d_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_honesty_60d_day_live"):
		var day: Dictionary = MapManager.medium_honesty_60d_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_honesty_80d_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_honesty_80d_day_live"):
		var day: Dictionary = MapManager.medium_honesty_80d_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_honesty_100d_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_honesty_100d_day_live"):
		var day: Dictionary = MapManager.medium_honesty_100d_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_honesty_unit_stats_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_honesty_unit_stats_day_live"):
		var day: Dictionary = MapManager.medium_honesty_unit_stats_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_honesty_factory_risk_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_honesty_factory_risk_day_live"):
		var day: Dictionary = MapManager.medium_honesty_factory_risk_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_honesty_stockpile_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_honesty_stockpile_day_live"):
		var day: Dictionary = MapManager.medium_honesty_stockpile_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_honesty_readiness_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_honesty_readiness_joint_day_for_province"):
		var day: Dictionary = MapManager.medium_honesty_readiness_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_honesty_manpower_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_honesty_manpower_joint_day_for_province"):
		var day: Dictionary = MapManager.medium_honesty_manpower_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_honesty_economy_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_honesty_economy_joint_day_for_province"):
		var day: Dictionary = MapManager.medium_honesty_economy_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_medium_tank_production_honesty_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_tank_production_honesty_close_day_for_province"):
		var day: Dictionary = MapManager.medium_tank_production_honesty_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_live_managers_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_live_managers_product_live"):
		var day: Dictionary = MapManager.apply_queue_live_managers_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_audit_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_audit_day_live"):
		var day: Dictionary = MapManager.apply_queue_audit_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_production_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_production_live_day_live"):
		var day: Dictionary = MapManager.apply_queue_production_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_combat_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_combat_live_day_live"):
		var day: Dictionary = MapManager.apply_queue_combat_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_supply_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_supply_live_day_live"):
		var day: Dictionary = MapManager.apply_queue_supply_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_focus_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_focus_live_day_live"):
		var day: Dictionary = MapManager.apply_queue_focus_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_agent_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_agent_live_day_live"):
		var day: Dictionary = MapManager.apply_queue_agent_live_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_station_live_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_station_live_day_for_province"):
		var day: Dictionary = MapManager.apply_queue_station_live_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_six_leaf_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_six_leaf_joint_day_for_province"):
		var day: Dictionary = MapManager.apply_queue_six_leaf_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_honesty_joint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_honesty_joint_day_for_province"):
		var day: Dictionary = MapManager.apply_queue_honesty_joint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_apply_queue_live_managers_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_queue_live_managers_close_day_for_province"):
		var day: Dictionary = MapManager.apply_queue_live_managers_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_resistance_compliance_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_resistance_compliance_product_live"):
		var day: Dictionary = MapManager.occupation_resistance_compliance_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_laws_training_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_laws_training_product_live"):
		var day: Dictionary = MapManager.manpower_laws_training_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_peace_conference_settlement_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("peace_conference_settlement_product_live"):
		var day: Dictionary = MapManager.peace_conference_settlement_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_resistance_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_resistance_board_day_live"):
		var day: Dictionary = MapManager.occupation_resistance_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_resistance_policy_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_resistance_policy_day_live"):
		var day: Dictionary = MapManager.occupation_resistance_policy_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_resistance_tick_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_resistance_tick_day_live"):
		var day: Dictionary = MapManager.occupation_resistance_tick_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_resistance_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_resistance_close_day_live"):
		var day: Dictionary = MapManager.occupation_resistance_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_law_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_law_board_day_live"):
		var day: Dictionary = MapManager.manpower_law_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_train_pipeline_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_train_pipeline_day_live"):
		var day: Dictionary = MapManager.manpower_train_pipeline_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_field_trained_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_field_trained_day_live"):
		var day: Dictionary = MapManager.manpower_field_trained_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_laws_training_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_laws_training_close_day_live"):
		var day: Dictionary = MapManager.manpower_laws_training_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_peace_conference_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("peace_conference_board_day_for_province"):
		var day: Dictionary = MapManager.peace_conference_board_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_peace_conference_demands_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("peace_conference_demands_day_for_province"):
		var day: Dictionary = MapManager.peace_conference_demands_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_peace_conference_settle_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("peace_conference_settle_day_for_province"):
		var day: Dictionary = MapManager.peace_conference_settle_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_peace_conference_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("peace_conference_campaign_close_day_for_province"):
		var day: Dictionary = MapManager.peace_conference_campaign_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_product_ux_command_polish_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("product_ux_command_polish_product_live"):
		var day: Dictionary = MapManager.product_ux_command_polish_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_domain_live_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_domain_live_product_live"):
		var day: Dictionary = MapManager.designer_domain_live_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_ai_multi_month_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_ai_multi_month_product_live"):
		var day: Dictionary = MapManager.campaign_ai_multi_month_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_product_ux_compact_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("product_ux_compact_day_live"):
		var day: Dictionary = MapManager.product_ux_compact_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_product_ux_chips_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("product_ux_chips_day_live"):
		var day: Dictionary = MapManager.product_ux_chips_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_product_ux_hotkeys_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("product_ux_hotkeys_day_live"):
		var day: Dictionary = MapManager.product_ux_hotkeys_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_product_ux_polish_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("product_ux_polish_close_day_live"):
		var day: Dictionary = MapManager.product_ux_polish_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_domain_catalog_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_domain_catalog_day_live"):
		var day: Dictionary = MapManager.designer_domain_catalog_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_domain_pick_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_domain_pick_day_live"):
		var day: Dictionary = MapManager.designer_domain_pick_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_domain_seed_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_domain_seed_day_live"):
		var day: Dictionary = MapManager.designer_domain_seed_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_domain_live_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_domain_live_close_day_live"):
		var day: Dictionary = MapManager.designer_domain_live_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_ai_month_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_ai_month_board_day_for_province"):
		var day: Dictionary = MapManager.campaign_ai_month_board_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_ai_weekly_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_ai_weekly_plan_day_for_province"):
		var day: Dictionary = MapManager.campaign_ai_weekly_plan_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_ai_theater_execute_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_ai_theater_execute_day_for_province"):
		var day: Dictionary = MapManager.campaign_ai_theater_execute_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_ai_multi_month_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_ai_multi_month_close_day_for_province"):
		var day: Dictionary = MapManager.campaign_ai_multi_month_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_revolt_garrison_product_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_revolt_garrison_product_live"):
		var day: Dictionary = MapManager.occupation_revolt_garrison_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_cohort_reserve_product_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_cohort_reserve_product_live"):
		var day: Dictionary = MapManager.manpower_cohort_reserve_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_party_peace_conference_product_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_party_peace_conference_product_live"):
		var day: Dictionary = MapManager.multi_party_peace_conference_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_revolt_board_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_revolt_board_day_live"):
		var day: Dictionary = MapManager.occupation_revolt_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_revolt_garrison_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_revolt_garrison_day_live"):
		var day: Dictionary = MapManager.occupation_revolt_garrison_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_revolt_suppress_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_revolt_suppress_day_live"):
		var day: Dictionary = MapManager.occupation_revolt_suppress_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_revolt_garrison_close_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_revolt_garrison_close_day_live"):
		var day: Dictionary = MapManager.occupation_revolt_garrison_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_cohort_board_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_cohort_board_day_live"):
		var day: Dictionary = MapManager.manpower_cohort_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_cohort_reserve_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_cohort_reserve_day_live"):
		var day: Dictionary = MapManager.manpower_cohort_reserve_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_cohort_mobilize_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_cohort_mobilize_day_live"):
		var day: Dictionary = MapManager.manpower_cohort_mobilize_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_manpower_cohort_reserve_close_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("manpower_cohort_reserve_close_day_live"):
		var day: Dictionary = MapManager.manpower_cohort_reserve_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_party_peace_board_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_party_peace_board_day_for_province"):
		var day: Dictionary = MapManager.multi_party_peace_board_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_party_peace_wargoals_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_party_peace_wargoals_day_for_province"):
		var day: Dictionary = MapManager.multi_party_peace_wargoals_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_party_peace_settle_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_party_peace_settle_day_for_province"):
		var day: Dictionary = MapManager.multi_party_peace_settle_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_party_peace_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_party_peace_campaign_close_day_for_province"):
		var day: Dictionary = MapManager.multi_party_peace_campaign_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_historical_oob_content_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("historical_oob_content_product_live"):
		var day: Dictionary = MapManager.historical_oob_content_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tech_tree_branching_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_tree_branching_product_live"):
		var day: Dictionary = MapManager.tech_tree_branching_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_save_resume_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_resume_campaign_product_live"):
		var day: Dictionary = MapManager.save_resume_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_historical_oob_catalog_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("historical_oob_catalog_day_live"):
		var day: Dictionary = MapManager.historical_oob_catalog_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_historical_oob_seed_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("historical_oob_seed_day_live"):
		var day: Dictionary = MapManager.historical_oob_seed_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_historical_oob_equip_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("historical_oob_equip_day_live"):
		var day: Dictionary = MapManager.historical_oob_equip_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_historical_oob_content_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("historical_oob_content_close_day_live"):
		var day: Dictionary = MapManager.historical_oob_content_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tech_tree_branches_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_tree_branches_day_live"):
		var day: Dictionary = MapManager.tech_tree_branches_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tech_tree_path_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_tree_path_day_live"):
		var day: Dictionary = MapManager.tech_tree_path_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tech_tree_field_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_tree_field_day_live"):
		var day: Dictionary = MapManager.tech_tree_field_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tech_tree_branching_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tech_tree_branching_close_day_live"):
		var day: Dictionary = MapManager.tech_tree_branching_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_save_resume_checkpoint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_resume_checkpoint_day_for_province"):
		var day: Dictionary = MapManager.save_resume_checkpoint_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_save_resume_save_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_resume_save_day_for_province"):
		var day: Dictionary = MapManager.save_resume_save_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_save_resume_resume_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_resume_resume_day_for_province"):
		var day: Dictionary = MapManager.save_resume_resume_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_save_resume_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("save_resume_campaign_close_day_for_province"):
		var day: Dictionary = MapManager.save_resume_campaign_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tutorial_first_session_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tutorial_first_session_product_live"):
		var day: Dictionary = MapManager.tutorial_first_session_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_focus_tree_content_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_tree_content_product_live"):
		var day: Dictionary = MapManager.focus_tree_content_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_balance_combat_supply_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("balance_combat_supply_product_live"):
		var day: Dictionary = MapManager.balance_combat_supply_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tutorial_session_brief_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tutorial_session_brief_day_live"):
		var day: Dictionary = MapManager.tutorial_session_brief_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tutorial_session_guide_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tutorial_session_guide_day_live"):
		var day: Dictionary = MapManager.tutorial_session_guide_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tutorial_session_checkpoint_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tutorial_session_checkpoint_day_live"):
		var day: Dictionary = MapManager.tutorial_session_checkpoint_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_tutorial_first_session_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("tutorial_first_session_close_day_live"):
		var day: Dictionary = MapManager.tutorial_first_session_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_focus_tree_catalog_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_tree_catalog_day_live"):
		var day: Dictionary = MapManager.focus_tree_catalog_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_focus_tree_path_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_tree_path_day_live"):
		var day: Dictionary = MapManager.focus_tree_path_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_focus_tree_commit_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_tree_commit_day_live"):
		var day: Dictionary = MapManager.focus_tree_commit_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_focus_tree_content_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("focus_tree_content_close_day_live"):
		var day: Dictionary = MapManager.focus_tree_content_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_balance_estimate_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("balance_estimate_board_day_for_province"):
		var day: Dictionary = MapManager.balance_estimate_board_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_balance_live_sample_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("balance_live_sample_day_for_province"):
		var day: Dictionary = MapManager.balance_live_sample_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_balance_variance_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("balance_variance_close_day_for_province"):
		var day: Dictionary = MapManager.balance_variance_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_balance_combat_supply_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("balance_combat_supply_close_day_for_province"):
		var day: Dictionary = MapManager.balance_combat_supply_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_air_multi_phase_theater_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_multi_phase_theater_product_live"):
		var day: Dictionary = MapManager.air_multi_phase_theater_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_naval_search_strike_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_search_strike_product_live"):
		var day: Dictionary = MapManager.naval_search_strike_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_war_economy_conversion_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_conversion_product_live"):
		var day: Dictionary = MapManager.war_economy_conversion_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_air_theater_recon_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_theater_recon_day_live"):
		var day: Dictionary = MapManager.air_theater_recon_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_air_theater_cas_gate_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_theater_cas_gate_day_live"):
		var day: Dictionary = MapManager.air_theater_cas_gate_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_air_theater_interdiction_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_theater_interdiction_day_live"):
		var day: Dictionary = MapManager.air_theater_interdiction_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_air_multi_phase_theater_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("air_multi_phase_theater_close_day_live"):
		var day: Dictionary = MapManager.air_multi_phase_theater_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_naval_search_patrol_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_search_patrol_day_live"):
		var day: Dictionary = MapManager.naval_search_patrol_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_naval_asw_escort_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_asw_escort_day_live"):
		var day: Dictionary = MapManager.naval_asw_escort_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_naval_carrier_strike_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_carrier_strike_day_live"):
		var day: Dictionary = MapManager.naval_carrier_strike_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_naval_search_strike_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("naval_search_strike_close_day_live"):
		var day: Dictionary = MapManager.naval_search_strike_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_economy_civ_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("economy_civ_board_day_for_province"):
		var day: Dictionary = MapManager.economy_civ_board_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_economy_war_convert_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("economy_war_convert_day_for_province"):
		var day: Dictionary = MapManager.economy_war_convert_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_economy_stockpile_sustain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("economy_stockpile_sustain_day_for_province"):
		var day: Dictionary = MapManager.economy_stockpile_sustain_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""


static func build_war_economy_conversion_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_economy_conversion_close_day_for_province"):
		var day: Dictionary = MapManager.war_economy_conversion_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_module_editor_product_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_module_editor_product_live"):
		var day: Dictionary = MapManager.designer_module_editor_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_stats_field_product_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_stats_field_product_live"):
		var day: Dictionary = MapManager.designer_stats_field_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_multi_domain_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_multi_domain_campaign_product_live"):
		var day: Dictionary = MapManager.designer_multi_domain_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_module_board_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_module_board_day_live"):
		var day: Dictionary = MapManager.designer_module_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_module_edit_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_module_edit_day_live"):
		var day: Dictionary = MapManager.designer_module_edit_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_reliability_gate_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_reliability_gate_day_live"):
		var day: Dictionary = MapManager.designer_reliability_gate_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_module_editor_close_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_module_editor_close_day_live"):
		var day: Dictionary = MapManager.designer_module_editor_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_stats_board_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_stats_board_day_live"):
		var day: Dictionary = MapManager.designer_stats_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_freeze_design_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_freeze_design_day_live"):
		var day: Dictionary = MapManager.designer_freeze_design_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_field_seed_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_field_seed_day_live"):
		var day: Dictionary = MapManager.designer_field_seed_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_stats_field_close_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_stats_field_close_day_live"):
		var day: Dictionary = MapManager.designer_stats_field_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_catalog_all_domains_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_catalog_all_domains_day_for_province"):
		var day: Dictionary = MapManager.designer_catalog_all_domains_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_seed_multi_domain_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_seed_multi_domain_day_for_province"):
		var day: Dictionary = MapManager.designer_seed_multi_domain_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_equip_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_equip_campaign_close_day_for_province"):
		var day: Dictionary = MapManager.designer_equip_campaign_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_designer_multi_domain_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null: return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("designer_multi_domain_campaign_close_day_for_province"):
		var day: Dictionary = MapManager.designer_multi_domain_campaign_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_crisis_campaign_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_campaign_product_live"):
		var day: Dictionary = MapManager.weather_crisis_campaign_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_cell_network_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_cell_network_product_live"):
		var day: Dictionary = MapManager.intel_cell_network_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_theater_command_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_theater_command_product_live"):
		var day: Dictionary = MapManager.leader_theater_command_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_crisis_forecast_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_forecast_day_live"):
		var day: Dictionary = MapManager.weather_crisis_forecast_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_crisis_gate_multi_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_gate_multi_day_live"):
		var day: Dictionary = MapManager.weather_crisis_gate_multi_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_crisis_sustain_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_sustain_day_live"):
		var day: Dictionary = MapManager.weather_crisis_sustain_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_weather_crisis_campaign_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("weather_crisis_campaign_close_day_live"):
		var day: Dictionary = MapManager.weather_crisis_campaign_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_cell_coverage_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_cell_coverage_day_live"):
		var day: Dictionary = MapManager.intel_cell_coverage_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_cell_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_cell_ops_day_live"):
		var day: Dictionary = MapManager.intel_cell_ops_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_counter_sweep_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_counter_sweep_day_live"):
		var day: Dictionary = MapManager.intel_counter_sweep_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_intel_cell_network_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("intel_cell_network_close_day_live"):
		var day: Dictionary = MapManager.intel_cell_network_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_hq_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_hq_board_day_for_province"):
		var day: Dictionary = MapManager.leader_hq_board_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_multi_station_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_multi_station_day_for_province"):
		var day: Dictionary = MapManager.leader_multi_station_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_theater_ops_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_theater_ops_day_for_province"):
		var day: Dictionary = MapManager.leader_theater_ops_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_leader_theater_command_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("leader_theater_command_close_day_for_province"):
		var day: Dictionary = MapManager.leader_theater_command_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_war_goal_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_war_goal_product_live"):
		var day: Dictionary = MapManager.strategic_war_goal_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_front_campaign_ai_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_campaign_ai_product_live"):
		var day: Dictionary = MapManager.multi_front_campaign_ai_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_grand_strategy_cycle_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("grand_strategy_cycle_product_live"):
		var day: Dictionary = MapManager.grand_strategy_cycle_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_goal_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_goal_board_day_live"):
		var day: Dictionary = MapManager.war_goal_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_goal_justify_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_goal_justify_day_live"):
		var day: Dictionary = MapManager.war_goal_justify_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_war_goal_execute_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("war_goal_execute_day_live"):
		var day: Dictionary = MapManager.war_goal_execute_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_strategic_war_goal_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("strategic_war_goal_close_day_live"):
		var day: Dictionary = MapManager.strategic_war_goal_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_front_plan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_plan_day_live"):
		var day: Dictionary = MapManager.multi_front_plan_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_front_weekly_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_weekly_day_live"):
		var day: Dictionary = MapManager.multi_front_weekly_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_front_execute_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_execute_day_live"):
		var day: Dictionary = MapManager.multi_front_execute_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_multi_front_campaign_ai_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("multi_front_campaign_ai_close_day_live"):
		var day: Dictionary = MapManager.multi_front_campaign_ai_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_gs_cycle_scan_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("gs_cycle_scan_day_for_province"):
		var day: Dictionary = MapManager.gs_cycle_scan_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_gs_cycle_rank_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("gs_cycle_rank_day_for_province"):
		var day: Dictionary = MapManager.gs_cycle_rank_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_gs_cycle_execute_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("gs_cycle_execute_day_for_province"):
		var day: Dictionary = MapManager.gs_cycle_execute_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_grand_strategy_cycle_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("grand_strategy_cycle_close_day_for_province"):
		var day: Dictionary = MapManager.grand_strategy_cycle_close_day_for_province(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_alliance_guarantee_network_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("alliance_guarantee_network_product_live"):
		var day: Dictionary = MapManager.alliance_guarantee_network_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_faction_personality_ai_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("faction_personality_ai_product_live"):
		var day: Dictionary = MapManager.faction_personality_ai_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_revolt_network_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_revolt_network_product_live"):
		var day: Dictionary = MapManager.occupation_revolt_network_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_alliance_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("alliance_board_day_live"):
		var day: Dictionary = MapManager.alliance_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_alliance_guarantee_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("alliance_guarantee_day_live"):
		var day: Dictionary = MapManager.alliance_guarantee_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_alliance_coalition_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("alliance_coalition_day_live"):
		var day: Dictionary = MapManager.alliance_coalition_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_alliance_guarantee_network_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("alliance_guarantee_network_close_day_live"):
		var day: Dictionary = MapManager.alliance_guarantee_network_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_personality_board_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("personality_board_day_live"):
		var day: Dictionary = MapManager.personality_board_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_personality_event_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("personality_event_day_live"):
		var day: Dictionary = MapManager.personality_event_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_personality_drive_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("personality_drive_day_live"):
		var day: Dictionary = MapManager.personality_drive_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_faction_personality_ai_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("faction_personality_ai_close_day_live"):
		var day: Dictionary = MapManager.faction_personality_ai_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_revolt_network_map_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("revolt_network_map_day_live"):
		var day: Dictionary = MapManager.revolt_network_map_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_revolt_cascade_risk_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("revolt_cascade_risk_day_live"):
		var day: Dictionary = MapManager.revolt_cascade_risk_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_revolt_network_suppress_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("revolt_network_suppress_day_live"):
		var day: Dictionary = MapManager.revolt_network_suppress_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_revolt_network_close_day_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("occupation_revolt_network_close_day_live"):
		var day: Dictionary = MapManager.occupation_revolt_network_close_day_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	return ""

static func build_campaign_alpha_primary_strip_product_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("campaign_alpha_primary_strip_product_live"):
		var day: Dictionary = MapManager.campaign_alpha_primary_strip_product_live(province.id)
		if not day.is_empty() and not bool(day.get("empty", false)):
			return str(day.get("bbcode", day.get("summary", ""))).strip_edges()
	elif typeof(MapPolishFormatters) != TYPE_NIL:
		var d: Dictionary = MapPolishFormatters.campaign_alpha_primary_strip_product(province.id)
		if not d.is_empty() and not bool(d.get("empty", false)):
			return str(d.get("bbcode", d.get("summary", ""))).strip_edges()
	return ""

static func build_occupation_visual_chip_bbcode(province: Province) -> String:
	if province == null:
		return ""
	var occupied := not province.controller_tag.is_empty() and province.owner_tag != province.controller_tag
	if not occupied and typeof(GameData) == TYPE_NIL:
		return ""
	var resistance := 0.0
	var compliance := 0.0
	var garr := 0.0
	var mode := "standard"
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_occupation_province_state"):
		var st: Dictionary = GameData.get_occupation_province_state(province.id)
		resistance = float(st.get("resistance_level", 0.0))
		compliance = float(st.get("compliance_level", 0.0))
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_occupation_revolt_state"):
		var rv: Dictionary = GameData.get_occupation_revolt_state(province.id)
		garr = float(rv.get("garrison_strength", 0.0))
		mode = str(rv.get("garrison_mode", "standard"))
	if not occupied and resistance <= 0.0 and compliance <= 0.0:
		return ""
	var tag := "OCC" if occupied else "CTRL"
	return "[color=#e08060]⚑ %s[/color] [color=#8899aa]R %.0f%% · C %.0f%% · garr %.0f%% (%s)[/color]" % [
		tag, resistance * 100.0, compliance * 100.0, garr * 100.0, mode
	]
