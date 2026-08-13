"""Next-350 occupation / manpower / leader depth pillars (20).

A) Occupation advanced (1–6)
B) Manpower advanced (7–12)
C) Leader command joints + close (13–20)
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from occupation_control_product import (  # type: ignore
    build_occupation_control_product, execute_occupation_step, occupation_control_integrity,
)
from manpower_reinforcement_product import (  # type: ignore
    build_manpower_reinforcement_product, execute_manpower_step, manpower_reinforcement_integrity,
)
from leader_command_product import (  # type: ignore
    build_leader_command_product, execute_leader_command_step, leader_command_product_integrity,
)
from front_continuity_campaign_product import build_front_continuity_campaign_product  # type: ignore
from war_economy_mobilization_product import build_war_economy_mobilization_product  # type: ignore
from intelligence_network_product import build_intelligence_network_product  # type: ignore
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
        "empty": False, "integration": [aid, "next350", "occupation_manpower_leader"] + tags,
    }
    if extra: out.update(extra)
    return out

def occupation_control_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_occupation_control_product(province_id=province_id)
    e = execute_occupation_step("control", province_id)
    score = _floor(0.55 * _norm(float(p.get("control_score", 0.5))) + 0.45 * _norm(float(e.get("score", 0.5))))
    return _day("occupation_control_advanced_day", "Occupation control advanced day",
        "Occupation control advanced day · score %.2f" % score, score,
        [_q("apply_station", province_id, score, "occ control primary"), _q("apply_assault", province_id, 0.5, "occ control assault")],
        "#c8a45e", "🏛", ["occupation"], {"occupation_score": score})

def occupation_garrison_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_occupation_step("garrison", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("occupation_garrison_advanced_day", "Occupation garrison advanced day",
        "Occupation garrison advanced day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "occ garrison primary"), _q("apply_station", province_id, 0.5, "occ garrison station")],
        "#c8a45e", "🏛", ["occupation"], {"occupation_score": score})

def occupation_integrate_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_occupation_step("integrate", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("occupation_integrate_advanced_day", "Occupation integrate advanced day",
        "Occupation integrate advanced day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "occ integrate primary"), _q("apply_station", province_id, 0.5, "occ integrate station")],
        "#c8a45e", "🏛", ["occupation"], {"occupation_score": score})

def occupation_front_joint_day(province_id: int = 1) -> Dict[str, Any]:
    occ = build_occupation_control_product(province_id=province_id)
    front = build_front_continuity_campaign_product(province_id=province_id)
    score = _floor(0.55 * _norm(float(occ.get("score", 0.5))) + 0.45 * _norm(float(front.get("score", 0.5))))
    return _day("occupation_front_joint_day", "Occupation front joint day",
        "Occupation front joint day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "occ front joint primary"), _q("apply_station", province_id, 0.5, "occ front joint station")],
        "#c8a45e", "🏛", ["occupation", "front"], {"occupation_score": score})

def occupation_economy_joint_day(province_id: int = 1) -> Dict[str, Any]:
    occ = build_occupation_control_product(province_id=province_id)
    econ = build_war_economy_mobilization_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(occ.get("score", 0.5))) + 0.5 * _norm(float(econ.get("score", 0.5))))
    return _day("occupation_economy_joint_day", "Occupation economy joint day",
        "Occupation economy joint day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "occ econ joint primary"), _q("apply_station", province_id, 0.5, "occ econ joint station")],
        "#c8a45e", "🏛", ["occupation", "economy"], {"occupation_score": score})

def occupation_control_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = occupation_control_advanced_day(province_id)
    d1 = occupation_garrison_advanced_day(province_id)
    d2 = occupation_integrate_advanced_day(province_id)
    avg = (float(d0.get("score",0))+float(d1.get("score",0))+float(d2.get("score",0)))/3.0
    gate = occupation_control_integrity()
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in (d0,d1,d2))
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day("occupation_control_close_day", "Occupation control close day",
        "Occupation control close · score %.2f · %s" % (score, "PASS" if ok else "FAIL"), score,
        [_q("apply_station", province_id, score, "occ close primary"), _q("apply_production", province_id, 0.5, "occ close prod")],
        "#c8a45e", "✓", ["occupation", "close"], {"occupation_score": score, "ok": ok, "gate": gate})

def manpower_draft_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_manpower_reinforcement_product(province_id=province_id)
    e = execute_manpower_step("draft", province_id)
    score = _floor(0.55 * _norm(float(p.get("draft_score", 0.5))) + 0.45 * _norm(float(e.get("score", 0.5))))
    return _day("manpower_draft_advanced_day", "Manpower draft advanced day",
        "Manpower draft advanced day · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "mp draft primary"), _q("apply_station", province_id, 0.5, "mp draft station")],
        "#9ad06a", "🎖", ["manpower"], {"manpower_score": score})

def manpower_reinforce_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_manpower_step("reinforce", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("manpower_reinforce_advanced_day", "Manpower reinforce advanced day",
        "Manpower reinforce advanced day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "mp reinforce primary"), _q("apply_station", province_id, 0.5, "mp reinforce station")],
        "#9ad06a", "🎖", ["manpower"], {"manpower_score": score})

def manpower_field_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_manpower_step("field", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("manpower_field_advanced_day", "Manpower field advanced day",
        "Manpower field advanced day · score %.2f" % score, score,
        [_q("apply_station", province_id, score, "mp field primary"), _q("apply_production", province_id, 0.5, "mp field prod")],
        "#9ad06a", "🎖", ["manpower"], {"manpower_score": score})

def manpower_front_joint_day(province_id: int = 1) -> Dict[str, Any]:
    mp = build_manpower_reinforcement_product(province_id=province_id)
    front = build_front_continuity_campaign_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(mp.get("score", 0.5))) + 0.5 * _norm(float(front.get("score", 0.5))))
    return _day("manpower_front_joint_day", "Manpower front joint day",
        "Manpower front joint day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "mp front joint primary"), _q("apply_station", province_id, 0.5, "mp front joint station")],
        "#9ad06a", "🎖", ["manpower", "front"], {"manpower_score": score})

def manpower_economy_joint_day(province_id: int = 1) -> Dict[str, Any]:
    mp = build_manpower_reinforcement_product(province_id=province_id)
    econ = build_war_economy_mobilization_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(mp.get("score", 0.5))) + 0.5 * _norm(float(econ.get("score", 0.5))))
    return _day("manpower_economy_joint_day", "Manpower economy joint day",
        "Manpower economy joint day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "mp econ joint primary"), _q("apply_focus", province_id, 0.5, "mp econ joint focus")],
        "#9ad06a", "🎖", ["manpower", "economy"], {"manpower_score": score})

def manpower_reinforcement_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = manpower_draft_advanced_day(province_id)
    d1 = manpower_reinforce_advanced_day(province_id)
    d2 = manpower_field_advanced_day(province_id)
    avg = (float(d0.get("score",0))+float(d1.get("score",0))+float(d2.get("score",0)))/3.0
    gate = manpower_reinforcement_integrity()
    ok = bool(gate.get("ok")) and all(not d.get("empty") for d in (d0,d1,d2))
    score = _floor(0.6 * avg + 0.4 * (1.0 if ok else 0.3))
    return _day("manpower_reinforcement_close_day", "Manpower reinforcement close day",
        "Manpower reinforcement close · score %.2f · %s" % (score, "PASS" if ok else "FAIL"), score,
        [_q("apply_production", province_id, score, "mp close primary"), _q("apply_station", province_id, 0.5, "mp close station")],
        "#9ad06a", "✓", ["manpower", "close"], {"manpower_score": score, "ok": ok, "gate": gate})

def leader_assign_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    p = build_leader_command_product(province_id=province_id)
    e = execute_leader_command_step("assign", province_id)
    score = _floor(0.55 * _norm(float(p.get("assign_score", 0.5))) + 0.45 * _norm(float(e.get("score", 0.5))))
    return _day("leader_assign_advanced_day", "Leader assign advanced day",
        "Leader assign advanced day · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "ld assign primary"), _q("apply_station", province_id, 0.5, "ld assign station")],
        "#d4a0ff", "★", ["leader"], {"leader_score": score})

def leader_station_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_leader_command_step("station", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("leader_station_advanced_day", "Leader station advanced day",
        "Leader station advanced day · score %.2f" % score, score,
        [_q("apply_station", province_id, score, "ld station primary"), _q("apply_focus", province_id, 0.5, "ld station focus")],
        "#d4a0ff", "★", ["leader"], {"leader_score": score})

def leader_ops_advanced_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_leader_command_step("command", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("leader_ops_advanced_day", "Leader ops advanced day",
        "Leader ops advanced day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "ld ops primary"), _q("apply_station", province_id, 0.5, "ld ops station")],
        "#d4a0ff", "★", ["leader"], {"leader_score": score})

def leader_occupation_joint_day(province_id: int = 1) -> Dict[str, Any]:
    ld = build_leader_command_product(province_id=province_id)
    occ = build_occupation_control_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(ld.get("score", 0.5))) + 0.5 * _norm(float(occ.get("score", 0.5))))
    return _day("leader_occupation_joint_day", "Leader occupation joint day",
        "Leader occupation joint day · score %.2f" % score, score,
        [_q("apply_station", province_id, score, "ld occ joint primary"), _q("apply_focus", province_id, 0.5, "ld occ joint focus")],
        "#d4a0ff", "★", ["leader", "occupation"], {"leader_score": score})

def leader_manpower_joint_day(province_id: int = 1) -> Dict[str, Any]:
    ld = build_leader_command_product(province_id=province_id)
    mp = build_manpower_reinforcement_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(ld.get("score", 0.5))) + 0.5 * _norm(float(mp.get("score", 0.5))))
    return _day("leader_manpower_joint_day", "Leader manpower joint day",
        "Leader manpower joint day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "ld mp joint primary"), _q("apply_station", province_id, 0.5, "ld mp joint station")],
        "#d4a0ff", "★", ["leader", "manpower"], {"leader_score": score})

def leader_intel_joint_day(province_id: int = 1) -> Dict[str, Any]:
    ld = build_leader_command_product(province_id=province_id)
    intel = build_intelligence_network_product(province_id=province_id)
    score = _floor(0.5 * _norm(float(ld.get("score", 0.5))) + 0.5 * _norm(float(intel.get("score", 0.5))))
    return _day("leader_intel_joint_day", "Leader intel joint day",
        "Leader intel joint day · score %.2f" % score, score,
        [_q("apply_agent_dispatch", province_id, score, "ld intel joint primary"), _q("apply_focus", province_id, 0.5, "ld intel joint focus")],
        "#d4a0ff", "★", ["leader", "intel"], {"leader_score": score})

def leader_theater_joint_day(province_id: int = 1) -> Dict[str, Any]:
    ld = build_leader_command_product(province_id=province_id)
    th = build_theater_command_product(province_id=province_id)
    score = _floor(0.55 * _norm(float(ld.get("score", 0.5))) + 0.45 * _norm(float(th.get("score", 0.5))))
    return _day("leader_theater_joint_day", "Leader theater joint day",
        "Leader theater joint day · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "ld th joint primary"), _q("apply_assault", province_id, 0.5, "ld th joint assault")],
        "#d4a0ff", "★", ["leader", "theater"], {"leader_score": score})

def occupation_manpower_leader_close_day(province_id: int = 1) -> Dict[str, Any]:
    pillars = [
        occupation_control_close_day(province_id),
        manpower_reinforcement_close_day(province_id),
        leader_assign_advanced_day(province_id),
        leader_station_advanced_day(province_id),
        leader_ops_advanced_day(province_id),
        leader_occupation_joint_day(province_id),
        leader_theater_joint_day(province_id),
    ]
    gates = {
        "occupation": occupation_control_integrity(),
        "manpower": manpower_reinforcement_integrity(),
        "leader": leader_command_product_integrity(),
        "exec": execution_integrity_gate(),
        "sole": sole_mult_integrity(),
    }
    gate_ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates.values())
    non_empty = sum(1 for p in pillars if not p.get("empty"))
    avg = sum(float(p.get("score", 0)) for p in pillars) / max(1, len(pillars))
    ok = gate_ok and non_empty >= 7
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("occupation_manpower_leader_close_day", "Occupation manpower leader close day",
        "Occupation manpower leader close · pillars %d/7 · gates %s · score %.2f" % (non_empty, "PASS" if ok else "FAIL", score), score,
        [_q("apply_focus", province_id, score, "oml close focus"), _q("apply_station", province_id, 0.55, "oml close station"),
         _q("apply_production", province_id, 0.5, "oml close prod"), _q("apply_assault", province_id, 0.45, "oml close assault")],
        "#5ec8ff", "✓", ["occupation", "manpower", "leader", "close"],
        {"pillars": pillars, "gates": gates, "ok": ok, "leader_score": score})

OCCUPATION_MANPOWER_LEADER_DAY_IDS = [
    "occupation_control_advanced_day", "occupation_garrison_advanced_day", "occupation_integrate_advanced_day",
    "occupation_front_joint_day", "occupation_economy_joint_day", "occupation_control_close_day",
    "manpower_draft_advanced_day", "manpower_reinforce_advanced_day", "manpower_field_advanced_day",
    "manpower_front_joint_day", "manpower_economy_joint_day", "manpower_reinforcement_close_day",
    "leader_assign_advanced_day", "leader_station_advanced_day", "leader_ops_advanced_day",
    "leader_occupation_joint_day", "leader_manpower_joint_day", "leader_intel_joint_day",
    "leader_theater_joint_day", "occupation_manpower_leader_close_day",
]

DAY_FUNCS = [
    occupation_control_advanced_day, occupation_garrison_advanced_day, occupation_integrate_advanced_day,
    occupation_front_joint_day, occupation_economy_joint_day, occupation_control_close_day,
    manpower_draft_advanced_day, manpower_reinforce_advanced_day, manpower_field_advanced_day,
    manpower_front_joint_day, manpower_economy_joint_day, manpower_reinforcement_close_day,
    leader_assign_advanced_day, leader_station_advanced_day, leader_ops_advanced_day,
    leader_occupation_joint_day, leader_manpower_joint_day, leader_intel_joint_day,
    leader_theater_joint_day, occupation_manpower_leader_close_day,
]

def occupation_manpower_leader_integrity() -> Dict[str, Any]:
    gates = [
        occupation_control_integrity(),
        manpower_reinforcement_integrity(),
        leader_command_product_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        occupation_control_advanced_day(),
        manpower_draft_advanced_day(),
        leader_assign_advanced_day(),
        occupation_manpower_leader_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Occupation/manpower/leader depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}

def close_next350_occupation_manpower_leader_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = occupation_manpower_leader_integrity()
    ok = bool(gate.get("ok")) and non_empty >= 20
    label = "Close next350 occupation/manpower/leader · packages %d/20 · queue %d · %s" % (
        non_empty, q_total, "PASS" if ok else "FAIL"
    )
    return {
        "packages": packages, "non_empty": non_empty, "queue_total": q_total, "gate": gate,
        "score": non_empty / 20.0, "summary": label, "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close next350 occupation/manpower/leader[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False, "ok": ok,
    }
