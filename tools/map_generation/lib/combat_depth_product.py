"""CP6 pure product — optional deep combat + AI logistics doctrine."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "cd_primary_catalog",
    "cd_primary_deep",
    "cd_primary_logistics",
    "cd_primary_joint",
    "cd_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "cd_catalog",
    "cd_deep",
    "cd_logistics",
    "cd_joint",
    "cd_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "cd_catalog": "apply_combat_depth_catalog_live",
    "cd_deep": "apply_combat_depth_deep_live",
    "cd_logistics": "apply_combat_depth_logistics_live",
    "cd_joint": "apply_combat_depth_joint_live",
    "cd_close": "apply_combat_depth_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead),
        "ok": len(dead) == 0 and len(ids) >= 5,
        "summary": "Combat depth audit", "plain": "Combat depth audit", "empty": False,
    }


def build_combat_depth_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    cr = (ROOT / "scripts/combat/CombatResolver.gd").read_text(encoding="utf-8")
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
    freeze = (ROOT / "docs/COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md").read_text(encoding="utf-8")

    hooks_ok = all(
        s in cr for s in (
            "func resolve_deep_combat",
            "func _deep_equipment_weight",
            "deep_equipment_weighted",
        )
    ) and "func ai_select_logistics_doctrine" in pm \
        and "func apply_combat_depth_primary_live" in gd \
        and "combat_depth_primary_live=1" in sl \
        and "CP6" in freeze

    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "CD · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Combat depth · hooks=%s" % hooks_ok
    return {
        "score": 0.96 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "model": "equipment_flow_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["combat_depth_product", "CombatResolver", "ProductionManager"],
        "phase": "CP6",
    }
