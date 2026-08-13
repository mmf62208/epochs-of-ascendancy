"""Next-290 full-game campaign pillars (20).

A) Strategic AI campaign depth (1–7) — majors #9/#11
B) Designers / industry / OOB campaign (8–14) — major #10/#3
C) Joint theater session / full-game close (15–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from multi_faction_strategic_ai_product import (  # type: ignore
    MAJOR_TAGS,
    build_multi_faction_strategic_ai_product,
    faction_doctrine,
    multi_faction_strategic_ai_integrity,
    plan_faction_ai,
)
from strategic_ai_daily_campaign_product import (  # type: ignore
    budget_ai_day_actions,
    build_strategic_ai_daily_campaign_product,
    strategic_ai_daily_campaign_integrity,
)
from designer_suite_product import (  # type: ignore
    build_designer_suite_product,
    designer_suite_product_integrity,
    recommend_domain,
)
from medium_tank_oob_product import (  # type: ignore
    build_medium_tank_oob_product,
    medium_tank_oob_product_integrity,
)
from theater_command_product import (  # type: ignore
    build_theater_command_product,
    theater_command_product_integrity,
)
from fleet_multi_day_autonomy_product import (  # type: ignore
    build_fleet_multi_day_autonomy_product,
    fleet_multi_day_autonomy_integrity,
)
from agent_campaign_product import (  # type: ignore
    build_agent_campaign_product,
    agent_campaign_product_integrity,
)
from combat_multi_phase_product import (  # type: ignore
    build_multi_phase_combat_product,
    multi_phase_combat_product_integrity,
)
from save_browser_campaign_product import (  # type: ignore
    build_save_browser_campaign_product,
    save_browser_campaign_product_integrity,
)
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


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
    return s if s >= lo else max(lo, min(1.0, s + 0.25))


def _q(aid: str, pid: int, score: float, label: str) -> Dict[str, Any]:
    return {
        "action_id": aid,
        "province_id": max(1, int(pid)),
        "score": float(score),
        "enabled": True,
        "label": label,
    }


def _day(
    action_id: str,
    title: str,
    summary: str,
    score: float,
    apply_queue: List[Dict[str, Any]],
    color: str = "#6eb5ff",
    marker: str = "★",
    integration: Optional[List[str]] = None,
    extra: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    out: Dict[str, Any] = {
        "score": float(score),
        "apply_queue": apply_queue,
        "actions": [{"action_id": action_id, "label": "Run %s" % title, "enabled": True}],
        "summary": summary,
        "plain": summary,
        "bbcode": "[color=%s]%s %s[/color] [color=#8899aa]%s[/color]"
        % (color, marker, title, summary),
        "empty": False,
        "integration": list(integration or ["next290", "full_game_campaign"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


# ---------------------------------------------------------------------------
# A) Strategic AI campaign depth
# ---------------------------------------------------------------------------


def strategic_ai_doctrine_depth_day(province_id: int = 1) -> Dict[str, Any]:
    ger = faction_doctrine("GER")
    eng = faction_doctrine("ENG")
    plan = plan_faction_ai("GER", province_id=province_id)
    combat_w = float(ger.get("combat", 1.0))
    fleet_w = float(eng.get("fleet", 1.0))
    score = _floor(0.45 * _norm(float(plan.get("urgency", 0.5))) + 0.3 * _norm(combat_w) + 0.25 * _norm(fleet_w))
    q = [
        _q("apply_assault", province_id, score, "strategic AI doctrine combat"),
        _q("apply_station", province_id, 0.55, "strategic AI doctrine fleet"),
        _q("apply_focus", province_id, 0.45, "strategic AI doctrine focus"),
    ]
    return _day(
        "strategic_ai_doctrine_depth_day",
        "Strategic AI doctrine depth day",
        "Strategic AI doctrine depth · GER top %s · combat×%.2f · ENG fleet×%.2f · score %.2f"
        % (plan.get("top_domain", "—"), combat_w, fleet_w, score),
        score,
        q,
        "#6eb5ff",
        "♟",
        ["strategic_ai", "doctrine", "depth"],
        {"plan": plan, "doctrine_ger": ger, "doctrine_eng": eng, "ai_score": score},
    )


def strategic_ai_urgency_board_day(province_id: int = 1) -> Dict[str, Any]:
    board = build_multi_faction_strategic_ai_product(province_id=province_id)
    n = int(board.get("faction_count", 0))
    top_u = 0.0
    for f in board.get("factions") or []:
        if isinstance(f, dict):
            top_u = max(top_u, float(f.get("urgency", 0)))
    score = _floor(0.5 * min(1.0, n / 7.0) + 0.5 * top_u)
    q = [
        _q("apply_focus", province_id, score, "strategic AI urgency board focus"),
        _q("apply_station", province_id, 0.5, "strategic AI urgency board station"),
        _q(str(board.get("top_leaf", "apply_assault")), province_id, top_u, "strategic AI urgency top leaf"),
    ]
    return _day(
        "strategic_ai_urgency_board_day",
        "Strategic AI urgency board day",
        "Strategic AI urgency board · majors %d · top %s/%.2f · score %.2f"
        % (n, board.get("top_faction", "—"), top_u, score),
        score,
        q,
        "#6eb5ff",
        "♟",
        ["strategic_ai", "urgency", "board"],
        {"board": board, "ai_score": score},
    )


def strategic_ai_player_skip_day(province_id: int = 1) -> Dict[str, Any]:
    board = build_multi_faction_strategic_ai_product(province_id=province_id)
    factions = list(board.get("factions") or [])
    skipped = budget_ai_day_actions(factions, player_tag="GER", max_actions=4, province_id=province_id)
    full = budget_ai_day_actions(factions, player_tag="", max_actions=7, province_id=province_id)
    sc = int(skipped.get("selected_count", 0))
    fc = int(full.get("selected_count", 0))
    shift = max(0, fc - sc)
    tags = [str(x.get("faction", "")) for x in skipped.get("queue") or []]
    ok_skip = "GER" not in tags
    score = _floor(0.4 + 0.1 * sc + (0.15 if ok_skip else 0.0) + 0.05 * min(3, shift))
    q = list(skipped.get("queue") or [])[:4] or [
        _q("apply_station", province_id, score, "strategic AI player skip station"),
        _q("apply_focus", province_id, 0.5, "strategic AI player skip focus"),
    ]
    return _day(
        "strategic_ai_player_skip_day",
        "Strategic AI player skip day",
        "Strategic AI player skip · budget %d · full %d · skip_shift %d · GER out %s · score %.2f"
        % (sc, fc, shift, "yes" if ok_skip else "no", score),
        score,
        q,
        "#6eb5ff",
        "♟",
        ["strategic_ai", "player_skip", "budget"],
        {"skipped": skipped, "full": full, "skip_shift": shift, "ai_score": score},
    )


def strategic_ai_budget_depth_day(province_id: int = 1) -> Dict[str, Any]:
    daily = build_strategic_ai_daily_campaign_product(player_tag="ENG", max_ai_actions=4, province_id=province_id)
    bc = int(daily.get("budget_count", 0))
    score = _floor(0.35 * float(daily.get("score", 0.5)) + 0.4 * min(1.0, bc / 4.0) + 0.25 * min(1.0, int(daily.get("faction_count", 0)) / 7.0))
    q = list((daily.get("budget") or {}).get("queue") or [])[:4]
    if not q:
        q = [
            _q("apply_station", province_id, score, "strategic AI budget depth station"),
            _q("apply_hh_commit", province_id, 0.55, "strategic AI budget depth HH"),
        ]
    return _day(
        "strategic_ai_budget_depth_day",
        "Strategic AI budget depth day",
        "Strategic AI budget depth · AI budget %d · player ENG · top %s · score %.2f"
        % (bc, daily.get("top_faction", "—"), score),
        score,
        q,
        "#6eb5ff",
        "♟",
        ["strategic_ai", "budget", "daily"],
        {"daily": daily, "ai_score": score},
    )


def strategic_ai_domain_weight_day(province_id: int = 1) -> Dict[str, Any]:
    plans = [plan_faction_ai(t, province_id=province_id) for t in list(MAJOR_TAGS)[:5]]
    domains = [str(p.get("top_domain", "")) for p in plans]
    diversity = len(set(domains))
    avg_u = sum(float(p.get("urgency", 0)) for p in plans) / max(1, len(plans))
    score = _floor(0.45 * min(1.0, diversity / 4.0) + 0.55 * avg_u)
    leaf = str(plans[0].get("top_leaf", "apply_station")) if plans else "apply_station"
    q = [
        _q(leaf, province_id, score, "strategic AI domain weight leaf"),
        _q("apply_production", province_id, 0.5, "strategic AI domain industry"),
        _q("apply_agent_dispatch", province_id, 0.45, "strategic AI domain agent"),
    ]
    return _day(
        "strategic_ai_domain_weight_day",
        "Strategic AI domain weight day",
        "Strategic AI domain weight · domains %d unique · avg urg %.2f · score %.2f"
        % (diversity, avg_u, score),
        score,
        q,
        "#6eb5ff",
        "♟",
        ["strategic_ai", "domain", "weight"],
        {"plans": plans, "domains": domains, "ai_score": score},
    )


def strategic_ai_daily_joint_day(province_id: int = 1) -> Dict[str, Any]:
    daily = build_strategic_ai_daily_campaign_product(player_tag="GER", province_id=province_id)
    board = daily.get("board") or build_multi_faction_strategic_ai_product(province_id=province_id)
    score = _floor(0.5 * float(daily.get("score", 0.5)) + 0.5 * float(board.get("score", 0.5)))
    q = list(daily.get("apply_queue") or [])[:5]
    if len(q) < 2:
        q = [
            _q("apply_focus", province_id, score, "strategic AI daily joint focus"),
            _q("apply_station", province_id, 0.5, "strategic AI daily joint station"),
        ]
    return _day(
        "strategic_ai_daily_joint_day",
        "Strategic AI daily joint day",
        "Strategic AI daily joint · factions %d · budget %d · score %.2f"
        % (int(daily.get("faction_count", 0)), int(daily.get("budget_count", 0)), score),
        score,
        q,
        "#6eb5ff",
        "♟",
        ["strategic_ai", "daily", "joint"],
        {"daily": daily, "board": board, "ai_score": score},
    )


def strategic_ai_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [
        strategic_ai_doctrine_depth_day(province_id),
        strategic_ai_urgency_board_day(province_id),
        strategic_ai_player_skip_day(province_id),
        strategic_ai_budget_depth_day(province_id),
        strategic_ai_domain_weight_day(province_id),
        strategic_ai_daily_joint_day(province_id),
    ]
    gate = strategic_ai_daily_campaign_integrity()
    base = multi_faction_strategic_ai_integrity()
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = bool(gate.get("ok")) and bool(base.get("ok")) and all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    q = [
        _q("apply_focus", province_id, score, "strategic AI campaign close focus"),
        _q("apply_station", province_id, 0.55, "strategic AI campaign close station"),
        _q("apply_assault", province_id, 0.5, "strategic AI campaign close assault"),
    ]
    return _day(
        "strategic_ai_campaign_close_day",
        "Strategic AI campaign close day",
        "Strategic AI campaign close · packages %d · gate %s · score %.2f"
        % (len(days), "PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["strategic_ai", "campaign", "close"],
        {"packages": {d.get("actions", [{}])[0].get("action_id"): d for d in days}, "gate": gate, "base": base, "ok": ok, "ai_score": score},
    )


# ---------------------------------------------------------------------------
# B) Designers / industry / OOB
# ---------------------------------------------------------------------------


def designer_catalog_depth_day(province_id: int = 1) -> Dict[str, Any]:
    des = build_designer_suite_product(province_id=province_id)
    n = int(des.get("catalog_count", 0))
    score = _floor(0.4 * float(des.get("score", 0.5)) + 0.6 * min(1.0, n / 12.0))
    q = [
        _q("apply_production", province_id, score, "designer catalog depth production"),
        _q("apply_focus", province_id, 0.5, "designer catalog depth focus"),
        _q("apply_station", province_id, 0.4, "designer catalog depth station"),
    ]
    return _day(
        "designer_catalog_depth_day",
        "Designer catalog depth day",
        "Designer catalog depth · entries %d · domain %s · score %.2f"
        % (n, (des.get("domain_recommendation") or {}).get("domain", "—"), score),
        score,
        q,
        "#f0b429",
        "⚙",
        ["designers", "catalog", "depth"],
        {"designer": des, "industry_score": score},
    )


def designer_seed_production_day(province_id: int = 1) -> Dict[str, Any]:
    from designer_suite_product import execute_designer_suite_step  # type: ignore

    des = build_designer_suite_product(province_id=province_id)
    seed = execute_designer_suite_step("seed", province_id)
    score = _floor(0.55 * float(des.get("score", 0.5)) + 0.45 * float(seed.get("score", 0.5)))
    q = list(seed.get("apply_queue") or [])[:3] or [
        _q("apply_production", province_id, score, "designer seed production"),
        _q("apply_focus", province_id, 0.45, "designer seed focus"),
    ]
    return _day(
        "designer_seed_production_day",
        "Designer seed production day",
        "Designer seed production · step %s · leaf %s · score %.2f"
        % (seed.get("step", "seed"), seed.get("leaf_action", "apply_production"), score),
        score,
        q,
        "#f0b429",
        "⚙",
        ["designers", "seed", "production"],
        {"designer": des, "seed": seed, "industry_score": score},
    )


def designer_domain_balance_day(province_id: int = 1) -> Dict[str, Any]:
    from designer_suite_product import normalize_catalog  # type: ignore

    cat = normalize_catalog()
    landish = recommend_domain(cat, tank_progress=0.1, naval_pressure=0.2)
    navalish = recommend_domain(cat, tank_progress=0.85, naval_pressure=0.9)
    des = build_designer_suite_product(province_id=province_id)
    shift = abs(
        float((landish.get("domain_scores") or {}).get("naval", 0))
        - float((navalish.get("domain_scores") or {}).get("naval", 0))
    )
    score = _floor(0.5 * float(des.get("score", 0.5)) + 0.5 * min(1.0, shift + 0.35))
    q = [
        _q("apply_production", province_id, score, "designer domain balance production"),
        _q("apply_station", province_id, 0.5, "designer domain balance naval"),
        _q("apply_focus", province_id, 0.45, "designer domain balance air/space"),
    ]
    return _day(
        "designer_domain_balance_day",
        "Designer domain balance day",
        "Designer domain balance · land→%s · naval-pressure→%s · shift %.2f · score %.2f"
        % (landish.get("domain"), navalish.get("domain"), shift, score),
        score,
        q,
        "#f0b429",
        "⚙",
        ["designers", "domain", "balance"],
        {"landish": landish, "navalish": navalish, "designer": des, "industry_score": score},
    )


def oob_horizon_joint_day(province_id: int = 1) -> Dict[str, Any]:
    oob = build_medium_tank_oob_product(province_id=province_id)
    score = _floor(float(oob.get("score", 0.5)))
    q = [
        _q("apply_production", province_id, score, "OOB horizon joint production"),
        _q("apply_supply", province_id, 0.5, "OOB horizon joint supply"),
        _q("apply_station", province_id, 0.45, "OOB horizon joint station"),
    ]
    return _day(
        "oob_horizon_joint_day",
        "OOB horizon joint day",
        "OOB horizon joint · %s · score %.2f" % (str(oob.get("summary", ""))[:72], score),
        score,
        q,
        "#f0b429",
        "🏭",
        ["oob", "horizon", "joint"],
        {"oob": oob, "industry_score": score},
    )


def production_line_bootstrap_day(province_id: int = 1) -> Dict[str, Any]:
    oob = build_medium_tank_oob_product(province_id=province_id)
    des = build_designer_suite_product(province_id=province_id)
    score = _floor(0.55 * float(oob.get("score", 0.5)) + 0.45 * float(des.get("score", 0.5)))
    q = [
        _q("apply_production", province_id, score, "production line bootstrap"),
        _q("apply_focus", province_id, 0.5, "production line bootstrap focus"),
        _q("apply_supply", province_id, 0.45, "production line bootstrap supply"),
    ]
    return _day(
        "production_line_bootstrap_day",
        "Production line bootstrap day",
        "Production line bootstrap · OOB %.2f · designer %.2f · score %.2f"
        % (float(oob.get("score", 0)), float(des.get("score", 0)), score),
        score,
        q,
        "#f0b429",
        "🏭",
        ["production", "bootstrap", "line"],
        {"oob": oob, "designer": des, "industry_score": score},
    )


def industry_design_joint_day(province_id: int = 1) -> Dict[str, Any]:
    des = build_designer_suite_product(province_id=province_id)
    oob = build_medium_tank_oob_product(province_id=province_id)
    theater = build_theater_command_product(province_id=province_id)
    score = _floor(
        0.4 * float(des.get("score", 0.5))
        + 0.35 * float(oob.get("score", 0.5))
        + 0.25 * float(theater.get("score", 0.5))
    )
    q = [
        _q("apply_production", province_id, score, "industry design joint production"),
        _q("apply_assault", province_id, 0.5, "industry design joint combat leaf"),
        _q("apply_station", province_id, 0.45, "industry design joint fleet leaf"),
    ]
    return _day(
        "industry_design_joint_day",
        "Industry design joint day",
        "Industry design joint · design %.2f · OOB %.2f · theater %.2f · score %.2f"
        % (float(des.get("score", 0)), float(oob.get("score", 0)), float(theater.get("score", 0)), score),
        score,
        q,
        "#f0b429",
        "🏭",
        ["industry", "design", "joint"],
        {"designer": des, "oob": oob, "theater": theater, "industry_score": score},
    )


def designer_industry_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [
        designer_catalog_depth_day(province_id),
        designer_seed_production_day(province_id),
        designer_domain_balance_day(province_id),
        oob_horizon_joint_day(province_id),
        production_line_bootstrap_day(province_id),
        industry_design_joint_day(province_id),
    ]
    gate = designer_suite_product_integrity()
    oob_gate = medium_tank_oob_product_integrity()
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = bool(gate.get("ok")) and bool(oob_gate.get("ok")) and all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    q = [
        _q("apply_production", province_id, score, "designer industry close production"),
        _q("apply_focus", province_id, 0.5, "designer industry close focus"),
        _q("apply_supply", province_id, 0.45, "designer industry close supply"),
    ]
    return _day(
        "designer_industry_close_day",
        "Designer industry close day",
        "Designer industry close · packages %d · gate %s · score %.2f"
        % (len(days), "PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["designers", "industry", "close"],
        {"packages": days, "gate": gate, "oob_gate": oob_gate, "ok": ok, "industry_score": score},
    )


# ---------------------------------------------------------------------------
# C) Joint theater session / full-game close
# ---------------------------------------------------------------------------


def theater_ai_command_joint_day(province_id: int = 1) -> Dict[str, Any]:
    th = build_theater_command_product(province_id=province_id)
    ai = build_multi_faction_strategic_ai_product(province_id=province_id)
    score = _floor(0.55 * float(th.get("score", 0.5)) + 0.45 * float(ai.get("score", 0.5)))
    q = [
        _q(str(th.get("top_leaf", "apply_assault")), province_id, score, "theater AI command top leaf"),
        _q("apply_focus", province_id, 0.5, "theater AI command focus"),
        _q("apply_station", province_id, 0.45, "theater AI command station"),
    ]
    return _day(
        "theater_ai_command_joint_day",
        "Theater AI command joint day",
        "Theater AI command joint · theater %.2f · AI top %s · score %.2f"
        % (float(th.get("score", 0)), ai.get("top_faction", "—"), score),
        score,
        q,
        "#a78bfa",
        "⚔",
        ["theater", "ai", "joint"],
        {"theater": th, "ai": ai, "campaign_score": score},
    )


def fleet_ai_campaign_depth_day(province_id: int = 1) -> Dict[str, Any]:
    fleet = build_fleet_multi_day_autonomy_product(province_id=province_id)
    score = _floor(float(fleet.get("score", 0.5)))
    q = [
        _q("apply_station", province_id, score, "fleet AI campaign station"),
        _q("apply_supply", province_id, 0.5, "fleet AI campaign supply"),
        _q("apply_focus", province_id, 0.45, "fleet AI campaign focus"),
    ]
    return _day(
        "fleet_ai_campaign_depth_day",
        "Fleet AI campaign depth day",
        "Fleet AI campaign depth · %s · score %.2f" % (str(fleet.get("summary", ""))[:72], score),
        score,
        q,
        "#38bdf8",
        "⚓",
        ["fleet", "ai", "campaign"],
        {"fleet": fleet, "campaign_score": score},
    )


def agent_ai_campaign_depth_day(province_id: int = 1) -> Dict[str, Any]:
    agent = build_agent_campaign_product(province_id=province_id)
    score = _floor(float(agent.get("score", 0.5)))
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent AI campaign dispatch"),
        _q("apply_hh_commit", province_id, 0.5, "agent AI campaign HH"),
        _q("apply_focus", province_id, 0.45, "agent AI campaign focus"),
    ]
    return _day(
        "agent_ai_campaign_depth_day",
        "Agent AI campaign depth day",
        "Agent AI campaign depth · %s · score %.2f" % (str(agent.get("summary", ""))[:72], score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "ai", "campaign"],
        {"agent": agent, "campaign_score": score},
    )


def combat_ai_phase_depth_day(province_id: int = 1) -> Dict[str, Any]:
    combat = build_multi_phase_combat_product(province_id=province_id)
    score = _floor(float(combat.get("score", 0.5)))
    q = [
        _q("apply_assault", province_id, score, "combat AI phase engage"),
        _q("apply_supply", province_id, 0.55, "combat AI phase approach supply"),
        _q("apply_station", province_id, 0.45, "combat AI phase disengage hold"),
    ]
    return _day(
        "combat_ai_phase_depth_day",
        "Combat AI phase depth day",
        "Combat AI phase depth · %s · score %.2f" % (str(combat.get("summary", ""))[:72], score),
        score,
        q,
        "#f87171",
        "⚔",
        ["combat", "ai", "phase"],
        {"combat": combat, "campaign_score": score},
    )


def save_session_ai_joint_day(province_id: int = 1) -> Dict[str, Any]:
    save = build_save_browser_campaign_product()
    daily = build_strategic_ai_daily_campaign_product(player_tag="GER", province_id=province_id)
    score = _floor(0.5 * float(save.get("score", 0.5)) + 0.5 * float(daily.get("score", 0.5)))
    q = [
        _q("apply_focus", province_id, score, "save session AI joint focus"),
        _q("apply_station", province_id, 0.5, "save session AI joint station"),
        _q("apply_production", province_id, 0.45, "save session AI joint production"),
    ]
    return _day(
        "save_session_ai_joint_day",
        "Save session AI joint day",
        "Save session AI joint · save %.2f · AI daily %.2f · score %.2f"
        % (float(save.get("score", 0)), float(daily.get("score", 0)), score),
        score,
        q,
        "#94a3b8",
        "💾",
        ["save", "session", "ai", "joint"],
        {"save": save, "daily": daily, "campaign_score": score},
    )


def full_game_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    pillars = [
        strategic_ai_campaign_close_day(province_id),
        designer_industry_close_day(province_id),
        theater_ai_command_joint_day(province_id),
        fleet_ai_campaign_depth_day(province_id),
        agent_ai_campaign_depth_day(province_id),
        combat_ai_phase_depth_day(province_id),
        save_session_ai_joint_day(province_id),
    ]
    gates = {
        "ai": strategic_ai_daily_campaign_integrity(),
        "designers": designer_suite_product_integrity(),
        "theater": theater_command_product_integrity(),
        "fleet": fleet_multi_day_autonomy_integrity(),
        "agent": agent_campaign_product_integrity(),
        "combat": multi_phase_combat_product_integrity(),
        "save": save_browser_campaign_product_integrity(),
        "exec": execution_integrity_gate(),
        "sole": sole_mult_integrity(),
    }
    gate_ok = all(
        bool(g.get("ok", g.get("integrity_ok", True)))
        for g in gates.values()
    )
    non_empty = sum(1 for p in pillars if not p.get("empty"))
    avg = sum(float(p.get("score", 0)) for p in pillars) / max(1, len(pillars))
    ok = gate_ok and non_empty >= 7
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    q = [
        _q("apply_focus", province_id, score, "full game campaign close focus"),
        _q("apply_production", province_id, 0.55, "full game campaign close production"),
        _q("apply_assault", province_id, 0.5, "full game campaign close assault"),
        _q("apply_station", province_id, 0.45, "full game campaign close fleet"),
    ]
    return _day(
        "full_game_campaign_close_day",
        "Full game campaign close day",
        "Full game campaign close · pillars %d/7 · gates %s · score %.2f"
        % (non_empty, "PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["full_game", "campaign", "close", "next290"],
        {"pillars": pillars, "gates": gates, "ok": ok, "campaign_score": score},
    )


# ---------------------------------------------------------------------------
# Registry / integrity / close
# ---------------------------------------------------------------------------

FULL_GAME_CAMPAIGN_DAY_IDS = [
    "strategic_ai_doctrine_depth_day",
    "strategic_ai_urgency_board_day",
    "strategic_ai_player_skip_day",
    "strategic_ai_budget_depth_day",
    "strategic_ai_domain_weight_day",
    "strategic_ai_daily_joint_day",
    "strategic_ai_campaign_close_day",
    "designer_catalog_depth_day",
    "designer_seed_production_day",
    "designer_domain_balance_day",
    "oob_horizon_joint_day",
    "production_line_bootstrap_day",
    "industry_design_joint_day",
    "designer_industry_close_day",
    "theater_ai_command_joint_day",
    "fleet_ai_campaign_depth_day",
    "agent_ai_campaign_depth_day",
    "combat_ai_phase_depth_day",
    "save_session_ai_joint_day",
    "full_game_campaign_close_day",
]

DAY_FUNCS = [
    strategic_ai_doctrine_depth_day,
    strategic_ai_urgency_board_day,
    strategic_ai_player_skip_day,
    strategic_ai_budget_depth_day,
    strategic_ai_domain_weight_day,
    strategic_ai_daily_joint_day,
    strategic_ai_campaign_close_day,
    designer_catalog_depth_day,
    designer_seed_production_day,
    designer_domain_balance_day,
    oob_horizon_joint_day,
    production_line_bootstrap_day,
    industry_design_joint_day,
    designer_industry_close_day,
    theater_ai_command_joint_day,
    fleet_ai_campaign_depth_day,
    agent_ai_campaign_depth_day,
    combat_ai_phase_depth_day,
    save_session_ai_joint_day,
    full_game_campaign_close_day,
]


def full_game_campaign_integrity() -> Dict[str, Any]:
    ai = strategic_ai_daily_campaign_integrity()
    des = designer_suite_product_integrity()
    oob = medium_tank_oob_product_integrity()
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    sample = [
        strategic_ai_urgency_board_day(),
        designer_catalog_depth_day(),
        theater_ai_command_joint_day(),
        full_game_campaign_close_day(),
    ]
    ok = (
        bool(ai.get("ok"))
        and bool(des.get("ok"))
        and bool(oob.get("ok"))
        and bool(gate.get("ok"))
        and bool(sole.get("integrity_ok", True))
        and all(not s.get("empty") for s in sample)
    )
    return {
        "ok": ok,
        "ai_ok": bool(ai.get("ok")),
        "designers_ok": bool(des.get("ok")),
        "oob_ok": bool(oob.get("ok")),
        "gate": gate,
        "summary": "Full-game campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next290_full_game_campaign_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = full_game_campaign_integrity()
    ok = bool(gate.get("ok")) and non_empty >= 20
    label = "Close next290 full-game campaign · packages %d/20 · queue %d · %s" % (
        non_empty,
        q_total,
        "PASS" if ok else "FAIL",
    )
    return {
        "packages": packages,
        "non_empty": non_empty,
        "queue_total": q_total,
        "gate": gate,
        "score": non_empty / 20.0,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next290 full-game campaign[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
