"""CP5 pure product — combat munitions consume + reliability mult + troop XP."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "cc_primary_catalog",
    "cc_primary_consume",
    "cc_primary_reliability",
    "cc_primary_xp",
    "cc_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "cc_catalog",
    "cc_consume",
    "cc_reliability",
    "cc_xp",
    "cc_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "cc_catalog": "apply_combat_consume_catalog_live",
    "cc_consume": "apply_combat_consume_munitions_live",
    "cc_reliability": "apply_combat_consume_reliability_live",
    "cc_xp": "apply_combat_consume_xp_live",
    "cc_close": "apply_combat_consume_close_live",
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
        "summary": "Combat consume audit", "plain": "Combat consume audit", "empty": False,
    }


def build_combat_consume_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    cr = (ROOT / "scripts/combat/CombatResolver.gd").read_text(encoding="utf-8")
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
    freeze = (ROOT / "docs/COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md").read_text(encoding="utf-8")

    hooks_ok = all(
        s in cr for s in (
            "func apply_combat_munitions_consume",
            "func apply_formation_combat_experience_gain",
            "func get_formation_reliability_snapshot",
            "reliability_combat_mult",
            "combat_consume_ok",
        )
    ) and "func consume_munitions_from_stockpile" in pm \
        and "func apply_combat_consume_primary_live" in gd \
        and "combat_consume_primary_live=1" in sl \
        and "CP5" in freeze

    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "CC · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Combat consume · hooks=%s" % hooks_ok
    return {
        "score": 0.96 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "model": "equipment_flow_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["combat_consume_product", "CombatResolver", "ProductionManager"],
        "phase": "CP5",
    }
