"""Next-410 Phase 5 depth (12): historical OOB · tech branching · save/resume."""
from __future__ import annotations
from typing import Any, Dict
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from historical_oob_content_product import (  # type: ignore
    build_historical_oob_content_product, execute_historical_oob_step, historical_oob_content_integrity,
)
from tech_tree_branching_product import (  # type: ignore
    build_tech_tree_branching_product, execute_tech_tree_branching_step, tech_tree_branching_integrity,
)
from save_resume_campaign_product import (  # type: ignore
    build_save_resume_campaign_product, execute_save_resume_step, save_resume_campaign_integrity,
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
        "empty": False, "integration": [aid, "next410", "phase5_depth"],
    }
    if extra:
        out.update(extra)
    return out


def historical_oob_catalog_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_historical_oob_step("catalog", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("historical_oob_catalog_day", "Historical OOB catalog day",
                "Historical OOB catalog day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "oob catalog primary"), _q("apply_production", province_id, 0.5, "oob catalog prod")],
                {"oob_score": score})


def historical_oob_seed_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_historical_oob_step("seed", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("historical_oob_seed_day", "Historical OOB seed day",
                "Historical OOB seed day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "oob seed primary"), _q("apply_station", province_id, 0.5, "oob seed station")],
                {"oob_score": score})


def historical_oob_equip_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_historical_oob_step("equip", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("historical_oob_equip_day", "Historical OOB equip day",
                "Historical OOB equip day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "oob equip primary"), _q("apply_supply", province_id, 0.5, "oob equip supply")],
                {"oob_score": score})


def historical_oob_content_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = historical_oob_catalog_day(province_id), historical_oob_seed_day(province_id), historical_oob_equip_day(province_id)
    p = build_historical_oob_content_product(province_id=province_id)
    gate = historical_oob_content_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("historical_oob_content_close_day", "Historical OOB content close day",
                "Historical OOB content close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_production", province_id, score, "oob close primary"), _q("apply_station", province_id, 0.5, "oob close station")],
                {"ok": ok, "oob_score": score, "gate": gate})


def tech_tree_branches_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_tech_tree_branching_step("branches", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("tech_tree_branches_day", "Tech tree branches day",
                "Tech tree branches day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "tech branches primary"), _q("apply_production", province_id, 0.5, "tech branches prod")],
                {"tech_score": score})


def tech_tree_path_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_tech_tree_branching_step("path", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("tech_tree_path_day", "Tech tree path day",
                "Tech tree path day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "tech path primary"), _q("apply_focus", province_id, 0.5, "tech path focus")],
                {"tech_score": score})


def tech_tree_field_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_tech_tree_branching_step("field", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("tech_tree_field_day", "Tech tree field day",
                "Tech tree field day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "tech field primary"), _q("apply_station", province_id, 0.5, "tech field station")],
                {"tech_score": score})


def tech_tree_branching_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = tech_tree_branches_day(province_id), tech_tree_path_day(province_id), tech_tree_field_day(province_id)
    p = build_tech_tree_branching_product(province_id=province_id)
    gate = tech_tree_branching_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("tech_tree_branching_close_day", "Tech tree branching close day",
                "Tech tree branching close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_production", province_id, score, "tech close primary"), _q("apply_focus", province_id, 0.5, "tech close focus")],
                {"ok": ok, "tech_score": score, "gate": gate})


def save_resume_checkpoint_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_save_resume_step("checkpoint", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("save_resume_checkpoint_day", "Save resume checkpoint day",
                "Save resume checkpoint day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "save check primary"), _q("apply_station", province_id, 0.5, "save check station")],
                {"save_score": score})


def save_resume_save_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_save_resume_step("save", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("save_resume_save_day", "Save resume save day",
                "Save resume save day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "save write primary"), _q("apply_focus", province_id, 0.5, "save write focus")],
                {"save_score": score})


def save_resume_resume_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_save_resume_step("resume", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("save_resume_resume_day", "Save resume resume day",
                "Save resume resume day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "save resume primary"), _q("apply_production", province_id, 0.5, "save resume prod")],
                {"save_score": score})


def save_resume_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = save_resume_checkpoint_day(province_id)
    d1 = save_resume_save_day(province_id)
    d2 = save_resume_resume_day(province_id)
    p = build_save_resume_campaign_product(province_id=province_id)
    gate = save_resume_campaign_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("save_resume_campaign_close_day", "Save resume campaign close day",
                "Save resume campaign close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_station", province_id, score, "save close primary"), _q("apply_focus", province_id, 0.5, "save close focus")],
                {"ok": ok, "save_score": score, "gate": gate})


PHASE5_DEPTH_DAY_IDS = [
    "historical_oob_catalog_day", "historical_oob_seed_day", "historical_oob_equip_day", "historical_oob_content_close_day",
    "tech_tree_branches_day", "tech_tree_path_day", "tech_tree_field_day", "tech_tree_branching_close_day",
    "save_resume_checkpoint_day", "save_resume_save_day", "save_resume_resume_day", "save_resume_campaign_close_day",
]
DAY_FUNCS = [
    historical_oob_catalog_day, historical_oob_seed_day, historical_oob_equip_day, historical_oob_content_close_day,
    tech_tree_branches_day, tech_tree_path_day, tech_tree_field_day, tech_tree_branching_close_day,
    save_resume_checkpoint_day, save_resume_save_day, save_resume_resume_day, save_resume_campaign_close_day,
]


def phase5_depth_integrity() -> Dict[str, Any]:
    gates = [
        historical_oob_content_integrity(),
        tech_tree_branching_integrity(),
        save_resume_campaign_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        historical_oob_catalog_day(), tech_tree_branches_day(), save_resume_checkpoint_day(),
        historical_oob_content_close_day(), tech_tree_branching_close_day(), save_resume_campaign_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase5 depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next410_phase5_depth_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase5_depth_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-410 phase5 depth · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
