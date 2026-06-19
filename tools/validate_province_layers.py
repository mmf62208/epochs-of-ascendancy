#!/usr/bin/env python3
"""Validate layered province JSON for Epochs of Ascendancy map data."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Dict, List, Set, Tuple


ROOT = Path(__file__).resolve().parents[1]


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def as_int_set(entries: List[Dict[str, Any]], key: str = "id") -> Set[int]:
    return {int(x[key]) for x in entries}


def polygon_centroid(points: List[List[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    x = sum(p[0] for p in points) / len(points)
    y = sum(p[1] for p in points) / len(points)
    return x, y


def point_in_polygon(x: float, y: float, poly: List[List[float]]) -> bool:
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i][0], poly[i][1]
        xj, yj = poly[j][0], poly[j][1]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi):
            inside = not inside
        j = i
    return inside


def validate(data_dir: Path, strict_base_match: bool = False) -> Tuple[List[str], List[str]]:
    errors: List[str] = []
    warnings: List[str] = []

    base_payload = load(data_dir / "provinces_base.json")
    geom_payload = load(data_dir / "provinces_geometry.json")
    base = base_payload["provinces"]
    geom = geom_payload["provinces"]
    adjacency = load(data_dir / "province_adjacency.json")["adjacency"]
    terrain = load(data_dir / "province_terrain_layer.json")["provinces"]
    cities = load(data_dir / "province_city_layer.json")["provinces"]
    resources = load(data_dir / "province_resources_layer.json")["provinces"]
    projects_path = data_dir / "project_sites.json"
    projects = load(projects_path)["sites"] if projects_path.exists() else []
    economy = load(data_dir / "province_economy_layer.json")["provinces"]
    states = load(data_dir / "province_states.json")["states"]
    regions = load(data_dir / "strategic_regions.json")["regions"]

    base_ids = as_int_set(base)
    geom_ids = as_int_set(geom)
    layer_ids = (
        {int(k) for k in adjacency.keys()}
        | {int(k) for k in terrain.keys()}
        | {int(k) for k in cities.keys()}
        | {int(k) for k in resources.keys()}
        | {int(k) for k in economy.keys()}
    )

    target_geom_count = int(geom_payload.get("meta", {}).get("target_province_count", len(geom_ids)))
    if not geom_ids.issubset(base_ids):
        errors.append(
            f"Geometry ids missing from base: {sorted(geom_ids - base_ids)[:20]}"
        )
    if strict_base_match and base_ids != geom_ids:
        errors.append(
            f"Base must match geometry exactly (base={len(base_ids)} geom={len(geom_ids)} "
            f"extra_in_base={len(base_ids - geom_ids)} missing={len(geom_ids - base_ids)})"
        )
    elif base_ids != geom_ids:
        warnings.append(
            f"Base/geometry differ (base={len(base_ids)} geom={len(geom_ids)}). "
            f"Run sync_phase1_base_catalog.py for strict match."
        )

    if len(geom_ids) < target_geom_count and target_geom_count > len(geom_ids):
        warnings.append(
            f"Geometry count below meta target ({len(geom_ids)} < {target_geom_count})"
        )

    if not geom_ids.issubset(layer_ids):
        missing = sorted(geom_ids - layer_ids)[:20]
        errors.append(f"Missing ids in layer files: {missing}")

    for site in projects:
        pid = int(site.get("province_id", -1))
        if pid not in geom_ids:
            errors.append(f"Project site references missing province {pid}")
            break

    geom_by_id = {int(g["id"]): g for g in geom}
    for pid in sorted(geom_ids):
        entry = geom_by_id[pid]
        pts = entry.get("points", [])
        if len(pts) < 3:
            errors.append(f"Province {pid} has fewer than 3 points")
            continue
        for p in pts:
            if not isinstance(p, list) or len(p) < 2:
                errors.append(f"Province {pid} has malformed point")
                break
        cx, cy = polygon_centroid(pts)
        anchor = entry.get("label_anchor")
        if anchor and len(anchor) >= 2:
            if not point_in_polygon(anchor[0], anchor[1], pts):
                warnings.append(f"Province {pid} label_anchor outside polygon (centroid fallback ok)")
        elif not point_in_polygon(cx, cy, pts):
            warnings.append(f"Province {pid} centroid outside polygon")

        if bool(entry.get("river_aware", False)):
            terr = terrain.get(str(pid), {})
            if not terr.get("river_aware") and terr.get("terrain") not in ("coastal", "river"):
                warnings.append(f"Province {pid} river_aware in geometry but not terrain layer")

    for sid, neigh in adjacency.items():
        a = int(sid)
        if a not in geom_ids:
            continue
        for b in neigh:
            b = int(b)
            if b not in geom_ids:
                errors.append(f"Adjacency {a} -> {b} references missing province")
                continue
            back = adjacency.get(str(b), [])
            if a not in [int(x) for x in back]:
                errors.append(f"Asymmetric adjacency {a} -> {b}")
                break

    for st in states:
        for pid in st.get("province_ids", []):
            if int(pid) not in geom_ids:
                errors.append(f"State {st['id']} references missing province {pid}")
                break
    for rg in regions:
        for pid in rg.get("province_ids", []):
            if int(pid) not in geom_ids:
                errors.append(f"Region {rg['id']} references missing province {pid}")
                break

    return errors, warnings


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dir",
        default="data/provinces",
        help="Province data directory relative to project root",
    )
    parser.add_argument(
        "--strict-base",
        action="store_true",
        help="Require base ids == geometry ids exactly",
    )
    args = parser.parse_args()

    data_dir = ROOT / args.dir
    if not data_dir.exists():
        raise SystemExit(f"Data dir not found: {data_dir}")

    errors, warnings = validate(data_dir, strict_base_match=args.strict_base)
    if errors:
        print("VALIDATION FAILED")
        for e in errors[:50]:
            print(" -", e)
        raise SystemExit(1)

    print("VALIDATION PASSED")
    for w in warnings[:30]:
        print("WARN:", w)
    geom_count = len(load(data_dir / "provinces_geometry.json")["provinces"])
    print(f"dir={data_dir.name} provinces={geom_count}")


if __name__ == "__main__":
    main()
