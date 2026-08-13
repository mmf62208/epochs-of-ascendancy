class_name ProductionModifier
extends RefCounted

## A single global production effect (focus, doctrine, national spirit, etc.).

var id: String = ""
var source: String = ""
var output_multiplier: float = 1.0
var reliability_multiplier: float = 1.0
var reliability_flat_bonus: float = 0.0
var retooling_days_multiplier: float = 1.0
var tooling_gain_multiplier: float = 1.0
var new_design_experience_rate_multiplier: float = 1.0
var cost_multiplier: float = 1.0
var tags: Array[String] = []


static func from_dict(data: Dictionary) -> ProductionModifier:
	var mod := ProductionModifier.new()
	mod.id = str(data.get("id", ""))
	mod.source = str(data.get("source", mod.id))
	mod.output_multiplier = float(data.get("output_multiplier", 1.0))
	mod.reliability_multiplier = float(data.get("reliability_multiplier", 1.0))
	mod.reliability_flat_bonus = float(data.get("reliability_flat_bonus", 0.0))
	mod.retooling_days_multiplier = float(data.get("retooling_days_multiplier", 1.0))
	mod.tooling_gain_multiplier = float(data.get("tooling_gain_multiplier", 1.0))
	mod.new_design_experience_rate_multiplier = float(data.get("new_design_experience_rate_multiplier", 1.0))
	mod.cost_multiplier = float(data.get("cost_multiplier", 1.0))
	mod.tags = _string_array(data.get("tags", []))
	return mod


func to_dict() -> Dictionary:
	return {
		"id": id,
		"source": source,
		"output_multiplier": output_multiplier,
		"reliability_multiplier": reliability_multiplier,
		"reliability_flat_bonus": reliability_flat_bonus,
		"retooling_days_multiplier": retooling_days_multiplier,
		"tooling_gain_multiplier": tooling_gain_multiplier,
		"new_design_experience_rate_multiplier": new_design_experience_rate_multiplier,
		"cost_multiplier": cost_multiplier,
		"tags": tags.duplicate(),
	}


static func _string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		out.append(str(item))
	return out
