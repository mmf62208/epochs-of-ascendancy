class_name SupplyMapLayer
extends Node2D

## Draws land / sea / air supply routes on the map.
## Canvas `z_index` is driven from `MapRenderer.supply_route_layer_z_order` — keep polylines below
## floating province name Labels and above raw `Polygon2D` fills. Per-province supply/engineer rings
## (`ProvinceMapVisuals.Z_SUPPLY`) draw inside each province subtree, so routes still read across the corridor.
## Trade corridors (SupplyRoutePlan.represents_trade_flow) draw first, thinner and more transparent,
## so player logistics routes read as the primary overlay. Province `trade_transit` rings (`ProvinceMapVisuals OUTLINE_TRADE_TRANSIT`)
## use a matching soft amber so corridors read as one logistics family. See MapRenderer / TradeManager map queries.
## `setup()` assigns a provisional `z_index`; authoritative ordering comes from MapRenderer `_sync_supply_route_canvas_stack()` (`supply_route_layer_z_order`).

@export var line_width: float = 3.0
## Trade corridors use a quieter style (see _draw_single_route).
## Trade corridors — softer than military routes; underglow separates them visually without dominating hubs.
@export var trade_corridor_alpha: float = 0.235
@export var trade_corridor_width_scale: float = 0.34
@export_range(1.0, 3.5, 0.05) var trade_corridor_underglow_width_mul: float = 2.15
@export_range(0.0, 0.95, 0.05) var trade_corridor_underglow_alpha_mul: float = 0.42
## Pass 10/11: retrowave convoy chips along trade corridors (animated travel).
@export var show_convoy_markers: bool = true
@export var convoy_marker_size: float = 18.0
@export var convoy_marker_max: int = 24
## Seconds for a full end-to-end loop along a corridor.
@export var convoy_loop_seconds: float = 14.0
## Extra trailing ghost chip (0 = off).
@export var convoy_trail_count: int = 1
@export var convoy_trail_spacing: float = 0.08
## Pass 12: interdiction flash when route risk is high.
@export var show_interdiction_flash: bool = true
@export var interdiction_flash_threshold: float = 0.18
var _centroids: Dictionary = {}
var _rules: SupplyRules = null
## Extra dim for trade polylines while Supply overlay (L) is on — military routes use layer `self_modulate` only.
var trade_corridor_supply_dim: float = 1.0
var _convoy_tex: Texture2D = null
var _convoy_tex_checked: bool = false
var _routes_to_draw: Array = []
var _convoy_phase: float = 0.0
## Each entry: {pts: PackedVector2Array, interdiction: float, trade: bool}
var _trade_paths_cache: Array = []
var _flash_phase: float = 0.0
## When true (G / F5 play mode): skip bulk route spiderweb; only highlight polyline draws.
## Trade mesh alone was the yellow-lime blinking web over Europe.
var corridor_focus_only: bool = false
## Pass 18: highlighted route polyline (from minimap double-click).
var _highlight_pts: PackedVector2Array = PackedVector2Array()
var _highlight_ttl: float = 0.0
@export var highlight_seconds: float = 4.5
## Pass 19/26/27: multi-route compare (A cyan, B magenta, C amber, D green).
var _compare_a: PackedVector2Array = PackedVector2Array()
var _compare_b: PackedVector2Array = PackedVector2Array()
var _compare_c: PackedVector2Array = PackedVector2Array()
var _compare_d: PackedVector2Array = PackedVector2Array()
var _compare_ttl: float = 0.0


func setup(centroids: Dictionary, rules: SupplyRules) -> void:
	_centroids = centroids
	_rules = rules
	z_index = 60
	_ensure_convoy_tex()
	set_process(true)
	queue_redraw()


func set_routes(plans: Array) -> void:
	_routes_to_draw = plans
	_rebuild_trade_path_cache()
	queue_redraw()


