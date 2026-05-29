# scripts/map/MapRenderer.gd
class_name MapRenderer
extends Node2D

#region Exports
@export var container: Node2D
@export var info_panel: Panel
@export var info_name: Label
@export var info_owner: Label
@export var info_population: Label
@export var info_terrain: Label
@export var info_factories: Label
@export var info_dev: Label
@export var info_resources: Label
@export var info_core: Label
@export var info_special: Label
@export var info_logistics: Label
@export var info_combat: Label
@export var info_modifiers: RichTextLabel
@export var info_national: Label
@export var btn_national_spirits: Button
@export var btn_close: Button

# Dynamically created infrastructure investment UI (MVP — matches engineers button pattern)
var _btn_invest_infra: Button = null
var _label_invest_status: Label = null

# Dynamically created Special Sites section in InfoPanel
var _label_special_sites_header: Label = null
var _special_sites_container: VBoxContainer = null

#region Terrain / readability (fill characterization layered under overlays)
## Cohesion: terrain strength, `terrain_tone_close_zoom_multiplier`, and `development_close_zoom_multiplier`
## all key off `terrain_zoom_near_thresh` (map container scale). Labels/glyphs use `province_detail_min_zoom`
## for visibility — intentionally separate gates (detail vs characterization).
## RGB multiplier applied after political coloring so terrain reads at a glance without hiding ownership.
@export_range(0.0, 0.35, 0.01) var terrain_tone_strength: float = 0.145
## Terrain reads more strongly when zoomed out (province fills can otherwise look homogeneous).
@export_range(1.0, 1.4, 0.02) var terrain_tone_far_zoom_boost: float = 1.24
## Slightly tame terrain modulation when zoomed fully in so overlays dominate.
@export_range(0.82, 1.0, 0.01) var terrain_tone_near_zoom_factor: float = 0.94
@export_range(0.06, 0.45, 0.02) var terrain_zoom_far_thresh: float = 0.24
@export_range(0.7, 2.5, 0.05) var terrain_zoom_near_thresh: float = 1.22
## As scale enters tactical zoom (`terrain_zoom_near_thresh`), ease terrain modulation toward × this — smooth ramp (see `_tactical_character_blend`; ~88–100% thresh band).
@export_range(0.78, 1.0, 0.01) var terrain_tone_close_zoom_multiplier: float = 0.93
## Extra brighten toward developed provinces (normalized ~0–9 gameplay band).
@export_range(0.0, 0.12, 0.005) var development_visual_lighten: float = 0.058
## Very subtle warmth on high-development land (paired with lighten; keeps overlays legible).
@export_range(0.0, 0.09, 0.005) var development_visual_warmth: float = 0.028
## How strongly sea provinces blend toward deep water vs trace political hue.
@export_range(0.05, 0.55, 0.01) var sea_political_trace: float = 0.26
## With Supply overlay (L), pull terrain/dev characterization back toward political color before depot tint —
## keeps reds/greens/teals readable and avoids muddy stacking.
@export_range(0.34, 1.0, 0.02) var supply_overlay_base_character_blend: float = 0.78
## How strongly depot health tints province fills while L is on (political→terrain/dev applied first).
@export_range(0.18, 0.52, 0.01) var supply_depot_fill_blend: float = 0.34
## Extra outline thickness for province name labels when L is visible (helps on tinted fills).
@export_range(0, 5, 1) var province_name_outline_boost_supply_overlay: int = 2
## Regenerate province fill colors when `abs(container.scale)` crosses this width (same units as drift below).
## Typical play ~0.15–6 scale → ~20–40 repaints across the zoom range at default 0.05.
@export_range(0.028, 0.11, 0.002) var fill_zoom_bucket_size: float = 0.05
## Repaint once drift inside the current bucket exceeds `fill_zoom_bucket_size * this` (avoids stale tone while zoom lerps).
@export_range(0.22, 0.58, 0.02) var fill_zoom_intra_bucket_drift: float = 0.38
## Towards tactical zoom (`terrain_zoom_near_thresh`), ease dev lighten/warmth toward this × full strength (smooth ramp).
@export_range(0.82, 1.0, 0.01) var development_close_zoom_multiplier: float = 0.91
#endregion

#region Province names (visible at lower zoom when enabled)
@export var show_province_names: bool = false
@export var province_name_font_size: int = 11
@export var province_name_color: Color = Color(1, 1, 1, 0.85)
#endregion

#region Hover name
@export var show_hover_province_name: bool = true
@export var hover_name_follow_mouse: bool = false
#endregion

#region Feature markers
## --- Map canvas stacking (ProvinceContainers scale; typical z values, low → high) ---
## -1  ConflictOverlayLayer (fills under provinces)
##  0  `Prov_*` Polygon2D + `Z_MAP_GLYPH*` Labels (8 / 10 with L), then compare/hover/select Line2D (11–16),
##     then supply/engineer Line2D (`Z_SUPPLY` 20; `trade_transit` glow at 19). Trade corridor **rings** match
##     soft amber underlay in `SupplyMapLayer` (`OUTLINE_TRADE_TRANSIT`).
##  6  AgentNetworkLayer
## ~58 Military + trade **polylines** (`supply_route_layer_z_order`; `SupplyMapLayer` draws trade first, thinner).
## 82/100 Floating province **name** Labels (higher index while L held — `province_name_label_z_index*`).
@export var feature_icon_ring_radius: float = 28.0
@export var province_detail_min_zoom: float = 0.8
## Keep name labels above drawn supply/trade polylines (see `SupplyMapLayer`).
@export_range(30, 140, 2) var province_name_label_z_index: int = 82
@export_range(40, 160, 2) var province_name_label_z_index_supply_overlay: int = 100
## Polylines layer z (under name labels, above default province fills at 0).
@export_range(12, 90, 2) var supply_route_layer_z_order: int = 58
## Gentle dim for route lines while L is on so fills + rings win the first read.
@export_range(0.55, 1.0, 0.02) var supply_route_layer_modulate_with_overlay: float = 0.91
## Additional alpha scale for trade corridor polylines only while L is on (secondary logistics read).
@export_range(0.72, 1.0, 0.02) var trade_corridor_supply_overlay_dim: float = 0.86
#endregion

#region Debug
@export var debug_draw_province_centroids: bool = false
#endregion

#region Camera Controls
@export var pan_speed: float = 900.0
@export var edge_scroll_speed: float = 1100.0
@export var edge_margin: float = 50.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.15
@export var max_zoom: float = 8.0
@export var middle_mouse_pan_speed: float = 1.0
#endregion

#region Picking (MapPickGrid integration)
## Recommended production configuration for 250+ provinces (pure spatial, zero Area2D overhead):
##   use_spatial_picking = true
##   create_area_nodes_for_fallback = false
##
## In this mode:
## - No Area2D nodes are created at render time.
## - Hover is handled exclusively by _update_spatial_hover() polling MapPickGrid.
## - Clicks are handled by the unhandled_input spatial path.
## - All visuals (outlines, fills, etc.) continue to work on the province node via ProvinceMapVisuals.
## This is the intended long-term default for performance and simplicity.
@export var use_spatial_picking: bool = true
@export var create_area_nodes_for_fallback: bool = true
#endregion

var _is_middle_dragging := false
var _middle_drag_start := Vector2.ZERO
var _last_mouse_pos := Vector2.ZERO

var provinces: Dictionary[int, Province] = {}
var geometry: Dictionary = {}
var countries: Dictionary[String, Variant] = {}
var adjacency: AdjacencySystem

var province_nodes: Dictionary[int, Node2D] = {}
var province_centroids: Dictionary[int, Vector2] = {}
var _province_name_labels: Dictionary[int, Label] = {}
var current_hover: Node2D = null
var _hover_province: Province = null
var hover_tooltip: ProvinceHoverTooltip = null

var selected_province_id: int = -1
var _hover_outline_province_id: int = -1
var _compare_preview_province_id: int = -1
var _outline_pulse_phase: float = 0.0
var _hover_fill_province_id: int = -1

const _HOVER_FILL_TINT := Color(0.5, 0.82, 1.0, 1.0)
const _COMPARE_FILL_TINT := Color(1.0, 0.72, 0.32, 1.0)
const _CANDIDATE_FILL_TINT := ProvinceMapVisuals.FILL_COMPARE_CANDIDATE
const _CONFLICT_FILL_TINT := ProvinceMapVisuals.FILL_CONFLICT
const _AGENT_FILL_TINT := ProvinceMapVisuals.FILL_AGENT

var _supply_role_by_province: Dictionary[int, String] = {}
var _compare_candidate_ids: Array[int] = []
var _supply_legend_panel: PanelContainer = null
var _compare_hint_label: Label = null
var _legend_tracked_year: int = -1
var _legend_tracked_month: int = -1
var _legend_tracked_day: int = -1
var _map_time_pulse_bbcode: String = ""
var _map_time_pulse_kind: String = ""
var _map_time_pulse_until_msec: int = 0
var _engineer_assign_flash_by_province: Dictionary[int, Dictionary] = {}
const _ENGINEER_ASSIGN_FLASH_MS := 2400
var _engineer_deploy_pick_index: int = 0

#region Supply overlay
@export var supply_overlay_panel: SupplyMenuPanel
var supply_map_layer: SupplyMapLayer = null
var supply_mode: bool = false
var _supply_reroute_active: bool = false
var _supply_overlay_legend: RichTextLabel = null
#endregion

const META_MAP_GLYPH_PX := &"_map_glyph_px"
const META_MAP_GLYPH_CAPITAL := &"_map_glyph_capital"
const META_MAP_GLYPH_OFFS := &"_map_glyph_offs"
var _zoom_fill_characterization_scale: float = 1.0
var _fill_color_zoom_bucket: int = -2000000000
var _fill_zoom_at_last_paint: float = -10.0

#region Conflict overlay
@export var show_conflict_overlay: bool = true
var _conflict_layer: ConflictOverlayLayer = null
#endregion

#region Agent network overlay
@export var show_agent_overlay: bool = true
var _agent_layer: AgentNetworkLayer = null
#endregion

var _btn_station_engineers: Button = null


func _ready():
	if btn_close == null:
		btn_close = get_node_or_null("UI/InfoPanel/BtnClose") as Button

	if btn_close:
		if not btn_close.pressed.is_connected(_on_close_pressed):
			btn_close.pressed.connect(_on_close_pressed)
	else:
		push_warning("MapRenderer: Could not find BtnClose!")

	if container == null:
		container = get_node_or_null("ProvinceContainers") as Node2D

	var cam := get_node_or_null("MapCamera") as Camera2D
	if cam:
		cam.make_current()
		print("✅ Camera2D activated")
	else:
		push_warning("MapRenderer: MapCamera node missing!")

	_setup_hover_tooltip()
	_setup_inspector_extras()
	_connect_time_manager_signals()
	_connect_map_manager_signals()
	_connect_trade_manager_signals_for_map_layers()
	_init_legend_calendar_tracking()
	set_process(true)
	print("MapRenderer _ready() completed")


func _init_legend_calendar_tracking() -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	_legend_tracked_year = TimeManager.get_current_year()
	_legend_tracked_month = TimeManager.get_current_month()
	_legend_tracked_day = TimeManager.get_current_day()


func _connect_map_manager_signals() -> void:
	if typeof(MapManager) == TYPE_NIL:
		return
	if not MapManager.province_data_changed.is_connected(_on_map_province_data_changed):
		MapManager.province_data_changed.connect(_on_map_province_data_changed)


func _on_map_province_data_changed(province_id: int, what: String) -> void:
	if what not in ["effects", "development", "infrastructure", "owner", "controller", "all", "infrastructure_project"]:
		return
	if provinces.has(province_id):
		_refresh_single_province_fill(province_id)
		# If the info panel is open on this province, refresh the investment section live
		if info_panel and info_panel.visible and selected_province_id == province_id:
			show_info_panel(provinces[province_id])
	if _hover_fill_province_id == province_id:
		_apply_hover_fill(province_id, true)


func _connect_trade_manager_signals_for_map_layers() -> void:
	## Lightweight map refresh when TradeFlows get real routes — avoids stale polylines / rings.
	if typeof(TradeManager) == TYPE_NIL:
		return
	if not TradeManager.trade_flow_created.is_connected(_on_trade_flow_supply_map_refresh):
		TradeManager.trade_flow_created.connect(_on_trade_flow_supply_map_refresh)
	if not TradeManager.trade_flow_rerouted.is_connected(_on_trade_flow_map_rerouted):
		TradeManager.trade_flow_rerouted.connect(_on_trade_flow_map_rerouted)
	if not TradeManager.trade_flow_suspended.is_connected(_on_trade_flow_map_suspended):
		TradeManager.trade_flow_suspended.connect(_on_trade_flow_map_suspended)
	if not TradeManager.trade_flow_interdicted.is_connected(_on_trade_flow_map_interdicted):
		TradeManager.trade_flow_interdicted.connect(_on_trade_flow_map_interdicted)


func _on_trade_flow_supply_map_refresh(
	flow_id: String, from: String, to: String, _itype: String, _qty: float,
) -> void:
	_try_refresh_trade_supply_map_layers()
	_maybe_toast_player_trade_route_event("activated", flow_id, from, to, "")


func _on_trade_flow_map_rerouted(flow_id: String, _new_plan_id: String) -> void:
	_try_refresh_trade_supply_map_layers()
	var flow := TradeManager.get_trade_flow(flow_id) if typeof(TradeManager) != TYPE_NIL else null
	if flow != null:
		_maybe_toast_player_trade_route_event("rerouted", flow_id, flow.from_tag, flow.to_tag, "")


func _on_trade_flow_map_suspended(flow_id: String, reason: String) -> void:
	_try_refresh_trade_supply_map_layers()
	var flow := TradeManager.get_trade_flow(flow_id) if typeof(TradeManager) != TYPE_NIL else null
	if flow == null:
		return
	## Interdict→suspend is already announced by TradeManager for meaningful losses; avoid double toasts.
	if reason.strip_edges().begins_with("interdicted_"):
		return
	_maybe_toast_player_trade_route_event("suspended", flow_id, flow.from_tag, flow.to_tag, reason)


## Refresh polylines / rings when convoy risk or throughput changes (no extra toast — TradeManager toasts big hits).
func _on_trade_flow_map_interdicted(
	_flow_id: String, _interdictor_type: String, _loss_fraction: float, _metadata: Dictionary,
) -> void:
	_try_refresh_trade_supply_map_layers()


func _try_refresh_trade_supply_map_layers() -> void:
	if not is_inside_tree():
		return
	_refresh_supply_routes()
	if supply_mode:
		_refresh_supply_highlights()
		_update_supply_legend_text()
	if _hover_province != null and hover_tooltip != null and hover_tooltip.visible:
		_refresh_hover_tooltip(_hover_province)


## Optional feedback when trade geometry changes — skips noise for spectators.
func _maybe_toast_player_trade_route_event(
	kind: String,
	_flow_id: String,
	from: String,
	to: String,
	detail: String = "",
) -> void:
	if typeof(LeaderEventUI) == TYPE_NIL or not LeaderEventUI.has_method("show_toast"):
		return
	var p := _player_tag().strip_edges().to_upper()
	var a := from.strip_edges().to_upper()
	var b := to.strip_edges().to_upper()
	if p.is_empty() or (p != a and p != b):
		return
	var pair := "%s ↔ %s" % [a, b]
	var msg := ""
	match kind:
		"suspended":
			msg = "Trade corridor paused — %s" % pair
			if not detail.is_empty():
				msg += " · %s" % detail
		"rerouted":
			msg = "Trade corridor updated — %s" % pair
		_:
			msg = "Trade corridor on map — %s (L overlay)" % pair
	LeaderEventUI.show_toast(msg, 2.6)


func _connect_time_manager_signals() -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced_legend):
		TimeManager.game_day_advanced.connect(_on_game_day_advanced_legend)
	if not TimeManager.game_month_advanced.is_connected(_on_time_advanced_refresh_legend):
		TimeManager.game_month_advanced.connect(_on_time_advanced_refresh_legend)
	if not TimeManager.game_year_advanced.is_connected(_on_time_advanced_refresh_legend):
		TimeManager.game_year_advanced.connect(_on_time_advanced_refresh_legend)


func _on_game_day_advanced_legend(year: int, month: int, day: int) -> void:
	if _legend_tracked_day < 0:
		_legend_tracked_day = day
		_legend_tracked_month = month
		_legend_tracked_year = year
		return
	if day != _legend_tracked_day or month != _legend_tracked_month or year != _legend_tracked_year:
		_try_set_map_time_pulse(
			GameDateDisplay.build_map_time_pulse_bbcode("day", year, month, day),
			"day",
			2200,
		)
	_legend_tracked_day = day
	_legend_tracked_month = month
	_legend_tracked_year = year
	_refresh_province_fill_colors()
	_refresh_map_time_ui()


