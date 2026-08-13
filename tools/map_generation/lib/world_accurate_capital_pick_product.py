"""Director D4.3 — accurate-board capital pick samples (pure, no Godot).

Validates that world_accurate major capitals have:
  - land domain + ownership matching scenario tag
  - geometry with enough points for a pick centroid
  - label_anchor inside reasonable world canvas
  - pairwise centroid separation (no stacked capitals)

Scaffold dual pick harness (map_manager_pick_harness.gd) stays on world_full city IDs.
This product is the machine gate for accurate capital samples without full-scene OOM risk.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
DEFAULT_SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"

WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean", "naval"})

# World canvas is ~8192×4096 equirectangular (label anchors from assemble).
_CANVAS_W = 9000.0
_CANVAS_H = 4500.0
_MIN_PTS = 3
_MIN_PAIR_DIST = 40.0  # world units; capitals must not share a centroid


def _is_water(row: dict) -> bool:
    terr = str(row.get("terrain", "")).lower()
    dom = str(row.get("domain", "land")).lower()
    return terr in WATER_T or dom in WATER_D


def _centroid_from_points(pts: Sequence[Any]) -> Optional[Tuple[float, float]]:
    xs: List[float] = []
    ys: List[float] = []
    for pt in pts:
        if isinstance(pt, (list, tuple)) and len(pt) >= 2:
            try:
                xs.append(float(pt[0]))
                ys.append(float(pt[1]))
            except (TypeError, ValueError):
                continue
    if not xs:
        return None
    return (sum(xs) / len(xs), sum(ys) / len(ys))


def _anchor_or_centroid(geo_row: dict) -> Optional[Tuple[float, float]]:
    anc = geo_row.get("label_anchor")
    if isinstance(anc, (list, tuple)) and len(anc) >= 2:
        try:
            return (float(anc[0]), float(anc[1]))
        except (TypeError, ValueError):
            pass
    return _centroid_from_points(geo_row.get("points") or [])


def _dist(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def load_accurate_capital_samples(
    board_dir: Optional[Path] = None,
    scenario_path: Optional[Path] = None,
) -> Dict[str, Any]:
    """Load capital rows from scenario + board JSON."""
    d = Path(board_dir or DEFAULT_DIR)
    sc_path = Path(scenario_path or DEFAULT_SCENARIO)
    base = {
        int(p["id"]): p
        for p in json.loads((d / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    }
    geo = {
        int(p["id"]): p
        for p in json.loads((d / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
    }
    owners = (
        json.loads((d / "province_ownership_1936.json").read_text(encoding="utf-8")).get("owners")
        or {}
    )
    sc = json.loads(sc_path.read_text(encoding="utf-8"))
    samples: List[Dict[str, Any]] = []
    for c in sc.get("countries") or []:
        tag = str(c.get("tag") or "").strip().upper()
        pid = int(c.get("capital_province_id") or 0)
        brow = base.get(pid) or {}
        grow = geo.get(pid) or {}
        pts = grow.get("points") or []
        cent = _anchor_or_centroid(grow)
        samples.append(
            {
                "tag": tag,
                "province_id": pid,
                "name": str(brow.get("name") or ""),
                "owner": str(owners.get(str(pid)) or ""),
                "is_water": _is_water(brow) if brow else True,
                "point_n": len(pts) if isinstance(pts, list) else 0,
                "centroid": list(cent) if cent else None,
                "color": str(c.get("color") or ""),
                "in_base": pid in base,
                "in_geo": pid in geo,
            }
        )
    return {
        "samples": samples,
        "board_dir": str(d),
        "scenario": str(sc_path),
        "province_count": len(base),
    }


def build_world_accurate_capital_pick_product(
    board_dir: Optional[Path] = None,
    scenario_path: Optional[Path] = None,
    *,
    min_capitals: int = 8,
    min_pair_dist: float = _MIN_PAIR_DIST,
) -> Dict[str, Any]:
    """Main D4.3 entry: capital pick sample integrity on world_accurate."""
    packed = load_accurate_capital_samples(board_dir, scenario_path)
    samples: List[Dict[str, Any]] = list(packed.get("samples") or [])
    fails: List[str] = []
    passes: List[str] = []

    if len(samples) < min_capitals:
        fails.append("too_few_capitals=%d need>=%d" % (len(samples), min_capitals))

    centroids: Dict[str, Tuple[float, float]] = {}
    for s in samples:
        tag = s["tag"]
        pid = int(s["province_id"])
        if not s.get("in_base"):
            fails.append("%s missing_base id=%d" % (tag, pid))
            continue
        if not s.get("in_geo"):
            fails.append("%s missing_geo id=%d" % (tag, pid))
            continue
        if s.get("is_water"):
            fails.append("%s capital_is_water id=%d" % (tag, pid))
        else:
            passes.append("%s land" % tag)
        if s.get("owner") != tag:
            fails.append("%s owner=%s expected=%s" % (tag, s.get("owner"), tag))
        else:
            passes.append("%s owned" % tag)
        if int(s.get("point_n") or 0) < _MIN_PTS:
            fails.append("%s too_few_points n=%s" % (tag, s.get("point_n")))
        else:
            passes.append("%s pts=%d" % (tag, int(s["point_n"])))
        cent = s.get("centroid")
        if not cent or len(cent) < 2:
            fails.append("%s no_centroid" % tag)
            continue
        x, y = float(cent[0]), float(cent[1])
        if not (0.0 <= x <= _CANVAS_W and 0.0 <= y <= _CANVAS_H):
            fails.append("%s centroid_oob (%.1f,%.1f)" % (tag, x, y))
        else:
            passes.append("%s centroid_ok" % tag)
            centroids[tag] = (x, y)

    # Pairwise separation — HOI-style capitals must not stack
    tags = sorted(centroids.keys())
    for i, a in enumerate(tags):
        for b in tags[i + 1 :]:
            d = _dist(centroids[a], centroids[b])
            if d < min_pair_dist:
                fails.append("capitals_too_close %s-%s dist=%.1f" % (a, b, d))
            else:
                passes.append("sep_%s_%s=%.0f" % (a, b, d))

    # Required major tags for full-test board
    required = {"GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL"}
    present = {s["tag"] for s in samples}
    missing = sorted(required - present)
    if missing:
        fails.append("missing_majors=%s" % ",".join(missing))
    else:
        passes.append("majors_present=8")

    ok = len(fails) == 0 and len(samples) >= min_capitals
    score = 0.0 if not samples else max(
        0.0,
        min(1.0, (len(passes) / max(1, len(passes) + len(fails) * 3))),
    )
    if ok:
        score = max(score, 0.85)

    label = (
        "Accurate capital pick · n=%d · province_board=%s · pass=%d fail=%d · %s"
        % (
            len(samples),
            packed.get("province_count"),
            len(passes),
            len(fails),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "ok": ok,
        "empty": len(samples) == 0,
        "score": score,
        "status": "PASS" if ok else "FAIL",
        "sample_n": len(samples),
        "samples": samples,
        "pass": passes,
        "fail": fails,
        "province_count": packed.get("province_count"),
        "board_dir": packed.get("board_dir"),
        "summary": label,
        "plain": label + ("\nFAIL: " + " | ".join(fails) if fails else ""),
        "dual_note": (
            "Scaffold dual pick stays world_full city IDs "
            "(tools/map_manager_pick_harness.gd). Accurate capitals: this product + "
            "tools/map_manager_pick_harness_accurate.gd (8 majors, MapManager-only)."
        ),
        "integration": [
            "world_accurate_capital_pick_product",
            "d4_3",
            "world_accurate",
            "capital_samples",
        ],
    }


def world_accurate_capital_pick_integrity() -> Dict[str, Any]:
    """Shipped-board integrity gate."""
    p = build_world_accurate_capital_pick_product()
    return {
        "ok": bool(p.get("ok")),
        "sample_n": p.get("sample_n"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
