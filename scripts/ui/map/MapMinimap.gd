# scripts/ui/map/MapMinimap.gd
## Corner minimap: click-to-pan, LOD tier hint, strategic political dots (Vic3-style).
extends PanelContainer

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")
const MINIMAP_FRAME_PATH := "res://assets/graphics/ui/minimap_frame_512.png"

var _map_renderer: Node = null
var _camera: Camera2D = null
var _draw_area: Control = null
var _frame_overlay: TextureRect = null
var _world_bounds: Rect2 = MapCanvasConfig.WORLD_CANONICAL_BOUNDS
var _viewport_rect: Rect2 = Rect2()
var _lod_tier: int = MapZoomLODScript.Tier.STRATEGIC
var _political_dots: Array = []  # [{pos: Vector2, color: Color}]
var _dots_built: bool = false
## Pass 15: weather ground-state dots on minimap when weather mapmode active.
var _weather_dots: Array = []  # [{pos: Vector2, color: Color, key: String}]
var _weather_dots_built: bool = false
var _show_weather_dots: bool = false
## Pass 16/17: convoy route midpoints as amber pips; click focuses target province.
var _convoy_pips: Array = []  # [{pos: Vector2, interdiction: float, focus_pid: int}]
var _convoy_pips_built: bool = false
var _show_convoy_pips: bool = false
## Pass 23/24: depot munitions ratio pips (cyan full → red empty).
var _munitions_pips: Array = []  # [{pos: Vector2, ratio: float, focus_pid: int}]
var _munitions_pips_built: bool = false
var _show_munitions_pips: bool = false
## Pass 24: only show player-owned depots (default true).
var _munitions_pips_player_only: bool = true
## Pass 27: all | occupied | mine
var _munitions_occupation_filter: String = "all"
const CONVOY_PIP_HIT_PX := 8.0
const MUNITIONS_PIP_HIT_PX := 7.0
var _last_pip_click_ms: int = 0
var _last_pip_index: int = -1
const DOUBLE_CLICK_MS := 380
## Pass 19/26/27: multi-route compare — Shift+click A→B→C→D pack.
var _compare_path_a: Array = []
var _compare_meta_a: Dictionary = {}
var _compare_path_b: Array = []
var _compare_meta_b: Dictionary = {}
var _compare_path_c: Array = []
var _compare_meta_c: Dictionary = {}
## Pass 30: pack slot pins [{pos, label, color, slot, focus_pid}].
var _pack_pins: Array = []
var _show_pack_pins: bool = true
const PACK_PIN_HIT_PX := 9.0
## Pass 33: click near a pack route polyline segment → load that slot.
const PACK_POLY_HIT_PX := 5.5
## Pass 34: pack pin legend [{slot, label, color, routes}].
var _pack_legend: Array = []
var _show_pack_legend: bool = true
## Pass 35: hit rects for legend rows [{rect: Rect2, slot: int}].
var _pack_legend_hits: Array = []
## Pass 43: soft risk heat blobs under pack pins on minimap.
var _show_pack_risk_heat: bool = true
## Pass 45: heat intensity multiplier (0.0–2.0, default 1.0).
var _pack_risk_heat_intensity: float = 1.0
## Pass 47: pack pin legend opacity (0.0–1.0, default 1.0).
var _pack_legend_opacity: float = 1.0
## Pass 48/49: heat color ramp id (classic | inferno | viridis | mono | custom).
var _pack_heat_ramp: String = "classic"
## Pass 49: custom cool/hot colors (used when ramp == custom).
var _pack_heat_cool: Color = Color(0.35, 0.85, 1.0, 1.0)
var _pack_heat_hot: Color = Color(1.0, 0.25, 0.15, 1.0)
## Pass 50: draw heat ramp swatch legend (top-right under tier label).
var _show_heat_ramp_legend: bool = true
## Pass 51: hit rect for click-to-cycle heat ramp.
var _heat_swatch_hit: Rect2 = Rect2()


func _ready() -> void:
	custom_minimum_size = Vector2(180, 100)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_area = Control.new()
	_draw_area.custom_minimum_size = Vector2(180, 100)
	_draw_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_area.gui_input.connect(_on_minimap_input)
	_draw_area.draw.connect(_on_draw_minimap)
	_draw_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_draw_area)
	_apply_minimap_frame()


func bind(map_renderer: Node, camera: Camera2D) -> void:
	_map_renderer = map_renderer
	_camera = camera
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_world_bounds"):
		var wb: Rect2 = MapManager.get_world_bounds()
		if wb.size.x > 10.0 and wb.size.y > 0.0:
			_world_bounds = wb
	invalidate_political_cache()
	_apply_minimap_frame()
	# Pass 30/34: seed pack pins + legend from renderer slots.
	if _map_renderer != null and _map_renderer.has_method("get_pack_slot_pins"):
		set_pack_pins(_map_renderer.call("get_pack_slot_pins"))
	if _map_renderer != null and _map_renderer.has_method("get_pack_slot_legend"):
		set_pack_legend(_map_renderer.call("get_pack_slot_legend"))
	_draw_area.queue_redraw()


## Pass 30: set/clear pack slot pins on minimap.
func set_pack_pins(pins: Array) -> void:
	_pack_pins = []
	for p in pins:
		if p is Dictionary:
			_pack_pins.append((p as Dictionary).duplicate(true))
	if _draw_area:
		_draw_area.queue_redraw()


## Pass 43: toggle soft risk heat overlay under pack pins.
func set_show_pack_risk_heat(enable: bool) -> void:
	_show_pack_risk_heat = enable
	if _draw_area:
		_draw_area.queue_redraw()


func get_show_pack_risk_heat() -> bool:
	return _show_pack_risk_heat


## Pass 45: heat intensity 0–2 (radius + alpha scale).
func set_pack_risk_heat_intensity(intensity: float) -> void:
	_pack_risk_heat_intensity = clampf(intensity, 0.0, 2.0)
	if _draw_area:
		_draw_area.queue_redraw()


func get_pack_risk_heat_intensity() -> float:
	return _pack_risk_heat_intensity


## Pass 47: pack pin legend opacity 0–1.
func set_pack_legend_opacity(opacity: float) -> void:
	_pack_legend_opacity = clampf(opacity, 0.0, 1.0)
	if _draw_area:
		_draw_area.queue_redraw()


func get_pack_legend_opacity() -> float:
	return _pack_legend_opacity


## Pass 48/49: heat color ramp preset id.
func set_pack_heat_ramp(ramp: String) -> void:
	var r := ramp.strip_edges().to_lower()
	if r not in ["classic", "inferno", "viridis", "mono", "custom"]:
		r = "classic"
	_pack_heat_ramp = r
	if _draw_area:
		_draw_area.queue_redraw()


func get_pack_heat_ramp() -> String:
	return _pack_heat_ramp


## Pass 49: custom cool endpoint for heat lerp.
func set_pack_heat_cool(col: Color) -> void:
	_pack_heat_cool = col
	if _draw_area:
		_draw_area.queue_redraw()


func get_pack_heat_cool() -> Color:
	return _pack_heat_cool


