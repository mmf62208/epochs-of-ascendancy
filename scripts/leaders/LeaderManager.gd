# scripts/leaders/LeaderManager.gd
extends Node

## Registry for leaders, army assignments, and national command positions.

signal leader_died(leader_id: String, cause: String)
signal leader_captured(leader_id: String, cause: String)
signal leader_retirement_offered(leader_id: String)
signal leader_retired(leader_id: String)
signal leader_introduced(leader_id: String)
signal game_year_advanced(year: int)
signal leader_experience_gained(leader_id: String, amount: int, source: String)
signal trait_leveled(leader_id: String, trait_id: String, new_level: int)
signal training_path_invested(leader_id: String, path_id: String, new_level: int)
signal training_path_switched(leader_id: String, old_path_id: String, new_path_id: String)
signal officer_training_quality_notice(country_tag: String, message: String, severity: String)
signal leader_replacement_needed(request: Dictionary)
signal leader_replacement_resolved(request_id: String, new_leader_id: String, left_vacant: bool)

const REPLACEMENT_CONTEXT_FORMATION := "formation_commander"
const DEBUG_DOCTRINE_LOGS := false  # Set true for verbose "Doctrine set" / CHANGE during tests/demos; off for clean normal play logs. Feature itself (org loss on change) always active.
const REPLACEMENT_CONTEXT_NATIONAL_POSITION := "national_position"
## When only one eligible candidate matches the auto-pick, assign immediately (player countries).
const REPLACEMENT_INSTANT_SINGLE_CANDIDATE := true

const POSITION_CHIEF_OF_ARMY := "chief_of_army"
const POSITION_CHIEF_OF_NAVY := "chief_of_navy"
const POSITION_CHIEF_OF_AIR_FORCE := "chief_of_air_force"
const POSITION_CHIEF_OF_SPACE_FORCE := "chief_of_space_force"
const POSITION_OFFICER_TRAINING := "officer_training"
## Legacy constants (kept for reference / compatibility; actual runtime values are in the
## OFFICER_TRAINING_* tuning block below and the functions that use them).
const OFFICER_TRAINING_POSITIVE_TRAIT_INHERIT_CHANCE := 0.30
const OFFICER_TRAINING_NEGATIVE_TRAIT_INHERIT_CHANCE := 0.45
const OFFICER_TRAINING_FLAW_TRAIT_IDS: Array[String] = [
	"reckless",
	"arrogant",
	"political_liability",
	"butcher",
	"slow_planner",
]

## Officer Training tuning constants (extracted for balance, clarity, and future moddability)
## These control quality progression, inheritance chances, and milestone thresholds.
const OFFICER_TRAINING_DECAY_PER_MONTH := 3.0
const OFFICER_TRAINING_BASE_GAIN := 2.5
const OFFICER_TRAINING_SKILL_BONUS_MULTIPLIER := 0.15
const OFFICER_TRAINING_LONG_TENURE_MONTHS := 24
const OFFICER_TRAINING_LONG_TENURE_MULTIPLIER := 0.6
const OFFICER_TRAINING_MENTOR_BONUS_MULTIPLIER := 0.15
const OFFICER_TRAINING_POSITIVE_BASE_CHANCE := 0.28
const OFFICER_TRAINING_POSITIVE_QUALITY_DIVISOR := 400.0
const OFFICER_TRAINING_NEGATIVE_BASE_CHANCE := 0.42
const OFFICER_TRAINING_NEGATIVE_QUALITY_DIVISOR := 300.0
const OFFICER_TRAINING_EXCELLENT_THRESHOLD := 75.0
const OFFICER_TRAINING_WARNING_THRESHOLD := 30.0
const OFFICER_TRAINING_CRISIS_THRESHOLD := 10.0

# Mentor change / death behavior (per user direction May 2026)
const OFFICER_TRAINING_MENTOR_CHANGE_DEBUFF_MONTHS := 6
const OFFICER_TRAINING_MENTOR_CHANGE_DEBUFF_MULTIPLIER := 0.5   # growth rate during penalty period
const OFFICER_TRAINING_DEATH_DEBUFF_PERCENT := 15.0             # immediate % quality loss on mentor death

# Cadet generation costs (Phase 1-2)
# Per user direction: Prestige only for cadet generation (Stability reserved for more serious events like death/capture).
const OFFICER_TRAINING_CADET_PRESTIGE_COST := 3.0   # Small but noticeable prestige cost per generated cadet

## Very simple cost application for national positions (Officer Training first).
## Deducts prestige where we have tracking; logs other costs for now.
func _apply_national_position_cost(country_tag: String, cost: Dictionary) -> void:
	if cost.is_empty():
		return
	var tag := country_tag.strip_edges().to_upper()

	var prestige_cost := float(cost.get("prestige", 0.0))
	if prestige_cost > 0.0:
		var current := float(national_prestige.get(tag, 50.0))
		national_prestige[tag] = maxf(current - prestige_cost, 0.0)
		print("Applied %.1f prestige cost for national position change in %s" % [prestige_cost, tag])

	var stability_cost := float(cost.get("stability", 0.0))
	if stability_cost > 0.0:
		# Stability system not fully wired yet — log for future integration
		print("Would apply %.1f stability cost for national position change in %s (pending full resource system)" % [stability_cost, tag])
const NATIONAL_POSITIONS: Array[String] = [
	POSITION_CHIEF_OF_ARMY,
	POSITION_CHIEF_OF_NAVY,
	POSITION_CHIEF_OF_AIR_FORCE,
	POSITION_CHIEF_OF_SPACE_FORCE,
	POSITION_OFFICER_TRAINING,
]

const NATIONAL_POSITION_CHANGE_COST: Dictionary = {
	"stability": 5.0,
	"prestige": 3.0,
}

const TRAITS_PATH := "res://data/leaders/traits.json"
const LEGACY_TRAITS_PATH := "res://data/leaders/leader_traits.json"
const TRAINING_PATHS_PATH := "res://data/leaders/doctrine_training_paths.json"
const TRAINING_PATH_SWITCH_COST_BASE := 400
const TRAINING_PATH_SWITCH_COST_PER_LEVEL := 150
const HISTORICAL_LEADERS_1936_PATH := "res://data/leaders/historical_leaders_1936.json"
const HISTORICAL_LEADERS_1918_PATH := "res://data/leaders/historical_leaders_1918.json"
const HISTORICAL_LEADERS_2026_PATH := "res://data/leaders/historical_leaders_2026.json"
const HISTORICAL_LEADERS_1910_PATH := HISTORICAL_LEADERS_1918_PATH  # reuse 1918 roster (year filter active leaders); create dedicated 1910.json for pre-war exclusives if needed
const SCENARIO_LEADER_PATHS: Dictionary = {
	"1918": HISTORICAL_LEADERS_1918_PATH,
	"1936": HISTORICAL_LEADERS_1936_PATH,
	"2026": HISTORICAL_LEADERS_2026_PATH,
	"1910": HISTORICAL_LEADERS_1910_PATH,
}
## Earlier-era rosters merged forward; later files override same leader_id. 2026 is isolated. 1910 reuses 1918 for continuity (many pre-1914 leaders active).
const SCENARIO_LEADER_ROSTER_CHAIN: Dictionary = {
	"1910": [HISTORICAL_LEADERS_1910_PATH],
	"1918": [HISTORICAL_LEADERS_1918_PATH],
	"1936": [HISTORICAL_LEADERS_1918_PATH, HISTORICAL_LEADERS_1936_PATH],
	"2026": [HISTORICAL_LEADERS_2026_PATH],
	# Full-world / grand-theater / europe playtests share 1936 start → same 1918+1936 chain.
	"world_full": [HISTORICAL_LEADERS_1918_PATH, HISTORICAL_LEADERS_1936_PATH],
	"world_accurate": [HISTORICAL_LEADERS_1918_PATH, HISTORICAL_LEADERS_1936_PATH],
	"grand_theater": [HISTORICAL_LEADERS_1918_PATH, HISTORICAL_LEADERS_1936_PATH],
	"phase1_europe_test": [HISTORICAL_LEADERS_1918_PATH, HISTORICAL_LEADERS_1936_PATH],
}
const MODERN_LEADER_MIN_BIRTH_YEAR := 1950
const MAX_SKILL := 10
const MAX_TRAITS_PER_LEADER := 6
const MAX_LEGENDARY_TRAITS := 2
const RARITY_LEGENDARY := "legendary"
const XP_BASE_COMBAT := 25
const XP_COMBAT_MULTIPLIER := 2.75
## Passive XP per process_passive_xp() call (scaled to weekly rates in XP_SYSTEM_DESIGN.md).
const XP_PASSIVE_ASSIGNED_IDLE := 1
const XP_PASSIVE_TRAINING := 4
const XP_PASSIVE_IN_COMBAT := 12
const XP_PASSIVE_AT_WAR_BONUS := 2
const XP_COMBAT_BATTLE_BASE := 12
const XP_COMBAT_MAJOR_VICTORY_BONUS := 60
const XP_COMBAT_HEROIC_DEFENSE_BONUS := 80
const XP_COMBAT_HIGH_RISK_SUCCESS_BONUS := 40
const XP_COST_BY_RARITY: Dictionary = {
	"common": 100,
	"notable": 200,
	"rare": 350,
	"legendary": 600,
}
const ROMAN_LEVELS: Array[String] = ["", "I", "II", "III", "IV"]

## Yearly mortality chart (max age exclusive upper bound in loop).
## Per-battle while assigned to an active formation (not yearly natural death).
const COMBAT_DEATH_CHANCE_PER_BATTLE := 0.0003
## When the leader's formation is destroyed, death or capture combined chance.
const FORMATION_DESTROYED_FATE_CHANCE := 0.30
## Share of destroyed-formation fate rolls that kill rather than capture.
const FORMATION_DESTROYED_DEATH_SHARE := 0.45
const RETIREMENT_HONORS_PRESTIGE := 3.0
const RETIREMENT_HONORS_UNITY := 2.0

const AGE_MORTALITY_BRACKETS: Array[Dictionary] = [
	{"max_age": 50, "death": 0.003, "retire": 0.005},
	{"max_age": 60, "death": 0.008, "retire": 0.020},
	{"max_age": 65, "death": 0.018, "retire": 0.050},
	{"max_age": 70, "death": 0.035, "retire": 0.120},
	{"max_age": 75, "death": 0.065, "retire": 0.220},
	{"max_age": 80, "death": 0.110, "retire": 0.300},
	{"max_age": 999, "death": 0.180, "retire": 0.350},
]

var leaders: Dictionary = {}  # leader_id -> Leader
var leader_pool: Dictionary = {}  # leader_id -> Dictionary (not yet available by year)
var pending_retirements: Array[String] = []
var pending_leader_replacements: Array[Dictionary] = []
## Human player country — replacement popups and pending badge only apply here.
var player_country_tag: String = "USA"
var formations: Dictionary = {}  # formation_id -> Formation
var country_positions: Dictionary = {}  # country_tag -> { position_id -> leader_id }
var trait_definitions: Dictionary = {}
var training_path_definitions: Dictionary = {}
## Per-country and per-service military doctrines (critical high-level choice impacting all military production, training, and operations).
# Structure: country_tag -> { "army": "blitzkrieg", "navy": "carrier_task_force", "air_force": "strategic_bombing", ... }
# Doctrines provide branch-wide bonuses/penalties (e.g., resilient/extra armor vs high performance/cheap), guide AI/agent module choices in design, affect leader training paths.
# Evolves over time: research/agents unlock new doctrines or reveal weaknesses, allowing player/agents to change with costs (stability, mandate, transition penalties).
# Player sets via Doctrine page (high-level direction for agents/AI); Chiefs (generals/admirals) can enforce or propose changes.
# Micro allowed in designer (override per unit); macro via doctrine as guideline.
var service_doctrines: Dictionary = {}  # country_tag -> { "army": doctrine_id, "navy": ..., "air_force": ..., "space_force": ... }

# Example doctrines with real trade-offs (WWI to 2026+). Expand in data/leaders/doctrines.json later.
const DOCTRINE_DEFINITIONS = {
	"attrition_warfare": { # WWI Army
		"name": "Attrition Warfare",
		"branch": "army",
		"era": "ww1",
		"benefits": {"manpower_efficiency": 0.15, "artillery_bonus": 0.20, "attrition_resist": 0.10},
		"costs": {"mobility": -0.25, "casualty_rate": 0.30, "supply_drain": 0.15},
		"description": "Mass infantry assaults, heavy artillery prep. Resilient to losses but slow, high casualties. Classic WWI French/German doctrine."
	},
	"blitzkrieg": { # WWII German Army
		"name": "Blitzkrieg / Maneuver Warfare",
		"branch": "army",
		"era": "ww2",
		"benefits": {"mobility": 0.30, "breakthrough": 0.25, "coordination": 0.15},
		"costs": {"supply_drain": 0.25, "attrition_sensitivity": 0.20, "overextension_risk": 0.10},
		"description": "Fast armored thrusts + air support, deep exploitation. High performance, cheap in short wars but vulnerable to prolonged attrition or bad weather."
	},
	"deep_battle": { # Soviet
		"name": "Deep Battle",
		"branch": "army",
		"era": "ww2",
		"benefits": {"mass": 0.20, "artillery_integration": 0.25, "resilience": 0.15},
		"costs": {"coordination_complexity": 0.10, "mobility": -0.10},
		"description": "Echeloned attacks, combined arms. Resilient, good for large fronts."
	},
	"carrier_task_force": { # WWII US Navy
		"name": "Carrier Task Force",
		"branch": "navy",
		"era": "ww2",
		"benefits": {"air_power_projection": 0.35, "flexibility": 0.20, "strike_range": 0.25},
		"costs": {"vulnerability_to_subs": 0.15, "high_cost": 0.20, "logistics_demand": 0.15},
		"description": "Mobile carriers + escorts for sea control and strikes. High performance, transforms naval warfare."
	},
	"submarine_commerce_raiding": { # German/Japanese
		"name": "Unrestricted Submarine Warfare",
		"branch": "navy",
		"era": "ww2",
		"benefits": {"commerce_disruption": 0.40, "stealth": 0.30, "cost_efficiency": 0.20},
		"costs": {"international_backlash": 0.25, "escort_counter": 0.15, "ethical_penalty": 0.10},
		"description": "Cheap, high-impact on enemy supply. High performance but risks escalation."
	},
	"strategic_bombing": { # Allied Air
		"name": "Strategic Bombing",
		"branch": "air_force",
		"era": "ww2",
		"benefits": {"industrial_disruption": 0.35, "morale_impact": 0.15, "long_range": 0.20},
		"costs": {"high_losses": 0.25, "resource_intensive": 0.20, "civilian_cost": 0.15},
		"description": "Heavy bombers to destroy enemy industry/will. Resilient in theory but expensive and ethically costly."
	},
	"network_centric_warfare": { # Modern
		"name": "Network-Centric / Precision Warfare",
		"branch": "army",
		"era": "modern",
		"benefits": {"precision": 0.30, "coordination": 0.25, "info_superiority": 0.20},
		"costs": {"cyber_vulnerability": 0.15, "tech_dependency": 0.15, "high_cost": 0.20},
		"description": "Sensors, drones, real-time data for dominant battlespace awareness. High performance but fragile to disruption."
	},
	"distributed_lethality": { # Modern Navy
		"name": "Distributed Lethality / A2/AD",
		"branch": "navy",
		"era": "modern",
		"benefits": {"survivability": 0.25, "flexible_strike": 0.25, "anti_access": 0.30},
		"costs": {"complex_command": 0.15, "logistics_spread": 0.10},
		"description": "Disperse forces, small ships with big missiles. Resilient to concentration attacks."
	},
	"drone_swarm_ai": { # 2026+
		"name": "Drone Swarm / AI-Augmented Ops",
		"branch": "air_force",
		"era": "future",
		"benefits": {"mass_low_cost": 0.40, "attrition_tolerance": 0.30, "speed_of_decision": 0.25},
		"costs": {"ai_ethics_risk": 0.15, "electronic_warfare_suscept": 0.20, "training_complexity": 0.10},
		"description": "Cheap, resilient swarms over expensive manned. High performance in volume, but ethical and jam vulnerabilities."
	},
	"methodical_battle": {
		"name": "Methodical Battle / Firepower Doctrine",
		"branch": "army",
		"era": "ww1_interwar",
		"benefits": {"artillery_bonus": 0.25, "defense": 0.20, "organization_recovery": 0.10, "entrenchment": 0.15},
		"costs": {"mobility": -0.20, "initiative": -0.15, "supply_drain": 0.10},
		"description": "Deliberate set-piece attacks with massive prep fires. French 1918-40 school (Maginot compatible). Rewards prepared positions, high resilience, punishes rushing."
	},
	"close_air_support": {
		"name": "Close Air Support / Tactical Air",
		"branch": "air_force",
		"era": "ww2",
		"benefits": {"air_ground_attack": 0.30, "coordination": 0.20, "breakthrough": 0.10},
		"costs": {"air_losses_vs_fighters": 0.20, "range_limit": 0.15},
		"description": "Airpower as flying artillery for ground spearheads. German 1939-42 model. Synergizes with blitz; vulnerable if air superiority lost."
	},
	"air_defense": {
		"name": "Integrated Air Defense",
		"branch": "air_force",
		"era": "ww2",
		"benefits": {"air_detection": 0.25, "interception": 0.20, "attrition_resist": 0.10},
		"costs": {"offensive_air_power": -0.15, "high_infra_demand": 0.10},
		"description": "Radar + fighters + AA for homeland defense. UK Battle of Britain model. Excellent for surviving strategic bombing; less aggressive projection."
	}
}

# Get/set service doctrine
func get_service_doctrine(country_tag: String, service: String) -> String:
	var tag := country_tag.strip_edges().to_upper()
	if not service_doctrines.has(tag):
		return ""
	var serv := service_doctrines[tag] as Dictionary
	return str(serv.get(service, ""))

func set_service_doctrine(
	country_tag: String,
	service: String,
	doctrine_id: String,
	silent: bool = false,
) -> void:
	var tag := country_tag.strip_edges().to_upper()
	if not service_doctrines.has(tag):
		service_doctrines[tag] = {}
	var serv := service_doctrines[tag] as Dictionary
	var old_doctrine = serv.get(service, "")
	if old_doctrine == doctrine_id:
		return
	serv[service] = doctrine_id
	if not silent and (DEBUG_DOCTRINE_LOGS or old_doctrine != doctrine_id or old_doctrine == ""):
		print("Doctrine set: %s %s -> %s (was %s)" % [tag, service, doctrine_id, old_doctrine])

	# Apply org loss to relevant units on doctrine philosophy change (simulates retraining, re-equipping, confusion in tactics/prototypes).
	# No direct stability hit (too macro); instead targeted military disruption + temp design/production penalties.
	if not silent and old_doctrine != "" and old_doctrine != doctrine_id:
		_apply_doctrine_change_penalties(tag, service, old_doctrine, doctrine_id)
		# Event: surface the philosophy shift with news (player sees org disruption + design penalty hooks).
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			LeaderEventUI.post_news("Doctrine Change", "%s %s shifts to '%s' (was '%s'). Formations take org/readiness hits; production & prototypes temporarily penalized. Agent missions for exploit/stabilize may appear." % [tag, service, doctrine_id, old_doctrine], "doctrine")

	# Notify for UI/events, update design filters if service doctrine.
	if typeof(DesignManager) != TYPE_NIL:
		# Future: refresh design pools for this service.
		pass

