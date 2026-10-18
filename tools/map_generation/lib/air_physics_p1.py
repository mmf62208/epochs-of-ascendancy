"""P1 air-physics MVP — pure Breguet / drag / radius mirror (read-only).

Formulas and named constants match scripts/units/UnitPhysics.gd.
No RNG, no wall clock, no unsorted dict walks in the math.

STORE_CLASS_EXPONENT is 1.0 (linear) so the Me 262 1,000 kg case in spec
§4.3 reproduces (×0.50). F2 text says ^(2/3); do not silently pick 2/3.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

# --- named consts (mirrored in UnitPhysics.gd) ---
HEX_KM: float = 24.1
MI_TO_KM: float = 1.609344
NMI_TO_KM: float = 1.852
LB_TO_KG: float = 0.45359237
K_BREGUET_DEFAULT: float = 0.54
D_PROP: float = 0.19
D_JET: float = 0.25
# Linear in P1. Spec §4.3 Me 262 1,000 kg needs ×0.50; F2's (2/3) would give ×0.603.
STORE_CLASS_EXPONENT: float = 1.0
STORE_CLASS_REF_KG: float = 500.0
RESERVE_FRACTION: float = 0.10
AVGAS_LB_PER_US_GAL: float = 6.0
AVGAS_LB_PER_IMP_GAL: float = 7.2
AVGAS_KG_PER_L: float = 0.72
J2_KG_PER_L: float = 0.83
RAILS_PERMANENT_DRAG: float = 0.90
ROCKETS_LOADED_LD: float = 0.75
CG_AFT_GAL_THRESHOLD: float = 40.0
CG_AFT_AGILITY_MALUS: float = 0.15
K_SOFT_MIN: float = 0.35
K_SOFT_MAX: float = 0.75
WE_REF_PROP_KG: float = 4010.0  # Typhoon Ib empty [R53] — prop frame-class = 1.0
WE_REF_JET_KG: float = 3795.0  # Me 262 A-1a empty [spec §4.1] — jet frame-class = 1.0
TARGET_RATIO_DEFAULT: float = 1.015
TARGET_RATIO_ME262: float = 1.020
CAL_BAND_LO: float = 1.010
CAL_BAND_HI: float = 1.020
FIGHTER_CG_STORE_KG: float = 1000.0
NEAR_MTOW_FRAC: float = 0.95

ROLE_F: Dict[str, float] = {
    "escort": 0.40,
    "intercept": 0.40,
    "strike_heavy": 0.35,
    "strike_light": 0.45,
    "patrol": 0.25,
    "ferry": 1.00,
    "missile": 1.00,
}

RATO_STUB: Dict[str, Any] = {
    "allowed": False,
    "deferred": "P2",
    "rule": (
        "≤ ~10% over MTOW; needs RATO tech; consumes RATO units; "
        "crash/wear risk; handling penalty; runway by airfield size class / carrier deck"
    ),
}

ROOT = Path(__file__).resolve().parents[3]
PRESETS_PATH = ROOT / "data" / "unit_physics" / "air_presets_p1.json"
GOLDEN_PATH = ROOT / "data" / "unit_physics" / "p1_golden.json"


def lb(x: float) -> float:
    return float(x) * LB_TO_KG


def us_gal_avgas_kg(gal: float) -> float:
    return float(gal) * AVGAS_LB_PER_US_GAL * LB_TO_KG


def imp_gal_avgas_kg(gal: float) -> float:
    return float(gal) * AVGAS_LB_PER_IMP_GAL * LB_TO_KG


def mi_to_km(mi: float) -> float:
    return float(mi) * MI_TO_KM


def nmi_to_km(nmi: float) -> float:
    return float(nmi) * NMI_TO_KM


def km_to_mi(km: float) -> float:
    return float(km) / MI_TO_KM


def km_to_nmi(km: float) -> float:
    return float(km) / NMI_TO_KM


def round_half_even(x: float) -> int:
    """Range hexes: banker's rounding. Positive values only in P1."""
    n = math.floor(x)
    frac = x - n
    if frac < 0.5:
        return int(n)
    if frac > 0.5:
        return int(n + 1)
    return int(n) if (int(n) % 2 == 0) else int(n + 1)


def range_hexes(r_km: float) -> int:
    return round_half_even(float(r_km) / HEX_KM)


def radius_hexes(f: float, r_km: float) -> int:
    return int(math.floor(float(f) * float(r_km) / HEX_KM))


def reserve_kg(standard_internal_fuel_kg: float) -> float:
    return RESERVE_FRACTION * float(standard_internal_fuel_kg)


def usable_fuel_kg(
    loaded_fuel_kg: float,
    standard_internal_fuel_kg: float,
    apply_reserve: bool,
) -> float:
    if not apply_reserve:
        return float(loaded_fuel_kg)
    return float(loaded_fuel_kg) - reserve_kg(standard_internal_fuel_kg)


def breguet_prop_mi(
    k: float,
    eta: float,
    sfc: float,
    ld_eff: float,
    w_i: float,
    w_f: float,
) -> float:
    if w_i <= 0.0 or w_f <= 0.0 or w_i <= w_f or sfc <= 0.0:
        return 0.0
    return float(k) * 375.0 * (float(eta) / float(sfc)) * float(ld_eff) * math.log(w_i / w_f)


