#!/usr/bin/env python3
"""Densify province polygon boundaries for world-class map readability.

Phase-1 geometry is extremely coarse (median ~4 vertices, many triangles).
This script subdivides edges so provinces read as regions rather than wedges,
without changing province ids or adjacency (points only).

Usage:
  python3 tools/map_generation/scripts/densify_province_geometry.py \\
      --dir data/provinces_full_europe [--write] [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

Point = List[float]


def edge_len(a: Sequence[float], b: Sequence[float]) -> float:
    return math.hypot(float(a[0]) - float(b[0]), float(a[1]) - float(b[1]))


def lerp(a: Sequence[float], b: Sequence[float], t: float) -> Point:
    return [
        float(a[0]) + (float(b[0]) - float(a[0])) * t,
        float(a[1]) + (float(b[1]) - float(a[1])) * t,
    ]


def polygon_centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    sx = sum(float(p[0]) for p in points)
    sy = sum(float(p[1]) for p in points)
    n = float(len(points))
    return sx / n, sy / n


def densify_ring(
    points: Sequence[Sequence[float]],
    *,
    max_edge: float = 14.0,
    min_vertices: int = 12,
    max_vertices: int = 64,
) -> List[Point]:
    """Subdivide edges until max edge length and min vertex targets are met.

    Closed rings (first==last) are handled by dropping the duplicate closing
    point during processing and not re-closing (game data uses open rings).
    """
    if not points:
        return []
    ring: List[Point] = [[float(p[0]), float(p[1])] for p in points]
    # Drop explicit closing vertex if present
    if len(ring) >= 2 and ring[0][0] == ring[-1][0] and ring[0][1] == ring[-1][1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return ring

    # Iteratively split longest edges until targets met or cap reached
    guard = 0
    while guard < 10_000:
        guard += 1
        n = len(ring)
        if n >= max_vertices:
            break
        # Find edges
        edges: List[Tuple[float, int]] = []
        for i in range(n):
            j = (i + 1) % n
            edges.append((edge_len(ring[i], ring[j]), i))
        edges.sort(reverse=True)
        longest, idx = edges[0]
        need_min = n < min_vertices
        need_edge = longest > max_edge
        if not need_min and not need_edge:
            break
        # Insert midpoint after idx
        j = (idx + 1) % n
        mid = lerp(ring[idx], ring[j], 0.5)
        # Slight inward bias for very long edges only (organic look, stay near edge)
        if longest > max_edge * 1.5:
            cx, cy = polygon_centroid(ring)
            # pull midpoint 3% toward centroid (still on-ish boundary for coarse shapes)
            mid[0] = mid[0] * 0.97 + cx * 0.03
            mid[1] = mid[1] * 0.97 + cy * 0.03
        ring.insert(idx + 1, mid)

    return ring


def densify_province_entry(
    entry: Dict[str, Any],
    *,
    max_edge: float = 14.0,
    min_vertices: int = 12,
    max_vertices: int = 64,
) -> Dict[str, Any]:
    """Return a new province geometry dict with densified points."""
    out = dict(entry)
    pts = entry.get("points") or []
    new_pts = densify_ring(
        pts, max_edge=max_edge, min_vertices=min_vertices, max_vertices=max_vertices
    )
    out["points"] = new_pts
    # Refresh label_anchor to centroid if missing or still default-ish
    cx, cy = polygon_centroid(new_pts)
    la = entry.get("label_anchor")
    if not la or not isinstance(la, (list, tuple)) or len(la) < 2:
        out["label_anchor"] = [cx, cy]
    return out


def densify_geometry_payload(
    geom_payload: Dict[str, Any],
    *,
    max_edge: float = 14.0,
    min_vertices: int = 12,
    max_vertices: int = 64,
) -> Dict[str, Any]:
    """Pure transform of provinces_geometry.json structure."""
    out = dict(geom_payload)
    provs = geom_payload.get("provinces") or []
    new_provs = [
        densify_province_entry(
            p, max_edge=max_edge, min_vertices=min_vertices, max_vertices=max_vertices
        )
        for p in provs
    ]
    out["provinces"] = new_provs
    meta = dict(out.get("meta") or {})
    sizes = [len(p.get("points") or []) for p in new_provs]
    meta["densified"] = "densify_province_geometry.py"
    meta["densify_max_edge"] = max_edge
    meta["densify_min_vertices"] = min_vertices
    if sizes:
        meta["vertex_min"] = min(sizes)
        meta["vertex_max"] = max(sizes)
        meta["vertex_avg"] = round(sum(sizes) / len(sizes), 2)
        meta["vertex_median"] = sorted(sizes)[len(sizes) // 2]
        meta["triangle_count"] = sum(1 for s in sizes if s == 3)
    out["meta"] = meta
    return out


def geometry_stats(provinces: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    sizes = [len(p.get("points") or []) for p in provinces]
    if not sizes:
        return {"count": 0}
    return {
        "count": len(sizes),
        "min": min(sizes),
        "max": max(sizes),
        "avg": sum(sizes) / len(sizes),
        "median": sorted(sizes)[len(sizes) // 2],
        "triangles": sum(1 for s in sizes if s == 3),
        "below_12": sum(1 for s in sizes if s < 12),
    }


def run_on_dir(
    data_dir: Path,
    *,
    write: bool = False,
    max_edge: float = 14.0,
    min_vertices: int = 12,
    max_vertices: int = 64,
) -> Dict[str, Any]:
    geom_path = data_dir / "provinces_geometry.json"
    if not geom_path.exists():
        raise FileNotFoundError(geom_path)
    payload = json.loads(geom_path.read_text(encoding="utf-8"))
    before = geometry_stats(payload.get("provinces") or [])
    densified = densify_geometry_payload(
        payload, max_edge=max_edge, min_vertices=min_vertices, max_vertices=max_vertices
    )
    after = geometry_stats(densified.get("provinces") or [])
    # Id stability
    ids_before = [int(p["id"]) for p in payload.get("provinces") or []]
    ids_after = [int(p["id"]) for p in densified.get("provinces") or []]
    if ids_before != ids_after:
        raise RuntimeError("Province id order/set changed during densify — abort")

    if write:
        geom_path.write_text(
            json.dumps(densified, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )

    return {
        "before": before,
        "after": after,
        "ids_stable": True,
        "wrote": write,
        "path": str(geom_path),
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dir",
        default="data/provinces_full_europe",
        help="Province data directory relative to project root",
    )
    parser.add_argument("--write", action="store_true", help="Write densified geometry")
    parser.add_argument("--dry-run", action="store_true", help="Force dry-run")
    parser.add_argument("--max-edge", type=float, default=14.0)
    parser.add_argument("--min-vertices", type=int, default=12)
    parser.add_argument("--max-vertices", type=int, default=64)
    args = parser.parse_args(argv)

    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    write = bool(args.write) and not args.dry_run
    stats = run_on_dir(
        data_dir,
        write=write,
        max_edge=args.max_edge,
        min_vertices=args.min_vertices,
        max_vertices=args.max_vertices,
    )
    mode = "WROTE" if write else "DRY-RUN"
    print(f"[{mode}] {stats['path']}")
    print(f"  before: {stats['before']}")
    print(f"  after:  {stats['after']}")
    print(f"  ids_stable: {stats['ids_stable']}")

    after = stats["after"]
    ok = (
        after.get("count", 0) > 0
        and after.get("triangles", 1) == 0
        and after.get("median", 0) >= args.min_vertices
        and after.get("below_12", 1) == 0
    )
    if not ok:
        print("FAIL: densify quality gates not met", file=sys.stderr)
        return 1
    print("PASS: no triangles, median>=min_vertices, all polys densified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