func _apply_doctrine_change_penalties(country_tag: String, service: String, old_doctrine: String, new_doctrine: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	if DEBUG_DOCTRINE_LOGS:
		print("[DOCTRINE CHANGE] %s %s changing from %s to %s: applying org disruption to %s units, temp design penalties." % [tag, service, old_doctrine, new_doctrine, service])

	# Org loss to formations of matching service.
	if "formations" in self:
		for fid in formations:
			var f: Formation = formations[fid]
			if f == null or f.country_tag != tag: continue
			var matches_service := false
			if service == "army" and f.formation_type in [Formation.TYPE_DIVISION, Formation.TYPE_ARMY, Formation.TYPE_ARMY_GROUP, Formation.TYPE_GARRISON]:
				matches_service = true
			elif service == "navy" and f.formation_type in [Formation.TYPE_FLEET, Formation.TYPE_TASK_FORCE, Formation.TYPE_SHIP]:
				matches_service = true
			elif service == "air_force" and f.formation_type in [Formation.TYPE_AIR_WING, Formation.TYPE_AIR_SQUADRON, Formation.TYPE_AIR_GROUP]:
				matches_service = true
			if matches_service:
				# Apply org hit (e.g. 30-50% loss, simulates adaptation shock). Recover over time via training/reinforce.
				var org_loss := 0.35
				if "organization" in f:
					f.organization = max(0.1, float(f.organization) * (1.0 - org_loss))
				if "readiness" in f:
					f.readiness = max(0.3, float(f.readiness) * 0.8)
				if DEBUG_DOCTRINE_LOGS:
					print("  - %s formation %s hit with org/readiness loss from doctrine shift." % [service, fid])

	# Temp penalty to new designs/production for this service (e.g. 3-6 months "retooling philosophy").
	# Could set a national modifier or per-country "doctrine_transition" flag with timer.
	# For now, log + hook to ProductionManager if exists.
	if typeof(ProductionManager) != TYPE_NIL:
		# Example: increase design time or cost for new lines in this branch.
		if DEBUG_DOCTRINE_LOGS:
			print("  - Production/design for %s temporarily penalized (prototype re-evaluation)." % service)

	# Agents/leaders notified: e.g. chiefs may gain stress, agents get "doctrine shift" intel opportunities.
	if typeof(AgentManager) != TYPE_NIL and DEBUG_DOCTRINE_LOGS:
		print("  - Agent hooks: potential 'exploit transition' or 'stabilize doctrine' missions available.")

# Apply doctrine effects (e.g., to training or stats). Call when chief assigned or periodically.
func apply_service_doctrine_effects(country_tag: String, service: String) -> void:
	var doctrine := get_service_doctrine(country_tag, service)
	if doctrine.is_empty() or not DOCTRINE_DEFINITIONS.has(doctrine):
		return
	var def := DOCTRINE_DEFINITIONS[doctrine] as Dictionary
	print("[DOCTRINE EFFECTS] %s %s: %s benefits=%s costs=%s" % [country_tag, service, def.get("name"), def.get("benefits"), def.get("costs")])
	# Hook to leader training, unit stats, production multipliers, etc.
	# E.g., if army "blitzkrieg", boost mobility in formations under that service.
var current_year: int = 1936
var _historical_leaders_source_path: String = ""
## Per-country morale bonuses from honored retirements (stub until national UI exists).
var national_prestige: Dictionary = {}  # country_tag -> float
var national_unity: Dictionary = {}  # country_tag -> float
var countries_at_war: Dictionary = {}  # country_tag -> bool (stub for +2 wartime XP)

# === Officer Training Progress (per country_tag) ===
var officer_training_quality: Dictionary = {}  # country_tag -> float 0–100
var officer_training_leader_id: Dictionary = {}  # country_tag -> leader_id
var months_in_training: Dictionary = {}  # country_tag -> int
var officer_training_debuff_months: Dictionary = {}  # country_tag -> int (months of reduced growth after mentor change)

# === Screen data caching ===
var _leader_screen_cache: Dictionary = {}  # country_tag -> LeaderScreenData


func _ready() -> void:
	if typeof(SupplyManager) != TYPE_NIL and not SupplyManager.player_tag.is_empty():
		player_country_tag = SupplyManager.player_tag
	_load_trait_definitions()
	_load_training_path_definitions()
	set_current_year(1936)
	load_historical_leaders(HISTORICAL_LEADERS_1936_PATH, 1936)
	# Retirement popups + news toasts: LeaderEventUI autoload listens to
	# leader_retirement_offered and related signals.


func register_leader(leader: Leader) -> void:
	if leader == null or leader.leader_id.is_empty():
		push_warning("LeaderManager: cannot register leader without leader_id")
		return
	leaders[leader.leader_id] = leader
	invalidate_leader_cache(leader.country_tag)


func assign_leader_to_army(leader_id: String, army_id: String) -> bool:
	if formations.has(army_id):
		return assign_leader_to_formation(leader_id, army_id)

	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null:
		return false
	_unassign_leader_from_current_formation(leader)
	leader.assigned_army_id = army_id
	invalidate_leader_cache(leader.country_tag)
	return true


func unassign_leader_from_army(leader_id: String) -> void:
	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null:
		return
	_unassign_leader_from_current_formation(leader)
	leader.assigned_army_id = ""
	invalidate_leader_cache(leader.country_tag)


func get_leader(leader_id: String) -> Leader:
	return leaders.get(leader_id) as Leader


func get_leader_for_army(army_id: String) -> Leader:
	var formation: Formation = get_formation(army_id)
	if formation != null and formation.has_leader():
		return get_leader(formation.leader_id)

	for leader_key in leaders:
		var leader: Leader = leaders[leader_key] as Leader
		if leader != null and leader.assigned_army_id == army_id:
			return leader
	return null


# === Formation registry & assignment ===

func register_formation(formation: Formation) -> void:
	if formation == null or formation.formation_id.is_empty():
		push_warning("LeaderManager: cannot register formation without formation_id")
		return
	formations[formation.formation_id] = formation
	invalidate_leader_cache(formation.country_tag)


## Field a designer template as a living map unit (selectable chip + orders).
func field_designed_unit(
	country_tag: String,
	design_id: String,
	province_id: int,
	domain: String = "land",
	extras: Dictionary = {},
) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	var did := design_id.strip_edges()
	var pid := int(province_id)
	var dom := domain.strip_edges().to_lower()
	if tag.is_empty() or did.is_empty() or pid <= 0:
		return {"ok": false, "error": "bad_args"}
	if pid < 1000:
		pid = 710173 if tag == "GER" else pid
		if pid <= 0:
			return {"ok": false, "error": "no_station"}
	# Reuse a same-design unit already on this hex (Field seed). Multi-recruit passes force_new.
	var force_new := bool(extras.get("force_new", false))
	if not force_new:
		for existing in get_formations_for_country(tag):
			if existing == null:
				continue
			if int(existing.stationed_province_id) != pid:
				continue
			var ed := str(existing.design_id) if "design_id" in existing else ""
			if ed == did:
				_notify_map_icon_pid(pid)
				return {
					"ok": true,
					"already": true,
					"formation_id": str(existing.formation_id),
					"design_id": did,
					"province_id": pid,
					"country_tag": tag,
				}
	var f := Formation.new()
	f.formation_id = "fielded_%s_%d" % [tag.to_lower(), Time.get_ticks_usec() % 100000000]
	f.country_tag = tag
	f.name = "%s %s" % [tag, did]
	f.organization = clampf(float(extras.get("organization", extras.get("org", 1.0))), 0.2, 1.0)
	f.readiness = 1.0
	f.strength = clampf(float(extras.get("strength", 1.0)), 0.2, 1.0)
	f.stationed_province_id = pid
	var vis := str(extras.get("visual_archetype", "")).strip_edges()
	if not vis.is_empty():
		f.set_meta("visual_archetype", vis)
	var mob := str(extras.get("mobility", "")).strip_edges().to_lower()
	if not mob.is_empty():
		f.set_meta("mobility", mob)
	var arm_el := str(extras.get("armor_element", "")).strip_edges().to_lower()
	if not arm_el.is_empty() and arm_el != "none":
		f.set_meta("armor_element", arm_el)
	match dom:
		"naval":
			f.formation_type = Formation.TYPE_FLEET
			f.naval_design_id = did
		"air":
			f.formation_type = Formation.TYPE_AIR_WING
			f.air_design_id = did
		"space":
			f.formation_type = Formation.TYPE_SPACE_WING
			f.design_id = did
		_:
			f.formation_type = Formation.TYPE_DIVISION
			f.design_id = did
			f.current_land_mission = Formation.LAND_MISSION_ASSAULT
	register_formation(f)
	if str(f.leader_id).strip_edges().is_empty() and has_method("pick_leader_id_for_formation"):
		var used: Dictionary = _seed_used_leader_ids() if has_method("_seed_used_leader_ids") else {}
		var pick := pick_leader_id_for_formation(tag, f.formation_type, used, ["general", "field_marshal"])
		if not pick.is_empty() and has_method("assign_leader_to_formation"):
			assign_leader_to_formation(pick, f.formation_id)
	_notify_map_icon_pid(pid)
	print(
		"LeaderManager: fielded designer unit %s design=%s @%d"
		% [f.formation_id, did, pid]
	)
	return {
		"ok": true,
		"already": false,
		"formation_id": f.formation_id,
		"design_id": did,
		"province_id": pid,
		"country_tag": tag,
		"formation_type": f.formation_type,
		"strength": f.strength,
		"visual_archetype": vis,
	}


var organize_priority: String = "field"
var organize_jobs: Array = []


func list_core_deploy_pids(country_tag: String) -> Array:
	var tag := country_tag.strip_edges().to_upper()
	var out: Array = []
	if tag.is_empty() or typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_provinces_by_owner"):
		if tag == "GER":
			return [710173, 710300]
		return out
	for pv in MapManager.get_provinces_by_owner(tag):
		var pid := int(pv)
		var p = MapManager.get_province(pid) if MapManager.has_method("get_province") else null
		if p == null or bool(p.is_sea):
			continue
		var cores: Array = p.core_for if "core_for" in p else []
		var is_core := false
		if cores is Array and not cores.is_empty():
			for c in cores:
				if str(c).strip_edges().to_upper() == tag:
					is_core = true
					break
		else:
			is_core = true  # owned land with empty core list = home soil
		if is_core:
			out.append(pid)
		if out.size() >= 80:
			break
	if out.is_empty() and tag == "GER":
		out = [710173, 710300]
	elif tag == "GER":
		var prefer: Array = [710173, 710300]
		var ranked: Array = []
		for pref in prefer:
			if int(pref) in out and int(pref) not in ranked:
				ranked.append(int(pref))
		for pid2 in out:
			if int(pid2) not in ranked:
				ranked.append(int(pid2))
		out = ranked
	return out


func set_organize_priority(mode: String, country_tag: String = "") -> void:
	var m := mode.strip_edges().to_lower()
	organize_priority = "new" if m == "new" else "field"
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = str(get_player_country_tag()) if has_method("get_player_country_tag") else "GER"
	if typeof(ProductionManager) == TYPE_NIL:
		return
	for f in get_formations_for_country(tag):
		if f == null:
			continue
		var fid := str(f.formation_id)
		var training := bool(f.is_training) if "is_training" in f else false
		var want := (not training) if organize_priority == "field" else training
		if ProductionManager.has_method("set_unit_priority_reinforcement"):
			ProductionManager.set_unit_priority_reinforcement(fid, want)


func organize_equip_share(is_training: bool) -> float:
	if organize_priority == "new":
		return 1.0 if is_training else 0.35
	return 0.35 if is_training else 1.0


func enqueue_organize(plan: Dictionary) -> Dictionary:
	var tag := str(plan.get("country_tag", "")).strip_edges().to_upper()
	if tag.is_empty():
		tag = str(get_player_country_tag()) if has_method("get_player_country_tag") else "GER"
	var mode := str(plan.get("mode", "new")).strip_edges().to_lower()
	var did := str(plan.get("template_id", plan.get("design_id", "panzer_iii_j_medium"))).strip_edges()
	var n := clampi(int(plan.get("count", 1)), 1, 8)
	var pid := int(plan.get("deploy_pid", 710173))
	var cores: Array = list_core_deploy_pids(tag)
	var core_ok := false
	for c in cores:
		if int(c) == pid:
			core_ok = true
			break
	if not core_ok:
		return {"ok": false, "error": "not_core", "deploy_pid": pid, "cores": cores}
	var existing := mode in ["existing", "existing_new"]
	var refit := mode in ["refit", "convert", "existing_field"]
	var days := 7 if refit else (10 if (existing or mode == "existing") else 14)
	if existing:
		mode = "existing"
	if refit:
		mode = "refit"
		days = 7
	var pri := str(plan.get("priority", organize_priority)).strip_edges().to_lower()
	set_organize_priority(pri, tag)
	var extras: Dictionary = plan.get("extras", {}) as Dictionary if plan.get("extras") is Dictionary else {}
	var tgt_str := clampf(float(extras.get("strength", extras.get("target_strength", 1.0))), 0.4, 1.0)
	var jobs_out: Array = []
	var also_refit := bool(plan.get("refit_fielded", false)) and mode != "refit"
	if mode == "refit" or also_refit:
		var converted := 0
		var refit_cap := n if mode == "refit" else 8
		var at_deploy: Array = []
		var elsewhere: Array = []
		for f in get_formations_for_country(tag):
			if f == null:
				continue
			if bool(f.is_training) or bool(f.is_in_combat):
				continue
			var ft := str(f.formation_type) if "formation_type" in f else ""
			if ft != Formation.TYPE_DIVISION and ft != Formation.TYPE_GARRISON:
				continue
			if int(f.stationed_province_id) == pid:
				at_deploy.append(f)
			else:
				elsewhere.append(f)
		for f in at_deploy + elsewhere:
			if converted >= refit_cap:
				break
			f.is_training = true
			f.is_trained = false
			f.training_progress = 0.0
			f.organization = 0.65
			f.readiness = 0.55
			f.strength = clampf(float(f.strength) * 0.85, 0.2, 1.0)
			f.set_meta("organize_days", 7.0)
			f.set_meta("organize_mode", "refit")
			f.set_meta("organize_target_design", did)
			f.set_meta("organize_target_strength", tgt_str)
			converted += 1
			jobs_out.append({"formation_id": str(f.formation_id), "mode": "refit", "days": 7, "deploy_pid": int(f.stationed_province_id)})
		if mode == "refit":
			organize_jobs.append_array(jobs_out)
			_notify_map_icon_pid(pid)
			return {"ok": converted > 0, "mode": "refit", "count": converted, "jobs": jobs_out, "train_days": 7}
	for i in n:
		var field_ex: Dictionary = extras.duplicate(true) if extras else {}
		field_ex["strength"] = 0.50
		field_ex["organization"] = 0.40
		field_ex["force_new"] = true
		var spawned: Dictionary = field_designed_unit(tag, did, pid, str(plan.get("domain", "land")), field_ex)
		if not bool(spawned.get("ok", false)):
			continue
		var fid := str(spawned.get("formation_id", ""))
		var f2: Formation = get_formation(fid)
		if f2 != null:
			f2.is_training = true
			f2.is_trained = false
			f2.training_progress = 0.0
			f2.readiness = 0.35
			f2.organization = 0.40
			f2.strength = 0.50
			f2.set_meta("organize_days", float(days))
			f2.set_meta("organize_mode", mode)
			f2.set_meta("organize_target_design", did)
			f2.set_meta("organize_target_strength", tgt_str)
		jobs_out.append({"formation_id": fid, "mode": mode, "days": days, "deploy_pid": pid})
	organize_jobs.append_array(jobs_out)
	_notify_map_icon_pid(pid)
	print("LeaderManager: enqueue_organize mode=%s n=%d days=%d pid=%d" % [mode, jobs_out.size(), days, pid])
	return {
		"ok": not jobs_out.is_empty(),
		"mode": mode,
		"count": jobs_out.size(),
		"jobs": jobs_out,
		"train_days": days,
		"deploy_pid": pid,
		"priority": organize_priority,
	}


func tick_organize_day() -> Dictionary:
	var done: Array = []
	var active := 0
	var touch_pids: Dictionary = {}
	for f_id in formations:
		var f: Formation = formations[f_id] as Formation
		if f == null:
			continue
		if not bool(f.is_training):
			continue
		active += 1
		f.training_progress = float(f.training_progress) + 1.0
		var need := float(f.get_meta("organize_days", 14.0))
		var t := clampf(f.training_progress / maxf(need, 1.0), 0.0, 1.0)
		var mode := str(f.get_meta("organize_mode", "new"))
		var tgt_str := clampf(float(f.get_meta("organize_target_strength", 1.0)), 0.4, 1.0)
		if mode == "refit":
			f.organization = 0.65 + 0.35 * t
			f.readiness = 0.55 + 0.45 * t
			var start_str := clampf(tgt_str * 0.85, 0.2, 1.0)
			f.strength = start_str + (tgt_str - start_str) * t
		else:
			f.organization = 0.40 + 0.60 * t
			f.readiness = 0.35 + 0.65 * t
			f.strength = 0.50 + (tgt_str - 0.50) * t
		var pid := int(f.stationed_province_id)
		if pid > 0 and touch_pids.size() < 12:
			touch_pids[pid] = true
		if f.training_progress + 0.001 >= need:
			f.is_training = false
			f.is_trained = true
			f.organization = 1.0
			f.readiness = 1.0
			f.strength = tgt_str
			var tgt := str(f.get_meta("organize_target_design", ""))
			if not tgt.is_empty() and "design_id" in f:
				f.design_id = tgt
			done.append(str(f.formation_id))
	var keep: Array = []
	for job in organize_jobs:
		if not (job is Dictionary):
			continue
		var jf: Formation = get_formation(str((job as Dictionary).get("formation_id", "")))
		if jf != null and bool(jf.is_training):
			keep.append(job)
	organize_jobs = keep
	if not done.is_empty():
		var tag := str(get_player_country_tag()) if has_method("get_player_country_tag") else "GER"
		set_organize_priority(organize_priority, tag)
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("daily_reinforcement_tick"):
		ProductionManager.daily_reinforcement_tick(_organize_required_map())
	for pid_v in touch_pids.keys():
		_notify_map_icon_pid(int(pid_v))
	if not done.is_empty():
		print("LeaderManager: organize ready n=%d" % done.size())
	return {"ok": true, "active": active, "ready": done, "priority": organize_priority}


func _organize_required_map() -> Dictionary:
	var required: Dictionary = {}
	var n_new := 0
	var n_field := 0
	for f_id in formations:
		var f: Formation = formations[f_id] as Formation
		if f == null:
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft != Formation.TYPE_DIVISION and ft != Formation.TYPE_GARRISON:
			continue
		if bool(f.is_in_combat):
			continue
		if bool(f.is_training):
			if n_new >= 8:
				continue
			var share := organize_equip_share(true)
			required[str(f.formation_id)] = {
				"infantry_equipment": maxi(1, int(round(8.0 * share))),
				"_country_tag": str(f.country_tag),
			}
			n_new += 1
		else:
			if n_field >= 8:
				continue
			if float(f.strength) >= 0.99:
				continue
			var share_f := organize_equip_share(false)
			required[str(f.formation_id)] = {
				"infantry_equipment": maxi(1, int(round(8.0 * share_f))),
				"_country_tag": str(f.country_tag),
			}
			n_field += 1
	return required


func _notify_map_icon_pid(pid: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var mr: Node = tree.get_first_node_in_group("map_renderer")
	if mr == null:
		mr = tree.root.find_child("WorldMap", true, false)
	if mr != null and mr.has_method("_update_unit_icons_for_pids"):
		mr.call_deferred("_update_unit_icons_for_pids", [pid])


func get_formation(formation_id: String) -> Formation:
	return formations.get(formation_id) as Formation


func get_formations_for_country(country_tag: String) -> Array[Formation]:
	var result: Array[Formation] = []
	for formation_id in formations:
		var formation: Formation = formations[formation_id] as Formation
		if formation != null and formation.country_tag == country_tag:
			result.append(formation)
	return result


## Formation type sets for auto-assign (mirrors _is_leader_valid_for_formation).
const LAND_FORMATION_TYPES_FOR_ASSIGN: Array[String] = [
	Formation.TYPE_DIVISION,
	Formation.TYPE_ARMY,
	Formation.TYPE_ARMY_GROUP,
	Formation.TYPE_GARRISON,
	Formation.TYPE_BRIGADE,
]
const NAVAL_FORMATION_TYPES_FOR_ASSIGN: Array[String] = [
	Formation.TYPE_FLEET,
	Formation.TYPE_TASK_FORCE,
	Formation.TYPE_SHIP,
]
const AIR_FORMATION_TYPES_FOR_ASSIGN: Array[String] = [
	Formation.TYPE_AIR_WING,
	Formation.TYPE_AIR_SQUADRON,
	Formation.TYPE_AIR_GROUP,
]


func _allowed_leader_types_for_formation_type(formation_type: String) -> Array[String]:
	if formation_type in LAND_FORMATION_TYPES_FOR_ASSIGN:
		return ["general", "field_marshal"] as Array[String]
	if formation_type in NAVAL_FORMATION_TYPES_FOR_ASSIGN:
		return ["admiral"] as Array[String]
	if formation_type in AIR_FORMATION_TYPES_FOR_ASSIGN:
		return ["air_marshal"] as Array[String]
	return [] as Array[String]


## Pure-style pick: next available same-tag leader of allowed types. Deterministic skill sort.
## Mirrors tools/map_generation/lib/leader_formation_assigner.py
func pick_leader_id_for_formation(
	country_tag: String,
	formation_type: String,
	used_leader_ids: Dictionary,
	allowed_leader_types: Array = [],
) -> String:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return ""
	var allowed: Array = allowed_leader_types
	if allowed.is_empty():
		allowed = _allowed_leader_types_for_formation_type(formation_type)
	if allowed.is_empty():
		return ""
	var candidates: Array[Leader] = []
	for lid in leaders.keys():
		var leader: Leader = leaders[lid] as Leader
		if leader == null:
			continue
		if str(leader.country_tag).strip_edges().to_upper() != tag:
			continue
		if leader.leader_type not in allowed:
			continue
		if leader.is_deceased or leader.is_retired or leader.is_captured:
			continue
		var id_str := str(leader.leader_id)
		if used_leader_ids.has(id_str):
			continue
		if not str(leader.assigned_army_id).is_empty():
			continue
		candidates.append(leader)
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a: Leader, b: Leader) -> bool:
		var sa := a.attack_skill + a.defense_skill + a.planning_skill + a.organization_skill
		var sb := b.attack_skill + b.defense_skill + b.planning_skill + b.organization_skill
		if sa != sb:
			return sa > sb
		return a.leader_id < b.leader_id
	)
	return candidates[0].leader_id


