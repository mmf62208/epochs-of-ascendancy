#!/usr/bin/env python3
"""Apply FEED-6 Caribbean ordinary-island sizing on world_accurate.

Append-only RoW IDs 905845–905848 (Barbados, Saint Lucia, Saint Vincent,
Grenada). Does not renumber existing play-board or world_full IDs. Does not
touch Gibraltar, Hong Kong, Alboran, Maginot, Great Lakes, or combat.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from caribbean_island_sizing_feed6_product import (  # noqa: E402
    apply_caribbean_island_sizing,
    build_caribbean_island_sizing_product,
    plan_caribbean_island_sizing,
)


def main() -> int:
    ap = argparse.ArgumentParser(description="Carve Windward ordinary-island lands on world_accurate")
    ap.add_argument(
        "--dir",
        default=str(ROOT / "data" / "provinces_world_accurate"),
        help="Board directory (default: data/provinces_world_accurate)",
    )
    ap.add_argument("--dry-run", action="store_true", help="Print the plan only; do not write")
    args = ap.parse_args()
    if args.dry_run:
        plan = plan_caribbean_island_sizing(args.dir)
        slim = {
            "already_applied": plan.get("already_applied"),
            "new_ids": plan.get("new_ids"),
            "areas": {k: round(float(v), 2) for k, v in (plan.get("areas") or {}).items()},
            "mainland_areas": {k: round(float(v), 2) for k, v in (plan.get("mainland_areas") or {}).items()},
            "preserved_ids": plan.get("preserved_ids"),
        }
        print(json.dumps(slim, indent=2, default=str))
        return 0
    result = apply_caribbean_island_sizing(args.dir)
    print(json.dumps(result, indent=2))
    qc = build_caribbean_island_sizing_product(args.dir)
    print(
        json.dumps(
            {
                "qc_ok": qc.get("ok"),
                "qc_summary": qc.get("summary"),
                "fails": qc.get("fails"),
                "passes": qc.get("passes"),
                "areas": qc.get("areas"),
            },
            indent=2,
        )
    )
    return 0 if result.get("ok") and qc.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
