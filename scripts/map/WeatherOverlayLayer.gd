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
## Pass 11: lightweight animated particles for weather mapmode (independent of full veil).
var particle_mode: bool = false
## Pass 14: when non-empty, only spawn particles matching this ground key (dry|mud|snow|storm).
var particle_ground_filter: String = ""
var _particles: Array = []  # {pos: Vector2, vel: Vector2, life: float, kind: String}
var _particle_bounds: Rect2 = Rect2()
var _particle_seed_t: float = 0.0
const PARTICLE_MAX := 120

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
	set_process(true)
	print("WeatherOverlayLayer ready (full visuals: dynamic snow veil+mask+ tint on bg, rain/storm cues, event icons, blackout dims, naval notes; togglable)")
	if show_weather:
		call_deferred("rebuild_weather_visuals")


## Pass 11: enable cheap snow/rain/storm particle field (weather mapmode).
func set_particle_mode(enable: bool) -> void:
	particle_mode = enable
	if enable:
		visible = true
		_seed_particles()
	else:
		_particles.clear()
		# Keep full weather layer visible only if player toggled show_weather.
		if not show_weather:
			# Do not hide whole layer if show_weather was never on — particle-only visibility.
			queue_redraw()
	queue_redraw()


## Pass 14: sync with MapModeToolbar Wx filter (empty = all states).
func set_particle_ground_filter(key: String) -> void:
	var k := key.strip_edges().to_lower()
	if k in ["dry", "mud", "snow", "storm"]:
		particle_ground_filter = k
	else:
		particle_ground_filter = ""
	if particle_mode:
		_seed_particles()
		queue_redraw()

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


func _on_weather_changed(_pid: int, _changes: Dictionary) -> void:
	if show_weather:
		# Rebuild only affected / visible (future: smarter dirty list)
		rebuild_weather_visuals()

func toggle() -> void:
	set_show_weather(not show_weather)

# Called from MapRenderer on phase1 bg apply or render so the layer sits on the new larger scope image.
func refresh_for_grand_theater() -> void:
	if show_weather:
		rebuild_weather_visuals()
	if particle_mode:
		_seed_particles()


func _process(delta: float) -> void:
	if not particle_mode:
		return
	if _particles.is_empty():
		_seed_particles()
		if _particles.is_empty():
			return
	_update_particles(delta)
	queue_redraw()


func _seed_particles() -> void:
	_particles.clear()
	var b := Rect2(Vector2.ZERO, Vector2(2000, 1200))
	if map_renderer and map_renderer.has_method("get_rendered_province_bounds"):
		var rb = map_renderer.get_rendered_province_bounds()
		if rb is Rect2 and rb.size.x > 10.0:
			b = rb
	_particle_bounds = b
	# Pass 12: seed density from province weather centroids when available.
	var seeded := _seed_particles_per_province()
	if seeded > 0:
		return
	# Fallback: global field by dominant kind (or forced filter).
	var kind := _dominant_particle_kind()
	var filt := particle_ground_filter.strip_edges().to_lower()
	if not filt.is_empty():
		kind = filt if filt != "mud" else "rain"
	var n := PARTICLE_MAX
	if kind == "dry":
		n = 24
	elif kind == "mud" or kind == "rain":
		n = 48
	elif kind == "storm":
		n = PARTICLE_MAX
	else:
		n = 80
	if not filt.is_empty():
		n = mini(PARTICLE_MAX, n + 24)
	for i in n:
		_particles.append(_make_particle(kind, true))


