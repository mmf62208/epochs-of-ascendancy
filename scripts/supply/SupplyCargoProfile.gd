class_name SupplyCargoProfile
extends RefCounted

var cargo_tons: float = 0.0
var prefers_air: bool = false
var prefers_sea: bool = false
var land_ok: bool = true
## Pass 18: cargo kind for munitions-aware ammo UI (general | munitions | fuel | mixed).
var cargo_kind: String = "general"
## Fraction of cargo considered munitions/ammo (0–1). General supplies default ~0.35.
var munitions_fraction: float = 0.35


static func from_template(template: UnitTemplate, rules: SupplyRules, tonnage_override: float = -1.0) -> SupplyCargoProfile:
	var profile := SupplyCargoProfile.new()
	if template == null:
		return profile
	var routing := rules.get_block("routing")
	profile.cargo_tons = tonnage_override if tonnage_override >= 0.0 else template.get_stat("cargo_capacity", 0.0)
	var min_air := float(routing.get("min_cargo_capacity_for_airlift", 500.0))
	var min_sea := float(routing.get("min_cargo_capacity_for_sealift", 2000.0))
	var archetype := template.visual_archetype.to_lower()
	var base_type := template.base_type.to_lower()

	if profile.cargo_tons >= min_air or archetype.contains("transport") or base_type == "air":
		profile.prefers_air = profile.cargo_tons <= min_sea or base_type == "air"
	if profile.cargo_tons >= min_sea or base_type == "naval" or archetype.contains("cargo"):
		profile.prefers_sea = true
	if base_type == "naval":
		profile.land_ok = false
	elif base_type == "air":
		profile.land_ok = false
	# Munitions-heavy archetypes.
	if "ammo" in archetype or "munition" in archetype or "artillery" in archetype or "ordnance" in archetype:
		profile.cargo_kind = "munitions"
		profile.munitions_fraction = 0.85
	elif "fuel" in archetype or "tanker" in archetype:
		profile.cargo_kind = "fuel"
		profile.munitions_fraction = 0.1
	else:
		profile.cargo_kind = "general"
		profile.munitions_fraction = 0.35
	return profile


static func general_supplies(tons: float) -> SupplyCargoProfile:
	var p := SupplyCargoProfile.new()
	p.cargo_tons = tons
	p.land_ok = true
	p.cargo_kind = "general"
	p.munitions_fraction = 0.35
	return p


## Pass 18: dedicated munitions cargo profile for ammo-centric logistics.
static func munitions(tons: float) -> SupplyCargoProfile:
	var p := SupplyCargoProfile.new()
	p.cargo_tons = tons
	p.land_ok = true
	p.cargo_kind = "munitions"
	p.munitions_fraction = 0.9
	return p


## Effective munitions tons in this cargo shipment.
func munitions_tons() -> float:
	return maxf(0.0, cargo_tons * clampf(munitions_fraction, 0.0, 1.0))