func pick_leader_id_for_land_formation(
	country_tag: String,
	formation_type: String,
	used_leader_ids: Dictionary,
) -> String:
	if formation_type not in LAND_FORMATION_TYPES_FOR_ASSIGN:
		return ""
	return pick_leader_id_for_formation(
		country_tag, formation_type, used_leader_ids, ["general", "field_marshal"]
	)


func _seed_used_leader_ids() -> Dictionary:
	var used: Dictionary = {}
	for lid in leaders.keys():
		var L: Leader = leaders[lid] as Leader
		if L != null and not str(L.assigned_army_id).is_empty():
			used[str(L.leader_id)] = true
	return used


## Assign free leaders of allowed types to vacant formations of matching types for one country.
func auto_assign_leaders_for_country(
	country_tag: String,
	formation_types: Array,
	allowed_leader_types: Array,
) -> int:
	var tag := country_tag.strip_edges().to_upper()
	var used: Dictionary = _seed_used_leader_ids()
	var forms: Array[Formation] = get_formations_for_country(tag)
	forms.sort_custom(func(a: Formation, b: Formation) -> bool:
		return a.formation_id < b.formation_id
	)
	var assigned_n := 0
	for formation in forms:
		if formation == null:
			continue
		if formation.formation_type not in formation_types:
			continue
		if formation.has_leader():
			var cur := str(formation.leader_id)
			if not cur.is_empty():
				used[cur] = true
			continue
		var pick := pick_leader_id_for_formation(
			tag, formation.formation_type, used, allowed_leader_types
		)
		if pick.is_empty():
			continue
		if assign_leader_to_formation(pick, formation.formation_id):
			used[pick] = true
			assigned_n += 1
	return assigned_n


func auto_assign_land_leaders_for_country(country_tag: String) -> int:
	return auto_assign_leaders_for_country(
		country_tag, LAND_FORMATION_TYPES_FOR_ASSIGN, ["general", "field_marshal"]
	)


func auto_assign_naval_leaders_for_country(country_tag: String) -> int:
	return auto_assign_leaders_for_country(
		country_tag, NAVAL_FORMATION_TYPES_FOR_ASSIGN, ["admiral"]
	)


func auto_assign_air_leaders_for_country(country_tag: String) -> int:
	return auto_assign_leaders_for_country(
		country_tag, AIR_FORMATION_TYPES_FOR_ASSIGN, ["air_marshal"]
	)


func _country_tags_with_formations() -> Array[String]:
	var tags: Array[String] = []
	for formation_id in formations:
		var f: Formation = formations[formation_id] as Formation
		if f == null:
			continue
		var t := str(f.country_tag).strip_edges().to_upper()
		if t.is_empty() or t in tags:
			continue
		tags.append(t)
	tags.sort()
	return tags


## Auto-assign land commanders for every country that has formations.
func auto_assign_land_leaders_for_all_countries() -> Dictionary:
	var by_tag: Dictionary = {}
	var total := 0
	for tag in _country_tags_with_formations():
		var n := auto_assign_land_leaders_for_country(tag)
		by_tag[tag] = n
		total += n
	return {"total_assigned": total, "by_tag": by_tag}


## Auto-assign admirals to naval formations and air marshals to air formations.
func auto_assign_branch_leaders_for_all_countries() -> Dictionary:
	var by_tag_naval: Dictionary = {}
	var by_tag_air: Dictionary = {}
	var total_naval := 0
	var total_air := 0
	for tag in _country_tags_with_formations():
		var nn := auto_assign_naval_leaders_for_country(tag)
		var na := auto_assign_air_leaders_for_country(tag)
		by_tag_naval[tag] = nn
		by_tag_air[tag] = na
		total_naval += nn
		total_air += na
	return {
		"total_naval_assigned": total_naval,
		"total_air_assigned": total_air,
		"by_tag_naval": by_tag_naval,
		"by_tag_air": by_tag_air,
	}


func assign_leader_to_formation(leader_id: String, formation_id: String) -> bool:
	var leader: Leader = get_leader(leader_id)
	var formation: Formation = get_formation(formation_id)

	if leader == null or formation == null:
		return false

	if not _is_leader_valid_for_formation(leader, formation):
		push_warning(
			"LeaderManager: leader type mismatch — %s cannot lead %s (%s)"
			% [leader.leader_type, formation.name, formation.formation_type]
		)
		return false

	_unassign_leader_from_current_formation(leader)

	var previous_leader: Leader = get_leader(formation.leader_id)
	if previous_leader != null and previous_leader != leader:
		_unassign_leader_from_current_formation(previous_leader)

	formation.assign_leader(leader)
	leader.assigned_army_id = formation_id
	invalidate_leader_cache(leader.country_tag)
	return true


func unassign_leader_from_formation(formation_id: String) -> void:
	var formation: Formation = get_formation(formation_id)
	if formation == null or not formation.has_leader():
		return

	var leader: Leader = get_leader(formation.leader_id)
	formation.remove_leader()
	if leader != null:
		leader.assigned_army_id = ""
		invalidate_leader_cache(leader.country_tag)


## Register division templates from SupplyManager as land formations for a country.
func register_division_formations_for_country(country_tag: String) -> void:
	if SupplyManager == null or SupplyManager.division_templates == null:
		return

	SupplyManager.division_templates.load_all()

	for div_id in SupplyManager.division_templates.get_all_division_ids():
		var div_template: DivisionTemplate = SupplyManager.division_templates.get_division(div_id)
		if div_template == null:
			continue

		var division_country := div_template.country_tag
		if division_country.is_empty():
			division_country = _infer_division_country_tag(div_id)
		if division_country != country_tag:
			continue

		if formations.has(div_id):
			continue

		register_formation(Formation.from_division_template(div_id, div_template, country_tag))


func clear_all_formations() -> void:
	formations.clear()


## Formations for [param country_tag] that do not have a leader assigned.
func get_available_formations(country_tag: String) -> Array[Dictionary]:
	var available: Array[Dictionary] = []

	register_division_formations_for_country(country_tag)

	for formation_id in formations:
		var formation: Formation = formations[formation_id] as Formation
		if formation == null:
			continue
		if formation.country_tag != country_tag:
			continue
		if formation.has_leader():
			continue

		available.append({
			"formation_id": formation.formation_id,
			"name": formation.name,
			"type": formation.formation_type,
			"category": formation.get_category(),
		})

	return available


func _unassign_leader_from_current_formation(leader: Leader) -> void:
	if leader == null or leader.assigned_army_id.is_empty():
		return

	var current: Formation = get_formation(leader.assigned_army_id)
	if current != null and current.leader_id == leader.leader_id:
		current.remove_leader()


func _is_leader_valid_for_formation(leader: Leader, formation: Formation) -> bool:
	match formation.formation_type:
		Formation.TYPE_FLEET, Formation.TYPE_TASK_FORCE, Formation.TYPE_SHIP:
			return leader.leader_type == "admiral"
		Formation.TYPE_AIR_WING, Formation.TYPE_AIR_SQUADRON, Formation.TYPE_AIR_GROUP:
			return leader.leader_type == "air_marshal"
		Formation.TYPE_SPACE_WING, Formation.TYPE_ORBITAL_GROUP:
			return leader.leader_type == "space_commander"
		Formation.TYPE_DIVISION, Formation.TYPE_ARMY, Formation.TYPE_ARMY_GROUP, Formation.TYPE_GARRISON, Formation.TYPE_BRIGADE:
			return leader.leader_type in ["general", "field_marshal"]
		_:
			return true


func _infer_division_country_tag(division_id: String) -> String:
	var div_key := division_id.to_lower()
	const PREFIX_TAGS: Array[Dictionary] = [
		{"prefix": "german_", "tag": "GER"},
		{"prefix": "us_", "tag": "USA"},
		{"prefix": "sov_", "tag": "SOV"},
		{"prefix": "fra_", "tag": "FRA"},
		{"prefix": "uk_", "tag": "ENG"},
		{"prefix": "eng_", "tag": "ENG"},
		{"prefix": "ita_", "tag": "ITA"},
		{"prefix": "jap_", "tag": "JAP"},
		{"prefix": "ger_", "tag": "GER"},
	]
	for entry in PREFIX_TAGS:
		if div_key.begins_with(str(entry.get("prefix", ""))):
			return str(entry.get("tag", ""))
	return ""


# === National top positions (chiefs of staff) ===

func get_valid_leader_types_for_position(position: String) -> Array[String]:
	match position:
		POSITION_CHIEF_OF_NAVY:
			return ["admiral"]
		POSITION_CHIEF_OF_AIR_FORCE:
			return ["air_marshal"]
		POSITION_CHIEF_OF_SPACE_FORCE:
			return ["space_commander"]
		POSITION_CHIEF_OF_ARMY:
			return ["general", "field_marshal"]
		POSITION_OFFICER_TRAINING:
			return ["general", "field_marshal"]
		_:
			return ["general", "field_marshal", "admiral", "air_marshal"]


func can_assign_national_position(
	country_tag: String,
	position: String,
	new_leader_id: String,
) -> Dictionary:
	var result := {
		"can_assign": true,
		"cost": NATIONAL_POSITION_CHANGE_COST.duplicate(),
		"reason": "",
	}

	if not NATIONAL_POSITIONS.has(position):
		result["can_assign"] = false
		result["reason"] = "Invalid position"
		return result

	var leader: Leader = leaders.get(new_leader_id) as Leader
	if leader == null:
		result["can_assign"] = false
		result["reason"] = "Leader not found"
		return result
	if leader.country_tag != country_tag:
		result["can_assign"] = false
		result["reason"] = "Leader does not match country"
		return result
	if position == POSITION_OFFICER_TRAINING:
		if leader.is_injured or leader.is_captured or leader.is_retired or leader.is_deceased:
			result["can_assign"] = false
			result["reason"] = "Leader cannot mentor while unavailable"
			return result
		# Brand new leaders (recent start_year) are explicitly allowed as mentors for historical/test scenarios.
	elif not leader.is_available_for_command():
		result["can_assign"] = false
		result["reason"] = "Leader is not available for command"
		return result

	var valid_types := get_valid_leader_types_for_position(position)
	if not valid_types.has(leader.leader_type):
		result["can_assign"] = false
		result["reason"] = "Leader type not eligible for this position"
		return result

	return result


func set_country_position(
	country_tag: String,
	position: String,
	leader_id: String,
	apply_cost: bool = true,
) -> bool:
	if position == POSITION_OFFICER_TRAINING:
		return set_officer_training_leader(country_tag, leader_id)

	if not NATIONAL_POSITIONS.has(position):
		push_warning("LeaderManager: invalid national position: " + position)
		return false

	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null:
		return false
	if leader.country_tag != country_tag:
		push_warning(
			"LeaderManager: leader %s (%s) does not match country %s"
			% [leader_id, leader.country_tag, country_tag]
		)
		return false

	if not country_positions.has(country_tag):
		country_positions[country_tag] = {}

	if apply_cost:
		print(
			"Changing %s position for %s. Cost will be applied (future system)."
			% [position, country_tag]
		)

	(country_positions[country_tag] as Dictionary)[position] = leader_id
	print(
		"Set %s as %s for %s"
		% [leader.name, position, country_tag]
	)

	# Apply service doctrine effects when chief is set (the head implements the philosophy).
	if position in [POSITION_CHIEF_OF_ARMY, POSITION_CHIEF_OF_NAVY, POSITION_CHIEF_OF_AIR_FORCE, POSITION_CHIEF_OF_SPACE_FORCE]:
		var service := "army"
		if position == POSITION_CHIEF_OF_NAVY: service = "navy"
		elif position == POSITION_CHIEF_OF_AIR_FORCE: service = "air_force"
		elif position == POSITION_CHIEF_OF_SPACE_FORCE: service = "space_force"
		apply_service_doctrine_effects(country_tag, service)
	invalidate_leader_cache(country_tag)
	return true


func get_country_position_leader(country_tag: String, position: String) -> Leader:
	if not country_positions.has(country_tag):
		return null
	var positions: Dictionary = country_positions[country_tag]
	var leader_id := str(positions.get(position, ""))
	if leader_id.is_empty():
		return null
	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null or leader.is_retired or leader.is_deceased or leader.is_captured or not leader.is_available_for_command():
		# Auto-clean dangling assignment for unavailable leaders (e.g. retired/test historical edge or mortality edge cases).
		# This ensures the UI shows "Vacant" + "Assign" cleanly and a new leader can be chosen.
		(positions as Dictionary).erase(position)
		invalidate_leader_cache(country_tag)
		return null
	return leader


func get_national_bonuses(country_tag: String) -> Dictionary:
	var bonuses := {
		"army_attack": 0.0,
		"army_organization": 0.0,
		"naval_combat": 0.0,
		"air_support": 0.0,
		"planning_speed": 0.0,
	}

	var chief_army := get_country_position_leader(country_tag, POSITION_CHIEF_OF_ARMY)
	if chief_army != null:
		bonuses["army_attack"] = float(bonuses["army_attack"]) + chief_army.get_attack_modifier() * 0.8
		bonuses["army_organization"] = (
			float(bonuses["army_organization"]) + chief_army.get_organization_modifier() * 0.7
		)
		bonuses["planning_speed"] = float(bonuses["planning_speed"]) + chief_army.get_planning_modifier() * 1.2

	var chief_navy := get_country_position_leader(country_tag, POSITION_CHIEF_OF_NAVY)
	if chief_navy != null:
		bonuses["naval_combat"] = float(bonuses["naval_combat"]) + chief_navy.get_attack_modifier() * 0.9

	var chief_air := get_country_position_leader(country_tag, POSITION_CHIEF_OF_AIR_FORCE)
	if chief_air != null:
		bonuses["air_support"] = float(bonuses["air_support"]) + chief_air.get_attack_modifier() * 0.6

	# === Light National Spirit / Modifier Integration (Combat) ===
	# This is a light pass — full deep integration can come later.
	var national_combat := _get_combined_national_combat_modifiers(country_tag)
	bonuses["army_organization"] = float(bonuses["army_organization"]) + float(national_combat.get("army_org_factor", 0.0))
	bonuses["planning_speed"] = float(bonuses["planning_speed"]) + float(national_combat.get("planning_speed", 0.0))

	return bonuses


func get_national_combat_modifiers(country_tag: String) -> Dictionary:
	"""Public helper: combined combat modifiers from national spirits + temporary national effects."""
	var result := {
		"army_org_factor": 0.0,
		"defence_factor": 0.0,
		"planning_speed": 0.0,
		"attack_factor": 0.0,
		"manpower_factor": 0.0,
		# Extended for new techs (cloning/cyber/genetic/sonic/CB/drone/shield/phaser/tele/layered/VR)
		"infantry_enhancement": 0.0,
		"soldier_enhancement": 0.0,
		"precision_strike": 0.0,
		"defensive_shielding": 0.0,
		"energy_weapon_dmg": 0.0,
		"manpower_replacement": 0.0,
		"rapid_deployment": 0.0,
		"training_efficiency": 0.0,
	}

	if country_tag.is_empty():
		return result

	if typeof(NationalSpiritManager) != TYPE_NIL:
		var spirit := NationalSpiritManager.get_spirit_combat_modifiers(country_tag)
		for k in result.keys():
			result[k] = float(result[k]) + float(spirit.get(k, 0.0))

	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp: Dictionary = NationalModifierManager.get_combat_modifiers(country_tag)
		for k in result.keys():
			result[k] = float(result[k]) + float(temp.get(k, 0.0))

	return result


func _get_combined_national_combat_modifiers(country_tag: String) -> Dictionary:
	var result := {
		"army_org_factor": 0.0,
		"defence_factor": 0.0,
		"planning_speed": 0.0,
		"attack_factor": 0.0,
		# Extended for new techs (cloning/cyber/genetic/sonic/CB/drone/shield/phaser/tele etc)
		"infantry_enhancement": 0.0,
		"soldier_enhancement": 0.0,
		"precision_strike": 0.0,
		"defensive_shielding": 0.0,
		"energy_weapon_dmg": 0.0,
		"manpower_replacement": 0.0,
		"rapid_deployment": 0.0,
	}

	if typeof(NationalSpiritManager) != TYPE_NIL:
		var spirit_mods := NationalSpiritManager.get_spirit_combat_modifiers(country_tag)
		for key in result.keys():
			result[key] = float(result[key]) + float(spirit_mods.get(key, 0.0))

	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp_mods: Dictionary = NationalModifierManager.get_combat_modifiers(country_tag)
		for key in result.keys():
			result[key] = float(result[key]) + float(temp_mods.get(key, 0.0))

	return result


func get_leaders_for_country(country_tag: String) -> Array[Leader]:
	var out: Array[Leader] = []
	for leader_id in leaders:
		var leader: Leader = leaders[leader_id] as Leader
		if leader != null and leader.country_tag == country_tag:
			out.append(leader)
	return out


# === Leader Assignment screen support ===
# Screen snapshots are cached per country; invalidate_leader_cache() on state changes.

func get_available_leaders(country_tag: String) -> Array[Leader]:
	var result: Array[Leader] = []
	for leader_id in leaders:
		var leader: Leader = leaders[leader_id] as Leader
		if leader == null or leader.country_tag != country_tag:
			continue
		if not leader.is_available_for_command():
			continue
		if leader.is_injured:
			continue
		if leader.assigned_army_id.is_empty():
			result.append(leader)
	return result


func get_current_year() -> int:
	# During transition, prefer the central TimeManager when present.
	if typeof(TimeManager) != TYPE_NIL:
		return TimeManager.get_current_year()
	return current_year


func set_current_year(year: int) -> void:
	current_year = maxi(year, 1)
	# Migration note: TimeManager is now the intended single source of truth for date.
	# Other systems should prefer TimeManager.get_current_year() / get_current_date().
	# LeaderManager still owns the detailed yearly simulation (mortality, officer training)
	# for the time being; future work will move more of the tick loop into TimeManager.


func get_leader_age(leader: Leader) -> int:
	if leader == null or leader.birth_year <= 0:
		return 0
	var age := current_year - leader.birth_year
	# Historical WW-era leaders in a modern scenario year (e.g. 2026 roster from 1936 data).
	if age > 90 and leader.start_year > leader.birth_year:
		age = leader.start_year - leader.birth_year
	if leader.end_year > 0 and leader.end_year < current_year:
		age = mini(age, leader.end_year - leader.birth_year)
	return clampi(age, 18, 90)


func get_pool_leader_count(country_tag: String = "") -> int:
	if country_tag.is_empty():
		return leader_pool.size()
	var count := 0
	for entry in leader_pool.values():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str((entry as Dictionary).get("country_tag", "")) == country_tag:
			count += 1
	return count


func is_leader_entry_active_for_year(entry: Dictionary, year: int) -> bool:
	var start := int(entry.get("start_year", 0))
	if start > 0 and year < start:
		return false
	var end := int(entry.get("end_year", 0))
	if end > 0 and year > end:
		return false
	return true


func get_yearly_death_chance(leader: Leader) -> float:
	if leader == null or leader.is_deceased or leader.is_retired:
		return 0.0
	if _is_brand_new(leader):
		return 0.0
	var age := get_leader_age(leader)
	var base := _base_chance_for_age(age, "death")
	base *= _mortality_situation_multiplier(leader, true)
	base *= leader.health
	if leader.stayed_past_retirement:
		base *= 1.25
	return clampf(base, 0.0, 0.35)


func get_yearly_retirement_chance(leader: Leader) -> float:
	if leader == null or leader.is_deceased or leader.is_retired:
		return 0.0
	if _is_brand_new(leader):
		return 0.0
	var age := get_leader_age(leader)
	var base := _base_chance_for_age(age, "retire")
	base *= _mortality_situation_multiplier(leader, false)
	if leader.stayed_past_retirement:
		base *= 1.35
	return clampf(base, 0.0, 0.45)


func _base_chance_for_age(age: int, kind: String) -> float:
	for bracket in AGE_MORTALITY_BRACKETS:
		if age < int(bracket.get("max_age", 999)):
			return float(bracket.get(kind, 0.0))
	return 0.0

## Brand-new historical leaders (e.g. Patton with start_year == scenario year) are protected from immediate mortality/retirement offers.
func _is_brand_new(leader: Leader) -> bool:
	if leader == null or leader.start_year <= 0:
		return false
	return get_current_year() - leader.start_year < 2


func get_combat_death_chance_per_battle(leader: Leader, intensity: float = 1.0) -> float:
	if leader == null or not leader.is_available_for_command() or not leader.is_in_combat_role():
		return 0.0
	var chance := COMBAT_DEATH_CHANCE_PER_BATTLE * clampf(intensity, 0.25, 4.0)
	chance *= _combat_casualty_trait_multiplier(leader)
	if leader.is_injured:
		chance *= 1.5
	return clampf(chance, 0.0, 0.01)


func get_formation_destroyed_fate_chance(leader: Leader) -> float:
	if leader == null or not leader.is_available_for_command():
		return 0.0
	if leader.assigned_army_id.is_empty():
		return 0.0
	return clampf(
		FORMATION_DESTROYED_FATE_CHANCE * _combat_casualty_trait_multiplier(leader),
		0.0,
		0.5,
	)


