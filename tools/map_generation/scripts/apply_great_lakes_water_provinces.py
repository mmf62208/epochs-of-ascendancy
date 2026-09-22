#!/usr/bin/env python3
"""Apply FEED-1 Great Lakes basin rings on world_accurate (ID-stable).

Reuses allocated lake IDs 950333–950337. Does not renumber land or world_full.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from great_lakes_water_province_product import (  # noqa: E402
    apply_great_lakes_water_provinces,
    build_great_lakes_water_province_product,
)


def main() -> int:
    ap = argparse.ArgumentParser(description="Place Great Lakes water provinces on world_accurate")
    ap.add_argument(
        "--dir",
        default=str(ROOT / "data" / "provinces_world_accurate"),
        help="Board directory (default: data/provinces_world_accurate)",
    )
    args = ap.parse_args()
    result = apply_great_lakes_water_provinces(args.dir)
    print(json.dumps(result, indent=2))
    qc = build_great_lakes_water_province_product(args.dir)
    print(json.dumps({"qc_ok": qc.get("ok"), "qc_summary": qc.get("summary"), "fails": qc.get("fails")}, indent=2))
    return 0 if result.get("ok") and qc.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
