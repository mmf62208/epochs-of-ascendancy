"""Strategic AI daily logistics doctrine pure product."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "ald_primary_catalog",
    "ald_primary_doctrine",
    "ald_primary_apply",
    "ald_primary_seed",
    "ald_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "ald_catalog",
    "ald_doctrine",
    "ald_apply",
    "ald_seed",
    "ald_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "ald_catalog": "apply_ai_logistics_day_catalog_live",
    "ald_doctrine": "apply_ai_logistics_day_doctrine_live",
    "ald_apply": "apply_ai_logistics_day_apply_live",
    "ald_seed": "apply_ai_logistics_day_seed_live",
    "ald_close": "apply_ai_logistics_day_close_live",
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
        "summary": "AI logistics day audit", "plain": "AI logistics day audit", "empty": False,
    }


def build_ai_logistics_day_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    mm = (ROOT / "scripts/map/MapManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
    daily = (ROOT / "tools/map_generation/lib/strategic_ai_daily_campaign_product.py").read_text(encoding="utf-8")

    hooks_ok = "func ai_select_logistics_doctrine" in pm \
        and "func apply_ai_logistics_doctrine_day" in mm \
        and "apply_ai_logistics_doctrine_day" in mm \
        and "logistics_ok" in mm \
        and "apply_ai" in mm \
        and "func apply_strategic_ai_daily_apply" in gd \
        and "logistics_ok" in gd \
        and "func apply_ai_logistics_day_primary_live" in gd \
        and "ai_logistics_day_primary_live=1" in sl \
        and "apply_ai" in daily

    # Daily path must call doctrine from apply step
    wire_ok = "apply_ai_logistics_doctrine_day" in mm and "apply_strategic_ai_daily_step_for_province" in mm

    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and wire_ok and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "ALD · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "AI logistics day · hooks=%s wire=%s" % (hooks_ok, wire_ok)
    return {
        "score": 0.96 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "wire_ok": wire_ok,
        "model": "reinforce_experience_logistics_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "ai_logistics_day_product", "MapManager.apply_ai_logistics_doctrine_day",
            "ProductionManager.ai_select_logistics_doctrine", "strategic_ai_daily_apply",
        ],
    }
