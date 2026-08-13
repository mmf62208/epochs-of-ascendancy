#!/usr/bin/env python3
"""Rebuild strategic regions from live province geometry centroids.

Uses k-means on canvas centroids (the map's real layout), then labels each
cluster by the nearest named theater seed so regions are geographically
coherent on the *actual* board (which still mixes expanded Europe + world
seed geometry).

Usage:
  python3 tools/map_generation/scripts/rebuild_strategic_regions.py \\
      --dir data/provinces_full_europe [--write] [--k 15]
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

# Label dictionary: preferred display names + canvas hints (for naming clusters).
THEATER_LABELS: List[Tuple[str, float, float]] = [
    ("British Isles", 2030.0, 442.0),
    ("France", 2059.0, 472.0),
    ("Iberia", 2006.0, 563.0),
    ("Low Countries", 2110.0, 430.0),
    ("Germany", 2185.0, 431.0),
    ("Italy", 2190.0, 546.0),
    ("Alps & Danube", 2229.0, 477.0),
    ("Scandinavia", 2180.0, 340.0),
    ("Poland & Baltic", 2286.0, 428.0),
    ("Balkans", 2320.0, 560.0),
    ("Anatolia & Straits", 2378.0, 557.0),
    ("Western Russia", 2461.0, 394.0),
    ("Black Sea & Caucasus", 2450.0, 520.0),
    ("North Africa Coast", 2100.0, 620.0),
    ("Atlantic Approaches", 1950.0, 480.0),
    ("Eastern Frontiers", 2800.0, 500.0),
    ("Mediterranean East", 2400.0, 700.0),
    ("High North", 2200.0, 300.0),
    ("Western Approaches", 1200.0, 600.0),
    ("Far East Theater", 3400.0, 600.0),
]


def centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    return (
        sum(float(p[0]) for p in points) / len(points),
        sum(float(p[1]) for p in points) / len(points),
    )


def _dist2(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def kmeans(
    points: List[Tuple[float, float]],
    k: int,
    *,
    iters: int = 40,
    seed: int = 42,
) -> Tuple[List[int], List[Tuple[float, float]]]:
    """Simple k-means. Returns (labels, centers)."""
    if not points:
        return [], []
    k = max(1, min(k, len(points)))
    rng = random.Random(seed)
    # Init: pick spread seeds via greedy farthest-point
    centers: List[Tuple[float, float]] = [points[rng.randrange(len(points))]]
    while len(centers) < k:
        best_p = points[0]
        best_d = -1.0
        for p in points:
            d = min(_dist2(p, c) for c in centers)
            if d > best_d:
                best_d = d
                best_p = p
        centers.append(best_p)

    labels = [0] * len(points)
    for _ in range(iters):
        # Assign
        for i, p in enumerate(points):
            labels[i] = min(range(k), key=lambda j: _dist2(p, centers[j]))
        # Update
        new_centers: List[Tuple[float, float]] = []
        for j in range(k):
            members = [points[i] for i, lab in enumerate(labels) if lab == j]
            if not members:
                new_centers.append(centers[j])
            else:
                new_centers.append(
                    (
                        sum(m[0] for m in members) / len(members),
                        sum(m[1] for m in members) / len(members),
                    )
                )
        if all(_dist2(a, b) < 1e-6 for a, b in zip(centers, new_centers)):
            centers = new_centers
            break
        centers = new_centers
    return labels, centers


def label_center(cx: float, cy: float, used: set) -> str:
    ranked = sorted(
        THEATER_LABELS, key=lambda t: (cx - t[1]) ** 2 + (cy - t[2]) ** 2
    )
    for name, _, _ in ranked:
        if name not in used:
            used.add(name)
            return name
    # Fallback unique
    n = 1
    while f"Theater {n}" in used:
        n += 1
    name = f"Theater {n}"
    used.add(name)
    return name


def rebuild_regions(
    geom_provinces: List[Dict[str, Any]],
    *,
    k: int = 15,
    seed: int = 42,
) -> Dict[str, Any]:
    ids: List[int] = []
    pts: List[Tuple[float, float]] = []
    for g in geom_provinces:
        ids.append(int(g["id"]))
        pts.append(centroid(g.get("points") or []))

    labels, centers = kmeans(pts, k, seed=seed)
    buckets: Dict[int, List[int]] = {i: [] for i in range(len(centers))}
    for pid, lab in zip(ids, labels):
        buckets[lab].append(pid)

    used_names: set = set()
    regions: List[Dict[str, Any]] = []
    rid = 1
    # Sort clusters by size desc for stable numbering of large theaters first
    order = sorted(buckets.keys(), key=lambda j: (-len(buckets[j]), j))
    for j in order:
        pids = sorted(buckets[j])
        if not pids:
            continue
        cx, cy = centers[j]
        name = label_center(cx, cy, used_names)
        regions.append(
            {
                "id": rid,
                "name": name,
                "province_ids": pids,
                "province_count": len(pids),
                "center": [round(cx, 2), round(cy, 2)],
                "notes": f"k-means cluster labeled nearest '{name}' seed",
            }
        )
        rid += 1

    return {
        "version": 3,
        "source": "rebuild_strategic_regions.py",
        "assignment": "kmeans_centroid_nearest_label",
        "k": k,
        "seed": seed,
        "regions": regions,
    }


def quality_gates(payload: Dict[str, Any], expected_province_count: int) -> Dict[str, Any]:
    regions = payload.get("regions") or []
    all_ids: List[int] = []
    for r in regions:
        all_ids.extend(int(x) for x in r.get("province_ids") or [])
    unique = set(all_ids)
    empty = [r["name"] for r in regions if not r.get("province_ids")]
    sizes = [len(r.get("province_ids") or []) for r in regions]
    return {
        "region_count": len(regions),
        "total_assignments": len(all_ids),
        "unique_provinces": len(unique),
        "expected": expected_province_count,
        "empty_regions": empty,
        "no_dup_ids": len(all_ids) == len(unique),
        "full_coverage": len(unique) == expected_province_count
        and len(all_ids) == expected_province_count,
        "max_region_share": (max(sizes) / expected_province_count)
        if expected_province_count and sizes
        else 1.0,
        "min_region_size": min(sizes) if sizes else 0,
    }


def rebalance_payload(
    payload: Dict[str, Any],
    id_to_pt: Dict[int, Tuple[float, float]],
    *,
    max_share: float = 0.12,
    min_size: int = 8,
    seed: int = 42,
) -> Dict[str, Any]:
    """Split oversized regions and absorb tiny ones into nearest neighbor.

    Guarantees max region size share <= max_share (when geometrically possible)
    and merges regions smaller than min_size into the nearest larger theater.
    """
    expected = len(id_to_pt)
    if expected == 0:
        return payload
    max_allowed = max(min_size, int(math.floor(expected * max_share)))
    regions: List[Dict[str, Any]] = [dict(r) for r in (payload.get("regions") or [])]
    used_names: set = {str(r.get("name") or "") for r in regions}
    rng_seed = seed

    # --- Split oversized ---
    guard = 0
    while guard < 200:
        guard += 1
        oversized = [
            r
            for r in regions
            if len(r.get("province_ids") or []) > max_allowed
        ]
        if not oversized:
            break
        r = max(oversized, key=lambda x: len(x.get("province_ids") or []))
        pids = [int(x) for x in (r.get("province_ids") or [])]
        pts = [id_to_pt[pid] for pid in pids if pid in id_to_pt]
        if len(pts) < 2:
            break
        # Split into 2 (or more if still huge)
        parts = max(2, int(math.ceil(len(pids) / float(max_allowed))))
        parts = min(parts, len(pts))
        labels, centers = kmeans(pts, parts, seed=rng_seed + guard)
        buckets: Dict[int, List[int]] = {i: [] for i in range(parts)}
        valid_pids = [pid for pid in pids if pid in id_to_pt]
        for pid, lab in zip(valid_pids, labels):
            buckets[lab].append(pid)
        # Replace r with non-empty subregions
        regions = [x for x in regions if x is not r]
        base_name = str(r.get("name") or "Theater")
        for j, center in enumerate(centers):
            sub = sorted(buckets.get(j) or [])
            if not sub:
                continue
            name = base_name if j == 0 and base_name not in used_names else None
            if name is None:
                name = label_center(center[0], center[1], used_names)
            else:
                used_names.add(name)
            # If parent name already used, make part suffix
            if j > 0 or any(
                x.get("name") == base_name for x in regions
            ):
                suffix = j + 1
                cand = f"{base_name} {suffix}"
                while cand in used_names:
                    suffix += 1
                    cand = f"{base_name} {suffix}"
                name = cand
                used_names.add(name)
            regions.append(
                {
                    "id": 0,
                    "name": name,
                    "province_ids": sub,
                    "province_count": len(sub),
                    "center": [round(center[0], 2), round(center[1], 2)],
                    "notes": f"rebalanced split from oversized (max_share={max_share})",
                }
            )

    # --- Absorb tiny regions into nearest non-tiny by center ---
    guard = 0
    while guard < 200:
        guard += 1
        tiny = [r for r in regions if 0 < len(r.get("province_ids") or []) < min_size]
        large = [r for r in regions if len(r.get("province_ids") or []) >= min_size]
        if not tiny or not large:
            break
        t = tiny[0]
        t_center = t.get("center") or [0.0, 0.0]
        tc = (float(t_center[0]), float(t_center[1]))
        best = min(
            large,
            key=lambda r: _dist2(
                tc,
                (
                    float((r.get("center") or [0, 0])[0]),
                    float((r.get("center") or [0, 0])[1]),
                ),
            ),
        )
        merged = sorted(
            set(int(x) for x in (best.get("province_ids") or []))
            | set(int(x) for x in (t.get("province_ids") or []))
        )
        # If merge would exceed max_allowed, skip and raise min_size behavior: attach to next
        if len(merged) > max_allowed and len(large) > 1:
            large2 = [r for r in large if r is not best]
            if large2:
                best = min(
                    large2,
                    key=lambda r: _dist2(
                        tc,
                        (
                            float((r.get("center") or [0, 0])[0]),
                            float((r.get("center") or [0, 0])[1]),
                        ),
                    ),
                )
                merged = sorted(
                    set(int(x) for x in (best.get("province_ids") or []))
                    | set(int(x) for x in (t.get("province_ids") or []))
                )
        best["province_ids"] = merged
        best["province_count"] = len(merged)
        # recompute center
        mpts = [id_to_pt[pid] for pid in merged if pid in id_to_pt]
        if mpts:
            best["center"] = [
                round(sum(p[0] for p in mpts) / len(mpts), 2),
                round(sum(p[1] for p in mpts) / len(mpts), 2),
            ]
        regions = [r for r in regions if r is not t]

    # Renumber ids, sort by size desc
    regions.sort(key=lambda r: (-len(r.get("province_ids") or []), str(r.get("name") or "")))
    for i, r in enumerate(regions, start=1):
        r["id"] = i
        r["province_count"] = len(r.get("province_ids") or [])

    out = dict(payload)
    out["regions"] = regions
    out["source"] = "rebuild_strategic_regions.py+rebalance"
    out["assignment"] = "kmeans_centroid_nearest_label+rebalance"
    out["max_share_target"] = max_share
    out["min_size_target"] = min_size
    return out


def run_on_dir(
    data_dir: Path,
    write: bool = False,
    k: int = 15,
    seed: int = 42,
    *,
    max_share: Optional[float] = None,
    min_size: int = 1,
) -> Dict[str, Any]:
    geom_path = data_dir / "provinces_geometry.json"
    out_path = data_dir / "strategic_regions.json"
    geom = json.loads(geom_path.read_text(encoding="utf-8"))
    provs = geom.get("provinces") or []
    payload = rebuild_regions(provs, k=k, seed=seed)
    if max_share is not None and max_share > 0:
        id_to_pt: Dict[int, Tuple[float, float]] = {}
        for g in provs:
            id_to_pt[int(g["id"])] = centroid(g.get("points") or [])
        payload = rebalance_payload(
            payload,
            id_to_pt,
            max_share=max_share,
            min_size=max(1, min_size),
            seed=seed,
        )
    gates = quality_gates(payload, len(provs))
    if write:
        out_path.write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    return {
        "path": str(out_path),
        "wrote": write,
        "gates": gates,
        "regions": [(r["name"], r["province_count"]) for r in payload["regions"]],
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_full_europe")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--k", type=int, default=15)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument(
        "--max-share",
        type=float,
        default=None,
        help="If set, split oversized regions until max share <= this (e.g. 0.12)",
    )
    ap.add_argument(
        "--min-size",
        type=int,
        default=8,
        help="Absorb regions smaller than this into nearest neighbor (with --max-share)",
    )
    args = ap.parse_args(argv)
    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    write = bool(args.write) and not args.dry_run
    result = run_on_dir(
        data_dir,
        write=write,
        k=args.k,
        seed=args.seed,
        max_share=args.max_share,
        min_size=args.min_size,
    )
    mode = "WROTE" if write else "DRY-RUN"
    print(f"[{mode}] {result['path']}")
    print("  gates:", result["gates"])
    for name, n in result["regions"][:25]:
        print(f"  - {name}: {n}")
    if len(result["regions"]) > 25:
        print(f"  ... +{len(result['regions']) - 25} more")
    g = result["gates"]
    share_cap = float(args.max_share) if args.max_share is not None else 0.35
    ok = (
        g["region_count"] >= 12
        and g["full_coverage"]
        and g["no_dup_ids"]
        and len(g["empty_regions"]) == 0
        and g["max_region_share"] <= share_cap + 1e-9
        and g["min_region_size"] >= 1
    )
    if not ok:
        print("FAIL strategic region gates", file=sys.stderr)
        return 1
    print(
        f"PASS: >=12 non-empty regions, full unique coverage, max_share<={share_cap:.0%}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
