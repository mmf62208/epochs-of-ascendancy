#!/usr/bin/env python3
"""Apply FEED-10 Tyrrhenian seas coarsen on world_accurate (ID-stable).

Reuses allocated sea ID 950120. Does not renumber land or world_full.
Does not rewrite Ligurian / Alboran / Adriatic / Maginot / Flanders /
SE England land.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from seas_coarsen_feed10_tyrrhenian_product import (  # noqa: E402
    apply_seas_coarsen_feed10,
    build_seas_coarsen_feed10_tyrrhenian_product,
)


def main() -> int:
    ap = argparse.ArgumentParser(description="Place coarse Tyrrhenian Sea basin on world_accurate")
    ap.add_argument(
        "--dir",
        default=str(ROOT / "data" / "provinces_world_accurate"),
        help="Board directory (default: data/provinces_world_accurate)",
    )
    args = ap.parse_args()
    result = apply_seas_coarsen_feed10(args.dir)
    print(json.dumps(result, indent=2))
    qc = build_seas_coarsen_feed10_tyrrhenian_product(args.dir)
    print(
        json.dumps(
            {
                "qc_ok": qc.get("ok"),
                "qc_summary": qc.get("summary"),
                "fails": qc.get("fails"),
                "passes": qc.get("passes"),
                "metrics": qc.get("metrics"),
            },
            indent=2,
        )
    )
    return 0 if result.get("ok") and qc.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
