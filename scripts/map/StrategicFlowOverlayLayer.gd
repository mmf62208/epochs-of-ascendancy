# scripts/map/StrategicFlowOverlayLayer.gd
## Phase 2 gap-closure: supply flow + naval sealane particle-lite arrows.
## Toggleable, cheap polyline arrows with phase animation; budgets for world_full.

class_name StrategicFlowOverlayLayer
extends Node2D

@export var enabled: bool = true
@export var show_land_supply: bool = true
@export var show_sea_lanes: bool = true
@export var show_chokepoints: bool = true
## CP3: EquipmentFlow story glyphs (train/truck/air/sea/drone/orbital) — not every vehicle.
@export var show_equipment_flows: bool = true
## Independent player toggle (can disable glyphs while supply/sealane arrows stay on).
@export var equipment_flow_glyphs_enabled: bool = true
@export var max_routes: int = 28
@export var max_equipment_glyphs: int = 24
@export var arrow_spacing: float = 48.0
@export var line_width: float = 2.2
@export var anim_speed: float = 0.55
## MapZoomLOD.Tier: 0 strategic · 1 operational · 2 tactical
@export var zoom_tier: int = 0

var _centroids: Dictionary = {}
var _phase: float = 0.0
var _last_route_n: int = 0
var _last_arrow_n: int = 0
var _last_equipment_glyph_n: int = 0
var _last_equipment_symbols: Dictionary = {}
var _last_lod_policy: Dictionary = {}
var _province_count: int = 0


func setup(centroids: Dictionary) -> void:
	_centroids = centroids
	_province_count = centroids.size()
	queue_redraw()


func set_zoom_tier(tier: int) -> void:
	zoom_tier = clampi(tier, 0, 2)
	queue_redraw()


func set_equipment_flow_glyphs_enabled(on: bool) -> void:
	equipment_flow_glyphs_enabled = on
	queue_redraw()


func toggle_equipment_flow_glyphs() -> bool:
	equipment_flow_glyphs_enabled = not equipment_flow_glyphs_enabled
	queue_redraw()
	return equipment_flow_glyphs_enabled


## Shipped query surface for duals / UI (toggle + LOD + last paint).
func get_equipment_flow_glyph_query() -> Dictionary:
	var pol := _resolve_lod_policy()
	return {
		"ok": true,
		"equipment_flows_export": show_equipment_flows,
		"equipment_flow_glyphs_enabled": equipment_flow_glyphs_enabled,
		"visible": show_equipment_flows and equipment_flow_glyphs_enabled and bool(pol.get("show", true)),
		"zoom_tier": zoom_tier,
		"tier_name": str(pol.get("tier", "strategic")),
		"lod_policy": pol.duplicate(true),
		"max_equipment_glyphs": max_equipment_glyphs,
		"last_glyph_n": _last_equipment_glyph_n,
		"last_symbols": _last_equipment_symbols.duplicate(true),
		"aggregate": bool(pol.get("aggregate", false)),
		"style": str(pol.get("style", "discrete")),
		"model": "equipment_flow_compact_ledger",
	}


func _resolve_lod_policy() -> Dictionary:
	# Call MapZoomLOD statics via load()+call — never ClassName.has_method (parse error).
	var pol: Dictionary = {}
	var lod_scr = load("res://scripts/map/MapZoomLOD.gd")
	if lod_scr != null:
		pol = lod_scr.call("equipment_flow_glyph_policy", zoom_tier) as Dictionary
		var cap_v: Variant = lod_scr.call("max_equipment_flow_glyphs_for_board", zoom_tier, _province_count)
		if cap_v != null:
			pol["max_glyphs"] = int(cap_v)
		if not pol.is_empty():
			return pol
	match zoom_tier:
		0:
			return {"tier": "strategic", "show": true, "max_glyphs": 8, "aggregate": true, "style": "corridor", "draw_corridor_lines": true, "glyph_scale": 0.85}
		1:
			return {"tier": "operational", "show": true, "max_glyphs": 18, "aggregate": false, "style": "discrete", "draw_corridor_lines": true, "glyph_scale": 1.0}
		_:
			return {"tier": "tactical", "show": true, "max_glyphs": 32, "aggregate": false, "style": "discrete", "draw_corridor_lines": false, "glyph_scale": 1.15}


