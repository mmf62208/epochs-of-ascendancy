class_name EquipmentModule
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var category: String = ""
@export var tier: int = 1
@export var soft_attack: float = 0.0
@export var hard_attack: float = 0.0
@export var piercing: float = 0.0
@export var air_attack: float = 0.0
@export var anti_ship: float = 0.0
@export var anti_air: float = 0.0
@export var reliability_bonus: float = 0.0
@export var reliability_penalty: float = 0.0
@export var fuel_efficiency: float = 0.0  # higher = lower fuel/supply consumption for vehicles/ships/planes
@export var speed_bonus: float = 0.0  # direct + to movement/combat speed or range
@export var power_output: float = 0.0  # hp/kw proxy for thrust/power/weight tradeoffs
@export var production_time: float = 0.0
@export var cost: Dictionary = {}
@export var special_flags: Array[String] = []
@export var description: String = ""


static func from_dict(data: Dictionary) -> EquipmentModule:
	var mod := EquipmentModule.new()
	mod.id = str(data.get("id", ""))
	mod.display_name = str(data.get("name", mod.id))
	mod.category = str(data.get("category", ""))
	mod.tier = int(data.get("tier", 1))
	mod.soft_attack = float(data.get("soft_attack", 0))
	mod.hard_attack = float(data.get("hard_attack", 0))
	mod.piercing = float(data.get("piercing", 0))
	mod.air_attack = float(data.get("air_attack", 0))
	mod.anti_ship = float(data.get("anti_ship", 0))
	mod.anti_air = float(data.get("anti_air", 0))
	mod.reliability_bonus = float(data.get("reliability_bonus", 0))
	mod.reliability_penalty = float(data.get("reliability_penalty", 0))
	mod.fuel_efficiency = float(data.get("fuel_efficiency", 0))
	mod.speed_bonus = float(data.get("speed_bonus", 0))
	mod.power_output = float(data.get("power_output", 0))
	mod.production_time = float(data.get("production_time", 0))
	mod.cost = _dict_from_variant(data.get("cost", {}))
	mod.special_flags = _string_array(data.get("special_flags", []))
	mod.description = str(data.get("description", ""))
	return mod


static func _dict_from_variant(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw.duplicate(true)


static func _string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		out.append(str(item))
	return out
