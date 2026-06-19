# scripts/data/Province.gd
class_name Province
extends Resource

#region Identity / map
@export var id: int = 0
@export var name: String = ""
@export var terrain: String = "plains"
@export var snow_potential: float = 0.0  # from layers inference, for winter snow on high elev (0-1)
@export var is_sea: bool = false
## Coastal / port access — required for shipyards and naval production.
@export var has_port: bool = false
## Map-local position (e.g. label anchor or province centroid in province space).
@export var coordinates: Vector2 = Vector2.ZERO
## Neighboring province IDs (same convention as province_adjacency.json).
@export var adjacencies: Array[int] = []
#endregion

#region Politics
@export var owner_tag: String = ""
@export var controller_tag: String = ""
@export var core_for: Array[String] = []
## Cached strategic region id (from strategic_regions.json at scenario load; 0 = unassigned).
@export var strategic_region_id: int = 0
#endregion

#region Economy & stats
@export var development_level: int = 1
@export var infrastructure: int = 1
@export var factories: int = 0
@export var population: int = 0
## Resource tag -> numeric amount (e.g. iron, coal).
@export var resources: Dictionary = {}
@export var victory_points: int = 0
#endregion

#region Modding / rules
## Feature tag -> numeric level (0 omits feature; booleans coerce to 1).
@export var special_features: Dictionary = {}
@export var tags: Array[String] = []

## Special sites (ports, airfields, special projects, fortifications, etc.)
@export var special_sites: Array[SpecialSite] = []

## Explicit built infrastructure connections (populated by player/AI decisions via projects).
## These drive the dynamic road/rail layers on the map, making it "come alive".
## Roads/rails can be added/removed/edited independently of base infrastructure level.
@export var built_road_neighbors: Array[int] = []
@export var built_rail_neighbors: Array[int] = []
#endregion

# Runtime settlement / repopulation level (0.0-1.0+). Set by GameData.apply_encourage_relocation and demographic policies.
# Boosts org recovery, lowers attrition, improves local supply feel in "our people have land" areas.
# Not persisted in base JSON (runtime + save via GameData settled_areas); dev/infra mutation is the main visible effect.
var settlement_level: float = 0.0


## Safe getter for optional WeatherManager (autoload or transient created by MapRenderer for demo/test).
## Uses main loop root to avoid any direct class reference that could trigger "call non-static on class" analyzer errors.
func _get_weather_manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	# Primary: autoload path (once added to project autoloads)
	var wm: Node = tree.root.get_node_or_null("/root/WeatherManager")
	if wm != null:
		return wm
	# Fallback: meta set by transient creator (MapRenderer)
	if tree.root.has_meta("weather_manager"):
		wm = tree.root.get_meta("weather_manager") as Node
		if wm != null:
			return wm
	# Last resort name search among root children
	for c in tree.root.get_children():
		if str(c.name) == "WeatherManager":
			return c
	return null


func get_movement_cost() -> float:
	var terrain_mult := _base_terrain_movement_multiplier()
	var infra := float(clampi(infrastructure, 0, 50))
	var dev := float(clampi(development_level, 0, 50))
	var infra_factor := 1.0 / (1.0 + infra * 0.04)
	var dev_factor := 1.0 / (1.0 + dev * 0.02)
	if is_sea:
		return terrain_mult * infra_factor
	# Factor snow from weather + snow_potential from layers (high elev get more snow penalty)
	var mult := 1.0
	var wm: Node = _get_weather_manager()
	if wm and wm.has_method("get_movement_multiplier"):
		mult = wm.get_movement_multiplier(id)
		if snow_potential > 0.2 and mult < 1.0:
			mult *= 0.9  # extra on high snow potential
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_river_border") and MapManager.has_river_border(id):
		mult *= 0.97  # river border friction (natural barrier for movement/invasion)
	return terrain_mult * infra_factor * dev_factor * mult


func resolve_has_port() -> bool:
	if is_sea:
		return false
	if has_port:
		return true
	if has_feature("port") or has_feature("harbor") or has_feature("naval_base"):
		return true
	if "port" in tags or "coastal" in tags or "harbor" in tags:
		return true
	var terrain_key := str(terrain).to_lower()
	if terrain_key in ["coastal", "coast", "harbor", "port"]:
		return true
	return false


func has_feature(feature: String) -> bool:
	return get_feature_level(feature) > 0


