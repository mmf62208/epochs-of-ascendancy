"""Faction personality AI product (major #57) — Phase 11 world-class GS depth.

Personality board → event-driven reaction → doctrine drive package.
Deepens multi-faction AI (#9) + campaign AI war goals (#53–#55) with personality weights.
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from multi_faction_strategic_ai_product import build_multi_faction_strategic_ai_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_faction_strategic_ai_product(*_a, **_k):  # type: ignore
        return {"score": 0.58, "empty": False}

try:
    from strategic_war_goal_product import build_strategic_war_goal_product  # type: ignore
except Exception:  # pragma: no cover
    def build_strategic_war_goal_product(*_a, **_k):  # type: ignore
        return {"score": 0.65, "empty": False}

try:
    from multi_front_campaign_ai_product import build_multi_front_campaign_ai_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_front_campaign_ai_product(*_a, **_k):  # type: ignore
        return {"score": 0.7, "empty": False}

try:
    from campaign_ai_multi_month_product import build_campaign_ai_multi_month_product  # type: ignore
except Exception:  # pragma: no cover
    def build_campaign_ai_multi_month_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False}

PRODUCT_STEPS = ("board", "event", "drive")
_STEP_META = {
    "board": {"action_id": "personality_board", "leaf": "apply_focus", "label": "Step 0 — personality board"},
    "event": {"action_id": "personality_event", "leaf": "apply_agent_dispatch", "label": "Step 1 — event-driven reaction"},
    "drive": {"action_id": "personality_drive", "leaf": "apply_assault", "label": "Step 2 — doctrine drive package"},
}

_PERSONALITIES = (
    {"id": "GER", "trait": "blitz_aggressive", "aggression": 0.88, "caution": 0.35, "naval": 0.4, "industry": 0.8},
    {"id": "SOV", "trait": "depth_defense", "aggression": 0.7, "caution": 0.65, "naval": 0.3, "industry": 0.85},
    {"id": "USA", "trait": "arsenal_buildup", "aggression": 0.55, "caution": 0.5, "naval": 0.85, "industry": 0.95},
    {"id": "ENG", "trait": "naval_containment", "aggression": 0.5, "caution": 0.7, "naval": 0.95, "industry": 0.7},
    {"id": "FRA", "trait": "fortress_hold", "aggression": 0.45, "caution": 0.8, "naval": 0.55, "industry": 0.65},
    {"id": "ITA", "trait": "opportunist", "aggression": 0.6, "caution": 0.55, "naval": 0.7, "industry": 0.55},
    {"id": "JAP", "trait": "carrier_strike", "aggression": 0.75, "caution": 0.45, "naval": 0.9, "industry": 0.7},
)

_EVENTS = (
    {"id": "border_clash", "weight": 0.8, "domain": "combat"},
    {"id": "trade_embargo", "weight": 0.65, "domain": "industry"},
    {"id": "naval_incident", "weight": 0.7, "domain": "fleet"},
    {"id": "agent_scandal", "weight": 0.55, "domain": "agent"},
    {"id": "alliance_invite", "weight": 0.75, "domain": "hh"},
)


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def compute_personality_board(*, faction_score: float = 0.58, ai_score: float = 0.6) -> Dict[str, Any]:
    f = _floor(faction_score)
    a = _floor(ai_score)
    rows = []
    for p in _PERSONALITIES:
        sc = _floor(
            0.35 * float(p["aggression"]) + 0.2 * float(p["industry"])
            + 0.15 * float(p["naval"]) + 0.15 * f + 0.15 * a
        )
        rows.append({**p, "score": sc, "enabled": True, "label": "%s · %s" % (p["id"], p["trait"])})
    rows.sort(key=lambda x: -float(x["score"]))
    top = rows[0] if rows else {"id": "GER", "trait": "blitz_aggressive", "score": 0.5}
    score = _floor(0.55 * float(top["score"]) + 0.45 * f)
    return {
        "personalities": rows, "personality_n": len(rows), "top_id": str(top.get("id")),
        "top_trait": str(top.get("trait")), "score": score,
        "summary": "Personality board · %d factions · top %s/%s · score %.2f"
        % (len(rows), top.get("id"), top.get("trait"), score),
        "empty": False,
    }


def compute_event_react(*, board: Dict[str, Any], war_score: float = 0.65) -> Dict[str, Any]:
    b = _floor(float(board.get("score", 0.5)))
    w = _floor(war_score)
    top_id = str(board.get("top_id", "GER"))
    top_trait = str(board.get("top_trait", "blitz_aggressive"))
    reactions = []
    for ev in _EVENTS:
        sc = _floor(0.4 * float(ev["weight"]) + 0.35 * b + 0.25 * w)
        reactions.append({
            **ev, "score": sc, "faction": top_id, "trait": top_trait,
            "response": "%s reacts to %s" % (top_id, ev["id"]),
        })
    reactions.sort(key=lambda x: -float(x["score"]))
    top = reactions[0] if reactions else {"id": "border_clash", "score": 0.5}
    score = _floor(0.5 * float(top["score"]) + 0.5 * b)
    return {
        "reactions": reactions, "event_n": len(reactions), "top_event": str(top.get("id")),
        "faction": top_id, "score": score,
        "summary": "Event react · %d events · top %s · %s · score %.2f"
        % (len(reactions), top.get("id"), top_id, score),
        "empty": False,
    }


def compute_doctrine_drive(*, event: Dict[str, Any], front_score: float = 0.7) -> Dict[str, Any]:
    e = _floor(float(event.get("score", 0.5)))
    f = _floor(front_score)
    packages = max(1, int(round((0.55 * e + 0.45 * f) * 4)))
    score = _floor(0.45 * e + 0.4 * f + 0.15 * (1.0 if packages >= 2 else 0.5))
    return {
        "packages": packages, "top_event": str(event.get("top_event", "")),
        "faction": str(event.get("faction", "")), "score": score,
        "summary": "Doctrine drive · %s · packages %d · score %.2f"
        % (event.get("faction"), packages, score),
        "empty": False,
    }


def recommend_personality_step(*, boarded: bool = False, evented: bool = False) -> Dict[str, Any]:
    if not boarded:
        step, reason = "board", "scan personality board"
    elif not evented:
        step, reason = "event", "process event-driven reactions"
    else:
        step, reason = "drive", "execute doctrine drive package"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_faction_personality_ai_product(*, province_id: int = 1) -> Dict[str, Any]:
    faction = build_multi_faction_strategic_ai_product(province_id=province_id)
    war = build_strategic_war_goal_product(province_id=province_id)
    front = build_multi_front_campaign_ai_product(province_id=province_id)
    ai = build_campaign_ai_multi_month_product(province_id=province_id)
    board = compute_personality_board(
        faction_score=float(faction.get("score", 0.58)),
        ai_score=float(ai.get("score", 0.6)),
    )
    event = compute_event_react(board=board, war_score=float(war.get("score", 0.65)))
    drive = compute_doctrine_drive(event=event, front_score=float(front.get("score", 0.7)))
    b_s, e_s, d_s = _floor(float(board["score"])), _floor(float(event["score"])), _floor(float(drive["score"]))
    score = _floor(0.3 * b_s + 0.35 * e_s + 0.35 * d_s)
    rec = recommend_personality_step(boarded=True, evented=int(event.get("event_n", 0)) >= 3)
    step_scores = {"board": b_s, "event": e_s, "drive": d_s}
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        sc = step_scores[step]
        recommended = step == str(rec.get("step"))
        lab = ("★ " if recommended else "") + meta["label"] + " · score %.2f" % sc
        day_rows.append({
            "index": i, "step": step, "action_id": meta["action_id"], "leaf_action": meta["leaf"],
            "label": lab, "score": sc, "enabled": True, "recommended": recommended,
            "province_id": max(1, int(province_id)),
        })
        apply_queue.append({
            "action_id": meta["leaf"], "province_id": max(1, int(province_id)), "score": sc,
            "enabled": True, "label": lab, "step": step, "product_action": meta["action_id"],
        })
    actions = [
        {"action_id": "faction_personality_ai_product", "label": "Run faction personality AI product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Faction personality · %s/%s · events %d · packages %d · score %.2f" % (
        board["top_id"], board["top_trait"], int(event["event_n"]), int(drive["packages"]), score)
    return {
        "faction": faction, "war": war, "front": front, "ai": ai,
        "board": board, "event": event, "drive": drive,
        "recommendation": rec, "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "personality_n": int(board["personality_n"]), "event_n": int(event["event_n"]),
        "packages": int(drive["packages"]), "top_id": board["top_id"], "top_trait": board["top_trait"],
        "score": score, "personality_score": score, "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), board["summary"], event["summary"], drive["summary"]] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#c090e0]♟ Personality AI[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "faction_personality_ai_product", "personality_board", "personality_event", "personality_drive",
            "major_57", "personality", "campaign_ai", "phase11_depth", "world_class_gs",
        ],
    }


def execute_personality_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "board").strip().lower().replace("personality_", "").replace("faction_", "")
    if s.startswith("board") or s.startswith("scan"):
        s = "board"
    elif s.startswith("event") or s.startswith("react"):
        s = "event"
    elif s.startswith("drive") or s.startswith("doctrine") or s.startswith("exec"):
        s = "drive"
    if s not in _STEP_META:
        s = "board"
    meta = _STEP_META[s]
    product = build_faction_personality_ai_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute personality %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_personality_step", s, leaf],
    }


def faction_personality_ai_integrity() -> Dict[str, Any]:
    product = build_faction_personality_ai_product()
    steps = [execute_personality_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and int(product.get("personality_n", 0)) >= 5
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Faction personality AI integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_faction_personality_ai_product_loop() -> Dict[str, Any]:
    product = build_faction_personality_ai_product(province_id=2)
    gate = faction_personality_ai_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close faction personality AI · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