## Pass 12: place particle clusters near province centroids by ground_state / precip.
func _seed_particles_per_province() -> int:
	if weather_manager == null or not weather_manager.has_method("get_province_weather"):
		return 0
	var centroids: Dictionary = {}
	if map_renderer != null and "province_centroids" in map_renderer:
		centroids = map_renderer.province_centroids
	if centroids.is_empty():
		return 0
	var count := 0
	var keys: Array = centroids.keys()
	# Cap how many provinces we sample for perf on world_full.
	var step := 1
	if keys.size() > 400:
		step = maxi(1, int(keys.size() / 120))
	elif keys.size() > 120:
		step = maxi(1, int(keys.size() / 80))
	var idx := 0
	while idx < keys.size() and count < PARTICLE_MAX:
		var pid_v = keys[idx]
		idx += step
		var pid := int(pid_v)
		var ctr: Vector2 = centroids[pid_v] as Vector2
		if ctr == Vector2.ZERO:
			continue
		var w: Variant = weather_manager.call("get_province_weather", pid)
		if not (w is Dictionary):
			continue
		var wd: Dictionary = w
		var g := str(wd.get("ground_state", "dry")).to_lower()
		var precip := float(wd.get("precip_intensity", 0.0))
		var kind := "dry"
		var local_n := 1
		if precip >= 0.55 or "storm" in g:
			kind = "storm"
			local_n = 4
		elif "snow" in g or g in ["frozen", "ice"]:
			kind = "snow"
			local_n = 3
		elif "mud" in g or g in ["wet", "muddy"]:
			kind = "rain"
			local_n = 2
		else:
			kind = "dry"
			local_n = 1
			# Skip most dry provinces to keep density on interesting weather.
			if randf() > 0.12:
				continue
		# Pass 14: honor legend filter (rain maps to mud).
		var filt := particle_ground_filter.strip_edges().to_lower()
		if not filt.is_empty():
			var match_key := kind
			if kind == "rain":
				match_key = "mud"
			if match_key != filt:
				continue
			# Filtered view: denser clusters for the selected state.
			local_n = maxi(local_n, 3)
		var radius := 28.0 + local_n * 8.0
		for j in local_n:
			if count >= PARTICLE_MAX:
				break
			var offset := Vector2(randf_range(-radius, radius), randf_range(-radius, radius))
			_particles.append(_make_particle_at(kind, ctr + offset, true))
			count += 1
	return count


func _dominant_particle_kind() -> String:
	if weather_manager == null:
		return "snow"
	if weather_manager.has_method("get_aggregate_snow_coverage"):
		var snow := float(weather_manager.get_aggregate_snow_coverage())
		if snow > 0.35:
			return "snow"
	# Sample a few weather dicts if available.
	if weather_manager.has_method("get_province_weather"):
		var storm_n := 0
		var mud_n := 0
		var snow_n := 0
		for sample_pid in [1, 50, 100, 200, 500]:
			var w: Variant = weather_manager.call("get_province_weather", sample_pid)
			if w is Dictionary:
				var g := str(w.get("ground_state", "dry")).to_lower()
				var p := float(w.get("precip_intensity", 0.0))
				if p >= 0.55 or "storm" in g:
					storm_n += 1
				elif "mud" in g:
					mud_n += 1
				elif "snow" in g or "frozen" in g or "ice" in g:
					snow_n += 1
		if storm_n >= 2:
			return "storm"
		if snow_n >= 2:
			return "snow"
		if mud_n >= 2:
			return "mud"
	return "snow"


func _make_particle(kind: String, random_life: bool = false) -> Dictionary:
	var b := _particle_bounds
	var x := b.position.x + randf() * b.size.x
	var y := b.position.y + randf() * b.size.y
	return _make_particle_at(kind, Vector2(x, y), random_life)


func _make_particle_at(kind: String, pos: Vector2, random_life: bool = false) -> Dictionary:
	var vel := Vector2.ZERO
	var life := 1.0
	var k := kind
	match k:
		"storm":
			vel = Vector2(randf_range(-40.0, 80.0), randf_range(90.0, 180.0))
			life = randf_range(0.6, 1.8)
		"mud", "rain":
			vel = Vector2(randf_range(-10.0, 20.0), randf_range(70.0, 140.0))
			life = randf_range(0.8, 2.0)
			k = "rain"
		"dry":
			vel = Vector2(randf_range(-15.0, 15.0), randf_range(5.0, 20.0))
			life = randf_range(2.0, 4.0)
		_:
			vel = Vector2(randf_range(-25.0, 25.0), randf_range(25.0, 70.0))
			life = randf_range(1.2, 3.0)
			k = "snow"
	if random_life:
		life = randf() * life
	return {
		"pos": pos,
		"vel": vel,
		"life": life,
		"max_life": maxf(life, 0.05),
		"kind": k,
		"home": pos,
	}