## Pass 49: custom hot endpoint for heat lerp.
func set_pack_heat_hot(col: Color) -> void:
	_pack_heat_hot = col
	if _draw_area:
		_draw_area.queue_redraw()


func get_pack_heat_hot() -> Color:
	return _pack_heat_hot


## Pass 50: toggle heat ramp swatch legend on minimap.
func set_show_heat_ramp_legend(enable: bool) -> void:
	_show_heat_ramp_legend = enable
	if _draw_area:
		_draw_area.queue_redraw()


func get_show_heat_ramp_legend() -> bool:
	return _show_heat_ramp_legend


## Pass 48/49: cool/hot colors for current heat ramp.
func get_pack_heat_ramp_colors() -> Array:
	match _pack_heat_ramp:
		"custom":
			return [_pack_heat_cool, _pack_heat_hot]
		"inferno":
			return [Color(0.15, 0.05, 0.35, 1.0), Color(1.0, 0.95, 0.35, 1.0)]
		"viridis":
			return [Color(0.22, 0.15, 0.45, 1.0), Color(0.95, 0.9, 0.2, 1.0)]
		"mono":
			return [Color(0.35, 0.38, 0.42, 1.0), Color(0.95, 0.97, 1.0, 1.0)]
		_:
			# classic cyan → hot red
			return [Color(0.35, 0.85, 1.0, 1.0), Color(1.0, 0.25, 0.15, 1.0)]


## Pass 34: set pack pin legend entries (one per filled slot).
func set_pack_legend(entries: Array) -> void:
	_pack_legend = []
	for e in entries:
		if e is Dictionary:
			_pack_legend.append((e as Dictionary).duplicate(true))
	if _draw_area:
		_draw_area.queue_redraw()


func invalidate_pack_pins() -> void:
	if _map_renderer != null and _map_renderer.has_method("get_pack_slot_pins"):
		set_pack_pins(_map_renderer.call("get_pack_slot_pins"))
	else:
		_pack_pins.clear()
	if _map_renderer != null and _map_renderer.has_method("get_pack_slot_legend"):
		set_pack_legend(_map_renderer.call("get_pack_slot_legend"))
	else:
		_pack_legend.clear()
		if _draw_area:
			_draw_area.queue_redraw()


func _apply_minimap_frame() -> void:
	## Pass 5: retrowave minimap chrome overlay (does not block clicks — mouse_filter IGNORE).
	if _frame_overlay != null and is_instance_valid(_frame_overlay):
		return
	if not ResourceLoader.exists(MINIMAP_FRAME_PATH):
		# Fallback flat border via theme.
		RetrowaveTheme.style_world_panel(self)
		return
	var tex := load(MINIMAP_FRAME_PATH) as Texture2D
	if tex == null:
		return
	# Panel style for base
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 40
	sb.texture_margin_right = 40
	sb.texture_margin_top = 40
	sb.texture_margin_bottom = 40
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	_frame_overlay = TextureRect.new()
	_frame_overlay.name = "MinimapFrameOverlay"
	_frame_overlay.texture = tex
	_frame_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_frame_overlay.modulate = Color(1, 1, 1, 0.92)
	add_child(_frame_overlay)
	# Keep draw area below overlay for chrome, but overlay ignores mouse so clicks reach draw.
	if _draw_area:
		move_child(_draw_area, 0)


func set_lod_tier(tier: int) -> void:
	if tier == _lod_tier:
		return
	_lod_tier = tier
	# Pass 24: munitions pip density depends on LOD — rebuild list.
	if _show_munitions_pips:
		invalidate_munitions_cache()
	if _draw_area != null:
		_draw_area.queue_redraw()


func invalidate_political_cache() -> void:
	_political_dots.clear()
	_dots_built = false
	invalidate_weather_cache()
	invalidate_munitions_cache()


func invalidate_weather_cache() -> void:
	_weather_dots.clear()
	_weather_dots_built = false


func invalidate_convoy_cache() -> void:
	_convoy_pips.clear()
	_convoy_pips_built = false


func invalidate_munitions_cache() -> void:
	_munitions_pips.clear()
	_munitions_pips_built = false
	if _show_munitions_pips and _draw_area != null:
		_draw_area.queue_redraw()


## Pass 23: toggle per-depot munitions pips (munitions mapmode / Ammo preset).
func set_show_munitions_pips(enable: bool) -> void:
	if _show_munitions_pips == enable:
		if enable:
			invalidate_munitions_cache()
		if _draw_area:
			_draw_area.queue_redraw()
		return
	_show_munitions_pips = enable
	if not enable:
		invalidate_munitions_cache()
	else:
		_munitions_pips_built = false
	if _draw_area:
		_draw_area.queue_redraw()


## Pass 24: filter munitions pips to player-owned depots only.
func set_munitions_pips_player_only(enable: bool) -> void:
	if _munitions_pips_player_only == enable:
		return
	_munitions_pips_player_only = enable
	if enable:
		_munitions_occupation_filter = "mine"
	elif _munitions_occupation_filter == "mine":
		_munitions_occupation_filter = "all"
	if _show_munitions_pips:
		invalidate_munitions_cache()
	if _draw_area:
		_draw_area.queue_redraw()


func get_munitions_pips_player_only() -> bool:
	return _munitions_pips_player_only


## Pass 27: occupation filter for munitions pips.
func set_munitions_occupation_filter(mode: String) -> void:
	var m := mode.strip_edges().to_lower()
	if m not in ["all", "occupied", "mine"]:
		m = "all"
	if _munitions_occupation_filter == m:
		return
	_munitions_occupation_filter = m
	_munitions_pips_player_only = (m == "mine")
	if _show_munitions_pips:
		invalidate_munitions_cache()
	if _draw_area:
		_draw_area.queue_redraw()


## Pass 15: toggle weather ground-state dots (called when weather mapmode on/off).
func set_show_weather_dots(enable: bool) -> void:
	if _show_weather_dots == enable:
		return
	_show_weather_dots = enable
	if not enable:
		invalidate_weather_cache()
	else:
		_weather_dots_built = false
	if _draw_area != null:
		_draw_area.queue_redraw()


## Pass 16: trade/supply convoy midpoints as minimap pips.
func set_show_convoy_pips(enable: bool) -> void:
	if _show_convoy_pips == enable:
		if enable:
			invalidate_convoy_cache()
		if _draw_area != null:
			_draw_area.queue_redraw()
		return
	_show_convoy_pips = enable
	if not enable:
		invalidate_convoy_cache()
	else:
		_convoy_pips_built = false
	if _draw_area != null:
		_draw_area.queue_redraw()


