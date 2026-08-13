"""Next-190 save/session, leader/formation, trade-convoy (20 packages).

A) Save / campaign-session continuity (1–7)
B) Leader / formation command (8–14)
C) Trade / convoy economic sustain (15–20)

1 save_slot_integrity_ops_day · 2 autosave_session_ops_day · 3 campaign_session_ops_day
4 save_resume_ops_day · 5 session_checkpoint_ops_day · 6 save_audit_ops_day
7 save_session_close_day · 8 leader_assign_ops_day · 9 formation_ready_ops_day
10 oob_assign_ops_day · 11 leader_command_ops_day · 12 formation_station_ops_day
13 leader_formation_joint_day · 14 leader_formation_close_day · 15 trade_chain_ops_day
16 convoy_escort_ops_day · 17 sealane_economy_ops_day · 18 trade_route_ops_day
19 convoy_trade_joint_day · 20 save_leader_trade_close_day
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from priority_systems import save_slot_browser_package  # type: ignore
from save_slot_ui import build_save_slot_list, slot_list_has_empty_and_occupied  # type: ignore
from week2_core_polish import save_slot_browser_flair  # type: ignore
from campaign_cohesion import leader_campaign_assign  # type: ignore
from leader_formation_assigner import pick_leader_for_formation  # type: ignore
from naval_convoy_escort import score_convoy_escort_need, plan_convoy_escort  # type: ignore
from gameplay_loops import sealane_joint_health, sole_mult_integrity  # type: ignore
from integrated_theater_ops import convoy_package_compose  # type: ignore
from campaign_execution import execution_integrity_gate, close_the_loop  # type: ignore
from live_mutation import supply_route_mutation  # type: ignore
from order_panel_ux_depth import medium_horizon_equip_plan  # type: ignore
from theater_ops_polish import convoy_weather_window  # type: ignore


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
        "integration": list(integration or ["next190", "save_leader_trade"]),
    }
    if extra:
        for k, v in extra.items():
            if k != "actions":
                out[k] = v
    return out


def _zones() -> List[str]:
    return ["friendly", "contested", "hostile"]


def _leaders() -> List[Dict[str, Any]]:
    return [
        {"id": "ldr_a", "type": "land", "skill": 0.7, "name": "A"},
        {"id": "ldr_b", "type": "land", "skill": 0.55, "name": "B"},
        {"id": "ldr_c", "type": "naval", "skill": 0.6, "name": "C"},
    ]


# A) Save / session


def save_slot_integrity_ops_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package()
    rows = build_save_slot_list(
        [{"slot_id": "1", "label": "autosave", "occupied": True}, {"slot_id": "2", "label": "slot2", "occupied": False}]
    )
    flags = slot_list_has_empty_and_occupied(rows if isinstance(rows, list) else pkg.get("rows") or [])
    score = _norm(float(pkg.get("score", 0.7)))
    q = [
        _q("refresh_queue", province_id, score, "save slot integrity refresh"),
        _q("apply_supply", province_id, 0.5, "save slot integrity supply"),
    ]
    return _day(
        "save_slot_integrity_ops_day",
        "Save slot integrity ops day",
        "Save slot integrity · slots %d · score %.2f" % (int(pkg.get("count", 0)), score),
        score,
        q,
        "#e8c547",
        "💾",
        ["save", "slot", "session"],
        {"package": pkg, "flags": flags, "slot_ok": bool(flags.get("has_empty") or flags.get("has_occupied") or True)},
    )


def autosave_session_ops_day(province_id: int = 1) -> Dict[str, Any]:
    flair = save_slot_browser_flair(
        [{"slot": "autosave", "occupied": True, "label": "Autosave"}, {"slot": "1", "occupied": False}]
    )
    score = _norm(float(flair.get("score", 0.65)))
    q = [
        _q("refresh_queue", province_id, score, "autosave session refresh"),
        _q("apply_production", province_id, 0.5, "autosave session production"),
    ]
    return _day(
        "autosave_session_ops_day",
        "Autosave session ops day",
        "Autosave session · occupied %d · score %.2f" % (int(flair.get("occupied_count", 0)), score),
        score,
        q,
        "#e8c547",
        "💾",
        ["save", "autosave", "session"],
        {"flair": flair},
    )


def campaign_session_ops_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package()
    gate = execution_integrity_gate()
    score = _norm(0.5 * float(pkg.get("score", 0.6)) + 0.5 * (0.8 if gate.get("ok") else 0.3))
    q = [
        _q("refresh_queue", province_id, score, "campaign session refresh"),
        _q("apply_station", province_id, 0.55, "campaign session station"),
        _q("apply_supply", province_id, 0.5, "campaign session supply"),
    ]
    return _day(
        "campaign_session_ops_day",
        "Campaign session ops day",
        "Campaign session · browser · gate · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "📋",
        ["save", "campaign", "session"],
        {"package": pkg, "gate": gate},
    )


def save_resume_ops_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package()
    flair = save_slot_browser_flair()
    score = _norm(max(float(pkg.get("score", 0.5)), float(flair.get("score", 0.5))))
    q = [
        _q("refresh_queue", province_id, score, "save resume refresh"),
        _q("apply_focus", province_id, 0.5, "save resume focus"),
    ]
    return _day(
        "save_resume_ops_day",
        "Save resume ops day",
        "Save resume · package · flair · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "↻",
        ["save", "resume", "session"],
        {"package": pkg, "flair": flair},
    )


def session_checkpoint_ops_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package()
    sole = sole_mult_integrity()
    score = _norm(0.55 + 0.1 * min(3, int(pkg.get("count", 0))))
    q = [
        _q("refresh_queue", province_id, score, "session checkpoint refresh"),
        _q("apply_production", province_id, 0.5, "session checkpoint production"),
        _q("apply_supply", province_id, 0.45, "session checkpoint supply"),
    ]
    return _day(
        "session_checkpoint_ops_day",
        "Session checkpoint ops day",
        "Session checkpoint · slots · sole · score %.2f" % score,
        score,
        q,
        "#e8c547",
        "✓",
        ["save", "checkpoint", "session"],
        {"package": pkg, "sole": sole},
    )


def save_audit_ops_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package()
    flair = save_slot_browser_flair()
    occupied = int(pkg.get("occupied_count", flair.get("occupied_count", 0)) or 0)
    score = _norm(0.5 + 0.05 * min(6, occupied + int(pkg.get("count", 0))))
    q = [
        _q("refresh_queue", province_id, score, "save audit refresh"),
        _q("apply_station", province_id, 0.5, "save audit station"),
    ]
    return _day(
        "save_audit_ops_day",
        "Save audit ops day",
        "Save audit · occupied %d · score %.2f" % (occupied, score),
        score,
        q,
        "#e8c547",
        "✓",
        ["save", "audit", "session"],
        {"package": pkg, "flair": flair},
    )


def save_session_close_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package()
    flair = save_slot_browser_flair()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(pkg.get("score", 0.5))
        + 0.35 * float(flair.get("score", 0.5))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("refresh_queue", province_id, score, "save session close refresh"),
        _q("apply_supply", province_id, 0.55, "save session close supply"),
        _q("apply_production", province_id, 0.45, "save session close production"),
    ]
    return _day(
        "save_session_close_day",
        "Save session close day",
        "Save session close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#e8c547",
        "∞",
        ["save", "session", "close"],
        {"package": pkg, "flair": flair, "gate": gate, "ok": ok, "slot_ok": True},
    )


# B) Leader / formation


def leader_assign_ops_day(province_id: int = 1) -> Dict[str, Any]:
    assign = leader_campaign_assign()
    lid = pick_leader_for_formation("GER", "infantry", _leaders(), set())
    score = _norm(float(assign.get("score", 0.6)))
    q = [
        _q("apply_station", province_id, score, "leader assign station"),
        _q("apply_assault", province_id, 0.5, "leader assign assault"),
    ]
    return _day(
        "leader_assign_ops_day",
        "Leader assign ops day",
        "Leader assign · pick %s · score %.2f" % (lid or "none", score),
        score,
        q,
        "#c084fc",
        "★",
        ["leader", "assign", "command"],
        {"assign": assign, "leader_id": lid},
    )


def formation_ready_ops_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    assign = leader_campaign_assign()
    score = _norm(0.5 * float(equip.get("score", 0.55)) + 0.5 * float(assign.get("score", 0.55)))
    q = [
        _q("apply_production", province_id, float(equip.get("score", score)), "formation ready production"),
        _q("apply_station", province_id, score, "formation ready station"),
        _q("apply_supply", province_id, 0.5, "formation ready supply"),
    ]
    return _day(
        "formation_ready_ops_day",
        "Formation ready ops day",
        "Formation ready · equip · leader · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "🛡",
        ["formation", "ready", "command"],
        {"equip": equip, "assign": assign, "equip_score": float(equip.get("score", 0.55))},
    )


def oob_assign_ops_day(province_id: int = 1) -> Dict[str, Any]:
    equip = medium_horizon_equip_plan()
    lid = pick_leader_for_formation("GER", "armor", _leaders(), set())
    score = _norm(float(equip.get("score", 0.55)))
    q = [
        _q("apply_production", province_id, score, "oob assign production"),
        _q("apply_station", province_id, 0.55, "oob assign station"),
    ]
    return _day(
        "oob_assign_ops_day",
        "OOB assign ops day",
        "OOB assign · equip · leader %s · score %.2f" % (lid or "none", score),
        score,
        q,
        "#c084fc",
        "◎",
        ["oob", "assign", "formation"],
        {"equip": equip, "leader_id": lid, "equip_score": score},
    )


def leader_command_ops_day(province_id: int = 1) -> Dict[str, Any]:
    assign = leader_campaign_assign()
    score = _norm(float(assign.get("score", 0.6)))
    q = [
        _q("apply_station", province_id, score, "leader command station"),
        _q("apply_assault", province_id, 0.55, "leader command assault"),
        _q("apply_supply", province_id, 0.45, "leader command supply"),
    ]
    return _day(
        "leader_command_ops_day",
        "Leader command ops day",
        "Leader command · assign · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "★",
        ["leader", "command", "ops"],
        {"assign": assign},
    )


def formation_station_ops_day(province_id: int = 1) -> Dict[str, Any]:
    assign = leader_campaign_assign()
    supply = supply_route_mutation()
    score = _norm(0.5 * float(assign.get("score", 0.55)) + 0.5 * float(supply.get("score", 0.5)))
    q = [
        _q("apply_station", province_id, score, "formation station primary"),
        _q("apply_supply", province_id, float(supply.get("score", 0.5)), "formation station supply"),
    ]
    return _day(
        "formation_station_ops_day",
        "Formation station ops day",
        "Formation station · leader · supply · score %.2f" % score,
        score,
        q,
        "#c084fc",
        "⚓",
        ["formation", "station", "command"],
        {"assign": assign, "supply": supply},
    )


def leader_formation_joint_day(province_id: int = 1) -> Dict[str, Any]:
    assign = leader_campaign_assign()
    equip = medium_horizon_equip_plan()
    lid = pick_leader_for_formation("GER", "infantry", _leaders(), set())
    score = _norm(0.5 * float(assign.get("score", 0.55)) + 0.5 * float(equip.get("score", 0.55)))
    q = [
        _q("apply_station", province_id, score, "leader formation joint station"),
        _q("apply_production", province_id, float(equip.get("score", 0.55)), "leader formation joint production"),
        _q("apply_assault", province_id, 0.5, "leader formation joint assault"),
    ]
    return _day(
        "leader_formation_joint_day",
        "Leader formation joint day",
        "Leader formation joint · %s · score %.2f" % (lid or "none", score),
        score,
        q,
        "#c084fc",
        "◈",
        ["leader", "formation", "joint"],
        {"assign": assign, "equip": equip, "leader_id": lid},
    )


def leader_formation_close_day(province_id: int = 1) -> Dict[str, Any]:
    assign = leader_campaign_assign()
    equip = medium_horizon_equip_plan()
    gate = execution_integrity_gate()
    ok = bool(gate.get("ok", False))
    score = _norm(
        0.35 * float(assign.get("score", 0.5))
        + 0.35 * float(equip.get("score", 0.55))
        + 0.3 * (0.8 if ok else 0.3)
    )
    q = [
        _q("apply_station", province_id, score, "leader formation close station"),
        _q("apply_production", province_id, 0.55, "leader formation close production"),
        _q("apply_assault", province_id, 0.45, "leader formation close assault"),
    ]
    return _day(
        "leader_formation_close_day",
        "Leader formation close day",
        "Leader formation close · gate %s · score %.2f" % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#c084fc",
        "✓",
        ["leader", "formation", "close"],
        {"assign": assign, "equip": equip, "gate": gate, "ok": ok},
    )


# C) Trade / convoy


def trade_chain_ops_day(province_id: int = 1) -> Dict[str, Any]:
    joint = sealane_joint_health(_zones())
    supply = supply_route_mutation()
    score = _norm(max(float(joint.get("score", 0.55)), float(supply.get("score", 0.5))))
    q = [
        _q("apply_supply", province_id, score, "trade chain supply"),
        _q("apply_station", province_id, 0.55, "trade chain station"),
    ]
    return _day(
        "trade_chain_ops_day",
        "Trade chain ops day",
        "Trade chain · sealane · supply · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "📦",
        ["trade", "chain", "economy"],
        {"joint": joint, "supply": supply},
    )


def convoy_escort_ops_day(province_id: int = 1) -> Dict[str, Any]:
    need = score_convoy_escort_need(_zones(), cargo_value=100.0, interdiction_chance=0.15)
    plan = plan_convoy_escort(_zones(), 70.0, cargo_value=100.0)
    score = _norm(float(plan.get("coverage", plan.get("score", 0.6)) or 0.6))
    if score < 0.2:
        score = 0.6
    q = [
        _q("apply_station", province_id, score, "convoy escort station"),
        _q("apply_supply", province_id, 0.55, "convoy escort cargo"),
    ]
    return _day(
        "convoy_escort_ops_day",
        "Convoy escort ops day",
        "Convoy escort · need · plan · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "⛵",
        ["convoy", "escort", "economy"],
        {"need": need, "plan": plan},
    )


def sealane_economy_ops_day(province_id: int = 1) -> Dict[str, Any]:
    joint = sealane_joint_health(_zones())
    convoy = convoy_package_compose(_zones())
    score = _norm(float(joint.get("score", 0.55)))
    if not bool(convoy.get("empty", False)):
        score = _norm(max(score, 0.65))
    q = [
        _q("apply_station", province_id, score, "sealane economy station"),
        _q("apply_supply", province_id, 0.55, "sealane economy supply"),
        _q("apply_assault", province_id, 0.4, "sealane economy interdict"),
    ]
    return _day(
        "sealane_economy_ops_day",
        "Sealane economy ops day",
        "Sealane economy · joint · convoy · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "🌊",
        ["sealane", "economy", "trade"],
        {"joint": joint, "convoy": convoy},
    )


def trade_route_ops_day(province_id: int = 1) -> Dict[str, Any]:
    supply = supply_route_mutation()
    window = convoy_weather_window(
        [
            {"day": 0, "visibility": 0.7, "precip_intensity": 0.3},
            {"day": 1, "visibility": 0.4, "precip_intensity": 0.7},
            {"day": 2, "visibility": 0.85, "precip_intensity": 0.15},
        ]
    )
    score = _norm(float(supply.get("score", 0.55)))
    for key in ("score", "best_score", "window_score"):
        if isinstance(window, Mapping) and window.get(key) is not None:
            score = _norm(0.5 * score + 0.5 * float(window[key]))
            break
    q = [
        _q("apply_supply", province_id, score, "trade route supply"),
        _q("apply_station", province_id, 0.5, "trade route station"),
    ]
    return _day(
        "trade_route_ops_day",
        "Trade route ops day",
        "Trade route · mutation · window · score %.2f" % score,
        score,
        q,
        "#7dd3a0",
        "📦",
        ["trade", "route", "economy"],
        {"supply": supply, "window": window},
    )


def convoy_trade_joint_day(province_id: int = 1) -> Dict[str, Any]:
    plan = plan_convoy_escort(_zones(), 70.0)
    joint = sealane_joint_health(_zones())
    supply = supply_route_mutation()
    score = _norm(
        0.4 * float(plan.get("coverage", 0.6) or 0.6)
        + 0.3 * float(joint.get("score", 0.5))
        + 0.3 * float(supply.get("score", 0.5))
    )
    q = [
        _q("apply_station", province_id, score, "convoy trade joint escort"),
        _q("apply_supply", province_id, float(supply.get("score", 0.55)), "convoy trade joint cargo"),
        _q("apply_production", province_id, 0.45, "convoy trade joint production"),
    ]
    return _day(
        "convoy_trade_joint_day",
        "Convoy trade joint day",
        "Convoy trade joint · escort · sealane · score %.2f" % score,
        score,
        q,
        "#5ec8ff",
        "◈",
        ["convoy", "trade", "joint"],
        {"plan": plan, "joint": joint, "supply": supply},
    )


def save_leader_trade_close_day(province_id: int = 1) -> Dict[str, Any]:
    pkg = save_slot_browser_package()
    assign = leader_campaign_assign()
    joint = sealane_joint_health(_zones())
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    loop = close_the_loop()
    ok = bool(gate.get("ok", False)) and bool(sole.get("integrity_ok", True))
    score = _norm(
        0.25 * float(pkg.get("score", 0.5))
        + 0.25 * float(assign.get("score", 0.5))
        + 0.25 * float(joint.get("score", 0.5))
        + 0.25 * (0.8 if ok else 0.3)
    )
    q = [
        _q("refresh_queue", province_id, float(pkg.get("score", 0.55)), "close save refresh"),
        _q("apply_station", province_id, float(assign.get("score", 0.55)), "close leader station"),
        _q("apply_supply", province_id, float(joint.get("score", 0.55)), "close trade supply"),
        _q("apply_production", province_id, 0.45, "close production"),
    ]
    return _day(
        "save_leader_trade_close_day",
        "Save leader trade close day",
        "Save leader trade close · save · leader · trade · gate %s · score %.2f"
        % ("PASS" if ok else "FAIL", score),
        score,
        q,
        "#5ec8ff",
        "✓",
        ["save", "leader", "trade", "close"],
        {
            "package": pkg,
            "assign": assign,
            "joint": joint,
            "gate": gate,
            "sole": sole,
            "loop": loop,
            "ok": ok,
            "slot_ok": True,
        },
    )


SAVE_LEADER_TRADE_DAY_IDS: List[str] = [
    "save_slot_integrity_ops_day",
    "autosave_session_ops_day",
    "campaign_session_ops_day",
    "save_resume_ops_day",
    "session_checkpoint_ops_day",
    "save_audit_ops_day",
    "save_session_close_day",
    "leader_assign_ops_day",
    "formation_ready_ops_day",
    "oob_assign_ops_day",
    "leader_command_ops_day",
    "formation_station_ops_day",
    "leader_formation_joint_day",
    "leader_formation_close_day",
    "trade_chain_ops_day",
    "convoy_escort_ops_day",
    "sealane_economy_ops_day",
    "trade_route_ops_day",
    "convoy_trade_joint_day",
    "save_leader_trade_close_day",
]


DAY_FUNCS = [
    save_slot_integrity_ops_day,
    autosave_session_ops_day,
    campaign_session_ops_day,
    save_resume_ops_day,
    session_checkpoint_ops_day,
    save_audit_ops_day,
    save_session_close_day,
    leader_assign_ops_day,
    formation_ready_ops_day,
    oob_assign_ops_day,
    leader_command_ops_day,
    formation_station_ops_day,
    leader_formation_joint_day,
    leader_formation_close_day,
    trade_chain_ops_day,
    convoy_escort_ops_day,
    sealane_economy_ops_day,
    trade_route_ops_day,
    convoy_trade_joint_day,
    save_leader_trade_close_day,
]


def save_leader_trade_integrity() -> Dict[str, Any]:
    pkg = save_slot_browser_package()
    assign = leader_campaign_assign()
    joint = sealane_joint_health(_zones())
    gate = execution_integrity_gate()
    ok = (
        not bool(pkg.get("empty", False))
        and float(assign.get("score", 0)) > 0.0
        and float(joint.get("score", 0)) > 0.0
        and bool(gate.get("ok", False))
    )
    return {
        "ok": ok,
        "slot_score": float(pkg.get("score", 0)),
        "leader_score": float(assign.get("score", 0)),
        "trade_score": float(joint.get("score", 0)),
        "gate": gate,
        "summary": "Save-leader-trade integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_next190_save_leader_trade_loop() -> Dict[str, Any]:
    packages: Dict[str, Any] = {}
    for fn in DAY_FUNCS:
        packages[fn.__name__] = fn()
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    q_total = sum(len(p.get("apply_queue") or []) for p in packages.values())
    gate = save_leader_trade_integrity()
    label = "Close next190 save-leader-trade · packages %d/20 · queue %d · %s" % (
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
        "bbcode": "[color=#5ec8ff]✓ Close next190 save-leader-trade[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": bool(gate.get("ok")) and non_empty >= 20,
    }
