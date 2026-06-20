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
const DEBUG_AIR_MISSION_LOGS := false  # Off during play; F10 harness can call _process_air_missions directly when needed.

var player_depot_province_ids: Array[int] = []
var force_registry: CombatPresenceRegistry = CombatPresenceRegistry.new()
var mined_seas: Dictionary = {}  # sea_pid -> days_remaining (set by MINELAY order, decayed by time, cleared by ASW)
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
		depot_states[hub.province_id] = state

	# Apply regional control bonuses (full control of a strategic region gives desirable logistics/power projection rewards)
	_apply_regional_control_throughput_bonuses()


func get_depot_state(province_id: int) -> ProvinceDepotState:
	return depot_states.get(province_id)

## Regional control reward hook: if the owning country fully controls the strategic region containing this depot,
## grant a throughput bonus. This makes "cleaning up" a whole region (e.g. securing the British Isles, or the Baltic)
## strategically rewarding beyond just the provinces.
func _apply_regional_control_throughput_bonuses() -> void:
	if typeof(MapManager) == TYPE_NIL or not MapManager.is_ready():
		return
	for pid in depot_states.keys():
		var state: ProvinceDepotState = depot_states[pid]
		var p: Province = null
		if provinces.has(pid):
			p = provinces[pid]
		else:
			p = MapManager.get_province(pid)
		if p == null:
			continue
		var owner := p.owner_tag
		if owner.is_empty():
			continue
		# Check if this province's region is fully controlled by its owner
		var rid := MapManager.get_province_region_id(pid)
		if rid <= 0:
			continue
		if MapManager.is_strategic_region_fully_controlled(rid, owner):
			# Use real table bonuses from improved scenario connections (regional_pride etc already wired elsewhere; here throughput + resources)
			var bonuses := MapManager.get_active_regional_control_bonuses(owner)
			var tp := float(bonuses.get("supply_throughput", bonuses.get("throughput", 0.12)))
			if tp > 0.0:
				state.throughput_capacity *= (1.0 + tp)
				if not state.has_meta("regional_control_bonus"):
					state.set_meta("regional_control_bonus", tp)
			# Additional from table: winter/convoy resilience for full regions (e.g. Arctic, Atlantic) boost supply in harsh conditions
			var extra_s := float(bonuses.get("winter_supply_resilience", bonuses.get("convoy_efficiency", 0.0)))
			if extra_s > 0.0:
				state.throughput_capacity *= (1.0 + extra_s * 0.5)
			# port_capacity for depots that are ports (full control of port regions boosts trade/supply throughput)
			var h: ProvinceSupplyHub = hubs.get(pid) as ProvinceSupplyHub
			if h != null and h.port_level > 0:
				var port_b := float(bonuses.get("port_capacity", 0.0))
				if port_b > 0.0:
					state.throughput_capacity *= (1.0 + port_b * 0.5)
			# Resource bonus if this depot/hub provides relevant resources (e.g. iron in Scandinavia region)
			if bonuses.has("resource_bonus") and typeof(bonuses["resource_bonus"]) == TYPE_DICTIONARY:
				var res_b := bonuses["resource_bonus"] as Dictionary
				# Simple: boost stockpile or throughput if hub has matching resource (demo; full would check hub resources)
				for res in res_b.keys():
					if p != null and p.resources.has(res) and float(p.resources[res]) > 0:
						state.throughput_capacity *= (1.0 + float(res_b[res]) * 0.5)  # partial apply
						break
			# Next-level integration: river natural border or strategic chokepoint (Danish Straits, Gibraltar, Skagerrak from special sites + straits data)
			# gives supply throughput / naval logi bonus when controlled (narrows = force multiplier for supply).
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_chokepoint_or_river_supply_bonus"):
				var crb := MapManager.get_chokepoint_or_river_supply_bonus(pid)
				if crb > 1.001:
					state.throughput_capacity *= crb
					if not state.has_meta("chokepoint_river_bonus"):
						state.set_meta("chokepoint_river_bonus", crb - 1.0)

			# Agent-driven resource discovery / exploration national mod (new positive agent impact)
			# Boosts throughput if province has resources (simulates better extraction/gathering from agent prospecting).
			if typeof(NationalModifierManager) != TYPE_NIL:
				var res_mod: Dictionary = NationalModifierManager.get_resource_modifiers(owner) if NationalModifierManager.has_method("get_resource_modifiers") else {}
				var res_mult: float = float(res_mod.get("resource_output_multiplier", 1.0))
				if res_mult > 1.001 and p != null and p.resources.size() > 0:
					state.throughput_capacity *= res_mult
					if not state.has_meta("resource_agent_bonus"):
						state.set_meta("resource_agent_bonus", res_mult - 1.0)


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


