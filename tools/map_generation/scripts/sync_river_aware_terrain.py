#!/usr/bin/env python3
"""Copy river_aware flags from provinces_geometry.json into province_terrain_layer.json."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")
    print(f"  Wrote {path.relative_to(ROOT)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dir",
        default="data/provinces_phase1_test",
        help="Province data directory relative to project root",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    data_dir = ROOT / args.dir
    geom_path = data_dir / "provinces_geometry.json"
    terrain_path = data_dir / "province_terrain_layer.json"

    geom = load_json(geom_path)
    terrain_doc = load_json(terrain_path)
    provinces: Dict[str, Dict[str, Any]] = terrain_doc.setdefault("provinces", {})

    updated = 0
    for entry in geom.get("provinces", []):
        if not bool(entry.get("river_aware", False)):
            continue
        pid = str(int(entry["id"]))
        layer = provinces.setdefault(pid, {})
        if layer.get("river_aware"):
            continue
        layer["river_aware"] = True
        updated += 1

    print(f"sync_river_aware_terrain: {updated} terrain entries marked river_aware")
    if args.dry_run:
        print("  (dry-run — no file written)")
        return
    save_json(terrain_path, terrain_doc)


if __name__ == "__main__":
    main()
