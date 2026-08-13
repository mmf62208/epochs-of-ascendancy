# scripts/national/NationalPowerCalculator.gd
## National power index + nuclear danger class + matchup labels (hopelessly outmatched).
class_name NationalPowerCalculator
extends RefCounted

const RULES_PATH := "res://data/diplomacy/national_power_rules.json"

static var _rules: Dictionary = {}
static var _loaded: bool = false


static func get_rules() -> Dictionary:
	_load()
	return _rules


static func reload() -> void:
	_loaded = false
	_rules = {}
	_load()


## inputs: {
##   factories, steel, fuel, electronics, equipment_units, tech_flags: Array,
##   trade_capacity, naval_ports, fissiles_stock
## }
static func compute_power_index(inputs: Dictionary) -> Dictionary:
	_load()
	var w: Dictionary = _rules.get("weights", {}) as Dictionary if _rules.get("weights") is Dictionary else {}
	var factories := float(inputs.get("factories", 0))
	var steel := float(inputs.get("steel", 0))
	var fuel := float(inputs.get("fuel", 0))
	var elec := float(inputs.get("electronics", 0))
	var equip := float(inputs.get("equipment_units", 0))
	var trade_cap := float(inputs.get("trade_capacity", 0))
	var ports := float(inputs.get("naval_ports", 0))
	var fiss := float(inputs.get("fissiles_stock", 0))
	var flags: Array = inputs.get("tech_flags", []) as Array if inputs.get("tech_flags") is Array else []

	var conventional := 0.0
	conventional += factories * float(w.get("factories", 12.0))
	conventional += steel * float(w.get("steel_stock_scale", 0.02))
	conventional += fuel * float(w.get("fuel_stock_scale", 0.015))
	conventional += elec * float(w.get("electronics_stock_scale", 0.04))
	conventional += equip * float(w.get("equipment_units_scale", 0.08))
	conventional += float(flags.size()) * float(w.get("tech_flags_scale", 8.0))
	conventional += ports * float(w.get("naval_basing_scale", 15.0))
	conventional += trade_cap * float(w.get("trade_capacity_scale", 0.5))

	# Space power (orbital fleets, bombardment, defenses) — feeds diplomacy/threat like soft nuclear class
	var space_power := float(inputs.get("space_power_index", 0.0))
	if space_power <= 0.0:
		# Allow raw components if index not precomputed
		space_power = (
			float(inputs.get("space_fleet_strength", 0.0))
			+ float(inputs.get("orbital_weapons", 0.0)) * 40.0
			+ float(inputs.get("bombardment_ships", 0.0)) * 25.0
			+ float(inputs.get("orbital_defenses", 0.0)) * 18.0
			+ float(inputs.get("space_stations", 0.0)) * 15.0
		)
	conventional += space_power * float(w.get("space_power_scale", 1.0))

	var nuke: Dictionary = _rules.get("nuclear", {}) as Dictionary if _rules.get("nuclear") is Dictionary else {}
	var nuclear_score := 0.0
	var has_nuke_flag := "nuclear_fuel" in flags or "nuclear_propulsion" in flags or "nuclear_warhead" in flags
	if fiss > 0.0:
		nuclear_score += float(nuke.get("has_fissiles_stock_bonus", 80.0))
	if "nuclear_fuel" in flags:
		nuclear_score += float(nuke.get("has_nuclear_fuel_flag_bonus", 120.0))
	if "nuclear_warhead" in flags or "strategic_nuclear" in flags:
		nuclear_score += float(nuke.get("has_warhead_program_flag_bonus", 200.0))
	if "nuclear_propulsion" in flags:
		nuclear_score += float(nuke.get("has_nuclear_propulsion_flag_bonus", 40.0))

	var danger_mult := float(nuke.get("danger_multiplier_min", 1.0))
	if nuclear_score >= 200.0:
		danger_mult = float(nuke.get("danger_multiplier_full_triad", 5.0))
	elif nuclear_score >= 80.0 or has_nuke_flag:
		danger_mult = float(nuke.get("danger_multiplier_with_arsenal", 3.5))

	# Orbital bombardment asymmetry: attacker has space strike, defender has no orbital defenses
	var st: Dictionary = _rules.get("space_threat", {}) as Dictionary if _rules.get("space_threat") is Dictionary else {}
	var bomb_ships := float(inputs.get("bombardment_ships", inputs.get("bombardment_capable_ships", 0.0)))
	var orb_def := float(inputs.get("orbital_defenses", 0.0))
	var space_asym := bomb_ships > 0.0 and orb_def < 1.0
	var space_threat_add := 0.0
	if space_asym:
		space_threat_add = space_power * float(w.get("space_bombardment_threat_scale", 0.35)) * float(st.get("undefended_surface_mult", 2.0))

	var total := conventional + nuclear_score
	var effective_threat := conventional * danger_mult + nuclear_score + space_threat_add
	return {
		"conventional": snappedf(conventional, 0.1),
		"nuclear_score": snappedf(nuclear_score, 0.1),
		"nuclear_armed": nuclear_score >= 80.0 or has_nuke_flag,
		"space_power_index": snappedf(space_power, 0.1),
		"space_bombardment_asymmetry": space_asym,
		"danger_multiplier": danger_mult,
		"power_index": snappedf(total, 0.1),
		"effective_threat": snappedf(effective_threat, 0.1),
	}