func _on_time_advanced_refresh_legend(_a: Variant = null, _b: Variant = null) -> void:
	_note_time_boundary_for_legend(_b != null)
	_refresh_map_time_ui()


func _note_time_boundary_for_legend(is_month_signal: bool) -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	var cur_y := TimeManager.get_current_year()
	var cur_m := TimeManager.get_current_month()
	var cur_d := TimeManager.get_current_day()
	if _legend_tracked_year < 0:
		_legend_tracked_year = cur_y
		_legend_tracked_month = cur_m
		_legend_tracked_day = cur_d
		return
	if cur_y > _legend_tracked_year:
		_try_set_map_time_pulse(
			GameDateDisplay.build_map_time_pulse_bbcode("year", cur_y, cur_m, cur_d),
			"year",
			5000,
		)
	elif is_month_signal and cur_m != _legend_tracked_month:
		_try_set_map_time_pulse(
			GameDateDisplay.build_map_time_pulse_bbcode("month", cur_y, cur_m, cur_d),
			"month",
			5000,
		)
	_legend_tracked_year = cur_y
	_legend_tracked_month = cur_m
	_legend_tracked_day = cur_d


func _try_set_map_time_pulse(bbcode: String, kind: String, duration_msec: int) -> void:
	if bbcode.is_empty():
		return
	var new_prio := GameDateDisplay.time_pulse_priority(kind)
	if not _map_time_pulse_bbcode.is_empty() and Time.get_ticks_msec() <= _map_time_pulse_until_msec:
		var cur_prio := GameDateDisplay.time_pulse_priority(_map_time_pulse_kind)
		if cur_prio >= new_prio:
			return
	_map_time_pulse_bbcode = bbcode
	_map_time_pulse_kind = kind
	_map_time_pulse_until_msec = Time.get_ticks_msec() + duration_msec


func _refresh_map_time_ui() -> void:
	if supply_mode:
		_update_supply_legend_text()
	if _hover_province != null and hover_tooltip != null and hover_tooltip.visible:
		_refresh_hover_tooltip(_hover_province)


func _get_active_map_time_pulse_bbcode() -> String:
	if _map_time_pulse_bbcode.is_empty():
		return ""
	if Time.get_ticks_msec() > _map_time_pulse_until_msec:
		return ""
	return _map_time_pulse_bbcode


func _expire_map_time_pulse_if_needed() -> void:
	if _map_time_pulse_bbcode.is_empty():
		return
	if Time.get_ticks_msec() <= _map_time_pulse_until_msec:
		return
	_map_time_pulse_bbcode = ""
	_map_time_pulse_kind = ""
	if supply_mode:
		_update_supply_legend_text()


func _setup_inspector_extras() -> void:
	if btn_national_spirits and not btn_national_spirits.pressed.is_connected(_on_open_national_spirits_pressed):
		btn_national_spirits.pressed.connect(_on_open_national_spirits_pressed)
	if info_modifiers == null:
		info_modifiers = get_node_or_null("UI/InfoPanel/InfoContent/RichTextModifiers") as RichTextLabel
	if info_national == null:
		info_national = get_node_or_null("UI/InfoPanel/InfoContent/LabelNationalHeader") as Label
	if info_modifiers:
		info_modifiers.bbcode_enabled = true
		info_modifiers.fit_content = false
		info_modifiers.scroll_active = true
		info_modifiers.custom_minimum_size = Vector2(360, 140)
	if btn_national_spirits == null:
		btn_national_spirits = get_node_or_null("UI/InfoPanel/BtnNationalSpirits") as Button
		if btn_national_spirits and not btn_national_spirits.pressed.is_connected(_on_open_national_spirits_pressed):
			btn_national_spirits.pressed.connect(_on_open_national_spirits_pressed)
	_ensure_station_engineers_button()


func _setup_hover_tooltip() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	hover_tooltip = ProvinceHoverTooltip.new()
	hover_tooltip.name = "ProvinceHoverTooltip"
	ui.add_child(hover_tooltip)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_toward_mouse(1.0 + zoom_speed)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_toward_mouse(1.0 - zoom_speed)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			_toggle_supply_overlay()
			get_viewport().set_input_as_handled()
			return

	# Spatial picking click handling — this path makes the system fully functional
	# even when create_area_nodes_for_fallback=false (pure MapPickGrid mode, zero Area2D nodes).
	if use_spatial_picking and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := _screen_to_world(get_viewport().get_mouse_position())
		var pid := -1
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_at_world_pos"):
			pid = MapManager.get_province_at_world_pos(world_pos, true)
		if pid >= 0 and provinces.has(pid):
			var resolved_province: Province = provinces[pid] as Province
			var resolved_node: Node2D = _province_node(pid)
			if event is InputEventMouseButton and event.shift_pressed:
				if _try_station_engineers_at_province(resolved_province):
					get_viewport().set_input_as_handled()
					return
			if supply_mode and _handle_supply_province_click(resolved_province):
				_select_province(resolved_province, resolved_node)
				get_viewport().set_input_as_handled()
				return
			show_info_panel(resolved_province)
			_select_province(resolved_province, resolved_node)
			get_viewport().set_input_as_handled()
			return

	# Middle mouse drag start
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_is_middle_dragging = true
				_middle_drag_start = get_viewport().get_mouse_position()
				_last_mouse_pos = _middle_drag_start
			else:
				_is_middle_dragging = false


func _process(delta: float) -> void:
	_expire_map_time_pulse_if_needed()

	_refresh_province_detail_visibility()

	if hover_tooltip and hover_tooltip.visible and _hover_province != null and hover_name_follow_mouse:
		_refresh_hover_tooltip(_hover_province)

	_handle_camera_input(delta)
	_outline_pulse_phase += delta * 4.5
	_update_outline_pulse()

	# Spatial picking integration (MapPickGrid via MapManager)
	if use_spatial_picking:
		_update_spatial_hover()


func _handle_camera_input(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var nav_delta := MapViewInput.motion_delta(delta)
	var move_dir := Vector2.ZERO

	# WASD / Arrow keys (simulation pause must not freeze map navigation)
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    move_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  move_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  move_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move_dir.x += 1

	# Edge scrolling (including top strip over TopInfoBar — only block modals/panels)
	if not MapViewInput.edge_pan_blocked_by_gui(get_viewport()):
		var mouse_pos := get_viewport().get_mouse_position()
		var viewport_size := get_viewport().get_visible_rect().size

		if mouse_pos.x < edge_margin:              move_dir.x -= 1
		elif mouse_pos.x > viewport_size.x - edge_margin: move_dir.x += 1
		if mouse_pos.y < edge_margin:              move_dir.y -= 1
		elif mouse_pos.y > viewport_size.y - edge_margin: move_dir.y += 1

	# Middle mouse drag (pixel-based — works while paused)
	if _is_middle_dragging:
		var current_mouse := get_viewport().get_mouse_position()
		var drag_delta := current_mouse - _last_mouse_pos
		cam.global_position -= drag_delta * middle_mouse_pan_speed / cam.zoom.x
		_last_mouse_pos = current_mouse

	if move_dir != Vector2.ZERO:
		move_dir = move_dir.normalized()
		cam.global_position += move_dir * pan_speed * nav_delta / cam.zoom.x


func _zoom_toward_mouse(zoom_change: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var mouse_screen := get_viewport().get_mouse_position()
	var old_zoom := cam.zoom

	var new_zoom := old_zoom * zoom_change
	new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
	new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)

	if new_zoom == old_zoom:
		return

	var world_before := cam.get_canvas_transform().affine_inverse() * mouse_screen
	cam.zoom = new_zoom
	var world_after := cam.get_canvas_transform().affine_inverse() * mouse_screen
	cam.global_position += world_before - world_after

## Converts screen (pixel) mouse position to world/map space using the active Camera2D.
## This is the key bridge for using MapPickGrid / MapManager picking.
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return screen_pos
	return cam.get_canvas_transform().affine_inverse() * screen_pos


func _on_close_pressed() -> void:
	hide_info_panel()


func _refresh_province_detail_visibility() -> void:
	if container == null:
		return

	var current_zoom := absf(container.scale.x)
	var show_details := current_zoom > province_detail_min_zoom
	_zoom_fill_characterization_scale = current_zoom
	# Bucket boundaries + drift are in the same space as `container.scale` length.
	var q := clampf(fill_zoom_bucket_size, 0.028, 0.14)
	var b := int(floor((current_zoom + 0.0001) / q))
	var bucket_changed := b != _fill_color_zoom_bucket
	var drift_frac := clampf(fill_zoom_intra_bucket_drift, 0.15, 0.65)
	var drift := (
		_fill_zoom_at_last_paint >= 0.0
		and absf(current_zoom - _fill_zoom_at_last_paint) >= q * drift_frac
	)
	if bucket_changed or drift:
		if bucket_changed:
			_fill_color_zoom_bucket = b
		_refresh_province_fill_colors()

	for id in _province_name_labels:
		var lbl: Variant = _province_name_labels[id]
		if lbl is Label and is_instance_valid(lbl):
			(lbl as Label).visible = show_province_names and show_details
			if show_province_names and show_details:
				var l2 := lbl as Label
				l2.z_index = _map_province_name_label_z_index()
				l2.add_theme_font_size_override("font_size", _scale_province_name_font(current_zoom, true))
				_apply_province_name_label_readability_styles(l2, current_zoom)

	for pid in province_nodes:
		var node: Variant = province_nodes[pid]
		if node is Node2D and is_instance_valid(node):
			for child in (node as Node2D).get_children():
				if child is Label and not (child as Label).has_meta(META_MAP_GLYPH_PX):
					(child as Label).visible = show_details
			_layout_zoomed_map_glyphs_for_province_node(int(pid), current_zoom, show_details)


## Smooth 0→1 ramp as map scale enters tactical band (relative to `terrain_zoom_near_thresh`).
func _tactical_character_blend(zoom_scale: float, band_start_frac: float, band_end_frac: float) -> float:
	var zn := maxf(terrain_zoom_near_thresh, 0.05)
	var span := zn * maxf(band_end_frac - band_start_frac, 0.03)
	var z0 := zn * band_start_frac
	var z1 := z0 + span
	var zz := maxf(zoom_scale, 0.02)
	var u := clampf(inverse_lerp(z0, z1, zz), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _province_name_outline_zoom_extra(zoom_metric: float) -> int:
	var zmt := zoom_metric
	if zmt <= province_detail_min_zoom:
		return 0
	return mini(2, int((zmt - province_detail_min_zoom) * 2.0))


## Shared smooth ramp + cap for province names and map glyphs so tactical zoom scales read as one system.
func _zoom_detail_scale_smooth(zoom_metric: float, cap: float = 1.8) -> float:
	var denom := maxf(province_detail_min_zoom, 0.05)
	var raw := clampf(zoom_metric / denom, 1.0, cap)
	var span := maxf(cap - 1.0, 0.001)
	var u := clampf((raw - 1.0) / span, 0.0, 1.0)
	var smooth_u := u * u * (3.0 - 2.0 * u)
	return lerpf(1.0, raw, smooth_u)


func _apply_province_name_label_readability_styles(
	label: Label,
	outline_zoom_hint: float = -1.0,
) -> void:
	var fc := province_name_color
	if supply_mode:
		fc.a = minf(0.92, fc.a + 0.035)
	label.add_theme_color_override("font_color", fc)
	var zz := outline_zoom_hint
	if zz <= 0.0001:
		zz = absf(container.scale.x) if container != null else 1.0
	var zex := _province_name_outline_zoom_extra(zz)
	var sup_boost := clampi(province_name_outline_boost_supply_overlay, 0, 5) if supply_mode else 0
	var ol_cap := 7 if supply_mode else 9
	var ol := clampi(3 + sup_boost + zex, 2, ol_cap)
	label.add_theme_constant_override("outline_size", ol)
	var oa := 0.72 if supply_mode else 0.62
	if zz >= province_detail_min_zoom * 1.05:
		oa = minf(0.82, oa + 0.038)
	if supply_mode and zz >= province_detail_min_zoom * 1.18:
		oa = maxf(0.62, oa - 0.048)
	elif (not supply_mode) and zz >= province_detail_min_zoom * 1.32:
		oa = maxf(0.64, oa - 0.035)
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.035, 0.065, oa))
	var sh_a := 0.84 if supply_mode else 0.8
	if zz >= province_detail_min_zoom * 1.35:
		sh_a = clampf(sh_a - 0.045, 0.68, 0.88)
	var sh := Color(0, 0.03, 0.08, sh_a)
	label.add_theme_color_override("font_shadow_color", sh)
	label.add_theme_constant_override("shadow_offset_x", 2 if supply_mode else 1)
	label.add_theme_constant_override("shadow_offset_y", 2 if supply_mode else 1)


func _scale_province_name_font(current_zoom: float, for_visible_names: bool) -> int:
	if not for_visible_names:
		return province_name_font_size
	var z := _zoom_detail_scale_smooth(current_zoom, 1.8)
	return clampi(int(round(float(province_name_font_size) * z)), 9, 26)


func _apply_static_map_glyph_outline(lbl: Label) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.065, 0.1, 0.62))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0.02, 0.06, 0.5))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)


func _layout_zoomed_map_glyphs_for_province_node(pid: int, zoom_metric: float, show_glyphs: bool) -> void:
	var node: Variant = province_nodes.get(pid)
	if node == null or not (node is Node2D):
		return
	var ctr: Vector2 = province_centroids.get(pid, Vector2.ZERO) as Vector2
	var nd := node as Node2D
	for child in nd.get_children():
		if child is Label and (child as Label).has_meta(META_MAP_GLYPH_PX):
			var lbl := child as Label
			var base_px := int(lbl.get_meta(META_MAP_GLYPH_PX))
			lbl.visible = show_glyphs
			if show_glyphs:
				var zsc := _zoom_detail_scale_smooth(zoom_metric, 1.8)
				var fs := clampi(int(round(float(base_px) * zsc)), maxi(8, base_px - 6), 40)
				lbl.add_theme_font_size_override("font_size", fs)
			else:
				lbl.add_theme_font_size_override("font_size", base_px)
			var gzx := 0
			if zoom_metric > province_detail_min_zoom:
				gzx = mini(2, int((zoom_metric - province_detail_min_zoom) * 2.2))
			var g_ol_max := 5 if supply_mode else 7
			var g_ol := clampi(2 + (2 if supply_mode else 0) + gzx, 1, g_ol_max)
			var goa := 0.71 if supply_mode else 0.62
			if zoom_metric >= province_detail_min_zoom * 1.08:
				goa = minf(0.88, goa + 0.065)
			if supply_mode and zoom_metric >= province_detail_min_zoom * 1.18:
				goa = maxf(0.58, goa - 0.065)
			elif (not supply_mode) and zoom_metric >= province_detail_min_zoom * 1.32:
				goa = maxf(0.58, goa - 0.04)
			var goa_cap := 0.78 if supply_mode else 0.88
			lbl.add_theme_color_override(
				"font_outline_color",
				Color(0.038, 0.06, 0.096, clampf(goa, 0.52, goa_cap)),
			)
			lbl.add_theme_constant_override("outline_size", g_ol)
			var g_glyph_a := clampf((0.94 if supply_mode else 0.90) + 0.025 * zoom_metric / maxf(province_detail_min_zoom, 0.08), 0.82, 0.97)
			lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, g_glyph_a))
			lbl.z_index = (
				ProvinceMapVisuals.Z_MAP_GLYPH_SUPPLY_OVERLAY
				if supply_mode
				else ProvinceMapVisuals.Z_MAP_GLYPH
			)
			lbl.reset_size()
			var ms := lbl.get_minimum_size()
			if lbl.has_meta(META_MAP_GLYPH_CAPITAL):
				lbl.position = ctr - ms * 0.5
			elif lbl.has_meta(META_MAP_GLYPH_OFFS):
				var ofs: Variant = lbl.get_meta(META_MAP_GLYPH_OFFS)
				if ofs is Vector2:
					lbl.position = ctr + ofs as Vector2 - ms * 0.5


func _terrain_tone_strength_for_current_zoom() -> float:
	var base := clampf(terrain_tone_strength, 0.0, 0.42)
	var z := maxf(_zoom_fill_characterization_scale, 0.07)
	var raw_t := clampf(
		inverse_lerp(terrain_zoom_near_thresh, terrain_zoom_far_thresh, z),
		0.0,
		1.0,
	)
	var t := raw_t * raw_t * (3.0 - 2.0 * raw_t)
	var mul := lerpf(terrain_tone_near_zoom_factor, terrain_tone_far_zoom_boost, t)
	var out := clampf(base * mul, 0.0, 0.48)
	var tactical_damp := _tactical_character_blend(z, 0.88, 1.0)
	var close_mul := clampf(terrain_tone_close_zoom_multiplier, 0.75, 1.0)
	out *= lerpf(1.0, close_mul, tactical_damp)
	return out


