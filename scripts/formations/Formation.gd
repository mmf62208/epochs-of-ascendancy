# scripts/formations/Formation.gd
class_name Formation
extends Resource

const TYPE_DIVISION := "division"
const TYPE_ARMY := "army"
const TYPE_ARMY_GROUP := "army_group"
const TYPE_GARRISON := "garrison"
const TYPE_BRIGADE := "brigade"
const TYPE_FLEET := "fleet"
const TYPE_TASK_FORCE := "task_force"
const TYPE_SHIP := "ship"
const TYPE_AIR_WING := "air_wing"
const TYPE_AIR_SQUADRON := "air_squadron"
const TYPE_AIR_GROUP := "air_group"
const TYPE_SPACE_WING := "space_wing"
const TYPE_ORBITAL_GROUP := "orbital_group"

const CATEGORY_LAND := "land"
const CATEGORY_NAVAL := "naval"
const CATEGORY_AIR := "air"
const CATEGORY_SPACE := "space"

# Overarching naval orders/missions, inspired by HOI4 (Patrol, Convoy Escort, Strike Force, etc.), Rule the Waves, and other grand-strat naval games.
# Applied at fleet/task force level; affect spotting, stealth, engagement range, supply protection, interdiction in sea zones.
# Interact with ship class (subs stealthy in S&D), weather (storms favor stealthy orders), chokepoints (search easier in straits), groups (larger fleets better coverage).
const NAVAL_ORDER_NONE := "NONE"
const NAVAL_ORDER_CONVOY_DUTY := "CONVOY_DUTY"  # Protect trade/supply routes; boosts escort, reduces own detection but high protection mod
const NAVAL_ORDER_SEARCH_PATROL := "SEARCH_PATROL"  # Active search in sea zone; high detection/spot chance, good recon, exposed
const NAVAL_ORDER_SEARCH_AND_DESTROY := "SEARCH_AND_DESTROY"  # Aggressive S&D/raiding; high engage chance, good vs subs/convoys, subs excel in stealth
const NAVAL_ORDER_ESCORT := "ESCORT"  # Defensive escort for convoys/transports; visibility/stealth bonus for protected, counter-strike
const NAVAL_ORDER_STRIKE := "STRIKE"  # Offensive strike on detected enemy; range/engage bonus in good vis, carrier/air heavy
const NAVAL_ORDER_TRANSPORT := "TRANSPORT"  # Amphib/logistics support; low profile, bonus to supply delivery, vulnerable if spotted
const NAVAL_ORDER_AMBUSH := "AMBUSH"  # Sub/stealth focused (esp subs); low vis bonus in storms/night/straits, high surprise in close range
const NAVAL_ORDER_MINELAY := "MINELAY"  # Lay mines in sea; adds persistent threat to enemy movement/supply in zone (straits deadly)
const NAVAL_ORDER_ASW := "ASW"  # Anti-sub warfare; boosts detection vs subs, counters S&D/AMBUSH subs

# Air missions, inspired by HOI4 (Air Superiority, CAS, Interdiction, Strategic Bombing, Naval Strike, etc.), other games like Steel Division/Graviteam for recon/bombing intensity.
# Overarching orders for air wings/squadrons/groups.
const AIR_MISSION_NONE := "NONE"
const AIR_MISSION_RECON := "RECON"  # Scouting, intel, spot enemy, boost land/naval detection. % recon success based on planes, tech, weather, doctrine.
const AIR_MISSION_CLOSE_AIR_SUPPORT := "CAS"  # Support ground attacks/defense. Bonus to land combat power/org.
const AIR_MISSION_INTERDICTION := "INTERDICTION"  # Disrupt enemy supply/movement. Increase interdiction chance on routes.
const AIR_MISSION_STRATEGIC_BOMBING := "STRATEGIC_BOMBING"  # Target factories/infra. Damage production, morale.
const AIR_MISSION_AIR_SUPERIORITY := "AIR_SUPERIORITY"  # Contest sky, escort, reduce enemy air. Affects other air missions.
const AIR_MISSION_NAVAL_STRIKE := "NAVAL_STRIKE"  # Attack ships/fleets. Bonus vs naval, with naval spotting.
const AIR_MISSION_TRANSPORT := "TRANSPORT"  # Airlift supplies/troops. Supply delivery bonus, paradrop potential.

