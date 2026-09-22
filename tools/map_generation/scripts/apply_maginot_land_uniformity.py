#!/usr/bin/env python3
"""Apply FEED-2 Maginot land-area uniformity on world_accurate.

Append-only Europe IDs 711514–711519. Does not renumber existing play-board
or world_full IDs. Does not touch seas, Great Lakes, or combat systems.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from maginot_land_uniformity_product import (  # noqa: E402
    apply_maginot_land_uniformity,
    build_maginot_land_uniformity_product,
    plan_maginot_land_uniformity,
)


def main() -> int:
    ap = argparse.ArgumentParser(description="Uniform Maginot corridor land cells on world_accurate")
    ap.add_argument(
        "--dir",
        default=str(ROOT / "data" / "provinces_world_accurate"),
        help="Board directory (default: data/provinces_world_accurate)",
    )
    ap.add_argument("--dry-run", action="store_true", help="Print the plan only; do not write")
    args = ap.parse_args()
    if args.dry_run:
        plan = plan_maginot_land_uniformity(args.dir)
        slim = {
            "already_applied": plan.get("already_applied"),
            "new_ids": plan.get("new_ids"),
            "splits": [
                {
                    "parent_id": s["parent_id"],
                    "child_id": s["child_id"],
                    "parent_name": s["parent_name"],
                    "child_name": s["child_name"],
                    "keep_area": round(float(s["keep_area"]), 1),
                    "child_area": round(float(s["child_area"]), 1),
                    "parent_area_before": round(float(s["parent_area_before"]), 1),
                }
                for s in plan.get("splits") or []
            ],
            "grows": [
                {
                    "tiny_id": g["tiny_id"],
                    "donor_id": g["donor_id"],
                    "tiny_name": g["tiny_name"],
                    "tiny_area_before": round(float(g["tiny_area_before"]), 1),
                    "tiny_area_after": round(float(g["tiny_area_after"]), 1),
                    "donor_area_after": round(float(g["donor_area_after"]), 1),
                }
                for g in plan.get("grows") or []
            ],
        }
        print(json.dumps(slim, indent=2))
        return 0
    result = apply_maginot_land_uniformity(args.dir)
    print(json.dumps(result, indent=2))
    qc = build_maginot_land_uniformity_product(args.dir)
    print(json.dumps({"qc_ok": qc.get("ok"), "qc_summary": qc.get("summary"), "fails": qc.get("fails"), "metrics": qc.get("metrics")}, indent=2))
    return 0 if result.get("ok") and qc.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
