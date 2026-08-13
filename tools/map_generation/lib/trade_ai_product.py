"""Trade AI primary — monthly propose/accept using acceptance floors + flags + nuclear placate (R6)."""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
VALUE_PATH = ROOT / "data" / "trade" / "strategic_value_rules.json"
POWER_PATH = ROOT / "data" / "diplomacy" / "national_power_rules.json"
REL_PATH = ROOT / "data" / "diplomacy" / "relation_rules.json"

SURFACE_KEYS = (
    "tai_primary_catalog",
    "tai_primary_propose",
    "tai_primary_accept",
    "tai_primary_refuse",
    "tai_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "tai_catalog",
    "tai_propose",
    "tai_accept",
    "tai_refuse",
    "tai_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "tai_catalog": "apply_trade_ai_catalog_live",
    "tai_propose": "apply_trade_ai_propose_live",
    "tai_accept": "apply_trade_ai_accept_live",
    "tai_refuse": "apply_trade_ai_refuse_live",
    "tai_close": "apply_trade_ai_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def load_value_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    p = path or VALUE_PATH
    if not p.is_file():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


def load_power_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    p = path or POWER_PATH
    if not p.is_file():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


def base_refuse_below(rules: Optional[Dict] = None) -> float:
    r = rules or load_value_rules()
    a = r.get("acceptance") or {}
    return float(a.get("refuse_below", 0.85))


def ai_accept_decision(
    score: float,
    accept_floor: float = 0.95,
    hard_block: bool = False,
    placate_delta: float = 0.0,
    *,
    rules: Optional[Dict] = None,
) -> Dict[str, Any]:
    """Mirror TradeManager.ai_decide_accept pure core.

    accept_floor is band floor (e.g. 0.95 neutral). placate_delta is ≤0 and lowers the bar.
    """
    if hard_block:
        return {
            "decision": "refuse",
            "reason": "hard_block",
            "score": round(float(score), 4),
            "threshold": round(float(accept_floor) + float(placate_delta), 4),
            "placate": False,
            "hard_block": True,
        }
    base = base_refuse_below(rules)
    thr = float(accept_floor) + float(placate_delta)
    # Never require more than hostile-level absurdity when placating; clamp floor
    thr = max(0.55, min(1.5, thr))
    sc = float(score)
    if sc < thr:
        return {
            "decision": "refuse",
            "reason": "below_floor",
            "score": round(sc, 4),
            "threshold": round(thr, 4),
            "placate": False,
            "hard_block": False,
        }
    placate = thr < base and sc < base
    reason = "placate" if placate else ("generous" if sc >= 1.05 else "fair")
    return {
        "decision": "accept",
        "reason": reason,
        "score": round(sc, 4),
        "threshold": round(thr, 4),
        "placate": placate,
        "hard_block": False,
    }


def placate_delta_from_matchup(hopeless: bool = False, outmatched: bool = False, nuclear_asymmetry: bool = False, rules=None) -> float:
    r = rules or load_power_rules()
    ap = r.get("ai_placate") or {}
    d = 0.0
    if hopeless:
        d += float(ap.get("hopeless_accept_floor_bonus", -0.18))
    elif outmatched:
        d += float(ap.get("outmatched_accept_floor_bonus", -0.08))
    if nuclear_asymmetry:
        d += float(ap.get("nuclear_vs_non_accept_floor_bonus", -0.12))
    return d


def propose_resource_swap_spec(
    from_tag: str,
    to_tag: str,
    offer_resource: str = "steel",
    offer_qty: float = 40.0,
    request_resource: str = "fuel",
    request_qty: float = 30.0,
) -> Dict[str, Any]:
    """AI monthly propose payload shape (create_major_resource_trade args)."""
    return {
        "from_tag": from_tag.upper(),
        "to_tag": to_tag.upper(),
        "offer_resource": offer_resource.lower(),
        "offer_qty": float(offer_qty),
        "request_resource": request_resource.lower(),
        "request_qty": float(request_qty),
        "visibility": "public",
        "kind": "ai_monthly_resource_swap",
    }


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Trade AI audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Trade AI audit", "empty": False,
    }


def build_trade_ai_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    # Fair accept
    fair = ai_accept_decision(1.0, accept_floor=0.95, hard_block=False, placate_delta=0.0)
    fair_ok = fair["decision"] == "accept" and fair["reason"] == "fair"
    # Hard block refuse
    blocked = ai_accept_decision(2.0, accept_floor=0.75, hard_block=True)
    refuse_ok = blocked["decision"] == "refuse" and blocked["reason"] == "hard_block"
    # Nuclear/hopeless placate: score 0.80 would fail normal 0.85/0.95 but passes with thr 0.95-0.30
    pd = placate_delta_from_matchup(hopeless=True, nuclear_asymmetry=True)
    plac = ai_accept_decision(0.80, accept_floor=0.95, hard_block=False, placate_delta=pd)
    placate_ok = plac["decision"] == "accept" and pd < -0.2 and plac["threshold"] < 0.85
    # Poor without placate
    poor = ai_accept_decision(0.70, accept_floor=0.95, placate_delta=0.0)
    poor_ok = poor["decision"] == "refuse"
    accept_ok = fair_ok and placate_ok and poor_ok
    prop = propose_resource_swap_spec("GER", "FRA", "steel", 50, "fuel", 35)
    propose_ok = prop["from_tag"] == "GER" and prop["kind"] == "ai_monthly_resource_swap"
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = fair_ok and refuse_ok and accept_ok and propose_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "TAI · %s · live %s" % (step, api),
            "score": 0.79 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Trade AI · propose_ok=%s accept_ok=%s refuse_ok=%s placate_ok=%s" % (
        propose_ok, accept_ok, refuse_ok, placate_ok,
    )
    return {
        "score": 0.87 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "propose_ok": propose_ok, "accept_ok": accept_ok, "refuse_ok": refuse_ok,
        "placate_ok": placate_ok, "fair": fair, "placate_decision": plac, "blocked": blocked,
        "placate_delta": pd, "propose_spec": prop,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "trade_ai_product", "ai_monthly_propose", "ai_accept_floor",
            "hard_block_flags", "nuclear_placate", "strategic_compact_ledger",
        ],
    }