func _ensure_political_dots() -> void:
	if _dots_built:
		return
	_dots_built = true
	if typeof(MapManager) == TYPE_NIL:
		return
	var centroids: Dictionary = {}
	if MapManager.has_method("get_all_centroids"):
		centroids = MapManager.get_all_centroids()
	elif MapManager.has_method("get_province_centroid"):
		if "provinces" in MapManager:
			for pid_var in MapManager.provinces.keys():
				centroids[int(pid_var)] = MapManager.get_province_centroid(int(pid_var))
	if centroids.is_empty():
		return

	for pid_var in centroids.keys():
		var pid := int(pid_var)
		var pos: Vector2 = centroids[pid_var] as Vector2
		if pos == Vector2.ZERO:
			continue
		var prov: Province = null
		if MapManager.has_method("get_province"):
			prov = MapManager.get_province(pid) as Province
		if prov != null and prov.is_sea:
			continue
		var tag := ""
		if prov != null:
			tag = prov.owner_tag.strip_edges().to_upper()
		var col := Color(0.45, 0.48, 0.55, 0.85)
		if not tag.is_empty() and MapManager.has_method("get_country_color"):
			col = MapManager.get_country_color(tag)
			col.a = 0.88
		_political_dots.append({"pos": pos, "color": col})


func _ensure_weather_dots() -> void:
	if _weather_dots_built:
		return
	_weather_dots_built = true
	_weather_dots.clear()
	if typeof(WeatherManager) == TYPE_NIL or not WeatherManager.has_method("get_province_weather"):
		return
	var centroids: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL:
		if MapManager.has_method("get_all_centroids"):
			centroids = MapManager.get_all_centroids()
		elif _map_renderer != null and "province_centroids" in _map_renderer:
			centroids = _map_renderer.province_centroids
	if centroids.is_empty() and _map_renderer != null and "province_centroids" in _map_renderer:
		centroids = _map_renderer.province_centroids
	if centroids.is_empty():
		return
	var keys: Array = centroids.keys()
	# Sample denser on small maps, step on world_full.
	var step := 1
	if keys.size() > 600:
		step = maxi(1, int(keys.size() / 180))
	elif keys.size() > 200:
		step = maxi(1, int(keys.size() / 120))
	var filt := ""
	if _map_renderer != null and "weather_ground_filter" in _map_renderer:
		filt = str(_map_renderer.weather_ground_filter).strip_edges().to_lower()
	var idx := 0
	while idx < keys.size():
		var pid_v = keys[idx]
		idx += step
		var pos: Vector2 = centroids[pid_v] as Vector2
		if pos == Vector2.ZERO:
			continue
		var w: Variant = WeatherManager.call("get_province_weather", int(pid_v))
		if not (w is Dictionary):
			continue
		var wd: Dictionary = w
		var g := str(wd.get("ground_state", "dry")).to_lower()
		var precip := float(wd.get("precip_intensity", 0.0))
		var key := "dry"
		if precip >= 0.55 or "storm" in g:
			key = "storm"
		elif "snow" in g or g in ["frozen", "ice"]:
			key = "snow"
		elif "mud" in g or g in ["wet", "muddy"]:
			key = "mud"
		if not filt.is_empty() and key != filt:
			continue
		# Skip most dry when unfiltered to keep read clean.
		if filt.is_empty() and key == "dry" and randf() > 0.08:
			continue
		_weather_dots.append({"pos": pos, "color": _weather_dot_color(key), "key": key})


func _weather_dot_color(key: String) -> Color:
	match key:
		"mud":
			return Color(0.55, 0.38, 0.22, 0.9)
		"snow":
			return Color(0.82, 0.9, 1.0, 0.92)
		"storm":
			return Color(0.55, 0.35, 0.95, 0.92)
		_:
			return Color(0.92, 0.85, 0.55, 0.75)


func _ensure_convoy_pips() -> void:
	if _convoy_pips_built:
		return
	_convoy_pips_built = true
	_convoy_pips.clear()
	var routes: Array = []
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("get_all_routes"):
		routes = SupplyManager.get_all_routes()
	if routes.is_empty() and _map_renderer != null:
		# Fallback: supply map layer cache if manager empty.
		if "supply_map_layer" in _map_renderer:
			var sml = _map_renderer.supply_map_layer
			if sml != null and "_trade_paths_cache" in sml:
				var cache = sml._trade_paths_cache
				if cache is Array:
					for entry in cache:
						if entry is Dictionary and entry.get("pts") is PackedVector2Array:
							var pts: PackedVector2Array = entry.get("pts")
							if pts.size() >= 2:
								var mid_i := int(pts.size() / 2)
								_convoy_pips.append({
									"pos": pts[mid_i],
									"interdiction": float(entry.get("interdiction", 0.0)),
									"focus_pid": int(entry.get("focus_pid", -1)),
								})
					return
	var centroids: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_centroids"):
		centroids = MapManager.get_all_centroids()
	elif _map_renderer != null and "province_centroids" in _map_renderer:
		centroids = _map_renderer.province_centroids
	var n := 0
	const MAX_PIPS := 36
	for plan_var in routes:
		if n >= MAX_PIPS:
			break
		if not (plan_var is SupplyRoutePlan):
			continue
		var plan := plan_var as SupplyRoutePlan
		if plan.province_path.size() < 2:
			continue
		# Prefer trade corridors; also military with risk.
		var inter := float(plan.interdiction_chance) if "interdiction_chance" in plan else 0.0
		if not plan.represents_trade_flow and inter < 0.1:
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		var path_pids: Array = []
		for pid in plan.province_path:
			path_pids.append(int(pid))
			if centroids.has(pid):
				pts.append(centroids[pid] as Vector2)
			elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
				var c: Vector2 = MapManager.get_province_centroid(int(pid))
				if c != Vector2.ZERO:
					pts.append(c)
		if pts.size() < 2:
			continue
		var mid_i := int(pts.size() / 2)
		# Pass 17: focus target (route end) or mid province for click-to-focus.
		var focus_pid := int(plan.target_province_id) if "target_province_id" in plan else -1
		if focus_pid < 0 and not path_pids.is_empty():
			focus_pid = int(path_pids[mini(mid_i, path_pids.size() - 1)])
		_convoy_pips.append({
			"pos": pts[mid_i],
			"interdiction": inter,
			"focus_pid": focus_pid,
			"path": path_pids.duplicate(),
		})
		n += 1


