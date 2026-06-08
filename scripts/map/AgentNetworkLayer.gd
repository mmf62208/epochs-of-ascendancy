# scripts/map/AgentNetworkLayer.gd
## Agent network rings at province centroids (strength = network effectiveness).

class_name AgentNetworkLayer
extends Node2D

@export var ring_color: Color = Color(0.62, 0.45, 0.98, 0.88)
@export var ring_color_highlight: Color = Color(0.78, 0.58, 1.0, 0.98)
@export var ring_color_high_pressure: Color = Color(1.0, 0.42, 0.48, 0.9)
@export var ring_color_supply_disrupt: Color = Color(0.98, 0.58, 0.28, 0.92)
@export var ring_color_infra_sabotage: Color = Color(1.0, 0.38, 0.45, 0.92)
@export var ring_color_infra_repair: Color = Color(0.22, 0.95, 0.78, 0.9)
@export var ring_width: float = 2.8
@export var ring_width_highlight: float = 3.6
@export var max_ring_radius: float = 22.0
@export var min_ring_radius: float = 7.0
@export var pressure_reduction: float = 0.55
@export var show_focus_color_tint: bool = true
@export var double_ring_for_strong_low_pressure: bool = true
@export var target_country: String = ""

var _highlight_province_id: int = -1
var _pulse_phase: float = 0.0
var _pulse_active_until_msec: int = -1
var _ambient_pressure_active: bool = false


func _ready() -> void:
	z_index = 6
	if typeof(MapManager) != TYPE_NIL and MapManager.has_signal("province_data_changed"):
		if not MapManager.province_data_changed.is_connected(_on_province_data_changed):
			MapManager.province_data_changed.connect(_on_province_data_changed)

	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_day_advanced.is_connected(_on_daily_tick):
			TimeManager.game_day_advanced.connect(_on_daily_tick)


func setup() -> void:
	queue_redraw()


func set_highlight_province(province_id: int) -> void:
	if _highlight_province_id == province_id:
		return
	_highlight_province_id = province_id
	queue_redraw()


func trigger_daily_pulse(duration_msec: int = 2800) -> void:
	_pulse_phase = 0.0
	_pulse_active_until_msec = Time.get_ticks_msec() + duration_msec
	set_process(true)
	queue_redraw()


func is_daily_pulse_active() -> bool:
	return Time.get_ticks_msec() <= _pulse_active_until_msec


func _process(delta: float) -> void:
	var daily_pulse := is_daily_pulse_active()
	if daily_pulse:
		_pulse_phase += delta * 4.5
	elif _ambient_pressure_active:
		_pulse_phase += delta * 2.4
	else:
		set_process(false)
		return
	if daily_pulse and Time.get_ticks_msec() > _pulse_active_until_msec:
		if _ambient_pressure_active:
			_pulse_active_until_msec = -1
		else:
			set_process(false)
			return
	queue_redraw()


func _on_province_data_changed(_pid: int, what: String) -> void:
	if what in ["owner", "controller", "all", "effects", "infrastructure"]:
		queue_redraw()


func _on_daily_tick(_year: int, _month: int, _day: int) -> void:
	trigger_daily_pulse()


static func count_active_networks(provinces: Dictionary = {}, country_tag: String = "") -> int:
	if typeof(AgentManager) == TYPE_NIL:
		return 0
	var tag := country_tag.strip_edges().to_upper()
	if not tag.is_empty():
		var n := 0
		for net in AgentManager.get_networks_for_country(tag):
			if net != null and net.is_active():
				n += 1
		return n
	var total := 0
	for pid_var in provinces.keys():
		var net: AgentNetwork = AgentManager.get_network(int(pid_var))
		if net != null and net.is_active():
			total += 1
	return total


## Viewport bounds in map/world space (same coordinates as MapManager centroids).
func _get_camera_world_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var cam := vp.get_camera_2d()
	if cam == null:
		return Rect2()
	var screen_rect := vp.get_visible_rect()
	var inv := cam.get_canvas_transform().affine_inverse()
	var p0: Vector2 = inv * screen_rect.position
	var p1: Vector2 = inv * (screen_rect.position + Vector2(screen_rect.size.x, 0.0))
	var p2: Vector2 = inv * (screen_rect.position + screen_rect.size)
	var p3: Vector2 = inv * (screen_rect.position + Vector2(0.0, screen_rect.size.y))
	var min_x: float = minf(minf(p0.x, p1.x), minf(p2.x, p3.x))
	var max_x: float = maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x))
	var min_y: float = minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
	var max_y: float = maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


