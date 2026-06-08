# scripts/data/Province.gd
class_name Province
extends Resource

#region Identity / map
@export var id: int = 0
@export var name: String = ""
@export var terrain: String = "plains"
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


func get_movement_cost() -> float:
	var terrain_mult := _base_terrain_movement_multiplier()
	var infra := float(clampi(infrastructure, 0, 50))
	var dev := float(clampi(development_level, 0, 50))
	var infra_factor := 1.0 / (1.0 + infra * 0.04)
	var dev_factor := 1.0 / (1.0 + dev * 0.02)
	if is_sea:
		return terrain_mult * infra_factor
	return terrain_mult * infra_factor * dev_factor


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
func get_local_supply_generation_modifier() -> float:
	var dev := float(clampi(development_level, 0, 50))
	return maxf(0.0, (dev - 3) * 0.03)   # Only developed provinces generate local supply

## Returns a multiplier for combat width contribution from this province.
func get_combat_width_modifier() -> float:
	var infra := float(clampi(infrastructure, 0, 50))
	var dev := float(clampi(development_level, 0, 50))
	return (0.7 + infra * 0.02) * (0.9 + dev * 0.01)

## Returns a modifier for organization recovery and entrenchment speed in this province.
func get_organization_recovery_modifier() -> float:
	var infra := float(clampi(infrastructure, 0, 50))
	var dev := float(clampi(development_level, 0, 50))
	return 0.6 + (infra * 0.025) + (dev * 0.015)

## Returns a modifier for reinforcement and replacement speed into this province.
func get_reinforcement_speed_modifier() -> float:
	var infra := float(clampi(infrastructure, 0, 50))
	return 0.4 + (infra * 0.04)

## Returns a modifier for how much attrition is suffered when fighting in / moving through this province.
func get_attrition_modifier() -> float:
	var dev := float(clampi(development_level, 0, 50))
	# Higher development = better roads, hospitals, logistics = less attrition
	return maxf(0.6, 1.0 - (dev * 0.015))

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
		_:
			return 1.0