func _ready() -> void:
	z_index = 4
	set_process(true)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_signal("province_data_changed"):
		if not MapManager.province_data_changed.is_connected(_on_data):
			MapManager.province_data_changed.connect(_on_data)


func _on_data(_pid: int, _what: String) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if not enabled or not visible:
		return
	_phase = fmod(_phase + delta * anim_speed, 1.0)
	# Redraw every few frames only; world_full needs coarser cadence so pan/zoom stays live.
	var every := 8 if _province_count >= 800 else 3
	if Engine.get_process_frames() % every == 0:
		queue_redraw()


func refresh() -> void:
	queue_redraw()


func get_draw_stats() -> Dictionary:
	var q: Dictionary = get_equipment_flow_glyph_query()
	return {
		"route_n": _last_route_n,
		"arrow_n": _last_arrow_n,
		"equipment_glyph_n": _last_equipment_glyph_n,
		"equipment_symbols": _last_equipment_symbols.duplicate(true),
		"enabled": enabled,
		"sea": show_sea_lanes,
		"land": show_land_supply,
		"equipment_flows": show_equipment_flows,
		"equipment_flow_glyphs_enabled": equipment_flow_glyphs_enabled,
		"zoom_tier": zoom_tier,
		"lod_policy": _last_lod_policy.duplicate(true),
		"paint_ok": _last_equipment_glyph_n > 0 or not (show_equipment_flows and equipment_flow_glyphs_enabled),
		"glyph_query": q,
	}


func _draw() -> void:
	_last_route_n = 0
	_last_arrow_n = 0
	_last_equipment_glyph_n = 0
	_last_equipment_symbols = {}
	if not enabled:
		return
	var plans: Array = _collect_routes()
	var drawn := 0
	for plan_var in plans:
		if drawn >= max_routes:
			break
		var path: Array = []
		var is_sea := false
		var is_trade := false
		if plan_var is Dictionary:
			path = plan_var.get("path", []) as Array
			is_sea = bool(plan_var.get("sea", false))
			is_trade = bool(plan_var.get("trade", false))
		elif plan_var is Object and plan_var.has_method("get"):
			# SupplyRoutePlan-like
			if "province_path" in plan_var:
				path = plan_var.province_path
			if plan_var.has_method("primary_mode"):
				var mode := str(plan_var.primary_mode())
				is_sea = mode.contains("sea") or mode.contains("naval") or mode.contains("convoy")
			if "represents_trade_flow" in plan_var:
				is_trade = bool(plan_var.represents_trade_flow)
		if path.size() < 2:
			continue
		if is_sea and not show_sea_lanes:
			continue
		if not is_sea and not show_land_supply:
			continue
		var pts := PackedVector2Array()
		for pid_v in path:
			var pid := int(pid_v)
			if _centroids.has(pid):
				pts.append(_centroids[pid] as Vector2)
		if pts.size() < 2:
			continue
		var col := Color(0.45, 0.85, 0.55, 0.55) if not is_sea else Color(0.35, 0.65, 0.95, 0.5)
		if is_trade:
			col = Color(0.84, 0.7, 0.37, 0.42)
		draw_polyline(pts, col, line_width, true)
		_draw_flow_arrows(pts, col)
		_last_route_n += 1
		drawn += 1
	if show_equipment_flows and equipment_flow_glyphs_enabled:
		_draw_equipment_flow_glyphs()
	if show_chokepoints:
		_draw_chokepoints()


func _collect_routes() -> Array:
	var out: Array = []
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("get_all_routes"):
		for plan in SupplyManager.get_all_routes():
			out.append(plan)
			if out.size() >= max_routes:
				break
	if out.is_empty() and typeof(MapManager) != TYPE_NIL:
		# Fallback synthetic corridors from contested pairs (cheap visual proof)
		var contested: Dictionary = {}
		if MapManager.has_method("get_contested_provinces"):
			contested = MapManager.get_contested_provinces()
		var n := 0
		for pid_v in contested.keys():
			if n >= 8:
				break
			var pid := int(pid_v)
			var bundle: Dictionary = contested[pid] if contested[pid] is Dictionary else {}
			# Use adjacent if available
			if MapManager.has_method("get_adjacent_provinces"):
				var adj: Array = MapManager.get_adjacent_provinces(pid)
				if not adj.is_empty():
					out.append({"path": [pid, int(adj[0])], "sea": false, "trade": false})
					n += 1
	return out


