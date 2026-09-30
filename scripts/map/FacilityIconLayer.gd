# scripts/map/FacilityIconLayer.gd
## FAC-1a: transparent top-down airfield icons on the political map.
## One _draw() pass with draw_texture_rect. No Line2D children, no per-icon
## nodes, no absolute-coordinate AA polylines (IX-1 OOM/hang class).
## Cached icon list rebuilds on site data change only — never on zoom.
class_name FacilityIconLayer
extends Node2D

const FAC_DIR := "res://assets/graphics/icons/facilities/"
const MID_ICON_PX := 18.0
const CLOSE_ICON_PX := 26.0
const CLOSE_ZOOM := 1.0
const MAP_Z := 24
## Above roads (~21) / Rhine (22), below DemoUnitIcon (28) and name labels (82).
const UNIT_COUNTER_Z := 28
const VISIBLE_MODES: Array[String] = ["political", "diplomacy", "infra"]

var show_facilities: bool = true
var _icons: Array[Dictionary] = []
var _rebuild_count: int = 0
var _drawn_count: int = 0
var _last_zoom: float = -1.0
var _last_cam_pos: Vector2 = Vector2.INF
var _tex_cache: Dictionary = {}
var _test_provinces: Dictionary = {}
var _test_centroids: Dictionary = {}
var _test_zoom: float = -1.0
var _test_board_n: int = 0
var _test_map_mode: String = ""


func _ready() -> void:
	name = "FacilityIconLayer"
	z_as_relative = false
	z_index = MAP_Z
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	if typeof(SpecialSiteManager) != TYPE_NIL and SpecialSiteManager.has_signal("special_site_created"):
		if not SpecialSiteManager.special_site_created.is_connected(_on_special_site_created):
			SpecialSiteManager.special_site_created.connect(_on_special_site_created)
	rebuild_icon_list()
	queue_redraw()


func _on_special_site_created(_site: SpecialSite, _province_id: int) -> void:
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


func count_icons_that_would_draw() -> int:
	## Headless-safe: same gates as _draw, no viewport / GPU required.
	if not _should_draw():
		return 0
	return _icons.size()


func setup_for_test(provinces: Dictionary, centroids: Dictionary, board_n: int = 0) -> void:
	_test_provinces = provinces
	_test_centroids = centroids
	_test_board_n = board_n
	rebuild_icon_list()


func set_test_zoom(zoom: float) -> void:
	_test_zoom = zoom
	queue_redraw()


func set_test_map_mode(mode: String) -> void:
	_test_map_mode = mode.strip_edges().to_lower()
	queue_redraw()


func max_facility_icons_for_board(province_count: int) -> int:
	## Local budget (do not edit MapZoomLOD). Mirrors the resource-icon style.
	if province_count >= 3000:
		return 180
	if province_count >= 800:
		return 360
	return 9999


static func visual_state_for_site(site: SpecialSite) -> String:
	## Damaged is a data flag only for FAC-1a. DESTROYED counts as damaged.
	if site == null:
		return "intact"
	if int(site.damage_level) > 0:
		return "damaged"
	if site.construction_state == SpecialSite.ConstructionState.DAMAGED:
		return "damaged"
	if site.construction_state == SpecialSite.ConstructionState.DESTROYED:
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
	var provinces: Dictionary = _provinces_for_scan()
	var budget: int = max_facility_icons_for_board(_board_province_count(provinces))
	var added: int = 0
	for pid_v in provinces.keys():
		if added >= budget:
			break
		var p: Province = provinces[pid_v] as Province
		if p == null or p.is_sea:
			continue
		var site: SpecialSite = _best_airfield_on_province(p)
		if site == null:
			continue
		var level: int = clampi(int(site.tier), 1, 4)
		var state: String = visual_state_for_site(site)
		## FAC-1a: no damaged art yet — draw intact + TODO in _draw.
		var tex_key := texture_key_for_level(level, "intact")
		var world: Vector2 = _centroid_for(int(p.id), p)
		_icons.append({
			"pid": int(p.id),
			"world": world,
			"level": level,
			"state": state,
			"tex_key": tex_key,
			"site_id": str(site.id),
		})
		added += 1


func _best_airfield_on_province(p: Province) -> SpecialSite:
	if p == null or p.special_sites.is_empty():
		return null
	var best: SpecialSite = null
	var best_tier: int = -1
	for site in p.special_sites:
		if site == null:
			continue
		if site.site_type != SpecialSite.SiteType.AIRFIELD:
			continue
		if site.construction_state == SpecialSite.ConstructionState.NOT_BUILT:
			continue
		var t: int = int(site.tier)
		if t > best_tier:
			best = site
			best_tier = t
	return best


func _provinces_for_scan() -> Dictionary:
	if not _test_provinces.is_empty():
		return _test_provinces
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
		var all: Variant = MapManager.get_all_provinces()
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
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_count"):
		return maxi(provinces.size(), int(MapManager.get_province_count()))
	return provinces.size()


func _centroid_for(pid: int, p: Province) -> Vector2:
	if _test_centroids.has(pid):
		return _test_centroids[pid] as Vector2
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
		var c: Vector2 = MapManager.get_province_centroid(pid)
		if c != Vector2.ZERO:
			return c
	if p != null:
		return p.coordinates
	return Vector2.ZERO


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
	## KEY_P is unused on MapRenderer / MapViewInput. Layer-local so MV-1 paths stay untouched.
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
	if zoom >= CLOSE_ZOOM:
		return CLOSE_ICON_PX
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


func _draw() -> void:
	_drawn_count = 0
	if not _should_draw():
		return
	var z := _canvas_zoom()
	var screen_px := _icon_screen_px(z)
	var world_px := _world_size(screen_px)
	var close := z >= CLOSE_ZOOM
	var badge_px: float = 11.0 if not close else 12.0
	var pips_px: float = screen_px * 0.55
	for rec in _icons:
		var world: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
		if not world.is_finite():
			continue
		if not _in_viewport(world, screen_px + 20.0):
			continue
		var level: int = clampi(int(rec.get("level", 1)), 1, 4)
		var state: String = str(rec.get("state", "intact"))
		var tex_key: String = str(rec.get("tex_key", texture_key_for_level(level, "intact")))
		var icon_tex := _load_tex(tex_key, 32)
		if icon_tex == null:
			continue
		var rect := Rect2(world - Vector2(world_px, world_px) * 0.5, Vector2(world_px, world_px))
		draw_texture_rect(icon_tex, rect, false)
		## TODO(FAC-1a): damaged art not shipped — intact texture is drawn when state==damaged.
		if state == "damaged":
			pass
		if close:
			var pips := _load_tex("level_pips_l%d" % level, 32)
			if pips != null:
				var pw := _world_size(pips_px)
				var ph := pw * 0.25
				var pip_rect := Rect2(
					Vector2(world.x - pw * 0.5, world.y + world_px * 0.18),
					Vector2(pw, ph)
				)
				draw_texture_rect(pips, pip_rect, false)
		else:
			var badge := _load_tex("level_badge_l%d" % level, 16)
			if badge != null:
				var bw := _world_size(badge_px)
				var badge_rect := Rect2(
					Vector2(world.x + world_px * 0.18, world.y + world_px * 0.18),
					Vector2(bw, bw)
				)
				draw_texture_rect(badge, badge_rect, false)
		_drawn_count += 1
