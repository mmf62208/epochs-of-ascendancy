"""RF5 pure product — player-facing reinforce/XP/transit plain stories."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "rst_primary_catalog",
    "rst_primary_xp",
    "rst_primary_transit",
    "rst_primary_panel",
    "rst_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "rst_catalog",
    "rst_xp",
    "rst_transit",
    "rst_panel",
    "rst_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "rst_catalog": "apply_reinforce_story_catalog_live",
    "rst_xp": "apply_reinforce_story_xp_live",
    "rst_transit": "apply_reinforce_story_transit_live",
    "rst_panel": "apply_reinforce_story_panel_live",
    "rst_close": "apply_reinforce_story_close_live",
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
        "summary": "Reinforce story audit", "plain": "Reinforce story audit", "empty": False,
    }


def build_reinforce_story_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
    ui = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text(encoding="utf-8")
    calc = (ROOT / "scripts/production/ReinforcementLogisticsCalculator.gd").read_text(encoding="utf-8")

    hooks_ok = all(
        s in pm for s in (
            "func format_reinforce_story_plain",
            "func format_equipment_flow_map_strip",
            "func estimate_reinforce_transit_days",
            "func apply_manpower_reinforce_with_experience",
        )
    ) and "func attribution_plain_xp_dilution" in calc \
        and "func apply_reinforce_story_primary_live" in gd \
        and "reinforce_story_primary_live=1" in sl \
        and "format_reinforce_story_plain" in ui

    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "RST · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Reinforce story · hooks=%s" % hooks_ok
    return {
        "score": 0.95 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "model": "reinforce_experience_logistics_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["reinforce_story_product", "ProductionManager", "OrderCommandPanel"],
        "phase": "RF5",
    }
