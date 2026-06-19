# scripts/air/AirMissionProfile.gd
class_name AirMissionProfile
extends Resource

## Basic skeleton for air mission planning, integrating with AircraftDesignSystem.
## Can be used by formations, Supply, Combat for range, payload, effectiveness modifiers.
## Builds on ADS for prototyping/reliability/range tradeoffs.
## Human can create instances or extend for full mission UI/planning.
##
## Enhanced for continuous air superiority system (large regions require overwhelming force):
## - compute_air_power factors missions (AIR_SUPERIORITY weights higher for contest), assets, doctrine, tech (radar/jets).
## - get_contested_airspace_cost_mult models extra drain for disadv or maintaining sup (costly even when winning).

@export var formation_id: String = ""
@export var design_id: String = ""
@export var range_config: String = "COMBAT_LOAD"  # Ferry, Combat, Escort

var _ads: Node = null  # AircraftDesignSystem ref

func _init(f_id: String = "", d_id: String = "", cfg: String = "COMBAT_LOAD") -> void:
	formation_id = f_id
	design_id = d_id
	range_config = cfg
	_ads = _find_ads()

func _find_ads() -> Node:
	# Try to find ADS (created in Debug or root)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var debug := tree.get_first_node_in_group("debug_overlay")
		if debug and debug.has_method("_get_or_create_aircraft_design_system"):
			return debug.call("_get_or_create_aircraft_design_system")
	return null

## Compute effective range for this profile (uses ADS if available).
func get_effective_range(base_range: float = 1000.0, base_province: int = -1) -> float:
	if _ads and _ads.has_method("get_effective_range"):
		var cfg_enum := _range_config_to_enum()
		return _ads.get_effective_range(base_range, design_id, cfg_enum, base_province)
	return base_range

func _range_config_to_enum() -> int:
	match range_config:
		"FERRY_LONG_RANGE", "ferry": return 0
		"ESCORT_BALANCED", "escort": return 2
		_: return 1

## Rough mission effectiveness modifier (range + reliability from ADS).
func get_mission_modifier() -> float:
	if _ads and _ads.has_method("get_formation_air_modifier"):
		# Create temp formation-like for demo
		var temp_form := {
			"get_air_design_id": func(): return design_id,
			"get_air_range_config_enum": func(): return _range_config_to_enum()
		}
		return _ads.get_formation_air_modifier(temp_form)
	return 1.0

## Example: payload penalty based on config (for bombing missions etc).
func get_payload_multiplier() -> float:
	match range_config:
		"FERRY_LONG_RANGE", "ferry": return 0.4
		"ESCORT_BALANCED", "escort": return 0.8
		_: return 1.0

## Compute contribution to air power (for superiority calculation, continuous not binary).
## air_strength: from formation strength or unit count equiv (assets).
## mission: current air mission affects weighting (dedicated AIR_SUPERIORITY missions contribute more to air dominance/contest; CAS/Interdict less optimal for air-air).
## doctrine_mod, tech_mod: from air chiefs, research (advanced radar, jets, better avionics give advantage e.g. 1.4x).
## Used by ProvinceInsight preview, CombatResolver for CAS scaling, Supply for costs.
func compute_air_power(air_strength: float = 1.0, mission: String = "", doctrine_mod: float = 1.0, tech_mod: float = 1.0) -> float:
	if air_strength <= 0.0:
		return 0.0
	var power := air_strength * 12.0  # scaling to make 3:1-5:1 ratios meaningful for large provinces/regions
	# Base from ADS + config (maturity, reliability, range tradeoffs)
	var ads_mod := get_mission_modifier()
	power *= ads_mod
	# Mission weighting: AIR_SUPERIORITY dedicated fighter/escort ops for winning air war
	match mission:
		"AIR_SUPERIORITY":
			power *= 1.9  # high weight for contesting sky, escort, suppression
		"CAS", "CLOSE_AIR_SUPPORT":
			power *= 0.65  # ground attack birds (fighters/bombers) less optimal vs enemy fighters for air sup
		"INTERDICTION":
			power *= 0.75  # strike birds split focus
		"RECON":
			power *= 0.4
		"STRATEGIC_BOMBING", "NAVAL_STRIKE":
			power *= 0.55
		_:
			power *= 0.9
	# Tech: advanced radar, jets, avionics, ECM multiply effectiveness (satisfying tech edge)
	power *= clampf(tech_mod, 0.4, 3.0)
	# Doctrine: pilot training, air doctrine (e.g. from chief_of_air_force, spirits)
	power *= clampf(doctrine_mod, 0.5, 2.5)
	return maxf(0.05, power)

## Extra supply/fuel drain when operating in contested or inferior airspace.
## Disadvantaged side pays heavy (high losses, reduced effect). Even overwhelming requires costly sustained ops.
## Used in SupplyManager consumption for air and ground formations in the province.
## air_power_ratio: our_air / enemy_air ( >1 advantaged)
## is_advantaged: based on ratio
func get_contested_airspace_cost_mult(air_power_ratio: float = 1.0, is_advantaged: bool = true) -> float:
	if air_power_ratio <= 0.0:
		air_power_ratio = 0.01
	if is_advantaged:
		# Maintaining sup in large region is expensive (sorties, fuel, maintenance, AA risk)
		if air_power_ratio >= 4.0:
			return 1.65  # full dominance still costly to press advantage
		elif air_power_ratio >= 2.0:
			return 1.35
		return 1.15 + clampf((air_power_ratio - 1.0) * 0.2, 0.0, 0.5)
	else:
		# Disadv: much higher cost, reduced effect (like HoI4: you can still fly but bleed planes/supply)
		if air_power_ratio < 0.33:  # <1:3
			return 3.1
		return 1.7 + clampf( (1.0 / max(air_power_ratio, 0.2)) * 0.8 , 0.0, 2.5)

## Can be extended for full mission: fuel cost, abort chance (from reliability), etc.
## Integrate with Supply for air cargo/fuel, Combat for strike effectiveness.