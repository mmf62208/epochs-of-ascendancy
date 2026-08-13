"""Space depth S1 — multi-site Sol, habitability, space power, capacity, independence."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

from space_layer_product import (  # type: ignore
    asteroid_caps,
    compute_space_power_index,
    independence_years_to_breakaway,
    load_space_rules,
    loft_cost_mult,
    multi_site_sol_ok,
    spotting_detect_chance,
)

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "spd_primary_catalog",
    "spd_primary_sites",
    "spd_primary_capacity",
    "spd_primary_power",
    "spd_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "spd_catalog",
    "spd_sites",
    "spd_capacity",
    "spd_power",
    "spd_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "spd_catalog": "apply_space_depth_catalog_live",
    "spd_sites": "apply_space_depth_sites_live",
    "spd_capacity": "apply_space_depth_capacity_live",
    "spd_power": "apply_space_depth_power_live",
    "spd_close": "apply_space_depth_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Space depth audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Space depth audit", "empty": False,
    }


def build_space_depth_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    r = load_space_rules()
    model_ok = str(r.get("model", "")) == "orbital_compact_ledger"
    sol = multi_site_sol_ok(r)
    sites_ok = bool(sol.get("ok"))
    tiny = asteroid_caps("tiny", r)
    dwarf = asteroid_caps("dwarf", r)
    aster_ok = int(dwarf["max_pop"]) > int(tiny["max_pop"]) and int(dwarf["max_building_slots"]) > int(tiny["max_building_slots"])
    direct = loft_cost_mult(False, False, False, r)
    via_luna = loft_cost_mult(True, False, False, r)
    capacity_ok = via_luna < direct and "orbital_command" in str((r.get("capacity_model") or {}).get("player_facing_labels", {}))
    weak = compute_space_power_index({"fleet_strength": 5, "orbital_defenses": 0}, r)
    strong = compute_space_power_index({
        "fleet_strength": 40, "orbital_weapons": 3, "bombardment_capable_ships": 4,
        "orbital_defenses": 0, "stations": 2, "isr_coverage": 2, "lift_capacity": 10,
    }, r)
    power_ok = (
        strong["effective_space_threat"] > weak["space_power_index"]
        and strong["undefended_surface_penalty"]
        and strong["bombardment_threat"]
    )
    indep = independence_years_to_breakaway(30, False, r)
    indep_mit = independence_years_to_breakaway(30, True, r)
    indep_ok = indep["generation_years"] >= 20 and indep_mit["autonomy_after_neglect"] < indep["autonomy_after_neglect"]
    spot = spotting_detect_chance(0.4, True, True, False, r)
    spot_far = spotting_detect_chance(3.0, True, False, True, r)
    spot_ok = spot > spot_far
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = model_ok and sites_ok and aster_ok and capacity_ok and power_ok and indep_ok and spot_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "SPD · %s · live %s" % (step, api),
            "score": 0.81 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Space depth · sites_ok=%s capacity_ok=%s power_ok=%s indep_ok=%s" % (
        sites_ok, capacity_ok, power_ok, indep_ok,
    )
    return {
        "score": 0.89 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "sites_ok": sites_ok, "capacity_ok": capacity_ok, "power_ok": power_ok,
        "indep_ok": indep_ok, "spot_ok": spot_ok, "aster_ok": aster_ok,
        "sol": sol, "loft_direct": direct, "loft_via_luna": via_luna,
        "space_power_strong": strong, "independence": indep,
        "model": "orbital_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "space_depth_product", "multi_site_sol", "orbital_command",
            "space_power_threat", "generational_independence", "staging_ladder",
        ],
    }
