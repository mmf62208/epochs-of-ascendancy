# scripts/weather/WeatherManager.gd
# Lightweight weather / season / extreme event manager.
# Ticks on TimeManager day advances (throttled).
# Exposes query functions for movement, air, infra, energy, amphib etc.
# Visuals live in a separate cheap WeatherOverlayLayer (map).
# Most detail hidden; weather layer toggle for player visuals + basic info.
# Manipulation via apply_manipulation (from focus/tech/hidden hands).
# Snow progresses north-to-south + mountains + storms; altitude handled via high_ground_fraction in data.

# NOTE: Do NOT use class_name WeatherManager — this node is an autoload singleton.
# class_name + autoload with the same name makes WeatherManager resolve to the Class DB
# (script type) under Godot 4.7+, so instance methods appear "non-static" and fail to parse/call.
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
	print("WeatherManager ready (lightweight season + event stub)")

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
	var g = str(w.get("ground_state", "dry"))
	var vis := float(w.get("visibility", 1.0))
	var armored := "armor" in unit_tags or "motorized" in unit_tags or "mechanized" in unit_tags
	if true:
		return float(MapPolishFormatters.weather_move_multiplier(g, vis, armored))
	var base = 1.0
	if g == "mud":
		base *= 0.45 if armored else 0.75
	elif g == "frozen" or g == "snow_covered":
		base *= 0.85
		if "armor" in unit_tags:
			base *= 1.15  # frozen ground bonus example
	if vis < 0.3:
		base *= 0.6
	return base