func refresh_intel_from_forces() -> void:
	SupplyIntelBridge.refresh_manager(self, player_tag, force_registry, provinces, hubs, rules)
	_apply_agent_intelligence_modifiers()


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
		prov_id = formation.stationed_province_id
		if prov_id < 0 and division_deployments.has(formation_id):
			prov_id = int((division_deployments[formation_id] as Dictionary).get("province_id", -1))
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
	# Daily supply simulation driven by central TimeManager
	advance_supply_day(1.0)

func advance_supply_day(days: float = 1.0) -> void:
	if days <= 0.0:
		return

	# === Province Infrastructure & Development: Local Supply Generation ===
	_generate_local_supply_from_development(days)

	# Naval recon from fleets in sea zones (1 chance per day per seazone presence)
	_process_naval_recon(days)
	# Air missions: recon %, bombing, CAS, interdiction based on air formations/missions/intensity.
	# Intensity/aggressiveness: higher = more sorties (more supply/fuel cost, e.g. round-the-clock airbase ops), stronger effect (better recon %/interdiction).
	# Doctrines/tech (radio for org/coordination, proximity shells for AA, air doctrine) impact.
	# Air can be attached to ships (naval strike/bombard for amphib/land) or land forces (CAS).
	_process_air_missions(days)

	# Full training daily advance (roadmap phase3): is_training formations get readiness/org/xp boost daily; supply cost; leader (officer quality + path) bonuses apply to rate; progress to is_trained for combat bonus.
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_all_formations"):
		for f in LeaderManager.get_all_formations():
			if f == null or not ("is_training" in f and f.is_training):
				continue
			var train_mult := 1.0
			# Leader bonus: officer training quality or assigned leader training path effects speed unit training (readiness/org gain).
			if "leader_id" in f and not str(f.leader_id).is_empty() and LeaderManager.has_method("get_officer_training_quality"):
				var q := float(LeaderManager.get_officer_training_quality(str(f.country_tag if "country_tag" in f else "")))
				train_mult *= clampf(0.7 + q / 60.0, 0.7, 2.2)  # officer quality drives faster train
			# Simple training path synergy if leader (reuse org recovery etc as proxy for training efficiency).
			if "leader_id" in f and LeaderManager.has_method("get_leader_training_path_effects"):
				var leff: Dictionary = LeaderManager.get_leader_training_path_effects(LeaderManager.get_leader(f.leader_id))
				if leff.has("organization_recovery"):
					train_mult *= (1.0 + float(leff["organization_recovery"]) * 0.5)
			if "readiness" in f:
				f.readiness = min(1.8, float(f.readiness) + 0.025 * days * train_mult)
			if "organization" in f:
				f.organization = min(1.8, float(f.organization) + 0.012 * days * train_mult)
			if "training_progress" in f:
				f.training_progress = float(f.training_progress) + 0.8 * days * train_mult
			# Award xp to leader for training command (ties leaders to unit train complete).
			if "leader_id" in f and not str(f.leader_id).is_empty() and LeaderManager.has_method("award_xp_to_leader"):
				LeaderManager.award_xp_to_leader(str(f.leader_id), int(3 * days * train_mult), "formation_training")
			# Supply cost for training (readiness buildup burns supply/fuel; makes holding infra/supply provinces key).
			var stationed := int(f.stationed_province_id) if "stationed_province_id" in f else -1
			if stationed >= 0 and depot_states.has(stationed):
				var dep: ProvinceDepotState = depot_states[stationed]
				var cost: float = 4.0 * days * max(0.6, train_mult - 0.5)  # higher quality train costs more sustain
				dep.stockpile = max(0.0, dep.stockpile - cost)
				if dep.stockpile < 5.0:
					train_mult *= 0.4  # starved training slows
			# Reach trained state (better combat: higher rdy baseline, used in resolver/inspector).
			if "training_progress" in f and float(f.training_progress) >= 6.0 and not bool(f.get("is_trained", false)):
				f.is_trained = true
				if "readiness" in f: f.readiness = max(float(f.readiness), 1.35)
				if "organization" in f: f.organization = max(float(f.organization), 1.2)
				print("[TRAIN COMPLETE] %s reached trained state (progress %.1f, mult %.2f). +combat rdy/org bonus. is_training can now be cleared or kept for sustain." % [str(f.formation_id if "formation_id" in f else "form"), float(f.training_progress), train_mult])
			if float(f.get("training_progress", 0.0)) > 18.0:
				f.is_training = false  # auto graduate after extended training
				print("[TRAIN] %s auto-graduated from is_training after extended (sustained training)." % str(f.formation_id if "formation_id" in f else ""))

	# General formation recovery (core of main combat loop): all formations (idle, moving, post-battle) recover org/readiness daily from supply/infra.
	# Rate scaled by province local org recovery (infra/dev/settlement/weather), supply depot state, and national shortages.
	# Low org from combat or doctrine shifts now heals over time if supplied — makes holding good infra provinces and winning supply war matter.
	# Training gets additional on top (already handled). Combat formations or unsupplied recover much slower.
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_all_formations"):
		for f in LeaderManager.get_all_formations():
			if f == null or ("is_training" in f and f.is_training):
				continue  # training handled above; skip double
			var base_org_rec := 0.008 * days
			var base_rdy_rec := 0.015 * days
			var stationed := int(f.stationed_province_id) if "stationed_province_id" in f else -1
			var rec_factor := 1.0
			var has_local_supply := true
			if stationed >= 0 and typeof(MapManager) != TYPE_NIL:
				var p: Province = MapManager.get_province(stationed)
				if p != null:
					# Prefer Province method (includes settlement, welfare, terrain, snow etc.)
					if p.has_method("get_organization_recovery_modifier"):
						rec_factor = p.get_organization_recovery_modifier()
					else:
						rec_factor = 0.7 + (clampf(float(p.infrastructure), 0, 12) * 0.03) + (clampf(float(p.development_level), 0, 8) * 0.02)
					# Check local depot for supply pressure
					if depot_states.has(stationed):
						var dep: ProvinceDepotState = depot_states[stationed]
						if dep and dep.throughput_capacity > 0 and dep.stockpile < (dep.throughput_capacity * 0.2):
							has_local_supply = false
							rec_factor *= 0.4  # unsupplied province = slow healing
			# National/resource shortage drag (from production eval or NMM)
			if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("has_national_shortages"):
				if ProductionManager.has_national_shortages(f.country_tag if "country_tag" in f else ""):
					rec_factor *= 0.55
			if not has_local_supply:
				base_org_rec *= 0.3
				base_rdy_rec *= 0.4
			# Apply (clamped; also slightly reduced if unit is in aggressive mission)
			var intensity_drag := 1.0
			if "mission_intensity" in f:
				intensity_drag = clampf(1.0 - (float(f.mission_intensity) - 1.0) * 0.15, 0.6, 1.3)
			if "organization" in f:
				f.organization = min(1.5, float(f.organization) + base_org_rec * rec_factor * intensity_drag)
			if "readiness" in f:
				f.readiness = min(1.5, float(f.readiness) + base_rdy_rec * rec_factor * intensity_drag)

	# Basic reinforce from national equipment stockpile for strength-depleted formations (daily loop).
	# Uses shared _try_reinforce_formation for consistency with BM post-combat casualties.
	# Strength casualties now reinforced from stock; production matters.
	if typeof(ProductionManager) != TYPE_NIL and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_all_formations"):
		for f in LeaderManager.get_all_formations():
			_try_reinforce_formation(f)

	_process_air_missions(days)
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
		# Winter supply resilience from full regions for snow provinces (reduces snow penalty on delivery)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
			var reg := MapManager.get_active_regional_control_bonuses(player_tag)
			var winter_r := float(reg.get("winter_supply_resilience", 0.0))
			var dst_p := MapManager.get_province(plan.target_province_id) if MapManager.has_method("get_province") else null
			if winter_r > 0.0 and dst_p and dst_p.snow_potential > 0.1:
				delivery = clampf(delivery * (1.0 + winter_r * 0.5), 0.2, 1.15)
		var inflow := pulled * delivery
		var overflow := dst.apply_inflow(inflow)
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

		# Port capacity bonus for sea trade (full control of port regions boosts cargo for trade flows)
		if plan.uses_port and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
			var reg := MapManager.get_active_regional_control_bonuses(from_tag)
			var port_b := float(reg.get("port_capacity", 0.0))
			if port_b > 0.0:
				plan.cargo_tons_per_day *= (1.0 + port_b)

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
		if naval_report.navy_total <= 0.0:
			continue

		# Decay/clear mines (MINELAY sets, time decays, ASW clears)
		if mined_seas.has(sea_pid):
			mined_seas[sea_pid] = float(mined_seas.get(sea_pid, 0)) - days
			if mined_seas[sea_pid] <= 0:
				mined_seas.erase(sea_pid)

		# For each owner with naval presence in this seazone
		for owner in naval_report.naval_strength:
			var strength = float(naval_report.naval_strength[owner])
			if strength <= 0.0:
				continue

			# Apply overarching naval order mods from actual formations (if any in/near sea)
			var order_detect_mod := 1.0
			var order_stealth_mod := 1.0
			if typeof(LeaderManager) != TYPE_NIL:
				for f in LeaderManager.get_formations_for_country(owner):
					if f and f.get_category() == "naval" and f.stationed_province_id == sea_pid and f.current_naval_order != Formation.NAVAL_ORDER_NONE:
						order_detect_mod *= f.get_naval_order_detection_mod()
						order_stealth_mod *= f.get_naval_order_stealth_mod()
						break  # use one representative order per owner/zone for demo
			var owner_order := Formation.NAVAL_ORDER_NONE
			if typeof(LeaderManager) != TYPE_NIL:
				for f in LeaderManager.get_formations_for_country(owner):
					if f and f.get_category() == "naval" and f.stationed_province_id == sea_pid and f.current_naval_order != Formation.NAVAL_ORDER_NONE:
						owner_order = f.current_naval_order
						break
			# Air support boosts SEARCH/STRIKE detect/engage (tie to air wings over sea)
			var air_strength := 0.0
			if naval_report.has_method("total_air"):
				air_strength = naval_report.total_air(owner)
			if air_strength > 0 and owner_order in [Formation.NAVAL_ORDER_SEARCH_PATROL, Formation.NAVAL_ORDER_STRIKE]:
				order_detect_mod *= (1.0 + air_strength * 0.05)

			# Recon to adjacent land provinces (1 chance per day)
			if adjacency_sys != null:
				var land_neighbors = adjacency_sys.get_land_neighbors(sea_pid)
				for land_pid in land_neighbors:
					# Chance based on strength (stronger fleet = better chance) + order
					var chance = minf(0.75, strength / 25.0 * order_detect_mod)
					if randf() < chance:
						_add_naval_recon_intel(land_pid, owner, strength * 0.1)

			# Enemy fleet spotting in same seazone - enhanced with orders, class, weather, etc.
			for other_owner in naval_report.naval_strength:
				if other_owner == owner:
					continue
				if _are_hostile(owner, other_owner):
					var other_strength: float = float(naval_report.naval_strength.get(other_owner, 0.0))
					var other_subs: float = naval_report.total_subs(other_owner) if naval_report.has_method("total_subs") else other_strength * 0.2
					var other_surface: float = naval_report.total_surface(other_owner) if naval_report.has_method("total_surface") else other_strength * 0.8
					var recon_bonus: float = naval_report.total_naval_recon(owner) if naval_report.has_method("total_naval_recon") else strength * 0.1
					var detect_chance: float = minf(0.85, (strength * 1.1 + recon_bonus) / (other_strength + 8.0))
					# Orders: SEARCH boosts detect, AMBUSH/CONVOY lower profile (stealth)
					detect_chance *= order_detect_mod * (1.0 / max(0.5, order_stealth_mod))  # inverse stealth for enemy detect of us? adjust for own order
					# Enemy order stealth reduces their detect chance
					if typeof(LeaderManager) != TYPE_NIL:
						for f in LeaderManager.get_formations_for_country(other_owner):
							if f and f.get_category() == "naval" and f.stationed_province_id == sea_pid:
								detect_chance *= f.get_naval_order_stealth_mod()
								break
					# Weather/storms
					if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_naval_spotting_visibility"):
						var vis: float = WeatherManager.get_naval_spotting_visibility(sea_pid)
						detect_chance *= vis * 0.9 + 0.1
					# Chokepoint
					if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint") and MapManager.has_strategic_chokepoint(sea_pid):
						detect_chance *= 1.7
					# Subs harder
					if other_subs > other_surface * 0.5:
						detect_chance *= 0.6
					# Groups
					detect_chance = minf(0.95, detect_chance + (strength / 50.0))
					if randf() < detect_chance:
						_report_enemy_naval_detection(sea_pid, owner, other_owner, other_strength)
						var eng_range_mod: float = 1.0
						var is_closer: bool = false
						if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_naval_spotting_visibility"):
							var v: float = WeatherManager.get_naval_spotting_visibility(sea_pid)
							eng_range_mod = clamp(v, 0.4, 1.0)
							if v < 0.5:
								eng_range_mod *= 0.7
								is_closer = true
						# Orders affect range/closer: use full get_naval_order_engagement_mod (AMBUSH/S&D in low vis/strait -> closer; STRIKE good vis -> stand-off)
						var spotter_order = Formation.NAVAL_ORDER_NONE
						if typeof(LeaderManager) != TYPE_NIL and typeof(MapManager) != TYPE_NIL:
							for f in LeaderManager.get_formations_for_country(owner):
								if f and f.get_category() == "naval" and f.stationed_province_id == sea_pid and f.current_naval_order != Formation.NAVAL_ORDER_NONE:
									spotter_order = f.current_naval_order
									var choke = MapManager.has_strategic_chokepoint(sea_pid) if MapManager.has_method("has_strategic_chokepoint") else false
									var eng = f.get_naval_order_engagement_mod(eng_range_mod, choke)
									eng_range_mod = float(eng.get("range_mod", eng_range_mod))
									is_closer = bool(eng.get("closer_engagement", is_closer))
									break
						_try_trigger_naval_combat(sea_pid, owner, other_owner, eng_range_mod, other_subs > 0, is_closer)
						# Aggressive orders (S&D, STRIKE, MINELAY) set raiding threat for this sea, affecting enemy supply interdiction on routes using this sea
						if spotter_order in [Formation.NAVAL_ORDER_SEARCH_AND_DESTROY, Formation.NAVAL_ORDER_STRIKE, Formation.NAVAL_ORDER_MINELAY]:
							var threats = get_meta("sea_naval_raiding") if has_meta("sea_naval_raiding") else {}
							if not threats.has(sea_pid):
								threats[sea_pid] = {}
							threats[sea_pid][owner] = strength  # raider's strength as threat in sea for enemy supply
							set_meta("sea_naval_raiding", threats)

			# MINELAY sets persistent mines (threat to enemy in sea/straits), ASW clears them
			var owner_order_for_mine = Formation.NAVAL_ORDER_NONE
			if typeof(LeaderManager) != TYPE_NIL:
				for f in LeaderManager.get_formations_for_country(owner):
					if f and f.get_category() == "naval" and f.stationed_province_id == sea_pid and f.current_naval_order != Formation.NAVAL_ORDER_NONE:
						owner_order_for_mine = f.current_naval_order
						break
			if owner_order_for_mine == Formation.NAVAL_ORDER_MINELAY:
				mined_seas[sea_pid] = 30.0
			elif owner_order_for_mine == Formation.NAVAL_ORDER_ASW and mined_seas.has(sea_pid):
				mined_seas.erase(sea_pid)


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
	# Feed to intel or map for player awareness (future full UI)
	if typeof(SupplyIntelBridge) != TYPE_NIL:
		SupplyIntelBridge.record_naval_spotting(sea_pid, spotter, spotted, strength)

