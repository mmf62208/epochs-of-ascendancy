# scripts/production/ResourceHarvestCalculator.gd
## Auto-harvest province deposits → national major stockpiles (no goods micro).
## Mirrors data/production/resource_harvest_rules.json; pure helpers for dual + tests.
class_name ResourceHarvestCalculator
extends RefCounted

const RULES_PATH := "res://data/production/resource_harvest_rules.json"
const COST_RULES_PATH := "res://data/production/production_cost_rules.json"

static var _rules: Dictionary = {}
static var _cost_rules: Dictionary = {}
static var _loaded: bool = false


static func get_rules() -> Dictionary:
	_load_rules()
	return _rules


static func reload_rules() -> void:
	_loaded = false
	_rules = {}
	_cost_rules = {}
	_load_rules()


static func get_source_to_major_map() -> Dictionary:
	_load_rules()
	var out: Dictionary = {}
	var src: Variant = _rules.get("source_to_major", {})
	if src is Dictionary:
		for k in src:
			out[str(k).to_lower()] = str(src[k]).to_lower()
	# Fold production_cost_rules aliases into major map
	var majors: Variant = _cost_rules.get("major_resources", {})
	if majors is Dictionary:
		for major_id in majors:
			var entry: Variant = majors[major_id]
			if entry is Dictionary:
				var aliases: Variant = (entry as Dictionary).get("aliases", [])
				if typeof(aliases) == TYPE_ARRAY:
					for a in aliases:
						out[str(a).to_lower()] = str(major_id).to_lower()
			out[str(major_id).to_lower()] = str(major_id).to_lower()
	return out


static func is_major_visible(major_id: String, unlocks: Dictionary = {}) -> bool:
	_load_rules()
	var mid := major_id.strip_edges().to_lower()
	var always: Variant = _rules.get("always_visible_majors", [])
	if typeof(always) == TYPE_ARRAY:
		for a in always:
			if str(a).to_lower() == mid:
				return true
	var vis: Variant = _rules.get("visibility", {})
	if not (vis is Dictionary) or not (vis as Dictionary).has(mid):
		# endgame feeds that map to energy still need their unlock for *source* harvest
		return true
	var rule: Dictionary = (vis as Dictionary)[mid] as Dictionary
	var flag := str(rule.get("requires_rule_flag", ""))
	if not flag.is_empty():
		var flags: Array = unlocks.get("rule_flags", []) as Array
		if flag in flags:
			return true
		var unlocked_res: Array = unlocks.get("unlocked_resources", []) as Array
		var or_res := str(rule.get("or_unlocked_resource", ""))
		if not or_res.is_empty() and or_res in unlocked_res:
			return true
		return false
	return true


static func get_visible_majors(unlocks: Dictionary = {}) -> PackedStringArray:
	var out: PackedStringArray = []
	for mid in ProductionCostCalculator.get_major_resource_ids():
		if is_major_visible(str(mid), unlocks):
			out.append(str(mid))
	return out


static func size_tier_multiplier(size_tier: int) -> float:
	_load_rules()
	var tiers: Variant = _rules.get("size_tier_multipliers", {})
	if tiers is Dictionary:
		var key := str(clampi(size_tier, 1, 5))
		return float((tiers as Dictionary).get(key, 1.0))
	return 1.0


static func plant_boost_for_source(
	source_key: String,
	plants: Array = [],
	unlocks: Dictionary = {},
) -> Dictionary:
	## Returns {multiplier, also_fuel_fraction, energy_byproduct, plant_type, size_tier}.
	_load_rules()
	var sk := source_key.strip_edges().to_lower()
	var best_mult := float(_rules.get("no_plant_multiplier", 0.35))
	var also_fuel := 0.0
	var energy_by := 0.0
	var best_type := ""
	var best_tier := 0
	var energy_plants: Dictionary = _rules.get("energy_plant_types", {}) as Dictionary if _rules.get("energy_plant_types") is Dictionary else {}
	var res_plants: Dictionary = _rules.get("resource_plant_types", {}) as Dictionary if _rules.get("resource_plant_types") is Dictionary else {}
	var flags: Array = unlocks.get("rule_flags", []) as Array

	for raw in plants:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = raw as Dictionary
		var ptype := str(p.get("factory_type", p.get("plant_type", ""))).to_lower()
		var tier := int(p.get("size_tier", 1))
		var tier_m := size_tier_multiplier(tier)
		var conf: Dictionary = {}
		if energy_plants.has(ptype):
			conf = energy_plants[ptype] as Dictionary
		elif res_plants.has(ptype):
			conf = res_plants[ptype] as Dictionary
		else:
			continue
		var req := str(conf.get("requires_unlock", ""))
		if not req.is_empty() and req not in flags:
			continue
		var keys: Array = conf.get("source_keys", []) as Array
		var matches := false
		for k in keys:
			if str(k).to_lower() == sk:
				matches = true
				break
		if not matches:
			continue
		var mult := float(conf.get("base_mult", 1.0)) * tier_m
		if mult > best_mult:
			best_mult = mult
			best_type = ptype
			best_tier = tier
			also_fuel = float(conf.get("also_fuel_fraction", 0.0))
			energy_by = float(conf.get("energy_byproduct", 0.0))
	return {
		"multiplier": best_mult,
		"also_fuel_fraction": also_fuel,
		"energy_byproduct": energy_by,
		"plant_type": best_type,
		"size_tier": best_tier,
	}


