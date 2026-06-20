#!/usr/bin/env python3
"""QC British Isles province geography after carve_british_isles_provinces.py.

Checks north→south ordering, strategic region assignments, and Irish Sea gap.
Exit 0 = pass, 1 = failures.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "provinces_phase1_test"

BI_IDS = [9270, 9271, 9272, 9273, 9274, 9275, 9510, 9511, 9512, 9513, 9514]
ENG_IDS = [9270, 9271, 9272, 9273, 9274, 9275]

REGION_NAMES = {
    1: "Southern England",
    2: "Northern England & Midlands",
    3: "Scotland",
    4: "Wales",
    5: "Ireland",
}

EXPECTED_BY_TAG = {"SCO": 3, "WLS": 4, "IRL": 5}


def centroid(points: list[list[float]]) -> tuple[float, float]:
    return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)


def classify_eng_split(cx: float, cy: float) -> int:
    if cy < 760:
        return 3
    if cy >= 905:
        return 1
    return 2


def expected_region(tags: list[str], cx: float, cy: float) -> int:
    for tag in tags:
        t = tag.upper()
        if t in EXPECTED_BY_TAG:
            return EXPECTED_BY_TAG[t]
        if t == "ENG":
            return classify_eng_split(cx, cy)
    return -1


def min_poly_distance(a: list[list[float]], b: list[list[float]]) -> float:
    best = float("inf")
    for pa in a:
        for pb in b:
            best = min(best, math.hypot(pa[0] - pb[0], pa[1] - pb[1]))
    return best


def main() -> int:
    base = json.loads((DATA / "provinces_base.json").read_text())
    geo = json.loads((DATA / "provinces_geometry.json").read_text())
    regions = json.loads((DATA / "strategic_regions.json").read_text())
    adj = json.loads((DATA / "province_adjacency.json").read_text()).get("adjacency", {})

    base_by_id = {p["id"]: p for p in base["provinces"]}
    geo_by_id = {p["id"]: p for p in geo["provinces"]}
    prov_to_region: dict[int, int] = {}
    for r in regions["regions"]:
        for pid in r["province_ids"]:
            prov_to_region[pid] = r["id"]

    failures: list[str] = []
    print("=== British Isles Geography QC ===\n")

    rows: list[tuple[int, str, float, float, int, int]] = []
    for pid in BI_IDS:
        if pid not in geo_by_id or pid not in base_by_id:
            failures.append(f"Missing data for province {pid}")
            continue
        pts = geo_by_id[pid]["points"]
        cx, cy = centroid(pts)
        tags = base_by_id[pid].get("core_for_tags", [])
        exp = expected_region(tags, cx, cy)
        act = prov_to_region.get(pid, -1)
        rows.append((pid, base_by_id[pid]["name"], cx, cy, exp, act))
        if exp != act:
            failures.append(
                f"{pid} {base_by_id[pid]['name']}: expected region {exp} ({REGION_NAMES.get(exp, '?')}), "
                f"got {act} ({REGION_NAMES.get(act, '?')})"
            )

    print(f"{'ID':>5} {'Name':<12} {'Centroid':>14} {'Exp':>4} {'Act':>4} {'OK':>4}")
    for pid, name, cx, cy, exp, act in rows:
        ok = "✓" if exp == act else "✗"
        print(f"{pid:5d} {name:<12} ({cx:6.0f},{cy:5.0f}) {exp:4d} {act:4d} {ok:>4}")

    eng_rows = [(p, n, cy) for p, n, _, cy, _, _ in rows if p in ENG_IDS]
    eng_sorted = sorted(eng_rows, key=lambda r: r[2])
    expected_order = ["Newcastle", "Leeds", "Liverpool", "Birmingham", "London", "Southampton"]
    actual_order = [n for _, n, _ in eng_sorted]
    print(f"\nEngland north→south: {' → '.join(actual_order)}")
    if actual_order != expected_order:
        failures.append(f"England order wrong: expected {expected_order}, got {actual_order}")

    liv_pts = geo_by_id[9270]["points"]
    dub_pts = geo_by_id[9513]["points"]
    gap = min_poly_distance(liv_pts, dub_pts)
    adjacent = 9513 in adj.get("9270", [])
    print(f"\nIrish Sea Liverpool↔Dublin: min_dist={gap:.1f}px adjacent={adjacent}")
    if adjacent:
        failures.append("Dublin is adjacent to Liverpool across Irish Sea")
    if gap < 80:
        failures.append(f"Irish Sea gap too narrow ({gap:.1f}px < 80)")

    meta = geo.get("meta", {})
    print(f"\nMeta carve version: {meta.get('british_isles_carve', '?')}")
    print(f"Meta bbox: {meta.get('british_isles_bbox', '?')}")

    if failures:
        print(f"\nFAILED ({len(failures)} issues):")
        for f in failures:
            print(f"  - {f}")
        return 1

    print("\nPASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
