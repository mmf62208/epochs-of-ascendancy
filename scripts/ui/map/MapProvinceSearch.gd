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
	rebuild_index()


func rebuild_index() -> void:
	_rebuild_index()


func _rebuild_index() -> void:
	_names.clear()
	var sl := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	var city_layer: Dictionary = {}
	if sl != null:
		city_layer = sl.province_city_layer
		if city_layer.has("provinces") and city_layer["provinces"] is Dictionary:
			city_layer = city_layer["provinces"]
		for pid_var in sl.provinces.keys():
			_index_province(int(pid_var), sl.provinces[pid_var], city_layer)
	# MapRenderer.provinces may exist after ScenarioLoader was still empty at bind.
	if _map_renderer != null and "provinces" in _map_renderer:
		var mr_provs: Variant = _map_renderer.get("provinces")
		if mr_provs is Dictionary:
			for pid_var2 in (mr_provs as Dictionary).keys():
				_index_province(int(pid_var2), (mr_provs as Dictionary)[pid_var2], city_layer)


func _index_province(pid: int, p: Variant, city_layer: Dictionary) -> void:
	if p == null or not (p is Province):
		return
	var prov: Province = p as Province
	var key := prov.name.strip_edges().to_lower()
	if key != "":
		_names[key] = pid
	var cities = city_layer.get(str(pid), {}).get("cities", [])
	for c in cities:
		var cn := str(c.get("name", "")).strip_edges().to_lower()
		if cn != "":
			_names[cn] = pid


func _on_go_pressed() -> void:
	_on_submit(_line.text if _line != null else "")


func _on_submit(text: String) -> void:
	if _names.is_empty():
		_rebuild_index()
	var q := text.strip_edges().to_lower()
	if q == "":
		return
	var pid := _resolve_search_pid(q)
	if pid < 0:
		_rebuild_index()
		pid = _resolve_search_pid(q)
	if pid < 0:
		return
	if _map_renderer != null and _map_renderer.has_method("focus_province_by_id"):
		_map_renderer.call("focus_province_by_id", pid)
	var vp := get_viewport()
	if vp != null:
		vp.gui_release_focus()


func _resolve_search_pid(q: String) -> int:
	if q.is_empty():
		return -1
	if _names.has(q):
		return int(_names[q])
	# Prefer exact capital aliases (Berlin / Paris / Roma / Tokyo / London).
	for name_key in _names.keys():
		if str(name_key) == q:
			return int(_names[name_key])
	for name_key in _names.keys():
		var nk := str(name_key)
		if nk.begins_with(q) or q in nk:
			return int(_names[name_key])
	return -1


func select_province_by_id(pid: int) -> void:
	if _map_renderer != null and _map_renderer.has_method("focus_province_by_id"):
		_map_renderer.call("focus_province_by_id", pid)
