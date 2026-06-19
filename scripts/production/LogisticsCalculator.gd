class_name LogisticsCalculator
extends RefCounted

## Cargo capacity, supply demand, and combat contribution from module loadouts.

const WEAPON_SLOTS: Array[String] = ["MainWeapon", "SecondaryWeapon", "AntiAir", "NavalGun"]

const LOGISTICS_ARCHETYPES: Array[String] = [
	"transport", "cargo_ship", "rocket_launcher", "sam_battery", "icbm_launcher",
]

const CARGO_SLOT := "Cargo"


static func applies_logistics(template: UnitTemplate) -> bool:
	if template == null:
		return false
	if template.get_stat("cargo_capacity", 0.0) > 0.0:
		return true
	return template.visual_archetype in LOGISTICS_ARCHETYPES


static func resolve_loadout(template: UnitTemplate, loadout_override: Dictionary) -> Dictionary:
	if template == null:
		return {}
	var resolved: Dictionary = template.module_loadout.duplicate()
	for slot_name in loadout_override:
		var module_id := str(loadout_override[slot_name])
		if module_id.is_empty():
			resolved.erase(slot_name)
		else:
			resolved[slot_name] = module_id
	return resolved


static func compute(
	template: UnitTemplate,
	design_data: DesignDataLoader,
	rules: Dictionary,
	combat_readiness: float,
	loadout_override: Dictionary = {},
) -> Dictionary:
	var out := {
		"base_cargo_capacity": 0.0,
		"effective_cargo_capacity": 0.0,
		"cargo_capacity_ratio": 0.0,
		"armed_weapon_slots": 0,
		"logistics_supply_demand": 0.0,
		"combat_soft_attack": 0.0,
		"combat_hard_attack": 0.0,
		"combat_air_attack": 0.0,
		"combat_anti_air": 0.0,
		"combat_anti_ship": 0.0,
	}
	if template == null or not applies_logistics(template):
		return out

	var logistics_rules: Dictionary = rules.get("logistics", {})
	var loadout := resolve_loadout(template, loadout_override)
	var base_cargo := template.get_stat("cargo_capacity", 0.0)
	var cargo_mult := _cargo_module_multiplier(loadout, logistics_rules)
	var weapon_penalty := _weapon_slot_penalty_product(loadout, logistics_rules)
	var effective_cargo := base_cargo * cargo_mult * weapon_penalty

	out["base_cargo_capacity"] = base_cargo
	out["effective_cargo_capacity"] = effective_cargo
	out["cargo_capacity_ratio"] = weapon_penalty * cargo_mult
	out["armed_weapon_slots"] = _count_weapon_slots(loadout)
	out["logistics_supply_demand"] = _compute_supply_demand(
		template, loadout, effective_cargo, logistics_rules,
	)
	var combat := _aggregate_combat_stats(loadout, design_data)
	var engine := _aggregate_engine_stats(loadout, design_data)
	var readiness_mult := 1.0
	if bool(logistics_rules.get("combat_readiness_applies_to_cargo_units", true)):
		readiness_mult = clampf(combat_readiness, 0.0, 1.0)
	# High-value: Loyalty / foreign military penalty on combat effectiveness (from Province/GameData loyalty multiplier and foreign %).
	# Models reduced morale, coordination, or reliability in units with high foreign troop integration (historical parallels in mixed forces).
	var loyalty_penalty := 1.0
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_military_loyalty_multiplier"):
		var loy: float = GameData.get_military_loyalty_multiplier("player")
		loyalty_penalty = clampf(loy, 0.6, 1.1)
	out["combat_soft_attack"] = combat["soft"] * readiness_mult * loyalty_penalty
	out["combat_hard_attack"] = combat["hard"] * readiness_mult * loyalty_penalty
	out["combat_air_attack"] = combat["air"] * readiness_mult * loyalty_penalty
	out["combat_anti_air"] = combat["anti_air"] * readiness_mult * loyalty_penalty
	out["combat_anti_ship"] = combat["anti_ship"] * readiness_mult * loyalty_penalty
	# Engine stats now live: higher fuel_efficiency lowers consumption; speed_bonus aids mobility/range; power for thrust/accel.
	out["engine_fuel_efficiency"] = engine.get("fuel_efficiency", 0.0)
	out["engine_speed_bonus"] = engine.get("speed_bonus", 0.0)
	out["engine_power"] = engine.get("power_output", 0.0)
	out["engine_reliability_bonus"] = engine.get("reliability", 0.0)
	# Power system demo: higher fuel_efficiency reduces effective fuel/supply need for the unit (visible in production preview and supply draw).
	if float(out.get("engine_fuel_efficiency", 0.0)) > 0.0:
		var base_fuel: float = maxf(float(out.get("fuel_consumption", 1.0)), 1.0)
		out["fuel_consumption"] = base_fuel / (1.0 + float(out["engine_fuel_efficiency"]) * 0.02)  # 2% per point efficiency
	return out