func _update_particles(delta: float) -> void:
	var b := _particle_bounds
	_particle_seed_t += delta
	# Reseed from province weather periodically so state tracks sim.
	if _particle_seed_t > 3.5:
		_particle_seed_t = 0.0
		_seed_particles()
		return
	var i := 0
	while i < _particles.size():
		var p: Dictionary = _particles[i]
		p["life"] = float(p.get("life", 0.0)) - delta
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		var vel: Vector2 = p.get("vel", Vector2.ZERO)
		pos += vel * delta
		var kind := str(p.get("kind", "snow"))
		# Prefer respawn near home province cluster when available.
		if p["life"] <= 0.0 or pos.y > b.position.y + b.size.y + 40.0:
			if p.has("home"):
				var home: Vector2 = p.get("home", pos)
				_particles[i] = _make_particle_at(kind, home + Vector2(randf_range(-20, 20), randf_range(-20, 20)), false)
			else:
				_particles[i] = _make_particle(kind, false)
			i += 1
			continue
		if pos.x < b.position.x:
			pos.x += b.size.x
		elif pos.x > b.position.x + b.size.x:
			pos.x -= b.size.x
		p["pos"] = pos
		_particles[i] = p
		i += 1


func _draw() -> void:
	if not particle_mode or _particles.is_empty():
		return
	for p_v in _particles:
		if not (p_v is Dictionary):
			continue
		var p: Dictionary = p_v
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		var kind := str(p.get("kind", "snow"))
		var life := float(p.get("life", 1.0))
		var max_life := maxf(0.05, float(p.get("max_life", 1.0)))
		var a := clampf(life / max_life, 0.15, 0.85)
		match kind:
			"storm":
				# Short diagonal rain streak + occasional flash points
				var c := Color(0.55, 0.45, 0.95, a * 0.75)
				draw_line(pos, pos + Vector2(4.0, 10.0), c, 1.2, true)
				if randf() < 0.02:
					draw_circle(pos, 2.5, Color(0.9, 0.75, 1.0, a))
			"rain":
				var c2 := Color(0.55, 0.7, 0.95, a * 0.65)
				draw_line(pos, pos + Vector2(2.0, 8.0), c2, 1.0, true)
			"dry":
				draw_circle(pos, 1.2, Color(0.95, 0.88, 0.55, a * 0.35))
			_:
				# snow flake dots
				draw_circle(pos, 1.8, Color(0.95, 0.97, 1.0, a * 0.8))


## Phase 3: weather tint + movement cost readability (cheap aggregate cue).
func apply_movement_cost_tint(force: bool = false) -> Dictionary:
	if weather_manager == null and not force:
		return {"ok": false, "empty": true}
	var mult := 1.0
	var kind := "fair"
	if weather_manager:
		if weather_manager.has_method("get_aggregate_snow_coverage"):
			var snow = float(weather_manager.get_aggregate_snow_coverage())
			if snow > 0.35:
				mult *= 1.0 + snow * 0.45
				kind = "snow"
		if weather_manager.has_method("get_global_weather_summary"):
			var s = weather_manager.get_global_weather_summary()
			if s is Dictionary:
				var precip = float(s.get("precip", s.get("precipitation", 0.0)))
				var fog = float(s.get("fog", 0.0))
				if precip > 0.4:
					mult *= 1.0 + precip * 0.25
					kind = "rain" if kind == "fair" else kind
				if fog > 0.3:
					mult *= 1.0 + fog * 0.2
					kind = "fog" if kind == "fair" else kind
	var bg = map_renderer.find_child("WorldBackground", true, false) as Sprite2D if map_renderer else null
	if bg and bg.texture and show_weather:
		var base = Color(0.92, 0.90, 0.85, 0.92)
		var tint = base
		match kind:
			"snow":
				tint = Color(0.93, 0.95, 1.0, 0.95)
			"rain":
				tint = Color(0.75, 0.8, 0.88, 0.92)
			"fog":
				tint = Color(0.85, 0.86, 0.88, 0.9)
		bg.modulate = base.lerp(tint, clampf((mult - 1.0) * 1.2, 0.0, 0.55))
	return {
		"ok": true,
		"move_cost_mult": mult,
		"kind": kind,
		"summary": "Weather move ×%.2f (%s)" % [mult, kind],
		"empty": false,
	}
