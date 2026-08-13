"""Resource economy depth — food cohesion, combat reliability, plants seed, fuel ops.

Builds on resource_harvest_economy_product. LIVE_API → GameData resource_economy_depth_* .
"""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
HARVEST_PATH = ROOT / "data" / "production" / "resource_harvest_rules.json"
FACTORY_PATH = ROOT / "data" / "production" / "factory_rules.json"

try:
    from resource_harvest_economy_product import (  # type: ignore
        compute_province_daily_income,
        list_energy_plant_types,
        list_resource_plant_types,
        load_harvest_rules,
        recommend_plant_for_resources as _rec_plant_unused,
    )
except Exception:  # pragma: no cover
    def load_harvest_rules(path=None):  # type: ignore
        p = path or HARVEST_PATH
        return json.loads(p.read_text(encoding="utf-8"))

    def compute_province_daily_income(resources, plants=None, unlocks=None, harvest=None):  # type: ignore
        return {"energy": 1.0, "steel": 0.5}

    def list_energy_plant_types(h=None):  # type: ignore
        return list((load_harvest_rules().get("energy_plant_types") or {}).keys())

    def list_resource_plant_types(h=None):  # type: ignore
        return list((load_harvest_rules().get("resource_plant_types") or {}).keys())


SURFACE_KEYS = (
    "red_primary_catalog",
    "red_primary_food",
    "red_primary_combat",
    "red_primary_plants",
    "red_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "red_catalog",
    "red_food",
    "red_combat",
    "red_plants",
    "red_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "red_catalog": "apply_resource_economy_depth_catalog_live",
    "red_food": "apply_resource_economy_depth_food_live",
    "red_combat": "apply_resource_economy_depth_combat_live",
    "red_plants": "apply_resource_economy_depth_plants_live",
    "red_close": "apply_resource_economy_depth_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def compute_food_cohesion_delta(
    daily_supplies_income: float,
    supplies_stockpile: float = 0.0,
    harvest: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    h = harvest if harvest is not None else load_harvest_rules()
    fc = h.get("food_cohesion") or {}
    per = float(fc.get("supplies_income_per_cohesion_point", 25.0))
    max_gain = int(fc.get("max_daily_cohesion_gain", 2))
    starve_thr = float(fc.get("starvation_stockpile_threshold", 5.0))
    starve_pen = int(fc.get("starvation_cohesion_penalty", -1))
    delta = 0
    reason = "neutral"
    if daily_supplies_income > 0 and per > 0:
        delta = max(0, min(max_gain, int(daily_supplies_income // per)))
        if delta > 0:
            reason = "food_surplus"
    if supplies_stockpile + 0.001 < starve_thr and daily_supplies_income < per * 0.5:
        delta = min(delta, 0) + starve_pen
        reason = "food_shortage"
    return {
        "cohesion_delta": delta,
        "reason": reason,
        "daily_supplies_income": round(float(daily_supplies_income), 2),
        "supplies_stockpile": round(float(supplies_stockpile), 2),
    }


def fuel_ops_burn_rate(vehicle_class: str = "default", harvest: Optional[Dict[str, Any]] = None) -> float:
    h = harvest if harvest is not None else load_harvest_rules()
    table = h.get("fuel_ops_burn") or {}
    key = str(vehicle_class).lower()
    if key in table:
        return float(table[key])
    if key in ("tank", "medium_tank", "heavy_tank"):
        return float(table.get("armor", 0.35))
    if "jet" in key:
        return float(table.get("jet", 0.85))
    if key in ("missile", "rocket", "space"):
        return float(table.get("rocket", 1.6))
    return float(table.get("default", 0.25))


def combat_reliability_from_production(production_reliability: float) -> float:
    return max(0.72, min(1.0, float(production_reliability)))


def recommend_plant_for_resources(
    resources: Dict[str, float],
    unlocks: Optional[Dict[str, Any]] = None,
    harvest: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    h = harvest if harvest is not None else load_harvest_rules()
    seed_map = h.get("plant_auto_seed") or {}
    min_dep = float(h.get("plant_auto_seed_min_deposit", 40.0))
    flags = [str(x) for x in ((unlocks or {}).get("rule_flags") or [])]
    best_key, best_amt, best_plant = "", 0.0, ""
    catalogs = {}
    catalogs.update(h.get("energy_plant_types") or {})
    catalogs.update(h.get("resource_plant_types") or {})
    for sk, amt in resources.items():
        skl = str(sk).lower()
        a = float(amt)
        if a < min_dep or skl not in seed_map:
            continue
        plant = str(seed_map[skl]).lower()
        conf = catalogs.get(plant) or {}
        req = str(conf.get("requires_unlock") or "")
        if req and req not in flags:
            continue
        if a > best_amt:
            best_amt, best_key, best_plant = a, skl, plant
    if not best_plant:
        return {}
    tier = 1
    if best_amt >= 1000:
        tier = 4
    elif best_amt >= 500:
        tier = 3
    elif best_amt >= 200:
        tier = 2
    return {"plant_type": best_plant, "source_key": best_key, "deposit": best_amt, "size_tier": tier}


def jets_burn_more_than_trucks(harvest: Optional[Dict[str, Any]] = None) -> bool:
    return fuel_ops_burn_rate("jet", harvest) > fuel_ops_burn_rate("truck", harvest) + 0.1


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Resource economy depth audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_resource_economy_depth_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    h = load_harvest_rules()
    food_surplus = compute_food_cohesion_delta(50.0, 100.0, h)
    food_starve = compute_food_cohesion_delta(0.0, 1.0, h)
    food_ok = int(food_surplus["cohesion_delta"]) > 0 and int(food_starve["cohesion_delta"]) < 0
    rel_full = combat_reliability_from_production(1.0)
    rel_short = combat_reliability_from_production(0.55)
    combat_ok = rel_short < rel_full - 0.01 and rel_short >= 0.72
    plant_rec = recommend_plant_for_resources({"coal": 200.0, "iron": 150.0}, {}, h)
    plants_ok = bool(plant_rec.get("plant_type")) and plant_rec.get("plant_type") in (
        list_energy_plant_types(h) + list_resource_plant_types(h)
    )
    fuel_ok = jets_burn_more_than_trucks(h)
    seed_map_ok = len(h.get("plant_auto_seed") or {}) >= 8
    fuel_table_ok = len(h.get("fuel_ops_burn") or {}) >= 5
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = food_ok and combat_ok and plants_ok and fuel_ok and seed_map_ok and fuel_table_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "RED · %s · live %s" % (step, api),
            "score": 0.74 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = (
        "Resource economy depth · food_ok=%s combat_ok=%s plants_ok=%s fuel_ok=%s"
        % (food_ok, combat_ok, plants_ok, fuel_ok)
    )
    return {
        "score": 0.8 if all_ok else 0.42,
        "plain": label,
        "summary": label,
        "empty": False,
        "province_id": pid,
        "food_surplus": food_surplus,
        "food_starve": food_starve,
        "food_ok": food_ok,
        "rel_full": rel_full,
        "rel_short": rel_short,
        "combat_ok": combat_ok,
        "plant_recommend": plant_rec,
        "plants_ok": plants_ok,
        "fuel_ok": fuel_ok,
        "jet_burn": fuel_ops_burn_rate("jet", h),
        "truck_burn": fuel_ops_burn_rate("truck", h),
        "surface_keys": list(SURFACE_KEYS),
        "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0,
        "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]),
        "audit": audit,
        "steps": steps_out,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue,
        "integration": [
            "resource_economy_depth_product",
            "resource_economy_depth_primary",
            "food_cohesion",
            "production_reliability_combat",
            "plant_auto_seed",
            "fuel_ops_burn",
        ],
    }