func get_feature_level(feature: String) -> int:
	var key := _resolved_feature_key(feature)
	if key.is_empty():
		return 0
	var v: Variant = special_features[key]
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			return int(v)
		TYPE_BOOL:
			return 1 if v else 0
		_:
			return 1


func _resolved_feature_key(feature: String) -> String:
	var needle := feature.strip_edges()
	if needle.is_empty():
		return ""
	if special_features.has(needle):
		return needle
	var lower := needle.to_lower()
	for k in special_features:
		var sk := str(k)
		if sk.to_lower() == lower:
			return sk
	return ""

# ============================================
# Gameplay Effect Getters (Deeper Combat + Supply Integration)
# ============================================

## Returns a multiplier for supply depot/throughput capacity based on infrastructure.
func get_supply_throughput_modifier() -> float:
	var infra := float(clampi(infrastructure, 0, 50))
	return 0.5 + (infra * 0.04)   # level 1 ≈ 0.54, level 10 ≈ 0.9, level 25 ≈ 1.5

## Returns a modifier for how much local supply a high-development province can generate.
	# [Combat/Agent Polish Tester] settlement_level (from relocation) and welfare_burden (from agent lobby policies) feed these getters for combat (org/attrition/supply) and map effects. Sabotage lowers infra affecting downstream. See BattleManager/Resolver for 2.5% settlement_def and loyalty(foreign_military_pct).
func get_local_supply_generation_modifier() -> float:
	var dev := float(clampi(development_level, 0, 50))
	var base := maxf(0.0, (dev - 3) * 0.03)   # Only developed provinces generate local supply
	# Settlement bonus: repopulated areas generate extra local foraging/support (our people, farms, knowledge).
	if settlement_level > 0.0:
		base += settlement_level * 0.05
	# Welfare burden integration (new controversial services): high unsustainable load reduces local supply gen (abstract "services strain the land/people").
	if typeof(GameData) != TYPE_NIL:
		var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
		var welfare := float(ps.get("welfare_burden", {}).get(owner_tag if owner_tag else "player", 0.0))
		if welfare > 10:
			base = maxf(0.0, base * (1.0 - (welfare * 0.003)))  # gradual penalty, flavorful overreach cost
	return base

## Returns a multiplier for combat width contribution from this province.
func get_combat_width_modifier() -> float:
	var infra := float(clampi(infrastructure, 0, 50))
	var dev := float(clampi(development_level, 0, 50))
	var base := (0.7 + infra * 0.02) * (0.9 + dev * 0.01)
	# NEW (roadmap): national pop * conscription directly boosts combat width (more manpower = wider fronts / depth).
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_national_manpower_width_bonus") and not owner_tag.is_empty():
		base *= (1.0 + GameData.get_national_manpower_width_bonus(owner_tag))
	return base

## Returns a modifier for organization recovery and entrenchment speed in this province.
func get_organization_recovery_modifier() -> float:
	var infra := float(clampi(infrastructure, 0, 50))
	var dev := float(clampi(development_level, 0, 50))
	var base := 0.6 + (infra * 0.025) + (dev * 0.015)
	# Settlement / repopulation bonus (from apply_encourage_relocation + demographic engineering).
	# High settlement in "our people have land/future" areas improves recovery, local support, lower effective attrition.
	if settlement_level > 0.0:
		base += settlement_level * 0.04
	# High-value loyalty/foreign military hook: National foreign troop % reduces org recovery (loyalty, integration friction, morale issues per historical analysis).
	# Ties demographics directly to combat readiness in provinces (e.g. mixed or occupied forces).
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_military_loyalty_multiplier"):
		# Use player's or local controller's loyalty as proxy; lower loyalty = penalty.
		var controller := owner_tag if owner_tag else "player"  # fallback
		var loyalty: float = GameData.get_military_loyalty_multiplier(controller)
		base *= loyalty  # e.g. 0.84 loyalty = 16% slower org recovery
	return base

