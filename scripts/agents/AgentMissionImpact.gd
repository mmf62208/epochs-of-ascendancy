# scripts/agents/AgentMissionImpact.gd
class_name AgentMissionImpact
extends RefCounted

## Human-readable mission outcome / preview text for agent UI.


static func describe_outcome_result(result: Dictionary) -> String:
	if result.is_empty():
		return "No significant effect."

	var parts: PackedStringArray = []
	var description := str(result.get("description", "")).strip_edges()
	if not description.is_empty():
		parts.append(description)

	var prestige := int(result.get("prestige_gain", 0))
	if prestige > 0:
		parts.append("+%d national prestige" % prestige)

	var intel_type := str(result.get("intel_type", "")).strip_edges()
	var outcome_key := str(result.get("_outcome_key", ""))
	if not intel_type.is_empty() and outcome_key in ["success", "partial"]:
		var intel_gain := 10 if outcome_key == "success" else 4
		parts.append("+%d %s intel (reports)" % [intel_gain, intel_type])

	var effect := str(result.get("effect", "")).strip_edges()
	var magnitude := float(result.get("magnitude", 0.0))
	if not effect.is_empty():
		parts.append(_format_effect_label(effect, magnitude))

	if parts.is_empty():
		return "Outcome recorded."
	if parts.size() == 1:
		return parts[0]
	return parts[0] + " · " + " · ".join(parts.slice(1))


static func describe_mission_outcome(mission: Dictionary, outcome_key: String) -> String:
	var outcomes: Dictionary = mission.get("outcomes", {})
	var result: Variant = outcomes.get(outcome_key, {})
	if typeof(result) != TYPE_DICTIONARY:
		return "No significant effect."
	var result_dict := (result as Dictionary).duplicate()
	result_dict["_outcome_key"] = outcome_key
	return describe_outcome_result(result_dict)


static func get_impact_preview(mission: Dictionary) -> Dictionary:
	return {
		"success": describe_mission_outcome(mission, "success"),
		"partial": describe_mission_outcome(mission, "partial"),
		"failure": describe_mission_outcome(mission, "failure"),
	}


static func format_compact_preview(preview: Dictionary) -> String:
	var lines: PackedStringArray = []
	if preview.has("success"):
		lines.append("✓ %s" % preview.get("success", ""))
	if preview.has("partial"):
		lines.append("◐ %s" % preview.get("partial", ""))
	if preview.has("failure"):
		lines.append("✗ %s" % preview.get("failure", ""))
	return "\n".join(lines)


static func _format_effect_label(effect: String, magnitude: float) -> String:
	match effect:
		"production_delay":
			return "~%.0f%% production disruption on target" % (magnitude * 100.0)
		"supply_disruption":
			return "~%.0f%% supply throughput reduction on target" % (magnitude * 100.0)
		"stability_damage":
			return "~%.0f stability pressure on target" % magnitude
		"research_progress":
			return "~%.0f research progress stolen" % magnitude
		"long_term_tech_intel":
			return "Long-term technology intel source"
		"production_boost":
			return "+%.0f%% production output/speed boost" % (magnitude * 100.0)
		"resource_discovery":
			return "+%.0f%% resource output / exploration gain" % (magnitude * 100.0)
		"temporary_intel_bonus":
			return "Temporary intel network bonus (+%.0f)" % magnitude
		"enemy_agent_disruption":
			return "Enemy agent network disrupted"
		"enemy_intel_degradation":
			return "Enemy intel quality degraded"
		"tech_theft_protection":
			return "Counter-intel: tech theft protection"
		"inclusion_leverage":
			return "+%.0f Inclusion Leverage at the peace table (major diplomatic win)" % magnitude
		"minister_compromised":
			return "Key minister compromised — strong influence on conference terms"
		"narrative_shift":
			return "Public/elite narrative shifted (%.0f influence on grievance & legitimacy)" % magnitude
		"bargaining_leverage":
			return "+%.0f bargaining leverage from leaked positions" % magnitude
		"enemy_leverage_blocked":
			return "Enemy conference influence operations blocked (%.0f leverage denied)" % magnitude
		"grievance_backlash":
			return "Grievance backlash (+%.0f) — failed attempt hardened opposition" % magnitude
		"scandal_backlash":
			return "Scandal backlash — operation exposure damaged position"
		"term_modifier":
			return "Direct term influence applied (%.0f weight toward favorable outcome)" % magnitude
		_:
			if magnitude > 0.0:
				return "%s (%.2f)" % [effect.replace("_", " "), magnitude]
			return effect.replace("_", " ").capitalize()
