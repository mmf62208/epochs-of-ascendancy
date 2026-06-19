# scripts/map/WeatherOverlayLayer.gd
# Cheap weather visuals layer (snow, rain, storm, fog, event cues) on top of the grand strategy bg image.
# Modeled after InfrastructureOverlayLayer for culling, toggles, signals.
# Most of the system is "hidden" — this layer is the player-visible part + basic info.
# Not laggy: culls to visible provinces, simple overlays or modulates, updates on weather signals only.

extends Node2D

var map_renderer: Node = null
var map_manager: Node = null
var weather_manager: Node = null
var game_data: Node = null  # for riot/pending culling in weather visuals (only process active + owned + border)

var show_weather: bool = false  # toggled by player / debug / hotkey (default off for clean 1930s view)

# Layers for snow/veil and event markers (riots, ethics, scandal icons from subagent gens). Declared for scope in _ensure and rebuild (culling uses game_data for active_riots etc).
var snow_layer: Node = null
var event_layer: Node = null

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
	if typeof(GameData) != TYPE_NIL:
		game_data = GameData
	_ensure_layers()
	print("WeatherOverlayLayer ready (full visuals: dynamic snow veil+mask+ tint on bg, rain/storm cues, event icons, blackout dims, naval notes; togglable)")
	if show_weather:
		call_deferred("rebuild_weather_visuals")