## Process air missions for air formations (or attached air support to land/naval forces).
## Missions: RECON (spotting % boost), CAS (land combat support), INTERDICTION (supply disruption), STRATEGIC_BOMBING, AIR_SUPERIORITY, NAVAL_STRIKE (attach to ships for bombardment in amphib/land battles).
## Intensity/aggressiveness: higher = more missions/sorties (e.g. round-the-clock airbase ops with more supplies/fuel), stronger %/bonus but higher cost, risk, attrition.
## Doctrines/tech: radio for higher org/coordination in missions (move/attack support), proximity shells boost AA vs air missions, air doctrine improves effectiveness.
## Air can be assigned/attached to ships (naval strike/bombard support) or land forces (CAS, recon).
## Weather, basing (airfields), design maturity affect.
func _process_air_missions(days: float = 1.0) -> void:
	if days <= 0.0 or typeof(LeaderManager) == TYPE_NIL:
		return
	# For each country with air formations
	for tag in ["USA", "GER", "SOV", "ENG", "FRA"]:  # demo; in full scan all
		for f in LeaderManager.get_formations_for_country(tag):
			if f == null or f.get_category() != "air" or f.current_air_mission == Formation.AIR_MISSION_NONE:
				continue
			var intensity := f.mission_intensity
			var mission := f.current_air_mission
			var attached_to_ship := f.attached_air_formation_id != ""  # or check if formation is naval
			# Supply cost based on intensity (higher for aggressive/round-the-clock)
			var supply_cost := f.get_mission_supply_cost(1.0) * days * 0.1  # proxy
			# Effectiveness from ADS/profile
			var eff := 1.0
			if f.has_method("get_mission_mods"):
				var mods := f.get_mission_mods()
				eff = float(mods.get("effect", 1.0))
			# Doctrines/tech/radio/proximity impact (stub; wire to tech/doctrine)
			var tech_boost := 1.0
			# Example: radio for org in high intensity missions
			if intensity > 1.2:
				tech_boost *= 1.1
			# Proximity shells for AA (if mission involves air contest or attached)
			if mission in [Formation.AIR_MISSION_AIR_SUPERIORITY] or attached_to_ship:
				tech_boost *= 1.05  # AA better vs planes
			eff *= tech_boost
			# Mission effects
			match mission:
				Formation.AIR_MISSION_RECON:
					var recon_pct := 20.0 + intensity * 15.0
					recon_pct *= eff * (0.7 + days * 0.1)
					if DEBUG_AIR_MISSION_LOGS:
						print("Air RECON mission (intensity %.1f, eff %.2f): +%.0f%% recon/spotting boost for %s (attach to ships for naval recon)." % [intensity, eff, recon_pct, tag])
				Formation.AIR_MISSION_CLOSE_AIR_SUPPORT:
					if DEBUG_AIR_MISSION_LOGS:
						print("Air CAS mission (intensity %.1f): +%.0f%% ground combat/org support (attach to land forces or for amphib)." % [intensity, 10.0 + intensity * 10.0 * eff])
				Formation.AIR_MISSION_INTERDICTION:
					if DEBUG_AIR_MISSION_LOGS:
						var interd := 0.02 + intensity * 0.03
						print("Air INTERDICTION (intensity %.1f): +%.0f%% supply interdiction in area." % [intensity, interd * 100 * eff])
				Formation.AIR_MISSION_STRATEGIC_BOMBING:
					if DEBUG_AIR_MISSION_LOGS:
						print("Air STRATEGIC_BOMBING (intensity %.1f): infra/prod damage (higher intensity more but risk)." % [intensity])
				Formation.AIR_MISSION_AIR_SUPERIORITY:
					if DEBUG_AIR_MISSION_LOGS:
						print("Air SUPERIORITY (intensity %.1f): contest air, escort bonus, AA vs enemy air." % [intensity])
				Formation.AIR_MISSION_NAVAL_STRIKE:
					if DEBUG_AIR_MISSION_LOGS:
						print("Air NAVAL_STRIKE (intensity %.1f, attached to ship? %s): bonus vs fleets (naval bombardment support for land/amphib)." % [intensity, attached_to_ship])
				Formation.AIR_MISSION_TRANSPORT:
					if DEBUG_AIR_MISSION_LOGS:
						print("Air TRANSPORT (intensity %.1f): airlift supplies/troops (higher intensity more capacity but cost)." % [intensity])
			if intensity > 1.5 and randf() < 0.1 and DEBUG_AIR_MISSION_LOGS:
				print("  Air mission high intensity attrition for %s." % tag)
			# Doctrines/tech examples applied above.

