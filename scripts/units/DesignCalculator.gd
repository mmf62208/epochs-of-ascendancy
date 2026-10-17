# scripts/units/DesignCalculator.gd
## P1 air-physics presenter. Loads data/unit_physics/air_presets_p1.json via FileAccess
## (not GameData). Not wired into DesignManager. Read-only.
class_name DesignCalculator
extends RefCounted

const PRESETS_PATH: String = "res://data/unit_physics/air_presets_p1.json"
const GOLDEN_PATH: String = "res://data/unit_physics/p1_golden.json"

const PRESET_ORDER: Array[String] = [
	"bf109e", "spitfire_mk1", "p51d", "p47d", "typhoon_ib", "b17g",
	"me262_a1a", "f86a", "f16c", "f35a", "fw190a", "a6m2_zero",
]


var _presets: Dictionary = {}
var _loaded: bool = false
var _errors: PackedStringArray = PackedStringArray()


func load_presets() -> bool:
	_errors.clear()
	if not FileAccess.file_exists(PRESETS_PATH):
		_errors.append("missing %s" % PRESETS_PATH)
		return false
	var f: FileAccess = FileAccess.open(PRESETS_PATH, FileAccess.READ)
	if f == null:
		_errors.append("open failed %s" % PRESETS_PATH)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_errors.append("presets JSON is not an object")
		return false
	var root: Dictionary = parsed as Dictionary
	var raw: Variant = root.get("presets", root)
	if typeof(raw) != TYPE_DICTIONARY:
		_errors.append("presets map missing")
		return false
	_presets = raw as Dictionary
	_loaded = true
	var keys: Array = _presets.keys()
	keys.sort()
	for k in keys:
		var block: Dictionary = _presets[k] as Dictionary
		var errs: PackedStringArray = validate_preset(block)
		for e in errs:
			_errors.append("%s: %s" % [str(k), e])
	return _errors.is_empty()


func load_golden() -> Dictionary:
	if not FileAccess.file_exists(GOLDEN_PATH):
		return {}
	var f: FileAccess = FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func presets() -> Dictionary:
	if not _loaded:
		load_presets()
	return _presets


func preset_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var have: Dictionary = presets()
	for pid in PRESET_ORDER:
		if have.has(pid):
			out.append(pid)
	var extras: Array = have.keys()
	extras.sort()
	for k in extras:
		var s := str(k)
		if not out.has(s):
			out.append(s)
	return out


func get_preset(preset_id: String) -> Dictionary:
	var have: Dictionary = presets()
	if have.has(preset_id) and have[preset_id] is Dictionary:
		return have[preset_id] as Dictionary
	return {}


func errors() -> PackedStringArray:
	return _errors


func validate_preset(block: Dictionary) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	var required: Array[String] = [
		"id", "display_name", "variant", "template_id", "engine_kind",
		"frame_class_ref_role", "profile", "empty_weight_kg", "other_fixed_kg",
		"internal_fuel_kg", "gross_clean_kg", "mtow_kg", "sfc", "ld_clean",
		"calibration", "labels",
	]
	for k in required:
		if not block.has(k):
			errs.append("missing %s" % k)
	var kind := str(block.get("engine_kind", ""))
	if kind == "piston" and not block.has("prop_eta"):
		errs.append("piston missing prop_eta")
	if kind == "jet" and not block.has("cruise_kt"):
		errs.append("jet missing cruise_kt")
	if not (block.get("calibration", {}) is Dictionary):
		errs.append("calibration missing")
	else:
		var cal: Dictionary = block.get("calibration", {}) as Dictionary
		for ck in ["sourced_range", "unit", "source_id", "profile", "target_band", "fitted_param", "fitted_value"]:
			if not cal.has(ck):
				errs.append("calibration missing %s" % ck)
	var we: float = float(block.get("empty_weight_kg", 0.0))
	var oth: float = float(block.get("other_fixed_kg", 0.0))
	var fuel: float = float(block.get("internal_fuel_kg", 0.0))
	var gross: float = float(block.get("gross_clean_kg", 0.0))
	if absf((we + oth + fuel) - gross) > 1.0:
		errs.append("gross_clean_kg != empty+other+fuel")
	return errs


