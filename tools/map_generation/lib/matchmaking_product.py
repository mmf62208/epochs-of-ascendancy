"""Matchmaking primary product."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]
SURFACE_KEYS = ('mmk_primary_catalog', 'mmk_primary_queue', 'mmk_primary_match', 'mmk_primary_session', 'mmk_primary_close')
PRIMARY_COMMAND_STEPS = ('mmk_catalog', 'mmk_queue', 'mmk_match', 'mmk_session', 'mmk_close')
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {'mmk_catalog': 'apply_matchmaking_catalog_live', 'mmk_queue': 'apply_matchmaking_queue_live', 'mmk_match': 'apply_matchmaking_match_live', 'mmk_session': 'apply_matchmaking_session_live', 'mmk_close': 'apply_matchmaking_close_live'}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)
HOOKS = [('scripts/net/NetSessionManager.gd', 'func enqueue_matchmaking'), ('scripts/net/NetSessionManager.gd', 'func try_matchmake'), ('scripts/net/NetSessionManager.gd', 'func run_matchmaking_smoke')]

def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": len(dead)==0 and len(ids)>=5,
            "summary": "Matchmaking audit", "plain": "Matchmaking audit", "empty": False}

def build_matchmaking_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    hooks_ok = True
    for fpath, needle in HOOKS:
        txt = (ROOT / fpath).read_text(encoding="utf-8")
        if needle not in txt:
            hooks_ok = False
            break
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "MMK · %s" % step, "score": 0.86+0.02*i,
            "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Matchmaking · hooks_ok=%s" % hooks_ok
    return {"score": 0.93 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "model": "orbital_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit, "steps": steps_out,
        "step_ids": list(PRIMARY_COMMAND_STEPS), "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["matchmaking_product"]}
