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
const MapCanvasConfigScript = preload("res://scripts/map/MapCanvasConfig.gd")
const Rx1RhineCrossingScript = preload("res://scripts/map/Rx1RhineCrossing.gd")
const MID_ICON_PX := 22.0
const CLOSE_ICON_PX := 26.0
const CLOSE_GROW_PX := 32.0
const CLOSE_ZOOM := 1.0
const GROW_ZOOM := 2.0
const BADGE_PX := 16.0
const BADGE_OUTLINE_PX := 1.5
const MID_BADGE_PX := 8.0
const OPS_MIN_ICON_PX := 36.0
const OPS_SIZE_ZOOM := 1.20
const HALO_PX := 2.0
const COUNT_DIGIT_MIN_PX := 10.0
const COUNT_DIGIT_PX := 16.0
const COUNT_DISC_PX := 16.0
const CLUSTER_TAG_PX := 12.0
const CLUSTER_MID_MIN_PX := 34.0
const CHROME_GAP_PX := 2.0
const OVAL_W_FRAC := 0.88
const OVAL_H_FRAC := 0.58
const OVAL_TOP_FRAC := 0.26
const MAP_Z := 24
const UNIT_COUNTER_Z := 28
const THEATER_SCALE := 1.728
const MERGE_GAP_PX := 2.0
const SPLIT_GAP_PX := 10.0
const CLEAR_MARGIN_PX := 4.0
const SPINE_PIDS: Array[int] = [710416, 710417, 710418]
const RHINE_WALK_PIDS: Array[int] = [710416, 710417, 710401, 710402]
const LUX_CAPITAL_PID := 710977
const KOELN_PID := 710417
## Live cluster half at RX-1 mid (0.95) is ~20–29 world. Neuwied's whole
## province is ≤5.2 raw (~9 world) from the real course — it cannot host.
const RHINE_HOST_MIN_WORLD := 22.0
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
	if z + 0.0001 >= CLOSE_ZOOM:
		return 0.0
	return MID_BADGE_PX


func get_cluster_digit_px() -> float:
	return COUNT_DIGIT_PX


func _world_size_at(screen_px: float, zoom: float) -> float:
	return screen_px / maxf(zoom, 0.04)


func _drawn_icon_px(zoom: float, cluster: bool) -> float:
	var px := _icon_screen_px(zoom)
	if cluster:
		px += 4.0
		if zoom + 0.0001 < CLOSE_ZOOM:
			px = maxf(px, CLUSTER_MID_MIN_PX)
		if zoom + 0.0001 >= OPS_SIZE_ZOOM:
			px = maxf(px, OPS_MIN_ICON_PX)
		return px
	if zoom + 0.0001 >= OPS_SIZE_ZOOM:
		return maxf(px, OPS_MIN_ICON_PX)
	return px


func _oval_rect(icon_rect: Rect2) -> Rect2:
	if icon_rect.size.x <= 0.0:
		return icon_rect
	var w := icon_rect.size.x * OVAL_W_FRAC
	var h := icon_rect.size.y * OVAL_H_FRAC
	var x := icon_rect.position.x + (icon_rect.size.x - w) * 0.5
	var y := icon_rect.position.y + icon_rect.size.y * OVAL_TOP_FRAC
	return Rect2(Vector2(x, y), Vector2(w, h))


func _point_in_oval(r: Rect2, p: Vector2) -> bool:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return false
	var c := r.get_center()
	var rx := r.size.x * 0.5
	var ry := r.size.y * 0.5
	var dx := (p.x - c.x) / rx
	var dy := (p.y - c.y) / ry
	return dx * dx + dy * dy <= 1.002


func _should_draw_at(zoom: float) -> bool:
	if not show_facilities:
		return false
	if not _mode_allows_facilities():
		return false
	if zoom < _site_min_zoom():
		return false
	return true


func _rect_has_point_inclusive(r: Rect2, p: Vector2) -> bool:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return false
	return (
		p.x + 0.001 >= r.position.x
		and p.y + 0.001 >= r.position.y
		and p.x <= r.end.x + 0.001
		and p.y <= r.end.y + 0.001
	)


func _rect_contains_rect(outer: Rect2, inner: Rect2) -> bool:
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return true
	return (
		inner.position.x + 0.001 >= outer.position.x
		and inner.position.y + 0.001 >= outer.position.y
		and inner.end.x <= outer.end.x + 0.001
		and inner.end.y <= outer.end.y + 0.001
	)