func default_loadouts(block: Dictionary) -> Array:
	var pid := str(block.get("id", ""))
	var extras: Array = []
	if pid == "me262_a1a":
		extras = [
			_lo("sc500_racks", "1 × SC 500 + ETC racks (560 kg)", 560.0, 1.0, 500.0, true, "strike_light"),
			_lo("kg1000_racks", "1,000 kg + racks (1,060 kg)", 1060.0, 2.0, 1000.0, true, "strike_heavy"),
		]
	elif pid == "typhoon_ib":
		var lo500: Dictionary = _lo("2x500lb", "2 × 500 lb", UnitPhysics.lb_to_kg(1000.0), 1.0, UnitPhysics.lb_to_kg(1000.0), true, "strike_light")
		var lo_tanks: Dictionary = {
			"id": "2x45imp",
			"label": "2 × 45 gal tanks",
			"payload_kg": UnitPhysics.lb_to_kg(100.0),
			"extra_fuel_kg": UnitPhysics.imp_gal_avgas_kg(90.0),
			"store_class": 0.0,
			"ignore_drag": true,
			"droppable": true,
			"default_role": "ferry",
		}
		var lo_rp: Dictionary = {
			"id": "rp3",
			"label": "8 × RP-3",
			"payload_kg": UnitPhysics.lb_to_kg(640.0),
			"store_class": 0.0,
			"rockets_loaded": true,
			"droppable": true,
			"default_role": "strike_light",
		}
		extras = [lo500, lo_tanks, lo_rp]
	elif pid == "p51d":
		var lo_b: Dictionary = _lo("2x1000lb", "2 × 1,000 lb", UnitPhysics.lb_to_kg(2000.0), UnitPhysics.store_class_from_weight_kg(UnitPhysics.lb_to_kg(2000.0)), UnitPhysics.lb_to_kg(2000.0), true, "strike_heavy")
		var lo_aft: Dictionary = {
			"id": "aft85",
			"label": "85 gal aft tank full",
			"payload_kg": 0.0,
			"store_class": 0.0,
			"aft_tank_gal": 85.0,
			"droppable": false,
			"default_role": "escort",
		}
		extras = [lo_b, lo_aft]
	elif pid == "f16c":
		var lo_ferry: Dictionary = {
			"id": "ferry_2tanks",
			"label": "2 × tanks (ferry, no reserve)",
			"payload_kg": 0.0,
			"extra_fuel_kg": UnitPhysics.lb_to_kg(5000.0),
			"store_class": 0.0,
			"ignore_drag": true,
			"apply_reserve": false,
			"droppable": true,
			"default_role": "ferry",
		}
		extras = [
			lo_ferry,
			_lo("2x500lb", "2 × 500 lb", UnitPhysics.lb_to_kg(1000.0), 1.0, UnitPhysics.lb_to_kg(1000.0), true, "strike_light"),
		]
	else:
		extras = [
			_lo("2x500lb", "2 × 500 lb", UnitPhysics.lb_to_kg(1000.0), 1.0, UnitPhysics.lb_to_kg(1000.0), true, "strike_light"),
		]
	var clean: Dictionary = {
		"id": "clean",
		"label": "Clean (internal)",
		"payload_kg": 0.0,
		"store_class": 0.0,
		"droppable": false,
		"default_role": "strike_heavy" if pid == "b17g" else "escort",
	}
	if pid == "f16c":
		clean["derived_combat"] = true
		clean["apply_reserve"] = true
	var out: Array = [clean]
	for e in extras:
		out.append(e)
	return out


