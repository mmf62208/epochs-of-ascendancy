extends Node

## National supply: depots, multimodal routes, intel-driven interdiction, attrition cargo.

signal network_rebuilt(hub_count: int)
signal route_updated(route_id: String, plan: SupplyRoutePlan)
signal overlay_toggled(visible: bool)
signal depot_stock_changed(province_id: int, stockpile: float)

var rules: SupplyRules = null
var hubs: Dictionary[int, ProvinceSupplyHub] = {}
var depot_states: Dictionary[int, ProvinceDepotState] = {}
var provinces: Dictionary[int, Province] = {}
var adjacency: AdjacencySystem = null
var player_tag: String = "USA"

var player_depot_province_ids: Array[int] = []
var force_registry: CombatPresenceRegistry = CombatPresenceRegistry.new()
## formation_id -> {province_id, country_tag} — source of truth for player division map presence.
var division_deployments: Dictionary = {}
var attrition_ledger: AttritionReplenishmentLedger = AttritionReplenishmentLedger.new()
var division_templates: DivisionTemplateLoader = DivisionTemplateLoader.new()

var _countries: Dictionary[String, Variant] = {}
var _city_layer: Dictionary = {}
var _routes: Dictionary[String, SupplyRoutePlan] = {}
var _default_routes: Dictionary[String, SupplyRoutePlan] = {}
var overlay_visible: bool = false
var routing_mode_override: String = ""
var active_cargo: SupplyCargoProfile = null

# ProvinceEffects + MapManager: All province + national modifier queries should go through
# MapManager.get_province_effects(...) when possible (centralized after Map System start).

func _get_effects_safe(pid: int, tag: String) -> ProvinceEffects:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_effects"):
		var fx: ProvinceEffects = MapManager.get_province_effects(pid, tag)
		if fx != null:
			return fx
	var p: Province = null
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
		p = MapManager.get_province(pid) as Province
	if p == null:
		var loader := get_node_or_null("/root/ScenarioLoader")
		if loader != null and loader.has_method("get_province"):
			p = loader.call("get_province", pid)
	if p == null:
		return null
	return ProvinceEffects.for_country_province(p, tag) if typeof(ProvinceEffects) != TYPE_NIL else null

var _pending_waypoints: Array[int] = []
var _reroute_source_id: int = -1
var _reroute_target_id: int = -1
var _selected_province_id: int = -1


func _ready() -> void:
	rules = SupplyRules.load_from_path()
	division_templates.load_all()
	active_cargo = SupplyCargoProfile.general_supplies(500.0)

	# Connect to central daily clock
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced):
			TimeManager.game_day_advanced.connect(_on_game_day_advanced)


func build_network(
	p_provinces: Dictionary,
	p_countries: Dictionary,
	city_layer: Dictionary,
	p_adjacency: AdjacencySystem,
	tag: String = "",
) -> void:
	provinces = MapScenarioData.coerce_provinces(p_provinces)
	_countries = MapScenarioData.coerce_countries(p_countries)
	_city_layer = city_layer
	adjacency = p_adjacency
	if not tag.is_empty():
		player_tag = tag
	hubs = SupplyNetworkBuilder.build(
		provinces, p_countries, city_layer, player_depot_province_ids, rules,
	)
	_init_depot_states()
	refresh_intel_from_forces()
	_rebuild_default_routes()
	network_rebuilt.emit(hubs.size())


func _init_depot_states() -> void:
	depot_states.clear()
	for pid_var in hubs:
		var hub: ProvinceSupplyHub = hubs[pid_var]
		var throughput_rules := rules.get_block("throughput")
		var state := ProvinceDepotState.new(hub.province_id, hub.storage_capacity)

		# Base throughput fraction
		var base_fraction := float(throughput_rules.get("capacity_fraction_per_day", 0.15))

		# Infrastructure + Development now have strong combined effect on throughput
		# High development provinces act as logistics hubs
		var infra_factor := 0.8 + (float(hub.infrastructure) * 0.04)
		var dev_factor := 0.7 + (float(hub.development_level) * 0.06)   # Stronger dev scaling

		state.throughput_capacity = hub.storage_capacity * base_fraction * infra_factor * dev_factor
		state.stockpile = hub.storage_capacity * float(throughput_rules.get("initial_fill_ratio", 0.65))
		# Pass 18: seed munitions share of general stock for land ammo UI.
		state.munitions_stockpile = state.stockpile * 0.35
		depot_states[hub.province_id] = state


func get_depot_state(province_id: int) -> ProvinceDepotState:
	return depot_states.get(province_id)


## Pass 18: munitions readiness 0–1 at province depot (for OOB ammo bar).
func get_depot_munitions_ratio(province_id: int) -> float:
	var depot: ProvinceDepotState = depot_states.get(province_id)
	if depot == null:
		return -1.0
	if depot.has_method("munitions_ratio"):
		return float(depot.munitions_ratio())
	return -1.0


func get_depot_menu_lines(limit: int = 5) -> Array[String]:
	var lines: Array[String] = []
	var ranked: Array = []
	for pid_var in depot_states.keys():
		var depot: ProvinceDepotState = depot_states[pid_var]
		if depot == null:
			continue
		ranked.append({"id": int(pid_var), "fill": depot.fill_ratio(), "stock": depot.stockpile})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("fill", 0.0)) > float(b.get("fill", 0.0))
	)
	for entry in ranked.slice(0, maxi(limit, 0)):
		var pid := int(entry.get("id", -1))
		var pname := str(pid)
		if provinces.has(pid):
			pname = (provinces[pid] as Province).name
		lines.append(
			"%s: %d%% (%.0f t stored)"
			% [pname, int(round(float(entry.get("fill", 0.0)) * 100.0)), float(entry.get("stock", 0.0))]
		)
	return lines


func get_capital_hub_id() -> int:
	for hub: ProvinceSupplyHub in hubs.values():
		if hub.owner_tag == player_tag and hub.has_kind(ProvinceSupplyHub.DepotKind.CAPITAL):
			return hub.province_id
	return -1


func set_player_depot(province_id: int, enabled: bool) -> void:
	if enabled and province_id not in player_depot_province_ids:
		player_depot_province_ids.append(province_id)
	elif not enabled and province_id in player_depot_province_ids:
		player_depot_province_ids.erase(province_id)
	if not provinces.is_empty():
		build_network(provinces, _countries, _city_layer, adjacency, player_tag)


func set_selected_province(province_id: int) -> void:
	_selected_province_id = province_id


func get_selected_province_id() -> int:
	return _selected_province_id


func set_routing_mode(mode: String) -> void:
	routing_mode_override = mode


func set_active_cargo_from_template(template: UnitTemplate) -> void:
	active_cargo = SupplyCargoProfile.from_template(template, rules)


func set_active_cargo_tons(tons: float) -> void:
	active_cargo = SupplyCargoProfile.general_supplies(tons)


func register_unit_presence(
	province_id: int,
	owner_tag: String,
	template: UnitTemplate,
	count: float = 1.0,
) -> void:
	force_registry.add_unit(province_id, owner_tag, template, count)


func register_division_presence(
	province_id: int,
	owner_tag: String,
	division: DivisionTemplate,
	brigade_equiv: float = 1.0,
) -> void:
	## Call this (or the lower-level presence methods) when a division/formation is present
	## or stationed in a province (supply movement, combat, assignment, etc.). This feeds
	## both general presence (for interdiction) and engineer counts (for MapManager repair bonus).
	force_registry.register_division_presence(province_id, owner_tag, division, brigade_equiv)


func get_engineer_brigades_in_province(province_id: int, country_tag: String) -> float:
	## Used by MapManager for infrastructure repair engineer bonus.
	## Returns friendly engineer/combat_engineer brigade equivalents present in the province.
	## The registry is populated via register_division_presence() (called when divisions are
	## stationed or operate in a province) which uses DivisionTemplate.count_engineer_brigade_equivalent().
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		return 0.0
	return force_registry.get_report(province_id).total_engineers(tag)


func register_force_report(province_id: int, report: ProvinceForceReport) -> void:
	force_registry.set_report(province_id, report)


func clear_force_registry() -> void:
	force_registry.clear()


func get_combat_presence_registry() -> CombatPresenceRegistry:
	## Exposed for ProvinceInsight battle previews, CombatResolver air calcs, etc.
	return force_registry

func get_air_power_ratio(province_id: int, friendly_tag: String = "") -> float:
	## Continuous air power ratio (friendly/enemy) for the province using registry assets.
	## For full mission/doctrine/tech weighted power, use AirMissionProfile + formations in ProvinceInsight/Resolver.
	if friendly_tag.is_empty():
		friendly_tag = player_tag
	var report := force_registry.get_report(province_id)
	return report.get_air_power_ratio(friendly_tag) if report.has_method("get_air_power_ratio") else 1.0

func get_air_recon_bonus(province_id: int, friendly_tag: String = "") -> float:
	if friendly_tag.is_empty():
		friendly_tag = player_tag
	var report := force_registry.get_report(province_id)
	return report.get_air_recon_bonus(friendly_tag) if report.has_method("get_air_recon_bonus") else 0.0


func refresh_intel_from_forces() -> void:
	SupplyIntelBridge.refresh_manager(self, player_tag, force_registry, provinces, hubs, rules)
	_apply_agent_intelligence_modifiers()


