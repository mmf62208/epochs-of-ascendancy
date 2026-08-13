"""Next-400 Phase 4 depth (12): revolt/garrison · cohort/reserve · multi-party peace."""
from __future__ import annotations
from typing import Any, Dict
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from occupation_revolt_garrison_product import (  # type: ignore
    build_occupation_revolt_garrison_product, execute_occupation_revolt_step, occupation_revolt_garrison_integrity,
)
from manpower_cohort_reserve_product import (  # type: ignore
    build_manpower_cohort_reserve_product, execute_manpower_cohort_step, manpower_cohort_reserve_integrity,
)
from multi_party_peace_conference_product import (  # type: ignore
    build_multi_party_peace_conference_product, execute_multi_party_peace_step, multi_party_peace_conference_integrity,
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
        "empty": False, "integration": [aid, "next400", "phase4_depth"],
    }
    if extra:
        out.update(extra)
    return out


def occupation_revolt_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_occupation_revolt_step("board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("occupation_revolt_board_day", "Occupation revolt board day",
                "Occupation revolt board day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "revolt board primary"), _q("apply_station", province_id, 0.5, "revolt board station")],
                {"revolt_score": score})


def occupation_revolt_garrison_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_occupation_revolt_step("garrison", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("occupation_revolt_garrison_day", "Occupation revolt garrison day",
                "Occupation revolt garrison day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "revolt garr primary"), _q("apply_supply", province_id, 0.5, "revolt garr supply")],
                {"revolt_score": score})


def occupation_revolt_suppress_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_occupation_revolt_step("suppress", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("occupation_revolt_suppress_day", "Occupation revolt suppress day",
                "Occupation revolt suppress day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "revolt suppress primary"), _q("apply_station", province_id, 0.5, "revolt suppress station")],
                {"revolt_score": score})


def occupation_revolt_garrison_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = occupation_revolt_board_day(province_id), occupation_revolt_garrison_day(province_id), occupation_revolt_suppress_day(province_id)
    p = build_occupation_revolt_garrison_product(province_id=province_id)
    gate = occupation_revolt_garrison_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("occupation_revolt_garrison_close_day", "Occupation revolt garrison close day",
                "Occupation revolt garrison close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "revolt close primary"), _q("apply_station", province_id, 0.5, "revolt close station")],
                {"ok": ok, "revolt_score": score, "gate": gate})


def manpower_cohort_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_manpower_cohort_step("cohorts", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("manpower_cohort_board_day", "Manpower cohort board day",
                "Manpower cohort board day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "cohort board primary"), _q("apply_station", province_id, 0.5, "cohort board station")],
                {"cohort_score": score})


def manpower_cohort_reserve_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_manpower_cohort_step("reserve", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("manpower_cohort_reserve_day", "Manpower cohort reserve day",
                "Manpower cohort reserve day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "cohort reserve primary"), _q("apply_focus", province_id, 0.5, "cohort reserve focus")],
                {"cohort_score": score})


def manpower_cohort_mobilize_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_manpower_cohort_step("mobilize", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("manpower_cohort_mobilize_day", "Manpower cohort mobilize day",
                "Manpower cohort mobilize day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "cohort mobil primary"), _q("apply_assault", province_id, 0.5, "cohort mobil assault")],
                {"cohort_score": score})


def manpower_cohort_reserve_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = manpower_cohort_board_day(province_id), manpower_cohort_reserve_day(province_id), manpower_cohort_mobilize_day(province_id)
    p = build_manpower_cohort_reserve_product(province_id=province_id)
    gate = manpower_cohort_reserve_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("manpower_cohort_reserve_close_day", "Manpower cohort reserve close day",
                "Manpower cohort reserve close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_station", province_id, score, "cohort close primary"), _q("apply_focus", province_id, 0.5, "cohort close focus")],
                {"ok": ok, "cohort_score": score, "gate": gate})


def multi_party_peace_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_multi_party_peace_step("board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("multi_party_peace_board_day", "Multi-party peace board day",
                "Multi-party peace board day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "mp peace board primary"), _q("apply_station", province_id, 0.5, "mp peace board station")],
                {"peace_score": score})


def multi_party_peace_wargoals_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_multi_party_peace_step("wargoals", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("multi_party_peace_wargoals_day", "Multi-party peace wargoals day",
                "Multi-party peace wargoals day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "mp peace goals primary"), _q("apply_focus", province_id, 0.5, "mp peace goals focus")],
                {"peace_score": score})


def multi_party_peace_settle_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_multi_party_peace_step("settle", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("multi_party_peace_settle_day", "Multi-party peace settle day",
                "Multi-party peace settle day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "mp peace settle primary"), _q("apply_station", province_id, 0.5, "mp peace settle station")],
                {"peace_score": score})


def multi_party_peace_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = multi_party_peace_board_day(province_id)
    d1 = multi_party_peace_wargoals_day(province_id)
    d2 = multi_party_peace_settle_day(province_id)
    p = build_multi_party_peace_conference_product(province_id=province_id)
    gate = multi_party_peace_conference_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("multi_party_peace_campaign_close_day", "Multi-party peace campaign close day",
                "Multi-party peace campaign close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "mp peace close primary"), _q("apply_focus", province_id, 0.5, "mp peace close focus")],
                {"ok": ok, "peace_score": score, "gate": gate})


PHASE4_DEPTH_DAY_IDS = [
    "occupation_revolt_board_day", "occupation_revolt_garrison_day", "occupation_revolt_suppress_day",
    "occupation_revolt_garrison_close_day", "manpower_cohort_board_day", "manpower_cohort_reserve_day",
    "manpower_cohort_mobilize_day", "manpower_cohort_reserve_close_day", "multi_party_peace_board_day",
    "multi_party_peace_wargoals_day", "multi_party_peace_settle_day", "multi_party_peace_campaign_close_day",
]
DAY_FUNCS = [
    occupation_revolt_board_day, occupation_revolt_garrison_day, occupation_revolt_suppress_day,
    occupation_revolt_garrison_close_day, manpower_cohort_board_day, manpower_cohort_reserve_day,
    manpower_cohort_mobilize_day, manpower_cohort_reserve_close_day, multi_party_peace_board_day,
    multi_party_peace_wargoals_day, multi_party_peace_settle_day, multi_party_peace_campaign_close_day,
]


def phase4_depth_integrity() -> Dict[str, Any]:
    gates = [
        occupation_revolt_garrison_integrity(),
        manpower_cohort_reserve_integrity(),
        multi_party_peace_conference_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        occupation_revolt_board_day(), manpower_cohort_board_day(), multi_party_peace_board_day(),
        occupation_revolt_garrison_close_day(), manpower_cohort_reserve_close_day(), multi_party_peace_campaign_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase4 depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next400_phase4_depth_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase4_depth_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-400 phase4 depth · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