def breguet_jet_nmi(
    k: float,
    cruise_kt: float,
    sfc: float,
    ld_eff: float,
    w_i: float,
    w_f: float,
) -> float:
    if w_i <= 0.0 or w_f <= 0.0 or w_i <= w_f or sfc <= 0.0:
        return 0.0
    return float(k) * (float(cruise_kt) / float(sfc)) * float(ld_eff) * math.log(w_i / w_f)


def range_km_from_breguet(
    engine_kind: str,
    k: float,
    ld_eff: float,
    w_i: float,
    w_f: float,
    sfc: float,
    prop_eta: Optional[float] = None,
    cruise_kt: Optional[float] = None,
) -> float:
    kind = str(engine_kind)
    if kind == "piston":
        r_mi = breguet_prop_mi(k, float(prop_eta or 0.0), sfc, ld_eff, w_i, w_f)
        return mi_to_km(r_mi)
    r_nmi = breguet_jet_nmi(k, float(cruise_kt or 0.0), sfc, ld_eff, w_i, w_f)
    return nmi_to_km(r_nmi)


def frame_class(w_e_kg: float, frame_class_ref_role: str) -> float:
    ref = WE_REF_JET_KG if str(frame_class_ref_role) == "jet" else WE_REF_PROP_KG
    if ref <= 0.0 or w_e_kg <= 0.0:
        return 1.0
    return (float(w_e_kg) / float(ref)) ** (2.0 / 3.0)


def store_class_from_weight_kg(store_weight_kg: float) -> float:
    if store_weight_kg <= 0.0:
        return 0.0
    return (float(store_weight_kg) / STORE_CLASS_REF_KG) ** STORE_CLASS_EXPONENT


def ld_factor(
    engine_kind: str,
    store_class: float,
    frame_cls: float,
    rockets_loaded: bool = False,
    ignore_drag: bool = False,
    rails_only: bool = False,
) -> float:
    if ignore_drag:
        return 1.0
    if rails_only:
        return RAILS_PERMANENT_DRAG
    if rockets_loaded:
        return ROCKETS_LOADED_LD
    if store_class <= 0.0:
        return 1.0
    d = D_JET if str(engine_kind) == "jet" else D_PROP
    fc = frame_cls if frame_cls > 0.0 else 1.0
    return 1.0 - d * (float(store_class) / fc)


def top_speed_kmh(v_max_kmh: Optional[float], ld_fac: float, engine_kind: str) -> Optional[float]:
    if v_max_kmh is None:
        return None
    exp = 0.5 if str(engine_kind) == "jet" else (1.0 / 3.0)
    return float(v_max_kmh) * (float(ld_fac) ** exp)


def agility_index(
    w_clean_kg: float,
    w_loaded_kg: float,
    ld_fac: float,
    aft_tank_gal: Optional[float] = None,
) -> Tuple[float, bool]:
    if w_loaded_kg <= 0.0:
        return 0.0, False
    idx = (float(w_clean_kg) / float(w_loaded_kg)) * float(ld_fac)
    cg = False
    if aft_tank_gal is not None and float(aft_tank_gal) > CG_AFT_GAL_THRESHOLD:
        idx *= 1.0 - CG_AFT_AGILITY_MALUS
        cg = True
    return idx, cg


def takeoff_run_m(
    base_lo: Optional[float],
    base_hi: Optional[float],
    w_i_kg: float,
    w_ref_kg: float,
) -> Tuple[Optional[float], Optional[float]]:
    if base_lo is None or base_hi is None or w_ref_kg <= 0.0:
        return None, None
    ratio = (float(w_i_kg) / float(w_ref_kg)) ** 2.0
    return float(base_lo) * ratio, float(base_hi) * ratio


def two_leg_radius_hexes(r_loaded_km: float, r_clean_km: float, f: float) -> int:
    if r_loaded_km <= 0.0 or r_clean_km <= 0.0:
        return 0
    hm = 2.0 / (1.0 / float(r_loaded_km) + 1.0 / float(r_clean_km))
    return radius_hexes(f, hm)


def rato_overload_check(*_args: Any, **_kwargs: Any) -> Dict[str, Any]:
    """P1 stub. Never legalises an over-MTOW loadout."""
    out: Dict[str, Any] = {}
    keys = sorted(RATO_STUB.keys())
    for k in keys:
        out[k] = RATO_STUB[k]
    return out


def fuel_to_fit_mtow_kg(
    w_e_kg: float,
    w_other_kg: float,
    w_payload_kg: float,
    mtow_kg: float,
) -> float:
    return max(0.0, float(mtow_kg) - float(w_e_kg) - float(w_other_kg) - float(w_payload_kg))


def _sorted_items(d: Mapping[str, Any]) -> List[Tuple[str, Any]]:
    return [(k, d[k]) for k in sorted(d.keys())]


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_presets(path: Optional[Path] = None) -> Dict[str, Dict[str, Any]]:
    p = path or PRESETS_PATH
    data = load_json(p)
    if not isinstance(data, dict):
        raise ValueError("air_presets_p1.json must be an object")
    presets = data.get("presets", data)
    if not isinstance(presets, dict):
        raise ValueError("air_presets_p1.json presets must be an object")
    out: Dict[str, Dict[str, Any]] = {}
    for key in sorted(presets.keys()):
        block = presets[key]
        if not isinstance(block, dict):
            raise ValueError("preset %s is not an object" % key)
        out[str(key)] = block
    return out


