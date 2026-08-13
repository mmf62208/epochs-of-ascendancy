"""Medium-tank OOB / multi-month equip product (major #3).

Proves multi-month medium line honesty: horizon windows, factory risk,
production priority, equip projection, reinforce-from-stockpile path.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional

from order_panel_ux_depth import medium_horizon_equip_plan  # type: ignore
from live_mutation import production_priority_mutation  # type: ignore
from gameplay_loops import oob_factory_risk_loop, sole_mult_integrity  # type: ignore
from campaign_execution import production_order_resolve, execution_integrity_gate  # type: ignore
from force_readiness_day import force_readiness_day  # type: ignore
from campaign_cohesion import production_campaign_risk  # type: ignore


HORIZON_STEPS = (60, 80, 100)

_STEP_META = {
    60: {
        "action_id": "oob_horizon_60d",
        "leaf": "apply_production",
        "label": "60d horizon — seed/priority medium line",
    },
    80: {
        "action_id": "oob_horizon_80d",
        "leaf": "apply_production",
        "label": "80d horizon — factory risk + output",
    },
    100: {
        "action_id": "oob_horizon_100d",
        "leaf": "apply_supply",
        "label": "100d horizon — equip/stockpile prove",
    },
}


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.7,
        "precip": 0.3,
        "precip_intensity": 0.3,
        "ground_state": "mud",
        "wind": 0.25,
        "temperature_c": 8.0,
    }


def recommend_oob_horizon_step(
    will_complete_60: bool,
    will_complete_100: bool,
    *,
    tank_progress: float = 0.15,
    logistics: float = 0.5,
) -> Dict[str, Any]:
    prog = _norm(tank_progress)
    logi = _norm(logistics)
    if not will_complete_60 and prog < 0.4:
        step = 60
        reason = "line early — prioritize factories / seed"
    elif will_complete_60 and not will_complete_100:
        step = 80
        reason = "mid window — manage factory risk"
    elif will_complete_100 and logi < 0.45:
        step = 100
        reason = "completion window — stockpile/equip path"
    elif will_complete_100:
        step = 100
        reason = "prove equip at 100d horizon"
    else:
        step = 80
        reason = "sustain medium line"
    meta = _STEP_META[step]
    return {
        "step": step,
        "horizon_days": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %dd · %s" % (step, reason),
        "empty": False,
    }


def build_medium_tank_oob_product(
    province_id: int = 1,
    *,
    tank_line_progress: float = 0.15,
    tank_stock: float = 0.0,
    infantry_stock: float = 5.0,
    factories: int = 14,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Multi-horizon medium-tank OOB product for live industry panel."""
    wx = dict(weather or _wx())
    progress = max(0.0, min(1.0, float(tank_line_progress)))
    equip_rows: List[Dict[str, Any]] = []
    for days in HORIZON_STEPS:
        eq = medium_horizon_equip_plan(
            infantry_stock=float(infantry_stock),
            tank_stock=float(tank_stock),
            tank_line_progress=progress,
            days_horizon=int(days),
            factories=int(factories),
        )
        equip_rows.append(
            {
                "horizon_days": days,
                "equip": eq,
                "will_complete_tank": bool(eq.get("will_complete_tank", False)),
                "projected_progress": float(eq.get("projected_progress", 0.0) or 0.0),
                "score": float(eq.get("score", 0.55) or 0.55),
                "summary": str(eq.get("summary", "")),
            }
        )

    loop = oob_factory_risk_loop(weather=wx, base_output=1.0)
    mut = production_priority_mutation(weather=wx, base_output=1.0, line_id="medium_tank")
    order = production_order_resolve(weather=wx, base_output=1.0, line_id="medium_tank")
    try:
        pcr = production_campaign_risk(weather=wx)
    except TypeError:
        pcr = production_campaign_risk(wx)  # type: ignore
    ready = force_readiness_day(weather=wx, province_id=province_id)

    logistics = float(loop.get("effective_output", 0.7) or 0.7)
    prod_score = float(mut.get("score", order.get("score", 0.55)) or 0.55)
    equip100 = equip_rows[-1] if equip_rows else {}
    equip60 = equip_rows[0] if equip_rows else {}
    complete100 = bool(equip100.get("will_complete_tank", False))
    complete60 = bool(equip60.get("will_complete_tank", False))

    score = _floor(
        0.3 * float(equip100.get("score", 0.55))
        + 0.25 * prod_score
        + 0.25 * logistics
        + 0.1 * (0.8 if complete100 else 0.35)
        + 0.1 * float(ready.get("score", 0.5) or 0.5)
    )

    rec = recommend_oob_horizon_step(
        complete60,
        complete100,
        tank_progress=progress,
        logistics=logistics,
    )

    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for row in equip_rows:
        days = int(row["horizon_days"])
        meta = _STEP_META[days]
        recommended = days == int(rec.get("step", 100))
        label = str(meta["label"])
        if recommended:
            label = "★ " + label
        will = "complete" if row.get("will_complete_tank") else "incomplete"
        label = "%s · %s · score %.2f" % (label, will, float(row.get("score", 0.55)))
        r = {
            "horizon_days": days,
            "action_id": meta["action_id"],
            "leaf_action": meta["leaf"],
            "label": label,
            "score": float(row.get("score", 0.55)),
            "will_complete_tank": bool(row.get("will_complete_tank")),
            "enabled": True,
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
        }
        day_rows.append(r)
        apply_queue.append(
            {
                "action_id": meta["leaf"],
                "province_id": max(1, int(province_id)),
                "score": float(row.get("score", 0.55)),
                "enabled": True,
                "label": label,
                "horizon_days": days,
                "product_action": meta["action_id"],
            }
        )

    # Prove-path action: reinforce from stockpile when complete
    if complete100:
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": max(1, int(province_id)),
                "score": score,
                "enabled": True,
                "label": "Equip formations from stockpile (100d prove)",
                "product_action": "oob_equip_prove",
            }
        )

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "medium_tank_oob_product",
            "label": "Run medium-tank OOB product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "oob_horizon_100d")),
            "label": "Recommended: %dd" % int(rec.get("step", 100)),
            "enabled": True,
        },
    ]
    for r in day_rows:
        actions.append(
            {
                "action_id": r["action_id"],
                "label": r["label"],
                "enabled": True,
                "horizon_days": r["horizon_days"],
            }
        )

    label = (
        "Medium-tank OOB · 60/80/100d · progress %.0f%% · complete100 %s · factories %d · score %.2f"
        % (progress * 100.0, "yes" if complete100 else "no", int(factories), score)
    )
    plain_lines = [label, str(rec.get("summary", ""))]
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))
    plain_lines.append(str(equip100.get("summary", "")))

    return {
        "equip_rows": equip_rows,
        "horizon_rows": day_rows,
        "day_rows": day_rows,
        "loop": loop,
        "mutation": mut,
        "order": order,
        "campaign_risk": pcr,
        "readiness": ready,
        "recommendation": rec,
        "will_complete_60d": complete60,
        "will_complete_100d": complete100,
        "tank_line_progress": progress,
        "tank_stock": float(tank_stock),
        "factories": int(factories),
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "oob_score": score,
        "province_id": max(1, int(province_id)),
        "apply_ready": complete100 or progress >= 0.5,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#e8c060]🏭 Medium-tank OOB[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "medium_tank_oob_product",
            "oob_horizon_60d",
            "oob_horizon_80d",
            "oob_horizon_100d",
            "major_3",
        ],
    }