func get_air_mission_effectiveness(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	var vis = float(w.get("visibility", 1.0))
	var storm = float(w.get("precip_intensity", 0.0))
	var wind = float(w.get("wind", 0.2))
	# Prefer pure air-sortie readiness gate (mirrors weather_effects.air_sortie_readiness).
	var base := 1.0
	if true:
		var ready: Dictionary = MapPolishFormatters.air_sortie_weather_readiness(vis, storm, wind)
		base = float(ready.get("effectiveness", clamp(vis * (1.0 - storm * 0.8), 0.05, 1.0)))
	else:
		base = clamp(vis * (1.0 - storm * 0.8), 0.05, 1.0)

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
		var rel_mod := 1.0
		if ads.has_method("get_effective_reliability"):
			rel_mod = ads.get_effective_reliability(80.0, "demo_p51_prototype", 1.0) / 80.0
		base *= clamp(rel_mod, 0.4, 1.2)

	return base

func get_infra_wear_rate(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	if w.get("ground_state") in ["snow_covered", "ice", "frozen"]:
		return 0.8  # winter damage to roads etc.
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

## Naval spotting / detection visibility for engagement context (used by BM naval, resolver, recon).
## High vis good for surface/gun/carrier spot; low vis (storm/night/haze) favors subs/ambush/torps (history: Jutland haze/smoke, Midway searches hampered).
## Factors weather + power + future sat/light.
func get_naval_spotting_visibility(pid: int) -> float:
	var base := get_naval_mission_effectiveness(pid)
	# Spotting slightly different: penalize less for wind (surface waves), more for low vis/precip for visual/radar early.
	var w = _province_weather.get(pid, {})
	var vis = float(w.get("visibility", 1.0))
	var storm = float(w.get("precip_intensity", 0.0))
	var pure_spot := float(MapPolishFormatters.naval_spot_weather_multiplier(vis, storm))
	var spot = clamp(pure_spot, 0.1, 1.0) * base * 0.9 + 0.1  # weighted
	# Tech era later could boost via radar/sat but here base weather; caller applies tech/asset.
	return clamp(spot, 0.05, 1.2)


## Pure naval spot mult without mission-effectiveness base (BattleManager context fill).
func get_naval_spot_weather_multiplier(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	return float(MapPolishFormatters.naval_spot_weather_multiplier(
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
	))


## Air sortie weather effectiveness (pure readiness gate).
func get_air_sortie_weather_eff(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	var ready: Dictionary = MapPolishFormatters.air_sortie_weather_readiness(
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
		float(w.get("wind", 0.2)),
	)
	return float(ready.get("weather_eff", ready.get("effectiveness", 1.0)))

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
		# Stub: affect neighbors (in real, use adjacency from MapManager)
		# For demo, just log; full would query adj and set partial or reduced
		print("Env: Blackout in %d affecting surrounding provinces (power grid cascade)" % pid)
	# Could schedule recovery, but stub for now
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

## Pass 9: live province weather dict for icon resolution / inspector.
func get_province_weather(pid: int) -> Dictionary:
	var w: Variant = _province_weather.get(pid, {})
	if w is Dictionary:
		return (w as Dictionary).duplicate(true)
	return {}


# Example: get summary for player tooltip / weather layer
func get_conditions_summary(pid: int) -> String:
	var w = _province_weather.get(pid, {})
	var g = w.get("ground_state", "dry")
	var s = "Temp %.0fC, %s, vis %.0f%%" % [w.get("temp", 10), g, w.get("visibility",1)*100]
	if w.get("snow_coverage", 0) > 0.3:
		s += " (snow %.0f%%" % (w.snow_coverage*100) + (", high ground" if w.get("high_ground", false) else "") + ")"
	var pwr = get_power_availability(pid)
	if pwr < 0.5:
		s += " [BLACKOUT power loss]"
	# Naval note for coastal
	s += " Naval: %.0f%%" % (get_naval_mission_effectiveness(pid) * 100)
	return s


## Combat weather multiplier (shared pure rules via MapPolishFormatters when available).
func get_combat_weather_multiplier(pid: int) -> float:
	var w: Dictionary = _province_weather.get(pid, {})
	var vis := float(w.get("visibility", 1.0))
	var precip := float(w.get("precip_intensity", 0.0))
	var wind := float(w.get("wind", 0.2))
	if true:
		return float(MapPolishFormatters.weather_combat_multiplier(vis, precip, wind))
	return clampf(vis * (1.0 - precip * 0.55) * (1.0 - maxf(0.0, wind - 0.4) * 0.2), 0.2, 1.1)


## Supply throughput weather multiplier.
func get_supply_weather_multiplier(pid: int) -> float:
	var w: Dictionary = _province_weather.get(pid, {})
	var g := str(w.get("ground_state", "dry"))
	var precip := float(w.get("precip_intensity", 0.0))
	if true:
		return float(MapPolishFormatters.weather_supply_multiplier(g, precip))
	return 1.0


## Production output weather multiplier.
func get_production_weather_multiplier(pid: int) -> float:
	var w: Dictionary = _province_weather.get(pid, {})
	var temp := float(w.get("temp", 10.0))
	var precip := float(w.get("precip_intensity", 0.0))
	if true:
		return float(MapPolishFormatters.weather_production_multiplier(temp, precip))
	return 1.0


## Storm interdiction bump for supply routes.
func get_storm_interdiction_chance(pid: int, base_interdiction: float = 0.1) -> float:
	var w: Dictionary = _province_weather.get(pid, {})
	var storm := float(w.get("precip_intensity", 0.0))
	var vis := float(w.get("visibility", 1.0))
	var bump := storm * 0.18 + maxf(0.0, 0.5 - vis) * 0.12
	return clampf(base_interdiction + bump, 0.0, 0.95)


## Inspector BBCode weather chip (live surface).
func format_province_weather_chip_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var season := ""
	if typeof(TimeManager) != TYPE_NIL:
		var month := int(TimeManager.current_month) if "current_month" in TimeManager else 1
		if true:
			season = str(MapPolishFormatters.season_label(month))
	if true:
		return str(
			MapPolishFormatters.format_weather_chip_bbcode(
				float(w.get("temp", 10.0)),
				str(w.get("ground_state", "dry")),
				float(w.get("visibility", 1.0)),
				float(w.get("precip_intensity", 0.0)),
				season,
			)
		)
	return "[color=#8899aa]%s[/color]" % get_conditions_summary(pid)


## Weather overlay legend BBCode (live surface).
func format_weather_legend_bbcode() -> String:
	if true:
		return str(MapPolishFormatters.format_weather_legend_bbcode())
	return "[color=#8899aa]Weather legend unavailable[/color]"


## Next-day forecast chip for province (deterministic stub).
func format_province_forecast_chip_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var fx: Dictionary = MapPolishFormatters.forecast_next_day_weather(
		float(w.get("temp", 10.0)),
		float(w.get("precip_intensity", 0.0)),
		float(w.get("visibility", 1.0)),
		float(w.get("wind", 0.2)),
		str(w.get("ground_state", "dry")),
	)
	return str(fx.get("bbcode", fx.get("label", "")))


## Season + daylight chip for current month.
func format_season_daylight_chip_bbcode() -> String:
	var month := 1
	if typeof(TimeManager) != TYPE_NIL and "current_month" in TimeManager:
		month = int(TimeManager.current_month)
	var chip: Dictionary = MapPolishFormatters.format_season_daylight_chip(month)
	return str(chip.get("bbcode", chip.get("plain", "")))


## Extreme event severity chip from active events.
func format_extreme_event_chip_bbcode() -> String:
	var chip: Dictionary = MapPolishFormatters.format_extreme_event_chip(_active_events)
	if bool(chip.get("empty", true)):
		return ""
	return str(chip.get("bbcode", ""))


## Move cost estimate with weather for unit tags.
func estimate_move_cost_with_weather(pid: int, base_cost: float = 1.0, unit_tags: Array = []) -> Dictionary:
	var w: Dictionary = _province_weather.get(pid, {})
	var armored := "armor" in unit_tags or "motorized" in unit_tags or "mechanized" in unit_tags
	return MapPolishFormatters.estimate_move_cost_with_weather(
		base_cost,
		str(w.get("ground_state", "dry")),
		float(w.get("visibility", 1.0)),
		armored,
	)


## Storm convoy risk chip for province.
func format_storm_convoy_risk_bbcode(pid: int, escort_need_base: float = 25.0) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var risk: Dictionary = MapPolishFormatters.storm_convoy_risk(
		float(w.get("precip_intensity", 0.0)),
		float(w.get("visibility", 1.0)),
		escort_need_base,
		0.1,
	)
	return str(risk.get("bbcode", risk.get("label", "")))


## Weather pressure index for province.
func format_weather_pressure_chip_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var p: Dictionary = MapPolishFormatters.weather_pressure_index(
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
		str(w.get("ground_state", "dry")),
		float(w.get("wind", 0.2)),
	)
	return str(p.get("bbcode", p.get("label", "")))


## Trade weather multiplier for province (TradeManager live path).
func get_trade_weather_multiplier(pid: int) -> float:
	var w: Dictionary = _province_weather.get(pid, {})
	return float(MapPolishFormatters.trade_weather_multiplier(
		str(w.get("ground_state", "dry")),
		float(w.get("precip_intensity", 0.0)),
	))


## Naval engagement weather tip.
func format_naval_engagement_weather_tip_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var tip: Dictionary = MapPolishFormatters.naval_engagement_weather_tip(
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
	)
	return str(tip.get("bbcode", tip.get("summary", "")))


## Air grounding alert (empty when fair).
func format_air_grounding_alert_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var alert: Dictionary = MapPolishFormatters.air_grounding_alert(
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
		float(w.get("wind", 0.2)),
	)
	if bool(alert.get("empty", true)):
		return ""
	return str(alert.get("bbcode", ""))


## Freeze/thaw ground chip.
func format_freeze_thaw_chip_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var ft: Dictionary = MapPolishFormatters.freeze_thaw_transition(
		str(w.get("ground_state", "dry")),
		float(w.get("temp", 10.0)),
		float(w.get("precip_intensity", 0.0)),
	)
	return str(ft.get("bbcode", ft.get("summary", "")))


## Infra weather wear chip.
func format_infra_weather_wear_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var wear: Dictionary = MapPolishFormatters.infra_weather_wear(
		str(w.get("ground_state", "dry")),
		float(w.get("precip_intensity", 0.0)),
	)
	return str(wear.get("bbcode", wear.get("summary", "")))


## Coastal fog naval gate chip.
func format_coastal_fog_gate_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var fog: Dictionary = MapPolishFormatters.coastal_fog_naval_gate(
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
	)
	return str(fog.get("bbcode", fog.get("summary", "")))


## Compact weather ops section for inspector.
func format_inspector_weather_section_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	if w.is_empty():
		return ""
	var sec: Dictionary = MapPolishFormatters.format_inspector_weather_section(
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
		str(w.get("ground_state", "dry")),
		float(w.get("temp", 10.0)),
		float(w.get("wind", 0.2)),
	)
	return str(sec.get("bbcode", ""))


## Campaign day risk chip.
func format_campaign_day_risk_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var month := 1
	if typeof(TimeManager) != TYPE_NIL and "current_month" in TimeManager:
		month = int(TimeManager.current_month)
	var risk: Dictionary = MapPolishFormatters.campaign_day_risk(
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
		str(w.get("ground_state", "dry")),
		float(w.get("wind", 0.2)),
		month,
	)
	return str(risk.get("bbcode", risk.get("label", "")))


## Production weather alert (empty when fair).
func format_production_weather_alert_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var alert: Dictionary = MapPolishFormatters.production_weather_alert(
		float(w.get("temp", 10.0)),
		float(w.get("precip_intensity", 0.0)),
		0.85,
	)
	if bool(alert.get("empty", true)):
		return ""
	return str(alert.get("bbcode", ""))


## Combat morale weather mult (attacker).
func get_combat_morale_weather_mult(pid: int) -> float:
	var w: Dictionary = _province_weather.get(pid, {})
	var m: Dictionary = MapPolishFormatters.combat_morale_weather(
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
		float(w.get("wind", 0.2)),
	)
	return float(m.get("morale_mult", 1.0))


## Depot weather capacity factor.
func get_depot_weather_capacity(pid: int, base_capacity: float = 100.0) -> Dictionary:
	var w: Dictionary = _province_weather.get(pid, {})
	return MapPolishFormatters.depot_weather_capacity(
		base_capacity,
		str(w.get("ground_state", "dry")),
		float(w.get("precip_intensity", 0.0)),
	)


## Daylight combat mod for current month.
func format_daylight_combat_mod_bbcode() -> String:
	var month := 1
	if typeof(TimeManager) != TYPE_NIL and "current_month" in TimeManager:
		month = int(TimeManager.current_month)
	var d: Dictionary = MapPolishFormatters.daylight_combat_mod(month)
	return str(d.get("bbcode", d.get("summary", "")))


## Convoy weather window for province (stub 3-day forecast).
func format_convoy_weather_window_bbcode(pid: int) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var days: Array = []
	for i in range(3):
		days.append({
			"day_index": i,
			"visibility": clampf(float(w.get("visibility", 1.0)) + float(i) * 0.1, 0.1, 1.0),
			"precip_intensity": clampf(float(w.get("precip_intensity", 0.0)) - float(i) * 0.15, 0.0, 1.0),
			"ground_state": str(w.get("ground_state", "dry")),
		})
	var win: Dictionary = MapPolishFormatters.convoy_weather_window(days)
	return str(win.get("bbcode", win.get("summary", "")))


## Sea × naval weather ops mult for province.
func format_sea_naval_weather_ops_bbcode(pid: int, sea_mult: float = 1.0) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var ops: Dictionary = MapPolishFormatters.sea_naval_weather_ops(
		sea_mult,
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
	)
	return str(ops.get("bbcode", ops.get("summary", "")))


## Choke + weather synergy chip.
func format_choke_weather_synergy_bbcode(pid: int, is_choke: bool = false, controller_friendly: bool = true) -> String:
	var w: Dictionary = _province_weather.get(pid, {})
	var syn: Dictionary = MapPolishFormatters.choke_weather_synergy(
		is_choke,
		controller_friendly,
		float(w.get("visibility", 1.0)),
		float(w.get("precip_intensity", 0.0)),
	)
	if bool(syn.get("empty", true)):
		return ""
	return str(syn.get("bbcode", ""))

# Integrate power into infra etc.
func get_infra_effectiveness(pid: int) -> float:
	return get_power_availability(pid) * (1.0 - get_infra_wear_rate(pid) * 0.1)  # stub; power loss hurts infra ops, production, lights etc.

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
	}
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

	# Rare extreme (stub)
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
	var total := 0.0
	for v in _province_weather.values():
		total += float(v.get("snow_coverage", 0.0))
	return total / _province_weather.size()

func get_province_snow(pid: int) -> float:
	var w = _province_weather.get(pid, {})
	return float(w.get("snow_coverage", 0.0))


## Production output multiplier from local weather (storm/mud/snow hurt factories slightly).
func get_production_weather_mult(pid: int) -> float:
	var w: Dictionary = _province_weather.get(pid, {})
	if w.is_empty():
		return 1.0
	var mult := 1.0
	var precip := float(w.get("precip_intensity", 0.0))
	var vis := float(w.get("visibility", 1.0))
	var ground := str(w.get("ground_state", "dry"))
	if precip > 0.5:
		mult *= 0.92
	if vis < 0.35:
		mult *= 0.95
	if ground == "mud" or ground == "flooded":
		mult *= 0.9
	elif ground == "snow_covered" or ground == "frozen":
		mult *= 0.94
	return clampf(mult, 0.5, 1.1)


## Debug/test: force weather event on a province (blizzard/rain/mud).
func force_event_for_test(pid: int, event_type: String = "blizzard") -> void:
	if not _province_weather.has(pid):
		initialize_province(pid, {"is_northern": true, "lat": 55.0, "high_ground_fraction": 0.3, "snow_potential": 0.4})
	var w: Dictionary = _province_weather[pid]
	match str(event_type).to_lower():
		"blizzard", "snow":
			w["precip_intensity"] = 0.85
			w["precip_type"] = "snow"
			w["visibility"] = 0.25
			w["wind"] = 0.7
			w["ground_state"] = "snow_covered"
			w["snow_coverage"] = 0.8
		"mud", "rain":
			w["precip_intensity"] = 0.7
			w["precip_type"] = "rain"
			w["visibility"] = 0.45
			w["ground_state"] = "mud"
		_:
			w["precip_intensity"] = 0.6
			w["visibility"] = 0.4
	_province_weather[pid] = w
	_active_events.append({"type": event_type, "province_id": pid, "day": _last_tick_day})
	weather_changed.emit(pid, w.duplicate())


## Public write for debug harnesses (replaces illegal WeatherManager._province_weather[pid] = ...).
func debug_set_province_weather(pid: int, data: Dictionary) -> void:
	if not _province_weather.has(pid):
		initialize_province(pid, {})
	var w: Dictionary = _province_weather[pid]
	for k in data.keys():
		w[k] = data[k]
	_province_weather[pid] = w
	weather_changed.emit(pid, w.duplicate())
