#!/usr/bin/env python3
"""Spot-check province centroids vs city layer for alignment QA."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def centroid(points):
    if not points:
        return 0.0, 0.0
    return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default="data/provinces_phase1_test")
    parser.add_argument("--max-dist", type=float, default=250.0)
    parser.add_argument(
        "--europe-only",
        action="store_true",
        help="Skip province ids >= 9000 (coarse world territories outside Europe theater)",
    )
    args = parser.parse_args()
    data_dir = ROOT / args.dir
    geom = {int(p["id"]): p for p in json.loads((data_dir / "provinces_geometry.json").read_text())["provinces"]}
    cities = json.loads((data_dir / "province_city_layer.json").read_text()).get("provinces", {})

    warnings = 0
    checked = 0
    skipped = 0
    for pid_str, layer in cities.items():
        pid = int(pid_str)
        if args.europe_only and pid >= 9000:
            skipped += 1
            continue
        if pid not in geom:
            continue
        for city in layer.get("cities", []):
            pos = city.get("position", [])
            if len(pos) < 2:
                continue
            checked += 1
            cx, cy = centroid(geom[pid]["points"])
            d = dist((cx, cy), (pos[0], pos[1]))
            if d > args.max_dist:
                warnings += 1
                print(f"WARN pid {pid} city '{city.get('name','')}' dist={d:.0f}px from centroid")
    print(f"Alignment check: {checked} cities, {warnings} warnings (threshold {args.max_dist}px)" + (f", skipped {skipped} world ids" if skipped else ""))
    raise SystemExit(1 if warnings > checked * 0.25 else 0)


if __name__ == "__main__":
    main()
