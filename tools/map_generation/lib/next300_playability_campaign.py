"""Next-300 playability campaign pillars (20).

A) Air / convoy operational depth (1–7)
B) Focus / intel / leader campaign (8–14)
C) Player session / order feedback / close (15–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from air_forecast_day import (  # type: ignore
    air_forecast_integrity,
    air_ops_day_package,
    air_ops_package,
    air_sortie_weather_gate,
    weather_forecast_planning_day,
)
from focus_pick_priority import rank_focus_picks  # type: ignore
from naval_convoy_escort import plan_convoy_escort  # type: ignore
from campaign_execution import (  # type: ignore
    campaign_decision_strip,
    execution_integrity_gate,
    focus_order_path,
)
from strategic_continuity_day import (  # type: ignore
    focus_war_path_day,
    next_day_feedback,
    order_execute_day,
)
from next10_depth import campaign_decision_day, focus_pick_day  # type: ignore
from next240_air_convoy_order import (  # type: ignore
    air_front_readiness_day,
    air_land_campaign_day,
)
from next250_leader_intel_theater import counterintel_board_ops_day  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from force_readiness_day import force_readiness_day  # type: ignore
from theater_command_product import build_theater_command_product  # type: ignore
from strategic_ai_daily_campaign_product import (  # type: ignore
    build_strategic_ai_daily_campaign_product,
    strategic_ai_daily_campaign_integrity,
)
from combat_multi_phase_product import build_multi_phase_combat_product  # type: ignore
from fleet_multi_day_autonomy_product import build_fleet_multi_day_autonomy_product  # type: ignore
from war_economy_day import war_economy_day_package  # type: ignore


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
        "integration": list(integration or ["next300", "playability_campaign"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.65,
        "precip": 0.35,
        "precip_intensity": 0.35,
        "ground_state": "mud",
        "wind": 0.35,
        "temperature_c": 6.0,
    }


# ---------------------------------------------------------------------------
# A) Air / convoy
# ---------------------------------------------------------------------------


def air_ops_sortie_depth_day(province_id: int = 1) -> Dict[str, Any]:
    air = air_ops_day_package()
    pkg = air_ops_package(_wx())
    score = _floor(0.55 * _norm(float(air.get("score", 0.5))) + 0.45 * _norm(float(pkg.get("score", 0.5))))
    q = [
        _q("apply_focus", province_id, score, "air ops sortie focus"),
        _q("apply_assault", province_id, 0.55, "air ops sortie support assault"),
        _q("apply_station", province_id, 0.45, "air ops sortie station"),
    ]
    return _day(
        "air_ops_sortie_depth_day",
        "Air ops sortie depth day",
        "Air ops sortie depth · air %.2f · package · score %.2f"
        % (float(air.get("score", 0)), score),
        score,
        q,
        "#38bdf8",
        "✈",
        ["air", "sortie", "depth"],
        {"air": air, "package": pkg, "air_score": score},
    )


def air_forecast_planning_depth_day(province_id: int = 1) -> Dict[str, Any]:
    fc = weather_forecast_planning_day()
    score = _floor(_norm(float(fc.get("score", 0.5))))
    q = [
        _q("apply_focus", province_id, score, "air forecast planning focus"),
        _q("apply_supply", province_id, 0.5, "air forecast planning supply"),
        _q("apply_station", province_id, 0.45, "air forecast planning station"),
    ]
    return _day(
        "air_forecast_planning_depth_day",
        "Air forecast planning depth day",
        "Air forecast planning depth · score %.2f" % score,
        score,
        q,
        "#38bdf8",
        "☁",
        ["air", "forecast", "planning"],
        {"forecast": fc, "air_score": score},
    )


def air_sortie_weather_gate_day(province_id: int = 1) -> Dict[str, Any]:
    gate = air_sortie_weather_gate(_wx())
    gscore = float(gate.get("score", gate.get("sortie_ready", 0.5)) if isinstance(gate, dict) else 0.5)
    if not isinstance(gate, dict):
        gate = {"raw": gate, "score": 0.5}
        gscore = 0.5
    score = _floor(_norm(gscore))
    q = [
        _q("apply_station", province_id, score, "air sortie weather gate hold"),
        _q("apply_supply", province_id, 0.5, "air sortie weather gate supply"),
        _q("apply_focus", province_id, 0.45, "air sortie weather gate focus"),
    ]
    return _day(
        "air_sortie_weather_gate_day",
        "Air sortie weather gate day",
        "Air sortie weather gate · score %.2f" % score,
        score,
        q,
        "#94a3b8",
        "🌫",
        ["air", "weather", "gate"],
        {"gate": gate, "air_score": score},
    )


def convoy_escort_campaign_depth_day(province_id: int = 1) -> Dict[str, Any]:
    convoy = plan_convoy_escort(
        ["friendly", "contested", "hostile"],
        70.0,
        cargo_value=100.0,
        interdiction_chance=0.25,
        basing_refuel=0.3,
    )
    need_block = convoy.get("need")
    if isinstance(need_block, dict):
        need = float(need_block.get("escort_need", need_block.get("risk", 0.55)))
        # escort_need is absolute strength (~0-100); normalize
        need = _norm(need if need <= 2.0 else need / 100.0)
    elif isinstance(need_block, (int, float)):
        need = _norm(float(need_block) if float(need_block) <= 2.0 else float(need_block) / 100.0)
    else:
        need = 0.55
    suff = 1.0 if bool(convoy.get("sufficient", False)) else 0.45
    score = _floor(0.55 * need + 0.45 * suff)
    q = [
        _q("apply_station", province_id, score, "convoy escort depth station"),
        _q("apply_supply", province_id, 0.55, "convoy escort depth supply"),
        _q("apply_focus", province_id, 0.4, "convoy escort depth focus"),
    ]
    return _day(
        "convoy_escort_campaign_depth_day",
        "Convoy escort depth day",
        "Convoy escort depth · sufficient %s · score %.2f"
        % ("yes" if convoy.get("sufficient") else "no", score),
        score,
        q,
        "#0ea5e9",
        "🛡",
        ["convoy", "escort", "depth"],
        {"convoy": convoy, "air_score": score},
    )


def air_land_campaign_depth_day(province_id: int = 1) -> Dict[str, Any]:
    joint = air_land_campaign_day(province_id)
    combat = build_multi_phase_combat_product(province_id=province_id)
    score = _floor(0.55 * _norm(float(joint.get("score", 0.5))) + 0.45 * _norm(float(combat.get("score", 0.5))))
    q = [
        _q("apply_assault", province_id, score, "air land campaign assault"),
        _q("apply_focus", province_id, 0.5, "air land campaign focus"),
        _q("apply_supply", province_id, 0.45, "air land campaign supply"),
    ]
    return _day(
        "air_land_campaign_depth_day",
        "Air land campaign depth day",
        "Air land campaign depth · joint %.2f · combat %.2f · score %.2f"
        % (float(joint.get("score", 0)), float(combat.get("score", 0)), score),
        score,
        q,
        "#38bdf8",
        "✈",
        ["air", "land", "campaign"],
        {"joint": joint, "combat": combat, "air_score": score},
    )


def air_front_readiness_depth_day(province_id: int = 1) -> Dict[str, Any]:
    front = air_front_readiness_day(province_id)
    ready = force_readiness_day(weather=_wx())
    score = _floor(0.55 * _norm(float(front.get("score", 0.5))) + 0.45 * _norm(float(ready.get("score", 0.5))))
    q = [
        _q("apply_supply", province_id, score, "air front readiness supply"),
        _q("apply_station", province_id, 0.5, "air front readiness station"),
        _q("apply_focus", province_id, 0.45, "air front readiness focus"),
    ]
    return _day(
        "air_front_readiness_depth_day",
        "Air front readiness depth day",
        "Air front readiness depth · front %.2f · force %.2f · score %.2f"
        % (float(front.get("score", 0)), float(ready.get("score", 0)), score),
        score,
        q,
        "#38bdf8",
        "✈",
        ["air", "front", "readiness"],
        {"front": front, "ready": ready, "air_score": score},
    )


def air_convoy_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [
        air_ops_sortie_depth_day(province_id),
        air_forecast_planning_depth_day(province_id),
        air_sortie_weather_gate_day(province_id),
        convoy_escort_campaign_depth_day(province_id),
        air_land_campaign_depth_day(province_id),
        air_front_readiness_depth_day(province_id),
    ]
    gate = air_forecast_integrity()
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = bool(gate.get("ok", True)) and all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    q = [
        _q("apply_station", province_id, score, "air convoy campaign close station"),
        _q("apply_supply", province_id, 0.5, "air convoy campaign close supply"),
        _q("apply_focus", province_id, 0.45, "air convoy campaign close focus"),
    ]
    return _day(
        "air_convoy_campaign_close_day",
        "Air convoy campaign close day",
        "Air convoy campaign close · packages %d · gate %s · score %.2f"
        % (len(days), "PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["air", "convoy", "close"],
        {"packages": days, "gate": gate, "ok": ok, "air_score": score},
    )


# ---------------------------------------------------------------------------
# B) Focus / intel / leader
# ---------------------------------------------------------------------------


def focus_pick_depth_day(province_id: int = 1) -> Dict[str, Any]:
    picks = rank_focus_picks(
        [
            {"id": "industrial_effort", "urgency": 0.75, "name": "Industrial Effort"},
            {"id": "naval_effort", "urgency": 0.55, "name": "Naval Effort"},
            {"id": "air_effort", "urgency": 0.6, "name": "Air Effort"},
        ]
    )
    day = focus_pick_day(province_id=province_id)
    best = _norm(float(picks.get("best_score", 50)) / 140.0)
    score = _floor(0.55 * best + 0.45 * _norm(float(day.get("score", 0.5))))
    q = [
        _q("apply_focus", province_id, score, "focus pick depth apply"),
        _q("apply_production", province_id, 0.5, "focus pick depth production"),
        _q("apply_station", province_id, 0.4, "focus pick depth station"),
    ]
    return _day(
        "focus_pick_depth_day",
        "Focus pick depth day",
        "Focus pick depth · best %s · score %.2f" % (picks.get("best_id", "—"), score),
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "pick", "depth"],
        {"picks": picks, "day": day, "focus_score": score},
    )


def focus_order_path_day(province_id: int = 1) -> Dict[str, Any]:
    path = focus_order_path(weather=_wx(), focus_id="industrial_effort", focus_base=55.0)
    score = _floor(_norm(float(path.get("score", 0.5))))
    q = [
        _q("apply_focus", province_id, score, "focus order path hold/execute"),
        _q("apply_hh_commit", province_id, 0.5, "focus order path HH"),
        _q("apply_production", province_id, 0.45, "focus order path production"),
    ]
    return _day(
        "focus_order_path_day",
        "Focus order path day",
        "Focus order path · %s · score %.2f" % (path.get("action", "HOLD"), score),
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "order", "path"],
        {"path": path, "focus_score": score},
    )


def focus_war_path_depth_day(province_id: int = 1) -> Dict[str, Any]:
    war = focus_war_path_day(weather=_wx(), province_id=province_id)
    score = _floor(_norm(float(war.get("score", 0.5))))
    q = [
        _q("apply_focus", province_id, score, "focus war path depth"),
        _q("apply_assault", province_id, 0.5, "focus war path assault leaf"),
        _q("apply_hh_commit", province_id, 0.45, "focus war path agenda"),
    ]
    return _day(
        "focus_war_path_depth_day",
        "Focus war path depth day",
        "Focus war path depth · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "war_path", "depth"],
        {"war": war, "focus_score": score},
    )


def war_path_urgency_depth_day(province_id: int = 1) -> Dict[str, Any]:
    path = focus_order_path(weather=_wx(), focus_id="naval_effort", focus_base=60.0)
    board = path.get("board") or {}
    urg = float((board.get("war_path") or {}).get("urgency", path.get("score", 0.4)))
    score = _floor(0.5 * _norm(float(path.get("score", 0.5))) + 0.5 * _norm(urg))
    q = [
        _q("apply_focus", province_id, score, "war path urgency focus"),
        _q("apply_station", province_id, 0.55, "war path urgency fleet"),
        _q("apply_production", province_id, 0.45, "war path urgency production"),
    ]
    return _day(
        "war_path_urgency_depth_day",
        "War path urgency depth day",
        "War path urgency depth · urg %.0f%% · score %.2f" % (urg * 100.0 if urg <= 1 else urg, score),
        score,
        q,
        "#c084fc",
        "◆",
        ["focus", "war_path", "urgency"],
        {"path": path, "focus_score": score},
    )


def intel_counter_depth_campaign_day(province_id: int = 1) -> Dict[str, Any]:
    intel = counterintel_board_ops_day(province_id)
    score = _floor(_norm(float(intel.get("score", 0.5))))
    q = [
        _q("apply_agent_dispatch", province_id, score, "intel counter depth dispatch"),
        _q("apply_hh_commit", province_id, 0.5, "intel counter depth HH"),
        _q("apply_focus", province_id, 0.45, "intel counter depth focus"),
    ]
    return _day(
        "intel_counter_depth_campaign_day",
        "Intel counter depth campaign day",
        "Intel counter depth campaign · score %.2f" % score,
        score,
        q,
        "#a78bfa",
        "🕵",
        ["intel", "counter", "campaign"],
        {"intel": intel, "focus_score": score},
    )


def leader_campaign_assign_day(province_id: int = 1) -> Dict[str, Any]:
    ready = force_readiness_day(weather=_wx())
    theater = build_theater_command_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(ready.get("score", 0.5))) + 0.5 * _norm(float(theater.get("score", 0.5))))
    q = [
        _q("apply_station", province_id, score, "leader campaign assign station"),
        _q("apply_focus", province_id, 0.5, "leader campaign assign focus"),
        _q("apply_assault", province_id, 0.45, "leader campaign assign assault"),
    ]
    return _day(
        "leader_campaign_assign_day",
        "Leader campaign assign day",
        "Leader campaign assign · force %.2f · theater %.2f · score %.2f"
        % (float(ready.get("score", 0)), float(theater.get("score", 0)), score),
        score,
        q,
        "#fbbf24",
        "★",
        ["leader", "campaign", "assign"],
        {"ready": ready, "theater": theater, "focus_score": score},
    )


def focus_intel_leader_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [
        focus_pick_depth_day(province_id),
        focus_order_path_day(province_id),
        focus_war_path_depth_day(province_id),
        war_path_urgency_depth_day(province_id),
        intel_counter_depth_campaign_day(province_id),
        leader_campaign_assign_day(province_id),
    ]
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    q = [
        _q("apply_focus", province_id, score, "focus intel leader close focus"),
        _q("apply_agent_dispatch", province_id, 0.5, "focus intel leader close agent"),
        _q("apply_station", province_id, 0.45, "focus intel leader close station"),
    ]
    return _day(
        "focus_intel_leader_close_day",
        "Focus intel leader close day",
        "Focus intel leader close · packages %d · gate %s · score %.2f"
        % (len(days), "PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["focus", "intel", "leader", "close"],
        {"packages": days, "ok": ok, "focus_score": score},
    )


# ---------------------------------------------------------------------------
# C) Session / playability
# ---------------------------------------------------------------------------


def order_execute_session_day(province_id: int = 1) -> Dict[str, Any]:
    ex = order_execute_day(weather=_wx(), province_id=province_id)
    score = _floor(_norm(float(ex.get("score", 0.5))))
    q = list(ex.get("apply_queue") or [])[:3] or [
        _q("apply_focus", province_id, score, "order execute session focus"),
        _q("apply_station", province_id, 0.5, "order execute session station"),
        _q("apply_assault", province_id, 0.45, "order execute session assault"),
    ]
    return _day(
        "order_execute_session_day",
        "Order execute session day",
        "Order execute session · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "▶",
        ["order", "execute", "session"],
        {"execute": ex, "session_score": score},
    )


def next_day_feedback_session_day(province_id: int = 1) -> Dict[str, Any]:
    before = float(order_execute_day(weather=_wx(), province_id=province_id).get("score", 0.5))
    after = min(1.0, before + 0.08)
    fb = next_day_feedback(before_score=before, after_score=after, order="apply_focus")
    score = _floor(0.5 * _norm(after) + 0.5 * (0.7 if fb.get("trend") == "improved" else 0.45))
    q = [
        _q("apply_focus", province_id, score, "next day feedback session follow"),
        _q("apply_supply", province_id, 0.5, "next day feedback session supply"),
        _q("apply_station", province_id, 0.45, "next day feedback session station"),
    ]
    return _day(
        "next_day_feedback_session_day",
        "Next day feedback session day",
        "Next day feedback session · %s · Δ%+.2f · score %.2f"
        % (fb.get("trend", "—"), float(fb.get("delta", 0)), score),
        score,
        q,
        "#5ec8ff",
        "↻",
        ["session", "feedback", "next_day"],
        {"feedback": fb, "session_score": score},
    )


def campaign_decision_session_day(province_id: int = 1) -> Dict[str, Any]:
    dec = campaign_decision_day(province_id=province_id)
    strip = campaign_decision_strip(
        [
            dec if isinstance(dec, dict) else {"summary": str(dec), "score": 0.5, "empty": False},
            {"summary": "air ops", "score": 0.55, "empty": False},
            {"summary": "focus pick", "score": 0.6, "empty": False},
            {"summary": "theater AI", "score": 0.65, "empty": False},
        ]
    )
    strip_sc = float(strip.get("score", 0.5)) if isinstance(strip, dict) else 0.5
    score = _floor(0.55 * _norm(float(dec.get("score", 0.5))) + 0.45 * _norm(strip_sc))
    q = [
        _q("apply_focus", province_id, score, "campaign decision session focus"),
        _q("apply_assault", province_id, 0.5, "campaign decision session assault"),
        _q("apply_production", province_id, 0.45, "campaign decision session production"),
    ]
    return _day(
        "campaign_decision_session_day",
        "Campaign decision session day",
        "Campaign decision session · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◎",
        ["campaign", "decision", "session"],
        {"decision": dec, "strip": strip, "session_score": score},
    )


def theater_ai_session_joint_day(province_id: int = 1) -> Dict[str, Any]:
    th = build_theater_command_product(province_id=province_id)
    ai = build_strategic_ai_daily_campaign_product(player_tag="GER", province_id=province_id)
    score = _floor(0.5 * _norm(float(th.get("score", 0.5))) + 0.5 * _norm(float(ai.get("score", 0.5))))
    q = [
        _q(str(th.get("top_leaf", "apply_assault")), province_id, score, "theater AI session top leaf"),
        _q("apply_focus", province_id, 0.5, "theater AI session focus"),
        _q("apply_station", province_id, 0.45, "theater AI session station"),
    ]
    return _day(
        "theater_ai_session_joint_day",
        "Theater AI session joint day",
        "Theater AI session joint · theater %.2f · AI budget %d · score %.2f"
        % (float(th.get("score", 0)), int(ai.get("budget_count", 0)), score),
        score,
        q,
        "#a78bfa",
        "♟",
        ["theater", "ai", "session"],
        {"theater": th, "ai": ai, "session_score": score},
    )


def force_readiness_session_day(province_id: int = 1) -> Dict[str, Any]:
    ready = force_readiness_day(weather=_wx())
    fleet = build_fleet_multi_day_autonomy_product(province_id=province_id)
    econ = war_economy_day_package(weather=_wx())
    score = _floor(
        0.4 * _norm(float(ready.get("score", 0.5)))
        + 0.3 * _norm(float(fleet.get("score", 0.5)))
        + 0.3 * _norm(float(econ.get("score", 0.5)))
    )
    q = [
        _q("apply_supply", province_id, score, "force readiness session supply"),
        _q("apply_production", province_id, 0.5, "force readiness session production"),
        _q("apply_station", province_id, 0.45, "force readiness session station"),
    ]
    return _day(
        "force_readiness_session_day",
        "Force readiness session day",
        "Force readiness session · force %.2f · fleet %.2f · econ %.2f · score %.2f"
        % (
            float(ready.get("score", 0)),
            float(fleet.get("score", 0)),
            float(econ.get("score", 0)),
            score,
        ),
        score,
        q,
        "#fbbf24",
        "🛡",
        ["force", "readiness", "session"],
        {"ready": ready, "fleet": fleet, "economy": econ, "session_score": score},
    )


def play_session_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    pillars = [
        air_convoy_campaign_close_day(province_id),
        focus_intel_leader_close_day(province_id),
        order_execute_session_day(province_id),
        next_day_feedback_session_day(province_id),
        campaign_decision_session_day(province_id),
        theater_ai_session_joint_day(province_id),
        force_readiness_session_day(province_id),
    ]
    gates = {
        "air": air_forecast_integrity(),
        "ai": strategic_ai_daily_campaign_integrity(),
        "exec": execution_integrity_gate(),
        "sole": sole_mult_integrity(),
    }
    gate_ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates.values())
    non_empty = sum(1 for p in pillars if not p.get("empty"))
    avg = sum(float(p.get("score", 0)) for p in pillars) / max(1, len(pillars))
    ok = gate_ok and non_empty >= 7
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    q = [
        _q("apply_focus", province_id, score, "play session campaign close focus"),
        _q("apply_production", province_id, 0.55, "play session campaign close production"),
        _q("apply_assault", province_id, 0.5, "play session campaign close assault"),
        _q("apply_station", province_id, 0.45, "play session campaign close fleet"),
    ]
    return _day(
        "play_session_campaign_close_day",
        "Play session campaign close day",
        "Play session campaign close · pillars %d/7 · gates %s · score %.2f"
        % (non_empty, "PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["play_session", "campaign", "close", "next300"],
        {"pillars": pillars, "gates": gates, "ok": ok, "session_score": score},
    )


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

PLAYABILITY_CAMPAIGN_DAY_IDS = [
    "air_ops_sortie_depth_day",
    "air_forecast_planning_depth_day",
    "air_sortie_weather_gate_day",
    "convoy_escort_campaign_depth_day",
    "air_land_campaign_depth_day",
    "air_front_readiness_depth_day",
    "air_convoy_campaign_close_day",
    "focus_pick_depth_day",
    "focus_order_path_day",
    "focus_war_path_depth_day",
    "war_path_urgency_depth_day",
    "intel_counter_depth_campaign_day",
    "leader_campaign_assign_day",
    "focus_intel_leader_close_day",
    "order_execute_session_day",
    "next_day_feedback_session_day",
    "campaign_decision_session_day",
    "theater_ai_session_joint_day",
    "force_readiness_session_day",
    "play_session_campaign_close_day",
]

DAY_FUNCS = [
    air_ops_sortie_depth_day,
    air_forecast_planning_depth_day,
    air_sortie_weather_gate_day,
    convoy_escort_campaign_depth_day,
    air_land_campaign_depth_day,
    air_front_readiness_depth_day,
    air_convoy_campaign_close_day,
    focus_pick_depth_day,
    focus_order_path_day,
    focus_war_path_depth_day,
    war_path_urgency_depth_day,
    intel_counter_depth_campaign_day,
    leader_campaign_assign_day,
    focus_intel_leader_close_day,
    order_execute_session_day,
    next_day_feedback_session_day,
    campaign_decision_session_day,
    theater_ai_session_joint_day,
    force_readiness_session_day,
    play_session_campaign_close_day,
]


def playability_campaign_integrity() -> Dict[str, Any]:
    air = air_forecast_integrity()
    ai = strategic_ai_daily_campaign_integrity()
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    sample = [
        air_ops_sortie_depth_day(),
        focus_pick_depth_day(),
        order_execute_session_day(),
        play_session_campaign_close_day(),
    ]
    ok = (
        bool(air.get("ok", True))
        and bool(ai.get("ok"))
        and bool(gate.get("ok"))
        and bool(sole.get("integrity_ok", True))
        and all(not s.get("empty") for s in sample)
    )
    return {
        "ok": ok,
        "air_ok": bool(air.get("ok", True)),
        "ai_ok": bool(ai.get("ok")),
        "gate": gate,
        "summary": "Playability campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next300_playability_campaign_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = playability_campaign_integrity()
    ok = bool(gate.get("ok")) and non_empty >= 20
    label = "Close next300 playability campaign · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next300 playability campaign[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
