#!/usr/bin/env python3
"""
Promote stylized clean/composite PNG layers to in-game ultra_high JPG underlays.

No tile download — uses existing assets/maps/layers/* outputs from
build_real_world_map_layers.py (or manual art passes).
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]

CANDIDATES = [
    (
        "world",
        [
            "assets/maps/layers/world_grand_theater_clean.png",
            "assets/maps/layers/world_grand_theater_composite.png",
        ],
        "assets/maps/world_grand_theater_ultra_high.jpg",
        90,
    ),
    (
        "europe",
        [
            "assets/maps/layers/europe_grand_theater_clean.png",
            "assets/maps/layers/europe_grand_theater_composite.png",
        ],
        "assets/maps/europe_grand_theater_ultra_high.jpg",
        92,
    ),
]


def promote(source: Path, dest: Path, quality: int) -> None:
    img = Image.open(source)
    if img.mode != "RGB":
        img = img.convert("RGB")
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest, format="JPEG", quality=quality, optimize=True)
    print(f"  {source.relative_to(ROOT)} ({img.size[0]}x{img.size[1]}) -> {dest.relative_to(ROOT)} quality={quality}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", choices=["world", "europe", "both"], default="both")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    print("=== Promote map master (clean PNG -> ultra_high JPG) ===")
    for name, sources, dest_rel, quality in CANDIDATES:
        if args.region not in (name, "both"):
            continue
        source_path = None
        for rel in sources:
            candidate = ROOT / rel
            if candidate.exists():
                source_path = candidate
                break
        if source_path is None:
            print(f"  SKIP {name}: no source PNG found")
            continue
        dest = ROOT / dest_rel
        if args.dry_run:
            print(f"  DRY-RUN would promote {source_path.relative_to(ROOT)} -> {dest.relative_to(ROOT)}")
            continue
        promote(source_path, dest, quality)

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