func _draw_flow_arrows(pts: PackedVector2Array, col: Color) -> void:
	var total := 0.0
	var seglen: Array = []
	for i in range(pts.size() - 1):
		var d := pts[i].distance_to(pts[i + 1])
		seglen.append(d)
		total += d
	if total < 8.0:
		return
	var offset := _phase * arrow_spacing
	var dist := offset
	while dist < total:
		var acc := 0.0
		for i in range(seglen.size()):
			var seg: float = float(seglen[i])
			if acc + seg >= dist:
				var t := (dist - acc) / maxf(seg, 0.001)
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var pos := a.lerp(b, t)
				var dir := (b - a).normalized()
				_draw_arrow_head(pos, dir, col)
				_last_arrow_n += 1
				break
			acc += seg
		dist += arrow_spacing


func _draw_arrow_head(pos: Vector2, dir: Vector2, col: Color) -> void:
	var side := dir.orthogonal() * 4.5
	var tip := pos + dir * 6.0
	var left := pos - dir * 3.0 + side
	var right := pos - dir * 3.0 - side
	draw_colored_polygon(PackedVector2Array([tip, left, right]), col)


func _draw_chokepoints() -> void:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("has_strategic_chokepoint"):
		return
	var n := 0
	for pid_v in _centroids.keys():
		if n >= 16:
			break
		var pid := int(pid_v)
		if MapManager.has_strategic_chokepoint(pid):
			var c: Vector2 = _centroids[pid]
			draw_arc(c, 10.0, 0.0, TAU, 16, Color(0.3, 0.7, 1.0, 0.55), 1.6, true)
			draw_circle(c, 3.0, Color(0.5, 0.85, 1.0, 0.7))
			n += 1


## CP3: draw story glyphs per active EquipmentFlow, LOD-aware (aggregate at strategic).
func _draw_equipment_flow_glyphs() -> void:
	if typeof(ProductionManager) == TYPE_NIL or not ProductionManager.has_method("get_equipment_flow_board"):
		return
	var pol: Dictionary = _resolve_lod_policy()
	_last_lod_policy = pol.duplicate(true)
	if not bool(pol.get("show", true)):
		return
	var cap := int(pol.get("max_glyphs", max_equipment_glyphs))
	cap = mini(cap, max_equipment_glyphs)
	var aggregate := bool(pol.get("aggregate", false))
	var draw_lines := bool(pol.get("draw_corridor_lines", true))
	var gscale := float(pol.get("glyph_scale", 1.0))
	var board: Dictionary = ProductionManager.get_equipment_flow_board("")
	var glyphs: Array = board.get("glyphs", []) if board.get("glyphs") is Array else []
	if aggregate:
		glyphs = _aggregate_glyphs_by_symbol(glyphs)
	var drawn := 0
	for g_var in glyphs:
		if drawn >= cap:
			break
		if not (g_var is Dictionary):
			continue
		var g: Dictionary = g_var as Dictionary
		var from_pid := int(g.get("from_province", 0))
		var to_pid := int(g.get("to_province", 0))
		var a := _centroid_or_fallback(from_pid)
		var b := _centroid_or_fallback(to_pid)
		if a == Vector2.ZERO and b == Vector2.ZERO:
			continue
		if a == Vector2.ZERO:
			a = b + Vector2(-40, 0)
		if b == Vector2.ZERO:
			b = a + Vector2(40, 0)
		# Midpoint drifts with phase so glyphs feel in motion
		var t := 0.35 + 0.3 * _phase
		var pos := a.lerp(b, t)
		var sym := str(g.get("symbol", "train"))
		var mode := str(g.get("mode", "rail"))
		var col := _equipment_glyph_color(mode)
		if draw_lines:
			draw_line(a, b, Color(col.r, col.g, col.b, 0.28 if not aggregate else 0.38), 1.6 if not aggregate else 2.2, true)
		_draw_equipment_symbol(pos, sym, col, gscale)
		if aggregate and int(g.get("count", 1)) > 1:
			# Stack badge for aggregated corridor
			draw_circle(pos + Vector2(8, -8), 5.0, Color(0.1, 0.1, 0.12, 0.75))
		_last_equipment_symbols[sym] = int(_last_equipment_symbols.get(sym, 0)) + int(g.get("count", 1))
		_last_equipment_glyph_n += 1
		drawn += 1