## Pass 18: pulse-highlight a route path (world polyline).
func highlight_route_points(pts: PackedVector2Array, seconds: float = -1.0) -> void:
	_highlight_pts = pts.duplicate()
	_highlight_ttl = seconds if seconds > 0.0 else highlight_seconds
	visible = true
	queue_redraw()


func clear_route_highlight() -> void:
	_highlight_pts = PackedVector2Array()
	_highlight_ttl = 0.0
	queue_redraw()


## Pass 19: draw two routes for side-by-side compare.
func compare_route_points(pts_a: PackedVector2Array, pts_b: PackedVector2Array, seconds: float = 6.0) -> void:
	_compare_a = pts_a.duplicate()
	_compare_b = pts_b.duplicate()
	_compare_c = PackedVector2Array()
	_compare_d = PackedVector2Array()
	_compare_ttl = maxf(1.0, seconds)
	# Clear single highlight so compare owns the focus.
	_highlight_pts = PackedVector2Array()
	_highlight_ttl = 0.0
	visible = true
	queue_redraw()


## Pass 26: three-route compare (A cyan / B magenta / C amber).
func compare_route_points_abc(
	pts_a: PackedVector2Array,
	pts_b: PackedVector2Array,
	pts_c: PackedVector2Array,
	seconds: float = 7.0
) -> void:
	_compare_a = pts_a.duplicate()
	_compare_b = pts_b.duplicate()
	_compare_c = pts_c.duplicate()
	_compare_d = PackedVector2Array()
	_compare_ttl = maxf(1.0, seconds)
	_highlight_pts = PackedVector2Array()
	_highlight_ttl = 0.0
	visible = true
	queue_redraw()


## Pass 27: four-route pack (A cyan / B magenta / C amber / D green).
func compare_route_points_abcd(
	pts_a: PackedVector2Array,
	pts_b: PackedVector2Array,
	pts_c: PackedVector2Array,
	pts_d: PackedVector2Array,
	seconds: float = 8.0
) -> void:
	_compare_a = pts_a.duplicate()
	_compare_b = pts_b.duplicate()
	_compare_c = pts_c.duplicate()
	_compare_d = pts_d.duplicate()
	_compare_ttl = maxf(1.0, seconds)
	_highlight_pts = PackedVector2Array()
	_highlight_ttl = 0.0
	visible = true
	queue_redraw()


func clear_route_compare() -> void:
	_compare_a = PackedVector2Array()
	_compare_b = PackedVector2Array()
	_compare_c = PackedVector2Array()
	_compare_d = PackedVector2Array()
	_compare_ttl = 0.0
	queue_redraw()


func _ensure_convoy_tex() -> void:
	if _convoy_tex_checked:
		return
	_convoy_tex_checked = true
	var path := "res://assets/graphics/units/retrowave/convoy_32.png"
	if ResourceLoader.exists(path):
		_convoy_tex = load(path) as Texture2D


func _process(delta: float) -> void:
	if _highlight_ttl > 0.0:
		_highlight_ttl = maxf(0.0, _highlight_ttl - delta)
		if _highlight_ttl <= 0.0:
			_highlight_pts = PackedVector2Array()
		queue_redraw()
	if _compare_ttl > 0.0:
		_compare_ttl = maxf(0.0, _compare_ttl - delta)
		if _compare_ttl <= 0.0:
			_compare_a = PackedVector2Array()
			_compare_b = PackedVector2Array()
			_compare_c = PackedVector2Array()
			_compare_d = PackedVector2Array()
		queue_redraw()
	if not visible or not show_convoy_markers or _trade_paths_cache.is_empty():
		if _highlight_ttl > 0.0 or _compare_ttl > 0.0:
			return
		return
	# Animate even when sim paused — pure visual polish (matches stack pulse).
	var loop_s := maxf(4.0, convoy_loop_seconds)
	_convoy_phase = fmod(_convoy_phase + delta / loop_s, 1.0)
	_flash_phase = fmod(_flash_phase + delta * 3.2, TAU)
	queue_redraw()


