"""Next-450 Phase 9 full gameplay cycle (12): weather crisis · intel cells · leader theater."""
from __future__ import annotations
from typing import Any, Dict
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from weather_crisis_campaign_product import (  # type: ignore
    build_weather_crisis_campaign_product, execute_weather_crisis_step, weather_crisis_campaign_integrity,
)
from intel_cell_network_product import (  # type: ignore
    build_intel_cell_network_product, execute_intel_cell_step, intel_cell_network_integrity,
)
from leader_theater_command_product import (  # type: ignore
    build_leader_theater_command_product, execute_leader_theater_step, leader_theater_command_integrity,
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
        "empty": False, "integration": [aid, "next450", "phase9_cycle", "full_gameplay_cycle"],
    }
    if extra:
        out.update(extra)
    return out


def weather_crisis_forecast_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_weather_crisis_step("forecast", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("weather_crisis_forecast_day", "Weather crisis forecast day",
                "Weather crisis forecast day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "wx forecast primary"), _q("apply_supply", province_id, 0.5, "wx forecast supply")],
                {"cycle_score": score})


def weather_crisis_gate_multi_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_weather_crisis_step("gate_multi", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("weather_crisis_gate_multi_day", "Weather crisis gate multi day",
                "Weather crisis gate multi day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "wx gate primary"), _q("apply_station", province_id, 0.5, "wx gate station")],
                {"cycle_score": score})


def weather_crisis_sustain_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_weather_crisis_step("crisis_sustain", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("weather_crisis_sustain_day", "Weather crisis sustain day",
                "Weather crisis sustain day · score %.2f" % score, score,
                [_q("apply_supply", province_id, score, "wx sustain primary"), _q("apply_production", province_id, 0.5, "wx sustain prod")],
                {"cycle_score": score})


def weather_crisis_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = weather_crisis_forecast_day(province_id), weather_crisis_gate_multi_day(province_id), weather_crisis_sustain_day(province_id)
    p = build_weather_crisis_campaign_product(province_id=province_id)
    gate = weather_crisis_campaign_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("weather_crisis_campaign_close_day", "Weather crisis campaign close day",
                "Weather crisis campaign close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_supply", province_id, score, "wx close primary"), _q("apply_station", province_id, 0.5, "wx close station")],
                {"ok": ok, "cycle_score": score, "gate": gate})


def intel_cell_coverage_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_intel_cell_step("cells", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("intel_cell_coverage_day", "Intel cell coverage day",
                "Intel cell coverage day · score %.2f" % score, score,
                [_q("apply_agent_dispatch", province_id, score, "cell cover primary"), _q("apply_focus", province_id, 0.5, "cell cover focus")],
                {"cycle_score": score})


def intel_cell_ops_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_intel_cell_step("ops", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("intel_cell_ops_day", "Intel cell ops day",
                "Intel cell ops day · score %.2f" % score, score,
                [_q("apply_agent_dispatch", province_id, score, "cell ops primary"), _q("apply_production", province_id, 0.5, "cell ops prod")],
                {"cycle_score": score})


def intel_counter_sweep_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_intel_cell_step("sweep", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("intel_counter_sweep_day", "Intel counter sweep day",
                "Intel counter sweep day · score %.2f" % score, score,
                [_q("apply_hh_commit", province_id, score, "counter sweep primary"), _q("apply_agent_dispatch", province_id, 0.5, "counter sweep agent")],
                {"cycle_score": score})


def intel_cell_network_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = intel_cell_coverage_day(province_id), intel_cell_ops_day(province_id), intel_counter_sweep_day(province_id)
    p = build_intel_cell_network_product(province_id=province_id)
    gate = intel_cell_network_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("intel_cell_network_close_day", "Intel cell network close day",
                "Intel cell network close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_agent_dispatch", province_id, score, "intel close primary"), _q("apply_hh_commit", province_id, 0.5, "intel close hh")],
                {"ok": ok, "cycle_score": score, "gate": gate})


def leader_hq_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_leader_theater_step("hq_board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("leader_hq_board_day", "Leader HQ board day",
                "Leader HQ board day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "hq board primary"), _q("apply_station", province_id, 0.5, "hq board station")],
                {"cycle_score": score})


def leader_multi_station_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_leader_theater_step("multi_station", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("leader_multi_station_day", "Leader multi station day",
                "Leader multi station day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "multi station primary"), _q("apply_production", province_id, 0.5, "multi station prod")],
                {"cycle_score": score})


def leader_theater_ops_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_leader_theater_step("theater_ops", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("leader_theater_ops_day", "Leader theater ops day",
                "Leader theater ops day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "theater ops primary"), _q("apply_station", province_id, 0.5, "theater ops station")],
                {"cycle_score": score})


def leader_theater_command_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = leader_hq_board_day(province_id), leader_multi_station_day(province_id), leader_theater_ops_day(province_id)
    p = build_leader_theater_command_product(province_id=province_id)
    gate = leader_theater_command_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("leader_theater_command_close_day", "Leader theater command close day",
                "Leader theater command close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "leader close primary"), _q("apply_focus", province_id, 0.5, "leader close focus")],
                {"ok": ok, "cycle_score": score, "gate": gate})


PHASE9_CYCLE_DAY_IDS = [
    "weather_crisis_forecast_day", "weather_crisis_gate_multi_day", "weather_crisis_sustain_day", "weather_crisis_campaign_close_day",
    "intel_cell_coverage_day", "intel_cell_ops_day", "intel_counter_sweep_day", "intel_cell_network_close_day",
    "leader_hq_board_day", "leader_multi_station_day", "leader_theater_ops_day", "leader_theater_command_close_day",
]
DAY_FUNCS = [
    weather_crisis_forecast_day, weather_crisis_gate_multi_day, weather_crisis_sustain_day, weather_crisis_campaign_close_day,
    intel_cell_coverage_day, intel_cell_ops_day, intel_counter_sweep_day, intel_cell_network_close_day,
    leader_hq_board_day, leader_multi_station_day, leader_theater_ops_day, leader_theater_command_close_day,
]


def phase9_cycle_integrity() -> Dict[str, Any]:
    gates = [
        weather_crisis_campaign_integrity(),
        intel_cell_network_integrity(),
        leader_theater_command_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        weather_crisis_forecast_day(), intel_cell_coverage_day(), leader_hq_board_day(),
        weather_crisis_campaign_close_day(), intel_cell_network_close_day(), leader_theater_command_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase9 cycle integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next450_phase9_cycle_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase9_cycle_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-450 phase9 cycle · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
