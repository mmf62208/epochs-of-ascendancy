class_name CityLabelsLayer
extends Node2D

## ATLAS-1 view-only city names. Candidates load once. Collision reruns when
## the zoom band, zoom (±0.03), camera (~15% of the view), or live counters
## change — not on idle frames. Labels stay next to their own dots (small
## screen-space shift); overlapping lower-priority names are culled.
## Collision AABBs match the drawn glyph size. Live unit/air counters and
## already-placed city dots are obstacles. Same-city names collapse to one.
## Scenario capitals keep a dot and a label at mid zoom: nation/counter
## obstacles and cluster drops must not remove them.

const _LOD := preload("res://scripts/map/MapZoomLOD.gd")
const _Canvas := preload("res://scripts/map/MapCanvasConfig.gd")

## Above DemoUnitIcon (z 28) so a chip cannot hide Essen; dots sit just under text.
const CITY_Z := 30
const DOT_Z := 29
const MAX_ON_SCREEN := 60
const MID_TIER2_SCORE_FLOOR := 400.0
const LABEL_SHIFT_PX := 22.0
const CLOSE_SHIFT_PX := 22.0
const ANCHOR_MAX_PX := 30.0
## Ruhr cores may walk just past a chip half-width so the name sits beside
## the plate instead of on it (COUNTER_HALF.x 36 → ~44 px to the near edge).
const RUHR_ANCHOR_MAX_PX := 64.0
const COUNTER_INSET_PX := 12.0
const CLOSE_FONT_MIN_PX := 14
const COUNTER_MAX_SCREEN := Vector2(128.0, 160.0)
const OUTLINE_PAD_PX := 4.0
const ZOOM_REBUILD := 0.03
const PAN_REBUILD_FRAC := 0.15
const DEDUPE_WORLD := 36.0
const HUB_SCORE := 180.0
const DOT_BLOCK_PX := 6.0
const COUNTER_HALF := Vector2(36.0, 48.0)
const FILL_COLOR := Color(0.08, 0.07, 0.05, 1.0)
const OUTLINE_COLOR := Color(1.0, 0.97, 0.88, 1.0)
## Extra mid-zoom weight so Essen / the Rhine-Ruhr cores beat Hamm and Münster
## when Home-camera zoom-in ties on economy pop (all 20000).
const _RUHR_CORE := {
	710403: 90.0, # Essen
	710417: 80.0, # Köln
	710401: 70.0, # Düsseldorf
	710402: 70.0, # Duisburg
	710443: 60.0, # Dortmund
}

const _CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"
const _ECON_PATH := "res://data/provinces_world_accurate/province_economy_layer.json"
const _BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"
const _OWN_PATH := "res://data/provinces_world_accurate/province_ownership_1936.json"
const _GEO_PATH := "res://data/provinces_world_accurate/provinces_geometry.json"
const _SCENARIO_PATH := "res://data/scenarios/world_accurate.json"

const _ALIAS_FOLD := {
	"vienna": "wien",
	"munich": "munchen",
	"muenchen": "munchen",
	"cologne": "koln",
	"nuremberg": "nurnberg",
	"nurnberg": "nurnberg",
}

const _ALIAS_LOCAL := {
	"vienna": "Wien",
	"munich": "München",
	"muenchen": "München",
	"cologne": "Köln",
	"nuremberg": "Nürnberg",
	"nurnberg": "Nürnberg",
}

var rebuild_count: int = 0

var _candidates: Array = []
var _candidates_ready: bool = false
var _placed: Array = []
var _layout_ready: bool = false
var _last_band: int = -1
var _last_cam: Vector2 = Vector2(-1.0e9, -1.0e9)
var _last_vp: Vector2 = Vector2.ZERO
var _last_layout_zoom: float = -1.0
var _zoom: float = 1.0
var _cam: Vector2 = Vector2.ZERO
var _vp: Vector2 = Vector2(1920, 1080)
var _nation_override: Array = []
var _use_nation_override: bool = false
var _counter_override: Array = []
var _use_counter_override: bool = false
var _show_labels: bool = true
var _mode: String = "political"
var _font: Font = null
var _by_pid: Dictionary = {}
var _build_ms: float = -1.0
var _dots: Node2D = null
var _counters_dirty: bool = false
var _last_counter_sig: int = 0
var _last_counter_count: int = 0


func _ready() -> void:
	z_as_relative = false
	z_index = CITY_Z
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	var dots := _DotMarks.new()
	dots.name = "CityLabelDots"
	dots.host = self
	dots.z_as_relative = false
	dots.z_index = DOT_Z
	dots.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dots)
	_dots = dots
	ensure_candidates()


func bind_centroids(cents: Dictionary) -> void:
	if cents.is_empty() or _candidates.is_empty():
		ensure_candidates()
	for c in _candidates:
		var pid := int(c.get("pid", 0))
		if cents.has(pid):
			var w: Vector2 = cents[pid] as Vector2
			if w != Vector2.ZERO:
				c["world"] = w
				_by_pid[pid] = c
	_layout_ready = false


func set_labels_visible(on: bool) -> void:
	if _show_labels == on:
		return
	_show_labels = on
	_layout_ready = false
	if _candidates_ready:
		_resolve_layout()
	_queue_paint()


func set_map_mode(mode: String) -> void:
	var m := mode.strip_edges().to_lower()
	if m.is_empty():
		m = "political"
	var show := m != "states"
	if m == _mode and show == _show_labels:
		return
	var labels_changed := show != _show_labels
	_mode = m
	_show_labels = show
	if labels_changed:
		_layout_ready = false
		if _candidates_ready:
			_resolve_layout()
	_queue_paint()


func ensure_candidates() -> void:
	if _candidates_ready:
		return
	var t0 := Time.get_ticks_usec()
	_load_candidates()
	_candidates_ready = true
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func rebuild_candidates() -> void:
	_candidates_ready = false
	_candidates.clear()
	_by_pid.clear()
	rebuild_count += 1
	ensure_candidates()
	_layout_ready = false


func build_ms() -> float:
	ensure_candidates()
	return _build_ms


func fade_alpha(zoom: float, enter_zoom: float) -> float:
	return _LOD.city_label_fade_alpha(zoom, enter_zoom)


func _draw_alpha(zoom: float, enter_zoom: float) -> float:
	# Close-zoom names are full-opacity. The enter ramp is only for the
	# band edge so a city does not pop in at mid.
	if zoom > _LOD.CITY_LABEL_MID_MAX:
		return 1.0
	return _LOD.city_label_fade_alpha(zoom, enter_zoom)


func score_of(pid: int) -> float:
	ensure_candidates()
	if not _by_pid.has(pid):
		return -1.0
	return float((_by_pid[pid] as Dictionary).get("score", -1.0))


func world_of(pid: int) -> Vector2:
	ensure_candidates()
	if not _by_pid.has(pid):
		return Vector2.ZERO
	return (_by_pid[pid] as Dictionary).get("world", Vector2.ZERO) as Vector2


func screen_of(pid: int) -> Vector2:
	return _world_to_label_screen(world_of(pid))


func display_name_of(pid: int) -> String:
	ensure_candidates()
	if not _by_pid.has(pid):
		return ""
	return str((_by_pid[pid] as Dictionary).get("name", ""))


func cluster_key_of(pid: int) -> String:
	ensure_candidates()
	if not _by_pid.has(pid):
		return ""
	return str((_by_pid[pid] as Dictionary).get("cluster", _cluster_key(display_name_of(pid))))


func is_eligible(pid: int, band_name: String) -> bool:
	ensure_candidates()
	if not _by_pid.has(pid):
		return false
	return _in_band(_by_pid[pid], _zoom_for_band(band_name))


func eligible_count(band_name: String) -> int:
	ensure_candidates()
	var zoom := _zoom_for_band(band_name)
	var n := 0
	for c in _candidates:
		if _in_band(c, zoom):
			n += 1
	return n


func candidate_count() -> int:
	ensure_candidates()
	return _candidates.size()


func placed() -> Array:
	return _placed


func screen_count() -> int:
	var n := 0
	for p in _placed:
		if float(p.get("alpha", 0.0)) >= 0.04:
			n += 1
	return n