def validate_preset(block: Mapping[str, Any]) -> List[str]:
    errs: List[str] = []
    required = [
        "id",
        "display_name",
        "variant",
        "template_id",
        "engine_kind",
        "frame_class_ref_role",
        "profile",
        "empty_weight_kg",
        "other_fixed_kg",
        "internal_fuel_kg",
        "gross_clean_kg",
        "mtow_kg",
        "sfc",
        "ld_clean",
        "calibration",
        "labels",
    ]
    for k in required:
        if k not in block:
            errs.append("missing %s" % k)
    kind = str(block.get("engine_kind", ""))
    if kind == "piston" and "prop_eta" not in block:
        errs.append("piston missing prop_eta")
    if kind == "jet" and "cruise_kt" not in block:
        errs.append("jet missing cruise_kt")
    cal = block.get("calibration") if isinstance(block.get("calibration"), dict) else {}
    for k in ("sourced_range", "unit", "source_id", "profile", "target_band", "fitted_param", "fitted_value"):
        if k not in cal:
            errs.append("calibration missing %s" % k)
    we = float(block.get("empty_weight_kg", 0.0))
    oth = float(block.get("other_fixed_kg", 0.0))
    fuel = float(block.get("internal_fuel_kg", 0.0))
    gross = float(block.get("gross_clean_kg", 0.0))
    if abs((we + oth + fuel) - gross) > 1.0:
        errs.append(
            "gross_clean_kg != empty+other+fuel (%.4f vs %.4f)" % (gross, we + oth + fuel)
        )
    return errs


def _base_takeoff(block: Mapping[str, Any]) -> Tuple[Optional[float], Optional[float]]:
    raw = block.get("base_takeoff_m")
    if raw is None:
        return None, None
    if isinstance(raw, (list, tuple)) and len(raw) >= 2:
        return float(raw[0]), float(raw[1])
    return None, None


def _v_max(block: Mapping[str, Any]) -> Optional[float]:
    v = block.get("v_max_kmh")
    if v is None:
        return None
    return float(v)


def sourced_range_km(block: Mapping[str, Any]) -> float:
    cal = block.get("calibration") if isinstance(block.get("calibration"), dict) else {}
    val = float(cal.get("sourced_range", 0.0))
    unit = str(cal.get("unit", "km")).lower()
    if unit in ("mi", "mile", "miles"):
        return mi_to_km(val)
    if unit in ("nmi", "nm"):
        return nmi_to_km(val)
    return val


def target_ratio_for(preset_id: str) -> float:
    return TARGET_RATIO_ME262 if str(preset_id) == "me262_a1a" else TARGET_RATIO_DEFAULT


def clean_weights(block: Mapping[str, Any]) -> Tuple[float, float, float, float, float]:
    w_e = float(block["empty_weight_kg"])
    w_o = float(block["other_fixed_kg"])
    w_f = float(block["internal_fuel_kg"])
    w_i = float(block["gross_clean_kg"])
    mtow = float(block["mtow_kg"])
    return w_e, w_o, w_f, w_i, mtow


def breguet_range_km(
    block: Mapping[str, Any],
    w_i_kg: float,
    loaded_fuel_kg: float,
    ld_fac: float,
    k: Optional[float] = None,
    apply_reserve: Optional[bool] = None,
) -> float:
    kind = str(block["engine_kind"])
    k_use = float(k if k is not None else block.get("calibration", {}).get("fitted_value", K_BREGUET_DEFAULT))
    ld_eff = float(block["ld_clean"]) * float(ld_fac)
    std_fuel = float(block["internal_fuel_kg"])
    if apply_reserve is None:
        apply_reserve = str(block.get("profile", "combat")) != "ferry"
    usable = usable_fuel_kg(loaded_fuel_kg, std_fuel, apply_reserve)
    w_f = float(w_i_kg) - usable
    return range_km_from_breguet(
        kind,
        k_use,
        ld_eff,
        float(w_i_kg),
        w_f,
        float(block["sfc"]),
        prop_eta=float(block["prop_eta"]) if "prop_eta" in block else None,
        cruise_kt=float(block["cruise_kt"]) if "cruise_kt" in block else None,
    )


def fit_k_preset(block: Mapping[str, Any], target_ratio: Optional[float] = None) -> float:
    """Fit only k_preset so R_preset / R_sourced == target_ratio."""
    pid = str(block.get("id", ""))
    ratio = float(target_ratio if target_ratio is not None else target_ratio_for(pid))
    sourced = sourced_range_km(block)
    target = sourced * ratio
    if str(block.get("profile", "combat")) == "ferry" and "ferry_fuel_kg" in block:
        w_e = float(block["empty_weight_kg"])
        w_o = float(block["other_fixed_kg"])
        fuel = float(block["ferry_fuel_kg"])
        w_i = w_e + w_o + fuel
        r1 = breguet_range_km(block, w_i, fuel, 1.0, k=1.0, apply_reserve=False)
    else:
        _w_e, _w_o, fuel, w_i, _mtow = clean_weights(block)
        r1 = breguet_range_km(block, w_i, fuel, 1.0, k=1.0, apply_reserve=True)
    if r1 <= 0.0:
        return K_BREGUET_DEFAULT
    return target / r1


