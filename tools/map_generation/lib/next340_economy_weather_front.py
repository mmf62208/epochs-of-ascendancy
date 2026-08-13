"""Next-340 economy / weather / front depth pillars (20).

A) War economy advanced (1–6)
B) Weather theater advanced (7–12)
C) Front continuity joints + close (13–20)
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from war_economy_mobilization_product import (  # type: ignore
    build_war_economy_mobilization_product, execute_war_economy_step, war_economy_mobilization_integrity,
)
from weather_theater_ops_product import (  # type: ignore
    build_weather_theater_ops_product, execute_weather_theater_step, weather_theater_ops_integrity,
)
from front_continuity_campaign_product import (  # type: ignore
    build_front_continuity_campaign_product, execute_front_continuity_step, front_continuity_campaign_integrity,
)
from logistics_supply_theater_product import build_logistics_supply_theater_product  # type: ignore
from tech_research_campaign_product import build_tech_research_campaign_product  # type: ignore
from theater_command_product import build_theater_command_product  # type: ignore

def _norm(v: float) -> float:
    try: x = float(v)
    except (TypeError, ValueError): return 0.5
    if x > 2.0: x = x / 100.0
    return max(0.0, min(1.0, x))

def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))

def _q(aid: str, province_id: int, score: float, label: str) -> Dict[str, Any]:
    return {"action_id": aid, "province_id": max(1, int(province_id)), "score": score, "enabled": True, "label": label}

def _day(aid: str, title: str, summary: str, score: float, apply_queue: List, color: str, icon: str, tags: List[str], extra: Dict = None) -> Dict[str, Any]:
    sc = _floor(score)
    out = {
        "id": aid, "title": title, "score": sc, "apply_queue": apply_queue,
        "actions": [{"action_id": aid, "label": "Run %s" % title.lower(), "enabled": True}],
        "summary": summary, "plain": summary,
        "bbcode": "[color=%s]%s %s[/color] [color=#8899aa]%s[/color]" % (color, icon, title, summary),
        "empty": False, "integration": [aid, "next340", "economy_weather_front"] + tags,
    }
    if extra: out.update(extra)
    return out

def war_economy_board_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_war_economy_mobilization_product(province_id=province_id)
    e = execute_war_economy_step("board", province_id)
    score = _floor(0.55 * _norm(float(p.get("board_score", 0.5))) + 0.45 * _norm(float(e.get("score", 0.5))))
    return _day("war_economy_board_advanced_day", "War economy board advanced day",
        "War economy board advanced day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "econ board primary"), _q("apply_station", province_id, 0.5, "econ board station")],
        "#ffc857", "⚙", ["economy"], {"economy_score": score})

def war_economy_allocate_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_war_economy_step("allocate", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("war_economy_allocate_advanced_day", "War economy allocate advanced day",
        "War economy allocate advanced day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "econ allocate primary"), _q("apply_station", province_id, 0.5, "econ allocate station")],
        "#ffc857", "⚙", ["economy"], {"economy_score": score})

def war_economy_sustain_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_war_economy_step("sustain", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("war_economy_sustain_advanced_day", "War economy sustain advanced day",
        "War economy sustain advanced day · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "econ sustain primary"), _q("apply_station", province_id, 0.5, "econ sustain station")],
        "#ffc857", "⚙", ["economy"], {"economy_score": score})

def war_economy_logistics_joint_day(province_id: int = 1) -> Dict[str, Any]:
    econ = build_war_economy_mobilization_product(province_id=province_id)
    log = build_logistics_supply_theater_product(province_id=province_id)
    score = _floor(0.55 * _norm(float(econ.get("score", 0.5))) + 0.45 * _norm(float(log.get("score", 0.5))))
    return _day("war_economy_logistics_joint_day", "War economy logistics joint day",
        "War economy logistics joint day · score %.2f" % score, score,
        [_q("apply_supply", province_id, score, "econ log joint primary"), _q("apply_production", province_id, 0.5, "econ log joint prod")],
        "#ffc857", "⚙", ["economy", "logistics"], {"economy_score": score})

def war_economy_tech_joint_day(province_id: int = 1) -> Dict[str, Any]:
    econ = build_war_economy_mobilization_product(province_id=province_id)
    tech = build_tech_research_campaign_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(econ.get("score", 0.5))) + 0.5 * _norm(float(tech.get("score", 0.5))))
    return _day("war_economy_tech_joint_day", "War economy tech joint day",
        "War economy tech joint day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "econ tech joint primary"), _q("apply_focus", province_id, 0.5, "econ tech joint focus")],
        "#ffc857", "⚙", ["economy", "tech"], {"economy_score": score})

def war_economy_mobilization_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = war_economy_board_advanced_day(province_id)
    d1 = war_economy_allocate_advanced_day(province_id)
    d2 = war_economy_sustain_advanced_day(province_id)
    avg = (float(d0.get("score",0))+float(d1.get("score",0))+float(d2.get("score",0)))/3.0
    gate = war_economy_mobilization_integrity()
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in (d0,d1,d2))
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day("war_economy_mobilization_close_day", "War economy mobilization close day",
        "War economy mobilization close · score %.2f · %s" % (score, "PASS" if ok else "FAIL"), score,
        [_q("apply_production", province_id, score, "econ close primary"), _q("apply_station", province_id, 0.5, "econ close station")],
        "#ffc857", "✓", ["economy", "close"], {"economy_score": score, "ok": ok, "gate": gate})

def weather_pressure_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_weather_theater_ops_product(province_id=province_id)
    e = execute_weather_theater_step("pressure", province_id)
    score = _floor(0.55 * _norm(float(p.get("pressure_score", 0.5))) + 0.45 * _norm(float(e.get("score", 0.5))))
    return _day("weather_pressure_advanced_day", "Weather pressure advanced day",
        "Weather pressure advanced day · score %.2f" % score, score,
        [_q("apply_station", province_id, score, "wx pressure primary"), _q("apply_supply", province_id, 0.5, "wx pressure supply")],
        "#7ec8ff", "🌤", ["weather"], {"weather_score": score})

def weather_gate_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_weather_theater_step("gate", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("weather_gate_advanced_day", "Weather gate advanced day",
        "Weather gate advanced day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "wx gate primary"), _q("apply_station", province_id, 0.5, "wx gate station")],
        "#7ec8ff", "🌤", ["weather"], {"weather_score": score})

def weather_crisis_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_weather_theater_step("crisis", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("weather_crisis_advanced_day", "Weather crisis advanced day",
        "Weather crisis advanced day · score %.2f" % score, score,
        [_q("apply_supply", province_id, score, "wx crisis primary"), _q("apply_station", province_id, 0.5, "wx crisis station")],
        "#7ec8ff", "🌤", ["weather"], {"weather_score": score})

def weather_front_joint_day(province_id: int = 1) -> Dict[str, Any]:
    wx = build_weather_theater_ops_product(province_id=province_id)
    front = build_front_continuity_campaign_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(wx.get("score", 0.5))) + 0.5 * _norm(float(front.get("score", 0.5))))
    return _day("weather_front_joint_day", "Weather front joint day",
        "Weather front joint day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "wx front joint primary"), _q("apply_station", province_id, 0.5, "wx front joint station")],
        "#7ec8ff", "🌤", ["weather", "front"], {"weather_score": score})

def weather_economy_joint_day(province_id: int = 1) -> Dict[str, Any]:
    wx = build_weather_theater_ops_product(province_id=province_id)
    econ = build_war_economy_mobilization_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(wx.get("score", 0.5))) + 0.5 * _norm(float(econ.get("score", 0.5))))
    return _day("weather_economy_joint_day", "Weather economy joint day",
        "Weather economy joint day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "wx econ joint primary"), _q("apply_station", province_id, 0.5, "wx econ joint station")],
        "#7ec8ff", "🌤", ["weather", "economy"], {"weather_score": score})

def weather_theater_ops_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = weather_pressure_advanced_day(province_id)
    d1 = weather_gate_advanced_day(province_id)
    d2 = weather_crisis_advanced_day(province_id)
    avg = (float(d0.get("score",0))+float(d1.get("score",0))+float(d2.get("score",0)))/3.0
    gate = weather_theater_ops_integrity()
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in (d0,d1,d2))
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day("weather_theater_ops_close_day", "Weather theater ops close day",
        "Weather theater ops close · score %.2f · %s" % (score, "PASS" if ok else "FAIL"), score,
        [_q("apply_station", province_id, score, "wx close primary"), _q("apply_supply", province_id, 0.5, "wx close supply")],
        "#7ec8ff", "✓", ["weather", "close"], {"weather_score": score, "ok": ok, "gate": gate})

def front_combat_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_front_continuity_campaign_product(province_id=province_id)
    e = execute_front_continuity_step("combat", province_id)
    score = _floor(0.55 * _norm(float(p.get("combat_score", 0.5))) + 0.45 * _norm(float(e.get("score", 0.5))))
    return _day("front_combat_advanced_day", "Front combat advanced day",
        "Front combat advanced day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "front combat primary"), _q("apply_station", province_id, 0.5, "front combat station")],
        "#ff9a6e", "⚔", ["front"], {"front_score": score})

def front_assault_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_front_continuity_step("assault", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("front_assault_advanced_day", "Front assault advanced day",
        "Front assault advanced day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "front assault primary"), _q("apply_station", province_id, 0.5, "front assault station")],
        "#ff9a6e", "⚔", ["front"], {"front_score": score})

def front_sustain_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_front_continuity_step("sustain", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("front_sustain_advanced_day", "Front sustain advanced day",
        "Front sustain advanced day · score %.2f" % score, score,
        [_q("apply_supply", province_id, score, "front sustain primary"), _q("apply_station", province_id, 0.5, "front sustain station")],
        "#ff9a6e", "⚔", ["front"], {"front_score": score})

def front_weather_joint_day(province_id: int = 1) -> Dict[str, Any]:
    front = build_front_continuity_campaign_product(province_id=province_id)
    wx = build_weather_theater_ops_product(province_id=province_id)
    score = _floor(0.55 * _norm(float(front.get("score", 0.5))) + 0.45 * _norm(float(wx.get("score", 0.5))))
    return _day("front_weather_joint_day", "Front weather joint day",
        "Front weather joint day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "front wx joint primary"), _q("apply_station", province_id, 0.5, "front wx joint station")],
        "#ff9a6e", "⚔", ["front", "weather"], {"front_score": score})

def front_economy_joint_day(province_id: int = 1) -> Dict[str, Any]:
    front = build_front_continuity_campaign_product(province_id=province_id)
    econ = build_war_economy_mobilization_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(front.get("score", 0.5))) + 0.5 * _norm(float(econ.get("score", 0.5))))
    return _day("front_economy_joint_day", "Front economy joint day",
        "Front economy joint day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "front econ joint primary"), _q("apply_assault", province_id, 0.5, "front econ joint assault")],
        "#ff9a6e", "⚔", ["front", "economy"], {"front_score": score})

def front_logistics_joint_day(province_id: int = 1) -> Dict[str, Any]:
    front = build_front_continuity_campaign_product(province_id=province_id)
    log = build_logistics_supply_theater_product(province_id=province_id)
    score = _floor(0.55 * _norm(float(front.get("score", 0.5))) + 0.45 * _norm(float(log.get("score", 0.5))))
    return _day("front_logistics_joint_day", "Front logistics joint day",
        "Front logistics joint day · score %.2f" % score, score,
        [_q("apply_supply", province_id, score, "front log joint primary"), _q("apply_assault", province_id, 0.5, "front log joint assault")],
        "#ff9a6e", "⚔", ["front", "logistics"], {"front_score": score})

def front_theater_command_joint_day(province_id: int = 1) -> Dict[str, Any]:
    front = build_front_continuity_campaign_product(province_id=province_id)
    th = build_theater_command_product(province_id=province_id)
    score = _floor(0.55 * _norm(float(front.get("score", 0.5))) + 0.45 * _norm(float(th.get("score", 0.5))))
    return _day("front_theater_command_joint_day", "Front theater command joint day",
        "Front theater command joint day · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "front th joint primary"), _q("apply_assault", province_id, 0.5, "front th joint assault")],
        "#ff9a6e", "⚔", ["front", "theater"], {"front_score": score})

def front_continuity_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    pillars = [
        war_economy_mobilization_close_day(province_id),
        weather_theater_ops_close_day(province_id),
        front_combat_advanced_day(province_id),
        front_assault_advanced_day(province_id),
        front_sustain_advanced_day(province_id),
        front_weather_joint_day(province_id),
        front_theater_command_joint_day(province_id),
    ]
    gates = {
        "economy": war_economy_mobilization_integrity(),
        "weather": weather_theater_ops_integrity(),
        "front": front_continuity_campaign_integrity(),
        "exec": execution_integrity_gate(),
        "sole": sole_mult_integrity(),
    }
    gate_ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates.values())
    non_empty = sum(1 for p in pillars if not p.get("empty"))
    avg = sum(float(p.get("score", 0)) for p in pillars) / max(1, len(pillars))
    ok = gate_ok and non_empty >= 7
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("front_continuity_campaign_close_day", "Front continuity campaign close day",
        "Front continuity campaign close · pillars %d/7 · gates %s · score %.2f" % (non_empty, "PASS" if ok else "FAIL", score), score,
        [_q("apply_assault", province_id, score, "front close assault"), _q("apply_supply", province_id, 0.55, "front close supply"),
         _q("apply_production", province_id, 0.5, "front close prod"), _q("apply_focus", province_id, 0.45, "front close focus")],
        "#ff9a6e", "✓", ["front", "campaign", "close"], {"pillars": pillars, "gates": gates, "ok": ok, "front_score": score})

ECONOMY_WEATHER_FRONT_DAY_IDS = [
    "war_economy_board_advanced_day", "war_economy_allocate_advanced_day", "war_economy_sustain_advanced_day",
    "war_economy_logistics_joint_day", "war_economy_tech_joint_day", "war_economy_mobilization_close_day",
    "weather_pressure_advanced_day", "weather_gate_advanced_day", "weather_crisis_advanced_day",
    "weather_front_joint_day", "weather_economy_joint_day", "weather_theater_ops_close_day",
    "front_combat_advanced_day", "front_assault_advanced_day", "front_sustain_advanced_day",
    "front_weather_joint_day", "front_economy_joint_day", "front_logistics_joint_day",
    "front_theater_command_joint_day", "front_continuity_campaign_close_day",
]

DAY_FUNCS = [
    war_economy_board_advanced_day, war_economy_allocate_advanced_day, war_economy_sustain_advanced_day,
    war_economy_logistics_joint_day, war_economy_tech_joint_day, war_economy_mobilization_close_day,
    weather_pressure_advanced_day, weather_gate_advanced_day, weather_crisis_advanced_day,
    weather_front_joint_day, weather_economy_joint_day, weather_theater_ops_close_day,
    front_combat_advanced_day, front_assault_advanced_day, front_sustain_advanced_day,
    front_weather_joint_day, front_economy_joint_day, front_logistics_joint_day,
    front_theater_command_joint_day, front_continuity_campaign_close_day,
]

def economy_weather_front_integrity() -> Dict[str, Any]:
    gates = [
        war_economy_mobilization_integrity(),
        weather_theater_ops_integrity(),
        front_continuity_campaign_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        war_economy_board_advanced_day(),
        weather_pressure_advanced_day(),
        front_combat_advanced_day(),
        front_continuity_campaign_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Economy/weather/front depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_next340_economy_weather_front_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = economy_weather_front_integrity()
    ok = bool(gate.get("ok")) and non_empty >= 20
    label = "Close next340 economy/weather/front · packages %d/20 · queue %d · %s" % (
        non_empty, q_total, "PASS" if ok else "FAIL"
    )
    return {
        "packages": packages, "non_empty": non_empty, "queue_total": q_total, "gate": gate,
        "score": non_empty / 20.0, "summary": label, "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next340 economy/weather/front[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False, "ok": ok,
    }
