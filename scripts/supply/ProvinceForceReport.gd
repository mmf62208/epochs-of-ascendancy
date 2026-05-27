class_name ProvinceForceReport
extends RefCounted

var province_id: int = -1
var land_by_tag: Dictionary = {}
var air_by_tag: Dictionary = {}
var naval_by_tag: Dictionary = {}
var naval_at_port_by_tag: Dictionary = {}
## Engineer / combat-engineer brigade equivalents (friendly repair crews).
var engineers_by_tag: Dictionary = {}


func _init(p_province_id: int = -1) -> void:
	province_id = p_province_id


func add_land(tag: String, amount: float) -> void:
	land_by_tag[tag] = float(land_by_tag.get(tag, 0.0)) + amount


func add_air(tag: String, amount: float) -> void:
	air_by_tag[tag] = float(air_by_tag.get(tag, 0.0)) + amount


func add_naval(tag: String, amount: float, at_port: bool) -> void:
	naval_by_tag[tag] = float(naval_by_tag.get(tag, 0.0)) + amount
	if at_port:
		naval_at_port_by_tag[tag] = float(naval_at_port_by_tag.get(tag, 0.0)) + amount


func total_land(tag: String) -> float:
	return float(land_by_tag.get(tag, 0.0))


func total_air(tag: String) -> float:
	return float(air_by_tag.get(tag, 0.0))


func total_naval_at_port(tag: String) -> float:
	return float(naval_at_port_by_tag.get(tag, 0.0))


func add_engineers(tag: String, brigade_equiv: float) -> void:
	if brigade_equiv <= 0.0:
		return
	engineers_by_tag[tag] = float(engineers_by_tag.get(tag, 0.0)) + brigade_equiv


func total_engineers(tag: String) -> float:
	return float(engineers_by_tag.get(tag.strip_edges().to_upper(), 0.0))


func set_engineers(tag: String, amount: float) -> void:
	var t := tag.strip_edges().to_upper()
	if amount <= 0.001:
		engineers_by_tag.erase(t)
	else:
		engineers_by_tag[t] = amount
