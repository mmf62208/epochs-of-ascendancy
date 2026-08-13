# scripts/ui/MunitionsDeskChip.gd
## Pass 19–21: munitions production / logistics desk + stockpile sparkline.
class_name MunitionsDeskChip
extends PanelContainer

signal open_production_requested()
signal munitions_cargo_set()
signal munitions_line_assigned(line_id: String, factory_id: int)
## Pass 24: minimap munitions pips ownership filter toggled.
signal munitions_map_filter_changed(player_only: bool)
## Pass 27: occupation filter mode for munitions map/pips.
signal munitions_occupation_filter_changed(mode: String)

const HISTORY_MAX := 24
## Pass 27: map filter modes for munitions pips / mapmode emphasis.
const MAP_FILTER_MODES: Array[String] = ["mine", "all", "occupied"]

var _title: Label
var _status: Label
var _line_status: Label
var _progress: ProgressBar
var _spark: Control
var _btn_cargo: Button
var _btn_assign: Button
var _btn_prod: Button
var _btn_map_filter: Button
var _btn_occ_filter: Button
## Pass 24: minimap shows player depots only when true.
var map_pips_player_only: bool = true
## Pass 27: "mine" | "all" | "occupied" (occupied = controller≠owner only).
var map_occupation_filter: String = "all"
## Pass 21: rolling avg munitions ratio samples (0–1) for sparkline.
var _history: Array = []
var _day_connected: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280, 210)
	RetrowaveTheme.style_world_panel(self)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)
	_title = Label.new()
	_title.text = "Munitions desk"
	RetrowaveTheme.style_body_label(_title)
	_title.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	v.add_child(_title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(_status)
	_status.add_theme_font_size_override("font_size", 11)
	v.add_child(_status)
	_line_status = Label.new()
	_line_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(_line_status)
	_line_status.add_theme_font_size_override("font_size", 10)
	_line_status.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM if "TEXT_DIM" in RetrowaveTheme else Color(0.7, 0.78, 0.88))
	v.add_child(_line_status)
	# Pass 21: mini stockpile history graph.
	var graph_cap := Label.new()
	graph_cap.text = "Depot munitions · last %d samples" % HISTORY_MAX
	graph_cap.add_theme_font_size_override("font_size", 9)
	graph_cap.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9, 0.85))
	v.add_child(graph_cap)
	_spark = Control.new()
	_spark.custom_minimum_size = Vector2(0, 36)
	_spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spark.draw.connect(_on_spark_draw)
	_spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_spark)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.value = 0.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.55, 0.72, 0.98, 0.95)
	fg.set_corner_radius_all(2)
	_progress.add_theme_stylebox_override("background", bg)
	_progress.add_theme_stylebox_override("fill", fg)
	v.add_child(_progress)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	_btn_cargo = Button.new()
	_btn_cargo.text = "Ship munitions"
	_btn_cargo.focus_mode = Control.FOCUS_NONE
	_btn_cargo.custom_minimum_size = Vector2(0, 24)
	_btn_cargo.add_theme_font_size_override("font_size", 11)
	RetrowaveTheme.style_secondary_button(_btn_cargo)
	_btn_cargo.pressed.connect(_on_set_munitions_cargo)
	row.add_child(_btn_cargo)
	_btn_assign = Button.new()
	_btn_assign.text = "Assign factory"
	_btn_assign.focus_mode = Control.FOCUS_NONE
	_btn_assign.custom_minimum_size = Vector2(0, 24)
	_btn_assign.add_theme_font_size_override("font_size", 11)
	RetrowaveTheme.style_secondary_button(_btn_assign)
	_btn_assign.tooltip_text = "Create/find munitions line and assign to a free factory."
	_btn_assign.pressed.connect(_on_assign_munitions_factory)
	row.add_child(_btn_assign)
	_btn_prod = Button.new()
	_btn_prod.text = "Production"
	_btn_prod.focus_mode = Control.FOCUS_NONE
	_btn_prod.custom_minimum_size = Vector2(0, 24)
	_btn_prod.add_theme_font_size_override("font_size", 11)
	RetrowaveTheme.style_secondary_button(_btn_prod)
	_btn_prod.pressed.connect(func() -> void: open_production_requested.emit())
	row.add_child(_btn_prod)
	# Pass 24: minimap munitions pip ownership filter.
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	v.add_child(filter_row)
	_btn_map_filter = Button.new()
	_btn_map_filter.focus_mode = Control.FOCUS_NONE
	_btn_map_filter.custom_minimum_size = Vector2(0, 22)
	_btn_map_filter.add_theme_font_size_override("font_size", 10)
	_btn_map_filter.tooltip_text = "Minimap munitions pips: player-controlled (controller else owner) vs all depots."
	RetrowaveTheme.style_secondary_button(_btn_map_filter)
	_btn_map_filter.pressed.connect(_on_map_filter_toggle)
	filter_row.add_child(_btn_map_filter)
	# Pass 27: occupation filter chip.
	_btn_occ_filter = Button.new()
	_btn_occ_filter.focus_mode = Control.FOCUS_NONE
	_btn_occ_filter.custom_minimum_size = Vector2(0, 22)
	_btn_occ_filter.add_theme_font_size_override("font_size", 10)
	_btn_occ_filter.tooltip_text = (
		"Cycle munitions focus:\n• all — every depot\n• occupied — controller ≠ owner only\n• mine — player-controlled"
	)
	RetrowaveTheme.style_secondary_button(_btn_occ_filter)
	_btn_occ_filter.pressed.connect(_on_occupation_filter_cycle)
	filter_row.add_child(_btn_occ_filter)
	_sync_map_filter_btn()
	_sync_occ_filter_btn()
	_connect_day_tick()
	push_sample()
	refresh()


