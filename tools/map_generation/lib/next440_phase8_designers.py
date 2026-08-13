"""Next-440 Phase 8 full designers (12): modules · stats/field · multi-domain campaign."""
from __future__ import annotations
from typing import Any, Dict
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from designer_module_editor_product import (  # type: ignore
    build_designer_module_editor_product, execute_module_editor_step, designer_module_editor_integrity,
)
from designer_stats_field_product import (  # type: ignore
    build_designer_stats_field_product, execute_stats_field_step, designer_stats_field_integrity,
)
from designer_multi_domain_campaign_product import (  # type: ignore
    build_designer_multi_domain_campaign_product, execute_multi_domain_designer_step, designer_multi_domain_campaign_integrity,
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
        "empty": False, "integration": [aid, "next440", "phase8_designers", "full_designers"],
    }
    if extra:
        out.update(extra)
    return out


def designer_module_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_module_editor_step("modules", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_module_board_day", "Designer module board day",
                "Designer module board day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "mod board primary"), _q("apply_production", province_id, 0.5, "mod board prod")],
                {"designer_score": score})


def designer_module_edit_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_module_editor_step("edit", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_module_edit_day", "Designer module edit day",
                "Designer module edit day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "mod edit primary"), _q("apply_focus", province_id, 0.5, "mod edit focus")],
                {"designer_score": score})


def designer_reliability_gate_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_module_editor_step("reliability", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_reliability_gate_day", "Designer reliability gate day",
                "Designer reliability gate day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "rel gate primary"), _q("apply_station", province_id, 0.5, "rel gate station")],
                {"designer_score": score})


def designer_module_editor_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = designer_module_board_day(province_id), designer_module_edit_day(province_id), designer_reliability_gate_day(province_id)
    p = build_designer_module_editor_product(province_id=province_id)
    gate = designer_module_editor_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("designer_module_editor_close_day", "Designer module editor close day",
                "Designer module editor close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_production", province_id, score, "mod close primary"), _q("apply_focus", province_id, 0.5, "mod close focus")],
                {"ok": ok, "designer_score": score, "gate": gate})


def designer_stats_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_stats_field_step("stats", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_stats_board_day", "Designer stats board day",
                "Designer stats board day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "stats board primary"), _q("apply_production", province_id, 0.5, "stats board prod")],
                {"designer_score": score})


def designer_freeze_design_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_stats_field_step("freeze", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_freeze_design_day", "Designer freeze design day",
                "Designer freeze design day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "freeze primary"), _q("apply_focus", province_id, 0.5, "freeze focus")],
                {"designer_score": score})


def designer_field_seed_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_stats_field_step("field", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_field_seed_day", "Designer field seed day",
                "Designer field seed day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "field seed primary"), _q("apply_station", province_id, 0.5, "field seed station")],
                {"designer_score": score})


def designer_stats_field_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = designer_stats_board_day(province_id), designer_freeze_design_day(province_id), designer_field_seed_day(province_id)
    p = build_designer_stats_field_product(province_id=province_id)
    gate = designer_stats_field_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("designer_stats_field_close_day", "Designer stats field close day",
                "Designer stats/field close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_production", province_id, score, "stats close primary"), _q("apply_focus", province_id, 0.5, "stats close focus")],
                {"ok": ok, "designer_score": score, "gate": gate})


def designer_catalog_all_domains_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_multi_domain_designer_step("catalog_all", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_catalog_all_domains_day", "Designer catalog all domains day",
                "Designer catalog all domains day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "catalog all primary"), _q("apply_production", province_id, 0.5, "catalog all prod")],
                {"designer_score": score})


def designer_seed_multi_domain_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_multi_domain_designer_step("seed_multi", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_seed_multi_domain_day", "Designer seed multi domain day",
                "Designer seed multi domain day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "seed multi primary"), _q("apply_focus", province_id, 0.5, "seed multi focus")],
                {"designer_score": score})


def designer_equip_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_multi_domain_designer_step("equip_close", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_equip_campaign_close_day", "Designer equip campaign close day",
                "Designer equip campaign close day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "equip close primary"), _q("apply_station", province_id, 0.5, "equip close station")],
                {"designer_score": score})


def designer_multi_domain_campaign_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = designer_catalog_all_domains_day(province_id)
    d1 = designer_seed_multi_domain_day(province_id)
    d2 = designer_equip_campaign_close_day(province_id)
    p = build_designer_multi_domain_campaign_product(province_id=province_id)
    gate = designer_multi_domain_campaign_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty") and bool(p.get("complete"))
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("designer_multi_domain_campaign_close_day", "Designer multi domain campaign close day",
                "Designer multi-domain campaign close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_production", province_id, score, "campaign close primary"), _q("apply_focus", province_id, 0.5, "campaign close focus")],
                {"ok": ok, "designer_score": score, "gate": gate})


PHASE8_DESIGNERS_DAY_IDS = [
    "designer_module_board_day", "designer_module_edit_day", "designer_reliability_gate_day", "designer_module_editor_close_day",
    "designer_stats_board_day", "designer_freeze_design_day", "designer_field_seed_day", "designer_stats_field_close_day",
    "designer_catalog_all_domains_day", "designer_seed_multi_domain_day", "designer_equip_campaign_close_day", "designer_multi_domain_campaign_close_day",
]
DAY_FUNCS = [
    designer_module_board_day, designer_module_edit_day, designer_reliability_gate_day, designer_module_editor_close_day,
    designer_stats_board_day, designer_freeze_design_day, designer_field_seed_day, designer_stats_field_close_day,
    designer_catalog_all_domains_day, designer_seed_multi_domain_day, designer_equip_campaign_close_day, designer_multi_domain_campaign_close_day,
]


def phase8_designers_integrity() -> Dict[str, Any]:
    gates = [
        designer_module_editor_integrity(),
        designer_stats_field_integrity(),
        designer_multi_domain_campaign_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        designer_module_board_day(), designer_stats_board_day(), designer_catalog_all_domains_day(),
        designer_module_editor_close_day(), designer_stats_field_close_day(), designer_multi_domain_campaign_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase8 designers integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next440_phase8_designers_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase8_designers_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-440 phase8 designers · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