func has_visual_overlap() -> bool:
	var items: Array = []
	for p in _placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		items.append(p)
	for i in items.size():
		var a: Rect2 = (items[i] as Dictionary).get("screen_rect", Rect2())
		var a_pad := a.grow(OUTLINE_PAD_PX)
		for j in range(i + 1, items.size()):
			var b: Rect2 = (items[j] as Dictionary).get("screen_rect", Rect2())
			if a_pad.intersects(b.grow(OUTLINE_PAD_PX)):
				return true
			var other_dot: Rect2 = (items[j] as Dictionary).get("dot_rect", Rect2())
			if a.intersects(other_dot):
				return true
			var own_dot: Rect2 = (items[i] as Dictionary).get("dot_rect", Rect2())
			if own_dot.intersects(b):
				return true
	return false


func duplicate_drawn_names() -> PackedStringArray:
	var seen: Dictionary = {}
	var dups := PackedStringArray()
	for p in _placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		var nm := str(p.get("name", ""))
		var fold := _fold_drawn_name(nm)
		if fold.is_empty():
			continue
		if seen.has(fold):
			dups.append(nm)
		else:
			seen[fold] = true
	for row in _visible_screen_city_labels():
		var nm2 := str(row.get("text", ""))
		var fold2 := _fold_drawn_name(nm2)
		if fold2.is_empty():
			continue
		var is_hub := str(row.get("name", "")).begins_with("Hwy3Hub") or bool(row.get("hub", false))
		if not is_hub and not seen.has(fold2):
			continue
		if seen.has(fold2):
			dups.append(nm2)
		else:
			seen[fold2] = true
	return dups


func _fold_drawn_name(nm: String) -> String:
	var key := nm.strip_edges().to_lower()
	key = key.replace("ü", "u").replace("ö", "o").replace("ä", "a").replace("ß", "ss")
	if _ALIAS_FOLD.has(key):
		return str(_ALIAS_FOLD[key])
	return key


func _visible_screen_city_labels() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	var tree := get_tree()
	if tree == null or tree.root == null:
		return out
	var stack: Array = [tree.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == null:
			continue
		if node is Label:
			var lbl := node as Label
			if lbl.visible and is_instance_valid(lbl) and lbl.modulate.a >= 0.05:
				var text := str(lbl.text).strip_edges()
				if _is_citylike_label_text(text):
					var hub := str(lbl.name).begins_with("Hwy3Hub")
					var walk: Node = lbl.get_parent()
					while walk != null and not hub:
						if str(walk.name) == "Hwy3HubCityLabels" or str(walk.name) == "Ix1GoldSpineLabels":
							hub = true
							break
						walk = walk.get_parent()
					out.append({
						"text": text,
						"rect": _control_screen_rect(lbl),
						"name": str(lbl.name),
						"hub": hub,
					})
		for ch in node.get_children():
			stack.append(ch)
	return out


func _is_citylike_label_text(text: String) -> bool:
	if text.length() < 3 or text.length() > 24:
		return false
	if text.begins_with("Select") or text.begins_with("NEXT"):
		return false
	if " " in text and text.length() > 18:
		return false
	if text.contains("%") or text.contains(":") or text.contains("/"):
		return false
	return true


func chrome_screen_rects() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	var tree := get_tree()
	if tree == null or tree.root == null:
		return out
	var names: Array[String] = [
		"TopInfoBar", "MapModeToolbar", "FirstSessionTipStrip", "MapMinimap",
		"ProvinceHoverTooltip", "UnitDetailPopup", "LabelSpineStartNotice",
	]
	for nm in names:
		var n: Node = tree.root.find_child(nm, true, false)
		if n is Control:
			var c := n as Control
			if c.visible:
				var r := c.get_global_rect()
				if r.size.x > 2.0 and r.size.y > 2.0:
					out.append(r)
	return out


func labels_hit_chrome(chrome_rects: Array = []) -> PackedStringArray:
	var rects: Array = chrome_rects
	if rects.is_empty():
		rects = chrome_screen_rects()
	var hits := PackedStringArray()
	for p in _placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		var r: Rect2 = p.get("screen_rect", Rect2())
		for c in rects:
			if c is Rect2 and r.intersects(c as Rect2):
				hits.append(str(p.get("name", "")))
				break
	return hits


func anchor_distance_px(item: Dictionary) -> float:
	# Nearest edge of the glyph box to the city mark — a left-of-dot
	# "Duisburg" is still by its own dot even when the baseline is ~70 px west.
	var world: Vector2 = item.get("world", Vector2.ZERO)
	var rect: Rect2 = item.get("screen_rect", Rect2())
	return _rect_gap_from_point(rect, _world_to_label_screen(world))


func labels_hit_counters(counter_rects: Array = []) -> PackedStringArray:
	var rects: Array = counter_rects
	if rects.is_empty():
		if _use_counter_override:
			rects = _counter_override
		else:
			rects = _live_counter_rects()
	# Match packing: COUNTER_HALF is plate+bars with empty margin. A name
	# sitting beside the painted chip still clips that oversized AABB.
	var hit_rects: Array = _inset_counter_obstacles(rects, COUNTER_INSET_PX)
	var hits := PackedStringArray()
	for p in _placed:
		if float(p.get("alpha", 0.0)) < 0.04:
			continue
		var r: Rect2 = p.get("screen_rect", Rect2())
		for c in hit_rects:
			if c is Rect2 and r.intersects(c as Rect2):
				hits.append(str(p.get("name", "")))
				break
	return hits


func last_layout_zoom() -> float:
	return _last_layout_zoom


func last_counter_rect_count() -> int:
	return _last_counter_count


func set_view(zoom: float, camera_world: Vector2, viewport: Vector2, nation_rects: Array = [], counter_rects: Array = []) -> void:
	_zoom = zoom
	_cam = camera_world
	_vp = viewport
	if _vp.x < 8.0 or _vp.y < 8.0:
		_vp = Vector2(1920, 1080)
	_nation_override = nation_rects
	_use_nation_override = true
	_counter_override = counter_rects
	_use_counter_override = true
	_layout_ready = false
	_resolve_layout()
	_queue_paint()


## Live camera/zoom without freezing nation/counter obstacles to empty arrays.
func set_live_view(zoom: float, camera_world: Vector2, viewport: Vector2) -> void:
	_use_nation_override = false
	_use_counter_override = false
	_nation_override = []
	_counter_override = []
	sync_view(zoom, camera_world, viewport, true)


func notify_counters_dirty() -> void:
	_counters_dirty = true


## Live hysteresis. Idle frames with the same camera/zoom do not rebuild.
func sync_view(zoom: float, camera_world: Vector2, viewport: Vector2, force: bool = false) -> void:
	var vp := viewport
	if vp.x < 8.0 or vp.y < 8.0:
		vp = Vector2(1920, 1080)
	if not force and not _should_rebuild(zoom, camera_world, vp):
		_zoom = zoom
		return
	_zoom = zoom
	_cam = camera_world
	_vp = vp
	_resolve_layout()
	_queue_paint()


func place_competing(cands: Array, zoom: float, cam: Vector2, vp: Vector2, nation_rects: Array, max_shift: float, obstacles: Array = []) -> Array:
	_cam = cam
	_zoom = zoom
	_vp = vp
	var list: Array = cands.duplicate(true)
	for c in list:
		var world: Vector2 = c.get("world", Vector2.ZERO)
		c["dist"] = world.distance_to(cam)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _priority_before(a, b)
	)
	var placed: Array = []
	var font := _font_or_null()
	var blockers: Array = []
	for n in nation_rects:
		blockers.append(n)
	for o in obstacles:
		blockers.append(o)
	var close := zoom > _LOD.CITY_LABEL_MID_MAX
	var shift_px := max_shift
	if close and max_shift >= LABEL_SHIFT_PX:
		shift_px = CLOSE_SHIFT_PX
	for c in list:
		if not _in_band(c, zoom):
			continue
		var is_cap := bool(c.get("capital", false))
		var must_keep := bool(c.get("must_keep", false))
		var pid := int(c.get("pid", 0))
		var ruhr_keep := float(_RUHR_CORE.get(pid, 0.0)) > 0.05
		var enter := float(c.get("enter", 0.0))
		var alpha := _draw_alpha(zoom, enter)
		if alpha < 0.04 and not must_keep:
			continue
		if must_keep and alpha < 0.04:
			alpha = 1.0
		var world: Vector2 = c.get("world", Vector2.ZERO)
		var anchor_s := _world_to_label_screen(world)
		if anchor_s.x < -120.0 or anchor_s.y < -80.0 or anchor_s.x > vp.x + 120.0 or anchor_s.y > vp.y + 80.0:
			continue
		var tier := int(c.get("tier", 1))
		var px := _LOD.city_label_font_px(tier)
		if close:
			px = maxi(px, CLOSE_FONT_MIN_PX)
		var text := str(c.get("name", ""))
		var size := _measure(font, text, px)
		var ascent := size.y * 0.78
		var base := Vector2(8.0, -2.0)
		if is_cap:
			base = Vector2(14.0, -2.0)
		# Capitals and Ruhr cores stay by their dots (chips draw under labels).
		# Everyone still misses already-placed city labels and those cities' dots.
		var accepted := false
		var chosen := Rect2()
		var chosen_off := base
		# Ruhr cores still collide with unit plates — try chip-clear slots
		# first (inset so a 44 px walk can sit beside the plate). Last
		# resort keeps the name by the mark so Dortmund cannot vanish at mid.
		var keep := ruhr_keep or must_keep or is_cap
		var walk_shift := RUHR_ANCHOR_MAX_PX if keep else shift_px
		var walk_anchor := RUHR_ANCHOR_MAX_PX if keep else ANCHOR_MAX_PX
		var chip_blockers: Array = _inset_counter_obstacles(obstacles, COUNTER_INSET_PX)
		var sibling_dots: Array = []
		for c2 in list:
			var pid2 := int(c2.get("pid", 0))
			if pid2 == pid:
				continue
			if float(_RUHR_CORE.get(pid2, 0.0)) <= 0.05 and not bool(c2.get("must_keep", false)) and not bool(c2.get("capital", false)):
				continue
			var w2: Vector2 = c2.get("world", Vector2.ZERO)
			var a2 := _world_to_label_screen(w2)
			sibling_dots.append(Rect2(a2 - Vector2(DOT_BLOCK_PX, DOT_BLOCK_PX), Vector2(DOT_BLOCK_PX * 2.0, DOT_BLOCK_PX * 2.0)))
		var try_blockers: Array = []
		for n in nation_rects:
			try_blockers.append(n)
		for o in chip_blockers:
			try_blockers.append(o)
		for sd in sibling_dots:
			try_blockers.append(sd)
		var dot_rect := Rect2(anchor_s - Vector2(DOT_BLOCK_PX, DOT_BLOCK_PX), Vector2(DOT_BLOCK_PX * 2.0, DOT_BLOCK_PX * 2.0))
		if not must_keep and not is_cap and not ruhr_keep and not bool(c.get("hub", false)) and _dot_hits_placed(dot_rect, placed):
			continue
		# Duisburg is ~30 px west of Essen at z 2.9; a right-growing 22 px
		# walk always hits Essen. Flush-left (glyph east-edge by the mark)
		# keeps the nearest edge inside the keep/anchor cap.
		for off_v in _candidate_slots(base, walk_shift, size, ascent, anchor_s, placed, keep):
			var off: Vector2 = off_v as Vector2
			if _anchor_gap_px(off, size, ascent) > walk_anchor + 0.05:
				continue
			var baseline_s: Vector2 = anchor_s + off
			var rect := Rect2(baseline_s + Vector2(0.0, -ascent), size)
			if _rects_clear(rect, placed, try_blockers, vp):
				chosen = rect
				chosen_off = off
				accepted = true
				break
		if not accepted and keep:
			var keep_blockers: Array = []
			for n2 in nation_rects:
				keep_blockers.append(n2)
			for sd2 in sibling_dots:
				keep_blockers.append(sd2)
			for off_v2 in _candidate_slots(base, walk_shift, size, ascent, anchor_s, placed, keep):
				var off2: Vector2 = off_v2 as Vector2
				if _anchor_gap_px(off2, size, ascent) > walk_anchor + 0.05:
					continue
				var rect2 := Rect2(anchor_s + off2 + Vector2(0.0, -ascent), size)
				if _rects_clear(rect2, placed, keep_blockers, vp):
					chosen = rect2
					chosen_off = off2
					accepted = true
					break
		if not accepted and (is_cap or must_keep):
			var cap_base: Vector2 = anchor_s + base
			chosen = Rect2(cap_base + Vector2(0.0, -ascent), size)
			chosen_off = base
			accepted = true
		elif not accepted and ruhr_keep:
			# Chips may cover the mark; a nation label still owns the screen.
			var nation_only: Array = []
			for n3 in nation_rects:
				nation_only.append(n3)
			var ruhr_base: Vector2 = anchor_s + base
			var ruhr_rect := Rect2(ruhr_base + Vector2(0.0, -ascent), size)
			if _rects_clear(ruhr_rect, placed, nation_only, vp):
				chosen = ruhr_rect
				chosen_off = base
				accepted = true
		# Never last-resort 48/120px: that put Duisburg south of Köln and
		# names ~75px east of their dots. Cull if it will not sit by the mark.
		if not accepted:
			continue
		if placed.size() >= MAX_ON_SCREEN and not must_keep and not ruhr_keep:
			break
		placed.append({
			"name": text,
			"pid": pid,
			"screen_rect": chosen,
			"screen_offset": chosen_off,
			"capital": is_cap,
			"must_keep": must_keep,
			"ruhr_keep": ruhr_keep,
			"tier": tier,
			"alpha": alpha,
			"score": float(c.get("score", 0.0)),
			"world": world,
			"enter": enter,
			"font_px": px,
			"ascent": ascent,
			"dot_rect": dot_rect,
		})
		blockers.append(dot_rect)
	placed = _nudge_keep_apart(placed, vp)
	placed = _nudge_keep_off_counters(placed, obstacles, vp)
	placed = _nudge_keep_apart(placed, vp)
	placed = _nudge_labels_off_foreign_dots(placed, vp)
	return _drop_visual_overlaps(placed, zoom)