static func matchup(self_power: Dictionary, other_power: Dictionary) -> Dictionary:
	_load()
	var m: Dictionary = _rules.get("matchup", {}) as Dictionary if _rules.get("matchup") is Dictionary else {}
	var self_t := maxf(float(self_power.get("effective_threat", self_power.get("power_index", 1.0))), 1.0)
	var other_t := maxf(float(other_power.get("effective_threat", other_power.get("power_index", 1.0))), 1.0)
	var ratio := self_t / other_t
	var label := "peer"
	var hopeless := false
	var outmatched := false
	if ratio < float(m.get("hopeless_ratio", 0.22)):
		label = "hopelessly_outmatched"
		hopeless = true
		outmatched = true
	elif ratio < float(m.get("outmatched_ratio", 0.45)):
		label = "outmatched"
		outmatched = true
	elif ratio < float(m.get("contested_ratio", 0.75)):
		label = "contested"
	elif ratio <= float(m.get("peer_ratio", 1.15)):
		label = "peer"
	else:
		label = "dominant"
	return {
		"ratio": snappedf(ratio, 0.01),
		"label": label,
		"hopeless": hopeless,
		"outmatched": outmatched,
		"self_threat": self_t,
		"other_threat": other_t,
		"other_nuclear": bool(other_power.get("nuclear_armed", false)),
		"self_nuclear": bool(self_power.get("nuclear_armed", false)),
		"nuclear_asymmetry": bool(other_power.get("nuclear_armed", false)) and not bool(self_power.get("nuclear_armed", false)),
	}


## AI accept floor adjustment: weaker / non-nuclear vs nuclear powers placate more.
static func ai_placate_accept_floor_delta(matchup_info: Dictionary) -> float:
	_load()
	var ap: Dictionary = _rules.get("ai_placate", {}) as Dictionary if _rules.get("ai_placate") is Dictionary else {}
	var delta := 0.0
	if bool(matchup_info.get("hopeless", false)):
		delta += float(ap.get("hopeless_accept_floor_bonus", -0.18))
	elif bool(matchup_info.get("outmatched", false)):
		delta += float(ap.get("outmatched_accept_floor_bonus", -0.08))
	if bool(matchup_info.get("nuclear_asymmetry", false)):
		delta += float(ap.get("nuclear_vs_non_accept_floor_bonus", -0.12))
	return delta


static func relationship_discount_mults(band_id: String, has_mfn: bool = false, relationship_years: float = 0.0) -> Dictionary:
	_load()
	var rd: Dictionary = _rules.get("relationship_discounts", {}) as Dictionary if _rules.get("relationship_discounts") is Dictionary else {}
	var base: Dictionary = rd.get(band_id, {}) as Dictionary if rd.get(band_id) is Dictionary else {}
	var trade_m := float(base.get("trade_suu_mult", 1.0))
	var tech_m := float(base.get("tech_share_suu_mult", 1.0))
	var design_m := float(base.get("design_license_mult", 1.0))
	var basing_m := float(base.get("basing_suu_mult", 1.0))
	if has_mfn:
		trade_m *= float(rd.get("mfn_extra_trade_mult", 0.95))
	var yrs_need := float(rd.get("long_term_years_for_extra", 5))
	if relationship_years >= yrs_need:
		var extra := float(rd.get("long_term_extra_mult", 0.93))
		trade_m *= extra
		tech_m *= extra
	return {
		"trade_suu_mult": snappedf(trade_m, 0.001),
		"tech_share_suu_mult": snappedf(tech_m, 0.001),
		"design_license_mult": snappedf(design_m, 0.001),
		"basing_suu_mult": snappedf(basing_m, 0.001),
		"band_id": band_id,
		"long_term": relationship_years >= yrs_need,
	}


static func spy_clarity(mission_success: bool = false, has_network: bool = false) -> float:
	_load()
	var s: Dictionary = _rules.get("spy_intel", {}) as Dictionary if _rules.get("spy_intel") is Dictionary else {}
	var c := float(s.get("base_clarity", 0.35))
	if mission_success:
		c += float(s.get("mission_bonus", 0.4))
	if has_network:
		c += float(s.get("network_bonus", 0.15))
	return clampf(c, 0.0, 1.0)


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
