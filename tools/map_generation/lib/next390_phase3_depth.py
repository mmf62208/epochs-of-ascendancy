"""Next-390 Phase 3 depth (12): product UX · designer domain live · campaign AI multi-month."""
from __future__ import annotations
from typing import Any, Dict
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from product_ux_command_polish_product import (  # type: ignore
    build_product_ux_command_polish_product, execute_product_ux_step, product_ux_command_polish_integrity,
)
from designer_domain_live_product import (  # type: ignore
    build_designer_domain_live_product, execute_designer_domain_live_step, designer_domain_live_integrity,
)
from campaign_ai_multi_month_product import (  # type: ignore
    build_campaign_ai_multi_month_product, execute_campaign_ai_step, campaign_ai_multi_month_integrity,
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
        "empty": False, "integration": [aid, "next390", "phase3_depth"],
    }
    if extra:
        out.update(extra)
    return out


def product_ux_compact_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_product_ux_step("compact", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("product_ux_compact_day", "Product UX compact day",
                "Product UX compact day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "ux compact primary"), _q("apply_station", province_id, 0.5, "ux compact station")],
                {"ux_score": score})


def product_ux_chips_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_product_ux_step("chips", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("product_ux_chips_day", "Product UX chips day",
                "Product UX chips day · score %.2f" % score, score,
                [_q("apply_station", province_id, score, "ux chips primary"), _q("apply_focus", province_id, 0.5, "ux chips focus")],
                {"ux_score": score})


def product_ux_hotkeys_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_product_ux_step("hotkeys", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("product_ux_hotkeys_day", "Product UX hotkeys day",
                "Product UX hotkeys day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "ux hotkeys primary"), _q("apply_station", province_id, 0.5, "ux hotkeys station")],
                {"ux_score": score})


def product_ux_polish_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = product_ux_compact_day(province_id), product_ux_chips_day(province_id), product_ux_hotkeys_day(province_id)
    p = build_product_ux_command_polish_product(province_id=province_id)
    gate = product_ux_command_polish_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("product_ux_polish_close_day", "Product UX polish close day",
                "Product UX polish close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_focus", province_id, score, "ux close primary"), _q("apply_production", province_id, 0.5, "ux close prod")],
                {"ok": ok, "ux_score": score, "gate": gate})


def designer_domain_catalog_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_designer_domain_live_step("catalog", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_domain_catalog_day", "Designer domain catalog day",
                "Designer domain catalog day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "des catalog primary"), _q("apply_production", province_id, 0.5, "des catalog prod")],
                {"designer_score": score})


def designer_domain_pick_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_designer_domain_live_step("pick", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_domain_pick_day", "Designer domain pick day",
                "Designer domain pick day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "des pick primary"), _q("apply_focus", province_id, 0.5, "des pick focus")],
                {"designer_score": score})


def designer_domain_seed_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_designer_domain_live_step("seed", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("designer_domain_seed_day", "Designer domain seed day",
                "Designer domain seed day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "des seed primary"), _q("apply_station", province_id, 0.5, "des seed station")],
                {"designer_score": score})


def designer_domain_live_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0, d1, d2 = designer_domain_catalog_day(province_id), designer_domain_pick_day(province_id), designer_domain_seed_day(province_id)
    p = build_designer_domain_live_product(province_id=province_id)
    gate = designer_domain_live_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("designer_domain_live_close_day", "Designer domain live close day",
                "Designer domain live close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_production", province_id, score, "des close primary"), _q("apply_focus", province_id, 0.5, "des close focus")],
                {"ok": ok, "designer_score": score, "gate": gate})