# Land unit missions/assignments, inspired by HOI4 division orders (Assault, Defend, etc.), other games like Unity of Command or Graviteam for orders.
# Overarching for divisions/armies.
const LAND_MISSION_NONE := "NONE"
const LAND_MISSION_ASSAULT := "ASSAULT"  # Aggressive attack. Bonus attack power, but higher org loss/risk.
const LAND_MISSION_DEFEND := "DEFEND"  # Hold position. Bonus defense, org recovery, counter-battery if tech.
const LAND_MISSION_PATROL := "PATROL"  # Secure area, recon. Boost local detection, lower intensity.
const LAND_MISSION_ADVANCE := "ADVANCE"  # Move and fight. Movement speed + combat, supply use.
const LAND_MISSION_GARRISON := "GARRISON"  # Occupy, low intensity. Stability, lower attrition.
const LAND_MISSION_ARTILLERY_PREP := "ARTILLERY_PREP"  # Pre-bombard before assault. Bonus if counter-battery planning/tech (radios, precalc fire).

# Intensity/aggressiveness level (0.5 conservative/sustainable, 1.0 normal, 1.5+ aggressive/round-the-clock).
# Higher = more sorties/missions (higher supply/fuel/maintenance cost, higher risk/attrition, but stronger effect).
# Doctrines/tech (e.g., radio for org, proximity shells for AA, counter-battery doctrine) modify.
@export var mission_intensity: float = 1.0

@export var formation_id: String = ""
@export var name: String = ""
@export var formation_type: String = TYPE_DIVISION
@export var country_tag: String = ""
@export var leader_id: String = ""
@export var parent_formation_id: String = ""
@export var is_training: bool = false
@export var is_in_combat: bool = false
@export var training_progress: float = 0.0  # days invested in training (full daily advance per roadmap)
@export var is_trained: bool = false  # reached threshold for combat bonus (readiness/org/xp)
@export var combat_log: Array[Dictionary] = []  # per-unit combat history: {date, province_id, result, key_factors: Array[String], leader: String, outcome: String} - follows unit like leader logs
## Map province where this formation is stationed (division movement / engineer repair).
@export var stationed_province_id: int = -1

## For air formations: current range/loadout config chosen by player (Ferry_Long_Range, Combat_Load, Escort_Balanced).
## Used by AircraftDesignSystem for effective range calculations.
@export var air_range_config: String = "COMBAT_LOAD"

## Design/template id for land (division) or general unit design (e.g. "panzer_iii_medium", "german_infantry_division_1943" from data/unit_templates/*.json or production lines).
@export var design_id: String = ""

## Links air formation to a specific design in AircraftDesignSystem for range/reliability/prototyping effects.
@export var air_design_id: String = ""

## Naval/ship design id for fleets, task forces, ships (e.g. "u_boat_type_vii", "fletcher_class_destroyer", "hms_king_george_v_bb" from unit_templates).
@export var naval_design_id: String = ""

## Current overarching naval order for this formation (fleet/task force/ship group).
## Affects detection, stealth, engagement, supply in sea provinces. See consts above.
@export var current_naval_order: String = NAVAL_ORDER_NONE

## Current air mission for air formations (or attached air support).
@export var current_air_mission: String = AIR_MISSION_NONE

## Current land mission for land formations.
@export var current_land_mission: String = LAND_MISSION_NONE

## Attached air support formation id (air wing/squadron attached to fleet/army/division for support missions, naval bombardment, etc.).
## Ships can have attached aircraft/helicopters/drones for recon, strike, ASW.
@export var attached_air_formation_id: String = ""

