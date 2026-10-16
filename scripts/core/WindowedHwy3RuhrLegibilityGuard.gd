extends SceneTree

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")

## HWY-3 FIX #5: Ruhr live legibility at Essen (7356, 1606) z 2.4 / 4.0.
## Boots TestScenario through ScenarioLoader like Play. Pixel-samples highway
## casing along the metro chain; requires ≥3 hub city labels. Fixed orientation.
##
##   tools/eoa_hwy3_ruhr_legibility_guard.sh

const ESSEN_POS := Vector2(7356, 1606)
const Z_MID := 2.4
const Z_CLOSE := 4.0
const WAIT_MAP_SECS := 420
const SETTLE_FRAMES := 36
const CASING_MIN_Z24 := 60
const CASING_MIN_Z4 := 120
const RIVER_Z := 22

enum Phase {
	WAIT_MAP,
	SETTLE,
	CAPTURE,
	MUTANTS,
	DONE,
}

var _phase: int = Phase.WAIT_MAP
var _after_settle: int = Phase.CAPTURE
var _t0_msec: int = 0
var _settle_left: int = 0
var _fail_reasons: PackedStringArray = PackedStringArray()
var _out_dir: String = ""
var _captures: PackedStringArray = PackedStringArray()
var _last_wait_log: int = -1
var _image_y_flipped: bool = false
var _orient_ready: bool = false
var _capture_i: int = 0
var _z24_px: int = 0
var _z4_px: int = 0
var _z24_labels: int = 0
var _z4_labels: int = 0


func _init() -> void:
	_t0_msec = Time.get_ticks_msec()
	call_deferred("_start")


func _start() -> void:
	var ds := DisplayServer.get_name()
	_log("WindowedHwy3RuhrLegibilityGuard: DisplayServer=%s" % ds)
	if ds == "headless":
		_fail_reasons.append("headless_display")
		_finish(false)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_out_dir = OS.get_environment("EOA_HWY3_RUHR_OUT").strip_edges()
	if _out_dir.is_empty():
		_out_dir = "/tmp/eoa-hwy3-ruhr"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts"):
		DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/hwy3-ruhr")
	if OS.get_environment("EOA_SMOKE_AUTO_BEGIN").strip_edges() != "1":
		OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	var err := change_scene_to_file("res://scenes/TestScenario.tscn")
	if err != OK:
		_fail_reasons.append("scene_load_%d" % err)
		_finish(false)
		return
	_phase = Phase.WAIT_MAP
	if not process_frame.is_connected(_on_process):
		process_frame.connect(_on_process)


func _on_process() -> void:
	match _phase:
		Phase.WAIT_MAP:
			_tick_wait_map()
		Phase.SETTLE:
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = _after_settle
		Phase.CAPTURE:
			_do_capture()
		Phase.MUTANTS:
			_do_mutants()
		Phase.DONE:
			pass


func _go_settle(next_phase: int) -> void:
	_after_settle = next_phase
	_settle_left = SETTLE_FRAMES
	_phase = Phase.SETTLE


func _tick_wait_map() -> void:
	var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
	if elapsed >= WAIT_MAP_SECS:
		_fail_reasons.append("map_timeout")
		_finish(false)
		return
	if elapsed != _last_wait_log and elapsed > 0 and elapsed % 15 == 0:
		_last_wait_log = elapsed
		_log("HWY3_RUHR who=wait elapsed=%d n=%d" % [elapsed, _province_count()])
	_dismiss_title_if_needed()
	if not _map_is_ready():
		return
	if int(root.get_meta("hwy3_ruhr_ready_msec", 0)) == 0:
		root.set_meta("hwy3_ruhr_ready_msec", Time.get_ticks_msec())
		return
	if Time.get_ticks_msec() - int(root.get_meta("hwy3_ruhr_ready_msec", 0)) < 2000:
		return
	_pause_clock_only()
	_force_political_clean()
	_set_units_view(false)
	var ol := _overlay()
	if ol != null and ol.has_method("rebuild_road_layer"):
		ol.call("rebuild_road_layer")
	_log("HWY3_RUHR who=map_ready n=%d" % _province_count())
	_go_settle(Phase.CAPTURE)