func _process_air_missions(days: float = 1.0) -> void:
	## DYNAMIC SORTIE / ENDURANCE / RECON / FUEL MODEL
	## Uses Formation.get_effective_air_sorties() + AirMissionProfile.compute + ADS.
	## - Computes realistic sorties based on org/supply/range/infra/leader/doctrine/weather/tech/era/AA.
	## - Burns fuel (affects future readiness), applies AA attrition to air strength (not elim).
	## - Updates registry with *sorties* dynamic air presence (so ratios/CAS reflect actual ops tempo, not static).
	## - RECON missions seed recon_points -> intel bonus (decays).
	## - Costly even in dominance (fuel, fatigue, AA losses). Early low tempo; late high with support.
	## Integrates with existing contested cost, weather, profile power.
	## Called daily + from debug menu. Evidence prints on EOA_HEADLESS_EVIDENCE=1.
	if days <= 0.0 or typeof(LeaderManager) == TYPE_NIL:
		return
	var wm_eff := 1.0
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_air_mission_effectiveness"):
		# Will query per pid below
		pass
	var year_now := 1942
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
		year_now = int(TimeManager.get_current_year())
	elif typeof(GameData) != TYPE_NIL:
		year_now = GameData.get_current_year() if GameData.has_method("get_current_year") else 1942

	# Process player + proxy other countries (for sims)
	var countries_to_proc := [player_tag]
	# In full sim would enumerate all active; for now player + seeded enemies
	for f in LeaderManager.get_formations_for_country(player_tag):
		if f == null or f.get_category() != "air": continue
		_process_single_air_formation(f, days, year_now, wm_eff)
	# Also any air in registry from other (demo/enemy air wings if registered via LeaderManager elsewhere)
	# Rate-limit log spam — printing every day hung the Output panel / debugger during F5 play.
	if OS.get_environment("EOA_HEADLESS_EVIDENCE").strip_edges() == "1" or Engine.get_process_frames() % 120 == 0:
		print("[AIR] _process_air_missions tick (dynamic sorties, fuel, recon, attrition now active)")

func _process_single_air_formation(f: Formation, days: float, year: int, base_wm: float) -> void:
	if f == null or f.get_category() != "air": return
	var mid := str(f.current_air_mission) if "current_air_mission" in f else ""
	if mid == "" or mid == "NONE": return
	var pid := -1
	if "stationed_province_id" in f:
		pid = int(f.stationed_province_id)
	if pid < 0 and division_deployments.has(f.formation_id):
		var dep: Dictionary = division_deployments[f.formation_id] as Dictionary
		if dep.has("province_id"):
			pid = int(dep["province_id"])
	if pid < 0: return

	# Weather per province — prefer pure air sortie readiness gate when available.
	var w_eff := base_wm
	if typeof(WeatherManager) != TYPE_NIL:
		if WeatherManager.has_method("get_air_sortie_weather_eff"):
			w_eff = float(WeatherManager.get_air_sortie_weather_eff(pid))
		elif WeatherManager.has_method("get_air_mission_effectiveness"):
			w_eff = float(WeatherManager.call("get_air_mission_effectiveness", pid))
	# Enemy AA from registry report (defenders in pid)
	var en_aa := 0.1
	var reg_report = force_registry.get_report(pid) if force_registry else null
	if reg_report and reg_report.has_method("total_air"):
		# Rough: enemy air implies AA threat proxy; real AA from land/aa templates later
		en_aa = clampf(0.05 + (reg_report.total_air("player" if f.country_tag != "player" else "GER") * 0.08), 0.0, 0.8)

	# Jamming / stealth proxy from tech (late game)
	var jam := 1.0
	var stl := 1.0
	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("has_rule_flag"):
		var tag := f.country_tag if "country_tag" in f else player_tag
		if TechnologyManager.has_rule_flag(tag if f.country_tag == player_tag else "enemy", "ecm_jamming"):
			jam = 0.7  # enemy jamming hurts our
		if TechnologyManager.has_rule_flag(tag, "stealth_aircraft") or year >= 1985:
			stl = 1.35

	# Get dynamic sorties using new model (distance proxy 400km avg; infra from province if avail)
	var base_inf := 5
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
		var p: Province = MapManager.get_province(pid)
		if p: base_inf = int(p.infrastructure)
	var sdata: Dictionary = f.get_effective_air_sorties(450.0, base_inf, en_aa, w_eff, jam, stl, year)
	var sorties := float(sdata.get("sorties", 1.0))
	var fuel_b := float(sdata.get("fuel_burn", sorties * 1.2))
	var rec_pts := float(sdata.get("recon_points", 0.0))
	var rdy_imp := float(sdata.get("readiness_impact", -0.1))
	var ab_ch := float(sdata.get("abort_chance", 0.1))

	# Apply to formation readiness/org/strength (fatigue + fuel state)
	if "organization" in f:
		f.organization = clampf(float(f.organization) + rdy_imp * 0.7, 0.3, 1.8)
	if "readiness" in f:
		var cur_r := float(f.readiness)
		cur_r = clampf(cur_r + rdy_imp, 0.25, 1.6)
		f.readiness = cur_r
	# Strength attrition (AA + mech)
	var attr := AirMissionProfile.new().apply_air_mission_attrition( float(f.strength if "strength" in f else 1.0), en_aa, sorties, w_eff, stl )
	if "strength" in f:
		f.strength = float(attr.get("new_strength", f.strength))
	# Log for evidence
	if OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1" or (sorties > 1.5 and randf() > 0.6):
		print("[AIR SORTIE] %s @%d mission=%s sorties=%.2f loiter=%.1f fuel=%.1f abort=%.0f%% rdy_imp=%.2f AA=%.2f recon=%.1f | %s" % [
			f.formation_id, pid, mid, sorties, float(sdata.get("loiter",1.0)), fuel_b, ab_ch*100, rdy_imp, en_aa, rec_pts, str(sdata.get("notes",""))
		])

	# Dynamic presence update: presence reflects actual flown (sorties * strength factor). Makes CAS/interdict vary with ops tempo.
	var pres_str := float(f.strength if "strength" in f else 1.0) * sorties * 0.7
	force_registry.add_air_presence(pid, f.country_tag if "country_tag" in f else player_tag, pres_str)

	# Recon bonus if RECON mission (persistent short term for intel feed)
	if mid == Formation.AIR_MISSION_RECON and rec_pts > 0.1:
		force_registry.add_air_recon_presence(pid, f.country_tag if "country_tag" in f else player_tag, rec_pts * 0.8)
		# Also to adjacent for area effect (simplified; real would use region)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacent_provinces"):
			for adj in MapManager.get_adjacent_provinces(pid).slice(0, 3):
				force_registry.add_air_recon_presence(int(adj), f.country_tag if "country_tag" in f else player_tag, rec_pts * 0.3)

	# Fuel burn impact (reduce local depot or global fuel if avail; simple readiness hit if can't)
	# For now, extra readiness/org hit proportional fuel if low infra
	if fuel_b > 3.0 and base_inf < 4:
		if "organization" in f: f.organization = maxf(0.3, float(f.organization) * 0.92)
		if OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1":
			print("[AIR FUEL] High burn %.1f with low infra %d at %d -> extra org drain" % [fuel_b, base_inf, pid])

	# Interdict boost for INTERDICTION mission (existing + scaled by sorties)
	if mid == "INTERDICTION" and sorties > 0.5:
		# Slight boost to enemy interdict chance via registry (SupplyInterdictionEstimator uses presence)
		# Already presence higher -> interdict estimators pick up air
		if OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1":
			print("[AIR INTERDICT] %s flew %.1f sorties -> supply pressure on enemies at %d" % [f.formation_id, sorties, pid])

	# Note: full fuel drawn from Supply depots/cargo happens in calculate/consume paths using extra from sdata if wired.
	# CAS/ other effects via updated registry ratios + resolver using sorties in future calls.


func set_enemy_presence(province_id: int, presence: Dictionary) -> void:
	var store: Dictionary = get_meta("enemy_presence") if has_meta("enemy_presence") else {}
	store[province_id] = presence
	set_meta("enemy_presence", store)


func get_enemy_presence() -> Dictionary:
	return get_meta("enemy_presence") if has_meta("enemy_presence") else {}


func _apply_agent_intelligence_modifiers() -> void:
	if typeof(AgentManager) == TYPE_NIL:
		return

	var presence: Dictionary = get_enemy_presence()
	if presence.is_empty():
		return

	var military_mod: float = AgentManager.get_intelligence_modifier(player_tag, "military")
	var economic_mod: float = AgentManager.get_intelligence_modifier(player_tag, "economic")
	var intel_mod := minf(military_mod, economic_mod)

	if intel_mod >= 0.99:
		return  # No meaningful bonus

	for pid in presence.keys():
		var p: Dictionary = presence[pid] as Dictionary
		if typeof(p) != TYPE_DICTIONARY:
			continue

		# Agent intel reduces the perceived threat of enemy forces
		if p.has("enemy_brigade_equiv"):
			p["enemy_brigade_equiv"] = float(p["enemy_brigade_equiv"]) * intel_mod
		if p.has("enemy_air_superiority"):
			p["enemy_air_superiority"] = float(p["enemy_air_superiority"]) * intel_mod

		# Economic intel can slightly reduce perceived naval/port threats
		if economic_mod < 1.0 and p.has("enemy_naval_at_port"):
			if bool(p["enemy_naval_at_port"]):
				# With good economic intel we are less surprised by naval interdiction
				p["naval_threat_reduced_by_intel"] = true


func record_attrition(
	division_id: String,
	manpower_lost: int,
	equipment_losses: Dictionary = {},
	leader_id: String = "",
) -> void:
	var resolved_leader := leader_id
	if resolved_leader.is_empty() and typeof(LeaderManager) != TYPE_NIL:
		resolved_leader = LeaderManager.resolve_leader_id_for_formation(division_id)
	attrition_ledger.record_manpower_loss(division_id, manpower_lost, resolved_leader)
	for tpl_id in equipment_losses:
		attrition_ledger.record_equipment_loss(str(tpl_id), float(equipment_losses[tpl_id]))


func get_formation(formation_id: String) -> Formation:
	if formation_id.is_empty() or typeof(LeaderManager) == TYPE_NIL:
		return null
	return LeaderManager.get_formation(formation_id)


func _get_base_supply_consumption(formation_id: String) -> float:
	var template: DivisionTemplate = division_templates.get_division(formation_id)
	if template == null:
		return 1.0
	var design_data: DesignDataLoader = null
	var gd := get_node_or_null("/root/GameData")
	if gd != null and "design_data" in gd:
		design_data = gd.design_data
	var stats := template.get_final_combat_stats({}, design_data)
	return float(stats.get("supply_consumption", 1.0))


