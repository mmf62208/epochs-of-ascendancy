# scripts/ui/map/MapProvinceSearch.gd
## Type-ahead province / city search with camera fly-to.
extends HBoxContainer

var _map_renderer: Node = null
var _line: LineEdit = null
var _names: Dictionary = {}  # lower name -> pid


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_line = LineEdit.new()
	_line.placeholder_text = "Search province..."
	_line.custom_minimum_size = Vector2(180, 0)
	_line.text_submitted.connect(_on_submit)
	add_child(_line)

	var btn := Button.new()
	btn.text = "Go"
	btn.pressed.connect(_on_go_pressed)
	add_child(btn)


func bind(map_renderer: Node, _camera: Camera2D) -> void:
	_map_renderer = map_renderer
	_rebuild_index()


func _rebuild_index() -> void:
	_names.clear()
	var sl := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if sl == null:
		return
	var city_layer: Dictionary = sl.province_city_layer
	if city_layer.has("provinces") and city_layer["provinces"] is Dictionary:
		city_layer = city_layer["provinces"]

	for pid_var in sl.provinces.keys():
		var pid := int(pid_var)
		var p: Province = sl.provinces[pid]
		if p == null:
			continue
		var key := p.name.strip_edges().to_lower()
		if key != "":
			_names[key] = pid
		var cities = city_layer.get(str(pid), {}).get("cities", [])
		for c in cities:
			var cn := str(c.get("name", "")).strip_edges().to_lower()
			if cn != "":
				_names[cn] = pid


func _on_go_pressed() -> void:
	_on_submit(_line.text)


func _on_submit(text: String) -> void:
	var q := text.strip_edges().to_lower()
	if q == "":
		return
	var pid := -1
	if _names.has(q):
		pid = int(_names[q])
	else:
		for name_key in _names.keys():
			if q in name_key:
				pid = int(_names[name_key])
				break
	if pid < 0:
		return
	if _map_renderer != null and _map_renderer.has_method("focus_province_by_id"):
		_map_renderer.call("focus_province_by_id", pid)


func select_province_by_id(pid: int) -> void:
	if _map_renderer != null and _map_renderer.has_method("focus_province_by_id"):
		_map_renderer.call("focus_province_by_id", pid)
