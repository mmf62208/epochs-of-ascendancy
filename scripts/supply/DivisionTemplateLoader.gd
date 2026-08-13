class_name DivisionTemplateLoader
extends RefCounted

const PATH := "res://data/formations/division_templates.json"

var divisions: Dictionary = {}
## load_all() used to re-parse JSON on every call; map unit icons walked all provinces and
## each province called get_land_divisions → load_all, freezing F5 after markers (world_full).
var _loaded: bool = false


func load_all(force: bool = false) -> void:
	if _loaded and not force and not divisions.is_empty():
		return
	divisions.clear()
	_loaded = false
	if not FileAccess.file_exists(PATH):
		push_warning("DivisionTemplateLoader: missing ", PATH)
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var raw: Variant = parser.data.get("divisions", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var div := DivisionTemplate.from_dict(entry)
		if not div.id.is_empty():
			divisions[div.id] = div
	_loaded = true


func get_division(division_id: String) -> DivisionTemplate:
	if not _loaded:
		load_all()
	return divisions.get(division_id) as DivisionTemplate


func get_all_division_ids() -> Array[String]:
	if not _loaded:
		load_all()
	var ids: Array[String] = []
	for division_id in divisions.keys():
		ids.append(str(division_id))
	ids.sort()
	return ids
