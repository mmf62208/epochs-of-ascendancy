"""Next-330 world-class depth pillars (20).

A) Logistics advanced (1–6)
B) Intelligence advanced (7–12)
C) World-class command joints + close (13–20)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from logistics_supply_theater_product import (  # type: ignore
    build_logistics_supply_theater_product,
    execute_logistics_supply_step,
    logistics_supply_theater_integrity,
)
from intelligence_network_product import (  # type: ignore
    build_intelligence_network_product,
    execute_intel_network_step,
    intelligence_network_product_integrity,
)
from world_class_campaign_command_product import (  # type: ignore
    build_world_class_campaign_command_product,
    execute_world_class_step,
    world_class_campaign_command_integrity,
)
from theater_command_product import build_theater_command_product  # type: ignore
from play_session_campaign_product import build_play_session_campaign_product  # type: ignore
from naval_multi_phase_campaign_product import build_naval_multi_phase_campaign_product  # type: ignore
from air_ops_campaign_product import build_air_ops_campaign_product  # type: ignore
from diplomacy_peace_campaign_product import build_diplomacy_peace_campaign_product  # type: ignore
from tech_research_campaign_product import build_tech_research_campaign_product  # type: ignore
from strategic_ai_daily_campaign_product import build_strategic_ai_daily_campaign_product  # type: ignore
from focus_war_path_product import build_focus_war_path_product  # type: ignore
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
    return {"action_id": aid, "province_id": max(1, int(pid)), "score": float(score), "enabled": True, "label": label}


def _day(action_id, title, summary, score, apply_queue, color="#6eb5ff", marker="★", integration=None, extra=None):
    out = {
        "score": float(score),
        "apply_queue": apply_queue,
        "actions": [{"action_id": action_id, "label": "Run %s" % title, "enabled": True}],
        "summary": summary,
        "plain": summary,
        "bbcode": "[color=%s]%s %s[/color] [color=#8899aa]%s[/color]" % (color, marker, title, summary),
        "empty": False,
        "integration": list(integration or ["next330", "world_class_depth"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


# Logistics 1-6
def logistics_route_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_logistics_supply_theater_product(province_id=province_id)
    e = execute_logistics_supply_step("route", province_id)
    score = _floor(0.55 * float(p.get("route_score", 0.5)) + 0.45 * float(e.get("score", 0.5)))
    return _day("logistics_route_advanced_day", "Logistics route advanced day",
        "Logistics route advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_supply", province_id, score, "route")],
        "#5ec8ff", "📦", ["logistics", "route"], {"product": p, "logistics_score": score})


def logistics_sustain_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_logistics_supply_step("sustain", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("logistics_sustain_advanced_day", "Logistics sustain advanced day",
        "Logistics sustain advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_station", province_id, score, "sustain")],
        "#5ec8ff", "⛽", ["logistics", "sustain"], {"step": e, "logistics_score": score})


def logistics_readiness_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_logistics_supply_step("readiness", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("logistics_readiness_advanced_day", "Logistics readiness advanced day",
        "Logistics readiness advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_production", province_id, score, "readiness")],
        "#5ec8ff", "🛡", ["logistics", "readiness"], {"step": e, "logistics_score": score})


def logistics_naval_joint_day(province_id: int = 1) -> Dict[str, Any]:
    log = build_logistics_supply_theater_product(province_id=province_id)
    naval = build_naval_multi_phase_campaign_product(province_id=province_id)
    score = _floor(0.55 * float(log.get("score", 0.5)) + 0.45 * float(naval.get("score", 0.5)))
    return _day("logistics_naval_joint_day", "Logistics naval joint day",
        "Logistics naval joint · score %.2f" % score, score,
        [_q("apply_supply", province_id, score, "log naval supply"), _q("apply_station", province_id, 0.55, "log naval station")],
        "#0ea5e9", "⚓", ["logistics", "naval", "joint"], {"logistics": log, "naval": naval, "logistics_score": score})


def logistics_tech_industry_joint_day(province_id: int = 1) -> Dict[str, Any]:
    log = build_logistics_supply_theater_product(province_id=province_id)
    tech = build_tech_research_campaign_product(province_id=province_id)
    score = _floor(0.5 * float(log.get("score", 0.5)) + 0.5 * float(tech.get("score", 0.5)))
    return _day("logistics_tech_industry_joint_day", "Logistics tech industry joint day",
        "Logistics tech industry joint · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "log tech prod"), _q("apply_supply", province_id, 0.5, "log tech supply")],
        "#f0b429", "🏭", ["logistics", "tech", "joint"], {"logistics": log, "tech": tech, "logistics_score": score})


def logistics_supply_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [logistics_route_advanced_day(province_id), logistics_sustain_advanced_day(province_id),
            logistics_readiness_advanced_day(province_id), logistics_naval_joint_day(province_id),
            logistics_tech_industry_joint_day(province_id)]
    gate = logistics_supply_theater_integrity()
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day("logistics_supply_close_day", "Logistics supply close day",
        "Logistics supply close · packages %d · %s · score %.2f" % (len(days), "PASS" if ok else "FAIL", score), score,
        [_q("apply_supply", province_id, score, "log close"), _q("apply_station", province_id, 0.5, "log close station")],
        "#5ec8ff", "✓", ["logistics", "close"], {"packages": days, "gate": gate, "ok": ok, "logistics_score": score})


# Intel 7-12
def intel_coverage_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_intelligence_network_product(province_id=province_id)
    e = execute_intel_network_step("coverage", province_id)
    score = _floor(0.55 * float(p.get("coverage_score", 0.5)) + 0.45 * float(e.get("score", 0.5)))
    return _day("intel_coverage_advanced_day", "Intel coverage advanced day",
        "Intel coverage advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_agent_dispatch", province_id, score, "coverage")],
        "#c084fc", "🕵", ["intel", "coverage"], {"product": p, "intel_score": score})


def intel_counterintel_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_intel_network_step("counterintel", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("intel_counterintel_advanced_day", "Intel counterintel advanced day",
        "Intel counterintel advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_agent_dispatch", province_id, score, "counterintel")],
        "#c084fc", "🕵", ["intel", "counterintel"], {"step": e, "intel_score": score})


def intel_counterplay_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_intel_network_step("counterplay", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("intel_counterplay_advanced_day", "Intel counterplay advanced day",
        "Intel counterplay advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_hh_commit", province_id, score, "counterplay")],
        "#c084fc", "🕵", ["intel", "counterplay"], {"step": e, "intel_score": score})


def intel_diplomacy_joint_day(province_id: int = 1) -> Dict[str, Any]:
    intel = build_intelligence_network_product(province_id=province_id)
    diplo = build_diplomacy_peace_campaign_product(province_id=province_id)
    score = _floor(0.55 * float(intel.get("score", 0.5)) + 0.45 * float(diplo.get("score", 0.5)))
    return _day("intel_diplomacy_joint_day", "Intel diplomacy joint day",
        "Intel diplomacy joint · score %.2f" % score, score,
        [_q("apply_agent_dispatch", province_id, score, "intel diplo agent"), _q("apply_hh_commit", province_id, 0.5, "intel diplo HH")],
        "#a78bfa", "🕊", ["intel", "diplomacy", "joint"], {"intel": intel, "diplo": diplo, "intel_score": score})


def intel_session_joint_day(province_id: int = 1) -> Dict[str, Any]:
    intel = build_intelligence_network_product(province_id=province_id)
    sess = build_play_session_campaign_product(province_id=province_id, player_tag="GER")
    score = _floor(0.5 * float(intel.get("score", 0.5)) + 0.5 * float(sess.get("score", 0.5)))
    return _day("intel_session_joint_day", "Intel session joint day",
        "Intel session joint · score %.2f" % score, score,
        [_q("apply_agent_dispatch", province_id, score, "intel session agent"), _q("apply_focus", province_id, 0.5, "intel session focus")],
        "#6eb5ff", "▶", ["intel", "session", "joint"], {"intel": intel, "session": sess, "intel_score": score})


def intelligence_network_close_day(province_id: int = 1) -> Dict[str, Any]:
    days = [intel_coverage_advanced_day(province_id), intel_counterintel_advanced_day(province_id),
            intel_counterplay_advanced_day(province_id), intel_diplomacy_joint_day(province_id),
            intel_session_joint_day(province_id)]
    gate = intelligence_network_product_integrity()
    avg = sum(float(d.get("score", 0)) for d in days) / max(1, len(days))
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in days)
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day("intelligence_network_close_day", "Intelligence network close day",
        "Intelligence network close · packages %d · %s · score %.2f" % (len(days), "PASS" if ok else "FAIL", score), score,
        [_q("apply_agent_dispatch", province_id, score, "intel close"), _q("apply_hh_commit", province_id, 0.5, "intel close HH")],
        "#5ec8ff", "✓", ["intel", "close"], {"packages": days, "gate": gate, "ok": ok, "intel_score": score})


# World-class 13-20
def world_class_scan_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_world_class_campaign_command_product(province_id=province_id)
    e = execute_world_class_step("scan", province_id)
    score = _floor(0.55 * float(p.get("score", 0.5)) + 0.45 * float(e.get("score", 0.5)))
    return _day("world_class_scan_advanced_day", "World class scan advanced day",
        "World class scan advanced · domains %d · score %.2f" % (int(p.get("domain_count", 0)), score), score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_focus", province_id, score, "wc scan")],
        "#fbbf24", "★", ["world_class", "scan"], {"product": p, "world_class_score": score})


def world_class_rank_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_world_class_step("rank", province_id)
    p = build_world_class_campaign_command_product(province_id=province_id)
    score = _floor(0.5 * float(e.get("score", 0.5)) + 0.5 * float(p.get("top_score", 0.5)))
    return _day("world_class_rank_advanced_day", "World class rank advanced day",
        "World class rank advanced · top %s · score %.2f" % (p.get("top_domain"), score), score,
        list(e.get("apply_queue") or [])[:2] or [_q("apply_station", province_id, score, "wc rank")],
        "#fbbf24", "★", ["world_class", "rank"], {"product": p, "world_class_score": score})


def world_class_execute_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_world_class_step("execute", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("world_class_execute_advanced_day", "World class execute advanced day",
        "World class execute advanced · score %.2f" % score, score,
        list(e.get("apply_queue") or [])[:3] or [_q("apply_assault", province_id, score, "wc execute")],
        "#fbbf24", "★", ["world_class", "execute"], {"step": e, "world_class_score": score})


def world_class_logistics_intel_joint_day(province_id: int = 1) -> Dict[str, Any]:
    log = build_logistics_supply_theater_product(province_id=province_id)
    intel = build_intelligence_network_product(province_id=province_id)
    score = _floor(0.5 * float(log.get("score", 0.5)) + 0.5 * float(intel.get("score", 0.5)))
    return _day("world_class_logistics_intel_joint_day", "World class logistics intel joint day",
        "World class logistics intel joint · score %.2f" % score, score,
        [_q("apply_supply", province_id, score, "wc log"), _q("apply_agent_dispatch", province_id, 0.55, "wc intel")],
        "#fbbf24", "★", ["world_class", "logistics", "intel"], {"logistics": log, "intel": intel, "world_class_score": score})


def world_class_air_naval_joint_day(province_id: int = 1) -> Dict[str, Any]:
    air = build_air_ops_campaign_product(province_id=province_id)
    naval = build_naval_multi_phase_campaign_product(province_id=province_id)
    score = _floor(0.5 * float(air.get("score", 0.5)) + 0.5 * float(naval.get("score", 0.5)))
    return _day("world_class_air_naval_joint_day", "World class air naval joint day",
        "World class air naval joint · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "wc air"), _q("apply_station", province_id, 0.55, "wc naval")],
        "#0ea5e9", "✈", ["world_class", "air", "naval"], {"air": air, "naval": naval, "world_class_score": score})


def world_class_session_ai_joint_day(province_id: int = 1) -> Dict[str, Any]:
    sess = build_play_session_campaign_product(province_id=province_id, player_tag="GER")
    ai = build_strategic_ai_daily_campaign_product(province_id=province_id, player_tag="GER")
    score = _floor(0.5 * float(sess.get("score", 0.5)) + 0.5 * float(ai.get("score", 0.5)))
    return _day("world_class_session_ai_joint_day", "World class session AI joint day",
        "World class session AI joint · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "wc session"), _q("apply_station", province_id, 0.5, "wc AI")],
        "#6eb5ff", "♟", ["world_class", "session", "ai"], {"session": sess, "ai": ai, "world_class_score": score})


def world_class_theater_command_joint_day(province_id: int = 1) -> Dict[str, Any]:
    wc = build_world_class_campaign_command_product(province_id=province_id)
    th = build_theater_command_product(province_id=province_id)
    focus = build_focus_war_path_product(province_id=province_id)
    score = _floor(0.45 * float(wc.get("score", 0.5)) + 0.3 * float(th.get("score", 0.5)) + 0.25 * float(focus.get("score", 0.5)))
    return _day("world_class_theater_command_joint_day", "World class theater command joint day",
        "World class theater command joint · top %s · score %.2f" % (wc.get("top_domain"), score), score,
        [_q(str(wc.get("top_leaf", "apply_focus")), province_id, score, "wc top leaf"), _q("apply_focus", province_id, 0.5, "wc theater focus")],
        "#fbbf24", "★", ["world_class", "theater", "joint"], {"world_class": wc, "theater": th, "world_class_score": score})


def world_class_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    pillars = [
        logistics_supply_close_day(province_id),
        intelligence_network_close_day(province_id),
        world_class_scan_advanced_day(province_id),
        world_class_execute_advanced_day(province_id),
        world_class_logistics_intel_joint_day(province_id),
        world_class_session_ai_joint_day(province_id),
        world_class_theater_command_joint_day(province_id),
    ]
    gates = {
        "logistics": logistics_supply_theater_integrity(),
        "intel": intelligence_network_product_integrity(),
        "world_class": world_class_campaign_command_integrity(),
        "exec": execution_integrity_gate(),
        "sole": sole_mult_integrity(),
    }
    gate_ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates.values())
    non_empty = sum(1 for p in pillars if not p.get("empty"))
    avg = sum(float(p.get("score", 0)) for p in pillars) / max(1, len(pillars))
    ok = gate_ok and non_empty >= 7
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("world_class_campaign_close_day", "World class campaign close day",
        "World class campaign close · pillars %d/7 · gates %s · score %.2f"
        % (non_empty, "PASS" if ok else "FAIL", score), score,
        [_q("apply_focus", province_id, score, "wc close focus"), _q("apply_supply", province_id, 0.55, "wc close supply"),
         _q("apply_agent_dispatch", province_id, 0.5, "wc close intel"), _q("apply_production", province_id, 0.45, "wc close prod")],
        "#5ec8ff", "✓", ["world_class", "campaign", "close", "next330"],
        {"pillars": pillars, "gates": gates, "ok": ok, "world_class_score": score})


WORLD_CLASS_DEPTH_DAY_IDS = [
    "logistics_route_advanced_day", "logistics_sustain_advanced_day", "logistics_readiness_advanced_day",
    "logistics_naval_joint_day", "logistics_tech_industry_joint_day", "logistics_supply_close_day",
    "intel_coverage_advanced_day", "intel_counterintel_advanced_day", "intel_counterplay_advanced_day",
    "intel_diplomacy_joint_day", "intel_session_joint_day", "intelligence_network_close_day",
    "world_class_scan_advanced_day", "world_class_rank_advanced_day", "world_class_execute_advanced_day",
    "world_class_logistics_intel_joint_day", "world_class_air_naval_joint_day", "world_class_session_ai_joint_day",
    "world_class_theater_command_joint_day", "world_class_campaign_close_day",
]

DAY_FUNCS = [
    logistics_route_advanced_day, logistics_sustain_advanced_day, logistics_readiness_advanced_day,
    logistics_naval_joint_day, logistics_tech_industry_joint_day, logistics_supply_close_day,
    intel_coverage_advanced_day, intel_counterintel_advanced_day, intel_counterplay_advanced_day,
    intel_diplomacy_joint_day, intel_session_joint_day, intelligence_network_close_day,
    world_class_scan_advanced_day, world_class_rank_advanced_day, world_class_execute_advanced_day,
    world_class_logistics_intel_joint_day, world_class_air_naval_joint_day, world_class_session_ai_joint_day,
    world_class_theater_command_joint_day, world_class_campaign_close_day,
]


def world_class_depth_integrity() -> Dict[str, Any]:
    gates = [
        logistics_supply_theater_integrity(),
        intelligence_network_product_integrity(),
        world_class_campaign_command_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        logistics_route_advanced_day(),
        intel_coverage_advanced_day(),
        world_class_scan_advanced_day(),
        world_class_campaign_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "World-class depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next330_world_class_depth_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = world_class_depth_integrity()
    ok = bool(gate.get("ok")) and non_empty >= 20
    label = "Close next330 world-class depth · packages %d/20 · queue %d · %s" % (
        non_empty, q_total, "PASS" if ok else "FAIL"
    )
    return {
        "packages": packages, "non_empty": non_empty, "queue_total": q_total, "gate": gate,
        "score": non_empty / 20.0, "summary": label, "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next330 world-class[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False, "ok": ok,
    }