func _lo(id: String, label: String, payload: float, store_class: float, store_weight: float, droppable: bool, role: String) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"payload_kg": payload,
		"store_class": store_class,
		"store_weight_kg": store_weight,
		"droppable": droppable,
		"default_role": role,
	}


func loadout_by_id(block: Dictionary, loadout_id: String) -> Dictionary:
	for lo in default_loadouts(block):
		if lo is Dictionary and str((lo as Dictionary).get("id", "")) == loadout_id:
			return lo as Dictionary
	return default_loadouts(block)[0] as Dictionary


func evaluate(block: Dictionary, loadout: Dictionary, role: String, fuel_override_kg: float = -1.0) -> Dictionary:
	var w_e: float = float(block.get("empty_weight_kg", 0.0))
	var w_o: float = float(block.get("other_fixed_kg", 0.0))
	var std_fuel: float = float(block.get("internal_fuel_kg", 0.0))
	var w_clean: float = float(block.get("gross_clean_kg", 0.0))
	var mtow: float = float(block.get("mtow_kg", 1.0))
	var payload: float = float(loadout.get("payload_kg", 0.0))
	var extra_fuel: float = float(loadout.get("extra_fuel_kg", 0.0))
	var fuel: float = std_fuel + extra_fuel
	if fuel_override_kg >= 0.0:
		fuel = fuel_override_kg
	var w_i: float = w_e + w_o + fuel + payload
	var kind := str(block.get("engine_kind", "piston"))
	var fc: float = UnitPhysics.frame_class(w_e, str(block.get("frame_class_ref_role", "prop")))
	var sc: float = float(loadout.get("store_class", 0.0))
	var ld_fac: float = UnitPhysics.ld_factor(
		kind,
		sc,
		fc,
		bool(loadout.get("rockets_loaded", false)),
		bool(loadout.get("ignore_drag", false)),
		bool(loadout.get("rails_only", false)),
	)
	var apply_reserve: bool = str(block.get("profile", "combat")) != "ferry"
	if loadout.has("apply_reserve"):
		apply_reserve = bool(loadout.get("apply_reserve"))
	if str(loadout.get("id", "")) == "ferry_2tanks":
		apply_reserve = false
	if str(loadout.get("id", "")) == "clean" and bool(loadout.get("derived_combat", false)):
		apply_reserve = true
	var cal: Dictionary = block.get("calibration", {}) as Dictionary
	var k: float = float(cal.get("fitted_value", UnitPhysics.K_BREGUET_DEFAULT))
	var r_clean: float = UnitPhysics.breguet_range_km(block, w_clean, std_fuel, 1.0, k, true)
	if str(block.get("id", "")) == "f16c" and str(loadout.get("id", "")) == "ferry_2tanks":
		var w_ferry: float = w_e + w_o + (std_fuel + extra_fuel)
		r_clean = UnitPhysics.breguet_range_km(block, w_ferry, std_fuel + extra_fuel, 1.0, k, false)
	var r_loaded: float = UnitPhysics.breguet_range_km(block, w_i, fuel, ld_fac, k, apply_reserve)
	var usable_c: float = UnitPhysics.usable_fuel_kg(std_fuel, std_fuel, true)
	var usable_l: float = UnitPhysics.usable_fuel_kg(fuel, std_fuel, apply_reserve)
	var ln_c: float = UnitPhysics.ln_ratio(w_clean, usable_c)
	var ln_l: float = UnitPhysics.ln_ratio(w_i, usable_l)
	var weight_loss: float = 0.0 if ln_c <= 0.0 else (1.0 - (ln_l / ln_c)) * 100.0
	var drag_loss: float = (1.0 - ld_fac) * 100.0
	var role_key := str(role).strip_edges()
	if role_key.is_empty():
		role_key = str(loadout.get("default_role", "escort"))
	var f: float = UnitPhysics.role_f(role_key)
	var droppable: bool = bool(loadout.get("droppable", false)) and (
		payload > 0.0 or bool(loadout.get("rockets_loaded", false)) or extra_fuel > 0.0
	)
	var two_leg: int = -1
	if droppable:
		two_leg = UnitPhysics.two_leg_radius_hexes(r_loaded, r_clean, f)
	var aft_f: float = 0.0
	var apply_aft: bool = false
	if loadout.has("aft_tank_gal"):
		aft_f = float(loadout.get("aft_tank_gal"))
		apply_aft = true
	elif block.get("aft_tank_gal", null) != null:
		aft_f = float(block.get("aft_tank_gal"))
		apply_aft = true
	var agi_d: Dictionary = UnitPhysics.agility_index(w_clean, w_i, ld_fac, aft_f, apply_aft)
	var agi: float = float(agi_d.get("index", 0.0))
	var cg_aft: bool = bool(agi_d.get("cg", false))
	var agi_clean_d: Dictionary = UnitPhysics.agility_index(w_clean, w_clean, 1.0, 0.0, false)
	var agi_clean: float = float(agi_clean_d.get("index", 1.0))
	var agi_delta: float = 0.0 if agi_clean <= 0.0 else (1.0 - agi / agi_clean) * 100.0
	var has_v: bool = block.get("v_max_kmh", null) != null
	var v_clean: float = float(block.get("v_max_kmh", 0.0)) if has_v else -1.0
	var v_loaded: float = UnitPhysics.top_speed_kmh(v_clean, has_v, ld_fac, kind)
	var has_to: bool = block.get("base_takeoff_m", null) != null and block.get("base_takeoff_m") is Array
	var to_lo: float = -1.0
	var to_hi: float = -1.0
	if has_to:
		var arr: Array = block.get("base_takeoff_m") as Array
		if arr.size() >= 2:
			var to: Dictionary = UnitPhysics.takeoff_run_m(float(arr[0]), float(arr[1]), true, w_i, w_clean)
			to_lo = float(to.get("lo", -1.0))
			to_hi = float(to.get("hi", -1.0))
	var over: float = w_i - mtow
	var frac: float = w_i / mtow if mtow > 0.0 else 0.0
	var density: float = float(block.get("fuel_density_kg_per_L", UnitPhysics.J2_KG_PER_L if kind == "jet" else UnitPhysics.AVGAS_KG_PER_L))
	var fuel_cut_kg: float = -1.0
	var fuel_cut_L: float = -1.0
	var fuel_cut_range: float = -1.0
	var fuel_cut_radius: int = -1
	if over > 0.0:
		fuel_cut_kg = UnitPhysics.fuel_to_fit_mtow_kg(w_e, w_o, payload, mtow)
		fuel_cut_L = fuel_cut_kg / density if density > 0.0 else 0.0
		var w_fit: float = w_e + w_o + fuel_cut_kg + payload
		fuel_cut_range = UnitPhysics.breguet_range_km(block, w_fit, fuel_cut_kg, ld_fac, k, true)
		fuel_cut_radius = UnitPhysics.radius_hexes(f, fuel_cut_range)
	var fighter: bool = str(block.get("id", "")) != "b17g"
	var warnings: Array = []
	if over > 0.0:
		warnings.append({
			"id": "overweight",
			"severity": "error",
			"text": "OVER by %.0f kg (%.1f%%)" % [over, 100.0 * over / mtow],
			"fixes": [
				"cut fuel to %.0f L, giving radius %s" % [fuel_cut_L, str(fuel_cut_radius)],
				"RATO overload (deferred to P2, see the D7 rule)",
				"choose a bomber frame",
			],
		})
	elif frac >= UnitPhysics.NEAR_MTOW_FRAC:
		warnings.append({
			"id": "near_mtow",
			"severity": "warn",
			"text": "Near MTOW (%.1f%%) — %.0f kg spare" % [100.0 * frac, mtow - w_i],
			"fixes": ["leave a fuel or store margin"],
		})
	if cg_aft:
		warnings.append({
			"id": "cg_aft",
			"severity": "warn",
			"text": "burn the aft tank first; no hard manoeuvres",
			"fixes": ["burn the aft tank first; no hard manoeuvres above 40 gal"],
		})
	if fighter and payload >= UnitPhysics.FIGHTER_CG_STORE_KG:
		warnings.append({
			"id": "cg_heavy_store",
			"severity": "warn",
			"text": "≥1,000 kg store on a fighter frame (DESIGN PICK)",
			"fixes": ["use a bomber frame or a lighter store"],
		})
	if to_hi >= 0.0:
		warnings.append({
			"id": "field_length",
			"severity": "info",
			"text": "needs concrete ≥ %.0f m" % to_hi,
			"fixes": ["needs concrete ≥ %.0f m" % to_hi],
		})
	if block.get("flavour_notes", []) is Array:
		var ni: int = 0
		for note in block.get("flavour_notes", []) as Array:
			warnings.append({"id": "flavour_%d" % ni, "severity": "info", "text": str(note), "fixes": []})
			ni += 1
	if block.get("source_caveats", []) is Array:
		var ci: int = 0
		for note in block.get("source_caveats", []) as Array:
			warnings.append({"id": "caveat_%d" % ci, "severity": "info", "text": str(note), "fixes": []})
			ci += 1
	return {
		"preset_id": str(block.get("id", "")),
		"loadout_id": str(loadout.get("id", "clean")),
		"loadout_label": str(loadout.get("label", "Clean")),
		"role": role_key,
		"f": f,
		"w_e_kg": w_e,
		"w_other_kg": w_o,
		"w_fuel_kg": fuel,
		"w_payload_kg": payload,
		"w_i_kg": w_i,
		"w_clean_kg": w_clean,
		"mtow_kg": mtow,
		"mtow_delta_kg": mtow - w_i,
		"mtow_frac": frac,
		"over_mtow": over > 0.0,
		"legal": over <= 0.0,
		"range_clean_km": r_clean,
		"range_loaded_km": r_loaded,
		"range_clean_hexes": UnitPhysics.range_hexes(r_clean),
		"range_loaded_hexes": UnitPhysics.range_hexes(r_loaded),
		"weight_loss_pct": weight_loss,
		"drag_loss_pct": drag_loss,
		"ld_factor": ld_fac,
		"radius_hexes": UnitPhysics.radius_hexes(f, r_loaded),
		"two_leg_radius_hexes": two_leg,
		"v_max_clean_kmh": v_clean,
		"v_max_loaded_kmh": v_loaded,
		"has_v_max": has_v,
		"agility": agi,
		"agility_delta_pct": agi_delta,
		"takeoff_lo_m": to_lo,
		"takeoff_hi_m": to_hi,
		"has_takeoff": has_to,
		"fuel_cut_kg": fuel_cut_kg,
		"fuel_cut_L": fuel_cut_L,
		"fuel_cut_range_km": fuel_cut_range,
		"fuel_cut_radius_hexes": fuel_cut_radius,
		"warnings": warnings,
		"k_preset": k,
		"k_soft_warning": k < UnitPhysics.K_SOFT_MIN or k > UnitPhysics.K_SOFT_MAX,
		"calibration": cal,
		"rato": UnitPhysics.rato_overload_check(),
		"apply_reserve": apply_reserve,
		"frame_class": fc,
		"store_class": sc,
	}