func _do_capture() -> void:
	var bands: Array = [
		{"name": "z24", "z": Z_MID, "min_px": CASING_MIN_Z24},
		{"name": "z4", "z": Z_CLOSE, "min_px": CASING_MIN_Z4},
	]
	if _capture_i >= bands.size():
		_go_settle(Phase.MUTANTS)
		return
	var row: Dictionary = bands[_capture_i]
	_frame_essen(float(row["z"]))
	_settle_left = SETTLE_FRAMES
	_after_settle = Phase.CAPTURE
	if _settle_left > 0 and int(root.get_meta("hwy3_ruhr_band", -1)) != _capture_i:
		root.set_meta("hwy3_ruhr_band", _capture_i)
		_phase = Phase.SETTLE
		return
	var img := _capture("ruhr_essen_%s" % str(row["name"]))
	if img == null:
		_fail_reasons.append("capture_%s" % str(row["name"]))
		_finish(false)
		return
	if not _orient_ready:
		_image_y_flipped = _detect_image_y_flip(img)
		_orient_ready = true
		_log("HWY3_RUHR who=orient HWY3_FIXED_ORIENTATION=1 flipped=%s" % str(_image_y_flipped))
	var px: int = _count_ruhr_casing_px(img)
	var labels: Array = _ruhr_label_names()
	_log(
		"HWY3_RUHR who=sample zoom=%.2f casing_px=%d labels=%d names=%s"
		% [float(row["z"]), px, labels.size(), str(labels)]
	)
	if str(row["name"]) == "z24":
		_z24_px = px
		_z24_labels = labels.size()
	else:
		_z4_px = px
		_z4_labels = labels.size()
	if px < int(row["min_px"]):
		_fail_reasons.append("casing_%s_%d" % [str(row["name"]), px])
	if labels.size() < 3:
		_fail_reasons.append("labels_%s_%d" % [str(row["name"]), labels.size()])
	if _hub_labels_overlap():
		_fail_reasons.append("label_overlap_%s" % str(row["name"]))
	if _koln_label_count() > 1:
		_fail_reasons.append("koln_dup_%s_%d" % [str(row["name"]), _koln_label_count()])
	_capture_i += 1
	root.set_meta("hwy3_ruhr_band", -1)
	_phase = Phase.CAPTURE


func _do_mutants() -> void:
	var ol := _overlay()
	_frame_essen(Z_MID)
	if ol != null and ol.has_method("_sync_hub_city_labels"):
		ol.call("_sync_hub_city_labels")
	var before: int = _ruhr_label_names().size()
	_hide_hub_labels()
	var after_off: int = _ruhr_label_names().size()
	_log("HWY3_RUHR who=mutant_labels_off before=%d after=%d" % [before, after_off])
	if after_off >= 3:
		_fail_reasons.append("labels_off_survived")
	else:
		_log("HWY3_RUHR who=mutant_labels_off killed")
	if ol != null and ol.has_method("_sync_hub_city_labels"):
		ol.call("_sync_hub_city_labels")
	var hwy_z: int = 0
	if ol != null and ol.has_method("get_highway_draw_z_index"):
		hwy_z = int(ol.call("get_highway_draw_z_index"))
	var node: Node = null
	if ol != null and ol.has_method("get_road_tier_draw"):
		var nv: Variant = ol.call("get_road_tier_draw", 2)
		if nv is Node2D:
			node = nv
	var z_before: int = hwy_z
	if node is Node2D:
		(node as Node2D).z_as_relative = false
		(node as Node2D).z_index = 20
	var z_after: int = -1
	if node is Node2D:
		z_after = (node as Node2D).z_index
	if ol != null and ol.has_method("get_highway_draw_z_index"):
		z_after = int(ol.call("get_highway_draw_z_index"))
	_log("HWY3_RUHR who=mutant_under_river before=%d after=%d river=%d" % [z_before, z_after, RIVER_Z])
	if z_after > RIVER_Z:
		_fail_reasons.append("under_river_survived")
	else:
		_log("HWY3_RUHR who=mutant_under_river killed")
	if node is Node2D:
		(node as Node2D).z_index = 24
	if z_before <= RIVER_Z:
		_fail_reasons.append("highway_under_river")
	if ol != null and ol.has_method("get_hub_label_candidates_uncull"):
		var raw_v: Variant = ol.call("get_hub_label_candidates_uncull")
		var raw: Array = raw_v if typeof(raw_v) == TYPE_ARRAY else []
		var had_overlap: bool = RoadTierVisualScript.hwy3_labels_have_overlap(raw)
		_log("HWY3_RUHR who=mutant_no_cull raw=%d overlap=%s" % [raw.size(), str(had_overlap)])
		if had_overlap:
			_log("HWY3_RUHR who=mutant_no_cull killed")
		else:
			_fail_reasons.append("no_cull_survived")
	var ok: bool = _fail_reasons.is_empty()
	_log(
		"HWY3_RUHR bars z24_px=%d z4_px=%d z24_labels=%d z4_labels=%d hwy_z=%d"
		% [_z24_px, _z4_px, _z24_labels, _z4_labels, z_before]
	)
	_finish(ok)


