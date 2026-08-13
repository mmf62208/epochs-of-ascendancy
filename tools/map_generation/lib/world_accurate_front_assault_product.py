"""Multi-front assault ranking on real world_accurate border edges.

Composes multi_front map edges + multi_front_assault.rank_assault_targets so
GER (or any attacker) gets HOI-style priority targets on Maginot / Polish fronts
instead of synthetic province_id+1 placeholders.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence

from multi_front_assault import rank_assault_targets  # type: ignore
from world_accurate_multi_front_product import (  # type: ignore
    build_world_accurate_multi_front_product,
    collect_border_edges,
)

try:
    from front_continuity_campaign_product import (  # type: ignore
        build_front_continuity_campaign_product,
    )
except Exception:  # pragma: no cover
    build_front_continuity_campaign_product = None  # type: ignore

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

# Preferred assault samples (attacker province, defender province)
CANONICAL = {
    "rhineland_maginot": (710173, 710739),  # Baden-Baden → Bas-Rhin
}


def _load_board(board_dir: Path):
    adj = json.loads((board_dir / "province_adjacency.json").read_text(encoding="utf-8")).get(
        "adjacency"
    ) or {}
    own = (
        json.loads((board_dir / "province_ownership_1936.json").read_text(encoding="utf-8")).get(
            "owners"
        )
        or {}
    )
    base = {
        int(p["id"]): p
        for p in json.loads((board_dir / "provinces_base.json").read_text(encoding="utf-8"))[
            "provinces"
        ]
    }
    return adj, {str(k): str(v).upper() for k, v in own.items()}, base


def build_world_accurate_front_assault_product(
    *,
    attacker_tag: str = "GER",
    board_dir: Optional[Path] = None,
    attacker_power: float = 120.0,
    max_targets: int = 8,
) -> Dict[str, Any]:
    d = Path(board_dir or DEFAULT_DIR)
    fronts_prod = build_world_accurate_multi_front_product(d)
    adj, owners, base = _load_board(d)
    att = str(attacker_tag).upper()
    fails: List[str] = []
    passes: List[str] = []

    if not fronts_prod.get("ok"):
        fails.append("multi_front_board_fail")

    targets: List[Dict[str, Any]] = []
    for front in fronts_prod.get("fronts") or []:
        tags = front.get("tags") or []
        if att not in tags:
            continue
        enemy = tags[0] if tags[1] == att else tags[1]
        edges = collect_border_edges(adj, owners, att, enemy)
        # Prefer canonical edge first for Rhineland
        preferred = CANONICAL.get(str(front.get("id")))
        ordered = list(edges)
        if preferred:
            lo, hi = preferred
            # normalize orientation attacker→defender
            for a, b in list(edges):
                if {a, b} == {lo, hi}:
                    if owners.get(str(a)) == att:
                        ordered = [(a, b)] + [e for e in edges if e != (a, b) and e != (b, a)]
                    else:
                        ordered = [(b, a)] + [e for e in edges if e != (a, b) and e != (b, a)]
                    break
        for a, b in ordered[:6]:
            # orient so defender is enemy
            if owners.get(str(a)) == att and owners.get(str(b)) == enemy:
                src, dst = a, b
            elif owners.get(str(b)) == att and owners.get(str(a)) == enemy:
                src, dst = b, a
            else:
                continue
            dfn = 70.0 if front.get("id") == "rhineland_maginot" else 85.0
            if front.get("id") == "polish_border":
                dfn = 55.0
            targets.append(
                {
                    "province_id": dst,
                    "from_province_id": src,
                    "name": str((base.get(dst) or {}).get("name") or dst),
                    "from_name": str((base.get(src) or {}).get("name") or src),
                    "front_id": front.get("id"),
                    "front_name": front.get("name"),
                    "defender_tag": enemy,
                    "defender_power": dfn,
                    "weather_mult": 1.0,
                    "pressure": 0.7 if front.get("id") == "rhineland_maginot" else 0.55,
                }
            )

    if not targets:
        fails.append("no_assault_targets")
    else:
        passes.append("targets=%d" % len(targets))

    ranked = rank_assault_targets(
        targets, attacker_power=attacker_power, attacker_supply=1.0, max_targets=max_targets
    )
    best = ranked.get("best") or {}
    best_pid = int(ranked.get("best_province_id") or -1)
    if best_pid > 0:
        passes.append("best=%d %s" % (best_pid, best.get("recommendation")))
    else:
        fails.append("no_best_target")

    # Canonical Maginot edge must be in ranking pool
    maginot_in = any(
        int(t.get("province_id") or 0) == 710739 for t in (ranked.get("all") or targets)
    )
    if maginot_in:
        passes.append("bas_rhin_in_pool")
    else:
        fails.append("bas_rhin_missing_from_pool")

    continuity = None
    if build_front_continuity_campaign_product is not None and best_pid > 0:
        continuity = build_front_continuity_campaign_product(province_id=best_pid)
        if float(continuity.get("score") or 0) > 0.4:
            passes.append("front_continuity=%.2f" % float(continuity.get("score")))

    ok = len(fails) == 0 and not ranked.get("empty")
    score = float((ranked.get("best") or {}).get("overall") or 0.0) * 0.5 + (
        0.4 if fronts_prod.get("ok") else 0.0
    )
    score = max(0.0, min(1.0, score + (0.15 if ok else 0.0)))
    if ok:
        score = max(score, 0.82)

    label = (
        "Accurate front assault · attacker=%s · targets=%d · best=#%d · %s"
        % (att, len(targets), best_pid, "PASS" if ok else "FAIL")
    )
    return {
        "ok": ok,
        "empty": ranked.get("empty", True),
        "score": score,
        "status": "PASS" if ok else "FAIL",
        "attacker_tag": att,
        "targets_n": len(targets),
        "ranked": ranked,
        "best_province_id": best_pid,
        "best": best,
        "fronts_active": fronts_prod.get("active_n"),
        "continuity": continuity,
        "pass": passes,
        "fail": fails,
        "summary": label,
        "plain": label + ("\nFAIL: " + " | ".join(fails) if fails else ""),
        "integration": [
            "world_accurate_front_assault_product",
            "multi_front",
            "assault",
            "world_accurate",
        ],
    }


def world_accurate_front_assault_integrity() -> Dict[str, Any]:
    p = build_world_accurate_front_assault_product()
    return {
        "ok": bool(p.get("ok")),
        "best_province_id": p.get("best_province_id"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