func evaluate_ids(preset_id: String, loadout_id: String, role: String, fuel_override_kg: float = -1.0) -> Dictionary:
	var block: Dictionary = get_preset(preset_id)
	if block.is_empty():
		return {}
	return evaluate(block, loadout_by_id(block, loadout_id), role, fuel_override_kg)


func calibration_row(block: Dictionary) -> Dictionary:
	var sourced: float = UnitPhysics.sourced_range_km(block)
	var ev: Dictionary
	if str(block.get("id", "")) == "f16c":
		ev = evaluate(block, loadout_by_id(block, "ferry_2tanks"), "ferry")
	else:
		ev = evaluate(block, loadout_by_id(block, "clean"), "escort")
	var result: float = float(ev.get("range_loaded_km", 0.0))
	var ratio: float = result / sourced if sourced > 0.0 else 0.0
	var cal: Dictionary = block.get("calibration", {}) as Dictionary
	var k: float = float(cal.get("fitted_value", ev.get("k_preset", 0.0)))
	return {
		"id": str(block.get("id", "")),
		"display_name": str(block.get("display_name", "")),
		"sourced_km": sourced,
		"source_id": str(cal.get("source_id", "")),
		"profile": str(cal.get("profile", block.get("profile", ""))),
		"result_km": result,
		"ratio": ratio,
		"k_preset": k,
		"in_band": UnitPhysics.CAL_BAND_LO <= ratio and ratio <= UnitPhysics.CAL_BAND_HI and result + 1e-9 >= sourced,
		"k_soft_warning": k < UnitPhysics.K_SOFT_MIN or k > UnitPhysics.K_SOFT_MAX,
		"hexes": int(ev.get("range_loaded_hexes", 0)),
		"unit": str(cal.get("unit", "km")),
		"sourced_raw": float(cal.get("sourced_range", 0.0)),
	}


