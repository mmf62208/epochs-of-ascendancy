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

## === SORTIE GENERATION & ENDURANCE MODEL (core of dynamic air warfare 1914-2026+) ===
## Realistic + fun: planes limited by fuel, pilot/org endurance, base proximity/infra, range config.
## Early eras: 1 (rarely 2) sorties/day typical (WWI, BoB limited loiter/fatigue).
## Mid: 1.5-2.5 with better planes.
## Late (jets + tankers/AWACS): 3-6+ sustained with support (Rolling Thunder costly due SAM, modern drones persistent).
## Not binary supremacy: even inferior can fly harassment if willing to pay (fuel/org/AA losses); full dominance still expensive to maintain.
## Recon critical for intel (feeds PI/naval/land). Jamming/Sat change calculus.
## Attrition: losses to AA/SAM/mech, but repair/rotate at airfields (supply + infra); strength/org recover, not total wipe.
## Hooks: called from Supply daily _process_air_missions, Formation, Resolver for CAS scale, BM tests.
## Factors: org/supply (abort/reduce), range vs base dist (config trade), infra/airfield at origin (resupply), leader air skill + doctrine, weather (from WM), tech (tanker/AWACS/stealth/jam/sat), era, carrier penalty.
func compute_effective_sorties(
	air_strength: float = 1.0,
	base_range_km: float = 600.0,
	current_org: float = 1.0,
	supply_level: float = 1.0,
	base_infra: int = 5,
	leader_air_skill: float = 0.5,  # 0-1 from air chief or assigned marshal
	doctrine_mod: float = 1.0,
	year: int = 1942,
	has_tanker_support: bool = false,
	has_awacs: bool = false,
	is_carrier_op: bool = false,
	enemy_aa_threat: float = 0.0,  # from registry or def_power aa_factor
	weather_eff: float = 1.0,  # from WeatherManager.get_air...
	jamming_mod: float = 1.0,  # <1 if enemy ECM active
	stealth_mod: float = 1.0   # >1 late stealth reduces effective AA
) -> Dictionary:
	if air_strength <= 0.0:
		return {"sorties": 0.0, "loiter": 1.0, "fuel_burn": 0.0, "abort_chance": 1.0, "readiness_impact": 0.0, "recon_points": 0.0, "notes": "no assets"}

	var era := float(year)
	# Base loiter/sortie potential from history/tech (WWI ~1, BoB ~1-2 defender advantage close base, late jets/tankers 3-5+)
	var base_loiter := clampf(1.0 + (era - 1916.0) * 0.06, 0.9, 3.5)
	if has_tanker_support:
		base_loiter *= 1.7  # historical tanker extension (Linebacker, modern)
	if has_awacs:
		base_loiter *= 1.4  # better control, night/coord -> more effective runs
	if is_carrier_op:
		base_loiter *= 0.75  # deck cycle, fuel/range tighter (Midway historical)
	# Tech era cap fun: pre-jet hard limit low
	if era < 1935 and base_loiter > 1.6:
		base_loiter = 1.6

	# Range / basing / config impact (from ADS profile already factored in caller base_range)
	var range_factor := clampf(base_range_km / 550.0, 0.4, 1.6)
	if range_factor > 1.3:
		base_loiter *= 0.65  # long range = fewer runs (fuel, time on station)
	elif range_factor < 0.8:
		base_loiter *= 1.15  # short hop = high tempo (BoB RAF)

	# Readiness (org + supply + base infra for rearm/repair/fuel) -- core endurance
	var readiness := clampf(current_org * 0.6 + supply_level * 0.4, 0.25, 1.6)
	readiness *= clampf(0.6 + float(base_infra) * 0.04, 0.7, 1.4)  # forward airfields key
	# Skill + doctrine (pilot training, air chief, spirits)
	var skill_mod := 0.75 + leader_air_skill * 0.8 + (doctrine_mod - 1.0) * 0.5
	readiness *= clampf(skill_mod, 0.6, 1.8)

	# Weather, jamming, stealth (SAM/jam heavy eras increase risk)
	var env_mod := clampf(weather_eff, 0.2, 1.3)
	env_mod *= clampf(jamming_mod, 0.5, 1.4)
	env_mod *= clampf(stealth_mod, 0.8, 1.6)  # stealth counters AA/jam
	readiness *= env_mod

	# AA/SAM threat: increases abort, reduces effective even if dominance
	var aa_impact := clampf(1.0 - enemy_aa_threat * 0.45, 0.4, 1.1) * (1.0 + (stealth_mod - 1.0) * 0.8)
	readiness *= aa_impact

	# Compute max/effective sorties (multiple runs if high readiness + support)
	var max_possible := base_loiter * 1.1
	var effective_sorties := clampf(max_possible * readiness * 0.9 + randf() * 0.3, 0.4, max_possible * 1.3)
	# Intensity (from formation) caller can scale post; here base gen
	# Early war hard cap realism
	if era < 1930:
		effective_sorties = min(effective_sorties, 1.4)

	# Abort/reduced if bad readiness (historical: many aborts or jettison)
	var abort_chance := clampf(0.05 + (1.0 - readiness) * 0.55 + enemy_aa_threat * 0.25, 0.0, 0.75)
	if effective_sorties < 0.9 or readiness < 0.55:
		effective_sorties *= 0.55
		abort_chance = max(abort_chance, 0.4)

	# Fuel burn for mission (consumed from origin depot or stock; ties Supply fuel)
	var fuel_burn := effective_sorties * (base_range_km / 450.0) * (1.35 if is_carrier_op else 1.0)
	fuel_burn *= (0.85 if has_tanker_support else 1.0)  # tankers help efficiency too but consume themselves
	# Config penalty baked in caller range, here slight
	fuel_burn = clampf(fuel_burn, 0.1, 25.0)

	# Loiter factor for CAS/interdict effect scaling (more time = better ground effect per sortie wave)
	var loiter_factor := clampf(base_loiter * 0.7 + (effective_sorties - 1.0) * 0.25, 1.0, 4.5)

	# Recon points (only high value if RECON mission; caller checks mission)
	var recon_points := effective_sorties * 0.8 * (1.0 + (has_awacs as int) * 1.2 + (stealth_mod - 1.0) * 0.5) * env_mod
	if is_carrier_op: recon_points *= 0.7

	# Post-mission readiness impact (fatigue, rearm time; recoverable at base with supply)
	var readiness_impact := clampf( -0.08 * effective_sorties - (fuel_burn * 0.01), -0.45, -0.02)

	var notes := "era%.0f loiter~%.1f rdy%.2f aa%.2f jam%.2f" % [era, base_loiter, readiness, enemy_aa_threat, jamming_mod]
	if has_tanker_support or has_awacs:
		notes += " +tanker/awacs"
	if abort_chance > 0.3:
		notes += " HIGH_ABORT_RISK"

	return {
		"sorties": clampf(effective_sorties, 0.3, 8.0),
		"loiter": loiter_factor,
		"fuel_burn": fuel_burn,
		"abort_chance": abort_chance,
		"readiness_impact": readiness_impact,
		"recon_points": recon_points,
		"notes": notes,
		"effective_readiness": clampf(readiness, 0.3, 1.6)
	}