func initialize(p_provinces: Dictionary, p_geometry: Dictionary, p_adjacency: AdjacencySystem, p_countries: Dictionary = {}):
	provinces = MapScenarioData.coerce_provinces(p_provinces)
	geometry = p_geometry
	adjacency = p_adjacency
	countries = MapScenarioData.coerce_countries(p_countries)
	render_provinces()


func render_provinces():
	if container == null:
		push_error("MapRenderer: container not assigned")
		return

	_clear_selection()
	for child in container.get_children():
		child.queue_free()
	province_nodes.clear()
	province_centroids.clear()
	_province_name_labels.clear()

	print("Rendering map with %d provinces using Polygon2D..." % provinces.size())

	for id in provinces.keys():
		var province: Province = provinces[id]
		if not geometry.has(id):
			continue

		var geo = geometry[id]
		var node := _create_province_node(province, geo)
		container.add_child(node)
		province_nodes[id] = node

	_fill_color_zoom_bucket = -2000000000
	_fill_zoom_at_last_paint = -10.0
	_refresh_province_detail_visibility()
	_setup_supply_layer()
	_setup_conflict_layer()
	_setup_agent_layer()
	_refresh_supply_highlights()
	_update_compare_hint_label()
	print("✅ Map rendered with real polygons")

	# Sync MapPickGrid (via MapManager) after rendering for best picking accuracy
	if use_spatial_picking and typeof(MapManager) != TYPE_NIL and MapManager.has_method("rebuild_pick_grid"):
		MapManager.rebuild_pick_grid()


func _create_province_node(province: Province, geo: Dictionary) -> Node2D:
	var node := Node2D.new()
	node.name = "Prov_%d" % province.id

	var points: PackedVector2Array = geo.get("points", PackedVector2Array())
	if points.size() < 3:
		return node

	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = _get_province_color(province)
	poly.antialiased = true

	# Area2D is now completely optional.
	# In the recommended production pure-spatial configuration (use_spatial_picking=true AND
	# create_area_nodes_for_fallback=false), no Area2D nodes are ever created.
	if create_area_nodes_for_fallback or not use_spatial_picking:
		var area := Area2D.new()
		var collision := CollisionPolygon2D.new()
		collision.polygon = points
		area.add_child(collision)
		area.input_event.connect(_on_province_input.bind(province, node))
		area.mouse_entered.connect(_on_mouse_entered.bind(node, province))
		area.mouse_exited.connect(_on_mouse_exited.bind(node))

		node.add_child(area)

	node.add_child(poly)

	var center := _calculate_centroid(points)
	province_centroids[province.id] = center

	if debug_draw_province_centroids:
		var marker := _make_centroid_debug_marker(4.0)
		marker.position = center
		node.add_child(marker)

	if province.has_feature("capital"):
		var star := Label.new()
		star.text = "⭐"
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.z_index = ProvinceMapVisuals.Z_MAP_GLYPH
		star.add_theme_font_size_override("font_size", 22)
		star.set_meta(META_MAP_GLYPH_PX, 22)
		star.set_meta(META_MAP_GLYPH_CAPITAL, true)
		_apply_static_map_glyph_outline(star)
		star.reset_size()
		var sms := star.get_minimum_size()
		star.position = center - sms * 0.5
		node.add_child(star)

	var icon_dirs := _feature_icon_offsets_radial(_count_special_icons(province), feature_icon_ring_radius)
	var icon_i := 0
	for feature in province.special_features.keys():
		var fk := str(feature)
		if fk == "capital" or icon_i >= icon_dirs.size():
			continue
		var offs: Vector2 = icon_dirs[icon_i]
		var icon := Label.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.text = _get_feature_icon(fk)
		icon.z_index = ProvinceMapVisuals.Z_MAP_GLYPH
		icon.add_theme_font_size_override("font_size", 15)
		icon.set_meta(META_MAP_GLYPH_PX, 15)
		icon.set_meta(META_MAP_GLYPH_OFFS, offs)
		_apply_static_map_glyph_outline(icon)
		icon.reset_size()
		var ims := icon.get_minimum_size()
		icon.position = center + offs - ims * 0.5
		node.add_child(icon)
		icon_i += 1

	_create_or_update_province_name_label(province, center)

	return node


func _create_or_update_province_name_label(province: Province, center: Vector2) -> void:
	if not show_province_names or container == null:
		return

	var current_zoom := absf(container.scale.x)
	var show_details_zoom := current_zoom > province_detail_min_zoom

	var label: Label
	if _province_name_labels.has(province.id):
		label = _province_name_labels[province.id]
		if not is_instance_valid(label):
			_province_name_labels.erase(province.id)
			label = null

	if label == null:
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(label)
		_province_name_labels[province.id] = label

	label.z_index = _map_province_name_label_z_index()
	label.add_theme_font_size_override(
		"font_size",
		_scale_province_name_font(current_zoom, show_details_zoom),
	)
	_apply_province_name_label_readability_styles(label, current_zoom)
	label.reset_size()
	var ms := label.get_minimum_size()
	label.position = center - Vector2(ms.x * 0.5, 8)
	label.visible = true


func _count_special_icons(province: Province) -> int:
	var n := 0
	for feature in province.special_features.keys():
		if str(feature) != "capital":
			n += 1
	return mini(n, 4)


