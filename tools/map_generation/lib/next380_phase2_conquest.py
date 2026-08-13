"""Next-380 Phase 2 conquest depth (12): occupation R/C · manpower laws · peace conference."""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from occupation_resistance_compliance_product import (  # type: ignore
    build_occupation_resistance_compliance_product, execute_occupation_resistance_step,
    occupation_resistance_compliance_integrity,
)
from manpower_laws_training_product import (  # type: ignore
    build_manpower_laws_training_product, execute_manpower_law_step, manpower_laws_training_integrity,
)
from peace_conference_settlement_product import (  # type: ignore
    build_peace_conference_settlement_product, execute_peace_conference_step,
    peace_conference_settlement_integrity,
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
        "empty": False, "integration": [aid, "next380", "phase2_conquest"],
    }
    if extra:
        out.update(extra)
    return out


def occupation_resistance_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_occupation_resistance_step("board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "occupation_resistance_board_day", "Occupation resistance board day",
        "Occupation resistance board day · score %.2f" % score, score,
        [_q("apply_station", province_id, score, "occ board primary"), _q("apply_station", province_id, 0.5, "occ board station")],
        {"occupation_score": score},
    )


def occupation_resistance_policy_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_occupation_resistance_step("policy", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "occupation_resistance_policy_day", "Occupation resistance policy day",
        "Occupation resistance policy day · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "occ policy primary"), _q("apply_station", province_id, 0.5, "occ policy station")],
        {"occupation_score": score},
    )


def occupation_resistance_tick_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_occupation_resistance_step("tick", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "occupation_resistance_tick_day", "Occupation resistance tick day",
        "Occupation resistance tick day · score %.2f" % score, score,
        [_q("apply_supply", province_id, score, "occ tick primary"), _q("apply_station", province_id, 0.5, "occ tick station")],
        {"occupation_score": score},
    )


def occupation_resistance_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = occupation_resistance_board_day(province_id)
    d1 = occupation_resistance_policy_day(province_id)
    d2 = occupation_resistance_tick_day(province_id)
    p = build_occupation_resistance_compliance_product(province_id=province_id)
    gate = occupation_resistance_compliance_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day(
        "occupation_resistance_close_day", "Occupation resistance close day",
        "Occupation resistance close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
        [_q("apply_station", province_id, score, "occ close primary"), _q("apply_focus", province_id, 0.5, "occ close focus")],
        {"ok": ok, "occupation_score": score, "gate": gate},
    )


def manpower_law_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_manpower_law_step("law", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "manpower_law_board_day", "Manpower law board day",
        "Manpower law board day · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "mp law primary"), _q("apply_station", province_id, 0.5, "mp law station")],
        {"manpower_score": score},
    )


def manpower_train_pipeline_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_manpower_law_step("train", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "manpower_train_pipeline_day", "Manpower train pipeline day",
        "Manpower train pipeline day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "mp train primary"), _q("apply_supply", province_id, 0.5, "mp train supply")],
        {"manpower_score": score},
    )


def manpower_field_trained_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_manpower_law_step("field", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "manpower_field_trained_day", "Manpower field trained day",
        "Manpower field trained day · score %.2f" % score, score,
        [_q("apply_station", province_id, score, "mp field primary"), _q("apply_assault", province_id, 0.5, "mp field assault")],
        {"manpower_score": score},
    )


def manpower_laws_training_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = manpower_law_board_day(province_id)
    d1 = manpower_train_pipeline_day(province_id)
    d2 = manpower_field_trained_day(province_id)
    p = build_manpower_laws_training_product(province_id=province_id)
    gate = manpower_laws_training_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day(
        "manpower_laws_training_close_day", "Manpower laws training close day",
        "Manpower laws training close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
        [_q("apply_focus", province_id, score, "mp close primary"), _q("apply_station", province_id, 0.5, "mp close station")],
        {"ok": ok, "manpower_score": score, "gate": gate},
    )


def peace_conference_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_peace_conference_step("board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "peace_conference_board_day", "Peace conference board day",
        "Peace conference board day · score %.2f" % score, score,
        [_q("apply_focus", province_id, score, "peace board primary"), _q("apply_station", province_id, 0.5, "peace board station")],
        {"peace_score": score},
    )


def peace_conference_demands_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_peace_conference_step("demands", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "peace_conference_demands_day", "Peace conference demands day",
        "Peace conference demands day · score %.2f" % score, score,
        [_q("apply_production", province_id, score, "peace demands primary"), _q("apply_focus", province_id, 0.5, "peace demands focus")],
        {"peace_score": score},
    )


def peace_conference_settle_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_peace_conference_step("settle", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day(
        "peace_conference_settle_day", "Peace conference settle day",
        "Peace conference settle day · score %.2f" % score, score,
        [_q("apply_assault", province_id, score, "peace settle primary"), _q("apply_station", province_id, 0.5, "peace settle station")],
        {"peace_score": score},
    )


def peace_conference_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = peace_conference_board_day(province_id)
    d1 = peace_conference_demands_day(province_id)
    d2 = peace_conference_settle_day(province_id)
    p = build_peace_conference_settlement_product(province_id=province_id)
    gate = peace_conference_settlement_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day(
        "peace_conference_campaign_close_day", "Peace conference campaign close day",
        "Peace conference campaign close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
        [_q("apply_assault", province_id, score, "peace close primary"), _q("apply_focus", province_id, 0.5, "peace close focus")],
        {"ok": ok, "peace_score": score, "gate": gate},
    )


PHASE2_CONQUEST_DAY_IDS = [
    "occupation_resistance_board_day", "occupation_resistance_policy_day", "occupation_resistance_tick_day",
    "occupation_resistance_close_day", "manpower_law_board_day", "manpower_train_pipeline_day",
    "manpower_field_trained_day", "manpower_laws_training_close_day", "peace_conference_board_day",
    "peace_conference_demands_day", "peace_conference_settle_day", "peace_conference_campaign_close_day",
]
DAY_FUNCS = [
    occupation_resistance_board_day, occupation_resistance_policy_day, occupation_resistance_tick_day,
    occupation_resistance_close_day, manpower_law_board_day, manpower_train_pipeline_day,
    manpower_field_trained_day, manpower_laws_training_close_day, peace_conference_board_day,
    peace_conference_demands_day, peace_conference_settle_day, peace_conference_campaign_close_day,
]


def phase2_conquest_depth_integrity() -> Dict[str, Any]:
    gates = [
        occupation_resistance_compliance_integrity(),
        manpower_laws_training_integrity(),
        peace_conference_settlement_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        occupation_resistance_board_day(), manpower_law_board_day(), peace_conference_board_day(),
        occupation_resistance_close_day(), manpower_laws_training_close_day(), peace_conference_campaign_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase2 conquest depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next380_phase2_conquest_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase2_conquest_depth_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-380 phase2 conquest · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