## Strategic naval combat trigger after spotting.
## Uses detection mod, weather for range, chokepoint for close, ship types (subs), groups.
## For sea provinces (large ocean/sea "squares"), spotting chance determines if battle "happens".
## Once spotted, adjusted engagement range based on vis/storms/night -> closer = different tactics (subs shine in low vis/close, surface in good vis/long).
func _try_trigger_naval_combat(sea_pid: int, spotter: String, spotted: String, range_mod: float = 1.0, sub_heavy: bool = false, closer_engagement: bool = false) -> void:
	# Only for hostile, and with some chance even after detect (not every spot leads to immediate full action; positioning etc.)
	if not _are_hostile(spotter, spotted):
		return
	var engage_chance: float = 0.6 * clamp(range_mod, 0.3, 1.2)
	# In straits/chokepoints, higher chance of engagement (less room to maneuver/hide)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint") and MapManager.has_strategic_chokepoint(sea_pid):
		engage_chance *= 1.4
	# Night/storm/closer from order (low range_mod or explicit) -> chance for closer, more intense or ambush style
	if range_mod < 0.6 or closer_engagement:
		engage_chance *= 1.2
	if randf() < engage_chance:
		print("Naval combat triggered: %s vs %s in sea %d (range_mod=%.2f, sub_heavy=%s, closer=%s, chokepoint_engage_boost)" % [spotter, spotted, sea_pid, range_mod, sub_heavy, closer_engagement])
		# In full: call BattleManager or naval specific combat resolver with sea_pid, formations if any, range_mod for weapon effectiveness, sub bonuses. Orders influence (S&D aggressive close).
		# For demo: log detailed factors, and if BattleManager available, attempt naval engagement (passes order mods via range/closer).
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("execute_naval_engagement"):
			BattleManager.execute_naval_engagement(spotter, spotted, sea_pid, range_mod, sub_heavy, closer_engagement)
		else:
			if typeof(LeaderManager) != TYPE_NIL:
				pass
			print("  [NAVAL ENGAGEMENT SIM] Spot -> possible combat at adjusted range. Factors: vis/storm/night/closer=%s, straits=%s, subs=%s, groups boost spot, order mods applied." % [closer_engagement or range_mod<0.6, MapManager.has_strategic_chokepoint(sea_pid) if typeof(MapManager)!=TYPE_NIL and MapManager.has_method("has_strategic_chokepoint") else false, sub_heavy])