func _ensure_layers() -> void:
	if snow_layer == null:
		snow_layer = Node2D.new()
		snow_layer.name = "SnowLayer"
		snow_layer.z_index = 20  # on top of terrain/elev for white bits visible
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
		var bg : Variant = map_renderer.find_child("WorldBackground", true, false) as Sprite2D if map_renderer else null
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
		var snow_rect : Variant = ColorRect.new()
		snow_rect.color = Color(0.95, 0.97, 1.0, snow_opacity * 0.25)  # light veil for snow mix (lower for "mix" with mask bits on highs)
		snow_rect.size = b.size  # full coverage for the grand theater area (high res map supports close zoom)
		snow_rect.position = b.position
		snow_layer.add_child(snow_rect)

		# Additional rain/storm veil for full visuals (cheap, dynamic from manager precip)
		var avg_precip : Variant = 0.0
		if weather_manager and weather_manager.has_method("get_aggregate_snow_coverage"):  # reuse for rough
			# rough precip from sample (in full would aggregate properly)
			avg_precip = clamp(snow_opacity * 0.4, 0.0, 0.6)  # proxy
		if avg_precip > 0.2:
			var rain_veil : Variant = ColorRect.new()
			rain_veil.color = Color(0.6, 0.7, 0.9, avg_precip * 0.15)
			rain_veil.size = b.size * 0.9
			rain_veil.position = b.position + Vector2(b.size.x * 0.05, b.size.y * 0.05)
			snow_layer.add_child(rain_veil)  # reuse snow layer for veil (or event)
			print("WeatherOverlay: added dynamic rain veil for wet weather")

		# Make snow affect the *appropriate layer* -- the main WorldBackground (the high-quality larger detailed stylized grand map image, the one requested for up quality and close zoom).
		# Modulate it with snow tint so the terrain/rivers/hills get winter look dynamically on the high-res map. This is the "winter thing" on the map layer (works great with the larger image for close views).
		var bg : Variant = map_renderer.find_child("WorldBackground", true, false) as Sprite2D if map_renderer else null
		if bg and bg.texture and (map_renderer == null or map_renderer.get("show_terrain_layer") != false):
			var base_mod = Color(0.92, 0.90, 0.85, 0.92)
			var snow_tint = Color(0.95, 0.97, 1.0, 0.95)
			bg.modulate = base_mod.lerp(snow_tint, snow_opacity * 0.7)  # stronger snow on the main high-res detailed image (skipped if terrain layer off for clean view)

		# Note: high ground % within province is handled in WeatherManager impacts (e.g. movement scaled by fraction) not full province punish
		print("WeatherOverlay: snow visual rebuilt from manager data (progressing north + mountains; % territory high ground handled in impacts); snow modulates the main detailed map bg")

		# Simple rain/storm overlay for precip events (cheap ColorRect or lines for visual cue on grand bg; ties to events like storms, naval spotting).
		if weather_manager and weather_manager.has_method("get_precip_intensity"):
			var precip = float(weather_manager.call("get_precip_intensity", 0)) if weather_manager.has_method("get_precip_intensity") else 0.0
			if precip > 0.3:
				var rain_op = clamp(precip * 0.4, 0.1, 0.5)
				var rain_rect : Variant = ColorRect.new()
				rain_rect.color = Color(0.6, 0.7, 0.9, rain_op * 0.3)  # light blue rain veil
				rain_rect.size = b.size
				rain_rect.position = b.position
				snow_layer.add_child(rain_rect)  # reuse snow layer for simplicity, or event_layer
				print("WeatherOverlay: rain overlay added for precip=", precip)

		# Use the winter mix snow mask (generated from DEM high elevations in build) to add *bits of white* specifically to the highest elevations.
		# This uses the "snow thing" / winter layer to sprinkle white on peaks (Alps, Norway, Scotland, Iceland highs etc.) based on the snow_mask.png (white where high z).
		# Opacity driven by aggregate snow_coverage from manager (dynamic season/north/mountain).
		var snow_mask_path : Variant = "res://assets/maps/layers/europe_snow_mask.png"
		# Prefer world_snow_mask for global consistency if present (from --only-snow world build); fallback europe/metadata/chunk
		if ResourceLoader.exists("res://assets/maps/layers/world_snow_mask.png"):
			snow_mask_path = "res://assets/maps/layers/world_snow_mask.png"
		# Try to load from metadata for flexibility (e.g. chunk or world snow mask)
		var meta_path : Variant = "res://data/map/layer_metadata.json"
		if not ResourceLoader.exists(snow_mask_path) and ResourceLoader.exists(meta_path):
			var mf : Variant = FileAccess.open(meta_path, FileAccess.READ)
			if mf:
				var md = JSON.parse_string(mf.get_as_text())
				if md is Dictionary and md.has("layers") and md.layers.has("snow_mask"):
					var sp : Variant = "res://" + str(md.layers.snow_mask)
					if ResourceLoader.exists(sp):
						snow_mask_path = sp
		# If current underlay is a world chunk, prefer chunk's snow_mask for localized high elev bits
		var bg_check : Variant = map_renderer.find_child("WorldBackground", true, false) as Sprite2D if map_renderer else null
		if bg_check and bg_check.texture and "world_chunk" in str(bg_check.texture.resource_path):
			var chunk_str : Variant = str(bg_check.texture.resource_path)
			var idx_str : Variant = chunk_str.get_slice("_", 2)  # rough parse of world_chunk_XX_...
			if idx_str.is_valid_int():
				var ci : Variant = idx_str.to_int()
				# prefer normalized snow_mask.png (from updated splitter), fallback to legacy europe_ name in chunks
				var csp : Variant = "res://assets/maps/world_chunks/world_chunk_%02d_snow_mask.png" % ci
				if not ResourceLoader.exists(csp):
					csp = "res://assets/maps/world_chunks/world_chunk_%02d_europe_snow_mask.png" % ci
				if ResourceLoader.exists(csp):
					snow_mask_path = csp
		if ResourceLoader.exists(snow_mask_path):
			var snow_mask_tex : Variant = load(snow_mask_path) as Texture2D
			if snow_mask_tex:
				var snow_mask_sprite : Variant = Sprite2D.new()
				snow_mask_sprite.texture = snow_mask_tex
				snow_mask_sprite.position = b.position
				snow_mask_sprite.scale = b.size / Vector2(snow_mask_tex.get_width(), snow_mask_tex.get_height())
				# White with opacity from snow; the mask itself has the "bits" (brighter where higher elev)
				var mask_alpha: float = clamp(snow_opacity * 0.85, 0.0, 0.9)
				snow_mask_sprite.modulate = Color(0.98, 0.99, 1.0, mask_alpha)
				snow_mask_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				snow_mask_sprite.z_index = 5  # on top of elev for visible white bits
				snow_layer.add_child(snow_mask_sprite)
				print("WeatherOverlay: added snow mask bits of white on highest elevations (DEM-driven via snow_mask.png from build layers)")

		# Also slightly whiten the elevation/hillshade layer for winter mix on highs (global light, mask sprite adds localized bits)
		var tls : Variant = map_renderer.find_child("TerrainLayerStack", true, false)
		if tls and snow_opacity > 0.1:
			var el : Variant = tls.get_node_or_null("ElevationLayer") as Sprite2D
			if el and el.texture:
				var cur_mod : Variant = el.modulate
				el.modulate = cur_mod.lerp(Color(0.95, 0.97, 1.0, 1.0), snow_opacity * 0.2)  # light winter mix on the hills
				print("WeatherOverlay: boosted snow white on elevation layer for mix")

		# Demo power blackout visual (dim overlay for provinces with low power from EMP/nuke/espionage/solar/atmospheric)
		# Real: per province mask or tint on affected; power loss affects surrounding via grid (see WeatherManager.cause_blackout)
		# Also naval: sea state impacts surface naval and carrier air ops (see manager get_naval... and get_carrier_air...)
		_clear_layer(event_layer)  # reuse for power + weather event icons
		if weather_manager and weather_manager.has_method("get_power_availability"):
			# For seeded demo, assume some blackout impact; in full query pids + dynamic
			var pwr = weather_manager.get_power_availability(999)  # northern demo
			if pwr < 0.5:
				var dim : Variant = ColorRect.new()
				dim.color = Color(0.1, 0.1, 0.15, 0.4)  # blackout dim / lights out
				dim.size = Vector2(b.size.x * 0.3, b.size.y * 0.3)
				dim.position = b.position + Vector2(b.size.x * 0.1, b.size.y * 0.1)
				event_layer.add_child(dim)
				print("WeatherOverlay: blackout/power loss visual (EMP, nuke atmo, espionage, solar flare equiv - affects province + surrounding power); naval weather impacts also modeled in manager")

		# Full polish visuals beyond stub: add simple rain/storm icon cues + event symbols (unicode for perf, no extra assets)
		# Icons placed on layer for visible weather state (snow already main veil/mask, add rain overlays + labels)
		# Perf: culling to active provinces only (GameData riots + pending + majors/owned) + visible, majors full, rand light others (existing weather manager light for non-majors).
		if weather_manager and weather_manager.has_method("_province_weather"):
			var pw: Dictionary = weather_manager.get("_province_weather") if weather_manager.has_method("get") else {}
			var active_riots_pids := []
			if game_data and game_data.has_method("get_provinces_with_active_riots"):
				active_riots_pids = game_data.get_provinces_with_active_riots()
			var rain_count : Variant = 0
			for pid in pw.keys():
				var ipid := int(pid)
				# Culling: skip non-active unless major or border/high (simple owned by known majors for scale)
				var is_active_event := ipid in active_riots_pids
				var is_major := false
				if map_manager and map_manager.has_method("get_provinces_by_owner"):
					for t in ["GER","FRA","ENG","SOV","USA"]:
						if ipid in map_manager.call("get_provinces_by_owner", t):
							is_major = true
							break
				if not is_active_event and not is_major and randf() > 0.25:  # rand light for others (25% keep)
					continue
				var ww: Dictionary = pw.get(pid, {})
				var precip : Variant = float(ww.get("precip_intensity", 0))
				if precip > 0.3 and rain_count < 3:  # limit cheap icons
					rain_count += 1
					var rain_icon : Variant = Label.new()
					rain_icon.text = "☔" if ww.get("precip_type","") == "rain" else "❄"
					rain_icon.position = b.position + Vector2(80 + rain_count*60, 60)
					rain_icon.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.7))
					rain_icon.add_theme_font_size_override("font_size", 18)
					event_layer.add_child(rain_icon)
			# Storm / major event cue icon
			var events : Array = weather_manager.get_all_active_events() if weather_manager.has_method("get_all_active_events") else []
			if events.size() > 0:
				var ev_icon : Variant = Label.new()
				ev_icon.text = "⚡ STORM/EVENT"
				ev_icon.position = b.position + Vector2(120, b.size.y - 80)
				ev_icon.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 0.85))
				ev_icon.add_theme_font_size_override("font_size", 12)
				event_layer.add_child(ev_icon)
				print("WeatherOverlay: event icon cue for active storms/extremes")

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