func _is_keep_item(item: Dictionary) -> bool:
	return bool(item.get("must_keep", false)) or bool(item.get("capital", false)) or bool(item.get("ruhr_keep", false))


func _drop_visual_overlaps(placed: Array, _zoom: float = 1.0) -> Array:
	var out: Array = placed.duplicate()
	var guard := 0
	while guard < 24:
		guard += 1
		var drop_at := -1
		var drop_score := 1.0e12
		for i in out.size():
			var a: Dictionary = out[i]
			if float(a.get("alpha", 0.0)) < 0.04:
				continue
			var ar: Rect2 = a.get("screen_rect", Rect2())
			var ad: Rect2 = a.get("dot_rect", Rect2())
			for j in range(i + 1, out.size()):
				var b: Dictionary = out[j]
				if float(b.get("alpha", 0.0)) < 0.04:
					continue
				var br: Rect2 = b.get("screen_rect", Rect2())
				var bd: Rect2 = b.get("dot_rect", Rect2())
				var hit := ar.grow(OUTLINE_PAD_PX).intersects(br.grow(OUTLINE_PAD_PX))
				hit = hit or (ad.size.x > 0.5 and br.intersects(ad))
				hit = hit or (bd.size.x > 0.5 and ar.intersects(bd))
				if not hit:
					continue
				var ia_keep := _is_keep_item(a)
				var ib_keep := _is_keep_item(b)
				if ia_keep and ib_keep:
					continue
				var victim := j
				var vs := float(b.get("score", 0.0))
				if ia_keep and not ib_keep:
					victim = j
					vs = float(b.get("score", 0.0))
				elif ib_keep and not ia_keep:
					victim = i
					vs = float(a.get("score", 0.0))
				elif float(a.get("score", 0.0)) < float(b.get("score", 0.0)):
					victim = i
					vs = float(a.get("score", 0.0))
				if _is_keep_item(out[victim]):
					continue
				if vs < drop_score:
					drop_at = victim
					drop_score = vs
		if drop_at < 0:
			break
		out.remove_at(drop_at)
	return out