func _rebuild_trade_path_cache() -> void:
	_trade_paths_cache.clear()
	for plan_var in _routes_to_draw:
		if not (plan_var is SupplyRoutePlan):
			continue
		var plan := plan_var as SupplyRoutePlan
		# Animate trade corridors + military routes with meaningful interdiction risk.
		var is_trade := bool(plan.represents_trade_flow)
		var inter := float(plan.interdiction_chance) if "interdiction_chance" in plan else 0.0
		if not is_trade and inter < interdiction_flash_threshold * 0.5:
			continue
		if plan.province_path.size() < 2:
			continue
		var pts := _path_points(plan)
		if pts.size() >= 2:
			var focus_pid := int(plan.target_province_id) if "target_province_id" in plan else -1
			if focus_pid < 0 and plan.province_path.size() > 0:
				focus_pid = int(plan.province_path[plan.province_path.size() - 1])
			_trade_paths_cache.append({
				"pts": pts,
				"interdiction": inter,
				"trade": is_trade,
				"focus_pid": focus_pid,
			})


func _draw() -> void:
	# Pass 18/19: highlighted / compare routes (always drawn — the intended G corridor).
	if _compare_ttl > 0.0:
		_draw_route_compare()
	elif _highlight_pts.size() >= 2 and _highlight_ttl > 0.0:
		_draw_route_highlight()
	# Corridor-focus (G playtest): no bulk trade/military mesh — that was the blinking spiderweb.
	if corridor_focus_only:
		return
	if _routes_to_draw.is_empty():
		return
	var colors_cfg := {}
	if _rules != null:
		colors_cfg = _rules.get_block("overlay_colors")

	var trade_plans: Array = []
	var other_plans: Array = []
	for plan_var in _routes_to_draw:
		if not (plan_var is SupplyRoutePlan):
			continue
		var plan := plan_var as SupplyRoutePlan
		if plan.province_path.size() < 2:
			continue
		if plan.represents_trade_flow:
			trade_plans.append(plan)
		else:
			other_plans.append(plan)
	for plan in trade_plans:
		_draw_single_route(plan, colors_cfg, true)
	for plan in other_plans:
		_draw_single_route(plan, colors_cfg, false)
	# Pass 10/11: animated convoy chips along trade corridors.
	if show_convoy_markers:
		_draw_trade_convoy_markers()
	# Redraw highlight / compare above markers.
	if _compare_ttl > 0.0:
		_draw_route_compare()
	elif _highlight_pts.size() >= 2 and _highlight_ttl > 0.0:
		_draw_route_highlight()


func _draw_route_highlight() -> void:
	if _highlight_pts.size() < 2:
		return
	var t := clampf(_highlight_ttl / maxf(0.1, highlight_seconds), 0.0, 1.0)
	var pulse := 0.55 + 0.45 * sin(_flash_phase * 1.7)
	var col := Color(1.0, 0.85, 0.25, 0.35 + 0.45 * t * pulse)
	var w := line_width * (2.2 + pulse * 0.8)
	draw_polyline(_highlight_pts, Color(1.0, 0.5, 0.15, 0.25 * t), w * 1.6, true)
	draw_polyline(_highlight_pts, col, w, true)
	# Endpoint gems
	draw_circle(_highlight_pts[0], 5.0, Color(1.0, 0.9, 0.4, 0.7 * t))
	draw_circle(_highlight_pts[_highlight_pts.size() - 1], 5.5, Color(1.0, 0.55, 0.25, 0.8 * t))


