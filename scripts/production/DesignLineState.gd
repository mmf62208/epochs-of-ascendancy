class_name DesignLineState
extends RefCounted

## Per-design memory on a production line (tooling, maturity, refinement).

var template_id: String = ""
var tooling_efficiency: float = 0.0
var reliability_refinement_bonus: float = 0.0
## 0.0 = brand-new design, 1.0 = fully shaken down / field-proven.
var design_maturity: float = 0.0
## Multiplier on maintenance costs; reduced by refinement projects (lower is better).
var maintenance_burden_multiplier: float = 1.0
var maturity_from_projects: float = 0.0
var units_produced: int = 0
var days_on_design: float = 0.0
var completed_refinements: Dictionary = {}


func get_refinement_completions(project_id: String) -> int:
	return int(completed_refinements.get(project_id, 0))


func record_refinement_completion(project_id: String) -> void:
	completed_refinements[project_id] = get_refinement_completions(project_id) + 1


func to_save_dict() -> Dictionary:
	return {
		"template_id": template_id,
		"tooling_efficiency": tooling_efficiency,
		"reliability_refinement_bonus": reliability_refinement_bonus,
		"design_maturity": design_maturity,
		"maintenance_burden_multiplier": maintenance_burden_multiplier,
		"maturity_from_projects": maturity_from_projects,
		"units_produced": units_produced,
		"days_on_design": days_on_design,
		"completed_refinements": completed_refinements.duplicate(true),
	}


static func from_save_dict(data: Dictionary) -> DesignLineState:
	var state := DesignLineState.new()
	state.template_id = str(data.get("template_id", ""))
	state.tooling_efficiency = float(data.get("tooling_efficiency", 0.0))
	state.reliability_refinement_bonus = float(data.get("reliability_refinement_bonus", 0.0))
	state.design_maturity = float(data.get("design_maturity", 0.0))
	state.maintenance_burden_multiplier = float(data.get("maintenance_burden_multiplier", 1.0))
	state.maturity_from_projects = float(data.get("maturity_from_projects", 0.0))
	state.units_produced = int(data.get("units_produced", 0))
	state.days_on_design = float(data.get("days_on_design", 0.0))
	var done: Variant = data.get("completed_refinements", {})
	if done is Dictionary:
		state.completed_refinements = (done as Dictionary).duplicate(true)
	return state


func duplicate_state() -> DesignLineState:
	var copy := DesignLineState.new()
	copy.template_id = template_id
	copy.tooling_efficiency = tooling_efficiency
	copy.reliability_refinement_bonus = reliability_refinement_bonus
	copy.design_maturity = design_maturity
	copy.maintenance_burden_multiplier = maintenance_burden_multiplier
	copy.maturity_from_projects = maturity_from_projects
	copy.units_produced = units_produced
	copy.days_on_design = days_on_design
	copy.completed_refinements = completed_refinements.duplicate()
	return copy