func _nudge_keep_apart(placed: Array, vp: Vector2) -> Array:
	if placed.size() < 2:
		return placed
	for i in placed.size():
		var a: Dictionary = placed[i]
		if not _is_keep_item(a) or float(a.get("alpha", 0.0)) < 0.04:
			continue
		var ar: Rect2 = a.get("screen_rect", Rect2())
		for j in range(i + 1, placed.size()):
			var b: Dictionary = placed[j]
			if not _is_keep_item(b) or float(b.get("alpha", 0.0)) < 0.04:
				continue
			var br: Rect2 = b.get("screen_rect", Rect2())
			var ad: Rect2 = a.get("dot_rect", Rect2())
			var bd: Rect2 = b.get("dot_rect", Rect2())
			var hit := ar.grow(OUTLINE_PAD_PX).intersects(br.grow(OUTLINE_PAD_PX))
			hit = hit or (ad.size.x > 0.5 and br.intersects(ad))
			hit = hit or (bd.size.x > 0.5 and ar.intersects(bd))
			if not hit:
				continue
			var victim := j
			if ar.intersects(bd):
				victim = i
			elif br.intersects(ad):
				victim = j
			elif float(a.get("score", 0.0)) < float(b.get("score", 0.0)):
				victim = i
			var item: Dictionary = placed[victim]
			var world: Vector2 = item.get("world", Vector2.ZERO)
			var anchor_s := _world_to_label_screen(world)
			var size: Vector2 = (item.get("screen_rect", Rect2()) as Rect2).size
			var ascent := float(item.get("ascent", size.y * 0.78))
			var others: Array = []
			for k in placed.size():
				if k == victim:
					continue
				others.append(placed[k])
			var moved := false
			for off_v in _candidate_slots(Vector2(8.0, -2.0), RUHR_ANCHOR_MAX_PX, size, ascent, anchor_s, others, true):
				var off: Vector2 = off_v as Vector2
				if _anchor_gap_px(off, size, ascent) > RUHR_ANCHOR_MAX_PX + 0.05:
					continue
				var cand := Rect2(anchor_s + off + Vector2(0.0, -ascent), size)
				if not _rects_clear(cand, others, [], vp):
					continue
				item["screen_rect"] = cand
				item["screen_offset"] = off
				placed[victim] = item
				if victim == i:
					ar = cand
				moved = true
				break
			if not moved:
				continue
	return placed


func _nudge_keep_off_counters(placed: Array, obstacles: Array, vp: Vector2) -> Array:
	if obstacles.is_empty() or placed.is_empty():
		return placed
	var chip_blockers: Array = _inset_counter_obstacles(obstacles, COUNTER_INSET_PX)
	for i in placed.size():
		var item: Dictionary = placed[i]
		if not _is_keep_item(item):
			continue
		var rect: Rect2 = item.get("screen_rect", Rect2())
		var hits := false
		for o in chip_blockers:
			if o is Rect2 and rect.intersects(o as Rect2):
				hits = true
				break
		if not hits:
			continue
		var world: Vector2 = item.get("world", Vector2.ZERO)
		var anchor_s := _world_to_label_screen(world)
		var size := rect.size
		var ascent := float(item.get("ascent", size.y * 0.78))
		var keep_others: Array = []
		for j in placed.size():
			if j == i:
				continue
			if _is_keep_item(placed[j]):
				keep_others.append(placed[j])
		# Names draw at z 30 above chips (z 28). Stay by the dot — a 120px
		# last-resort put Duisburg south of Köln and ~75px east of its mark.
		for off_v in _candidate_slots(Vector2(8.0, -2.0), RUHR_ANCHOR_MAX_PX, size, ascent, anchor_s, keep_others, true):
			var off: Vector2 = off_v as Vector2
			if _anchor_gap_px(off, size, ascent) > RUHR_ANCHOR_MAX_PX + 0.05:
				continue
			var cand := Rect2(anchor_s + off + Vector2(0.0, -ascent), size)
			if not _rects_clear(cand, keep_others, chip_blockers, vp):
				continue
			item["screen_rect"] = cand
			item["screen_offset"] = off
			placed[i] = item
			break
	var kept_list: Array = []
	for i2 in placed.size():
		var rec: Dictionary = placed[i2]
		if _is_keep_item(rec):
			kept_list.append(rec)
			continue
		var orect: Rect2 = rec.get("screen_rect", Rect2())
		var clash := false
		for k in placed.size():
			if not _is_keep_item(placed[k]):
				continue
			var krect: Rect2 = (placed[k] as Dictionary).get("screen_rect", Rect2())
			if orect.grow(OUTLINE_PAD_PX).intersects(krect.grow(OUTLINE_PAD_PX)):
				clash = true
				break
		if not clash:
			kept_list.append(rec)
	return kept_list


func _nudge_labels_off_foreign_dots(placed: Array, vp: Vector2) -> Array:
	if placed.size() < 2:
		return placed
	for i in placed.size():
		var item: Dictionary = placed[i]
		var rect: Rect2 = item.get("screen_rect", Rect2())
		var hits := false
		for j in placed.size():
			if i == j:
				continue
			var other_dot: Rect2 = (placed[j] as Dictionary).get("dot_rect", Rect2())
			if rect.intersects(other_dot):
				hits = true
				break
		if not hits:
			continue
		var world: Vector2 = item.get("world", Vector2.ZERO)
		var anchor_s := _world_to_label_screen(world)
		var size := rect.size
		var ascent := float(item.get("ascent", size.y * 0.78))
		var others: Array = []
		var extra: Array = []
		for j2 in placed.size():
			if j2 == i:
				continue
			others.append(placed[j2])
			extra.append((placed[j2] as Dictionary).get("dot_rect", Rect2()))
		for off_v in _candidate_slots(Vector2(8.0, -2.0), LABEL_SHIFT_PX, size, ascent, anchor_s, others, _is_keep_item(item)):
			var off: Vector2 = off_v as Vector2
			if _anchor_gap_px(off, size, ascent) > ANCHOR_MAX_PX + 0.05:
				continue
			var cand := Rect2(anchor_s + off + Vector2(0.0, -ascent), size)
			if not _rects_clear(cand, others, extra, vp):
				continue
			item["screen_rect"] = cand
			item["screen_offset"] = off
			placed[i] = item
			break
	return placed


func _priority_before(a: Dictionary, b: Dictionary) -> bool:
	# Ruhr cores before generic capitals (Paris is must_keep). Otherwise
	# tier-4 Paris sorts ahead of Duisburg and Essen takes the west slot.
	var apid := int(a.get("pid", 0))
	var bpid := int(b.get("pid", 0))
	var ar := float(_RUHR_CORE.get(apid, 0.0)) > 0.05 or apid == 710403
	var br := float(_RUHR_CORE.get(bpid, 0.0)) > 0.05 or bpid == 710403
	if ar != br:
		return ar
	var ac := bool(a.get("capital", false)) or bool(a.get("must_keep", false))
	var bc := bool(b.get("capital", false)) or bool(b.get("must_keep", false))
	if ac != bc:
		return ac
	var at := int(a.get("tier", 0))
	var bt := int(b.get("tier", 0))
	if at != bt:
		return at > bt
	var ascore := float(a.get("score", 0.0))
	var bscore := float(b.get("score", 0.0))
	if absf(ascore - bscore) > 0.05:
		return ascore > bscore
	var ad := float(a.get("dist", 0.0))
	var bd := float(b.get("dist", 0.0))
	if absf(ad - bd) > 0.5:
		return ad < bd
	var an := str(a.get("name", ""))
	var bn := str(b.get("name", ""))
	if an.length() != bn.length():
		return an.length() < bn.length()
	return int(a.get("pid", 0)) < int(b.get("pid", 0))


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var cam := viewport.get_camera_2d()
	if cam == null:
		return
	var vp_size := viewport.get_visible_rect().size
	if vp_size.x < 8.0 or vp_size.y < 8.0:
		vp_size = Vector2(1920, 1080)
	var zoom := maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	var pos := cam.global_position
	if _should_rebuild(zoom, pos, vp_size):
		_zoom = zoom
		_cam = pos
		_vp = vp_size
		_use_nation_override = false
		_use_counter_override = false
		_resolve_layout()
		_queue_paint()
	elif absf(zoom - _zoom) > 0.001:
		_zoom = zoom
		_queue_paint()


func _should_rebuild(zoom: float, pos: Vector2, vp_size: Vector2) -> bool:
	if not _layout_ready:
		return true
	if not _show_labels:
		return false
	var band := _LOD.city_label_band_for_zoom(zoom)
	if band != _last_band:
		return true
	if absf(zoom - _last_layout_zoom) >= ZOOM_REBUILD:
		return true
	var z := maxf(zoom, 0.04)
	var pan_x := vp_size.x * PAN_REBUILD_FRAC / z
	var pan_y := vp_size.y * PAN_REBUILD_FRAC / z
	if absf(pos.x - _last_cam.x) > pan_x or absf(pos.y - _last_cam.y) > pan_y:
		return true
	if vp_size.distance_squared_to(_last_vp) > 4.0:
		return true
	if _counters_dirty:
		return true
	if not _use_counter_override:
		var n := _live_counter_count_cheap()
		if n != _last_counter_count:
			return true
	return false