def campaign_ai_month_board_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_campaign_ai_step("board", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("campaign_ai_month_board_day", "Campaign AI month board day",
                "Campaign AI month board day · score %.2f" % score, score,
                [_q("apply_focus", province_id, score, "cai board primary"), _q("apply_station", province_id, 0.5, "cai board station")],
                {"campaign_ai_score": score})


def campaign_ai_weekly_plan_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_campaign_ai_step("weekly", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("campaign_ai_weekly_plan_day", "Campaign AI weekly plan day",
                "Campaign AI weekly plan day · score %.2f" % score, score,
                [_q("apply_production", province_id, score, "cai weekly primary"), _q("apply_supply", province_id, 0.5, "cai weekly supply")],
                {"campaign_ai_score": score})


def campaign_ai_theater_execute_day(province_id: int = 1) -> Dict[str, Any]:
    e = execute_campaign_ai_step("execute", province_id)
    score = _floor(float(e.get("score", 0.5)))
    return _day("campaign_ai_theater_execute_day", "Campaign AI theater execute day",
                "Campaign AI theater execute day · score %.2f" % score, score,
                [_q("apply_assault", province_id, score, "cai exec primary"), _q("apply_station", province_id, 0.5, "cai exec station")],
                {"campaign_ai_score": score})


def campaign_ai_multi_month_close_day(province_id: int = 1) -> Dict[str, Any]:
    d0 = campaign_ai_month_board_day(province_id)
    d1 = campaign_ai_weekly_plan_day(province_id)
    d2 = campaign_ai_theater_execute_day(province_id)
    p = build_campaign_ai_multi_month_product(province_id=province_id)
    gate = campaign_ai_multi_month_integrity()
    avg = (float(d0.get("score", 0)) + float(d1.get("score", 0)) + float(d2.get("score", 0))) / 3.0
    ok = bool(gate.get("ok")) and not p.get("empty")
    score = _floor(0.55 * avg + 0.45 * (1.0 if ok else 0.3))
    return _day("campaign_ai_multi_month_close_day", "Campaign AI multi-month close day",
                "Campaign AI multi-month close · gates %s · score %.2f" % ("PASS" if ok else "FAIL", score), score,
                [_q("apply_assault", province_id, score, "cai close primary"), _q("apply_focus", province_id, 0.5, "cai close focus")],
                {"ok": ok, "campaign_ai_score": score, "gate": gate})


PHASE3_DEPTH_DAY_IDS = [
    "product_ux_compact_day", "product_ux_chips_day", "product_ux_hotkeys_day", "product_ux_polish_close_day",
    "designer_domain_catalog_day", "designer_domain_pick_day", "designer_domain_seed_day", "designer_domain_live_close_day",
    "campaign_ai_month_board_day", "campaign_ai_weekly_plan_day", "campaign_ai_theater_execute_day", "campaign_ai_multi_month_close_day",
]
DAY_FUNCS = [
    product_ux_compact_day, product_ux_chips_day, product_ux_hotkeys_day, product_ux_polish_close_day,
    designer_domain_catalog_day, designer_domain_pick_day, designer_domain_seed_day, designer_domain_live_close_day,
    campaign_ai_month_board_day, campaign_ai_weekly_plan_day, campaign_ai_theater_execute_day, campaign_ai_multi_month_close_day,
]


def phase3_depth_integrity() -> Dict[str, Any]:
    gates = [
        product_ux_command_polish_integrity(),
        designer_domain_live_integrity(),
        campaign_ai_multi_month_integrity(),
        execution_integrity_gate(),
        sole_mult_integrity(),
    ]
    sample = [
        product_ux_compact_day(), designer_domain_catalog_day(), campaign_ai_month_board_day(),
        product_ux_polish_close_day(), designer_domain_live_close_day(), campaign_ai_multi_month_close_day(),
    ]
    ok = all(bool(g.get("ok", g.get("integrity_ok", True))) for g in gates) and all(not s.get("empty") for s in sample)
    return {"ok": ok, "summary": "Phase3 depth integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}


def close_next390_phase3_depth_loop() -> Dict[str, Any]:
    packages = {fn.__name__: fn() for fn in DAY_FUNCS}
    non_empty = sum(1 for p in packages.values() if not p.get("empty"))
    gate = phase3_depth_integrity()
    ok = non_empty >= 12 and bool(gate.get("ok"))
    label = "Close next-390 phase3 depth · packages %d/12 · %s" % (non_empty, "PASS" if ok else "FAIL")
    return {"packages": packages, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False, "score": 1.0 if ok else 0.3}
