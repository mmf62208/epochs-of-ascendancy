# scripts/map/SpecialSite.gd
class_name SpecialSite
extends Resource

enum SiteType {
    PORT,
    AIRFIELD,
    NAVAL_SHIPYARD,
    FACTORY,
    OIL_REFINERY,
    ENERGY_PLANT,
    ICBM_SITE,
    RADAR_STATION,
    FLAK_BATTERY,
    MISSILE_DEFENSE,
    SPECIAL_PROJECT,      # Manhattan Project, Heavy Water, etc.
    FORTIFICATION,
    BRIDGE,               # Can be used for important bridges later
}

enum ConstructionState {
    NOT_BUILT,
    UNDER_CONSTRUCTION,
    COMPLETED,
    DAMAGED,
    DESTROYED
}

@export var id: String
@export var site_type: SiteType
@export var tier: int = 1                    # 1 = Basic, 2 = Developed, 3 = Advanced
@export var province_id: int

@export var construction_state: ConstructionState = ConstructionState.NOT_BUILT
@export var construction_progress: float = 0.0   # 0.0 to 1.0

@export var damage_level: int = 0                # 0 = undamaged, higher = more damaged
@export var max_damage_level: int = 3

@export var owner_tag: String = ""
@export var is_visible_to_owner: bool = true
@export var discovered_by: Array[String] = []    # Tags of countries that have intel on this site

# Optional: Link to infrastructure level requirement
@export var required_infra_level: int = 1

# Effects (can be expanded later)
@export var supply_bonus: float = 0.0
@export var trade_capacity: float = 0.0


func is_completed() -> bool:
    return construction_state == ConstructionState.COMPLETED


func is_under_construction() -> bool:
    return construction_state == ConstructionState.UNDER_CONSTRUCTION


func is_damaged() -> bool:
    return damage_level > 0 and construction_state != ConstructionState.DESTROYED


func get_visual_tier() -> int:
    if construction_state == ConstructionState.UNDER_CONSTRUCTION:
        return 0  # Under construction uses special visual
    if is_damaged():
        return -damage_level  # Negative = damaged variant
    return tier


func apply_damage(amount: int) -> void:
    damage_level = clamp(damage_level + amount, 0, max_damage_level)
    if damage_level >= max_damage_level:
        construction_state = ConstructionState.DAMAGED


func repair_damage(amount: int) -> void:
    damage_level = clamp(damage_level - amount, 0, max_damage_level)
    if damage_level == 0 and construction_state == ConstructionState.DAMAGED:
        construction_state = ConstructionState.COMPLETED


func start_construction() -> void:
    construction_state = ConstructionState.UNDER_CONSTRUCTION
    construction_progress = 0.0


func complete_construction() -> void:
    construction_state = ConstructionState.COMPLETED
    construction_progress = 1.0
    damage_level = 0


func get_fog_of_war_visible(for_country_tag: String) -> bool:
    if for_country_tag == owner_tag:
        return true
    return for_country_tag in discovered_by


# === Upgrade Support ===
var upgrade_target_id: String = ""   # e.g. "port_tier_2" if this is "port_tier_1"

func can_be_upgraded() -> bool:
    return is_completed() and not upgrade_target_id.is_empty() and damage_level == 0

func get_upgrade_target_id() -> String:
    return upgrade_target_id

func start_upgrade() -> void:
    if can_be_upgraded():
        construction_state = ConstructionState.UNDER_CONSTRUCTION
        construction_progress = 0.0

func complete_upgrade(new_site_data: Dictionary = {}) -> void:
    if not can_be_upgraded():
        return
    # In real usage, the caller (InfrastructureDevelopmentManager) will replace this site
    # with a new one created from upgrade_target_id
    construction_state = ConstructionState.COMPLETED
    construction_progress = 1.0
    damage_level = 0