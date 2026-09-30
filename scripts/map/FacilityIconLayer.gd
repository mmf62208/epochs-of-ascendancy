# scripts/map/FacilityIconLayer.gd
## FAC-1a: transparent top-down airfield icons on the political map.
## One _draw() pass (draw_texture_rect + draw_circle). No Line2D children,
## no per-icon nodes, no absolute-coordinate AA polylines.
## Cached icon list rebuilds on site data change only — never on zoom.
## World anchors are interior (polylabel) points, computed once on rebuild.
class_name FacilityIconLayer
extends Node2D

const FAC_DIR := "res://assets/graphics/icons/facilities/"
const ANCHOR_RES := "res://data/provinces_world_accurate/facility_icon_anchors.json"
const MID_ICON_PX := 22.0
const CLOSE_ICON_PX := 26.0
const CLOSE_GROW_PX := 32.0
const CLOSE_ZOOM := 1.0
const GROW_ZOOM := 2.0
const BADGE_PX := 16.0
const BADGE_OUTLINE_PX := 1.5
const MAP_Z := 24
const UNIT_COUNTER_Z := 28
const THEATER_SCALE := 1.728
const MERGE_GAP_PX := 2.0
const SPLIT_GAP_PX := 10.0
const VISIBLE_MODES: Array[String] = ["political", "diplomacy", "infra"]
const SITE_AIRFIELD := 1
const STATE_NOT_BUILT := 0
const STATE_DAMAGED := 3
const STATE_DESTROYED := 4

var show_facilities: bool = true
var _icons: Array[Dictionary] = []
var _rebuild_count: int = 0
var _drawn_count: int = 0
var _last_zoom: float = -1.0
var _last_cam_pos: Vector2 = Vector2.INF
var _tex_cache: Dictionary = {}
var _test_provinces: Dictionary = {}
var _test_centroids: Dictionary = {}
var _test_polygons: Dictionary = {}
var _test_zoom: float = -1.0
var _test_board_n: int = 0
var _test_map_mode: String = ""
var _test_counter_rects: Array[Rect2] = []
var _json_anchors: Dictionary = {}
var _clustered: bool = false
var _last_markers: Array[Dictionary] = []


func _ready() -> void:
	name = "FacilityIconLayer"
	z_as_relative = false
	z_index = MAP_Z
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	var env_show := OS.get_environment("EOA_FAC1A_SHOW").strip_edges().to_lower()
	if env_show == "0" or env_show == "false" or env_show == "off":
		show_facilities = false
	_load_json_anchors()
	var ssm := _special_site_manager()
	if ssm != null and ssm.has_signal("special_site_created"):
		if not ssm.special_site_created.is_connected(_on_special_site_created):
			ssm.special_site_created.connect(_on_special_site_created)
	rebuild_icon_list()
	queue_redraw()


func _on_special_site_created(_site: Object, _province_id: int) -> void:
	notify_sites_changed()


func notify_sites_changed() -> void:
	rebuild_icon_list()
	queue_redraw()


func set_show_facilities(enabled: bool) -> void:
	if show_facilities == enabled:
		return
	show_facilities = enabled
	queue_redraw()


func toggle_show_facilities() -> void:
	set_show_facilities(not show_facilities)


func get_icon_list() -> Array[Dictionary]:
	return _icons


func get_rebuild_count() -> int:
	return _rebuild_count


func get_last_drawn_count() -> int:
	return _drawn_count


func get_last_markers() -> Array[Dictionary]:
	return _last_markers


func is_clustered() -> bool:
	return _clustered


func count_icons_that_would_draw() -> int:
	if not _should_draw():
		return 0
	return _icons.size()


func get_badge_screen_px(zoom: float = -1.0) -> float:
	var z := zoom if zoom >= 0.0 else _canvas_zoom()
	if z < _site_min_zoom():
		return 0.0
	return BADGE_PX


func get_draw_world(pid: int) -> Vector2:
	for rec in _icons:
		if int(rec.get("pid", -1)) == pid:
			return rec.get("world", Vector2.ZERO) as Vector2
	return Vector2.ZERO