func _draw() -> void:
	if typeof(MapManager) == TYPE_NIL or typeof(AgentManager) == TYPE_NIL:
		return

	var visible_rect: Rect2 = _get_camera_world_rect()
	var visible_pids: Array[int] = []
	if visible_rect.has_area():
		visible_pids = MapManager.get_provinces_in_rect(visible_rect.grow(80.0))

	var tag_filter := target_country.strip_edges().to_upper()
	var networks: Array[AgentNetwork] = []
	if not tag_filter.is_empty():
		networks = AgentManager.get_networks_for_country(tag_filter)
	else:
		for pid in MapManager.get_all_provinces().keys():
			var net: AgentNetwork = AgentManager.get_network(int(pid))
			if net != null:
				networks.append(net)

	var global_pulse := is_daily_pulse_active()
	var pulse_wave := 0.5 + 0.5 * sin(_pulse_phase) if global_pulse else 0.0
	_ambient_pressure_active = false

	for net in networks:
		if net == null or not net.is_active():
			continue
		var pid := net.province_id
		if visible_rect.has_area() and pid not in visible_pids:
			continue
		var data := MapManager.get_overlay_data_for_province(pid, net.controlling_country) as Dictionary
		if data.is_empty():
			continue
		var c: Vector2 = data.get("centroid", Vector2.ZERO)
		var owner := str(data.get("owner", ""))
		var controller := str(data.get("controller", ""))
		var pressure := _enemy_pressure(pid, owner, controller)
		var base := net.get_effectiveness()
		var effective := clampf(base * (1.0 - pressure * pressure_reduction), 0.08, 1.0)
		var emphasized := pid == _highlight_province_id
		var activity_note := net.last_daily_note.strip_edges()
		var pressure_focus := net.focus in ["supply_disruption", "infrastructure_sabotage"]
		var today_hit := activity_note in ["disrupt", "sabotage", "infra_pressure"]
		var activity_pulse := global_pulse and (
			pulse_wave > 0.55
			or not activity_note.is_empty()
			or pressure_focus
		)
		_draw_network_ring(
			c,
			effective,
			emphasized,
			net.focus,
			pressure,
			activity_pulse,
			activity_note,
			pressure_focus,
			today_hit,
			pid,
		)
		if pressure_focus:
			_ambient_pressure_active = true

	if _ambient_pressure_active or global_pulse:
		set_process(true)


func _enemy_pressure(province_id: int, owner: String, controller: String) -> float:
	var pressure := 0.0
	if owner != controller and not controller.is_empty():
		pressure += 0.45
	for nid in MapManager.get_adjacent_provinces(province_id, true) as Array:
		var ndata := MapManager.get_overlay_data_for_province(int(nid)) as Dictionary
		if ndata.is_empty():
			continue
		if str(ndata.get("owner", "")) != str(ndata.get("controller", "")):
			pressure += 0.12
	return clampf(pressure, 0.0, 1.0)