static func _cargo_module_multiplier(loadout: Dictionary, rules: Dictionary) -> float:
	if not loadout.has(CARGO_SLOT):
		return 1.0
	var module_id := str(loadout[CARGO_SLOT])
	var multipliers: Dictionary = rules.get("cargo_module_multipliers", {})
	if multipliers.has(module_id):
		return float(multipliers[module_id])
	if module_id.contains("armed") or module_id.contains("reduced"):
		return float(rules.get("default_reduced_cargo_multiplier", 0.72))
	return 1.0


static func _weapon_slot_penalty_product(loadout: Dictionary, rules: Dictionary) -> float:
	var penalties: Dictionary = rules.get("weapon_slot_cargo_penalty", {})
	var product := 1.0
	for slot_name in WEAPON_SLOTS:
		if not loadout.has(slot_name):
			continue
		if str(loadout[slot_name]).is_empty():
			continue
		var penalty := float(penalties.get(slot_name, 0.0))
		product *= 1.0 - clampf(penalty, 0.0, 0.95)
	return product


static func _count_weapon_slots(loadout: Dictionary) -> int:
	var count := 0
	for slot_name in WEAPON_SLOTS:
		if loadout.has(slot_name) and not str(loadout[slot_name]).is_empty():
			count += 1
	return count


static func _compute_supply_demand(
	template: UnitTemplate,
	loadout: Dictionary,
	effective_cargo: float,
	rules: Dictionary,
) -> float:
	var base_supply := template.get_stat("supply_need", 0.0)
	var reference_cargo := float(rules.get("reference_cargo_tons", 10000.0))
	var per_ton := float(rules.get("supply_need_per_cargo_ton", 0.0008))
	var cargo_component := 0.0
	if effective_cargo > 0.0 and reference_cargo > 0.0:
		cargo_component = (effective_cargo / reference_cargo) * reference_cargo * per_ton

	var overhead := float(rules.get("armed_supply_overhead_per_weapon_slot", 0.06))
	var weapon_slots := _count_weapon_slots(loadout)
	var weapon_supply := base_supply * overhead * float(weapon_slots)
	return base_supply + cargo_component + weapon_supply


static func _aggregate_combat_stats(loadout: Dictionary, design_data: DesignDataLoader) -> Dictionary:
	var combat := {"soft": 0.0, "hard": 0.0, "air": 0.0, "anti_air": 0.0, "anti_ship": 0.0}
	if design_data == null:
		return combat
	for slot_name in WEAPON_SLOTS:
		if not loadout.has(slot_name):
			continue
		var module_id := str(loadout[slot_name])
		if module_id.is_empty():
			continue
		var mod: EquipmentModule = design_data.get_module(module_id)
		if mod == null:
			continue
		combat["soft"] += mod.soft_attack
		combat["hard"] += mod.hard_attack
		combat["air"] += mod.air_attack
		combat["anti_air"] += mod.anti_air
		combat["anti_ship"] += mod.anti_ship
	return combat

## Aggregate engine/propulsion module effects from loadout (for speed, fuel efficiency, power, reliability).
## Used by supply (fuel draw), movement (speed), reliability, and combat mobility.
## Engine choice (diesel vs gas vs nuclear) now has real gameplay weight and cross-domain potential.
static func _aggregate_engine_stats(loadout: Dictionary, design_data: DesignDataLoader) -> Dictionary:
	var eng := {"fuel_efficiency": 0.0, "speed_bonus": 0.0, "power_output": 0.0, "reliability": 0.0}
	if design_data == null:
		return eng
	for slot_name in loadout:
		var module_id := str(loadout[slot_name])
		if module_id.is_empty(): continue
		var mod: EquipmentModule = design_data.get_module(module_id)
		if mod == null or mod.category.to_lower() != "engine": continue
		eng["fuel_efficiency"] += mod.fuel_efficiency
		eng["speed_bonus"] += mod.speed_bonus
		eng["power_output"] += mod.power_output
		eng["reliability"] += mod.reliability_bonus
	return eng
