class_name MapTechnologyContext
extends RefCounted

## Bridge between map UI (ProvinceInsight, MapRenderer) and TechnologyManager.
## Keeps technology map/tooltip hooks in one place until build-mode overlays land.
##
## Map Build Eligibility:
##   Use is_design_buildable_in_province() + get_province_build_lock_reason()
##   for province tech, development, terrain, and factory-type gates.
##   Rules: res://data/production/province_build_gates.json

const COLOR_TECH := "[color=#6ec8ff]"
const COLOR_MUTED := "[color=#8899aa]"
const COLOR_HEADER := "[color=#6eb5ff]"
const COLOR_WARN := "[color=#ffb85a]"
const COLOR_OK := "[color=#88c8a0]"

## Support/Radio chain — used for “completed tech” attribution on map UI.
const SUPPORT_RADIO_TECH_IDS: Array[String] = ["radio_i", "radio_ii", "radio_iii"]
const SUPPORT_RADIO_DISPLAY_NAMES: Dictionary = {
	"radio_i": "Radio Detection",
	"radio_ii": "Radio Networks",
	"radio_iii": "Encrypted Networks",
}
## Modifier values from data/technology/trees/support_radio.json (for attribution UI).
const SUPPORT_RADIO_MODIFIERS: Dictionary = {
	"radio_i": {"reconnaissance": 0.05},
	"radio_ii": {"planning_speed": 0.08},
	"radio_iii": {"encryption": 1.0},
}

static func technology_section_header() -> String:
	return "%s── 🔬 Technology ──[/color]" % COLOR_HEADER


static func build_eligibility_section_header() -> String:
	return "%s── 🏭 Build eligibility ──[/color]" % COLOR_HEADER



static func get_map_integration_note(country_tag: String) -> String:
	if typeof(TechnologyManager) == TYPE_NIL:
		return "Map build highlights: wire TechnologyManager when build mode is enabled."
	var tag := country_tag.strip_edges().to_upper()
	var n := TechnologyManager.get_active_research_count(tag)
	var completed := _completed_count(tag)
	var support_note := ""
	if has_support_radio_bonuses(tag):
		support_note = " Support/Radio bonuses show on map tooltips (📡) and affect supply routing."
	return (
		"Map: production gates (tech, development, terrain), research, and Support/Radio (📡) on owned provinces."
		+ support_note
		+ " Planned: cyan highlight for %s placement (%d active, %d completed)."
		% [_build_target_placeholder(tag), n, completed]
	)


static func has_support_radio_bonuses(country_tag: String) -> bool:
	if typeof(TechnologyManager) == TYPE_NIL:
		return false
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return false
	var plan := TechnologyManager.get_effective_planning_speed(tag)
	var recon := TechnologyManager.get_effective_reconnaissance(tag)
	return absf(plan) >= 0.001 or absf(recon) >= 0.001


static func country_has_map_technology(country_tag: String) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() or typeof(TechnologyManager) == TYPE_NIL:
		return false
	if has_support_radio_bonuses(tag):
		return true
	if TechnologyManager.get_active_research_count(tag) > 0:
		return true
	return _completed_count(tag) > 0


static func get_radio_chain_modifier_totals(country_tag: String) -> Dictionary:
	## Planning/recon/encryption from completed Support/Radio tech only (not other trees).
	var out := {"planning_speed": 0.0, "reconnaissance": 0.0, "encryption": 0.0}
	if typeof(TechnologyManager) == TYPE_NIL:
		return out
	var tag := country_tag.strip_edges().to_upper()
	for tech_id in SUPPORT_RADIO_TECH_IDS:
		if not TechnologyManager.is_tech_completed(tag, tech_id):
			continue
		var mods: Dictionary = SUPPORT_RADIO_MODIFIERS.get(tech_id, {}) as Dictionary
		for key in mods.keys():
			out[key] = float(out.get(key, 0.0)) + float(mods[key])
	return out


static func get_support_radio_attribution(country_tag: String) -> Dictionary:
	## Breaks planning/recon into radio-chain vs other completed tech vs non-tech sources.
	var tag := country_tag.strip_edges().to_upper()
	var radio := get_radio_chain_modifier_totals(tag)
	var total_plan := 0.0
	var total_recon := 0.0
	if typeof(TechnologyManager) != TYPE_NIL:
		total_plan = TechnologyManager.get_effective_planning_speed(tag)
		total_recon = TechnologyManager.get_effective_reconnaissance(tag)
	var tech_all := {}
	if typeof(TechnologyManager) != TYPE_NIL:
		tech_all = TechnologyManager.get_technology_modifiers(tag)
	var tech_plan := float(tech_all.get("planning_speed", 0.0))
	var tech_recon := float(tech_all.get("reconnaissance", 0.0))
	var radio_plan := float(radio.get("planning_speed", 0.0))
	var radio_recon := float(radio.get("reconnaissance", 0.0))
	return {
		"total_planning": total_plan,
		"total_recon": total_recon,
		"radio_planning": radio_plan,
		"radio_recon": radio_recon,
		"other_tech_planning": maxf(0.0, tech_plan - radio_plan),
		"other_tech_recon": maxf(0.0, tech_recon - radio_recon),
		"non_tech_planning": maxf(0.0, total_plan - tech_plan),
		"non_tech_recon": maxf(0.0, total_recon - tech_recon),
	}


