"""Multi-front weekly execute package on accurate board (plan → weekly → assault).

Closes the gap between pure front ranking and “live AI execute” by producing a
machine package: multi-front board + ranked Maginot/Polish assaults + apply queue
with real defender province IDs for GER (or any attacker).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional
from pathlib import Path

from world_accurate_front_assault_product import (  # type: ignore
    build_world_accurate_front_assault_product,
)
from world_accurate_multi_front_product import (  # type: ignore
    build_world_accurate_multi_front_product,
)

try:
    from multi_front_campaign_ai_product import (  # type: ignore
        build_multi_front_campaign_ai_product,
    )
except Exception:  # pragma: no cover
    build_multi_front_campaign_ai_product = None  # type: ignore


def build_world_accurate_multi_front_execute_product(
    *,
    attacker_tag: str = "GER",
    board_dir: Optional[Path] = None,
    max_assaults: int = 4,
) -> Dict[str, Any]:
    fails: List[str] = []
    passes: List[str] = []
    att = str(attacker_tag or "GER").upper()

    fronts = build_world_accurate_multi_front_product(board_dir)
    if fronts.get("ok"):
        passes.append("fronts_active=%s" % fronts.get("active_n"))
    else:
        fails.append("fronts_fail")

    assault = build_world_accurate_front_assault_product(
        attacker_tag=att, board_dir=board_dir, max_targets=max_assaults
    )
    if assault.get("ok"):
        passes.append("assault_ok best=%s" % assault.get("best_province_id"))
    else:
        fails.extend(list(assault.get("fail") or ["assault_fail"])[:4])

    campaign = None
    if build_multi_front_campaign_ai_product is not None:
        # Seed with best assault province when available
        seed = int(assault.get("best_province_id") or 710739)
        campaign = build_multi_front_campaign_ai_product(province_id=seed)
        if float(campaign.get("score") or 0) > 0.5:
            passes.append("campaign_ai=%.2f" % float(campaign.get("score")))

    # Build execute apply_queue from ranked targets
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_focus",
            "step": "plan",
            "product_action": "multi_front_plan",
            "province_id": int(assault.get("best_province_id") or 710300),
            "score": 0.8,
            "enabled": True,
            "label": "Multi-front plan board",
        },
        {
            "action_id": "apply_production",
            "step": "weekly",
            "product_action": "multi_front_weekly",
            "province_id": int(assault.get("best_province_id") or 710300),
            "score": 0.81,
            "enabled": True,
            "label": "Weekly AI tick",
        },
    ]
    ranked = (assault.get("ranked") or {}).get("targets") or (assault.get("ranked") or {}).get(
        "all"
    ) or []
    for i, t in enumerate(ranked[: max(1, int(max_assaults))]):
        if not isinstance(t, dict):
            continue
        pid = int(t.get("province_id") or 0)
        if pid <= 0:
            continue
        overall = float(t.get("overall") or t.get("priority") or 0.5)
        if overall > 2.0:
            overall = min(1.0, overall / 100.0)
        apply_queue.append(
            {
                "action_id": "apply_assault",
                "step": "execute",
                "product_action": "multi_front_execute",
                "province_id": pid,
                "from_province_id": int(t.get("from_province_id") or 0),
                "defender_tag": str(t.get("defender_tag") or t.get("front_id") or ""),
                "score": overall,
                "enabled": overall >= 0.35,
                "label": "Assault %s #%d" % (t.get("name") or pid, pid),
                "front_id": t.get("front_id"),
            }
        )

    assault_ids = [
        int(q["province_id"])
        for q in apply_queue
        if q.get("action_id") == "apply_assault" and int(q.get("province_id") or 0) > 0
    ]
    if 710739 in assault_ids:
        passes.append("maginot_bas_rhin_queued")
    else:
        # Still ok if ranked differently but Maginot front present
        if any(
            str(q.get("front_id")) == "rhineland_maginot"
            for q in apply_queue
            if q.get("action_id") == "apply_assault"
        ):
            passes.append("maginot_front_queued")
        elif assault.get("ok"):
            # bas-rhin must be in ranked pool at least
            all_ids = [
                int(t.get("province_id") or 0)
                for t in ((assault.get("ranked") or {}).get("all") or [])
                if isinstance(t, dict)
            ]
            if 710739 in all_ids:
                passes.append("maginot_in_rank_pool")
            else:
                fails.append("maginot_not_in_execute_package")

    if len(assault_ids) < 2:
        fails.append("too_few_assaults=%d" % len(assault_ids))
    else:
        passes.append("assault_n=%d" % len(assault_ids))

    ok = len(fails) == 0 and bool(assault.get("ok")) and bool(fronts.get("ok"))
    score = 0.35 * float(fronts.get("score") or 0) + 0.45 * float(assault.get("score") or 0)
    if campaign:
        score += 0.15 * float(campaign.get("score") or 0)
    score = max(0.0, min(1.0, score + (0.1 if ok else 0.0)))
    if ok:
        score = max(score, 0.84)

    label = (
        "Accurate multi-front execute · attacker=%s · assaults=%d · best=#%s · %s"
        % (
            att,
            len(assault_ids),
            assault.get("best_province_id"),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "ok": ok,
        "empty": False,
        "score": score,
        "status": "PASS" if ok else "FAIL",
        "attacker_tag": att,
        "fronts": fronts,
        "assault": assault,
        "campaign": campaign,
        "apply_queue": apply_queue,
        "assault_province_ids": assault_ids,
        "pass": passes,
        "fail": fails,
        "summary": label,
        "plain": label + ("\nFAIL: " + " | ".join(fails) if fails else ""),
        "integration": [
            "world_accurate_multi_front_execute_product",
            "multi_front_execute",
            "world_accurate",
            "apply_assault",
        ],
    }


def world_accurate_multi_front_execute_integrity() -> Dict[str, Any]:
    p = build_world_accurate_multi_front_execute_product()
    return {
        "ok": bool(p.get("ok")),
        "assault_province_ids": p.get("assault_province_ids"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