func _frame_essen(zoom: float) -> void:
	var pos: Vector2 = ESSEN_POS
	var cam := _camera()
	if cam != null:
		cam.global_position = pos
		cam.zoom = Vector2(zoom, zoom)
	var mr := _map_renderer()
	if mr != null and mr.has_method("player_path_wheel_toward_world"):
		mr.call("player_path_wheel_toward_world", pos, zoom)
	cam = _camera()
	if cam != null:
		cam.global_position = pos
		cam.zoom = Vector2(zoom, zoom)
	var ol := _overlay()
	if ol != null and ol.has_method("_apply_screen_space_road_widths"):
		ol.call("_apply_screen_space_road_widths")
	if ol != null and ol.has_method("_sync_hub_city_labels"):
		ol.call("_sync_hub_city_labels")
	if ol != null and ol.has_method("refresh_ix1_gold_spine"):
		ol.call("refresh_ix1_gold_spine", true)
	_log("HWY3_RUHR who=frame zoom=%.2f pos=%.1f,%.1f" % [zoom, pos.x, pos.y])


func _hub_labels_overlap() -> bool:
	var ol := _overlay()
	if ol == null or not ol.has_method("get_visible_hub_label_rects"):
		return false
	var raw_v: Variant = ol.call("get_visible_hub_label_rects")
	var raw: Array = raw_v if typeof(raw_v) == TYPE_ARRAY else []
	return RoadTierVisualScript.hwy3_labels_have_overlap(raw)


func _koln_label_count() -> int:
	var n: int = 0
	var ol := _overlay()
	if ol != null and ol.has_method("get_visible_hub_label_rects"):
		var raw_v: Variant = ol.call("get_visible_hub_label_rects")
		var raw: Array = raw_v if typeof(raw_v) == TYPE_ARRAY else []
		for row_v in raw:
			if typeof(row_v) != TYPE_DICTIONARY:
				continue
			var key: String = str((row_v as Dictionary).get("key", ""))
			if key == "koln":
				n += 1
	return n


func _ruhr_label_names() -> Array:
	var ol := _overlay()
	if ol == null or not ol.has_method("get_hub_city_label_names"):
		return []
	var raw_v: Variant = ol.call("get_hub_city_label_names")
	var raw: Array = raw_v if typeof(raw_v) == TYPE_ARRAY else []
	var out: Array = []
	for n_v in raw:
		var n: String = str(n_v).strip_edges().to_lower()
		if (
			n.contains("duisburg")
			or n.contains("essen")
			or n.contains("dortmund")
			or n.contains("düsseldorf")
			or n.contains("dusseldorf")
			or n.contains("bochum")
			or n.contains("mülheim")
			or n.contains("mulheim")
		):
			out.append(str(n_v))
	return out