## Persistent combat state (org/readiness/strength) for main combat loop.
## These are the "health" of the formation across battles; fresh designs start at full (1.0).
## Reduced by combat losses (BattleManager/Resolver), recovered via supply + infra + time (SupplyManager).
## Doctrine shifts also hit these directly (see LeaderManager _apply_doctrine_change_penalties).
@export var organization: float = 1.0
@export var readiness: float = 1.0
@export var strength: float = 1.0  # 1.0 = full TOE; <1.0 from unreplaced casualties (future: manpower/equip tracking)
## Formation troop combat experience band 0–100 (RF1). Diluted by green manpower; rearm hits lightly.
## Green 0–20 · trained 21–40 · regular 41–60 · seasoned 61–80 · veteran 81–100.
@export var combat_experience: float = 48.0
@export var fuel_level: float = 1.0  # for naval (and future air/land vehicles): 1.0 full, low = reduced power/speed, vuln in combat; consumed on ops, resupplied at hubs/ports/tenders. Naval long endurance but limited.

## Runtime land-battle depth. planning / entrenchment / combat_experience persist in LeaderManager save.
var last_equip_loss: Dictionary = {}
var last_equip_loss_plain: String = ""
var last_manpower_loss: int = 0
var last_supply_plain: String = ""
var planning: float = 0.0
var entrenchment: float = 0.0

var assigned_leader: Leader = null
## Alias of leader_id for LandCombatPower commander lookup (not separately persisted).
var assigned_leader_id: String:
	get:
		return leader_id
	set(value):
		leader_id = str(value)


func has_leader() -> bool:
	return not leader_id.is_empty()


func assign_leader(leader: Leader) -> bool:
	if leader == null:
		return false
	leader_id = leader.leader_id
	assigned_leader = leader
	return true


func remove_leader() -> void:
	leader_id = ""
	assigned_leader = null


func get_category() -> String:
	match formation_type:
		TYPE_FLEET, TYPE_TASK_FORCE, TYPE_SHIP:
			return CATEGORY_NAVAL
		TYPE_AIR_WING, TYPE_AIR_SQUADRON, TYPE_AIR_GROUP:
			return CATEGORY_AIR
		TYPE_SPACE_WING, TYPE_ORBITAL_GROUP:
			return CATEGORY_SPACE
		_:
			return CATEGORY_LAND


static func from_division_template(
	division_id: String,
	div_template: DivisionTemplate,
	country: String,
) -> Formation:
	var formation := Formation.new()
	formation.formation_id = division_id
	formation.name = div_template.display_name if not div_template.display_name.is_empty() else division_id
	formation.formation_type = TYPE_DIVISION
	formation.country_tag = country
	formation.organization = 1.0
	formation.readiness = 1.0
	formation.strength = 1.0
	return formation

## Helper for air range config (used by AircraftDesignSystem and mission planning).
func get_air_range_config_enum() -> int:
	# Matches AircraftDesignSystem.RangeConfig
	match air_range_config:
		"FERRY_LONG_RANGE", "ferry": return 0
		"ESCORT_BALANCED", "escort": return 2
		_: return 1  # COMBAT_LOAD default

func set_air_range_config_from_string(cfg: String) -> void:
	air_range_config = cfg.to_upper() if cfg else "COMBAT_LOAD"

func get_air_design_id() -> String:
	return air_design_id

func set_air_design_id(did: String) -> void:
	air_design_id = did