def ln_ratio(w_i: float, usable: float) -> float:
    w_f = float(w_i) - float(usable)
    if w_i <= 0.0 or w_f <= 0.0 or w_i <= w_f:
        return 0.0
    return math.log(w_i / w_f)


def variant_pair_model_delta(
    w_i_a: float,
    fuel_a: float,
    w_i_b: float,
    fuel_b: float,
    earlier_standard_fuel: float,
) -> float:
    """Ratio method: k cancels. Reserve = 10% of the earlier variant's standard fuel."""
    res = reserve_kg(earlier_standard_fuel)
    ln_a = ln_ratio(w_i_a, fuel_a - res)
    ln_b = ln_ratio(w_i_b, fuel_b - res)
    if ln_a <= 0.0:
        return 0.0
    return (ln_b / ln_a) - 1.0


def _pair_error(model_delta: float, real_delta: float) -> Dict[str, float]:
    """Ratio-method error: (R_new/R_old)_model / (R_new/R_old)_real − 1."""
    model_ratio = 1.0 + float(model_delta)
    real_ratio = 1.0 + float(real_delta)
    err = (model_ratio / real_ratio) - 1.0 if real_ratio != 0.0 else 0.0
    return {
        "model_delta": float(model_delta),
        "real_delta": float(real_delta),
        "error": err,
        "model_pct": float(model_delta) * 100.0,
        "real_pct": float(real_delta) * 100.0,
        "error_pct": err * 100.0,
        "model_ratio": model_ratio,
        "real_ratio": real_ratio,
    }


def p51_tank_pair() -> Dict[str, float]:
    # 180 → 269 US gal; W_i 9,200 → 9,800 lb; real 755 → 1,180 mi (+56.3%)
    fuel_a = 180.0 * AVGAS_LB_PER_US_GAL
    fuel_b = 269.0 * AVGAS_LB_PER_US_GAL
    model = variant_pair_model_delta(9200.0, fuel_a, 9800.0, fuel_b, fuel_a)
    real = (1180.0 / 755.0) - 1.0
    return _pair_error(model, real)


def p51_bc_to_d_pair() -> Dict[str, float]:
    # 269 gal both; W_i 9,800 → 10,100 lb; real 1,180 → 1,155 mi (−2.1%)
    fuel = 269.0 * AVGAS_LB_PER_US_GAL
    model = variant_pair_model_delta(9800.0, fuel, 10100.0, fuel, fuel)
    real = (1155.0 / 1180.0) - 1.0
    return _pair_error(model, real)


def typhoon_tank_pair() -> Dict[str, float]:
    # 154 imp gal + 90 imp gal; tanks 100 lb ESTIMATE; drag ignored
    fuel_a = 154.0 * AVGAS_LB_PER_IMP_GAL
    fuel_b = fuel_a + 90.0 * AVGAS_LB_PER_IMP_GAL
    w_i_b = 11400.0 + 90.0 * AVGAS_LB_PER_IMP_GAL + 100.0
    model = variant_pair_model_delta(11400.0, fuel_a, w_i_b, fuel_b, fuel_a)
    real = (1090.0 / 690.0) - 1.0
    out = _pair_error(model, real)
    out["w_i_b_lb"] = w_i_b
    return out


