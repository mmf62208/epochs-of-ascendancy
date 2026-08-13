"""Next-170 combat multi-phase, agent/HH campaign, joint multi-domain (20 packages).

A) Combat multi-phase / assault continuity (1–7)
B) Agent / HH campaign path (8–14)
C) Joint multi-domain command (15–20)

1 combat_phase_ops_day · 2 assault_ready_ops_day · 3 multi_phase_est_ops_day
4 combat_order_ops_day · 5 assault_rank_ops_day · 6 phase_ribbon_ops_day
7 combat_phase_close_day · 8 agent_mission_campaign_day · 9 agent_dispatch_ops_day
10 hh_commit_campaign_day · 11 counterplay_campaign_day · 12 hh_agenda_ops_day
13 agent_hh_joint_day · 14 agent_hh_close_day · 15 joint_theater_combat_day
16 joint_naval_combat_day · 17 focus_joint_ops_day · 18 joint_command_ops_day
19 multi_domain_strip_day · 20 combat_agent_joint_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from integrated_theater_ops import assault_readiness_compose  # type: ignore
from campaign_cohesion import (  # type: ignore
    agent_campaign_response,
    combat_campaign_phase,
    hh_campaign_board,
    theater_campaign_strip,
)
from campaign_ops_depth import combat_air_naval_joint  # type: ignore
from joint_campaign_day import joint_campaign_day  # type: ignore
from campaign_execution import (  # type: ignore
    execution_integrity_gate,
    close_the_loop,
    theater_order_board,
)
from gameplay_loops import sole_mult_integrity, counter_ops_execute_order  # type: ignore
from agent_mission_priority import rank_agent_missions  # type: ignore
from map_next_list_helpers import apply_hh_counterplay, pick_hh_action_class  # type: ignore
from live_mutation import (  # type: ignore
    assault_stage_mutation,
    agent_dispatch_mutation,
    hh_commit_mutation,
)
from theater_ops_polish import focus_weather_aware_score  # type: ignore
from campaign_cohesion import naval_campaign_package  # type: ignore


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


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
    color: str = "#5ec8ff",
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
        "integration": list(integration or ["next170", "combat_agent_joint"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _leaf_queue(raw: Any, province_id: int, fallback: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    leaf: List[Dict[str, Any]] = []
    if isinstance(raw, list):
        for item in raw:
            if not isinstance(item, Mapping):
                continue
            aid = str(item.get("action_id", ""))
            if not aid or aid.endswith("_day"):
                continue
            row = dict(item)
            if not row.get("province_id"):
                row["province_id"] = province_id
            leaf.append(row)
    return leaf[:4] if leaf else fallback


# A) Combat multi-phase


def combat_phase_ops_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0)
    phase = combat_campaign_phase()
    win = float(est.get("overall_attacker_win_chance", 0.5))
    score = _norm(0.5 * win + 0.5 * float(phase.get("score", 0.5)))
    q = [
        _q("apply_assault", province_id, score, "combat phase ops primary"),
        _q("apply_supply", province_id, 0.5, "combat phase ops supply"),
    ]
    return _day(
        "combat_phase_ops_day",
        "Combat phase ops day",
        "Combat phase ops · win %.2f · score %.2f" % (win, score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["combat", "phase", "ops"],
        {"estimate": est, "phase": phase, "win_chance": win},
    )


def assault_ready_ops_day(province_id: int = 1) -> Dict[str, Any]:
    ready = assault_readiness_compose(
        [{"province_id": province_id, "defender_power": 45, "supply": 0.6}],
        100.0,
    )
    score = 0.6
    if not bool(ready.get("empty", False)):
        score = _norm(0.55 + 0.1)
    q = [
        _q("apply_assault", province_id, score, "assault ready ops primary"),
        _q("apply_supply", province_id, 0.5, "assault ready ops supply"),
    ]
    return _day(
        "assault_ready_ops_day",
        "Assault ready ops day",
        "Assault ready ops · %s · score %.2f" % (ready.get("summary", "ready"), score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["combat", "assault", "readiness"],
        {"readiness": ready},
    )


def multi_phase_est_ops_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0, attacker_supply=0.85, weather_mult=0.85)
    win = float(est.get("overall_attacker_win_chance", 0.5))
    engage = float(est.get("engage_win_chance", win))
    score = _norm(0.6 * win + 0.4 * engage)
    q = [
        _q("apply_assault", province_id, score, "multi phase estimate primary"),
        _q("apply_supply", province_id, 0.5, "multi phase estimate supply"),
        _q("apply_station", province_id, 0.45, "multi phase estimate station"),
    ]
    return _day(
        "multi_phase_est_ops_day",
        "Multi phase estimate day",
        "Multi phase estimate · win %.2f · engage %.2f · score %.2f" % (win, engage, score),
        score,
        q,
        "#ef8f6e",
        "📊",
        ["combat", "multi_phase", "estimate"],
        {"estimate": est, "win_chance": win, "engage_win": engage},
    )


def combat_order_ops_day(province_id: int = 1) -> Dict[str, Any]:
    mut = assault_stage_mutation()
    score = _norm(float(mut.get("score", 0.5)))
    q = [
        _q("apply_assault", province_id, score, "combat order ops primary"),
        _q("apply_supply", province_id, 0.5, "combat order ops supply"),
    ]
    return _day(
        "combat_order_ops_day",
        "Combat order ops day",
        "Combat order ops · %s · score %.2f" % (mut.get("summary", "order"), score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["combat", "order", "ops"],
        {"mutation": mut},
    )


def assault_rank_ops_day(province_id: int = 1) -> Dict[str, Any]:
    ready = assault_readiness_compose(
        [
            {"province_id": province_id, "defender_power": 50, "supply": 0.55},
            {"province_id": province_id + 1, "defender_power": 40, "supply": 0.7},
        ],
        100.0,
    )
    best = int(ready.get("best_province_id", province_id) or province_id)
    score = _norm(0.62)
    q = [
        _q("apply_assault", best if best > 0 else province_id, score, "assault rank ops primary"),
        _q("apply_supply", province_id, 0.5, "assault rank ops supply"),
    ]
    return _day(
        "assault_rank_ops_day",
        "Assault rank ops day",
        "Assault rank ops · best #%d · score %.2f" % (best, score),
        score,
        q,
        "#ef8f6e",
        "◎",
        ["combat", "assault", "rank"],
        {"readiness": ready, "best_province_id": best},
    )


def phase_ribbon_ops_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0)
    phases = est.get("phases") or est.get("phase_names") or []
    win = float(est.get("overall_attacker_win_chance", 0.5))
    score = _norm(win)
    q = [
        _q("apply_assault", province_id, score, "phase ribbon ops primary"),
        _q("refresh_queue", province_id, 0.5, "phase ribbon ops refresh"),
    ]
    return _day(
        "phase_ribbon_ops_day",
        "Phase ribbon ops day",
        "Phase ribbon ops · phases %d · win %.2f · score %.2f"
        % (len(phases) if isinstance(phases, list) else 3, win, score),
        score,
        q,
        "#ef8f6e",
        "🎗",
        ["combat", "phase", "ribbon"],
        {"estimate": est, "win_chance": win},
    )


def combat_phase_close_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0)
    ready = assault_readiness_compose(
        [{"province_id": province_id, "defender_power": 45, "supply": 0.6}], 100.0
    )
    mut = assault_stage_mutation()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    win = float(est.get("overall_attacker_win_chance", 0.5))
    score = _norm(
        0.35 * win
        + 0.35 * float(mut.get("score", 0.5))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_assault", province_id, score, "combat phase close assault"),
        _q("apply_supply", province_id, 0.55, "combat phase close supply"),
        _q("apply_station", province_id, 0.45, "combat phase close station"),
    ]
    return _day(
        "combat_phase_close_day",
        "Combat phase close day",
        "Combat phase close · win %.2f · gate %s · score %.2f"
        % (win, "PASS" if ok else "FAIL", score),
        score,
        q,
        "#ef8f6e",
        "∞",
        ["combat", "phase", "close"],
        {"estimate": est, "readiness": ready, "mutation": mut, "gate": gate, "ok": ok, "win_chance": win},
    )


# B) Agent / HH campaign


def agent_mission_campaign_day(province_id: int = 1) -> Dict[str, Any]:
    missions = rank_agent_missions(hh_action_class="sabotage", threat=0.55)
    best = float(missions.get("best_score", 0.6) or 0.6)
    score = _norm(best if best <= 1.0 else best / 100.0)
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent mission campaign primary"),
        _q("apply_counterplay", province_id, 0.5, "agent mission campaign counter"),
    ]
    return _day(
        "agent_mission_campaign_day",
        "Agent mission campaign day",
        "Agent mission campaign · %s · score %.2f" % (missions.get("best_mission", "mission"), score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "mission", "campaign"],
        {"missions": missions},
    )


def agent_dispatch_ops_day(province_id: int = 1) -> Dict[str, Any]:
    mut = agent_dispatch_mutation()
    resp = agent_campaign_response()
    score = _norm(max(float(mut.get("score", 0.5)), float(resp.get("score", 0.5))))
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent dispatch ops primary"),
        _q("apply_hh_commit", province_id, 0.5, "agent dispatch ops hh"),
    ]
    return _day(
        "agent_dispatch_ops_day",
        "Agent dispatch ops day",
        "Agent dispatch ops · mut · campaign · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "dispatch", "ops"],
        {"mutation": mut, "response": resp},
    )


def hh_commit_campaign_day(province_id: int = 1) -> Dict[str, Any]:
    mut = hh_commit_mutation()
    board = hh_campaign_board()
    score = _norm(max(float(mut.get("score", 0.5)), float(board.get("score", 0.45))))
    if bool(mut.get("empty", False)) and bool(board.get("empty", False)):
        score = 0.45
    q = [
        _q("apply_hh_commit", province_id, score, "hh commit campaign primary"),
        _q("apply_counterplay", province_id, 0.5, "hh commit campaign counter"),
    ]
    return _day(
        "hh_commit_campaign_day",
        "HH commit campaign day",
        "HH commit campaign · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["hh", "commit", "campaign"],
        {"mutation": mut, "board": board},
    )


def counterplay_campaign_day(province_id: int = 1) -> Dict[str, Any]:
    counter = apply_hh_counterplay(
        0.55, {"action_class": "sabotage", "province_id": province_id, "influence": 0.55}
    )
    try:
        order = counter_ops_execute_order(
            {"action_class": "sabotage", "influence": 0.55, "province_id": province_id}
        )
    except TypeError:
        order = counter_ops_execute_order(
            signal={"action_class": "sabotage", "influence": 0.55, "province_id": province_id}
        )
    score = _norm(0.55 + float(counter.get("reduction", 0.12) or 0.12))
    q = [
        _q("apply_counterplay", province_id, score, "counterplay campaign primary"),
        _q("apply_agent_dispatch", province_id, 0.55, "counterplay campaign agents"),
    ]
    return _day(
        "counterplay_campaign_day",
        "Counterplay campaign day",
        "Counterplay campaign · %s · score %.2f" % (counter.get("method", "counter"), score),
        score,
        q,
        "#c084fc",
        "🛡",
        ["hh", "counterplay", "campaign"],
        {"counter": counter, "order": order},
    )


def hh_agenda_ops_day(province_id: int = 1) -> Dict[str, Any]:
    primary = pick_hh_action_class(3, 0.55)
    board = hh_campaign_board()
    mut = hh_commit_mutation()
    score = _norm(max(0.55, float(board.get("score", 0.5)), float(mut.get("score", 0.45))))
    q = [
        _q("apply_hh_commit", province_id, score, "hh agenda ops commit"),
        _q("apply_counterplay", province_id, 0.55, "hh agenda ops counter"),
        _q("apply_agent_dispatch", province_id, 0.5, "hh agenda ops agents"),
    ]
    return _day(
        "hh_agenda_ops_day",
        "HH agenda ops day",
        "HH agenda ops · class %s · score %.2f" % (primary, score),
        score,
        q,
        "#c084fc",
        "📜",
        ["hh", "agenda", "ops"],
        {"primary": primary, "board": board, "mutation": mut},
    )


def agent_hh_joint_day(province_id: int = 1) -> Dict[str, Any]:
    missions = rank_agent_missions(hh_action_class="sabotage", threat=0.55)
    resp = agent_campaign_response()
    hh = hh_commit_mutation()
    best = float(missions.get("best_score", 0.6) or 0.6)
    if best > 1.0:
        best = best / 100.0
    score = _norm(0.4 * best + 0.3 * float(resp.get("score", 0.5)) + 0.3 * float(hh.get("score", 0.45)))
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent hh joint agents"),
        _q("apply_hh_commit", province_id, 0.55, "agent hh joint hh"),
        _q("apply_counterplay", province_id, 0.5, "agent hh joint counter"),
    ]
    return _day(
        "agent_hh_joint_day",
        "Agent HH joint day",
        "Agent HH joint · missions · hh · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["agent", "hh", "joint"],
        {"missions": missions, "response": resp, "hh": hh},
    )


def agent_hh_close_day(province_id: int = 1) -> Dict[str, Any]:
    missions = rank_agent_missions(hh_action_class="sabotage", threat=0.55)
    counter = apply_hh_counterplay(0.55, {"action_class": "sabotage", "province_id": province_id})
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    best = float(missions.get("best_score", 0.6) or 0.6)
    if best > 1.0:
        best = best / 100.0
    score = _norm(
        0.35 * best
        + 0.35 * (0.55 + float(counter.get("reduction", 0.12) or 0.12))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent hh close agents"),
        _q("apply_hh_commit", province_id, 0.55, "agent hh close hh"),
        _q("apply_counterplay", province_id, 0.5, "agent hh close counter"),
    ]
    return _day(
        "agent_hh_close_day",
        "Agent HH close day",
        "Agent HH close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#c084fc",
        "✓",
        ["agent", "hh", "close"],
        {"missions": missions, "counter": counter, "gate": gate, "ok": ok},
    )


# C) Joint multi-domain


def joint_theater_combat_day(province_id: int = 1) -> Dict[str, Any]:
    strip = theater_campaign_strip()
    combat = combat_campaign_phase()
    board = theater_order_board(
        [{"summary": "assault", "score": 0.65}, {"summary": "supply", "score": 0.6}]
    )
    score = _norm(
        0.4 * float(strip.get("score", 0.5))
        + 0.4 * float(combat.get("score", 0.5))
        + 0.2 * float(board.get("score", 0.5))
    )
    q = [
        _q("apply_assault", province_id, score, "joint theater combat assault"),
        _q("apply_supply", province_id, 0.55, "joint theater combat supply"),
        _q("apply_station", province_id, 0.5, "joint theater combat station"),
    ]
    return _day(
        "joint_theater_combat_day",
        "Joint theater combat day",
        "Joint theater combat · theater · combat · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "🗺",
        ["joint", "theater", "combat"],
        {"strip": strip, "combat": combat, "board": board},
    )


def joint_naval_combat_day(province_id: int = 1) -> Dict[str, Any]:
    air_naval = combat_air_naval_joint()
    naval = naval_campaign_package()
    score = _norm(max(float(air_naval.get("score", 0.5)), float(naval.get("score", 0.5))))
    q = [
        _q("apply_assault", province_id, score, "joint naval combat assault"),
        _q("apply_station", province_id, 0.55, "joint naval combat station"),
        _q("apply_supply", province_id, 0.5, "joint naval combat supply"),
    ]
    return _day(
        "joint_naval_combat_day",
        "Joint naval combat day",
        "Joint naval combat · air-naval · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["joint", "naval", "combat"],
        {"air_naval": air_naval, "naval": naval},
    )


def focus_joint_ops_day(province_id: int = 1) -> Dict[str, Any]:
    focus = focus_weather_aware_score(50.0, "industrial_effort")
    joint = joint_campaign_day()
    raw = float(focus.get("score", 50.0))
    fscore = _norm(raw / 100.0 if raw > 2.0 else raw)
    score = _norm(0.5 * fscore + 0.5 * float(joint.get("score", 0.5)))
    q = _leaf_queue(
        joint.get("apply_queue"),
        province_id,
        [
            _q("apply_focus", province_id, score, "focus joint ops focus"),
            _q("apply_production", province_id, 0.55, "focus joint ops production"),
            _q("apply_assault", province_id, 0.5, "focus joint ops assault"),
        ],
    )
    if not any(str(i.get("action_id")) == "apply_focus" for i in q):
        q.insert(0, _q("apply_focus", province_id, score, "focus joint ops focus"))
    return _day(
        "focus_joint_ops_day",
        "Focus joint ops day",
        "Focus joint ops · focus · joint · score %.2f" % score,
        score,
        q[:4],
        "#c084fc",
        "◆",
        ["joint", "focus", "ops"],
        {"focus": focus, "joint": joint},
    )


def joint_command_ops_day(province_id: int = 1) -> Dict[str, Any]:
    joint = joint_campaign_day()
    board = theater_order_board(
        [
            {"summary": "combat", "score": 0.7},
            {"summary": "naval", "score": 0.65},
            {"summary": "agents", "score": 0.6},
        ]
    )
    score = _norm(max(float(joint.get("score", 0.5)), float(board.get("score", 0.5))))
    q = _leaf_queue(
        joint.get("apply_queue"),
        province_id,
        [
            _q("apply_assault", province_id, score, "joint command assault"),
            _q("apply_station", province_id, 0.55, "joint command station"),
            _q("apply_agent_dispatch", province_id, 0.5, "joint command agents"),
        ],
    )
    return _day(
        "joint_command_ops_day",
        "Joint command ops day",
        "Joint command ops · score %.2f" % score,
        score,
        q[:4],
        "#7dd3a0",
        "◎",
        ["joint", "command", "ops"],
        {"joint": joint, "board": board},
    )


def multi_domain_strip_day(province_id: int = 1) -> Dict[str, Any]:
    strip = theater_campaign_strip()
    air_naval = combat_air_naval_joint()
    agents = rank_agent_missions(hh_action_class="sabotage", threat=0.5)
    score = _norm(
        0.4 * float(strip.get("score", 0.5))
        + 0.4 * float(air_naval.get("score", 0.5))
        + 0.2 * _norm(float(agents.get("best_score", 0.6) or 0.6))
    )
    q = [
        _q("refresh_queue", province_id, score, "multi domain strip refresh"),
        _q("apply_assault", province_id, 0.55, "multi domain strip assault"),
        _q("apply_station", province_id, 0.5, "multi domain strip station"),
        _q("apply_agent_dispatch", province_id, 0.45, "multi domain strip agents"),
    ]
    return _day(
        "multi_domain_strip_day",
        "Multi domain strip day",
        "Multi domain strip · theater · naval · agents · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "◆",
        ["joint", "multi_domain", "strip"],
        {"strip": strip, "air_naval": air_naval, "missions": agents},
    )


def combat_agent_joint_close_day(province_id: int = 1) -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0)
    missions = rank_agent_missions(hh_action_class="sabotage", threat=0.55)
    joint = joint_campaign_day()
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    win = float(est.get("overall_attacker_win_chance", 0.5))
    best = float(missions.get("best_score", 0.6) or 0.6)
    if best > 1.0:
        best = best / 100.0
    score = _norm(
        0.25 * win
        + 0.25 * best
        + 0.25 * float(joint.get("score", 0.5))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_assault", province_id, win, "close combat assault"),
        _q("apply_agent_dispatch", province_id, best, "close agent dispatch"),
        _q("apply_station", province_id, 0.5, "close joint station"),
        _q("apply_hh_commit", province_id, 0.45, "close hh commit"),
    ]
    return _day(
        "combat_agent_joint_close_day",
        "Combat agent joint close day",
        "Combat agent joint close · combat · agent · joint · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["combat", "agent", "joint", "close"],
        {
            "estimate": est,
            "missions": missions,
            "joint": joint,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
            "win_chance": win,
        },
    )


COMBAT_AGENT_JOINT_DAY_IDS: List[str] = [
    "combat_phase_ops_day",
    "assault_ready_ops_day",
    "multi_phase_est_ops_day",
    "combat_order_ops_day",
    "assault_rank_ops_day",
    "phase_ribbon_ops_day",
    "combat_phase_close_day",
    "agent_mission_campaign_day",
    "agent_dispatch_ops_day",
    "hh_commit_campaign_day",
    "counterplay_campaign_day",
    "hh_agenda_ops_day",
    "agent_hh_joint_day",
    "agent_hh_close_day",
    "joint_theater_combat_day",
    "joint_naval_combat_day",
    "focus_joint_ops_day",
    "joint_command_ops_day",
    "multi_domain_strip_day",
    "combat_agent_joint_close_day",
]


DAY_FUNCS = [
    combat_phase_ops_day,
    assault_ready_ops_day,
    multi_phase_est_ops_day,
    combat_order_ops_day,
    assault_rank_ops_day,
    phase_ribbon_ops_day,
    combat_phase_close_day,
    agent_mission_campaign_day,
    agent_dispatch_ops_day,
    hh_commit_campaign_day,
    counterplay_campaign_day,
    hh_agenda_ops_day,
    agent_hh_joint_day,
    agent_hh_close_day,
    joint_theater_combat_day,
    joint_naval_combat_day,
    focus_joint_ops_day,
    joint_command_ops_day,
    multi_domain_strip_day,
    combat_agent_joint_close_day,
]


def combat_agent_joint_integrity() -> Dict[str, Any]:
    est = estimate_multi_phase_combat(100.0, 80.0)
    missions = rank_agent_missions(hh_action_class="sabotage", threat=0.55)
    joint = joint_campaign_day()
    gate = execution_integrity_gate()
    ok = (
        float(est.get("overall_attacker_win_chance", 0)) > 0.0
        and not bool(missions.get("empty", False))
        and not bool(joint.get("empty", False))
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "win_chance": float(est.get("overall_attacker_win_chance", 0)),
        "mission": missions.get("best_mission", ""),
        "joint_score": float(joint.get("score", 0)),
        "gate": gate,
        "summary": "Combat-agent-joint integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next170_combat_agent_joint_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = combat_agent_joint_integrity()
    label = "Close next170 combat-agent-joint · packages %d/20 · queue %d · %s" % (
        non_empty,
        q_total,
        "PASS" if gate.get("ok") and non_empty >= 20 else "FAIL",
    )
    return {
        "packages": packages,
        "non_empty": non_empty,
        "queue_total": q_total,
        "gate": gate,
        "score": non_empty / 20.0,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next170 combat-agent-joint[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