## Naval detection / spotting support for strategic naval simulator.
## Visibility (signature): higher = easier to spot (large surface ships). Subs low.
## Detection contrib: from own sensors (radar/sonar/plane) + size of group.
func get_naval_visibility() -> float:
	if get_category() != CATEGORY_NAVAL:
		return 1.0
	var n = name.to_lower()
	if "sub" in n or formation_type == TYPE_SHIP and "sub" in n:
		return 0.25  # subs very hard to spot
	if "destroyer" in n or "frigate" in n or "corvette" in n or "patrol" in n:
		return 0.55
	if "cruiser" in n or "destroyer leader" in n:
		return 0.7
	if "carrier" in n or "battleship" in n or "battlecruiser" in n:
		return 1.3  # capital ships large signature
	if "task force" in n or "fleet" in n:
		return 1.0  # group average
	return 0.8

## Base contribution to spotting enemy (own search capability).
func get_naval_detection_contrib() -> float:
	if get_category() != CATEGORY_NAVAL:
		return 0.0
	var base := 0.4
	var n = name.to_lower()
	if "radar" in n or "sonar" in n:  # from name or future modules
		base += 0.3
	if "carrier" in n:  # air search
		base += 0.5
	if "fleet" in n or "task force" in n:
		base += 0.3  # more assets
	# Group size bonus (more ships = better coverage, harder to hide from)
	# In real would count subunits; for demo use formation "weight"
	base += 0.2
	return clamp(base, 0.1, 2.0)

## For a fleet, estimated "size" for detection scaling (number of major units).
func get_estimated_ship_count() -> int:
	if get_category() != CATEGORY_NAVAL:
		return 0
	var n = name.to_lower()
	if "fleet" in n: return 8
	if "task force" in n: return 4
	if "sub" in n: return 1
	return 2  # single ship or small

## Mod for straits/chokepoints: less room to hide, easier search.
func get_chokepoint_detection_mod(pid: int) -> float:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
		if MapManager.has_strategic_chokepoint(pid):
			return 1.6  # significantly higher chance in narrow waters
	return 1.0

## Get detection/spotting modifier from current naval order.
## SEARCH_PATROL: high detect. S&D: aggressive. CONVOY/ESCORT/TRANSPORT: lower profile.
## Stacks with ship visibility (subs in S&D/AMBUSH get extra stealth), weather, groups, chokepoints.
func get_naval_order_detection_mod() -> float:
	match current_naval_order:
		NAVAL_ORDER_SEARCH_PATROL, NAVAL_ORDER_SEARCH_AND_DESTROY:
			return 1.4  # active search boosts spot chance (own and vs enemy)
		NAVAL_ORDER_STRIKE:
			return 1.2
		NAVAL_ORDER_AMBUSH:
			return 0.7  # stealthy, lower detect but higher surprise
		NAVAL_ORDER_ASW:
			return 1.3  # ASW boosts vs subs
		NAVAL_ORDER_CONVOY_DUTY, NAVAL_ORDER_ESCORT, NAVAL_ORDER_TRANSPORT, NAVAL_ORDER_MINELAY:
			return 0.85  # defensive or minelay less aggressive spotting
		_:
			return 1.0

## Stealth / reduced visibility mod from order (for being spotted).
## Subs in AMBUSH/S&D very stealthy in low vis; large surface in CONVOY exposed.
func get_naval_order_stealth_mod() -> float:
	match current_naval_order:
		NAVAL_ORDER_AMBUSH:
			return 0.6  # hard to spot
		NAVAL_ORDER_SEARCH_AND_DESTROY:
			return 0.8
		NAVAL_ORDER_CONVOY_DUTY, NAVAL_ORDER_ESCORT:
			return 1.1  # slightly more visible when protecting
		NAVAL_ORDER_TRANSPORT:
			return 1.15
		NAVAL_ORDER_SEARCH_PATROL, NAVAL_ORDER_STRIKE:
			return 1.0
		NAVAL_ORDER_MINELAY:
			return 1.2  # minelaying exposes
		NAVAL_ORDER_ASW:
			return 0.9
		_:
			return 1.0