## Daily supply use for a formation, including training-path supply_consumption modifiers
## and national spirit / temporary modifier effects.
## Enhanced: air contested airspace adds extra drain (disadv much higher; full sup also costly to maintain for large regions).
func calculate_daily_supply_consumption(formation_id: String) -> float:
	var base_consumption := _get_base_supply_consumption(formation_id)

	# Apply national spirit + temporary modifier effects
	base_consumption = _apply_national_supply_modifiers(formation_id, base_consumption)

	# Air contested / air ops cost multiplier (uses registry for ratio + profile for mission weighting)
	var formation := get_formation(formation_id)
	var prov_id := -1
	if formation != null:
		if "stationed_province_id" in formation:
			prov_id = int(formation.stationed_province_id)
		if prov_id < 0 and division_deployments.has(formation_id):
			var dep2: Dictionary = division_deployments[formation_id] as Dictionary
			if dep2.has("province_id"):
				prov_id = int(dep2["province_id"])
	if prov_id >= 0:
		var ratio := get_air_power_ratio(prov_id, formation.country_tag if formation and "country_tag" in formation else player_tag)
		var is_adv := ratio >= 1.0
		var prof := AirMissionProfile.new(formation_id, formation.get_air_design_id() if formation and formation.has_method("get_air_design_id") else "", formation.air_range_config if formation and "air_range_config" in formation else "COMBAT_LOAD")
		var air_mult := prof.get_contested_airspace_cost_mult(ratio, is_adv)
		base_consumption *= air_mult
		if air_mult > 1.4 and OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1":
			print("[AIR COST] contested airspace x%.2f applied for %s (ratio %.2f) at %d" % [air_mult, formation_id, ratio, prov_id])

	if typeof(LeaderManager) == TYPE_NIL:
		return maxf(base_consumption, 0.1)

	var leader_id := ""
	if formation != null and formation.has_leader():
		leader_id = formation.leader_id
	elif not formation_id.is_empty():
		leader_id = LeaderManager.resolve_leader_id_for_formation(formation_id)

	if not leader_id.is_empty():
		return LeaderManager.apply_supply_consumption_for_leader(base_consumption, leader_id)
	return maxf(base_consumption, 0.1)


func _apply_national_supply_modifiers(formation_id: String, base_consumption: float) -> float:
	# Try to determine the owning country of the formation
	var owner_tag := ""
	var formation := get_formation(formation_id)
	if formation != null:
		if "country_tag" in formation and not formation.country_tag.is_empty():
			owner_tag = formation.country_tag

	if owner_tag.is_empty():
		return base_consumption

	# Get combined national supply modifiers (spirits + temporary effects)
	var supply_mod := 0.0

	if typeof(NationalSpiritManager) != TYPE_NIL:
		supply_mod += NationalSpiritManager.get_total_supply_consumption_modifier(owner_tag)

	# NMM supply + space tech wiring: deflector shields power hungry cost; tele rapid gives small supply efficiency
	if typeof(NationalModifierManager) != TYPE_NIL:
		var smods := NationalModifierManager.get_supply_modifiers(owner_tag)
		supply_mod += float(smods.get("supply_consumption", 0.0))
		# Shields 1995: power hungry (positive = worse consumption)
		if typeof(TechnologyManager) != TYPE_NIL and (TechnologyManager.has_rule_flag(owner_tag, "energy_shields") or TechnologyManager.is_tech_completed(owner_tag, "deflector_shields_1995")):
			supply_mod += 0.12  # +12% supply for shields energy draw (tradeoff)
			if OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1":
				print("[SPACE WIRING] deflector_shields power cost +supply for %s" % owner_tag)
		# Tele rapid deploy: small supply bonus (efficiency from instant)
		var rapid := float(smods.get("rapid_deployment", 0.0))  # note: may be in combat, fallback
		if rapid == 0.0 and typeof(NationalModifierManager) != TYPE_NIL:
			var cmods := NationalModifierManager.get_combat_modifiers(owner_tag)
			rapid = float(cmods.get("rapid_deployment", 0.0))
		if rapid > 0.0 or (typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_rule_flag(owner_tag, "teleportation")):
			supply_mod -= minf(0.15, rapid * 0.4)  # reduce consumption
			if OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1":
				print("[SPACE WIRING] teleporters rapid deploy supply bonus for %s rapid=%.2f" % [owner_tag, rapid])

	if supply_mod == 0.0:
		return base_consumption

	# Apply as multiplicative modifier (negative value = lower consumption = beneficial)
	var multiplier := 1.0 + supply_mod
	return maxf(base_consumption * multiplier, 0.05)


func get_attrition_cargo_summary(_leader_id: String = "") -> Dictionary:
	var design_data: DesignDataLoader = null
	var gd := get_node_or_null("/root/GameData")
	if gd != null and "design_data" in gd:
		design_data = gd.design_data
	return attrition_ledger.compute_replenishment_cargo(
		division_templates,
		design_data,
		rules,
	)


func _on_game_day_advanced(_year: int, _month: int, _day: int) -> void:
	# Daily supply simulation driven by central TimeManager.
	# Interactive F5: always light path (no air/naval recon spam — that made 1x + wheel unusable).
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_interactive_light_sim") and bool(TimeManager.is_interactive_light_sim()):
		_advance_supply_day_light(1.0)
		return
	advance_supply_day(1.0)


func _advance_supply_day_light(days: float = 1.0) -> void:
	## Depot flow without air/naval recon spam — keeps 1x playable past January/February.
	if days <= 0.0:
		return
	_generate_local_supply_from_development_light(days)
	if force_registry and force_registry.has_method("decay_all_recon"):
		force_registry.decay_all_recon(days)


func _generate_local_supply_from_development_light(days: float) -> void:
	## Budgeted slice of depots per day so world_full (2k+ depots) cannot freeze the clock.
	if days <= 0.0 or depot_states.is_empty():
		return
	var keys: Array = depot_states.keys()
	var n := keys.size()
	if n == 0:
		return
	var budget := 96 if n > 800 else n
	var start := 0
	if typeof(TimeManager) != TYPE_NIL and "total_days_elapsed" in TimeManager:
		start = int(TimeManager.total_days_elapsed) % n
	var checked := 0
	var offset := 0
	while checked < budget and offset < n:
		var pid_var = keys[(start + offset) % n]
		offset += 1
		var state: ProvinceDepotState = depot_states.get(pid_var)
		if state == null:
			continue
		checked += 1
		if state.sabotage_level > 0.0:
			state.sabotage_level = maxf(0.0, state.sabotage_level - 0.13)
		var province: Province = null
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			province = MapManager.get_province(int(pid_var)) as Province
		if province == null:
			continue
		# Skip heavy ProvinceEffects on the light path — use province getter only.
		var local_gen := province.get_local_supply_generation_modifier()
		if local_gen <= 0.0:
			continue
		var daily_gen := 40.0 * local_gen * days
		if typeof(AgentManager) != TYPE_NIL and AgentManager.has_method("get_supply_disruption_in_province"):
			var disruption: float = AgentManager.get_supply_disruption_in_province(int(pid_var))
			if disruption > 0.0:
				daily_gen *= (1.0 - clampf(disruption * 0.25, 0.0, 0.6))
		state.apply_inflow(daily_gen)