static func tech_major_bonus(major_id: String, unlocks: Dictionary = {}) -> float:
	## Additive efficiency from tech modifiers (e.g. plastics on rubber/electronics).
	_load_rules()
	var mid := major_id.strip_edges().to_lower()
	var bonus := 0.0
	var flags: Array = unlocks.get("rule_flags", []) as Array
	var mods: Dictionary = unlocks.get("permanent_modifiers", {}) as Dictionary if unlocks.get("permanent_modifiers") is Dictionary else {}
	var tmods: Variant = _rules.get("tech_modifiers", {})
	if tmods is Dictionary:
		var plastics: Variant = (tmods as Dictionary).get("plastics_improves_efficiency", {})
		if plastics is Dictionary:
			var pflag := str((plastics as Dictionary).get("rule_flag", "plastics_industry"))
			if pflag in flags:
				var majors: Variant = (plastics as Dictionary).get("majors", {})
				if majors is Dictionary and (majors as Dictionary).has(mid):
					bonus += float((majors as Dictionary)[mid])
		var ppo: Variant = (tmods as Dictionary).get("power_plant_output", {})
		if ppo is Dictionary and str((ppo as Dictionary).get("applies_to", "")) == "energy" and mid == "energy":
			bonus += float(mods.get("power_plant_output", 0.0))
		var ro: Variant = (tmods as Dictionary).get("resource_output", {})
		if ro is Dictionary and str((ro as Dictionary).get("applies_to", "")) == "all_majors":
			bonus += float(mods.get("resource_output", 0.0))
			bonus += float(mods.get("resource_output_multiplier", 0.0))
	return bonus


static func synthetic_fuel_fraction(unlocks: Dictionary = {}) -> float:
	_load_rules()
	var flags: Array = unlocks.get("rule_flags", []) as Array
	var tmods: Variant = _rules.get("tech_modifiers", {})
	if tmods is Dictionary:
		var sf: Variant = (tmods as Dictionary).get("synthetic_fuel", {})
		if sf is Dictionary:
			var flag := str((sf as Dictionary).get("rule_flag", "synthetic_fuel"))
			if flag in flags:
				return float((sf as Dictionary).get("energy_to_fuel_fraction", 0.08))
	return 0.0


static func raw_daily_from_deposit(deposit_amount: float) -> float:
	_load_rules()
	var frac := float(_rules.get("base_extract_fraction", 0.01))
	var min_d := float(_rules.get("base_extract_min_daily", 0.05))
	var cap := float(_rules.get("deposit_soft_cap", 5000.0))
	var amt := clampf(float(deposit_amount), 0.0, cap)
	if amt <= 0.0:
		return 0.0
	return maxf(amt * frac, min_d if amt >= 1.0 else amt * frac)


static func can_harvest_source(source_key: String, unlocks: Dictionary = {}) -> bool:
	var sk := source_key.strip_edges().to_lower()
	if sk in ["uranium", "plutonium", "fissiles"]:
		return is_major_visible("fissiles", unlocks)
	if sk == "helium3":
		return is_major_visible("helium3", unlocks)
	if sk == "antimatter":
		return is_major_visible("antimatter", unlocks)
	return true


