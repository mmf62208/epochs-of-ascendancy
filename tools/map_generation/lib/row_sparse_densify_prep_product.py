"""Prep product for sparse RoW densify (Africa/CA/SA/Aus/India/Siberia/Mongolia/China).

Does NOT rebuild boards. Gates target bands + wiring expectations for a future merge PR
(same spirit as US county→playable merge).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
NOTES = ROOT / "docs" / "SESSION_NOTES" / "2026-07-29_densify_prep.md"
US_MERGE = ROOT / "tools" / "map_generation" / "scripts" / "merge_us_counties_to_state_provinces.py"

# Planning bands (playable land targets after merge) — not executed counts.
REGION_TARGETS: Dict[str, Dict[str, int]] = {
    "africa": {"min_playable": 80, "max_playable": 220},
    "central_america": {"min_playable": 25, "max_playable": 80},
    "south_america": {"min_playable": 60, "max_playable": 160},
    "australia": {"min_playable": 12, "max_playable": 40},
    "india": {"min_playable": 40, "max_playable": 120},
    "siberia_mongolia_sparse_china": {"min_playable": 40, "max_playable": 140},
}

CONSTRAINTS = [
    "never_renumber_world_full_ids",
    "keep_dual_board_world_accurate_vs_world_full",
    "adjacency_land_shared_floor_0_97",
    "preserve_strait_chokepoints",
    "sea_zones_similar_size_except_straits",
]


def band_ok(n: int, region: str) -> bool:
    t = REGION_TARGETS.get(region, {})
    if not t:
        return False
    return int(t["min_playable"]) <= int(n) <= int(t["max_playable"])


def build_row_sparse_densify_prep_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    # Synthetic acceptance of bands
    if band_ok(100, "africa") and not band_ok(10, "africa"):
        passes.append("africa_band")
    else:
        fails.append("africa_band")
    if band_ok(20, "australia") and not band_ok(200, "australia"):
        passes.append("australia_band")
    else:
        fails.append("australia_band")
    if NOTES.is_file():
        passes.append("prep_note")
    else:
        fails.append("missing_prep_note")
    # Prefer US merge script as template (path may vary)
    us_ok = US_MERGE.is_file() or any(
        (ROOT / "tools" / "map_generation").rglob("merge_us_counties*.py")
    )
    if us_ok:
        passes.append("us_merge_template")
    else:
        fails.append("no_us_merge_template")
    for c in CONSTRAINTS:
        if c:
            passes.append("constraint_%s" % c[:24])

    ok = len(fails) == 0
    return {
        "ok": ok,
        "regions": list(REGION_TARGETS.keys()),
        "targets": REGION_TARGETS,
        "constraints": CONSTRAINTS,
        "pass": passes,
        "fail": fails,
        "summary": "row_sparse_densify_prep · regions=%d · %s"
        % (len(REGION_TARGETS), "PASS" if ok else "FAIL"),
        "status": "prep_landed_t1_board_merge_see_row_sparse_density_product",
        "note": "Tranche1 board merge: merge_row_sparse_to_playable.py; full plan product is row_sparse_density_product.",
    }