func _aggregate_glyphs_by_symbol(glyphs: Array) -> Array:
	## One glyph per symbol family (strategic zoom density control).
	var by_sym: Dictionary = {}
	for g_var in glyphs:
		if not (g_var is Dictionary):
			continue
		var g: Dictionary = g_var as Dictionary
		var sym := str(g.get("symbol", "train"))
		if not by_sym.has(sym):
			var base: Dictionary = g.duplicate(true)
			base["count"] = 1
			by_sym[sym] = base
		else:
			var cur: Dictionary = by_sym[sym] as Dictionary
			cur["count"] = int(cur.get("count", 1)) + 1
			# Prefer wider span endpoints when aggregating
			by_sym[sym] = cur
	var out: Array = []
	for k in by_sym.keys():
		out.append(by_sym[k])
	return out


func _centroid_or_fallback(pid: int) -> Vector2:
	if pid > 0 and _centroids.has(pid):
		return _centroids[pid] as Vector2
	return Vector2.ZERO


func _equipment_glyph_color(mode: String) -> Color:
	match mode.strip_edges().to_lower():
		"rail":
			return Color(0.75, 0.55, 0.35, 0.9)
		"road":
			return Color(0.65, 0.7, 0.4, 0.9)
		"airlift", "helicopter":
			return Color(0.55, 0.75, 0.95, 0.9)
		"sealift", "river":
			return Color(0.35, 0.6, 0.9, 0.9)
		"drone_logistics":
			return Color(0.55, 0.9, 0.7, 0.9)
		"orbital":
			return Color(0.85, 0.6, 0.95, 0.9)
		_:
			return Color(0.8, 0.8, 0.55, 0.85)


func _draw_equipment_symbol(pos: Vector2, symbol: String, col: Color, scale_mult: float = 1.0) -> void:
	var s := clampf(scale_mult, 0.5, 1.6)
	var sym := symbol.strip_edges().to_lower()
	match sym:
		"train":
			draw_rect(Rect2(pos + Vector2(-8, -4) * s, Vector2(16, 8) * s), col)
			draw_rect(Rect2(pos + Vector2(-5, -9) * s, Vector2(4, 5) * s), col)
			draw_circle(pos + Vector2(-5, 5) * s, 2.0 * s, col)
			draw_circle(pos + Vector2(5, 5) * s, 2.0 * s, col)
		"truck":
			draw_rect(Rect2(pos + Vector2(-7, -3) * s, Vector2(14, 7) * s), col)
			draw_rect(Rect2(pos + Vector2(2, -6) * s, Vector2(5, 4) * s), Color(col.r, col.g, col.b, 0.7))
			draw_circle(pos + Vector2(-4, 5) * s, 2.0 * s, col)
			draw_circle(pos + Vector2(4, 5) * s, 2.0 * s, col)
		"transport_plane", "helicopter":
			draw_line(pos + Vector2(-10, 0) * s, pos + Vector2(10, 0) * s, col, 2.0 * s, true)
			draw_line(pos + Vector2(0, -3) * s, pos + Vector2(0, 5) * s, col, 1.6 * s, true)
			draw_line(pos + Vector2(-6, 0) * s, pos + Vector2(6, -4) * s, col, 1.4 * s, true)
			draw_line(pos + Vector2(-6, 0) * s, pos + Vector2(6, 4) * s, col, 1.4 * s, true)
		"merchant", "barge":
			draw_colored_polygon(PackedVector2Array([
				pos + Vector2(-9, 2) * s, pos + Vector2(9, 2) * s, pos + Vector2(6, -3) * s, pos + Vector2(-6, -3) * s,
			]), col)
			draw_line(pos + Vector2(0, -3) * s, pos + Vector2(0, -8) * s, col, 1.2 * s, true)
		"drone_convoy":
			draw_circle(pos, 3.0 * s, col)
			draw_circle(pos + Vector2(7, -2) * s, 2.0 * s, Color(col.r, col.g, col.b, 0.7))
			draw_circle(pos + Vector2(-6, 3) * s, 2.0 * s, Color(col.r, col.g, col.b, 0.7))
		"orbital_loft":
			draw_arc(pos, 7.0 * s, 0.0, TAU, 14, col, 1.4 * s, true)
			draw_circle(pos, 2.2 * s, col)
			draw_line(pos + Vector2(0, -10) * s, pos + Vector2(0, -4) * s, col, 1.5 * s, true)
		_:
			draw_circle(pos, 4.0 * s, col)


