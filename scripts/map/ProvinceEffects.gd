# scripts/map/ProvinceEffects.gd
## Aggregates base province stats (infrastructure + development) with
## national spirits and temporary modifiers to produce final effective values.
##
## This is the clean layer for "what does this province actually do right now?"

class_name ProvinceEffects
extends RefCounted

var province: Province = null
var national_modifiers: Dictionary = {}   # from NationalModifierManager or combined

func _init(p_province: Province, p_national_mods: Dictionary = {}):
	province = p_province
	national_modifiers = p_national_mods if p_national_mods else {}

# --- Supply ---
func get_effective_throughput_multiplier() -> float:
	var base := province.get_supply_throughput_modifier() if province else 1.0
	var nat := float(national_modifiers.get("supply_throughput", 0.0))
	var site_bonus := get_special_site_supply_bonus() * 0.005  # small throughput boost from ports etc.
	return base * (1.0 + nat + site_bonus)

func get_effective_local_supply_generation() -> float:
	var base := province.get_local_supply_generation_modifier() if province else 0.0
	var nat := float(national_modifiers.get("local_supply", 0.0))
	var site_bonus := get_special_site_supply_bonus() * 0.01  # treat as percentage-ish for now
	return maxf(0.0, base + nat + site_bonus)

# --- Combat ---
func get_effective_combat_width_multiplier() -> float:
	var base := province.get_combat_width_modifier() if province else 1.0
	var nat := float(national_modifiers.get("combat_width", 0.0))
	return base * (1.0 + nat)

func get_effective_organization_recovery() -> float:
	var base := province.get_organization_recovery_modifier() if province else 1.0
	var nat := float(national_modifiers.get("organization_recovery", 0.0))
	return base * (1.0 + nat)

func get_effective_attrition_multiplier() -> float:
	var base := province.get_attrition_modifier() if province else 1.0
	var nat := float(national_modifiers.get("attrition_reduction", 0.0))
	# national attrition_reduction reduces the multiplier (good)
	return maxf(0.3, base * (1.0 - nat))

# --- Logistics / Movement ---
func get_effective_logistics_quality() -> float:
	var base := province.get_logistics_quality() if province else 50.0
	var nat := float(national_modifiers.get("logistics_quality", 0.0))
	return base + nat

func get_effective_reinforcement_speed() -> float:
	var base := province.get_reinforcement_speed_modifier() if province else 1.0
	var nat := float(national_modifiers.get("reinforcement_speed", 0.0))
	return base * (1.0 + nat)

## Logistics / Interdiction resistance (higher = harder for enemy to interdict supply in/through this province)
func get_effective_interdiction_resistance() -> float:
	var base := province.get_interdiction_resistance_modifier() if province else 1.0
	var nat := float(national_modifiers.get("interdiction_resistance", 0.0))
	return base * (1.0 + nat)

## Convenience: Build ProvinceEffects pulling combined national supply+combat modifiers (spirits + temp)
## for the given country. Enables one-line "effective value with all layers" usage.
static func for_country_province(p_province: Province, country_tag: String) -> ProvinceEffects:
	var nat: Dictionary = {}
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() or p_province == null:
		return ProvinceEffects.new(p_province, {})

	if typeof(NationalSpiritManager) != TYPE_NIL:
		var spirit_supply := NationalSpiritManager.get_spirit_supply_modifiers(tag)
		for k in spirit_supply.keys():
			nat[k] = float(spirit_supply[k])
		var spirit_combat := NationalSpiritManager.get_spirit_combat_modifiers(tag)
		for k in ["attrition_reduction", "interdiction_resistance", "reinforcement_speed", "organization_recovery"]:
			if spirit_combat.has(k):
				nat[k] = float(nat.get(k, 0.0)) + float(spirit_combat[k])

	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp_supply := NationalModifierManager.get_supply_modifiers(tag)
		for k in temp_supply.keys():
			nat[k] = float(nat.get(k, 0.0)) + float(temp_supply[k])
		var temp_combat := NationalModifierManager.get_combat_modifiers(tag)
		for k in ["attrition_reduction", "interdiction_resistance", "reinforcement_speed"]:
			if temp_combat.has(k):
				nat[k] = float(nat.get(k, 0.0)) + float(temp_combat[k])

	return ProvinceEffects.new(p_province, nat)


## === Special Site Effects (Phase 2 wiring) ===
func get_special_site_supply_bonus() -> float:
	if province == null or province.special_sites.is_empty():
		return 0.0
	var total := 0.0
	for site in province.special_sites:
		if site != null and site.is_completed():
			total += site.supply_bonus
	return total


func get_special_site_trade_capacity() -> float:
	if province == null or province.special_sites.is_empty():
		return 0.0
	var total := 0.0
	for site in province.special_sites:
		if site != null and site.is_completed():
			total += site.trade_capacity
	return total


## Returns combined special site effects as a dictionary for easy consumption
func get_special_site_effects() -> Dictionary:
	return {
		"supply_bonus": get_special_site_supply_bonus(),
		"trade_capacity": get_special_site_trade_capacity(),
		"has_ports": province.has_special_site_of_type(SpecialSite.SiteType.PORT) if province else false,
		"has_airfields": province.has_special_site_of_type(SpecialSite.SiteType.AIRFIELD) if province else false,
		"special_site_count": province.special_sites.filter(func(s): return s != null and s.is_completed()).size() if province else 0
	}


func get_special_site_air_recon_bonus() -> float:
	if province == null or province.special_sites.is_empty():
		return 0.0
	var total := 0.0
	for site in province.special_sites:
		if site != null and site.is_completed() and site.site_type == SpecialSite.SiteType.AIRFIELD:
			# Pull from definition if we had a live lookup, for now use hardcoded scaling
			total += 8.0 * site.tier   # Tier 1 = +8 recon, Tier 2 = +16, etc.
	return total
