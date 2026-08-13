"""M1 — resources mapmode tint helper (pure, mirrors MapRenderer path).

Given a province resources dict (from province_resources_layer / Province.resources),
returns an RGB color signal that is distinct from political greys and stronger for
oil/rubber/strategic goods than coal alone.
"""
from __future__ import annotations

from typing import Any, Dict, Mapping, Optional, Sequence, Tuple

# Resource priority weights for dominant-good tint (HOI strategic map feel).
RESOURCE_WEIGHTS: Dict[str, float] = {
    "oil": 3.0,
    "rubber": 2.5,
    "chromium": 2.0,
    "tungsten": 2.0,
    "aluminum": 1.8,
    "steel": 1.4,
    "coal": 1.0,
    "iron": 1.2,
}

# Distinct hues (RGB 0–1) per strategic good.
RESOURCE_COLORS: Dict[str, Tuple[float, float, float]] = {
    "oil": (0.12, 0.55, 0.28),  # green-black oil
    "rubber": (0.45, 0.72, 0.22),  # rubber green
    "chromium": (0.55, 0.35, 0.85),  # violet
    "tungsten": (0.75, 0.55, 0.20),  # bronze
    "aluminum": (0.70, 0.78, 0.90),  # silver-blue
    "steel": (0.45, 0.50, 0.58),  # steel grey-blue
    "coal": (0.22, 0.20, 0.18),  # coal black
    "iron": (0.55, 0.32, 0.28),  # iron red-brown
}

EMPTY_LAND = (0.18, 0.20, 0.24)  # dim slate — no strategic goods
SEA = (0.08, 0.14, 0.28)


def _as_amount(v: Any) -> float:
    try:
        f = float(v)
    except (TypeError, ValueError):
        return 0.0
    return max(0.0, f)


def resource_dominance(
    resources: Optional[Mapping[str, Any]],
) -> Dict[str, Any]:
    """Pick dominant resource key and normalized intensity for a province."""
    if not resources:
        return {
            "dominant": "",
            "amount": 0.0,
            "score": 0.0,
            "has_strategic": False,
            "present": [],
        }
    present: list = []
    best_key = ""
    best_score = 0.0
    best_amt = 0.0
    for k, v in resources.items():
        key = str(k).strip().lower()
        amt = _as_amount(v)
        if amt <= 0:
            continue
        w = float(RESOURCE_WEIGHTS.get(key, 0.5))
        sc = amt * w
        present.append({"key": key, "amount": amt, "score": sc})
        if sc > best_score:
            best_score = sc
            best_key = key
            best_amt = amt
    present.sort(key=lambda r: -float(r["score"]))
    return {
        "dominant": best_key,
        "amount": best_amt,
        "score": best_score,
        "has_strategic": bool(best_key),
        "present": present,
    }


def resources_mapmode_rgb(
    resources: Optional[Mapping[str, Any]] = None,
    *,
    is_sea: bool = False,
    base_rgb: Optional[Sequence[float]] = None,
) -> Tuple[float, float, float]:
    """RGB fill for resources mapmode (0–1 components).

    Sea → deep blue. Empty land → dim slate. Else dominant resource hue
    blended slightly toward base_rgb (political) for readability of ownership.
    """
    if is_sea:
        return SEA
    dom = resource_dominance(resources)
    if not dom.get("has_strategic"):
        return EMPTY_LAND
    key = str(dom.get("dominant") or "")
    hue = RESOURCE_COLORS.get(key, (0.5, 0.5, 0.45))
    # Intensity from amount (cap soft)
    amt = float(dom.get("amount") or 0.0)
    intensity = max(0.35, min(1.0, 0.35 + 0.2 * amt))
    r = hue[0] * intensity
    g = hue[1] * intensity
    b = hue[2] * intensity
    if base_rgb is not None and len(base_rgb) >= 3:
        br, bg, bb = float(base_rgb[0]), float(base_rgb[1]), float(base_rgb[2])
        # Keep 25% political so countries still readable under resource paint
        r = r * 0.75 + br * 0.25
        g = g * 0.75 + bg * 0.25
        b = b * 0.75 + bb * 0.25
    return (
        max(0.0, min(1.0, r)),
        max(0.0, min(1.0, g)),
        max(0.0, min(1.0, b)),
    )


def build_resources_mapmode_product(
    samples: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Integrity product: oil sample ≠ empty ≠ sea; steel distinct from oil."""
    fails = []
    passes = []
    oil = resources_mapmode_rgb({"oil": 3}, is_sea=False)
    steel = resources_mapmode_rgb({"steel": 2}, is_sea=False)
    empty = resources_mapmode_rgb({}, is_sea=False)
    sea = resources_mapmode_rgb({}, is_sea=True)
    if oil == empty:
        fails.append("oil_eq_empty")
    else:
        passes.append("oil_distinct")
    if oil == steel:
        fails.append("oil_eq_steel")
    else:
        passes.append("oil_ne_steel")
    if sea[2] > sea[0]:  # blue channel stronger
        passes.append("sea_blue")
    else:
        fails.append("sea_not_blue")
    # Optional real samples
    sample_rows = []
    for s in samples or []:
        if not isinstance(s, Mapping):
            continue
        rgb = resources_mapmode_rgb(
            s.get("resources") if isinstance(s.get("resources"), Mapping) else s,
            is_sea=bool(s.get("is_sea", False)),
        )
        sample_rows.append({"id": s.get("id"), "rgb": rgb, "dom": resource_dominance(
            s.get("resources") if isinstance(s.get("resources"), Mapping) else s
        ).get("dominant")})
    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "oil_rgb": oil,
        "steel_rgb": steel,
        "empty_rgb": empty,
        "sea_rgb": sea,
        "samples": sample_rows,
        "pass": passes,
        "fail": fails,
        "summary": "Resources mapmode tint %s" % ("PASS" if ok else "FAIL"),
        "integration": ["map_resources_mapmode_product", "m1", "resources"],
    }


def resources_mapmode_integrity_from_board(board_dir: str = "") -> Dict[str, Any]:
    """Load real accurate resources layer samples (oil province + empty)."""
    from pathlib import Path
    import json

    root = Path(__file__).resolve().parents[3]
    d = Path(board_dir) if board_dir else root / "data" / "provinces_world_accurate"
    res = json.loads((d / "province_resources_layer.json").read_text(encoding="utf-8")).get(
        "provinces"
    ) or {}
    # Baku oil (painted)
    baku = res.get("904831") or {}
    samples = [
        {"id": 904831, "resources": baku, "is_sea": False},
        {"id": 0, "resources": {}, "is_sea": False},
        {"id": 950001, "resources": {}, "is_sea": True},
    ]
    # find a steel-heavy province
    for pid, row in res.items():
        if isinstance(row, dict) and float(row.get("steel") or 0) >= 2 and float(row.get("oil") or 0) <= 0:
            samples.append({"id": int(pid), "resources": row, "is_sea": False})
            break
    prod = build_resources_mapmode_product(samples)
    # Real oil province must not look empty
    if baku and float(baku.get("oil") or 0) > 0:
        rgb = resources_mapmode_rgb(baku)
        if rgb == EMPTY_LAND:
            prod["ok"] = False
            prod["fail"] = list(prod.get("fail") or []) + ["baku_empty_tint"]
        else:
            prod["pass"] = list(prod.get("pass") or []) + ["baku_oil_tint"]
    prod["board"] = str(d)
    return prod