func _ensure_munitions_pips() -> void:
	if _munitions_pips_built:
		return
	_munitions_pips_built = true
	_munitions_pips.clear()
	if typeof(SupplyManager) == TYPE_NIL:
		return
	var centroids: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_centroids"):
		centroids = MapManager.get_all_centroids()
	elif _map_renderer != null and "province_centroids" in _map_renderer:
		centroids = _map_renderer.province_centroids
	# Pass 24: LOD-capped count.
	var max_mun: int = MapZoomLODScript.munitions_pip_max_count(_lod_tier)
	var prefer_critical: bool = MapZoomLODScript.munitions_pip_prefer_critical(_lod_tier)
	var player := ""
	if _munitions_pips_player_only:
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
			player = str(LeaderManager.get_player_country_tag()).to_upper()
		elif typeof(SupplyManager) != TYPE_NIL and "player_tag" in SupplyManager:
			player = str(SupplyManager.player_tag).to_upper()
	if not ("depot_states" in SupplyManager):
		return
	var deps: Dictionary = SupplyManager.depot_states
	var candidates: Array = []
	for pid_v in deps.keys():
		var pid := int(pid_v)
		var prov = null
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			prov = MapManager.get_province(pid)
		elif _map_renderer != null and "provinces" in _map_renderer:
			prov = _map_renderer.provinces.get(pid)
		var owner_tag := ""
		var ctrl_tag := ""
		if prov != null:
			if "owner_tag" in prov:
				owner_tag = str(prov.owner_tag).to_upper()
			if "controller_tag" in prov:
				ctrl_tag = str(prov.controller_tag).to_upper()
		var effective := ctrl_tag if not ctrl_tag.is_empty() else owner_tag
		var occupied := not ctrl_tag.is_empty() and not owner_tag.is_empty() and ctrl_tag != owner_tag
		# Pass 24/25/27: mine / occupied / all filters.
		var ofilt := _munitions_occupation_filter
		if ofilt == "mine" or _munitions_pips_player_only:
			if not player.is_empty() and not effective.is_empty() and effective != player:
				continue
		elif ofilt == "occupied":
			if not occupied:
				continue
		var ratio := -1.0
		if SupplyManager.has_method("get_depot_munitions_ratio"):
			ratio = float(SupplyManager.get_depot_munitions_ratio(pid))
		else:
			var d = deps[pid_v]
			if d != null and d.has_method("munitions_ratio"):
				ratio = float(d.munitions_ratio())
		if ratio < 0.0:
			continue
		var pos := Vector2.ZERO
		if centroids.has(pid):
			pos = centroids[pid] as Vector2
		elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
			pos = MapManager.get_province_centroid(pid)
		if pos == Vector2.ZERO:
			continue
		candidates.append({
			"pos": pos,
			"ratio": clampf(ratio, 0.0, 1.0),
			"focus_pid": pid,
			"occupied": occupied,
		})
	# Strategic: lowest fill first (critical ammo). Operational/tactical: lowest first still helps urgency.
	candidates.sort_custom(func(a, b) -> bool:
		if prefer_critical:
			return float(a.get("ratio", 1.0)) < float(b.get("ratio", 1.0))
		# At higher zoom still surface low fill near top but keep variety by id.
		return float(a.get("ratio", 1.0)) < float(b.get("ratio", 1.0))
	)
	var n := 0
	for c in candidates:
		if n >= max_mun:
			break
		_munitions_pips.append(c)
		n += 1


func _minimap_transform(r: Rect2) -> Dictionary:
	var scale_x := r.size.x / _world_bounds.size.x
	var scale_y := r.size.y / _world_bounds.size.y
	var s := minf(scale_x, scale_y) * 0.95
	var ox := r.position.x + (r.size.x - _world_bounds.size.x * s) * 0.5
	var oy := r.position.y + (r.size.y - _world_bounds.size.y * s) * 0.5
	return {"s": s, "ox": ox, "oy": oy}


func _world_to_minimap(p: Vector2, xf: Dictionary) -> Vector2:
	return Vector2(xf["ox"] + p.x * xf["s"], xf["oy"] + p.y * xf["s"])


