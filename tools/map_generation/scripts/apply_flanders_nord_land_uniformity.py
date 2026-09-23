#!/usr/bin/env python3
"""Apply FEED-7 Flanders/Nord land-area uniformity on world_accurate.

Append-only Europe IDs starting at 711521 (after Gibraltar 711520).
Does not renumber existing play-board or world_full IDs. Does not touch
Maginot, Ruhr/NRW, seas, Great Lakes, or combat systems.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from flanders_nord_land_uniformity_product import (  # noqa: E402
    apply_flanders_nord_land_uniformity,
    build_flanders_nord_land_uniformity_product,
    plan_flanders_nord_land_uniformity,
)


def main() -> int:
    ap = argparse.ArgumentParser(description="Uniform Flanders/Nord land cells on world_accurate")
    ap.add_argument(
        "--dir",
        default=str(ROOT / "data" / "provinces_world_accurate"),
        help="Board directory (default: data/provinces_world_accurate)",
    )
    ap.add_argument("--dry-run", action="store_true", help="Print the plan only; do not write")
    args = ap.parse_args()
    if args.dry_run:
        plan = plan_flanders_nord_land_uniformity(args.dir)
        slim = {
            "already_applied": plan.get("already_applied"),
            "new_ids": plan.get("new_ids"),
            "secondary": plan.get("secondary"),
            "post_nord_metrics": plan.get("post_nord_metrics"),
            "splits": [
                {
                    "parent_id": s["parent_id"],
                    "child_id": s["child_id"],
                    "parent_name": s["parent_name"],
                    "child_name": s["child_name"],
                    "keep_area": round(float(s["keep_area"]), 1),
                    "child_area": round(float(s["child_area"]), 1),
                    "parent_area_before": round(float(s["parent_area_before"]), 1),
                    "keep_lonlat": [round(float(x), 3) for x in (s.get("keep_lonlat") or [])],
                    "child_lonlat": [round(float(x), 3) for x in (s.get("child_lonlat") or [])],
                }
                for s in plan.get("splits") or []
            ],
            "grows": [],
        }
        print(json.dumps(slim, indent=2))
        return 0
    result = apply_flanders_nord_land_uniformity(args.dir)
    print(json.dumps(result, indent=2))
    qc = build_flanders_nord_land_uniformity_product(args.dir)
    print(
        json.dumps(
            {
                "qc_ok": qc.get("ok"),
                "qc_summary": qc.get("summary"),
                "fails": qc.get("fails"),
                "metrics": qc.get("metrics"),
            },
            indent=2,
        )
    )
    return 0 if result.get("ok") and qc.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
