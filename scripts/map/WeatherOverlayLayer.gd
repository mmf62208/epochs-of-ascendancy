# scripts/map/WeatherOverlayLayer.gd
# Cheap weather visuals layer (snow, rain, storm, fog, event cues) on top of the grand strategy bg image.
# Modeled after InfrastructureOverlayLayer for culling, toggles, signals.
# Most of the system is "hidden" — this layer is the player-visible part + basic info.
# Not laggy: culls to visible provinces, simple overlays or modulates, updates on weather signals only.

extends Node2D

var map_renderer: Node = null
var map_manager: Node = null
var weather_manager: Node = null

var snow_layer: Node2D = null
var event_layer: Node2D = null

var show_weather: bool = false  # toggled by player / debug / hotkey (default off for clean 1930s view)

func _ready() -> void:
	name = "WeatherOverlayLayer"
	add_to_group("weather_overlay")
	map_renderer = get_parent()  # assume under MapRenderer or container
	if typeof(MapManager) != TYPE_NIL:
		map_manager = MapManager
	var wm = get_node_or_null("/root/WeatherManager")
	if wm:
		weather_manager = wm
		if weather_manager.has_signal("weather_changed"):
			weather_manager.weather_changed.connect(_on_weather_changed)
	_ensure_layers()
	print("WeatherOverlayLayer ready (stub — snow progression + event cues on grand theater map)")
	if show_weather:
		call_deferred("rebuild_weather_visuals")

func _ensure_layers() -> void:
	if snow_layer == null:
		snow_layer = Node2D.new()
		snow_layer.name = "SnowLayer"
		add_child(snow_layer)
	if event_layer == null:
		event_layer = Node2D.new()
		event_layer.name = "EventLayer"
		add_child(event_layer)

func set_show_weather(v: bool) -> void:
	show_weather = v
	visible = show_weather
	if show_weather:
		rebuild_weather_visuals()

func rebuild_weather_visuals() -> void:
	if not show_weather or weather_manager == null:
		# reset main bg when layer off
		var bg := map_renderer.find_child("WorldBackground", true, false) as Sprite2D if map_renderer else null
		if bg and bg.texture:
			bg.modulate = Color(0.92, 0.90, 0.85, 0.92)
		return
	# Cull to visible like infra layer (reuse or simple)
	_clear_layer(snow_layer)
	# Use data from WeatherManager for progressive snow on GRAND THEATER (UK/Scand/N Russia high north get more).
	# For altitude: if high_ground_fraction, show extra cap or higher opacity.
	# This is cheap: one or few rects or modulate; real would use a mask texture or shader on bg.
	if map_renderer and map_renderer.has_method("get_rendered_province_bounds"):
		var b = map_renderer.get_rendered_province_bounds()
		# Northern snow veil (progresses via manager _simulate_day with lat/season + high ground)
		var snow_opacity = 0.28
		# If manager has data for seeded northern pids, average the snow_coverage for dynamic opacity
		if weather_manager and weather_manager.has_method("get_aggregate_snow_coverage"):
			var avg = weather_manager.get_aggregate_snow_coverage()
			snow_opacity = clamp(0.15 + avg * 0.6, 0.15, 0.75)
		var snow_rect := ColorRect.new()
		snow_rect.color = Color(0.95, 0.97, 1.0, snow_opacity * 0.4)  # light veil for snow on the high-res map
		snow_rect.size = b.size  # full coverage for the grand theater area (high res map supports close zoom)
		snow_rect.position = b.position
		snow_layer.add_child(snow_rect)

		# Make snow affect the *appropriate layer* -- the main WorldBackground (the high-quality larger detailed stylized grand map image, the one requested for up quality and close zoom).
		# Modulate it with snow tint so the terrain/rivers/hills get winter look dynamically on the high-res map. This is the "winter thing" on the map layer (works great with the larger image for close views).
		var bg := map_renderer.find_child("WorldBackground", true, false) as Sprite2D if map_renderer else null
		if bg and bg.texture and (map_renderer == null or map_renderer.get("show_terrain_layer") != false):
			var base_mod = Color(0.92, 0.90, 0.85, 0.92)
			var snow_tint = Color(0.95, 0.97, 1.0, 0.95)
			bg.modulate = base_mod.lerp(snow_tint, snow_opacity * 0.7)  # stronger snow on the main high-res detailed image (skipped if terrain layer off for clean view)

		# Note: high ground % within province is handled in WeatherManager impacts (e.g. movement scaled by fraction) not full province punish
		print("WeatherOverlay: snow visual rebuilt from manager data (progressing north + mountains; % territory high ground handled in impacts); snow modulates the main detailed map bg")

		# Demo power blackout visual (dim overlay for provinces with low power from EMP/nuke/espionage/solar/atmospheric)
		# Real: per province mask or tint on affected; power loss affects surrounding via grid (see WeatherManager.cause_blackout)
		# Also naval: sea state impacts surface naval and carrier air ops (see manager get_naval... and get_carrier_air...)
		_clear_layer(event_layer)  # reuse for power too
		if weather_manager and weather_manager.has_method("get_power_availability"):
			# For seeded demo, assume some blackout impact; in full query pids
			var pwr = weather_manager.get_power_availability(999)  # northern demo
			if pwr < 0.5:
				var dim := ColorRect.new()
				dim.color = Color(0.1, 0.1, 0.15, 0.4)  # blackout dim / lights out
				dim.size = Vector2(b.size.x * 0.3, b.size.y * 0.3)
				dim.position = b.position + Vector2(b.size.x * 0.1, b.size.y * 0.1)
				event_layer.add_child(dim)
				print("WeatherOverlay: blackout/power loss visual (EMP, nuke atmo, espionage, solar flare equiv - affects province + surrounding power); naval weather impacts also modeled in manager")

func _clear_layer(parent: Node) -> void:
	for c in parent.get_children():
		c.queue_free()

func _on_weather_changed(pid: int, changes: Dictionary) -> void:
	if show_weather:
		# Rebuild only affected / visible (future: smarter dirty list)
		rebuild_weather_visuals()

func toggle() -> void:
	set_show_weather(not show_weather)

# Called from MapRenderer on phase1 bg apply or render so the layer sits on the new larger scope image.
func refresh_for_grand_theater() -> void:
	if show_weather:
		rebuild_weather_visuals()