func _feature_icon_offsets_radial(count: int, radius: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	if count <= 0:
		return pts
	var mid_angle := PI * 0.5
	var span := clampf(PI * (0.42 + 0.11 * float(count - 1)), PI * 0.38, PI * 1.12)
	for i in count:
		var u := 0.5 if count == 1 else float(i) / float(count - 1)
		var ang := mid_angle - span * 0.5 + u * span
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	return pts


func _make_centroid_debug_marker(radius: float) -> Polygon2D:
	var poly := Polygon2D.new()
	var ring := PackedVector2Array()
	var segments := 12
	for i in segments:
		var a := TAU * float(i) / float(segments)
		ring.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = ring
	poly.color = Color(1.0, 0.08, 0.06, 0.95)
	poly.z_index = 500
	return poly


func _calculate_centroid(points: PackedVector2Array) -> Vector2:
	if points.size() < 3:
		return points[0] if points.size() > 0 else Vector2.ZERO

	var area := 0.0
	var cx := 0.0
	var cy := 0.0

	for i in range(points.size()):
		var p1 := points[i]
		var p2 := points[(i + 1) % points.size()]

		var cross := p1.x * p2.y - p2.x * p1.y
		area += cross
		cx += (p1.x + p2.x) * cross
		cy += (p1.y + p2.y) * cross

	area *= 0.5

	if absf(area) < 0.0001:
		var sum := Vector2.ZERO
		for p in points:
			sum += p
		return sum / float(points.size())

	cx /= (6.0 * area)
	cy /= (6.0 * area)
	return Vector2(cx, cy)


func _get_province_color(province: Province) -> Color:
	var base := _political_province_base_color(province)
	return _characterize_province_fill(base, province, _overlay_base_character_blend())


func _overlay_base_character_blend() -> float:
	if supply_mode:
		return clampf(supply_overlay_base_character_blend, 0.3, 1.0)
	return 1.0


func _supply_depot_mix_amount() -> float:
	return clampf(supply_depot_fill_blend, 0.12, 0.55)


func _political_province_base_color(province: Province) -> Color:
	var land_fallback := Color(0.34, 0.34, 0.41, 0.86)
	var sea_fallback := Color(0.16, 0.33, 0.47, 0.88)
	if province.owner_tag.is_empty() or not countries.has(province.owner_tag):
		return sea_fallback if province.is_sea else land_fallback
	var nation: Variant = countries[province.owner_tag]
	if nation is Country:
		var c := nation as Country
		var col := c.color
		col.a = clampf(col.a if col.a > 0.05 else 0.85, 0.72, 0.93)
		return col
	if typeof(nation) == TYPE_DICTIONARY:
		var d: Dictionary = nation
		if d.has("color"):
			var co: Variant = d["color"]
			var cc: Color
			if typeof(co) == TYPE_COLOR:
				cc = co as Color
			else:
				cc = Color(String(co))
			cc.a = clampf(cc.a if cc.a > 0.05 else 0.85, 0.72, 0.93)
			return cc
	return land_fallback


## Terrain + development hues sit on top of political color; overlays tint afterward.
## `character_blend` pulls toward raw political fills when < 1 (used under Supply / heavy tinting).
func _characterize_province_fill(base: Color, province: Province, character_blend: float = 1.0) -> Color:
	var cb := clampf(character_blend, 0.2, 1.0)
	if province.is_sea:
		var sea_col := _shade_sea_province_fill(base)
		return base.lerp(sea_col, cb)
	var mul := _terrain_palette_multipliers(province.terrain)
	var toned := Color(
		clampf(base.r * mul.x, 0.02, 1.0),
		clampf(base.g * mul.y, 0.02, 1.0),
		clampf(base.b * mul.z, 0.02, 1.0),
		base.a,
	)
	var k := _terrain_tone_strength_for_current_zoom() * cb
	var col := base.lerp(toned, k)
	var z := maxf(_zoom_fill_characterization_scale, 0.07)
	var dev_blend := _tactical_character_blend(z, 0.82, 1.04)
	var dev_mul := clampf(development_close_zoom_multiplier, 0.78, 1.0)
	var dev_near := lerpf(1.0, dev_mul, dev_blend)
	var dev_n := clampf(float(clampi(province.development_level, 0, 50)) / 9.0, 0.0, 1.0)
	dev_n = sqrt(dev_n)
	var lighten := clampf(development_visual_lighten, 0.0, 0.2) * dev_n * cb * dev_near
	col = col.lightened(lighten)
	var warmth := clampf(development_visual_warmth, 0.0, 0.12) * cb * dev_near
	if warmth > 0.0005:
		col = col.lerp(col * Color(1.028, 1.012, 0.992, 1.0), dev_n * warmth)
	return col


func _shade_sea_province_fill(base: Color) -> Color:
	var deep := Color(0.05, 0.20, 0.34, clampf(base.a * 1.02, 0.74, 0.94))
	var mix := clampf(sea_political_trace, 0.0, 0.9)
	var col := deep.lerp(base, mix)
	col.r = clampf(col.r * 1.05, 0.0, 1.0)
	col.g = clampf(col.g * 1.03, 0.0, 1.0)
	return col


func _terrain_palette_multipliers(terrain_key: String) -> Vector3:
	var key := terrain_key.strip_edges().to_lower()
	match key:
		"hills":
			return Vector3(0.93, 0.89, 0.82)
		"mountains", "mountain":
			return Vector3(0.86, 0.88, 0.93)
		"desert", "arid":
			return Vector3(1.05, 0.98, 0.87)
		"tundra", "arctic":
			return Vector3(0.93, 0.96, 1.06)
		"urban":
			return Vector3(0.94, 0.95, 1.03)
		"coastal", "coast", "harbor", "port":
			return Vector3(0.90, 0.97, 1.03)
		"forest", "woods", "jungle":
			return Vector3(0.88, 0.97, 0.90)
		"marsh", "swamp":
			return Vector3(0.88, 0.93, 0.94)
		"plains", _:
			return Vector3(0.97, 0.99, 0.93)


# ====================== INTERACTION ======================

func _on_province_input(_viewport: Node, event: InputEvent, _shape_idx: int, province: Province, node: Node2D):
	# When pure spatial picking is active (no Area2D or ignoring it), this handler should not fire for hover/selection.
	# The unhandled_input path above handles clicks.
	if use_spatial_picking:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var resolved_province := province
		var resolved_node := node

		if supply_mode and _handle_supply_province_click(resolved_province):
			_select_province(resolved_province, resolved_node)
			return
		show_info_panel(resolved_province)
		_select_province(resolved_province, resolved_node)


func _clear_selection() -> void:
	if selected_province_id >= 0:
		_set_selection_outline(selected_province_id, false)
	selected_province_id = -1
	_clear_compare_preview_outline()
	_refresh_compare_candidate_outlines()
	_update_supply_legend_text()
	_update_compare_hint_label()


## Select a province and pan the map camera to it (used by production / relocate UI).
func focus_province_by_id(province_id: int) -> bool:
	if province_id < 0 or typeof(MapManager) == TYPE_NIL:
		return false
	var province: Province = MapManager.get_province(province_id)
	if province == null:
		return false
	var node := _province_node(province_id)
	if node == null:
		return false
	_select_province(province, node)
	var cam := get_node_or_null("MapCamera") as Camera2D
	if cam != null:
		var pos: Vector2 = province_centroids.get(province_id, Vector2.ZERO)
		if pos == Vector2.ZERO:
			pos = MapManager.get_province_centroid(province_id)
		if pos != Vector2.ZERO:
			cam.global_position = pos
	show_info_panel(province)
	MapManager.province_selected.emit(province_id)
	return true


func _select_province(province: Province, node: Node2D) -> void:
	if selected_province_id >= 0 and selected_province_id != province.id:
		_set_selection_outline(selected_province_id, false)

	selected_province_id = province.id
	_set_selection_outline(province.id, true)
	var sm := _supply_manager()
	if sm != null:
		sm.set_selected_province(province.id)
	if info_panel != null and info_panel.visible:
		show_info_panel(province)
	if _hover_province != null:
		_refresh_hover_tooltip(_hover_province)
	else:
		_clear_compare_preview_outline()
	_refresh_supply_highlights()
	_refresh_compare_candidate_outlines()
	_update_supply_legend_text()
	_update_compare_hint_label()


func _clear_hover_state() -> void:
	if _hover_fill_province_id >= 0:
		_apply_hover_fill(_hover_fill_province_id, false)
		_hover_fill_province_id = -1
	if _hover_outline_province_id >= 0:
		_set_hover_outline(_hover_outline_province_id, false)
		_hover_outline_province_id = -1
	current_hover = null
	_hover_province = null
	_set_conflict_highlight(-1)
	_set_agent_highlight(-1)
	_hide_hover_tooltip()


func _on_mouse_entered(node: Node2D, province: Province):
	# When spatial picking is the primary mode, completely ignore Area2D hover events.
	# This reduces overhead from hundreds of Area2D nodes at scale.
	if use_spatial_picking:
		return
	current_hover = node
	_hover_province = province
	_apply_hover_visuals(province.id, true)
	if show_hover_province_name:
		_refresh_hover_tooltip(province)


func _on_mouse_exited(node: Node2D) -> void:
	if use_spatial_picking:
		return   # Pure spatial mode - Area2D events are ignored
	if node != null and current_hover != node:
		return
	_clear_hover_state()


func _refresh_hover_tooltip(province: Province) -> void:
	if hover_tooltip == null or province == null:
		return
	var counterpart := _battle_counterpart_for_hover(province)
	_update_compare_preview_outline(province, counterpart)
	_refresh_compare_candidate_outlines()
	var hover_role := str(_supply_role_by_province.get(province.id, ""))
	var is_candidate := _is_compare_candidate(province.id) and counterpart == null
	var contested := ProvinceInsight.is_province_contested(province)
	var has_agent := ProvinceInsight.has_active_agent_network(province)
	var p_tag := _player_tag()
	if p_tag.is_empty():
		p_tag = ProvinceInsight.country_tag_for_province(province)
	var has_radio := (
		not p_tag.is_empty()
		and ProvinceInsight.province_benefits_country(province, p_tag)
		and MapTechnologyContext.has_support_radio_bonuses(p_tag)
	)
	var has_tech := has_radio
	if not has_tech and typeof(TechnologyManager) != TYPE_NIL and not p_tag.is_empty():
		has_tech = TechnologyManager.get_active_research_count(p_tag) > 0
	if not has_tech and not p_tag.is_empty():
		var prod_note := MapTechnologyContext.build_province_production_tech_bbcode(province, p_tag)
		has_tech = not prod_note.is_empty() and "need" in prod_note.to_lower()
	if not has_tech and not p_tag.is_empty():
		var elig_glance := MapTechnologyContext.build_build_eligibility_glance_bbcode(province, p_tag)
		has_tech = not elig_glance.is_empty() and (
			"lock" in elig_glance.to_lower()
			or "📉" in elig_glance
			or "🏔" in elig_glance
			or "↗" in elig_glance
		)
	var text := ProvinceInsight.build_hover_tooltip(
		province, selected_province_id, counterpart, supply_mode, hover_role,
		is_candidate, contested, has_agent,
	)
	var mouse := get_viewport().get_mouse_position()
	var compare_active := counterpart != null
	var selected_accent := selected_province_id == province.id
	var dual := contested and has_agent
	var agent_activity := has_agent and ProvinceInsight.agent_has_daily_activity(province)
	var agent_pressure := ProvinceInsight.agent_pressure_focus_kind(province) if has_agent else ""
	if hover_role == "infra_sabotage":
		agent_pressure = "sabotage"
		if typeof(MapManager) != TYPE_NIL:
			var hover_bd: Dictionary = MapManager.get_infrastructure_repair_breakdown(province.id)
			if ProvinceInsight.daily_infra_duel_winner(province, hover_bd) == "repair":
				agent_pressure = "repair"
			elif ProvinceInsight.daily_infra_duel_winner(province, hover_bd) == "even":
				agent_pressure = "stalemate"
	elif hover_role in [
		"infra_repair", "infra_repair_engineers", "infra_duel_even",
		"engineers_stationed", "engineers_needed", "engineers_recommended", "engineers_insufficient",
	]:
		agent_pressure = (
			"repair"
			if hover_role in ["infra_repair", "infra_repair_engineers", "engineers_stationed"]
			else "stalemate"
		)
		if hover_role in ["engineers_needed", "engineers_recommended", "engineers_insufficient"]:
			agent_pressure = "sabotage"
	elif hover_role == "depot_sabotage":
		agent_pressure = "depot"
	elif hover_role == "supply_pressure":
		agent_pressure = "disrupt"
	var hover_bd_eng: Dictionary = {}
	var has_engineers := false
	var engineers_needed := false
	if typeof(MapManager) != TYPE_NIL:
		hover_bd_eng = MapManager.get_infrastructure_repair_breakdown(province.id)
		has_engineers = ProvinceInsight.has_engineers_stationed(hover_bd_eng)
		engineers_needed = ProvinceInsight.province_needs_engineer_assignment(province, hover_bd_eng)
	hover_tooltip.show_text(
		text,
		mouse,
		get_viewport().get_visible_rect().size,
		true,
		supply_mode,
		compare_active,
		selected_accent,
		is_candidate,
		contested and not compare_active,
		has_agent and not compare_active,
		has_tech and not compare_active,
		has_radio and not compare_active,
		dual and not compare_active,
		agent_activity,
		has_engineers and supply_mode and not compare_active,
		engineers_needed and supply_mode and not compare_active,
		agent_pressure,
	)
	_set_conflict_highlight(province.id if ProvinceInsight.is_province_contested(province) else -1)
	_set_agent_highlight(province.id if ProvinceInsight.has_active_agent_network(province) else -1)
	_update_compare_hint_label()


func _set_conflict_highlight(province_id: int) -> void:
	if _conflict_layer == null or not is_instance_valid(_conflict_layer):
		return
	_conflict_layer.set_highlight_province(province_id)


func _set_agent_highlight(province_id: int) -> void:
	if _agent_layer == null or not is_instance_valid(_agent_layer):
		return
	_agent_layer.set_highlight_province(province_id)


func _is_compare_candidate(province_id: int) -> bool:
	if selected_province_id < 0 or province_id == selected_province_id:
		return false
	return province_id in _compare_candidate_ids


func _battle_counterpart_for_hover(province: Province) -> Province:
	if selected_province_id < 0 or selected_province_id == province.id:
		return null
	if adjacency == null or not adjacency.are_adjacent(province.id, selected_province_id):
		return null
	if not provinces.has(selected_province_id):
		return null
	return provinces[selected_province_id] as Province


func _hide_hover_tooltip() -> void:
	_clear_compare_preview_outline()
	if hover_tooltip:
		hover_tooltip.hide_tooltip()

## Uses MapManager + MapPickGrid (when available) for fast hover detection.
## This is the primary hover mechanism when use_spatial_picking is true (hybrid with Area2D).
func _update_spatial_hover() -> void:
	if not use_spatial_picking:
		return

	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return

	var mouse_screen := get_viewport().get_mouse_position()
	var world_pos := _screen_to_world(mouse_screen)

	var pid := -1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_at_world_pos"):
		pid = MapManager.get_province_at_world_pos(world_pos, true)

	var new_hover_province: Province = null
	if pid >= 0 and provinces.has(pid):
		new_hover_province = provinces[pid]

	# Only update state if the hovered province actually changed
	if new_hover_province != _hover_province:
		if _hover_province != null:
			_clear_hover_state()
		if new_hover_province != null:
			_hover_province = new_hover_province
			current_hover = province_nodes.get(pid) as Node2D
			_apply_hover_visuals(pid, true)
			if show_hover_province_name:
				_refresh_hover_tooltip(new_hover_province)


# ====================== INFO PANEL ======================

func show_info_panel(province: Province):
	if info_panel == null:
		return

	var name_text := province.name
	if selected_province_id >= 0 and selected_province_id != province.id:
		var other := _battle_counterpart_for_hover(province)
		if other != null:
			name_text += "  ⚔ vs " + other.name
	info_name.text = name_text
	var ctrl_note := ""
	if ProvinceInsight.is_province_contested(province):
		ctrl_note = "  ⚑ held by %s" % province.controller_tag
	elif province.controller_tag != province.owner_tag and not province.controller_tag.is_empty():
		ctrl_note = " (controlled by %s)" % province.controller_tag
	info_owner.text = (
		"Owner: %s%s" % [province.owner_tag if province.owner_tag != "" else "None", ctrl_note]
	)
	info_population.text = "Population: %s" % str(province.population)
	info_terrain.text = "Terrain: " + province.terrain.capitalize()
	info_factories.text = "Factories: %d" % province.factories
	info_dev.text = "Development: %d  ·  Infrastructure: %d" % [
		province.development_level, province.infrastructure,
	]
	if info_logistics != null:
		info_logistics.text = ProvinceInsight.build_at_a_glance_logistics(province)
	if info_combat != null:
		info_combat.text = ProvinceInsight.build_combat_summary_for_inspector(
			province, selected_province_id,
		)
	if info_modifiers != null:
		info_modifiers.text = ProvinceInsight.build_inspector_text(province, selected_province_id)
	if info_national != null:
		var conflict_note := ""
		if ProvinceInsight.is_province_contested(province):
			conflict_note = " Contested provinces show ⚑ in tooltip and diagonal stripes on the map."
		info_national.text = (
			"Inspector: Province | National | Effective columns. "
			+ "National section lists spirits, timed effects, agents, then combined rollup."
			+ conflict_note
		)

	var res_text := "Resources: "
	if province.resources.size() > 0:
		for key in province.resources:
			res_text += "%s:%s " % [key, str(province.resources[key])]
	else:
		res_text += "None"
	info_resources.text = res_text.strip_edges()

	# Quick visibility for special site economic impact
	var ssm = _get_special_site_manager()
	if ssm != null and typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_national_special_site_trade_capacity_bonus"):
		var nat_bonus := TradeManager.get_national_special_site_trade_capacity_bonus(province.owner_tag)
		if nat_bonus > 0 and info_resources != null:
			info_resources.text += "  |  Trade Cap +%d (Special Sites)" % int(nat_bonus)

	info_core.text = "Core For: " + (", ".join(province.core_for) if province.core_for.size() > 0 else "None")

	var special_list := []
	for feature in province.special_features.keys():
		var fk := str(feature)
		var level = province.special_features[feature]
		special_list.append("%s %s (Lv.%d)" % [_get_feature_icon(fk), fk.capitalize(), level])
	info_special.text = "Special: " + (", ".join(special_list) if special_list.size() > 0 else "None")

	info_panel.visible = true
	_update_station_engineers_button(province)
	_update_infrastructure_investment_ui(province)
	_update_special_sites_ui(province)


func hide_info_panel():
	if info_panel:
		info_panel.visible = false


func _ensure_station_engineers_button() -> void:
	if info_panel == null:
		return
	if _btn_station_engineers != null and is_instance_valid(_btn_station_engineers):
		return
	_btn_station_engineers = Button.new()
	_btn_station_engineers.name = "BtnStationEngineers"
	_btn_station_engineers.text = "Station engineers"
	_btn_station_engineers.tooltip_text = (
		"Move an engineer-capable division here (same as a move-to-province order).\n"
		+ "Each click cycles which division moves; Shift+click picks the best match on the map.\n"
		+ "Supply overlay (L) shows URGENT / recommended / weak rings."
	)
	_btn_station_engineers.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_btn_station_engineers.offset_left = 210.0
	_btn_station_engineers.offset_top = 8.0
	_btn_station_engineers.offset_right = 340.0
	_btn_station_engineers.offset_bottom = 32.0
	_btn_station_engineers.visible = false
	if not _btn_station_engineers.pressed.is_connected(_on_station_engineers_pressed):
		_btn_station_engineers.pressed.connect(_on_station_engineers_pressed)
	info_panel.add_child(_btn_station_engineers)


func _update_station_engineers_button(province: Province) -> void:
	_ensure_station_engineers_button()
	if _btn_station_engineers == null:
		return
	if province == null:
		_btn_station_engineers.visible = false
		return
	var bd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL:
		bd = MapManager.get_infrastructure_repair_breakdown(province.id)
	var level := ProvinceInsight.get_engineer_guidance_level(province, bd)
	var can_station := ProvinceInsight.province_accepts_player_engineers(province, bd)
	var p_tag := _player_tag()
	if p_tag.is_empty():
		p_tag = ProvinceInsight.country_tag_for_province(province)
	var next_name := _next_engineer_deploy_label(p_tag)
	var roster_n := 0
	if typeof(SupplyManager) != TYPE_NIL:
		roster_n = SupplyManager.get_engineer_capable_formations(p_tag).size()
	_btn_station_engineers.visible = can_station and roster_n > 0 and level != "present"
	match level:
		"critical":
			_btn_station_engineers.text = "Deploy %s (URGENT)" % next_name if not next_name.is_empty() else "Deploy engineers (URGENT)"
			_btn_station_engineers.tooltip_text = (
				"Sabotage is winning the daily duel here.\n"
				+ "Moves an engineer-capable division here (Shift+click on map).\n"
				+ "Amber pulsing ring on Supply overlay (L)."
			)
		"recommended":
			_btn_station_engineers.text = "Deploy %s" % next_name if not next_name.is_empty() else "Deploy engineers"
			_btn_station_engineers.tooltip_text = (
				"Repair is weak — engineers recommended before sabotage escalates.\n"
				+ "Shift+click province · softer amber ring on L overlay."
			)
		"present_insufficient":
			_btn_station_engineers.text = "Deploy %s (+more)" % next_name if not next_name.is_empty() else "Deploy more engineers"
			_btn_station_engineers.tooltip_text = (
				"Engineers are present but repair still loses (or barely holds).\n"
				+ "Cycle another division here or clear the ◎ agent network."
			)
		_:
			if ProvinceInsight.has_engineers_stationed(bd) and roster_n > 1:
				_btn_station_engineers.text = "Reassign %s" % next_name if not next_name.is_empty() else "Reassign engineers"
				_btn_station_engineers.visible = can_station
				_btn_station_engineers.tooltip_text = (
					"Engineers are holding repair — cycle a different division to this province."
				)
			else:
				_btn_station_engineers.text = "Deploy engineers"
				_btn_station_engineers.visible = false
	if can_station and typeof(SupplyManager) != TYPE_NIL:
		var tip_lines: PackedStringArray = [
			"Move an engineer-capable division here (updates repair at origin and destination).",
			"Shift+click on the map picks the best division; this button cycles divisions.",
		]
		for entry in SupplyManager.get_engineer_capable_formations(p_tag):
			var label := str(entry.get("display_name", "?"))
			var pid := int(entry.get("stationed_province_id", -1))
			var loc := "unassigned"
			if pid >= 0 and provinces.has(pid):
				var sp: Province = provinces[pid] as Province
				if sp != null:
					loc = sp.name
			tip_lines.append("· %s — %s" % [label, loc])
		_btn_station_engineers.tooltip_text = "\n".join(tip_lines)


# ====================== INFRASTRUCTURE INVESTMENT UI (Phase A) ======================

func _ensure_infrastructure_investment_ui() -> void:
	if info_panel == null:
		return
	if _btn_invest_infra != null and is_instance_valid(_btn_invest_infra):
		return

	# Status label (shows "In Progress — 68% (ETA 9 days)" or current effective values)
	_label_invest_status = Label.new()
	_label_invest_status.name = "LabelInvestStatus"
	_label_invest_status.text = ""
	_label_invest_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_invest_status.custom_minimum_size = Vector2(280, 0)
	_label_invest_status.add_theme_font_size_override("font_size", 11)
	info_panel.add_child(_label_invest_status)

	# Invest button
	_btn_invest_infra = Button.new()
	_btn_invest_infra.name = "BtnInvestInfrastructure"
	_btn_invest_infra.text = "Invest in Infrastructure"
	_btn_invest_infra.tooltip_text = "Start a provincial development project. Raises infrastructure over time, improving supply, combat width, and unlocking advanced factory types. Cost scales with current level."
	_btn_invest_infra.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_btn_invest_infra.offset_left = 8.0
	_btn_invest_infra.offset_top = 178.0   # Positioned below existing content (tune as needed)
	_btn_invest_infra.offset_right = 195.0
	_btn_invest_infra.offset_bottom = 200.0
	_btn_invest_infra.visible = false
	if not _btn_invest_infra.pressed.is_connected(_on_invest_infrastructure_pressed):
		_btn_invest_infra.pressed.connect(_on_invest_infrastructure_pressed)
	info_panel.add_child(_btn_invest_infra)


func _update_infrastructure_investment_ui(province: Province) -> void:
	_ensure_infrastructure_investment_ui()
	if _btn_invest_infra == null or _label_invest_status == null:
		return
	if province == null:
		_btn_invest_infra.visible = false
		_label_invest_status.visible = false
		return

	var mgr = _get_infra_manager()
	if mgr == null:
		_btn_invest_infra.visible = false
		_label_invest_status.visible = false
		return

	var player_tag := _player_tag()
	var show_ui: bool = (
		mgr.should_show_investment_button(province.id, player_tag)
		if mgr.has_method("should_show_investment_button")
		else true
	)
	if not show_ui:
		_btn_invest_infra.visible = false
		_label_invest_status.visible = false
		return

	_label_invest_status.visible = true
	_btn_invest_infra.visible = true

	var status: Dictionary = (
		mgr.get_project_status(province.id) if mgr.has_method("get_project_status") else {}
	)
	var has_project: bool = bool(status.get("active", false))

	if has_project:
		var pct := int(round(float(status.get("progress", 0.0))))
		var eta := int(status.get("eta_days", 0))
		var sabotaged := bool(status.get("is_sabotaged", false))
		var sab_note := " ⚠ Sabotage slowing progress" if sabotaged else ""
		_label_invest_status.text = "Infra Project: %d%% → Lv.%d (ETA %d days)%s" % [
			pct, int(status.get("target_level", province.infrastructure + 1)), eta, sab_note
		]
		_label_invest_status.modulate = Color(1.0, 0.85, 0.4) if sabotaged else Color(0.6, 0.95, 0.85)
		_btn_invest_infra.text = "Project Active"
		_btn_invest_infra.disabled = true
	else:
		_label_invest_status.text = "Infra: %d  ·  Dev: %d  (Invest to raise)" % [
			province.infrastructure, province.development_level
		]
		_label_invest_status.modulate = Color(0.85, 0.9, 0.95)
		_btn_invest_infra.text = "Invest in Infrastructure"
		_btn_invest_infra.disabled = false


func _on_invest_infrastructure_pressed() -> void:
	if selected_province_id < 0:
		return
	var mgr = _get_infra_manager()
	if mgr == null:
		print("InfrastructureDevelopmentManager not available yet.")
		return

	var player := _player_tag()
	var result: Dictionary = {}
	if mgr.has_method("try_start_infrastructure_investment"):
		result = mgr.try_start_infrastructure_investment(selected_province_id, player)
	else:
		# Fallback to older API — target current + 1
		var target := 0
		if provinces.has(selected_province_id):
			target = provinces[selected_province_id].infrastructure + 1
		var proj: RefCounted = (
			mgr.start_infrastructure_project(selected_province_id, target if target > 0 else 5, player)
			if mgr.has_method("start_infrastructure_project")
			else null
		)
		result = {"success": proj != null, "reason": "started via legacy call" if proj else "manager missing method"}

	if result.get("success", false):
		var eta := int(result.get("eta_days", 18))
		print("Infrastructure project started on province %d — ETA ~%d days" % [selected_province_id, eta])
		# Refresh the panel so the button immediately shows "Project Active"
		if provinces.has(selected_province_id):
			show_info_panel(provinces[selected_province_id])
	else:
		print("Cannot start infrastructure investment: %s" % result.get("reason", "unknown"))

	# TODO (Phase B): Show a proper toast / confirmation popup instead of print


# ====================== SPECIAL SITES UI (InfoPanel) ======================

func _update_special_sites_ui(province: Province) -> void:
	_ensure_special_sites_ui()
	if _label_special_sites_header == null or _special_sites_container == null:
		return
	if province == null:
		_label_special_sites_header.visible = false
		_special_sites_container.visible = false
		return

	var sites := province.special_sites
	if sites.is_empty():
		_label_special_sites_header.visible = true
		_label_special_sites_header.text = "Special Sites (None)"
		_special_sites_container.visible = true

		# Clear previous
		for child in _special_sites_container.get_children():
			child.queue_free()

		# === Real Site Construction Picker ===
		var ssm = _get_special_site_manager()
		if ssm != null and ssm.has_method("get_constructible_sites_for_province"):
			var available := ssm.get_constructible_sites_for_province(province) as Array
			if available.size() > 0:
				var header := Label.new()
				header.text = "Available Constructions:"
				header.add_theme_font_size_override("font_size", 11)
				_special_sites_container.add_child(header)

				for site_id_var in available:
					var site_id := str(site_id_var)
					var def: Dictionary = (
						ssm.get_site_definition(site_id) if ssm.has_method("get_site_definition") else {}
					)
					var name := str(def.get("name", site_id)) if def else site_id

					var cons := def.get("construction", {}) as Dictionary if def else {}
					var req_infra := int(cons.get("required_infra_level", 1))
					var days := int(cons.get("base_days", 30))
					var pp := int(cons.get("political_power_cost", 50))

					var row := HBoxContainer.new()
					_special_sites_container.add_child(row)

					var info_label := Label.new()
					info_label.text = "%s (Infra %d, %d days, %d PP)" % [name, req_infra, days, pp]
					info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					row.add_child(info_label)

					# Effects summary from JSON
					var effects := def.get("effects", {}) as Dictionary if def else {}
					var eff_parts := []
					for k in effects:
						var val: Variant = effects[k]
						if val is float or val is int:
							if val > 0:
								eff_parts.append("+%d %s" % [int(val), str(k).replace("_", " ").capitalize()])
					if eff_parts.size() > 0:
						var eff_label := Label.new()
						eff_label.text = "  " + " · ".join(eff_parts)
						eff_label.add_theme_font_size_override("font_size", 9)
						eff_label.modulate = Color(0.6, 0.9, 0.7)
						row.add_child(eff_label)

					var btn := Button.new()
					btn.text = "Build"
					btn.custom_minimum_size = Vector2(70, 24)
					btn.pressed.connect(_on_construct_special_site_pressed.bind(province.id, site_id))
					row.add_child(btn)
			else:
				var note := Label.new()
				note.text = "No special sites available at current infrastructure level."
				note.add_theme_font_size_override("font_size", 10)
				_special_sites_container.add_child(note)
		else:
			# Fallback
			var build_btn := Button.new()
			build_btn.text = "Construct New Special Site (Port)"
			build_btn.pressed.connect(_on_start_special_site_construction_pressed.bind(province.id))
			_special_sites_container.add_child(build_btn)
		return

	_label_special_sites_header.visible = true
	_special_sites_container.visible = true

	# Clear previous
	for child in _special_sites_container.get_children():
		child.queue_free()

	_label_special_sites_header.text = "Special Sites (%d)" % sites.size()

	# Show national trade capacity bonus from special sites (makes the economic impact visible)
	var ssm = _get_special_site_manager()
	if ssm != null and typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_national_special_site_trade_capacity_bonus"):
		var bonus := TradeManager.get_national_special_site_trade_capacity_bonus(province.owner_tag)
		if bonus > 0:
			var bonus_label := Label.new()
			bonus_label.text = "National Trade Capacity +%d from special sites" % int(bonus)
			bonus_label.add_theme_font_size_override("font_size", 10)
			bonus_label.modulate = Color(0.6, 0.9, 0.7)
			_special_sites_container.add_child(bonus_label)

	for site in sites:
		if site == null:
			continue

		var row := HBoxContainer.new()
		_special_sites_container.add_child(row)

		var name_label := Label.new()
		var state_icon := "✓" if site.is_completed() else "🚧" if site.is_under_construction() else "⚠"
		var dmg := " [Dmg %d]" % site.damage_level if site.is_damaged() else ""
		name_label.text = "%s %s (T%d)%s" % [state_icon, site.id, site.tier, dmg]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		if site.is_damaged():
			var repair_btn := Button.new()
			repair_btn.text = "Repair"
			repair_btn.custom_minimum_size = Vector2(60, 24)
			repair_btn.pressed.connect(_on_repair_special_site_pressed.bind(province.id, site))
			row.add_child(repair_btn)

		if site.can_be_upgraded():
			var target_def := {}
			if ssm != null and ssm.has_method("get_site_definition"):
				target_def = ssm.get_site_definition(site.get_upgrade_target_id())

			var cons := target_def.get("construction", {}) as Dictionary if target_def else {}
			var up_days := int(cons.get("base_days", 60))
			var up_pp := int(cons.get("political_power_cost", 100))

			var upgrade_btn := Button.new()
			upgrade_btn.text = "Upgrade → T%d (%d days, %d PP)" % [site.tier + 1, up_days, up_pp]
			upgrade_btn.custom_minimum_size = Vector2(160, 24)
			upgrade_btn.pressed.connect(_on_upgrade_special_site_pressed.bind(province.id, site))
			row.add_child(upgrade_btn)

		# Show key effects
		var effects_label := Label.new()
		var eff_text := ""
		if site.supply_bonus > 0:
			eff_text += "+%d Supply " % int(site.supply_bonus)
		if site.trade_capacity > 0:
			eff_text += "+%d Trade" % int(site.trade_capacity)
		effects_label.text = eff_text.strip_edges()
		effects_label.add_theme_font_size_override("font_size", 10)
		row.add_child(effects_label)


func _ensure_special_sites_ui() -> void:
	if info_panel == null:
		return
	if _label_special_sites_header != null and is_instance_valid(_label_special_sites_header):
		return

	_label_special_sites_header = Label.new()
	_label_special_sites_header.name = "LabelSpecialSitesHeader"
	_label_special_sites_header.text = "Special Sites"
	_label_special_sites_header.add_theme_font_size_override("font_size", 12)
	info_panel.add_child(_label_special_sites_header)

	_special_sites_container = VBoxContainer.new()
	_special_sites_container.name = "SpecialSitesContainer"
	_special_sites_container.add_theme_constant_override("separation", 4)
	info_panel.add_child(_special_sites_container)


func _on_repair_special_site_pressed(province_id: int, site: SpecialSite) -> void:
	if site == null or not site.is_damaged():
		return

	var repair_amount := 1

	# Sophisticated repair: engineers present give bonus repair
	var mgr = _get_infra_manager()
	if mgr != null and mgr.has_method("get_engineer_brigades_in_province"):
		var engineers: float = float(mgr.get_engineer_brigades_in_province(province_id))
		if engineers > 0.5:
			repair_amount += 1   # engineers speed up special site repair too

	site.repair_damage(repair_amount)

	# Notify systems
	if typeof(MapManager) != TYPE_NIL:
		MapManager.notify_province_changed(province_id, "special_site")

	# Refresh the panel
	if provinces.has(province_id):
		show_info_panel(provinces[province_id])

	print("Repaired special site %s in province %d (amount %d)" % [site.id, province_id, repair_amount])


func _on_upgrade_special_site_pressed(province_id: int, site: SpecialSite) -> void:
	if site == null or not site.can_be_upgraded():
		return

	var mgr = _get_infra_manager()
	if mgr == null or not mgr.has_method("start_special_site_upgrade_project"):
		# Fallback: instant upgrade for debug
		site.complete_upgrade()
		if typeof(MapManager) != TYPE_NIL:
			MapManager.notify_province_changed(province_id, "special_site")
		if provinces.has(province_id):
			show_info_panel(provinces[province_id])
		print("Instant upgraded special site (fallback)")
		return

	var player := _player_tag()
	var proj: RefCounted = mgr.start_special_site_upgrade_project(province_id, site, player)
	if proj:
		print("Started upgrade project for special site %s in province %d" % [site.id, province_id])
		if provinces.has(province_id):
			show_info_panel(provinces[province_id])
	else:
		print("Could not start upgrade project")


func _on_start_special_site_construction_pressed(province_id: int) -> void:
	var mgr = _get_infra_manager()
	if mgr == null or not mgr.has_method("debug_start_special_site_project"):
		return

	var player := _player_tag()
	mgr.debug_start_special_site_project(province_id, "port_tier_1", player)   # MVP: starts real project for basic port

	if provinces.has(province_id):
		show_info_panel(provinces[province_id])


func _on_construct_special_site_pressed(province_id: int, site_id: String) -> void:
	var mgr = _get_infra_manager()
	if mgr == null or not mgr.has_method("start_special_site_project"):
		print("Cannot start special site project - manager missing method")
		return

	var player := _player_tag()
	var proj: RefCounted = mgr.start_special_site_project(province_id, site_id, player)
	if proj:
		print("Started real special site construction project: %s in province %d" % [site_id, province_id])
	else:
		print("Failed to start special site project for %s" % site_id)

	if provinces.has(province_id):
		show_info_panel(provinces[province_id])


func _get_special_site_manager() -> Object:
	return get_node_or_null("/root/SpecialSiteManager")


func _get_infra_manager() -> Object:
	if typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		return InfrastructureDevelopmentManager
	# Fallback for early boot / tests
	return get_node_or_null("/root/InfrastructureDevelopmentManager")


func _next_engineer_deploy_label(country_tag: String) -> String:
	if typeof(SupplyManager) == TYPE_NIL:
		return "engineers"
	var formations := SupplyManager.get_engineer_capable_formations(country_tag)
	if formations.is_empty():
		return ""
	_engineer_deploy_pick_index = _engineer_deploy_pick_index % formations.size()
	var entry: Dictionary = formations[_engineer_deploy_pick_index]
	var name := str(entry.get("display_name", ""))
	if name.length() > 22:
		name = name.substr(0, 20) + "…"
	return name if not name.is_empty() else "engineers"


func _formation_id_for_deploy(country_tag: String, province: Province, use_cycle: bool) -> String:
	if typeof(SupplyManager) == TYPE_NIL:
		return ""
	if use_cycle:
		var formations := SupplyManager.get_engineer_capable_formations(country_tag)
		if formations.is_empty():
			return ""
		_engineer_deploy_pick_index = _engineer_deploy_pick_index % formations.size()
		var fid := str(formations[_engineer_deploy_pick_index].get("formation_id", ""))
		_engineer_deploy_pick_index += 1
		return fid
	return SupplyManager.pick_formation_for_engineer_deployment(country_tag, province.id)


func _try_station_engineers_at_province(
	province: Province,
	_brigade_equiv: float = 1.0,
	use_cycle: bool = false,
) -> bool:
	if province == null or typeof(SupplyManager) == TYPE_NIL:
		return false
	var tag := _player_tag()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(province)
	var bd_before: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL:
		bd_before = MapManager.get_infrastructure_repair_breakdown(province.id)
	var level_before := ProvinceInsight.get_engineer_guidance_level(province, bd_before)
	var fid := _formation_id_for_deploy(tag, province, use_cycle)
	var result: Dictionary = FormationMovement.move_engineer_formation_to_province(
		fid, province.id, tag,
	)
	if not bool(result.get("ok", false)):
		var err := str(result.get("error", "Could not station engineers"))
		var msg := ProvinceInsight.build_engineer_assignment_toast_message(
			province, false, level_before, "", 0.0, err, result,
		)
		_trigger_engineer_assignment_flash(province.id, false)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(msg, 3.5, true)
		return false
	var bd_after: Dictionary = bd_before
	if typeof(MapManager) != TYPE_NIL:
		bd_after = MapManager.get_infrastructure_repair_breakdown(province.id)
	var level_after := str(result.get("guidance_after", ""))
	if level_after.is_empty():
		level_after = ProvinceInsight.get_engineer_guidance_level(province, bd_after)
	var eng := float(result.get("engineer_brigades", 0.0))
	_trigger_engineer_assignment_flash(province.id, true, "arrived")
	_refresh_supply_highlights()
	_refresh_single_province_fill(province.id)
	var moved_from_pid := int(result.get("moved_from_province_id", -1))
	if moved_from_pid >= 0 and moved_from_pid != province.id:
		_trigger_engineer_assignment_flash(moved_from_pid, true, "departed")
		_refresh_single_province_fill(moved_from_pid)
		if _hover_province != null and _hover_province.id == moved_from_pid:
			_refresh_hover_tooltip(_hover_province)
		if selected_province_id == moved_from_pid:
			var origin_p: Province = MapManager.get_province(moved_from_pid) if typeof(MapManager) != TYPE_NIL else null
			if origin_p != null:
				show_info_panel(origin_p)
	if _hover_province != null and _hover_province.id == province.id:
		_refresh_hover_tooltip(province)
	if selected_province_id == province.id:
		show_info_panel(province)
		_select_province(province, _province_node(province.id))
	var msg_ok := ProvinceInsight.build_engineer_assignment_toast_message(
		province, true, level_before, level_after, eng, "", result,
	)
	if not supply_mode:
		msg_ok += " · Press L for Supply overlay rings"
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(msg_ok, 4.0)
	return true


func _trigger_engineer_assignment_flash(
	province_id: int,
	success: bool,
	kind: String = "arrived",
) -> void:
	_engineer_assign_flash_by_province[province_id] = {
		"until_msec": Time.get_ticks_msec() + _ENGINEER_ASSIGN_FLASH_MS,
		"success": success,
		"kind": kind,
	}
	var node := _province_node(province_id)
	if node == null:
		return
	var role := "engineers_stationed" if success else "engineers_needed"
	if kind == "departed":
		role = "engineers_recommended"
	var style: Dictionary = ProvinceMapVisuals.get_supply_outline_style(role)
	ProvinceMapVisuals.ensure_polished_outline(
		node,
		_province_polygon(node),
		ProvinceMapVisuals.NODE_SUPPLY,
		style["color"],
		style["width"],
		style["glow"],
		style["glow_extra"],
		style["z_index"],
	)


func _apply_engineer_assignment_flash_pulses() -> void:
	var now := Time.get_ticks_msec()
	var expired: Array[int] = []
	for pid in _engineer_assign_flash_by_province.keys():
		var flash: Dictionary = _engineer_assign_flash_by_province[pid]
		if now > int(flash.get("until_msec", 0)):
			expired.append(pid)
			continue
		var node := _province_node(int(pid))
		if node == null:
			continue
		var success := bool(flash.get("success", true))
		var kind := str(flash.get("kind", "arrived"))
		var col := ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED
		var glow := ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED_GLOW
		var pulse_amt := 0.62
		if not success:
			col = ProvinceMapVisuals.OUTLINE_INFRA_SABOTAGE
			glow = ProvinceMapVisuals.OUTLINE_INFRA_SABOTAGE_GLOW
			pulse_amt = 0.44
		elif kind == "departed":
			pulse_amt = 0.30
		var boost := 0.48 + 0.28 * sin(_outline_pulse_phase * 5.25 + float(pid) * 0.4)
		ProvinceMapVisuals.apply_pulse_to_polished(
			node,
			ProvinceMapVisuals.NODE_SUPPLY,
			col,
			3.05 + boost,
			glow,
			5.1 + boost * 1.75,
			_outline_pulse_phase + float(pid) * 0.2,
			pulse_amt,
			1.38,
		)
	for pid in expired:
		_engineer_assign_flash_by_province.erase(pid)
	if not expired.is_empty():
		_refresh_supply_highlights()


func _on_station_engineers_pressed() -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		return
	var province: Province = provinces[selected_province_id] as Province
	_try_station_engineers_at_province(province, 1.0, true)


#region Overlay layer infrastructure (preparing for M3 gameplay overlays)
## Clean API for adding future layers (AgentNetworkLayer, ConflictOverlayLayer, TechBuildLayer, etc.)
## All overlay layers live under ProvinceContainers so they move/zoom with the map.
## Data for overlays is best accessed via MapManager (centroids, bounds, adjacency, effects, etc.).
func add_overlay_layer(layer_name: String, layer_node: Node2D, z_index: int = 0) -> void:
	if container == null or layer_node == null:
		return
	layer_node.name = layer_name
	layer_node.z_index = z_index   # Allows basic ordering (e.g. supply routes behind conflict lines)
	var existing := container.get_node_or_null(layer_name)
	if existing:
		existing.queue_free()
	container.add_child(layer_node)

func remove_overlay_layer(layer_name: String) -> void:
	if container == null:
		return
	var existing := container.get_node_or_null(layer_name)
	if existing:
		existing.queue_free()

func get_active_overlay_layers() -> Array[String]:
	## Returns names of active custom overlay layers added via add_overlay_layer.
	## Excludes core map elements. Useful for UI/debug.
	var names: Array[String] = []
	if container == null:
		return names
	var excluded: Array[String] = ["SupplyMapLayer", "ProvinceContainers"]
	for child in container.get_children():
		if child is Node2D:
			var n := child.name
			if n not in excluded and not n.begins_with("Prov_") and not n.ends_with("Outline") and not n.ends_with("Glow"):
				names.append(n)
	return names

func get_overlay_layer(name: String) -> Node2D:
	if container == null:
		return null
	return container.get_node_or_null(name) as Node2D

func _setup_conflict_layer() -> void:
	if not show_conflict_overlay or container == null:
		remove_overlay_layer("ConflictOverlay")
		_conflict_layer = null
		return
	if _conflict_layer == null or not is_instance_valid(_conflict_layer):
		_conflict_layer = ConflictOverlayLayer.new()
	var centroids := province_centroids
	var provs := provinces
	if typeof(MapManager) != TYPE_NIL:
		if MapManager.has_method("get_all_centroids"):
			centroids = MapManager.get_all_centroids()
		if MapManager.has_method("get_all_provinces"):
			provs = MapManager.get_all_provinces()
	_conflict_layer.setup_with_map(container, centroids, provs, geometry)
	add_overlay_layer("ConflictOverlay", _conflict_layer, -1)


## Convenience alias for scenes/scripts that call this after map init.
func setup_demo_conflict_overlay() -> void:
	_setup_conflict_layer()


func _setup_agent_layer() -> void:
	if not show_agent_overlay or container == null:
		remove_overlay_layer("AgentNetworkLayer")
		_agent_layer = null
		return
	if _agent_layer == null or not is_instance_valid(_agent_layer):
		_agent_layer = AgentNetworkLayer.new()
	var sm := _supply_manager()
	if sm != null and sm.get("player_tag"):
		_agent_layer.target_country = str(sm.player_tag).strip_edges().to_upper()
	else:
		_agent_layer.target_country = ""
	_agent_layer.setup()
	add_overlay_layer("AgentNetworkLayer", _agent_layer, 6)


func setup_demo_agent_overlay() -> void:
	_setup_agent_layer()

# Recommended data access for any overlay layer:
#   MapManager.get_all_centroids()
#   MapManager.get_world_bounds()
#   MapManager.get_adjacency_system()
#   MapManager.get_province_effects(pid, tag)
#   MapManager.get_provinces_in_rect(...) for culling
#endregion


#region Supply map layer
## Polylines: trade corridors share hue with province `trade_transit` rings; drawn first beneath military routes — see `SupplyMapLayer`.
func _map_province_name_label_z_index() -> int:
	return province_name_label_z_index_supply_overlay if supply_mode else province_name_label_z_index


## Slows outline pulses while L is on so hover / supply / engineer rings do not compete visually.
func _map_overlay_pulse_speed_scale() -> float:
	return 0.82 if supply_mode else 1.0


func _sync_map_label_glyph_stack(zoom_metric: float = -1.0) -> void:
	var zz := zoom_metric
	if zz <= 0.0001 and container != null:
		zz = absf(container.scale.x)
	if zz <= 0.0001:
		zz = 1.0
	var show_glyphs := zz > province_detail_min_zoom
	for id in _province_name_labels:
		var lbl: Variant = _province_name_labels[id]
		if lbl is Label and is_instance_valid(lbl):
			var l2 := lbl as Label
			l2.z_index = _map_province_name_label_z_index()
			if show_province_names and show_glyphs:
				_apply_province_name_label_readability_styles(l2, zz)
	for pid in province_nodes:
		_layout_zoomed_map_glyphs_for_province_node(int(pid), zz, show_glyphs)


func _sync_supply_route_canvas_stack() -> void:
	if supply_map_layer == null or not is_instance_valid(supply_map_layer):
		return
	supply_map_layer.z_index = clampi(supply_route_layer_z_order, -40, 120)
	var lm := clampf(supply_route_layer_modulate_with_overlay, 0.5, 1.0)
	if supply_mode and supply_map_layer.visible:
		supply_map_layer.self_modulate = Color(lm, lm, lm, 1.0)
		supply_map_layer.trade_corridor_supply_dim = clampf(trade_corridor_supply_overlay_dim, 0.72, 1.0)
	else:
		supply_map_layer.self_modulate = Color.WHITE
		supply_map_layer.trade_corridor_supply_dim = 1.0
	_sync_map_label_glyph_stack()
	supply_map_layer.queue_redraw()


func _setup_supply_layer() -> void:
	if container == null:
		return
	if supply_map_layer == null or not is_instance_valid(supply_map_layer):
		supply_map_layer = SupplyMapLayer.new()
		supply_map_layer.name = "SupplyMapLayer"
		container.add_child(supply_map_layer)
	var sm := _supply_manager()
	if sm != null and sm.rules != null:
		supply_map_layer.setup(province_centroids, sm.rules)
	_ensure_supply_overlay_panel()
	_refresh_supply_routes()
	_sync_supply_route_canvas_stack()


func _ensure_supply_overlay_panel() -> void:
	if supply_overlay_panel != null:
		supply_overlay_panel.set_callbacks(
			_on_supply_commit, _on_supply_clear_waypoints, _on_supply_close_overlay,
		)
		return
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	supply_overlay_panel = SupplyMenuPanel.new()
	supply_overlay_panel.name = "SupplyMenuPanel"
	supply_overlay_panel.custom_minimum_size = Vector2(420, 300)
	supply_overlay_panel.position = Vector2(16, 120)
	ui.add_child(supply_overlay_panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_top = 12
	vbox.offset_right = -12
	vbox.offset_bottom = -12
	supply_overlay_panel.add_child(vbox)
	supply_overlay_panel.title_label = Label.new()
	supply_overlay_panel.title_label.text = "Supply command"
	vbox.add_child(supply_overlay_panel.title_label)
	supply_overlay_panel.mode_option = OptionButton.new()
	vbox.add_child(supply_overlay_panel.mode_option)
	supply_overlay_panel.setup_mode_selector()
	supply_overlay_panel.depot_label = Label.new()
	supply_overlay_panel.depot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(supply_overlay_panel.depot_label)
	supply_overlay_panel.attrition_label = Label.new()
	supply_overlay_panel.attrition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(supply_overlay_panel.attrition_label)
	supply_overlay_panel.body_label = RichTextLabel.new()
	supply_overlay_panel.body_label.fit_content = true
	supply_overlay_panel.body_label.custom_minimum_size = Vector2(380, 90)
	vbox.add_child(supply_overlay_panel.body_label)
	var row := HBoxContainer.new()
	supply_overlay_panel.btn_commit = Button.new()
	supply_overlay_panel.btn_commit.text = "Commit route"
	row.add_child(supply_overlay_panel.btn_commit)
	supply_overlay_panel.btn_clear = Button.new()
	supply_overlay_panel.btn_clear.text = "Clear waypoints"
	row.add_child(supply_overlay_panel.btn_clear)
	supply_overlay_panel.btn_close = Button.new()
	supply_overlay_panel.btn_close.text = "Close"
	row.add_child(supply_overlay_panel.btn_close)
	vbox.add_child(row)
	supply_overlay_panel.set_callbacks(
		_on_supply_commit, _on_supply_clear_waypoints, _on_supply_close_overlay,
	)
	supply_overlay_panel.set_mode_callback(_on_supply_mode_changed)


func _player_tag() -> String:
	var sm := _supply_manager()
	if sm != null and sm.get("player_tag"):
		return str(sm.player_tag).strip_edges().to_upper()
	return ""


func _supply_manager() -> Node:
	return get_tree().root.get_node_or_null("SupplyManager")


func build_supply_network(city_layer: Dictionary, player_tag: String = "USA") -> void:
	var sm := _supply_manager()
	if sm == null:
		return
	sm.build_network(provinces, countries, city_layer, adjacency, player_tag)
	if sm.has_method("seed_demo_enemy_forces"):
		sm.seed_demo_enemy_forces()
	if sm.has_method("seed_demo_engineer_presence"):
		sm.seed_demo_engineer_presence(player_tag)
	_setup_supply_layer()


func _toggle_supply_overlay() -> void:
	var sm := _supply_manager()
	if sm == null:
		return
	sm.toggle_overlay()
	supply_mode = sm.overlay_visible
	if supply_map_layer:
		supply_map_layer.visible = supply_mode
	if supply_mode:
		_refresh_supply_routes()
	else:
		_end_supply_reroute()
	_refresh_province_fill_colors()
	_refresh_province_detail_visibility()
	_refresh_supply_highlights()
	_update_supply_overlay_legend()
	_refresh_compare_candidate_outlines()
	if _hover_province != null:
		_refresh_hover_tooltip(_hover_province)
	if supply_overlay_panel:
		if not supply_mode:
			supply_overlay_panel.hide_panel()
	_sync_supply_route_canvas_stack()


func _refresh_supply_routes() -> void:
	var sm := _supply_manager()
	if supply_map_layer == null or sm == null:
		return
	supply_map_layer.set_routes(sm.get_all_routes())
	supply_map_layer.visible = supply_mode
	_sync_supply_route_canvas_stack()
	_refresh_supply_highlights()


func _handle_supply_province_click(province: Province) -> bool:
	var sm := _supply_manager()
	if sm == null:
		return false
	sm.set_selected_province(province.id)
	if not _supply_reroute_active:
		var source: int = sm.get_capital_hub_id()
		if source < 0:
			source = province.id
		sm.begin_player_reroute(source, province.id)
		_supply_reroute_active = true
		_show_supply_preview()
		return true
	sm.add_reroute_waypoint(province.id)
	_show_supply_preview()
	_refresh_supply_highlights()
	return true


func _show_supply_preview() -> void:
	var sm := _supply_manager()
	if sm == null:
		return
	var plan: SupplyRoutePlan = sm.preview_player_route()
	_update_supply_menu(plan, true)
	_refresh_supply_routes()


func _update_supply_menu(plan: SupplyRoutePlan, reroute_mode: bool) -> void:
	var sm := _supply_manager()
	if sm == null or supply_overlay_panel == null:
		return
	var depot: ProvinceDepotState = sm.get_depot_state(sm.get_selected_province_id())
	if depot == null:
		depot = sm.get_depot_state(plan.target_province_id)
	var attrition: Dictionary = sm.get_attrition_cargo_summary()
	var extra := ""
	for line in sm.get_depot_menu_lines(5):
		extra += line + "\n"
	var pid: int = SupplyManager.get_selected_province_id()
	var province: Province = provinces.get(pid) as Province if provinces.has(pid) else null
	supply_overlay_panel.show_supply_state(
		plan, depot, attrition, reroute_mode, province, sm.player_tag, extra.strip_edges(),
	)


func _on_supply_mode_changed(mode: String) -> void:
	var sm := _supply_manager()
	if sm:
		sm.set_routing_mode(mode)
	_show_supply_preview()


func _on_supply_commit() -> void:
	var sm := _supply_manager()
	if sm == null:
		return
	var plan: SupplyRoutePlan = sm.commit_player_route()
	_update_supply_menu(plan, false)
	_refresh_supply_routes()


func _on_supply_clear_waypoints() -> void:
	var sm := _supply_manager()
	if sm:
		sm.clear_reroute_waypoints()
	_show_supply_preview()


func _on_supply_close_overlay() -> void:
	_toggle_supply_overlay()


func _end_supply_reroute() -> void:
	_supply_reroute_active = false
	var sm := _supply_manager()
	if sm:
		sm.clear_reroute_waypoints()


func _refresh_province_fill_colors() -> void:
	if container != null:
		_zoom_fill_characterization_scale = absf(container.scale.x)
	for pid in province_nodes.keys():
		var node: Variant = province_nodes[pid]
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		if not provinces.has(pid):
			continue
		var province: Province = provinces[pid] as Province
		var poly: Polygon2D = _get_province_polygon(node as Node2D)
		if poly == null:
			continue
		var col := _get_province_color(province)
		if supply_mode:
			var fill := ProvinceInsight.depot_fill_ratio(int(pid))
			if fill >= 0.0:
				col = col.lerp(_supply_depot_tint_color(fill), _supply_depot_mix_amount())
		col = _apply_agent_pressure_base_tint(col, province)
		poly.color = col
	_refresh_supply_highlights()
	_fill_zoom_at_last_paint = _zoom_fill_characterization_scale


func _province_polygon(node: Node2D) -> PackedVector2Array:
	var poly := _get_province_polygon(node)
	if poly == null:
		return PackedVector2Array()
	return poly.polygon


func _province_node(province_id: int) -> Node2D:
	var node: Variant = province_nodes.get(province_id)
	return node as Node2D if node is Node2D else null

## Robust helper to find the Polygon2D child regardless of whether an Area2D was also added.
## Essential for pure spatial mode (no Area2D) and hybrid mode.
func _get_province_polygon(node: Node2D) -> Polygon2D:
	if node == null:
		return null
	for child in node.get_children():
		if child is Polygon2D:
			return child as Polygon2D
	return null


func _apply_hover_visuals(province_id: int, active: bool) -> void:
	if active:
		if _hover_outline_province_id >= 0 and _hover_outline_province_id != province_id:
			_apply_hover_visuals(_hover_outline_province_id, false)
		_hover_outline_province_id = province_id
		_hover_fill_province_id = province_id
	_set_hover_outline(province_id, active)
	if active:
		_apply_hover_fill(province_id, true)
		if selected_province_id >= 0:
			_refresh_compare_candidate_outlines()
		if supply_mode:
			_update_supply_legend_text()
	elif _hover_fill_province_id == province_id:
		_apply_hover_fill(province_id, false)
		_hover_fill_province_id = -1
	if not active and supply_mode:
		_update_supply_legend_text()
	if not active and selected_province_id >= 0:
		_refresh_compare_candidate_outlines()


func _hover_outline_colors(province_id: int) -> Dictionary:
	var colors := {
		"color": ProvinceMapVisuals.OUTLINE_HOVER,
		"glow": ProvinceMapVisuals.OUTLINE_HOVER_GLOW,
	}
	if not provinces.has(province_id):
		return colors
	var hp: Province = provinces[province_id] as Province
	var contested := ProvinceInsight.is_province_contested(hp)
	var agent := ProvinceInsight.has_active_agent_network(hp)
	if contested and agent:
		var dual_lerp := 0.22 if supply_mode else 0.28
		var dual_base := ProvinceMapVisuals.OUTLINE_DUAL
		match ProvinceInsight.agent_pressure_focus_kind(hp):
			"disrupt":
				dual_base = ProvinceMapVisuals.OUTLINE_DUAL_DISRUPT
				dual_lerp = 0.16 if ProvinceInsight.agent_applies_daily_pressure(hp) else dual_lerp
			"sabotage":
				dual_base = ProvinceMapVisuals.OUTLINE_DUAL_SABOTAGE
				dual_lerp = 0.16 if ProvinceInsight.agent_applies_daily_pressure(hp) else dual_lerp
		if ProvinceInsight.agent_has_today_pressure_tick(hp):
			dual_lerp = maxf(0.12, dual_lerp - 0.06)
		colors["color"] = dual_base.lerp(ProvinceMapVisuals.OUTLINE_HOVER, dual_lerp)
		colors["glow"] = ProvinceMapVisuals.OUTLINE_DUAL_GLOW
	elif agent:
		var agent_lerp := 0.28 if ProvinceInsight.agent_has_daily_activity(hp) else 0.38
		var pressure_kind := ProvinceInsight.agent_pressure_focus_kind(hp)
		var agent_outline := ProvinceMapVisuals.OUTLINE_AGENT
		if pressure_kind == "disrupt":
			agent_outline = ProvinceMapVisuals.OUTLINE_AGENT_DISRUPT
			agent_lerp = 0.24 if ProvinceInsight.agent_applies_daily_pressure(hp) else agent_lerp
		elif pressure_kind == "sabotage":
			agent_outline = ProvinceMapVisuals.OUTLINE_AGENT_SABOTAGE
			agent_lerp = 0.24 if ProvinceInsight.agent_applies_daily_pressure(hp) else agent_lerp
		if ProvinceInsight.agent_has_today_pressure_tick(hp):
			agent_lerp = maxf(0.18, agent_lerp - 0.08)
		colors["color"] = agent_outline.lerp(ProvinceMapVisuals.OUTLINE_HOVER, agent_lerp)
		colors["glow"] = ProvinceMapVisuals.OUTLINE_AGENT_GLOW
	elif contested:
		colors["color"] = ProvinceMapVisuals.OUTLINE_CONFLICT.lerp(ProvinceMapVisuals.OUTLINE_HOVER, 0.42)
		colors["glow"] = ProvinceMapVisuals.OUTLINE_CONFLICT_GLOW
	if provinces.has(province_id):
		var hp2: Province = provinces[province_id] as Province
		if _province_has_support_radio_benefit(hp2):
			colors["color"] = colors["color"].lerp(ProvinceMapVisuals.OUTLINE_SUPPORT_RADIO, 0.18)
			colors["glow"] = colors["glow"].lerp(ProvinceMapVisuals.OUTLINE_SUPPORT_RADIO_GLOW, 0.24)
		if ProvinceInsight.agent_applies_daily_pressure(hp2):
			var role := str(_supply_role_by_province.get(province_id, ""))
			if role == "infra_sabotage":
				colors["color"] = colors["color"].lerp(ProvinceMapVisuals.OUTLINE_INFRA_SABOTAGE, 0.2)
				colors["glow"] = colors["glow"].lerp(ProvinceMapVisuals.OUTLINE_INFRA_SABOTAGE_GLOW, 0.22)
			elif role == "supply_pressure":
				colors["color"] = colors["color"].lerp(ProvinceMapVisuals.OUTLINE_SUPPLY_PRESSURE, 0.16)
			elif role in [
				"infra_repair", "infra_repair_engineers", "engineers_stationed", "engineers_needed",
				"engineers_recommended", "engineers_insufficient",
			]:
				var eng_col := ProvinceMapVisuals.OUTLINE_INFRA_REPAIR
				var eng_glow := ProvinceMapVisuals.OUTLINE_INFRA_REPAIR_GLOW
				var lerp_amt := 0.18
				match role:
					"infra_repair_engineers":
						eng_col = ProvinceMapVisuals.OUTLINE_INFRA_REPAIR_ENGINEERS
						eng_glow = ProvinceMapVisuals.OUTLINE_INFRA_REPAIR_ENGINEERS_GLOW
					"engineers_stationed":
						eng_col = ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED
						eng_glow = ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED_GLOW
					"engineers_needed":
						eng_col = ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED
						eng_glow = ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED_GLOW
						lerp_amt = 0.26
					"engineers_recommended":
						eng_col = ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED.lerp(
							ProvinceMapVisuals.OUTLINE_INFRA_REPAIR, 0.35,
						)
						eng_glow = ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED_GLOW.lerp(
							ProvinceMapVisuals.OUTLINE_INFRA_REPAIR_GLOW, 0.3,
						)
					"engineers_insufficient":
						eng_col = ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED.lerp(
							ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED, 0.5,
						)
						eng_glow = ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED_GLOW.lerp(
							ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED_GLOW, 0.4,
						)
						lerp_amt = 0.22
				colors["color"] = colors["color"].lerp(eng_col, lerp_amt)
				colors["glow"] = colors["glow"].lerp(eng_glow, lerp_amt * 0.9)
			elif role == "depot_sabotage":
				colors["color"] = colors["color"].lerp(ProvinceMapVisuals.OUTLINE_DEPOT_SABOTAGE, 0.14)
	return colors


func _set_hover_outline(province_id: int, visible: bool) -> void:
	var node := _province_node(province_id)
	if node == null:
		return
	if visible:
		var width := 2.8 if province_id == selected_province_id else 2.5
		if provinces.has(province_id):
			var hp: Province = provinces[province_id] as Province
			if ProvinceInsight.agent_has_today_pressure_tick(hp):
				width += 0.3
			if (
				ProvinceInsight.is_province_contested(hp)
				and ProvinceInsight.has_active_agent_network(hp)
			):
				width += 0.35
				if province_id == selected_province_id:
					width += 0.2
				if ProvinceInsight.agent_applies_daily_pressure(hp):
					width += 0.15
		var oc: Dictionary = _hover_outline_colors(province_id)
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_HOVER,
			oc["color"],
			width,
			oc["glow"],
			3.5,
			ProvinceMapVisuals.Z_HOVER,
		)
	else:
		ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_HOVER)
		if _hover_outline_province_id == province_id:
			_hover_outline_province_id = -1


