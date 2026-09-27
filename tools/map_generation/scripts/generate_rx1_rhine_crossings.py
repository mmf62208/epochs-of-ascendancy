#!/usr/bin/env python3
"""Generate data/map/rx1_rhine_crossings.json from GISCO ∩ reprojected Rhine.

Fails if a listed candidate is not a real shared border on the Rhine.
Does not read province_adjacency.json kNN.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from rx1_rhine_crossing_product import (  # noqa: E402
    SPEC_PATH,
    shared_border_guard,
    write_spec,
)


def main() -> int:
    payload = write_spec(SPEC_PATH)
    fails = payload.get("fails") or []
    if fails:
        print("generate_rx1_rhine_crossings: FAIL listed edges not real shared Rhine borders")
        for f in fails:
            print("  ", f)
        return 1
    spec = {k: v for k, v in payload.items() if k != "fails"}
    guard = shared_border_guard(spec)
    if not guard.get("ok"):
        print("generate_rx1_rhine_crossings: FAIL shared-border guard", guard)
        return 1
    edges = spec.get("edges") or []
    print("generate_rx1_rhine_crossings: wrote", SPEC_PATH)
    print("  course_pts", len((spec.get("course") or {}).get("points") or []))
    print("  edges", len(edges))
    for row in edges:
        pair = row.get("edge")
        print(
            "   ",
            pair,
            "bridged_1936=" + str(row.get("bridged_1936")),
            "share=" + str(row.get("shared_border_length")),
            "banks=" + str(row.get("banks")),
        )
    print("  knn_lists_koeln_essen", guard.get("knn_lists_koeln_essen"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