## Pure/live dual helper: describe what the paint layer would show without requiring a scene.
## opts: zoom_tier (0–2), glyphs_enabled, province_count
static func collect_equipment_paint_preview(centroids: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var preview := {
		"ok": false,
		"paint_ok": false,
		"glyph_n": 0,
		"symbols": {},
		"glyphs": [],
		"model": "equipment_flow_compact_ledger",
	}
	if typeof(ProductionManager) == TYPE_NIL or not ProductionManager.has_method("get_equipment_flow_board"):
		return preview
	var glyphs_enabled := true if not opts.has("glyphs_enabled") else bool(opts.get("glyphs_enabled", true))
	var tier := int(opts.get("zoom_tier", 0))
	var lod_scr = load("res://scripts/map/MapZoomLOD.gd")
	var pol: Dictionary = {}
	if lod_scr != null:
		pol = lod_scr.call("equipment_flow_glyph_policy", tier) as Dictionary
		var pc := int(opts.get("province_count", centroids.size()))
		var cap_v: Variant = lod_scr.call("max_equipment_flow_glyphs_for_board", tier, pc)
		if cap_v != null:
			pol["max_glyphs"] = int(cap_v)
	if pol.is_empty():
		pol = {"tier": "strategic", "show": true, "max_glyphs": 8, "aggregate": tier == 0, "style": "corridor" if tier == 0 else "discrete"}
	if not glyphs_enabled or not bool(pol.get("show", true)):
		preview["ok"] = true
		preview["paint_ok"] = false
		preview["glyphs_enabled"] = glyphs_enabled
		preview["lod_policy"] = pol
		preview["visible"] = false
		preview["layer"] = "StrategicFlowOverlayLayer"
		return preview
	var board: Dictionary = ProductionManager.get_equipment_flow_board("")
	var glyphs: Array = board.get("glyphs", []) if board.get("glyphs") is Array else []
	var symbols: Dictionary = board.get("symbols", {}) if board.get("symbols") is Dictionary else {}
	if bool(pol.get("aggregate", false)):
		# Mirror layer aggregate: one entry per symbol
		var by_sym: Dictionary = {}
		for g_var in glyphs:
			if not (g_var is Dictionary):
				continue
			var g0: Dictionary = g_var as Dictionary
			var sym0 := str(g0.get("symbol", "train"))
			by_sym[sym0] = int(by_sym.get(sym0, 0)) + 1
		var agg: Array = []
		for sk in by_sym.keys():
			agg.append({"symbol": sk, "count": int(by_sym[sk]), "drawable": true, "aggregated": true})
		glyphs = agg
	var cap := int(pol.get("max_glyphs", 24))
	var placed: Array = []
	for g_var in glyphs:
		if placed.size() >= cap:
			break
		if not (g_var is Dictionary):
			continue
		var g: Dictionary = (g_var as Dictionary).duplicate(true)
		var from_pid := int(g.get("from_province", 0))
		var to_pid := int(g.get("to_province", 0))
		var has_geo := centroids.is_empty() or centroids.has(from_pid) or centroids.has(to_pid)
		g["has_geo"] = has_geo
		g["drawable"] = true
		placed.append(g)
	preview["glyphs"] = placed
	preview["glyph_n"] = placed.size()
	preview["symbols"] = symbols.duplicate(true)
	preview["paint_ok"] = placed.size() > 0
	preview["ok"] = true
	preview["layer"] = "StrategicFlowOverlayLayer"
	preview["show_equipment_flows"] = true
	preview["glyphs_enabled"] = glyphs_enabled
	preview["visible"] = glyphs_enabled and bool(pol.get("show", true))
	preview["lod_policy"] = pol
	preview["zoom_tier"] = tier
	return preview