func _resolve_layout() -> void:
	ensure_candidates()
	if not _show_labels:
		if not _placed.is_empty():
			_placed = []
		_layout_ready = true
		_last_band = _LOD.city_label_band_for_zoom(_zoom)
		_last_layout_zoom = _zoom
		_last_cam = _cam
		_last_vp = _vp
		return
	_last_band = _LOD.city_label_band_for_zoom(_zoom)
	_last_layout_zoom = _zoom
	_last_cam = _cam
	_last_vp = _vp
	_layout_ready = true
	rebuild_count += 1
	_counters_dirty = false
	var nations := _nation_rects_for_layout()
	var counters := _counter_rects_for_layout()
	if not _use_counter_override:
		_last_counter_sig = _signature_of_rects(counters)
		_last_counter_count = counters.size()
	_placed = place_competing(_candidates, _zoom, _cam, _vp, nations, LABEL_SHIFT_PX, counters)


func _nation_rects_for_layout() -> Array:
	if _use_nation_override:
		return _nation_override
	var out: Array = _live_nation_rects()
	for r in chrome_screen_rects():
		out.append(r)
	return out


func _counter_rects_for_layout() -> Array:
	if _use_counter_override:
		return _counter_override
	return _live_counter_rects()


func _live_nation_rects() -> Array:
	if _zoom >= _LOD.NATION_LABEL_HIDE_ZOOM:
		return []
	var parent_node := get_parent()
	if parent_node == null:
		return []
	var layer := parent_node.get_node_or_null("PoliticalLabelsLayer")
	if layer == null:
		return []
	var out: Array = []
	for child in layer.get_children():
		if not (child is Label):
			continue
		var lbl := child as Label
		if not lbl.visible:
			continue
		if lbl.modulate.a < 0.05:
			continue
		if not str(lbl.name).begins_with("NationLabel_"):
			continue
		var rect := _control_screen_rect(lbl)
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			out.append(rect)
	return out


func _live_counter_rects() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var mr := _map_renderer_host()
	if mr != null:
		_collect_counters_from_map_renderer(mr, out, seen)
		return out
	var parent_node := get_parent()
	if parent_node != null:
		_collect_counter_rects(parent_node, out, seen, 0, 2)
	return out


func _live_counter_count_cheap() -> int:
	var mr := _map_renderer_host()
	if mr == null:
		return _last_counter_count
	var n := 0
	if mr.has_method("_count_visible_unit_icons"):
		n = int(mr.call("_count_visible_unit_icons"))
	elif "_demo_unit_icon_pids" in mr:
		n = (mr.get("_demo_unit_icon_pids") as Array).size()
	var sea: Node = null
	if "container" in mr:
		var cont: Node = mr.get("container") as Node
		if cont != null:
			sea = cont.get_node_or_null("SeaNationFleetLayer")
	if sea != null:
		for c in sea.get_children():
			if c is Node2D and str(c.name).begins_with("DemoUnitIcon_") and (c as Node2D).visible:
				n += 1
	return n


func _map_renderer_host() -> Node:
	var n := get_parent()
	if n == null:
		return null
	var r := n.get_parent()
	if r != null and ("province_nodes" in r or r.has_method("set_unit_counters_visible")):
		return r
	if n.has_method("set_unit_counters_visible") or "province_nodes" in n:
		return n
	return null


func _collect_counters_from_map_renderer(mr: Node, out: Array, seen: Dictionary) -> void:
	var pids: Array = []
	if "_demo_unit_icon_pids" in mr:
		pids = mr.get("_demo_unit_icon_pids") as Array
	var nodes: Dictionary = {}
	if "province_nodes" in mr:
		nodes = mr.get("province_nodes") as Dictionary
	for id_v in pids:
		var id := int(id_v)
		if not nodes.has(id):
			continue
		var host: Node = nodes[id] as Node
		if host == null:
			continue
		for c in host.get_children():
			_maybe_append_counter(c, out, seen)
			_maybe_append_pin(c, out, seen)
	var sea: Node = null
	if "container" in mr:
		var cont: Node = mr.get("container") as Node
		if cont != null:
			sea = cont.get_node_or_null("SeaNationFleetLayer")
	if sea != null:
		for c in sea.get_children():
			_maybe_append_counter(c, out, seen)


func _collect_counter_rects(node: Node, out: Array, seen: Dictionary, depth: int, max_depth: int) -> void:
	if node == null or depth > max_depth:
		return
	_maybe_append_counter(node, out, seen)
	for child in node.get_children():
		_collect_counter_rects(child, out, seen, depth + 1, max_depth)


func _maybe_append_counter(node: Node, out: Array, seen: Dictionary) -> void:
	if node == null or not (node is Node2D):
		return
	if not str(node.name).begins_with("DemoUnitIcon_"):
		return
	var icon := node as Node2D
	if not icon.visible:
		return
	var iid := icon.get_instance_id()
	if seen.has(iid):
		return
	seen[iid] = true
	var crect := _counter_label_screen_rect(icon)
	if crect.size.x > 1.0 and crect.size.y > 1.0:
		out.append(crect)


func _maybe_append_pin(node: Node, out: Array, seen: Dictionary) -> void:
	if node == null or not (node is Node2D):
		return
	var nm := str(node.name)
	if nm != "PinFocusPulse" and nm != "StackBadge" and not nm.begins_with("SelectedFrame"):
		return
	var icon := node as Node2D
	if not icon.visible:
		return
	var iid := icon.get_instance_id()
	if seen.has(iid):
		return
	seen[iid] = true
	var prect := _counter_label_screen_rect(icon)
	if prect.size.x > 1.0 and prect.size.y > 1.0:
		out.append(prect)


func _signature_of_rects(rects: Array) -> int:
	var sig := rects.size() * 10007
	for r in rects:
		if not (r is Rect2):
			continue
		var rr: Rect2 = r
		sig = sig * 31 + int(round(rr.position.x)) + int(round(rr.position.y)) * 17
		sig = sig + int(round(rr.size.x)) * 13 + int(round(rr.size.y)) * 7
	return sig


func _world_to_label_screen(world: Vector2) -> Vector2:
	# Isolated set_view injects cam/zoom with no Camera2D. Live Play uses the
	# canvas transform so chip AABBs match what the player sees.
	if not _use_counter_override and not _use_nation_override and is_inside_tree():
		var viewport := get_viewport()
		if viewport != null and viewport.get_camera_2d() != null:
			return get_global_transform_with_canvas() * world
	return (world - _cam) * _zoom + _vp * 0.5


func _counter_label_screen_rect(icon: Node2D) -> Rect2:
	if icon == null or not is_instance_valid(icon):
		return Rect2()
	# Plate + bars only. Merging designation text made 400px AABBs that
	# swallowed the whole Ruhr and hid Essen from packing.
	var local := Rect2(-COUNTER_HALF, COUNTER_HALF * 2.0)
	var xf := icon.get_global_transform_with_canvas()
	var corners: Array[Vector2] = [
		local.position,
		local.position + Vector2(local.size.x, 0.0),
		local.end,
		local.position + Vector2(0.0, local.size.y),
	]
	var p0: Vector2 = xf * corners[0]
	var p1: Vector2 = p0
	for c in corners:
		var p: Vector2 = xf * c
		p0 = Vector2(minf(p0.x, p.x), minf(p0.y, p.y))
		p1 = Vector2(maxf(p1.x, p.x), maxf(p1.y, p.y))
	var rect := Rect2(p0, p1 - p0).abs().grow(2.0)
	if rect.size.x > COUNTER_MAX_SCREEN.x or rect.size.y > COUNTER_MAX_SCREEN.y:
		var mid := rect.get_center()
		rect = Rect2(mid - COUNTER_MAX_SCREEN * 0.5, COUNTER_MAX_SCREEN)
	var view := Rect2(Vector2.ZERO, _vp).grow(32.0)
	if not rect.intersects(view):
		return Rect2()
	return rect


func _control_screen_rect(lbl: Control) -> Rect2:
	if lbl == null or not lbl.is_inside_tree():
		return Rect2()
	var xf := lbl.get_global_transform_with_canvas()
	var p0: Vector2 = xf * Vector2.ZERO
	var p1: Vector2 = xf * lbl.size
	var rect := Rect2(p0, p1 - p0).abs()
	return rect


func _counter_screen_rect(icon: Node2D) -> Rect2:
	return _counter_label_screen_rect(icon)


func _icon_local_aabb(icon: Node2D) -> Rect2:
	var acc := Rect2(-COUNTER_HALF, COUNTER_HALF * 2.0)
	if icon == null:
		return acc
	for ch in icon.get_children():
		acc = _merge_child_local_rect(acc, ch, icon)
		if ch is Node:
			for sub in (ch as Node).get_children():
				acc = _merge_child_local_rect(acc, sub, icon)
	return acc