## Engagement / combat range/power mod from order + visibility context.
## Low vis/storm/night (vis<0.5) + AMBUSH/S&D -> closer range (subs/torps advantage).
## Good vis + STRIKE/CONVOY -> stand-off (guns/carriers/air).
## Straights (chokepoint) force closer regardless.
func get_naval_order_engagement_mod(visibility: float = 1.0, is_chokepoint: bool = false) -> Dictionary:
	var base_range := 1.0  # 1.0 = normal, <1 closer (sub/torp), >1 stand-off (air/gun)
	var power_mod := 1.0
	var closer_chance := false

	match current_naval_order:
		NAVAL_ORDER_AMBUSH, NAVAL_ORDER_SEARCH_AND_DESTROY:
			base_range = 0.7
			if visibility < 0.5 or is_chokepoint:
				base_range *= 0.6  # even closer in storm/night/strait; sub advantage
				closer_chance = true
				power_mod = 1.15
		NAVAL_ORDER_STRIKE:
			base_range = 1.3
			power_mod = 1.1
			if visibility < 0.5:
				base_range = 0.9  # storm hurts long range
		NAVAL_ORDER_CONVOY_DUTY, NAVAL_ORDER_ESCORT:
			base_range = 0.9
			if visibility < 0.5 or is_chokepoint:
				closer_chance = true
		NAVAL_ORDER_SEARCH_PATROL:
			base_range = 1.0
			if is_chokepoint:
				base_range = 0.8  # straits = closer fights
		NAVAL_ORDER_MINELAY:
			base_range = 0.85  # minelay forces careful/closer
			power_mod = 0.9
		NAVAL_ORDER_ASW:
			base_range = 0.95
			if visibility < 0.5:
				power_mod = 1.1  # ASW better vs subs in low vis
		_:
			pass

	if is_chokepoint:
		base_range = min(base_range, 0.85)  # narrow waters limit long range, easier search/closer
		power_mod *= 1.1

	return {
		"range_mod": clamp(base_range, 0.3, 1.5),
		"power_mod": power_mod,
		"closer_engagement": closer_chance or visibility < 0.5 or is_chokepoint,
		"order": current_naval_order
	}

## Supply/convoy protection or interdiction mod from order.
## CONVOY_DUTY/ESCORT: protect trade, reduce interdiction on own routes.
## S&D/STRIKE: increase interdiction on enemy.
func get_naval_order_supply_mod(is_protecting: bool = true) -> float:
	match current_naval_order:
		NAVAL_ORDER_CONVOY_DUTY, NAVAL_ORDER_ESCORT:
			return 1.25 if is_protecting else 0.9
		NAVAL_ORDER_SEARCH_AND_DESTROY, NAVAL_ORDER_STRIKE:
			return 0.85 if is_protecting else 1.3  # raiding bonus
		NAVAL_ORDER_TRANSPORT:
			return 1.15 if is_protecting else 1.0
		NAVAL_ORDER_MINELAY:
			return 0.9 if is_protecting else 1.2  # minelay threatens enemy supply
		NAVAL_ORDER_ASW:
			return 1.1 if is_protecting else 0.95  # ASW helps protect vs sub threats
		_:
			return 1.0

func set_naval_order(order: String) -> void:
	if order in [NAVAL_ORDER_NONE, NAVAL_ORDER_CONVOY_DUTY, NAVAL_ORDER_SEARCH_PATROL, NAVAL_ORDER_SEARCH_AND_DESTROY, NAVAL_ORDER_ESCORT, NAVAL_ORDER_STRIKE, NAVAL_ORDER_TRANSPORT, NAVAL_ORDER_AMBUSH, NAVAL_ORDER_MINELAY, NAVAL_ORDER_ASW]:
		current_naval_order = order
	else:
		current_naval_order = NAVAL_ORDER_NONE

## Set air mission (overarching order for air ops).
func set_air_mission(mission: String) -> void:
	if mission in [AIR_MISSION_NONE, AIR_MISSION_RECON, AIR_MISSION_CLOSE_AIR_SUPPORT, AIR_MISSION_INTERDICTION, AIR_MISSION_STRATEGIC_BOMBING, AIR_MISSION_AIR_SUPERIORITY, AIR_MISSION_NAVAL_STRIKE, AIR_MISSION_TRANSPORT]:
		current_air_mission = mission
	else:
		current_air_mission = AIR_MISSION_NONE

