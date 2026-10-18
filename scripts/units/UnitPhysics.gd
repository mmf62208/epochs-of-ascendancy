# scripts/units/UnitPhysics.gd
## P1 air-physics MVP — static pure functions. Additive and read-only.
## Nothing in combat / production / missions / AI / save / TimeManager reads this.
## STORE_CLASS_EXPONENT is 1.0 (linear) so spec §4.3 Me 262 1,000 kg reproduces (×0.50).
## F2 text says ^(2/3); do not silently pick 2/3 — open for Ship/Mike.
class_name UnitPhysics
extends Object


const HEX_KM: float = 24.1
const MI_TO_KM: float = 1.609344
const NMI_TO_KM: float = 1.852
const LB_TO_KG: float = 0.45359237
const K_BREGUET_DEFAULT: float = 0.54
const D_PROP: float = 0.19
const D_JET: float = 0.25
const STORE_CLASS_EXPONENT: float = 1.0
const STORE_CLASS_REF_KG: float = 500.0
const RESERVE_FRACTION: float = 0.10
const AVGAS_LB_PER_US_GAL: float = 6.0
const AVGAS_LB_PER_IMP_GAL: float = 7.2
const AVGAS_KG_PER_L: float = 0.72
const J2_KG_PER_L: float = 0.83
const RAILS_PERMANENT_DRAG: float = 0.90
const ROCKETS_LOADED_LD: float = 0.75
const CG_AFT_GAL_THRESHOLD: float = 40.0
const CG_AFT_AGILITY_MALUS: float = 0.15
const K_SOFT_MIN: float = 0.35
const K_SOFT_MAX: float = 0.75
const WE_REF_PROP_KG: float = 4010.0
const WE_REF_JET_KG: float = 3795.0
const TARGET_RATIO_DEFAULT: float = 1.015
const TARGET_RATIO_ME262: float = 1.020
const CAL_BAND_LO: float = 1.010
const CAL_BAND_HI: float = 1.020
const FIGHTER_CG_STORE_KG: float = 1000.0
const NEAR_MTOW_FRAC: float = 0.95
const RATO_RULE: String = "≤ ~10% over MTOW; needs RATO tech; consumes RATO units; crash/wear risk; handling penalty; runway by airfield size class / carrier deck"


static func role_f(role: String) -> float:
	match str(role):
		"escort", "intercept":
			return 0.40
		"strike_heavy":
			return 0.35
		"strike_light":
			return 0.45
		"patrol":
			return 0.25
		"ferry", "missile":
			return 1.00
		_:
			return 0.40


static func lb_to_kg(x: float) -> float:
	return x * LB_TO_KG


static func us_gal_avgas_kg(gal: float) -> float:
	return gal * AVGAS_LB_PER_US_GAL * LB_TO_KG


static func imp_gal_avgas_kg(gal: float) -> float:
	return gal * AVGAS_LB_PER_IMP_GAL * LB_TO_KG


static func mi_to_km(mi: float) -> float:
	return mi * MI_TO_KM


static func nmi_to_km(nmi: float) -> float:
	return nmi * NMI_TO_KM


static func round_half_even(x: float) -> int:
	var n: int = int(floor(x))
	var frac: float = x - float(n)
	if frac < 0.5:
		return n
	if frac > 0.5:
		return n + 1
	if n % 2 == 0:
		return n
	return n + 1


static func range_hexes(r_km: float) -> int:
	return round_half_even(r_km / HEX_KM)


static func radius_hexes(f: float, r_km: float) -> int:
	return int(floor(f * r_km / HEX_KM))


static func reserve_kg(standard_internal_fuel_kg: float) -> float:
	return RESERVE_FRACTION * standard_internal_fuel_kg


static func usable_fuel_kg(loaded_fuel_kg: float, standard_internal_fuel_kg: float, apply_reserve: bool) -> float:
	if not apply_reserve:
		return loaded_fuel_kg
	return loaded_fuel_kg - reserve_kg(standard_internal_fuel_kg)


static func breguet_prop_mi(k: float, eta: float, sfc: float, ld_eff: float, w_i: float, w_f: float) -> float:
	if w_i <= 0.0 or w_f <= 0.0 or w_i <= w_f or sfc <= 0.0:
		return 0.0
	return k * 375.0 * (eta / sfc) * ld_eff * log(w_i / w_f)