func _on_draw_minimap() -> void:
	if _draw_area == null:
		return
	var r := _draw_area.get_rect()
	# Slightly darker fill so cyan minimap frame chrome reads cleaner.
	_draw_area.draw_rect(r, Color(0.05, 0.07, 0.12, 0.94))
	if _frame_overlay == null:
		_draw_area.draw_rect(r, Color(0.2, 0.9, 1.0, 0.35), false, 1.5)

	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province_count"):
		return

	var xf := _minimap_transform(r)

	if MapZoomLODScript.show_minimap_political_dots(_lod_tier):
		_ensure_political_dots()
		var dot_r := 1.6 if _lod_tier == MapZoomLODScript.Tier.STRATEGIC else 1.2
		for entry: Dictionary in _political_dots:
			var mp := _world_to_minimap(entry["pos"] as Vector2, xf)
			if not r.has_point(mp):
				continue
			_draw_area.draw_circle(mp, dot_r, entry["color"] as Color)
	else:
		# Europe cluster hint when not showing full political dots
		var europe := Rect2(
			_world_bounds.position.x,
			_world_bounds.position.y,
			_world_bounds.size.x * 0.45,
			_world_bounds.size.y * 0.45
		)
		_draw_area.draw_rect(
			Rect2(
				xf["ox"] + europe.position.x * xf["s"],
				xf["oy"] + europe.position.y * xf["s"],
				europe.size.x * xf["s"],
				europe.size.y * xf["s"]
			),
			Color(0.2, 0.75, 0.55, 0.25)
		)

	# Pass 15: weather ground-state dots (when weather mapmode / Climate preset active).
	if _show_weather_dots:
		_ensure_weather_dots()
		var wr := 1.8 if _lod_tier == MapZoomLODScript.Tier.STRATEGIC else 1.35
		for entry: Dictionary in _weather_dots:
			var mp2 := _world_to_minimap(entry["pos"] as Vector2, xf)
			if not r.has_point(mp2):
				continue
			_draw_area.draw_circle(mp2, wr, entry["color"] as Color)
			# Tiny ring so storm/snow read on dark fill.
			if str(entry.get("key", "")) in ["storm", "snow"]:
				_draw_area.draw_arc(mp2, wr + 0.8, 0.0, TAU, 8, Color(1, 1, 1, 0.25), 0.8)

	# Pass 16: convoy midpoints (trade / at-risk supply).
	if _show_convoy_pips:
		_ensure_convoy_pips()
		var pr := 2.0 if _lod_tier == MapZoomLODScript.Tier.STRATEGIC else 1.5
		for entry: Dictionary in _convoy_pips:
			var mp3 := _world_to_minimap(entry["pos"] as Vector2, xf)
			if not r.has_point(mp3):
				continue
			var inter := clampf(float(entry.get("interdiction", 0.0)), 0.0, 1.0)
			var col := Color(0.95, 0.75, 0.25, 0.92).lerp(Color(1.0, 0.3, 0.25, 0.95), inter)
			_draw_area.draw_circle(mp3, pr, col)
			_draw_area.draw_arc(mp3, pr + 1.0, 0.0, TAU, 10, Color(1, 1, 1, 0.3 + inter * 0.25), 0.9)

	# Pass 30–32/43: pack multi-pins + polylines + risk heat overlay.
	if _show_pack_pins and not _pack_pins.is_empty():
		# Pass 43/45/48: soft heat blobs (intensity + color ramp).
		if _show_pack_risk_heat and _pack_risk_heat_intensity > 0.01:
			var inten := _pack_risk_heat_intensity
			var ramp_cols: Array = get_pack_heat_ramp_colors()
			var cool_c: Color = ramp_cols[0] as Color if ramp_cols.size() >= 1 else Color(0.35, 0.85, 1.0)
			var hot_c: Color = ramp_cols[1] as Color if ramp_cols.size() >= 2 else Color(1.0, 0.25, 0.15)
			for pin_h in _pack_pins:
				if not pin_h is Dictionary:
					continue
				var pe_h: Dictionary = pin_h
				var ph := _world_to_minimap(pe_h.get("pos", Vector2.ZERO) as Vector2, xf)
				if not r.has_point(ph):
					continue
				var risk_h := clampf(float(pe_h.get("risk", 0.0)), 0.0, 1.0)
				var heat_r := (5.0 + risk_h * 10.0) * (0.55 + inten * 0.45)
				var a_scale := clampf(inten, 0.0, 2.0)
				var base := cool_c.lerp(hot_c, risk_h)
				var heat_col := Color(
					base.r, base.g, base.b,
					(0.12 + risk_h * 0.28) * a_scale
				)
				heat_col.a = clampf(heat_col.a, 0.0, 0.85)
				# Concentric soft discs (outer faint → inner hotter).
				_draw_area.draw_circle(ph, heat_r, heat_col)
				_draw_area.draw_circle(ph, heat_r * 0.55, Color(heat_col.r, heat_col.g, heat_col.b, clampf(heat_col.a * 1.4, 0.0, 0.9)))
		# Pass 32: draw polylines under pins (faint route skeletons).
		for pin_pl in _pack_pins:
			if not pin_pl is Dictionary:
				continue
			var pe_pl: Dictionary = pin_pl
			var poly_raw = pe_pl.get("polyline", [])
			if not (poly_raw is Array) or (poly_raw as Array).size() < 2:
				continue
			var pcol_pl: Color = pe_pl.get("color", Color(0.8, 0.9, 1.0, 0.95)) as Color
			var line_col := Color(pcol_pl.r, pcol_pl.g, pcol_pl.b, 0.42 if bool(pe_pl.get("primary", true)) else 0.28)
			var w := 1.6 if bool(pe_pl.get("primary", true)) else 1.1
			var prev_mp := Vector2.INF
			for pt in poly_raw:
				if not (pt is Vector2):
					continue
				var mp_pl := _world_to_minimap(pt as Vector2, xf)
				if prev_mp != Vector2.INF:
					_draw_area.draw_line(prev_mp, mp_pl, line_col, w)
				prev_mp = mp_pl
		for pin in _pack_pins:
			if not pin is Dictionary:
				continue
			var pe: Dictionary = pin
			var pp := _world_to_minimap(pe.get("pos", Vector2.ZERO) as Vector2, xf)
			if not r.has_point(pp):
				continue
			var pcol: Color = pe.get("color", Color(0.8, 0.9, 1.0, 0.95)) as Color
			var is_primary := bool(pe.get("primary", true))
			# Pass 38: risk intensity scales radius + hot outer ring.
			var risk_i := clampf(float(pe.get("risk", 0.0)), 0.0, 1.0)
			var rad := (3.4 if is_primary else 2.4) + risk_i * 1.4
			_draw_area.draw_circle(pp, rad, pcol)
			var ring_a := 0.28 + risk_i * 0.55
			var ring_col := Color(1.0, 0.35 + (1.0 - risk_i) * 0.45, 0.25, ring_a) if risk_i > 0.15 else Color(1, 1, 1, 0.4 if is_primary else 0.28)
			_draw_area.draw_arc(pp, rad + 1.3, 0.0, TAU, 10, ring_col, 1.0 + risk_i * 0.8)
			if risk_i >= 0.55:
				# High-risk core flash.
				_draw_area.draw_circle(pp, rad * 0.4, Color(1.0, 0.9, 0.4, 0.55 + risk_i * 0.25))
			var plab := str(pe.get("label", ""))
			if not plab.is_empty() and (is_primary or _lod_tier != MapZoomLODScript.Tier.STRATEGIC):
				_draw_area.draw_string(
					ThemeDB.fallback_font,
					pp + Vector2(4, -1),
					plab.substr(0, 7),
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					8 if not is_primary else 9,
					pcol
				)

	# Pass 23/24: munitions depot stockpile pips (LOD radius + detail).
	if _show_munitions_pips:
		_ensure_munitions_pips()
		var mr: float = MapZoomLODScript.munitions_pip_radius(_lod_tier)
		var show_detail: bool = MapZoomLODScript.show_minimap_munitions_detail(_lod_tier)
		for entry_m: Dictionary in _munitions_pips:
			var mpm := _world_to_minimap(entry_m["pos"] as Vector2, xf)
			if not r.has_point(mpm):
				continue
			var ratio := clampf(float(entry_m.get("ratio", 0.0)), 0.0, 1.0)
			var mcol := Color(0.95, 0.32, 0.28, 0.95).lerp(Color(0.35, 0.82, 1.0, 0.95), ratio)
			_draw_area.draw_circle(mpm, mr, mcol)
			# Pass 26: occupation ring (controller ≠ owner).
			if bool(entry_m.get("occupied", false)):
				_draw_area.draw_arc(mpm, mr + 1.4, 0.0, TAU, 12, Color(0.98, 0.75, 0.25, 0.85), 1.2)
			if show_detail:
				_draw_area.draw_arc(mpm, mr + 1.0, 0.0, TAU, 10, Color(0.9, 0.95, 1.0, 0.35), 0.85)
				# Low munitions urgency tick (operational+tactical).
				if ratio < 0.28:
					var tick := mr + 1.5
					_draw_area.draw_line(mpm + Vector2(0, -tick), mpm + Vector2(0, tick), Color(1.0, 0.45, 0.35, 0.85), 1.0)
			elif ratio < 0.28:
				# Strategic: still mark critical with a brighter core.
				_draw_area.draw_circle(mpm, mr * 0.45, Color(1.0, 0.9, 0.5, 0.9))

	if _camera != null:
		var vp := get_viewport().get_visible_rect().size
		var zoom := absf(_camera.zoom.x)
		var half := vp * 0.5 / maxf(zoom, 0.01)
		var cam_center := _camera.global_position
		var view := Rect2(cam_center - half, half * 2.0)
		_viewport_rect = Rect2(
			xf["ox"] + view.position.x * xf["s"],
			xf["oy"] + view.position.y * xf["s"],
			view.size.x * xf["s"],
			view.size.y * xf["s"]
		)
		_draw_area.draw_rect(_viewport_rect, Color(1.0, 0.35, 0.55, 0.55), false, 2.0)

	var tier_name := MapZoomLODScript.tier_name(_lod_tier)
	var tier_col := Color(0.55, 0.82, 0.98, 0.92)
	if _lod_tier == MapZoomLODScript.Tier.OPERATIONAL:
		tier_col = Color(0.78, 0.88, 0.55, 0.92)
	elif _lod_tier == MapZoomLODScript.Tier.TACTICAL:
		tier_col = Color(0.98, 0.72, 0.45, 0.92)
	_draw_area.draw_string(
		ThemeDB.fallback_font,
		r.position + Vector2(6, 14),
		tier_name.capitalize(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		tier_col
	)

	# Pass 50/51: heat ramp swatch legend (top-right; click to cycle).
	_heat_swatch_hit = Rect2()
	if (
		_show_heat_ramp_legend
		and _show_pack_risk_heat
		and _pack_risk_heat_intensity > 0.01
		and _show_pack_pins
		and not _pack_pins.is_empty()
	):
		var ramp_cols2: Array = get_pack_heat_ramp_colors()
		var cool_l: Color = ramp_cols2[0] as Color if ramp_cols2.size() >= 1 else Color(0.35, 0.85, 1.0)
		var hot_l: Color = ramp_cols2[1] as Color if ramp_cols2.size() >= 2 else Color(1.0, 0.25, 0.15)
		var sw_w := 48.0
		var sw_h := 6.0
		var sw_x := r.position.x + r.size.x - sw_w - 8.0
		var sw_y := r.position.y + 8.0
		var segs := 8
		for si2 in segs:
			var t_s := float(si2) / float(maxi(segs - 1, 1))
			var sc := cool_l.lerp(hot_l, t_s)
			sc.a = 0.92
			var sx := sw_x + float(si2) * (sw_w / float(segs))
			_draw_area.draw_rect(
				Rect2(sx, sw_y, sw_w / float(segs) + 0.5, sw_h), sc, true
			)
		_draw_area.draw_rect(
			Rect2(sw_x - 0.5, sw_y - 0.5, sw_w + 1.0, sw_h + 1.0),
			Color(1, 1, 1, 0.35), false, 1.0
		)
		var ramp_lab := _pack_heat_ramp if not _pack_heat_ramp.is_empty() else "heat"
		_draw_area.draw_string(
			ThemeDB.fallback_font,
			Vector2(sw_x, sw_y + sw_h + 10.0),
			ramp_lab.substr(0, 8),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			8,
			Color(0.85, 0.9, 0.95, 0.85)
		)
		_draw_area.draw_string(
			ThemeDB.fallback_font,
			Vector2(sw_x, sw_y + sw_h + 19.0),
			"click ↻",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			7,
			Color(0.7, 0.78, 0.88, 0.75)
		)
		_heat_swatch_hit = Rect2(sw_x - 2.0, sw_y - 2.0, sw_w + 4.0, sw_h + 22.0)

	# Pass 34/35/47: pack pin legend (bottom-left swatches; opacity scale).
	_pack_legend_hits.clear()
	if _show_pack_legend and not _pack_legend.is_empty() and _pack_legend_opacity > 0.02:
		var lx := r.position.x + 5.0
		var ly := r.position.y + r.size.y - 8.0
		# Stack upward if many slots.
		var row_h := 12.0
		var start_y := ly - float(_pack_legend.size() - 1) * row_h
		var lop := _pack_legend_opacity
		for i in _pack_legend.size():
			var le: Dictionary = _pack_legend[i]
			var col: Color = le.get("color", Color(0.7, 0.85, 1.0, 0.95)) as Color
			col.a = clampf(col.a * lop, 0.0, 1.0)
			var yy := start_y + float(i) * row_h
			_draw_area.draw_circle(Vector2(lx + 3.0, yy - 3.0), 3.0, col)
			_draw_area.draw_arc(
				Vector2(lx + 3.0, yy - 3.0), 4.0, 0.0, TAU, 8,
				Color(1, 1, 1, 0.3 * lop), 0.8
			)
			var lab := str(le.get("label", "P%d" % (int(le.get("slot", 0)) + 1)))
			var nrt := int(le.get("routes", 0))
			var txt := "%s·%d" % [lab.substr(0, 5), nrt] if nrt > 0 else lab.substr(0, 6)
			_draw_area.draw_string(
				ThemeDB.fallback_font,
				Vector2(lx + 9.0, yy),
				txt,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				9,
				Color(col.r, col.g, col.b, 0.92 * lop)
			)
			# Pass 35/36: clickable legend row + tooltip text.
			var hit_rect := Rect2(lx - 1.0, yy - 10.0, 58.0, row_h)
			_pack_legend_hits.append({
				"rect": hit_rect,
				"slot": int(le.get("slot", -1)),
				"label": lab,
				"tooltip": str(le.get("tooltip", "Pack «%s» · click to load" % lab)),
				"routes": nrt,
			})

	# Pass 39/40: risk intensity scale + histogram (bottom-right) when pack pins visible.
	if _show_pack_pins and not _pack_pins.is_empty():
		var bar_w := 56.0
		var bar_h := 6.0
		var bx := r.position.x + r.size.x - bar_w - 8.0
		var by := r.position.y + r.size.y - 28.0
		# Pass 40: 5-bin risk histogram from pin risks.
		var bins := [0, 0, 0, 0, 0]
		var pin_n := 0
		for pin_h in _pack_pins:
			if not pin_h is Dictionary:
				continue
			var rv := clampf(float((pin_h as Dictionary).get("risk", 0.0)), 0.0, 0.999)
			var bi := clampi(int(rv * 5.0), 0, 4)
			bins[bi] = int(bins[bi]) + 1
			pin_n += 1
		var max_bin := 1
		for b in bins:
			max_bin = maxi(max_bin, int(b))
		var hist_h := 14.0
		var hist_y := by - hist_h - 2.0
		# Pass 50: histogram colors follow active heat ramp.
		var hist_ramp: Array = get_pack_heat_ramp_colors()
		var hist_cool: Color = hist_ramp[0] as Color if hist_ramp.size() >= 1 else Color(0.45, 0.9, 1.0)
		var hist_hot: Color = hist_ramp[1] as Color if hist_ramp.size() >= 2 else Color(1.0, 0.28, 0.22)
		for bi2 in 5:
			var t2 := float(bi2) / 4.0
			var col_b := hist_cool.lerp(hist_hot, t2)
			col_b.a = 0.92
			var bw := bar_w / 5.0
			var bh := hist_h * (float(bins[bi2]) / float(max_bin))
			var bx2 := bx + float(bi2) * bw
			_draw_area.draw_rect(Rect2(bx2 + 0.5, hist_y + hist_h - bh, bw - 1.0, maxf(bh, 0.5)), col_b, true)
		_draw_area.draw_string(
			ThemeDB.fallback_font,
			Vector2(bx - 1.0, hist_y - 1.0),
			"hist n=%d" % pin_n,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			7,
			Color(0.8, 0.88, 0.95, 0.8)
		)
		# Gradient strips low→high risk (follow heat ramp).
		var segs := 10
		for s in segs:
			var t := float(s) / float(segs - 1)
			var seg_col := hist_cool.lerp(hist_hot, t)
			seg_col.a = 0.9
			var sx := bx + float(s) * (bar_w / float(segs))
			_draw_area.draw_rect(Rect2(sx, by, bar_w / float(segs) + 0.5, bar_h), seg_col, true)
		_draw_area.draw_rect(Rect2(bx - 0.5, by - 0.5, bar_w + 1.0, bar_h + 1.0), Color(1, 1, 1, 0.25), false, 1.0)
		_draw_area.draw_string(
			ThemeDB.fallback_font,
			Vector2(bx - 1.0, by - 2.0),
			"risk",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			8,
			Color(0.85, 0.9, 0.95, 0.85)
		)
		_draw_area.draw_string(
			ThemeDB.fallback_font,
			Vector2(bx, by + bar_h + 9.0),
			"lo",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			7,
			Color(0.55, 0.85, 0.95, 0.8)
		)
		_draw_area.draw_string(
			ThemeDB.fallback_font,
			Vector2(bx + bar_w - 12.0, by + bar_h + 9.0),
			"hi",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			7,
			Color(1.0, 0.45, 0.35, 0.85)
		)


func _on_minimap_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = _draw_area.get_local_mouse_position()
		var r := _draw_area.get_rect()
		var xf := _minimap_transform(r)
		# Pass 51: click heat swatch → cycle ramp (Shift = reverse).
		if _show_heat_ramp_legend and _heat_swatch_hit.size.x > 1.0 and _heat_swatch_hit.has_point(local):
			var dir := -1 if Input.is_key_pressed(KEY_SHIFT) else 1
			var nxt := ""
			if _map_renderer != null and _map_renderer.has_method("cycle_pack_heat_ramp"):
				nxt = str(_map_renderer.call("cycle_pack_heat_ramp", dir))
			else:
				# Local fallback cycle.
				var ramps := ["classic", "inferno", "viridis", "mono", "custom"]
				var ix := ramps.find(_pack_heat_ramp)
				if ix < 0:
					ix = 0
				ix = posmod(ix + dir, ramps.size())
				set_pack_heat_ramp(str(ramps[ix]))
				nxt = _pack_heat_ramp
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Heat ramp · %s" % nxt)
			_draw_area.queue_redraw()
			return
		# Pass 35: legend click → load slot (before free pan / pins for bottom area).
		if _show_pack_legend and _try_activate_pack_legend(local):
			_draw_area.queue_redraw()
			return
		# Pass 30: pack slot pin → load pack.
		if _show_pack_pins and _try_activate_pack_pin(local, xf):
			_draw_area.queue_redraw()
			return
		# Pass 23: munitions depot hit-test before convoy / free pan.
		if _show_munitions_pips and _try_focus_munitions_pip(local, xf):
			_draw_area.queue_redraw()
			return
		# Pass 17: convoy pip hit-test before free pan.
		if _show_convoy_pips and _try_focus_convoy_pip(local, xf):
			_draw_area.queue_redraw()
			return
		var wx: float = (local.x - float(xf["ox"])) / float(xf["s"])
		var wy: float = (local.y - float(xf["oy"])) / float(xf["s"])
		_camera.global_position = Vector2(wx, wy)
		_draw_area.queue_redraw()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# Pass 36/37: legend + pin hover tooltips (when not dragging pan).
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_update_pack_legend_tooltip(motion.position)
		elif motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_on_minimap_input(InputEventMouseButton.new())


## Pass 36/37: hover minimap legend or pack pin → tooltip on control.
func _update_pack_legend_tooltip(local: Vector2) -> void:
	# Pass 37: pin hover first (higher priority when overlapping legend).
	if _show_pack_pins and not _pack_pins.is_empty() and _draw_area:
		var r := _draw_area.get_rect()
		var xf := _minimap_transform(r)
		var best_i := -1
		var best_d := PACK_PIN_HIT_PX * PACK_PIN_HIT_PX
		for i in _pack_pins.size():
			var entry_p: Dictionary = _pack_pins[i]
			var mp := _world_to_minimap(entry_p.get("pos", Vector2.ZERO) as Vector2, xf)
			var d := local.distance_squared_to(mp)
			if d <= best_d:
				best_d = d
				best_i = i
		if best_i >= 0:
			var pe: Dictionary = _pack_pins[best_i]
			var tip_p := str(pe.get("tooltip", ""))
			if tip_p.is_empty():
				tip_p = "Pack «%s» · click to load" % str(pe.get("label", "?"))
			_draw_area.tooltip_text = tip_p
			return
	if not _show_pack_legend or _pack_legend_hits.is_empty():
		if _draw_area and not _draw_area.tooltip_text.is_empty():
			_draw_area.tooltip_text = ""
		return
	for i in range(_pack_legend_hits.size() - 1, -1, -1):
		var entry: Dictionary = _pack_legend_hits[i]
		var hr: Rect2 = entry.get("rect", Rect2()) as Rect2
		if hr.has_point(local):
			var tip := str(entry.get("tooltip", ""))
			if tip.is_empty():
				tip = "Pack «%s» · click to load" % str(entry.get("label", "?"))
			if _draw_area:
				_draw_area.tooltip_text = tip
			return
	if _draw_area:
		_draw_area.tooltip_text = ""


## Pass 35: click legend swatch/label → load that pack slot.
func _try_activate_pack_legend(local: Vector2) -> bool:
	if _pack_legend_hits.is_empty():
		return false
	# Reverse so topmost (later) entries win if overlapping.
	for i in range(_pack_legend_hits.size() - 1, -1, -1):
		var entry: Dictionary = _pack_legend_hits[i]
		var hr: Rect2 = entry.get("rect", Rect2()) as Rect2
		if hr.has_point(local):
			var slot := int(entry.get("slot", -1))
			if slot >= 0 and _map_renderer != null and _map_renderer.has_method("load_route_compare_slot"):
				_map_renderer.call("load_route_compare_slot", slot)
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Legend · loaded «%s»" % str(entry.get("label", slot + 1)))
				return true
	return false


## Pass 30/33: click pack pin or polyline → load that slot's compare pack.
func _try_activate_pack_pin(local: Vector2, xf: Dictionary) -> bool:
	if _pack_pins.is_empty():
		return false
	var best_i := -1
	var best_d := PACK_PIN_HIT_PX * PACK_PIN_HIT_PX
	for i in _pack_pins.size():
		var entry: Dictionary = _pack_pins[i]
		var mp := _world_to_minimap(entry.get("pos", Vector2.ZERO) as Vector2, xf)
		var d := local.distance_squared_to(mp)
		if d <= best_d:
			best_d = d
			best_i = i
	# Pass 33: if no pin hit, try nearest polyline segment.
	if best_i < 0:
		var poly_i := _nearest_pack_polyline_index(local, xf)
		if poly_i >= 0:
			best_i = poly_i
	if best_i < 0:
		return false
	var hit: Dictionary = _pack_pins[best_i]
	var slot := int(hit.get("slot", -1))
	if slot >= 0 and _map_renderer != null and _map_renderer.has_method("load_route_compare_slot"):
		_map_renderer.call("load_route_compare_slot", slot)
		if typeof(DebugOverlay) != TYPE_NIL:
			var via := "polyline" if best_d > PACK_PIN_HIT_PX * PACK_PIN_HIT_PX else "pin"
			DebugOverlay.toast_map_debug("Pack %s · loaded «%s»" % [via, str(hit.get("label", slot + 1))])
		return true
	var focus_pid := int(hit.get("focus_pid", -1))
	if focus_pid >= 0 and _map_renderer != null and _map_renderer.has_method("focus_province_by_id"):
		_map_renderer.call("focus_province_by_id", focus_pid)
		return true
	return false


## Pass 33: index of pack pin whose polyline is closest to local point, or -1.
func _nearest_pack_polyline_index(local: Vector2, xf: Dictionary) -> int:
	var best_i := -1
	var best_d := PACK_POLY_HIT_PX * PACK_POLY_HIT_PX
	for i in _pack_pins.size():
		var entry: Dictionary = _pack_pins[i]
		var poly_raw = entry.get("polyline", [])
		if not (poly_raw is Array) or (poly_raw as Array).size() < 2:
			continue
		var prev := Vector2.INF
		for pt in poly_raw:
			if not (pt is Vector2):
				continue
			var mp := _world_to_minimap(pt as Vector2, xf)
			if prev != Vector2.INF:
				var d := _point_seg_dist_sq(local, prev, mp)
				if d <= best_d:
					best_d = d
					best_i = i
			prev = mp
	return best_i


## Pass 33: squared distance from point p to segment ab.
func _point_seg_dist_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var proj := a + ab * t
	return p.distance_squared_to(proj)


## Pass 23: click nearest munitions depot pip → focus province.
func _try_focus_munitions_pip(local: Vector2, xf: Dictionary) -> bool:
	if _munitions_pips.is_empty():
		_ensure_munitions_pips()
	if _munitions_pips.is_empty():
		return false
	var best_i := -1
	var best_d := MUNITIONS_PIP_HIT_PX * MUNITIONS_PIP_HIT_PX
	for i in _munitions_pips.size():
		var entry: Dictionary = _munitions_pips[i]
		var mp := _world_to_minimap(entry["pos"] as Vector2, xf)
		var d := local.distance_squared_to(mp)
		if d <= best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return false
	var hit: Dictionary = _munitions_pips[best_i]
	var focus_pid := int(hit.get("focus_pid", -1))
	var ratio := float(hit.get("ratio", 0.0))
	if focus_pid >= 0 and _map_renderer != null and _map_renderer.has_method("focus_province_by_id"):
		_map_renderer.call("focus_province_by_id", focus_pid)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Munitions depot · P%d · %.0f%% fill" % [focus_pid, ratio * 100.0])
	return true


## Pass 17/18: click nearest convoy pip → focus; double-click → highlight full route.
func _try_focus_convoy_pip(local: Vector2, xf: Dictionary) -> bool:
	if _convoy_pips.is_empty():
		_ensure_convoy_pips()
	if _convoy_pips.is_empty():
		return false
	var best_i := -1
	var best_d := CONVOY_PIP_HIT_PX * CONVOY_PIP_HIT_PX
	for i in _convoy_pips.size():
		var entry: Dictionary = _convoy_pips[i]
		var mp := _world_to_minimap(entry["pos"] as Vector2, xf)
		var d := local.distance_squared_to(mp)
		if d <= best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return false
	var hit: Dictionary = _convoy_pips[best_i]
	var focus_pid := int(hit.get("focus_pid", -1))
	var world_pos: Vector2 = hit.get("pos", Vector2.ZERO) as Vector2
	var now_ms := Time.get_ticks_msec()
	var is_double := (best_i == _last_pip_index and (now_ms - _last_pip_click_ms) <= DOUBLE_CLICK_MS)
	_last_pip_click_ms = now_ms
	_last_pip_index = best_i
	var path: Array = hit.get("path", []) as Array if hit.get("path") is Array else []
	if path.is_empty() and focus_pid >= 0:
		path = [focus_pid]
	var meta := {"interdiction": float(hit.get("interdiction", 0.0)), "focus_pid": focus_pid}
	# Pass 19/26/27: Shift+click A → B → C → D pack.
	if Input.is_key_pressed(KEY_SHIFT):
		if _compare_path_a.is_empty():
			_compare_path_a = path.duplicate()
			_compare_meta_a = meta.duplicate()
			_compare_path_b.clear()
			_compare_meta_b.clear()
			_compare_path_c.clear()
			_compare_meta_c.clear()
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Route A locked · Shift+click B (C/D optional)")
		elif _compare_path_b.is_empty():
			_compare_path_b = path.duplicate()
			_compare_meta_b = meta.duplicate()
			# Immediately compare A/B; further Shift+clicks upgrade to C then D.
			if _map_renderer != null and _map_renderer.has_method("compare_supply_routes_multi"):
				_map_renderer.call("compare_supply_routes_multi",
					[_compare_path_a, _compare_path_b], [_compare_meta_a, _compare_meta_b])
			elif _map_renderer != null and _map_renderer.has_method("compare_supply_routes"):
				_map_renderer.call("compare_supply_routes", _compare_path_a, path, _compare_meta_a, meta)
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("A/B compare · Shift+click C (amber) or D pack")
		elif _compare_path_c.is_empty():
			_compare_path_c = path.duplicate()
			_compare_meta_c = meta.duplicate()
			if _map_renderer != null and _map_renderer.has_method("compare_supply_routes_multi"):
				_map_renderer.call("compare_supply_routes_multi",
					[_compare_path_a, _compare_path_b, _compare_path_c],
					[_compare_meta_a, _compare_meta_b, _compare_meta_c])
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("A/B/C compare · Shift+click D (green) for four-route pack")
		else:
			# Route D — four-route pack, then clear.
			if _map_renderer != null and _map_renderer.has_method("compare_supply_routes_multi"):
				_map_renderer.call("compare_supply_routes_multi",
					[_compare_path_a, _compare_path_b, _compare_path_c, path],
					[_compare_meta_a, _compare_meta_b, _compare_meta_c, meta])
			_compare_path_a.clear()
			_compare_meta_a.clear()
			_compare_path_b.clear()
			_compare_meta_b.clear()
			_compare_path_c.clear()
			_compare_meta_c.clear()
		if focus_pid >= 0 and _map_renderer != null and _map_renderer.has_method("focus_province_by_id"):
			_map_renderer.call("focus_province_by_id", focus_pid)
		return true
	if is_double:
		# Pass 18: double-click highlights entire route polyline on map.
		if _map_renderer != null and _map_renderer.has_method("highlight_supply_route_path"):
			_map_renderer.call("highlight_supply_route_path", path, 4.5)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"Route highlight · %d hops · risk %.0f%%" % [path.size(), float(hit.get("interdiction", 0.0)) * 100.0]
			)
		# Still focus target.
		if focus_pid >= 0 and _map_renderer != null and _map_renderer.has_method("focus_province_by_id"):
			_map_renderer.call("focus_province_by_id", focus_pid)
		return true
	if focus_pid >= 0 and _map_renderer != null:
		if _map_renderer.has_method("focus_province_by_id"):
			_map_renderer.call("focus_province_by_id", focus_pid)
		elif "province_centroids" in _map_renderer:
			var cents: Dictionary = _map_renderer.province_centroids
			if cents.has(focus_pid):
				_camera.global_position = cents[focus_pid] as Vector2
			else:
				_camera.global_position = world_pos
		else:
			_camera.global_position = world_pos
	else:
		_camera.global_position = world_pos
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(
			"Convoy focus · pid %d · risk %.0f%% · dbl-click highlight" % [focus_pid, float(hit.get("interdiction", 0.0)) * 100.0]
		)
	return true


func _process(_delta: float) -> void:
	if _draw_area != null and _camera != null:
		_draw_area.queue_redraw()