func advance_supply_day(days: float = 1.0) -> void:
	if days <= 0.0:
		return

	# === Province Infrastructure & Development: Local Supply Generation ===
	_generate_local_supply_from_development(days)

	# Naval recon from fleets in sea zones (1 chance per day per seazone presence)
	_process_naval_recon(days)

	# Naval fuel consumption + endurance for fleets at sea (long deployments burn fuel/supply; low = vuln/return forced; resupply at ports)
	_process_naval_fuel_endurance_and_repair(days)

	_process_air_missions(days)
	if force_registry and force_registry.has_method("decay_all_recon"):
		force_registry.decay_all_recon(days)  # air recon intel decays (persistent but not permanent)
	var attrition := get_attrition_cargo_summary()
	var attrition_tons := float(attrition.get("total_tons", 0.0)) * days
	for key in _routes:
		var plan: SupplyRoutePlan = _routes[key]
		if plan == null or plan.path_length() < 2:
			continue
		var src: ProvinceDepotState = depot_states.get(plan.source_province_id)
		var dst: ProvinceDepotState = depot_states.get(plan.target_province_id)
		if src == null or dst == null:
			continue
		var ship_tons := plan.cargo_tons_per_day * days
		if ship_tons <= 0.0:
			ship_tons = src.throughput_capacity * days * 0.25
		ship_tons += attrition_tons / maxf(float(_routes.size()), 1.0)
		var pulled := src.pull_outflow(ship_tons)
		# Apply interdiction + reinforcement speed (Phase 1): high dev/infra + national = more arrives
		var delivery := 1.0 - plan.interdiction_chance
		var reinf_bonus := clampf((plan.reinforcement_modifier - 1.0) * 0.6, 0.0, 0.35)
		delivery = clampf(delivery * (1.0 + reinf_bonus), 0.2, 1.15)
		# Sea-zone control + weather as ONE compose mult (no triple-count of sea/depot/wx).
		var sea_mult := get_sea_zone_supply_multiplier_for_path(plan.province_path, player_tag)
		var chain_ground := "dry"
		var chain_precip := 0.0
		var chain_vis := 1.0
		var chain_risk := 0.0
		if typeof(WeatherManager) != TYPE_NIL:
			var wsum := 0.0
			var wn := 0
			var path_wx: Array = []
			for pidv in plan.province_path:
				var pid := int(pidv)
				if WeatherManager.has_method("get_supply_weather_multiplier"):
					var sm := float(WeatherManager.get_supply_weather_multiplier(pid))
					wsum += sm
					wn += 1
					var entry := {"province_id": pid, "ground_state": "dry", "precip_intensity": 0.0}
					entry["precip_intensity"] = clampf((1.0 - sm) * 2.0, 0.0, 1.0)
					if sm < 0.75:
						entry["ground_state"] = "mud"
					path_wx.append(entry)
				if WeatherManager.has_method("get_storm_interdiction_chance"):
					var storm_c := float(WeatherManager.get_storm_interdiction_chance(pid, plan.interdiction_chance))
					# Storm interdiction residual only (not a full weather mult).
					delivery *= clampf(1.0 - maxf(0.0, storm_c - plan.interdiction_chance), 0.5, 1.0)
			if wn > 0:
				var avg_wx := wsum / float(wn)
				chain_precip = clampf((1.0 - avg_wx) * 2.0, 0.0, 1.0)
				if avg_wx < 0.75:
					chain_ground = "mud"
			if WeatherManager.has_method("get_naval_spot_weather_multiplier"):
				chain_vis = float(WeatherManager.get_naval_spot_weather_multiplier(plan.target_province_id))
			var ranked_wx: Dictionary = MapPolishFormatters.rank_supply_route_weather_risk(path_wx)
			if not bool(ranked_wx.get("empty", true)):
				var worst: Dictionary = ranked_wx.get("worst", {})
				chain_risk = float(worst.get("risk", 0.0)) if worst is Dictionary else 0.0
		# Sole mult for sea + depot + weather + route risk (compose once).
		var chain: Dictionary = MapPolishFormatters.supply_chain_health_compose(
			100.0, sea_mult, chain_ground, chain_precip, chain_vis, chain_risk
		)
		delivery = clampf(delivery * float(chain.get("health", 1.0)), 0.12, 1.4)
		# Basing repair weather loop residual for naval-capable destinations (rate metadata only).
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("basing_repair_weather_for_province"):
			var br: Dictionary = MapManager.basing_repair_weather_for_province(plan.target_province_id)
			if not bool(br.get("empty", true)):
				# Soft org-repair-aware delivery floor when major base services routes in fair weather.
				var refuel_r := float(br.get("refuel_rate", 0.0))
				if refuel_r > 0.2:
					delivery = clampf(delivery * (1.0 + minf(0.05, refuel_r * 0.08)), 0.12, 1.4)
		var inflow := pulled * delivery
		# Pass 18: munitions-tagged cargo fills munitions_stockpile for OOB ammo bars.
		var cargo := active_cargo if active_cargo != null else SupplyCargoProfile.general_supplies(500.0)
		var mun_frac := 0.35
		if cargo != null and "munitions_fraction" in cargo:
			mun_frac = clampf(float(cargo.munitions_fraction), 0.0, 1.0)
		elif cargo != null and "cargo_kind" in cargo and str(cargo.cargo_kind) == "munitions":
			mun_frac = 0.9
		var mun_in := inflow * mun_frac
		var overflow := 0.0
		if mun_in > 0.01 and dst.has_method("apply_munitions_inflow"):
			# apply_munitions_inflow also adds to general stockpile.
			overflow = dst.apply_munitions_inflow(mun_in)
			var rest := maxf(0.0, inflow - mun_in)
			if rest > 0.0:
				overflow += dst.apply_inflow(rest)
		else:
			overflow = dst.apply_inflow(inflow)
			if dst != null and "munitions_stockpile" in dst:
				dst.munitions_stockpile = minf(dst.storage_capacity, dst.munitions_stockpile + inflow * mun_frac)
		if overflow > 0.0 and src != null:
			src.apply_inflow(overflow * 0.5)
		depot_stock_changed.emit(dst.province_id, dst.stockpile)


func begin_player_reroute(source_province_id: int, target_province_id: int) -> void:
	_reroute_source_id = source_province_id
	_reroute_target_id = target_province_id
	_pending_waypoints.clear()


func set_reroute_target(province_id: int) -> void:
	_reroute_target_id = province_id


func add_reroute_waypoint(province_id: int) -> void:
	if province_id not in _pending_waypoints:
		_pending_waypoints.append(province_id)
	set_reroute_target(province_id)


func clear_reroute_waypoints() -> void:
	_pending_waypoints.clear()


func preview_player_route() -> SupplyRoutePlan:
	return _plan_route(_reroute_source_id, _reroute_target_id, _pending_waypoints, true)


func commit_player_route(route_key: String = "") -> SupplyRoutePlan:
	var plan := preview_player_route()
	if plan.path_length() < 2:
		return plan
	var key := route_key if not route_key.is_empty() else "%d_%d" % [_reroute_source_id, _reroute_target_id]
	var baseline: SupplyRoutePlan = _default_routes.get(key)
	if baseline != null:
		plan.baseline_days = baseline.total_days
		plan.extra_days_from_reroute = plan.total_days - baseline.total_days
	plan.route_id = key
	plan.is_player_override = true
	_routes[key] = plan
	route_updated.emit(key, plan)
	return plan


func get_route(route_key: String) -> SupplyRoutePlan:
	return _routes.get(route_key)


func get_all_routes() -> Array:
	return _routes.values()

## Finds a suitable route for a TradeFlow between two countries.
## This is the primary integration point for TradeManager to get a SupplyRoutePlan for a trade deal.
## Uses capitals/main hubs when available and general cargo profile.
func find_route_for_trade(from_tag: String, to_tag: String, cargo_tons: float = 100.0) -> SupplyRoutePlan:
	var source := _get_main_hub_for_tag(from_tag)
	var target := _get_main_hub_for_tag(to_tag)
	if source < 0 or target < 0 or source == target:
		return null

	var old_cargo := active_cargo
	active_cargo = SupplyCargoProfile.general_supplies(cargo_tons)

	var plan := _plan_route(source, target, [], false)  # non-player override
	if plan and plan.path_length() >= 2:
		plan.owner_tag = from_tag
		plan.route_id = "trade_%s_%s" % [from_tag, to_tag]
		plan.represents_trade_flow = true
		# Register so MapRenderer / SupplyMapLayer can draw alongside military supply routes.
		# Future: namespace per-flow_id once TradeFlows can diverge bilateral paths.
		_routes[plan.route_id] = plan
		# Note: interdiction estimation inside _plan_route uses player_tag currently.
		# For cross-country trade this is an approximation; future work can improve it.

	active_cargo = old_cargo
	return plan

## Internal helper to find a main hub (capital preferred) for any country tag.
func _get_main_hub_for_tag(tag: String) -> int:
	for hub: ProvinceSupplyHub in hubs.values():
		if hub.owner_tag == tag and hub.has_kind(ProvinceSupplyHub.DepotKind.CAPITAL):
			return hub.province_id
	# Fallback to any hub owned by the tag
	for hub: ProvinceSupplyHub in hubs.values():
		if hub.owner_tag == tag:
			return hub.province_id
	return -1


func _generate_local_supply_from_development(days: float) -> void:
	if days <= 0.0 or typeof(Province) == TYPE_NIL:
		return

	for pid in depot_states.keys():
		var state: ProvinceDepotState = depot_states[pid]
		if state == null:
			continue

		# Decay per-province sabotage state from agent networks (targeted supply disruption lingers but fades)
		# Counter-intel sweeps (via clear_daily_sabotage_effects) or time + repair pressure can clear it faster.
		if state.sabotage_level > 0.0:
			state.sabotage_level = maxf(0.0, state.sabotage_level - 0.13)

		# Prefer centralized MapManager for province access
		var province: Province = null
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			province = MapManager.get_province(int(pid)) as Province
		if province == null:
			var loader := get_node_or_null("/root/ScenarioLoader")
			if loader != null and loader.has_method("get_province"):
				province = loader.call("get_province", pid)
		if province == null:
			continue

		# Use ProvinceEffects when available (dev + national modifiers for local supply)
		var pe: ProvinceEffects = null
		if typeof(ProvinceEffects) != TYPE_NIL:
			pe = _get_effects_safe(pid, _ctrl(province))
		var local_gen := (
			pe.get_effective_local_supply_generation()
			if pe != null
			else province.get_local_supply_generation_modifier()
		)
		if local_gen <= 0.0:
			continue

		# Base local supply generation scaled by development + effects
		# Special sites (ports, etc.) now contribute via ProvinceEffects.get_effective_local_supply_generation()
		var daily_gen := 40.0 * local_gen * days

		# Additional naval/port bonus from special sites (Phase 2)
		var site_fx: Dictionary = pe.get_special_site_effects() if pe != null else {}
		if site_fx.get("has_ports", false):
			daily_gen *= 1.15  # Ports give 15% local supply efficiency bonus

		# Oil Refinery fuel production bonus
		if province.has_special_site_of_type(SpecialSite.SiteType.OIL_REFINERY):
			# Add a small fuel stockpile or efficiency bonus (simplified)
			state.fuel_stockpile += 8.0 * days

		# Targeted daily sabotage from active supply_disruption networks in this specific province
		if typeof(AgentManager) != TYPE_NIL:
			var disruption: float = AgentManager.get_supply_disruption_in_province(int(pid))
			if disruption > 0.0:
				var penalty := clampf(disruption * 0.25, 0.0, 0.6)  # up to 60% reduction from strong network
				daily_gen *= (1.0 - penalty)

		state.apply_inflow(daily_gen)

	# Note: stray menu-ranking code was previously inserted here by accident (removed in Phase 1 verify).
	# _generate is fire-and-forget; depot menu uses its own ranking in get_depot_menu_lines.

func toggle_overlay() -> void:
	overlay_visible = not overlay_visible
	overlay_toggled.emit(overlay_visible)


