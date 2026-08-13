"""CP4 pure product — missile 1:1 munitions + drone swarm batch categories."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "md_primary_catalog",
    "md_primary_missile",
    "md_primary_drone",
    "md_primary_consume",
    "md_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "md_catalog",
    "md_missile",
    "md_drone",
    "md_consume",
    "md_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "md_catalog": "apply_munitions_drone_catalog_live",
    "md_missile": "apply_munitions_drone_missile_live",
    "md_drone": "apply_munitions_drone_drone_live",
    "md_consume": "apply_munitions_drone_consume_live",
    "md_close": "apply_munitions_drone_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def stock_units(design_class: str, completes: int = 1) -> int:
    key = str(design_class).strip().lower()
    c = max(0, int(completes))
    batch = {
        "truck": 4, "drone_swarm": 6, "drone": 6, "rocket_artillery": 4,
        "missile": 1, "munition": 10, "tank": 1, "fighter": 1,
    }.get(key, 1)
    return c * batch


def consume_amount(design_class: str, volleys: int = 1, intensity: float = 1.0) -> int:
    import math
    v = max(1, int(volleys))
    inten = max(0.25, min(3.0, float(intensity)))
    key = str(design_class).strip().lower()
    per = 4 if key in ("munition", "shell", "rocket_artillery") else 1
    return max(1, int(math.ceil(per * v * inten)))


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead),
        "ok": len(dead) == 0 and len(ids) >= 5,
        "summary": "Munitions drone audit", "plain": "Munitions drone audit", "empty": False,
    }


def build_munitions_drone_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    calc = (ROOT / "scripts/production/EquipmentFlowCalculator.gd").read_text(encoding="utf-8")
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
    freeze = (ROOT / "docs/COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md").read_text(encoding="utf-8")

    hooks_ok = all(
        s in calc for s in (
            "func stock_units_on_complete", "func munitions_consume_amount",
            "drone_swarm", "missile",
        )
    ) and all(
        s in pm for s in (
            "func consume_munitions_from_stockpile",
            "func resolve_design_class_for_stock",
            "func credit_production_complete_to_stockpile",
            "drone_swarm",
        )
    ) and "func apply_munitions_drone_primary_live" in gd \
        and "munitions_drone_primary_live=1" in sl

    missile_ok = stock_units("missile", 3) == 3 and stock_units("tank", 2) == 2
    drone_ok = stock_units("drone_swarm", 1) == 6 and stock_units("drone_swarm", 2) == 12
    consume_ok = consume_amount("missile", 2) == 2 and consume_amount("munition", 1) >= 4
    freeze_ok = "CP4" in freeze and "drone" in freeze.lower() and "missile" in freeze.lower()
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and missile_ok and drone_ok and consume_ok and freeze_ok and audit["ok"]

    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "MD · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Munitions/drone · missile=%s drone=%s" % (missile_ok, drone_ok)
    return {
        "score": 0.96 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "missile_ok": missile_ok, "drone_ok": drone_ok,
        "consume_ok": consume_ok, "model": "equipment_flow_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["munitions_drone_product", "EquipmentFlowCalculator", "ProductionManager"],
        "phase": "CP4",
    }
