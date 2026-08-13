"""N4 dedicated server + reconnect primary command product."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "n4d_primary_catalog",
    "n4d_primary_host",
    "n4d_primary_client",
    "n4d_primary_reconnect",
    "n4d_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "n4d_catalog",
    "n4d_host",
    "n4d_client",
    "n4d_reconnect",
    "n4d_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "n4d_catalog": "apply_n4_dedicated_catalog_live",
    "n4d_host": "apply_n4_dedicated_host_live",
    "n4d_client": "apply_n4_dedicated_client_live",
    "n4d_reconnect": "apply_n4_dedicated_reconnect_live",
    "n4d_close": "apply_n4_dedicated_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def reconnect_resync_ok(drop_seq: int, resync_n: int, host_journal_n: int) -> bool:
    """Client must receive full host journal on reconnect (catch-up)."""
    return int(resync_n) == int(host_journal_n) and int(resync_n) > int(drop_seq)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "N4 dedicated audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "N4 dedicated audit", "empty": False,
    }


def build_n4_dedicated_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    logic_ok = reconnect_resync_ok(2, 5, 5) and not reconnect_resync_ok(4, 3, 5)
    mgr = (ROOT / "scripts" / "net" / "NetSessionManager.gd").read_text(encoding="utf-8")
    hooks_ok = all(h in mgr for h in (
        "func start_dedicated_server",
        "func join_dedicated_client",
        "func disconnect_peer",
        "func reconnect_peer",
        "func run_reconnect_smoke",
    ))
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = logic_ok and hooks_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "N4D · %s · live %s" % (step, api),
            "score": 0.85 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "N4 dedicated · logic_ok=%s hooks_ok=%s" % (logic_ok, hooks_ok)
    return {
        "score": 0.93 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "logic_ok": logic_ok, "hooks_ok": hooks_ok,
        "model": "dedicated_lockstep_journal",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["n4_dedicated_product", "NetSessionManager"],
    }