func compute_markers_at_zoom(zoom: float) -> Array[Dictionary]:
	var prev := _test_zoom
	_test_zoom = zoom
	var markers := _build_markers()
	_test_zoom = prev
	return markers


func setup_for_test(provinces: Dictionary, centroids: Dictionary, board_n: int = 0, polygons: Dictionary = {}) -> void:
	_test_provinces = provinces
	_test_centroids = centroids
	_test_polygons = polygons
	_test_board_n = board_n
	rebuild_icon_list()


func set_test_zoom(zoom: float) -> void:
	_test_zoom = zoom
	queue_redraw()


func set_test_map_mode(mode: String) -> void:
	_test_map_mode = mode.strip_edges().to_lower()
	queue_redraw()


func set_test_counter_rects(rects: Array) -> void:
	_test_counter_rects.clear()
	for r in rects:
		if r is Rect2:
			_test_counter_rects.append(r as Rect2)


func max_facility_icons_for_board(province_count: int) -> int:
	if province_count >= 3000:
		return 180
	if province_count >= 800:
		return 360
	return 9999


static func visual_state_for_site(site: Object) -> String:
	if site == null:
		return "intact"
	if int(site.get("damage_level")) > 0:
		return "damaged"
	var st: int = int(site.get("construction_state"))
	if st == STATE_DAMAGED or st == STATE_DESTROYED:
		return "damaged"
	return "intact"


static func texture_key_for_level(level: int, state: String) -> String:
	var lv: int = clampi(level, 1, 4)
	var st := state.strip_edges().to_lower()
	if st != "damaged":
		st = "intact"
	return "airfield_l%d_%s" % [lv, st]


func rebuild_icon_list() -> void:
	_rebuild_count += 1
	_icons.clear()
	_load_json_anchors()
	var provinces: Dictionary = _provinces_for_scan()
	var budget: int = max_facility_icons_for_board(_board_province_count(provinces))
	var added: int = 0
	for pid_v in provinces.keys():
		if added >= budget:
			break
		var p: Object = provinces[pid_v] as Object
		if p == null or bool(p.get("is_sea")):
			continue
		var site: Object = _best_airfield_on_province(p)
		if site == null:
			continue
		var level: int = clampi(int(site.get("tier")), 1, 4)
		var state: String = visual_state_for_site(site)
		var tex_key := texture_key_for_level(level, "intact")
		var pid := int(p.get("id"))
		var world: Vector2 = _interior_world_for(pid, p)
		_icons.append({
			"pid": pid,
			"world": world,
			"centroid": _centroid_for(pid, p),
			"level": level,
			"state": state,
			"tex_key": tex_key,
			"site_id": str(site.get("id")),
		})
		added += 1


func _best_airfield_on_province(p: Object) -> Object:
	if p == null:
		return null
	var raw: Variant = p.get("special_sites")
	if typeof(raw) != TYPE_ARRAY:
		return null
	var best: Object = null
	var best_tier: int = -1
	for site_v in raw:
		if typeof(site_v) != TYPE_OBJECT:
			continue
		var site: Object = site_v as Object
		if site == null:
			continue
		if int(site.get("site_type")) != SITE_AIRFIELD:
			continue
		if int(site.get("construction_state")) == STATE_NOT_BUILT:
			continue
		var t: int = int(site.get("tier"))
		if t > best_tier:
			best = site
			best_tier = t
	return best


func _special_site_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("SpecialSiteManager")


func _map_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("MapManager")


func _provinces_for_scan() -> Dictionary:
	if not _test_provinces.is_empty():
		return _test_provinces
	var mm := _map_manager()
	if mm != null and mm.has_method("get_all_provinces"):
		var all: Variant = mm.call("get_all_provinces")
		if all is Dictionary:
			return all as Dictionary
	var loader: Node = _scenario_loader()
	if loader != null and "provinces" in loader:
		var lp: Variant = loader.get("provinces")
		if lp is Dictionary:
			return lp as Dictionary
	return {}


func _board_province_count(provinces: Dictionary) -> int:
	if _test_board_n > 0:
		return _test_board_n
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_count"):
		return maxi(provinces.size(), int(mm.call("get_province_count")))
	return provinces.size()