func _draw_route_compare() -> void:
	var t := clampf(_compare_ttl / 7.0, 0.0, 1.0)
	var pulse := 0.55 + 0.45 * sin(_flash_phase * 1.4)
	var w := line_width * (2.0 + pulse * 0.5)
	if _compare_a.size() >= 2:
		var ca := Color(0.35, 0.9, 1.0, 0.4 + 0.45 * t * pulse)
		draw_polyline(_compare_a, Color(0.15, 0.45, 0.7, 0.3 * t), w * 1.5, true)
		draw_polyline(_compare_a, ca, w, true)
		draw_circle(_compare_a[0], 4.5, Color(0.5, 0.95, 1.0, 0.75 * t))
		draw_circle(_compare_a[_compare_a.size() - 1], 5.0, Color(0.3, 0.85, 1.0, 0.85 * t))
	if _compare_b.size() >= 2:
		var cb := Color(1.0, 0.4, 0.85, 0.4 + 0.45 * t * pulse)
		draw_polyline(_compare_b, Color(0.55, 0.15, 0.45, 0.3 * t), w * 1.5, true)
		draw_polyline(_compare_b, cb, w, true)
		draw_circle(_compare_b[0], 4.5, Color(1.0, 0.55, 0.9, 0.75 * t))
		draw_circle(_compare_b[_compare_b.size() - 1], 5.0, Color(0.95, 0.35, 0.75, 0.85 * t))
	# Pass 26: route C amber.
	if _compare_c.size() >= 2:
		var cc := Color(1.0, 0.78, 0.28, 0.4 + 0.45 * t * pulse)
		draw_polyline(_compare_c, Color(0.55, 0.35, 0.08, 0.3 * t), w * 1.5, true)
		draw_polyline(_compare_c, cc, w, true)
		draw_circle(_compare_c[0], 4.5, Color(1.0, 0.9, 0.45, 0.75 * t))
		draw_circle(_compare_c[_compare_c.size() - 1], 5.0, Color(0.95, 0.7, 0.2, 0.85 * t))
	# Pass 27: route D green.
	if _compare_d.size() >= 2:
		var cd := Color(0.4, 0.95, 0.55, 0.4 + 0.45 * t * pulse)
		draw_polyline(_compare_d, Color(0.1, 0.4, 0.2, 0.3 * t), w * 1.5, true)
		draw_polyline(_compare_d, cd, w, true)
		draw_circle(_compare_d[0], 4.5, Color(0.55, 1.0, 0.65, 0.75 * t))
		draw_circle(_compare_d[_compare_d.size() - 1], 5.0, Color(0.3, 0.9, 0.45, 0.85 * t))


func _draw_single_route(plan: SupplyRoutePlan, colors_cfg: Dictionary, is_trade_corridor: bool) -> void:
	var color := _color_for_plan(plan, colors_cfg)
	var w := line_width
	if is_trade_corridor:
		var base_a := clampf(
			trade_corridor_alpha * clampf(trade_corridor_supply_dim, 0.55, 1.0),
			0.08,
			0.5,
		)
		color = ProvinceMapVisuals.COLOR_TRADE_CORRIDOR
		color.a = base_a
		w = maxf(1.0, line_width * clampf(trade_corridor_width_scale, 0.22, 0.52))
		# Regional convoy protection makes trade corridors more prominent (thicker/brighter) when owner has full naval/chokepoint regions
		if plan.owner_tag and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
			var reg := MapManager.get_active_regional_control_bonuses(plan.owner_tag)
			var prot := float(reg.get("convoy_efficiency", 0.0)) + float(reg.get("convoy_protection", 0.0))
			if prot > 0.0:
				color.a = clampf(color.a * (1.0 + prot * 0.8), 0.08, 0.8)
				w = maxf(w, line_width * (1.0 + prot * 0.4))
	var points: PackedVector2Array = _path_points(plan)
	if points.size() >= 2:
		if is_trade_corridor and trade_corridor_underglow_alpha_mul > 0.02:
			var glow := color
			glow.a = clampf(color.a * trade_corridor_underglow_alpha_mul, 0.04, 0.28)
			var gw := maxf(w * trade_corridor_underglow_width_mul, w + 1.2)
			draw_polyline(points, glow, gw, true)
		draw_polyline(points, color, w, true)
		_draw_route_nodes(points, color, is_trade_corridor)