func _merge_child_local_rect(acc: Rect2, n: Node, icon: Node2D) -> Rect2:
	var extra := _child_local_rect(n, icon)
	if extra.size.x <= 0.0 and extra.size.y <= 0.0:
		return acc
	return acc.merge(extra)


func _child_local_rect(n: Node, icon: Node2D) -> Rect2:
	if n == null or not (n is Node2D) or icon == null:
		return Rect2()
	var node := n as Node2D
	if not node.visible:
		return Rect2()
	var own := Rect2()
	if n is Polygon2D:
		var poly := n as Polygon2D
		if poly.polygon.is_empty():
			return Rect2()
		var mn: Vector2 = poly.polygon[0]
		var mx: Vector2 = mn
		for v in poly.polygon:
			var pv: Vector2 = v
			mn = Vector2(minf(mn.x, pv.x), minf(mn.y, pv.y))
			mx = Vector2(maxf(mx.x, pv.x), maxf(mx.y, pv.y))
		own = Rect2(mn, mx - mn)
	elif n is Sprite2D:
		var spr := n as Sprite2D
		if spr.texture == null:
			return Rect2()
		var sz: Vector2 = spr.texture.get_size()
		if spr.region_enabled:
			sz = spr.region_rect.size
		if spr.centered:
			own = Rect2(-sz * 0.5, sz)
		else:
			own = Rect2(Vector2.ZERO, sz)
	elif "text" in n:
		var t := str(n.get("text"))
		if t.is_empty():
			return Rect2()
		var fs := 13
		if "font_size" in n:
			fs = int(n.get("font_size"))
		var w := maxf(8.0, float(t.length()) * float(fs) * 0.55)
		var ox := 0.0
		if "align_center" in n and bool(n.get("align_center")):
			ox = -w * 0.5
		elif "align_right" in n and bool(n.get("align_right")):
			ox = -w
		own = Rect2(Vector2(ox, -float(fs)), Vector2(w, float(fs) + 4.0))
	if own.size.x <= 0.0 and own.size.y <= 0.0:
		return Rect2()
	if not icon.is_inside_tree() or not node.is_inside_tree():
		return Rect2(node.position + own.position, own.size)
	var xf := icon.global_transform.affine_inverse() * node.global_transform
	var corners: Array[Vector2] = [
		own.position,
		own.position + Vector2(own.size.x, 0.0),
		own.end,
		own.position + Vector2(0.0, own.size.y),
	]
	var mn2: Vector2 = xf * corners[0]
	var mx2: Vector2 = mn2
	for c in corners:
		var p: Vector2 = xf * c
		mn2 = Vector2(minf(mn2.x, p.x), minf(mn2.y, p.y))
		mx2 = Vector2(maxf(mx2.x, p.x), maxf(mx2.y, p.y))
	return Rect2(mn2, mx2 - mn2)


func _draw() -> void:
	if not _show_labels or _placed.is_empty():
		return
	var font := _font
	if font == null:
		font = _font_or_null()
	if font == null:
		return
	var zoom := _zoom
	var viewport := get_viewport()
	if viewport != null:
		var cam := viewport.get_camera_2d()
		if cam != null:
			zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
	var z := maxf(zoom, 0.04)
	var close := zoom > _LOD.CITY_LABEL_MID_MAX
	for item in _placed:
		var enter := float(item.get("enter", 0.0))
		var alpha := _draw_alpha(zoom, enter)
		if alpha < 0.04:
			continue
		var world: Vector2 = item.get("world", Vector2.ZERO)
		var off: Vector2 = item.get("screen_offset", Vector2(8, -2))
		var px := maxi(int(item.get("font_px", 11)), 8)
		if close:
			px = maxi(px, CLOSE_FONT_MIN_PX)
		# Rasterize at screen pixels, then cancel Camera2D zoom so close
		# names stay sharp (world-space 11/z px was blurry at z 2.9).
		var outline_px := 3
		var text := str(item.get("name", ""))
		draw_set_transform(world, 0.0, Vector2(1.0 / z, 1.0 / z))
		draw_string_outline(
			font, off, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, outline_px,
			Color(OUTLINE_COLOR.r, OUTLINE_COLOR.g, OUTLINE_COLOR.b, alpha)
		)
		draw_string(
			font, off, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px,
			Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, alpha)
		)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _inset_counter_obstacles(obstacles: Array, pad: float) -> Array:
	var out: Array = []
	for o in obstacles:
		if not (o is Rect2):
			continue
		var r: Rect2 = o as Rect2
		if pad > 0.05:
			r = r.grow(-pad)
		if r.size.x > 4.0 and r.size.y > 4.0:
			out.append(r)
	return out


func _rects_clear(rect: Rect2, placed: Array, blockers: Array, vp: Vector2) -> bool:
	var view := Rect2(Vector2.ZERO, vp).grow(8.0)
	if not rect.intersects(view):
		return false
	var pad := OUTLINE_PAD_PX
	for p in placed:
		var other: Rect2 = p.get("screen_rect", Rect2())
		if rect.grow(pad).intersects(other.grow(pad)):
			return false
		var other_dot: Rect2 = p.get("dot_rect", Rect2())
		if other_dot.size.x > 0.5 and rect.intersects(other_dot):
			return false
	for n in blockers:
		if n is Rect2 and rect.intersects((n as Rect2).grow(2.0)):
			return false
	return true


func _dot_hits_placed(dot_rect: Rect2, placed: Array) -> bool:
	for p in placed:
		var other: Rect2 = p.get("screen_rect", Rect2())
		if dot_rect.intersects(other.grow(1.0)):
			return true
	return false


func _rect_gap_from_point(rect: Rect2, p: Vector2) -> float:
	var dx := 0.0
	if p.x < rect.position.x:
		dx = rect.position.x - p.x
	elif p.x > rect.end.x:
		dx = p.x - rect.end.x
	var dy := 0.0
	if p.y < rect.position.y:
		dy = rect.position.y - p.y
	elif p.y > rect.end.y:
		dy = p.y - rect.end.y
	return Vector2(dx, dy).length()


func _anchor_gap_px(off: Vector2, size: Vector2, ascent: float) -> float:
	return _rect_gap_from_point(Rect2(off + Vector2(0.0, -ascent), size), Vector2.ZERO)


func _flush_slots(size: Vector2, ascent: float) -> Array:
	var gap := 8.0
	if size.x < 1.0:
		return []
	var left := Vector2(-size.x - gap, -2.0)
	var right := Vector2(gap + 2.0, -2.0)
	var above := Vector2(-size.x * 0.35, -ascent - gap)
	var below := Vector2(-size.x * 0.35, size.y - ascent + gap)
	var above_l := Vector2(-size.x - gap, -ascent - gap)
	var above_r := Vector2(gap + 2.0, -ascent - gap)
	var below_l := Vector2(-size.x - gap, size.y - ascent + gap)
	var below_r := Vector2(gap + 2.0, size.y - ascent + gap)
	return [left, above, below, right, above_l, above_r, below_l, below_r]


func _keep_to_the_east(anchor_s: Vector2, placed: Array) -> bool:
	for p in placed:
		if not _is_keep_item(p):
			continue
		var other_s := _world_to_label_screen(p.get("world", Vector2.ZERO) as Vector2)
		if other_s.x > anchor_s.x + 2.0 and absf(other_s.y - anchor_s.y) < 80.0:
			return true
	return false


func _keep_to_the_west(anchor_s: Vector2, placed: Array) -> bool:
	for p in placed:
		if not _is_keep_item(p):
			continue
		var other_s := _world_to_label_screen(p.get("world", Vector2.ZERO) as Vector2)
		if other_s.x < anchor_s.x - 2.0 and absf(other_s.y - anchor_s.y) < 80.0:
			return true
	return false


func _candidate_slots(base: Vector2, max_shift: float, size: Vector2, ascent: float, anchor_s: Vector2, placed: Array, _prefer_flush: bool) -> Array:
	var walk := _slot_offsets(base, max_shift)
	if max_shift < 1.0:
		return walk
	var out: Array = []
	var flush: Array = _flush_slots(size, ascent)
	# Essen must stay right of its mark. Only Duisburg (keep to the east)
	# tries west-of-mark first. Preferring left for every core put Essen
	# on top of Duisburg at z 2.9. Dortmund (keep to the west) skips the
	# short right walk that lands inside Essen's glyph.
	if _keep_to_the_east(anchor_s, placed) and flush.size() > 0:
		out.append(flush[0])
		for fs in flush:
			out.append(fs)
		out.append_array(walk)
		return out
	if _keep_to_the_west(anchor_s, placed):
		var far: Array = []
		for off_v in walk:
			var off: Vector2 = off_v as Vector2
			if off.x >= base.x + 16.0:
				far.append(off)
		out.append_array(far)
		out.append_array(walk)
		for fs in flush:
			out.append(fs)
		return out
	out.append_array(walk)
	for fs in flush:
		out.append(fs)
	return out