## Apply post-mission attrition to air assets (called from Supply/Resolver after sorties).
## Not total elimination: attrit strength/org, but repairable at friendly airfields (infra + supply).
## High AA/SAM (late eras) or poor readiness = higher pilot/plane losses (historical costly).
func apply_air_mission_attrition(
	formation_strength: float,
	enemy_aa: float,
	sorties: float,
	weather_penalty: float = 1.0,
	stealth_factor: float = 1.0
) -> Dictionary:
	var loss_base := enemy_aa * 0.12 * sorties * (1.0 / maxf(stealth_factor, 0.6))
	loss_base *= clampf(weather_penalty, 0.7, 1.4)
	var mech_fail := 0.03 * sorties * (1.0 if weather_penalty < 0.8 else 1.3)  # reliability implicit
	var total_loss := clampf(loss_base + mech_fail, 0.0, 0.65)  # cap never wipe
	var new_strength := clampf(formation_strength - total_loss * 0.7, 0.25, 1.0)  # strength hit
	var org_hit := total_loss * 0.5
	return {
		"strength_loss": total_loss,
		"new_strength": new_strength,
		"org_hit": org_hit,
		"notes": "AA/mech attrition %.1f%% (stealth %.1f, sorties %.1f)" % [total_loss*100, stealth_factor, sorties]
	}
