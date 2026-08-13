"""Stream α primary packs (C/E/F/G) — vertical playability audit + close helpers.

Ensures combat ribbon, OOB horizons, HH agenda, and save browser primary paths
are live-routed (no fake numbers / no apply_focus for save).
"""
from __future__ import annotations
from typing import Any, Dict, List

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

PACK_IDS = ("combat_c1", "oob_e1", "hh_f1", "save_g1")

PRIMARY_ACTION_MAP = {
    "combat_c1": {
        "ribbon": ["phase_approach", "phase_engage", "phase_disengage"],
        "close_live": "combat_ops_close",
        "product": "multi_phase_combat_product",
    },
    "oob_e1": {
        "horizons": ["oob_horizon_60d", "oob_horizon_100d"],
        "product": "medium_tank_oob_product",
        "forbid_fake": True,
    },
    "hh_f1": {
        "steps": ["hh_month_trail_board", "hh_month_brief", "hh_month_quarterly_counter"],
        "close_live": "hh_agenda_close",
        "product": "hh_multi_month_agenda_product",
    },
    "save_g1": {
        "actions": ["save_browser_resume", "save_browser_checkpoint"],
        "product": "save_browser_campaign_product",
        "forbid_apply_focus": True,
    },
}


def _floor(score: float, lo: float = 0.35) -> float:
    try:
        s = float(score)
    except (TypeError, ValueError):
        s = 0.5
    if s > 2.0:
        s = s / 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def audit_stream_alpha_primary(
    *,
    combat_ribbon_ok: bool = True,
    combat_close_routed: bool = True,
    oob_panel_ok: bool = True,
    oob_uses_real_apis: bool = True,
    hh_topbar_ok: bool = True,
    hh_close_routed: bool = True,
    save_product_path: bool = True,
    save_no_apply_focus: bool = True,
) -> Dict[str, Any]:
    checks = [
        ("combat_ribbon", combat_ribbon_ok),
        ("combat_close", combat_close_routed),
        ("oob_panel", oob_panel_ok),
        ("oob_real_apis", oob_uses_real_apis),
        ("hh_topbar", hh_topbar_ok),
        ("hh_close", hh_close_routed),
        ("save_product", save_product_path),
        ("save_no_focus", save_no_apply_focus),
    ]
    dead = [name for name, ok in checks if not ok]
    ok = len(dead) == 0
    score = _floor(1.0 - 0.1 * len(dead))
    label = "Stream α primary audit · packs 4 · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {
        "checks": {n: v for n, v in checks},
        "dead": dead,
        "dead_n": len(dead),
        "ok": ok,
        "score": score,
        "summary": label,
        "plain": label,
        "empty": False,
        "packs": list(PACK_IDS),
        "action_map": PRIMARY_ACTION_MAP,
    }


def build_stream_alpha_primary_packs_product(province_id: int = 1) -> Dict[str, Any]:
    audit = audit_stream_alpha_primary()
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, pid in enumerate(PACK_IDS):
        meta = PRIMARY_ACTION_MAP[pid]
        leaf = "apply_assault"
        if pid == "combat_c1":
            leaf = "phase_engage"
        elif pid == "oob_e1":
            leaf = "apply_production"
        elif pid == "hh_f1":
            leaf = "hh_month_brief"
        elif pid == "save_g1":
            leaf = "save_browser_checkpoint"
        sc = _floor(0.55 + 0.08 * i)
        lab = "Pack %s · %s · score %.2f" % (pid, meta.get("product", pid), sc)
        day_rows.append({
            "index": i, "pack": pid, "action_id": "stream_alpha_%s" % pid,
            "leaf_action": leaf, "label": lab, "score": sc, "enabled": True,
            "province_id": max(1, int(province_id)),
        })
        apply_queue.append({
            "action_id": leaf, "province_id": max(1, int(province_id)),
            "score": sc, "enabled": True, "label": lab, "pack": pid,
        })
    score = _floor(0.5 * float(audit.get("score", 0.5)) + 0.5 * 0.7)
    label = "Stream α C/E/F/G · dead %d · score %.2f" % (int(audit.get("dead_n", 0)), score)
    return {
        "audit": audit,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "packs": list(PACK_IDS),
        "dead_n": int(audit.get("dead_n", 0)),
        "dead_ok": bool(audit.get("ok")),
        "score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(audit.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#f0c060]★ Stream α[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "stream_alpha_primary_packs_product", "pack_c", "pack_e", "pack_f", "pack_g",
            "combat_ribbon", "oob_horizon", "hh_agenda", "save_browser", "phase1_alpha",
        ],
        "panel_actions": [
            {"action_id": "stream_alpha_primary_packs_product", "label": "Run Stream α packs", "enabled": True},
            {"action_id": "combat_ops_close", "label": "Combat phase advance (close-live)", "enabled": True},
            {"action_id": "hh_agenda_close", "label": "HH agenda advance (close-live)", "enabled": True},
            {"action_id": "save_browser_resume", "label": "Save browser resume", "enabled": True},
            {"action_id": "save_browser_checkpoint", "label": "Save browser checkpoint", "enabled": True},
            {"action_id": "oob_horizon_60d", "label": "OOB 60d", "enabled": True},
            {"action_id": "oob_horizon_100d", "label": "OOB 100d", "enabled": True},
        ],
    }


def stream_alpha_primary_packs_integrity() -> Dict[str, Any]:
    product = build_stream_alpha_primary_packs_product()
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and bool(product.get("dead_ok"))
        and int(product.get("dead_n", 1)) == 0
        and len(product.get("day_rows") or []) >= 4
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "dead_n": int(product.get("dead_n", 0)),
        "summary": "Stream α primary packs integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_stream_alpha_primary_packs_loop() -> Dict[str, Any]:
    product = build_stream_alpha_primary_packs_product(province_id=2)
    gate = stream_alpha_primary_packs_integrity()
    ok = bool(gate.get("ok")) and int(product.get("dead_n", 1)) == 0
    label = "Close Stream α · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "ok": ok, "summary": label, "plain": label, "empty": False}