func _slot_offsets(base: Vector2, max_shift: float) -> Array:
	var out: Array = [base]
	if max_shift < 1.0:
		return out
	var radii: Array[float] = [8.0, 12.0, 16.0, 22.0, 28.0, 36.0, 48.0, 56.0, 64.0, 80.0, 96.0, 120.0]
	var dirs: Array[Vector2] = [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(0.7071, -0.7071), Vector2(-0.7071, -0.7071),
		Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071),
	]
	for radius in radii:
		if radius > max_shift + 0.01:
			break
		for dir in dirs:
			out.append(base + dir * radius)
	return out


func _measure(font: Font, text: String, px: int) -> Vector2:
	if font != null:
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		return Vector2(maxf(sz.x, float(px)) + 4.0, maxf(sz.y, float(px) + 2.0))
	return Vector2(float(text.length()) * float(px) * 0.56 + 4.0, float(px) + 4.0)


func _font_or_null() -> Font:
	if _font != null:
		return _font
	_font = ThemeDB.fallback_font
	return _font


func _zoom_for_band(band_name: String) -> float:
	match band_name:
		"home", "wide":
			return 0.40
		"strategic":
			return 0.70
		"mid", "operational":
			return 1.55
		_:
			return 2.40


func _in_band(c: Dictionary, zoom: float) -> bool:
	var band := _LOD.city_label_band_for_zoom(zoom)
	var tier := int(c.get("tier", 1))
	var capital := bool(c.get("capital", false))
	var score := float(c.get("score", 0.0))
	var hub := bool(c.get("hub", false))
	if band == _LOD.CITY_BAND_HOME:
		return tier >= 4
	if band == _LOD.CITY_BAND_STRATEGIC:
		return tier >= 3 or capital or hub
	if band == _LOD.CITY_BAND_MID:
		return tier >= 3 or capital or hub or (tier >= 2 and score >= MID_TIER2_SCORE_FLOOR)
	return true


func _score_city(tier: int, pop: float, kreis: bool, port: bool, hub: bool = false, core_bonus: float = 0.0) -> float:
	var score := float(tier) * 100.0
	score += minf(pop, 5000000.0) * 0.001
	if kreis:
		score += 250.0
	if port:
		score += 40.0
	if hub:
		score += HUB_SCORE
	score += core_bonus
	return score


func _enter_zoom(tier: int, capital: bool, score: float, hub: bool = false) -> float:
	if tier >= 4:
		return 0.0
	if tier >= 3 or capital:
		return _LOD.CITY_LABEL_HOME_MAX
	if hub:
		return _LOD.CITY_LABEL_HOME_MAX
	if tier >= 2 and score >= MID_TIER2_SCORE_FLOOR:
		return _LOD.CITY_LABEL_STRATEGIC_MAX
	var t := clampf(1.0 - score / 600.0, 0.0, 1.0)
	return _LOD.CITY_LABEL_MID_MAX + t * 0.85


func _load_candidates() -> void:
	_candidates.clear()
	_by_pid.clear()
	var city_text := FileAccess.get_file_as_string(_CITY_PATH)
	var econ_text := FileAccess.get_file_as_string(_ECON_PATH)
	var base_text := FileAccess.get_file_as_string(_BASE_PATH)
	var own_text := FileAccess.get_file_as_string(_OWN_PATH)
	var scenario_text := FileAccess.get_file_as_string(_SCENARIO_PATH)
	if city_text.is_empty():
		return
	var city_root: Variant = JSON.parse_string(city_text)
	var econ_root: Variant = JSON.parse_string(econ_text)
	var base_root: Variant = JSON.parse_string(base_text)
	var own_root: Variant = JSON.parse_string(own_text)
	var scenario_root: Variant = JSON.parse_string(scenario_text)
	if typeof(city_root) != TYPE_DICTIONARY:
		return
	var city_rows: Dictionary = (city_root as Dictionary).get("provinces", {})
	var econ_rows: Dictionary = {}
	if typeof(econ_root) == TYPE_DICTIONARY:
		econ_rows = (econ_root as Dictionary).get("provinces", {})
	var names: Dictionary = {}
	var ports: Dictionary = {}
	if typeof(base_root) == TYPE_DICTIONARY:
		var rows: Variant = (base_root as Dictionary).get("provinces", [])
		if rows is Array:
			for row in rows:
				if typeof(row) != TYPE_DICTIONARY:
					continue
				var pid := int((row as Dictionary).get("id", 0))
				var pname := str((row as Dictionary).get("name", ""))
				names[pid] = pname
				if _row_has_port(row, pname):
					ports[pid] = true
	var owners: Dictionary = {}
	if typeof(own_root) == TYPE_DICTIONARY:
		owners = (own_root as Dictionary).get("owners", {})
	var explicit_pids: Dictionary = {}
	var explicit_tags: Dictionary = {}
	if typeof(scenario_root) == TYPE_DICTIONARY:
		var countries: Variant = (scenario_root as Dictionary).get("countries", [])
		if countries is Array:
			for country in countries:
				if typeof(country) != TYPE_DICTIONARY:
					continue
				var tag := str((country as Dictionary).get("tag", ""))
				var cap := int((country as Dictionary).get("capital_province_id", 0))
				if not tag.is_empty():
					explicit_tags[tag] = true
				if cap > 0:
					explicit_pids[cap] = true
	var anchors := _scan_anchors()
	var best_extra: Dictionary = {}
	for key in city_rows.keys():
		var pid := int(key)
		var row: Dictionary = city_rows[key]
		var tier := int(row.get("tier", 1))
		var pop := 0.0
		if econ_rows.has(key):
			pop = float((econ_rows[key] as Dictionary).get("population", 0.0))
		elif econ_rows.has(pid):
			pop = float((econ_rows[pid] as Dictionary).get("population", 0.0))
		var pname := str(names.get(pid, ""))
		var kreis := pname.ends_with(", Kreisfreie Stadt") or pname.ends_with(", Stadtkreis")
		var port := bool(ports.get(pid, false)) or str(row.get("city_name", "")).to_lower().find("port") >= 0
		var core_bonus := float(_RUHR_CORE.get(pid, 0.0))
		var hub := bool(row.get("hub", false)) or bool(row.get("industrial_hub", false)) or core_bonus > 0.05
		var score := _score_city(tier, pop, kreis, port, hub, core_bonus)
		var raw_name := str(row.get("city_name", pname))
		var display := _canonical_display(raw_name, pname, kreis)
		if display.is_empty():
			display = pname
		var world := Vector2.ZERO
		if anchors.has(pid):
			world = (anchors[pid] as Vector2) * _Canvas.THEATER_SCALE
		if world == Vector2.ZERO:
			continue
		var capital := bool(row.get("is_capital", false)) or bool(row.get("capital", false)) or explicit_pids.has(pid)
		var cluster := _cluster_key(raw_name)
		if cluster.is_empty():
			cluster = _cluster_key(display)
		var rec := {
			"pid": pid,
			"name": display,
			"pname": pname,
			"cluster": cluster,
			"local_core": _is_local_core(display, pname, cluster),
			"tier": tier,
			"score": score,
			"capital": capital,
			"must_keep": capital or pid == 710403,
			"hub": hub or core_bonus > 0.05,
			"world": world,
			"enter": 0.0,
			"tag": str(owners.get(str(pid), owners.get(pid, ""))),
		}
		_candidates.append(rec)
		_by_pid[pid] = rec
		var rec_tag := str(rec["tag"])
		if rec_tag.is_empty() or explicit_tags.has(rec_tag) or capital:
			continue
		if not best_extra.has(rec_tag):
			best_extra[rec_tag] = rec
		else:
			var prev: Dictionary = best_extra[rec_tag]
			if _better_capital(rec, prev):
				best_extra[rec_tag] = rec
	for extra_tag in best_extra.keys():
		var extra_rec: Dictionary = best_extra[extra_tag]
		extra_rec["capital"] = true
	_dedupe_same_city()
	_drop_district_satellites()
	for rec in _candidates:
		rec["enter"] = _enter_zoom(
			int(rec["tier"]), bool(rec["capital"]), float(rec["score"]), bool(rec["hub"])
		)