func _set_selection_outline(province_id: int, visible: bool) -> void:
	var node := _province_node(province_id)
	if node == null:
		return
	if visible:
		var sel_col := ProvinceMapVisuals.OUTLINE_SELECT
		var sel_glow := ProvinceMapVisuals.OUTLINE_SELECT_GLOW
		if provinces.has(province_id):
			var sp: Province = provinces[province_id] as Province
			var contested := ProvinceInsight.is_province_contested(sp)
			var agent := ProvinceInsight.has_active_agent_network(sp)
			if contested and agent:
				var dual_sel := ProvinceMapVisuals.OUTLINE_DUAL
				match ProvinceInsight.agent_pressure_focus_kind(sp):
					"disrupt":
						dual_sel = ProvinceMapVisuals.OUTLINE_DUAL_DISRUPT
					"sabotage":
						dual_sel = ProvinceMapVisuals.OUTLINE_DUAL_SABOTAGE
				sel_col = dual_sel.lerp(ProvinceMapVisuals.OUTLINE_SELECT, 0.35)
				sel_glow = ProvinceMapVisuals.OUTLINE_DUAL_GLOW
			elif contested:
				sel_col = ProvinceMapVisuals.OUTLINE_SELECT_CONTESTED
				sel_glow = ProvinceMapVisuals.OUTLINE_SELECT_CONTESTED_GLOW
			elif agent:
				var agent_sel := ProvinceMapVisuals.OUTLINE_AGENT
				match ProvinceInsight.agent_pressure_focus_kind(sp):
					"disrupt":
						agent_sel = ProvinceMapVisuals.OUTLINE_AGENT_DISRUPT
					"sabotage":
						agent_sel = ProvinceMapVisuals.OUTLINE_AGENT_SABOTAGE
				sel_col = agent_sel.lerp(ProvinceMapVisuals.OUTLINE_SELECT, 0.5)
				sel_glow = ProvinceMapVisuals.OUTLINE_AGENT_GLOW
			if _province_has_support_radio_benefit(sp):
				sel_col = sel_col.lerp(ProvinceMapVisuals.OUTLINE_SUPPORT_RADIO, 0.12)
				sel_glow = sel_glow.lerp(ProvinceMapVisuals.OUTLINE_SUPPORT_RADIO_GLOW, 0.18)
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_SELECT,
			sel_col,
			3.5,
			sel_glow,
			4.0,
			ProvinceMapVisuals.Z_SELECT,
		)
	else:
		ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_SELECT)


