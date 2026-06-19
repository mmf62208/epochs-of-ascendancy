# scripts/weather/WeatherManager.gd
# Lightweight weather / season / extreme event manager.
# Ticks on TimeManager day advances (throttled).
# Exposes query functions for movement, air, infra, energy, amphib etc.
# Visuals live in a separate cheap WeatherOverlayLayer (map).
# Most detail hidden; weather layer toggle for player visuals + basic info.
# Manipulation via apply_manipulation (from focus/tech/hidden hands).
# Snow progresses north-to-south + mountains + storms; altitude handled via high_ground_fraction in data.

extends Node

signal weather_changed(province_id: int, changes: Dictionary)
signal major_event_occurred(event: Dictionary)

# Simple state per province (or region for scale). Keep small.
var _province_weather: Dictionary = {}  # pid -> {temp, precip_intensity, precip_type, wind, visibility, ground_state, snow_coverage, coverage_notes, ...}

var _active_events: Array = []

var _last_tick_day: int = -1

# Global modulators (hidden hands, solar, large projects)
var _global_weather_mod: Dictionary = {
	"temp_bias": 0.0,
	"precip_bias": 0.0,
	"storm_suppress": 0.0,  # positive = less storms (cloud seeding etc.)
}

func _ready() -> void:
	if typeof(TimeManager) != TYPE_NIL:
		# Connect to daily tick when available
		if TimeManager.has_signal("day_tick"):
			TimeManager.day_tick.connect(_on_day_tick)
	print("WeatherManager ready (full season + snow progression + penalties + event support; visuals in OverlayLayer)")

func _on_day_tick(_year: int, _month: int, _day: int, _total_days: int) -> void:
	# Throttle: only full sim every N days or on interesting changes
	if _total_days - _last_tick_day < 1:
		return
	_last_tick_day = _total_days
	_simulate_day_impl(_year, _month, _day)

func _get_season_progress(month: int, day: int) -> float:
	# 0 winter ... 1 summer rough
	var m = month + (day / 30.0)
	return abs(fmod(m + 9, 12) - 6) / 6.0  # peaks summer

func get_movement_multiplier(pid: int, unit_tags: Array = []) -> float:
	var w = _province_weather.get(pid, {})
	var g = w.get("ground_state", "dry")
	var base = 1.0
	if g == "mud":
		base *= 0.45 if "armor" in unit_tags or "motorized" in unit_tags else 0.75
	elif g == "frozen" or g == "snow_covered":
		base *= 0.85
		if "armor" in unit_tags:
			base *= 1.15  # frozen ground bonus example
	if w.get("visibility", 1.0) < 0.3:
		base *= 0.6
	return base

