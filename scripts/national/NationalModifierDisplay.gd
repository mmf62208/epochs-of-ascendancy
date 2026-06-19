# scripts/national/NationalModifierDisplay.gd
class_name NationalModifierDisplay
extends RefCounted

## Shared formatting and tooltip copy for national spirits / modifier UI.

const MODIFIER_HELP: Dictionary = {
	"production_speed": "Factory production speed for this nation.",
	"factory_output": "Output per military factory.",
	"army_org_factor": "Army organization and cohesion in combat.",
	"planning_speed": "Speed of battle plan preparation.",
	"supply_consumption": "Supply used by fielded forces (lower is better).",
	"trade_opinion": "Trade deal willingness from other nations.",
	"manpower_factor": "Recruitable manpower pool size.",
	"training_time": "Time to train new divisions (lower is faster).",
	"defence_factor": "Defensive combat strength.",
	"surrender_limit": "National surrender threshold (higher holds longer).",
	"stability": "National stability — unrest and compliance.",
	"prestige_gain": "Prestige from operations and diplomacy.",
	"consumer_goods": "Civilian goods factories dedicated to needs (higher = more strain).",
	# Recent tech expansions (minimal high-impact wiring)
	"production_flexibility": "Production retool speed and custom/field fab efficiency (layered additive manufacturing).",
	"infantry_enhancement": "Enhanced infantry performance from cybernetics/prosthetics.",
	"soldier_enhancement": "Super-soldier quality from human genetic enhancement.",
	"manpower_replacement": "Artificial/cloned manpower pool/reinforce boost (cloning tech).",
	"defensive_shielding": "Energy barrier protection for units/space habs (deflector shields).",
	"energy_weapon_dmg": "Directed energy/phaser damage bonus.",
	"rapid_deployment": "Instant teleport/rapid deployment logistics (matter transporters).",
	"detection_range": "Advanced multi-spectral scanner/sensor awareness.",
	"ethics_risk": "Increased research ethics backlash/cohesion hit risk (biotech/CB/sonic).",
}


static func modifier_help(key: String) -> String:
	var normalized := key.strip_edges().to_lower()
	if MODIFIER_HELP.has(normalized):
		return str(MODIFIER_HELP[normalized])
	return "National modifier: %s." % key.replace("_", " ")


static func modifier_lines_detailed(modifiers: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key in modifiers.keys():
		var value := float(modifiers[key])
		rows.append({
			"key": str(key),
			"label": _modifier_key_label(str(key)),
			"value_text": _format_modifier_value(value),
			"tooltip": "%s\nCurrent: %s" % [modifier_help(str(key)), _format_modifier_value(value)],
			"is_positive": _is_positive_modifier(str(key), value),
		})
	return rows


static func build_spirit_tooltip(row: Dictionary) -> String:
	var lines: PackedStringArray = [
		str(row.get("name", "Spirit")),
		str(row.get("description", "")),
		"",
		"Category: %s" % str(row.get("category", "")).capitalize(),
		"Permanent national spirit.",
	]
	for detail in row.get("modifier_details", []) as Array:
		if typeof(detail) != TYPE_DICTIONARY:
			continue
		lines.append("• %s: %s" % [detail.get("label", ""), detail.get("value_text", "")])
	return "\n".join(lines).strip_edges()


static func build_effect_tooltip(row: Dictionary) -> String:
	var remaining := int(row.get("remaining_months", 0))
	var duration := int(row.get("duration_months", 0))
	var lines: PackedStringArray = [
		str(row.get("source_label", "Effect")),
		"Temporary national modifier.",
		"Duration: %d / %d months remaining." % [remaining, maxi(duration, remaining)],
	]
	if bool(row.get("is_debuff", false)):
		lines.append("Type: Debuff (negative pressure).")
	else:
		lines.append("Type: Buff or prestige bonus.")
	lines.append("")
	for detail in row.get("modifier_details", []) as Array:
		if typeof(detail) != TYPE_DICTIONARY:
			continue
		var d := detail as Dictionary
		lines.append("• %s: %s" % [d.get("label", ""), d.get("value_text", "")])
		lines.append("  %s" % d.get("tooltip", ""))
	return "\n".join(lines).strip_edges()


static func duration_progress(remaining_months: int, duration_months: int) -> float:
	var total := maxi(duration_months, 1)
	return clampf(float(remaining_months) / float(total), 0.0, 1.0)


static func _modifier_key_label(key: String) -> String:
	return key.replace("_", " ").capitalize()


static func _format_modifier_value(value: float) -> String:
	if absf(value) < 1.0 and value != 0.0:
		return "%+.0f%%" % (value * 100.0)
	return "%+.1f" % value


static func _is_positive_modifier(key: String, value: float) -> bool:
	var inverted_keys := ["supply_consumption", "training_time", "consumer_goods"]
	if key in inverted_keys:
		return value < 0.0
	return value >= 0.0