## Naval Recon System
## Fleets in sea provinces provide daily recon rolls on adjacent land provinces.
## Chance based on naval strength (proxy for #ships + value + recon planes).
## 1 "attempt" per day per seazone presence.
## Also handles spotting enemy fleets in the same seazone (not guaranteed).
func _process_naval_recon(days: float = 1.0) -> void:
	if days <= 0.0 or typeof(MapManager) == TYPE_NIL:
		return

	var sea_provinces: Array = []
	if MapManager.has_method("get_provinces_by_terrain"):
		sea_provinces = MapManager.get_provinces_by_terrain("sea")
	if sea_provinces.is_empty():
		# Fallback: scan all provinces for sea ones with naval presence
		for pid in force_registry.all_province_ids():
			var p: Province = MapManager.get_province(pid) as Province
			if p != null and p.is_sea:
				sea_provinces.append(pid)

	var adjacency_sys: AdjacencySystem = null
	if MapManager.has_method("get_adjacency_system"):
		adjacency_sys = MapManager.get_adjacency_system()

	for sea_pid in sea_provinces:
		var naval_report := force_registry.get_report(sea_pid)
		if naval_report == null or naval_report.get_navy_total() <= 0.0:
			continue

		# For each owner with naval presence in this seazone
		var naval_strength: Dictionary = naval_report.get_naval_strength()
		for owner in naval_strength:
			var strength = float(naval_strength[owner])
			if strength <= 0.0:
				continue

			# Recon to adjacent land provinces (1 chance per day)
			if adjacency_sys != null:
				var land_neighbors = adjacency_sys.get_land_neighbors(sea_pid)
				for land_pid in land_neighbors:
					# Chance based on strength (stronger fleet = better chance)
					# Base chance per day ~ strength / 20 , capped
					var chance = minf(0.75, strength / 25.0)
					if randf() < chance:
						# Successful recon on land province
						# For now, boost local recon or log; later feed to intel map or Province "scouted"
						# Example: add temporary bonus to interdiction resistance or reveal to player
						_add_naval_recon_intel(land_pid, owner, strength * 0.1)

			# Enemy fleet spotting in same seazone
			for other_owner in naval_strength:
				if other_owner == owner:
					continue
				# Simple hostility check (in real game, use diplomacy or at_war)
				if _are_hostile(owner, other_owner):
					var other_strength = float(naval_strength[other_owner])
					# Detection chance based on relative strength + recon value
					var detect_chance = minf(0.6, (strength * 1.2) / (other_strength + 5.0))
					if randf() < detect_chance:
						# Enemy fleet detected in zone
						_report_enemy_naval_detection(sea_pid, owner, other_owner, other_strength)


func _add_naval_recon_intel(land_pid: int, owner: String, recon_value: float) -> void:
	# Placeholder: in full system, this would add to a per-country intel map or trigger "province scouted" event
	# For now, we can boost the province's temporary recon or feed to SupplyIntelBridge
	if typeof(SupplyIntelBridge) != TYPE_NIL:
		# Hypothetical hook
		pass
	# Debug / future: print("Naval recon: %s gained intel on province %d (value %.1f)" % [owner, land_pid, recon_value])


func _report_enemy_naval_detection(sea_pid: int, spotter: String, spotted: String, strength: float) -> void:
	# Placeholder for UI/AI notification: "Enemy fleet detected in seazone X"
	# Can emit signal or add to intel
	print("Naval detection: %s spotted %s fleet (str %.1f) in sea province %d" % [spotter, spotted, strength, sea_pid])


func _are_hostile(a: String, b: String) -> bool:
	# Simple placeholder; real version would check diplomacy/war state
	return a != b  # Assume different tags are potentially hostile for recon purposes


## Naval fuel/endurance consumption, vulnerability, resupply at ports, and repair hooks.
## Formations with naval category in sea provinces consume based on template fuel + order intensity + days.
## Low fuel: power/speed penalty (caller passes to BM), higher detect vuln.
## Resupply: if in/adjacent port province with fuel_stockpile or depot, refuel.
## Repair: slow org/readiness/strength recovery at port (dockyards/tech later).
## Also: chance to trigger full BM naval engagement on strong detection (beyond log).
func _process_naval_fuel_endurance_and_repair(days: float = 1.0) -> void:
	if days <= 0.0 or typeof(LeaderManager) == TYPE_NIL or typeof(MapManager) == TYPE_NIL:
		return
	var sea_pids: Array = []
	if MapManager.has_method("get_provinces_by_terrain"):
		sea_pids = MapManager.get_provinces_by_terrain("sea")
	for pidv in sea_pids:
		var pid := int(pidv)
		var report := force_registry.get_report(pid)
		if report == null or report.get_navy_total() <= 0.0:
			continue
		var naval_strength: Dictionary = report.get_naval_strength()
		for owner in naval_strength.keys():
			if float(naval_strength[owner]) <= 0.0:
				continue
			# Find naval formations for this owner (use LeaderManager)
			for f in LeaderManager.get_formations_for_country(owner):
				if f == null or f.get_category() != "naval" or int(f.stationed_province_id if "stationed_province_id" in f else -1) != pid:
					continue
				# Consume fuel/supply for at-sea ops (use template if linked, else proxy from name/size)
				var base_fuel := 12.0  # abstract daily for fleet proxy
				var nname := str(f.name).to_lower() + " " + str(f.naval_design_id).to_lower()
				if "sub" in nname: base_fuel = 6.0
				elif "carrier" in nname or "battleship" in nname: base_fuel = 22.0
				elif "destroyer" in nname or "frigate" in nname: base_fuel = 9.0
				var order_mult := 1.0
				match f.current_naval_order:
					Formation.NAVAL_ORDER_SEARCH_PATROL, Formation.NAVAL_ORDER_SEARCH_AND_DESTROY, Formation.NAVAL_ORDER_STRIKE:
						order_mult = 1.25
					Formation.NAVAL_ORDER_AMBUSH:
						order_mult = 0.9
					Formation.NAVAL_ORDER_ASW, Formation.NAVAL_ORDER_ESCORT:
						order_mult = 1.1
				var consume := base_fuel * order_mult * days * (f.mission_intensity if "mission_intensity" in f else 1.0) * 0.15
				# Apply to a fuel proxy on formation (add export if needed; use meta or readiness decay for now)
				var cur_fuel := float(f.get("fuel_level") if f.has("fuel_level") else 0.9)
				cur_fuel = clamp(cur_fuel - consume * 0.01, 0.1, 1.2)
				if f.has_method("set"):
					f.set("fuel_level", cur_fuel)  # may not persist perfectly but for sim
				# If low fuel, increase vuln (meta for BM context)
				if cur_fuel < 0.4:
					# Tag for next engagement
					if not has_meta("low_fuel_navies"): set_meta("low_fuel_navies", {})
					var lf := get_meta("low_fuel_navies") as Dictionary
					lf[str(pid) + "_" + owner] = cur_fuel
					set_meta("low_fuel_navies", lf)
				# Resupply/repair rates from naval basing capacity (not flat at_port only).
				var rates: Dictionary = _resolve_naval_basing_service_rates(pid, owner, report)
				if bool(rates.get("can_service", false)):
					var refuel_r := float(rates.get("refuel_rate", 0.0))
					var org_r := float(rates.get("repair_org_rate", 0.0))
					var ready_r := float(rates.get("repair_readiness_rate", 0.0))
					var str_r := float(rates.get("repair_strength_rate", 0.0))
					if refuel_r > 0.0 and cur_fuel < 0.95:
						cur_fuel = min(1.05, cur_fuel + refuel_r * days)
						if f.has_method("set"):
							f.set("fuel_level", cur_fuel)
					if org_r > 0.0:
						f.organization = clamp(float(f.organization) + org_r * days, 0.3, 1.0)
					if ready_r > 0.0:
						f.readiness = clamp(float(f.readiness) + ready_r * days, 0.3, 1.0)
					if str_r > 0.0 and float(f.strength) < 0.95:
						f.strength = clamp(float(f.strength) + str_r * days, 0.4, 1.0)
				# Possible engagement trigger on good mutual detect (beyond log in recon)
				if randf() < 0.12 * days :  # hostiles exist proxy (simplified; in full check war/diplo)
					var has_hostile := false
					for o2 in report.naval_strength.keys():
						if str(o2) != owner and _are_hostile(owner, str(o2)):
							has_hostile = true; break
					if has_hostile:
						# Find possible enemy
						for o2 in report.naval_strength.keys():
							if o2 == owner or float(report.naval_strength[o2]) < 1.0:
								continue
							if _are_hostile(owner, str(o2)) and randf() < 0.4:
								if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("execute_naval_engagement"):
									var intens: float = clampf(0.4 + (1.0 - cur_fuel) * 0.3, 0.3, 0.9)
									BattleManager.execute_naval_engagement(owner, str(o2), pid, intens, "sub" in nname, cur_fuel < 0.5)
								break
	# Decay low fuel meta occasionally
	if has_meta("low_fuel_navies") and randf() < 0.3:
		var lf2: Dictionary = get_meta("low_fuel_navies") as Dictionary
		for k in lf2.keys():
			lf2[k] = float(lf2[k]) + 0.05
			if float(lf2[k]) > 0.9: lf2.erase(k)
		set_meta("low_fuel_navies", lf2)


## Average friendly sea-zone supply multiplier along a route path.
## Landlocked segments (no sea zone) are skipped; all-land paths → 1.0.
func get_sea_zone_supply_multiplier_for_path(path: Array, friendly_tag: String = "") -> float:
	var tag := friendly_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = player_tag.strip_edges().to_upper()
	var mults: Array = []
	if typeof(MapManager) == TYPE_NIL:
		return 1.0
	for pidv in path:
		var pid := int(pidv)
		var control: Dictionary = {}
		if MapManager.has_method("get_sea_zone_control_for_province"):
			control = MapManager.get_sea_zone_control_for_province(pid)
		elif MapManager.has_method("get_sea_zone_strategic_modifiers_for_province"):
			control = MapManager.get_sea_zone_strategic_modifiers_for_province(pid)
		if control.is_empty():
			continue  # no sea zone on this province
		var fr: Dictionary = {}
		if typeof(MapPolishFormatters) != TYPE_NIL:
			fr = MapPolishFormatters.friendly_sea_zone_multipliers_from_dict(control, tag)
		else:
			fr = {"supply_multiplier": float(control.get("supply_multiplier", 1.0)), "applies": true}
		if bool(fr.get("applies", true)):
			mults.append(float(fr.get("supply_multiplier", 1.0)))
	if typeof(MapPolishFormatters) != TYPE_NIL:
		return MapPolishFormatters.combine_path_multipliers(mults, 1.0)
	if mults.is_empty():
		return 1.0
	var s := 0.0
	for m in mults:
		s += float(m)
	return clampf(s / float(mults.size()), 0.5, 1.25)