func me262_cases() -> Dictionary:
	var block: Dictionary = get_preset("me262_a1a")
	var cut_fuel: float = UnitPhysics.fuel_to_fit_mtow_kg(
		float(block.get("empty_weight_kg", 0.0)),
		float(block.get("other_fixed_kg", 0.0)),
		1060.0,
		float(block.get("mtow_kg", 0.0)),
	)
	return {
		"clean": evaluate(block, loadout_by_id(block, "clean"), "escort"),
		"sc500": evaluate(block, loadout_by_id(block, "sc500_racks"), "strike_light"),
		"kg1000_full": evaluate(block, loadout_by_id(block, "kg1000_racks"), "strike_heavy"),
		"kg1000_fuel_cut": evaluate(block, loadout_by_id(block, "kg1000_racks"), "strike_heavy", 1257.0),
		"kg1000_fuel_cut_computed": evaluate(block, loadout_by_id(block, "kg1000_racks"), "strike_heavy", cut_fuel),
	}


func format_readout(ev: Dictionary, block: Dictionary) -> String:
	var name := str(block.get("display_name", ev.get("preset_id", ""))).to_upper()
	var load_lbl := str(ev.get("loadout_label", "Clean"))
	var to_hi: float = float(ev.get("takeoff_hi_m", -1.0))
	var field := "Field: —"
	if to_hi >= 0.0:
		field = "Field: Concrete ≥ %.0f m" % to_hi
	var w_i: float = float(ev.get("w_i_kg", 0.0))
	var mtow: float = float(ev.get("mtow_kg", 1.0))
	var frac: float = float(ev.get("mtow_frac", 0.0))
	var delta: float = float(ev.get("mtow_delta_kg", 0.0))
	var bar_n: int = clampi(int(round(frac * 20.0)), 0, 20)
	var bar := ""
	var i: int = 0
	while i < 20:
		bar += "█" if i < bar_n else "░"
		i += 1
	var legal := "OVER by %.0f kg (%.1f%%)" % [-delta, 100.0 * (-delta) / mtow] if bool(ev.get("over_mtow", false)) else "✔ legal (%.0f kg spare)" % delta
	var r0: float = float(ev.get("range_clean_km", 0.0))
	var r1: float = float(ev.get("range_loaded_km", 0.0))
	var h0: int = int(ev.get("range_clean_hexes", 0))
	var h1: int = int(ev.get("range_loaded_hexes", 0))
	var two := int(ev.get("two_leg_radius_hexes", -1))
	var rad := int(ev.get("radius_hexes", 0))
	var rad_line := "Strike radius   %d hexes" % rad
	if two >= 0:
		rad_line += "  (%d if bombs released over target)" % two
	var v_line := "Top speed  —"
	if bool(ev.get("has_v_max", false)):
		v_line = "Top speed  %.0f → %.0f km/h" % [float(ev.get("v_max_clean_kmh", 0.0)), float(ev.get("v_max_loaded_kmh", 0.0))]
	var to_line := "Takeoff —"
	if bool(ev.get("has_takeoff", false)):
		to_line = "Takeoff ≈%.1f–%.1f km concrete" % [float(ev.get("takeoff_lo_m", 0.0)) / 1000.0, float(ev.get("takeoff_hi_m", 0.0)) / 1000.0]
	var cal: Dictionary = ev.get("calibration", {}) as Dictionary
	var sourced: float = UnitPhysics.sourced_range_km(block)
	var src_id := str(cal.get("source_id", ""))
	var preset_r: float = float(cal.get("result", r0))
	if str(block.get("id", "")) == "f16c":
		preset_r = float(cal.get("result", r1))
	var ratio: float = float(cal.get("ratio", 0.0))
	var cal_line := "Sourced %s [%s] → preset %.0f km (%+.1f%%) · k=%.4f" % [
		_fmt_sourced(cal, sourced), src_id, preset_r, (ratio - 1.0) * 100.0, float(ev.get("k_preset", 0.0)),
	]
	if str(block.get("id", "")) == "p47d":
		cal_line += "  · candidate source, pending"
	if str(block.get("id", "")) == "f16c":
		cal_line += "  · combat range derived (ferry-calibrated)"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s  ▸  Loadout: %s            %s" % [name, load_lbl, field])
	lines.append("Weight     %.0f / %.0f kg  %s  %.1f%%   %s" % [w_i, mtow, bar, 100.0 * frac, legal])
	lines.append("Breakdown  empty %.0f · other %.0f · fuel %.0f · payload %.0f kg" % [
		float(ev.get("w_e_kg", 0.0)), float(ev.get("w_other_kg", 0.0)),
		float(ev.get("w_fuel_kg", 0.0)), float(ev.get("w_payload_kg", 0.0)),
	])
	lines.append("Range      %.0f → %.0f km   (%d → %d hexes)   weight −%.0f%%, bomb drag −%.0f%%" % [
		r0, r1, h0, h1, float(ev.get("weight_loss_pct", 0.0)), float(ev.get("drag_loss_pct", 0.0)),
	])
	lines.append(rad_line)
	lines.append("%s   Climb/agility −%.0f%%   %s" % [v_line, float(ev.get("agility_delta_pct", 0.0)), to_line])
	lines.append(cal_line)
	if bool(ev.get("k_soft_warning", false)):
		lines.append("k_preset outside [0.35, 0.75] (soft warning; k is the only fitted parameter)")
	var rato: Dictionary = ev.get("rato", {}) as Dictionary
	lines.append("RATO overload: deferred %s · allowed=%s" % [str(rato.get("deferred", "P2")), str(rato.get("allowed", false))])
	for w in ev.get("warnings", []) as Array:
		if w is Dictionary:
			var wd: Dictionary = w as Dictionary
			lines.append("⚠ %s" % str(wd.get("text", "")))
			if wd.get("fixes", []) is Array:
				for fx in wd.get("fixes", []) as Array:
					lines.append("   → %s" % str(fx))
	return "\n".join(lines)


func _fmt_sourced(cal: Dictionary, sourced_km: float) -> String:
	var unit := str(cal.get("unit", "km"))
	var raw: float = float(cal.get("sourced_range", sourced_km))
	if unit == "mi":
		return "%s mi" % _comma(raw)
	if unit == "nmi":
		return "%s nmi" % _comma(raw)
	return "%s km" % _comma(raw)


func _comma(v: float) -> String:
	var digits: int = 0
	if v != floor(v):
		digits = 1
	return "%s" % String.num(v, digits)