func _centroid_for(pid: int, p: Object) -> Vector2:
	if _test_centroids.has(pid):
		return _test_centroids[pid] as Vector2
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", pid)
		if c != Vector2.ZERO:
			return c
	if p != null:
		var coords: Variant = p.get("coordinates")
		if coords is Vector2:
			return coords as Vector2
	return Vector2.ZERO


func _load_json_anchors() -> void:
	if not _json_anchors.is_empty():
		return
	if not FileAccess.file_exists(ANCHOR_RES):
		return
	var f := FileAccess.open(ANCHOR_RES, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(txt) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var blob: Dictionary = parser.data
	var raw: Variant = blob.get("anchors", {})
	if raw is Dictionary:
		_json_anchors = raw as Dictionary


func _ring_for(pid: int, p: Object) -> PackedVector2Array:
	if _test_polygons.has(pid):
		var tp: Variant = _test_polygons[pid]
		if tp is PackedVector2Array:
			return tp as PackedVector2Array
		if tp is Array:
			var acc := PackedVector2Array()
			for q in tp as Array:
				if q is Vector2:
					acc.append(q as Vector2)
			return acc
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_geometry"):
		var geo: Dictionary = mm.call("get_province_geometry", pid)
		var pts: Variant = geo.get("points", [])
		return _variant_ring_to_packed(pts)
	if p != null:
		var raw: Variant = p.get("boundary")
		return _variant_ring_to_packed(raw)
	return PackedVector2Array()


func _variant_ring_to_packed(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if raw is PackedVector2Array:
		return raw as PackedVector2Array
	if raw is Array:
		for p in raw as Array:
			if p is Vector2:
				out.append(p as Vector2)
			elif p is Array and (p as Array).size() >= 2:
				out.append(Vector2(float(p[0]), float(p[1])))
	return out


func _interior_world_for(pid: int, p: Object) -> Vector2:
	var centroid := _centroid_for(pid, p)
	var key := str(pid)
	if _test_polygons.is_empty() and _json_anchors.has(key):
		var rec: Variant = _json_anchors[key]
		if rec is Dictionary:
			var w: Variant = (rec as Dictionary).get("world", [])
			if w is Array and (w as Array).size() >= 2:
				return Vector2(float(w[0]), float(w[1]))
			var raw: Variant = (rec as Dictionary).get("raw", [])
			if raw is Array and (raw as Array).size() >= 2:
				return Vector2(float(raw[0]) * THEATER_SCALE, float(raw[1]) * THEATER_SCALE)
	var ring := _ring_for(pid, p)
	if ring.size() >= 3:
		var raw_like := _ring_looks_raw(ring, centroid)
		var pole := _polylabel(ring)
		if raw_like and centroid != Vector2.ZERO:
			var c_raw := _mean_ring(ring)
			if c_raw != Vector2.ZERO:
				pole = centroid + (pole - c_raw) * THEATER_SCALE
		if pole != Vector2.ZERO:
			return pole
	return centroid


func _ring_looks_raw(ring: PackedVector2Array, world_centroid: Vector2) -> bool:
	if ring.is_empty() or world_centroid == Vector2.ZERO:
		return false
	var mean := _mean_ring(ring)
	if mean == Vector2.ZERO:
		return false
	return mean.distance_to(world_centroid) > 8.0 and mean.length() * 1.2 < world_centroid.length()


func _mean_ring(ring: PackedVector2Array) -> Vector2:
	if ring.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p in ring:
		acc += p
	return acc / float(ring.size())


func _signed_edge(x: float, y: float, ring: PackedVector2Array) -> float:
	if ring.size() < 3:
		return -1.0e9
	var best := 1.0e18
	var n := ring.size()
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var d := _dist_seg(Vector2(x, y), a, b)
		if d < best:
			best = d
	if Geometry2D.is_point_in_polygon(Vector2(x, y), ring):
		return best
	return -best


func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var den := ab.length_squared()
	if den < 0.0000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / den, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _polylabel(ring: PackedVector2Array) -> Vector2:
	if ring.size() < 3:
		return _mean_ring(ring)
	var min_v := ring[0]
	var max_v := ring[0]
	for p in ring:
		min_v.x = minf(min_v.x, p.x)
		min_v.y = minf(min_v.y, p.y)
		max_v.x = maxf(max_v.x, p.x)
		max_v.y = maxf(max_v.y, p.y)
	var width := max_v.x - min_v.x
	var height := max_v.y - min_v.y
	var cell := minf(width, height)
	if cell < 0.0001:
		return _mean_ring(ring)
	var best := _mean_ring(ring)
	var best_d := _signed_edge(best.x, best.y, ring)
	var precision := 0.18
	var heap: Array[Dictionary] = []
	var h := cell * 0.5
	var x := min_v.x + h
	while x < max_v.x:
		var y := min_v.y + h
		while y < max_v.y:
			_push_cell(heap, ring, x, y, h)
			y += cell
		x += cell
	var guard := 0
	while not heap.is_empty() and guard < 400:
		guard += 1
		heap.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("pot", 0.0)) > float(b.get("pot", 0.0)))
		var cell_d: Dictionary = heap[0]
		heap.remove_at(0)
		var d: float = float(cell_d.get("d", -1.0e9))
		var cx: float = float(cell_d.get("x", 0.0))
		var cy: float = float(cell_d.get("y", 0.0))
		var half: float = float(cell_d.get("h", 0.0))
		if d > best_d:
			best = Vector2(cx, cy)
			best_d = d
		if float(cell_d.get("pot", 0.0)) - best_d <= precision:
			continue
		var nh := half * 0.5
		if nh < precision * 0.5:
			continue
		_push_cell(heap, ring, cx - nh, cy - nh, nh)
		_push_cell(heap, ring, cx + nh, cy - nh, nh)
		_push_cell(heap, ring, cx - nh, cy + nh, nh)
		_push_cell(heap, ring, cx + nh, cy + nh, nh)
	return best


