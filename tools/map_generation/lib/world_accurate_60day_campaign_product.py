"""Director D3.4 machine proxy — 60-day campaign feel on world_accurate.

Extends the 20-day product with multi-front board health + mid/late checkpoints.
Human narrative 60d notes remain open; this is the automated long-session gate.
"""
from __future__ import annotations

from typing import Any, Dict, Optional
from pathlib import Path

try:
    from world_accurate_20day_campaign_product import (  # type: ignore
        build_world_accurate_20day_campaign_product,
    )
except Exception:  # pragma: no cover
    build_world_accurate_20day_campaign_product = None  # type: ignore

try:
    from world_accurate_multi_front_product import (  # type: ignore
        build_world_accurate_multi_front_product,
    )
except Exception:  # pragma: no cover
    build_world_accurate_multi_front_product = None  # type: ignore


def build_world_accurate_60day_campaign_product(
    *,
    player_tag: str = "GER",
    province_id: int = 710300,
    board_dir: Optional[Path] = None,
    days: int = 60,
) -> Dict[str, Any]:
    n = max(20, min(90, int(days)))
    fails = []
    passes = []

    if build_world_accurate_20day_campaign_product is None:
        return {
            "ok": False,
            "empty": True,
            "score": 0.0,
            "status": "FAIL",
            "summary": "60d campaign FAIL · 20d product missing",
            "fail": ["20day_product_missing"],
        }

    base = build_world_accurate_20day_campaign_product(
        days=n,
        player_tag=player_tag,
        province_id=province_id,
        board_dir=board_dir,
    )
    if base.get("ok"):
        passes.append("base_%dd_ok" % n)
    else:
        fails.extend(list(base.get("fail") or ["base_fail"]))

    fronts = None
    if build_world_accurate_multi_front_product is not None:
        fronts = build_world_accurate_multi_front_product(board_dir=board_dir)
        if fronts.get("ok"):
            passes.append("multi_front_ok active=%s" % fronts.get("active_n"))
        else:
            fails.append("multi_front_fail")
            fails.extend(list(fronts.get("fail") or [])[:4])

    # Require at least ~80% AI days on long roll
    ai_ok = int(base.get("ai_ok_days") or 0)
    if ai_ok >= max(1, int(0.8 * n)):
        passes.append("long_ai=%d/%d" % (ai_ok, n))
    else:
        fails.append("long_ai_weak=%d/%d" % (ai_ok, n))

    ok = bool(base.get("ok")) and (fronts is None or bool(fronts.get("ok"))) and len(
        [f for f in fails if "multi_front" in f or "long_ai" in f or "base" in f]
    ) == 0
    # stricter: no fails
    ok = len(fails) == 0
    score = float(base.get("score") or 0.0) * 0.7
    if fronts and fronts.get("ok"):
        score += 0.25 * float(fronts.get("score") or 0.0)
    score = max(0.0, min(1.0, score + (0.05 if ok else 0.0)))
    if ok:
        score = max(score, 0.86)

    label = (
        "Accurate 60d campaign · days=%d · player=%s · ai=%d/%d · fronts=%s · %s"
        % (
            n,
            player_tag,
            ai_ok,
            n,
            (fronts or {}).get("active_n", "?"),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "ok": ok,
        "empty": False,
        "score": score,
        "status": "PASS" if ok else "FAIL",
        "days": n,
        "player_tag": player_tag,
        "province_id": province_id,
        "ai_ok_days": ai_ok,
        "base": base,
        "fronts": fronts,
        "pass": passes,
        "fail": fails,
        "summary": label,
        "plain": label + ("\nFAIL: " + " | ".join(fails) if fails else ""),
        "human_note": (
            "Machine proxy for D3.4 60-day feel. Human owns narrative playtest notes."
        ),
        "integration": [
            "world_accurate_60day_campaign_product",
            "d3_4",
            "world_accurate",
            "multi_front",
        ],
    }


def world_accurate_60day_campaign_integrity() -> Dict[str, Any]:
    p = build_world_accurate_60day_campaign_product(days=60)
    return {
        "ok": bool(p.get("ok")),
        "ai_ok_days": p.get("ai_ok_days"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
