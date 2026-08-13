#!/usr/bin/env python3
"""Build data/provinces_pilot_europe denser Europe pilot (parallel to world_full)."""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from europe_pilot_densify import build_and_write_europe_pilot, europe_pilot_integrity  # type: ignore


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--splits", type=int, default=3)
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    if not args.write:
        print("Pass --write to generate data/provinces_pilot_europe")
        return 2
    out = build_and_write_europe_pilot(splits=max(2, int(args.splits)))
    print("[WROTE]", out)
    gate = europe_pilot_integrity()
    print(gate["summary"])
    return 0 if gate.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