## Average friendly sea-zone trade multiplier along a route path (for TradeManager).
func get_sea_zone_trade_multiplier_for_path(path: Array, friendly_tag: String = "") -> float:
	var tag := friendly_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = player_tag.strip_edges().to_upper()
	var mults: Array = []
	if typeof(MapManager) == TYPE_NIL:
		return 1.0
	for pidv in path:
		var pid := int(pidv)
		var control: Dictionary = {}
		if MapManager.has_method("get_sea_zone_control_for_province"):
			control = MapManager.get_sea_zone_control_for_province(pid)
		elif MapManager.has_method("get_sea_zone_strategic_modifiers_for_province"):
			control = MapManager.get_sea_zone_strategic_modifiers_for_province(pid)
		if control.is_empty():
			continue
		var fr: Dictionary = {}
		if typeof(MapPolishFormatters) != TYPE_NIL:
			fr = MapPolishFormatters.friendly_sea_zone_multipliers_from_dict(control, tag)
		else:
			fr = {"trade_multiplier": float(control.get("trade_multiplier", 1.0)), "applies": true}
		if bool(fr.get("applies", true)):
			mults.append(float(fr.get("trade_multiplier", 1.0)))
	if typeof(MapPolishFormatters) != TYPE_NIL:
		return MapPolishFormatters.combine_path_multipliers(mults, 1.0)
	if mults.is_empty():
		return 1.0
	var s := 0.0
	for m in mults:
		s += float(m)
	return clampf(s / float(mults.size()), 0.5, 1.25)


## Resolve basing service rates for a sea province (self or adjacent basing).
## Uses MapManager.get_naval_basing + MapPolishFormatters.basing_repair_refuel_rates.
func _resolve_naval_basing_service_rates(province_id: int, owner_tag: String, report: ProvinceForceReport = null) -> Dictionary:
	var empty := {
		"level": "none",
		"capacity": 0,
		"refuel_rate": 0.0,
		"repair_org_rate": 0.0,
		"repair_readiness_rate": 0.0,
		"repair_strength_rate": 0.0,
		"can_service": false,
		"scale": 1.0,
		"summary": "no basing service",
	}
	if typeof(MapManager) == TYPE_NIL:
		return empty
	var basing: Dictionary = {}
	var candidates: Array[int] = [province_id]
	if MapManager.has_method("get_adjacent_provinces"):
		for ap in MapManager.get_adjacent_provinces(province_id):
			candidates.append(int(ap))
	var best: Dictionary = {}
	var best_rank := -1
	for cid in candidates:
		var b: Dictionary = {}
		if MapManager.has_method("get_naval_basing"):
			b = MapManager.get_naval_basing(cid)
		elif MapManager.has_method("get_naval_basing_for_province"):
			b = MapManager.get_naval_basing_for_province(cid)
		if b.is_empty() or not bool(b.get("is_naval", false)):
			continue
		var rank := 0
		match str(b.get("level", "none")):
			"anchorage":
				rank = 1
			"port":
				rank = 2
			"major_base":
				rank = 3
			_:
				rank = 0
		if rank > best_rank or (rank == best_rank and int(b.get("capacity", 0)) > int(best.get("capacity", 0))):
			best_rank = rank
			best = b
	# Fallback: legacy at_port presence → treat as generic port rates if basing API empty
	if best.is_empty():
		var at_port := false
		if report != null:
			at_port = bool(report.naval_at_port_by_tag.get(owner_tag, 0.0) > 0.0)
		if not at_port and MapManager.has_method("get_adjacent_provinces"):
			for ap in MapManager.get_adjacent_provinces(province_id):
				var apv: Province = MapManager.get_province(int(ap)) if MapManager.has_method("get_province") else null
				if apv != null and (apv.has_feature("port") or apv.has_feature("naval_base")):
					at_port = true
					break
		if at_port:
			best = {"level": "port", "capacity": 6, "is_naval": true}
		else:
			return empty
	if typeof(MapPolishFormatters) != TYPE_NIL:
		return MapPolishFormatters.basing_repair_refuel_rates(best)
	# Inline port-tier fallback if formatter unavailable
	return {
		"level": str(best.get("level", "port")),
		"capacity": int(best.get("capacity", 6)),
		"refuel_rate": 0.25,
		"repair_org_rate": 0.04,
		"repair_readiness_rate": 0.03,
		"repair_strength_rate": 0.02,
		"can_service": true,
		"scale": 1.0,
		"summary": "fallback port rates",
	}


func ensure_division_formations_for_country(country_tag: String) -> void:
	if typeof(LeaderManager) != TYPE_NIL:
		LeaderManager.register_division_formations_for_country(country_tag)


func get_engineer_capable_formations(country_tag: String) -> Array[Dictionary]:
	## Divisions with engineer subunits/sustainment, including map location.
	var tag := country_tag.strip_edges().to_upper()
	var out: Array[Dictionary] = []
	if tag.is_empty():
		return out
	ensure_division_formations_for_country(tag)
	division_templates.load_all()
	if typeof(LeaderManager) == TYPE_NIL:
		return out
	for formation in LeaderManager.get_formations_for_country(tag):
		if formation == null or formation.formation_type != Formation.TYPE_DIVISION:
			continue
		var div_id := formation.formation_id
		var template: DivisionTemplate = division_templates.get_division(div_id)
		if template == null:
			continue
		var eng := template.count_engineer_brigade_equivalent()
		if eng < 0.05:
			continue
		var stationed := formation.stationed_province_id
		if division_deployments.has(div_id):
			stationed = int((division_deployments[div_id] as Dictionary).get("province_id", stationed))
		var display := formation.name
		if display.is_empty():
			display = template.display_name if not template.display_name.is_empty() else div_id
		out.append({
			"formation_id": div_id,
			"display_name": display,
			"engineer_brigades": eng,
			"stationed_province_id": stationed,
		})
	return out


func get_formations_stationed_at_province(province_id: int, country_tag: String = "") -> Array[Dictionary]:
	return get_land_divisions_at_province(province_id, country_tag, true)


func get_land_divisions_at_province(
	province_id: int,
	country_tag: String = "",
	engineers_only: bool = false,
) -> Array[Dictionary]:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = player_tag
	var out: Array[Dictionary] = []
	if tag.is_empty():
		return out
	# load_all is cached (idempotent); still avoid ensure_* on hot map paths when possible.
	division_templates.load_all()
	var seen: Dictionary = {}
	for fid_var in division_deployments.keys():
		var fid := str(fid_var)
		var dep: Dictionary = division_deployments[fid] as Dictionary
		if int(dep.get("province_id", -1)) != province_id:
			continue
		var dep_tag := str(dep.get("country_tag", tag)).strip_edges().to_upper()
		if dep_tag != tag:
			continue
		var template: DivisionTemplate = division_templates.get_division(fid)
		if template == null:
			continue
		if engineers_only and template.count_engineer_brigade_equivalent() < 0.05:
			continue
		var formation: Formation = null
		if typeof(LeaderManager) != TYPE_NIL:
			formation = LeaderManager.get_formation(fid)
		var display := fid
		if formation != null and not formation.name.is_empty():
			display = formation.name
		elif not template.display_name.is_empty():
			display = template.display_name
		out.append({
			"formation_id": fid,
			"display_name": display,
			"country_tag": tag,
			"stationed_province_id": province_id,
			"engineer_brigades": template.count_engineer_brigade_equivalent(),
		})
		seen[fid] = true
	# world_full / scenario OOB: land formations stationed by Formation.stationed_province_id
	# without a matching DivisionTemplate deployment entry.
	if not engineers_only and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formations_for_country"):
		for formation2 in LeaderManager.get_formations_for_country(tag):
			if formation2 == null:
				continue
			var ftype := str(formation2.formation_type) if "formation_type" in formation2 else ""
			if ftype != Formation.TYPE_DIVISION and ftype != Formation.TYPE_GARRISON:
				continue
			var fid2 := str(formation2.formation_id) if "formation_id" in formation2 else ""
			if fid2.is_empty() or seen.has(fid2):
				continue
			var sid := int(formation2.stationed_province_id) if "stationed_province_id" in formation2 else -1
			if sid != province_id:
				continue
			var display2 := str(formation2.name) if "name" in formation2 and not str(formation2.name).is_empty() else fid2
			out.append({
				"formation_id": fid2,
				"display_name": display2,
				"country_tag": tag,
				"stationed_province_id": province_id,
				"engineer_brigades": 0.0,
			})
	return out


func _formation_engineer_equiv(formation_id: String) -> float:
	division_templates.load_all()
	var template: DivisionTemplate = division_templates.get_division(formation_id)
	if template == null:
		return 0.0
	return template.count_engineer_brigade_equivalent()


func _recalculate_engineers_at_province(province_id: int, country_tag: String) -> void:
	var tag := country_tag.strip_edges().to_upper()
	var total := 0.0
	for fid in division_deployments.keys():
		var dep: Dictionary = division_deployments[fid] as Dictionary
		if int(dep.get("province_id", -1)) != province_id:
			continue
		if str(dep.get("country_tag", "")).strip_edges().to_upper() != tag:
			continue
		total += _formation_engineer_equiv(str(fid))
	var report := force_registry.get_report(province_id)
	report.set_engineers(tag, total)


func _sort_engineer_deploy_candidates(entries: Array[Dictionary]) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var eng_a := float(a.get("engineer_brigades", 0.0))
		var eng_b := float(b.get("engineer_brigades", 0.0))
		if eng_a != eng_b:
			return eng_a > eng_b
		return str(a.get("display_name", "")) < str(b.get("display_name", ""))
	)