## Set land mission (overarching order for ground units).
func set_land_mission(mission: String) -> void:
	if mission in [LAND_MISSION_NONE, LAND_MISSION_ASSAULT, LAND_MISSION_DEFEND, LAND_MISSION_PATROL, LAND_MISSION_ADVANCE, LAND_MISSION_GARRISON, LAND_MISSION_ARTILLERY_PREP]:
		current_land_mission = mission
	else:
		current_land_mission = LAND_MISSION_NONE

## Set mission intensity/aggressiveness (0.5-2.0+). Higher = more missions/sorties (e.g. round-the-clock air ops needs more supplies/fuel), stronger effects but higher cost/risk/attrition.
## Doctrines/tech (radio for org, proximity AA, counter-battery planning) modify effective intensity or bonuses.
func set_mission_intensity(level: float) -> void:
	mission_intensity = clampf(level, 0.5, 2.5)

## Get effective intensity mod, factoring doctrine/tech (e.g. radio improves org at high intensity; proximity shells boost AA vs air missions).
func get_effective_intensity_mod(tech_mod: float = 1.0, doctrine_mod: float = 1.0) -> float:
	var base := mission_intensity
	# Radio/tech for better coordination at high intensity (less org loss in move/attack/defend).
	if tech_mod > 1.0:
		base *= (1.0 + (tech_mod - 1.0) * 0.5)  # e.g. radios allow higher org at aggressive levels.
	return clampf(base * doctrine_mod, 0.5, 3.0)

## Get mission-specific modifiers (detection, combat power, supply cost, etc.).
## For air: recon % for RECON, CAS bonus, interdiction for INTERDICTION, etc.
## For land: assault power, defend org, artillery prep bonus (counter-battery if doctrine/tech).
## Intensity scales the effect and cost.
## Doctrines/tech impact: e.g. radio for org, counter-battery planning for defenders, proximity shells for AA vs air.
func get_mission_mods() -> Dictionary:
	var mods := {
		"effect": 1.0,
		"supply_cost_mult": 1.0,
		"risk_mult": 1.0,
		"org_mod": 1.0,  # higher intensity may hurt org unless radio/doctrine.
		"detection_bonus": 0.0,
		"combat_bonus": 0.0,
		"interdiction": 0.0,
		"aa_vs_air": 0.0,  # for proximity shells/tech.
	}
	var intensity = mission_intensity
	mods["supply_cost_mult"] = 0.8 + intensity * 0.4  # more intense = more supplies (fuel, ammo, maintenance).
	mods["risk_mult"] = 0.7 + intensity * 0.5
	mods["org_mod"] = 1.0 - (intensity - 1.0) * 0.1  # aggressive hurts org unless mitigated.

	# Air mission specific
	match current_air_mission:
		AIR_MISSION_RECON:
			mods["effect"] = 1.0 + (intensity - 1.0) * 0.3
			mods["detection_bonus"] = 0.2 + intensity * 0.2  # recon % boost to land/naval spotting.
			mods["supply_cost_mult"] *= 0.7  # recon lighter.
		AIR_MISSION_CLOSE_AIR_SUPPORT:
			mods["combat_bonus"] = 0.1 + intensity * 0.15  # CAS to land battles.
		AIR_MISSION_INTERDICTION:
			mods["interdiction"] = 0.05 + intensity * 0.1
		AIR_MISSION_STRATEGIC_BOMBING:
			mods["effect"] = 0.8 + intensity * 0.3  # infra/prod damage.
		AIR_MISSION_AIR_SUPERIORITY:
			mods["effect"] = 1.0 + intensity * 0.2
			mods["aa_vs_air"] = 0.1  # contest air.
		AIR_MISSION_NAVAL_STRIKE:
			mods["combat_bonus"] = 0.15 + intensity * 0.2  # vs naval.
		AIR_MISSION_TRANSPORT:
			mods["supply_cost_mult"] *= 1.2  # airlift costs.
			mods["effect"] = 0.9 + intensity * 0.2

	# Land mission specific
	match current_land_mission:
		LAND_MISSION_ASSAULT:
			mods["combat_bonus"] = 0.15 + intensity * 0.2
			mods["org_mod"] -= 0.1  # aggressive.
		LAND_MISSION_DEFEND:
			mods["combat_bonus"] = 0.1
			mods["org_mod"] += 0.1
			# Counter-battery/precalc fire if doctrine/tech (radios, planning): quick artillery assign.
			mods["aa_vs_air"] += 0.05  # example, or artillery defense.
		LAND_MISSION_ARTILLERY_PREP:
			mods["combat_bonus"] = 0.2  # pre-bombard bonus to subsequent assault.
			mods["interdiction"] = 0.05  # disrupts enemy.
		LAND_MISSION_PATROL:
			mods["detection_bonus"] = 0.1
			mods["supply_cost_mult"] *= 0.8

	# Tech/doctrine impacts (e.g. from TechnologyManager or doctrines).
	# Radio: higher org for move/attack/defend at high intensity.
	if intensity > 1.2:
		mods["org_mod"] += 0.05  # base radio bonus; more from tech.
	# Counter-battery doctrine: defenders better artillery response.
	if current_land_mission == LAND_MISSION_DEFEND:
		mods["combat_bonus"] += 0.05
	# Proximity shells: AA guns better vs planes (for air missions or attached).
	if current_air_mission != AIR_MISSION_NONE or attached_air_formation_id != "":
		mods["aa_vs_air"] += 0.1  # tech unlocked proximity boosts.

	# Scale by intensity
	mods["effect"] *= intensity
	mods["combat_bonus"] *= intensity
	mods["detection_bonus"] *= intensity
	mods["interdiction"] *= intensity

	return mods