static func compute_province_daily_income(
	resources: Dictionary,
	plants: Array = [],
	unlocks: Dictionary = {},
	development: Dictionary = {},
) -> Dictionary:
	## Returns major → daily float income from one province's deposits + plants.
	## Also credits HOI factory-feed keys (oil/coal/chromium/tungsten) so TOE lines can pay.
	_load_rules()
	var map := get_source_to_major_map()
	var income: Dictionary = {}
	for raw_key in resources:
		var sk := str(raw_key).to_lower()
		if not can_harvest_source(sk, unlocks):
			continue
		var deposit := float(resources[raw_key])
		if deposit <= 0.0:
			continue
		var major := str(map.get(sk, ""))
		if major.is_empty():
			continue
		# Ops supplies are allowed; majors use visibility
		if major != "supplies" and not is_major_visible(major, unlocks) and major != "energy":
			# helium3/antimatter map to energy but gated above via can_harvest_source
			if major in ["fissiles"] and not is_major_visible("fissiles", unlocks):
				continue
		var base := raw_daily_from_deposit(deposit)
		var boost: Dictionary = plant_boost_for_source(sk, plants, unlocks)
		var mult := float(boost.get("multiplier", 0.35))
		var tech_b := tech_major_bonus(major, unlocks)
		var lv_m := development_mult(int(development.get(sk, 0)))
		var amount := base * mult * (1.0 + tech_b) * lv_m
		income[major] = float(income.get(major, 0.0)) + amount
		var also_fuel := float(boost.get("also_fuel_fraction", 0.0))
		if also_fuel > 0.0 and major == "energy":
			income["fuel"] = float(income.get("fuel", 0.0)) + amount * also_fuel
		var energy_by := float(boost.get("energy_byproduct", 0.0))
		if energy_by > 0.0 and major == "fuel":
			income["energy"] = float(income.get("energy", 0.0)) + amount * energy_by
		# Factory-feed alias: oil→fuel major still needs an `oil` pile for TOE trucks/tanks.
		if sk in FACTORY_FEED_KEYS and major != sk:
			income[sk] = float(income.get(sk, 0.0)) + base * 0.35 * (1.0 + tech_b) * lv_m
	# Synthetic fuel: convert a slice of energy income into fuel
	var e2f := synthetic_fuel_fraction(unlocks)
	if e2f > 0.0 and float(income.get("energy", 0.0)) > 0.0:
		var convert := float(income["energy"]) * e2f
		income["fuel"] = float(income.get("fuel", 0.0)) + convert
	# Snap
	for k in income.keys():
		income[k] = snappedf(float(income[k]), 0.01)
	return income


static func merge_income(target: Dictionary, add: Dictionary, days: float = 1.0) -> Dictionary:
	var d := maxf(float(days), 0.0)
	for k in add:
		target[k] = float(target.get(k, 0.0)) + float(add[k]) * d
	return target