func _draw_pressure_status_bars(center: Vector2, radius: float, province_id: int, focus: String) -> void:
	if typeof(MapManager) == TYPE_NIL:
		return
	var p: Province = MapManager.get_province(province_id) as Province
	if p == null:
		return
	var bar_w := 16.0
	var bar_h := 3.0
	var pos := center + Vector2(-bar_w * 0.5, radius + 5.0)
	if focus == "infrastructure_sabotage":
		draw_rect(Rect2(pos, Vector2(bar_w, bar_h)), Color(0.12, 0.1, 0.14, 0.8), true)
		var t := clampf(float(p.infrastructure) / 50.0, 0.0, 1.0)
		var fill_col := Color(0.4, 0.92, 0.55) if p.infrastructure > 20 else Color(1.0, 0.52, 0.32)
		draw_rect(Rect2(pos, Vector2(bar_w * t, bar_h)), Color(fill_col, 0.92), true)
		if typeof(MapManager) != TYPE_NIL:
			var rate := MapManager.get_infrastructure_repair_rate(province_id)
			var repair_t := clampf(rate / 0.35, 0.05, 1.0)
			var repair_pos := pos + Vector2(0.0, bar_h + 2.0)
			draw_rect(Rect2(repair_pos, Vector2(bar_w, 2.0)), Color(0.1, 0.14, 0.12, 0.75), true)
			draw_rect(
				Rect2(repair_pos, Vector2(bar_w * repair_t, 2.0)),
				Color(0.28, 0.98, 0.78, 0.85),
				true,
			)
			var chip := 0
			if typeof(ProvinceInsight) != TYPE_NIL:
				chip = ProvinceInsight.estimate_daily_infra_chip_damage(p)
			if chip > 0:
				var duel_total := maxf(float(chip) + rate, 0.01)
				var chip_t := clampf(float(chip) / duel_total, 0.08, 0.92)
				var chip_pos := repair_pos + Vector2(0.0, 4.0)
				draw_rect(Rect2(chip_pos, Vector2(bar_w, 2.0)), Color(0.14, 0.08, 0.1, 0.75), true)
				var winner := "even"
				if float(chip) > rate:
					winner = "sabotage"
				elif rate > float(chip):
					winner = "repair"
				var chip_col := Color(0.9, 0.75, 0.35, 0.88)
				if winner == "sabotage":
					chip_col = Color(1.0, 0.35, 0.4, 0.92)
				elif winner == "repair":
					chip_col = Color(0.28, 0.98, 0.78, 0.9)
				draw_rect(Rect2(chip_pos, Vector2(bar_w * chip_t, 2.0)), chip_col, true)
	elif focus == "supply_disruption" and typeof(SupplyManager) != TYPE_NIL:
		var depot = SupplyManager.depot_states.get(province_id)
		if depot == null:
			return
		draw_rect(Rect2(pos, Vector2(bar_w, bar_h)), Color(0.1, 0.14, 0.12, 0.8), true)
		var fill := clampf(depot.fill_ratio(), 0.0, 1.0)
		var depot_col := Color(0.35, 0.95, 0.72) if fill >= 0.5 else Color(1.0, 0.62, 0.32)
		draw_rect(Rect2(pos, Vector2(bar_w * fill, bar_h)), Color(depot_col, 0.9), true)


func _draw_pressure_glyph(
	center: Vector2,
	radius: float,
	focus: String,
	activity_pulse: bool,
	today_hit: bool = false,
) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var wave := 0.5 + 0.5 * sin(t * 3.2) if activity_pulse else 0.65
	var offset := Vector2(0.0, -radius - 8.0)
	var pos := center + offset
	var alpha := 0.92 if today_hit else 0.78
	alpha *= 0.7 + 0.3 * wave
	var half := 5.5 if today_hit else 4.5
	if focus == "supply_disruption":
		var c := Color(ring_color_supply_disrupt.r, ring_color_supply_disrupt.g, ring_color_supply_disrupt.b, alpha)
		var diamond := PackedVector2Array([
			pos + Vector2(0.0, -half),
			pos + Vector2(half, 0.0),
			pos + Vector2(0.0, half),
			pos + Vector2(-half, 0.0),
		])
		draw_colored_polygon(diamond, c)
	elif focus == "infrastructure_sabotage":
		var c := Color(ring_color_infra_sabotage.r, ring_color_infra_sabotage.g, ring_color_infra_sabotage.b, alpha)
		var sz: float = 9.0 if today_hit else 8.0
		draw_rect(Rect2(pos - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), c, true)
	if today_hit:
		var flash := Color(1.0, 0.9, 0.75, 0.35 + 0.25 * wave)
		draw_circle(pos, half + 2.5, flash, false, 1.2, true)


