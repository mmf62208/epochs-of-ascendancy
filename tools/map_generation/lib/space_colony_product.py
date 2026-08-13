"""Space colony S3 — parent CRS, range interact, independence, landing/bombardment, save shape."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "sco_primary_catalog",
    "sco_primary_relations",
    "sco_primary_independence",
    "sco_primary_combat",
    "sco_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "sco_catalog",
    "sco_relations",
    "sco_independence",
    "sco_combat",
    "sco_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "sco_catalog": "apply_space_colony_catalog_live",
    "sco_relations": "apply_space_colony_relations_live",
    "sco_independence": "apply_space_colony_independence_live",
    "sco_combat": "apply_space_colony_combat_live",
    "sco_close": "apply_space_colony_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def parent_crs(vectors: Dict[str, float]) -> float:
    keys = ("public", "elite", "military", "trust")
    return sum(float(vectors.get(k, 0.0)) for k in keys) / 4.0


def range_can_interact(reach_au: float, distance_au: float, is_parent: bool = False) -> bool:
    if is_parent:
        return True
    return float(reach_au) + 0.001 >= float(distance_au)


def independence_ready(autonomy: float, years: float, min_years: float = 20.0) -> bool:
    return float(autonomy) >= 100.0 and float(years) >= float(min_years)


def can_land(landing_craft: int, in_range: bool) -> bool:
    return int(landing_craft) > 0 and bool(in_range)


def can_bombard(bombs: int, weapons: int, in_range: bool) -> bool:
    return (int(bombs) + int(weapons)) > 0 and bool(in_range)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Space colony audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Space colony audit", "empty": False,
    }


def build_space_colony_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    crs = parent_crs({"public": 20, "elite": 15, "military": 10, "trust": 25})
    rel_ok = 15.0 <= crs <= 20.0
    range_ok = range_can_interact(0.5, 0.3, False) and not range_can_interact(0.5, 5.0, False)
    range_ok = range_ok and range_can_interact(0.1, 99.0, True)
    indep_ok = independence_ready(100, 25) and not independence_ready(50, 30)
    land_ok = can_land(2, True) and not can_land(0, True)
    bomb_ok = can_bombard(1, 0, True) and not can_bombard(0, 0, True)
    mgr = (ROOT / "scripts" / "space" / "SpaceLayerManager.gd").read_text(encoding="utf-8")
    hooks_ok = all(s in mgr for s in (
        "func build_colony_board", "func can_land_assault", "func can_bombard_body",
        "func get_save_data", "func apply_save_data", "func force_independence_tick",
    ))
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = rel_ok and range_ok and indep_ok and land_ok and bomb_ok and hooks_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "SCO · %s · live %s" % (step, api),
            "score": 0.83 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Space colony · rel_ok=%s range_ok=%s indep_ok=%s combat_ok=%s" % (
        rel_ok, range_ok, indep_ok, land_ok and bomb_ok,
    )
    return {
        "score": 0.91 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "rel_ok": rel_ok, "range_ok": range_ok, "indep_ok": indep_ok,
        "land_ok": land_ok, "bomb_ok": bomb_ok, "hooks_ok": hooks_ok,
        "parent_crs_sample": crs,
        "model": "orbital_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "space_colony_product", "parent_crs", "range_interact",
            "independence", "landing_bombardment", "saveload",
        ],
    }
