#!/usr/bin/env python3
"""List enclosed holes in Canadian land on the world_accurate board.

Play reruns this after a map edit. It prints one row per hole: area px²,
area-weighted centroid, lon/lat, water-or-gap evidence, and the province
ids that own the surrounding edges.

    python3 tools/map_generation/scripts/measure_canada_holes.py
    python3 tools/map_generation/scripts/measure_canada_holes.py --json /tmp/canada_holes.json
    python3 tools/map_generation/scripts/measure_canada_holes.py --audit

--audit also counts invalid polygons, land×sea pixel overlaps, and
asymmetric adjacency. Those counts are the BEFORE/AFTER bars.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from canada_hole_measure import (  # noqa: E402
    DEFAULT_DIR,
    adjacency_asymmetric,
    count_invalid_polygons,
    count_land_sea_overlaps,
    measure_canada_holes,
)


def _fmt_surround(hole) -> str:
    parts = []
    for row in hole["surrounding"]:
        parts.append("%s:%s" % (row["id"], row["name"][:22]))
    return ", ".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description="Measure enclosed holes in Canadian land")
    parser.add_argument("--dir", type=Path, default=DEFAULT_DIR)
    parser.add_argument("--json", type=Path, default=None, help="Write the full hole records")
    parser.add_argument("--min-area", type=float, default=0.5)
    parser.add_argument("--audit", action="store_true", help="Also count invalid rings, land×sea overlaps, adjacency symmetry")
    parser.add_argument("--no-ne", action="store_true", help="Skip the Natural Earth lake/land test")
    args = parser.parse_args()
    report = measure_canada_holes(args.dir, use_natural_earth=not args.no_ne)
    holes = [h for h in report["holes"] if h["area_px2"] + 1e-9 >= args.min_area]
    print(
        "provinces=%d canada_land=%d scope=%d holes=%d over_100=%d"
        % (
            report["province_count"],
            report["canada_land_ids"],
            report["scope_provinces"],
            len(holes),
            sum(1 for h in holes if h["area_px2"] > 100.0),
        )
    )
    print(
        "%8s  %16s  %8s %7s  %-5s  %s"
        % ("area", "centroid", "lon", "lat", "kind", "surrounding")
    )
    for hole in holes:
        cx, cy = hole["centroid"]
        kind = hole.get("kind") or ""
        name = hole.get("water_name") or ""
        label = kind if not name else "%s:%s" % (kind, name)
        print(
            "%8.1f  (%7.1f,%7.1f)  %8.3f %7.3f  %-22s  %s"
            % (hole["area_px2"], cx, cy, hole["lon"], hole["lat"], label[:22], _fmt_surround(hole))
        )
        if hole.get("evidence"):
            print("          %s" % hole["evidence"])
    if args.json:
        payload = dict(report)
        payload["holes"] = holes
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print("wrote %s" % args.json)
    if args.audit:
        print("--- audit ---", flush=True)
        invalid = count_invalid_polygons(args.dir)
        print("invalid_polygons=%d" % invalid["count"])
        overlaps = count_land_sea_overlaps(args.dir)
        print("land_sea_overlap_pairs=%d" % overlaps["count"])
        for row in overlaps["pairs"][:20]:
            print("  %s x %s = %d px" % (row["land"], row["water"], row["px"]))
        asym = adjacency_asymmetric(args.dir)
        print("adjacency_asymmetric=%d" % len(asym))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