func _are_hostile(a: String, b: String) -> bool:
	# Simple placeholder; real version would check diplomacy/war state
	return a != b  # Assume different tags are potentially hostile for recon purposes


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


## World-class reinforce helper (called daily + from BM post strength casualties).
## Reinforces a specific formation from national stock if depleted; production/stock matters for endurance. Ties combat casualties to econ loop.
func _try_reinforce_formation(f: Formation) -> void:
	if f == null or not ("strength" in f) or not ("design_id" in f) or f.design_id.is_empty():
		return
	var str_val := float(f.strength)
	if str_val >= 0.90:
		return
	var ctag := str(f.country_tag if "country_tag" in f else "")
	if ctag.is_empty():
		return
	var stock: Dictionary = {}
	if ProductionManager.has_method("get_country_equipment_stockpile"):
		stock = ProductionManager.get_country_equipment_stockpile(ctag)
	var did := str(f.design_id)
	var avail := int(stock.get(did, 0)) if stock else 0
	if avail <= 0:
		return
	var taken := 0
	if ProductionManager.has_method("take_from_country_equipment_stockpile"):
		taken = ProductionManager.take_from_country_equipment_stockpile(ctag, did, 1)
	if taken > 0:
		f.strength = min(1.0, str_val + 0.09 + randf() * 0.03)
		if "organization" in f:
			f.organization = min(1.5, float(f.organization) + 0.03)
		if "readiness" in f:
			f.readiness = min(1.5, float(f.readiness) + 0.05)
		print("[REINFORCE] %s (%s) reinforced from stock post-casualty or daily (str now %.2f)." % [f.formation_id if "formation_id" in f else did, ctag, float(f.strength)])
	# NEW wiring: pop -> recruit pool -> reinforce formations (deduct manpower on reinforce if low str; strain already in recruit).
	if str_val < 0.85 and typeof(GameData) != TYPE_NIL and GameData.has_method("recruit_units") and GameData.has_method("get_available_recruits"):
		if GameData.get_available_recruits(ctag) > 10 and GameData.recruit_units(ctag, 1):
			f.strength = min(1.0, float(f.strength) + 0.06)
			print("[REINFORCE+MANPOWER] %s reinforced from pop recruit pool (manpower deducted + strain applied). Pool now feeds field strength." % (f.formation_id if "formation_id" in f else did))