func _on_map_filter_toggle() -> void:
	map_pips_player_only = not map_pips_player_only
	# Keep occupation mode in sync when toggling mine/all.
	if map_pips_player_only:
		map_occupation_filter = "mine"
	elif map_occupation_filter == "mine":
		map_occupation_filter = "all"
	_sync_map_filter_btn()
	_sync_occ_filter_btn()
	munitions_map_filter_changed.emit(map_pips_player_only)
	munitions_occupation_filter_changed.emit(map_occupation_filter)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(
			"Munitions map pips · %s" % ("player only" if map_pips_player_only else "all depots")
		)


func _on_occupation_filter_cycle() -> void:
	var idx := MAP_FILTER_MODES.find(map_occupation_filter)
	if idx < 0:
		idx = 0
	idx = (idx + 1) % MAP_FILTER_MODES.size()
	map_occupation_filter = str(MAP_FILTER_MODES[idx])
	map_pips_player_only = (map_occupation_filter == "mine")
	_sync_map_filter_btn()
	_sync_occ_filter_btn()
	munitions_map_filter_changed.emit(map_pips_player_only)
	munitions_occupation_filter_changed.emit(map_occupation_filter)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Munitions filter · %s" % map_occupation_filter)


func _sync_map_filter_btn() -> void:
	if _btn_map_filter == null:
		return
	_btn_map_filter.text = "Map pips: mine" if map_pips_player_only else "Map pips: all"
	_btn_map_filter.modulate = Color(0.85, 1.05, 0.95, 1.0) if map_pips_player_only else Color(1.05, 0.95, 0.85, 1.0)


func _sync_occ_filter_btn() -> void:
	if _btn_occ_filter == null:
		return
	match map_occupation_filter:
		"occupied":
			_btn_occ_filter.text = "Focus: occupied"
			_btn_occ_filter.modulate = Color(1.1, 0.9, 0.55, 1.0)
		"mine":
			_btn_occ_filter.text = "Focus: mine"
			_btn_occ_filter.modulate = Color(0.85, 1.05, 0.95, 1.0)
		_:
			_btn_occ_filter.text = "Focus: all"
			_btn_occ_filter.modulate = Color(1, 1, 1, 1)


func _connect_day_tick() -> void:
	if _day_connected:
		return
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_signal("game_day_advanced"):
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_sample):
			TimeManager.game_day_advanced.connect(_on_game_day_sample)
		_day_connected = true


func _on_game_day_sample(_year: int = 0, _month: int = 0, _day: int = 0) -> void:
	push_sample()
	if visible:
		refresh()


## Pass 21: append current avg munitions ratio to rolling history.
func push_sample() -> void:
	var v := clampf(_avg_depot_munitions(), 0.0, 1.0)
	_history.append(v)
	while _history.size() > HISTORY_MAX:
		_history.pop_front()
	if _spark != null and is_instance_valid(_spark):
		_spark.queue_redraw()


func get_history() -> Array:
	return _history.duplicate()


