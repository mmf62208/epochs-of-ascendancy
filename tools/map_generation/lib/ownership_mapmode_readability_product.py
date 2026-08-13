"""Director D3.3 — political/ownership mapmode readability (pure).

Gates HOI-style political map feel on world_accurate without GPU screenshots:
  - major tags have scenario colors
  - pairwise color distance for majors (no identical paints)
  - land ownership coverage + major sphere floors
  - political default + F1 wire still present in MapRenderer
  - accurate-board LOD culls for dense political readability
"""
from __future__ import annotations

import json
import math
import re
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
DEFAULT_SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
MAP_ZOOM_LOD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"
MAP_MODE_TOOLBAR = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"

WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean", "naval"})

# Minimum RGB Euclidean distance (0–441 scale) between major colors.
# Identical colors (GER/SOV both #8B0000 historically) fail; ~40 is still tight but distinct.
MIN_MAJOR_COLOR_DIST = 35.0

# Soft floors for 1936 major land spheres on accurate board (ownership counts).
# Post US + full RoW sparse merge (~3520 total): USA is playable-band not 3k counties;
# CHI is sparse-merged (~22 cells). Floors track playable map, not ADM2 densify.
MAJOR_SPHERE_FLOORS = {
    "USA": 80,
    "ENG": 200,
    "FRA": 100,
    "GER": 150,
    "SOV": 60,
    "ITA": 40,
    "JAP": 40,
    "CHI": 12,
}


def _is_water(row: dict) -> bool:
    terr = str(row.get("terrain", "")).lower()
    dom = str(row.get("domain", "land")).lower()
    return terr in WATER_T or dom in WATER_D


def _parse_hex_color(s: str) -> Optional[Tuple[float, float, float]]:
    raw = str(s or "").strip()
    if not raw:
        return None
    if raw.startswith("#"):
        raw = raw[1:]
    if len(raw) == 3:
        raw = "".join(ch * 2 for ch in raw)
    if len(raw) != 6:
        return None
    try:
        r = int(raw[0:2], 16)
        g = int(raw[2:4], 16)
        b = int(raw[4:6], 16)
    except ValueError:
        return None
    return (float(r), float(g), float(b))


def color_distance(a: str, b: str) -> float:
    pa = _parse_hex_color(a)
    pb = _parse_hex_color(b)
    if pa is None or pb is None:
        return 0.0
    return math.sqrt((pa[0] - pb[0]) ** 2 + (pa[1] - pb[1]) ** 2 + (pa[2] - pb[2]) ** 2)


