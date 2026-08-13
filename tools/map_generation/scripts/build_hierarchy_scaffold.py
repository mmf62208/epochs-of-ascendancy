#!/usr/bin/env python3
"""Build province→state→region hierarchy scaffold for world_full."""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from map_hierarchy_product import write_hierarchy_files, hierarchy_integrity, DEFAULT_DIR  # type: ignore


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=str(DEFAULT_DIR))
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    d = Path(args.dir)
    if not d.is_absolute():
        d = ROOT / d
    if args.write:
        out = write_hierarchy_files(d)
        print("[WROTE]", out)
    gate = hierarchy_integrity(d)
    print(gate["summary"])
    return 0 if gate.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
