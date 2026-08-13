"""Space fog primary command product — pure + source hooks."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = ('sfg_primary_catalog', 'sfg_primary_fog', 'sfg_primary_reveal', 'sfg_primary_view', 'sfg_primary_close')
PRIMARY_COMMAND_STEPS = ('sfg_catalog', 'sfg_fog', 'sfg_reveal', 'sfg_view', 'sfg_close')
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {'sfg_catalog': 'apply_space_fog_catalog_live', 'sfg_fog': 'apply_space_fog_state_live', 'sfg_reveal': 'apply_space_fog_reveal_live', 'sfg_view': 'apply_space_fog_view_live', 'sfg_close': 'apply_space_fog_close_live'}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def fog_unlocked(flags, gate):
    return any(g in flags for g in gate) if gate else True


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Space fog audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Space fog audit", "empty": False,
    }


def build_space_fog_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    logic_ok = bool(not fog_unlocked([], ['allow_satellites']) and fog_unlocked(['allow_satellites'], ['allow_satellites']))
    mgr = (ROOT / "scripts/space/SpaceLayerManager.gd").read_text(encoding="utf-8")
    hooks_ok = all(h in mgr for h in ['func get_layer_fog_board', 'func set_view_layer', 'func reveal_layer_for_view'])
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = logic_ok and hooks_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "SFG · %s · live %s" % (step, api),
            "score": 0.84 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Space fog · logic_ok=%s hooks_ok=%s" % (logic_ok, hooks_ok)
    return {
        "score": 0.91 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "logic_ok": logic_ok, "hooks_ok": hooks_ok,
        "model": "orbital_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["space_fog_product"],
    }