static func breguet_jet_nmi(k: float, cruise_kt: float, sfc: float, ld_eff: float, w_i: float, w_f: float) -> float:
	if w_i <= 0.0 or w_f <= 0.0 or w_i <= w_f or sfc <= 0.0:
		return 0.0
	return k * (cruise_kt / sfc) * ld_eff * log(w_i / w_f)


static func range_km_from_breguet(
	engine_kind: String,
	k: float,
	ld_eff: float,
	w_i: float,
	w_f: float,
	sfc: float,
	prop_eta: float,
	cruise_kt: float,
) -> float:
	if engine_kind == "piston":
		return mi_to_km(breguet_prop_mi(k, prop_eta, sfc, ld_eff, w_i, w_f))
	return nmi_to_km(breguet_jet_nmi(k, cruise_kt, sfc, ld_eff, w_i, w_f))


static func frame_class(w_e_kg: float, frame_class_ref_role: String) -> float:
	var ref: float = WE_REF_JET_KG if frame_class_ref_role == "jet" else WE_REF_PROP_KG
	if ref <= 0.0 or w_e_kg <= 0.0:
		return 1.0
	return pow(w_e_kg / ref, 2.0 / 3.0)


static func store_class_from_weight_kg(store_weight_kg: float) -> float:
	if store_weight_kg <= 0.0:
		return 0.0
	return pow(store_weight_kg / STORE_CLASS_REF_KG, STORE_CLASS_EXPONENT)


static func ld_factor(
	engine_kind: String,
	store_class: float,
	frame_cls: float,
	rockets_loaded: bool,
	ignore_drag: bool,
	rails_only: bool,
) -> float:
	if ignore_drag:
		return 1.0
	if rails_only:
		return RAILS_PERMANENT_DRAG
	if rockets_loaded:
		return ROCKETS_LOADED_LD
	if store_class <= 0.0:
		return 1.0
	var d: float = D_JET if engine_kind == "jet" else D_PROP
	var fc: float = frame_cls if frame_cls > 0.0 else 1.0
	return 1.0 - d * (store_class / fc)


static func top_speed_kmh(v_max_kmh: float, has_v: bool, ld_fac: float, engine_kind: String) -> float:
	if not has_v:
		return -1.0
	var exp: float = 0.5 if engine_kind == "jet" else (1.0 / 3.0)
	return v_max_kmh * pow(ld_fac, exp)


static func agility_index(w_clean_kg: float, w_loaded_kg: float, ld_fac: float, aft_tank_gal: float, apply_aft: bool) -> Dictionary:
	var out: Dictionary = {"index": 0.0, "cg": false}
	if w_loaded_kg <= 0.0:
		return out
	var idx: float = (w_clean_kg / w_loaded_kg) * ld_fac
	var cg: bool = false
	if apply_aft and aft_tank_gal > CG_AFT_GAL_THRESHOLD:
		idx *= 1.0 - CG_AFT_AGILITY_MALUS
		cg = true
	out["index"] = idx
	out["cg"] = cg
	return out


static func takeoff_run_m(base_lo: float, base_hi: float, has_base: bool, w_i_kg: float, w_ref_kg: float) -> Dictionary:
	var out: Dictionary = {"lo": -1.0, "hi": -1.0, "ok": false}
	if not has_base or w_ref_kg <= 0.0:
		return out
	var ratio: float = pow(w_i_kg / w_ref_kg, 2.0)
	out["lo"] = base_lo * ratio
	out["hi"] = base_hi * ratio
	out["ok"] = true
	return out


static func two_leg_radius_hexes(r_loaded_km: float, r_clean_km: float, f: float) -> int:
	if r_loaded_km <= 0.0 or r_clean_km <= 0.0:
		return 0
	var hm: float = 2.0 / (1.0 / r_loaded_km + 1.0 / r_clean_km)
	return radius_hexes(f, hm)


static func rato_overload_check(_w_i_kg: float = 0.0, _mtow_kg: float = 0.0) -> Dictionary:
	return {
		"allowed": false,
		"deferred": "P2",
		"rule": RATO_RULE,
	}


static func fuel_to_fit_mtow_kg(w_e_kg: float, w_other_kg: float, w_payload_kg: float, mtow_kg: float) -> float:
	return maxf(0.0, mtow_kg - w_e_kg - w_other_kg - w_payload_kg)