def default_loadouts(block: Mapping[str, Any]) -> List[Dict[str, Any]]:
    pid = str(block.get("id", ""))
    extras: List[Dict[str, Any]]
    if pid == "me262_a1a":
        extras = [
            {
                "id": "sc500_racks",
                "label": "1 × SC 500 + ETC racks (560 kg)",
                "payload_kg": 560.0,
                "store_class": 1.0,
                "store_weight_kg": 500.0,
                "droppable": True,
                "default_role": "strike_light",
            },
            {
                "id": "kg1000_racks",
                "label": "1,000 kg + racks (1,060 kg)",
                "payload_kg": 1060.0,
                "store_class": 2.0,
                "store_weight_kg": 1000.0,
                "droppable": True,
                "default_role": "strike_heavy",
            },
        ]
    elif pid == "typhoon_ib":
        extras = [
            {
                "id": "2x500lb",
                "label": "2 × 500 lb",
                "payload_kg": lb(1000.0),
                "store_class": 1.0,
                "store_weight_kg": lb(1000.0),
                "droppable": True,
                "default_role": "strike_light",
            },
            {
                "id": "2x45imp",
                "label": "2 × 45 gal tanks",
                "payload_kg": lb(100.0),
                "extra_fuel_kg": imp_gal_avgas_kg(90.0),
                "store_class": 0.0,
                "ignore_drag": True,
                "droppable": True,
                "default_role": "ferry",
            },
            {
                "id": "rp3",
                "label": "8 × RP-3",
                "payload_kg": lb(640.0),
                "store_class": 0.0,
                "rockets_loaded": True,
                "droppable": True,
                "default_role": "strike_light",
            },
        ]
    elif pid == "p51d":
        extras = [
            {
                "id": "2x1000lb",
                "label": "2 × 1,000 lb",
                "payload_kg": lb(2000.0),
                "store_class": store_class_from_weight_kg(lb(2000.0)),
                "store_weight_kg": lb(2000.0),
                "droppable": True,
                "default_role": "strike_heavy",
            },
            {
                "id": "aft85",
                "label": "85 gal aft tank full",
                "payload_kg": 0.0,
                "store_class": 0.0,
                "aft_tank_gal": 85.0,
                "droppable": False,
                "default_role": "escort",
            },
        ]
    elif pid == "f16c":
        extras = [
            {
                "id": "ferry_2tanks",
                "label": "2 × tanks (ferry, no reserve)",
                "payload_kg": 0.0,
                "extra_fuel_kg": lb(5000.0),
                "store_class": 0.0,
                "ignore_drag": True,
                "apply_reserve": False,
                "droppable": True,
                "default_role": "ferry",
            },
            {
                "id": "2x500lb",
                "label": "2 × 500 lb",
                "payload_kg": lb(1000.0),
                "store_class": 1.0,
                "store_weight_kg": lb(1000.0),
                "droppable": True,
                "default_role": "strike_light",
            },
        ]
    else:
        extras = [
            {
                "id": "2x500lb",
                "label": "2 × 500 lb",
                "payload_kg": lb(1000.0),
                "store_class": 1.0,
                "store_weight_kg": lb(1000.0),
                "droppable": True,
                "default_role": "strike_light",
            }
        ]
    clean = {
        "id": "clean",
        "label": "Clean (internal)",
        "payload_kg": 0.0,
        "store_class": 0.0,
        "droppable": False,
        "default_role": "escort" if pid != "b17g" else "strike_heavy",
    }
    if pid == "f16c":
        clean["default_role"] = "escort"
        clean["derived_combat"] = True
        clean["apply_reserve"] = True
    return [clean] + extras


