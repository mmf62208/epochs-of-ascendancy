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
var _centroids: Dictionary = {}
var _rules: SupplyRules = null
## Extra dim for trade polylines while Supply overlay (L) is on — military routes use layer `self_modulate` only.
var trade_corridor_supply_dim: float = 1.0


func setup(centroids: Dictionary, rules: SupplyRules) -> void:
	_centroids = centroids
	_rules = rules
	z_index = 60
	queue_redraw()


func set_routes(plans: Array) -> void:
	_routes_to_draw = plans
	queue_redraw()


var _routes_to_draw: Array = []


func _draw() -> void:
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
	var points: PackedVector2Array = PackedVector2Array()
	for pid in plan.province_path:
		if _centroids.has(pid):
			points.append(_centroids[pid])
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
		return Color(float(raw[0]), float(raw[1]), float(raw[2]), a)
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
