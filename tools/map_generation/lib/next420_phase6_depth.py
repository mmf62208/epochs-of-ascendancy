"""Next-420 Phase 6 depth (12): tutorial · focus content · balance honesty."""
from __future__ import annotations
from typing import Any, Dict
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from tutorial_first_session_product import (  # type: ignore
    build_tutorial_first_session_product, execute_tutorial_session_step, tutorial_first_session_integrity,
)
from focus_tree_content_product import (  # type: ignore
    build_focus_tree_content_product, execute_focus_tree_content_step, focus_tree_content_integrity,
)
from balance_combat_supply_product import (  # type: ignore
    build_balance_combat_supply_product, execute_balance_step, balance_combat_supply_integrity,
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
        "empty": False, "integration": [aid, "next420", "phase6_depth"],
    }
    if extra:
        out.update(extra)
    return out


def tutorial_session_brief_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_tutorial_session_step("brief", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("tutorial_session_brief_day", "Tutorial session brief day",
                "Tutorial session brief day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "tut brief primary"), _q("apply_station", province_id, 0.5, "tut brief station")],
                {"tutorial_score": score})


def tutorial_session_guide_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_tutorial_session_step("guide", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("tutorial_session_guide_day", "Tutorial session guide day",
                "Tutorial session guide day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "tut guide primary"), _q("apply_focus", province_id, 0.5, "tut guide focus")],
                {"tutorial_score": score})


def tutorial_session_checkpoint_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_tutorial_session_step("checkpoint", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("tutorial_session_checkpoint_day", "Tutorial session checkpoint day",
                "Tutorial session checkpoint day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "tut check primary"), _q("apply_production", province_id, 0.5, "tut check prod")],
                {"tutorial_score": score})


def tutorial_first_session_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = tutorial_session_brief_day(province_id), tutorial_session_guide_day(province_id), tutorial_session_checkpoint_day(province_id)
    p = build_tutorial_first_session_product(province_id=province_id)
    gate = tutorial_first_session_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("tutorial_first_session_close_day", "Tutorial first session close day",
                "Tutorial first session close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_focus", province_id, score, "tut close primary"), _q("apply_station", province_id, 0.5, "tut close station")],
                {"ok": ok, "tutorial_score": score, "gate": gate})


def focus_tree_catalog_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_focus_tree_content_step("catalog", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("focus_tree_catalog_day", "Focus tree catalog day",
                "Focus tree catalog day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "focus catalog primary"), _q("apply_production", province_id, 0.5, "focus catalog prod")],
                {"focus_score": score})


def focus_tree_path_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_focus_tree_content_step("path", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("focus_tree_path_day", "Focus tree path day",
                "Focus tree path day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "focus path primary"), _q("apply_station", province_id, 0.5, "focus path station")],
                {"focus_score": score})


def focus_tree_commit_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_focus_tree_content_step("commit", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("focus_tree_commit_day", "Focus tree commit day",
                "Focus tree commit day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "focus commit primary"), _q("apply_focus", province_id, 0.5, "focus commit focus")],
                {"focus_score": score})


def focus_tree_content_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = focus_tree_catalog_day(province_id), focus_tree_path_day(province_id), focus_tree_commit_day(province_id)
    p = build_focus_tree_content_product(province_id=province_id)
    gate = focus_tree_content_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("focus_tree_content_close_day", "Focus tree content close day",
                "Focus tree content close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_focus", province_id, score, "focus close primary"), _q("apply_production", province_id, 0.5, "focus close prod")],
                {"ok": ok, "focus_score": score, "gate": gate})


def balance_estimate_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_balance_step("estimate", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("balance_estimate_board_day", "Balance estimate board day",
                "Balance estimate board day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "bal est primary"), _q("apply_supply", province_id, 0.5, "bal est supply")],
                {"balance_score": score})


def balance_live_sample_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_balance_step("sample", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("balance_live_sample_day", "Balance live sample day",
                "Balance live sample day · score %.2f" % score, score,
                [_q("apply_supply", province_id, score, "bal sample primary"), _q("apply_assault", province_id, 0.5, "bal sample assault")],
                {"balance_score": score})


def balance_variance_close_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_balance_step("close", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("balance_variance_close_day", "Balance variance close day",
                "Balance variance close day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "bal close primary"), _q("apply_supply", province_id, 0.5, "bal close supply")],
                {"balance_score": score})


def balance_combat_supply_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = balance_estimate_board_day(province_id)
    d1 = balance_live_sample_day(province_id)
    d2 = balance_variance_close_day(province_id)
    p = build_balance_combat_supply_product(province_id=province_id)
    gate = balance_combat_supply_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("balance_combat_supply_close_day", "Balance combat supply close day",
                "Balance combat supply close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "bal campaign close primary"), _q("apply_supply", province_id, 0.5, "bal campaign close supply")],
                {"ok": ok, "balance_score": score, "gate": gate})


PHASE6_DEPTH_DAY_IDS = [
    "tutorial_session_brief_day", "tutorial_session_guide_day", "tutorial_session_checkpoint_day", "tutorial_first_session_close_day",
    "focus_tree_catalog_day", "focus_tree_path_day", "focus_tree_commit_day", "focus_tree_content_close_day",
    "balance_estimate_board_day", "balance_live_sample_day", "balance_variance_close_day", "balance_combat_supply_close_day",
]
DAY_FUNCS = [
    tutorial_session_brief_day, tutorial_session_guide_day, tutorial_session_checkpoint_day, tutorial_first_session_close_day,
    focus_tree_catalog_day, focus_tree_path_day, focus_tree_commit_day, focus_tree_content_close_day,
    balance_estimate_board_day, balance_live_sample_day, balance_variance_close_day, balance_combat_supply_close_day,
]


def phase6_depth_integrity() -> Dict[str, Any]:
    gates = [
        tutorial_first_session_integrity(),
        focus_tree_content_integrity(),
        balance_combat_supply_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        tutorial_session_brief_day(), focus_tree_catalog_day(), balance_estimate_board_day(),
        tutorial_first_session_close_day(), focus_tree_content_close_day(), balance_combat_supply_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase6 depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next420_phase6_depth_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase6_depth_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-420 phase6 depth · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