def evaluate(
    block: Mapping[str, Any],
    loadout: Optional[Mapping[str, Any]] = None,
    role: str = "",
    fuel_override_kg: Optional[float] = None,
) -> Dict[str, Any]:
    w_e, w_o, std_fuel, w_clean, mtow = clean_weights(block)
    lo = dict(loadout or {"id": "clean", "payload_kg": 0.0, "store_class": 0.0})
    payload = float(lo.get("payload_kg", 0.0))
    extra_fuel = float(lo.get("extra_fuel_kg", 0.0))
    fuel = std_fuel + extra_fuel if fuel_override_kg is None else float(fuel_override_kg)
    w_i = w_e + w_o + fuel + payload
    kind = str(block["engine_kind"])
    fc = frame_class(w_e, str(block["frame_class_ref_role"]))
    sc = float(lo.get("store_class", 0.0))
    ld_fac = ld_factor(
        kind,
        sc,
        fc,
        rockets_loaded=bool(lo.get("rockets_loaded", False)),
        ignore_drag=bool(lo.get("ignore_drag", False)),
        rails_only=bool(lo.get("rails_only", False)),
    )
    apply_reserve = lo.get("apply_reserve")
    if apply_reserve is None:
        apply_reserve = str(block.get("profile", "combat")) != "ferry"
    profile_is_ferry_cal = str(block.get("profile", "combat")) == "ferry" and str(lo.get("id", "")) != "clean"
    if str(lo.get("id", "")) == "ferry_2tanks":
        apply_reserve = False
        profile_is_ferry_cal = True
    if str(lo.get("id", "")) == "clean" and bool(lo.get("derived_combat", False)):
        apply_reserve = True
        profile_is_ferry_cal = False

    k = float(block.get("calibration", {}).get("fitted_value", K_BREGUET_DEFAULT))
    r_clean = breguet_range_km(block, w_clean, std_fuel, 1.0, k=k, apply_reserve=True if bool(lo.get("derived_combat", False)) else apply_reserve if str(lo.get("id", "clean")) == "clean" else True)
    # Clean combat range always uses standard internal + reserve, except the
    # ferry calibration loadout itself (F-16 2 tanks).
    if str(block.get("id", "")) == "f16c" and str(lo.get("id", "")) == "clean":
        r_clean = breguet_range_km(block, w_clean, std_fuel, 1.0, k=k, apply_reserve=True)
    elif str(block.get("id", "")) == "f16c" and str(lo.get("id", "")) == "ferry_2tanks":
        r_clean = breguet_range_km(
            block,
            w_e + w_o + (std_fuel + extra_fuel),
            std_fuel + extra_fuel,
            1.0,
            k=k,
            apply_reserve=False,
        )
    else:
        r_clean = breguet_range_km(block, w_clean, std_fuel, 1.0, k=k, apply_reserve=True)

    r_loaded = breguet_range_km(block, w_i, fuel, ld_fac, k=k, apply_reserve=apply_reserve)
    usable_c = usable_fuel_kg(std_fuel, std_fuel, True)
    usable_l = usable_fuel_kg(fuel, std_fuel, bool(apply_reserve))
    ln_c = ln_ratio(w_clean, usable_c)
    ln_l = ln_ratio(w_i, usable_l)
    weight_loss = 0.0 if ln_c <= 0.0 else (1.0 - (ln_l / ln_c)) * 100.0
    drag_loss = (1.0 - ld_fac) * 100.0

    role_key = str(role).strip() or str(lo.get("default_role", "escort"))
    if role_key not in ROLE_F:
        role_key = "escort"
    f = ROLE_F[role_key]
    droppable = bool(lo.get("droppable", False)) and payload > 0.0 or bool(lo.get("rockets_loaded", False)) or extra_fuel > 0.0 and bool(lo.get("droppable", False))
    two_leg = two_leg_radius_hexes(r_loaded, r_clean, f) if droppable else None

    aft = lo.get("aft_tank_gal", block.get("aft_tank_gal"))
    aft_f = float(aft) if aft is not None else None
    # Clean P-51D 269 gal includes the 85 gal aft tank.
    if aft_f is None and block.get("aft_tank_gal") is not None:
        aft_f = float(block["aft_tank_gal"])
    agi, cg_aft = agility_index(w_clean, w_i, ld_fac, aft_f)
    agi_clean, _ = agility_index(w_clean, w_clean, 1.0, None)
    agi_delta = 0.0 if agi_clean <= 0.0 else (1.0 - agi / agi_clean) * 100.0

    v_clean = _v_max(block)
    v_loaded = top_speed_kmh(v_clean, ld_fac, kind)
    t_lo, t_hi = _base_takeoff(block)
    to_lo, to_hi = takeoff_run_m(t_lo, t_hi, w_i, w_clean)

    over = w_i - mtow
    frac = w_i / mtow if mtow > 0.0 else 0.0
    fuel_cut_kg = None
    fuel_cut_L = None
    fuel_cut_range = None
    fuel_cut_radius = None
    density = float(block.get("fuel_density_kg_per_L") or (J2_KG_PER_L if kind == "jet" else AVGAS_KG_PER_L))
    if over > 0.0:
        fuel_cut_kg = fuel_to_fit_mtow_kg(w_e, w_o, payload, mtow)
        fuel_cut_L = fuel_cut_kg / density if density > 0.0 else 0.0
        w_fit = w_e + w_o + fuel_cut_kg + payload
        fuel_cut_range = breguet_range_km(
            block, w_fit, fuel_cut_kg, ld_fac, k=k, apply_reserve=True
        )
        fuel_cut_radius = radius_hexes(f, fuel_cut_range)

    fighter = str(block.get("id", "")) != "b17g"
    warnings: List[Dict[str, Any]] = []
    if over > 0.0:
        warnings.append(
            {
                "id": "overweight",
                "severity": "error",
                "text": "OVER by %.0f kg (%.1f%%)" % (over, 100.0 * over / mtow),
                "fixes": [
                    "cut fuel to %.0f L, giving radius %s"
                    % (fuel_cut_L or 0.0, fuel_cut_radius if fuel_cut_radius is not None else "—"),
                    "RATO overload (deferred to P2, see the D7 rule)",
                    "choose a bomber frame",
                ],
            }
        )
    elif frac >= NEAR_MTOW_FRAC:
        warnings.append(
            {
                "id": "near_mtow",
                "severity": "warn",
                "text": "Near MTOW (%.1f%%) — %.0f kg spare" % (100.0 * frac, mtow - w_i),
                "fixes": ["leave a fuel or store margin"],
            }
        )
    if cg_aft:
        warnings.append(
            {
                "id": "cg_aft",
                "severity": "warn",
                "text": "burn the aft tank first; no hard manoeuvres",
                "fixes": ["burn the aft tank first; no hard manoeuvres above 40 gal"],
            }
        )
    if fighter and payload >= FIGHTER_CG_STORE_KG:
        warnings.append(
            {
                "id": "cg_heavy_store",
                "severity": "warn",
                "text": "≥1,000 kg store on a fighter frame (DESIGN PICK)",
                "fixes": ["use a bomber frame or a lighter store"],
            }
        )
    if to_hi is not None:
        warnings.append(
            {
                "id": "field_length",
                "severity": "info",
                "text": "needs concrete ≥ %.0f m" % to_hi,
                "fixes": ["needs concrete ≥ %.0f m" % to_hi],
            }
        )
    notes = block.get("flavour_notes") if isinstance(block.get("flavour_notes"), list) else []
    for i, note in enumerate(notes):
        warnings.append({"id": "flavour_%d" % i, "severity": "info", "text": str(note), "fixes": []})
    caveats = block.get("source_caveats") if isinstance(block.get("source_caveats"), list) else []
    for i, note in enumerate(caveats):
        warnings.append({"id": "caveat_%d" % i, "severity": "info", "text": str(note), "fixes": []})

    cal = block.get("calibration") if isinstance(block.get("calibration"), dict) else {}
    rato = rato_overload_check()
    return {
        "preset_id": str(block.get("id", "")),
        "loadout_id": str(lo.get("id", "clean")),
        "loadout_label": str(lo.get("label", "Clean")),
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
        "range_clean_hexes": range_hexes(r_clean),
        "range_loaded_hexes": range_hexes(r_loaded),
        "weight_loss_pct": weight_loss,
        "drag_loss_pct": drag_loss,
        "ld_factor": ld_fac,
        "radius_hexes": radius_hexes(f, r_loaded),
        "two_leg_radius_hexes": two_leg,
        "v_max_clean_kmh": v_clean,
        "v_max_loaded_kmh": v_loaded,
        "agility": agi,
        "agility_delta_pct": agi_delta,
        "takeoff_lo_m": to_lo,
        "takeoff_hi_m": to_hi,
        "fuel_cut_kg": fuel_cut_kg,
        "fuel_cut_L": fuel_cut_L,
        "fuel_cut_range_km": fuel_cut_range,
        "fuel_cut_radius_hexes": fuel_cut_radius,
        "warnings": warnings,
        "k_preset": k,
        "k_soft_warning": k < K_SOFT_MIN or k > K_SOFT_MAX,
        "calibration": cal,
        "rato": rato,
        "apply_reserve": bool(apply_reserve),
        "frame_class": fc,
        "store_class": sc,
    }


