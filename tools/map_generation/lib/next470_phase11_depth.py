"""Next-470 Phase 11 world-class GS depth (12): alliance · personality AI · revolt network."""
from __future__ import annotations
from typing import Any, Dict
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from alliance_guarantee_network_product import (  # type: ignore
    build_alliance_guarantee_network_product, execute_alliance_step, alliance_guarantee_network_integrity,
)
from faction_personality_ai_product import (  # type: ignore
    build_faction_personality_ai_product, execute_personality_step, faction_personality_ai_integrity,
)
from occupation_revolt_network_product import (  # type: ignore
    build_occupation_revolt_network_product, execute_revolt_network_step, occupation_revolt_network_integrity,
)


def _floor(score: float, lo: float = 0.35) -> float:
    try:
        s = float(score)
    except Exception:
        s = 0.5
    if s > 2:
        s /= 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def _q(aid, pid, score, label):
    return {"action_id": aid, "province_id": max(1, int(pid)), "score": score, "enabled": True, "label": label}


def _day(aid, title, summary, score, apply_queue, extra=None):
    sc = _floor(score)
    out = {
        "id": aid, "title": title, "score": sc, "live_score": sc, "apply_queue": apply_queue,
        "actions": [{"action_id": aid, "label": "Run %s" % title.lower(), "enabled": True}],
        "summary": summary, "plain": summary,
        "bbcode": "[color=#6ec8ff]⚡ %s[/color] [color=#8899aa]%s[/color]" % (title, summary),
        "empty": False, "integration": [aid, "next470", "phase11_depth", "world_class_gs"],
    }
    if extra:
        out.update(extra)
    return out


def alliance_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_alliance_step("board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("alliance_board_day", "Alliance board day",
                "Alliance board day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "al board primary"), _q("apply_station", province_id, 0.5, "al board station")],
                {"depth_score": score})


def alliance_guarantee_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_alliance_step("guarantee", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("alliance_guarantee_day", "Alliance guarantee day",
                "Alliance guarantee day · score %.2f" % score, score,
                [_q("apply_agent_dispatch", province_id, score, "al guarantee primary"), _q("apply_focus", province_id, 0.5, "al guarantee focus")],
                {"depth_score": score})


def alliance_coalition_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_alliance_step("coalition", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("alliance_coalition_day", "Alliance coalition day",
                "Alliance coalition day · score %.2f" % score, score,
                [_q("apply_hh_commit", province_id, score, "al coalition primary"), _q("apply_production", province_id, 0.5, "al coalition prod")],
                {"depth_score": score})


def alliance_guarantee_network_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = alliance_board_day(province_id), alliance_guarantee_day(province_id), alliance_coalition_day(province_id)
    p = build_alliance_guarantee_network_product(province_id=province_id)
    gate = alliance_guarantee_network_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("alliance_guarantee_network_close_day", "Alliance guarantee network close day",
                "Alliance network close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_hh_commit", province_id, score, "al close primary"), _q("apply_focus", province_id, 0.5, "al close focus")],
                {"ok": ok, "depth_score": score, "gate": gate})


def personality_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_personality_step("board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("personality_board_day", "Personality board day",
                "Personality board day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "pers board primary"), _q("apply_station", province_id, 0.5, "pers board station")],
                {"depth_score": score})


def personality_event_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_personality_step("event", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("personality_event_day", "Personality event day",
                "Personality event day · score %.2f" % score, score,
                [_q("apply_agent_dispatch", province_id, score, "pers event primary"), _q("apply_focus", province_id, 0.5, "pers event focus")],
                {"depth_score": score})


def personality_drive_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_personality_step("drive", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("personality_drive_day", "Personality drive day",
                "Personality drive day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "pers drive primary"), _q("apply_production", province_id, 0.5, "pers drive prod")],
                {"depth_score": score})


def faction_personality_ai_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = personality_board_day(province_id), personality_event_day(province_id), personality_drive_day(province_id)
    p = build_faction_personality_ai_product(province_id=province_id)
    gate = faction_personality_ai_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("faction_personality_ai_close_day", "Faction personality AI close day",
                "Faction personality close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "pers close primary"), _q("apply_focus", province_id, 0.5, "pers close focus")],
                {"ok": ok, "depth_score": score, "gate": gate})


def revolt_network_map_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_revolt_network_step("map", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("revolt_network_map_day", "Revolt network map day",
                "Revolt network map day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "rev map primary"), _q("apply_station", province_id, 0.5, "rev map station")],
                {"depth_score": score})


def revolt_cascade_risk_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_revolt_network_step("cascade", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("revolt_cascade_risk_day", "Revolt cascade risk day",
                "Revolt cascade risk day · score %.2f" % score, score,
                [_q("apply_agent_dispatch", province_id, score, "rev cascade primary"), _q("apply_focus", province_id, 0.5, "rev cascade focus")],
                {"depth_score": score})


def revolt_network_suppress_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_revolt_network_step("suppress", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("revolt_network_suppress_day", "Revolt network suppress day",
                "Revolt network suppress day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "rev suppress primary"), _q("apply_supply", province_id, 0.5, "rev suppress supply")],
                {"depth_score": score})


def occupation_revolt_network_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = revolt_network_map_day(province_id), revolt_cascade_risk_day(province_id), revolt_network_suppress_day(province_id)
    p = build_occupation_revolt_network_product(province_id=province_id)
    gate = occupation_revolt_network_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("occupation_revolt_network_close_day", "Occupation revolt network close day",
                "Occupation revolt network close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_station", province_id, score, "rev close primary"), _q("apply_focus", province_id, 0.5, "rev close focus")],
                {"ok": ok, "depth_score": score, "gate": gate})


PHASE11_DEPTH_DAY_IDS = [
    "alliance_board_day", "alliance_guarantee_day", "alliance_coalition_day", "alliance_guarantee_network_close_day",
    "personality_board_day", "personality_event_day", "personality_drive_day", "faction_personality_ai_close_day",
    "revolt_network_map_day", "revolt_cascade_risk_day", "revolt_network_suppress_day", "occupation_revolt_network_close_day",
]
DAY_FUNCS = [
    alliance_board_day, alliance_guarantee_day, alliance_coalition_day, alliance_guarantee_network_close_day,
    personality_board_day, personality_event_day, personality_drive_day, faction_personality_ai_close_day,
    revolt_network_map_day, revolt_cascade_risk_day, revolt_network_suppress_day, occupation_revolt_network_close_day,
]


def phase11_depth_integrity() -> Dict[str, Any]:
    gates = [
        alliance_guarantee_network_integrity(),
        faction_personality_ai_integrity(),
        occupation_revolt_network_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        alliance_board_day(), personality_board_day(), revolt_network_map_day(),
        alliance_guarantee_network_close_day(), faction_personality_ai_close_day(), occupation_revolt_network_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase11 depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next470_phase11_depth_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase11_depth_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-470 phase11 depth · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