func _hide_hub_labels() -> void:
	var ol := _overlay()
	if ol == null:
		return
	var layer: Node = ol.get_node_or_null("Hwy3HubCityLabels")
	if layer == null:
		return
	for ch in layer.get_children():
		if ch is CanvasItem:
			(ch as CanvasItem).visible = false


func _ruhr_highway_edges() -> Array:
	var ol := _overlay()
	if ol == null or not ol.has_method("get_road_tier_cache"):
		return []
	var cache_v: Variant = ol.call("get_road_tier_cache")
	if typeof(cache_v) != TYPE_ARRAY:
		return []
	var out: Array = []
	for row_v in cache_v:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		if int(row.get("display_tier", 0)) != 2:
			continue
		var c1: Vector2 = row.get("c1", Vector2.ZERO)
		var c2: Vector2 = row.get("c2", Vector2.ZERO)
		if c1 == Vector2.ZERO or c2 == Vector2.ZERO:
			continue
		var mid: Vector2 = (c1 + c2) * 0.5
		if mid.distance_to(ESSEN_POS) <= 50.0:
			out.append(row)
	return out


func _count_ruhr_casing_px(img: Image) -> int:
	if img == null:
		return 0
	var edges: Array = _ruhr_highway_edges()
	var layer := _road_layer()
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var seen: Dictionary = {}
	var n: int = 0
	var img_h: int = img.get_height()
	var img_w: int = img.get_width()
	for row_v in edges:
		var row: Dictionary = row_v
		var sa: Vector2 = xform * row.get("c1", Vector2.ZERO)
		var sb: Vector2 = xform * row.get("c2", Vector2.ZERO)
		if _image_y_flipped:
			sa = Vector2(sa.x, float(img_h) - sa.y)
			sb = Vector2(sb.x, float(img_h) - sb.y)
		var dist: float = sa.distance_to(sb)
		var steps: int = maxi(8, int(dist))
		for s in range(steps + 1):
			var p: Vector2 = sa.lerp(sb, float(s) / float(steps))
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var x: int = int(round(p.x + float(dx)))
					var y: int = int(round(p.y + float(dy)))
					if x < 0 or y < 0 or x >= img_w or y >= img_h:
						continue
					var key: int = x * 10000 + y
					if seen.has(key):
						continue
					if _is_highway_color(img.get_pixel(x, y)):
						seen[key] = true
						n += 1
	return n


func _is_highway_color(c: Color) -> bool:
	return (
		_near_rgb(c, Color(0.05, 0.05, 0.07), 0.10)
		or _near_rgb(c, Color(0.22, 0.24, 0.28), 0.10)
		or _near_rgb(c, Color(0.98, 0.94, 0.62), 0.12)
		or _near_rgb(c, Color(0.20, 0.22, 0.24), 0.10)
	)


func _near_rgb(c: Color, target: Color, tol: float) -> bool:
	return absf(c.r - target.r) + absf(c.g - target.g) + absf(c.b - target.b) <= tol * 3.0


func _detect_image_y_flip(img: Image) -> bool:
	if img == null:
		return false
	var layer := _road_layer()
	var xform := Transform2D.IDENTITY
	if layer != null:
		xform = layer.get_global_transform_with_canvas()
	var s: Vector2 = xform * ESSEN_POS
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 8 or h < 8:
		return false
	var x: int = clampi(int(round(s.x)), 1, w - 2)
	var y: int = clampi(int(round(s.y)), 1, h - 2)
	var yf: int = clampi(h - 1 - int(round(s.y)), 1, h - 2)
	var uf: Color = img.get_pixel(x, y)
	var ff: Color = img.get_pixel(x, yf)
	var uf_land: bool = uf.r > uf.b + 0.05 and uf.r > 0.22
	var ff_land: bool = ff.r > ff.b + 0.05 and ff.r > 0.22
	return ff_land and not uf_land