func _color_for_plan(plan: SupplyRoutePlan, colors_cfg: Dictionary) -> Color:
	var key := plan.primary_mode()
	var raw: Variant = colors_cfg.get(key, colors_cfg.get("land", [0.4, 0.9, 0.5, 0.9]))
	if typeof(raw) == TYPE_ARRAY and raw.size() >= 3:
		var a := 0.9
		if raw.size() >= 4:
			a = float(raw[3])
		var col := Color(float(raw[0]), float(raw[1]), float(raw[2]), a)
		# Tint trade corridors greener if high convoy protection from full regions
		if plan.represents_trade_flow and plan.owner_tag and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_active_regional_control_bonuses"):
			var reg := MapManager.get_active_regional_control_bonuses(plan.owner_tag)
			var prot := float(reg.get("convoy_efficiency", 0.0)) + float(reg.get("convoy_protection", 0.0))
			if prot > 0.0:
				col = col.lerp(Color(0.2, 0.8, 0.3), clampf(prot * 0.5, 0.0, 0.5))
		return col
	return Color(0.4, 0.9, 0.5, 0.9)


func _draw_route_nodes(points: PackedVector2Array, color: Color, small: bool = false) -> void:
	var r := 2.6 if small else 4.0
	var r2 := 4.2 if small else 6.0
	var lw := 1.0 if small else 1.5
	# Trade: only endpoints when path is long — reduces sparkle along the corridor.
	if small and points.size() > 2:
		var tc := color.darkened(0.07)
		_draw_one_route_node(points[0], tc, r * 0.82, r2 * 0.82, lw * 0.85)
		_draw_one_route_node(points[points.size() - 1], tc, r * 0.82, r2 * 0.82, lw * 0.85)
		return
	for pt in points:
		_draw_one_route_node(pt, color, r, r2, lw)


func _draw_one_route_node(pt: Vector2, color: Color, r: float, r2: float, lw: float) -> void:
	draw_circle(pt, r, color)
	draw_arc(pt, r2, 0.0, TAU, 12, color.darkened(0.2), lw)


## Pass 11/12: convoy chips travel along routes; high interdiction gets attack flash FX.
func _draw_trade_convoy_markers() -> void:
	_ensure_convoy_tex()
	if _convoy_tex == null:
		return
	if _trade_paths_cache.is_empty():
		_rebuild_trade_path_cache()
	var drawn := 0
	var max_n := maxi(1, convoy_marker_max)
	var sz := clampf(convoy_marker_size, 8.0, 28.0)
	var trail_n := clampi(convoy_trail_count, 0, 3)
	var spacing := clampf(convoy_trail_spacing, 0.03, 0.25)
	var thr := clampf(interdiction_flash_threshold, 0.05, 0.9)
	# Stagger phases so parallel routes don't march in lockstep.
	var i := 0
	for entry_v in _trade_paths_cache:
		if drawn >= max_n:
			break
		var pts: PackedVector2Array
		var inter := 0.0
		if entry_v is Dictionary:
			var e: Dictionary = entry_v
			if not (e.get("pts") is PackedVector2Array):
				continue
			pts = e.get("pts") as PackedVector2Array
			inter = float(e.get("interdiction", 0.0))
		elif entry_v is PackedVector2Array:
			pts = entry_v as PackedVector2Array
		else:
			continue
		if pts.size() < 2:
			continue
		var phase_off := fmod(float(i) * 0.17, 1.0)
		var t0 := fmod(_convoy_phase + phase_off, 1.0)
		var lead_pos := Vector2.INF
		for k in range(trail_n + 1):
			var t := fmod(t0 - float(k) * spacing + 1.0, 1.0)
			var pos := _point_along_polyline(pts, t)
			if pos == Vector2.INF:
				continue
			if k == 0:
				lead_pos = pos
			var alpha := 1.0 if k == 0 else clampf(0.55 - float(k) * 0.18, 0.2, 0.55)
			var scale_k := 1.0 if k == 0 else clampf(0.85 - float(k) * 0.1, 0.55, 0.85)
			var s := sz * scale_k
			var h := Vector2(s, s) * 0.5
			draw_circle(pos, s * 0.55, Color(0.05, 0.08, 0.16, 0.55 * alpha))
			var rect := Rect2(pos - h, Vector2(s, s))
			# Under interdiction, tint lead convoy warmer/red.
			var mod := Color(1, 1, 1, alpha)
			if k == 0 and inter >= thr:
				mod = Color(1.0, 0.55, 0.45, alpha)
			draw_texture_rect(_convoy_tex, rect, false, mod)
		if show_interdiction_flash and inter >= thr and lead_pos != Vector2.INF:
			_draw_interdiction_flash(lead_pos, inter, thr)
		drawn += 1
		i += 1


