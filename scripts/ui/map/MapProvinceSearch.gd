# scripts/ui/map/MapProvinceSearch.gd
## Type-ahead province / city search with camera fly-to.
extends HBoxContainer

const IX1_HUB_ID := 710417
const IX1_BONN_ID := 710416
const IX1_LEVERKUSEN_ID := 710418
const LINE_NAME := "SearchLineEdit"
const GO_NAME := "SearchGoButton"
const SUBMIT_GUARD_MS := 180
## Live Search must resolve Köln / Cologne / Koln / Koeln to the Rhineland hub.
const SEARCH_ALIASES := {
	"cologne": IX1_HUB_ID,
	"koln": IX1_HUB_ID,
	"koeln": IX1_HUB_ID,
	"köln": IX1_HUB_ID,
	"bonn": IX1_BONN_ID,
	"leverkusen": IX1_LEVERKUSEN_ID,
	"berlin": 710300,
	"paris": 710707,
	"roma": 710963,
	"rome": 710963,
	"tokyo": 903995,
	"london": 711414,
}

var _map_renderer: Node = null
var _line: LineEdit = null
var _go: Button = null
var _names: Dictionary = {}  # lower / folded name -> pid
var _folded_names: Dictionary = {}  # ascii-folded key -> pid
var _submit_guard_msec: int = 0
var _last_live_submit_pid: int = -1


func _ready() -> void:
	ensure_chrome_visible()


func _input(event: InputEvent) -> void:
	# Enter after living title / +6d: LineEdit text_submitted can no-op if focus is stale.
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	if _line == null or not is_instance_valid(_line):
		return
	if not _line.has_focus() and not _search_owns_focus():
		return
	_on_submit(_line.text)
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func bind(map_renderer: Node, _camera: Camera2D) -> void:
	_map_renderer = map_renderer
	ensure_chrome_visible()
	rebuild_index()


func rebuild_index() -> void:
	_rebuild_index()


static func fold_search_key(s: String) -> String:
	## NFC/NFD + ASCII fallback so live "Koln" / "Köln" / "Cologne" all hit 710417.
	var t: String = s.strip_edges().to_lower()
	t = t.replace("ö", "o").replace("ä", "a").replace("ü", "u").replace("ß", "ss")
	t = t.replace("é", "e").replace("è", "e").replace("ê", "e").replace("ë", "e")
	t = t.replace("á", "a").replace("à", "a").replace("â", "a")
	t = t.replace("í", "i").replace("ì", "i").replace("î", "i")
	t = t.replace("ó", "o").replace("ò", "o").replace("ô", "o")
	t = t.replace("ú", "u").replace("ù", "u").replace("û", "u")
	t = t.replace("ç", "c").replace("ñ", "n").replace("ø", "o")
	t = t.replace("\u0308", "").replace("\u0301", "").replace("\u0300", "").replace("\u0302", "")
	return t


func ensure_chrome_visible() -> void:
	## Stay-alive / hatch: LineEdit+Go must stay on-screen and focusable.
	## Play 8f89145: Search on WorldMap UI layer 20 + TOP_RIGHT + 0-height
	## LineEdit was missing after past7 while Map Mode ate the top-right.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	modulate = Color(1, 1, 1, 1)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	z_as_relative = false
	custom_minimum_size = Vector2(308, 32)
	add_theme_constant_override("separation", 6)
	_ensure_live_controls()
	if _line != null:
		_style_search_line(_line)
	if _go != null:
		_style_search_go(_go)


func _ensure_live_controls() -> void:
	if _line == null or not is_instance_valid(_line):
		_line = get_node_or_null(LINE_NAME) as LineEdit
	if _line == null:
		_line = LineEdit.new()
		_line.name = LINE_NAME
		add_child(_line)
	_line.placeholder_text = "Search province..."
	_style_search_line(_line)
	if not _line.text_submitted.is_connected(_on_submit):
		_line.text_submitted.connect(_on_submit)
	if not _line.gui_input.is_connected(_on_line_gui_input):
		_line.gui_input.connect(_on_line_gui_input)

	if _go == null or not is_instance_valid(_go):
		_go = get_node_or_null(GO_NAME) as Button
	if _go == null:
		_go = Button.new()
		_go.name = GO_NAME
		add_child(_go)
	_go.text = "Go"
	_style_search_go(_go)
	# Press-on-down so leftover map-pan / pick-block cannot eat button-up.
	_go.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	if not _go.pressed.is_connected(_on_go_pressed):
		_go.pressed.connect(_on_go_pressed)
	if not _go.button_down.is_connected(_on_go_pressed):
		_go.button_down.connect(_on_go_pressed)
	if not _go.gui_input.is_connected(_on_go_gui_input):
		_go.gui_input.connect(_on_go_gui_input)


