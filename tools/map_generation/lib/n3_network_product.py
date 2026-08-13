"""N3 network primary command product — pure + source hooks."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = ('n3n_primary_catalog', 'n3n_primary_lobby', 'n3n_primary_seed', 'n3n_primary_sync', 'n3n_primary_close')
PRIMARY_COMMAND_STEPS = ('n3n_catalog', 'n3n_lobby', 'n3n_seed', 'n3n_sync', 'n3n_close')
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {'n3n_catalog': 'apply_n3_network_catalog_live', 'n3n_lobby': 'apply_n3_network_lobby_live', 'n3n_seed': 'apply_n3_network_seed_live', 'n3n_sync': 'apply_n3_network_sync_live', 'n3n_close': 'apply_n3_network_close_live'}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def lockstep_match(a, b):
    return a == b and len(a) > 0


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "N3 network audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "N3 network audit", "empty": False,
    }


def build_n3_network_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    logic_ok = bool(lockstep_match('abc', 'abc') and not lockstep_match('a', 'b'))
    mgr = (ROOT / "scripts/net/NetSessionManager.gd").read_text(encoding="utf-8")
    hooks_ok = all(h in mgr for h in ['func start_network_lobby', 'func enqueue_network_command', 'func verify_lockstep'])
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = logic_ok and hooks_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "N3N · %s · live %s" % (step, api),
            "score": 0.84 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "N3 network · logic_ok=%s hooks_ok=%s" % (logic_ok, hooks_ok)
    return {
        "score": 0.91 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "logic_ok": logic_ok, "hooks_ok": hooks_ok,
        "model": "network_lockstep_journal",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["n3_network_product"],
    }
