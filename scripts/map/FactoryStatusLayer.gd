# scripts/map/FactoryStatusLayer.gd
## Exception-first starved player factories: outline + missing-resource glyph.
## Node2D _draw only. Cap 24. Dirty on day tick or shortage signal — no pulse.

class_name FactoryStatusLayer
extends Node2D

const HudIcons := preload("res://scripts/ui/HudIconLibrary.gd")

@export var max_markers: int = 24
@export var marker_radius: float = 11.0

var _centroids: Dictionary = {}
var _markers: Array = []
var _glyph_tex: Dictionary = {}
var _player_tag: String = "GER"


func _ready() -> void:
	z_index = 9
	add_to_group("factory_status")
	if typeof(ProductionManager) != TYPE_NIL \
			and ProductionManager.has_signal("production_resource_shortage"):
		if not ProductionManager.production_resource_shortage.is_connected(_on_line_shortage):
			ProductionManager.production_resource_shortage.connect(_on_line_shortage)
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_signal("game_day_advanced"):
		if not TimeManager.game_day_advanced.is_connected(_on_day):
			TimeManager.game_day_advanced.connect(_on_day)


func setup(centroids: Dictionary, player_tag: String = "") -> void:
	_centroids = centroids
	var tag := player_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = _living_player_tag()
	_player_tag = tag if not tag.is_empty() else "GER"
	rebuild()


func rebuild() -> void:
	_markers = _collect_player_markers()
	queue_redraw()


func has_marker(pid: int) -> bool:
	return not get_marker(pid).is_empty()


func get_marker(pid: int) -> Dictionary:
	for row in _markers:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("pid", -1)) == pid:
			return row
	return {}


func _on_day(_year: int = 0, _month: int = 0, _day: int = 0) -> void:
	rebuild()


func _on_line_shortage(line_id: String, missing: Dictionary) -> void:
	var factory = _factory_for_line(line_id)
	if factory == null:
		rebuild()
		return
	var owner := str(factory.owner_tag).strip_edges().to_upper()
	if owner != _player_tag:
		return
	var fill := 0.0
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("preview_resource_fill_ratio"):
		fill = float(ProductionManager.preview_resource_fill_ratio(line_id, 1.0))
	var key := _worst_missing_key(missing)
	if key.is_empty():
		rebuild()
		return
	_upsert({
		"pid": int(factory.province_id),
		"missing_key": key,
		"fill_ratio": fill,
		"outline": "stopped" if fill <= 0.05 else "short",
	})
	queue_redraw()


func _collect_player_markers() -> Array:
	var out: Array = []
	if typeof(FactoryManager) == TYPE_NIL:
		return out
	var bag: Variant = FactoryManager.get("factories")
	if not (bag is Dictionary):
		return out
	for fid in (bag as Dictionary).keys():
		if out.size() >= max_markers:
			break
		var factory = FactoryManager.get_factory(int(fid)) if FactoryManager.has_method("get_factory") else null
		if factory == null:
			continue
		if str(factory.owner_tag).strip_edges().to_upper() != _player_tag:
			continue
		var lines: Array = factory.assigned_lines if "assigned_lines" in factory else []
		var best_fill := 1.0
		var best_missing: Dictionary = {}
		for lid in lines:
			var line_id := str(lid)
			if line_id.is_empty() or typeof(ProductionManager) == TYPE_NIL:
				continue
			var fill := 1.0
			if ProductionManager.has_method("preview_resource_fill_ratio"):
				fill = float(ProductionManager.preview_resource_fill_ratio(line_id, 1.0))
			if fill >= 0.999:
				continue
			var missing := _missing_for_line(line_id)
			if missing.is_empty():
				continue
			if fill < best_fill:
				best_fill = fill
				best_missing = missing
		var key := _worst_missing_key(best_missing)
		if key.is_empty():
			continue
		out.append({
			"pid": int(factory.province_id),
			"missing_key": key,
			"fill_ratio": best_fill,
			"outline": "stopped" if best_fill <= 0.05 else "short",
		})
	out.sort_custom(func(a, b): return float(a.get("fill_ratio", 1.0)) < float(b.get("fill_ratio", 1.0)))
	if out.size() > max_markers:
		out.resize(max_markers)
	return out


func _missing_for_line(line_id: String) -> Dictionary:
	if typeof(ProductionManager) == TYPE_NIL or not ProductionManager.has_method("get_line_resource_cost_for_days"):
		return {}
	var needed: Dictionary = ProductionManager.get_line_resource_cost_for_days(line_id, 1.0)
	var stock: Dictionary = {}
	var raw = ProductionManager.get("national_stockpile")
	if raw is Dictionary:
		stock = raw
	var missing: Dictionary = {}
	for resource in needed.keys():
		var req := float(needed[resource])
		var have := float(stock.get(resource, 0.0))
		if req > have + 0.001:
			missing[str(resource)] = req - have
	return missing


func _worst_missing_key(missing: Dictionary) -> String:
	if missing.is_empty():
		return ""
	for key in ["oil", "fuel", "steel", "rubber", "coal", "aluminum", "chromium", "tungsten"]:
		if float(missing.get(key, 0.0)) > 0.001:
			return "oil" if key == "fuel" else key
	for key in missing.keys():
		if float(missing[key]) > 0.001:
			var k := str(key).strip_edges().to_lower()
			return "oil" if k in ["fuel", "petroleum", "energy"] else k
	return ""


func _factory_for_line(line_id: String):
	if typeof(FactoryManager) != TYPE_NIL and FactoryManager.has_method("factory_for_line_id"):
		return FactoryManager.factory_for_line_id(line_id)
	return null


func _upsert(row: Dictionary) -> void:
	var pid := int(row.get("pid", -1))
	if pid <= 0:
		return
	for i in range(_markers.size()):
		var cur: Dictionary = _markers[i] if _markers[i] is Dictionary else {}
		if int(cur.get("pid", -1)) == pid:
			_markers[i] = row
			return
	if _markers.size() >= max_markers:
		_markers.pop_back()
	_markers.insert(0, row)


func _living_player_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		return str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	return "GER"


func _tex_for(key: String) -> Texture2D:
	var k := key.strip_edges().to_lower()
	if _glyph_tex.has(k):
		return _glyph_tex[k]
	var tex: Texture2D = HudIcons.resource_icon(k, 24)
	_glyph_tex[k] = tex
	return tex


func _draw() -> void:
	if _markers.is_empty():
		return
	for row_v in _markers:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var pid := int(row.get("pid", -1))
		if pid <= 0 or not _centroids.has(pid):
			continue
		var c: Vector2 = _centroids[pid]
		var stopped := str(row.get("outline", "")) == "stopped"
		var ring := Color(0.92, 0.22, 0.18, 0.92) if stopped else Color(0.95, 0.62, 0.12, 0.9)
		draw_arc(c, marker_radius, 0.0, TAU, 20, ring, 2.4, true)
		draw_circle(c, marker_radius - 2.5, Color(0.08, 0.08, 0.1, 0.72))
		var tex := _tex_for(str(row.get("missing_key", "oil")))
		if tex != null:
			var sz := Vector2(12, 12)
			draw_texture_rect(tex, Rect2(c - sz * 0.5, sz), false)
		else:
			draw_circle(c, 3.2, ring)