func _style_search_line(line: LineEdit) -> void:
	line.process_mode = Node.PROCESS_MODE_ALWAYS
	line.visible = true
	line.modulate = Color(1, 1, 1, 1)
	line.custom_minimum_size = Vector2(180, 28)
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	line.focus_mode = Control.FOCUS_ALL
	line.editable = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.16, 0.96)
	sb.border_color = Color(0.2, 0.9, 1, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	line.add_theme_stylebox_override("normal", sb)
	line.add_theme_stylebox_override("focus", sb)
	line.add_theme_color_override("font_color", Color(0.95, 0.96, 1, 1))
	line.add_theme_color_override("font_placeholder_color", Color(0.7, 0.78, 0.9, 0.85))


func _style_search_go(btn: Button) -> void:
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.visible = true
	btn.modulate = Color(1, 1, 1, 1)
	btn.custom_minimum_size = Vector2(48, 28)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.focus_mode = Control.FOCUS_ALL


func _search_owns_focus() -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var fo: Control = vp.gui_get_focus_owner()
	if fo == null:
		return false
	return fo == _line or fo == _go or is_ancestor_of(fo)


func _on_line_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	_on_submit(_line.text if _line != null else "")
	accept_event()


func _on_go_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_on_go_pressed()
	accept_event()


func _rebuild_index() -> void:
	_names.clear()
	_folded_names.clear()
	var sl: Node = get_node_or_null("/root/ScenarioLoader")
	var city_layer: Dictionary = {}
	if sl != null:
		if "province_city_layer" in sl:
			var raw_city: Variant = sl.get("province_city_layer")
			if raw_city is Dictionary:
				city_layer = raw_city
		if city_layer.has("provinces") and city_layer["provinces"] is Dictionary:
			city_layer = city_layer["provinces"]
		if "provinces" in sl:
			var sl_provs: Variant = sl.get("provinces")
			if sl_provs is Dictionary:
				for pid_var in (sl_provs as Dictionary).keys():
					_index_province(int(pid_var), (sl_provs as Dictionary)[pid_var], city_layer)
	# MapRenderer.provinces may exist after ScenarioLoader was still empty at bind.
	if _map_renderer != null and "provinces" in _map_renderer:
		var mr_provs: Variant = _map_renderer.get("provinces")
		if mr_provs is Dictionary:
			for pid_var2 in (mr_provs as Dictionary).keys():
				_index_province(int(pid_var2), (mr_provs as Dictionary)[pid_var2], city_layer)
	# City-layer rows can exist even when a Province object is late.
	for city_key in city_layer.keys():
		_index_city_entry(int(str(city_key)), city_layer.get(city_key))
	for alias_key in SEARCH_ALIASES.keys():
		_index_name(str(alias_key), int(SEARCH_ALIASES[alias_key]))


func _index_province(pid: int, p: Variant, city_layer: Dictionary) -> void:
	if p == null or not (p is Object):
		return
	var obj: Object = p as Object
	if "name" in obj:
		_index_name(str(obj.get("name")), pid)
	_index_name(str(pid), pid)
	var entry: Variant = city_layer.get(str(pid), {})
	_index_city_entry(pid, entry)


func _index_city_entry(pid: int, entry: Variant) -> void:
	if pid < 0 or not (entry is Dictionary):
		return
	var ed: Dictionary = entry
	_index_name(str(ed.get("city_name", "")), pid)
	var cities: Variant = ed.get("cities", [])
	if cities is Array:
		for c in cities:
			if c is Dictionary:
				_index_name(str((c as Dictionary).get("name", "")), pid)
			else:
				_index_name(str(c), pid)


func _index_name(raw: String, pid: int) -> void:
	var key: String = raw.strip_edges().to_lower()
	if key == "":
		return
	_names[key] = pid
	var folded: String = fold_search_key(key)
	if folded != "":
		_folded_names[folded] = pid
		if folded != key:
			_names[folded] = pid


func _on_go_pressed() -> void:
	_ensure_live_controls()
	_on_submit(_line.text if _line != null else "")


func _on_submit(text: String) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _submit_guard_msec < SUBMIT_GUARD_MS:
		return
	_submit_guard_msec = now
	_ensure_live_controls()
	if _names.is_empty():
		_rebuild_index()
	var pid: int = resolve_search_query(text)
	if pid < 0:
		_rebuild_index()
		pid = resolve_search_query(text)
	_last_live_submit_pid = pid
	if pid < 0:
		_toast_search_miss(text)
		return
	_go_to_province(pid)


func submit_from_live_ui(text: String) -> int:
	## Same path the live LineEdit Enter / Go button use (not resolve-only).
	_ensure_live_controls()
	if _line != null:
		_line.text = text
	_submit_guard_msec = 0
	_on_submit(text)
	return _last_live_submit_pid


func press_go_button() -> int:
	_ensure_live_controls()
	_submit_guard_msec = 0
	_on_go_pressed()
	return _last_live_submit_pid


func get_search_line() -> LineEdit:
	_ensure_live_controls()
	return _line


func get_go_button() -> Button:
	_ensure_live_controls()
	return _go


func last_live_submit_pid() -> int:
	return _last_live_submit_pid


func resolve_search_query(text: String) -> int:
	return _resolve_search_pid(fold_search_key(text) if text.strip_edges() != "" else "")


func _resolve_search_pid(q: String) -> int:
	var raw: String = q.strip_edges().to_lower()
	if raw.is_empty():
		return -1
	var folded: String = fold_search_key(raw)
	if raw.is_valid_int():
		var as_pid: int = int(raw)
		if as_pid == IX1_HUB_ID or as_pid == IX1_BONN_ID or as_pid == IX1_LEVERKUSEN_ID:
			return as_pid
		if _names.values().has(as_pid) or _folded_names.values().has(as_pid):
			return as_pid
	if SEARCH_ALIASES.has(raw):
		return int(SEARCH_ALIASES[raw])
	if SEARCH_ALIASES.has(folded):
		return int(SEARCH_ALIASES[folded])
	if _names.has(raw):
		return int(_names[raw])
	if _names.has(folded):
		return int(_names[folded])
	if _folded_names.has(folded):
		return int(_folded_names[folded])
	# Prefer exact capital / IX-1 aliases (Berlin / Paris / Köln / Cologne).
	for alias_key in SEARCH_ALIASES.keys():
		var ak: String = str(alias_key)
		if (ak.begins_with(raw) or fold_search_key(ak).begins_with(folded)) and folded.length() >= 3:
			return int(SEARCH_ALIASES[alias_key])
	var prefix_pid: int = -1
	for name_key in _names.keys():
		var nk: String = str(name_key)
		var fk: String = fold_search_key(nk)
		if nk.begins_with(raw) or fk.begins_with(folded):
			return int(_names[name_key])
		if prefix_pid < 0 and (raw in nk or folded in fk):
			prefix_pid = int(_names[name_key])
	if prefix_pid >= 0:
		return prefix_pid
	for fold_key in _folded_names.keys():
		var fk2: String = str(fold_key)
		if fk2.begins_with(folded) or folded in fk2:
			return int(_folded_names[fold_key])
	return -1


func _resolve_map_renderer() -> Node:
	if _map_renderer != null and is_instance_valid(_map_renderer):
		return _map_renderer
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var mr: Node = tree.get_first_node_in_group("map_renderer")
	if mr == null and tree.current_scene != null:
		mr = tree.current_scene.find_child("MapRenderer", true, false)
	if mr != null:
		_map_renderer = mr
	return _map_renderer


func _go_to_province(pid: int) -> void:
	var mr: Node = _resolve_map_renderer()
	var opened: bool = false
	if mr != null and mr.has_method("open_province_inspector_from_search"):
		opened = bool(mr.call("open_province_inspector_from_search", pid))
	elif mr != null and mr.has_method("focus_province_by_id"):
		opened = bool(mr.call("focus_province_by_id", pid, "soft"))
	if not opened:
		if mr == null:
			_toast_search_unbound(pid)
		else:
			_toast_inspector_failed(pid)
	var vp := get_viewport()
	if vp != null:
		vp.gui_release_focus()


func _toast_search_miss(text: String) -> void:
	var q: String = text.strip_edges()
	var msg: String = "No province match — type a name, then Go" if q == "" else "No province match for '%s'" % q
	_emit_search_toast(msg, true)
	var vp := get_viewport()
	if vp != null:
		vp.gui_release_focus()


func _toast_inspector_failed(pid: int) -> void:
	_emit_search_toast("Search found %d but province inspector did not open" % pid, true)


func _toast_search_unbound(pid: int) -> void:
	_emit_search_toast("Search is not bound to the map (pid %d)" % pid, true)


func _emit_search_toast(msg: String, is_error: bool) -> void:
	var mr: Node = _resolve_map_renderer()
	if mr != null and mr.has_method("_show_inspector_toast"):
		mr.call("_show_inspector_toast", msg, 2.4, is_error)
	elif typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(msg, 2.4, is_error)


func select_province_by_id(pid: int) -> void:
	_go_to_province(pid)