func refresh() -> void:
	_connect_day_tick()
	var avg_mun := _avg_depot_munitions()
	var cargo_kind := "general"
	var mun_frac := 0.35
	if typeof(SupplyManager) != TYPE_NIL and "active_cargo" in SupplyManager:
		var cargo = SupplyManager.active_cargo
		if cargo != null:
			if "cargo_kind" in cargo:
				cargo_kind = str(cargo.cargo_kind)
			if "munitions_fraction" in cargo:
				mun_frac = float(cargo.munitions_fraction)
	_progress.value = clampf(avg_mun, 0.0, 1.0)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.55, 0.72, 0.98, 0.95).lerp(Color(0.95, 0.4, 0.35, 0.95), clampf(1.0 - avg_mun, 0.0, 1.0))
	fg.set_corner_radius_all(2)
	_progress.add_theme_stylebox_override("fill", fg)
	var trend := ""
	if _history.size() >= 2:
		var d := float(_history[_history.size() - 1]) - float(_history[_history.size() - 2])
		if d > 0.02:
			trend = " · ↑"
		elif d < -0.02:
			trend = " · ↓"
		else:
			trend = " · →"
	_status.text = "Depot munitions avg %.0f%%%s · cargo %s (%.0f%% mun)" % [
		avg_mun * 100.0, trend, cargo_kind, mun_frac * 100.0
	]
	if _line_status:
		_line_status.text = _munitions_line_status_text()
	if _btn_cargo:
		_btn_cargo.text = "Shipping munitions" if cargo_kind == "munitions" else "Ship munitions"
	if _spark != null and is_instance_valid(_spark):
		_spark.queue_redraw()


func _on_spark_draw() -> void:
	if _spark == null:
		return
	var sz := _spark.size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	# Background
	_spark.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.08, 0.12, 0.92), true)
	# Grid lines
	for i in 3:
		var gy := sz.y * float(i + 1) / 4.0
		_spark.draw_line(Vector2(0, gy), Vector2(sz.x, gy), Color(0.2, 0.25, 0.35, 0.45), 1.0)
	if _history.is_empty():
		return
	var n := _history.size()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in n:
		var t := 0.0 if n <= 1 else float(i) / float(n - 1)
		var x := t * (sz.x - 2.0) + 1.0
		var y := sz.y - 2.0 - clampf(float(_history[i]), 0.0, 1.0) * (sz.y - 4.0)
		pts.append(Vector2(x, y))
	# Area fill under line
	if pts.size() >= 2:
		var poly: PackedVector2Array = PackedVector2Array()
		for p in pts:
			poly.append(p)
		poly.append(Vector2(pts[pts.size() - 1].x, sz.y - 1.0))
		poly.append(Vector2(pts[0].x, sz.y - 1.0))
		_spark.draw_colored_polygon(poly, Color(0.35, 0.65, 0.95, 0.18))
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var mid := (float(_history[i]) + float(_history[i + 1])) * 0.5
			var col := Color(0.45, 0.85, 0.7, 0.95).lerp(Color(0.95, 0.4, 0.4, 0.95), 1.0 - mid)
			_spark.draw_line(a, b, col, 2.0)
		# Last sample marker
		var last: Vector2 = pts[pts.size() - 1]
		_spark.draw_circle(last, 2.5, Color(0.95, 0.95, 1.0, 0.95))
	elif pts.size() == 1:
		_spark.draw_circle(pts[0], 2.5, Color(0.55, 0.8, 1.0, 0.95))


func _munitions_line_status_text() -> String:
	if typeof(ProductionManager) == TYPE_NIL:
		return "No ProductionManager"
	var line_id := _find_munitions_line_id()
	if line_id.is_empty():
		return "No munitions line · Assign factory to create"
	var line = ProductionManager.get_line(line_id) if ProductionManager.has_method("get_line") else null
	if line == null:
		return "Line %s missing" % line_id
	var fid := int(line.factory_id) if "factory_id" in line else -1
	if fid > 0:
		return "Line %s → factory %d" % [line_id, fid]
	return "Line %s unassigned" % line_id