def me262_cases(block: Mapping[str, Any]) -> Dict[str, Dict[str, Any]]:
    """Spec §5 reference cases. Inputs are the Me 262 preset + explicit stores."""
    loadouts = {lo["id"]: lo for lo in default_loadouts(block)}
    clean = evaluate(block, loadouts["clean"], "escort")
    sc500 = evaluate(block, loadouts["sc500_racks"], "strike_light")
    kg1000 = evaluate(block, loadouts["kg1000_racks"], "strike_heavy")
    cut = evaluate(block, loadouts["kg1000_racks"], "strike_heavy", fuel_override_kg=1257.0)
    # fuel-cut-to-fit uses computed fuel, not the hard 1257, but §5 says 1,257 kg.
    # Use the explicit 1,257 kg so the golden matches the table; also record computed.
    computed_cut = evaluate(
        block,
        loadouts["kg1000_racks"],
        "strike_heavy",
        fuel_override_kg=fuel_to_fit_mtow_kg(
            float(block["empty_weight_kg"]),
            float(block["other_fixed_kg"]),
            1060.0,
            float(block["mtow_kg"]),
        ),
    )
    return {
        "clean": clean,
        "sc500": sc500,
        "kg1000_full": kg1000,
        "kg1000_fuel_cut": cut,
        "kg1000_fuel_cut_computed": computed_cut,
    }


def calibration_row(block: Mapping[str, Any]) -> Dict[str, Any]:
    cal = block.get("calibration") if isinstance(block.get("calibration"), dict) else {}
    sourced = sourced_range_km(block)
    ev = evaluate(block, {"id": "clean", "payload_kg": 0.0, "store_class": 0.0, "derived_combat": bool(block.get("id") == "f16c")}, "escort")
    if str(block.get("id")) == "f16c":
        # Ferry calibration uses the 2-tank loadout, no reserve.
        tanks = [lo for lo in default_loadouts(block) if lo["id"] == "ferry_2tanks"][0]
        ev = evaluate(block, tanks, "ferry")
    result = float(ev["range_loaded_km"])
    ratio = result / sourced if sourced > 0.0 else 0.0
    k = float(cal.get("fitted_value", ev["k_preset"]))
    return {
        "id": str(block.get("id")),
        "display_name": str(block.get("display_name")),
        "sourced_km": sourced,
        "source_id": str(cal.get("source_id", "")),
        "profile": str(cal.get("profile", block.get("profile"))),
        "result_km": result,
        "ratio": ratio,
        "k_preset": k,
        "in_band": CAL_BAND_LO <= ratio <= CAL_BAND_HI and result + 1e-9 >= sourced,
        "k_soft_warning": k < K_SOFT_MIN or k > K_SOFT_MAX,
        "hexes": int(ev["range_loaded_hexes"]),
        "unit": str(cal.get("unit", "km")),
        "sourced_raw": float(cal.get("sourced_range", 0.0)),
    }