func pick_formation_for_engineer_deployment(country_tag: String, target_province_id: int) -> String:
	## Prefer a division already at the province, else strongest free division, then strongest remote.
	var tag := country_tag.strip_edges().to_upper()
	var candidates := get_engineer_capable_formations(tag)
	if candidates.is_empty():
		return ""
	for entry in candidates:
		if int(entry.get("stationed_province_id", -1)) == target_province_id:
			return str(entry.get("formation_id", ""))
	var unassigned: Array[Dictionary] = []
	var remote: Array[Dictionary] = []
	for entry in candidates:
		var pid := int(entry.get("stationed_province_id", -1))
		if pid < 0:
			unassigned.append(entry)
		elif pid != target_province_id:
			remote.append(entry)
	if not unassigned.is_empty():
		_sort_engineer_deploy_candidates(unassigned)
		return str(unassigned[0].get("formation_id", ""))
	if not remote.is_empty():
		_sort_engineer_deploy_candidates(remote)
		return str(remote[0].get("formation_id", ""))
	return str(candidates[0].get("formation_id", ""))


func _province_engineer_snapshot(province_id: int, country_tag: String) -> Dictionary:
	var snap := {
		"engineer_brigades": 0.0,
		"repair_total": 0.0,
		"guidance_level": "none",
		"province_name": "",
	}
	if typeof(MapManager) == TYPE_NIL:
		return snap
	var p: Province = MapManager.get_province(province_id)
	if p != null:
		snap["province_name"] = p.name
	var bd: Dictionary = MapManager.get_infrastructure_repair_breakdown(province_id)
	snap["engineer_brigades"] = float(bd.get("engineer_brigades", 0.0))
	snap["repair_total"] = float(bd.get("total", 0.0))
	if p != null and typeof(ProvinceInsight) != TYPE_NIL:
		snap["guidance_level"] = ProvinceInsight.get_engineer_guidance_level(p, bd)
	return snap


func move_formation_to_province(
	formation_id: String,
	province_id: int,
	country_tag: String = "",
) -> Dictionary:
	## General division movement order — deployment, formation location, and map presence.
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = player_tag
	var fid := formation_id.strip_edges()
	if fid.is_empty():
		return {"ok": false, "error": "No division specified"}
	if tag.is_empty() or not provinces.has(province_id):
		return {"ok": false, "error": "Invalid province or country"}
	var province: Province = provinces[province_id] as Province
	if province == null or _ctrl(province) != tag:
		return {"ok": false, "error": "Province not controlled by %s" % tag}
	division_templates.load_all()
	var template: DivisionTemplate = division_templates.get_division(fid)
	if template == null:
		return {"ok": false, "error": "Unknown division: %s" % fid}
	ensure_division_formations_for_country(tag)
	var moved_from := -1
	if division_deployments.has(fid):
		moved_from = int((division_deployments[fid] as Dictionary).get("province_id", -1))
	var dest_before := _province_engineer_snapshot(province_id, tag)
	var origin_before: Dictionary = {}
	if moved_from >= 0 and moved_from != province_id:
		origin_before = _province_engineer_snapshot(moved_from, tag)
	division_deployments[fid] = {
		"province_id": province_id,
		"country_tag": tag,
		"order_type": FormationMovement.ORDER_MOVE_TO_PROVINCE,
	}
	if typeof(LeaderManager) != TYPE_NIL:
		var formation: Formation = LeaderManager.get_formation(fid)
		if formation != null:
			formation.stationed_province_id = province_id
	if moved_from >= 0 and moved_from != province_id:
		_recalculate_engineers_at_province(moved_from, tag)
	register_division_presence(province_id, tag, template, 1.0)
	_recalculate_engineers_at_province(province_id, tag)
	var dest_after := _province_engineer_snapshot(province_id, tag)
	var origin_after: Dictionary = {}
	if moved_from >= 0 and moved_from != province_id:
		origin_after = _province_engineer_snapshot(moved_from, tag)
	return {
		"ok": true,
		"order_type": FormationMovement.ORDER_MOVE_TO_PROVINCE,
		"province_id": province_id,
		"formation_id": fid,
		"division_name": template.display_name if not template.display_name.is_empty() else fid,
		"engineer_brigades": float(dest_after.get("engineer_brigades", 0.0)),
		"engineer_equiv": template.count_engineer_brigade_equivalent(),
		"guidance_before": str(dest_before.get("guidance_level", "none")),
		"guidance_after": str(dest_after.get("guidance_level", "none")),
		"moved_from_province_id": moved_from,
		"moved_from_name": str(origin_before.get("province_name", "")),
		"origin_before": origin_before,
		"origin_after": origin_after,
		"destination_before": dest_before,
		"destination_after": dest_after,
	}


func deploy_engineer_formation_to_province(
	formation_id: String,
	province_id: int,
	country_tag: String = "",
) -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = player_tag
	var fid := formation_id.strip_edges()
	if fid.is_empty():
		fid = pick_formation_for_engineer_deployment(tag, province_id)
	if fid.is_empty():
		return {"ok": false, "error": "No engineer-capable division available"}
	division_templates.load_all()
	var template: DivisionTemplate = division_templates.get_division(fid)
	if template == null:
		return {"ok": false, "error": "Unknown division: %s" % fid}
	if template.count_engineer_brigade_equivalent() < 0.05:
		return {"ok": false, "error": "%s has no engineer brigades" % fid}
	var result := move_formation_to_province(fid, province_id, tag)
	if not bool(result.get("ok", false)):
		return result
	result["engineer_equiv"] = template.count_engineer_brigade_equivalent()
	return result


## Map assignment: move an engineer-capable division to a province (replaces demo-only registration).
func station_engineer_brigades_at(
	province_id: int,
	country_tag: String = "",
	_brigade_equiv: float = 1.0,
	formation_id: String = "",
) -> Dictionary:
	return deploy_engineer_formation_to_province(formation_id, province_id, country_tag)


func seed_demo_engineer_presence(country_tag: String = "") -> void:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = player_tag
	if tag.is_empty():
		return
	ensure_division_formations_for_country(tag)
	var target_pid := -1
	for pid_var in provinces:
		var province: Province = provinces[pid_var] as Province
		if province == null or _ctrl(province) != tag:
			continue
		if typeof(MapManager) != TYPE_NIL and typeof(ProvinceInsight) != TYPE_NIL:
			var bd := MapManager.get_infrastructure_repair_breakdown(province.id)
			if ProvinceInsight.province_needs_engineer_assignment(province, bd):
				target_pid = province.id
				break
		if target_pid < 0:
			target_pid = province.id
	if target_pid < 0:
		return
	deploy_engineer_formation_to_province("", target_pid, tag)


func resync_division_deployments_to_registry() -> void:
	## Rebuild engineer totals and division presence from division_deployments (after load).
	if division_deployments.is_empty():
		return
	var tags_seen: Dictionary = {}
	var provinces_seen: Dictionary = {}
	for fid in division_deployments.keys():
		var dep: Dictionary = division_deployments[fid] as Dictionary
		var tag := str(dep.get("country_tag", "")).strip_edges().to_upper()
		var pid := int(dep.get("province_id", -1))
		if tag.is_empty() or pid < 0:
			continue
		tags_seen[tag] = true
		provinces_seen[pid] = true
		division_templates.load_all()
		var template: DivisionTemplate = division_templates.get_division(str(fid))
		if template == null:
			continue
		if typeof(LeaderManager) != TYPE_NIL:
			var formation: Formation = LeaderManager.get_formation(str(fid))
			if formation != null:
				formation.stationed_province_id = pid
		register_division_presence(pid, tag, template, 1.0)
	for pid in provinces_seen.keys():
		for tag in tags_seen.keys():
			_recalculate_engineers_at_province(int(pid), str(tag))


## === Save/Load (division_deployments + depots via SaveLoadManager supply section) ===
func get_save_data() -> Dictionary:
	var depots := {}
	for pid in depot_states.keys():
		var depot: ProvinceDepotState = depot_states[pid]
		if depot == null:
			continue
		depots[str(pid)] = {
			"stockpile": depot.stockpile,
			"throughput_capacity": depot.throughput_capacity,
			"sabotage_level": depot.sabotage_level,
		}
	var deployments := {}
	for fid in division_deployments.keys():
		deployments[str(fid)] = (division_deployments[fid] as Dictionary).duplicate(true)
	return {
		"version": 1,
		"depots": depots,
		"division_deployments": deployments,
	}


func apply_save_data(
	data: Dictionary,
	restore_depots: bool = true,
	restore_deployments: bool = true,
) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	if restore_depots:
		var depots: Dictionary = data.get("depots", {}) as Dictionary
		for pid_str in depots.keys():
			var pid := int(pid_str)
			var entry: Dictionary = depots[pid_str] as Dictionary
			var depot: ProvinceDepotState = depot_states.get(pid)
			if depot != null and typeof(entry) == TYPE_DICTIONARY:
				depot.stockpile = float(entry.get("stockpile", depot.stockpile))
				if entry.has("throughput_capacity"):
					depot.throughput_capacity = float(entry["throughput_capacity"])
				if entry.has("sabotage_level"):
					depot.sabotage_level = float(entry["sabotage_level"])
	if restore_deployments and data.has("division_deployments"):
		division_deployments.clear()
		var saved_deps: Dictionary = data.get("division_deployments", {}) as Dictionary
		for fid in saved_deps.keys():
			var dep: Dictionary = saved_deps[fid] as Dictionary
			if typeof(dep) != TYPE_DICTIONARY:
				continue
			division_deployments[str(fid)] = dep.duplicate(true)
		resync_division_deployments_to_registry()
		print("SupplyManager: restored %d division deployments" % division_deployments.size())