## Engine tech / propulsion synergy from local resources (coal, oil, uranium, rare earths).
func get_engine_resource_bonus(engine_family: String = "") -> float:
	var res: Dictionary = resources if resources else {}
	var base: float = 0.0
	var ef: String = str(engine_family).strip_edges().to_lower()
	if "steam" in ef or "coal" in ef:
		base += float(res.get("coal", 0)) / 2000.0 * 0.15
	if "gas" in ef or "petrol" in ef or "diesel" in ef or "ic" in ef:
		base += float(res.get("oil", 0)) / 1500.0 * 0.12
		base += float(res.get("coal", 0)) / 3000.0 * 0.05
	if "nuclear" in ef or "uranium" in ef:
		base += float(res.get("uranium", res.get("rare_earths", 0))) / 500.0 * 0.25
	if "jet" in ef or "advanced" in ef or "rare" in ef:
		base += float(res.get("rare_earths", 0)) / 300.0 * 0.18
		base += float(res.get("semiconductors", 0)) / 400.0 * 0.08
	if settlement_level > 0.0:
		base *= (1.0 + settlement_level * 0.3)
	return clampf(base, 0.0, 0.35)

## Returns a modifier for reinforcement and replacement speed into this province.
func get_reinforcement_speed_modifier() -> float:
	var infra := float(clampi(infrastructure, 0, 50))
	var base := 0.4 + (infra * 0.04)
	# NEW (roadmap): pop/recruit pool directly speeds reinforce (casualties replaced faster with large trained manpower).
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_national_manpower_reinforce_mult") and not owner_tag.is_empty():
		base *= GameData.get_national_manpower_reinforce_mult(owner_tag)
	return base

## Returns a modifier for how much attrition is suffered when fighting in / moving through this province.
func get_attrition_modifier() -> float:
	var dev := float(clampi(development_level, 0, 50))
	# Higher development = better roads, hospitals, logistics = less attrition
	var base := maxf(0.6, 1.0 - (dev * 0.015))
	# Settlement / repopulation: Our settled areas have better local knowledge, hospitals, roads from repop — lower attrition.
	if settlement_level > 0.0:
		base = maxf(0.4, base - (settlement_level * 0.03))
	# Loyalty/foreign military: High foreign % increases attrition (desertion, distrust, supply friction in mixed forces).
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_military_loyalty_multiplier"):
		var controller := owner_tag if owner_tag else "player"
		var loyalty: float = GameData.get_military_loyalty_multiplier(controller)
		base /= maxf(0.7, loyalty)  # lower loyalty = higher attrition (e.g. 0.84 loyalty ~19% more attrition)
	return base

## Returns a combined "logistics quality" score for this province (used by supply & agents).
func get_logistics_quality() -> float:
	var infra := float(clampi(infrastructure, 0, 50))
	var dev := float(clampi(development_level, 0, 50))
	return (infra * 0.6) + (dev * 0.4)   # 0–100 scale roughly

## Returns a modifier for how resistant supply moving through this province is to interdiction.
## Higher development/infra = better roads, camouflage, local support = harder to interdict.
func get_interdiction_resistance_modifier() -> float:
	var infra := float(clampi(infrastructure, 0, 50))
	var dev := float(clampi(development_level, 0, 50))
	# Base 1.0, up to ~1.6 for max infra+dev
	return 1.0 + (infra * 0.008) + (dev * 0.012)

## Settlement-derived combat defense bonus (2.5% per settlement_level, cap 25%).
## "our people defend their land" flavor from relocation/settlement policies.
## Full conditional (coh/culture) in BattleManager; this is the core value for inspector display.
func get_settlement_combat_def_bonus() -> float:
	return clampf(settlement_level * 0.025, 0.0, 0.25)


# === Special Sites Helpers ===
func has_special_site_of_type(site_type: SpecialSite.SiteType) -> bool:
	for site in special_sites:
		if site != null and site.site_type == site_type and site.is_completed():
			return true
	return false


func get_special_sites_of_type(site_type: SpecialSite.SiteType) -> Array[SpecialSite]:
	var result: Array[SpecialSite] = []
	for site in special_sites:
		if site != null and site.site_type == site_type:
			result.append(site)
	return result


func add_special_site(site: SpecialSite) -> void:
	if site != null:
		special_sites.append(site)
		site.province_id = id


func _base_terrain_movement_multiplier() -> float:
	match str(terrain).to_lower():
		"urban", "metro":
			return 0.9
		"hills":
			return 1.35
		"mountains":
			return 2.15
		"desert", "jungle":
			return 1.45
		"tundra", "forest":
			return 1.25
		"marshes", "swamp":
			return 1.5
		"sea", "ocean":
			return 1.0
		"coastal":
			return 1.1
		"snow_capped":
			return 2.8
		_:
			return 1.0
