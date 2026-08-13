"""Next-430 Phase 7 depth (12): air theater · naval search/strike · economy conversion."""
from __future__ import annotations
from typing import Any, Dict
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from air_multi_phase_theater_product import (  # type: ignore
    build_air_multi_phase_theater_product, execute_air_theater_step, air_multi_phase_theater_integrity,
)
from naval_search_strike_product import (  # type: ignore
    build_naval_search_strike_product, execute_naval_search_step, naval_search_strike_integrity,
)
from war_economy_conversion_product import (  # type: ignore
    build_war_economy_conversion_product, execute_economy_conversion_step, war_economy_conversion_integrity,
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
        "empty": False, "integration": [aid, "next430", "phase7_depth"],
    }
    if extra:
        out.update(extra)
    return out


def air_theater_recon_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_air_theater_step("recon", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("air_theater_recon_day", "Air theater recon day",
                "Air theater recon day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "air recon primary"), _q("apply_station", province_id, 0.5, "air recon station")],
                {"air_score": score})


def air_theater_cas_gate_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_air_theater_step("cas_gate", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("air_theater_cas_gate_day", "Air theater CAS gate day",
                "Air theater CAS gate day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "air cas primary"), _q("apply_focus", province_id, 0.5, "air cas focus")],
                {"air_score": score})


def air_theater_interdiction_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_air_theater_step("interdiction", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("air_theater_interdiction_day", "Air theater interdiction day",
                "Air theater interdiction day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "air interdict primary"), _q("apply_supply", province_id, 0.5, "air interdict supply")],
                {"air_score": score})


def air_multi_phase_theater_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = air_theater_recon_day(province_id), air_theater_cas_gate_day(province_id), air_theater_interdiction_day(province_id)
    p = build_air_multi_phase_theater_product(province_id=province_id)
    gate = air_multi_phase_theater_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("air_multi_phase_theater_close_day", "Air multi-phase theater close day",
                "Air multi-phase theater close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "air close primary"), _q("apply_focus", province_id, 0.5, "air close focus")],
                {"ok": ok, "air_score": score, "gate": gate})


def naval_search_patrol_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_naval_search_step("search", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("naval_search_patrol_day", "Naval search patrol day",
                "Naval search patrol day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "naval search primary"), _q("apply_supply", province_id, 0.5, "naval search supply")],
                {"naval_score": score})


def naval_asw_escort_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_naval_search_step("asw_escort", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("naval_asw_escort_day", "Naval ASW escort day",
                "Naval ASW escort day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "naval asw primary"), _q("apply_production", province_id, 0.5, "naval asw prod")],
                {"naval_score": score})


def naval_carrier_strike_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_naval_search_step("strike", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("naval_carrier_strike_day", "Naval carrier strike day",
                "Naval carrier strike day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "naval strike primary"), _q("apply_station", province_id, 0.5, "naval strike station")],
                {"naval_score": score})


def naval_search_strike_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = naval_search_patrol_day(province_id), naval_asw_escort_day(province_id), naval_carrier_strike_day(province_id)
    p = build_naval_search_strike_product(province_id=province_id)
    gate = naval_search_strike_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("naval_search_strike_close_day", "Naval search strike close day",
                "Naval search/strike close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "naval close primary"), _q("apply_station", province_id, 0.5, "naval close station")],
                {"ok": ok, "naval_score": score, "gate": gate})


def economy_civ_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_economy_conversion_step("civ_board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("economy_civ_board_day", "Economy civ board day",
                "Economy civ board day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "econ board primary"), _q("apply_focus", province_id, 0.5, "econ board focus")],
                {"economy_score": score})


def economy_war_convert_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_economy_conversion_step("convert", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("economy_war_convert_day", "Economy war convert day",
                "Economy war convert day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "econ convert primary"), _q("apply_supply", province_id, 0.5, "econ convert supply")],
                {"economy_score": score})


def economy_stockpile_sustain_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_economy_conversion_step("sustain", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("economy_stockpile_sustain_day", "Economy stockpile sustain day",
                "Economy stockpile sustain day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "econ sustain primary"), _q("apply_production", province_id, 0.5, "econ sustain prod")],
                {"economy_score": score})


def war_economy_conversion_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = economy_civ_board_day(province_id)
    d1 = economy_war_convert_day(province_id)
    d2 = economy_stockpile_sustain_day(province_id)
    p = build_war_economy_conversion_product(province_id=province_id)
    gate = war_economy_conversion_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("war_economy_conversion_close_day", "War economy conversion close day",
                "War economy conversion close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_production", province_id, score, "econ close primary"), _q("apply_focus", province_id, 0.5, "econ close focus")],
                {"ok": ok, "economy_score": score, "gate": gate})


PHASE7_DEPTH_DAY_IDS = [
    "air_theater_recon_day", "air_theater_cas_gate_day", "air_theater_interdiction_day", "air_multi_phase_theater_close_day",
    "naval_search_patrol_day", "naval_asw_escort_day", "naval_carrier_strike_day", "naval_search_strike_close_day",
    "economy_civ_board_day", "economy_war_convert_day", "economy_stockpile_sustain_day", "war_economy_conversion_close_day",
]
DAY_FUNCS = [
    air_theater_recon_day, air_theater_cas_gate_day, air_theater_interdiction_day, air_multi_phase_theater_close_day,
    naval_search_patrol_day, naval_asw_escort_day, naval_carrier_strike_day, naval_search_strike_close_day,
    economy_civ_board_day, economy_war_convert_day, economy_stockpile_sustain_day, war_economy_conversion_close_day,
]


def phase7_depth_integrity() -> Dict[str, Any]:
    gates = [
        air_multi_phase_theater_integrity(),
        naval_search_strike_integrity(),
        war_economy_conversion_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        air_theater_recon_day(), naval_search_patrol_day(), economy_civ_board_day(),
        air_multi_phase_theater_close_day(), naval_search_strike_close_day(), war_economy_conversion_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase7 depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next430_phase7_depth_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase7_depth_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-430 phase7 depth · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