static func build_per_completed_radio_modifier_lines(country_tag: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	if typeof(TechnologyManager) == TYPE_NIL:
		return lines
	var tag := country_tag.strip_edges().to_upper()
	for tech_id in SUPPORT_RADIO_TECH_IDS:
		if not TechnologyManager.is_tech_completed(tag, tech_id):
			continue
		var name := str(SUPPORT_RADIO_DISPLAY_NAMES.get(tech_id, tech_id))
		var mods: Dictionary = SUPPORT_RADIO_MODIFIERS.get(tech_id, {}) as Dictionary
		var bits: PackedStringArray = []
		if absf(float(mods.get("planning_speed", 0.0))) >= 0.001:
			bits.append("+%.0f%% plan" % (float(mods.get("planning_speed", 0.0)) * 100.0))
		if absf(float(mods.get("reconnaissance", 0.0))) >= 0.001:
			bits.append("+%.0f%% recon" % (float(mods.get("reconnaissance", 0.0)) * 100.0))
		if absf(float(mods.get("encryption", 0.0))) >= 0.001:
			bits.append("encryption")
		if bits.is_empty():
			continue
		lines.append("%s  · %s: %s[/color]" % [COLOR_MUTED, name, " · ".join(bits)])
	return lines


static func build_support_bonus_attribution_bbcode(country_tag: String, compact: bool = true) -> String:
	if not has_support_radio_bonuses(country_tag):
		return ""
	var attr := get_support_radio_attribution(country_tag)
	var total_parts: PackedStringArray = []
	if absf(float(attr.get("total_planning", 0.0))) >= 0.001:
		total_parts.append("+%.0f%% planning" % (float(attr.get("total_planning", 0.0)) * 100.0))
	if absf(float(attr.get("total_recon", 0.0))) >= 0.001:
		total_parts.append("+%.0f%% recon" % (float(attr.get("total_recon", 0.0)) * 100.0))
	if total_parts.is_empty():
		return ""
	var lines: PackedStringArray = []
	lines.append("%s  Total: %s[/color]" % [COLOR_TECH, " · ".join(total_parts)])
	var per_radio := build_per_completed_radio_modifier_lines(country_tag)
	if not per_radio.is_empty():
		if compact and per_radio.size() <= 2:
			lines.append("%s  From completed tech:[/color]" % COLOR_MUTED)
			for line in per_radio:
				lines.append(line)
		else:
			lines.append("%s  From Support/Radio tech:[/color]" % COLOR_MUTED)
			for line in per_radio:
				lines.append(line)
	var other_bits: PackedStringArray = []
	var o_plan := float(attr.get("other_tech_planning", 0.0))
	var o_recon := float(attr.get("other_tech_recon", 0.0))
	if o_plan >= 0.001:
		other_bits.append("+%.0f%% plan (other tech)" % (o_plan * 100.0))
	if o_recon >= 0.001:
		other_bits.append("+%.0f%% recon (other tech)" % (o_recon * 100.0))
	var n_plan := float(attr.get("non_tech_planning", 0.0))
	var n_recon := float(attr.get("non_tech_recon", 0.0))
	if n_plan >= 0.001:
		other_bits.append("+%.0f%% plan (spirits/leaders/timed)" % (n_plan * 100.0))
	if n_recon >= 0.001:
		other_bits.append("+%.0f%% recon (spirits/leaders/timed)" % (n_recon * 100.0))
	if not other_bits.is_empty():
		lines.append("%s  Also: %s[/color]" % [COLOR_MUTED, " · ".join(other_bits)])
	return "\n".join(lines)


static func _support_bonus_parts(country_tag: String) -> PackedStringArray:
	var parts: PackedStringArray = []
	var plan := TechnologyManager.get_effective_planning_speed(country_tag)
	var recon := TechnologyManager.get_effective_reconnaissance(country_tag)
	if absf(plan) >= 0.001:
		parts.append("+%.0f%% planning" % (plan * 100.0))
	if absf(recon) >= 0.001:
		parts.append("+%.0f%% recon" % (recon * 100.0))
	return parts


static func build_support_radio_glance_bbcode(country_tag: String) -> String:
	if not has_support_radio_bonuses(country_tag):
		return ""
	var parts := _support_bonus_parts(country_tag.strip_edges().to_upper())
	return "%s📡 Support/Radio: %s[/color]" % [COLOR_TECH, " · ".join(parts)]


static func build_support_radio_completed_line(country_tag: String) -> String:
	if typeof(TechnologyManager) == TYPE_NIL:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	var names: PackedStringArray = []
	for tech_id in SUPPORT_RADIO_TECH_IDS:
		if TechnologyManager.is_tech_completed(tag, tech_id):
			names.append(str(SUPPORT_RADIO_DISPLAY_NAMES.get(tech_id, tech_id)))
	if names.is_empty():
		return ""
	return "%sCompleted: %s[/color]" % [COLOR_MUTED, " · ".join(names)]


static func build_technology_hover_chip(country_tag: String) -> String:
	## Single chip token for crowded tooltips (research + Support/Radio).
	if typeof(TechnologyManager) == TYPE_NIL:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return ""
	var parts: PackedStringArray = []
	if has_support_radio_bonuses(tag):
		var inner := _bbcode_strip(build_support_radio_compact_chip(tag))
		if not inner.is_empty():
			parts.append(inner)
	var n := TechnologyManager.get_active_research_count(tag)
	if n > 0:
		parts.append("🔬 %d/%d" % [n, TechnologyManager.get_research_slots_max(tag)])
	if parts.is_empty():
		return ""
	return "%s%s[/color]" % [COLOR_TECH, " · ".join(parts)]


static func build_province_technology_tooltip_section(
	province: Province,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	## Dedicated Technology block for hover tooltip / inspector (Support, research, production gates).
	if province == null:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(province)
	if tag.is_empty():
		return ""
	var owned := _province_owned_by(province, tag)
	var has_support := owned and has_support_radio_bonuses(tag)
	var research := build_country_research_glance_bbcode(tag, compact) if owned else ""
	var prod := build_province_production_tech_bbcode(province, tag)
	var has_research := not research.is_empty()
	var has_prod := not prod.is_empty()
	if not owned and not has_prod:
		return ""
	if not has_support and not has_research and not has_prod:
		if not country_has_map_technology(tag):
			return (
				"%s\n%s  No national technology bonuses apply here (not your province).[/color]"
				% [technology_section_header(), COLOR_MUTED]
			)
		return ""
	var lines: PackedStringArray = []
	lines.append(technology_section_header())
	if not owned:
		lines.append(
			"%s  Controller differs — factory gates shown for map owner only.[/color]" % COLOR_MUTED
		)
	if has_support:
		lines.append(build_support_radio_province_block_bbcode(province, tag, compact))
		var attr := build_support_bonus_attribution_bbcode(tag, compact)
		if not attr.is_empty():
			lines.append(attr)
	elif has_support == false and has_research:
		pass
	if has_research:
		if has_support:
			lines.append("%s  Active research[/color]" % COLOR_MUTED)
		lines.append("%s  %s[/color]" % [COLOR_MUTED, _bbcode_strip(research)])
	if has_prod:
		if has_support or has_research:
			lines.append("%s  Production[/color]" % COLOR_MUTED)
		lines.append("%s  %s[/color]" % [COLOR_MUTED, _bbcode_strip(prod)])
	elif owned and typeof(FactoryManager) != TYPE_NIL:
		var factories := FactoryManager.get_factories_in_province(province.id)
		if not factories.is_empty() and not has_support and not has_research:
			lines.append("%s  🔧 Factories: no tech locks[/color]" % COLOR_MUTED)
	if has_support and owned:
		var routes := build_support_route_summary_plain(tag)
		if not routes.is_empty():
			lines.append("%s  Route impact: %s[/color]" % [COLOR_MUTED, routes])
		lines.append(
			"%s  Applies on routes through your provinces (reinforcement & interdiction).[/color]"
			% COLOR_MUTED
		)
	elif has_research and not has_support:
		lines.append(
			"%s  Complete Support/Radio tech to boost planning, recon, and route efficiency.[/color]"
			% COLOR_MUTED
		)
	return "\n".join(lines)


static func build_support_radio_province_block_bbcode(
	province: Province,
	country_tag: String,
	compact: bool = true,
) -> String:
	if province == null or not has_support_radio_bonuses(country_tag):
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if not _province_owned_by(province, tag):
		return ""
	if compact:
		return "%s  📡 Support/Radio (national)[/color]" % COLOR_TECH
	var lines: PackedStringArray = ["%s  📡 Support/Radio (national)[/color]" % COLOR_TECH]
	var supply := build_support_supply_effect_bbcode(tag)
	if not supply.is_empty():
		lines.append("%s  %s[/color]" % [COLOR_MUTED, _bbcode_strip(supply)])
	return "\n".join(lines)


static func build_province_technology_inspector_section(
	province: Province,
	country_tag: String = "",
) -> String:
	var block := build_province_technology_tooltip_section(province, country_tag, false)
	if block.is_empty():
		return ""
	var lines: PackedStringArray = [block]
	lines.append(
		"%sOpen Technology screen for research slots and build unlocks.[/color]" % COLOR_MUTED
	)
	return "\n".join(lines)


static func _bbcode_strip(text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("[color"):
		var end := t.find("]")
		if end >= 0:
			t = t.substr(end + 1)
	if t.ends_with("[/color]"):
		t = t.substr(0, t.length() - 8)
	return t.strip_edges()


static func build_technology_status_chip(country_tag: String) -> String:
	## Single mode-chip token for research + Support/Radio (avoids two tech tokens).
	if typeof(TechnologyManager) == TYPE_NIL:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return ""
	var n := TechnologyManager.get_active_research_count(tag)
	var has_support := has_support_radio_bonuses(tag)
	if n <= 0 and not has_support:
		return ""
	if n > 0 and has_support:
		var slots := TechnologyManager.get_research_slots_max(tag)
		var suffix := _support_bonus_plain(tag)
		if suffix.is_empty():
			return "%s🔬 %d/%d slots[/color]" % [COLOR_TECH, n, slots]
		return "%s🔬 %d/%d · %s[/color]" % [COLOR_TECH, n, slots, suffix]
	if n > 0:
		return build_country_research_glance_bbcode(tag, true)
	return build_support_radio_compact_chip(tag)


static func _support_bonus_plain(country_tag: String) -> String:
	var parts := _support_bonus_parts(country_tag)
	if parts.is_empty():
		return ""
	return "📡 " + " · ".join(parts)


static func build_support_radio_compact_chip(country_tag: String) -> String:
	if not has_support_radio_bonuses(country_tag):
		return ""
	var tag := country_tag.strip_edges().to_upper()
	var plan := TechnologyManager.get_effective_planning_speed(tag)
	var recon := TechnologyManager.get_effective_reconnaissance(tag)
	if absf(plan) >= 0.001 and absf(recon) >= 0.001:
		return "%s📡 +%.0f%% plan · +%.0f%% recon[/color]" % [
			COLOR_TECH, plan * 100.0, recon * 100.0,
		]
	if absf(plan) >= 0.001:
		return "%s📡 +%.0f%% planning[/color]" % [COLOR_TECH, plan * 100.0]
	return "%s📡 +%.0f%% recon[/color]" % [COLOR_TECH, recon * 100.0]


static func build_support_route_summary_plain(country_tag: String) -> String:
	## Short plain summary for national one-liner (no duplicate 📡 prefix).
	if not has_support_radio_bonuses(country_tag):
		return ""
	var tag := country_tag.strip_edges().to_upper()
	var plan := TechnologyManager.get_effective_planning_speed(tag)
	var recon := TechnologyManager.get_effective_reconnaissance(tag)
	var parts: PackedStringArray = []
	if absf(plan) >= 0.001:
		parts.append("reinf +%.0f%%" % (plan * 60.0))
	if absf(recon) >= 0.001:
		var cut := (1.0 - maxf(0.55, 1.0 - recon * 1.2)) * 100.0
		parts.append("interdict −%.0f%%" % cut)
	if parts.is_empty():
		return ""
	return "routes: " + " · ".join(parts)


static func build_national_support_line_bbcode(country_tag: String, compact: bool = true) -> String:
	## National tooltip line — totals + route impact + completed-tech hint.
	if not has_support_radio_bonuses(country_tag):
		return ""
	var tag := country_tag.strip_edges().to_upper()
	var bonus := " · ".join(_support_bonus_parts(tag))
	var routes := build_support_route_summary_plain(tag)
	if compact:
		var line := "📡 " + bonus
		if not routes.is_empty():
			line += " · " + routes
		var per_radio := build_per_completed_radio_modifier_lines(tag)
		if per_radio.size() == 1:
			line += " · " + _bbcode_strip(per_radio[0]).replace("  · ", "")
		elif per_radio.size() > 1:
			line += " · %d radio techs" % per_radio.size()
		return "%s%s[/color]" % [COLOR_TECH, line]
	var lines: PackedStringArray = ["%s📡 Support/Radio[/color]" % COLOR_TECH]
	lines.append(build_support_bonus_attribution_bbcode(tag, true))
	if not routes.is_empty():
		lines.append("%s  %s[/color]" % [COLOR_MUTED, routes])
	return "\n".join(lines)


static func build_support_recovery_hint_bbcode(country_tag: String) -> String:
	if not has_support_radio_bonuses(country_tag):
		return ""
	var routes := build_support_route_summary_plain(country_tag)
	if routes.is_empty():
		return ""
	return "%s📡 Support/Radio helps recovery: %s[/color]" % [COLOR_TECH, routes]


static func build_support_supply_effect_bbcode(country_tag: String) -> String:
	## Matches SupplyManager radio hooks (reinforcement + interdiction).
	if not has_support_radio_bonuses(country_tag):
		return ""
	var tag := country_tag.strip_edges().to_upper()
	var plan := TechnologyManager.get_effective_planning_speed(tag)
	var recon := TechnologyManager.get_effective_reconnaissance(tag)
	var parts: PackedStringArray = []
	if absf(plan) >= 0.001:
		parts.append("reinforcement +%.0f%%" % (plan * 60.0))
	if absf(recon) >= 0.001:
		var cut := (1.0 - maxf(0.55, 1.0 - recon * 1.2)) * 100.0
		parts.append("route interdiction −%.0f%%" % cut)
	return "%s📡 Routes: %s[/color]" % [COLOR_TECH, " · ".join(parts)]


static func build_province_support_benefit_bbcode(province: Province, country_tag: String) -> String:
	## One line when a province is yours and national Support/Radio applies.
	if province == null or not has_support_radio_bonuses(country_tag):
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() or not _province_owned_by(province, tag):
		return ""
	var parts := _support_bonus_parts(tag)
	var bonus := " · ".join(parts)
	if bonus.is_empty():
		return "%s📡 Support/Radio bonuses apply to routes through this province.[/color]" % COLOR_TECH
	var routes := build_support_route_summary_plain(tag)
	var route_bit := ""
	if not routes.is_empty():
		route_bit = " · " + routes
	return (
		"%s📡 Support/Radio (%s)%s — bonuses apply on routes through here.[/color]"
		% [COLOR_TECH, bonus, route_bit]
	)


static func build_support_radio_inspector_block(country_tag: String) -> String:
	if not has_support_radio_bonuses(country_tag):
		return ""
	var lines: PackedStringArray = []
	lines.append(build_support_radio_glance_bbcode(country_tag))
	lines.append(build_support_supply_effect_bbcode(country_tag))
	lines.append(
		"%sApplies nationally — depots and routes in your provinces benefit.[/color]" % COLOR_MUTED
	)
	return "\n".join(lines)


static func build_country_research_glance_bbcode(country_tag: String, compact: bool = false) -> String:
	if typeof(TechnologyManager) == TYPE_NIL:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	var n := TechnologyManager.get_active_research_count(tag)
	if n <= 0:
		return ""
	var slots := TechnologyManager.get_research_slots_max(tag)
	var rp := TechnologyManager.get_daily_rp(tag)
	if compact:
		return "%s🔬 %d/%d · %.1f RP[/color]" % [COLOR_TECH, n, slots, rp]
	return "%s🔬 Research %d/%d slots · %.1f RP/day[/color]" % [COLOR_TECH, n, slots, rp]


static func build_province_production_tech_bbcode(province: Province, country_tag: String) -> String:
	if province == null or typeof(FactoryManager) == TYPE_NIL or typeof(TechnologyManager) == TYPE_NIL:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return ""
	var factories := FactoryManager.get_factories_in_province(province.id)
	if factories.is_empty():
		return ""
	var locked_names := PackedStringArray()
	for factory in factories:
		if factory == null:
			continue
		var tid := str(factory.current_production_design).strip_edges()
		if tid.is_empty():
			continue
		var gate: Dictionary = TechnologyManager.get_design_availability(tag, tid)
		if bool(gate.get("available", true)):
			continue
		var name := str(gate.get("tech_name", gate.get("reason", "Tech"))).strip_edges()
		if not name.is_empty() and name not in locked_names:
			locked_names.append(name)
	if locked_names.is_empty():
		return "%s🔧 Factories: designs available[/color]" % COLOR_MUTED
	if locked_names.size() == 1:
		return "%s🔧 Factories need: %s[/color]" % [COLOR_MUTED, locked_names[0]]
	return (
		"%s🔧 Factories need: %s (+%d)[/color]"
		% [COLOR_MUTED, locked_names[0], locked_names.size() - 1]
	)


static func build_province_technology_bbcode(province: Province, country_tag: String = "") -> String:
	if province == null:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(province)
	var parts: PackedStringArray = []
	var national := build_country_research_glance_bbcode(tag)
	if not national.is_empty() and _province_owned_by(province, tag):
		parts.append(national)
	var prod := build_province_production_tech_bbcode(province, tag)
	if not prod.is_empty():
		parts.append(prod)
	if parts.is_empty():
		return ""
	return "  ·  ".join(parts)


static func get_build_mode_preview(country_tag: String = "") -> Dictionary:
	var preview: Dictionary = {
		"active": false,
		"target_tech_id": "",
		"target_label": "Select technology",
		"outline_color": Color(0.45, 0.85, 1.0, 0.9),
		"legend_line": "[color=#8899aa]🔬 Build mode (planned): cyan outline = valid placement[/color]",
	}
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() or typeof(TechnologyManager) == TYPE_NIL:
		return preview
	var unlocked := TechnologyManager.get_unlocked_factory_types(tag)
	if not unlocked.is_empty():
		preview["legend_line"] = (
			"[color=#8899aa]🔬 Unlocks: [/color][color=#6ec8ff]%s[/color]"
			% ", ".join(unlocked)
		)
	return preview


static func _province_owned_by(province: Province, country_tag: String) -> bool:
	var owner := province.owner_tag.strip_edges().to_upper()
	var ctrl := province.controller_tag.strip_edges().to_upper()
	if ctrl.is_empty():
		ctrl = owner
	return ctrl == country_tag or owner == country_tag


static func _completed_count(country_tag: String) -> int:
	var state: Dictionary = TechnologyManager.get_country_state(country_tag)
	var completed: Dictionary = state.get("completed", {}) as Dictionary
	var n := 0
	for key in completed.keys():
		if bool(completed[key]):
			n += 1
	return n


static func _build_target_placeholder(country_tag: String) -> String:
	var state: Dictionary = TechnologyManager.get_country_state(country_tag)
	var types: Array = state.get("unlocked_factory_types", []) as Array
	if types.is_empty():
		return "factories/buildings"
	return str(types[types.size() - 1])


## === Map Build Eligibility (tech + development + terrain + factory) ===

const PROVINCE_BUILD_GATES_PATH := "res://data/production/province_build_gates.json"

static var _province_gates: Dictionary = {}
static var _province_gates_loaded: bool = false


static func _ensure_province_build_gates() -> Dictionary:
	if _province_gates_loaded:
		return _province_gates
	_province_gates_loaded = true
	if not FileAccess.file_exists(PROVINCE_BUILD_GATES_PATH):
		_province_gates = {}
		return _province_gates
	var f := FileAccess.open(PROVINCE_BUILD_GATES_PATH, FileAccess.READ)
	if f == null:
		_province_gates = {}
		return _province_gates
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_province_gates = parsed
	return _province_gates


static func _gates_messages() -> Dictionary:
	return _ensure_province_build_gates().get("messages", {}) as Dictionary


static func _province_for_id(province_id: int) -> Province:
	if typeof(MapManager) == TYPE_NIL or province_id < 0:
		return null
	return MapManager.get_province(province_id)


static func _resolve_country_tag(province: Province, country_tag: String) -> String:
	var tag := country_tag.strip_edges().to_upper()
	if not tag.is_empty():
		return tag
	if province == null:
		return ""
	tag = province.controller_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = province.owner_tag.strip_edges().to_upper()
	return tag


static func _design_domain(design_id: String) -> String:
	if typeof(DesignManager) != TYPE_NIL:
		return DesignManager.get_design_domain(design_id)
	if GameData.design_data == null:
		return "land"
	var template: UnitTemplate = GameData.design_data.get_template(design_id)
	if template == null:
		return "land"
	if not template.design_domain.is_empty():
		return template.design_domain.strip_edges().to_lower()
	if ProductionNavalRules.is_naval_design(design_id):
		return "naval"
	return "land"


static func _design_era(design_id: String) -> String:
	if GameData.design_data == null:
		return "ww2"
	var template: UnitTemplate = GameData.design_data.get_template(design_id)
	if template == null:
		return "ww2"
	return ProductionCostCalculator.infer_era(template)


static func min_development_for_design(design_id: String, factory_type: String = "") -> int:
	var gates := _ensure_province_build_gates()
	var dev_rules: Dictionary = gates.get("development", {}) as Dictionary
	var min_req := 1
	var era := _design_era(design_id)
	var era_map: Dictionary = dev_rules.get("min_by_era", {}) as Dictionary
	if era_map.has(era):
		min_req = maxi(min_req, int(era_map[era]))
	var domain := _design_domain(design_id)
	var domain_map: Dictionary = dev_rules.get("min_by_domain", {}) as Dictionary
	if domain_map.has(domain):
		min_req = maxi(min_req, int(domain_map[domain]))
	var ft := factory_type.strip_edges().to_lower()
	if not ft.is_empty():
		var ft_map: Dictionary = dev_rules.get("min_by_factory_type", {}) as Dictionary
		if ft_map.has(ft):
			min_req = maxi(min_req, int(ft_map[ft]))
	return min_req


static func _terrain_development_bonus(terrain: String, domain: String) -> int:
	var gates := _ensure_province_build_gates()
	var terrain_rules: Dictionary = gates.get("terrain", {}) as Dictionary
	var bonus_map: Dictionary = terrain_rules.get("domain_min_development_bonus", {}) as Dictionary
	var t_key := terrain.strip_edges().to_lower()
	if not bonus_map.has(t_key):
		return 0
	var per_domain: Dictionary = bonus_map[t_key] as Dictionary
	var d := domain.strip_edges().to_lower()
	if per_domain.has(d):
		return int(per_domain[d])
	if d == "land" and per_domain.has("armor"):
		return int(per_domain["armor"])
	return 0


static func evaluate_province_design_gate(
	province: Province,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> Dictionary:
	var blocked := {
		"allowed": true,
		"kind": "",
		"reason": "",
		"action": "",
		"min_development": 0,
		"development_level": 0,
		"terrain": "",
		"domain": "",
	}
	if province == null or design_id.strip_edges().is_empty():
		blocked["allowed"] = false
		blocked["kind"] = "invalid"
		blocked["reason"] = "Invalid province or design"
		return blocked
	var tag := _resolve_country_tag(province, country_tag)
	blocked["development_level"] = province.development_level
	blocked["terrain"] = str(province.terrain).strip_edges().to_lower()
	blocked["domain"] = _design_domain(design_id)
	if typeof(DesignManager) != TYPE_NIL and not tag.is_empty():
		if not DesignManager.country_may_use_design(tag, design_id):
			blocked["allowed"] = false
			blocked["kind"] = "catalog"
			blocked["reason"] = "Foreign design — not in national catalog (capture or purchase required)"
			blocked["action"] = "Capture factories producing this design or acquire via trade/licensing."
			return blocked
	if typeof(TechnologyManager) != TYPE_NIL and not tag.is_empty():
		var avail := TechnologyManager.get_design_availability(tag, design_id)
		if not bool(avail.get("available", true)):
			blocked["allowed"] = false
			blocked["kind"] = "tech"
			blocked["reason"] = str(avail.get("reason", "Requires technology"))
			blocked["action"] = "Complete %s on the Technology screen." % str(
				avail.get("tech_name", "required research"),
			)
			return blocked
	var ft := factory.factory_type if factory != null else ""
	var min_dev := min_development_for_design(design_id, ft)
	min_dev += _terrain_development_bonus(blocked["terrain"], blocked["domain"])
	blocked["min_development"] = min_dev
	if province.development_level < min_dev:
		var msgs := _gates_messages()
		blocked["allowed"] = false
		blocked["kind"] = "development"
		var gap := mini(min_dev - province.development_level, 9)
		blocked["reason"] = str(msgs.get("development_short", "Needs development %d (province %d)")) % [
			min_dev, province.development_level,
		]
		if msgs.has("development_gap_action"):
			blocked["action"] = str(msgs["development_gap_action"]) % [min_dev, province.development_level, gap]
		else:
			blocked["action"] = str(
				msgs.get(
					"development_action",
					"Raise province development through industry and infrastructure investment.",
				)
			)
		var alt := find_better_build_province_names(
			province, blocked["domain"], min_dev, tag, 2,
		)
		if not alt.is_empty():
			blocked["action"] += " Or reassign production to %s." % " / ".join(alt)
		return blocked
	var terrain_gate := _evaluate_terrain_gate(province, blocked["domain"])
	if not bool(terrain_gate.get("allowed", true)):
		blocked["allowed"] = false
		blocked["kind"] = "terrain"
		blocked["reason"] = str(terrain_gate.get("reason", "Terrain blocks this production"))
		blocked["action"] = str(terrain_gate.get("action", "Choose a province with suitable terrain or port access."))
		return blocked
	if factory != null and typeof(TechnologyManager) != TYPE_NIL and not tag.is_empty():
		var fc: Dictionary = TechnologyManager.factory_can_build_design(tag, factory, design_id)
		if not bool(fc.get("allowed", true)):
			blocked["allowed"] = false
			blocked["kind"] = "factory"
			var detail: Dictionary = fc.get("detail", {}) as Dictionary
			blocked["reason"] = str(detail.get("reason", "Wrong factory type for this design"))
			blocked["action"] = "Use a compatible factory type in a suitable province."
			return blocked
	if typeof(DesignManager) != TYPE_NIL and factory != null:
		if not DesignManager.is_design_factory_compatible(design_id, factory):
			blocked["allowed"] = false
			blocked["kind"] = "terrain"
			blocked["reason"] = "Naval design requires a shipyard at a port province"
			blocked["action"] = "Assign a shipyard factory in a coastal province with port access."
			return blocked
	return blocked


static func _evaluate_terrain_gate(province: Province, domain: String) -> Dictionary:
	var ok := {"allowed": true, "reason": "", "action": ""}
	if province == null:
		return ok
	var gates := _ensure_province_build_gates()
	var terrain_rules: Dictionary = gates.get("terrain", {}) as Dictionary
	var msgs := _gates_messages()
	var terrain := str(province.terrain).strip_edges().to_lower()
	var d := domain.strip_edges().to_lower()
	if province.is_sea:
		var sea_except: Array = terrain_rules.get("impossible_on_sea_except_domains", ["naval"]) as Array
		if d not in sea_except:
			ok["allowed"] = false
			ok["reason"] = str(msgs.get("terrain_sea_land", "Land production is not possible in sea provinces"))
			ok["action"] = "Use a land province, or produce naval designs only at sea zones with shipyards."
			return ok
	var port_domains: Array = terrain_rules.get("requires_port_domains", ["naval"]) as Array
	if d in port_domains and not province.resolve_has_port():
		ok["allowed"] = false
		ok["reason"] = str(
			msgs.get("terrain_port_required", "Naval production requires a coastal province with port access")
		)
		ok["action"] = "Capture or develop a coastal province with a port, then place a shipyard."
		return ok
	var blocked_all: Dictionary = terrain_rules.get("blocked_all_except_domains", {}) as Dictionary
	if blocked_all.has(terrain):
		var allowed: Array = blocked_all[terrain] as Array
		if d not in allowed:
			ok["allowed"] = false
			ok["reason"] = str(msgs.get("terrain_domain_blocked", "%s terrain cannot host %s production")) % [
				terrain.capitalize(), d,
			]
			ok["action"] = "Move production to a province with suitable terrain."
			return ok
	var blocked_domains: Dictionary = terrain_rules.get("blocked_domains", {}) as Dictionary
	if blocked_domains.has(terrain):
		var blocked_list: Array = blocked_domains[terrain] as Array
		if d in blocked_list:
			ok["allowed"] = false
			ok["reason"] = str(msgs.get("terrain_domain_blocked", "%s terrain cannot host %s production")) % [
				terrain.capitalize(), d,
			]
			ok["action"] = "Assign this line to plains, urban, or coastal industrial provinces."
			return ok
	return ok


static func gate_short_label(gate: Dictionary) -> String:
	if bool(gate.get("allowed", true)):
		return ""
	var kind := str(gate.get("kind", "tech"))
	match kind:
		"tech":
			var reason := str(gate.get("reason", "Research required"))
			if reason.length() > 48:
				reason = reason.substr(0, 46) + "…"
			return reason
		"development":
			return "Dev %d needed (have %d)" % [
				int(gate.get("min_development", 0)),
				int(gate.get("development_level", 0)),
			]
		"terrain":
			return str(gate.get("reason", "Terrain blocked")).split("—")[0].strip_edges()
		"factory":
			return str(gate.get("reason", "Wrong factory type"))
		"catalog":
			return "Not in national catalog"
		_:
			return str(gate.get("reason", "Locked"))


static func gate_action_hint(
	gate: Dictionary,
	province: Province = null,
	country_tag: String = "",
) -> String:
	if bool(gate.get("allowed", true)):
		return ""
	var action := str(gate.get("action", "")).strip_edges()
	if not action.is_empty():
		return action
	var kind := str(gate.get("kind", ""))
	match kind:
		"tech":
			return "Open Technology and complete the listed research."
		"development":
			return _development_investment_hint()
		"terrain":
			if province != null:
				var alts := find_better_build_province_names(
					province,
					str(gate.get("domain", "land")),
					int(gate.get("min_development", 3)),
					country_tag,
					2,
				)
				if not alts.is_empty():
					return "Move line to %s, or capture a suitable province." % " / ".join(alts)
			return "Pick a province with suitable terrain and port access."
		_:
			return ""


static func _development_investment_hint() -> String:
	var msgs := _gates_messages()
	return str(
		msgs.get(
			"development_investment_hint",
			"Factories and infrastructure raise development; investment projects coming later.",
		)
	)


static func normalize_relocate_label(label: String) -> String:
	var name := str(label).strip_edges()
	if name == "relocate":
		return ""
	if " (dev " in name:
		return name.split(" (dev ")[0].strip_edges()
	return name


static func _find_map_renderer() -> MapRenderer:
	var loop := Engine.get_main_loop()
	if loop == null or not loop is SceneTree:
		return null
	var found: Array[Node] = (loop as SceneTree).root.find_children("", "MapRenderer", true, false)
	if found.is_empty():
		return null
	return found[0] as MapRenderer


static func focus_province_on_map(province_id: int) -> bool:
	if province_id < 0:
		return false
	var renderer := _find_map_renderer()
	if renderer == null:
		return false
	return renderer.focus_province_by_id(province_id)


static func focus_relocate_target_on_map(
	target_name: String,
	country_tag: String = "",
) -> Dictionary:
	var name := normalize_relocate_label(target_name)
	var pid := find_province_id_for_relocate_target(name, country_tag)
	var out := {"ok": false, "province_id": pid, "name": name}
	if pid < 0:
		return out
	out["ok"] = focus_province_on_map(pid)
	return out


static func _pick_relocate_target_excluding_self(
	province: Province,
	country_tag: String,
	candidate_names: PackedStringArray,
) -> Dictionary:
	var out := {"name": "", "province_id": -1}
	for raw in candidate_names:
		var name := normalize_relocate_label(str(raw))
		if name.is_empty():
			continue
		var pid := find_province_id_for_relocate_target(name, country_tag)
		if pid < 0:
			continue
		if province != null and pid == province.id:
			continue
		out["name"] = name
		out["province_id"] = pid
		return out
	return out


static func get_primary_relocate_target(
	province: Province,
	country_tag: String = "",
	design_id: String = "",
) -> Dictionary:
	if province == null:
		return {"name": "", "province_id": -1}
	var snap := collect_province_build_eligibility(province, country_tag)
	var rec: Dictionary = get_relocate_recommendation(province, country_tag, snap)
	var candidates: PackedStringArray = []
	var primary := normalize_relocate_label(str(rec.get("primary_target", "")))
	if not primary.is_empty():
		candidates.append(primary)
	for sec_var in rec.get("secondary_targets", PackedStringArray()):
		var sec := normalize_relocate_label(str(sec_var))
		if not sec.is_empty() and sec not in candidates:
			candidates.append(sec)
	if not design_id.strip_edges().is_empty():
		for alt in find_best_provinces_for_design(province, design_id, country_tag, null, 3):
			var a := normalize_relocate_label(alt)
			if not a.is_empty() and a not in candidates:
				candidates.append(a)
	var picked := _pick_relocate_target_excluding_self(province, country_tag, candidates)
	picked["should_relocate"] = bool(rec.get("should_relocate", false))
	picked["should_invest_here"] = bool(rec.get("should_invest_here", false))
	return picked


static func find_province_id_for_relocate_target(
	target_name: String,
	country_tag: String = "",
) -> int:
	var name := normalize_relocate_label(target_name)
	if name.is_empty() or typeof(MapManager) == TYPE_NIL:
		return -1
	var tag := country_tag.strip_edges().to_upper()
	for pid in MapManager.get_provinces_by_controller(tag):
		var p: Province = MapManager.get_province(int(pid))
		if p != null and p.name == name:
			return int(pid)
	return -1


static func find_better_build_province_names(
	current: Province,
	domain: String,
	min_dev: int,
	country_tag: String,
	limit: int = 2,
) -> PackedStringArray:
	var names: PackedStringArray = []
	if current == null or typeof(MapManager) == TYPE_NIL or limit <= 0:
		return names
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(current)
	var candidates: Array[Dictionary] = []
	for pid in MapManager.get_provinces_by_controller(tag):
		if int(pid) == current.id:
			continue
		var p: Province = MapManager.get_province(int(pid))
		if p == null or p.development_level < min_dev:
			continue
		var terrain_gate := _evaluate_terrain_gate(p, domain)
		if not bool(terrain_gate.get("allowed", true)):
			continue
		var score := p.development_level
		if typeof(FactoryManager) != TYPE_NIL:
			var fc := FactoryManager.get_factories_in_province(p.id).size()
			if fc > 0:
				score += 3
		candidates.append({"name": p.name, "score": score, "dev": p.development_level})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	for entry in candidates:
		if names.size() >= limit:
			break
		var label := str(entry.get("name", ""))
		if label.is_empty():
			continue
		if int(entry.get("dev", 0)) > current.development_level:
			label += " (dev %d)" % int(entry["dev"])
		names.append(label)
	return names


static func find_best_provinces_for_design(
	current: Province,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
	limit: int = 2,
) -> PackedStringArray:
	var names: PackedStringArray = []
	if current == null or design_id.strip_edges().is_empty() or typeof(MapManager) == TYPE_NIL or limit <= 0:
		return names
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(current)
	var candidates: Array[Dictionary] = []
	for pid in MapManager.get_provinces_by_controller(tag):
		if int(pid) == current.id:
			continue
		var p: Province = MapManager.get_province(int(pid))
		if p == null:
			continue
		var gate := evaluate_province_design_gate(p, design_id, tag, null)
		if not bool(gate.get("allowed", true)):
			continue
		var score := p.development_level
		if typeof(FactoryManager) != TYPE_NIL:
			var fc := FactoryManager.get_factories_in_province(p.id).size()
			score += fc * 3
			if factory != null and fc > 0:
				for f in FactoryManager.get_factories_in_province(p.id):
					if f != null and f.factory_type == factory.factory_type:
						score += 2
						break
		candidates.append({"name": p.name, "score": score, "dev": p.development_level})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	for entry in candidates:
		if names.size() >= limit:
			break
		var label := str(entry.get("name", ""))
		if label.is_empty():
			continue
		if int(entry.get("dev", 0)) > current.development_level:
			label += " (dev %d)" % int(entry["dev"])
		names.append(label)
	return names


static func build_production_action_plain(
	province: Province,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> String:
	if province == null:
		return ""
	var gate := evaluate_province_design_gate(province, design_id, country_tag, factory)
	if bool(gate.get("allowed", true)):
		return str(_gates_messages().get("production_ready_action", "Production: assign here when ready"))
	var kind := str(gate.get("kind", ""))
	if kind == "tech":
		return str(_gates_messages().get("decision_research_first", "Research first"))
	var alts := find_best_provinces_for_design(province, design_id, country_tag, factory, 1)
	if not alts.is_empty():
		return str(_gates_messages().get("production_assign_action", "Assign at {target}")).format({
			"target": normalize_relocate_label(alts[0]),
		})
	var rec: Dictionary = get_relocate_recommendation(province, country_tag)
	var target := normalize_relocate_label(str(rec.get("primary_target", "")))
	if not target.is_empty():
		return str(_gates_messages().get("production_assign_action", "")).format({"target": target})
	return gate_action_hint(gate, province, country_tag)


static func build_province_build_actions_bbcode(
	province: Province,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if province == null:
		return ""
	var snap := collect_province_build_eligibility(province, country_tag)
	var lines: PackedStringArray = []
	if not compact:
		lines.append("%s  %s[/color]" % [COLOR_HEADER, str(_gates_messages().get("actions_header", "What to do next"))])
	var decision := build_retool_reloc_decision_bbcode(province, country_tag, true)
	if not decision.is_empty():
		lines.append(decision)
	var locked: Array = snap.get("locked_lines", [])
	if province.development_level < 5:
		var growth := build_development_growth_playbook_bbcode(province, country_tag, true)
		if not growth.is_empty() and (locked.is_empty() or decision.is_empty()):
			lines.append(growth)
		elif not locked.is_empty():
			var growth_plain := build_development_growth_plain(province)
			if not growth_plain.is_empty():
				lines.append("%s  %s[/color]" % [COLOR_MUTED, growth_plain])
	if not locked.is_empty() and decision.is_empty():
		var steps := build_eligibility_next_steps_bbcode(province, snap, country_tag, compact)
		if not steps.is_empty():
			lines.append(steps)
	if lines.is_empty():
		return ""
	return "\n".join(lines)


static func build_relocate_tooltip_plain(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var rec: Dictionary = get_relocate_recommendation(province, country_tag)
	var target := normalize_relocate_label(str(rec.get("primary_target", "")).strip_edges())
	if target.is_empty():
		return ""
	var parts: PackedStringArray = ["Recommended province: %s" % target]
	var target_pid := find_province_id_for_relocate_target(target, country_tag)
	if target_pid > 0:
		var map_hint := str(_gates_messages().get("relocate_map_hint", "Select on map: province #{id}"))
		parts.append(map_hint.format({"id": target_pid}))
	var decision := str(rec.get("decision_line", "")).strip_edges()
	if not decision.is_empty():
		parts.append(decision)
	var secondary: PackedStringArray = rec.get("secondary_targets", PackedStringArray())
	if secondary.size() > 0:
		parts.append("Also: %s" % " · ".join(secondary))
	var action_tmpl := str(_gates_messages().get("relocate_chip_action", "")).strip_edges()
	if action_tmpl.is_empty():
		action_tmpl = str(_gates_messages().get("production_assign_action", ""))
	parts.append(action_tmpl.format({"target": target}))
	return " · ".join(parts)


static func assess_province_production_profile(province: Province) -> Dictionary:
	var good: PackedStringArray = []
	var weak: PackedStringArray = []
	if province == null:
		return {"good": good, "weak": weak}
	var dev := province.development_level
	var terrain := str(province.terrain).strip_edges().to_lower()
	var has_port := province.resolve_has_port()
	var gates := _ensure_province_build_gates()
	var blocked_domains: Dictionary = (
		gates.get("terrain", {}).get("blocked_domains", {}) as Dictionary
	)
	var blocked_here: Array = blocked_domains.get(terrain, []) as Array
	if province.is_sea:
		good.append("naval (sea zone)")
		weak.append("land/armor")
	else:
		good.append("land")
		if dev >= 2:
			good.append("support")
		if dev >= 3:
			good.append("armor")
		else:
			weak.append("tank plant (need dev 3+)")
		if has_port and "naval" not in blocked_here and dev >= 3:
			good.append("naval")
		elif not has_port:
			weak.append("naval (no port)")
		elif "naval" in blocked_here:
			weak.append("naval (%s terrain)" % terrain)
		if dev >= 4 and "air" not in blocked_here:
			good.append("air")
		else:
			weak.append("air (need dev 4+)")
		if "space" in blocked_here:
			weak.append("space")
		var bonus := _terrain_development_bonus(terrain, "air")
		if bonus > 0 and dev < 4 + bonus:
			weak.append("air (+%d dev from terrain)" % bonus)
	return {"good": good, "weak": weak}


static func build_province_production_profile_bbcode(
	province: Province,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if province == null:
		return ""
	var profile: Dictionary = assess_province_production_profile(province)
	var good: PackedStringArray = profile.get("good", PackedStringArray())
	var weak: PackedStringArray = profile.get("weak", PackedStringArray())
	if good.is_empty() and weak.is_empty():
		return ""
	if compact:
		var bits: PackedStringArray = []
		if not good.is_empty():
			bits.append("Good for: %s" % ", ".join(good))
		if not weak.is_empty():
			bits.append("Weak for: %s" % ", ".join(weak))
		return "%s  %s[/color]" % [COLOR_TECH, " · ".join(bits)]
	var lines: PackedStringArray = []
	lines.append("%s  Province production profile[/color]" % COLOR_TECH)
	if not good.is_empty():
		lines.append("%s  Strong fit: %s[/color]" % [COLOR_OK, ", ".join(good)])
	if not weak.is_empty():
		lines.append("%s  Poor fit: %s[/color]" % [COLOR_WARN, ", ".join(weak)])
	return "\n".join(lines)


static func build_province_production_profile_plain(province: Province) -> String:
	var profile: Dictionary = assess_province_production_profile(province)
	var good: PackedStringArray = profile.get("good", PackedStringArray())
	var weak: PackedStringArray = profile.get("weak", PackedStringArray())
	if good.is_empty() and weak.is_empty():
		return ""
	var parts: PackedStringArray = []
	if not good.is_empty():
		parts.append("Good for: " + ", ".join(good))
	if not weak.is_empty():
		parts.append("Weak for: " + ", ".join(weak))
		if province.development_level < 5:
			var weak_hint := str(_gates_messages().get("profile_weak_hint", "")).strip_edges()
			if not weak_hint.is_empty():
				parts.append(weak_hint)
	return " · ".join(parts)


static func build_development_investment_vectors_bbcode(
	province: Province,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if province == null:
		return ""
	var dev := province.development_level
	var infra := province.infrastructure
	var factory_n := 0
	if typeof(FactoryManager) != TYPE_NIL:
		factory_n = FactoryManager.get_factories_in_province(province.id).size()
	var lines: PackedStringArray = []
	if compact:
		lines.append(
			"%s  📈 Dev %d · %d factories · infra %d — industry + repairs raise dev over time.[/color]"
			% [COLOR_MUTED, dev, factory_n, infra]
		)
	else:
		lines.append("%s  📈 Raising development here[/color]" % COLOR_TECH)
		lines.append(
			"%s  Now: development %d, infrastructure %d, %d factor%s assigned.[/color]"
			% [
				COLOR_MUTED,
				dev,
				infra,
				factory_n,
				"ies" if factory_n != 1 else "y",
			]
		)
		lines.append(
			"%s  What helps (today): build/repair infrastructure, keep factories producing, stabilize occupation.[/color]"
			% COLOR_MUTED
		)
		lines.append("%s  Planned: dedicated development investment projects on the map.[/color]" % COLOR_MUTED)
	var unlock_bits: PackedStringArray = []
	if dev < 3:
		unlock_bits.append("dev 3 → shipyards & tank plants")
	if dev < 4:
		unlock_bits.append("dev 4 → aircraft factories")
	if dev < 5:
		unlock_bits.append("dev 5+ → late-era & air-heavy lines")
	if not unlock_bits.is_empty():
		lines.append("%s  → Next unlocks: %s[/color]" % [COLOR_TECH, " · ".join(unlock_bits)])
	return "\n".join(lines)


static func build_retool_reloc_guidance_bbcode(
	province: Province,
	snap: Dictionary,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if province == null or snap.is_empty():
		return ""
	var locked: Array = snap.get("locked_lines", [])
	if locked.is_empty():
		return ""
	var msgs := _gates_messages()
	var kinds := _locked_line_kind_counts(locked)
	var lines: PackedStringArray = []
	if not compact:
		lines.append("%s  ↻ Retool vs relocate[/color]" % COLOR_HEADER)
		var comparison := build_retool_reloc_comparison_bbcode(province, country_tag)
		if not comparison.is_empty():
			lines.append(comparison)
	if int(kinds.get("tech", 0)) > 0:
		lines.append(
			"%s  → %s[/color]"
			% [COLOR_TECH, str(msgs.get("retool_vs_reloc_tech", "Research first — retool/relocation won't bypass tech."))]
		)
	if int(kinds.get("development", 0)) > 0:
		var max_need := 0
		for entry_var in locked:
			var entry: Dictionary = entry_var
			if str(entry.get("kind", "")) == "development":
				max_need = maxi(max_need, int(entry.get("min_development", 0)))
		var alts := find_better_build_province_names(province, "land", max_need, country_tag, 2)
		if not alts.is_empty():
			lines.append(
				"%s  → %s[/color]"
				% [
					COLOR_WARN,
					str(msgs.get("retool_vs_reloc_dev", "Relocate to %s")) % " / ".join(alts),
				]
			)
		else:
			lines.append(
				"%s  → Invest in development here or assign simpler lines until dev rises.[/color]"
				% COLOR_WARN
			)
	if int(kinds.get("terrain", 0)) > 0:
		var domain := "naval"
		for entry_var in locked:
			var e: Dictionary = entry_var
			if str(e.get("kind", "")) == "terrain":
				domain = _design_domain(str(e.get("design_id", "")))
				break
		var alts_t := find_better_build_province_names(province, domain, 3, country_tag, 2)
		if not alts_t.is_empty():
			lines.append(
				"%s  → %s[/color]"
				% [
					COLOR_WARN,
					str(msgs.get("retool_vs_reloc_terrain", "Move to %s")) % " / ".join(alts_t),
				]
			)
		else:
			lines.append(
				"%s  → %s[/color]"
				% [COLOR_WARN, str(msgs.get("retool_vs_reloc_terrain", "Pick suitable terrain/port provinces."))]
			)
	if int(kinds.get("factory", 0)) > 0:
		lines.append(
			"%s  → %s[/color]" % [COLOR_WARN, str(msgs.get("retool_vs_reloc_factory", "Fix factory type or design."))]
		)
	if int(kinds.get("development", 0)) + int(kinds.get("terrain", 0)) > 0:
		lines.append(
			"%s  → %s[/color]"
			% [COLOR_MUTED, str(msgs.get("relocate_priority", "Relocating often beats grinding dev in poor provinces."))]
		)
	lines.append(
		"%s  → %s[/color]" % [COLOR_MUTED, str(msgs.get("retool_in_place", "Same-province design change uses Production retooling."))]
	)
	return "\n".join(lines)


static func build_design_fit_hint_plain(
	province: Province,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> String:
	return build_design_province_fit_plain(province, design_id, country_tag, factory)


static func build_design_strategic_action_plain(
	province: Province,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> String:
	if province == null:
		return ""
	var gate := evaluate_province_design_gate(province, design_id, country_tag, factory)
	if bool(gate.get("allowed", true)):
		return build_design_fit_hint_plain(province, design_id, country_tag, factory)
	var msgs := _gates_messages()
	var kind := str(gate.get("kind", "tech"))
	match kind:
		"tech":
			return str(msgs.get("retool_vs_reloc_tech", gate_action_hint(gate, province, country_tag)))
		"development":
			var alts := find_better_build_province_names(
				province,
				str(gate.get("domain", _design_domain(design_id))),
				int(gate.get("min_development", 0)),
				country_tag,
				2,
			)
			if not alts.is_empty():
				return str(msgs.get("retool_vs_reloc_dev", "")) % " / ".join(alts)
			return gate_action_hint(gate, province, country_tag)
		"terrain":
			var alts_t := find_better_build_province_names(
				province, str(gate.get("domain", "naval")), 3, country_tag, 2,
			)
			if not alts_t.is_empty():
				return str(msgs.get("retool_vs_reloc_terrain", "")) % " / ".join(alts_t)
			return gate_action_hint(gate, province, country_tag)
		"factory":
			return str(msgs.get("retool_vs_reloc_factory", gate_action_hint(gate, province, country_tag)))
		_:
			return gate_action_hint(gate, province, country_tag)


static func get_relocate_recommendation(
	province: Province,
	country_tag: String = "",
	snap: Dictionary = {},
) -> Dictionary:
	var empty := {
		"should_relocate": false,
		"should_invest_here": false,
		"primary_target": "",
		"secondary_targets": PackedStringArray(),
		"reason": "",
		"decision_line": "",
		"max_dev_need": 0,
		"domain": "land",
	}
	if province == null:
		return empty
	if snap.is_empty():
		snap = collect_province_build_eligibility(province, country_tag)
	var locked: Array = snap.get("locked_lines", [])
	if locked.is_empty():
		return empty
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(province)
	var kinds := _locked_line_kind_counts(locked)
	var max_need := 0
	var domain := "land"
	for entry_var in locked:
		var entry: Dictionary = entry_var
		var kind := str(entry.get("kind", ""))
		if kind == "development":
			max_need = maxi(max_need, int(entry.get("min_development", 0)))
		elif kind == "terrain":
			domain = _design_domain(str(entry.get("design_id", "")))
	empty["max_dev_need"] = max_need
	empty["domain"] = domain
	var gap := maxi(0, max_need - province.development_level)
	var factory_n := int(snap.get("factory_count", 0))
	var msgs := _gates_messages()
	var non_tech_locks := (
		int(kinds.get("development", 0))
		+ int(kinds.get("terrain", 0))
		+ int(kinds.get("factory", 0))
		+ int(kinds.get("catalog", 0))
	)
	if int(kinds.get("tech", 0)) > 0 and non_tech_locks == 0:
		empty["decision_line"] = str(msgs.get("decision_research_first", "Research first"))
		return empty
	if int(kinds.get("terrain", 0)) > 0:
		empty["should_relocate"] = true
		empty["reason"] = "terrain or port"
	elif int(kinds.get("development", 0)) > 0:
		if gap >= 2:
			empty["should_relocate"] = true
			empty["reason"] = "development gap +%d" % gap
		elif gap == 1:
			empty["should_invest_here"] = factory_n >= 2
			empty["should_relocate"] = not empty["should_invest_here"]
			empty["reason"] = "small dev gap"
		else:
			empty["should_invest_here"] = true
	elif int(kinds.get("factory", 0)) > 0:
		empty["decision_line"] = str(msgs.get("decision_retool_here", "Retool in place"))
		return empty
	var need_dev := maxi(max_need, 3 if domain == "naval" else 1)
	var alts := find_better_build_province_names(province, domain, need_dev, tag, 3)
	if not alts.is_empty():
		empty["primary_target"] = alts[0]
		for i in range(1, alts.size()):
			empty["secondary_targets"].append(alts[i])
	if empty["should_relocate"] and empty["primary_target"].is_empty():
		for entry_var in locked:
			var locked_entry: Dictionary = entry_var
			var did := str(locked_entry.get("design_id", "")).strip_edges()
			if did.is_empty():
				continue
			var best := find_best_provinces_for_design(province, did, tag, null, 2)
			if not best.is_empty():
				var name := str(best[0])
				if " (dev " in name:
					name = name.split(" (dev ")[0]
				empty["primary_target"] = name
				for i in range(1, best.size()):
					var sec := str(best[i])
					if " (dev " in sec:
						sec = sec.split(" (dev ")[0]
					if sec not in empty["secondary_targets"]:
						empty["secondary_targets"].append(sec)
				break
	if empty["should_relocate"] and not empty["primary_target"].is_empty():
		empty["decision_line"] = str(msgs.get("decision_relocate_now", "↗ Move to %s")) % empty["primary_target"]
	elif empty["should_relocate"]:
		empty["decision_line"] = str(msgs.get("decision_relocate_no_target", "↗ Relocate blocked lines"))
	elif empty["should_invest_here"] and gap > 0:
		empty["decision_line"] = str(msgs.get("decision_invest_here", "")).format({
			"gap": gap,
			"need": max_need,
		})
	elif not empty["primary_target"].is_empty():
		empty["decision_line"] = "↗ Optional: %s also fits" % empty["primary_target"]
	return empty


static func build_relocate_prominence_chip(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var rec: Dictionary = get_relocate_recommendation(province, country_tag)
	var target := str(rec.get("primary_target", "")).strip_edges()
	var should_reloc := bool(rec.get("should_relocate", false))
	if target.is_empty() and not should_reloc:
		return ""
	if target.is_empty() and should_reloc:
		target = "relocate"
	var reason := str(rec.get("reason", "")).strip_edges()
	var secondary: PackedStringArray = rec.get("secondary_targets", PackedStringArray())
	var more := ""
	if secondary.size() > 0:
		more = " +%d" % secondary.size()
	if should_reloc:
		if target == "relocate":
			return "%s↗ relocate%s[/color]" % [COLOR_WARN, more]
		if reason.is_empty():
			return "%s↗ %s%s[/color]" % [COLOR_WARN, target, more]
		if reason.length() > 14:
			reason = reason.substr(0, 12) + "…"
		return "%s↗ %s%s (%s)[/color]" % [COLOR_WARN, target, more, reason]
	return "%s↗ %s%s?[/color]" % [COLOR_MUTED, target, more]


static func build_retool_reloc_decision_bbcode(
	province: Province,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if province == null:
		return ""
	var snap := collect_province_build_eligibility(province, country_tag)
	var locked: Array = snap.get("locked_lines", [])
	if locked.is_empty():
		return ""
	var rec: Dictionary = get_relocate_recommendation(province, country_tag, snap)
	var lines: PackedStringArray = []
	var decision := str(rec.get("decision_line", "")).strip_edges()
	if decision.is_empty():
		return ""
	if compact:
		return "%s  %s[/color]" % [COLOR_TECH, decision]
	lines.append("%s  Strategic choice[/color]" % COLOR_HEADER)
	lines.append("%s  %s[/color]" % [COLOR_TECH, decision])
	if bool(rec.get("should_relocate", false)):
		lines.append(
			"%s  ↗ Relocate: assign a new design in Production (retooling downtime) at the target province.[/color]"
			% COLOR_WARN
		)
	if bool(rec.get("should_invest_here", false)):
		lines.append(
			"%s  📈 Invest here: keep factories running and raise infrastructure — dev rises over time.[/color]"
			% COLOR_OK
		)
	var secondary: PackedStringArray = rec.get("secondary_targets", PackedStringArray())
	if secondary.size() > 0:
		lines.append("%s  Also suitable: %s[/color]" % [COLOR_MUTED, " · ".join(secondary)])
	return "\n".join(lines)


static func get_next_development_unlock_label(current_dev: int) -> String:
	if current_dev < 3:
		return "shipyards & tank plants"
	if current_dev < 4:
		return "aircraft factories"
	if current_dev < 5:
		return "late-era & advanced lines"
	if current_dev < 6:
		return "modern-era production"
	return ""


static func build_development_growth_plain(province: Province) -> String:
	if province == null:
		return ""
	var dev := province.development_level
	var next_unlock := get_next_development_unlock_label(dev)
	if next_unlock.is_empty():
		return ""
	var factory_n := 0
	if typeof(FactoryManager) != TYPE_NIL:
		factory_n = FactoryManager.get_factories_in_province(province.id).size()
	return str(_gates_messages().get("development_growth_short", "")).format({
		"factories": factory_n,
		"infra": province.infrastructure,
		"next": dev + 1,
		"unlock": next_unlock,
	})


static func assess_invest_reloc_choice(
	province: Province,
	country_tag: String = "",
	snap: Dictionary = {},
	rec: Dictionary = {},
) -> Dictionary:
	var empty := {
		"primary": "none",
		"headline": "",
		"compact_summary": "",
		"invest_strength": "",
		"reloc_strength": "",
		"lines": PackedStringArray(),
	}
	if province == null:
		return empty
	if snap.is_empty():
		snap = collect_province_build_eligibility(province, country_tag)
	if (snap.get("locked_lines", []) as Array).is_empty():
		return empty
	if rec.is_empty():
		rec = get_relocate_recommendation(province, country_tag, snap)
	var msgs := _gates_messages()
	var strong := str(msgs.get("recommend_strong", "★ Recommended"))
	var viable := str(msgs.get("recommend_viable", "○ Viable alternative"))
	var max_need := int(rec.get("max_dev_need", 0))
	var gap := maxi(0, max_need - province.development_level)
	var factory_n := int(snap.get("factory_count", 0))
	var unlock := get_next_development_unlock_label(province.development_level)
	if unlock.is_empty():
		unlock = "more production tiers"
	var target: Dictionary = get_primary_relocate_target(province, country_tag)
	var target_name := str(target.get("name", ""))
	var kinds := _locked_line_kind_counts(snap.get("locked_lines", []) as Array)
	var should_reloc := bool(rec.get("should_relocate", false))
	var should_invest := bool(rec.get("should_invest_here", false))
	var reloc_reason := ""
	if int(kinds.get("terrain", 0)) > 0:
		reloc_reason = str(msgs.get("reloc_detail_terrain", ""))
	elif gap >= 2:
		reloc_reason = str(msgs.get("reloc_detail_dev", "")).format({"gap": gap})
	var invest_detail := str(msgs.get("invest_detail_short", ""))
	var invest_strong := false
	var invest_viable := false
	var reloc_strong := false
	var reloc_viable := false
	if should_reloc and should_invest:
		empty["primary"] = "split"
		reloc_strong = true
		invest_viable = true
	elif should_reloc:
		empty["primary"] = "relocate"
		reloc_strong = true
		if not target_name.is_empty():
			invest_viable = true
	elif should_invest:
		empty["primary"] = "invest"
		invest_strong = true
		if not target_name.is_empty():
			reloc_viable = true
	elif not target_name.is_empty():
		empty["primary"] = "relocate"
		reloc_viable = true
	empty["invest_strength"] = "strong" if invest_strong else ("viable" if invest_viable else "")
	empty["reloc_strength"] = "strong" if reloc_strong else ("viable" if reloc_viable else "")
	if empty["primary"] == "split":
		empty["headline"] = str(msgs.get("invest_reloc_headline_split", ""))
	elif empty["primary"] == "relocate" and not target_name.is_empty():
		empty["headline"] = str(msgs.get("invest_reloc_headline_reloc", "")).format({
			"target": target_name,
		})
	elif empty["primary"] == "invest":
		empty["headline"] = str(msgs.get("invest_reloc_headline_invest", ""))
	var lines: PackedStringArray = []
	var primary := str(empty["primary"])
	if primary in ["relocate", "split"]:
		if reloc_strong and not target_name.is_empty():
			lines.append(
				str(msgs.get("reloc_line_strong", "")).format({
					"badge": strong,
					"target": target_name,
				})
			)
			if not reloc_reason.is_empty():
				lines.append(reloc_reason)
		elif reloc_viable and not target_name.is_empty():
			lines.append(
				str(msgs.get("reloc_line_viable", "")).format({
					"badge": viable,
					"target": target_name,
				})
			)
	if invest_strong:
		lines.append(
			str(msgs.get("invest_line_strong", "")).format({
				"badge": strong,
				"gap": gap,
				"need": max_need,
				"unlock": unlock,
			})
		)
		if not invest_detail.is_empty() and gap > 0:
			lines.append(invest_detail)
	elif invest_viable:
		lines.append(
			str(msgs.get("invest_line_viable", "")).format({
				"badge": viable,
				"factories": factory_n,
				"infra": province.infrastructure,
			})
		)
	if primary == "invest" and reloc_viable and not target_name.is_empty():
		lines.append(
			str(msgs.get("reloc_line_viable", "")).format({
				"badge": viable,
				"target": target_name,
			})
		)
	empty["lines"] = lines
	var secondary := ""
	for line in lines:
		if line.begins_with("★"):
			secondary = line.strip_edges()
			break
	if secondary.is_empty():
		for line in lines:
			if line.begins_with("○"):
				secondary = line.strip_edges()
				break
	if secondary.is_empty() and lines.size() > 0:
		secondary = lines[0].strip_edges()
	if not empty["headline"].is_empty() and not secondary.is_empty():
		empty["compact_summary"] = str(msgs.get("panel_compact_summary", "{headline} · {secondary}")).format({
			"headline": empty["headline"],
			"secondary": secondary,
		})
	elif not empty["headline"].is_empty():
		empty["compact_summary"] = empty["headline"]
	return empty


static func build_invest_vs_reloc_panel_plain(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var choice: Dictionary = assess_invest_reloc_choice(province, country_tag)
	var lines: PackedStringArray = choice.get("lines", PackedStringArray())
	if lines.is_empty():
		return ""
	var out: PackedStringArray = []
	var headline := str(choice.get("headline", "")).strip_edges()
	if not headline.is_empty():
		out.append(headline)
	out.append_array(lines)
	return "\n".join(out)


static func build_invest_vs_reloc_panel_bbcode(
	province: Province,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if province == null:
		return ""
	var choice: Dictionary = assess_invest_reloc_choice(province, country_tag)
	var lines: PackedStringArray = choice.get("lines", PackedStringArray())
	if lines.is_empty():
		return ""
	var msgs := _gates_messages()
	if compact:
		var summary := str(choice.get("compact_summary", "")).strip_edges()
		if summary.is_empty():
			summary = build_invest_vs_reloc_panel_plain(province, country_tag).replace("\n", " · ")
		return "%s  %s[/color]" % [COLOR_TECH, summary]
	var block: PackedStringArray = [
		"%s  %s[/color]" % [COLOR_HEADER, str(msgs.get("comparison_header", "Invest here vs relocate"))],
	]
	var headline := str(choice.get("headline", "")).strip_edges()
	if not headline.is_empty():
		block.append("%s  %s[/color]" % [COLOR_TECH, headline])
	for line in lines:
		if line.begins_with("★") and "↗" in line:
			block.append("%s  %s[/color]" % [COLOR_WARN, line])
		elif line.begins_with("★") and "↻" in line:
			block.append("%s  %s[/color]" % [COLOR_OK, line])
		elif line.begins_with("○") and "↗" in line:
			block.append("%s  %s[/color]" % [COLOR_WARN, line])
		elif line.begins_with("○") and "↻" in line:
			block.append("%s  %s[/color]" % [COLOR_MUTED, line])
		elif line.begins_with("—"):
			block.append("%s  %s[/color]" % [COLOR_MUTED, line])
		else:
			block.append("%s  %s[/color]" % [COLOR_MUTED, line])
	return "\n".join(block)


static func build_development_context_plain(
	province: Province,
	multiline: bool = false,
) -> String:
	if province == null or province.development_level >= 5:
		return ""
	var msgs := _gates_messages()
	var parts: PackedStringArray = []
	var long_term := str(msgs.get("development_long_term", "")).strip_edges()
	if not long_term.is_empty():
		parts.append(long_term)
	var unlock := get_next_development_unlock_label(province.development_level)
	if not unlock.is_empty():
		parts.append(
			str(msgs.get("development_unlock_ladder", "")).format({
				"cur": province.development_level,
				"next": province.development_level + 1,
				"unlock": unlock,
			})
		)
	var growth := build_development_picker_hint_plain(province)
	if growth.is_empty():
		growth = build_development_growth_plain(province)
	if not growth.is_empty() and growth not in " ".join(parts):
		parts.append(growth)
	if parts.is_empty():
		return ""
	return "\n".join(parts) if multiline else " · ".join(parts)


static func build_development_context_bbcode(
	province: Province,
	compact: bool = true,
) -> String:
	var plain := build_development_context_plain(province, not compact)
	if plain.is_empty():
		return ""
	if compact:
		var one_line := build_development_context_plain(province, false)
		return "%s  📈 %s[/color]" % [COLOR_TECH, one_line]
	plain = build_development_context_plain(province, true)
	if plain.is_empty():
		return ""
	var msgs := _gates_messages()
	var lines: PackedStringArray = [
		"%s  %s[/color]"
		% [COLOR_HEADER, str(msgs.get("development_section_header", "Development"))],
	]
	for part in plain.split("\n", false):
		var p := part.strip_edges()
		if p.is_empty():
			continue
		if p.begins_with("Unlock ladder"):
			lines.append("%s  %s[/color]" % [COLOR_TECH, p])
		else:
			lines.append("%s  %s[/color]" % [COLOR_MUTED, p])
	return "\n".join(lines)


static func build_development_long_term_plain(province: Province) -> String:
	return build_development_context_plain(province, false)


static func build_development_picker_hint_plain(province: Province) -> String:
	if province == null or province.development_level >= 5:
		return ""
	var unlock := get_next_development_unlock_label(province.development_level)
	if unlock.is_empty():
		return ""
	var factory_n := 0
	if typeof(FactoryManager) != TYPE_NIL:
		factory_n = FactoryManager.get_factories_in_province(province.id).size()
	return str(_gates_messages().get("development_picker_hint", "")).format({
		"cur": province.development_level,
		"factories": factory_n,
		"infra": province.infrastructure,
		"next": province.development_level + 1,
		"unlock": unlock,
	})


static func build_retool_reloc_comparison_plain(
	province: Province,
	country_tag: String = "",
) -> String:
	var panel := build_invest_vs_reloc_panel_plain(province, country_tag)
	if not panel.is_empty():
		return panel
	if province == null:
		return ""
	var snap := collect_province_build_eligibility(province, country_tag)
	if (snap.get("locked_lines", []) as Array).is_empty():
		return ""
	var rec: Dictionary = get_relocate_recommendation(province, country_tag, snap)
	var msgs := _gates_messages()
	var target: Dictionary = get_primary_relocate_target(province, country_tag)
	var target_name := str(target.get("name", "another province"))
	if target_name.is_empty():
		target_name = "a higher-dev province"
	var factory_n := int(snap.get("factory_count", 0))
	var retool := str(msgs.get("retool_if", "")).format({"factories": factory_n})
	var reloc := str(msgs.get("relocate_if", "")).format({"target": target_name})
	if retool.is_empty() and reloc.is_empty():
		return ""
	return "↻ %s  ·  ↗ %s" % [retool, reloc]


static func build_development_growth_playbook_bbcode(
	province: Province,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if province == null:
		return ""
	var msgs := _gates_messages()
	var dev := province.development_level
	var infra := province.infrastructure
	var factory_n := 0
	if typeof(FactoryManager) != TYPE_NIL:
		factory_n = FactoryManager.get_factories_in_province(province.id).size()
	var lines: PackedStringArray = []
	var next_unlock := get_next_development_unlock_label(dev)
	if compact:
		if not next_unlock.is_empty():
			lines.append(
				"%s  📈 Dev %d→%d: %s · grow via %d factories + infra %d[/color]"
				% [COLOR_TECH, dev, dev + 1, next_unlock, factory_n, infra]
			)
		else:
			lines.append(
				"%s  📈 Dev %d · %d factories · infra %d[/color]"
				% [COLOR_MUTED, dev, factory_n, infra]
			)
	else:
		lines.append("%s  📈 Development growth (this province)[/color]" % COLOR_HEADER)
		lines.append("%s  %s[/color]" % [COLOR_MUTED, str(msgs.get("dev_growth_factories", ""))])
		lines.append("%s  %s[/color]" % [COLOR_MUTED, str(msgs.get("dev_growth_infra", ""))])
		lines.append("%s  %s[/color]" % [COLOR_MUTED, _development_investment_hint()])
	if not next_unlock.is_empty():
		lines.append(
			"%s  → %s[/color]"
			% [
				COLOR_TECH,
				str(msgs.get("next_dev_unlock", "At development {next}: unlock {unlock}")).format({
					"next": dev + 1,
					"unlock": next_unlock,
				}),
			]
		)
	var unlock_bits: PackedStringArray = []
	if dev < 3:
		unlock_bits.append("dev 3 → shipyards & tank plants")
	if dev < 4:
		unlock_bits.append("dev 4 → aircraft factories")
	if dev < 5:
		unlock_bits.append("dev 5+ → late-era production")
	if not compact and not unlock_bits.is_empty():
		lines.append("%s  → Full ladder: %s[/color]" % [COLOR_MUTED, " · ".join(unlock_bits)])
	return "\n".join(lines)


static func build_retool_reloc_comparison_bbcode(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var snap := collect_province_build_eligibility(province, country_tag)
	if (snap.get("locked_lines", []) as Array).is_empty():
		return ""
	var panel := build_invest_vs_reloc_panel_bbcode(province, country_tag, false)
	if not panel.is_empty():
		return panel
	var rec: Dictionary = get_relocate_recommendation(province, country_tag, snap)
	var msgs := _gates_messages()
	var target: Dictionary = get_primary_relocate_target(province, country_tag)
	var target_name := str(target.get("name", "another province"))
	if target_name.is_empty():
		target_name = "a higher-dev province"
	var factory_n := int(snap.get("factory_count", 0))
	var lines: PackedStringArray = []
	lines.append("%s  ↻ vs ↗[/color]" % COLOR_HEADER)
	lines.append(
		"%s  %s[/color]"
		% [COLOR_OK, str(msgs.get("retool_if", "")).format({
			"factories": factory_n,
		})]
	)
	lines.append(
		"%s  %s[/color]"
		% [COLOR_WARN, str(msgs.get("relocate_if", "")).format({"target": target_name})]
	)
	return "\n".join(lines)


static func build_province_production_profile_chip(province: Province) -> String:
	if province == null:
		return ""
	var profile: Dictionary = assess_province_production_profile(province)
	var good: PackedStringArray = profile.get("good", PackedStringArray())
	var weak: PackedStringArray = profile.get("weak", PackedStringArray())
	if good.is_empty() and weak.is_empty():
		return ""
	var msgs := _gates_messages()
	var parts: PackedStringArray = []
	if not good.is_empty():
		var g_short := PackedStringArray()
		for g in good:
			g_short.append(str(g).split(" ")[0])
		parts.append(
			str(msgs.get("profile_chip_good", "✓ {items}")).format({"items": ",".join(g_short)})
		)
	if not weak.is_empty():
		var w_short := PackedStringArray()
		for w in weak:
			w_short.append(str(w).split("(")[0].strip_edges())
		parts.append(
			str(msgs.get("profile_chip_weak", "✗ {items}")).format({"items": ",".join(w_short)})
		)
	return "%s%s[/color]" % [COLOR_TECH, " ".join(parts)]


static func evaluate_design_province_fit(
	province: Province,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> Dictionary:
	var out := {
		"rating": "good",
		"label": "✓ Strong fit",
		"relocate_target": "",
		"summary": "",
	}
	if province == null or design_id.strip_edges().is_empty():
		return out
	var gate := evaluate_province_design_gate(province, design_id, country_tag, factory)
	if not bool(gate.get("allowed", true)):
		out["rating"] = "blocked"
		var kind := str(gate.get("kind", "tech"))
		out["label"] = "%s Blocked" % _lock_kind_icon(kind)
		out["summary"] = gate_short_label(gate)
		var g_domain := str(gate.get("domain", _design_domain(design_id)))
		var g_need := int(gate.get("min_development", min_development_for_design(design_id, factory.factory_type if factory else "")))
		if kind in ["development", "terrain", "factory"]:
			var alts_gate := find_best_provinces_for_design(province, design_id, country_tag, factory, 2)
			if alts_gate.is_empty():
				alts_gate = find_better_build_province_names(province, g_domain, g_need, country_tag, 2)
			if not alts_gate.is_empty():
				out["relocate_target"] = alts_gate[0]
				var msgs := _gates_messages()
				var tmpl := str(msgs.get("blocked_relocate_to", "Blocked here — run at {target} instead"))
				out["summary"] = tmpl.format({"target": alts_gate[0]})
		elif kind == "tech":
			out["summary"] = gate_short_label(gate) + " — " + str(
				_gates_messages().get("decision_research_first", "research first")
			)
		return out
	var domain := _design_domain(design_id)
	var profile: Dictionary = assess_province_production_profile(province)
	var weak: PackedStringArray = profile.get("weak", PackedStringArray())
	var good: PackedStringArray = profile.get("good", PackedStringArray())
	for w in weak:
		var ws := str(w).to_lower()
		if domain in ws or (domain == "land" and "land" in ws):
			out["rating"] = "poor"
			out["label"] = "✗ Weak here"
			var alts := find_best_provinces_for_design(province, design_id, country_tag, factory, 1)
			if alts.is_empty():
				alts = find_better_build_province_names(
					province,
					domain,
					min_development_for_design(design_id, factory.factory_type if factory else ""),
					country_tag,
					1,
				)
			if not alts.is_empty():
				out["relocate_target"] = alts[0]
				out["summary"] = "Better at %s" % alts[0]
			else:
				out["summary"] = "Poor for %s in this province" % domain
			return out
	for g in good:
		if domain in str(g).to_lower():
			out["rating"] = "good"
			out["label"] = "✓ Strong fit"
			out["summary"] = "Ideal for %s" % domain
			return out
	out["rating"] = "fair"
	out["label"] = "◐ Acceptable"
	out["summary"] = "Can run %s here" % domain
	var alts_fair := find_best_provinces_for_design(province, design_id, country_tag, factory, 1)
	if alts_fair.is_empty():
		alts_fair = find_better_build_province_names(
			province,
			domain,
			min_development_for_design(design_id, factory.factory_type if factory else ""),
			country_tag,
			1,
		)
	if not alts_fair.is_empty():
		var alt_name := str(alts_fair[0])
		if " (dev " in alt_name:
			alt_name = alt_name.split(" (dev ")[0]
		if alt_name != province.name:
			out["relocate_target"] = alt_name
			out["summary"] = "OK here · stronger at %s" % alt_name
	return out


static func build_design_province_fit_plain(
	province: Province,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> String:
	var fit: Dictionary = evaluate_design_province_fit(province, design_id, country_tag, factory)
	var parts: PackedStringArray = [str(fit.get("label", ""))]
	var summary := str(fit.get("summary", "")).strip_edges()
	if not summary.is_empty():
		parts.append(summary)
	var reloc := str(fit.get("relocate_target", "")).strip_edges()
	if not reloc.is_empty():
		parts.append("↗ " + reloc)
	var rating := str(fit.get("rating", ""))
	if rating in ["blocked", "poor", "fair"] and province != null:
		var act := build_production_action_plain(province, design_id, country_tag, factory)
		if not act.is_empty() and act not in " · ".join(parts):
			parts.append("Do: " + act)
	return " · ".join(parts)


static func build_province_build_strategic_tooltip_bbcode(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var snap := collect_province_build_eligibility(province, country_tag)
	if not bool(snap.get("has_factories", false)) or not bool(snap.get("owned", false)):
		return ""
	var lines: PackedStringArray = []
	var invest_panel := build_invest_vs_reloc_panel_bbcode(province, country_tag, false)
	if not invest_panel.is_empty():
		lines.append(invest_panel)
	else:
		var decision := build_retool_reloc_decision_bbcode(province, country_tag, true)
		if not decision.is_empty():
			lines.append(decision)
	var dev_ctx := build_development_context_bbcode(province, false)
	if not dev_ctx.is_empty():
		lines.append(dev_ctx)
	var profile := build_province_production_profile_bbcode(province, country_tag, true)
	if not profile.is_empty():
		lines.append(profile)
	var focus_link := build_relocate_focus_link_bbcode(province, country_tag)
	if not focus_link.is_empty():
		lines.append(focus_link)
	return "\n".join(lines)


static func build_relocate_focus_link_bbcode(
	province: Province,
	country_tag: String = "",
	design_id: String = "",
) -> String:
	if province == null:
		return ""
	var target: Dictionary = get_primary_relocate_target(province, country_tag, design_id)
	var pid := int(target.get("province_id", -1))
	var name := str(target.get("name", "")).strip_edges()
	if pid < 0 or name.is_empty():
		return ""
	return "%s  [url=focus_province:%d]↗ Focus %s on map[/url][/color]" % [COLOR_TECH, pid, name]


static func build_development_tier_chip(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var dev := province.development_level
	if dev >= 5:
		return ""
	var next_unlock := get_next_development_unlock_label(dev)
	if next_unlock.is_empty():
		return ""
	var msgs := _gates_messages()
	var tmpl := str(msgs.get("dev_tier_chip", "dev {cur}→{next}: {unlock}"))
	return "%s📈 %s[/color]" % [
		COLOR_WARN if dev < 3 else COLOR_MUTED,
		tmpl.format({"cur": dev, "next": dev + 1, "unlock": next_unlock}),
	]


static func build_retool_reloc_split_chip(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var rec: Dictionary = get_relocate_recommendation(province, country_tag)
	if not bool(rec.get("should_invest_here", false)):
		return ""
	var target := str(rec.get("primary_target", "")).strip_edges()
	if target.is_empty():
		return ""
	var msgs := _gates_messages()
	var choice: Dictionary = assess_invest_reloc_choice(province, country_tag)
	var summary := str(choice.get("compact_summary", "")).strip_edges()
	if not summary.is_empty():
		if summary.length() > 42:
			summary = summary.substr(0, 40) + "…"
		return "%s%s[/color]" % [COLOR_TECH, summary]
	var text := str(msgs.get("decision_split_retool_reloc", "↻ here · ↗ {target}")).format({
		"target": normalize_relocate_label(target),
	})
	return "%s%s[/color]" % [COLOR_TECH, text]


static func build_invest_reloc_choice_chip(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var choice: Dictionary = assess_invest_reloc_choice(province, country_tag)
	var summary := str(choice.get("compact_summary", "")).strip_edges()
	if summary.is_empty():
		return ""
	var primary := str(choice.get("primary", ""))
	var color := COLOR_WARN if primary in ["relocate", "split"] else COLOR_TECH
	if summary.length() > 36:
		summary = summary.substr(0, 34) + "…"
	if "★" not in summary:
		return "%s★ %s[/color]" % [color, summary]
	return "%s%s[/color]" % [color, summary]


static func build_design_picker_province_banner_plain(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var lines: PackedStringArray = []
	var snap := collect_province_build_eligibility(province, country_tag)
	var locked: Array = snap.get("locked_lines", [])
	var invest_reloc := build_invest_vs_reloc_panel_plain(province, country_tag)
	if not invest_reloc.is_empty():
		lines.append("Strategic:\n" + invest_reloc)
	elif locked.is_empty():
		var decision := str(
			get_relocate_recommendation(province, country_tag, snap).get("decision_line", "")
		).strip_edges()
		if not decision.is_empty():
			lines.append("Strategic: " + decision)
	var dev_banner := build_development_context_plain(province, true)
	if not dev_banner.is_empty():
		lines.append("Development:\n" + dev_banner.replace(" · ", "\n"))
	elif province.development_level < 5 and locked.is_empty():
		var hint := str(_gates_messages().get("development_unlocks_production", "")).strip_edges()
		if not hint.is_empty():
			lines.append("Development: " + hint)
	var profile := build_province_production_profile_plain(province)
	if not profile.is_empty():
		lines.append("Province fit: " + profile)
	if locked.is_empty() and invest_reloc.is_empty():
		var playbook_short := build_development_growth_playbook_bbcode(province, country_tag, true)
		if not playbook_short.is_empty():
			lines.append(
				playbook_short.strip_edges().replace("[color=#6ec8ff]", "").replace("[/color]", "")
			)
	return "\n".join(lines)


static func build_design_row_recommendation_plain(
	province: Province,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> String:
	if province == null or design_id.strip_edges().is_empty():
		return ""
	var gate := evaluate_province_design_gate(province, design_id, country_tag, factory)
	if bool(gate.get("allowed", true)):
		return ""
	var choice: Dictionary = assess_invest_reloc_choice(province, country_tag)
	var target: Dictionary = get_primary_relocate_target(province, country_tag, design_id)
	var target_name := str(target.get("name", ""))
	var primary := str(choice.get("primary", ""))
	if primary in ["relocate", "split"] and not target_name.is_empty():
		if str(choice.get("reloc_strength", "")) == "strong":
			return "★ ↗ %s" % target_name
		return "○ ↗ %s" % target_name
	if primary == "invest":
		if str(choice.get("invest_strength", "")) == "strong":
			return "★ ↻ invest here"
		return "○ ↻ invest here"
	return ""


static func build_build_eligibility_glance_bbcode(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var snap := collect_province_build_eligibility(province, country_tag)
	if not bool(snap.get("has_factories", false)) or not bool(snap.get("owned", false)):
		return ""
	var parts: PackedStringArray = []
	var chip := build_build_eligibility_hover_chip(province, country_tag)
	if not chip.is_empty():
		parts.append(chip)
	var reloc_chip := build_relocate_prominence_chip(province, country_tag)
	if not reloc_chip.is_empty() and (reloc_chip not in chip):
		parts.append(reloc_chip)
	var profile_chip := build_province_production_profile_chip(province)
	if not profile_chip.is_empty():
		parts.append(profile_chip)
	elif not build_province_production_profile_bbcode(province, country_tag, true).is_empty():
		parts.append(build_province_production_profile_bbcode(province, country_tag, true))
	return " · ".join(parts) if parts.size() > 0 else ""


static func build_province_development_build_guide_bbcode(
	province: Province,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if province == null:
		return ""
	var dev := province.development_level
	var terrain := str(province.terrain).strip_edges().to_lower()
	var lines: PackedStringArray = []
	if compact:
		lines.append(
			"%s  📉 Development %d sets build tiers (naval 3+, air 4+, modern 5+).[/color]"
			% [COLOR_MUTED, dev]
		)
	else:
		lines.append("%s  📉 How development affects builds[/color]" % COLOR_TECH)
		lines.append(
			"%s  Level %d here — gates era/domain lines and factory types (see province_build_gates).[/color]"
			% [COLOR_MUTED, dev]
		)
		var gates := _ensure_province_build_gates()
		var dev_rules: Dictionary = gates.get("development", {}) as Dictionary
		var era_map: Dictionary = dev_rules.get("min_by_era", {}) as Dictionary
		var era_bits: PackedStringArray = []
		for era_key in ["ww2", "early_cold_war", "modern"]:
			if era_map.has(era_key):
				era_bits.append("%s→dev %d" % [era_key, int(era_map[era_key])])
		if not era_bits.is_empty():
			lines.append("%s  Era thresholds: %s[/color]" % [COLOR_MUTED, " · ".join(era_bits)])
		var bonus := _terrain_development_bonus(terrain, "land")
		if bonus > 0:
			lines.append(
				"%s  %s terrain adds +%d effective dev requirement for some domains.[/color]"
				% [COLOR_WARN, terrain.capitalize(), bonus]
			)
	var vectors := build_development_investment_vectors_bbcode(province, country_tag, compact)
	if not vectors.is_empty():
		lines.append(vectors)
	elif not compact:
		lines.append("%s  → %s[/color]" % [COLOR_TECH, _development_investment_hint()])
	return "\n".join(lines)


static func build_eligibility_next_steps_bbcode(
	province: Province,
	snap: Dictionary,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if snap.is_empty() or province == null:
		return ""
	var locked: Array = snap.get("locked_lines", [])
	var lines: PackedStringArray = []
	var blocking: PackedStringArray = snap.get("blocking_techs", PackedStringArray())
	if blocking.size() > 0:
		if compact:
			lines.append(
				"%s  → Research: %s (Technology screen)[/color]"
				% [COLOR_TECH, " · ".join(blocking)]
			)
		else:
			lines.append("%s  → Priority research: %s[/color]" % [COLOR_TECH, " · ".join(blocking)])
	var kinds := _locked_line_kind_counts(locked)
	if int(kinds.get("development", 0)) > 0:
		var max_need := 0
		for entry_var in locked:
			var entry: Dictionary = entry_var
			if str(entry.get("kind", "")) != "development":
				continue
			max_need = maxi(max_need, int(entry.get("min_development", 0)))
		var gap := maxi(0, max_need - province.development_level)
		var dev_hint := "Raise development here (+{gap} to reach {need})".format({
			"gap": gap,
			"need": max_need,
		})
		var alts := find_better_build_province_names(province, "land", max_need, country_tag, 2)
		if not alts.is_empty():
			dev_hint += ", or move lines to %s" % " / ".join(alts)
		lines.append("%s  → %s[/color]" % [COLOR_WARN, dev_hint])
	if int(kinds.get("terrain", 0)) > 0:
		var domain := "naval"
		for entry_var in locked:
			var e: Dictionary = entry_var
			if str(e.get("kind", "")) == "terrain":
				domain = _design_domain(str(e.get("design_id", "")))
				break
		var alts_t := find_better_build_province_names(province, domain, 3, country_tag, 2)
		if not alts_t.is_empty():
			lines.append(
				"%s  → Terrain: reassign to %s (coastal/port for naval).[/color]"
				% [COLOR_WARN, " / ".join(alts_t)]
			)
		else:
			lines.append(
				"%s  → Terrain: use plains, urban, or coastal provinces with ports for blocked domains.[/color]"
				% COLOR_WARN
			)
	if int(kinds.get("factory", 0)) > 0:
		lines.append(
			"%s  → Factory: retool plant type or pick a design this factory supports (Production screen).[/color]"
			% COLOR_WARN
		)
	if int(kinds.get("development", 0)) + int(kinds.get("terrain", 0)) > 0:
		lines.append(
			"%s  → Relocate blocked lines via Design Picker when another province is a better fit.[/color]"
			% COLOR_MUTED
		)
	if lines.is_empty() and not bool(snap.get("all_current_clear", true)):
		lines.append("%s  → Open Design Picker for per-line lock details.[/color]" % COLOR_MUTED)
	return "\n".join(lines)


static func format_actionable_lock_hint(entry: Dictionary, province: Province, country_tag: String) -> String:
	var kind := str(entry.get("kind", "tech"))
	var action := str(entry.get("action", "")).strip_edges()
	var tech := str(entry.get("tech_name", "")).strip_edges()
	match kind:
		"tech":
			if not tech.is_empty():
				return "Research %s on the Technology screen." % tech
			if not action.is_empty():
				return action
			return "Complete required technology research."
		"development":
			var need := int(entry.get("min_development", 0))
			var have := province.development_level if province != null else 0
			var gap := maxi(0, need - have)
			var hint := "Need dev %d (have %d) — build industry & infrastructure here" % [need, have]
			if gap > 0:
				hint += " (+%d)" % gap
			var alts := find_better_build_province_names(
				province, _design_domain(str(entry.get("design_id", ""))), need, country_tag, 2,
			)
			if not alts.is_empty():
				hint += ", or move line to %s" % " / ".join(alts)
			return hint
		"terrain":
			if not action.is_empty():
				return action
			return "Reassign to a province with suitable terrain or port access."
		"factory":
			if not action.is_empty():
				return action
			return "Use a compatible factory type in a suitable province."
		_:
			return action if not action.is_empty() else str(entry.get("reason", ""))


static func build_province_environment_summary(province: Province) -> PackedStringArray:
	var lines: PackedStringArray = []
	if province == null:
		return lines
	var terrain := str(province.terrain).strip_edges().to_lower()
	var dev := province.development_level
	lines.append(
		"%s  Development %d · %s%s[/color]"
		% [
			COLOR_MUTED,
			dev,
			terrain.capitalize(),
			" · port" if province.resolve_has_port() else "",
		]
	)
	var limits: PackedStringArray = []
	if dev < 4:
		limits.append("air/modern lines need higher dev")
	if dev < 3:
		limits.append("shipyards/tank plants need dev 3+")
	var gates := _ensure_province_build_gates()
	var blocked_domains: Dictionary = (
		gates.get("terrain", {}).get("blocked_domains", {}) as Dictionary
	)
	if blocked_domains.has(terrain):
		var blocked: Array = blocked_domains[terrain] as Array
		if not blocked.is_empty():
			limits.append("%s blocks %s" % [terrain, ", ".join(blocked)])
	if province.is_sea:
		limits.append("sea — naval only")
	if not limits.is_empty():
		lines.append("%s  Strategic limits: %s[/color]" % [COLOR_MUTED, " · ".join(limits)])
	return lines


static func is_design_buildable_in_province(province_id: int, design_id: String, country_tag: String = "") -> bool:
	if typeof(MapManager) == TYPE_NIL:
		return true
	var province := _province_for_id(province_id)
	if province == null:
		return false
	var gate := evaluate_province_design_gate(province, design_id, country_tag, null)
	return bool(gate.get("allowed", true))


static func get_province_build_lock_reason(
	province_id: int,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> String:
	var province := _province_for_id(province_id)
	if province == null:
		return ""
	var gate := evaluate_province_design_gate(province, design_id, country_tag, factory)
	if bool(gate.get("allowed", true)):
		return ""
	return gate_short_label(gate)


static func get_province_build_lock_action(
	province_id: int,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> String:
	var province := _province_for_id(province_id)
	if province == null:
		return ""
	var gate := evaluate_province_design_gate(province, design_id, country_tag, factory)
	if bool(gate.get("allowed", true)):
		return ""
	return gate_action_hint(gate, province, country_tag)


static func build_design_picker_gate_bbcode(
	province_id: int,
	design_id: String,
	country_tag: String = "",
	factory: Factory = null,
) -> String:
	var province := _province_for_id(province_id)
	if province == null or design_id.strip_edges().is_empty():
		return ""
	var gate := evaluate_province_design_gate(province, design_id, country_tag, factory)
	if bool(gate.get("allowed", true)):
		return ""
	var icon := _lock_kind_icon(str(gate.get("kind", "tech")))
	var lines: PackedStringArray = [
		"%s%s %s[/color]" % [COLOR_WARN, icon, gate_short_label(gate)],
		"%s  %s[/color]" % [COLOR_MUTED, str(gate.get("reason", ""))],
	]
	var action := gate_action_hint(gate, province, country_tag)
	if not action.is_empty():
		lines.append("%s  → %s[/color]" % [COLOR_TECH, action])
	var dev := province.development_level
	lines.append(
		"%s  Province: dev %d · %s%s[/color]"
		% [
			COLOR_MUTED,
			dev,
			str(province.terrain).capitalize(),
			" · port" if province.resolve_has_port() else "",
		]
	)
	return "\n".join(lines)


static func collect_province_build_eligibility(
	province: Province,
	country_tag: String = "",
) -> Dictionary:
	var empty := {
		"owned": false,
		"has_factories": false,
		"factory_count": 0,
		"locked_lines": [],
		"factory_type_blocks": [],
		"blocking_techs": PackedStringArray(),
		"unlocked_factory_types": PackedStringArray(),
		"all_current_clear": true,
		"province_name": "",
		"development_level": 0,
		"terrain": "",
		"has_port": false,
		"dev_pressure": false,
		"terrain_pressure": false,
	}
	if province == null:
		return empty
	empty["province_name"] = province.name
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(province)
	empty["owned"] = _province_owned_by(province, tag)
	empty["development_level"] = province.development_level
	empty["terrain"] = str(province.terrain).strip_edges().to_lower()
	empty["has_port"] = province.resolve_has_port()
	if typeof(FactoryManager) == TYPE_NIL:
		return empty
	var factories := FactoryManager.get_factories_in_province(province.id)
	empty["factory_count"] = factories.size()
	empty["has_factories"] = not factories.is_empty()
	if factories.is_empty() or tag.is_empty():
		return empty
	if typeof(TechnologyManager) != TYPE_NIL:
		for ft in TechnologyManager.get_unlocked_factory_types(tag):
			var s := str(ft).strip_edges()
			if not s.is_empty() and s not in empty["unlocked_factory_types"]:
				empty["unlocked_factory_types"].append(s)
	var blocking_set: Dictionary = {}
	for factory in factories:
		if factory == null:
			continue
		var tid := str(factory.current_production_design).strip_edges()
		if tid.is_empty():
			continue
		var label := _design_display_name(tid)
		var gate := evaluate_province_design_gate(province, tid, tag, factory)
		if bool(gate.get("allowed", true)):
			continue
		empty["all_current_clear"] = false
		var kind := str(gate.get("kind", "tech"))
		var reason := str(gate.get("reason", "Locked")).strip_edges()
		var tech_name := ""
		if kind == "tech" and typeof(TechnologyManager) != TYPE_NIL:
			var avail := TechnologyManager.get_design_availability(tag, tid)
			tech_name = str(avail.get("tech_name", "")).strip_edges()
			if not tech_name.is_empty():
				blocking_set[tech_name] = true
		if kind == "development":
			empty["dev_pressure"] = true
		if kind == "terrain":
			empty["terrain_pressure"] = true
		if kind == "factory":
			empty["factory_type_blocks"].append({
				"design_id": tid,
				"label": label,
				"reason": reason,
				"factory_type": factory.factory_type,
				"kind": kind,
			})
		empty["locked_lines"].append({
			"design_id": tid,
			"label": label,
			"reason": reason,
			"tech_name": tech_name,
			"factory_type": factory.factory_type,
			"kind": kind,
			"action": str(gate.get("action", "")),
			"min_development": int(gate.get("min_development", 0)),
		})
	for key in blocking_set.keys():
		empty["blocking_techs"].append(str(key))
	empty["blocking_techs"].sort()
	return empty


static func build_province_build_eligibility_bbcode(
	province: Province,
	country_tag: String = "",
	compact: bool = true,
) -> String:
	if province == null:
		return ""
	var snap := collect_province_build_eligibility(province, country_tag)
	if not bool(snap.get("has_factories", false)):
		return ""
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(province)
	var owned := bool(snap.get("owned", false))
	var lines: PackedStringArray = [build_eligibility_section_header()]
	if not owned:
		lines.append(
			"%s  Not your province — factory gates shown for reference only.[/color]" % COLOR_MUTED
		)
		return "\n".join(lines)
	var n_factories := int(snap.get("factory_count", 0))
	var types: PackedStringArray = snap.get("unlocked_factory_types", PackedStringArray())
	if compact:
		lines.append("%s  %d factor%s in province[/color]" % [
			COLOR_MUTED,
			n_factories,
			"s" if n_factories != 1 else "y",
		])
	else:
		lines.append("%s  %d factor%s · assign designs from the production screen[/color]" % [
			COLOR_MUTED,
			n_factories,
			"s" if n_factories != 1 else "y",
		])
	if not types.is_empty():
		var type_line := ", ".join(types)
		if compact:
			lines.append("%s  Unlocked types: %s[/color]" % [COLOR_MUTED, type_line])
		else:
			lines.append("%s  National factory unlocks: %s[/color]" % [COLOR_TECH, type_line])
	for env_line in build_province_environment_summary(province):
		lines.append(env_line)
	var profile := build_province_production_profile_bbcode(province, tag, compact)
	if not profile.is_empty():
		lines.append(profile)
	var dev_guide := build_province_development_build_guide_bbcode(province, tag, compact)
	if not dev_guide.is_empty() and (not compact or int(snap.get("development_level", 0)) < 5):
		lines.append(dev_guide)
	if not compact:
		var vectors := build_development_investment_vectors_bbcode(province, tag, false)
		if not vectors.is_empty():
			lines.append(vectors)
	var locked: Array = snap.get("locked_lines", [])
	if locked.is_empty():
		lines.append("%s  Current lines: no locks (tech, dev, or terrain)[/color]" % COLOR_OK)
		var growth := build_development_growth_playbook_bbcode(province, tag, compact)
		if not growth.is_empty():
			lines.append(growth)
		lines.append(
			"%s  → Scout new designs: match province strengths above before assigning lines.[/color]"
			% COLOR_MUTED
		)
		return "\n".join(lines)
	var actions := build_province_build_actions_bbcode(province, tag, compact)
	if not actions.is_empty():
		lines.append(actions)
	if not compact:
		var playbook := build_development_growth_playbook_bbcode(province, tag, false)
		if not playbook.is_empty() and playbook not in actions:
			lines.append(playbook)
	var split := build_retool_reloc_split_chip(province, tag)
	if not split.is_empty() and compact:
		lines.append(split)
	var retool_sec := build_retool_reloc_guidance_bbcode(province, snap, tag, compact)
	if not retool_sec.is_empty() and not compact:
		lines.append(retool_sec)
	var show_max := 3 if compact else 6
	for i in range(mini(locked.size(), show_max)):
		var entry: Dictionary = locked[i]
		lines.append(_format_locked_line_bbcode(entry, compact, province, tag))
	if locked.size() > show_max:
		lines.append("%s  … +%d more locked line(s)[/color]" % [COLOR_MUTED, locked.size() - show_max])
	return "\n".join(lines)


static func _locked_line_kind_counts(locked: Array) -> Dictionary:
	var counts := {"development": 0, "terrain": 0, "tech": 0, "factory": 0, "catalog": 0}
	for entry_var in locked:
		var entry: Dictionary = entry_var
		var kind := str(entry.get("kind", ""))
		if counts.has(kind):
			counts[kind] = int(counts[kind]) + 1
	return counts


static func _lock_kind_icon(kind: String) -> String:
	match kind:
		"development":
			return "📉"
		"terrain":
			return "🏔"
		"factory":
			return "🏭"
		"catalog":
			return "🌐"
		_:
			return "🔒"


static func _format_locked_line_bbcode(
	entry: Dictionary,
	compact: bool,
	province: Province = null,
	country_tag: String = "",
) -> String:
	var label := str(entry.get("label", entry.get("design_id", "")))
	var reason := str(entry.get("reason", "")).strip_edges()
	var tech := str(entry.get("tech_name", "")).strip_edges()
	var ftype := str(entry.get("factory_type", "standard"))
	var kind := str(entry.get("kind", "tech"))
	var icon := _lock_kind_icon(kind)
	var hint := format_actionable_lock_hint(entry, province, country_tag)
	if compact:
		var gate := tech if not tech.is_empty() else reason
		if kind == "development":
			gate = "dev %d" % int(entry.get("min_development", 0))
		elif kind == "terrain":
			gate = reason.split("—")[0].strip_edges() if "—" in reason else reason
		var line := "%s  %s %s — %s (%s)[/color]" % [COLOR_WARN, icon, label, gate, ftype]
		if not hint.is_empty():
			line += "\n%s    → %s[/color]" % [COLOR_TECH, hint]
		var did_c := str(entry.get("design_id", "")).strip_edges()
		if not did_c.is_empty() and province != null:
			var pact := build_production_action_plain(province, did_c, country_tag)
			if not pact.is_empty():
				line += "\n%s    → %s[/color]" % [COLOR_MUTED, pact]
		return line
	if kind == "factory":
		var block := "%s  %s %s — %s[/color]\n%s    %s factory[/color]" % [
			COLOR_WARN, icon, label, reason, COLOR_MUTED, ftype.replace("_", " "),
		]
		if not hint.is_empty():
			block += "\n%s    → %s[/color]" % [COLOR_TECH, hint]
		return block
	var headline := tech if not tech.is_empty() else kind
	if kind == "development":
		headline = "development %d required" % int(entry.get("min_development", 0))
	elif kind == "terrain":
		headline = "terrain / geography"
	var block := "%s  %s %s — %s[/color]\n%s    %s[/color]" % [
		COLOR_WARN, icon, label, headline, COLOR_MUTED, reason,
	]
	if not hint.is_empty():
		block += "\n%s    → %s[/color]" % [COLOR_TECH, hint]
	var did := str(entry.get("design_id", "")).strip_edges()
	if not did.is_empty() and province != null:
		var prod_act := build_production_action_plain(province, did, country_tag)
		if not prod_act.is_empty():
			block += "\n%s    → %s[/color]" % [COLOR_MUTED, prod_act]
	return block


static func build_province_build_eligibility_inspector_section(
	province: Province,
	country_tag: String = "",
) -> String:
	var body := build_province_build_eligibility_bbcode(province, country_tag, false)
	var panel := build_invest_vs_reloc_panel_bbcode(province, country_tag, false)
	var dev_ctx := build_development_context_bbcode(province, false)
	var parts: PackedStringArray = []
	if not body.is_empty():
		parts.append(body)
	if not panel.is_empty():
		parts.append(panel)
	if not dev_ctx.is_empty() and dev_ctx not in body and dev_ctx not in panel:
		parts.append(dev_ctx)
	return "\n".join(parts)


static func build_build_eligibility_hover_chip(
	province: Province,
	country_tag: String = "",
) -> String:
	if province == null:
		return ""
	var snap := collect_province_build_eligibility(province, country_tag)
	if not bool(snap.get("has_factories", false)):
		return ""
	if not bool(snap.get("owned", false)):
		return ""
	var locked: Array = snap.get("locked_lines", [])
	if locked.is_empty():
		var n := int(snap.get("factory_count", 0))
		var dev := int(snap.get("development_level", 0))
		if bool(snap.get("terrain_pressure", false)):
			return "%s🏔 terrain OK[/color]" % COLOR_MUTED
		if dev < 4:
			return "%s📉 dev %d tier[/color]" % [COLOR_WARN, dev]
		return "%s🏭 %d OK[/color]" % [COLOR_OK, n]
	var kinds := _locked_line_kind_counts(locked)
	var parts: PackedStringArray = []
	if int(kinds.get("development", 0)) > 0:
		parts.append("📉%d" % kinds["development"])
	if int(kinds.get("terrain", 0)) > 0:
		parts.append("🏔%d" % kinds["terrain"])
	if int(kinds.get("tech", 0)) > 0:
		parts.append("🔒%d" % kinds["tech"])
	if int(kinds.get("factory", 0)) > 0:
		parts.append("🏭%d" % kinds["factory"])
	if parts.is_empty():
		return "%s🔒 %d locked[/color]" % [COLOR_WARN, locked.size()]
	var reloc := build_relocate_prominence_chip(province, country_tag)
	if not reloc.is_empty():
		return "%s%s · %s lock[/color]" % [COLOR_WARN, _bbcode_inner(reloc), " ".join(parts)]
	return "%s%s lock[/color]" % [COLOR_WARN, " ".join(parts)]


static func _bbcode_inner(bbcode_line: String) -> String:
	var s := bbcode_line.strip_edges()
	var start := s.find("]")
	if start < 0:
		return s
	var end := s.rfind("[")
	if end <= start:
		return s.substr(start + 1)
	return s.substr(start + 1, end - start - 1).strip_edges()


static func build_factory_picker_context_plain(factory: Factory, country_tag: String = "") -> String:
	if factory == null:
		return ""
	var tag := country_tag.strip_edges().to_upper()
	var parts: PackedStringArray = []
	var pid := factory.province_id
	if typeof(MapManager) != TYPE_NIL and pid > 0:
		var p: Province = MapManager.get_province(pid)
		if p != null:
			parts.append("%s (#%d)" % [p.name, p.id])
	parts.append("%s factory" % factory.factory_type.replace("_", " "))
	if factory.current_damage > 0.0:
		parts.append("%.0f%% damage" % factory.current_damage)
	var tid := str(factory.current_production_design).strip_edges()
	if not tid.is_empty():
		parts.append("line: %s" % _design_display_name(tid))
	if not tid.is_empty():
		var fit := evaluate_design_province_fit(
			_province_for_id(pid) if pid > 0 else null, tid, tag, factory,
		)
		var fit_summary := str(fit.get("summary", "")).strip_edges()
		if not fit_summary.is_empty():
			parts.append("%s %s" % [str(fit.get("label", "")), fit_summary])
	if not tid.is_empty() and typeof(MapManager) != TYPE_NIL:
		var prov_gate := _province_for_id(pid)
		if prov_gate != null:
			var gate := evaluate_province_design_gate(prov_gate, tid, tag, factory)
			if not bool(gate.get("allowed", true)):
				parts.append(gate_short_label(gate))
	if typeof(MapManager) != TYPE_NIL and pid > 0:
		var prov: Province = MapManager.get_province(pid)
		if prov != null:
			var rec: Dictionary = get_relocate_recommendation(prov, tag)
			var decision := str(rec.get("decision_line", "")).strip_edges()
			if not decision.is_empty():
				parts.append(decision)
			elif not build_province_production_profile_plain(prov).is_empty():
				parts.append(build_province_production_profile_plain(prov))
			var snap := collect_province_build_eligibility(prov, tag)
			var locked: Array = snap.get("locked_lines", [])
			if locked.size() > 1:
				parts.append("%d province locks" % locked.size())
			if factory != null and factory.is_retooling:
				parts.append("retooling in progress")
	return " · ".join(parts)


static func build_factory_picker_context_bbcode(factory: Factory, country_tag: String = "") -> String:
	var plain := build_factory_picker_context_plain(factory, country_tag)
	if plain.is_empty():
		return ""
	return "%s%s[/color]" % [COLOR_MUTED, plain]


static func _design_display_name(design_id: String) -> String:
	var tid := design_id.strip_edges()
	if tid.is_empty():
		return ""
	if GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(tid)
		if template != null and not template.display_name.is_empty():
			return template.display_name
	return tid.replace("_", " ")
