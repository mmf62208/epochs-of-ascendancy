"""Space supply AI primary command product."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]
SURFACE_KEYS = ('ssa_primary_catalog', 'ssa_primary_setup', 'ssa_primary_tick', 'ssa_primary_flows', 'ssa_primary_close')
PRIMARY_COMMAND_STEPS = ('ssa_catalog', 'ssa_setup', 'ssa_tick', 'ssa_flows', 'ssa_close')
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {'ssa_catalog': 'apply_space_supply_ai_catalog_live', 'ssa_setup': 'apply_space_supply_ai_setup_live', 'ssa_tick': 'apply_space_supply_ai_tick_live', 'ssa_flows': 'apply_space_supply_ai_flows_live', 'ssa_close': 'apply_space_supply_ai_close_live'}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
            "summary": "Space supply AI audit", "plain": "Space supply AI audit", "empty": False}


def build_space_supply_ai_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    mgr = (ROOT / "scripts/space/SpaceLayerManager.gd").read_text(encoding="utf-8")
    hooks_ok = all(h in mgr for h in ['func process_monthly_space_ai_sustain', 'func create_sustain_flow', 'func buy_commercial_lift'])
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
                          "leaf_action": api, "label": "SSA · %s" % step, "score": 0.85+0.02*i,
                          "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Space supply AI · hooks_ok=%s" % hooks_ok
    return {
        "score": 0.92 if all_ok else 0.4, "plain": label, "summary": label, "empty": False, "province_id": pid,
        "hooks_ok": hooks_ok, "model": "orbital_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit, "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "integration": ["space_supply_ai_product"],
    }