## Attach air support (e.g., air wing to fleet for naval strike/bombard, or to army for CAS).
## Ships/forces get attached aircraft/helicopters/drones as support.
func attach_air_support(air_formation_id: String) -> void:
	attached_air_formation_id = air_formation_id

## Get bonus from attached air (e.g., for naval bombardment in amphib/land battle, recon, etc.).
func get_attached_air_bonus(mission_context: String = "") -> float:
	if attached_air_formation_id.is_empty():
		return 0.0
	# In full, query the attached formation's mission/mod.
	# For demo: base bonus, higher if attached air on naval strike or land CAS.
	var base := 0.1
	if mission_context == "naval_bombard" or current_naval_order in [NAVAL_ORDER_STRIKE, NAVAL_ORDER_SEARCH_AND_DESTROY]:
		base += 0.15  # naval bombardment support from attached air/helos.
	if current_land_mission == LAND_MISSION_ASSAULT:
		base += 0.1  # CAS.
	return base

## Get mission intensity cost (supplies/fuel for high ops, e.g. round-the-clock airbase needs more supplies).
func get_mission_supply_cost(base_cost: float = 1.0) -> float:
	return base_cost * (0.7 + mission_intensity * 0.5)  # higher intensity more costly.

## === DYNAMIC AIR SORTIE / ENDURANCE HOOK ===
## Returns effective sorties + supporting data for this air formation on its current mission.
## Integrates AirMissionProfile + ADS range/reliability + leader (air skill) + org/strength + infra proxy.
## Called by Supply _process_air_missions (daily fuel/recon/presence update), Resolver for CAS scale, tests.
## Distance_km can be passed from target or base-to-province calc (future MapManager dist).
func get_effective_air_sorties(distance_km: float = 500.0, base_infra: int = 5, enemy_aa: float = 0.0, weather_eff: float = 1.0, jamming: float = 1.0, stealth: float = 1.0, year: int = 1942) -> Dictionary:
	var prof := AirMissionProfile.new(formation_id if "formation_id" in self else "", get_air_design_id(), air_range_config)
	var base_r := float(prof.get_effective_range(distance_km, -1)) if prof.has_method("get_effective_range") else distance_km
	var org := 1.0
	if "organization" in self:
		org = float(self.organization)
	var sup := 1.0
	if "supply_level" in self:
		sup = float(self.supply_level)  # proxy; real from Supply calc
	var stren := float(self.strength) if "strength" in self else 1.0
	var skill := 0.6
	if typeof(LeaderManager) != TYPE_NIL:
		var ldr = LeaderManager.get_leader_for_army(formation_id) if LeaderManager.has_method("get_leader_for_army") else null
		if ldr and "air_skill" in ldr:  # or general skill proxy
			skill = clampf(float(ldr.air_skill if "air_skill" in ldr else ldr.skill if "skill" in ldr else 0.5), 0.0, 1.0)
	var doctrine := 1.0  # future: from National or chief_of_air_force
	# Tanker/AWACS proxy: check tech or special attached (late era fun)
	var has_tank := false
	var has_aw := false
	if typeof(TechnologyManager) != TYPE_NIL:
		# Rough: if player or owner has advanced air refuel / awacs tech
		var tag := country_tag if "country_tag" in self else "player"
		if TechnologyManager.has_method("has_tech_unlock"):
			has_tank = TechnologyManager.has_tech_unlock(tag, "air_equipment", "aerial_refueling") or year >= 1955
			has_aw = TechnologyManager.has_tech_unlock(tag, "strategic_future", "awacs") or year >= 1970
	var ftype := ""
	if "formation_type" in self:
		ftype = str(formation_type)
	var is_car := "carrier" in ftype.to_lower() or "naval" in str(current_air_mission).to_lower()
	# Call the model (also uses mission for recon calc but here general; caller filters)
	var res := prof.compute_effective_sorties(stren * 1.2, base_r, org, sup, base_infra, skill, doctrine, year, has_tank, has_aw, is_car, enemy_aa, weather_eff, jamming, stealth)
	# Scale by our mission intensity (more aggressive = potentially more but riskier)
	var intens := float(mission_intensity) if "mission_intensity" in self else 1.0
	res["sorties"] = clampf(float(res.get("sorties", 1.0)) * (0.8 + intens * 0.25), 0.3, 7.0)
	res["intensity_scaled"] = intens
	# Add air power weighted
	var air_pow := prof.compute_air_power(stren, current_air_mission, doctrine, 1.0 + (year-1940)*0.01)
	res["air_power_contrib"] = air_pow * float(res.get("sorties",1.0)) * 0.6
	return res

## Get recon bonus contribution (if on RECON mission) for intel/spotting hooks in PI/Supply/naval.
func get_air_recon_contrib() -> float:
	if current_air_mission != AIR_MISSION_RECON:
		return 0.0
	var sdata := get_effective_air_sorties(400.0, 6, 0.1, 1.0, 1.0, 1.0, 1945)
	return clampf(float(sdata.get("recon_points", 0.0)), 0.0, 6.0)

func log_combat(date: String, province_id: int, result: String, key_factors: Array[String], leader: String = "", outcome: String = "") -> void:
	# Log important combat action for this unit (date, province, result, key impactful factors only - not overwhelming)
	if not combat_log is Array:
		combat_log = []
	combat_log.append({
		"date": date,
		"province_id": province_id,
		"result": result,
		"key_factors": key_factors,  # e.g. ["our_forces_outnumbered", "we_have_air_superiority", "enemy_fortified", "leader_impact_high"]
		"leader": leader,
		"outcome": outcome
	})
	if combat_log.size() > 15:  # limit for performance/display
		combat_log = combat_log.slice(-15)