func _clear_compare_preview_outline() -> void:
	if _compare_preview_province_id >= 0:
		_set_compare_preview_outline(_compare_preview_province_id, false)
	_compare_preview_province_id = -1


func _update_compare_preview_outline(hover_province: Province, counterpart: Province) -> void:
	_clear_compare_preview_outline()
	if hover_province == null or counterpart == null:
		return
	if counterpart.id == hover_province.id:
		return
	_compare_preview_province_id = counterpart.id
	_set_compare_preview_outline(counterpart.id, true)


func _refresh_single_province_fill(province_id: int) -> void:
	if container != null:
		_zoom_fill_characterization_scale = absf(container.scale.x)
	if not provinces.has(province_id):
		return
	var node := _province_node(province_id)
	if node == null:
		return
	var poly := _get_province_polygon(node)
	if poly == null:
		return
	var province: Province = provinces[province_id] as Province
	var col := _get_province_color(province)
	if supply_mode:
		var fill := ProvinceInsight.depot_fill_ratio(province_id)
		if fill >= 0.0:
			col = col.lerp(_supply_depot_tint_color(fill), _supply_depot_mix_amount())
	col = _apply_agent_pressure_base_tint(col, province)
	col = _apply_recovering_fill_tint(col, province_id)
	col = _apply_support_radio_fill_tint(col, province)
	poly.color = col