func _draw_network_ring(
	center: Vector2,
	strength: float,
	emphasized: bool,
	focus: String,
	pressure: float = 0.0,
	activity_pulse: bool = false,
	activity_note: String = "",
	pressure_focus: bool = false,
	today_hit: bool = false,
	province_id: int = -1,
) -> void:
	var ambient_t := Time.get_ticks_msec() * 0.001
	var pulse_hz := 3.4 if focus == "infrastructure_sabotage" else 2.8
	var ambient_wave := 0.5 + 0.5 * sin(ambient_t * pulse_hz) if pressure_focus else 0.0
	var radius := lerpf(min_ring_radius, max_ring_radius, strength)
	var alpha := lerpf(0.35, 0.95, strength)
	var base_col := ring_color_highlight if emphasized else ring_color

	var pressure_t := clampf(pressure * 0.8, 0.0, 1.0)
	var col := base_col.lerp(ring_color_high_pressure, pressure_t)

	if show_focus_color_tint:
		if focus == "supply_disruption":
			col = col.lerp(ring_color_supply_disrupt, 0.52 if pressure_focus else 0.3)
		elif focus == "infrastructure_sabotage":
			col = col.lerp(ring_color_infra_sabotage, 0.52 if pressure_focus else 0.28)
		elif province_id >= 0 and typeof(MapManager) != TYPE_NIL:
			var bd_rec: Dictionary = MapManager.get_infrastructure_repair_breakdown(province_id)
			if (
				not bool(bd_rec.get("under_infra_sabotage", false))
				and int(bd_rec.get("infrastructure", 50)) < 50
			):
				col = col.lerp(ring_color_infra_repair, 0.22 if pressure_focus else 0.12)

	col.a *= alpha
	if pressure_focus:
		var pulse_boost := 0.18 if focus == "infrastructure_sabotage" else 0.1
		if focus == "infrastructure_sabotage" and province_id >= 0 and typeof(MapManager) != TYPE_NIL:
			var bd: Dictionary = MapManager.get_infrastructure_repair_breakdown(province_id)
			if bool(bd.get("under_infra_sabotage", false)):
				var chip := 0
				if typeof(ProvinceInsight) != TYPE_NIL:
					var p: Province = MapManager.get_province(province_id) as Province
					if p != null:
						chip = ProvinceInsight.estimate_daily_infra_chip_damage(p)
				var rate := float(bd.get("total", 0.0))
				pulse_boost = 0.24 if float(chip) > rate else 0.16
		col.a = minf(1.0, col.a * (0.9 + ambient_wave * pulse_boost))

	var width := ring_width_highlight if emphasized else ring_width
	if pressure_focus:
		var width_boost := 0.65 if focus == "infrastructure_sabotage" else 0.5
		width += width_boost + ambient_wave * 0.35
	if today_hit:
		width += 0.4
		draw_arc(
			center,
			radius * 1.08,
			-_pulse_phase * 0.5,
			-_pulse_phase * 0.5 + PI * 0.65,
			20,
			Color(1.0, 0.92, 0.7, 0.55 + ambient_wave * 0.2),
			maxf(1.2, width * 0.35),
			true,
		)
	if activity_pulse:
		var boost := 0.22 + 0.18 * sin(_pulse_phase)
		if activity_note in ["intel", "disrupt", "recruit", "sabotage", "infra_pressure"]:
			boost += 0.14
		if pressure_focus:
			boost += 0.1
		radius *= 1.0 + boost * 0.35
		width += boost * 1.4
		col.a = minf(1.0, col.a * (1.0 + boost * 0.25))

	draw_arc(center, radius, 0.0, TAU, 56, col, width, true)

	if pressure_focus:
		var outer_a := 0.38 + ambient_wave * 0.22
		var outer := Color(col.r, col.g, col.b, col.a * outer_a)
		draw_arc(center, radius * (1.34 + ambient_wave * 0.06), 0.0, TAU, 40, outer, maxf(1.0, width * 0.55), true)

	if activity_pulse:
		var pulse_col := Color(col, col.a * (0.25 + 0.2 * sin(_pulse_phase)))
		draw_arc(center, radius * 1.22, 0.0, TAU, 48, pulse_col, maxf(1.0, width * 0.45), true)

	if emphasized or strength > 0.65:
		var core_radius := 3.8 if emphasized else 2.8
		if activity_note == "recruit":
			core_radius += 1.2
		if pressure_focus:
			core_radius += 0.6
		draw_circle(center, core_radius, Color(col, col.a * 0.7), true)

	if pressure_focus:
		_draw_pressure_glyph(center, radius, focus, activity_pulse or pressure_focus, today_hit)
		if province_id >= 0:
			_draw_pressure_status_bars(center, radius, province_id, focus)
	if today_hit:
		var tick_col := Color(1.0, 0.92, 0.7, 0.85 + ambient_wave * 0.1)
		draw_circle(center + Vector2(0.0, radius + 3.0), 2.6, tick_col, true)

	if double_ring_for_strong_low_pressure and strength > 0.82 and pressure < 0.35:
		draw_arc(center, radius * 0.6, 0.0, TAU, 40, Color(col, col.a * 0.5), width * 0.65, true)