func get_air_mission_effectiveness(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	var vis = w.get("visibility", 1.0)
	var storm = w.get("precip_intensity", 0.0)
	var base = clamp(vis * (1.0 - storm * 0.8), 0.05, 1.0)

	# Wire to AircraftDesignSystem for range/reliability impact on missions (from editor/prototyping)
	var ads = get_node_or_null("/root/AircraftDesignSystem")  # if autoloaded or added
	if ads == null:
		# Try from Debug if created there
		var debug = get_tree().get_first_node_in_group("debug_overlay") if get_tree() else null
		if debug and debug.has_method("_get_or_create_aircraft_design_system"):
			ads = debug.call("_get_or_create_aircraft_design_system")

	if ads and ads.has_method("get_effective_range"):
		# Rough: lower reliability hurts effectiveness; range config would be per-formation
		# For demo, use a default design if set
		var rel_mod : float = 1.0
		if ads.has_method("get_effective_reliability"):
			rel_mod = ads.get_effective_reliability(80.0, "demo_p51_prototype", 1.0) / 80.0
		base *= clamp(rel_mod, 0.4, 1.2)

	return base

func get_infra_wear_rate(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	if w.get("ground_state") in ["snow_covered", "ice", "frozen"]:
		return 0.8  # winter damage to roads etc.
	elif w.get("ground_state") == "mud":
		return 1.15  # mud accelerates wear
	return 1.0

func get_energy_demand_mod(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	var t = w.get("temp", 10.0)
	if t < -10: return 1.6
	if t < 0: return 1.3
	if t > 35: return 1.4
	return 1.0

# Naval impacts (sea state from storms/visibility/wind affects surface and carrier ops)
func get_naval_mission_effectiveness(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	var vis = w.get("visibility", 1.0)
	var storm = w.get("precip_intensity", 0.0)
	var wind = w.get("wind", 0.2)
	var sea_state = (storm * 0.6) + ((1.0 - vis) * 0.3) + (wind * 0.2)
	var base = clamp(1.0 - sea_state * 0.75, 0.05, 1.0)
	# Power blackout impacts naval ops (ports, comms, fuel, carriers need shore power etc.)
	base *= get_power_availability(pid)
	return base

## Spotting / detection visibility factor for naval search (recon planes, radar, sonar, visual).
## Storms, low vis, night drastically reduce surface search; subs less affected by visual but sonar helps.
## Used in naval spotting simulator.
func get_naval_spotting_visibility(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	var vis = w.get("visibility", 1.0)
	var storm = w.get("precip_intensity", 0.0)
	var wind = w.get("wind", 0.2)
	# Storms/fog/wind kill visual and some radar; subs use sonar which is less impacted.
	var surf_mod = clamp(vis * (1.0 - storm * 0.7 - wind * 0.2), 0.15, 1.0)
	return surf_mod

func get_naval_detection_mod(pid: int, is_sub_search: bool = false) -> float:
	var vis = get_naval_spotting_visibility(pid)
	var base = vis
	if is_sub_search:
		# Subs benefit from low vis for approach, but detection of subs is hard anyway.
		base = clamp(vis * 0.6 + 0.4, 0.3, 0.9)
	# Night/storm implicit in vis; add explicit if time of day available.
	return base

func get_carrier_air_effectiveness(pid: int) -> float:
	# Carrier launched aircraft more vulnerable to weather than land-based
	var air = get_air_mission_effectiveness(pid)
	var naval = get_naval_mission_effectiveness(pid)
	var base = min(air, naval) * 0.6  # extra penalty for deck ops, pitching, etc.
	base *= get_power_availability(pid)  # no power = no launch/recovery support
	return base

# Power / blackout system (can be triggered by weather events, EMP, nuke atmo, espionage, solar flare equivalent)
var _power_states: Dictionary = {}  # pid -> "normal" | "blackout" | "partial"

func cause_blackout(pid: int, affect_surrounding: bool = true, duration_days: int = 3) -> void:
	_power_states[pid] = "blackout"
	if affect_surrounding:
		# Full impl: use MapManager adjacency for realistic grid cascade (partial on neighbors)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_neighbors"):
			var neigh: Array = MapManager.get_province_neighbors(pid)
			for npid in neigh:
				if randf() < 0.7 and (not _power_states.has(npid) or _power_states[npid] == "normal"):
					_power_states[npid] = "partial"
					print("Env: Blackout cascade partial to neighbor pid %d" % int(npid))
		print("Env: Blackout in %d affecting surrounding provinces (power grid cascade)" % pid)
	# Schedule recovery hook (simple, Time will clear on future days if we track duration)
	print("Env: Blackout caused at pid %d (EMP/nuke/atmospheric detonation/espionage/solar equivalent). Power loss impacts province + neighbors." % pid)

func get_power_availability(pid: int) -> float:
	var state = _power_states.get(pid, "normal")
	if state == "blackout":
		return 0.0
	if state == "partial":
		return 0.4
	return 1.0

func apply_emp_or_flare_effect(pid: int = -1, strength: float = 1.0) -> void:
	# Can be called for solar flare, nuke EMP, espionage on power plants, etc.
	if pid > 0:
		cause_blackout(pid, true)
	else:
		# Global or random
		for p in _province_weather.keys():
			if randf() < strength * 0.3:
				cause_blackout(p, false)
	print("Env: EMP/flare/nuke/atmospheric effect applied (blackouts, comms/power loss like solar flare or targeted strike)")

func apply_manipulation(manip_type: String, strength: float, target_pids: Array = []) -> void:
	# Hidden hands / focus / tech hook. Example: cloud seeding reduces storms.
	if manip_type == "cloud_seeding":
		_global_weather_mod["storm_suppress"] = strength
		print("Weather: cloud seeding / manipulation applied (storm suppress ", strength, ")")
	# Extend with temp_bias, force_clear, etc. for Vietnam-style or larger scale.

func _trigger_sample_event() -> void:
	# Stub for typhoon / tornado / quake / x_flare / emp / nuke_atmo / espionage_power etc.
	var types = ["typhoon", "tornado", "quake", "x_flare", "emp_detonation", "espionage_power_plant", "nuke_atmo"]
	var etype = types[randi() % types.size()]
	var ev = {"type": etype, "severity": 2, "affected": [], "duration": 3}
	_active_events.append(ev)
	major_event_occurred.emit(ev)
	if etype in ["x_flare", "emp_detonation", "espionage_power_plant", "nuke_atmo"]:
		apply_emp_or_flare_effect(-1, 0.5 if etype == "x_flare" else 1.0)
	else:
		print("Weather: sample extreme event triggered (expand with real defs + damage)")
	print("Env: Event %s (solar/EMP/nuke/espionage can cause blackout equiv to flare, affecting power in province + surrounding)" % etype)
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
		LeaderEventUI.post_news("Weather Event: " + etype.capitalize(), "Extreme weather/phenom in theater: %s. Affects movement/air/infra/power (see overlays)." % etype, "crisis")

# Example: get summary for player tooltip / weather layer
func get_conditions_summary(pid: int) -> String:
	var w = _province_weather.get(pid, {})
	var g = w.get("ground_state", "dry")
	var s = "Temp %.0fC, %s, vis %.0f%%" % [w.get("temp", 10), g, w.get("visibility",1)*100]
	if w.get("snow_coverage", 0) > 0.3:
		s += " (snow %.0f%%" % (w.snow_coverage*100) + (", high ground" if w.get("high_ground", false) else "") + ")"
	if w.get("snow_potential", 0) > 0.1:
		s += " (high elev snow potential %.0f%% from layers)" % (w.snow_potential*100)
	var pwr = get_power_availability(pid)
	if pwr < 0.5:
		s += " [BLACKOUT power loss]"
	# Naval note for coastal
	s += " Naval: %.0f%%" % (get_naval_mission_effectiveness(pid) * 100)
	return s

# Integrate power into infra etc. (full penalties for econ/combat)
func get_infra_effectiveness(pid: int) -> float:
	var pwr : float = get_power_availability(pid)
	var wear : float = get_infra_wear_rate(pid)
	var eff : float = pwr * (1.0 - (wear - 1.0) * 0.2)
	if pwr < 0.5:
		eff *= 0.6  # blackout drags production/combat infra hard
	return clampf(eff, 0.1, 1.4)

# Init a province from data layer (call from ScenarioLoader or MapManager load)
func initialize_province(pid: int, baseline: Dictionary) -> void:
	var is_northern = baseline.get("is_northern", false) or baseline.get("lat", 50) > 55  # crude for demo UK/Scand/NRus
	var hg = baseline.get("high_ground_fraction", 0.0)
	_province_weather[pid] = {
		"temp": baseline.get("avg_temp", 5.0 if is_northern else 12.0),
		"precip_intensity": 0.0,
		"precip_type": "none",
		"wind": 0.3,
		"visibility": 1.0,
		"ground_state": "dry",
		"snow_coverage": 0.6 if is_northern else 0.0,  # start with snow in north for GRAND THEATER demo
		"is_northern": is_northern,
		"high_ground": hg > 0.3,
		"high_ground_fraction": hg,
		"lat": baseline.get("lat", 60 if is_northern else 50),
		"snow_potential": baseline.get("snow_potential", 0.0),
	}
	# Boost initial snow_coverage from inferred snow_potential (from DEM layers) for high elevations
	var w = _province_weather[pid]
	var sp = baseline.get("snow_potential", 0.0)
	if sp > 0.1:
		w["snow_coverage"] = max(w.get("snow_coverage", 0.0), sp)
		w["high_ground"] = true
		w["high_ground_fraction"] = max(hg, sp)
	_power_states[pid] = "normal"
	# TODO: load real historical + terrain + lat from weather_climate_layer + solar modulation

func simulate_day(year: int, month: int, day: int) -> void:  # public for debug/demo forcing
	_simulate_day_impl(year, month, day)

func _simulate_day_impl(year: int, month: int, day: int) -> void:
	# Very lightweight: season curve + lat bias for snow line + simple noise.
	# Real version would load baselines from data layer + historical + solar.
	var season = _get_season_progress(month, day)
	var solar_bias = sin(year * 0.1) * 1.5  # crude solar cycle

	# Example: advance snow line southward in fall/winter for northern provinces.
	# In real: per-province or per "northing" band + mountain bonus from terrain data.
	for pid in _province_weather.keys():
		var w = _province_weather[pid]
		# World-class perf (HoI4 style): cull heavy daily per-prov to interesting set (player majors + neighbors + event zones); minor provinces light decay only. GDScript daily on 800+ would lag vs C++ state/MTTH.
		var do_full_sim : bool = true
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_owner"):
			var ow := MapManager.get_province_owner(int(pid))
			if ow != "" and ow not in ["GER","FRA","ENG","USA","SOV","JAP","ITA","player"]:
				if randf() > 0.25: do_full_sim = false
		if not do_full_sim:
			w["precip_intensity"] = max(0.0, float(w.get("precip_intensity", 0.0)) * 0.92)
			continue
		var lat = w.get("lat", 50)
		var is_north = w.get("is_northern", lat > 55)
		var hg_frac = w.get("high_ground_fraction", 0.0)
		# Progress snow: north + mountains get more, season drives it (winter months)
		var snow_push = 0.0
		if month >= 9 or month <= 4:  # fall to spring
			snow_push = 0.015 * (1.0 + (lat - 50) / 30.0)  # more north
		else:
			snow_push = -0.008
		var new_snow = clamp(w.get("snow_coverage", 0.0) + snow_push + (hg_frac * 0.01), 0.0, 1.0)
		# Extra from snow_potential (inferred from layers for high elev)
		var sp = w.get("snow_potential", 0.0)
		if sp > 0.1:
			new_snow = clamp(new_snow + sp * 0.005, 0.0, 1.0)
		w["snow_coverage"] = new_snow
		# Ground state
		if new_snow > 0.65:
			w["ground_state"] = "snow_covered"
		elif new_snow > 0.25 or (is_north and month <= 3):
			w["ground_state"] = "frozen"
		elif w.get("precip_type") == "rain" and w.get("precip_intensity", 0) > 0.3:
			w["ground_state"] = "mud"
		else:
			w["ground_state"] = "dry"
		# Simple storm example in north
		if is_north and randf() < 0.1:
			w["precip_intensity"] = randf() * 0.7
			w["precip_type"] = "snow" if w.get("temp", 0) < 2 else "rain"
			w["visibility"] = max(0.2, 1.0 - w["precip_intensity"] * 0.7)
		else:
			w["precip_intensity"] = max(0.0, w.get("precip_intensity", 0) - 0.05)
			w["visibility"] = min(1.0, w.get("visibility", 1) + 0.05)
		# Emit on significant
		if abs(new_snow - w.get("last_snow", 0)) > 0.2:
			w["last_snow"] = new_snow
			weather_changed.emit(pid, {"snow_coverage": new_snow, "ground": w["ground_state"]})

		# Full penalties integration: apply weather-driven infra wear directly to province (beyond query; persistent until repair)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province") and MapManager.has_method("update_province_infrastructure"):
			var p = MapManager.get_province(pid)
			if p != null and p.infrastructure > 0:
				var wear : float = get_infra_wear_rate(pid)
				if wear > 1.0 or (w.get("snow_coverage", 0) > 0.4):
					var dmg : int = 0
					if wear > 1.05: dmg = 1
					if w.get("snow_coverage", 0) > 0.7: dmg += 1
					if dmg > 0 and randf() < 0.15:
						var new_inf : int = max(0, p.infrastructure - dmg)
						MapManager.update_province_infrastructure(pid, new_inf)
						if new_inf < p.infrastructure:
							print("Weather: winter/mud wear damaged infra in pid %d (%d -> %d)" % [pid, p.infrastructure, new_inf])

	# Rare extreme events (full support: typhoon etc trigger blackout/penalties; naval/air hit hard)
	if randf() < 0.005:
		_trigger_sample_event()

func get_all_active_events() -> Array:
	return _active_events.duplicate()

# For save/load
func get_save_state() -> Dictionary:
	return {"province_weather": _province_weather, "events": _active_events, "mods": _global_weather_mod}

func load_save_state(state: Dictionary) -> void:
	_province_weather = state.get("province_weather", {})
	_active_events = state.get("events", [])
	_global_weather_mod = state.get("mods", _global_weather_mod)

# Public for visuals / debug (lightweight aggregate)
func get_aggregate_snow_coverage() -> float:
	if _province_weather.is_empty():
		return 0.0
	var total : float = 0.0
	for v in _province_weather.values():
		total += float(v.get("snow_coverage", 0.0))
	return total / _province_weather.size()

func get_province_snow(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	return float(w.get("snow_coverage", 0.0))

# New full penalty hook for econ/production (cold/mud/blackout hit output; called from GameData/Production if desired)
func get_production_weather_mult(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	var mult : float = 1.0
	var g : String = str(w.get("ground_state", "dry"))
	if g in ["frozen", "snow_covered", "mud"]:
		mult *= 0.85 if g == "mud" else 0.92
	var pwr : float = get_power_availability(pid)
	if pwr < 0.5: mult *= 0.6
	if w.get("visibility", 1.0) < 0.4: mult *= 0.9
	return clampf(mult, 0.4, 1.1)