func roll_combat_battle_casualty(
	army_or_formation_id: String,
	intensity: float = 1.0,
) -> Dictionary:
	var leader: Leader = get_leader_for_army(army_or_formation_id)
	if leader == null:
		return {"type": "none", "leader_id": ""}

	var chance := get_combat_death_chance_per_battle(leader, intensity)
	if chance <= 0.0:
		return {"type": "none", "leader_id": leader.leader_id}

	if randf() < chance:
		var leader_id := leader.leader_id
		_remove_leader(leader_id, "combat", true)
		leader_died.emit(leader_id, "combat")
		return {"type": "death", "leader_id": leader_id, "cause": "combat", "chance": chance}

	return {"type": "none", "leader_id": leader.leader_id, "chance": chance}


func handle_formation_destroyed(formation_id: String) -> Dictionary:
	var leader: Leader = get_leader_for_army(formation_id)
	if leader == null:
		return {"type": "none", "leader_id": ""}

	var leader_id := leader.leader_id
	var vacant_formation_id := formation_id
	if vacant_formation_id.is_empty():
		vacant_formation_id = leader.assigned_army_id
	var fate_chance := get_formation_destroyed_fate_chance(leader)
	if randf() >= fate_chance:
		return {"type": "survived", "leader_id": leader_id, "chance": fate_chance}

	_unassign_leader_from_current_formation(leader)
	_clear_leader_from_national_positions(leader_id)

	if randf() < FORMATION_DESTROYED_DEATH_SHARE:
		_remove_leader(leader_id, "formation_destroyed", true)
		leader_died.emit(leader_id, "formation_destroyed")
		return {
			"type": "death",
			"leader_id": leader_id,
			"cause": "formation_destroyed",
			"chance": fate_chance,
		}

	# Leader survives as POW; formation may still exist and need a new commander.
	if not vacant_formation_id.is_empty():
		_enqueue_formation_command_vacancy(
			leader.country_tag,
			vacant_formation_id,
			leader_id,
			leader.name,
			"formation_destroyed",
		)

	leader.is_captured = true
	print("%s has been captured after their command was destroyed!" % leader.name)
	invalidate_leader_cache(leader.country_tag)
	leader_captured.emit(leader_id, "formation_destroyed")
	return {
		"type": "captured",
		"leader_id": leader_id,
		"cause": "formation_destroyed",
		"chance": fate_chance,
	}


func _combat_casualty_trait_multiplier(leader: Leader) -> float:
	var mult := 1.0
	if leader.has_trait("iron_will"):
		mult *= 0.75
	if leader.has_trait("reckless"):
		mult *= 1.35
	if leader.has_trait("cautious"):
		mult *= 0.9
	if leader.duty_post == "rear_area":
		mult *= 0.5
	return mult


func _mortality_situation_multiplier(leader: Leader, for_death: bool) -> float:
	var mult := 1.0
	if leader.duty_post == "training":
		mult *= 0.55 if for_death else 0.7
	elif leader.duty_post == "rear_area":
		mult *= 0.4 if for_death else 0.6
	if leader.experience >= 800:
		mult *= 0.85 if for_death else 0.9
	if leader.has_trait("iron_will"):
		mult *= 0.8 if for_death else 0.9
	if leader.has_trait("reckless") or leader.has_trait("arrogant"):
		mult *= 1.25 if for_death else 1.1
	if leader.has_trait("political_liability"):
		mult *= 1.15 if for_death else 1.2
	if leader.has_trait("logistics_wizard"):
		mult *= 0.92 if for_death else 0.95
	if leader.is_injured:
		mult *= 1.35 if for_death else 1.0
	return mult


func check_leader_mortality(year: int = -1) -> Array[Dictionary]:
	if year > 0:
		set_current_year(year)
	var events: Array[Dictionary] = []
	# Prune any pending retirements for brand new leaders (defensive against timing/advance edges so Patton etc. don't offer retire immediately).
	var to_prune: Array[String] = []
	for rid in pending_retirements:
		var l: Leader = leaders.get(rid)
		if l and _is_brand_new(l):
			to_prune.append(rid)
	for rid in to_prune:
		pending_retirements.erase(rid)
	for leader_id in leaders.keys():
		var leader: Leader = leaders[leader_id] as Leader
		if leader == null or not leader.is_available_for_command():
			continue
		if leader_id in pending_retirements:
			continue
		if _is_brand_new(leader):
			continue  # brand new leaders (e.g. Patton 1936 start) protected from death/retire offers for first ~2 years
		var death_chance := get_yearly_death_chance(leader)
		if randf() < death_chance:
			_remove_leader(leader_id, "natural", true)
			events.append({"type": "death", "leader_id": leader_id, "cause": "natural"})
			leader_died.emit(leader_id, "natural")
			continue
		var retire_chance := get_yearly_retirement_chance(leader)
		if randf() < retire_chance:
			pending_retirements.append(leader_id)
			events.append({"type": "retirement_offer", "leader_id": leader_id})
			leader_retirement_offered.emit(leader_id)

	return events


func resolve_retirement(leader_id: String, let_retire: bool, ask_to_stay: bool = false) -> bool:
	if leader_id not in pending_retirements:
		return false
	pending_retirements.erase(leader_id)
	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null:
		return false

	if let_retire:
		apply_retirement_honors(leader.country_tag)
		_remove_leader(leader_id, "retirement", false)
		leader_retired.emit(leader_id)
		return true

	if ask_to_stay:
		var agree_chance := 0.65
		if leader.has_trait("charismatic"):
			agree_chance += 0.1
		if leader.has_trait("iron_will"):
			agree_chance += 0.08
		if randf() < agree_chance:
			leader.stayed_past_retirement = true
			print("%s agrees to serve one more year." % leader.name)
			return true

	apply_retirement_honors(leader.country_tag)
	_remove_leader(leader_id, "retirement", false)
	leader_retired.emit(leader_id)
	return true


func apply_retirement_honors(country_tag: String) -> void:
	if country_tag.is_empty():
		return
	national_prestige[country_tag] = (
		float(national_prestige.get(country_tag, 50.0)) + RETIREMENT_HONORS_PRESTIGE
	)
	national_unity[country_tag] = (
		float(national_unity.get(country_tag, 50.0)) + RETIREMENT_HONORS_UNITY
	)


func get_national_prestige(country_tag: String) -> float:
	return float(national_prestige.get(country_tag, 50.0))


func get_national_unity(country_tag: String) -> float:
	return float(national_unity.get(country_tag, 50.0))


func advance_game_year() -> Dictionary:
	# This method now contains the heavy yearly simulation (officer training, leader events, mortality).
	# It is primarily called by TimeManager when a year boundary is crossed.
	current_year += 1

	# Keep TimeManager in sync (in case this was called manually for testing)
	if typeof(TimeManager) != TYPE_NIL:
		TimeManager.sync_year_from_external(current_year)

	for _month in 12:
		advance_officer_training_progress()
	var introduced := introduce_eligible_leaders_for_year(current_year)
	var mortality_events := check_leader_mortality()
	game_year_advanced.emit(current_year)
	return {
		"year": current_year,
		"introduced": introduced,
		"mortality_events": mortality_events,
	}


func introduce_eligible_leaders_for_year(year: int = -1) -> int:
	var target_year := year if year > 0 else current_year
	var introduced := 0
	for leader_id in leader_pool.keys():
		var entry: Variant = leader_pool[leader_id]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not is_leader_entry_active_for_year(entry as Dictionary, target_year):
			continue
		if leaders.has(leader_id):
			continue
		var leader := _leader_from_dict(entry as Dictionary)
		if leader == null:
			continue
		register_leader(leader)
		leader_pool.erase(leader_id)
		introduced += 1
		leader_introduced.emit(leader_id)
		print("%s has entered command (%d)." % [leader.name, target_year])
	return introduced


func _remove_leader(leader_id: String, cause: String, is_death: bool) -> void:
	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null:
		return
	_enqueue_leader_replacement_requests(leader, cause)
	_unassign_leader_from_current_formation(leader)
	_clear_leader_from_national_positions(leader_id)

	if is_death:
		# Special handling for Officer Training mentor death (per user direction)
		_apply_officer_training_death_debuff(leader.country_tag)
		leader.is_deceased = true
		print("%s has died (%s)." % [leader.name, cause])
	else:
		leader.is_retired = true
		print("%s has retired." % leader.name)
	leaders.erase(leader_id)
	invalidate_leader_cache(leader.country_tag)


# ============================================
# LEADER REPLACEMENT (vacancy queue + auto-fallback)
# ============================================

func set_player_country_tag(tag: String) -> void:
	player_country_tag = tag.strip_edges().to_upper()
	if typeof(SupplyManager) != TYPE_NIL:
		SupplyManager.player_tag = player_country_tag


func get_player_country_tag() -> String:
	if not player_country_tag.is_empty():
		return player_country_tag
	if typeof(SupplyManager) != TYPE_NIL and not SupplyManager.player_tag.is_empty():
		return SupplyManager.player_tag
	return "USA"


func is_player_country(country_tag: String) -> bool:
	return country_tag.strip_edges().to_upper() == get_player_country_tag()


func get_pending_replacement_count(country_tag: String = "") -> int:
	return get_pending_leader_replacements(country_tag).size()


func get_pending_leader_replacements(country_tag: String = "") -> Array[Dictionary]:
	_prune_stale_leader_replacement_requests()
	if country_tag.is_empty():
		return pending_leader_replacements.duplicate()
	var filtered: Array[Dictionary] = []
	for request in pending_leader_replacements:
		if str(request.get("country_tag", "")) == country_tag:
			filtered.append(request.duplicate())
	return filtered


func _prune_stale_leader_replacement_requests() -> void:
	for i in range(pending_leader_replacements.size() - 1, -1, -1):
		var request: Dictionary = pending_leader_replacements[i]
		if not _is_replacement_request_still_valid(request):
			pending_leader_replacements.remove_at(i)


func get_leader_replacement_request(request_id: String) -> Dictionary:
	for request in pending_leader_replacements:
		if str(request.get("request_id", "")) == request_id:
			return request.duplicate()
	return {}


func dismiss_leader_replacement(request_id: String) -> void:
	_remove_leader_replacement_request(request_id)


func get_replacement_candidates(request: Dictionary) -> Array[Dictionary]:
	var country := str(request.get("country_tag", ""))
	var valid_types: Array = request.get("valid_leader_types", []) as Array
	var context := str(request.get("context", ""))
	var target_id := str(request.get("target_id", ""))
	var recommended_id := str(request.get("recommended_leader_id", ""))

	var rows: Array[Dictionary] = []
	for leader in get_leaders_for_country(country):
		if leader == null or not _is_leader_eligible_replacement(leader, valid_types, context):
			continue
		var score := _score_replacement_candidate(leader, context, target_id)
		rows.append({
			"leader_id": leader.leader_id,
			"name": leader.name,
			"leader_type": leader.leader_type,
			"experience": leader.experience,
			"score": score,
			"is_recommended": leader.leader_id == recommended_id,
		})

	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if bool(a.get("is_recommended", false)) != bool(b.get("is_recommended", false)):
				return bool(a.get("is_recommended", false))
			return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	return rows


func pick_auto_replacement_leader(request: Dictionary) -> String:
	return str(request.get("recommended_leader_id", ""))


func apply_auto_replacement(request_id: String) -> bool:
	var request := get_leader_replacement_request(request_id)
	if request.is_empty():
		return false
	var leader_id := pick_auto_replacement_leader(request)
	if leader_id.is_empty():
		return false
	return resolve_leader_replacement(request_id, leader_id, false)


## Player-only: skip the picker when there is exactly one strong candidate (the auto-pick).
func try_instant_player_replacement(request: Dictionary) -> bool:
	if not REPLACEMENT_INSTANT_SINGLE_CANDIDATE:
		return false
	if not is_player_country(str(request.get("country_tag", ""))):
		return false
	if str(request.get("context", "")) == REPLACEMENT_CONTEXT_FORMATION:
		if get_formation(str(request.get("target_id", ""))) == null:
			return false
	var candidates := get_replacement_candidates(request)
	if candidates.size() != 1:
		return false
	var row: Dictionary = candidates[0]
	if not bool(row.get("is_recommended", false)):
		return false
	var request_id := str(request.get("request_id", ""))
	if request_id.is_empty():
		return false
	return resolve_leader_replacement(request_id, str(row.get("leader_id", "")), false)


func resolve_leader_replacement(
	request_id: String,
	new_leader_id: String,
	leave_vacant: bool = false,
) -> bool:
	var request := get_leader_replacement_request(request_id)
	if request.is_empty():
		return false

	if leave_vacant:
		_remove_leader_replacement_request(request_id)
		leader_replacement_resolved.emit(request_id, "", true)
		return true

	if new_leader_id.is_empty():
		return false

	var country := str(request.get("country_tag", ""))
	var context := str(request.get("context", ""))
	var target_id := str(request.get("target_id", ""))
	var applied := false

	match context:
		REPLACEMENT_CONTEXT_FORMATION:
			if get_formation(target_id) != null:
				applied = assign_leader_to_formation(new_leader_id, target_id)
			else:
				applied = assign_leader_to_army(new_leader_id, target_id)
		REPLACEMENT_CONTEXT_NATIONAL_POSITION:
			if target_id == POSITION_OFFICER_TRAINING:
				applied = set_officer_training_leader(country, new_leader_id)
			else:
				applied = set_country_position(country, target_id, new_leader_id, false)

	if not applied:
		return false

	_remove_leader_replacement_request(request_id)
	leader_replacement_resolved.emit(request_id, new_leader_id, false)
	return true


func _enqueue_leader_replacement_requests(leader: Leader, cause: String) -> void:
	if leader == null:
		return

	var country_tag := leader.country_tag
	var departed_id := leader.leader_id
	var departed_name := leader.name

	if not leader.assigned_army_id.is_empty():
		_enqueue_formation_command_vacancy(
			country_tag,
			leader.assigned_army_id,
			departed_id,
			departed_name,
			cause,
		)

	if not country_positions.has(country_tag):
		return

	var positions: Dictionary = country_positions[country_tag] as Dictionary
	for position_key in positions.keys():
		if str(positions[position_key]) != departed_id:
			continue
		var position_id := str(position_key)
		var position_request := _build_replacement_request(
			country_tag,
			REPLACEMENT_CONTEXT_NATIONAL_POSITION,
			position_id,
			_position_display_label(position_id),
			departed_id,
			departed_name,
			cause,
			get_valid_leader_types_for_position(position_id),
		)
		_push_leader_replacement_request(position_request)


func _build_replacement_request(
	country_tag: String,
	context: String,
	target_id: String,
	target_label: String,
	departed_leader_id: String,
	departed_leader_name: String,
	cause: String,
	valid_leader_types: Array[String],
) -> Dictionary:
	var draft := {
		"request_id": "%s_%s_%d" % [context, target_id, Time.get_unix_time_from_system()],
		"country_tag": country_tag,
		"context": context,
		"target_id": target_id,
		"target_label": target_label,
		"departed_leader_id": departed_leader_id,
		"departed_leader_name": departed_leader_name,
		"departure_cause": cause,
		"valid_leader_types": valid_leader_types.duplicate(),
		"recommended_leader_id": "",
	}
	draft["recommended_leader_id"] = _pick_auto_replacement_leader_id(draft)
	return draft


func _enqueue_formation_command_vacancy(
	country_tag: String,
	formation_id: String,
	departed_leader_id: String,
	departed_leader_name: String,
	cause: String,
) -> void:
	var formation := get_formation(formation_id)
	if formation != null and formation.has_leader():
		return

	var formation_label := formation_id
	var valid_types: Array[String] = ["general", "field_marshal"]
	if formation != null:
		formation_label = formation.name
		valid_types = _valid_leader_types_for_formation(formation)

	var formation_request := _build_replacement_request(
		country_tag,
		REPLACEMENT_CONTEXT_FORMATION,
		formation_id,
		formation_label,
		departed_leader_id,
		departed_leader_name,
		cause,
		valid_types,
	)
	_push_leader_replacement_request(formation_request)


func _push_leader_replacement_request(request: Dictionary) -> void:
	if request.is_empty():
		return
	if not _is_replacement_request_still_valid(request):
		return

	pending_leader_replacements.append(request)

	if is_player_country(str(request.get("country_tag", ""))):
		if try_instant_player_replacement(request):
			return
		leader_replacement_needed.emit(request.duplicate())
	else:
		_auto_resolve_replacement_for_ai(str(request.get("request_id", "")))


func _is_replacement_request_still_valid(request: Dictionary) -> bool:
	var context := str(request.get("context", ""))
	var country_tag := str(request.get("country_tag", ""))
	var target_id := str(request.get("target_id", ""))

	match context:
		REPLACEMENT_CONTEXT_FORMATION:
			var formation := get_formation(target_id)
			if formation == null:
				# Legacy army_id assignments (e.g. third_army_test) have no Formation registry.
				return true
			return not formation.has_leader()
		REPLACEMENT_CONTEXT_NATIONAL_POSITION:
			if not country_positions.has(country_tag):
				return true
			var positions: Dictionary = country_positions[country_tag] as Dictionary
			return not positions.has(target_id) or str(positions.get(target_id, "")).is_empty()
		_:
			return true


func _auto_resolve_replacement_for_ai(request_id: String) -> void:
	if request_id.is_empty():
		return
	if not apply_auto_replacement(request_id):
		resolve_leader_replacement(request_id, "", true)


func _remove_leader_replacement_request(request_id: String) -> void:
	for i in range(pending_leader_replacements.size() - 1, -1, -1):
		if str(pending_leader_replacements[i].get("request_id", "")) == request_id:
			pending_leader_replacements.remove_at(i)
			return


func _pick_auto_replacement_leader_id(request: Dictionary) -> String:
	var country := str(request.get("country_tag", ""))
	var valid_types: Array = request.get("valid_leader_types", []) as Array
	var context := str(request.get("context", ""))
	var target_id := str(request.get("target_id", ""))

	var best_id := ""
	var best_score := -1
	for leader in get_leaders_for_country(country):
		if leader == null or not _is_leader_eligible_replacement(leader, valid_types, context):
			continue
		var score := _score_replacement_candidate(leader, context, target_id)
		if score > best_score:
			best_score = score
			best_id = leader.leader_id
	return best_id


func _is_leader_eligible_replacement(
	leader: Leader,
	valid_types: Array,
	context: String,
) -> bool:
	if leader == null:
		return false
	if not leader.is_available_for_command():
		return false
	if leader.is_injured or leader.is_captured or leader.is_retired or leader.is_deceased:
		return false
	if leader.is_in_officer_training and context != REPLACEMENT_CONTEXT_NATIONAL_POSITION:
		return false
	if valid_types.size() > 0 and not valid_types.has(leader.leader_type):
		return false
	if context == REPLACEMENT_CONTEXT_FORMATION and not leader.assigned_army_id.is_empty():
		return false
	if context == REPLACEMENT_CONTEXT_NATIONAL_POSITION and not leader.assigned_army_id.is_empty():
		return false
	return true


func _score_replacement_candidate(leader: Leader, context: String, target_id: String) -> int:
	var score := (
		leader.attack_skill
		+ leader.defense_skill
		+ leader.planning_skill
		+ leader.initiative_skill
		+ int(leader.experience / 50.0)
	)
	if context == REPLACEMENT_CONTEXT_NATIONAL_POSITION:
		score += leader.logistics_skill + leader.organization_skill
		if target_id == POSITION_OFFICER_TRAINING:
			score += int(
				get_officer_training_suitability(leader.leader_id) * 0.15
			)
	return score


func _valid_leader_types_for_formation(formation: Formation) -> Array[String]:
	if formation == null:
		return ["general", "field_marshal"]
	match formation.formation_type:
		Formation.TYPE_FLEET, Formation.TYPE_TASK_FORCE, Formation.TYPE_SHIP:
			return ["admiral"]
		Formation.TYPE_AIR_WING, Formation.TYPE_AIR_SQUADRON, Formation.TYPE_AIR_GROUP:
			return ["air_marshal"]
		Formation.TYPE_SPACE_WING, Formation.TYPE_ORBITAL_GROUP:
			return ["space_commander"]
		_:
			return ["general", "field_marshal"]


func _position_display_label(position_key: String) -> String:
	match position_key:
		POSITION_CHIEF_OF_ARMY:
			return "Chief of Army"
		POSITION_CHIEF_OF_NAVY:
			return "Chief of Navy"
		POSITION_CHIEF_OF_AIR_FORCE:
			return "Chief of Air Force"
		POSITION_CHIEF_OF_SPACE_FORCE:
			return "Chief of Space Force"
		POSITION_OFFICER_TRAINING:
			return "Officer Training Command"
		_:
			return position_key.replace("_", " ").capitalize()


