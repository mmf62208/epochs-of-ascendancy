# scripts/map/ProvinceEditor.gd
class_name ProvinceEditor
extends Node2D

## In-Game Province Editor Tool
##
## Allows designers and modders to draw, edit, and iterate on provinces directly on the map
## using the real camera, zoom, and visual style.
##
## See full design: docs/PROVINCE_EDITOR_IN_GAME_DESIGN.md
##
## Philosophy:
## - Blank / clean parchment base map first (rivers & mountains clearly visible).
## - Live Polygon2D previews.
## - Smart assistance for realistic borders.
## - Full roundtrip to the layered JSON format (provinces_geometry + base + historical variants).
## - Integrated into DebugOverlay for easy access during development.

signal province_created(province_id: int, points: PackedVector2Array)
signal province_edited(province_id: int)
signal provinces_exported(export_path: String)

# Editor state
var _is_active: bool = false
var _current_points: PackedVector2Array = []
var _editor_provinces: Dictionary = {}   # temp_id -> { "id": int, "points": PackedVector2Array, "attrs": Dictionary, "preview_node": Polygon2D }
var _next_temp_id: int = 90000

var _selected_prov_id: int = -1
var _dragging_vertex_index: int = -1
var _last_mouse_world: Vector2 = Vector2.ZERO

var snap_enabled: bool = true
var snap_distance: float = 30.0  # world units for snap
var grid_snap_enabled: bool = false
var grid_size: float = 50.0
var pop_snap_enabled: bool = true  # snap to high pop centers / strategic points
var _river_polylines: Array = []  # Array of PackedVector2Array for river/coast segments, for snap
var river_snap_enabled: bool = true

# Visuals (live previews)
var _preview_layer: Node2D = null
var _current_preview_poly: Polygon2D = null
var _vertex_markers: Array[Node] = []

# References
var map_renderer: Node = null
var map_manager: Node = null

# Simple attribute defaults (expand in UI)
var _default_attrs := {
	"terrain": "plains",
	"is_sea": false,
	"has_port": false,
	"development_level": 1,
	"infrastructure": 1,
	"population": 100000,
	"victory_points": 0,
	"tags": [],
	"historical_variants": []
}

const EDITOR_OUTLINE_NODE := "EditorOutline"

const EDITOR_FILL_DEFAULT := Color(0.3, 0.8, 0.4, 0.18)
const EDITOR_OUTLINE_DEFAULT := Color(0.2, 0.6, 0.3, 0.95)
const EDITOR_OUTLINE_WIDTH_DEFAULT := 2.5

func _style_editor_polygon(
	poly: Polygon2D,
	fill: Color,
	outline: Color,
	outline_width: float = EDITOR_OUTLINE_WIDTH_DEFAULT,
) -> void:
	poly.color = fill
	ProvinceMapVisuals.ensure_outline(
		poly, poly.polygon, EDITOR_OUTLINE_NODE, outline, outline_width, 2
	)


func _sync_editor_polygon_outline(
	poly: Polygon2D,
	outline: Color = EDITOR_OUTLINE_DEFAULT,
	outline_width: float = EDITOR_OUTLINE_WIDTH_DEFAULT,
) -> void:
	if poly == null:
		return
	ProvinceMapVisuals.ensure_outline(
		poly, poly.polygon, EDITOR_OUTLINE_NODE, outline, outline_width, 2
	)