static func ln_ratio(w_i: float, usable: float) -> float:
	var w_f: float = w_i - usable
	if w_i <= 0.0 or w_f <= 0.0 or w_i <= w_f:
		return 0.0
	return log(w_i / w_f)


static func variant_pair_model_delta(
	w_i_a: float,
	fuel_a: float,
	w_i_b: float,
	fuel_b: float,
	earlier_standard_fuel: float,
) -> float:
	var res: float = reserve_kg(earlier_standard_fuel)
	var ln_a: float = ln_ratio(w_i_a, fuel_a - res)
	var ln_b: float = ln_ratio(w_i_b, fuel_b - res)
	if ln_a <= 0.0:
		return 0.0
	return (ln_b / ln_a) - 1.0


static func pair_error(model_delta: float, real_delta: float) -> Dictionary:
	var model_ratio: float = 1.0 + model_delta
	var real_ratio: float = 1.0 + real_delta
	var err: float = 0.0
	if real_ratio != 0.0:
		err = (model_ratio / real_ratio) - 1.0
	return {
		"model_delta": model_delta,
		"real_delta": real_delta,
		"error": err,
		"model_pct": model_delta * 100.0,
		"real_pct": real_delta * 100.0,
		"error_pct": err * 100.0,
		"model_ratio": model_ratio,
		"real_ratio": real_ratio,
	}


static func p51_tank_pair() -> Dictionary:
	var fuel_a: float = 180.0 * AVGAS_LB_PER_US_GAL
	var fuel_b: float = 269.0 * AVGAS_LB_PER_US_GAL
	var model: float = variant_pair_model_delta(9200.0, fuel_a, 9800.0, fuel_b, fuel_a)
	var real: float = (1180.0 / 755.0) - 1.0
	return pair_error(model, real)


static func p51_bc_to_d_pair() -> Dictionary:
	var fuel: float = 269.0 * AVGAS_LB_PER_US_GAL
	var model: float = variant_pair_model_delta(9800.0, fuel, 10100.0, fuel, fuel)
	var real: float = (1155.0 / 1180.0) - 1.0
	return pair_error(model, real)


static func typhoon_tank_pair() -> Dictionary:
	var fuel_a: float = 154.0 * AVGAS_LB_PER_IMP_GAL
	var fuel_b: float = fuel_a + 90.0 * AVGAS_LB_PER_IMP_GAL
	var w_i_b: float = 11400.0 + 90.0 * AVGAS_LB_PER_IMP_GAL + 100.0
	var model: float = variant_pair_model_delta(11400.0, fuel_a, w_i_b, fuel_b, fuel_a)
	var real: float = (1090.0 / 690.0) - 1.0
	var out: Dictionary = pair_error(model, real)
	out["w_i_b_lb"] = w_i_b
	return out


static func sourced_range_km(block: Dictionary) -> float:
	var cal: Dictionary = block.get("calibration", {}) as Dictionary
	var val: float = float(cal.get("sourced_range", 0.0))
	var unit: String = str(cal.get("unit", "km")).to_lower()
	if unit == "mi" or unit == "mile" or unit == "miles":
		return mi_to_km(val)
	if unit == "nmi" or unit == "nm":
		return nmi_to_km(val)
	return val


static func target_ratio_for(preset_id: String) -> float:
	if preset_id == "me262_a1a":
		return TARGET_RATIO_ME262
	return TARGET_RATIO_DEFAULT


static func breguet_range_km(
	block: Dictionary,
	w_i_kg: float,
	loaded_fuel_kg: float,
	ld_fac: float,
	k: float,
	apply_reserve: bool,
) -> float:
	var kind: String = str(block.get("engine_kind", "piston"))
	var ld_eff: float = float(block.get("ld_clean", 1.0)) * ld_fac
	var std_fuel: float = float(block.get("internal_fuel_kg", 0.0))
	var usable: float = usable_fuel_kg(loaded_fuel_kg, std_fuel, apply_reserve)
	var w_f: float = w_i_kg - usable
	var eta: float = float(block.get("prop_eta", 0.0))
	var cruise: float = float(block.get("cruise_kt", 0.0))
	return range_km_from_breguet(kind, k, ld_eff, w_i_kg, w_f, float(block.get("sfc", 1.0)), eta, cruise)


static func rel_err(a: float, b: float) -> float:
	if a == 0.0 and b == 0.0:
		return 0.0
	var den: float = maxf(absf(a), maxf(absf(b), 1e-15))
	return absf(a - b) / den