def build_golden(presets: Mapping[str, Mapping[str, Any]]) -> Dict[str, Any]:
    cal_rows: Dict[str, Any] = {}
    for pid in sorted(presets.keys()):
        cal_rows[pid] = calibration_row(presets[pid])
    me = presets["me262_a1a"]
    cases = me262_cases(me)
    slim_cases: Dict[str, Any] = {}
    keep = [
        "w_i_kg",
        "mtow_delta_kg",
        "mtow_frac",
        "over_mtow",
        "range_loaded_km",
        "range_clean_km",
        "range_loaded_hexes",
        "radius_hexes",
        "two_leg_radius_hexes",
        "v_max_loaded_kmh",
        "agility",
        "agility_delta_pct",
        "takeoff_lo_m",
        "takeoff_hi_m",
        "weight_loss_pct",
        "drag_loss_pct",
        "ld_factor",
        "fuel_cut_kg",
        "fuel_cut_L",
        "fuel_cut_range_km",
        "fuel_cut_radius_hexes",
        "w_fuel_kg",
    ]
    for name, ev in cases.items():
        slim_cases[name] = {k: ev.get(k) for k in keep}

    f35 = evaluate(presets["f35a"], {"id": "clean", "payload_kg": 0.0, "store_class": 0.0}, "strike_light")
    return {
        "schema": "eoa_p1_air_physics_golden_v1",
        "constants": {
            "HEX_KM": HEX_KM,
            "MI_TO_KM": MI_TO_KM,
            "NMI_TO_KM": NMI_TO_KM,
            "K_BREGUET_DEFAULT": K_BREGUET_DEFAULT,
            "D_PROP": D_PROP,
            "D_JET": D_JET,
            "STORE_CLASS_EXPONENT": STORE_CLASS_EXPONENT,
            "WE_REF_PROP_KG": WE_REF_PROP_KG,
            "WE_REF_JET_KG": WE_REF_JET_KG,
            "RESERVE_FRACTION": RESERVE_FRACTION,
        },
        "presets": cal_rows,
        "me262_cases": slim_cases,
        "variant_pairs": {
            "p51_tank": p51_tank_pair(),
            "p51_bc_to_d": p51_bc_to_d_pair(),
            "typhoon_tanks": typhoon_tank_pair(),
        },
        "f35a_light_strike": {
            "range_km": f35["range_loaded_km"],
            "range_hexes_unrounded": float(f35["range_loaded_km"]) / HEX_KM,
            "radius_hexes": f35["radius_hexes"],
            "f": 0.45,
        },
        "rato": rato_overload_check(),
    }


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")


def report_text(presets: Mapping[str, Mapping[str, Any]]) -> str:
    rows = [calibration_row(presets[pid]) for pid in sorted(presets.keys())]
    lines = [
        "P1 air-physics calibration (k_preset only; target 1.015, Me 262 = 1.020)",
        "id                sourced_km  result_km  ratio   k_preset  band  src",
        "-" * 78,
    ]
    for r in rows:
        lines.append(
            "%-16s %10.3f %10.3f %6.4f %8.5f  %s  %s"
            % (
                r["id"],
                r["sourced_km"],
                r["result_km"],
                r["ratio"],
                r["k_preset"],
                "OK" if r["in_band"] else "OUT",
                r["source_id"],
            )
        )
    pairs = {
        "P-51 tank 180→269": p51_tank_pair(),
        "P-51 B/C→D": p51_bc_to_d_pair(),
        "Typhoon +2×45 gal": typhoon_tank_pair(),
    }
    lines.append("")
    lines.append("Variant pairs (k cancels; |error| ≤ 5%)")
    for name in sorted(pairs.keys()):
        p = pairs[name]
        lines.append(
            "  %s  model %+.2f%%  real %+.2f%%  error %+.2f%%"
            % (name, p["model_pct"], p["real_pct"], p["error_pct"])
        )
    return "\n".join(lines) + "\n"


def rel_err(a: float, b: float) -> float:
    if a == 0.0 and b == 0.0:
        return 0.0
    den = max(abs(a), abs(b), 1e-15)
    return abs(float(a) - float(b)) / den


def compare_golden(computed: Mapping[str, Any], stored: Mapping[str, Any], tol: float = 1e-9) -> Tuple[int, float, List[str]]:
    """Walk both trees; floats within rel 1e-9, ints exact."""
    n = 0
    max_rel = 0.0
    fails: List[str] = []

    def walk(c: Any, s: Any, path: str) -> None:
        nonlocal n, max_rel
        if isinstance(c, dict) and isinstance(s, dict):
            keys = sorted(set(list(c.keys()) + list(s.keys())))
            for k in keys:
                if k not in c or k not in s:
                    fails.append("%s: key mismatch %s" % (path, k))
                    continue
                walk(c[k], s[k], path + "." + str(k))
            return
        if isinstance(c, bool) or isinstance(s, bool):
            n += 1
            if c != s:
                fails.append("%s: bool %s vs %s" % (path, c, s))
            return
        if isinstance(c, int) and not isinstance(c, bool) and isinstance(s, int) and not isinstance(s, bool):
            n += 1
            if c != s:
                fails.append("%s: int %s vs %s" % (path, c, s))
            return
        if isinstance(c, (int, float)) and isinstance(s, (int, float)):
            n += 1
            e = rel_err(float(c), float(s))
            if e > max_rel:
                max_rel = e
            if e > tol:
                fails.append("%s: float %s vs %s rel=%g" % (path, c, s, e))
            return
        n += 1
        if c != s:
            fails.append("%s: %r vs %r" % (path, c, s))

    walk(computed, stored, "golden")
    return n, max_rel, fails


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="P1 air-physics Python mirror")
    parser.add_argument("--write-golden", action="store_true")
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--presets", type=str, default=str(PRESETS_PATH))
    parser.add_argument("--golden", type=str, default=str(GOLDEN_PATH))
    args = parser.parse_args(list(argv) if argv is not None else None)
    presets = load_presets(Path(args.presets))
    if args.report:
        sys.stdout.write(report_text(presets))
    if args.write_golden:
        golden = build_golden(presets)
        write_json(Path(args.golden), golden)
        sys.stdout.write("wrote %s (%d bytes)\n" % (args.golden, Path(args.golden).stat().st_size))
    if not args.report and not args.write_golden:
        sys.stdout.write(report_text(presets))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