func _clear_leader_from_national_positions(leader_id: String) -> void:
	var leader := get_leader(leader_id)
	for country_key in country_positions.keys():
		var positions: Dictionary = country_positions[country_key] as Dictionary
		for position_key in positions.keys():
			if str(positions[position_key]) != leader_id:
				continue
			if position_key == POSITION_OFFICER_TRAINING and leader != null:
				leader.is_in_officer_training = false
				if leader.duty_post == "training":
					leader.duty_post = "active"
			positions.erase(position_key)


## Applies the 15% quality debuff when the Officer Training mentor dies (per approved plan).
func _apply_officer_training_death_debuff(country_tag: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	var current := get_officer_training_quality(tag)
	if current <= 0.0:
		return

	var loss := current * (OFFICER_TRAINING_DEATH_DEBUFF_PERCENT / 100.0)
	var new_quality := maxf(current - loss, 0.0)
	officer_training_quality[tag] = new_quality

	# Also start a fresh debuff period so the program feels the loss for a while
	officer_training_debuff_months[tag] = max(
		int(officer_training_debuff_months.get(tag, 0)),
		OFFICER_TRAINING_MENTOR_CHANGE_DEBUFF_MONTHS
	)

	print("Officer Training program for %s suffered a %.0f%% quality debuff due to mentor death." % [tag, OFFICER_TRAINING_DEATH_DEBUFF_PERCENT])


func get_armies_without_leader(_country_tag: String) -> Array[String]:
	# Placeholder until Army registry exists.
	return []


func get_leader_summary(leader_id: String) -> Dictionary:
	var leader: Leader = get_leader(leader_id)
	if leader == null:
		return {}

	return {
		"leader_id": leader_id,
		"name": leader.name,
		"country_tag": leader.country_tag,
		"leader_type": leader.leader_type,
		"attack_skill": leader.attack_skill,
		"defense_skill": leader.defense_skill,
		"organization_skill": leader.organization_skill,
		"logistics_skill": leader.logistics_skill,
		"planning_skill": leader.planning_skill,
		"initiative_skill": leader.initiative_skill,
		"traits": leader.traits.duplicate(),
		"trait_levels": leader.trait_levels.duplicate(),
		"training_path_id": leader.training_path_id,
		"training_path_level": leader.training_path_level,
		"previous_training_path_id": leader.previous_training_path_id,
		"training_path_display": get_leader_training_path_summary(leader_id),
		"trait_display": get_trait_display_list(leader),
		"experience": leader.experience,
		"total_experience_earned": leader.total_experience_earned,
		"last_xp_source": leader.last_xp_source,
		"battles_fought": leader.battles_fought,
		"birth_year": leader.birth_year,
		"start_year": leader.start_year,
		"end_year": leader.end_year,
		"age": get_leader_age(leader),
		"health": leader.health,
		"duty_post": leader.duty_post,
		"is_injured": leader.is_injured,
		"is_captured": leader.is_captured,
		"is_retired": leader.is_retired,
		"is_deceased": leader.is_deceased,
		"assigned_army_id": leader.assigned_army_id,
		"is_in_officer_training": leader.is_in_officer_training,
		"portrait_path": leader.portrait_path,
	}


func get_country_leader_overview(country_tag: String) -> Dictionary:
	var summaries: Array = []
	for leader in get_leaders_for_country(country_tag):
		summaries.append(get_leader_summary(leader.leader_id))

	var positions: Dictionary = {}
	if country_positions.has(country_tag):
		positions = (country_positions[country_tag] as Dictionary).duplicate()

	return {
		"country_tag": country_tag,
		"total_leaders": summaries.size(),
		"available_count": get_available_leaders(country_tag).size(),
		"leaders": summaries,
		"national_positions": positions,
	}


func get_leader_screen_data(country_tag: String, use_cache: bool = true) -> LeaderScreenData:
	if use_cache and _leader_screen_cache.has(country_tag):
		return _leader_screen_cache[country_tag] as LeaderScreenData

	var data := _build_leader_screen_data(country_tag)
	_leader_screen_cache[country_tag] = data
	return data


func invalidate_leader_cache(country_tag: String) -> void:
	_leader_screen_cache.erase(country_tag)


func clear_all_leader_caches() -> void:
	_leader_screen_cache.clear()


func _build_leader_screen_data(country_tag: String) -> LeaderScreenData:
	var data := LeaderScreenData.new()
	data.country_tag = country_tag

	var country_leader_list := get_leaders_for_country(country_tag)
	data.total_leaders = country_leader_list.size()

	var available := 0
	var injured := 0
	var captured := 0
	var assigned := 0

	var by_type: Dictionary = {}
	var by_availability: Dictionary = {
		"available": [],
		"assigned": [],
		"injured": [],
		"captured": [],
	}
	var by_skill_tier: Dictionary = {}

	for leader in country_leader_list:
		var summary := get_leader_summary(leader.leader_id)
		summary["skill_tier"] = _get_skill_tier(leader)
		summary["leader_type_name"] = _get_leader_type_name(leader.leader_type)
		data.leaders.append(summary)

		if leader.is_captured:
			captured += 1
			_append_leader_to_group(by_availability, "captured", summary)
		elif leader.is_injured:
			injured += 1
			_append_leader_to_group(by_availability, "injured", summary)
		elif not leader.assigned_army_id.is_empty():
			assigned += 1
			_append_leader_to_group(by_availability, "assigned", summary)
		else:
			available += 1
			_append_leader_to_group(by_availability, "available", summary)

		var leader_type := leader.leader_type if not leader.leader_type.is_empty() else "general"
		_append_leader_to_group(by_type, leader_type, summary)
		_append_leader_to_group(by_skill_tier, str(summary.get("skill_tier", "average")), summary)

	data.available_leaders = available
	data.injured_leaders = injured
	data.captured_leaders = captured
	data.leaders_assigned_to_armies = assigned
	data.leaders_by_type = by_type
	data.leaders_by_availability = by_availability
	data.leaders_by_skill_tier = by_skill_tier

	if country_positions.has(country_tag):
		data.national_positions = (country_positions[country_tag] as Dictionary).duplicate()
	data.national_position_bonuses = get_national_bonuses(country_tag)

	data.has_many_injured = (
		data.total_leaders > 0 and float(injured) > float(data.total_leaders) * 0.25
	)
	data.has_no_chief_of_army = not data.national_positions.has(POSITION_CHIEF_OF_ARMY)

	return data


# === Leader helper methods ===

func _get_skill_tier(leader: Leader) -> String:
	var avg_skill := (
		float(leader.attack_skill)
		+ float(leader.defense_skill)
		+ float(leader.logistics_skill)
		+ float(leader.planning_skill)
	) / 4.0

	if avg_skill >= 8.0:
		return "elite"
	if avg_skill >= 6.0:
		return "veteran"
	if avg_skill >= 4.0:
		return "average"
	return "green"


func _get_leader_type_name(leader_type: String) -> String:
	match leader_type:
		"general":
			return "General"
		"admiral":
			return "Admiral"
		"air_marshal":
			return "Air Marshal"
		"space_commander":
			return "Space Commander"
		_:
			return leader_type.capitalize()


func _append_leader_to_group(group_dict: Dictionary, key: String, summary: Dictionary) -> void:
	if not group_dict.has(key):
		group_dict[key] = []
	(group_dict[key] as Array).append(summary)


# === XP system ===

func award_xp_to_leader(leader_id: String, amount: int, source: String = "") -> void:
	if amount <= 0:
		return
	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null or not leader.is_available_for_command():
		return
	var count_as_battle := source == "combat" or source == "battle"
	leader.add_experience(amount, source, count_as_battle)
	leader_experience_gained.emit(leader_id, amount, source)
	if count_as_battle:
		_check_for_trait_gain(leader)
	invalidate_leader_cache(leader.country_tag)


func award_xp_to_formation_leaders(formation_id: String, amount: int, source: String = "") -> void:
	if formation_id.is_empty() or amount <= 0:
		return
	var formation := get_formation(formation_id)
	if formation == null or not formation.has_leader():
		return
	award_xp_to_leader(formation.leader_id, amount, source)


func get_passive_xp_for_leader(leader: Leader) -> int:
	if leader == null or not leader.is_available_for_command():
		return 0
	if leader.assigned_army_id.is_empty():
		return 0

	var formation := get_formation(leader.assigned_army_id)
	if formation == null:
		return 0

	var xp := XP_PASSIVE_ASSIGNED_IDLE
	if formation.is_training or leader.duty_post == "training":
		xp = XP_PASSIVE_TRAINING
	elif formation.is_in_combat:
		xp = XP_PASSIVE_IN_COMBAT

	if bool(countries_at_war.get(leader.country_tag, false)):
		xp += XP_PASSIVE_AT_WAR_BONUS

	return xp


func process_passive_xp() -> void:
	process_weekly_leader_xp()


# ============================================
# XP SYSTEM - Combat & passive gain (weekly tick)
# ============================================

func calculate_combat_xp_from_result(battle_result: Dictionary) -> int:
	var xp := XP_COMBAT_BATTLE_BASE
	if bool(battle_result.get("is_major_victory", false)):
		xp += XP_COMBAT_MAJOR_VICTORY_BONUS
	elif bool(battle_result.get("is_heroic_defense", false)):
		xp += XP_COMBAT_HEROIC_DEFENSE_BONUS
	if bool(battle_result.get("was_high_risk", false)) and bool(battle_result.get("success", false)):
		xp += XP_COMBAT_HIGH_RISK_SUCCESS_BONUS
	var intensity := float(battle_result.get("intensity", 1.0))
	xp = int(float(xp) * clampf(intensity, 0.25, 4.0))
	return maxi(xp, 1)


func award_combat_xp(leader_id: String, battle_result: Dictionary = {}) -> void:
	if leader_id.is_empty():
		return
	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null or not leader.is_available_for_command():
		return
	if leader.is_injured:
		return
	var amount := int(battle_result.get("total_xp", 0))
	if amount <= 0:
		amount = calculate_combat_xp_from_result(battle_result)
	award_xp_to_leader(leader_id, amount, "combat")


func process_weekly_leader_xp() -> void:
	for leader_id in leaders.keys():
		var leader: Leader = leaders.get(leader_id) as Leader
		if leader == null or not leader.is_available_for_command():
			continue
		if leader.assigned_army_id.is_empty():
			continue

		var formation := get_formation(leader.assigned_army_id)
		if formation == null:
			continue

		var xp_to_gain := XP_PASSIVE_ASSIGNED_IDLE
		if formation.is_training or leader.duty_post == "training":
			xp_to_gain = XP_PASSIVE_TRAINING
		elif formation.is_in_combat:
			xp_to_gain = XP_PASSIVE_IN_COMBAT

		if bool(countries_at_war.get(leader.country_tag, false)):
			xp_to_gain += XP_PASSIVE_AT_WAR_BONUS

		if xp_to_gain > 0:
			award_xp_to_leader(leader_id, xp_to_gain, "passive")


func award_battle_xp_to_participants(
	attacker_leader_id: String,
	defender_leader_id: String,
	battle_result: Dictionary = {},
) -> void:
	if not attacker_leader_id.is_empty():
		award_combat_xp(attacker_leader_id, battle_result)
	var defender_result := battle_result.duplicate()
	if not defender_leader_id.is_empty():
		# Defenders gain slightly less baseline pressure unless heroic defense.
		if not bool(defender_result.get("is_heroic_defense", false)):
			defender_result["intensity"] = float(defender_result.get("intensity", 1.0)) * 0.85
		award_combat_xp(defender_leader_id, defender_result)


func get_leader_id_for_army(army_or_formation_id: String) -> String:
	var leader: Leader = get_leader_for_army(army_or_formation_id)
	if leader == null:
		return ""
	return leader.leader_id


func set_country_at_war(country_tag: String, at_war: bool) -> void:
	if country_tag.is_empty():
		return
	countries_at_war[country_tag] = at_war


func award_major_victory_xp(leader_id: String, bonus: int = 60) -> void:
	award_xp_to_leader(leader_id, clampi(bonus, 30, 150), "major_victory")


func award_high_risk_operation_xp(leader_id: String, bonus: int = 45) -> void:
	award_xp_to_leader(leader_id, clampi(bonus, 30, 80), "high_risk_operation")


# ============================================
# XP SYSTEM - Trait Leveling
# ============================================

## Returns the current level of a trait for a leader (0 if they don't have it).
func get_trait_level(leader_id: String, trait_id: String) -> int:
	var leader := get_leader(leader_id)
	if leader == null:
		return 0
	return leader.get_trait_level(trait_id)


## Trait definition lookup (traits.json via LeaderManager cache).
func get_trait_data(trait_id: String) -> Dictionary:
	return get_trait_definition(trait_id)


## XP cost to advance from current_level to current_level + 1.
func get_trait_level_cost(current_level: int) -> int:
	match current_level:
		0: return 100
		1: return 150
		2: return 250
		_: return 300


func can_level_trait(leader_id: String, trait_id: String) -> bool:
	var leader := get_leader(leader_id)
	if leader == null:
		return false

	var trait_data := get_trait_data(trait_id)
	if trait_data.is_empty():
		return false

	var current_level := get_trait_level(leader_id, trait_id)
	var max_level := int(trait_data.get("max_level", 3))
	if current_level >= max_level:
		return false

	if not can_add_trait(leader, trait_id, 1):
		return false

	var cost := get_trait_level_cost(current_level)
	return leader.has_enough_experience(cost)


## Levels up a trait by spending XP. Returns true if at least one level was gained.
func level_trait(leader_id: String, trait_id: String, levels: int = 1) -> bool:
	var gained := 0
	for _i in maxi(levels, 0):
		if not _level_trait_once(leader_id, trait_id):
			break
		gained += 1
	return gained > 0


func _level_trait_once(leader_id: String, trait_id: String) -> bool:
	if not can_level_trait(leader_id, trait_id):
		return false

	var leader := get_leader(leader_id)
	var current_level := get_trait_level(leader_id, trait_id)
	var cost := get_trait_level_cost(current_level)

	if not leader.spend_experience(cost):
		return false

	if not try_add_trait_to_leader(leader, trait_id, 1):
		return false

	var new_level := get_trait_level(leader_id, trait_id)
	print("%s leveled %s to level %d" % [leader.name, trait_id, new_level])
	emit_signal("trait_leveled", leader_id, trait_id, new_level)
	return true


# ============================================
# DOCTRINE TRAINING PATHS
# ============================================
## One primary path per leader (training_path_id + training_path_level on Leader).
## Future: optional training_paths: Dictionary or trait-gated second path.


## Returns all training paths the leader is eligible for.
func get_available_training_paths(leader_id: String) -> Array[Dictionary]:
	var leader := get_leader(leader_id)
	if leader == null:
		return []

	var available: Array[Dictionary] = []
	var all_paths := _load_training_paths()

	for path_id in all_paths.keys():
		var path_data: Dictionary = all_paths[path_id] as Dictionary
		var requirement: String = str(path_data.get("doctrine_requirement", ""))
		if not _country_has_doctrine(leader.country_tag, requirement):
			continue

		var pid := str(path_id)
		var current_level := (
			leader.training_path_level if leader.training_path_id == pid else 0
		)
		available.append({
			"path_id": pid,
			"name": str(path_data.get("name", pid)),
			"current_level": current_level,
			"max_level": int(path_data.get("max_level", 3)),
			"description": str(path_data.get("description", "")),
			"effects": _get_training_path_effects(pid, current_level),
			"next_level_effects": _get_training_path_effects(pid, current_level + 1),
			"is_active": leader.training_path_id == pid,
		})

	return available


## Returns the current level of a training path for a leader.
func get_leader_training_path_level(leader_id: String, path_id: String) -> int:
	var leader := get_leader(leader_id)
	if leader == null:
		return 0
	if leader.training_path_id == path_id:
		return leader.training_path_level
	return 0


## Invest XP into a training path (sets it as the leader's active path).
func invest_xp_in_training_path(leader_id: String, path_id: String) -> bool:
	var leader := get_leader(leader_id)
	if leader == null:
		return false

	var current_level := get_leader_training_path_level(leader_id, path_id)
	var path_data := _get_training_path_data(path_id)
	if path_data.is_empty():
		return false
	if current_level >= int(path_data.get("max_level", 3)):
		return false
	if not _country_has_doctrine(leader.country_tag, str(path_data.get("doctrine_requirement", ""))):
		return false

	var cost := get_training_path_level_cost(current_level)
	if leader.experience < cost:
		return false
	if not leader.spend_experience(cost):
		return false

	var new_level := mini(current_level + 1, int(path_data.get("max_level", 3)))
	leader.set_training_path(path_id, new_level)
	invalidate_leader_cache(leader.country_tag)
	emit_signal("training_path_invested", leader_id, path_id, new_level)
	return true


## Switch a leader to a different training path (expensive).
func switch_training_path(leader_id: String, new_path_id: String) -> bool:
	var leader := get_leader(leader_id)
	if leader == null:
		return false

	if leader.training_path_id == new_path_id:
		return false

	var path_data := _get_training_path_data(new_path_id)
	if path_data.is_empty():
		return false
	if not _country_has_doctrine(leader.country_tag, str(path_data.get("doctrine_requirement", ""))):
		return false

	var switch_cost := get_training_path_switch_cost(leader_id, new_path_id)
	if switch_cost <= 0:
		return false
	if leader.experience < switch_cost:
		print("Not enough XP to switch training path. Cost: %d" % switch_cost)
		return false
	if not leader.spend_experience(switch_cost):
		return false

	var old_path_id := leader.training_path_id
	leader.set_training_path(new_path_id, 1)
	invalidate_leader_cache(leader.country_tag)
	print(
		"%s switched to new training path: %s (Cost: %d XP)"
		% [leader.name, new_path_id, switch_cost]
	)
	emit_signal("training_path_switched", leader_id, old_path_id, new_path_id)
	return true


func leader_has_training_path(leader_id: String) -> bool:
	var leader := get_leader(leader_id)
	if leader == null:
		return false
	return leader.has_training_path()


func get_training_path_definition(path_id: String) -> Dictionary:
	return _get_training_path_data(path_id)


func get_training_path_max_level(path_id: String) -> int:
	var def: Dictionary = get_training_path_definition(path_id)
	if def.is_empty():
		return 0
	return maxi(int(def.get("max_level", 3)), 1)


func get_training_path_doctrine_requirement(path_id: String) -> String:
	var def: Dictionary = get_training_path_definition(path_id)
	return str(def.get("doctrine_requirement", ""))


func get_training_path_effects_at_level(path_id: String, level: int) -> Dictionary:
	return _get_training_path_effects(path_id, level)


func get_leader_training_path_effects(leader: Leader) -> Dictionary:
	if leader == null or not leader.has_training_path():
		return {}
	return get_training_path_effects_at_level(leader.training_path_id, leader.training_path_level)


# ============================================
# TRAINING PATH - COMBAT MODIFIERS
# ============================================

const TRAINING_PATH_COMBAT_EFFECT_KEYS: Array[String] = [
	"attack",
	"defense",
	"initiative",
	"breakthrough",
	"planning",
	"combined_arms_sync",
]


## Returns combat-related modifiers from the leader's current training path.
func get_leader_training_path_combat_modifiers(leader_id: String) -> Dictionary:
	var leader := get_leader(leader_id)
	if leader == null or not leader.has_training_path():
		return {}

	var effects := get_training_path_effects_at_level(
		leader.training_path_id,
		leader.training_path_level,
	)
	if effects.is_empty():
		return {}

	var modifiers: Dictionary = {}
	for effect_key in effects.keys():
		var key := str(effect_key)
		if TRAINING_PATH_COMBAT_EFFECT_KEYS.has(key):
			modifiers[key] = float(effects[effect_key])
	return modifiers


## Final combat stats for a leader after training path bonuses (delegates to CombatResolver).
func get_leader_final_combat_stats(leader_id: String, base_stats: Dictionary) -> Dictionary:
	if leader_id.is_empty():
		return base_stats.duplicate()
	var resolver: CombatResolver = CombatResolver.new()
	var stats: Dictionary = resolver.apply_training_path_combat_bonuses(leader_id, base_stats)
	resolver.free()
	return stats


# ============================================
# TRAINING PATH - SUPPLY & LOGISTICS MODIFIERS
# ============================================

## Returns supply and logistics modifiers from the leader's current training path.
func get_leader_training_path_supply_modifiers(leader_id: String) -> Dictionary:
	var leader := get_leader(leader_id)
	if leader == null or leader.training_path_id.is_empty():
		return {}

	var path_id := leader.training_path_id
	var level := leader.training_path_level
	var effects := _get_training_path_effects(path_id, level)
	if effects.is_empty():
		return {}

	var modifiers: Dictionary = {}
	if effects.has("supply_consumption"):
		modifiers["supply_consumption"] = float(effects["supply_consumption"])
	if effects.has("organization_recovery"):
		modifiers["organization_recovery"] = float(effects["organization_recovery"])
	if effects.has("reinforcement_speed"):
		modifiers["reinforcement_speed"] = float(effects["reinforcement_speed"])
	if effects.has("attrition_reduction"):
		modifiers["attrition_reduction"] = float(effects["attrition_reduction"])
	return modifiers


func resolve_leader_id_for_formation(formation_id: String) -> String:
	if formation_id.is_empty():
		return ""
	var formation := get_formation(formation_id)
	if formation != null and formation.has_leader():
		return formation.leader_id
	return get_leader_id_for_army(formation_id)


func apply_supply_consumption_for_leader(base_consumption: float, leader_id: String) -> float:
	var consumption := base_consumption
	var modifiers := get_leader_training_path_supply_modifiers(leader_id)
	if modifiers.has("supply_consumption"):
		consumption *= 1.0 + float(modifiers["supply_consumption"])
	return maxf(consumption, 0.1)


func apply_attrition_for_leader(base_attrition: float, leader_id: String) -> float:
	var modifiers := get_leader_training_path_supply_modifiers(leader_id)
	var final_attrition := base_attrition
	if modifiers.has("attrition_reduction"):
		final_attrition *= maxf(1.0 - float(modifiers["attrition_reduction"]), 0.0)
	return maxf(final_attrition, 0.0)


func apply_reinforcement_rate_for_leader(base_rate: float, leader_id: String) -> float:
	var modifiers := get_leader_training_path_supply_modifiers(leader_id)
	if modifiers.has("reinforcement_speed"):
		return base_rate * (1.0 + float(modifiers["reinforcement_speed"]))
	return base_rate


## Applies training path supply/logistics modifiers to division combat/supply stats.
func apply_training_path_supply_to_stats(
	stats: Dictionary,
	army_or_unit_id: String = "",
) -> Dictionary:
	if stats.is_empty():
		return stats

	var leader_id := resolve_leader_id_for_formation(army_or_unit_id)
	if leader_id.is_empty() and get_leader(army_or_unit_id) != null:
		leader_id = army_or_unit_id
	var modifiers := get_leader_training_path_supply_modifiers(leader_id)
	if modifiers.is_empty():
		return stats

	var modified := stats.duplicate()
	modified["supply_consumption"] = apply_supply_consumption_for_leader(
		float(modified.get("supply_consumption", 1.0)),
		leader_id,
	)

	if modifiers.has("organization_recovery"):
		var recovery := float(modifiers["organization_recovery"])
		modified["readiness"] = float(modified.get("readiness", 1.0)) + recovery * 0.35
		modified["organization"] = float(modified.get("organization", 1.0)) + recovery * 0.25

	modified["training_path_supply_modifiers"] = modifiers
	return modified


func get_training_path_reinforcement_multiplier(leader_id: String) -> float:
	return apply_reinforcement_rate_for_leader(1.0, leader_id)


func get_training_path_data(path_id: String) -> Dictionary:
	return _get_training_path_data(path_id)


func get_training_path_level_cost(current_level: int) -> int:
	return 150 + (maxi(current_level, 0) * 100)


## Returns how much XP it would cost to switch to a new training path.
func get_training_path_switch_cost(leader_id: String, new_path_id: String) -> int:
	var leader := get_leader(leader_id)
	if leader == null or leader.training_path_id == new_path_id:
		return 0
	var current_level := leader.training_path_level
	return TRAINING_PATH_SWITCH_COST_BASE + (current_level * TRAINING_PATH_SWITCH_COST_PER_LEVEL)


func can_invest_training_path(leader_id: String, path_id: String) -> bool:
	var leader := get_leader(leader_id)
	if leader == null:
		return false
	var current_level := get_leader_training_path_level(leader_id, path_id)
	var path_data := _get_training_path_data(path_id)
	if path_data.is_empty() or current_level >= int(path_data.get("max_level", 3)):
		return false
	if not _country_has_doctrine(leader.country_tag, str(path_data.get("doctrine_requirement", ""))):
		return false
	return leader.experience >= get_training_path_level_cost(current_level)


func can_switch_training_path(leader_id: String, new_path_id: String) -> bool:
	var leader := get_leader(leader_id)
	if leader == null:
		return false
	if leader.training_path_id == new_path_id:
		return false
	if not _get_training_path_data(new_path_id):
		return false
	if not _country_has_doctrine(
		leader.country_tag, get_training_path_doctrine_requirement(new_path_id)
	):
		return false
	var switch_cost := get_training_path_switch_cost(leader_id, new_path_id)
	return leader_has_training_path(leader_id) and switch_cost > 0 and leader.experience >= switch_cost


func get_leader_training_path_state(leader_id: String) -> Dictionary:
	var leader := get_leader(leader_id)
	if leader == null:
		return {"path_id": "", "level": 0}
	return {
		"path_id": leader.training_path_id,
		"level": leader.training_path_level,
		"previous_path_id": leader.previous_training_path_id,
	}


func get_available_training_paths_for_leader(leader_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in get_available_training_paths(leader_id):
		var pid := str(entry.get("path_id", ""))
		var current_level := int(entry.get("current_level", 0))
		var max_level := int(entry.get("max_level", 3))
		var is_active := bool(entry.get("is_active", false))
		var row: Dictionary = entry.duplicate()
		row.merge({
			"doctrine_requirement": get_training_path_doctrine_requirement(pid),
			"doctrine_unlocked": true,
			"is_current": is_active,
			"effects_text": format_trait_effects_text(entry.get("effects", {})),
			"can_invest": can_invest_training_path(leader_id, pid),
			"invest_cost": get_training_path_level_cost(
				current_level if is_active else 0
			),
			"can_switch": can_switch_training_path(leader_id, pid) and not is_active,
			"switch_cost": get_training_path_switch_cost(leader_id, pid),
			"at_max_level": is_active and current_level >= max_level,
		})
		rows.append(row)
	return rows


func get_leader_training_path_summary(leader_id: String) -> Dictionary:
	var leader := get_leader(leader_id)
	if leader == null or not leader.has_training_path():
		return {
			"path_id": "",
			"level": 0,
			"name": "",
			"effects": {},
			"effects_text": "",
		}

	var def: Dictionary = get_training_path_definition(leader.training_path_id)
	var effects := get_leader_training_path_effects(leader)
	return {
		"path_id": leader.training_path_id,
		"level": leader.training_path_level,
		"name": str(def.get("name", leader.training_path_id)),
		"description": str(def.get("description", "")),
		"max_level": get_training_path_max_level(leader.training_path_id),
		"effects": effects,
		"effects_text": format_trait_effects_text(effects),
		"can_invest": can_invest_training_path(leader_id, leader.training_path_id),
		"invest_cost": get_training_path_level_cost(leader.training_path_level),
		"switch_cost_preview": (
			TRAINING_PATH_SWITCH_COST_BASE
			+ leader.training_path_level * TRAINING_PATH_SWITCH_COST_PER_LEVEL
		),
		"previous_path_id": leader.previous_training_path_id,
	}


func _load_training_paths() -> Dictionary:
	if not training_path_definitions.is_empty():
		return training_path_definitions

	var json_path := TRAINING_PATHS_PATH
	if not FileAccess.file_exists(json_path):
		push_error("Doctrine training paths file not found: " + json_path)
		return {}

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("Could not open doctrine training paths file: " + json_path)
		return {}

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK:
		push_error("Failed to parse doctrine_training_paths.json: " + json.get_error_message())
		return {}

	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("doctrine_training_paths.json root must be a dictionary")
		return {}

	training_path_definitions = data as Dictionary
	return training_path_definitions


func _get_training_path_data(path_id: String) -> Dictionary:
	var paths := _load_training_paths()
	var key := str(path_id)
	if paths.has(key):
		return paths[key] as Dictionary
	return {}


func _get_training_path_effects(path_id: String, level: int) -> Dictionary:
	if level <= 0:
		return {}
	var path_data := _get_training_path_data(path_id)
	var effects_by_level: Variant = path_data.get("effects_by_level", {})
	if typeof(effects_by_level) != TYPE_DICTIONARY:
		return {}
	var level_key := str(clampi(level, 1, get_training_path_max_level(path_id)))
	if not (effects_by_level as Dictionary).has(level_key):
		return {}
	var effects: Variant = (effects_by_level as Dictionary)[level_key]
	if typeof(effects) != TYPE_DICTIONARY:
		return {}
	return (effects as Dictionary).duplicate()


func _country_has_doctrine(country_tag: String, doctrine_id: String) -> bool:
	if str(doctrine_id).is_empty():
		return true
	if typeof(TechnologyManager) != TYPE_NIL:
		return TechnologyManager.is_doctrine_key_unlocked(country_tag, doctrine_id)
	return country_has_military_doctrine(country_tag, doctrine_id)


func _load_training_path_definitions() -> void:
	_load_training_paths()


func get_country_military_doctrines(country_tag: String) -> Array[String]:
	# Legacy shim for old Array API. Returns list of all service doctrines for country.
	var tag := str(country_tag)
	if not service_doctrines.has(tag):
		return []
	var serv := service_doctrines[tag] as Dictionary
	var out: Array[String] = []
	for s in serv:
		var d := str(serv[s])
		if not d.is_empty() and not out.has(d):
			out.append(d)
	return out


func set_country_military_doctrine(
	country_tag: String,
	doctrine_id: String,
	active: bool,
	silent: bool = false,
) -> void:
	# Legacy: set on army for simplicity. Prefer set_service_doctrine.
	if active:
		set_service_doctrine(country_tag, "army", doctrine_id, silent)


func country_has_military_doctrine(country_tag: String, doctrine_id: String) -> bool:
	var tag := str(country_tag)
	if not service_doctrines.has(tag):
		return false
	var serv := service_doctrines[tag] as Dictionary
	for s in serv:
		if str(serv[s]) == doctrine_id:
			return true
	return false


func leader_meets_training_path_doctrine(leader: Leader, path_id: String) -> bool:
	if leader == null:
		return false
	return _country_has_doctrine(leader.country_tag, get_training_path_doctrine_requirement(path_id))


# ============================================
# LEADER DISPLAY HELPERS
# ============================================

## UI-friendly trait rows for a leader (character sheet, assignment panel, etc.).
func get_leader_trait_display_data(leader_id: String) -> Array[Dictionary]:
	var leader := get_leader(leader_id)
	if leader == null:
		return []

	var display_data: Array[Dictionary] = []
	for trait_id in leader.trait_levels.keys():
		var tid := str(trait_id)
		var level := int(leader.trait_levels[tid])
		var trait_data := get_trait_data(tid)
		var effects := get_trait_effects_at_level(tid, level)
		var can_level := can_level_trait(leader_id, tid)
		display_data.append({
			"trait_id": tid,
			"id": tid,
			"name": str(trait_data.get("name", tid)),
			"level": level,
			"max_level": get_trait_max_level(tid),
			"roman": ROMAN_LEVELS[mini(level, ROMAN_LEVELS.size() - 1)],
			"rarity": str(trait_data.get("rarity", "common")),
			"description": str(trait_data.get("description", "")),
			"effects": effects,
			"effects_text": format_trait_effects_text(effects),
			"can_level_up": can_level,
			"level_up_cost": get_trait_level_cost(level) if can_level else 0,
		})
	return display_data


# ============================================
# TRAIT AVAILABILITY & UNLOCK HELPERS
# ============================================

const POTENTIAL_TRAIT_CANDIDATES: Array[String] = [
	"tank_leader",
	"logistics_wizard",
	"combined_arms_master",
	"mountain_specialist",
	"artillery_expert",
]


## Traits the leader does not have yet but could potentially unlock (UI preview).
func get_potential_traits_for_leader(leader_id: String) -> Array[Dictionary]:
	var leader := get_leader(leader_id)
	if leader == null:
		return []

	var potential: Array[Dictionary] = []
	for trait_id in POTENTIAL_TRAIT_CANDIDATES:
		if leader.has_trait(trait_id) or leader.trait_levels.has(trait_id):
			continue

		var trait_data := get_trait_data(trait_id)
		if trait_data.is_empty():
			continue

		potential.append({
			"trait_id": trait_id,
			"name": str(trait_data.get("name", trait_id)),
			"rarity": str(trait_data.get("rarity", "common")),
			"unlock_reason": _get_unlock_reason(leader_id, trait_id),
			"can_unlock_now": false,
		})
	return potential


func _get_unlock_reason(_leader_id: String, trait_id: String) -> String:
	match trait_id:
		"tank_leader":
			return "Requires Armor Doctrine or significant time commanding armored units"
		"logistics_wizard":
			return "Requires Logistics focus or extended supply management experience"
		"combined_arms_master":
			return "Requires Combined Arms Doctrine"
		"mountain_specialist":
			return "Requires significant time operating in mountainous terrain"
		"artillery_expert":
			return "Requires Artillery Doctrine or prolonged artillery coordination"
		_:
			return "Locked behind doctrine, focus, or experience"


# === Experience, traits, injury, capture, promotion ===

func award_battle_experience(leader_id: String, amount: int = 25, count_as_battle: bool = true) -> void:
	var source := "combat" if count_as_battle else "battle"
	award_xp_to_leader(leader_id, amount, source)


func award_combat_experience_for_army(army_id: String, intensity: float = 1.0) -> void:
	if army_id.is_empty():
		return
	var leader: Leader = get_leader_for_army(army_id)
	if leader == null or leader.is_injured or leader.is_captured:
		return
	var amount := int(float(XP_BASE_COMBAT) * clampf(intensity, 0.25, 4.0) * XP_COMBAT_MULTIPLIER)
	award_battle_experience(leader.leader_id, amount, true)


func get_trait_level_up_cost(leader: Leader, trait_id: String) -> int:
	if leader == null or trait_id.is_empty():
		return 0
	if get_trait_definition(trait_id).is_empty():
		return 0
	return get_trait_level_cost(leader.get_trait_level(trait_id))


func can_spend_xp_on_trait(leader: Leader, trait_id: String) -> Dictionary:
	if leader == null:
		return {"ok": false, "reason": "no_leader"}
	if get_trait_definition(trait_id).is_empty():
		return {"ok": false, "reason": "unknown_trait"}
	var cost := get_trait_level_up_cost(leader, trait_id)
	if leader.get_trait_level(trait_id) >= get_trait_max_level(trait_id):
		return {"ok": false, "reason": "max_level", "cost": cost}
	if not can_add_trait(leader, trait_id, 1):
		return {"ok": false, "reason": "blocked", "cost": cost}
	if not leader.has_enough_experience(cost):
		return {"ok": false, "reason": "insufficient_xp", "cost": cost}
	return {"ok": true, "cost": cost}


func spend_xp_on_trait(leader_id: String, trait_id: String) -> Dictionary:
	var leader: Leader = get_leader(leader_id)
	var check := can_spend_xp_on_trait(leader, trait_id)
	if not bool(check.get("ok", false)):
		return {"success": false, "reason": str(check.get("reason", "blocked"))}

	var cost := int(check.get("cost", 0))
	if not level_trait(leader_id, trait_id, 1):
		return {"success": false, "reason": "failed"}
	return {
		"success": true,
		"cost": cost,
		"trait_id": trait_id,
		"new_level": get_trait_level(leader_id, trait_id),
	}


func get_trait_display_list(leader: Leader) -> Array:
	if leader == null:
		return []
	var rows: Array = []
	for entry in get_leader_trait_display_data(leader.leader_id):
		rows.append(entry)
	return rows


func format_trait_effects_text(effects: Dictionary) -> String:
	if effects.is_empty():
		return ""
	var parts: PackedStringArray = []
	for effect_key in effects.keys():
		var key := str(effect_key)
		var value: float = float(effects[effect_key])
		parts.append("%s: %s" % [_format_effect_label(key), _format_effect_value(key, value)])
	return ", ".join(parts)


func _format_effect_label(effect_key: String) -> String:
	match effect_key:
		"attack":
			return "Attack"
		"defense":
			return "Defense"
		"logistics":
			return "Logistics"
		"planning":
			return "Planning"
		"initiative":
			return "Initiative"
		"organization":
			return "Organization"
		"supply_consumption":
			return "Supply use"
		"breakthrough":
			return "Breakthrough"
		"combined_arms_sync":
			return "Combined arms"
		"organization_recovery":
			return "Org recovery"
		"movement_speed":
			return "Movement speed"
		"entrenchment":
			return "Entrenchment"
		"reinforcement_speed":
			return "Reinforcement"
		"attrition_reduction":
			return "Attrition"
		"casualties":
			return "Casualties"
		"naval_combat":
			return "Naval combat"
		"armor_attack":
			return "Armor attack"
		"combat_width":
			return "Combat width"
		"desert_attack":
			return "Desert attack"
		"desert_defense":
			return "Desert defense"
		"arctic_attack":
			return "Arctic attack"
		"arctic_defense":
			return "Arctic defense"
		"jungle_attack":
			return "Jungle attack"
		"jungle_defense":
			return "Jungle defense"
		"mountain_attack":
			return "Mountain attack"
		"mountain_defense":
			return "Mountain defense"
		_:
			return effect_key.replace("_", " ").capitalize()


func _format_effect_value(effect_key: String, value: float) -> String:
	if effect_key in ["attack", "defense", "logistics", "planning", "initiative", "organization"]:
		if value >= 0.0:
			return "+%d" % int(value)
		return "%d" % int(value)
	if effect_key == "supply_consumption":
		return "%+d%%" % int(value * 100.0)
	if absf(value) < 1.0:
		return "%+d%%" % int(value * 100.0)
	return "%+.2f" % value


func _check_for_trait_gain(leader: Leader) -> void:
	if leader.battles_fought >= 15 and not leader.has_trait("logistics_wizard"):
		if randf() < 0.25 and try_add_trait_to_leader(leader, "logistics_wizard", 1):
			print("%s has gained the trait: Logistics Wizard!" % leader.name)

	if leader.battles_fought >= 25 and randf() < 0.15:
		if not leader.has_trait("desert_fox") and randf() < 0.3:
			if try_add_trait_to_leader(leader, "desert_fox", 1):
				print("%s has gained the trait: Desert Fox!" % leader.name)


func handle_injury_or_capture(leader_id: String) -> void:
	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null:
		return

	if randf() < 0.04:
		leader.is_injured = true
		print("%s has been injured!" % leader.name)

	if randf() < 0.015:
		leader.is_captured = true
		print("%s has been captured!" % leader.name)

	invalidate_leader_cache(leader.country_tag)


func promote_leader(leader_id: String) -> bool:
	var leader: Leader = leaders.get(leader_id) as Leader
	if leader == null:
		return false
	leader.attack_skill = mini(leader.attack_skill + 1, MAX_SKILL)
	leader.defense_skill = mini(leader.defense_skill + 1, MAX_SKILL)
	leader.organization_skill = mini(leader.organization_skill + 1, MAX_SKILL)
	leader.logistics_skill = mini(leader.logistics_skill + 1, MAX_SKILL)
	leader.planning_skill = mini(leader.planning_skill + 1, MAX_SKILL)
	print("%s has been promoted!" % leader.name)
	invalidate_leader_cache(leader.country_tag)
	return true


func create_and_register_new_leader(country_tag: String, leader_type: String = "general") -> Leader:
	var generator := LeaderGenerator.new()
	var new_leader := generator.generate_leader(country_tag, leader_type)
	generator.free()
	register_leader(new_leader)
	return new_leader


# ============================================
# NATIONAL POSITIONS - OFFICER TRAINING
# ============================================

## Assigns a leader to the Officer Training national position for a country.
func set_officer_training_leader(country_tag: String, leader_id: String, apply_cost: bool = true) -> bool:
	var tag := country_tag.strip_edges().to_upper()
	var leader := get_leader(leader_id)
	if leader == null:
		return false
	if leader.country_tag != tag:
		push_warning(
			"LeaderManager: leader %s does not match country %s for officer training"
			% [leader_id, tag]
		)
		return false
	if not leader.is_available_for_command() and not leader.is_in_officer_training and not _is_brand_new(leader):
		return false

	var prior_mentor_id := str(officer_training_leader_id.get(tag, ""))
	if not prior_mentor_id.is_empty() and prior_mentor_id != leader_id:
		# New behavior (May 2026): temporary debuff instead of hard reset to 0
		officer_training_debuff_months[tag] = OFFICER_TRAINING_MENTOR_CHANGE_DEBUFF_MONTHS
		# months_in_training is intentionally left alone so long-tenure penalty doesn't reset unfairly
		var previous_mentor := get_leader(prior_mentor_id)
		if previous_mentor != null:
			previous_mentor.is_in_officer_training = false
			if previous_mentor.duty_post == "training":
				previous_mentor.duty_post = "active"

	unassign_leader_from_army(leader_id)
	_clear_leader_from_national_positions(leader_id)

	if apply_cost:
		var cost_check := can_assign_national_position(tag, POSITION_OFFICER_TRAINING, leader_id)
		var cost: Dictionary = cost_check.get("cost", {})
		_apply_national_position_cost(tag, cost)

	if not country_positions.has(tag):
		country_positions[tag] = {}
	(country_positions[tag] as Dictionary)[POSITION_OFFICER_TRAINING] = leader_id
	leader.is_in_officer_training = true
	leader.duty_post = "training"
	officer_training_leader_id[tag] = leader_id
	invalidate_leader_cache(tag)
	return true


## Returns the mentor assigned to Officer Training for a country (if any).
## Auto-cleans dangling unavailable (retired/deceased/captured or !available unless brand-new) so UI cards show "Vacant"/"Assign" and new leaders (cadets) can be assigned without stale Patton/retire state.
func get_officer_training_leader(country_tag: String = "") -> Leader:
	var tag := country_tag.strip_edges().to_upper()
	var leader: Leader = null
	var leader_id := ""
	if not tag.is_empty() and country_positions.has(tag):
		var positions: Dictionary = country_positions[tag] as Dictionary
		leader_id = str(positions.get(POSITION_OFFICER_TRAINING, ""))
		if not leader_id.is_empty():
			leader = get_leader(leader_id) as Leader
	if leader == null:
		# Fallback scan (legacy is_in_officer_training flag)
		for leader_key in leaders.keys():
			var l: Leader = leaders[leader_key] as Leader
			if l == null or not l.is_in_officer_training:
				continue
			if tag.is_empty() or l.country_tag == tag:
				leader = l
				leader_id = l.leader_id
				break
	if leader == null:
		return null
	# Clean if bad state (retired etc). Brand-new protected (start_year recent) are kept even if !is_available_for_command during intro.
	var should_clear := false
	if leader.is_retired or leader.is_deceased or leader.is_captured or leader.is_injured:
		should_clear = true
	elif leader.is_in_officer_training and leader.duty_post == "training":
		# Active training mentors are intentionally unavailable for field command.
		pass
	elif not leader.is_available_for_command():
		# Allow brand new exceptions (Patton 1936 etc)
		if not (leader.start_year > 0 and get_current_year() - leader.start_year < 2):
			should_clear = true
	if should_clear:
		# Remove from tracking so next get + UI sees Vacant and assign works
		if country_positions.has(tag):
			(country_positions[tag] as Dictionary).erase(POSITION_OFFICER_TRAINING)
		officer_training_leader_id.erase(tag)
		leader.is_in_officer_training = false
		if leader.duty_post == "training":
			leader.duty_post = "active"
		invalidate_leader_cache(tag)
		return null
	return leader


## Clears the Officer Training assignment for a country.
func clear_officer_training_leader(country_tag: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	var current := get_officer_training_leader(tag)
	if current != null:
		current.is_in_officer_training = false
		if current.duty_post == "training":
			current.duty_post = "active"
	if country_positions.has(tag):
		var positions: Dictionary = country_positions[tag] as Dictionary
		positions.erase(POSITION_OFFICER_TRAINING)
	officer_training_leader_id.erase(tag)
	months_in_training.erase(tag)
	officer_training_debuff_months.erase(tag)
	invalidate_leader_cache(tag)


## === Save/Load support (SaveLoadManager contract) ===
## Preserves leaders (with XP, traits, status, assignments via Leader Resource),
## national positions, officer training assignments, and pending items.
func get_save_data() -> Dictionary:
	var leaders_data := {}
	for lid in leaders:
		var l: Leader = leaders[lid]
		if l != null:
			leaders_data[lid] = inst_to_dict(l)

	var formations_data := {}
	for fid in formations.keys():
		var f: Formation = formations[fid] as Formation
		if f == null:
			continue
		formations_data[str(fid)] = {
			"formation_id": f.formation_id,
			"name": f.name,
			"formation_type": f.formation_type,
			"country_tag": f.country_tag,
			"leader_id": f.leader_id,
			"stationed_province_id": f.stationed_province_id,
			# design_id required so post-load reinforce / combat equip stats resolve OOB requirements
			"design_id": f.design_id if "design_id" in f else "",
			"air_design_id": f.air_design_id if "air_design_id" in f else "",
			"naval_design_id": f.naval_design_id if "naval_design_id" in f else "",
			"is_training": f.is_training,
			"is_in_combat": f.is_in_combat,
			"training_progress": f.training_progress,
			"is_trained": f.is_trained,
			"organization": f.organization,
			"readiness": f.readiness,
			"strength": f.strength,
			"combat_experience": float(f.combat_experience) if "combat_experience" in f else 48.0,
			"planning": float(f.planning) if "planning" in f else 0.0,
			"entrenchment": float(f.entrenchment) if "entrenchment" in f else 0.0,
			"current_land_mission": str(f.current_land_mission) if "current_land_mission" in f else "",
			"organize_days": float(f.get_meta("organize_days", 0.0)) if f.has_meta("organize_days") else 0.0,
			"organize_mode": str(f.get_meta("organize_mode", "")) if f.has_meta("organize_mode") else "",
			"organize_target_design": str(f.get_meta("organize_target_design", "")) if f.has_meta("organize_target_design") else "",
			"organize_target_strength": float(f.get_meta("organize_target_strength", 1.0)) if f.has_meta("organize_target_strength") else 1.0,
			"visual_archetype": str(f.get_meta("visual_archetype", "")) if f.has_meta("visual_archetype") else "",
			"combat_log": f.combat_log.duplicate() if "combat_log" in f and f.combat_log is Array else [],
			"mobility": str(f.get_meta("mobility", "foot")) if f.has_meta("mobility") else "foot",
			"armor_element": str(f.get_meta("armor_element", "")) if f.has_meta("armor_element") else "",
			"last_manpower_loss": int(f.last_manpower_loss) if "last_manpower_loss" in f else 0,
		}

	return {
		"leaders": leaders_data,
		"formations": formations_data,
		"country_positions": country_positions.duplicate(true),
		"officer_training_leader_id": officer_training_leader_id.duplicate(true),
		"pending_retirements": pending_retirements.duplicate(true),
		"pending_leader_replacements": pending_leader_replacements.duplicate(true),
		"player_country_tag": player_country_tag,
		"service_doctrines": service_doctrines.duplicate(true),
		"organize_priority": organize_priority,
	}

func apply_save_data(data: Dictionary) -> void:
	leaders.clear()
	country_positions.clear()
	officer_training_leader_id.clear()
	pending_retirements.clear()
	pending_leader_replacements.clear()

	if data.has("leaders"):
		var ldata: Dictionary = data["leaders"]
		for lid in ldata:
			var ld: Dictionary = ldata[lid]
			var l := Leader.new()
			# Restore core + mutable fields from Leader resource
			l.leader_id = str(ld.get("leader_id", lid))
			l.name = str(ld.get("name", ""))
			l.country_tag = str(ld.get("country_tag", ""))
			l.leader_type = str(ld.get("leader_type", "general"))
			l.attack_skill = int(ld.get("attack_skill", 3))
			l.defense_skill = int(ld.get("defense_skill", 3))
			l.organization_skill = int(ld.get("organization_skill", 3))
			l.logistics_skill = int(ld.get("logistics_skill", 3))
			l.planning_skill = int(ld.get("planning_skill", 3))
			l.initiative_skill = int(ld.get("initiative_skill", 3))
			var raw_lt = ld.get("traits", [])
			l.traits = []
			if raw_lt is Array:
				for t in raw_lt:
					l.traits.append(str(t))
			l.experience = int(ld.get("experience", 0))
			l.total_experience_earned = int(ld.get("total_experience_earned", 0))
			l.battles_fought = int(ld.get("battles_fought", 0))
			l.is_injured = bool(ld.get("is_injured", false))
			l.is_captured = bool(ld.get("is_captured", false))
			l.is_retired = bool(ld.get("is_retired", false))
			l.is_deceased = bool(ld.get("is_deceased", false))
			l.assigned_army_id = str(ld.get("assigned_army_id", ""))
			l.birth_year = int(ld.get("birth_year", 1900))
			l.health = float(ld.get("health", 1.0))
			l.duty_post = str(ld.get("duty_post", "active"))
			l.stayed_past_retirement = bool(ld.get("stayed_past_retirement", false))
			l.is_in_officer_training = bool(ld.get("is_in_officer_training", false))
			l.training_path_id = str(ld.get("training_path_id", ""))
			l.training_path_level = int(ld.get("training_path_level", 0))
			l.previous_training_path_id = str(ld.get("previous_training_path_id", ""))
			l.last_xp_gain_time = int(ld.get("last_xp_gain_time", 0))
			l.last_xp_source = str(ld.get("last_xp_source", ""))
			l.portrait_path = str(ld.get("portrait_path", ld.get("portrait", "")))
			if ld.has("trait_levels"):
				l.trait_levels = (ld.get("trait_levels", {}) as Dictionary).duplicate(true)
			# Add other fields (officer training quality etc.) as they become critical
			leaders[l.leader_id] = l

	if data.has("country_positions"):
		country_positions = (data["country_positions"] as Dictionary).duplicate(true)
	if data.has("officer_training_leader_id"):
		officer_training_leader_id = (data["officer_training_leader_id"] as Dictionary).duplicate(true)
	if data.has("pending_retirements"):
		pending_retirements = []
		for x in (data["pending_retirements"] as Array):
			pending_retirements.append(str(x))
	if data.has("pending_leader_replacements"):
		pending_leader_replacements = []
		for x in (data["pending_leader_replacements"] as Array):
			pending_leader_replacements.append(x if x is Dictionary else {})
	if data.has("player_country_tag"):
		player_country_tag = str(data["player_country_tag"])
	if data.has("organize_priority"):
		organize_priority = "new" if str(data.get("organize_priority")).strip_edges().to_lower() == "new" else "field"

	if data.has("service_doctrines"):
		service_doctrines = (data["service_doctrines"] as Dictionary).duplicate(true)

	if data.has("formations"):
		var fdata: Dictionary = data["formations"] as Dictionary
		for fid in fdata.keys():
			var fd: Dictionary = fdata[fid] as Dictionary
			if typeof(fd) != TYPE_DICTIONARY:
				continue
			var f := Formation.new()
			f.formation_id = str(fd.get("formation_id", fid))
			f.name = str(fd.get("name", ""))
			f.formation_type = str(fd.get("formation_type", Formation.TYPE_DIVISION))
			f.country_tag = str(fd.get("country_tag", ""))
			f.leader_id = str(fd.get("leader_id", ""))
			f.stationed_province_id = int(fd.get("stationed_province_id", -1))
			f.design_id = str(fd.get("design_id", ""))
			f.air_design_id = str(fd.get("air_design_id", ""))
			f.naval_design_id = str(fd.get("naval_design_id", ""))
			f.is_training = bool(fd.get("is_training", false))
			f.is_in_combat = bool(fd.get("is_in_combat", false))
			f.training_progress = float(fd.get("training_progress", 0.0))
			f.is_trained = bool(fd.get("is_trained", false))
			f.organization = float(fd.get("organization", 1.0))
			f.readiness = float(fd.get("readiness", 1.0))
			f.strength = float(fd.get("strength", 1.0))
			if "combat_experience" in f:
				f.combat_experience = float(fd.get("combat_experience", 48.0))
			if "planning" in f:
				f.planning = float(fd.get("planning", 0.0))
			if "entrenchment" in f:
				f.entrenchment = float(fd.get("entrenchment", 0.0))
			if "current_land_mission" in f and str(fd.get("current_land_mission", "")).strip_edges() != "":
				f.current_land_mission = str(fd.get("current_land_mission"))
			if float(fd.get("organize_days", 0.0)) > 0.0:
				f.set_meta("organize_days", float(fd.get("organize_days")))
			if str(fd.get("organize_mode", "")).strip_edges() != "":
				f.set_meta("organize_mode", str(fd.get("organize_mode")))
			if str(fd.get("organize_target_design", "")).strip_edges() != "":
				f.set_meta("organize_target_design", str(fd.get("organize_target_design")))
			if fd.has("organize_target_strength"):
				f.set_meta("organize_target_strength", clampf(float(fd.get("organize_target_strength", 1.0)), 0.4, 1.0))
			if str(fd.get("visual_archetype", "")).strip_edges() != "":
				f.set_meta("visual_archetype", str(fd.get("visual_archetype")))
			if str(fd.get("mobility", "")).strip_edges() != "":
				f.set_meta("mobility", str(fd.get("mobility")))
			if str(fd.get("armor_element", "")).strip_edges() != "":
				f.set_meta("armor_element", str(fd.get("armor_element")))
			if "last_manpower_loss" in f:
				f.last_manpower_loss = int(fd.get("last_manpower_loss", 0))
			if fd.get("combat_log") is Array:
				f.combat_log.clear()
				for row in fd.get("combat_log") as Array:
					if row is Dictionary:
						f.combat_log.append(row)
			if str(fd.get("leader_id", "")).strip_edges() != "":
				f.leader_id = str(fd.get("leader_id"))
			formations[f.formation_id] = f
		organize_jobs.clear()
		for fid2 in formations:
			var ft2: Formation = formations[fid2] as Formation
			if ft2 != null and bool(ft2.is_training):
				organize_jobs.append({
					"formation_id": str(ft2.formation_id),
					"mode": str(ft2.get_meta("organize_mode", "new")),
					"days": int(ft2.get_meta("organize_days", 14.0)),
					"deploy_pid": int(ft2.stationed_province_id),
				})
		print("LeaderManager: Restored %d formation locations" % fdata.size())

	print("LeaderManager: Restored %d leaders + positions" % leaders.size())


## Assigns a leader to Officer Training using their country tag.
func assign_leader_to_officer_training(leader_id: String) -> bool:
	var leader := get_leader(leader_id)
	if leader == null:
		return false
	return set_officer_training_leader(leader.country_tag, leader_id)


## Removes Officer Training assignments (one country, or all if tag empty).
func unassign_officer_training_leader(country_tag: String = "") -> void:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		for country_key in country_positions.keys():
			clear_officer_training_leader(str(country_key))
		for leader_key in leaders.keys():
			var leader: Leader = leaders[leader_key] as Leader
			if leader != null and leader.is_in_officer_training:
				leader.is_in_officer_training = false
				if leader.duty_post == "training":
					leader.duty_post = "active"
	else:
		clear_officer_training_leader(tag)


func get_officer_training_quality(country_tag: String) -> float:
	var tag := country_tag.strip_edges().to_upper()
	return clampf(float(officer_training_quality.get(tag, 0.0)), 0.0, 100.0)


func get_officer_training_months(country_tag: String) -> int:
	var tag := country_tag.strip_edges().to_upper()
	return maxi(int(months_in_training.get(tag, 0)), 0)


## Returns remaining months of reduced growth debuff after a recent mentor change or death.
func get_officer_training_debuff_months(country_tag: String) -> int:
	var tag := country_tag.strip_edges().to_upper()
	return maxi(int(officer_training_debuff_months.get(tag, 0)), 0)


## Returns the Prestige cost to generate one cadet via Officer Training.
## (Stability is deliberately not used for cadet generation.)
func get_officer_training_cadet_prestige_cost() -> float:
	return OFFICER_TRAINING_CADET_PRESTIGE_COST


# ============================================
# OFFICER TRAINING - UI HELPERS
# ============================================

## Returns training quality label text, color, and numeric value for UI.
func get_officer_training_quality_display(country_tag: String) -> Dictionary:
	var quality := get_officer_training_quality(country_tag)
	var label_text := ""
	var color := Color.WHITE

	if quality < 25.0:
		label_text = "Poor"
		color = Color(0.9, 0.3, 0.3)
	elif quality < 50.0:
		label_text = "Average"
		color = Color(0.95, 0.7, 0.2)
	elif quality < 75.0:
		label_text = "Good"
		color = Color(0.4, 0.85, 0.5)
	else:
		label_text = "Excellent"
		color = Color(0.3, 0.7, 0.95)

	return {
		"text": "%s (%.0f%%)" % [label_text, quality],
		"color": color,
		"value": quality,
	}


## Short flavor text describing current training effectiveness.
func get_officer_training_status_text(country_tag: String) -> String:
	var quality := get_officer_training_quality(country_tag)
	var debuff_months := get_officer_training_debuff_months(country_tag)

	if get_officer_training_leader(country_tag) == null:
		return "No mentor assigned — program idle."

	if debuff_months > 0:
		return "Program recovering from recent mentor change (%d months)." % debuff_months

	if quality < 20.0:
		return "Training program is struggling."
	if quality < 45.0:
		return "Producing average officers."
	if quality < 70.0:
		return "Producing solid officers."
	return "Producing high-quality officers."


## Returns how suitable a leader is for Officer Training mentorship (0–100).
func get_officer_training_suitability(leader_id: String) -> int:
	var leader := get_leader(leader_id)
	if leader == null:
		return 0

	var score := 0
	score += leader.planning_skill * 8
	score += leader.logistics_skill * 6
	score += leader.initiative_skill * 4
	score += leader.defense_skill * 3

	if leader.trait_levels.has("mentor") or leader.trait_levels.has("reformer"):
		score += 25
	if leader.trait_levels.has("logistics_wizard") or leader.trait_levels.has("methodical"):
		score += 10

	if leader.trait_levels.has("reckless") or leader.trait_levels.has("arrogant"):
		score -= 20
	if leader.trait_levels.has("political_liability"):
		score -= 15
	if leader.trait_levels.has("butcher"):
		score -= 10

	return clampi(score, 0, 100)


## Advances training quality by one month for all countries (call monthly or 12× per year).
func advance_officer_training_progress(country_tag: String = "") -> void:
	var tags: Array[String] = []
	if country_tag.is_empty():
		var seen: Dictionary = {}
		for country_key in country_positions.keys():
			var tag := str(country_key).strip_edges().to_upper()
			if not tag.is_empty():
				seen[tag] = true
		for country_key in officer_training_quality.keys():
			var tag := str(country_key).strip_edges().to_upper()
			if not tag.is_empty():
				seen[tag] = true
		for tag in seen.keys():
			tags.append(tag)
	else:
		tags.append(country_tag.strip_edges().to_upper())

	for tag in tags:
		_advance_officer_training_progress_for_country(tag)


func _advance_officer_training_progress_for_country(country_tag: String) -> void:
	var previous_quality := get_officer_training_quality(country_tag)
	var training_leader := get_officer_training_leader(country_tag)

	# Decrement any active debuff
	if officer_training_debuff_months.has(country_tag):
		var remaining := int(officer_training_debuff_months[country_tag]) - 1
		if remaining <= 0:
			officer_training_debuff_months.erase(country_tag)
		else:
			officer_training_debuff_months[country_tag] = remaining

	if training_leader == null:
		var decayed := maxf(previous_quality - OFFICER_TRAINING_DECAY_PER_MONTH, 0.0)
		officer_training_quality[country_tag] = decayed
		_check_training_quality_changes(country_tag, previous_quality, decayed)
		return

	var mentor_id := training_leader.leader_id
	if str(officer_training_leader_id.get(country_tag, "")) != mentor_id:
		officer_training_leader_id[country_tag] = mentor_id
		months_in_training[country_tag] = 0

	var months := int(months_in_training.get(country_tag, 0)) + 1
	months_in_training[country_tag] = months

	var skill_bonus := float(training_leader.planning_skill + training_leader.logistics_skill) * 0.5
	var gain := OFFICER_TRAINING_BASE_GAIN + (skill_bonus * OFFICER_TRAINING_SKILL_BONUS_MULTIPLIER)
	if months > OFFICER_TRAINING_LONG_TENURE_MONTHS:
		gain *= OFFICER_TRAINING_LONG_TENURE_MULTIPLIER

	# Apply temporary debuff from recent mentor change (per user direction)
	if officer_training_debuff_months.has(country_tag) and int(officer_training_debuff_months[country_tag]) > 0:
		gain *= OFFICER_TRAINING_MENTOR_CHANGE_DEBUFF_MULTIPLIER

	var current_quality := clampf(previous_quality + gain, 0.0, 100.0)
	officer_training_quality[country_tag] = current_quality
	_check_training_quality_changes(country_tag, previous_quality, current_quality)


func _check_training_quality_changes(
	country_tag: String,
	previous: float,
	current: float,
) -> void:
	if is_equal_approx(previous, current):
		return

	if current >= OFFICER_TRAINING_EXCELLENT_THRESHOLD and previous < OFFICER_TRAINING_EXCELLENT_THRESHOLD:
		var msg := "%s officer training has reached Excellent quality." % country_tag
		print(msg)
		officer_training_quality_notice.emit(country_tag, msg, "success")
	elif current < OFFICER_TRAINING_WARNING_THRESHOLD and previous >= OFFICER_TRAINING_WARNING_THRESHOLD:
		var msg := "%s officer training quality has dropped significantly." % country_tag
		print(msg)
		officer_training_quality_notice.emit(country_tag, msg, "warning")
	elif current < OFFICER_TRAINING_CRISIS_THRESHOLD and previous >= OFFICER_TRAINING_CRISIS_THRESHOLD:
		var msg := "%s officer training program is in crisis." % country_tag
		print(msg)
		officer_training_quality_notice.emit(country_tag, msg, "critical")


## Generates a new officer with training-program quality, mentor influence, and trait risks.
func generate_new_leader_from_training(
	country_tag: String,
	leader_type: String = "",
) -> Leader:
	var tag := country_tag.strip_edges().to_upper()
	var training_leader := get_officer_training_leader(tag)
	var effective_quality := _get_effective_officer_training_quality(tag, training_leader)

	var new_leader := Leader.new()
	new_leader.leader_id = "%s_officer_%d" % [tag.to_lower(), Time.get_unix_time_from_system()]
	new_leader.country_tag = tag
	new_leader.leader_type = _pick_officer_cadet_leader_type(tag, leader_type)
	new_leader.birth_year = get_current_year() - randi_range(27, 35)
	new_leader.start_year = get_current_year()
	new_leader.name = _generate_officer_cadet_name(tag, new_leader.leader_type)

	_roll_officer_cadet_skills(new_leader, effective_quality, new_leader.leader_type)

	if training_leader == null:
		new_leader.experience = randi_range(15, 35)
		return new_leader

	new_leader.experience = randi_range(35, 75) + int(effective_quality * 0.6)
	# Apply mentor flaws before positive traits so exclusive_with does not block inheritance.
	_apply_officer_cadet_flaw_inheritance(new_leader, training_leader, effective_quality)
	_apply_officer_cadet_positive_inheritance(new_leader, training_leader, effective_quality)

	return new_leader


func _get_effective_officer_training_quality(country_tag: String, mentor: Leader) -> float:
	var program_quality := get_officer_training_quality(country_tag)
	if mentor == null:
		return program_quality
	var mentor_bonus := float(get_officer_training_suitability(mentor.leader_id)) * OFFICER_TRAINING_MENTOR_BONUS_MULTIPLIER
	return clampf(program_quality + mentor_bonus, 0.0, 100.0)


func _pick_officer_cadet_leader_type(country_tag: String, requested_type: String = "") -> String:
	var normalized := requested_type.strip_edges().to_lower()
	if not normalized.is_empty() and normalized != "general":
		return normalized

	var leader_type_roll := randf()
	var resolved := "general"
	if _country_has_naval_technology(country_tag) and leader_type_roll < 0.25:
		resolved = "admiral"
	elif _country_has_air_technology(country_tag) and leader_type_roll < 0.40:
		resolved = "air_marshal"
	return resolved


func _country_has_naval_technology(country_tag: String) -> bool:
	# TODO: Replace with national naval technology/focus unlock checks when exposed.
	return (
		country_has_military_doctrine(country_tag, "fleet_in_being")
		or country_has_military_doctrine(country_tag, "carrier_doctrine")
	)


func _country_has_air_technology(country_tag: String) -> bool:
	# TODO: Replace with national air technology/focus unlock checks when exposed.
	return (
		country_has_military_doctrine(country_tag, "air_supremacy")
		or country_has_military_doctrine(country_tag, "strategic_bombing")
	)


func _generate_officer_cadet_name(country_tag: String, leader_type: String) -> String:
	# Officer cadet name pools — quick win expansion (Phase 0).
	# TODO: Proper per-country/culture name lists for generated leaders (see project TODO.md).
	# Current implementation is intentionally small and hardcoded; will be replaced by data-driven
	# cultural name system in a later pass (Phase 3+).
	var pools: Dictionary = {
		"USA": {
			"general": [
				"Ethan Brooks",
				"Sophia Ramirez",
				"Marcus Hale",
				"Jordan Pierce",
				"Nathaniel Voss",
				"Lila Chen",
				"Benjamin Rook",
				"Harper Kline",
			],
			"admiral": [
				"Sarah Whitmore",
				"Derek Holloway",
				"Keisha Monroe",
				"Ryan Caldwell",
				"Gabriel Soto",
				"Naomi Everett",
			],
			"air_marshal": [
				"Marcus Chen",
				"Aisha Porter",
				"Victoria Lane",
				"Tyler Nguyen",
				"Damien Hale",
				"Priya Solis",
			],
		},
		"GER": {
			"general": [
				"Klaus Weber",
				"Hans Richter",
				"Elena Brandt",
				"Felix Kruger",
				"Matthias Lang",
				"Greta Hoffmann",
				"Otto Steiner",
			],
			"admiral": [
				"Ingrid Holtz",
				"Jonas Meier",
				"Clara Seidel",
				"Lukas Brenner",
				"Helga Voss",
			],
			"air_marshal": [
				"Stefan Vogel",
				"Mira Engel",
				"Tobias Kern",
				"Nina Falk",
				"Reinhard Koch",
			],
		},
		"ENG": {
			"general": [
				"Oliver Ashford",
				"Charlotte Reid",
				"Thomas Greer",
				"Amelia Shaw",
				"Henry Talbot",
				"Evelyn Moore",
				"James Whitaker",
			],
			"admiral": [
				"Harriet Lang",
				"William Croft",
				"Eleanor Marsh",
				"James Holt",
				"Arthur Penrose",
			],
			"air_marshal": [
				"Lucas Finch",
				"Grace Palmer",
				"Henry Vale",
				"Isla Monroe",
				"Sebastian Cole",
			],
		},
	}

	var tag := country_tag.to_upper()
	var branch := leader_type if leader_type != "" else "general"
	var names: Array = []
	if pools.has(tag):
		var country_pool: Variant = pools[tag]
		if typeof(country_pool) == TYPE_DICTIONARY:
			names = (country_pool as Dictionary).get(branch, []) as Array
	if names.is_empty() and pools.has("USA"):
		names = (pools["USA"] as Dictionary).get(branch, []) as Array
	if not names.is_empty():
		var picked: String = str(names[randi() % names.size()])
		return picked

	var rank := _officer_cadet_rank_prefix(leader_type)
	return "%s %s %s" % [rank, tag, randi_range(100, 999)]


func _officer_cadet_rank_prefix(leader_type: String) -> String:
	match leader_type:
		"admiral":
			return "Cmdr."
		"air_marshal":
			return "Wg Cdr."
		"field_marshal":
			return "Gen."
		_:
			return "Col."


func _roll_officer_cadet_skills(
	leader: Leader,
	effective_quality: float,
	leader_type: String,
) -> void:
	var base_min := 4
	var base_max := 6
	var quality_bonus := int(effective_quality / 25.0)

	leader.attack_skill = randi_range(base_min, base_max) + quality_bonus
	leader.defense_skill = randi_range(base_min, base_max) + quality_bonus
	leader.logistics_skill = randi_range(base_min, base_max) + quality_bonus
	leader.planning_skill = randi_range(base_min, base_max) + quality_bonus + 1
	leader.initiative_skill = randi_range(base_min, base_max) + quality_bonus
	leader.organization_skill = randi_range(base_min, base_max) + quality_bonus

	match leader_type:
		"admiral":
			leader.defense_skill += 1
			leader.logistics_skill += 1
		"air_marshal":
			leader.initiative_skill += 1
			leader.attack_skill += 1

	leader.attack_skill = clampi(leader.attack_skill, 1, MAX_SKILL)
	leader.defense_skill = clampi(leader.defense_skill, 1, MAX_SKILL)
	leader.organization_skill = clampi(leader.organization_skill, 1, MAX_SKILL)
	leader.logistics_skill = clampi(leader.logistics_skill, 1, MAX_SKILL)
	leader.planning_skill = clampi(leader.planning_skill, 1, MAX_SKILL)
	leader.initiative_skill = clampi(leader.initiative_skill, 1, MAX_SKILL)


func _apply_officer_cadet_flaw_inheritance(
	cadet: Leader,
	mentor: Leader,
	effective_quality: float,
) -> void:
	var negative_traits := _get_negative_traits(mentor)
	if negative_traits.is_empty():
		return

	var negative_chance := OFFICER_TRAINING_NEGATIVE_BASE_CHANCE - (
		effective_quality / OFFICER_TRAINING_NEGATIVE_QUALITY_DIVISOR
	)
	negative_chance = clampf(negative_chance, 0.22, OFFICER_TRAINING_NEGATIVE_TRAIT_INHERIT_CHANCE)
	if randf() >= negative_chance:
		return

	for flaw_id in negative_traits:
		if try_add_trait_to_leader(cadet, flaw_id, 1):
			return


func _apply_officer_cadet_positive_inheritance(
	cadet: Leader,
	mentor: Leader,
	effective_quality: float,
) -> void:
	if mentor.trait_levels.is_empty():
		return

	var positive_chance := OFFICER_TRAINING_POSITIVE_BASE_CHANCE + (
		effective_quality / OFFICER_TRAINING_POSITIVE_QUALITY_DIVISOR
	)
	if randf() >= positive_chance:
		return

	var positive_traits := _get_positive_traits(mentor)
	if positive_traits.is_empty():
		return

	var trait_id := str(positive_traits[randi() % positive_traits.size()])
	try_add_trait_to_leader(cadet, trait_id, 1)


## Legacy wrapper kept for any external callers.
func _apply_officer_cadet_trait_inheritance(
	cadet: Leader,
	mentor: Leader,
	effective_quality: float,
) -> void:
	_apply_officer_cadet_flaw_inheritance(cadet, mentor, effective_quality)
	_apply_officer_cadet_positive_inheritance(cadet, mentor, effective_quality)


func _get_positive_traits(leader: Leader) -> Array[String]:
	var positive: Array[String] = []
	for trait_id in leader.trait_levels.keys():
		var tid := str(trait_id)
		if _is_officer_training_flaw_trait(tid):
			continue
		if not trait_definitions.has(tid):
			continue
		positive.append(tid)
	return positive


func _get_negative_traits(leader: Leader) -> Array[String]:
	var negative: Array[String] = []
	for trait_id in leader.trait_levels.keys():
		var tid := str(trait_id)
		if not _is_officer_training_flaw_trait(tid):
			continue
		if not trait_definitions.has(tid):
			continue
		negative.append(tid)
	return negative


func _is_officer_training_flaw_trait(trait_id: String) -> bool:
	return OFFICER_TRAINING_FLAW_TRAIT_IDS.has(trait_id)


## Generates and registers a mentored officer for the given country.
## Applies the per-cadet Prestige cost (Stability is intentionally not used here).
func generate_and_register_leader_from_training(
	country_tag: String,
	leader_type: String = "general",
) -> Leader:
	var tag := country_tag.strip_edges().to_upper()

	# Apply small Prestige cost for cadet generation (Prestige only, per direction)
	var prestige_cost := OFFICER_TRAINING_CADET_PRESTIGE_COST
	if prestige_cost > 0.0:
		var current_prestige := float(national_prestige.get(tag, 50.0))
		national_prestige[tag] = maxf(current_prestige - prestige_cost, 0.0)
		print("Generated cadet for %s — applied %.1f Prestige cost (remaining: %.1f)" % [
			tag, prestige_cost, float(national_prestige.get(tag, 0.0))
		])

	var new_leader := generate_new_leader_from_training(country_tag, leader_type)
	if new_leader == null or new_leader.leader_id.is_empty():
		return null
	register_leader(new_leader)
	return new_leader


func get_trait_definition(trait_id: String) -> Dictionary:
	var key := str(trait_id)
	if trait_definitions.has(key):
		return trait_definitions[key] as Dictionary
	return {}


func get_trait_max_level(trait_id: String) -> int:
	var def: Dictionary = get_trait_definition(trait_id)
	if def.is_empty():
		return 1
	return maxi(int(def.get("max_level", 1)), 1)


func get_trait_rarity(trait_id: String) -> String:
	var def: Dictionary = get_trait_definition(trait_id)
	return str(def.get("rarity", "common"))


func get_trait_effects_at_level(trait_id: String, level: int) -> Dictionary:
	var def: Dictionary = get_trait_definition(trait_id)
	if def.is_empty():
		return {}
	var by_level: Variant = def.get("effects_by_level", {})
	if typeof(by_level) != TYPE_DICTIONARY:
		return {}
	var clamped_level := clampi(level, 1, get_trait_max_level(trait_id))
	var level_key := str(clamped_level)
	if not (by_level as Dictionary).has(level_key):
		return {}
	var effects: Variant = (by_level as Dictionary)[level_key]
	if typeof(effects) != TYPE_DICTIONARY:
		return {}
	return (effects as Dictionary).duplicate()


func get_leader_trait_effects(leader: Leader) -> Dictionary:
	if leader == null:
		return {}
	var combined: Dictionary = {}
	for trait_id in leader.traits:
		var level := leader.get_trait_level(trait_id)
		var effects := get_trait_effects_at_level(trait_id, level)
		for effect_key in effects.keys():
			var key := str(effect_key)
			combined[key] = float(combined.get(key, 0.0)) + float(effects[effect_key])
	return combined


func count_traits_by_rarity(leader: Leader, rarity: String) -> int:
	var count := 0
	for trait_id in leader.traits:
		if get_trait_rarity(trait_id) == rarity:
			count += 1
	return count


func traits_conflict(leader: Leader, trait_id: String) -> bool:
	var def: Dictionary = get_trait_definition(trait_id)
	if def.is_empty():
		return false
	var exclusive: Variant = def.get("exclusive_with", [])
	if typeof(exclusive) != TYPE_ARRAY:
		return false
	for other_id in exclusive as Array:
		if leader.has_trait(str(other_id)):
			return true
	for existing_id in leader.traits:
		var existing_def := get_trait_definition(existing_id)
		var existing_exclusive: Variant = existing_def.get("exclusive_with", [])
		if typeof(existing_exclusive) == TYPE_ARRAY:
			for blocked_id in existing_exclusive as Array:
				if str(blocked_id) == trait_id:
					return true
	return false


func can_add_trait(leader: Leader, trait_id: String, level: int = 1) -> bool:
	if leader == null or trait_id.is_empty():
		return false
	var def := get_trait_definition(trait_id)
	if def.is_empty():
		push_warning("LeaderManager: unknown trait '%s'" % trait_id)
		return false
	if traits_conflict(leader, trait_id):
		return false
	if leader.has_trait(trait_id):
		var next_level := leader.get_trait_level(trait_id) + level
		if next_level > get_trait_max_level(trait_id):
			return false
		return true
	if leader.traits.size() >= MAX_TRAITS_PER_LEADER:
		return false
	if get_trait_rarity(trait_id) == RARITY_LEGENDARY:
		if count_traits_by_rarity(leader, RARITY_LEGENDARY) >= MAX_LEGENDARY_TRAITS:
			return false
	# Era / tech gating (per user: traits not available ahead of time unless tech unlocked or rare "ahead of his time" leader)
	var era_min := int(def.get("era_min", 0))
	var cur_year := 1936
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("game_year"):
		cur_year = TimeManager.game_year
	if era_min > 0 and cur_year < era_min:
		# Allow only if legendary rarity or special "ahead of time" flag on leader (rare historical or player choice sci-fi leader)
		if get_trait_rarity(trait_id) != RARITY_LEGENDARY and not leader.has_trait("ahead_of_time_visionary"):
			return false
	var req_tech := str(def.get("requires_tech", ""))
	if req_tech != "" and typeof(TechnologyManager) != TYPE_NIL:
		if not TechnologyManager.has_rule_flag(leader.country_tag if leader.country_tag else "player", req_tech):
			if get_trait_rarity(trait_id) != RARITY_LEGENDARY:
				return false  # rare legendary can bypass for "genius ahead of time"
	return true


func try_add_trait_to_leader(leader: Leader, trait_id: String, level: int = 1) -> bool:
	if not can_add_trait(leader, trait_id, level):
		return false
	if leader.has_trait(trait_id):
		var new_level := mini(
			leader.get_trait_level(trait_id) + level,
			get_trait_max_level(trait_id)
		)
		leader.trait_levels[trait_id] = new_level
	else:
		leader.add_trait_unchecked(trait_id, clampi(level, 1, get_trait_max_level(trait_id)))
	invalidate_leader_cache(leader.country_tag)
	return true


func _load_trait_definitions() -> void:
	trait_definitions = _read_trait_json_file(TRAITS_PATH)
	if trait_definitions.is_empty():
		trait_definitions = _read_trait_json_file(LEGACY_TRAITS_PATH)


func _read_trait_json_file(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func get_leader_roster_paths_for_scenario(scenario_name: String) -> Array[String]:
	var key := scenario_name.strip_edges().to_lower()
	if SCENARIO_LEADER_ROSTER_CHAIN.has(key):
		var paths: Array[String] = []
		for roster_path in SCENARIO_LEADER_ROSTER_CHAIN[key] as Array:
			paths.append(str(roster_path))
		return paths
	var candidate := "res://data/leaders/historical_leaders_%s.json" % key
	if ResourceLoader.exists(candidate):
		return [candidate]
	# Playtest scenarios (e.g. phase1_europe_test) use 1936 start dates but have no dedicated roster file.
	if key.contains("test") or key.contains("phase1") or key.contains("playtest"):
		var fallback: Array[String] = []
		for roster_path in SCENARIO_LEADER_ROSTER_CHAIN["1936"] as Array:
			fallback.append(str(roster_path))
		return fallback
	push_warning(
		"LeaderManager: no roster file for scenario '%s' (expected %s)"
		% [scenario_name, candidate]
	)
	return []


func get_leaders_path_for_scenario(scenario_name: String) -> String:
	var paths := get_leader_roster_paths_for_scenario(scenario_name)
	if paths.is_empty():
		return ""
	return paths[paths.size() - 1]


func load_leaders_for_scenario(scenario_name: String, start_year: int = -1) -> int:
	if start_year > 0:
		set_current_year(start_year)
	var paths := get_leader_roster_paths_for_scenario(scenario_name)
	return reload_leaders_from_roster_paths(paths, current_year)


func reload_leaders_from_json(path: String, as_of_year: int = -1) -> int:
	if path.is_empty():
		return reload_leaders_from_roster_paths([], as_of_year)
	return reload_leaders_from_roster_paths([path], as_of_year)


func reload_leaders_from_roster_paths(paths: Array[String], as_of_year: int = -1) -> int:
	leaders.clear()
	leader_pool.clear()
	pending_retirements.clear()
	pending_leader_replacements.clear()
	country_positions.clear()
	officer_training_quality.clear()
	officer_training_leader_id.clear()
	months_in_training.clear()
	officer_training_debuff_months.clear()
	clear_all_leader_caches()
	var year := as_of_year if as_of_year > 0 else current_year
	if paths.is_empty():
		_historical_leaders_source_path = ""
		print("LeaderManager: cleared roster (no leaders file for this scenario)")
		return 0

	var merged_entries: Dictionary = {}
	for path in paths:
		if path.is_empty() or not FileAccess.file_exists(path):
			push_warning("Leader roster file not found: %s" % path)
			continue
		for entry in _load_leader_entries_from_path(path):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var entry_dict := entry as Dictionary
			var leader_id := str(entry_dict.get("leader_id", ""))
			if leader_id.is_empty():
				continue
			merged_entries[leader_id] = entry_dict.duplicate(true)

	if _roster_paths_are_modern_isolated(paths):
		for leader_id in merged_entries.keys():
			if not _leader_entry_valid_for_modern_roster(merged_entries[leader_id]):
				push_warning(
					"LeaderManager: dropped non-modern entry '%s' from 2026 roster"
					% leader_id
				)
				merged_entries.erase(leader_id)

	_historical_leaders_source_path = ", ".join(paths)
	var loaded := 0
	var pooled := 0
	for entry_dict in merged_entries.values():
		var leader_id := str(entry_dict.get("leader_id", ""))
		if not is_leader_entry_active_for_year(entry_dict, year):
			leader_pool[leader_id] = entry_dict
			pooled += 1
			continue
		var leader := _leader_from_dict(entry_dict)
		if leader == null:
			continue
		register_leader(leader)
		loaded += 1

	print(
		"Loaded %d leaders (%d in pool) from [%s] for year %d"
		% [loaded, pooled, _historical_leaders_source_path, year]
	)
	return loaded


func _roster_paths_are_modern_isolated(paths: Array[String]) -> bool:
	return paths.size() == 1 and str(paths[0]) == HISTORICAL_LEADERS_2026_PATH


func _leader_entry_valid_for_modern_roster(entry: Dictionary) -> bool:
	var birth_year := int(entry.get("birth_year", 0))
	if birth_year > 0 and birth_year < MODERN_LEADER_MIN_BIRTH_YEAR:
		return false
	var leader_id := str(entry.get("leader_id", ""))
	if leader_id.ends_with("_2026"):
		return true
	return birth_year >= MODERN_LEADER_MIN_BIRTH_YEAR


func _load_leader_entries_from_path(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_warning(
			"Failed to parse leader roster JSON %s: %s" % [path, json.get_error_message()]
		)
		return []
	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return []
	return _historical_leader_entries_from_data(data as Dictionary)


func load_leaders_from_json(path: String) -> int:
	return load_historical_leaders(path)


# === Historical Leaders Loading ===

func load_historical_leaders(
	path: String = HISTORICAL_LEADERS_1936_PATH,
	as_of_year: int = -1,
) -> int:
	return reload_leaders_from_roster_paths([path], as_of_year)


func _historical_leader_entries_from_data(data: Dictionary) -> Array:
	var entries: Array = []
	var leaders_block: Variant = data.get("leaders", null)
	if typeof(leaders_block) == TYPE_ARRAY:
		for entry in leaders_block as Array:
			if typeof(entry) == TYPE_DICTIONARY:
				entries.append(entry)
		return entries

	# Flat map format: { "ger_rommel": { ... }, ... }
	for leader_key in data.keys():
		var leader_data: Variant = data[leader_key]
		if typeof(leader_data) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = (leader_data as Dictionary).duplicate()
		if not entry.has("leader_id"):
			entry["leader_id"] = str(leader_key)
		entries.append(entry)
	return entries


func _leader_from_dict(data: Dictionary) -> Leader:
	var leader := LeaderGenerator.create_leader_from_data(data)
	if leader == null or leader.leader_id.is_empty():
		return null
	return leader