## Wiring: factory production output (mil or civilian) boosts local province depot stock/supply (roadmap).
## Called from Production on complete for the factory's province.
func boost_depot_from_production(province_id: int, owner_tag: String, amount: int) -> void:
	if province_id < 0 or amount <= 0:
		return
	if not depot_states.has(province_id):
		# ensure basic
		var st := ProvinceDepotState.new(province_id, 100.0)
		depot_states[province_id] = st
	var dep: ProvinceDepotState = depot_states[province_id]
	var boost: float = float(amount) * 0.8  # goods to local stock
	dep.stockpile = min(dep.storage_capacity * 1.2, dep.stockpile + boost)
	dep.throughput_capacity = max(dep.throughput_capacity, 50.0)
	depot_stock_changed.emit(province_id, dep.stockpile)
	print("[PROD->SUPPLY WIRE] %s boosted depot #%d stock +%.1f (from factory output %d). Local supply for combat/recovery now higher." % [owner_tag, province_id, boost, amount])


func get_land_divisions_at_province(
	province_id: int,
	country_tag: String = "",
	engineers_only: bool = false,
) -> Array[Dictionary]:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = player_tag
	# Teleporters rapid deploy wiring (minor Supply/Leader tie per task)
	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_rule_flag(tag, "teleportation"):
		print("[SPACE WIRING] tele rapid formation deploy for %s (first Mars alt + movement/combat reinforce)" % tag)
	# Teleporters rapid deploy wiring (minor Supply/Leader tie per task)
	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_rule_flag(tag, "teleportation"):
		print("[SPACE WIRING] tele rapid formation deploy for %s (first Mars alt + movement/combat reinforce)" % tag)
	var out: Array[Dictionary] = []
	if tag.is_empty():
		return out
	ensure_division_formations_for_country(tag)
	division_templates.load_all()
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
			# Teleport capability (from teleporters_2025): if division has teleport_infantry capability, allow 'instant' flavor (no extra cost here, but flag rapid)
			if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_division_capability(tag, "teleport_infantry"):
				print("[TELEPORT WIRING] %s division %s uses teleport_infantry capability (rapid_deployment bonus from tech; energy cost in supply)." % [tag, fid])
			# Naval sea move trigger: if moving naval formation to sea province, apply default order if none, trigger recon/detect
			if formation.get_category() == "naval" and province.is_sea:
				if formation.current_naval_order == Formation.NAVAL_ORDER_NONE:
					formation.current_naval_order = Formation.NAVAL_ORDER_SEARCH_PATROL
				# Trigger naval recon/detect in zone (may spot enemy or set orders effects)
				if has_method("_process_naval_recon"):
					_process_naval_recon(0.1)
				# If enemy naval present, may trigger spot/engagement via recon logic
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
		var temp: Dictionary = NationalModifierManager.get_supply_modifiers(player_tag)
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
		var temp_c: Dictionary = NationalModifierManager.get_combat_modifiers(player_tag)
		nat_reinforce += float(temp_c.get("reinforcement_speed", 0.0))
		var temp_s: Dictionary = NationalModifierManager.get_supply_modifiers(player_tag)
		nat_reinforce += float(temp_s.get("reinforcement_speed", 0.0))

	# === Radio tree (Support) effects: planning_speed and reconnaissance ===
	if typeof(TechnologyManager) != TYPE_NIL:
		var planning := TechnologyManager.get_effective_planning_speed(player_tag)
		nat_reinforce += planning * 0.6   # 0.08 from radio_ii → ~4.8% reinforcement bonus (modest but visible)

		var recon := TechnologyManager.get_effective_reconnaissance(player_tag)
		if recon > 0.0:
			# Better reconnaissance improves intel, reducing effective interdiction
			plan.interdiction_chance *= maxf(0.55, 1.0 - recon * 1.2)   # 0.05 from radio_i → noticeable reduction

		# Drone swarms + advanced scanners (drone_swarm_1980, scanners_sensors_1975): +recon/precision from tech + rule_flag
		# Wires to supply interdiction (drones for persistent ISR/EW, scanners multi-spectral); balance: jamming/EM/power vuln (flags allow counter via agents)
		if typeof(TechnologyManager) != TYPE_NIL:
			if TechnologyManager.has_rule_flag(player_tag, "drone_warfare") or TechnologyManager.has_rule_flag(player_tag, "advanced_sensors"):
				var drone_recon := 0.0
				if TechnologyManager.has_rule_flag(player_tag, "drone_warfare"):
					drone_recon += 0.12
				if TechnologyManager.has_rule_flag(player_tag, "advanced_sensors"):
					drone_recon += 0.18
				plan.interdiction_chance *= maxf(0.4, 1.0 - drone_recon)
				# Also slight supply efficiency (better routing/awareness)
				plan.daily_supply_need = max(0.1, plan.daily_supply_need * (1.0 - drone_recon * 0.25))

		# Shields/tele high-future (deflector_shields_1995, teleporters_2025): power/precision costs trade-off (higher supply for energy fields/transporters)
		# Balance with prior supply engines: strong defense/rapid but power hog (fusion prereq); also in space habs
		if typeof(TechnologyManager) != TYPE_NIL:
			if TechnologyManager.has_rule_flag(player_tag, "energy_shields"):
				plan.daily_supply_need *= 1.08  # power draw
			if TechnologyManager.has_rule_flag(player_tag, "teleportation"):
				plan.daily_supply_need *= 1.12  # extreme energy/precision
				plan.interdiction_chance *= 0.6  # hard to interdict teleported supply? but risky
			# Use rapid_deployment mod from nat for faster effective reinforce in plans
			if typeof(NationalModifierManager) != TYPE_NIL:
				var sm := NationalModifierManager.get_combat_modifiers(player_tag)
				var rapid := float(sm.get("rapid_deployment", 0.0))
				if rapid > 0.0:
					plan.daily_supply_need *= maxf(0.7, 1.0 - rapid * 0.5)  # offset some via efficiency of instant?

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

	# Sea naval raiding/protection from orders (S&D/MINELAY/STRIKE in sea on route add threat; CONVOY_DUTY/ESCORT protect)
	# This makes assigning aggressive orders to fleets in key sea zones (e.g. Atlantic, straits) directly raid enemy supply, while escort orders safeguard your own.
	var sea_raiding := 0.0
	var sea_protect := 0.0
	for pid in plan.province_path:
		var p: Province = provinces.get(pid)
		if p != null and p.is_sea:
			# Raiding threat from enemy aggressive orders
			var threats = get_meta("sea_naval_raiding") if has_meta("sea_naval_raiding") else {}
			var sea_th = threats.get(pid, {})
			for r in sea_th:
				if r != player_tag:
					sea_raiding += float(sea_th[r]) * 0.015
			# Persistent minelay threat from MINELAY order (decays, cleared by ASW)
			if mined_seas.get(pid, 0) > 0:
				sea_raiding += 0.05  # adds to interdiction until cleared
			# Protection from own CONVOY/ESCORT orders in the sea
			if typeof(LeaderManager) != TYPE_NIL:
				for f in LeaderManager.get_formations_for_country(player_tag):
					if f and f.get_category() == "naval" and f.stationed_province_id == pid and f.current_naval_order in [Formation.NAVAL_ORDER_CONVOY_DUTY, Formation.NAVAL_ORDER_ESCORT]:
						sea_protect += 0.05  # or use f.get_naval_order_supply_mod etc.
	if sea_raiding > 0.0:
		plan.interdiction_chance = min(0.92, plan.interdiction_chance + sea_raiding)
		plan.interdiction_breakdown["sea_naval_raiding"] = sea_raiding
	if sea_protect > 0.0:
		var prot_red := clampf(sea_protect * 0.8, 0.0, 0.4)
		plan.interdiction_chance *= (1.0 - prot_red)
		plan.interdiction_breakdown["sea_naval_protect"] = prot_red

	plan.reinforcement_modifier = maxf(0.6, 1.0 + route_reinforce + nat_reinforce)

	var attrition := get_attrition_cargo_summary()
	plan.cargo_tons_per_day = maxf(plan.cargo_tons_per_day, float(attrition.get("total_tons", 0.0)))

	# === National + province attrition_reduction (prefer explicit totals) ===
	var attrition_res := 0.0
	if typeof(NationalSpiritManager) != TYPE_NIL:
		attrition_res += NationalSpiritManager.get_total_attrition_reduction_modifier(player_tag)
	if typeof(NationalModifierManager) != TYPE_NIL:
		var temp: Dictionary = NationalModifierManager.get_supply_modifiers(player_tag)
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
	var base_avg := total / float(count)

	# Regional convoy protection boosts route resistance (full control of naval/chokepoint regions)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
		var reg := MapManager.get_active_regional_control_bonuses(player_tag)
		var c_eff := float(reg.get("convoy_efficiency", 0.0))
		var c_prot := float(reg.get("convoy_protection", 0.0))
		var n_mult := float(reg.get("naval_range_multiplier", 1.0))
		var reg_boost: float = c_eff + c_prot + max(0.0, n_mult - 1.0) * 0.2
		if reg_boost > 0.0:
			base_avg += reg_boost * 0.5  # additive to resistance
	return base_avg


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
