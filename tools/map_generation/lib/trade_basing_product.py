"""Trade basing primary — DOCKING_RIGHTS basing graph (R7)."""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
VALUE_PATH = ROOT / "data" / "trade" / "strategic_value_rules.json"

SURFACE_KEYS = (
    "tba_primary_catalog",
    "tba_primary_grant",
    "tba_primary_query",
    "tba_primary_expire",
    "tba_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "tba_catalog",
    "tba_grant",
    "tba_query",
    "tba_expire",
    "tba_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "tba_catalog": "apply_trade_basing_catalog_live",
    "tba_grant": "apply_trade_basing_grant_live",
    "tba_query": "apply_trade_basing_query_live",
    "tba_expire": "apply_trade_basing_expire_live",
    "tba_close": "apply_trade_basing_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def load_value_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    p = path or VALUE_PATH
    if not p.is_file():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


def docking_suu(months: float = 12.0, major_port: bool = True, rules=None) -> float:
    r = rules or load_value_rules()
    d = r.get("docking_rights") or {}
    v = float(d.get("base_per_month", 18.0)) * max(float(months), 1.0)
    if major_port:
        v *= float(d.get("major_port_mult", 2.0))
    v *= float(d.get("sovereignty_premium", 1.4))
    return round(v, 2)


def make_basing_edge(
    host: str,
    guest: str,
    province_id: int = 0,
    duration_months: int = 12,
    major_port: bool = True,
    range_bonus: float = 0.15,
    grant_id: str = "",
) -> Dict[str, Any]:
    h = host.strip().upper()
    g = guest.strip().upper()
    months = max(1, int(duration_months))
    gid = grant_id or ("basing_%s_%s_%d" % (h, g, int(province_id)))
    return {
        "grant_id": gid,
        "host_tag": h,
        "guest_tag": g,
        "province_id": max(0, int(province_id)),
        "duration_months": months,
        "remaining_months": months,
        "major_port": bool(major_port),
        "range_bonus": float(range_bonus),
        "active": True,
        "suu": docking_suu(months, major_port),
        "model": "strategic_compact_ledger",
        "kind": "docking_rights",
    }


def grant_to_graph(graph: Dict[str, Any], edge: Dict[str, Any]) -> Dict[str, Any]:
    """Pure basing graph: grant_id -> edge."""
    g = dict(graph or {})
    e = dict(edge)
    e["active"] = True
    g[str(e.get("grant_id", ""))] = e
    return g


def has_basing_access(
    graph: Dict[str, Any],
    guest: str,
    host: str = "",
    province_id: int = 0,
) -> bool:
    gtag = guest.strip().upper()
    htag = host.strip().upper()
    for _gid, raw in (graph or {}).items():
        if not isinstance(raw, dict):
            continue
        if not bool(raw.get("active", True)):
            continue
        if int(raw.get("remaining_months", 0)) <= 0:
            continue
        if str(raw.get("guest_tag", "")).upper() != gtag:
            continue
        if htag and str(raw.get("host_tag", "")).upper() != htag:
            continue
        if province_id > 0:
            pid = int(raw.get("province_id", 0))
            # province 0 = host-wide rights
            if pid > 0 and pid != province_id:
                continue
        return True
    return False


def tick_basing_graph(graph: Dict[str, Any], months: int = 1) -> Dict[str, Any]:
    """Advance remaining months; deactivate expired edges."""
    out: Dict[str, Any] = {}
    expired = 0
    for gid, raw in (graph or {}).items():
        if not isinstance(raw, dict):
            continue
        e = dict(raw)
        if bool(e.get("active", True)):
            rem = int(e.get("remaining_months", 0)) - max(1, int(months))
            e["remaining_months"] = rem
            if rem <= 0:
                e["active"] = False
                e["remaining_months"] = 0
                expired += 1
        out[str(gid)] = e
    return {"graph": out, "expired": expired, "active_n": sum(1 for e in out.values() if bool(e.get("active")))}


def basing_board(graph: Dict[str, Any], viewer: str = "") -> Dict[str, Any]:
    edges = []
    for gid, raw in (graph or {}).items():
        if not isinstance(raw, dict):
            continue
        if viewer:
            v = viewer.strip().upper()
            if str(raw.get("host_tag", "")).upper() != v and str(raw.get("guest_tag", "")).upper() != v:
                continue
        edges.append(dict(raw))
    active = [e for e in edges if bool(e.get("active", True)) and int(e.get("remaining_months", 0)) > 0]
    return {
        "viewer": viewer.upper() if viewer else "",
        "edges": edges,
        "edge_n": len(edges),
        "active_n": len(active),
        "model": "strategic_compact_ledger",
        "desk_version": 1,
    }


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Trade basing audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Trade basing audit", "empty": False,
    }


def build_trade_basing_primary_command_product(*, province_id: int = 42, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    edge = make_basing_edge("ENG", "GER", pid, 12, True, 0.2)
    suu_ok = edge["suu"] > 100.0
    graph = grant_to_graph({}, edge)
    grant_ok = has_basing_access(graph, "GER", "ENG", pid)
    query_ok = has_basing_access(graph, "GER", "ENG") and not has_basing_access(graph, "FRA", "ENG")
    board = basing_board(graph, "GER")
    board_ok = int(board.get("active_n", 0)) >= 1
    # Expire
    ticked = tick_basing_graph(graph, 12)
    expire_ok = int(ticked.get("expired", 0)) >= 1 and not has_basing_access(ticked["graph"], "GER", "ENG", pid)
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = suu_ok and grant_ok and query_ok and board_ok and expire_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "TBA · %s · live %s" % (step, api),
            "score": 0.8 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Trade basing · grant_ok=%s query_ok=%s expire_ok=%s suu_ok=%s" % (
        grant_ok, query_ok, expire_ok, suu_ok,
    )
    return {
        "score": 0.88 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "grant_ok": grant_ok, "query_ok": query_ok, "expire_ok": expire_ok, "suu_ok": suu_ok,
        "edge": edge, "board": board, "tick": ticked,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "trade_basing_product", "docking_rights", "basing_graph",
            "grant_expire", "strategic_compact_ledger",
        ],
    }