func _find_munitions_line_id() -> String:
	if typeof(ProductionManager) == TYPE_NIL or not ProductionManager.has_method("get_line_ids"):
		return ""
	var ids: Array = ProductionManager.get_line_ids()
	for id_v in ids:
		var lid := str(id_v)
		if "munition" in lid.to_lower() or "ammo" in lid.to_lower() or "shell" in lid.to_lower():
			return lid
		var line = ProductionManager.get_line(lid) if ProductionManager.has_method("get_line") else null
		if line == null:
			continue
		var did := ""
		if "design_id" in line:
			did = str(line.design_id).to_lower()
		elif "current_template_id" in line:
			did = str(line.current_template_id).to_lower()
		if "munition" in did or "ammo" in did or "shell" in did or "ordnance" in did:
			return lid
	return ""


func _avg_depot_munitions() -> float:
	if typeof(SupplyManager) == TYPE_NIL:
		return 0.0
	var sum := 0.0
	var n := 0
	if "depot_states" in SupplyManager:
		var deps: Dictionary = SupplyManager.depot_states
		for pid_v in deps.keys():
			var d = deps[pid_v]
			if d == null:
				continue
			if d.has_method("munitions_ratio"):
				sum += float(d.munitions_ratio())
				n += 1
			elif SupplyManager.has_method("get_depot_munitions_ratio"):
				var r := float(SupplyManager.get_depot_munitions_ratio(int(pid_v)))
				if r >= 0.0:
					sum += r
					n += 1
	if n <= 0:
		return 0.0
	return sum / float(n)


func _on_set_munitions_cargo() -> void:
	if typeof(SupplyManager) == TYPE_NIL:
		return
	var profile: SupplyCargoProfile = SupplyCargoProfile.munitions(500.0)
	SupplyManager.active_cargo = profile
	munitions_cargo_set.emit()
	push_sample()
	refresh()
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Active cargo → munitions (90% munitions fraction)")


## Pass 20: create/find munitions production line and assign to a free factory.
func _on_assign_munitions_factory() -> void:
	if typeof(ProductionManager) == TYPE_NIL:
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("ProductionManager unavailable")
		return
	var line_id := _find_munitions_line_id()
	if line_id.is_empty():
		line_id = "munitions_bulk_line"
		if ProductionManager.has_method("create_line"):
			var line = ProductionManager.create_line(line_id)
			if line != null:
				# Prefer munitions-ish design tags if the line supports them.
				if "design_id" in line and str(line.design_id).is_empty():
					line.design_id = "ammo_stock"
				if "current_template_id" in line and str(line.current_template_id).is_empty():
					line.current_template_id = "ammo_stock"
	var factory_id := _pick_factory_for_line(line_id)
	if factory_id <= 0:
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("No free factory for munitions line")
		refresh()
		return
	var ok := false
	if ProductionManager.has_method("assign_line_to_factory"):
		ok = bool(ProductionManager.assign_line_to_factory(line_id, factory_id))
	if ok:
		munitions_line_assigned.emit(line_id, factory_id)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Munitions line %s → factory %d" % [line_id, factory_id])
	else:
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Assign failed · line %s factory %d" % [line_id, factory_id])
	refresh()


func _pick_factory_for_line(line_id: String) -> int:
	# Prefer factories already holding this line, else first that can take more lines.
	if typeof(FactoryManager) == TYPE_NIL:
		return -1
	var player := ""
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		player = str(LeaderManager.get_player_country_tag()).to_upper()
	# Scan known line's factory first.
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("get_line"):
		var existing = ProductionManager.get_line(line_id)
		if existing != null and "factory_id" in existing and int(existing.factory_id) > 0:
			return int(existing.factory_id)
	# Walk factories if API exists.
	if FactoryManager.has_method("get_all_factory_ids"):
		var fids = FactoryManager.get_all_factory_ids()
		if fids is Array:
			for fid_v in fids:
				var fid := int(fid_v)
				var f = FactoryManager.get_factory(fid) if FactoryManager.has_method("get_factory") else null
				if f == null:
					continue
				if not player.is_empty() and "owner_tag" in f and str(f.owner_tag).to_upper() != player:
					continue
				if f.has_method("can_add_more_lines") and not bool(f.can_add_more_lines()):
					continue
				return fid
	# Fallback: try province 1–20 factories.
	if FactoryManager.has_method("get_factories_in_province"):
		for pid in range(1, 40):
			var fs = FactoryManager.get_factories_in_province(pid)
			if fs is Array and not fs.is_empty():
				var first = fs[0]
				if first is int:
					return int(first)
				if first is Object and "id" in first:
					return int(first.id)
				if first is Dictionary:
					return int(first.get("id", -1))
	return -1