func _canonical_display(city_name: String, pname: String, kreis: bool) -> String:
	if kreis:
		var core := pname.get_slice(",", 0).strip_edges()
		if not core.is_empty():
			return core
	var display := city_name.strip_edges()
	if display.is_empty():
		display = pname.strip_edges()
	var folded := _fold_name(display)
	if _ALIAS_LOCAL.has(folded):
		var local := str(_ALIAS_LOCAL[folded])
		var pn := pname.strip_edges()
		var pn_fold := _fold_name(pn.get_slice(",", 0).get_slice("/", 0))
		var local_fold := _fold_name(local)
		if pn_fold == local_fold or pn == local or pn.begins_with(local + ","):
			return local
		if not pn.is_empty() and pn_fold != local_fold:
			if pn.find("Landkreis") >= 0 or pn.find("Umland") >= 0 or pn.begins_with("Greater "):
				return pn
			return local
		return local
	return display


func _is_local_core(display: String, pname: String, cluster: String) -> bool:
	var pn := _cluster_key(pname.get_slice(",", 0).get_slice("/", 0))
	if pn == cluster:
		return true
	return _cluster_key(display) == cluster and pname.find("Landkreis") < 0 and pname.find("Umland") < 0 and not pname.begins_with("Greater ")


func _cluster_key(name: String) -> String:
	var folded := _fold_name(name.get_slice(",", 0).get_slice("/", 0))
	if _ALIAS_FOLD.has(folded):
		return str(_ALIAS_FOLD[folded])
	return folded


func _fold_name(s: String) -> String:
	var t := s.strip_edges().to_lower()
	t = t.replace("ü", "u").replace("ö", "o").replace("ä", "a").replace("ß", "ss")
	t = t.replace("é", "e").replace("è", "e").replace("ê", "e")
	t = t.replace("á", "a").replace("à", "a")
	t = t.replace("ó", "o").replace("ò", "o")
	t = t.replace("í", "i").replace("ì", "i")
	t = t.replace("ú", "u")
	t = t.replace("ñ", "n").replace("ç", "c")
	return t


func _dedupe_same_city() -> void:
	var groups: Dictionary = {}
	for rec in _candidates:
		var key := str(rec.get("cluster", ""))
		if key.is_empty():
			continue
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(rec)
	var drop: Dictionary = {}
	for key in groups.keys():
		var recs: Array = groups[key]
		if recs.size() < 2:
			continue
		var kept: Array = []
		recs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _better_keep(a, b)
		)
		for rec_v in recs:
			var rec: Dictionary = rec_v
			if bool(rec.get("must_keep", false)):
				kept.append(rec)
				continue
			var world: Vector2 = rec.get("world", Vector2.ZERO) as Vector2
			var pid := int(rec.get("pid", 0))
			var absorbed := false
			for other_v in kept:
				var other: Dictionary = other_v
				var ow: Vector2 = other.get("world", Vector2.ZERO) as Vector2
				if world.distance_to(ow) <= DEDUPE_WORLD:
					absorbed = true
					drop[pid] = true
					break
			if not absorbed:
				kept.append(rec)
	if drop.is_empty():
		return
	var kept_list: Array = []
	for rec in _candidates:
		var pid := int(rec.get("pid", 0))
		if drop.has(pid):
			_by_pid.erase(pid)
			continue
		kept_list.append(rec)
		_by_pid[pid] = rec
	_candidates = kept_list


func _is_district(rec: Dictionary) -> bool:
	var pn := str(rec.get("pname", ""))
	if pn.find("Landkreis") >= 0 or pn.find("Umland") >= 0:
		return true
	if pn.begins_with("Greater "):
		return true
	return false


func _drop_district_satellites() -> void:
	var cores: Array = []
	for rec in _candidates:
		if not _is_district(rec):
			cores.append(rec)
	if cores.is_empty():
		return
	var drop: Dictionary = {}
	for rec in _candidates:
		if not _is_district(rec):
			continue
		if bool(rec.get("must_keep", false)):
			continue
		var world: Vector2 = rec.get("world", Vector2.ZERO)
		for core in cores:
			var ow: Vector2 = core.get("world", Vector2.ZERO)
			if world.distance_to(ow) <= DEDUPE_WORLD:
				drop[int(rec.get("pid", 0))] = true
				break
	if drop.is_empty():
		return
	var kept_list: Array = []
	for rec in _candidates:
		var pid := int(rec.get("pid", 0))
		if drop.has(pid):
			_by_pid.erase(pid)
			continue
		kept_list.append(rec)
		_by_pid[pid] = rec
	_candidates = kept_list


func _better_keep(a: Dictionary, b: Dictionary) -> bool:
	var ac := bool(a.get("capital", false))
	var bc := bool(b.get("capital", false))
	if ac != bc:
		return ac
	var al := bool(a.get("local_core", false))
	var bl := bool(b.get("local_core", false))
	if al != bl:
		return al
	var at := int(a.get("tier", 0))
	var bt := int(b.get("tier", 0))
	if at != bt:
		return at > bt
	var ascore := float(a.get("score", 0.0))
	var bscore := float(b.get("score", 0.0))
	if absf(ascore - bscore) > 0.05:
		return ascore > bscore
	return int(a.get("pid", 0)) < int(b.get("pid", 0))


func _better_capital(a: Dictionary, b: Dictionary) -> bool:
	var ad := _is_district(a)
	var bd := _is_district(b)
	if ad != bd:
		return not ad
	if int(a["tier"]) != int(b["tier"]):
		return int(a["tier"]) > int(b["tier"])
	if absf(float(a["score"]) - float(b["score"])) > 0.05:
		return float(a["score"]) > float(b["score"])
	return int(a["pid"]) < int(b["pid"])


func _row_has_port(row: Dictionary, pname: String) -> bool:
	if pname.to_lower().find("port") >= 0:
		return true
	var feats: Variant = row.get("special_features", [])
	if feats is Array:
		for feat in feats:
			if str(feat).to_lower().find("port") >= 0:
				return true
	return false


func _scan_anchors() -> Dictionary:
	var out: Dictionary = {}
	var text := FileAccess.get_file_as_string(_GEO_PATH)
	if text.is_empty():
		return out
	var search := 0
	while true:
		var id_at := text.find("\"id\":", search)
		if id_at < 0:
			break
		var num_at := id_at + 5
		var pid := 0
		var k := num_at
		while k < text.length() and text[k] >= "0" and text[k] <= "9":
			pid = pid * 10 + int(text[k])
			k += 1
		var anchor_at := text.find("\"label_anchor\":[", id_at)
		var next_id := text.find("\"id\":", id_at + 5)
		if anchor_at < 0:
			break
		if next_id > 0 and anchor_at > next_id:
			search = next_id
			continue
		var x_at := anchor_at + 16
		var comma := text.find(",", x_at)
		var end_br := text.find("]", x_at)
		if comma < 0 or end_br < 0:
			search = anchor_at + 16
			continue
		var x := float(text.substr(x_at, comma - x_at))
		var y := float(text.substr(comma + 1, end_br - comma - 1))
		out[pid] = Vector2(x, y)
		search = end_br + 1
	return out


func _queue_paint() -> void:
	queue_redraw()
	if _dots != null:
		_dots.queue_redraw()


## Anchor dots sit under the name (DOT_Z 29 / CITY_Z 30) and above chips (28)
## so a neighbour's mark cannot cover Essen. Capital stars stay at z 40.
class _DotMarks extends Node2D:
	var host: Node = null

	func _draw() -> void:
		if host == null or not host.has_method("placed"):
			return
		var zoom := 1.0
		var viewport := get_viewport()
		if viewport != null:
			var cam := viewport.get_camera_2d()
			if cam != null:
				zoom = maxf(absf(cam.zoom.x), absf(cam.zoom.y))
		var z := maxf(zoom, 0.04)
		var placed: Array = host.call("placed")
		for item in placed:
			var enter := float(item.get("enter", 0.0))
			var alpha := 1.0
			if host.has_method("_draw_alpha"):
				alpha = float(host.call("_draw_alpha", zoom, enter))
			elif host.has_method("fade_alpha"):
				alpha = float(host.call("fade_alpha", zoom, enter))
			if alpha < 0.04:
				continue
			var world: Vector2 = item.get("world", Vector2.ZERO)
			draw_set_transform(world, 0.0, Vector2(1.0 / z, 1.0 / z))
			draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.97, 0.88, alpha), true, -1.0, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
