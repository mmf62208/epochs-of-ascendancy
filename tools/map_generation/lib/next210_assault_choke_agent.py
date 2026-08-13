"""Next-210 reinforced assault/follow-on, choke/sea-zone, agent escalation (20 packages).

A) Reinforced assault / follow-on (1–7)
B) Choke / sea-zone control (8–14)
C) Agent escalation / coverage (15–20)

1 follow_on_assault_ops_day · 2 reinforced_combat_ops_day · 3 war_path_urgency_ops_day
4 assault_follow_ops_day · 5 reinforce_step_ops_day · 6 combat_urgency_ops_day
7 follow_reinforce_close_day · 8 choke_sea_wx_ops_day · 9 sea_zone_mod_ops_day
10 basing_choke_ops_day · 11 choke_control_ops_day · 12 sea_zone_control_ops_day
13 choke_basing_joint_day · 14 choke_sea_close_day · 15 agent_escalation_ops_day
16 coverage_ops_day · 17 counter_ops_board_ops_day · 18 escalation_ladder_ops_day
19 agent_coverage_joint_day · 20 assault_choke_agent_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from gameplay_loops import (  # type: ignore
    assault_follow_on_loop,
    reinforced_assault_loop,
    war_path_urgency,
    counter_ops_execute_order,
    basing_fleet_fuel_logistics,
    sole_mult_integrity,
)
from integrated_theater_ops import (  # type: ignore
    counter_ops_board,
    choke_sea_weather_package,
    assault_readiness_compose,
)
from theater_ops_polish import choke_weather_synergy  # type: ignore
from sea_zone_control import sea_zone_strategic_modifiers, compute_sea_zone_control  # type: ignore
from map_polish_pilots import choke_basing_synergy_score  # type: ignore
from agent_escalation_ladder import plan_agent_escalation  # type: ignore
from agent_coverage_plan import plan_agent_coverage  # type: ignore
from campaign_execution import execution_integrity_gate, close_the_loop  # type: ignore
from map_next_list_helpers import apply_hh_counterplay  # type: ignore
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore


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
        "integration": list(integration or ["next210", "assault_choke_agent"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _tgts(province_id: int = 1) -> List[Dict[str, Any]]:
    return [
        {"province_id": province_id, "defender_power": 45.0, "supply": 0.6},
        {"province_id": province_id + 1, "defender_power": 55.0, "supply": 0.5},
    ]


def _sig(province_id: int = 1) -> Dict[str, Any]:
    return {"action_class": "sabotage", "influence": 0.55, "province_id": province_id, "threat": 0.55}


# A) Reinforced assault / follow-on


def follow_on_assault_ops_day(province_id: int = 1) -> Dict[str, Any]:
    fo = assault_follow_on_loop(_tgts(province_id), 100.0, 0.85)
    score = _norm(float(fo.get("overall", fo.get("score", fo.get("win", 0.55)))))
    q = [
        _q("apply_assault", province_id, score, "follow on assault primary"),
        _q("apply_supply", province_id, 0.5, "follow on assault supply"),
    ]
    return _day(
        "follow_on_assault_ops_day",
        "Follow on assault ops day",
        "Follow-on assault · %s · score %.2f" % (fo.get("summary", "follow-on"), score),
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["combat", "follow_on", "assault"],
        {"follow_on": fo, "win_chance": score},
    )


def reinforced_combat_ops_day(province_id: int = 1) -> Dict[str, Any]:
    reinf = reinforced_assault_loop(_tgts(province_id), 100.0, 0.85, month=6, is_choke=True)
    score = _norm(float(reinf.get("score", 0.55)))
    q = [
        _q("apply_assault", province_id, score, "reinforced combat primary"),
        _q("apply_supply", province_id, 0.55, "reinforced combat supply"),
        _q("apply_station", province_id, 0.45, "reinforced combat station"),
    ]
    return _day(
        "reinforced_combat_ops_day",
        "Reinforced combat ops day",
        "Reinforced combat · %s · score %.2f" % (reinf.get("summary", "reinf"), score),
        score,
        q,
        "#ef8f6e",
        "🛡",
        ["combat", "reinforced", "assault"],
        {"reinforced": reinf, "win_chance": score},
    )


def war_path_urgency_ops_day(province_id: int = 1) -> Dict[str, Any]:
    war = war_path_urgency(
        focus_id="military_buildup",
        focus_base=70.0,
        trail=[{"class": "sabotage", "influence": 0.6}],
    )
    score = _norm(float(war.get("urgency", war.get("score", 0.5))))
    q = [
        _q("apply_focus", province_id, score, "war path urgency focus"),
        _q("apply_production", province_id, 0.55, "war path urgency production"),
        _q("apply_assault", province_id, 0.5, "war path urgency assault"),
    ]
    return _day(
        "war_path_urgency_ops_day",
        "War path urgency ops day",
        "War path urgency · %s · score %.2f" % (war.get("summary", "urgency"), score),
        score,
        q,
        "#ef8f6e",
        "◆",
        ["combat", "war_path", "urgency"],
        {"war_path": war},
    )


def assault_follow_ops_day(province_id: int = 1) -> Dict[str, Any]:
    fo = assault_follow_on_loop(_tgts(province_id))
    ready = assault_readiness_compose(_tgts(province_id), 100.0)
    score = _norm(
        0.55 * float(fo.get("overall", fo.get("score", 0.5)))
        + 0.45 * (0.6 if not bool(ready.get("empty", False)) else 0.4)
    )
    q = [
        _q("apply_assault", province_id, score, "assault follow primary"),
        _q("apply_supply", province_id, 0.5, "assault follow supply"),
    ]
    return _day(
        "assault_follow_ops_day",
        "Assault follow ops day",
        "Assault follow · follow-on · ready · score %.2f" % score,
        score,
        q,
        "#ef8f6e",
        "⚔",
        ["combat", "assault", "follow_on"],
        {"follow_on": fo, "readiness": ready},
    )


def reinforce_step_ops_day(province_id: int = 1) -> Dict[str, Any]:
    reinf = reinforced_assault_loop(_tgts(province_id), is_choke=False)
    est = estimate_multi_phase_combat(100.0, 80.0, attacker_supply=0.85, weather_mult=0.9)
    win = float(est.get("overall_attacker_win_chance", 0.5))
    score = _norm(0.5 * float(reinf.get("score", 0.5)) + 0.5 * win)
    q = [
        _q("apply_assault", province_id, score, "reinforce step primary"),
        _q("apply_supply", province_id, 0.55, "reinforce step supply"),
        _q("apply_production", province_id, 0.45, "reinforce step production"),
    ]
    return _day(
        "reinforce_step_ops_day",
        "Reinforce step ops day",
        "Reinforce step · reinf · multi-phase · score %.2f" % score,
        score,
        q,
        "#ef8f6e",
        "◎",
        ["combat", "reinforce", "step"],
        {"reinforced": reinf, "estimate": est, "win_chance": win},
    )


def combat_urgency_ops_day(province_id: int = 1) -> Dict[str, Any]:
    war = war_path_urgency(
        focus_id="military_buildup",
        focus_base=70.0,
        trail=[{"class": "sabotage", "influence": 0.55}],
    )
    fo = assault_follow_on_loop(_tgts(province_id))
    score = _norm(
        0.5 * float(war.get("urgency", 0.5))
        + 0.5 * float(fo.get("overall", fo.get("score", 0.5)))
    )
    q = [
        _q("apply_assault", province_id, score, "combat urgency assault"),
        _q("apply_focus", province_id, 0.55, "combat urgency focus"),
        _q("apply_supply", province_id, 0.5, "combat urgency supply"),
    ]
    return _day(
        "combat_urgency_ops_day",
        "Combat urgency ops day",
        "Combat urgency · war-path · follow-on · score %.2f" % score,
        score,
        q,
        "#ef8f6e",
        "⚠",
        ["combat", "urgency", "war_path"],
        {"war_path": war, "follow_on": fo},
    )


def follow_reinforce_close_day(province_id: int = 1) -> Dict[str, Any]:
    fo = assault_follow_on_loop(_tgts(province_id))
    reinf = reinforced_assault_loop(_tgts(province_id), is_choke=True)
    war = war_path_urgency(
        focus_id="military_buildup",
        focus_base=65.0,
        trail=[{"class": "sabotage", "influence": 0.55}],
    )
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.3 * float(fo.get("overall", fo.get("score", 0.5)))
        + 0.3 * float(reinf.get("score", 0.5))
        + 0.2 * float(war.get("urgency", 0.5))
        + 0.2 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_assault", province_id, score, "follow reinforce close assault"),
        _q("apply_supply", province_id, 0.55, "follow reinforce close supply"),
        _q("apply_station", province_id, 0.45, "follow reinforce close station"),
    ]
    return _day(
        "follow_reinforce_close_day",
        "Follow reinforce close day",
        "Follow reinforce close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#ef8f6e",
        "∞",
        ["combat", "follow_on", "close"],
        {"follow_on": fo, "reinforced": reinf, "war_path": war, "gate": gate, "ok": ok},
    )


# B) Choke / sea-zone


def choke_sea_wx_ops_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = choke_sea_weather_package()
    score = _norm(float(pkg.get("combined_score", pkg.get("score", 0.6))))
    q = [
        _q("apply_station", province_id, score, "choke sea wx station"),
        _q("apply_supply", province_id, 0.55, "choke sea wx supply"),
        _q("apply_assault", province_id, 0.45, "choke sea wx assault"),
    ]
    return _day(
        "choke_sea_wx_ops_day",
        "Choke sea wx ops day",
        "Choke×sea×wx · %s · score %.2f" % (pkg.get("summary", "choke"), score),
        score,
        q,
        "#5ec8ff",
        "🌊",
        ["choke", "sea", "weather"],
        {"package": pkg},
    )


def sea_zone_mod_ops_day(province_id: int = 1) -> Dict[str, Any]:
    control = compute_sea_zone_control(
        "North Sea",
        [province_id, province_id + 1, province_id + 2],
        {province_id: "GER", province_id + 1: "GER", province_id + 2: "ENG"},
    )
    mods = sea_zone_strategic_modifiers(control)
    score = _norm(float(mods.get("trade_mult", mods.get("score", 0.55)) if isinstance(mods.get("trade_mult", None), (int, float)) else float(mods.get("score", 0.6) or 0.6)))
    if score < 0.2:
        score = 0.6
    q = [
        _q("apply_station", province_id, score, "sea zone mod station"),
        _q("apply_supply", province_id, 0.55, "sea zone mod supply"),
    ]
    return _day(
        "sea_zone_mod_ops_day",
        "Sea zone mod ops day",
        "Sea zone mods · control · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["sea_zone", "control", "mods"],
        {"control": control, "mods": mods},
    )


def basing_choke_ops_day(province_id: int = 1) -> Dict[str, Any]:
    basing = basing_fleet_fuel_logistics()
    syn = choke_basing_synergy_score(True, "port", 2)
    score = _norm(
        0.5 * float(basing.get("logistics_score", 0.55))
        + 0.5 * float(syn.get("score", syn.get("synergy", 0.6)) if isinstance(syn, dict) else 0.6)
    )
    q = [
        _q("apply_station", province_id, score, "basing choke station"),
        _q("apply_supply", province_id, 0.55, "basing choke supply"),
    ]
    return _day(
        "basing_choke_ops_day",
        "Basing choke ops day",
        "Basing×choke · fuel · synergy · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⛽",
        ["basing", "choke", "ops"],
        {"basing": basing, "synergy": syn},
    )


def choke_control_ops_day(province_id: int = 1) -> Dict[str, Any]:
    choke = choke_weather_synergy(
        is_choke=True,
        controller_friendly=True,
        weather={"visibility": 0.7, "precip_intensity": 0.3},
    )
    pkg = choke_sea_weather_package()
    score = _norm(
        max(
            float(choke.get("score", 0.6)) if not bool(choke.get("empty", False)) else 0.55,
            float(pkg.get("combined_score", 0.55)),
        )
    )
    q = [
        _q("apply_station", province_id, score, "choke control station"),
        _q("apply_assault", province_id, 0.55, "choke control assault"),
        _q("apply_supply", province_id, 0.5, "choke control supply"),
    ]
    return _day(
        "choke_control_ops_day",
        "Choke control ops day",
        "Choke control · wx · sea · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🗺",
        ["choke", "control", "ops"],
        {"choke": choke, "package": pkg},
    )


def sea_zone_control_ops_day(province_id: int = 1) -> Dict[str, Any]:
    control = compute_sea_zone_control(
        "Baltic",
        [province_id, province_id + 1],
        {province_id: "GER", province_id + 1: "SOV"},
        contested_ratio=0.3,
    )
    mods = sea_zone_strategic_modifiers(control)
    score = 0.62 if not bool(control.get("empty", False)) else 0.45
    if mods.get("contested"):
        score = 0.58
    q = [
        _q("apply_station", province_id, score, "sea zone control station"),
        _q("apply_supply", province_id, 0.55, "sea zone control supply"),
        _q("apply_assault", province_id, 0.45, "sea zone control assault"),
    ]
    return _day(
        "sea_zone_control_ops_day",
        "Sea zone control ops day",
        "Sea zone control · %s · score %.2f" % (control.get("summary", "zone"), score),
        score,
        q,
        "#5ec8ff",
        "⚓",
        ["sea_zone", "control", "ops"],
        {"control": control, "mods": mods},
    )


def choke_basing_joint_day(province_id: int = 1) -> Dict[str, Any]:
    basing = basing_fleet_fuel_logistics()
    pkg = choke_sea_weather_package()
    syn = choke_basing_synergy_score(True, "major_base", 3)
    score = _norm(
        0.35 * float(basing.get("logistics_score", 0.5))
        + 0.35 * float(pkg.get("combined_score", 0.5))
        + 0.3 * float(syn.get("score", 0.6) if isinstance(syn, dict) else 0.6)
    )
    q = [
        _q("apply_station", province_id, score, "choke basing joint station"),
        _q("apply_supply", province_id, 0.55, "choke basing joint supply"),
        _q("apply_assault", province_id, 0.45, "choke basing joint assault"),
    ]
    return _day(
        "choke_basing_joint_day",
        "Choke basing joint day",
        "Choke basing joint · fuel · sea · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◈",
        ["choke", "basing", "joint"],
        {"basing": basing, "package": pkg, "synergy": syn},
    )


def choke_sea_close_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = choke_sea_weather_package()
    control = compute_sea_zone_control(
        "Channel", [province_id], {province_id: "ENG"}
    )
    basing = basing_fleet_fuel_logistics()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.3 * float(pkg.get("combined_score", 0.5))
        + 0.3 * 0.6
        + 0.2 * float(basing.get("logistics_score", 0.5))
        + 0.2 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, score, "choke sea close station"),
        _q("apply_supply", province_id, 0.55, "choke sea close supply"),
        _q("apply_assault", province_id, 0.45, "choke sea close assault"),
    ]
    return _day(
        "choke_sea_close_day",
        "Choke sea close day",
        "Choke sea close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["choke", "sea", "close"],
        {"package": pkg, "control": control, "basing": basing, "gate": gate, "ok": ok},
    )


# C) Agent escalation / coverage


def agent_escalation_ops_day(province_id: int = 1) -> Dict[str, Any]:
    esc = plan_agent_escalation(_sig(province_id), network_strength=0.35, available_agents=4)
    score = _norm(float(esc.get("score", esc.get("level", 2)) if float(esc.get("score", 2) or 2) <= 1 else float(esc.get("level", 2)) / 3.0))
    if score < 0.2:
        score = 0.55
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent escalation primary"),
        _q("apply_counterplay", province_id, 0.55, "agent escalation counter"),
    ]
    return _day(
        "agent_escalation_ops_day",
        "Agent escalation ops day",
        "Agent escalation · %s · score %.2f" % (esc.get("summary", "escalation"), score),
        score,
        q,
        "#c084fc",
        "🕵",
        ["agent", "escalation", "ops"],
        {"escalation": esc},
    )


def coverage_ops_day(province_id: int = 1) -> Dict[str, Any]:
    cov = plan_agent_coverage(
        [
            {"province_id": province_id, "threat": 0.6, "action_class": "sabotage"},
            {"province_id": province_id + 1, "threat": 0.4, "action_class": "influence"},
        ],
        available_agents=5,
        network_strength=0.35,
    )
    score = _norm(float(cov.get("score", cov.get("coverage", 0.6)) or 0.6))
    if score < 0.2:
        score = 0.6
    q = [
        _q("apply_agent_dispatch", province_id, score, "coverage ops primary"),
        _q("apply_hh_commit", province_id, 0.5, "coverage ops hh"),
    ]
    return _day(
        "coverage_ops_day",
        "Coverage ops day",
        "Coverage ops · %s · score %.2f" % (cov.get("summary", "coverage"), score),
        score,
        q,
        "#c084fc",
        "◎",
        ["agent", "coverage", "ops"],
        {"coverage": cov},
    )


def counter_ops_board_ops_day(province_id: int = 1) -> Dict[str, Any]:
    board = counter_ops_board(_sig(province_id), network_strength=0.35, available_agents=4)
    order = counter_ops_execute_order(_sig(province_id))
    score = _norm(
        0.5 * (0.7 if not bool(board.get("empty", True)) else 0.3)
        + 0.5 * (0.65 if not bool(order.get("empty", True)) else 0.3)
    )
    q = [
        _q("apply_counterplay", province_id, score, "counter ops board primary"),
        _q("apply_agent_dispatch", province_id, 0.55, "counter ops board agents"),
    ]
    return _day(
        "counter_ops_board_ops_day",
        "Counter ops board ops day",
        "Counter-ops board · board · execute · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🛡",
        ["agent", "counter_ops", "board"],
        {"board": board, "order": order},
    )


def escalation_ladder_ops_day(province_id: int = 1) -> Dict[str, Any]:
    esc = plan_agent_escalation(_sig(province_id), available_agents=5)
    counter = apply_hh_counterplay(0.55, _sig(province_id))
    score = _norm(
        0.55
        + 0.1 * float(esc.get("level", 1) or 1) / 3.0
        + float(counter.get("reduction", 0.12) or 0.12) * 0.5
    )
    q = [
        _q("apply_agent_dispatch", province_id, score, "escalation ladder primary"),
        _q("apply_counterplay", province_id, 0.6, "escalation ladder counter"),
        _q("apply_hh_commit", province_id, 0.45, "escalation ladder hh"),
    ]
    return _day(
        "escalation_ladder_ops_day",
        "Escalation ladder ops day",
        "Escalation ladder · level · counter · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "▲",
        ["agent", "escalation", "ladder"],
        {"escalation": esc, "counter": counter},
    )


def agent_coverage_joint_day(province_id: int = 1) -> Dict[str, Any]:
    esc = plan_agent_escalation(_sig(province_id))
    cov = plan_agent_coverage(
        [{"province_id": province_id, "threat": 0.55, "action_class": "sabotage"}],
        available_agents=4,
    )
    board = counter_ops_board(_sig(province_id))
    score = _norm(
        0.4 * (0.55 + 0.1 * float(esc.get("level", 1) or 1) / 3.0)
        + 0.3 * float(cov.get("score", 0.6) or 0.6)
        + 0.3 * (0.65 if not bool(board.get("empty", True)) else 0.35)
    )
    q = [
        _q("apply_agent_dispatch", province_id, score, "agent coverage joint agents"),
        _q("apply_counterplay", province_id, 0.55, "agent coverage joint counter"),
        _q("apply_hh_commit", province_id, 0.5, "agent coverage joint hh"),
    ]
    return _day(
        "agent_coverage_joint_day",
        "Agent coverage joint day",
        "Agent coverage joint · escal · cover · board · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "◈",
        ["agent", "coverage", "joint"],
        {"escalation": esc, "coverage": cov, "board": board},
    )


def assault_choke_agent_close_day(province_id: int = 1) -> Dict[str, Any]:
    fo = assault_follow_on_loop(_tgts(province_id))
    pkg = choke_sea_weather_package()
    esc = plan_agent_escalation(_sig(province_id))
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * float(fo.get("overall", fo.get("score", 0.5)))
        + 0.25 * float(pkg.get("combined_score", 0.5))
        + 0.25 * (0.55 + 0.1 * float(esc.get("level", 1) or 1) / 3.0)
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q(
            "apply_assault",
            province_id,
            float(fo.get("overall", fo.get("score", 0.55))),
            "close assault follow-on",
        ),
        _q("apply_station", province_id, float(pkg.get("combined_score", 0.55)), "close choke station"),
        _q("apply_agent_dispatch", province_id, 0.55, "close agent dispatch"),
        _q("apply_counterplay", province_id, 0.45, "close counterplay"),
    ]
    return _day(
        "assault_choke_agent_close_day",
        "Assault choke agent close day",
        "Assault choke agent close · combat · choke · agent · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["assault", "choke", "agent", "close"],
        {
            "follow_on": fo,
            "package": pkg,
            "escalation": esc,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
        },
    )


ASSAULT_CHOKE_AGENT_DAY_IDS: List[str] = [
    "follow_on_assault_ops_day",
    "reinforced_combat_ops_day",
    "war_path_urgency_ops_day",
    "assault_follow_ops_day",
    "reinforce_step_ops_day",
    "combat_urgency_ops_day",
    "follow_reinforce_close_day",
    "choke_sea_wx_ops_day",
    "sea_zone_mod_ops_day",
    "basing_choke_ops_day",
    "choke_control_ops_day",
    "sea_zone_control_ops_day",
    "choke_basing_joint_day",
    "choke_sea_close_day",
    "agent_escalation_ops_day",
    "coverage_ops_day",
    "counter_ops_board_ops_day",
    "escalation_ladder_ops_day",
    "agent_coverage_joint_day",
    "assault_choke_agent_close_day",
]


DAY_FUNCS = [
    follow_on_assault_ops_day,
    reinforced_combat_ops_day,
    war_path_urgency_ops_day,
    assault_follow_ops_day,
    reinforce_step_ops_day,
    combat_urgency_ops_day,
    follow_reinforce_close_day,
    choke_sea_wx_ops_day,
    sea_zone_mod_ops_day,
    basing_choke_ops_day,
    choke_control_ops_day,
    sea_zone_control_ops_day,
    choke_basing_joint_day,
    choke_sea_close_day,
    agent_escalation_ops_day,
    coverage_ops_day,
    counter_ops_board_ops_day,
    escalation_ladder_ops_day,
    agent_coverage_joint_day,
    assault_choke_agent_close_day,
]


def assault_choke_agent_integrity() -> Dict[str, Any]:
    fo = assault_follow_on_loop(_tgts(1))
    pkg = choke_sea_weather_package()
    esc = plan_agent_escalation(_sig(1))
    gate = execution_integrity_gate()
    ok = (
        not bool(fo.get("empty", False))
        and float(pkg.get("combined_score", 0)) > 0.0
        and bool(esc)
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "follow_score": float(fo.get("overall", fo.get("score", 0))),
        "choke_score": float(pkg.get("combined_score", 0)),
        "escalation": esc.get("summary", ""),
        "gate": gate,
        "summary": "Assault-choke-agent integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next210_assault_choke_agent_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = assault_choke_agent_integrity()
    label = "Close next210 assault-choke-agent · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next210 assault-choke-agent[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
