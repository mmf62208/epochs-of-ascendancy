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
	var lines: PackedStringArray = []
	lines.append(province.name)
	var owner := province.owner_tag.strip_edges()
	if owner.is_empty():
		owner = country_tag_for_province(province)
	if not owner.is_empty():
		lines.append("Owner: %s" % owner)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_region_id"):
		var rid: int = MapManager.get_province_region_id(province.id)
		if rid > 0:
			var rname: String = MapManager.get_strategic_region_name(rid)
			if not rname.is_empty():
				lines.append("Region: %s" % rname)
	lines.append(province.terrain.capitalize())
	return "\n".join(lines)


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
		var rid: int = MapManager.get_province_region_id(province.id)
		if rid > 0:
			region = MapManager.get_strategic_region_name(rid)
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
	if not pressure_inspector.is_empty():
		if not infra_inspector.is_empty():
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
	lines.append("%sModifier breakdown[/color]" % COLOR_HEADER)
	lines.append(_modifier_legend_bbcode())
	lines.append("")
	var situation_sec := build_inspector_situation_section(province)
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


static func build_province_infrastructure_card_bbcode(
	province: Province,
	compact: bool = true,
) -> String:
	if not province_needs_infrastructure_ui(province):
		return ""
	var bd := _infra_repair_breakdown(province)
	if bd.is_empty():
		return ""
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
	if typeof(MapManager) != TYPE_NIL:
		var bd := MapManager.get_infrastructure_repair_breakdown(province.id)
		if float(bd.get("depot_sabotage_level", 0.0)) > 0.05:
			return true
	return false


static func build_province_infrastructure_section_bbcode(province: Province) -> String:
	var base := build_province_infrastructure_card_bbcode(province, false)

	# Add special sites summary if present
	if province != null and province.special_sites.size() > 0:
		var ss_lines: PackedStringArray = []
		for site in province.special_sites:
			if site == null:
				continue
			var state := "✓" if site.is_completed() else "🚧" if site.is_under_construction() else "⚠"
			ss_lines.append("%s %s (T%d)" % [state, site.id, site.tier])
		if ss_lines.size() > 0:
			base += "\n[color=#a0c0ff]Special Sites:[/color] " + " · ".join(ss_lines)

	return base


## Shows active "Invest in Infrastructure" project status in hover tooltips and inspector.
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

	var pct := int(round(float(st.get("progress", 0.0))))
	var eta := int(st.get("eta_days", 0))
	var target := int(st.get("target_level", province.infrastructure + 1))
	var sabotaged := bool(st.get("is_sabotaged", false))

	var color := COLOR_TECH
	var icon := "🚧"
	if sabotaged:
		color = COLOR_WARN
		icon = "⚠"

	var sab := " (under sabotage)" if sabotaged else ""
	return "%s%s Infra Investment → Lv.%d  %d%%%s (ETA %dd)[/color]" % [
		color, icon, target, pct, sab, eta
	]


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
	if is_province_contested(province):
		return (
			"%sOwner %s  ·  %s⚑ Held by %s[/color]"
			% [COLOR_MUTED, owner, COLOR_WARN, province.controller_tag]
		)
	return "%sOwner: %s[/color]" % [COLOR_MUTED, owner]


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
	preview["engaged_units_att"] = ["Infantry x4", "Armor x2", "Support x1"]
	preview["engaged_units_def"] = ["Infantry x3", "Fort x1"]
	preview["leaders_att"] = ["Rommel (+15% attack, +org)"]
	preview["leaders_def"] = ["Manstein (+12% def)"]
	preview["air_factors"] = "+10% attacker CAS support" if randf() > 0.5 else ""
	preview["modifiers"] = ["-8% night attack (weather)", "+22% defending bonus", "+5% terrain advantage"]
	if "marine" in str(preview.get("terrain", "")) or randf() > 0.7:
		preview["modifiers"].append("+12% amphibious (Marines)")
	if "mountain" in str(preview.get("terrain", "")):
		preview["modifiers"].append("+15% mountain specialists")
	preview["odds_note"] = "Est. attacker success odds: %.0f%% (power %.1f:%.1f)" % [odds, att_pow, def_pow]
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
	if tips.size() > 0:
		block += "\n  %sKey situation: %s[/color]" % [COLOR_MUTED, " · ".join(tips)]
	# Update tips to reference AAR for full specificity (unit logs from Formation, leader, modifiers %, space/air)
	tips.append("See full AAR (F10) for unit combat logs (Formation.combat_log: date/province/result/key factors/leader), leader impacts, modifiers with % values, space/air effects")
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

static func _combat_presence_registry() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	var sm = tree.root.get_node_or_null("SupplyManager")
	if sm and sm.has_method("get_combat_presence_registry"):
		return sm.call("get_combat_presence_registry")
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