def execute_oob_horizon_step(
    horizon_days: int = 100,
    province_id: int = 1,
    *,
    tank_line_progress: float = 0.15,
    factories: int = 14,
) -> Dict[str, Any]:
    days = int(horizon_days)
    if days not in _STEP_META:
        # allow action ids
        for k, meta in _STEP_META.items():
            if str(horizon_days) == meta["action_id"] or str(horizon_days).endswith(str(k)):
                days = k
                break
        else:
            days = 100
    meta = _STEP_META[days]
    product = build_medium_tank_oob_product(
        province_id,
        tank_line_progress=tank_line_progress,
        factories=factories,
    )
    row = next(
        (r for r in (product.get("day_rows") or []) if int(r.get("horizon_days", 0)) == days),
        None,
    )
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q = [
        {
            "action_id": meta["leaf"],
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": True,
            "label": meta["label"],
            "horizon_days": days,
            "product_action": meta["action_id"],
        }
    ]
    label = "Execute OOB %dd · leaf %s · complete %s · #%d" % (
        days,
        meta["leaf"],
        "yes" if (row or {}).get("will_complete_tank") else "no",
        max(1, int(province_id)),
    )
    return {
        "horizon_days": days,
        "leaf_action": meta["leaf"],
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "will_complete_tank": bool((row or {}).get("will_complete_tank")),
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8c060]🏭 OOB %dd[/color] [color=#8899aa]%s[/color]" % (days, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_oob_horizon", str(days), meta["leaf"]],
    }


def medium_tank_oob_product_integrity() -> Dict[str, Any]:
    product = build_medium_tank_oob_product(1, tank_line_progress=0.15, factories=14)
    early = build_medium_tank_oob_product(1, tank_line_progress=0.05, factories=8)
    steps = [execute_oob_horizon_step(d, 1) for d in HORIZON_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and len(product.get("day_rows") or []) >= 3
        and bool(product.get("will_complete_100d"))
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and float(product.get("score", 0)) >= float(early.get("score", 0)) * 0.9
    )
    return {
        "ok": ok,
        "complete_100d": bool(product.get("will_complete_100d")),
        "complete_60d": bool(product.get("will_complete_60d")),
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Medium-tank OOB product integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_medium_tank_oob_product_loop() -> Dict[str, Any]:
    product = build_medium_tank_oob_product(1, tank_line_progress=0.2, factories=16)
    gate = medium_tank_oob_product_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = (
        "Close medium-tank OOB product · horizons 3 · complete100 %s · queue %d · %s"
        % (
            "yes" if product.get("will_complete_100d") else "no",
            len(product.get("apply_queue") or []),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8c060]✓ Medium-tank OOB product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