func _push_cell(heap: Array[Dictionary], ring: PackedVector2Array, x: float, y: float, half: float) -> void:
	var d := _signed_edge(x, y, ring)
	var pot := d + half * 1.41421356
	heap.append({"x": x, "y": y, "h": half, "d": d, "pot": pot})


func _scenario_loader() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var n: Node = tree.root.get_node_or_null("ScenarioLoader")
	if n != null:
		return n
	return tree.root.find_child("ScenarioLoader", true, false)


func _map_renderer() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes: Array = tree.get_nodes_in_group("map_renderer")
	if nodes.size() > 0 and nodes[0] is Node:
		return nodes[0] as Node
	return tree.root.find_child("WorldMap", true, false)


func _map_mode() -> String:
	if not _test_map_mode.is_empty():
		return _test_map_mode
	var mr := _map_renderer()
	if mr != null and "current_map_mode" in mr:
		return str(mr.get("current_map_mode")).strip_edges().to_lower()
	return "political"


func _mode_allows_facilities() -> bool:
	var m := _map_mode()
	if m == "resources":
		return false
	return m in VISIBLE_MODES


func _canvas_zoom() -> float:
	if _test_zoom >= 0.0:
		return _test_zoom
	var cam := _player_map_camera()
	if cam != null:
		return maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	return 1.0


func _player_map_camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var named := mr.get_node_or_null("MapCamera") as Camera2D
		if named != null:
			return named
	var vp := get_viewport()
	if vp != null:
		return vp.get_camera_2d()
	return null


func _site_min_zoom() -> float:
	const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")
	return float(MapZoomLODScript.site_marker_min_zoom_for_board(_board_province_count(_provinces_for_scan())))


func _process(_delta: float) -> void:
	var cam := _player_map_camera()
	var z := _canvas_zoom()
	var pos := cam.global_position if cam != null else Vector2.ZERO
	var zoom_changed := absf(z - _last_zoom) > 0.008
	var pan_changed := _last_cam_pos != Vector2.INF and pos.distance_to(_last_cam_pos) > 8.0
	if zoom_changed or pan_changed:
		_last_zoom = z
		_last_cam_pos = pos
		queue_redraw()
	elif _last_cam_pos == Vector2.INF:
		_last_cam_pos = pos
		_last_zoom = z


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed:
		return
	if key.keycode == KEY_P:
		toggle_show_facilities()
		get_viewport().set_input_as_handled()