static func compute_national_daily_income(
	provinces: Array,
	unlocks_by_tag: Dictionary = {},
) -> Dictionary:
	## provinces: [{owner_tag, resources, plants}]
	## returns {tag: {major: daily}}
	var by_tag: Dictionary = {}
	for raw in provinces:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = raw as Dictionary
		var tag := str(p.get("owner_tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			continue
		var unlocks: Dictionary = unlocks_by_tag.get(tag, {}) as Dictionary if unlocks_by_tag.get(tag) is Dictionary else {}
		var res: Dictionary = p.get("resources", {}) as Dictionary if p.get("resources") is Dictionary else {}
		var plants: Array = p.get("plants", []) as Array if p.get("plants") is Array else []
		var development: Dictionary = p.get("development", {}) as Dictionary if p.get("development") is Dictionary else {}
		var day_inc := compute_province_daily_income(res, plants, unlocks, development)
		if not by_tag.has(tag):
			by_tag[tag] = {}
		merge_income(by_tag[tag], day_inc, 1.0)
	return by_tag


static func list_energy_plant_types() -> PackedStringArray:
	_load_rules()
	var out: PackedStringArray = []
	var ep: Variant = _rules.get("energy_plant_types", {})
	if ep is Dictionary:
		for k in ep:
			out.append(str(k))
	return out


static func list_resource_plant_types() -> PackedStringArray:
	_load_rules()
	var out: PackedStringArray = []
	var rp: Variant = _rules.get("resource_plant_types", {})
	if rp is Dictionary:
		for k in rp:
			out.append(str(k))
	return out


static func is_resource_plant_type(factory_type: String) -> bool:
	var ft := factory_type.strip_edges().to_lower()
	_load_rules()
	var ep: Variant = _rules.get("energy_plant_types", {})
	var rp: Variant = _rules.get("resource_plant_types", {})
	if ep is Dictionary and (ep as Dictionary).has(ft):
		return true
	if rp is Dictionary and (rp as Dictionary).has(ft):
		return true
	return false


## Food/supplies income → cohesion delta (ops triad, not factory major UI).
## Positive when daily supplies income is healthy; negative when stockpile is near empty.
static func compute_food_cohesion_delta(
	daily_supplies_income: float,
	supplies_stockpile: float = 0.0,
) -> Dictionary:
	_load_rules()
	var fc: Dictionary = _rules.get("food_cohesion", {}) as Dictionary if _rules.get("food_cohesion") is Dictionary else {}
	var per := float(fc.get("supplies_income_per_cohesion_point", 25.0))
	var max_gain := int(fc.get("max_daily_cohesion_gain", 2))
	var starve_thr := float(fc.get("starvation_stockpile_threshold", 5.0))
	var starve_pen := int(fc.get("starvation_cohesion_penalty", -1))
	var delta := 0
	var reason := "neutral"
	if daily_supplies_income > 0.0 and per > 0.0:
		delta = clampi(int(floor(daily_supplies_income / per)), 0, max_gain)
		if delta > 0:
			reason = "food_surplus"
	if supplies_stockpile + 0.001 < starve_thr and daily_supplies_income < per * 0.5:
		delta = mini(delta, 0) + starve_pen
		reason = "food_shortage"
	return {
		"cohesion_delta": delta,
		"reason": reason,
		"daily_supplies_income": snappedf(daily_supplies_income, 0.01),
		"supplies_stockpile": snappedf(supplies_stockpile, 0.01),
	}


## Relative fuel burn for ops by vehicle class (jets/rockets higher than trucks).
static func fuel_ops_burn_rate(vehicle_class: String = "default") -> float:
	_load_rules()
	var table: Dictionary = _rules.get("fuel_ops_burn", {}) as Dictionary if _rules.get("fuel_ops_burn") is Dictionary else {}
	var key := vehicle_class.strip_edges().to_lower()
	if table.has(key):
		return float(table[key])
	# aliases
	if key in ["tank", "medium_tank", "heavy_tank", "light_tank"]:
		return float(table.get("armor", 0.35))
	if key in ["fighter", "bomber", "jet_fighter"]:
		return float(table.get("jet" if "jet" in key else "prop_aircraft", 0.4))
	if key in ["missile", "space", "rocket"]:
		return float(table.get("rocket", 1.6))
	if key in ["ship", "destroyer", "cruiser", "battleship", "carrier", "submarine"]:
		return float(table.get("naval", 1.2))
	return float(table.get("default", 0.25))


static func compute_ops_fuel_cost(vehicle_class: String, units: float = 1.0, days: float = 1.0) -> float:
	return snappedf(fuel_ops_burn_rate(vehicle_class) * maxf(units, 0.0) * maxf(days, 0.0), 0.01)


## Recommend a plant type for the richest deposit on a province (auto-seed).
static func recommend_plant_for_resources(
	resources: Dictionary,
	unlocks: Dictionary = {},
) -> Dictionary:
	_load_rules()
	var seed_map: Dictionary = _rules.get("plant_auto_seed", {}) as Dictionary if _rules.get("plant_auto_seed") is Dictionary else {}
	var min_dep := float(_rules.get("plant_auto_seed_min_deposit", 40.0))
	var default_tier := int(_rules.get("plant_default_size_tier", 1))
	var best_key := ""
	var best_amt := 0.0
	var best_plant := ""
	for raw_key in resources:
		var sk := str(raw_key).to_lower()
		var amt := float(resources[raw_key])
		if amt < min_dep:
			continue
		if not can_harvest_source(sk, unlocks):
			continue
		if not seed_map.has(sk):
			continue
		var plant := str(seed_map[sk]).to_lower()
		# nuclear/enrichment/fusion require unlocks
		var conf: Dictionary = {}
		var ep: Dictionary = _rules.get("energy_plant_types", {}) as Dictionary if _rules.get("energy_plant_types") is Dictionary else {}
		var rp: Dictionary = _rules.get("resource_plant_types", {}) as Dictionary if _rules.get("resource_plant_types") is Dictionary else {}
		if ep.has(plant):
			conf = ep[plant] as Dictionary
		elif rp.has(plant):
			conf = rp[plant] as Dictionary
		var req := str(conf.get("requires_unlock", ""))
		var flags: Array = unlocks.get("rule_flags", []) as Array
		if not req.is_empty() and req not in flags:
			continue
		if amt > best_amt:
			best_amt = amt
			best_key = sk
			best_plant = plant
	if best_plant.is_empty():
		return {}
	# Size tier from deposit scale
	var tier := default_tier
	if best_amt >= 1000.0:
		tier = 4
	elif best_amt >= 500.0:
		tier = 3
	elif best_amt >= 200.0:
		tier = 2
	return {
		"plant_type": best_plant,
		"source_key": best_key,
		"deposit": best_amt,
		"size_tier": clampi(tier, 1, 5),
	}


static func endgame_deposit_year(source_key: String) -> int:
	_load_rules()
	var years: Dictionary = _rules.get("endgame_deposit_years", {}) as Dictionary if _rules.get("endgame_deposit_years") is Dictionary else {}
	return int(years.get(source_key.strip_edges().to_lower(), 0))


static func is_endgame_source_year_ok(source_key: String, scenario_year: int = 0) -> bool:
	var y := endgame_deposit_year(source_key)
	if y <= 0:
		return true
	if scenario_year <= 0:
		return false
	return scenario_year >= y


## Painted deposits are 1936-baseline. 1918 extracts less oil/aluminum; 2026 more oil, less coal.
const ERA_OMIT_THRESHOLD := 0.25
const DEVELOP_MAX_LEVEL := 3
const DEVELOP_COMPLETES_INSTANT := true
const DEVELOP_BONUS_PER_LEVEL := 0.35
const DEVELOP_STEEL_BASE := 8.0
const DEVELOP_STEEL_PER_LEVEL := 4.0
const FACTORY_FEED_KEYS := ["steel", "coal", "oil", "rubber", "aluminum", "chromium", "tungsten"]
const ERA_SCALE := {
	"coal": [1.20, 1.00, 0.65],
	"iron": [0.90, 1.00, 1.10],
	"steel": [0.65, 1.00, 1.20],
	"oil": [0.32, 1.00, 1.80],
	"rubber": [0.40, 1.00, 0.75],
	"aluminum": [0.00, 1.00, 1.55],
	"chromium": [0.35, 1.00, 1.25],
	"tungsten": [0.28, 1.00, 1.30],
	"uranium": [0.00, 0.08, 1.00],
	"rare_earths": [0.00, 0.00, 1.00],
}


static func era_band_for_year(year: int) -> int:
	var y := int(year)
	if y <= 1924:
		return 0
	if y >= 2000:
		return 2
	return 1


static func era_resource_scale(year: int, key: String) -> float:
	var k := key.strip_edges().to_lower()
	if not ERA_SCALE.has(k):
		return 1.0
	var row: Array = ERA_SCALE[k] as Array
	var band := clampi(era_band_for_year(year), 0, 2)
	if band >= row.size():
		return 1.0
	return float(row[band])


static func scale_deposits_for_year(resources: Dictionary, year: int) -> Dictionary:
	var out: Dictionary = {}
	if resources.is_empty():
		return out
	for raw_key in resources:
		var key := str(raw_key).strip_edges().to_lower()
		var amt := float(resources[raw_key])
		if amt <= 0.0:
			continue
		var scaled := amt * era_resource_scale(year, key)
		if scaled < ERA_OMIT_THRESHOLD:
			continue
		out[key] = snappedf(scaled, 0.0001)
	return out


static func development_mult(level: int) -> float:
	var lv := clampi(int(level), 0, DEVELOP_MAX_LEVEL)
	return 1.0 + DEVELOP_BONUS_PER_LEVEL * float(lv)


static func apply_development(resources: Dictionary, development: Dictionary = {}) -> Dictionary:
	if resources.is_empty():
		return {}
	if development.is_empty():
		return resources.duplicate()
	var out: Dictionary = {}
	for raw_key in resources:
		var key := str(raw_key).strip_edges().to_lower()
		var amt := float(resources[raw_key])
		if amt <= 0.0:
			continue
		var lv := int(development.get(key, 0))
		out[key] = snappedf(amt * development_mult(lv), 0.0001)
	return out


static func develop_cost(current_level: int = 0) -> Dictionary:
	var lv := clampi(int(current_level), 0, DEVELOP_MAX_LEVEL)
	return {"steel": DEVELOP_STEEL_BASE + DEVELOP_STEEL_PER_LEVEL * float(lv)}


static func icon_px_for_amount(amount: float) -> float:
	return clampf(10.0 + maxf(float(amount), 0.0) * 2.2, 10.0, 22.0)


static func build_develop_resource_action(
	resources: Dictionary,
	key: String = "",
	scenario_year: int = 1936,
	development: Dictionary = {},
	stockpile: Dictionary = {},
) -> Dictionary:
	var scaled := scale_deposits_for_year(resources, scenario_year)
	var want := key.strip_edges().to_lower()
	if want.is_empty():
		var best := ""
		var best_amt := 0.0
		for k in scaled:
			var a := float(scaled[k])
			if a > best_amt:
				best_amt = a
				best = str(k)
		want = best
	if want.is_empty():
		return {"ok": false, "error": "no_deposit"}
	if float(scaled.get(want, 0.0)) <= 0.0:
		return {"ok": false, "error": "not_visible", "key": want, "year": scenario_year}
	var cur := int(development.get(want, 0))
	if cur >= DEVELOP_MAX_LEVEL:
		return {"ok": false, "error": "max_level", "key": want, "level": cur}
	var cost: Dictionary = develop_cost(cur)
	for rk in cost:
		if float(stockpile.get(rk, 0.0)) + 0.001 < float(cost[rk]):
			return {"ok": false, "error": "no_resources", "key": want, "cost": cost}
	return {
		"ok": true,
		"key": want,
		"level_before": cur,
		"level_after": cur + 1,
		"cost": cost,
		"bonus_after": development_mult(cur + 1),
		"year": scenario_year,
	}


## Levels apply immediately (pay steel → +1). NEXT does not invent a multi-day mine.
static func develop_days_remaining(_development: Dictionary = {}, _key: String = "") -> float:
	return -1.0


static func compute_developed_income(resources: Dictionary, development: Dictionary = {}) -> Dictionary:
	return compute_province_daily_income(resources, [], {}, development)


static func harvest_holder_tag(owner: String, controller: String = "") -> String:
	var c := controller.strip_edges().to_upper()
	if not c.is_empty():
		return c
	return owner.strip_edges().to_upper()


static func occupation_harvest_mult(owner: String, controller: String = "") -> float:
	var holder := harvest_holder_tag(owner, controller)
	var own := owner.strip_edges().to_upper()
	if holder.is_empty() or own.is_empty() or holder == own:
		return 1.0
	return 0.65


static func refuel_from_stockpile(
	fuel_level: float,
	fuel_use: float,
	stockpile: Dictionary = {},
	amount: float = 0.10,
) -> Dictionary:
	var cur := clampf(float(fuel_level), 0.0, 1.0)
	var use := maxf(float(fuel_use), 0.0)
	if use <= 0.000000001:
		return {"ok": true, "fuel_after": cur, "paid": 0.0, "drawn": {}, "reason": "foot"}
	var gap := minf(maxf(float(amount), 0.0), 1.0 - cur)
	if gap <= 0.000000001:
		return {"ok": true, "fuel_after": cur, "paid": 0.0, "drawn": {}, "reason": "full"}
	var need := (gap / 0.10) * 0.5
	var have_fuel := maxf(float(stockpile.get("fuel", 0.0)), 0.0)
	var have_oil := maxf(float(stockpile.get("oil", 0.0)), 0.0)
	var have := have_fuel + have_oil
	if have <= 0.000000001:
		return {"ok": false, "fuel_after": cur, "paid": 0.0, "drawn": {}, "error": "empty_stock"}
	var paid := minf(have, need)
	var fill := paid / need if need > 0.0 else 0.0
	var take_fuel := minf(have_fuel, paid)
	var take_oil := paid - take_fuel
	var drawn: Dictionary = {}
	if take_fuel > 0.0:
		drawn["fuel"] = take_fuel
	if take_oil > 0.0:
		drawn["oil"] = take_oil
	return {
		"ok": true,
		"fuel_after": snappedf(cur + gap * fill, 0.0001),
		"paid": snappedf(paid, 0.0001),
		"drawn": drawn,
		"reason": "refueled",
	}


## Combat reliability scale from production shortage multiplier stamped on equipment.
static func combat_reliability_from_production(production_reliability: float) -> float:
	# Soft floor: never collapse combat from production alone below ~0.72 path.
	return clampf(float(production_reliability), 0.72, 1.0)


## Browser / map surface: plant rows for a province (type icon key, size, upgrade preview).
static func build_plant_browser_rows(plants: Array = []) -> Array:
	var rows: Array = []
	_load_rules()
	var ep: Dictionary = _rules.get("energy_plant_types", {}) as Dictionary if _rules.get("energy_plant_types") is Dictionary else {}
	var rp: Dictionary = _rules.get("resource_plant_types", {}) as Dictionary if _rules.get("resource_plant_types") is Dictionary else {}
	for raw in plants:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = raw as Dictionary
		var ptype := str(p.get("factory_type", p.get("plant_type", ""))).to_lower()
		if ptype.is_empty():
			continue
		var conf: Dictionary = {}
		var plant_class := "resource"
		if ep.has(ptype):
			conf = ep[ptype] as Dictionary
			plant_class = "energy"
		elif rp.has(ptype):
			conf = rp[ptype] as Dictionary
		var tier := clampi(int(p.get("size_tier", 1)), 1, 5)
		var next_tier := mini(tier + 1, 5)
		rows.append({
			"factory_id": int(p.get("factory_id", 0)),
			"plant_type": ptype,
			"plant_class": plant_class,
			"icon": str(conf.get("icon", ptype)),
			"size_tier": tier,
			"size_mult": size_tier_multiplier(tier),
			"can_upgrade": tier < 5,
			"next_size_tier": next_tier,
			"next_size_mult": size_tier_multiplier(next_tier),
			"feeds": str(conf.get("feeds", conf.get("major", ""))),
			"source_keys": conf.get("source_keys", []),
		})
	return rows


## Place-plant surface: validate recommend + optional override type for UI / live apply.
static func build_place_plant_action(
	resources: Dictionary,
	unlocks: Dictionary = {},
	override_plant_type: String = "",
) -> Dictionary:
	var rec := recommend_plant_for_resources(resources, unlocks)
	var ptype := override_plant_type.strip_edges().to_lower()
	if ptype.is_empty():
		ptype = str(rec.get("plant_type", ""))
	if ptype.is_empty() or not is_resource_plant_type(ptype):
		return {"ok": false, "error": "no_plant_type", "recommend": rec}
	# Unlock gate for override types
	_load_rules()
	var conf: Dictionary = {}
	var ep: Dictionary = _rules.get("energy_plant_types", {}) as Dictionary if _rules.get("energy_plant_types") is Dictionary else {}
	var rp: Dictionary = _rules.get("resource_plant_types", {}) as Dictionary if _rules.get("resource_plant_types") is Dictionary else {}
	if ep.has(ptype):
		conf = ep[ptype] as Dictionary
	elif rp.has(ptype):
		conf = rp[ptype] as Dictionary
	var req := str(conf.get("requires_unlock", ""))
	var flags: Array = unlocks.get("rule_flags", []) as Array
	if not req.is_empty() and req not in flags:
		return {"ok": false, "error": "locked", "requires_unlock": req, "plant_type": ptype}
	var tier := int(rec.get("size_tier", _rules.get("plant_default_size_tier", 1)))
	return {
		"ok": true,
		"plant_type": ptype,
		"size_tier": clampi(tier, 1, 5),
		"icon": str(conf.get("icon", ptype)),
		"recommend": rec,
		"source_keys": conf.get("source_keys", []),
	}


## Inject He-3 / antimatter deposits when scenario year unlocks endgame sources.
## Mutates a copy of province resource dicts; does not invent deposits before year gates.
static func apply_endgame_deposits(
	provinces: Array,
	scenario_year: int,
	unlocks_by_tag: Dictionary = {},
) -> Dictionary:
	_load_rules()
	var report := {"year": scenario_year, "helium3_added": 0, "antimatter_added": 0, "touched": []}
	var he_year := endgame_deposit_year("helium3")
	var am_year := endgame_deposit_year("antimatter")
	var he_ok := he_year > 0 and scenario_year >= he_year
	var am_ok := am_year > 0 and scenario_year >= am_year
	if not he_ok and not am_ok:
		report["skipped"] = "year_gate"
		return report
	for raw in provinces:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = raw as Dictionary
		var res: Dictionary = p.get("resources", {}) as Dictionary if p.get("resources") is Dictionary else {}
		if res.is_empty():
			continue
		var tag := str(p.get("owner_tag", "")).strip_edges().to_upper()
		var unlocks: Dictionary = unlocks_by_tag.get(tag, {}) as Dictionary if unlocks_by_tag.get(tag) is Dictionary else {}
		var flags: Array = unlocks.get("rule_flags", []) as Array
		var changed := false
		# Prefer uranium/rare_earth sites for He-3; oil/energy-rich for antimatter feedstock flavor
		if he_ok and ("fusion_power_industry" in flags or scenario_year >= he_year + 5):
			var has_u := float(res.get("uranium", 0.0)) > 0.0 or float(res.get("rare_earths", 0.0)) > 40.0
			if has_u and float(res.get("helium3", 0.0)) <= 0.0:
				var base := maxf(float(res.get("uranium", res.get("rare_earths", 20.0))) * 0.15, 8.0)
				res["helium3"] = snappedf(base, 0.1)
				report["helium3_added"] = int(report["helium3_added"]) + 1
				changed = true
		if am_ok and ("antimatter_unlock" in flags or scenario_year >= am_year):
			var has_energy := float(res.get("oil", 0.0)) > 200.0 or float(res.get("coal", 0.0)) > 400.0
			if has_energy and float(res.get("antimatter", 0.0)) <= 0.0 and scenario_year >= am_year:
				res["antimatter"] = 5.0
				report["antimatter_added"] = int(report["antimatter_added"]) + 1
				changed = true
		if changed:
			p["resources"] = res
			(report["touched"] as Array).append(int(p.get("province_id", 0)))
	return report


## Resource browser majors: always-visible + unlock-gated (fissiles/endgame never in WWI UI).
static func build_resource_browser(
	stockpile: Dictionary = {},
	unlocks: Dictionary = {},
	scenario_year: int = 0,
) -> Dictionary:
	var majors: Array = []
	for mid in get_visible_majors(unlocks):
		var key := str(mid)
		majors.append({
			"id": key,
			"amount": float(stockpile.get(key, 0.0)),
			"visible": true,
		})
	# Endgame feeders only when unlocked (not separate majors — browser chips)
	var endgame: Array = []
	for eg in ["helium3", "antimatter"]:
		if is_major_visible(eg, unlocks) and is_endgame_source_year_ok(eg, scenario_year):
			endgame.append({
				"id": eg,
				"feeds": "energy",
				"amount": float(stockpile.get(eg, 0.0)),
				"visible": true,
			})
	return {
		"majors": majors,
		"endgame_sources": endgame,
		"major_n": majors.size(),
		"endgame_n": endgame.size(),
	}


## Pure trade pricing for majors (shortage raises export value).
static func major_trade_unit_value(resource_id: String, stockpile: Dictionary = {}, base_rates: Dictionary = {}) -> float:
	var rid := resource_id.strip_edges().to_lower()
	var rates := base_rates.duplicate() if not base_rates.is_empty() else {
		"steel": 1.0, "aluminum": 1.5, "energy": 1.2, "fuel": 1.8,
		"rubber": 2.2, "electronics": 3.0, "specials": 2.8, "fissiles": 4.5,
		"oil": 2.5, "supplies": 0.8,
	}
	var base := float(rates.get(rid, 1.0))
	var have := float(stockpile.get(rid, 0.0))
	# Soft shortage pressure: scarce stock → higher export ask
	var scarcity := 1.0
	if have < 20.0:
		scarcity = 1.35
	elif have < 50.0:
		scarcity = 1.15
	elif have > 200.0:
		scarcity = 0.9
	return snappedf(base * scarcity, 0.01)


static func _load_rules() -> void:
	if _loaded:
		return
	_loaded = true
	_rules = {}
	_cost_rules = {}
	if FileAccess.file_exists(RULES_PATH):
		var file := FileAccess.open(RULES_PATH, FileAccess.READ)
		if file != null:
			var parser := JSON.new()
			if parser.parse(file.get_as_text()) == OK and typeof(parser.data) == TYPE_DICTIONARY:
				_rules = parser.data
	if FileAccess.file_exists(COST_RULES_PATH):
		var file2 := FileAccess.open(COST_RULES_PATH, FileAccess.READ)
		if file2 != null:
			var parser2 := JSON.new()
			if parser2.parse(file2.get_as_text()) == OK and typeof(parser2.data) == TYPE_DICTIONARY:
				_cost_rules = parser2.data
