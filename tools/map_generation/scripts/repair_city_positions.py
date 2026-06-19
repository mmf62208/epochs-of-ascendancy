#!/usr/bin/env python3
"""Snap misplaced city markers onto province label_anchor / centroid."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[3]


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")
    print(f"  Wrote {path.relative_to(ROOT)}")


def centroid(points: List[List[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)


def anchor(entry: Dict[str, Any]) -> Tuple[float, float]:
    la = entry.get("label_anchor")
    if isinstance(la, list) and len(la) >= 2:
        return float(la[0]), float(la[1])
    return centroid(entry.get("points", []))


def dist(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default="data/provinces_phase1_test")
    parser.add_argument("--max-dist", type=float, default=250.0)
    parser.add_argument(
        "--bogus-y-max",
        type=float,
        default=150.0,
        help="Cities with y below this on large provinces are treated as misplaced world-strip coords",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    data_dir = ROOT / args.dir
    city_path = data_dir / "province_city_layer.json"
    geom = {
        int(p["id"]): p
        for p in load_json(data_dir / "provinces_geometry.json").get("provinces", [])
    }
    city_doc = load_json(city_path)
    provinces: Dict[str, Any] = city_doc.setdefault("provinces", {})

    repaired = 0
    checked = 0
    for pid_str, layer in provinces.items():
        pid = int(pid_str)
        if pid not in geom:
            continue
        ax, ay = anchor(geom[pid])
        for city in layer.get("cities", []):
            pos = city.get("position", [])
            if len(pos) < 2:
                continue
            checked += 1
            cx, cy = float(pos[0]), float(pos[1])
            d = dist((cx, cy), (ax, ay))
            misplaced = d > args.max_dist or (cy < args.bogus_y_max and d > 80.0)
            if not misplaced:
                continue
            city["position"] = [round(ax, 2), round(ay, 2)]
            repaired += 1
            print(
                f"  pid {pid} '{city.get('name', '?')}': "
                f"({cx:.0f},{cy:.0f}) -> ({ax:.0f},{ay:.0f}) dist was {d:.0f}px"
            )

    print(f"repair_city_positions: checked {checked}, repaired {repaired}")
    if args.dry_run:
        print("  (dry-run — no file written)")
        return
    if repaired:
        save_json(city_path, city_doc)


if __name__ == "__main__":
    main()