func _tags_from_variant(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for item in raw:
			var s := str(item).strip_edges()
			if not s.is_empty():
				out.append(s)
	return out

func _ready() -> void:
	name = "ProvinceEditor"
	add_to_group("province_editor")
	_create_preview_layer()
	load_rivers_for_snap()  # load once for snap support
	# Will be activated from DebugOverlay

func _create_preview_layer() -> void:
	_preview_layer = Node2D.new()
	_preview_layer.name = "EditorPreviewLayer"
	_preview_layer.z_index = 50   # Above normal provinces but below UI
	add_child(_preview_layer)

func set_active(active: bool) -> void:
	_is_active = active
	visible = active
	if not active:
		_clear_current_drawing()
	print("ProvinceEditor: ", "ACTIVE (draw on the clean base map)" if active else "inactive")

func is_active() -> bool:
	return _is_active

# === INPUT (called from DebugOverlay._input or a dedicated input handler when active) ===
func handle_map_input(event: InputEvent) -> bool:
	if not _is_active:
		return false

	var world_pos := _screen_to_world(event.position) if event is InputEventMouse else Vector2.ZERO
	_last_mouse_world = world_pos

	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				# Try to start drag on nearest vertex of selected or current
				if _try_start_drag(world_pos):
					return true
				_add_vertex(world_pos)
				return true

			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_finish_current_province()
				return true
		else:
			# Release drag
			if _dragging_vertex_index >= 0:
				_stop_drag()
				return true

	if event is InputEventMouseMotion:
		if _dragging_vertex_index >= 0:
			_update_drag(world_pos)
			return true

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _dragging_vertex_index >= 0:
			_stop_drag()
		else:
			_clear_current_drawing()
		return true

	return false

func _try_start_drag(world_pos: Vector2) -> bool:
	# Check current drawing first
	if _current_points.size() > 0:
		var idx := _find_nearest_vertex_index(_current_points, world_pos, 25.0)
		if idx >= 0:
			_dragging_vertex_index = idx
			_selected_prov_id = -1
			return true

	# Check selected existing province
	if _selected_prov_id >= 0 and _editor_provinces.has(_selected_prov_id):
		var data: Dictionary = _editor_provinces[_selected_prov_id]
		var pts: PackedVector2Array = data["points"]
		var idx := _find_nearest_vertex_index(pts, world_pos, 25.0)
		if idx >= 0:
			_dragging_vertex_index = idx
			return true

	return false

func _find_nearest_vertex_index(pts: PackedVector2Array, pos: Vector2, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist
	for i in pts.size():
		var d := pts[i].distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best

func _update_drag(world_pos: Vector2) -> void:
	if _dragging_vertex_index < 0:
		return
	if _selected_prov_id >= 0 and _editor_provinces.has(_selected_prov_id):
		var data: Dictionary = _editor_provinces[_selected_prov_id]
		var pts: PackedVector2Array = data["points"]
		if _dragging_vertex_index < pts.size():
			pts[_dragging_vertex_index] = world_pos
			data["points"] = pts
			# Update preview
			if data.has("preview_node") and is_instance_valid(data["preview_node"]):
				var preview_poly := data["preview_node"] as Polygon2D
				preview_poly.polygon = pts
				_sync_editor_polygon_outline(preview_poly)
	elif _current_points.size() > 0 and _dragging_vertex_index < _current_points.size():
		_current_points[_dragging_vertex_index] = world_pos
		_update_live_preview()

func _stop_drag() -> void:
	_dragging_vertex_index = -1
	# Could trigger province_edited signal here for the selected one

func select_province_for_edit(temp_id: int) -> void:
	_selected_prov_id = temp_id
	_clear_current_drawing()
	print("ProvinceEditor: Selected province ", temp_id, " for editing. Drag vertices with LMB.")

func add_historical_variant(temp_id: int, year: int, changes: Dictionary) -> void:
	"""Stub for historical variants support (full in design doc)."""
	if temp_id in _editor_provinces:
		var data: Dictionary = _editor_provinces[temp_id]
		var vars = data["attrs"].setdefault("historical_variants", [])
		vars.append({"year": year, "changes": changes})
		print("ProvinceEditor: Added variant for year", year, "to", temp_id)
		# In full: export will include them, ScenarioLoader can apply per era.

func highlight_conflicts(temp_id: int = -1) -> void:
	# Visual conflict layer aid: temporarily highlight conflicting provinces in red.
	# Called from Debug list for per-province, or global.
	if temp_id >= 0 and _editor_provinces.has(temp_id):
		var data: Dictionary = _editor_provinces[temp_id]
		if data.has("preview_node") and is_instance_valid(data["preview_node"]):
			var p := data["preview_node"] as Polygon2D
			p.color = Color(1, 0, 0, 0.4)
			_sync_editor_polygon_outline(p, Color(1, 0, 0, 1), 2.0)
			# reset after time? for now, user clears.
	else:
		# global
		for tid in _editor_provinces:
			highlight_conflicts(tid)

## Snap to nearest feature (current map province edges as proxy for rivers/coasts/natural borders).
## Human can disable snap or drag to override after snap.
func snap_to_nearest_feature(pos: Vector2) -> Vector2:
	var snapped := pos
	if grid_snap_enabled:
		snapped.x = round(snapped.x / grid_size) * grid_size
		snapped.y = round(snapped.y / grid_size) * grid_size
	if not snap_enabled or typeof(MapManager) == TYPE_NIL:
		if pop_snap_enabled:
			snapped = _snap_to_pop(snapped)
		return snapped

	var best_pos := snapped
	var best_dist := snap_distance

	# Use current geometry (includes base + any temp editor)
	var geo_dict = MapManager._geometry if MapManager.has("_geometry") else {}
	for pid in geo_dict:
		var g: Dictionary = geo_dict[pid]
		var pts: PackedVector2Array = g.get("points", PackedVector2Array())
		if pts.size() < 2:
			continue
		for i in range(pts.size()):
			var p1: Vector2 = pts[i]
			var p2: Vector2 = pts[(i+1) % pts.size()]
			var proj := _project_point_on_segment(snapped, p1, p2)
			var d := snapped.distance_to(proj)
			if d < best_dist:
				best_dist = d
				best_pos = proj

	if pop_snap_enabled:
		best_pos = _snap_to_pop(best_pos)

	if river_snap_enabled and not _river_polylines.is_empty():
		best_pos = _snap_to_rivers(best_pos)

	return best_pos

func _snap_to_pop(pos: Vector2) -> Vector2:
	var best := pos
	var best_d := 1000.0
	if typeof(MapManager) != TYPE_NIL:
		for pid in MapManager._provinces:
			var p: Province = MapManager._provinces[pid]
			if p.population > 200000:
				var d := pos.distance_to(p.coordinates)
				if d < best_d:
					best_d = d
					best = p.coordinates
	for tid in _editor_provinces:
		var edata = _editor_provinces[tid]
		var epts = edata.get("points", PackedVector2Array())
		if epts.size() > 0:
			var cx = 0.0; var cy = 0.0
			for pt in epts: cx += pt.x; cy += pt.y
			var ecent = Vector2(cx / epts.size(), cy / epts.size())
			var d := pos.distance_to(ecent)
			if d < best_d:
				best_d = d
				best = ecent
	return best

## Load river/coast polylines for snap (from data/map/rivers.json or editor export).
## If not present, uses province geometry edges as proxy (as before).
## Call from Debug or auto on editor activate.
## Supports world chunks: if rivers_path is default and a world chunk underlay is active (via MapRenderer bg tex), auto-loads the per-chunk rivers.json for localized snap in that theater portion.
func load_rivers_for_snap(rivers_path: String = "res://data/map/rivers.json") -> void:
	# For world-scale editing you can pass "res://data/map/rivers_world.json" (or the region specific one).
	_river_polylines.clear()
	var effective_path := rivers_path
	# Auto-detect chunk for portion editing (when MapRenderer has swapped to world_chunk underlay)
	if rivers_path == "res://data/map/rivers.json" or rivers_path.ends_with("rivers.json"):
		var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
		if mr and mr.has_method("find_child"):
			var bg := mr.find_child("WorldBackground", true, false) as Sprite2D
			if bg and bg.texture and "world_chunk" in str(bg.texture.resource_path):
				var chunk_str := str(bg.texture.resource_path)
				var idx_str := chunk_str.get_slice("_", 2)
				if idx_str.is_valid_int():
					var cpath := "res://assets/maps/world_chunks/world_chunk_%02d_rivers.json" % idx_str.to_int()
					if FileAccess.file_exists(cpath):
						effective_path = cpath
						print("ProvinceEditor: Detected chunk underlay, using per-chunk rivers for snap: ", cpath)
	_load_rivers_from_path(effective_path)
	# Fallback: add some province edges as "rivers" if no data (proxy for natural borders)
	if _river_polylines.is_empty() and typeof(MapManager) != TYPE_NIL:
		for pid in MapManager._geometry:
			var g: Dictionary = MapManager._geometry[pid]
			var pts: PackedVector2Array = g.get("points", PackedVector2Array())
			if pts.size() > 3:  # add every other edge as proxy
				for i in range(0, pts.size(), 2):
					var p1: Vector2 = pts[i]
					var p2: Vector2 = pts[(i+1) % pts.size()]
					_river_polylines.append(PackedVector2Array([p1, p2]))

func _load_rivers_from_path(path: String) -> void:
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var txt := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("rivers"):
			for r in (parsed as Dictionary)["rivers"]:
				if r is Array:
					var line := PackedVector2Array()
					for pt in r:
						if pt is Array and pt.size() >= 2:
							line.append(Vector2(float(pt[0]), float(pt[1])))
					if line.size() > 1:
						_river_polylines.append(line)
			print("ProvinceEditor: Loaded ", _river_polylines.size(), " river polylines for snap from ", path)
		else:
			print("ProvinceEditor: No valid rivers in ", path, " - using geometry proxy.")
	else:
		print("ProvinceEditor: No rivers.json at ", path, " - river snap will use province edges as terrain boundaries.")

## Public helper for explicit chunk (e.g. called after debug chunk load).
func load_chunk_rivers_for_snap(chunk_index: int) -> void:
	var cpath := "res://assets/maps/world_chunks/world_chunk_%02d_rivers.json" % chunk_index
	load_rivers_for_snap(cpath)  # will use the chunk one, or fallback logic if missing

func _snap_to_rivers(pos: Vector2) -> Vector2:
	var best := pos
	var best_d := 1000.0
	for line in _river_polylines:
		if line.size() < 2: continue
		for i in range(line.size()-1):
			var p1: Vector2 = line[i]
			var p2: Vector2 = line[i+1]
			var proj := _project_point_on_segment(pos, p1, p2)
			var d := pos.distance_to(proj)
			if d < best_d:
				best_d = d
				best = proj
	return best

## Auto-suggest full border continuation: from current points, snap additional points along features to help close a polygon.
## Human can then drag/override. Aids drawing natural borders.
func auto_suggest_border(num_points: int = 4) -> void:
	if _current_points.size() < 1:
		return
	var last := _current_points[-1]
	var dir := Vector2(randf_range(-1,1), randf_range(-1,1)).normalized() * 80.0  # rough direction
	for i in range(num_points):
		var candidate := last + dir * (i+1)
		var snapped := snap_to_nearest_feature(candidate)
		_current_points.append(snapped)
		last = snapped
	_update_live_preview()
	# Optional auto-close if close to start
	if _current_points.size() > 5:
		var dist := _current_points[-1].distance_to(_current_points[0])
		if dist < 50.0:
			_finish_current_province()

func _project_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var ap := p - a
	var len2 := ab.length_squared()
	if len2 == 0:
		return a
	var t := clampf(ap.dot(ab) / len2, 0.0, 1.0)
	return a + ab * t

func toggle_snap(enabled: bool = true) -> void:
	snap_enabled = enabled
	print("ProvinceEditor: Snap to features ", "ENABLED" if enabled else "DISABLED")

## Persistent save/load for editor session (user:// for in-game persistence, separate from export JSON for pipeline).
## Allows saving drawn provinces across game sessions or reloads, with human override via clear/edit.
func save_session(path: String = "user://editor_provinces_save.json") -> void:
	var data: Dictionary = {}
	for tid in _editor_provinces:
		var d: Dictionary = _editor_provinces[tid]
		data[str(tid)] = {
			"points": _packed_vec2_to_array(d["points"]),
			"attrs": d.get("attrs", {}).duplicate(true)
		}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		print("ProvinceEditor: Saved session to ", path)

func load_session(path: String = "user://editor_provinces_save.json") -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	# Clear current previews and data
	_clear_all_previews()
	_editor_provinces.clear()
	for tid_str in parsed:
		var tid := int(tid_str)
		var entry: Dictionary = parsed[tid_str]
		var pts := _array_to_packed_vec2(entry.get("points", []))
		var attrs: Dictionary = entry.get("attrs", {}).duplicate(true)
		# Recreate preview
		var preview := Polygon2D.new()
		preview.polygon = pts
		_style_editor_polygon(preview, EDITOR_FILL_DEFAULT, EDITOR_OUTLINE_DEFAULT)
		_preview_layer.add_child(preview)
		_editor_provinces[tid] = {
			"id": tid,
			"points": pts,
			"attrs": attrs,
			"preview_node": preview
		}
	print("ProvinceEditor: Loaded session from ", path, " (", _editor_provinces.size(), " provinces)")

func _clear_all_previews() -> void:
	for ch in _preview_layer.get_children():
		ch.queue_free()

func _packed_vec2_to_array(pts: PackedVector2Array) -> Array:
	var out := []
	for p in pts:
		out.append([p.x, p.y])
	return out

func _array_to_packed_vec2(arr: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for item in arr:
		if item is Array and item.size() >= 2:
			pts.append(Vector2(float(item[0]), float(item[1])))
	return pts

## For SaveLoadManager integration (debug tool persistence in full saves).
## Saves the current editor provinces so drawn borders survive game save/load.
func get_save_data() -> Dictionary:
	var editor_data := {}
	for tid in _editor_provinces:
		var d: Dictionary = _editor_provinces[tid]
		editor_data[str(tid)] = {
			"points": _packed_vec2_to_array(d["points"]),
			"attrs": d.get("attrs", {}).duplicate(true)
		}
	return {"editor_provinces": editor_data, "version": 1}

func apply_save_data(data: Dictionary) -> void:
	if not data.has("editor_provinces"):
		return
	var editor_data: Dictionary = data["editor_provinces"]
	_clear_all_previews()
	_editor_provinces.clear()
	for tid_str in editor_data:
		var tid := int(tid_str)
		var entry: Dictionary = editor_data[tid_str]
		var pts := _array_to_packed_vec2(entry.get("points", []))
		var attrs: Dictionary = entry.get("attrs", {}).duplicate(true)
		var preview := Polygon2D.new()
		preview.polygon = pts
		_style_editor_polygon(preview, EDITOR_FILL_DEFAULT, EDITOR_OUTLINE_DEFAULT)
		_preview_layer.add_child(preview)
		_editor_provinces[tid] = {
			"id": tid,
			"points": pts,
			"attrs": attrs,
			"preview_node": preview
		}
	print("ProvinceEditor: Applied saved editor provinces from save data (", _editor_provinces.size(), ")")

func _detect_overlap_aid(new_id: int, new_pts: PackedVector2Array) -> void:
	"""Simple overlap detection as aid (not blocker - human override always allowed by editing/deleting)."""
	if typeof(MapManager) == TYPE_NIL or new_pts.size() < 3:
		return
	# Rough AABB check against current provinces
	var minx = INF; var maxx = -INF; var miny = INF; var maxy = -INF
	for p in new_pts:
		minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
		miny = minf(miny, p.y); maxy = maxf(maxy, p.y)
	var new_rect := Rect2(minx, miny, maxx-minx, maxy-miny)

	var overlaps := []
	for pid in MapManager._provinces:
		if pid == new_id: continue
		var g: Dictionary = MapManager._geometry.get(pid, {})
		var pts: PackedVector2Array = g.get("points", PackedVector2Array())
		if pts.size() < 3: continue
		var ominx := INF; var omaxx := -INF; var ominy := INF; var omaxy := -INF
		for p in pts:
			ominx = minf(ominx, p.x); omaxx = maxf(omaxx, p.x)
			ominy = minf(ominy, p.y); omaxy = maxf(omaxy, p.y)
		var orect := Rect2(ominx, ominy, omaxx-ominx, omaxy-ominy)
		if new_rect.intersects(orect):
			overlaps.append(pid)

	if overlaps.size() > 0:
		print("ProvinceEditor AID (overrideable): New prov %d may overlap existing %s. Drag vertices or delete to adjust." % [new_id, overlaps])
		# Visual aid: add semi-transparent red highlight poly for the new one (human can delete/edit to clear)
		var highlight := Polygon2D.new()
		highlight.polygon = new_pts
		highlight.z_index = 20
		_style_editor_polygon(highlight, Color(1.0, 0.2, 0.2, 0.25), Color(1, 0, 0, 0.8), 2.0)
		_preview_layer.add_child(highlight)
		# Store to clean later if needed (simple: clear on next draw or manual)
		# For now, user can use Clear or toggle editor to refresh
		print("  Red highlight added for overlap - edit or clear to remove.")

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam:
		return cam.get_canvas_transform().affine_inverse() * screen_pos
	return screen_pos

# === DRAWING ===

func _add_vertex(world_pos: Vector2) -> void:
	var snapped_pos := snap_to_nearest_feature(world_pos) if snap_enabled else world_pos
	_current_points.append(snapped_pos)
	_update_live_preview()

	# Simple auto-finish hint if we have enough points and are close to start
	if _current_points.size() >= 5:
		var dist := snapped_pos.distance_to(_current_points[0])
		if dist < 35.0:
			_finish_current_province()

func _update_live_preview() -> void:
	if _current_preview_poly == null:
		_current_preview_poly = Polygon2D.new()
		_style_editor_polygon(
			_current_preview_poly,
			Color(0.2, 0.6, 1.0, 0.25),
			Color(0.1, 0.4, 0.9, 0.9),
			3.0,
		)
		_preview_layer.add_child(_current_preview_poly)

	_current_preview_poly.polygon = _current_points
	_sync_editor_polygon_outline(_current_preview_poly, Color(0.1, 0.4, 0.9, 0.9), 3.0)

	# Update vertex markers (simple ColorRect dots)
	for m in _vertex_markers:
		m.queue_free()
	_vertex_markers.clear()

	for pt in _current_points:
		var dot := ColorRect.new()
		dot.size = Vector2(8, 8)
		dot.color = Color(1, 0.9, 0.2)
		dot.position = pt - dot.size * 0.5
		_preview_layer.add_child(dot)
		_vertex_markers.append(dot)

func _finish_current_province() -> void:
	if _current_points.size() < 3:
		_clear_current_drawing()
		return

	var prov_id := _next_temp_id
	_next_temp_id += 1

	var attrs := _default_attrs.duplicate(true)
	attrs["name"] = "New Province %d" % prov_id

	_editor_provinces[prov_id] = {
		"id": prov_id,
		"points": _current_points.duplicate(),
		"attrs": attrs
	}

	# Create a more permanent preview polygon for this province
	var final_poly := Polygon2D.new()
	final_poly.polygon = _current_points
	_style_editor_polygon(final_poly, EDITOR_FILL_DEFAULT, EDITOR_OUTLINE_DEFAULT)
	_preview_layer.add_child(final_poly)

	# Store reference so we can edit/delete later
	_editor_provinces[prov_id]["preview_node"] = final_poly

	province_created.emit(prov_id, _current_points.duplicate())

	# Basic human-override friendly aid: detect rough overlap with existing (simple AABB for demo)
	_detect_overlap_aid(prov_id, _current_points)

	_clear_current_drawing()

	print("ProvinceEditor: Created temporary province %d with %d vertices" % [prov_id, _current_points.size()])

func _clear_current_drawing() -> void:
	_current_points.clear()
	if _current_preview_poly:
		_current_preview_poly.queue_free()
		_current_preview_poly = null
	for m in _vertex_markers:
		m.queue_free()
	_vertex_markers.clear()

# === EDITING EXISTING (stubs for next iteration) ===

func get_edited_provinces() -> Dictionary:
	return _editor_provinces.duplicate(true)

func delete_edited_province(temp_id: int) -> void:
	if _editor_provinces.has(temp_id):
		var data: Dictionary = _editor_provinces[temp_id]
		if data.has("preview_node") and is_instance_valid(data["preview_node"]):
			data["preview_node"].queue_free()
		_editor_provinces.erase(temp_id)
		print("ProvinceEditor: Deleted temporary province %d" % temp_id)

# === SMART ASSISTANCE (future expansion) ===

func suggest_split_along_river(province_id: int) -> void:
	# TODO: Use river data from map generation pipeline or texture analysis.
	# For now just a placeholder that prints advice.
	print("ProvinceEditor: Smart river split suggestion for %d (implement using river mask data)" % province_id)

# === EXPORT / ROUNDTRIP ===

func export_to_json(base_path: String = "user://editor_provinces/") -> Dictionary:
	var geometry_entries: Array = []
	var base_entries: Array = []

	for temp_id in _editor_provinces:
		var data: Dictionary = _editor_provinces[temp_id]
		var pts: PackedVector2Array = data["points"]
		var attrs: Dictionary = data["attrs"]

		var entry := {
			"id": data["id"],
			"name": attrs.get("name", "Unnamed"),
			"points": _packed_vec2_to_array(pts),
			"label_anchor": _packed_vec2_to_array(pts)[0] if pts.size() > 0 else [0,0]
		}
		geometry_entries.append(entry)

		var base := {
			"id": data["id"],
			"name": attrs.get("name", ""),
			"terrain": attrs.get("terrain", "plains"),
			"population_base": attrs.get("population", 50000),
			"special_features": attrs.get("tags", [])
		}
		base_entries.append(base)

	var geo_out := {
		"meta": {
			"version": 1,
			"created_by": "in_game_province_editor",
			"timestamp": Time.get_datetime_string_from_system()
		},
		"provinces": geometry_entries
	}

	var base_out := {
		"provinces": base_entries
	}

	# Write files
	DirAccess.make_dir_recursive_absolute(base_path)
	var geo_file := FileAccess.open(base_path + "provinces_geometry.json", FileAccess.WRITE)
	if geo_file:
		geo_file.store_string(JSON.stringify(geo_out, "\t"))
		geo_file.close()

	var base_file := FileAccess.open(base_path + "provinces_base.json", FileAccess.WRITE)
	if base_file:
		base_file.store_string(JSON.stringify(base_out, "\t"))
		base_file.close()

	var result := {
		"geometry_path": base_path + "provinces_geometry.json",
		"base_path": base_path + "provinces_base.json",
		"count": geometry_entries.size()
	}

	provinces_exported.emit(result["geometry_path"])
	print("ProvinceEditor: Exported %d provinces to %s" % [geometry_entries.size(), base_path])
	return result


## Hot-reload exported editor geometry into the active test scenario (Debug workflow).
func hot_reload_to_test_scenario(export_base: String = "user://editor_provinces/") -> bool:
	var exported := export_to_json(export_base)
	if exported.is_empty():
		return false
	var sl := get_node_or_null("/root/ScenarioLoader") as ScenarioLoader
	if sl == null:
		push_warning("ProvinceEditor: ScenarioLoader unavailable for hot reload")
		return false
	if sl.has_method("load_province_geometry"):
		sl.load_province_geometry(sl.current_province_data_dir)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("rebuild_pick_grid"):
		MapManager.rebuild_pick_grid()
	var mapr := get_tree().get_first_node_in_group("map_renderer")
	if mapr != null and mapr.has_method("force_full_map_refresh"):
		mapr.call("force_full_map_refresh")
	print("ProvinceEditor: Hot-reload requested (%d editor provinces exported). Re-run scenario load for full merge." % int(exported.get("count", 0)))
	return true

# === Integration with MapRenderer (future) ===
# When active, MapRenderer can call set_editor_mode(true) to lower normal province alpha
# and show the clean base map.

func apply_temporary_to_map() -> void:
	# Feed editor provinces as temporary overlays for live picking, hover, movement preview etc.
	# Calls into MapManager to register temp provinces + rebuild pick grid.
	print("ProvinceEditor: Applying %d editor provinces temporarily for live picking..." % _editor_provinces.size())

	var temp_provs: Dictionary[int, Province] = {}
	var temp_geo: Dictionary = {}

	for temp_id in _editor_provinces:
		var data: Dictionary = _editor_provinces[temp_id]
		var pts: PackedVector2Array = data["points"]
		var attrs: Dictionary = data["attrs"]

		# Create Province resource
		var p := Province.new()
		p.id = int(data["id"])
		p.name = attrs.get("name", "EditorProv%d" % p.id)
		p.terrain = attrs.get("terrain", "plains")
		p.is_sea = attrs.get("is_sea", false)
		p.has_port = attrs.get("has_port", false)
		p.development_level = attrs.get("development_level", 1)
		p.infrastructure = attrs.get("infrastructure", 1)
		p.population = attrs.get("population", 50000)
		p.victory_points = attrs.get("victory_points", 0)
		p.tags = _tags_from_variant(attrs.get("tags", []))
		# Centroid
		if pts.size() > 0:
			var cx := 0.0
			var cy := 0.0
			for pt in pts:
				cx += pt.x
				cy += pt.y
			p.coordinates = Vector2(cx / pts.size(), cy / pts.size())

		temp_provs[p.id] = p
		temp_geo[p.id] = {"points": pts, "label_anchor": p.coordinates}

	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("add_temporary_editor_provinces"):
		MapManager.add_temporary_editor_provinces(temp_provs, temp_geo)
		print("  Registered with MapManager for live picking and queries.")

	# Aid: preview costs for new provinces (human can override attrs before apply)
	for pid in temp_provs:
		var p: Province = temp_provs[pid]
		var move_cost := p.get_movement_cost() if p.has_method("get_movement_cost") else 1.0
		print("  Preview for %s: movement_cost=%.2f (edit attrs or vertices to tune)" % [p.name, move_cost])

	# Rebuild previews
	_rebuild_all_editor_previews()

func _rebuild_all_editor_previews() -> void:
	# Clear old non-current previews? For simplicity, existing ones stay; new draws update.
	for temp_id in _editor_provinces:
		var data: Dictionary = _editor_provinces[temp_id]
		if data.has("preview_node") and is_instance_valid(data["preview_node"]):
			var preview_poly := data["preview_node"] as Polygon2D
			preview_poly.polygon = data["points"]
			_sync_editor_polygon_outline(preview_poly)


## Phase 3: province property inspector board + export roundtrip helpers.
func get_selected_property_board() -> Dictionary:
	var attrs: Dictionary = {}
	if _selected_prov_id >= 0 and _editor_provinces.has(_selected_prov_id):
		var rec: Dictionary = _editor_provinces[_selected_prov_id]
		attrs = (rec.get("attrs", {}) as Dictionary).duplicate(true)
		attrs["temp_id"] = _selected_prov_id
		attrs["vertex_n"] = (rec.get("points", PackedVector2Array()) as PackedVector2Array).size()
	else:
		attrs = _default_attrs.duplicate(true)
		attrs["temp_id"] = -1
		attrs["vertex_n"] = _current_points.size()
	return {
		"ok": true,
		"selected_id": _selected_prov_id,
		"attrs": attrs,
		"active": _is_active,
		"province_n": _editor_provinces.size(),
		"summary": "Editor inspector · sel %d · provinces %d · verts %d" % [
			_selected_prov_id, _editor_provinces.size(), int(attrs.get("vertex_n", 0))
		],
		"empty": false,
	}


func set_selected_property(key: String, value: Variant) -> Dictionary:
	if _selected_prov_id < 0 or not _editor_provinces.has(_selected_prov_id):
		return {"ok": false, "reason": "no selection", "empty": true}
	var rec: Dictionary = _editor_provinces[_selected_prov_id]
	if not rec.has("attrs") or not (rec["attrs"] is Dictionary):
		rec["attrs"] = _default_attrs.duplicate(true)
	(rec["attrs"] as Dictionary)[key] = value
	_editor_provinces[_selected_prov_id] = rec
	province_edited.emit(_selected_prov_id)
	return {"ok": true, "key": key, "value": value, "province_id": _selected_prov_id, "empty": false}


func export_roundtrip_check(base_path: String = "user://editor_provinces/") -> Dictionary:
	var exported := export_to_json(base_path)
	var ok := not exported.is_empty() and int(exported.get("count", 0)) >= 0
	var geom_path := str(exported.get("geometry_path", base_path + "provinces_geometry.json"))
	var exists := FileAccess.file_exists(geom_path) if ok else false
	return {
		"ok": ok and (exists or int(exported.get("count", 0)) == 0),
		"export": exported,
		"geometry_path": geom_path,
		"exists": exists,
		"summary": "Editor export roundtrip · count %d · %s" % [
			int(exported.get("count", 0)), "PASS" if ok else "FAIL"
		],
		"empty": false,
	}