func _province_has_support_radio_benefit(province: Province) -> bool:
	if province == null:
		return false
	var tag := _player_tag()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(province)
	return (
		not tag.is_empty()
		and MapTechnologyContext.has_support_radio_bonuses(tag)
		and ProvinceInsight.province_benefits_country(province, tag)
	)


func _apply_support_radio_fill_tint(col: Color, province: Province) -> Color:
	if not _province_has_support_radio_benefit(province):
		return col
	var strength := 0.06 if supply_mode else 0.09
	if province != null and ProvinceInsight.agent_applies_daily_pressure(province):
		strength = minf(strength, 0.05)
	return col.lerp(ProvinceMapVisuals.FILL_SUPPORT_RADIO, strength)


func _apply_recovering_fill_tint(col: Color, province_id: int) -> Color:
	if not supply_mode:
		return col
	var role := str(_supply_role_by_province.get(province_id, ""))
	if role in [
		"infra_repair", "infra_repair_engineers", "engineers_stationed", "engineers_needed",
		"engineers_recommended", "engineers_insufficient",
	]:
		var strength := 0.44
		match role:
			"infra_repair_engineers":
				strength = 0.48
			"engineers_stationed":
				strength = 0.22
			"engineers_needed":
				strength = 0.32
				return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.14).lerp(
					ProvinceMapVisuals.FILL_INFRA_RECOVERING, strength,
				)
			"engineers_recommended":
				strength = 0.26
				return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.08).lerp(
					ProvinceMapVisuals.FILL_INFRA_RECOVERING, strength,
				)
			"engineers_insufficient":
				strength = 0.30
				return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.11).lerp(
					ProvinceMapVisuals.FILL_INFRA_RECOVERING, strength,
				)
		return col.lerp(ProvinceMapVisuals.FILL_INFRA_RECOVERING, strength)
	if role == "infra_sabotage":
		return col.lerp(ProvinceMapVisuals.FILL_INFRA_SABOTAGE_ACTIVE, 0.34)
	if role == "infra_duel_even":
		return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.09).lerp(
			ProvinceMapVisuals.FILL_INFRA_RECOVERING, 0.18,
		)
	if str(_supply_role_by_province.get(province_id, "")) == "supply_pressure":
		return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.14)
	if str(_supply_role_by_province.get(province_id, "")) == "depot_sabotage":
		return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.12)
	return col


func _apply_agent_pressure_base_tint(col: Color, province: Province) -> Color:
	var strength := ProvinceInsight.get_agent_pressure_fill_strength(province, supply_mode)
	if strength <= 0.0:
		return col
	var tint := ProvinceInsight.get_agent_pressure_fill_tint(province)
	if tint.a <= 0.0:
		return col
	col = col.lerp(tint, strength)
	if (
		ProvinceInsight.agent_pressure_focus_kind(province) == "sabotage"
		and province.infrastructure <= 12
	):
		col = col.lerp(ProvinceMapVisuals.FILL_AGENT_SABOTAGE, 0.04)
	return col


func _apply_hover_fill(province_id: int, active: bool) -> void:
	if not active:
		_refresh_single_province_fill(province_id)
		return
	var node := _province_node(province_id)
	if node == null or not provinces.has(province_id):
		return
	var poly := _get_province_polygon(node)
	if poly == null:
		return
	var province: Province = provinces[province_id] as Province
	var col := _get_province_color(province)
	if supply_mode:
		var fill := ProvinceInsight.depot_fill_ratio(province_id)
		if fill >= 0.0:
			col = col.lerp(_supply_depot_tint_color(fill), _supply_depot_mix_amount())
	col = _apply_agent_pressure_base_tint(col, province)
	col = _apply_recovering_fill_tint(col, province_id)
	col = _apply_support_radio_fill_tint(col, province)
	var boost := 0.2
	if _compare_preview_province_id >= 0 and province_id == _hover_outline_province_id:
		col = col.lerp(_COMPARE_FILL_TINT, 0.14)
		boost = 0.16
	elif _is_compare_candidate(province_id):
		col = col.lerp(_CANDIDATE_FILL_TINT, 0.12)
		boost = 0.18
	var contested := ProvinceInsight.is_province_contested(province)
	var agent := ProvinceInsight.has_active_agent_network(province)
	if contested and agent:
		var dual_strength := 0.14
		if supply_mode:
			dual_strength = 0.2
		if province_id == selected_province_id:
			dual_strength += 0.04
		col = col.lerp(ProvinceMapVisuals.FILL_DUAL, dual_strength)
		if ProvinceInsight.agent_applies_daily_pressure(province):
			match ProvinceInsight.agent_pressure_focus_kind(province):
				"disrupt":
					col = col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT, 0.07)
				"sabotage":
					col = col.lerp(ProvinceMapVisuals.FILL_AGENT_SABOTAGE, 0.07)
	elif agent:
		var agent_tint := _AGENT_FILL_TINT
		match ProvinceInsight.agent_pressure_focus_kind(province):
			"disrupt":
				agent_tint = ProvinceMapVisuals.FILL_AGENT_DISRUPT
			"sabotage":
				agent_tint = ProvinceMapVisuals.FILL_AGENT_SABOTAGE
		var fill_strength := 0.08
		if ProvinceInsight.agent_applies_daily_pressure(province):
			fill_strength = 0.2 if supply_mode else 0.15
		if ProvinceInsight.agent_has_today_pressure_tick(province):
			fill_strength += 0.06
		elif ProvinceInsight.agent_has_daily_activity(province):
			fill_strength += 0.03
		col = col.lerp(agent_tint, fill_strength)
	elif contested:
		col = col.lerp(_CONFLICT_FILL_TINT, 0.09)
	poly.color = col.lerp(_HOVER_FILL_TINT, boost)


func _update_outline_pulse() -> void:
	var hover_on_selection := (
		_hover_outline_province_id >= 0
		and _hover_outline_province_id == selected_province_id
	)
	if _hover_outline_province_id >= 0:
		var node := _province_node(_hover_outline_province_id)
		if node != null:
			var hover_w := 3.0 if hover_on_selection else 2.5
			var pulse_amp := 0.4 if hover_on_selection else 0.35
			var pulse_speed := (5.5 if hover_on_selection else 4.5) * _map_overlay_pulse_speed_scale()
			if supply_mode:
				pulse_amp = minf(pulse_amp, 0.36 if hover_on_selection else 0.32)
			if provinces.has(_hover_outline_province_id):
				var hp: Province = provinces[_hover_outline_province_id] as Province
				var dual_hover := (
					ProvinceInsight.is_province_contested(hp)
					and ProvinceInsight.has_active_agent_network(hp)
				)
				if ProvinceInsight.agent_has_today_pressure_tick(hp):
					hover_w += 0.35
					pulse_amp += 0.12 if not supply_mode else 0.085
					pulse_speed += 0.60 if not supply_mode else 0.42
				elif ProvinceInsight.agent_applies_daily_pressure(hp):
					hover_w += 0.2
					pulse_amp += 0.06 if not supply_mode else 0.045
				if dual_hover:
					hover_w += 0.25
					pulse_amp += 0.08 if not supply_mode else 0.055
					if supply_mode:
						pulse_amp += 0.035
			var hoc: Dictionary = _hover_outline_colors(_hover_outline_province_id)
			ProvinceMapVisuals.apply_pulse_to_polished(
				node,
				ProvinceMapVisuals.NODE_HOVER,
				hoc["color"],
				hover_w,
				hoc["glow"],
				6.0,
				_outline_pulse_phase,
				pulse_amp,
				pulse_speed,
			)
	if selected_province_id >= 0 and not hover_on_selection:
		var sel_node := _province_node(selected_province_id)
		if sel_node != null:
			var sel_col := ProvinceMapVisuals.OUTLINE_SELECT
			var sel_glow := ProvinceMapVisuals.OUTLINE_SELECT_GLOW
			if provinces.has(selected_province_id):
				var sp: Province = provinces[selected_province_id] as Province
				var contested := ProvinceInsight.is_province_contested(sp)
				var agent := ProvinceInsight.has_active_agent_network(sp)
				if contested and agent:
					var dual_sel := ProvinceMapVisuals.OUTLINE_DUAL
					match ProvinceInsight.agent_pressure_focus_kind(sp):
						"disrupt":
							dual_sel = ProvinceMapVisuals.OUTLINE_DUAL_DISRUPT
						"sabotage":
							dual_sel = ProvinceMapVisuals.OUTLINE_DUAL_SABOTAGE
					sel_col = dual_sel.lerp(ProvinceMapVisuals.OUTLINE_SELECT, 0.35)
					sel_glow = ProvinceMapVisuals.OUTLINE_DUAL_GLOW
				elif contested:
					sel_col = ProvinceMapVisuals.OUTLINE_SELECT_CONTESTED
					sel_glow = ProvinceMapVisuals.OUTLINE_SELECT_CONTESTED_GLOW
				elif agent:
					var agent_sel := ProvinceMapVisuals.OUTLINE_AGENT
					match ProvinceInsight.agent_pressure_focus_kind(sp):
						"disrupt":
							agent_sel = ProvinceMapVisuals.OUTLINE_AGENT_DISRUPT
						"sabotage":
							agent_sel = ProvinceMapVisuals.OUTLINE_AGENT_SABOTAGE
					sel_col = agent_sel.lerp(ProvinceMapVisuals.OUTLINE_SELECT, 0.5)
					sel_glow = ProvinceMapVisuals.OUTLINE_AGENT_GLOW
			ProvinceMapVisuals.apply_pulse_to_polished(
				sel_node,
				ProvinceMapVisuals.NODE_SELECT,
				sel_col,
				3.5,
				sel_glow,
				7.5,
				_outline_pulse_phase + 0.8,
				0.3,
				3.2 * _map_overlay_pulse_speed_scale(),
			)
	if _compare_preview_province_id >= 0:
		var cmp_node := _province_node(_compare_preview_province_id)
		if cmp_node != null:
			ProvinceMapVisuals.apply_pulse_to_polished(
				cmp_node,
				ProvinceMapVisuals.NODE_COMPARE,
				ProvinceMapVisuals.OUTLINE_COMPARE,
				3.0,
				ProvinceMapVisuals.OUTLINE_COMPARE_GLOW,
				5.8,
				_outline_pulse_phase + 1.6,
				0.45,
				5.0 * _map_overlay_pulse_speed_scale(),
			)
	for pid in _compare_candidate_ids:
		if pid == _compare_preview_province_id:
			continue
		var cand_node := _province_node(pid)
		if cand_node == null:
			continue
		var emph := pid == _hover_outline_province_id
		var c_col := (
			ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE_EMPH
			if emph
			else ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE
		)
		ProvinceMapVisuals.apply_pulse_to_polished(
			cand_node,
			ProvinceMapVisuals.NODE_COMPARE_CANDIDATE,
			c_col,
			2.6 if emph else 1.6,
			ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE_GLOW if not emph else ProvinceMapVisuals.OUTLINE_COMPARE_GLOW,
			4.1,
			_outline_pulse_phase + float(pid % 5) * 0.4,
			0.22 if emph else 0.12,
			(3.0 if emph else 2.0) * _map_overlay_pulse_speed_scale(),
		)
	if supply_mode:
		_pulse_supply_outlines()
	_apply_engineer_assignment_flash_pulses()