func _should_draw() -> bool:
	if not show_facilities:
		return false
	if not _mode_allows_facilities():
		return false
	var z := _canvas_zoom()
	if z < _site_min_zoom():
		return false
	return true


func _icon_screen_px(zoom: float) -> float:
	if zoom >= GROW_ZOOM:
		return CLOSE_GROW_PX
	if zoom >= CLOSE_ZOOM:
		var t := (zoom - CLOSE_ZOOM) / maxf(GROW_ZOOM - CLOSE_ZOOM, 0.01)
		return lerpf(CLOSE_ICON_PX, CLOSE_GROW_PX, clampf(t, 0.0, 1.0))
	return MID_ICON_PX


func _world_size(screen_px: float) -> float:
	return screen_px / maxf(_canvas_zoom(), 0.04)


func _load_tex(stem: String, px: int) -> Texture2D:
	var cache_key := "%s_%d" % [stem, px]
	if _tex_cache.has(cache_key):
		return _tex_cache[cache_key] as Texture2D
	var path := "%s%s_%d.png" % [FAC_DIR, stem, px]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		tex = res as Texture2D
	if tex == null and px != 64:
		var fallback := "%s%s_64.png" % [FAC_DIR, stem]
		if ResourceLoader.exists(fallback):
			var res2: Resource = load(fallback)
			tex = res2 as Texture2D
	_tex_cache[cache_key] = tex
	return tex


func _in_viewport(world: Vector2, pad_px: float) -> bool:
	var vp := get_viewport()
	if vp == null:
		return true
	var cam := _player_map_camera()
	if cam == null:
		return true
	var screen: Vector2 = cam.get_canvas_transform() * world
	var r: Rect2 = Rect2(Vector2.ZERO, Vector2(vp.get_visible_rect().size)).grow(pad_px)
	return r.has_point(screen)


func _screen_of(world: Vector2) -> Vector2:
	var cam := _player_map_camera()
	if cam == null:
		return world * _canvas_zoom()
	return cam.get_canvas_transform() * world


func _build_markers() -> Array[Dictionary]:
	var z := _canvas_zoom()
	var icon_px := _icon_screen_px(z)
	var items: Array[Dictionary] = []
	for rec in _icons:
		var world: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
		if not world.is_finite():
			continue
		var scr := _screen_of(world)
		var half := icon_px * 0.5 + BADGE_PX * 0.35
		var rect := Rect2(scr - Vector2(half, half), Vector2(half, half) * 2.0)
		items.append({
			"pid": int(rec.get("pid", 0)),
			"world": world,
			"screen": scr,
			"rect": rect,
			"level": clampi(int(rec.get("level", 1)), 1, 4),
			"state": str(rec.get("state", "intact")),
			"tex_key": str(rec.get("tex_key", "")),
		})
	if items.size() < 2:
		_clustered = false
		return items
	var min_gap := 1.0e9
	for i in range(items.size()):
		var a: Rect2 = items[i].get("rect", Rect2()) as Rect2
		for j in range(i + 1, items.size()):
			var b: Rect2 = items[j].get("rect", Rect2()) as Rect2
			var gap := _rect_gap(a, b)
			if gap < min_gap:
				min_gap = gap
	if _clustered:
		if min_gap >= SPLIT_GAP_PX:
			_clustered = false
	else:
		if min_gap < MERGE_GAP_PX:
			_clustered = true
	if not _clustered:
		return items
	return _cluster_items(items)


func _rect_gap(a: Rect2, b: Rect2) -> float:
	if a.intersects(b):
		return -1.0
	var dx := 0.0
	if a.end.x < b.position.x:
		dx = b.position.x - a.end.x
	elif b.end.x < a.position.x:
		dx = a.position.x - b.end.x
	var dy := 0.0
	if a.end.y < b.position.y:
		dy = b.position.y - a.end.y
	elif b.end.y < a.position.y:
		dy = a.position.y - b.end.y
	return maxf(dx, dy)


func _uf_find(parent: Array[int], i: int) -> int:
	var x := i
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


