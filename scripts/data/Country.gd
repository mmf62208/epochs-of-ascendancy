# scripts/data/Country.gd
class_name Country
extends Resource

@export var tag: String = ""
@export var name: String = ""
@export var color: Color = Color(0.5, 0.5, 0.5)
@export var capital_province_id: int = -1
## HOI-style industrial / strategic hubs for OOB station priority and mapmode.
@export var key_provinces: Array = []

# Future expansion examples:
# @export var ideology: String = ""
# @export var stability: float = 1.0
# @export var war_support: float = 0.0

func get_color() -> Color:
	return color
