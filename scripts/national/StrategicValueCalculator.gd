# scripts/national/StrategicValueCalculator.gd
## Strategic Utility Units (SUU) — unified deal valuation for Trade & Relations.
class_name StrategicValueCalculator
extends RefCounted

const RULES_PATH := "res://data/trade/strategic_value_rules.json"

static var _rules: Dictionary = {}
static var _loaded: bool = false


static func get_rules() -> Dictionary:
	_load()
	return _rules


static func reload() -> void:
	_loaded = false
	_rules = {}
	_load()


static func scarcity_multiplier(have: float) -> float:
	_load()
	var s: Dictionary = _rules.get("scarcity", {}) as Dictionary if _rules.get("scarcity") is Dictionary else {}
	if have < float(s.get("empty_below", 20.0)):
		return float(s.get("empty_mult", 1.35))
	if have < float(s.get("tight_below", 50.0)):
		return float(s.get("tight_mult", 1.15))
	if have > float(s.get("ample_above", 200.0)):
		return float(s.get("ample_mult", 0.9))
	return 1.0


static func resource_suu(resource_id: String, quantity: float, stockpile: Dictionary = {}) -> float:
	_load()
	var rid := resource_id.strip_edges().to_lower()
	if rid in ["oil", "petroleum"]:
		rid = "fuel"
	var rates: Dictionary = _rules.get("resource_base_suu", {}) as Dictionary if _rules.get("resource_base_suu") is Dictionary else {}
	var base := float(rates.get(rid, 1.0))
	var crit: Dictionary = _rules.get("critical_resource_suu_weight", {}) as Dictionary if _rules.get("critical_resource_suu_weight") is Dictionary else {}
	if crit.has(rid):
		base *= float(crit[rid])
	var have := float(stockpile.get(rid, stockpile.get(resource_id, 0.0)))
	return snappedf(base * scarcity_multiplier(have) * maxf(quantity, 0.0), 0.01)


static func equipment_suu(production_cost: float, quantity: float = 1.0) -> float:
	_load()
	var per := float(_rules.get("equipment_suu_per_production_cost", 1.0))
	var fallback := float(_rules.get("equipment_fallback_suu", 80.0))
	var unit := production_cost if production_cost > 0.0 else fallback
	return snappedf(unit * per * maxf(quantity, 0.0), 0.01)


static func design_suu(production_cost: float, quality_mod: float = 1.0, tech_gap_years: float = 0.0) -> float:
	_load()
	var gap_p := float(_rules.get("design_tech_gap_premium_per_year", 0.08))
	var max_p := float(_rules.get("design_max_gap_premium", 2.5))
	var premium := clampf(1.0 + maxf(tech_gap_years, 0.0) * gap_p, 1.0, max_p)
	var base := production_cost if production_cost > 0.0 else 150.0
	return snappedf(base * clampf(quality_mod, 0.5, 1.5) * premium, 0.01)


static func tech_share_suu(quantity: float = 1.0) -> float:
	_load()
	return snappedf(float(_rules.get("tech_share_base_suu", 120.0)) * maxf(quantity, 0.0), 0.01)


static func intel_suu(quantity: float = 1.0) -> float:
	_load()
	return snappedf(float(_rules.get("intel_base_suu", 60.0)) * maxf(quantity, 0.0), 0.01)


static func province_suu(
	dev: float = 0.0,
	infra: float = 0.0,
	has_port: bool = false,
	resource_score: float = 0.0,
	factory_count: int = 0,
	is_choke: bool = false,
	is_core: bool = false,
) -> float:
	_load()
	var p: Dictionary = _rules.get("province", {}) as Dictionary if _rules.get("province") is Dictionary else {}
	var v := float(p.get("base", 400.0))
	v += float(dev) * float(p.get("per_dev", 25.0))
	v += float(infra) * float(p.get("per_infra", 20.0))
	if has_port:
		v += float(p.get("port_bonus", 350.0))
	v += float(resource_score) * float(p.get("resource_score_scale", 0.15))
	v += float(factory_count) * float(p.get("factory_bonus", 120.0))
	if is_choke:
		v += float(p.get("choke_bonus", 500.0))
	if is_core:
		v *= float(p.get("core_multiplier", 1.75))
	v *= float(p.get("durable_premium", 3.5))
	return snappedf(v, 0.01)


static func docking_suu(months: float = 12.0, major_port: bool = false) -> float:
	_load()
	var d: Dictionary = _rules.get("docking_rights", {}) as Dictionary if _rules.get("docking_rights") is Dictionary else {}
	var v := float(d.get("base_per_month", 18.0)) * maxf(months, 1.0)
	if major_port:
		v *= float(d.get("major_port_mult", 2.0))
	v *= float(d.get("sovereignty_premium", 1.4))
	return snappedf(v, 0.01)


static func military_access_suu(months: float = 12.0) -> float:
	_load()
	var d: Dictionary = _rules.get("military_access", {}) as Dictionary if _rules.get("military_access") is Dictionary else {}
	return snappedf(float(d.get("base_per_month", 12.0)) * maxf(months, 1.0), 0.01)


static func tariff_multiplier(rate: float) -> float:
	## Import tariff raises effective SUU cost of goods for importer.
	return 1.0 + clampf(rate, 0.0, 0.5)


static func acceptance_ratio(value_received: float, value_given: float) -> float:
	if value_given <= 0.001:
		return 99.0 if value_received > 0.0 else 1.0
	return value_received / value_given


static func relation_accept_multiplier(band_id: String) -> float:
	_load()
	var m: Dictionary = _rules.get("relation_accept_mult", {}) as Dictionary if _rules.get("relation_accept_mult") is Dictionary else {}
	return float(m.get(band_id, 1.0))


static func classify_acceptance(ratio: float) -> String:
	_load()
	var a: Dictionary = _rules.get("acceptance", {}) as Dictionary if _rules.get("acceptance") is Dictionary else {}
	if ratio < float(a.get("refuse_below", 0.85)):
		return "refuse"
	if ratio < float(a.get("fair_high", 1.05)):
		return "fair"
	return "generous"


static func compare_asset_classes() -> Dictionary:
	## Design-intent comparisons for dual/UI (order-of-magnitude education).
	_load()
	var c: Dictionary = _rules.get("comparisons", {}) as Dictionary if _rules.get("comparisons") is Dictionary else {}
	var tank := float(c.get("medium_tank_batch_hint_suu", 110.0))
	var fighter := float(c.get("fighter_hint_suu", 180.0))
	var peri := float(c.get("peripheral_province_hint_suu", 3500.0))
	var core := float(c.get("core_port_province_hint_suu", 12000.0))
	var dock := docking_suu(12.0, true)
	return {
		"medium_tank_suu": tank,
		"fighter_suu": fighter,
		"docking_12m_major_suu": dock,
		"peripheral_province_suu": peri,
		"core_port_province_suu": core,
		"province_over_tank": peri > tank * 10.0,
		"core_over_fighter": core > fighter * 20.0,
		"notes": str(c.get("notes", "")),
	}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_rules = {}
	if not FileAccess.file_exists(RULES_PATH):
		return
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	if f == null:
		return
	var p := JSON.new()
	if p.parse(f.get_as_text()) == OK and typeof(p.data) == TYPE_DICTIONARY:
		_rules = p.data