func seed_demo_enemy_forces(sample_tags: Array[String] = []) -> void:
	force_registry.clear()
	if sample_tags.is_empty():
		sample_tags = ["RUS", "CHN", "IRN", "PRK"]
	var border_candidates: Array[int] = []
	for pid_var in provinces:
		var province: Province = provinces[pid_var]
		if _ctrl(province) != player_tag:
			continue
		for adj_id in province.adjacencies:
			var adj: Province = provinces.get(adj_id)
			if adj != null and _ctrl(adj) != player_tag and not _ctrl(adj).is_empty():
				border_candidates.append(province.id)
				break
	var tag_i := 0
	for pid in border_candidates.slice(0, mini(border_candidates.size(), 12)):
		var enemy_tag: String = sample_tags[tag_i % sample_tags.size()]
		tag_i += 1
		force_registry.add_air_presence(pid, enemy_tag, 1.2 + float(tag_i) * 0.15)
		force_registry.add_land_presence(pid, enemy_tag, 0.8)
		var hub: ProvinceSupplyHub = hubs.get(pid)
		if hub != null and hub.port_level > 0:
			force_registry.add_naval_presence(pid, enemy_tag, 1.5, true)
	refresh_intel_from_forces()


func _plan_route(
	source_id: int,
	target_id: int,
	waypoints: Array[int],
	player_override: bool,
) -> SupplyRoutePlan:
	var cargo := active_cargo if active_cargo != null else SupplyCargoProfile.general_supplies(500.0)
	var plan := SupplyMultimodalRouter.find_best_route(
		source_id, target_id, player_tag, provinces, adjacency, hubs, rules,
		cargo, waypoints, routing_mode_override,
	)
	plan.is_player_override = player_override
	var enemy_presence: Dictionary = get_enemy_presence()
	var inter := SupplyInterdictionEstimator.estimate(
		plan.province_path, provinces, hubs, player_tag, rules, enemy_presence,
	)
	plan.interdiction_chance = float(inter.get("chance", 0.0))
	plan.interdiction_breakdown = inter.get("breakdown", {})

	# === Phase 1: Use ProvinceEffects (or direct getters) + national totals for interdiction resistance ===
	# Province dev/infra + explicit interdiction_resistance from spirits + temp modifiers
	var route_resist := _calculate_route_interdiction_resistance(plan.province_path, player_tag)
	var nat_interdiction := 0.0
	if typeof(NationalSpiritManager) != TYPE_NIL:
		nat_interdiction += NationalSpiritManager.get_total_interdiction_resistance_modifier(player_tag)
	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp := NationalModifierManager.get_supply_modifiers(player_tag)
		nat_interdiction += float(temp.get("interdiction_resistance", 0.0))

	var total_interdiction_resist := route_resist + nat_interdiction
	plan.avg_interdiction_resistance = 1.0 + total_interdiction_resist
	if total_interdiction_resist > 0.0:
		var reduction := clampf(total_interdiction_resist * 0.65, 0.0, 0.60)
		plan.interdiction_chance *= (1.0 - reduction)

	# Air superiority integration: high *our* air adv protects our supply from enemy interdiction (we strafe their strike aircraft, contest airspace).
	# Uses continuous ratio; overwhelming not strictly needed for some protection, but better adv = stronger effect.
	# Matches design: slight adv does not ground enemy, but high adv increases their costs + our protection.
	var our_air_adv := 0.0
	for pth in plan.province_path:
		var r := get_air_power_ratio(int(pth), player_tag)
		our_air_adv = max(our_air_adv, r)
	if our_air_adv > 1.2:
		var protect := clampf( (our_air_adv - 1.0) * 0.12 , 0.0, 0.65)
		if our_air_adv >= 3.5:
			protect = max(protect, 0.55)  # strong protection with overwhelming
		plan.interdiction_chance *= (1.0 - protect)
		if OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1":
			print("[AIR INTERDICT] our air adv x%.2f reduced our interdict chance by %.0f%%" % [our_air_adv, protect*100])

	# === Reinforcement speed from ProvinceEffects / getters + national ===
	var route_reinforce := _calculate_route_reinforcement_modifier(plan.province_path, player_tag)
	var nat_reinforce := 0.0
	if typeof(NationalSpiritManager) != TYPE_NIL:
		# Pull from combat spirits too (training paths / spirits expose it)
		var spirit_combat := NationalSpiritManager.get_spirit_combat_modifiers(player_tag)
		nat_reinforce += float(spirit_combat.get("reinforcement_speed", 0.0))
	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp_c := NationalModifierManager.get_combat_modifiers(player_tag)
		nat_reinforce += float(temp_c.get("reinforcement_speed", 0.0))
		var temp_s := NationalModifierManager.get_supply_modifiers(player_tag)
		nat_reinforce += float(temp_s.get("reinforcement_speed", 0.0))

	# === Radio tree (Support) effects: planning_speed and reconnaissance ===
	if typeof(TechnologyManager) != TYPE_NIL:
		var planning := TechnologyManager.get_effective_planning_speed(player_tag)
		nat_reinforce += planning * 0.6   # 0.08 from radio_ii → ~4.8% reinforcement bonus (modest but visible)

		var recon := TechnologyManager.get_effective_reconnaissance(player_tag)
		if recon > 0.0:
			# Better reconnaissance improves intel, reducing effective interdiction
			plan.interdiction_chance *= maxf(0.55, 1.0 - recon * 1.2)   # 0.05 from radio_i → noticeable reduction

		# Airfield special sites provide additional reconnaissance (Phase 2)
		var air_recon := 0.0
		if typeof(MapManager) != TYPE_NIL:
			for pid in MapManager.get_provinces_by_owner(player_tag):
				var p := MapManager.get_province(pid)
				if p and p.has_special_site_of_type(SpecialSite.SiteType.AIRFIELD):
					# Use ProvinceEffects if available
					var pe := MapManager.get_province_effects(pid, player_tag) if MapManager.has_method("get_province_effects") else null
					if pe and pe.has_method("get_special_site_air_recon_bonus"):
						air_recon += pe.get_special_site_air_recon_bonus()
		if air_recon > 0.0:
			plan.interdiction_chance *= maxf(0.7, 1.0 - air_recon * 0.01)

	plan.reinforcement_modifier = maxf(0.6, 1.0 + route_reinforce + nat_reinforce)

	var attrition := get_attrition_cargo_summary()
	plan.cargo_tons_per_day = maxf(plan.cargo_tons_per_day, float(attrition.get("total_tons", 0.0)))

	# === National + province attrition_reduction (prefer explicit totals) ===
	var attrition_res := 0.0
	if typeof(NationalSpiritManager) != TYPE_NIL:
		attrition_res += NationalSpiritManager.get_total_attrition_reduction_modifier(player_tag)
	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp := NationalModifierManager.get_supply_modifiers(player_tag)
		attrition_res += float(temp.get("attrition_reduction", 0.0))

	if attrition_res > 0.0:
		var reduction := clampf(attrition_res * 0.55, 0.0, 0.45)
		plan.cargo_tons_per_day *= (1.0 - reduction)
	else:
		# Fallback proxy via supply consumption (legacy)
		if typeof(NationalSpiritManager) != TYPE_NIL and player_tag != "":
			var nat_attr_mod := NationalSpiritManager.get_total_supply_consumption_modifier(player_tag)
			if nat_attr_mod < 0.0:
				var reduction := clampf(-nat_attr_mod * 0.35, 0.0, 0.28)
				plan.cargo_tons_per_day *= (1.0 - reduction)

	return plan


func _calculate_route_interdiction_resistance(path: Array, player_tag: String) -> float:
	if path.is_empty() or player_tag.is_empty():
		return 0.0
	var total := 0.0
	var count := 0
	for pid_var in path:
		var pid := int(pid_var)
		if not provinces.has(pid):
			continue
		var province: Province = provinces[pid]
		if _ctrl(province) != player_tag:
			continue
		# Light ProvinceEffects wiring (item 3): prefer it when available for combined layers
		var resist := 1.0
		if typeof(ProvinceEffects) != TYPE_NIL:
			var pe := _get_effects_safe(pid, player_tag)
			resist = pe.get_effective_interdiction_resistance() if pe != null else province.get_interdiction_resistance_modifier()
		else:
			resist = province.get_interdiction_resistance_modifier()
		total += maxf(0.0, resist - 1.0)
		count += 1
	if count == 0:
		return 0.0
	return total / float(count)


## Average friendly-path reinforcement speed modifier (dev/infra + national).
## Used to make high-infra/dev provinces deliver replacements and supplies faster / more effectively.
func _calculate_route_reinforcement_modifier(path: Array, player_tag: String) -> float:
	if path.is_empty() or player_tag.is_empty():
		return 0.0
	var total := 0.0
	var count := 0
	for pid_var in path:
		var pid := int(pid_var)
		if not provinces.has(pid):
			continue
		var province: Province = provinces[pid]
		if _ctrl(province) != player_tag:
			continue
		var reinf := 1.0
		if typeof(ProvinceEffects) != TYPE_NIL:
			var pe := _get_effects_safe(pid, player_tag)
			reinf = pe.get_effective_reinforcement_speed() if pe != null else province.get_reinforcement_speed_modifier()
		else:
			reinf = province.get_reinforcement_speed_modifier()
		total += maxf(0.0, reinf - 1.0)
		count += 1
	if count == 0:
		return 0.0
	return total / float(count)


func _rebuild_default_routes() -> void:
	_default_routes.clear()
	_routes.clear()
	var source := get_capital_hub_id()
	if source < 0:
		return
	var targets: Array[int] = []
	for hub: ProvinceSupplyHub in hubs.values():
		if hub.owner_tag == player_tag and hub.province_id != source:
			targets.append(hub.province_id)
	targets.sort()
	var max_routes := mini(targets.size(), 24)
	for i in range(max_routes):
		var target := targets[i]
		var key := "%d_%d" % [source, target]
		var plan := _plan_route(source, target, [], false)
		plan.route_id = key
		plan.baseline_days = plan.total_days
		_default_routes[key] = plan
		_routes[key] = plan


func _ctrl(province: Province) -> String:
	if not province.controller_tag.is_empty():
		return province.controller_tag
	return province.owner_tag
