#!/usr/bin/env python3
"""Apply FEED-3 Gibraltar island-scale land key on world_accurate.

Append-only Europe ID 711520. Does not renumber existing play-board or
world_full IDs. Does not touch seas coarsening, Hong Kong, Maginot, or combat.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gibraltar_island_land_product import (  # noqa: E402
    apply_gibraltar_island_land,
    build_gibraltar_island_land_product,
    plan_gibraltar_island_land,
)


def main() -> int:
    ap = argparse.ArgumentParser(description="Carve Gibraltar island-scale land on world_accurate")
    ap.add_argument(
        "--dir",
        default=str(ROOT / "data" / "provinces_world_accurate"),
        help="Board directory (default: data/provinces_world_accurate)",
    )
    ap.add_argument("--dry-run", action="store_true", help="Print the plan only; do not write")
    args = ap.parse_args()
    if args.dry_run:
        plan = plan_gibraltar_island_land(args.dir)
        slim = {
            "already_applied": plan.get("already_applied"),
            "new_ids": plan.get("new_ids"),
            "gibraltar_area": round(float(plan.get("gibraltar_area") or 0.0), 2),
            "cadiz_area_before": round(float(plan.get("cadiz_area_before") or 0.0), 1),
            "cadiz_area_after": round(float(plan.get("cadiz_area_after") or 0.0), 1),
            "preserved_ids": plan.get("preserved_ids"),
        }
        print(json.dumps(slim, indent=2))
        return 0
    result = apply_gibraltar_island_land(args.dir)
    print(json.dumps(result, indent=2))
    qc = build_gibraltar_island_land_product(args.dir)
    print(
        json.dumps(
            {
                "qc_ok": qc.get("ok"),
                "qc_summary": qc.get("summary"),
                "fails": qc.get("fails"),
                "passes": qc.get("passes"),
                "gibraltar_area": qc.get("gibraltar_area"),
            },
            indent=2,
        )
    )
    return 0 if result.get("ok") and qc.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