func _cluster_items(items: Array[Dictionary]) -> Array[Dictionary]:
	var n := items.size()
	var parent: Array[int] = []
	parent.resize(n)
	for i in range(n):
		parent[i] = i
	for i in range(n):
		var ai: Rect2 = items[i].get("rect", Rect2()) as Rect2
		for j in range(i + 1, n):
			var bj: Rect2 = items[j].get("rect", Rect2()) as Rect2
			if _rect_gap(ai, bj) < MERGE_GAP_PX:
				var ra := _uf_find(parent, i)
				var rb := _uf_find(parent, j)
				if ra != rb:
					parent[rb] = ra
	var groups: Dictionary = {}
	for i in range(n):
		var r := _uf_find(parent, i)
		if not groups.has(r):
			groups[r] = []
		(groups[r] as Array).append(i)
	var out: Array[Dictionary] = []
	for g_v in groups.values():
		var idxs: Array = g_v
		if idxs.size() <= 1:
			out.append(items[int(idxs[0])])
			continue
		var acc := Vector2.ZERO
		var hi := 1
		var pids: Array[int] = []
		for ii in idxs:
			var it: Dictionary = items[int(ii)]
			acc += it.get("world", Vector2.ZERO) as Vector2
			hi = maxi(hi, int(it.get("level", 1)))
			pids.append(int(it.get("pid", 0)))
		var world := acc / float(idxs.size())
		var scr := _screen_of(world)
		var z := _canvas_zoom()
		var icon_px := _icon_screen_px(z) + 4.0
		var half := icon_px * 0.5 + BADGE_PX * 0.35
		out.append({
			"pid": pids[0],
			"pids": pids,
			"cluster": true,
			"count": idxs.size(),
			"world": world,
			"screen": scr,
			"rect": Rect2(scr - Vector2(half, half), Vector2(half, half) * 2.0),
			"level": hi,
			"state": "intact",
			"tex_key": texture_key_for_level(hi, "intact"),
		})
	return out


func _draw() -> void:
	_drawn_count = 0
	_last_markers.clear()
	if not _should_draw():
		return
	var z := _canvas_zoom()
	var markers := _build_markers()
	_last_markers = markers
	var screen_px := _icon_screen_px(z)
	var close := z >= CLOSE_ZOOM
	for rec in markers:
		var world: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
		if not world.is_finite():
			continue
		if not _in_viewport(world, screen_px + BADGE_PX + 20.0):
			continue
		var level: int = clampi(int(rec.get("level", 1)), 1, 4)
		var tex_key: String = str(rec.get("tex_key", texture_key_for_level(level, "intact")))
		var icon_tex := _load_tex(tex_key, 32)
		if icon_tex == null:
			continue
		var px := screen_px
		if bool(rec.get("cluster", false)):
			px = screen_px + 4.0
		var world_px := _world_size(px)
		var rect := Rect2(world - Vector2(world_px, world_px) * 0.5, Vector2(world_px, world_px))
		draw_texture_rect(icon_tex, rect, false)
		if str(rec.get("state", "intact")) == "damaged":
			pass
		var badge_n := int(rec.get("count", 0)) if bool(rec.get("cluster", false)) else (level if not close else 0)
		if close and not bool(rec.get("cluster", false)):
			var pips := _load_tex("level_pips_l%d" % level, 32)
			if pips != null:
				var pw := _world_size(px * 0.55)
				var ph := pw * 0.25
				draw_texture_rect(
					pips,
					Rect2(Vector2(world.x - pw * 0.5, world.y + world_px * 0.18), Vector2(pw, ph)),
					false
				)
		if badge_n >= 1:
			_draw_outlined_badge(world, world_px, badge_n)
		_drawn_count += 1


func _draw_outlined_badge(world: Vector2, icon_world: float, number: int) -> void:
	var bw := _world_size(BADGE_PX)
	var outline := _world_size(BADGE_PX + BADGE_OUTLINE_PX * 2.0)
	var center := Vector2(world.x + icon_world * 0.28, world.y + icon_world * 0.28)
	draw_circle(center + Vector2(bw, bw) * 0.0, outline * 0.52, Color(0.05, 0.04, 0.03, 0.92))
	var n := clampi(number, 1, 5)
	var badge := _load_tex("level_badge_l%d" % n, 16)
	if badge != null:
		draw_texture_rect(badge, Rect2(center - Vector2(bw, bw) * 0.5, Vector2(bw, bw)), false)
