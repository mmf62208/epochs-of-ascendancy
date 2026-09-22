#!/usr/bin/env python3
"""Apply FEED-5 Hong Kong island-scale land key on world_accurate.

Append-only RoW/Asia ID 905844. Does not renumber existing play-board or
world_full IDs. Does not touch seas coarsening, Gibraltar, Maginot, or combat.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from hong_kong_island_land_product import (  # noqa: E402
    apply_hong_kong_island_land,
    build_hong_kong_island_land_product,
    plan_hong_kong_island_land,
)


def main() -> int:
    ap = argparse.ArgumentParser(description="Carve Hong Kong island-scale land on world_accurate")
    ap.add_argument(
        "--dir",
        default=str(ROOT / "data" / "provinces_world_accurate"),
        help="Board directory (default: data/provinces_world_accurate)",
    )
    ap.add_argument("--dry-run", action="store_true", help="Print the plan only; do not write")
    args = ap.parse_args()
    if args.dry_run:
        plan = plan_hong_kong_island_land(args.dir)
        slim = {
            "already_applied": plan.get("already_applied"),
            "new_ids": plan.get("new_ids"),
            "hong_kong_area": round(float(plan.get("hong_kong_area") or 0.0), 2),
            "yuen_long_area": round(float(plan.get("yuen_long_area") or 0.0), 2),
            "preserved_ids": plan.get("preserved_ids"),
        }
        print(json.dumps(slim, indent=2))
        return 0
    result = apply_hong_kong_island_land(args.dir)
    print(json.dumps(result, indent=2))
    qc = build_hong_kong_island_land_product(args.dir)
    print(
        json.dumps(
            {
                "qc_ok": qc.get("ok"),
                "qc_summary": qc.get("summary"),
                "fails": qc.get("fails"),
                "passes": qc.get("passes"),
                "hong_kong_area": qc.get("hong_kong_area"),
            },
            indent=2,
        )
    )
    return 0 if result.get("ok") and qc.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