func _clamp_rect_inside(inner: Rect2, outer: Rect2) -> Rect2:
	if inner.size.x <= 0.0 or outer.size.x <= 0.0:
		return inner
	var w := minf(inner.size.x, outer.size.x)
	var h := minf(inner.size.y, outer.size.y)
	var x := clampf(inner.position.x, outer.position.x, outer.end.x - w)
	var y := clampf(inner.position.y, outer.position.y, outer.end.y - h)
	return Rect2(Vector2(x, y), Vector2(w, h))


func _layout_drawn_marker(rec: Dictionary, zoom: float) -> Dictionary:
	var world: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
	var cluster := bool(rec.get("cluster", false))
	var level: int = clampi(int(rec.get("level", 1)), 1, 4)
	var count: int = int(rec.get("count", 0)) if cluster else (level if zoom + 0.0001 < CLOSE_ZOOM else 0)
	var icon_px := _drawn_icon_px(zoom, cluster)
	var world_px := _world_size_at(icon_px, zoom)
	var icon_rect := Rect2(world - Vector2(world_px, world_px) * 0.5, Vector2(world_px, world_px))
	var oval_rect := _oval_rect(icon_rect)
	var hits: Array[Rect2] = [oval_rect]
	var badge_rect := Rect2()
	var tag_rect := Rect2()
	var gap := _world_size_at(CHROME_GAP_PX, zoom)
	if cluster:
		var disc_w := _world_size_at(COUNT_DISC_PX, zoom)
		var tag_w := _world_size_at(CLUSTER_TAG_PX, zoom)
		var cy := oval_rect.get_center().y
		var count_n := maxi(int(rec.get("count", 0)), 1)
		if count_n >= 1:
			var bx := icon_rect.position.x + gap
			badge_rect = Rect2(Vector2(bx, cy - disc_w * 0.5), Vector2(disc_w, disc_w))
			badge_rect = _clamp_rect_inside(badge_rect, icon_rect)
			hits.append(badge_rect)
		var tx := icon_rect.end.x - tag_w - gap
		tag_rect = Rect2(Vector2(tx, cy - tag_w * 0.5), Vector2(tag_w, tag_w))
		tag_rect = _clamp_rect_inside(tag_rect, icon_rect)
		if badge_rect.size.x > 0.0 and tag_rect.position.x < badge_rect.end.x + gap:
			tag_rect.position.x = badge_rect.end.x + gap
			tag_rect = _clamp_rect_inside(tag_rect, icon_rect)
		hits.append(tag_rect)
	elif count >= 1:
		var bw := _world_size_at(MID_BADGE_PX, zoom)
		var raw_badge2 := Rect2(oval_rect.get_center() - Vector2(bw, bw) * 0.5, Vector2(bw, bw))
		badge_rect = _clamp_rect_inside(raw_badge2, oval_rect)
		hits.append(badge_rect)
	return {
		"pid": int(rec.get("pid", -1)),
		"cluster": cluster,
		"world": world,
		"icon_px": icon_px,
		"icon_rect": icon_rect,
		"oval_rect": oval_rect,
		"hit_icon": oval_rect,
		"badge_rect": badge_rect,
		"tag_rect": tag_rect,
		"hits": hits,
		"count": count if not cluster else int(rec.get("count", 0)),
		"level": level,
		"digit_px": COUNT_DIGIT_PX if cluster else 0.0,
		"digit_h_px": cluster_digit_screen_h_px(zoom) if cluster else 0.0,
		"halo_px": HALO_PX if zoom + 0.0001 >= CLOSE_ZOOM else 0.0,
	}


func hit_test_world(world: Vector2) -> int:
	if not _should_draw():
		return -1
	return hit_test_at_zoom(world, _canvas_zoom())


func hit_test_at_zoom(world: Vector2, zoom: float) -> int:
	if not _should_draw_at(zoom):
		return -1
	var layouts := get_hit_rects_at_zoom(zoom)
	for layout_v in layouts:
		var layout: Dictionary = layout_v
		if _layout_owns_world(layout, world):
			return int(layout.get("pid", -1))
	return -1


func _layout_owns_world(layout: Dictionary, world: Vector2) -> bool:
	var oval: Rect2 = layout.get("oval_rect", Rect2()) as Rect2
	if _point_in_oval(oval, world):
		return true
	var badge: Rect2 = layout.get("badge_rect", Rect2()) as Rect2
	if _point_in_oval(badge, world):
		return true
	var tag: Rect2 = layout.get("tag_rect", Rect2()) as Rect2
	if _point_in_oval(tag, world):
		return true
	return false