## Pass 12: pulsing strike rings + radial spokes on threatened convoy.
func _draw_interdiction_flash(pos: Vector2, inter: float, thr: float) -> void:
	var risk := clampf((inter - thr) / maxf(0.01, 1.0 - thr), 0.0, 1.0)
	var pulse := 0.55 + 0.45 * sin(_flash_phase + inter * 7.0)
	var r_outer := 10.0 + risk * 10.0 * pulse
	var col := Color(1.0, 0.25 + 0.2 * (1.0 - risk), 0.15, 0.35 + 0.45 * pulse * risk)
	draw_arc(pos, r_outer, 0.0, TAU, 20, col, 1.6 + risk, true)
	draw_arc(pos, r_outer * 0.55, 0.0, TAU, 16, Color(col.r, col.g, col.b, col.a * 0.7), 1.1, true)
	# Burst spokes (attack vectors)
	var spokes := 4 + int(risk * 4.0)
	for s in spokes:
		var ang := TAU * float(s) / float(spokes) + _flash_phase * 0.35
		var tip := pos + Vector2(cos(ang), sin(ang)) * (r_outer * 1.15)
		draw_line(pos, tip, Color(1.0, 0.4, 0.2, 0.25 + 0.35 * pulse * risk), 1.2, true)
	# Hot core flash
	if pulse > 0.85:
		draw_circle(pos, 3.0 + risk * 2.0, Color(1.0, 0.85, 0.35, 0.55 * pulse))


func _path_points(plan: SupplyRoutePlan) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if plan == null:
		return points
	for pid in plan.province_path:
		if _centroids.has(pid):
			points.append(_centroids[pid])
	return points


func _route_midpoint(plan: SupplyRoutePlan) -> Vector2:
	var pts := _path_points(plan)
	if pts.size() < 2:
		return Vector2.INF
	return _point_along_polyline(pts, 0.5)


## t in [0,1] along cumulative segment lengths.
func _point_along_polyline(pts: PackedVector2Array, t: float) -> Vector2:
	if pts.size() < 2:
		return Vector2.INF
	t = clampf(t, 0.0, 1.0)
	var total := 0.0
	var segs: PackedFloat32Array = PackedFloat32Array()
	for i in range(pts.size() - 1):
		var d := pts[i].distance_to(pts[i + 1])
		segs.append(d)
		total += d
	if total < 0.001:
		return pts[0]
	var target := t * total
	var acc := 0.0
	for i in range(segs.size()):
		var seg_len := segs[i]
		if acc + seg_len >= target - 0.0001:
			var u := 0.0 if seg_len < 0.001 else (target - acc) / seg_len
			return pts[i].lerp(pts[i + 1], clampf(u, 0.0, 1.0))
		acc += seg_len
	return pts[pts.size() - 1]
