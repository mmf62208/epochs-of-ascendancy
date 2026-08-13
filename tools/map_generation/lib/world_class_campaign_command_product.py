"""World-class campaign command product (major #20).

Unifies theater domains into one command board:
  scan multi-major products → rank urgency → execute top leaf.
Composes theater, logistics, intel, play session, diplo, tech, AI daily.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from theater_command_product import build_theater_command_product, theater_command_product_integrity  # type: ignore
from logistics_supply_theater_product import (  # type: ignore
    build_logistics_supply_theater_product,
    logistics_supply_theater_integrity,
)
from intelligence_network_product import (  # type: ignore
    build_intelligence_network_product,
    intelligence_network_product_integrity,
)
from play_session_campaign_product import (  # type: ignore
    build_play_session_campaign_product,
    play_session_campaign_integrity,
)
from diplomacy_peace_campaign_product import (  # type: ignore
    build_diplomacy_peace_campaign_product,
    diplomacy_peace_campaign_integrity,
)
from tech_research_campaign_product import (  # type: ignore
    build_tech_research_campaign_product,
    tech_research_campaign_integrity,
)
from strategic_ai_daily_campaign_product import (  # type: ignore
    build_strategic_ai_daily_campaign_product,
    strategic_ai_daily_campaign_integrity,
)
from multi_faction_strategic_ai_product import build_multi_faction_strategic_ai_product  # type: ignore
from naval_multi_phase_campaign_product import build_naval_multi_phase_campaign_product  # type: ignore
from air_ops_campaign_product import build_air_ops_campaign_product  # type: ignore
from focus_war_path_product import build_focus_war_path_product  # type: ignore


PRODUCT_STEPS = ("scan", "rank", "execute")

_STEP_META = {
    "scan": {
        "action_id": "world_class_scan",
        "leaf": "apply_focus",
        "label": "Step 0 — scan world-class domains",
    },
    "rank": {
        "action_id": "world_class_rank",
        "leaf": "apply_station",
        "label": "Step 1 — rank domain urgency",
    },
    "execute": {
        "action_id": "world_class_execute",
        "leaf": "apply_assault",
        "label": "Step 2 — execute top domain leaf",
    },
}

DOMAIN_LEAF = {
    "theater": "apply_assault",
    "logistics": "apply_supply",
    "intel": "apply_agent_dispatch",
    "session": "apply_focus",
    "diplomacy": "apply_hh_commit",
    "tech": "apply_production",
    "ai": "apply_station",
    "naval": "apply_station",
    "air": "apply_assault",
    "focus": "apply_focus",
}


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


def recommend_world_class_step(
    *,
    domain_count: int = 0,
    top_score: float = 0.5,
) -> Dict[str, Any]:
    if domain_count <= 0:
        step = "scan"
        reason = "empty board — scan domains"
    elif top_score < 0.4:
        step = "rank"
        reason = "low scores — re-rank"
    else:
        step = "execute"
        reason = "execute top domain leaf"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_world_class_campaign_command_product(
    *,
    province_id: int = 1,
    player_tag: str = "GER",
) -> Dict[str, Any]:
    domains_raw = {
        "theater": build_theater_command_product(province_id=province_id),
        "logistics": build_logistics_supply_theater_product(province_id=province_id),
        "intel": build_intelligence_network_product(province_id=province_id),
        "session": build_play_session_campaign_product(
            province_id=province_id, player_tag=player_tag
        ),
        "diplomacy": build_diplomacy_peace_campaign_product(province_id=province_id),
        "tech": build_tech_research_campaign_product(province_id=province_id),
        "ai": build_strategic_ai_daily_campaign_product(
            province_id=province_id, player_tag=player_tag
        ),
        "naval": build_naval_multi_phase_campaign_product(province_id=province_id),
        "air": build_air_ops_campaign_product(province_id=province_id),
        "focus": build_focus_war_path_product(province_id=province_id),
    }
    board = build_multi_faction_strategic_ai_product(province_id=province_id)

    domains: List[Dict[str, Any]] = []
    for name, block in domains_raw.items():
        sc = _floor(float(block.get("score", 0.5)))
        # urgency boost from AI board affinity
        if name in ("theater", "ai", "session"):
            sc = _floor(sc * 1.05)
        domains.append(
            {
                "domain": name,
                "score": sc,
                "leaf": DOMAIN_LEAF.get(name, "apply_focus"),
                "summary": str(block.get("summary", name))[:90],
                "empty": bool(block.get("empty", False)),
            }
        )
    domains.sort(key=lambda d: (-float(d.get("score", 0)), str(d.get("domain", ""))))
    top = domains[0] if domains else {"domain": "theater", "score": 0.5, "leaf": "apply_assault"}
    top_score = float(top.get("score", 0.5))
    score = _floor(
        0.45 * top_score
        + 0.3 * min(1.0, len(domains) / 10.0)
        + 0.25 * _norm(float(board.get("score", 0.5)))
    )
    rec = recommend_world_class_step(domain_count=len(domains), top_score=top_score)

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores = {
        "scan": _floor(0.45 + 0.05 * min(10, len(domains))),
        "rank": _floor(0.4 + 0.1 * top_score),
        "execute": _floor(0.5 + 0.1 * top_score),
    }
    step_leaves = {
        "scan": "apply_focus",
        "rank": "apply_station",
        "execute": str(top.get("leaf", "apply_assault")),
    }
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        leaf = step_leaves[step]
        lab = str(meta["label"])
        if recommended:
            lab = "★ " + lab
        lab = "%s · top %s · score %.2f" % (lab, top.get("domain"), sc)
        row = {
            "index": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": leaf,
            "label": lab,
            "score": sc,
            "enabled": True,
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": leaf,
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": True,
                "label": lab,
                "step": step,
                "product_action": meta["action_id"],
                "domain": top.get("domain"),
            }
        )
    # top domain apply also
    apply_queue.append(
        {
            "action_id": str(top.get("leaf", "apply_focus")),
            "province_id": max(1, int(province_id)),
            "score": top_score,
            "enabled": True,
            "label": "Top domain · %s" % top.get("domain"),
            "step": "execute",
            "product_action": "world_class_execute",
            "domain": top.get("domain"),
        }
    )

    board_lines = [
        "%s · %.2f · %s" % (d.get("domain"), float(d.get("score", 0)), d.get("leaf"))
        for d in domains[:8]
    ]
    actions = [
        {
            "action_id": "world_class_campaign_command_product",
            "label": "Run world-class campaign command",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "world_class_scan")),
            "label": "Recommended: %s" % rec.get("step", "scan"),
            "enabled": True,
        },
        {
            "action_id": "theater_command_product",
            "label": "Open theater command product",
            "enabled": True,
        },
    ]
    for r in day_rows:
        actions.append(
            {
                "action_id": r["action_id"],
                "label": r["label"],
                "enabled": True,
                "step": r["step"],
            }
        )

    label = (
        "World-class campaign command · domains %d · top %s/%.2f · AI majors %d · score %.2f"
        % (
            len(domains),
            top.get("domain"),
            top_score,
            int(board.get("faction_count", 0)),
            score,
        )
    )
    return {
        "domains": domains,
        "domain_count": len(domains),
        "top_domain": str(top.get("domain")),
        "top_score": top_score,
        "top_leaf": str(top.get("leaf")),
        "board": board,
        "domains_raw": {k: {"score": v.get("score"), "summary": v.get("summary")} for k, v in domains_raw.items()},
        "board_lines": board_lines,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "world_class_score": score,
        "province_id": max(1, int(province_id)),
        "player_tag": str(player_tag or "").upper(),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", ""))] + board_lines + [str(r.get("label", "")) for r in day_rows]),
        "bbcode": "[color=#fbbf24]★ World-class command[/color] [color=#8899aa]%s[/color]" % label,
        "empty": len(domains) <= 0,
        "integration": [
            "world_class_campaign_command_product",
            "world_class_scan",
            "world_class_rank",
            "world_class_execute",
            "major_20",
            "world_class",
            "campaign_command",
        ],
    }


def execute_world_class_step(
    step: str, province_id: int = 1, *, player_tag: str = "GER"
) -> Dict[str, Any]:
    s = str(step or "scan").strip().lower()
    if s.startswith("world_class_"):
        s = s.replace("world_class_", "")
    if s not in _STEP_META:
        s = "scan"
    meta = _STEP_META[s]
    product = build_world_class_campaign_command_product(
        province_id=province_id, player_tag=player_tag
    )
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q = [
        {
            "action_id": leaf,
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": True,
            "label": meta["label"],
            "step": s,
            "product_action": meta["action_id"],
            "domain": product.get("top_domain"),
        }
    ]
    if s == "execute":
        q.append(
            {
                "action_id": str(product.get("top_leaf", leaf)),
                "province_id": max(1, int(province_id)),
                "score": float(product.get("top_score", score)),
                "enabled": True,
                "label": "Top domain · %s" % product.get("top_domain"),
                "step": "execute",
                "product_action": "world_class_execute",
            }
        )
    label = "Execute world-class %s · leaf %s · top %s · score %.2f" % (
        s,
        leaf,
        product.get("top_domain"),
        score,
    )
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#fbbf24]★ World-class %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_world_class_step", s, leaf],
    }


def world_class_campaign_command_integrity() -> Dict[str, Any]:
    product = build_world_class_campaign_command_product(player_tag="GER")
    steps = [execute_world_class_step(s, 1, player_tag="GER") for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    gates = [
        theater_command_product_integrity(),
        logistics_supply_theater_integrity(),
        intelligence_network_product_integrity(),
        play_session_campaign_integrity(),
        diplomacy_peace_campaign_integrity(),
        tech_research_campaign_integrity(),
        strategic_ai_daily_campaign_integrity(),
    ]
    ok = (
        not bool(product.get("empty"))
        and int(product.get("domain_count", 0)) >= 8
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and all(bool(g.get("ok", True)) for g in gates)
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "domain_count": int(product.get("domain_count", 0)),
        "top_domain": product.get("top_domain"),
        "gate": gate,
        "summary": "World-class campaign command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_world_class_campaign_command_product_loop() -> Dict[str, Any]:
    product = build_world_class_campaign_command_product(player_tag="ENG")
    gate = world_class_campaign_command_integrity()
    ok = (
        bool(gate.get("ok"))
        and len(product.get("apply_queue") or []) >= 3
        and int(product.get("domain_count", 0)) >= 8
    )
    label = "Close world-class command · domains %d · top %s · score %.2f · %s" % (
        int(product.get("domain_count", 0)),
        product.get("top_domain"),
        float(product.get("score", 0)),
        "PASS" if ok else "FAIL",
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#fbbf24]✓ World-class command[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "ok": ok,
    }