func tight_hit_samples(layout: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var oval: Rect2 = layout.get("oval_rect", Rect2()) as Rect2
	out.append_array(_ellipse_cardinals(oval, 0.15))
	var badge: Rect2 = layout.get("badge_rect", Rect2()) as Rect2
	out.append_array(_ellipse_cardinals(badge, 0.15))
	var tag: Rect2 = layout.get("tag_rect", Rect2()) as Rect2
	out.append_array(_ellipse_cardinals(tag, 0.15))
	return out


func drawn_outside_samples(layout: Dictionary, zoom: float, pad_px: float = 2.0) -> Array[Vector2]:
	var pad := _world_size_at(pad_px, zoom)
	var rects := _drawn_bound_rects(layout)
	if rects.is_empty():
		return []
	var union: Rect2 = rects[0]
	for r in rects:
		union = union.merge(r)
	return _rect_outside_cardinals(union, pad)


func _drawn_bound_rects(layout: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var oval: Rect2 = layout.get("oval_rect", Rect2()) as Rect2
	if oval.size.x > 0.0:
		out.append(oval)
	var badge: Rect2 = layout.get("badge_rect", Rect2()) as Rect2
	if badge.size.x > 0.0:
		out.append(badge)
	var tag: Rect2 = layout.get("tag_rect", Rect2()) as Rect2
	if tag.size.x > 0.0:
		out.append(tag)
	return out


func _ellipse_cardinals(r: Rect2, inset: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return out
	var c := r.get_center()
	var rx := r.size.x * 0.5 * (1.0 - clampf(inset, 0.0, 0.45))
	var ry := r.size.y * 0.5 * (1.0 - clampf(inset, 0.0, 0.45))
	out.append(c)
	out.append(c + Vector2(0.0, -ry))
	out.append(c + Vector2(rx, 0.0))
	out.append(c + Vector2(0.0, ry))
	out.append(c + Vector2(-rx, 0.0))
	return out


func _rect_outside_cardinals(r: Rect2, pad: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return out
	var c := r.get_center()
	out.append(Vector2(c.x, r.position.y - pad))
	out.append(Vector2(r.end.x + pad, c.y))
	out.append(Vector2(c.x, r.end.y + pad))
	out.append(Vector2(r.position.x - pad, c.y))
	return out


func get_hit_rects_at_zoom(zoom: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _should_draw_at(zoom):
		return out
	var markers := compute_markers_at_zoom(zoom)
	for rec_v in markers:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		out.append(_layout_drawn_marker(rec_v as Dictionary, zoom))
	return out


func badge_inside_footprint_at(zoom: float) -> bool:
	for layout_v in get_hit_rects_at_zoom(zoom):
		var layout: Dictionary = layout_v
		var oval: Rect2 = layout.get("oval_rect", Rect2()) as Rect2
		var badge: Rect2 = layout.get("badge_rect", Rect2()) as Rect2
		if bool(layout.get("cluster", false)):
			continue
		if not _rect_inside_oval(oval, badge):
			return false
	return true


func _rect_inside_oval(oval: Rect2, inner: Rect2) -> bool:
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return true
	var corners: Array[Vector2] = [
		inner.position,
		Vector2(inner.end.x, inner.position.y),
		inner.end,
		Vector2(inner.position.x, inner.end.y),
	]
	for p in corners:
		if not _point_in_oval(oval, p):
			return false
	return true


func cluster_digit_height_px() -> float:
	return cluster_digit_screen_h_px(1.0)


func cluster_digit_screen_h_px(zoom: float) -> float:
	var z := maxf(zoom, 0.04)
	var font_sz := maxi(1, int(round(COUNT_DIGIT_PX / z)))
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return COUNT_DIGIT_PX
	var h := float(font.get_height(font_sz)) * z
	var sz: Vector2 = font.get_string_size("2", HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz)
	return maxf(h, sz.y * z)


func cluster_chrome_gap_px(zoom: float) -> float:
	var best := 1.0e9
	var found := false
	for layout_v in get_hit_rects_at_zoom(zoom):
		var layout: Dictionary = layout_v
		if not bool(layout.get("cluster", false)):
			continue
		var badge: Rect2 = layout.get("badge_rect", Rect2()) as Rect2
		var tag: Rect2 = layout.get("tag_rect", Rect2()) as Rect2
		if badge.size.x <= 0.0 or tag.size.x <= 0.0:
			continue
		found = true
		var gap_w := tag.position.x - badge.end.x
		var gap_h := tag.position.y - badge.end.y
		if tag.end.x < badge.position.x:
			gap_w = badge.position.x - tag.end.x
		if tag.end.y < badge.position.y:
			gap_h = badge.position.y - tag.end.y
		var sep := 0.0
		if badge.intersects(tag):
			sep = -1.0
		elif gap_w >= 0.0 and badge.end.y + 0.001 >= tag.position.y and tag.end.y + 0.001 >= badge.position.y:
			sep = gap_w
		elif gap_h >= 0.0 and badge.end.x + 0.001 >= tag.position.x and tag.end.x + 0.001 >= badge.position.x:
			sep = gap_h
		else:
			sep = minf(absf(gap_w), absf(gap_h))
		best = minf(best, sep * zoom)
	if not found:
		return 0.0
	return best


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
	var ring := _ring_for(pid, p)
	if ring.size() < 3:
		return centroid
	## Test polygons are already in the dummy world the headless harness uses.
	if not _test_polygons.is_empty():
		var pole_t := _polylabel(ring)
		return pole_t if pole_t != Vector2.ZERO else centroid
	var world_ring := _world_ring(ring, centroid)
	var key := str(pid)
	if _json_anchors.has(key):
		var rec: Variant = _json_anchors[key]
		if rec is Dictionary:
			var raw: Variant = (rec as Dictionary).get("raw", [])
			if raw is Array and (raw as Array).size() >= 2 and centroid != Vector2.ZERO:
				var raw_pt := Vector2(float(raw[0]), float(raw[1]))
				## Same offset as `_world_ring` fallback (ring mean, not label
				## anchor). Label-anchor remap put opposite-edge seeds outside
				## the world ring, so polylabel snapped them together.
				var raw_mean := _mean_ring(ring)
				var cand := centroid + (raw_pt - raw_mean) * THEATER_SCALE
				if not Geometry2D.is_point_in_polygon(cand, world_ring):
					var craw: Variant = (rec as Dictionary).get("centroid_raw", [])
					if craw is Array and (craw as Array).size() >= 2:
						cand = centroid + (raw_pt - Vector2(float(craw[0]), float(craw[1]))) * THEATER_SCALE
				if Geometry2D.is_point_in_polygon(cand, world_ring):
					return _snap_to_own_pick(pid, cand, centroid)
	var pole := _polylabel(world_ring)
	if pole != Vector2.ZERO and Geometry2D.is_point_in_polygon(pole, world_ring):
		return _snap_to_own_pick(pid, pole, centroid)
	return _snap_to_own_pick(pid, centroid, centroid)


func _snap_to_own_pick(pid: int, cand: Vector2, centroid: Vector2) -> Vector2:
	## Existing province hit-test (untouched) must resolve the icon center to
	## this pid. Walk toward the MapManager centroid, then sample nearby
	## interiors, until it does (LUX inflation can steal a first cand).
	var mm := _map_manager()
	if mm == null or not mm.has_method("get_province_at_world_pos"):
		return cand
	if int(mm.call("get_province_at_world_pos", cand, true)) == pid:
		return cand
	## Prefer a nearby own-pick so opposite-edge cluster seeds do not collapse
	## onto the centroid (nearby NUTS3 centroids can sit only ~9 raw apart).
	var near := 0.7
	while near <= 4.2:
		var ang := 0.0
		while ang < TAU:
			var nq: Vector2 = cand + Vector2(cos(ang), sin(ang)) * near
			if int(mm.call("get_province_at_world_pos", nq, true)) == pid:
				return nq
			ang += PI / 6.0
		near += 0.7
	if centroid != Vector2.ZERO:
		if int(mm.call("get_province_at_world_pos", centroid, true)) == pid:
			var t := 0.08
			while t <= 1.001:
				var p: Vector2 = cand.lerp(centroid, t)
				if int(mm.call("get_province_at_world_pos", p, true)) == pid:
					return p
				t += 0.08
			return centroid
		var step := 1.6
		var r := step
		while r <= 12.0:
			var a := 0.0
			while a < TAU:
				var q: Vector2 = centroid + Vector2(cos(a), sin(a)) * r
				if int(mm.call("get_province_at_world_pos", q, true)) == pid:
					return q
				a += PI / 6.0
			r += step
	return cand if cand != Vector2.ZERO else centroid


func _world_ring(ring: PackedVector2Array, world_centroid: Vector2) -> PackedVector2Array:
	if ring.size() < 3:
		return ring
	var native := true
	var mm := _map_manager()
	if mm != null and "_geometry_world_native" in mm:
		native = bool(mm.get("_geometry_world_native"))
	var world_mode := true
	if mm != null and mm.has_method("get_world_bounds"):
		var b: Rect2 = mm.call("get_world_bounds")
		world_mode = MapCanvasConfigScript.is_world_mode(b) or native
	var transformed: PackedVector2Array = MapCanvasConfigScript.transform_province_points(ring, world_mode, true, native)
	if transformed.size() >= 3:
		return transformed
	if world_centroid != Vector2.ZERO and _ring_looks_raw(ring, world_centroid):
		var c_raw := _mean_ring(ring)
		var acc := PackedVector2Array()
		for q in ring:
			acc.append(world_centroid + (q - c_raw) * THEATER_SCALE)
		return acc
	return ring


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
	return _world_size_at(screen_px, _canvas_zoom())


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
	## compute_markers_at_zoom must project at the requested zoom, not the
	## live Home camera. Pairwise gaps only need world*zoom (translation cancels).
	if _test_zoom >= 0.0:
		return world * _test_zoom
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
		var host := _pick_cluster_host(items, idxs)
		var hi := int(host.get("level", 1))
		var pids: Array[int] = []
		for ii in idxs:
			var it: Dictionary = items[int(ii)]
			hi = maxi(hi, int(it.get("level", 1)))
			pids.append(int(it.get("pid", 0)))
		var z := _canvas_zoom()
		var icon_px := _icon_screen_px(z) + 4.0
		var half := icon_px * 0.5 + BADGE_PX * 0.35
		var host_pid := int(host.get("pid", 0))
		var host_world: Vector2 = host.get("world", Vector2.ZERO) as Vector2
		## Never the raw member centroid — that sat on the Rhine south end
		## and dropped RX-1 mid_river 0.749 → 0.631 while individual-icon
		## occlusion still passed (cluster marker was unsampled).
		var others: Array[Vector2] = []
		for rec in _icons:
			var opid := int(rec.get("pid", 0))
			if opid == host_pid or pids.has(opid):
				continue
			var ow: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
			if ow.is_finite() and ow != Vector2.ZERO:
				others.append(ow)
		var world := _nudge_cluster_world(host_pid, host_world, z, half, others)
		var scr := _screen_of(world)
		out.append({
			"pid": host_pid,
			"pids": pids,
			"cluster": true,
			"count": idxs.size(),
			"world": world,
			"screen": scr,
			"rect": Rect2(scr - Vector2(half, half), Vector2(half, half) * 2.0),
			"level": hi,
			"level_tag": "L%d" % hi,
			"state": "intact",
			"tex_key": texture_key_for_level(hi, "intact"),
		})
	return out


func _pick_cluster_host(items: Array[Dictionary], idxs: Array) -> Dictionary:
	var mean := Vector2.ZERO
	for ii in idxs:
		mean += items[int(ii)].get("world", Vector2.ZERO) as Vector2
	mean /= float(maxi(idxs.size(), 1))
	var course := _rhine_course_line()
	var pool: Array[int] = []
	for ii in idxs:
		var w: Vector2 = items[int(ii)].get("world", Vector2.ZERO) as Vector2
		if course.size() < 2 or _dist_to_polyline(w, course) >= RHINE_HOST_MIN_WORLD:
			pool.append(int(ii))
	if pool.is_empty():
		for ii in idxs:
			pool.append(int(ii))
	var best: Dictionary = items[pool[0]]
	var best_lv := int(best.get("level", 1))
	var best_d := (best.get("world", Vector2.ZERO) as Vector2).distance_to(mean)
	for ii in pool:
		var it: Dictionary = items[ii]
		var lv := int(it.get("level", 1))
		var d := (it.get("world", Vector2.ZERO) as Vector2).distance_to(mean)
		if lv > best_lv or (lv == best_lv and d < best_d - 0.01):
			best = it
			best_lv = lv
			best_d = d
	return best


func _nudge_cluster_world(
	pid: int,
	cand: Vector2,
	zoom: float,
	half_px: float,
	others: Array[Vector2] = [],
) -> Vector2:
	if not cand.is_finite() or pid <= 0:
		return cand
	## Headless dummy rings have no Rhine / spine — keep the host interior.
	if not _test_polygons.is_empty():
		return cand
	var z := maxf(zoom, 0.04)
	## FIX #3: edge of the cluster rect must sit ≥ CLEAR_MARGIN_PX from
	## Rhine / spine at this zoom (hardest at site-min ~0.62).
	var need := (half_px + CLEAR_MARGIN_PX) / z
	## Screen-rect AABB (not Euclidean): a west walk of ~8u kept Viersen
	## "clear" by distance while the 0.70 cluster/isolate squares crossed.
	var isolate_half := _icon_screen_px(z) * 0.5 + BADGE_PX * 0.35
	var iso_need := (half_px + isolate_half + 2.0) / z
	var lines := _corridor_polylines()
	if (
		_cluster_site_clear(pid, cand, need, lines, z)
		and _cluster_iso_clear(cand, others, iso_need)
	):
		return cand
	var best := cand
	var best_s := _cluster_site_score(cand, lines, z)
	var step := maxf(1.4, need * 0.18)
	var r := step
	while r <= need * 2.2:
		var ang := 0.0
		while ang < TAU:
			var q: Vector2 = cand + Vector2(cos(ang), sin(ang)) * r
			if _cluster_own_interior(pid, q) and _cluster_iso_clear(q, others, iso_need):
				var s := _cluster_site_score(q, lines, z)
				if s > best_s + 0.4:
					best_s = s
					best = q
				if s >= need:
					return q
			ang += PI / 8.0
		r += step
	return best


func _cluster_iso_clear(world: Vector2, others: Array[Vector2], need: float) -> bool:
	for o in others:
		if absf(world.x - o.x) < need and absf(world.y - o.y) < need:
			return false
	return true


func _cluster_own_interior(pid: int, world: Vector2) -> bool:
	var p: Object = _provinces_for_scan().get(pid, null)
	var ring := _ring_for(pid, p)
	var centroid := _centroid_for(pid, p)
	var wr := _world_ring(ring, centroid)
	if wr.size() >= 3 and not Geometry2D.is_point_in_polygon(world, wr):
		return false
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_at_world_pos"):
		return int(mm.call("get_province_at_world_pos", world, true)) == pid
	return true


func _cluster_site_clear(pid: int, world: Vector2, need: float, lines: Array, zoom: float) -> bool:
	if not _cluster_own_interior(pid, world):
		return false
	return _cluster_site_score(world, lines, zoom) >= need


func _cluster_site_score(world: Vector2, lines: Array, zoom: float) -> float:
	var best := 1.0e9
	for line_v in lines:
		if not (line_v is PackedVector2Array):
			continue
		var line: PackedVector2Array = line_v
		best = minf(best, _dist_to_polyline(world, line))
	var kc := _mm_centroid(KOELN_PID)
	if kc != Vector2.ZERO:
		var chx := 28.0 / maxf(zoom, 0.04)
		var chy := 20.0 / maxf(zoom, 0.04)
		var dx := absf(world.x - kc.x) - chx
		var dy := absf(world.y - kc.y) - chy
		best = minf(best, maxf(dx, dy))
	var lux := _mm_centroid(LUX_CAPITAL_PID)
	if lux != Vector2.ZERO:
		best = minf(best, world.distance_to(lux) - 56.0)
	return best


func _dist_to_polyline(p: Vector2, line: PackedVector2Array) -> float:
	if line.size() < 2:
		return 1.0e9
	var best := 1.0e9
	for i in range(line.size() - 1):
		best = minf(best, _dist_seg(p, line[i], line[i + 1]))
	return best


func _corridor_polylines() -> Array:
	var out: Array = []
	var spine := _pids_polyline(SPINE_PIDS)
	var rhine := _pids_polyline(RHINE_WALK_PIDS)
	var course := _rhine_course_line()
	if spine.size() >= 2:
		out.append(spine)
	if rhine.size() >= 2:
		out.append(rhine)
	if course.size() >= 2:
		out.append(course)
	return out


func _rhine_course_line() -> PackedVector2Array:
	if not _test_polygons.is_empty():
		return PackedVector2Array()
	## Static course_points() — do not .call()/.has_method() on the class
	## (Godot parse: those are instance methods; -s instantiate then fails).
	return MapCanvasConfigScript.scale_points(Rx1RhineCrossingScript.course_points())


func _pids_polyline(pids: Array[int]) -> PackedVector2Array:
	var line := PackedVector2Array()
	for pid in pids:
		var c := _mm_centroid(pid)
		if c != Vector2.ZERO:
			line.append(c)
	return line


func _mm_centroid(pid: int) -> Vector2:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_centroid"):
		var c: Vector2 = mm.call("get_province_centroid", pid)
		if c != Vector2.ZERO:
			return c
	return Vector2.ZERO


func _draw() -> void:
	_drawn_count = 0
	_last_markers.clear()
	if not _should_draw():
		return
	var z := _canvas_zoom()
	var markers := _build_markers()
	_last_markers = markers
	for rec in markers:
		var world: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
		if not world.is_finite():
			continue
		var layout := _layout_drawn_marker(rec, z)
		var icon_px: float = float(layout.get("icon_px", 0.0))
		if not _in_viewport(world, icon_px + 20.0):
			continue
		var level: int = clampi(int(layout.get("level", 1)), 1, 4)
		var tex_key: String = str(rec.get("tex_key", texture_key_for_level(level, "intact")))
		var icon_tex := _load_tex(tex_key, 32)
		if icon_tex == null:
			continue
		var icon_rect: Rect2 = layout.get("icon_rect", Rect2()) as Rect2
		var cluster := bool(rec.get("cluster", false))
		if z + 0.0001 >= CLOSE_ZOOM:
			_draw_icon_halo(icon_rect, z)
		draw_texture_rect(icon_tex, icon_rect, false)
		if z + 0.0001 >= CLOSE_ZOOM and not cluster:
			var pips := _load_tex("level_pips_l%d" % level, 32)
			if pips != null:
				var pw := icon_rect.size.x * 0.55
				var ph := pw * 0.25
				var pip_rect := Rect2(
					Vector2(icon_rect.position.x + (icon_rect.size.x - pw) * 0.5, icon_rect.position.y + icon_rect.size.y * 0.62),
					Vector2(pw, ph)
				)
				pip_rect = _clamp_rect_inside(pip_rect, icon_rect)
				draw_texture_rect(pips, pip_rect, false)
		if cluster:
			_draw_cluster_count(layout, z)
			_draw_level_tag_in(layout, z)
		elif int(layout.get("count", 0)) >= 1:
			_draw_outlined_badge_in(layout)
		_drawn_count += 1


func anchor_edge_world(pid: int) -> float:
	var rec: Variant = _json_anchors.get(str(pid), {})
	if rec is Dictionary:
		return float((rec as Dictionary).get("edge_dist", 0.0)) * THEATER_SCALE
	return 0.0


func get_cluster_level_tag() -> String:
	for rec in _last_markers:
		if bool(rec.get("cluster", false)):
			return str(rec.get("level_tag", "L%d" % int(rec.get("level", 0))))
	return ""


func marker_half_px(zoom: float, cluster: bool) -> float:
	var px := _drawn_icon_px(zoom, cluster)
	var halo := 0.0
	if zoom + 0.0001 >= CLOSE_ZOOM:
		halo = HALO_PX
	return px * 0.5 + halo


func report_clearance_at_zoom(zoom: float) -> Dictionary:
	var markers := compute_markers_at_zoom(zoom)
	var course := _rhine_course_line()
	var spine := _pids_polyline(SPINE_PIDS)
	var worst := 1.0e9
	var fails: Array[int] = []
	for rec_v in markers:
		var rec: Dictionary = rec_v
		var world: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
		var cluster := bool(rec.get("cluster", false))
		var half := marker_half_px(zoom, cluster)
		var d_r := _dist_to_polyline(world, course) * zoom - half
		var d_s := _dist_to_polyline(world, spine) * zoom - half
		worst = minf(worst, minf(d_r, d_s))
		if d_r + 0.01 < CLEAR_MARGIN_PX or d_s + 0.01 < CLEAR_MARGIN_PX:
			fails.append(int(rec.get("pid", 0)))
	return {
		"ok": fails.is_empty(),
		"worst": worst,
		"fail_pids": fails,
		"count": markers.size(),
	}


func disc_sample_worlds(world: Vector2, zoom: float, cluster: bool = false) -> Array[Vector2]:
	var half := marker_half_px(zoom, cluster) / maxf(zoom, 0.04)
	var out: Array[Vector2] = [world]
	var i := 0
	while i < 8:
		var ang := float(i) * TAU / 8.0
		out.append(world + Vector2(cos(ang), sin(ang)) * half)
		out.append(world + Vector2(cos(ang), sin(ang)) * half * 0.5)
		i += 1
	return out


func _draw_icon_halo(icon_rect: Rect2, zoom: float) -> void:
	var halo := _world_size_at(HALO_PX, zoom)
	if halo <= 0.0:
		return
	var oval := _oval_rect(icon_rect)
	_draw_ellipse_outline(oval.grow(halo), Color(0.04, 0.03, 0.02, 0.62), halo * 1.15)
	_draw_ellipse_outline(oval.grow(halo * 0.45), Color(0.07, 0.06, 0.05, 0.80), halo * 0.70)


func _draw_ellipse_outline(r: Rect2, color: Color, width: float) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0 or width <= 0.0:
		return
	var c := r.get_center()
	var rx := r.size.x * 0.5
	var ry := r.size.y * 0.5
	var pts := PackedVector2Array()
	var n := 28
	var i := 0
	while i <= n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		i += 1
	draw_polyline(pts, color, width, true)


func _draw_cluster_count(layout: Dictionary, zoom: float) -> void:
	var badge: Rect2 = layout.get("badge_rect", Rect2()) as Rect2
	if badge.size.x <= 0.01:
		return
	var center := badge.get_center()
	var radius := badge.size.x * 0.5
	draw_circle(center, radius, Color(0.05, 0.04, 0.03, 0.96))
	var rim := _world_size_at(1.1, zoom)
	draw_arc(center, radius * 0.90, 0.0, TAU, 28, Color(0.94, 0.90, 0.74, 0.90), rim)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var z := maxf(zoom, 0.04)
	var font_sz := maxi(1, int(round(COUNT_DIGIT_PX / z)))
	var n := clampi(int(layout.get("count", 1)), 1, 9)
	var digit := str(n)
	var sz: Vector2 = font.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz)
	draw_string(
		font,
		center + Vector2(-sz.x * 0.5, sz.y * 0.32),
		digit,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_sz,
		Color(0.99, 0.97, 0.90, 1.0)
	)


func _draw_level_tag_in(layout: Dictionary, zoom: float) -> void:
	var tag_rect: Rect2 = layout.get("tag_rect", Rect2()) as Rect2
	if tag_rect.size.x <= 0.01:
		return
	var center := tag_rect.get_center()
	draw_circle(center, tag_rect.size.x * 0.52, Color(0.05, 0.04, 0.03, 0.92))
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var z := maxf(zoom, 0.04)
	var font_sz := maxi(1, int(round(10.0 / z)))
	var tag := "L%d" % clampi(int(layout.get("level", 1)), 1, 4)
	var sz: Vector2 = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz)
	draw_string(
		font,
		center + Vector2(-sz.x * 0.5, sz.y * 0.28),
		tag,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_sz,
		Color(0.96, 0.88, 0.48, 1.0)
	)


func _draw_outlined_badge_in(layout: Dictionary) -> void:
	var badge: Rect2 = layout.get("badge_rect", Rect2()) as Rect2
	if badge.size.x <= 0.01:
		return
	draw_circle(badge.get_center(), badge.size.x * 0.52, Color(0.05, 0.04, 0.03, 0.92))
	var n := clampi(int(layout.get("count", 1)), 1, 5)
	var tex := _load_tex("level_badge_l%d" % n, 16)
	if tex != null:
		draw_texture_rect(tex, badge, false)


func _draw_level_tag(world: Vector2, icon_world: float, level: int) -> void:
	## Kept for headless needles. Draw uses `_draw_level_tag_in` (same geometry as hit-test).
	var rec := {"world": world, "cluster": true, "level": level, "count": 1, "pid": 0}
	var layout := _layout_drawn_marker(rec, _canvas_zoom())
	_draw_level_tag_in(layout, _canvas_zoom())
	if icon_world <= 0.0:
		pass


func _draw_outlined_badge(world: Vector2, icon_world: float, number: int) -> void:
	## Kept for headless needles. Draw uses `_draw_outlined_badge_in`.
	var rec := {"world": world, "cluster": false, "level": number, "count": number, "pid": 0}
	var layout := _layout_drawn_marker(rec, _canvas_zoom())
	_draw_outlined_badge_in(layout)
	if icon_world <= 0.0:
		pass
