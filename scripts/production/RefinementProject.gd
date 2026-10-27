class_name RefinementProject
extends RefCounted

var id: String = ""
var display_name: String = ""
var category: String = "refinement"
var template_id: String = ""
var days_total: float = 0.0
var days_elapsed: float = 0.0
var reliability_gain: float = 0.0
var maturity_gain: float = 0.0
var maintenance_reduction: float = 0.0
var cost: Dictionary = {}
var blocks_production: bool = false
var production_penalty: float = 0.0
var max_completions: int = 1
var tradeoff_summary: String = ""


static func from_def(def: Dictionary, for_template_id: String) -> RefinementProject:
	var project := RefinementProject.new()
	project.id = str(def.get("id", ""))
	project.display_name = str(def.get("name", project.id))
	project.category = str(def.get("category", "refinement"))
	project.template_id = for_template_id
	project.days_total = float(def.get("days", 1))
	project.reliability_gain = float(def.get("reliability_gain", 0))
	project.maturity_gain = float(def.get("maturity_gain", 0))
	project.maintenance_reduction = float(def.get("maintenance_reduction", 0))
	project.cost = _dict_from_variant(def.get("cost", {}))
	project.blocks_production = bool(def.get("blocks_production", false))
	project.production_penalty = float(def.get("production_penalty", 0.0))
	project.max_completions = int(def.get("max_completions", 1))
	project.tradeoff_summary = str(def.get("tradeoff_summary", ""))
	return project


func to_save_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"category": category,
		"template_id": template_id,
		"days_total": days_total,
		"days_elapsed": days_elapsed,
		"reliability_gain": reliability_gain,
		"maturity_gain": maturity_gain,
		"maintenance_reduction": maintenance_reduction,
		"cost": cost.duplicate(true),
		"blocks_production": blocks_production,
		"production_penalty": production_penalty,
		"max_completions": max_completions,
		"tradeoff_summary": tradeoff_summary,
	}


static func from_save_dict(data: Dictionary) -> RefinementProject:
	var project := RefinementProject.new()
	project.id = str(data.get("id", ""))
	project.display_name = str(data.get("display_name", project.id))
	project.category = str(data.get("category", "refinement"))
	project.template_id = str(data.get("template_id", ""))
	project.days_total = float(data.get("days_total", 0.0))
	project.days_elapsed = float(data.get("days_elapsed", 0.0))
	project.reliability_gain = float(data.get("reliability_gain", 0.0))
	project.maturity_gain = float(data.get("maturity_gain", 0.0))
	project.maintenance_reduction = float(data.get("maintenance_reduction", 0.0))
	project.cost = _dict_from_variant(data.get("cost", {}))
	project.blocks_production = bool(data.get("blocks_production", false))
	project.production_penalty = float(data.get("production_penalty", 0.0))
	project.max_completions = int(data.get("max_completions", 1))
	project.tradeoff_summary = str(data.get("tradeoff_summary", ""))
	return project


func advance(days: float) -> void:
	days_elapsed = minf(days_elapsed + days, days_total)


func is_complete() -> bool:
	return days_elapsed >= days_total - 0.001


func progress_ratio() -> float:
	if days_total <= 0.0:
		return 1.0
	return clampf(days_elapsed / days_total, 0.0, 1.0)


static func _dict_from_variant(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw.duplicate(true)
