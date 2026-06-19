# scripts/air/AirMissionProfile.gd
class_name AirMissionProfile
extends Resource

## Basic skeleton for air mission planning, integrating with AircraftDesignSystem.
## Can be used by formations, Supply, Combat for range, payload, effectiveness modifiers.
## Builds on ADS for prototyping/reliability/range tradeoffs.
## Human can create instances or extend for full mission UI/planning.

@export var formation_id: String = ""
@export var design_id: String = ""
@export var range_config: String = "COMBAT_LOAD"  # Ferry, Combat, Escort
@export var mission_type: String = "NONE"  # RECON, CAS, etc. from Formation air missions
@export var intensity: float = 1.0  # aggressiveness: higher = more sorties, more supply cost, stronger effect (round-the-clock ops need more supplies)

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

## Rough mission effectiveness modifier (range + reliability from ADS + mission type + intensity + doctrines/tech).
func get_mission_modifier() -> float:
	var base := 1.0
	if _ads and _ads.has_method("get_formation_air_modifier"):
		# Create temp formation-like for demo
		var temp_form := {
			"get_air_design_id": func(): return design_id,
			"get_air_range_config_enum": func(): return _range_config_to_enum()
		}
		base = _ads.get_formation_air_modifier(temp_form)
	# Mission type bonuses (recon for intel, CAS for ground, interdiction for supply, etc.)
	match mission_type:
		"RECON":
			base *= 1.2  # better spotting/recon %
		"CLOSE_AIR_SUPPORT", "CAS":
			base *= 1.15  # ground support bonus
		"INTERDICTION":
			base *= 1.1  # supply disruption
		"STRATEGIC_BOMBING":
			base *= 0.9  # long range, but infra damage
		"AIR_SUPERIORITY":
			base *= 1.1
		"NAVAL_STRIKE":
			base *= 1.25  # vs ships
		"TRANSPORT":
			base *= 0.95
		_:
			pass
	# Intensity: higher = stronger effect but scales cost/risk (e.g. more supplies for round-the-clock)
	base *= (0.8 + intensity * 0.3)
	# Doctrines/tech example: radio improves org/coordination for air missions at high intensity.
	# Proximity shells etc. in AA context.
	return clampf(base, 0.3, 2.0)

## Example: payload penalty based on config (for bombing missions etc).
func get_payload_multiplier() -> float:
	match range_config:
		"FERRY_LONG_RANGE", "ferry": return 0.4
		"ESCORT_BALANCED", "escort": return 0.8
		_: return 1.0

## Intensity cost: higher aggressiveness (round-the-clock air ops) requires more supplies/fuel/maintenance.
## Doctrines/tech (e.g. better logistics, engine reliability) can reduce cost.
func get_intensity_supply_cost(base_cost: float = 1.0, tech_logistics_mod: float = 1.0) -> float:
	var cost := base_cost * (0.7 + intensity * 0.6)  # high intensity more costly
	cost /= tech_logistics_mod  # tech reduces (e.g. better fuel efficiency)
	return clampf(cost, 0.5, 3.0)

## Recon % success for RECON mission (based on intensity, design, weather/doctrine).
## Higher intensity = more % but higher risk/cost. Radios/tech improve org/coordination.
func get_recon_success_pct(base_pct: float = 50.0, weather_mod: float = 1.0, doctrine_mod: float = 1.0) -> float:
	var pct := base_pct
	if mission_type == "RECON":
		pct *= (0.8 + intensity * 0.4)  # intensity boosts sorties/recon coverage
		pct *= weather_mod
		pct *= doctrine_mod  # e.g. air doctrine, radio for better reporting.
	return clampf(pct, 10.0, 95.0)

## Can be extended for full mission: fuel cost, abort chance (from reliability), etc.
## Integrate with Supply for air cargo/fuel, Combat for strike effectiveness.
## Attach to ships: air support for naval strike/bombard in amphib/land battles.