func _capture(name: String) -> Image:
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var vp := root.get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	_captures.append(path)
	if DirAccess.dir_exists_absolute("/opt/cursor/artifacts/hwy3-ruhr"):
		img.save_png("/opt/cursor/artifacts/hwy3-ruhr/%s.png" % name)
	if DirAccess.dir_exists_absolute("/workspace/docs/evidence/hwy3"):
		img.save_png("/workspace/docs/evidence/hwy3/%s.png" % name)
	_log("HWY3_RUHR who=capture file=%s %dx%d" % [path, img.get_width(), img.get_height()])
	return img


func _overlay() -> Node:
	return _find_named("InfrastructureOverlayLayer")


func _road_layer() -> CanvasItem:
	var ol := _overlay()
	if ol != null:
		var ch := ol.get_node_or_null("RoadLayer")
		if ch is CanvasItem:
			return ch as CanvasItem
	return _find_named("RoadLayer") as CanvasItem


func _map_renderer() -> Node:
	var nodes: Array = get_nodes_in_group("map_renderer")
	if nodes.size() > 0:
		return nodes[0] as Node
	return _find_named("WorldMap")


func _map_manager() -> Node:
	return root.get_node_or_null("MapManager")


func _camera() -> Camera2D:
	var mr := _map_renderer()
	if mr != null:
		var named_cam := mr.get_node_or_null("MapCamera") as Camera2D
		if named_cam != null:
			return named_cam
	var vp := root.get_viewport()
	if vp != null:
		return vp.get_camera_2d()
	return null


func _find_named(nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, false)


func _set_units_view(on: bool) -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_unit_counters_visible"):
		mr.call("set_unit_counters_visible", on)


func _force_political_clean() -> void:
	var mr := _map_renderer()
	if mr != null and mr.has_method("set_map_mode"):
		mr.call("set_map_mode", "political")


func _map_is_ready() -> bool:
	if not _title_has_closed():
		return false
	if _province_count() < 3000:
		return false
	return _map_renderer() != null and _camera() != null


func _title_has_closed() -> bool:
	var tm: Node = _time_manager()
	if tm != null and tm.has_method("living_title_has_closed"):
		if bool(tm.call("living_title_has_closed")):
			return true
	var boot: Node = _find_named("LivingTitleBoot")
	if boot != null and bool(boot.get("_closed")):
		return true
	if boot == null and _province_count() >= 3000:
		var elapsed := int((Time.get_ticks_msec() - _t0_msec) / 1000.0)
		if elapsed >= 8:
			return true
	return false


func _time_manager() -> Node:
	if root != null:
		var tm: Node = root.get_node_or_null("TimeManager")
		if tm != null:
			return tm
	return _find_named("TimeManager")


func _dismiss_title_if_needed() -> void:
	var boot: Node = _find_named("LivingTitleBoot")
	if boot == null:
		return
	if bool(boot.get("_closed")):
		return
	OS.set_environment("EOA_SMOKE_AUTO_BEGIN", "1")
	if boot.has_method("apply_smoke_auto_begin"):
		boot.call("apply_smoke_auto_begin")
	if not bool(boot.get("_closed")) and boot.has_method("handle_live_begin"):
		boot.call("handle_live_begin")


func _province_count() -> int:
	var mm := _map_manager()
	if mm != null and mm.has_method("get_province_count"):
		return int(mm.call("get_province_count"))
	return 0


func _pause_clock_only() -> void:
	var tm: Node = _time_manager()
	if tm != null and tm.has_method("set_paused"):
		tm.call("set_paused", true)


func _log(msg: String) -> void:
	print(msg)
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _finish(ok: bool) -> void:
	_phase = Phase.DONE
	if not ok and _fail_reasons.is_empty():
		_fail_reasons.append("unknown")
	_log("WindowedHwy3RuhrLegibilityGuard: RESULT=%s reasons=%s captures=%d" % [
		"PASS" if ok else "FAIL", ",".join(_fail_reasons), _captures.size()
	])
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)