def build_ownership_mapmode_readability_product(
    board_dir: Optional[Path] = None,
    scenario_path: Optional[Path] = None,
    *,
    min_color_dist: float = MIN_MAJOR_COLOR_DIST,
) -> Dict[str, Any]:
    """Main D3.3 entry for political/ownership readability on accurate board."""
    d = Path(board_dir or DEFAULT_DIR)
    sc_path = Path(scenario_path or DEFAULT_SCENARIO)
    fails: List[str] = []
    passes: List[str] = []

    base = {
        int(p["id"]): p
        for p in json.loads((d / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    }
    owners = (
        json.loads((d / "province_ownership_1936.json").read_text(encoding="utf-8")).get("owners")
        or {}
    )
    sc = json.loads(sc_path.read_text(encoding="utf-8"))
    countries = list(sc.get("countries") or [])

    land_ids = [pid for pid, p in base.items() if not _is_water(p)]
    land_n = len(land_ids)
    owned = sum(1 for pid in land_ids if owners.get(str(pid)))
    if land_n <= 0:
        fails.append("no_land")
    elif owned < land_n:
        fails.append("unowned_land=%d" % (land_n - owned))
    else:
        passes.append("land_owned=%d" % land_n)

    counts = Counter(str(v) for v in owners.values() if v)
    for tag, floor in MAJOR_SPHERE_FLOORS.items():
        n = int(counts.get(tag) or 0)
        if n < floor:
            fails.append("sphere_%s=%d need>=%d" % (tag, n, floor))
        else:
            passes.append("sphere_%s=%d" % (tag, n))

    # Scenario colors for majors
    color_by_tag: Dict[str, str] = {}
    for c in countries:
        tag = str(c.get("tag") or "").strip().upper()
        col = str(c.get("color") or "").strip()
        if tag:
            color_by_tag[tag] = col
            if not _parse_hex_color(col):
                fails.append("%s bad_color=%s" % (tag, col))
            else:
                passes.append("%s color=%s" % (tag, col))

    major_tags = [t for t in ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL") if t in color_by_tag]
    if len(major_tags) < 8:
        fails.append("missing_major_colors have=%d" % len(major_tags))

    collisions: List[str] = []
    for i, a in enumerate(major_tags):
        for b in major_tags[i + 1 :]:
            dist = color_distance(color_by_tag[a], color_by_tag[b])
            if dist < min_color_dist:
                collisions.append("%s-%s dist=%.1f (%s vs %s)" % (a, b, dist, color_by_tag[a], color_by_tag[b]))
                fails.append("color_collision %s-%s dist=%.1f" % (a, b, dist))
            else:
                passes.append("color_sep_%s_%s=%.0f" % (a, b, dist))

    # GD surfaces: political default + F1 + accurate culls
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    lod = MAP_ZOOM_LOD.read_text(encoding="utf-8") if MAP_ZOOM_LOD.is_file() else ""
    tb = MAP_MODE_TOOLBAR.read_text(encoding="utf-8") if MAP_MODE_TOOLBAR.is_file() else ""

    if 'current_map_mode: String = "political"' in ren or 'current_map_mode = "political"' in ren:
        passes.append("default_political")
    else:
        # looser: assignment somewhere
        if re.search(r'current_map_mode\s*[:=]\s*"political"', ren):
            passes.append("default_political")
        else:
            fails.append("default_mapmode_not_political")

    if "set_map_mode" in ren and "political" in ren:
        passes.append("set_map_mode_political")
    else:
        fails.append("set_map_mode_missing")

    if "KEY_F1" in ren or "F1" in ren:
        passes.append("f1_political_hint")
    if "ACCURATE_BOARD_CULL_THRESHOLD" in lod and (
        "3000" in lod or "4000" in lod or "5000" in lod or "7000" in lod
    ):
        passes.append("accurate_cull_threshold")
    else:
        fails.append("accurate_cull_missing")

    if MAP_MODE_TOOLBAR.is_file() and ("political" in tb.lower() or "Political" in tb):
        passes.append("toolbar_political")

    ok = len(fails) == 0
    score = 0.0
    if land_n > 0:
        score = max(0.0, min(1.0, len(passes) / max(1.0, len(passes) + len(fails) * 2.5)))
    if ok:
        score = max(score, 0.88)

    label = (
        "Ownership mapmode readability · land=%d · majors_colored=%d · collisions=%d · %s"
        % (land_n, len(major_tags), len(collisions), "PASS" if ok else "FAIL")
    )
    return {
        "ok": ok,
        "empty": land_n == 0,
        "score": score,
        "status": "PASS" if ok else "FAIL",
        "land_n": land_n,
        "owned_n": owned,
        "major_colors": color_by_tag,
        "sphere_counts": {k: int(counts.get(k) or 0) for k in MAJOR_SPHERE_FLOORS},
        "collisions": collisions,
        "pass": passes,
        "fail": fails,
        "min_color_dist": min_color_dist,
        "summary": label,
        "plain": label + ("\nFAIL: " + " | ".join(fails) if fails else ""),
        "integration": [
            "ownership_mapmode_readability_product",
            "d3_3",
            "political",
            "world_accurate",
        ],
    }


def ownership_mapmode_readability_integrity() -> Dict[str, Any]:
    p = build_ownership_mapmode_readability_product()
    return {
        "ok": bool(p.get("ok")),
        "collisions": p.get("collisions") or [],
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