func _refresh_compare_candidate_outlines() -> void:
	for pid in _compare_candidate_ids:
		_set_compare_candidate_outline(pid, false, false)
	_compare_candidate_ids.clear()
	if selected_province_id < 0 or adjacency == null:
		return
	for nid in adjacency.get_neighbors(selected_province_id):
		var id := int(nid)
		if id == selected_province_id:
			continue
		if id == _compare_preview_province_id:
			continue
		_compare_candidate_ids.append(id)
		var emphasized := id == _hover_outline_province_id
		_set_compare_candidate_outline(id, true, emphasized)


func _set_compare_candidate_outline(province_id: int, visible: bool, emphasized: bool = false) -> void:
	var node := _province_node(province_id)
	if node == null:
		return
	if visible:
		var color := ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE
		var glow := ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE_GLOW
		var width := 1.6
		if emphasized:
			color = ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE_EMPH
			glow = ProvinceMapVisuals.OUTLINE_COMPARE_GLOW
			width = 2.6
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_COMPARE_CANDIDATE,
			color,
			width,
			glow,
			2.5,
			ProvinceMapVisuals.Z_COMPARE_CANDIDATE,
		)
	else:
		ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_COMPARE_CANDIDATE)


func _set_compare_preview_outline(province_id: int, visible: bool) -> void:
	var node := _province_node(province_id)
	if node == null:
		return
	if visible:
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_COMPARE,
			ProvinceMapVisuals.OUTLINE_COMPARE,
			2.8,
			ProvinceMapVisuals.OUTLINE_COMPARE_GLOW,
			3.0,
			ProvinceMapVisuals.Z_COMPARE,
		)
	else:
		ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_COMPARE)


func _supply_highlight_roles() -> Dictionary[int, String]:
	var roles: Dictionary[int, String] = {}
	if not supply_mode:
		return roles
	var sm := _supply_manager()
	for pid in province_nodes.keys():
		if ProvinceInsight.depot_fill_ratio(int(pid)) >= 0.0:
			roles[int(pid)] = "hub"  # overwritten below if on route / preview / selected
	if sm == null:
		return roles
	var selected: int = SupplyManager.get_selected_province_id()
	if selected < 0:
		selected = selected_province_id
	if selected >= 0:
		roles[selected] = "active"
	var preview_pids: Dictionary[int, bool] = {}
	if _supply_reroute_active:
		var preview: SupplyRoutePlan = sm.preview_player_route()
		if preview != null and preview.path_length() > 0:
			for pid_var in preview.province_path:
				preview_pids[int(pid_var)] = true
	for plan_var in sm.get_all_routes():
		if not (plan_var is SupplyRoutePlan):
			continue
		var plan := plan_var as SupplyRoutePlan
		if plan.represents_trade_flow:
			continue
		for pid_var in plan.province_path:
			var pid := int(pid_var)
			if str(roles.get(pid, "")) == "active":
				continue
			if preview_pids.has(pid):
				roles[pid] = "preview"
			else:
				roles[pid] = "route"
	for pid in preview_pids.keys():
		if str(roles.get(pid, "")) != "active":
			roles[pid] = "preview"
	# Trade corridors: soft ring on path provinces that are not already primary logistics / depots.
	for plan_var in sm.get_all_routes():
		if not (plan_var is SupplyRoutePlan):
			continue
		var tplan := plan_var as SupplyRoutePlan
		if not tplan.represents_trade_flow or tplan.province_path.size() < 2:
			continue
		for pid_var in tplan.province_path:
			var pid2 := int(pid_var)
			var cur := str(roles.get(pid2, ""))
			if cur in ["active", "preview", "route", "hub"]:
				continue
			roles[pid2] = "trade_transit"
	_apply_infra_pressure_overlay_roles(roles)
	return roles


func _apply_infra_pressure_overlay_roles(roles: Dictionary[int, String]) -> void:
	if not supply_mode or typeof(MapManager) == TYPE_NIL:
		return
	for pid_var in province_nodes.keys():
		var pid := int(pid_var)
		var existing: String = str(roles.get(pid, ""))
		if existing in ["active", "preview", "route"]:
			continue
		if not provinces.has(pid):
			continue
		var p: Province = provinces[pid] as Province
		if p == null:
			continue
		var bd: Dictionary = MapManager.get_infrastructure_repair_breakdown(pid)
		var eng_role := ProvinceInsight.get_engineer_supply_overlay_role(p, bd)
		if not eng_role.is_empty():
			roles[pid] = eng_role
			continue
		if ProvinceInsight.agent_pressure_focus_kind(p) == "disrupt":
			roles[pid] = "supply_pressure"
			continue
		var depot_sab := float(bd.get("depot_sabotage_level", 0.0))
		if depot_sab > 0.12:
			roles[pid] = "depot_sabotage"
			continue


func _pulse_supply_outlines() -> void:
	for pid in _supply_role_by_province.keys():
		if _engineer_assign_flash_by_province.has(pid):
			continue  # `_apply_engineer_assignment_flash_pulses` owns NODE_SUPPLY for this province.
		if int(pid) == _hover_outline_province_id:
			continue  # Hover outline already pulses this province; avoids stacked ring flicker.
		var role: String = str(_supply_role_by_province[pid])
		if role not in [
			"active", "preview", "route", "infra_sabotage", "infra_repair", "infra_repair_engineers",
			"infra_duel_even", "depot_sabotage", "supply_pressure", "engineers_stationed",
			"engineers_needed", "engineers_recommended", "engineers_insufficient", "trade_transit",
		]:
			continue
		var node := _province_node(int(pid))
		if node == null:
			continue
		var style: Dictionary = ProvinceMapVisuals.get_supply_outline_style(role)
		var phase_off := float(int(pid) % 7) * 0.35
		ProvinceMapVisuals.apply_pulse_to_polished(
			node,
			ProvinceMapVisuals.NODE_SUPPLY,
			style["color"],
			style["width"],
			style["glow"],
			float(style["width"]) + float(style["glow_extra"]),
			_outline_pulse_phase + phase_off,
			_pulse_amount_for_supply_role(role),
			float(style.get("pulse_speed", 1.0)),
		)


func _pulse_amount_for_supply_role(role: String) -> float:
	match role:
		"active":
			return 0.21
		"preview":
			return 0.26
		"route":
			return 0.15
		"infra_sabotage":
			return 0.66
		"infra_duel_even":
			return 0.42
		"supply_pressure":
			return 0.42
		"depot_sabotage":
			return 0.32
		"infra_repair":
			return 0.14
		"infra_repair_engineers":
			return 0.24
		"engineers_stationed":
			return 0.12
		"engineers_needed":
			return 0.58
		"engineers_recommended":
			return 0.35
		"engineers_insufficient":
			return 0.48
		"trade_transit":
			return 0.038
		"hub":
			return 0.17
		_:
			return 0.28


func _refresh_supply_highlights() -> void:
	var roles := _supply_highlight_roles()
	_supply_role_by_province = roles
	for pid in province_nodes.keys():
		var node := _province_node(int(pid))
		if node == null:
			continue
		var role: String = str(roles.get(int(pid), ""))
		if role.is_empty():
			ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_SUPPLY)
			continue
		var style: Dictionary = ProvinceMapVisuals.get_supply_outline_style(role)
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_SUPPLY,
			style["color"],
			style["width"],
			style["glow"],
			style["glow_extra"],
			style["z_index"],
		)


func _update_supply_overlay_legend() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	if _supply_overlay_legend == null or not is_instance_valid(_supply_overlay_legend):
		var panel := PanelContainer.new()
		_supply_legend_panel = panel
		panel.name = "SupplyOverlayLegend"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.offset_left = 10.0
		panel.offset_top = 10.0
		panel.custom_minimum_size = Vector2(520, 0)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.08, 0.14, 0.88)
		style.border_color = Color(0.35, 0.55, 0.85, 0.75)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		panel.add_theme_stylebox_override("panel", style)
		var margin := MarginContainer.new()
		panel.add_child(margin)
		_supply_overlay_legend = RichTextLabel.new()
		_supply_overlay_legend.bbcode_enabled = true
		_supply_overlay_legend.fit_content = true
		_supply_overlay_legend.scroll_active = false
		_supply_overlay_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_supply_overlay_legend.add_theme_font_size_override("normal_font_size", 11)
		margin.add_child(_supply_overlay_legend)
		ui.add_child(panel)
	_update_supply_legend_text()


func _update_supply_legend_text() -> void:
	_set_supply_legend_visible(supply_mode)
	if _supply_overlay_legend != null and supply_mode:
		var hover_role := ""
		if _hover_province != null:
			hover_role = str(_supply_role_by_province.get(_hover_province.id, ""))
		var hid := _hover_province.id if _hover_province != null else -1
		var contested_n := ProvinceInsight.count_contested_provinces(provinces)
		var agent_n := ProvinceInsight.count_agent_networks(provinces, _player_tag())
		var dual_n := ProvinceInsight.count_dual_situation_provinces(provinces)
		var pulse := _get_active_map_time_pulse_bbcode()
		_supply_overlay_legend.text = ProvinceInsight.build_supply_legend_bbcode(
			selected_province_id,
			_compare_candidate_ids.size(),
			hid,
			hover_role,
			contested_n,
			agent_n,
			_player_tag(),
			dual_n,
			pulse,
			_map_time_pulse_kind,
		)
		_apply_supply_legend_time_pulse_style(not pulse.is_empty(), _map_time_pulse_kind)
	_update_compare_hint_label()


func _apply_supply_legend_time_pulse_style(pulse_active: bool, pulse_kind: String = "") -> void:
	if _supply_legend_panel == null:
		return
	var style := _supply_legend_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	if not pulse_active:
		style.border_color = Color(0.35, 0.55, 0.85, 0.75)
	elif pulse_kind == "year":
		style.border_color = Color(0.45, 0.82, 1.0, 0.95)
	elif pulse_kind == "month":
		style.border_color = Color(0.55, 0.72, 0.92, 0.9)
	elif pulse_kind == "day":
		style.border_color = Color(0.42, 0.52, 0.68, 0.82)
	else:
		style.border_color = Color(0.55, 0.72, 0.92, 0.9)


func _update_compare_hint_label() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	if _compare_hint_label == null or not is_instance_valid(_compare_hint_label):
		_compare_hint_label = Label.new()
		_compare_hint_label.name = "CompareHintLabel"
		_compare_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_compare_hint_label.add_theme_font_size_override("font_size", 11)
		_compare_hint_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
		_compare_hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_compare_hint_label.offset_left = 12.0
		_compare_hint_label.offset_top = 52.0
		_compare_hint_label.custom_minimum_size = Vector2(480, 0)
		ui.add_child(_compare_hint_label)
	var contested_n := ProvinceInsight.count_contested_provinces(provinces)
	var agent_n := ProvinceInsight.count_agent_networks(provinces, _player_tag())
	var dual_n := ProvinceInsight.count_dual_situation_provinces(provinces)
	var show_compare := selected_province_id >= 0 and not supply_mode
	var show_conflict := contested_n > 0 and not supply_mode and not show_compare
	var show_agent := agent_n > 0 and not supply_mode and not show_compare and not show_conflict
	var show_supply_compare := selected_province_id >= 0 and supply_mode
	var p_tag := _player_tag()
	var has_radio := MapTechnologyContext.has_support_radio_bonuses(p_tag)
	var show_supply_overlays := (
		supply_mode
		and not show_supply_compare
		and (contested_n > 0 or agent_n > 0 or has_radio)
	)
	_compare_hint_label.visible = (
		show_compare or show_conflict or show_agent or show_supply_compare or show_supply_overlays
	)
	if show_supply_compare:
		var hid := _hover_province.id if _hover_province != null else -1
		var hover_cand := _is_compare_candidate(hid)
		var base := ProvinceInsight.build_map_compare_hint_plain(
			selected_province_id, _compare_candidate_ids.size(), hid, hover_cand,
		)
		var overlay := ProvinceInsight.build_map_supply_mode_hint_plain(
			contested_n, agent_n, dual_n, selected_province_id, p_tag,
		)
		_compare_hint_label.text = base + "  |  " + overlay if not overlay.is_empty() else base
		_compare_hint_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
	elif show_supply_overlays:
		_compare_hint_label.text = ProvinceInsight.build_map_supply_mode_hint_plain(
			contested_n, agent_n, dual_n, -1, p_tag,
		)
		_compare_hint_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.78))
	elif show_compare:
		var hid := _hover_province.id if _hover_province != null else -1
		var hover_cand := _is_compare_candidate(hid)
		_compare_hint_label.text = ProvinceInsight.build_map_compare_hint_plain(
			selected_province_id, _compare_candidate_ids.size(), hid, hover_cand,
		)
	elif show_conflict:
		_compare_hint_label.text = ProvinceInsight.build_conflict_map_hint_plain(contested_n)
		_compare_hint_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	elif show_agent:
		_compare_hint_label.text = (
			"◎ %d agent network%s — rings pulse daily · hover for strength & today's activity"
			% [agent_n, "s" if agent_n != 1 else ""]
		)
		_compare_hint_label.add_theme_color_override("font_color", Color(0.72, 0.55, 1.0))
	else:
		_compare_hint_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))


func _set_supply_legend_visible(visible: bool) -> void:
	if _supply_overlay_legend == null:
		return
	var panel: CanvasItem = _supply_legend_panel
	if panel == null:
		var margin := _supply_overlay_legend.get_parent()
		panel = margin.get_parent() if margin else null
	if panel is CanvasItem:
		panel.visible = visible


func _supply_depot_tint_color(fill_ratio: float) -> Color:
	if fill_ratio < 0.35:
		return Color(0.85, 0.2, 0.25, 0.9)
	if fill_ratio < 0.65:
		return Color(0.9, 0.65, 0.15, 0.85)
	return Color(0.25, 0.75, 0.45, 0.85)


func _on_open_national_spirits_pressed() -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		return
	var province: Province = provinces[selected_province_id] as Province
	var tag := ProvinceInsight.country_tag_for_province(province)
	var existing := get_tree().root.get_node_or_null("NationalSpiritsScreen")
	if existing != null:
		existing.queue_free()
	var packed: PackedScene = load("res://scenes/ui/NationalSpiritsScreen.tscn") as PackedScene
	if packed == null:
		return
	var screen: NationalSpiritsScreen = packed.instantiate() as NationalSpiritsScreen
	if screen == null:
		return
	screen.country_tag = tag
	screen.name = "NationalSpiritsScreen"
	get_tree().root.add_child(screen)
	screen.refresh_screen()


#endregion


func _get_feature_icon(feature: String) -> String:
	match feature.to_lower():
		"port", "major_port": return "⚓"
		"naval_shipyard": return "⚙️"
		"airfield": return "✈️"
		"fort": return "🛡️"
		"research_center": return "🔬"
		"oil_rig", "oil": return "⛽"
		"nuclear_plant": return "☢️"
		"spaceport": return "🚀"
		"mega_factory", "major_factory": return "🏭"
		_: return "◆"
