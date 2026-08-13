"""Geometry-aware shared-edge adjacency for EOA province boards.

Replaces pure centroid-KNN for land where rings share quantized edges.
Falls back to KNN only for residual orphans (islands / cracked scaffold rings).

Honest method tags:
- shared_edge: neighbor found via shared quantized ring edge
- knn_fallback: orphan fill only
"""
from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
WATER_DOMAINS = frozenset({"sea", "strait", "lake"})

PRODUCT_STEPS = ("shared_edge", "knn_fallback", "integrity", "write")


def _centroid(pts: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not pts:
        return 0.0, 0.0
    ring = list(pts)
    if len(ring) >= 2 and float(ring[0][0]) == float(ring[-1][0]) and float(ring[0][1]) == float(ring[-1][1]):
        ring = ring[:-1]
    if not ring:
        return 0.0, 0.0
    return sum(float(p[0]) for p in ring) / len(ring), sum(float(p[1]) for p in ring) / len(ring)


def _edge_key(a: Sequence[float], b: Sequence[float], quant: float) -> Tuple[Tuple[int, int], Tuple[int, int]]:
    """Undirected quantized edge key from two vertices."""
    ax, ay = int(round(float(a[0]) / quant)), int(round(float(a[1]) / quant))
    bx, by = int(round(float(b[0]) / quant)), int(round(float(b[1]) / quant))
    p1, p2 = (ax, ay), (bx, by)
    if p1 == p2:
        return p1, p2
    return (p1, p2) if p1 < p2 else (p2, p1)


def load_board_geometry(data_dir: Path) -> Tuple[Dict[int, List[List[float]]], Dict[int, bool]]:
    """Return id→ring points and id→is_water."""
    geom = json.loads((data_dir / "provinces_geometry.json").read_text(encoding="utf-8"))
    base = json.loads((data_dir / "provinces_base.json").read_text(encoding="utf-8"))
    provs = base.get("provinces") or []
    water: Dict[int, bool] = {}
    for p in provs:
        pid = int(p["id"])
        dom = str(p.get("domain") or "land").lower()
        water[pid] = bool(p.get("is_sea")) or dom in WATER_DOMAINS
    rings: Dict[int, List[List[float]]] = {}
    for g in geom.get("provinces") or []:
        pid = int(g["id"])
        pts = g.get("points") or []
        ring = [[float(pt[0]), float(pt[1])] for pt in pts if isinstance(pt, (list, tuple)) and len(pt) >= 2]
        if len(ring) >= 3:
            rings[pid] = ring
        if pid not in water:
            water[pid] = bool(g.get("is_sea", False))
    return rings, water


def _collect_shared_at_quant(
    rings: Dict[int, List[List[float]]],
    quant: float,
) -> Tuple[Dict[int, Set[int]], int]:
    edge_to_pids: Dict[Tuple[Tuple[int, int], Tuple[int, int]], Set[int]] = defaultdict(set)
    for pid, ring in rings.items():
        if len(ring) < 2:
            continue
        closed = ring
        if ring[0][0] != ring[-1][0] or ring[0][1] != ring[-1][1]:
            closed = ring + [ring[0]]
        for i in range(len(closed) - 1):
            ek = _edge_key(closed[i], closed[i + 1], quant)
            if ek[0] == ek[1]:
                continue
            edge_to_pids[ek].add(int(pid))
    shared: Dict[int, Set[int]] = defaultdict(set)
    pair_hits = 0
    for _ek, pids in edge_to_pids.items():
        if len(pids) < 2:
            continue
        # Cap fan-out: if too many provinces share one quantized edge, skip (noise).
        if len(pids) > 8:
            continue
        plist = sorted(pids)
        for i in range(len(plist)):
            for j in range(i + 1, len(plist)):
                a, b = plist[i], plist[j]
                shared[a].add(b)
                shared[b].add(a)
                pair_hits += 1
    return shared, pair_hits


def _near_vertex_links(
    rings: Dict[int, List[List[float]]],
    candidate_pids: Sequence[int],
    all_land_ids: Sequence[int],
    *,
    touch_dist: float,
    max_nbrs: int = 6,
) -> Dict[int, Set[int]]:
    """Link residual land provinces whose rings nearly touch (vertex proximity).

    Spatial-hash of land vertices; candidates (orphans after shared-edge) get
    neighbors among land that share a grid cell within touch_dist. Caps fan-out
    so a cracked ring cannot attach to half the continent.
    """
    if touch_dist <= 0 or not candidate_pids:
        return {}
    cell = max(touch_dist, 1.0)
    inv = 1.0 / cell
    # Hash land vertices: cell → set of pids
    grid: Dict[Tuple[int, int], Set[int]] = defaultdict(set)
    land_set = set(int(x) for x in all_land_ids)
    for pid in land_set:
        ring = rings.get(int(pid)) or []
        # subsample long rings for speed
        step = max(1, len(ring) // 48)
        for i in range(0, len(ring), step):
            pt = ring[i]
            if len(pt) < 2:
                continue
            cx = int(float(pt[0]) * inv)
            cy = int(float(pt[1]) * inv)
            grid[(cx, cy)].add(int(pid))

    touch2 = float(touch_dist) * float(touch_dist)
    out: Dict[int, Set[int]] = defaultdict(set)
    for pid in candidate_pids:
        pid = int(pid)
        ring = rings.get(pid) or []
        if len(ring) < 2:
            continue
        scores: Dict[int, float] = {}
        step = max(1, len(ring) // 64)
        for i in range(0, len(ring), step):
            pt = ring[i]
            if len(pt) < 2:
                continue
            x, y = float(pt[0]), float(pt[1])
            cx, cy = int(x * inv), int(y * inv)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for oid in grid.get((cx + dx, cy + dy), ()):
                        if oid == pid or oid not in land_set:
                            continue
                        # cheapest: use that other province centroid-ish sample
                        oring = rings.get(oid) or []
                        if not oring:
                            continue
                        # compare against a few verts of oid near this cell
                        best = scores.get(oid, 1e30)
                        ostep = max(1, len(oring) // 32)
                        for j in range(0, len(oring), ostep):
                            op = oring[j]
                            if len(op) < 2:
                                continue
                            d = (x - float(op[0])) ** 2 + (y - float(op[1])) ** 2
                            if d < best:
                                best = d
                        if best <= touch2:
                            scores[oid] = best
        # keep nearest max_nbrs
        ranked = sorted(scores.items(), key=lambda kv: kv[1])[: max(1, int(max_nbrs))]
        for oid, _d in ranked:
            out[pid].add(int(oid))
            out[int(oid)].add(pid)
    return out


def build_shared_edge_adjacency(
    rings: Dict[int, List[List[float]]],
    water: Dict[int, bool],
    *,
    quant: float = 0.5,
    knn_k: int = 4,
    min_shared_edges: int = 1,
    multi_quant: bool = True,
    near_vertex_touch: float = 0.0,
    near_vertex_max_nbrs: int = 6,
) -> Dict[str, Any]:
    """Build undirected adjacency from shared quantized edges + orphan KNN fallback.

    Optional near_vertex_touch (>0): after shared-edge pass, residual land without
    a shared edge get near-vertex links (geometry-touch residual) before KNN.
    Those still count toward land_shared_coverage as geometry-backed neighbors.
    """
    shared: Dict[int, Set[int]] = defaultdict(set)
    shared_edge_pairs = 0
    quant_levels = [quant]
    if multi_quant:
        for q in (quant * 0.5, quant * 2.0, quant * 4.0):
            if q > 0.05 and q not in quant_levels:
                quant_levels.append(q)
    for q in quant_levels:
        part, hits = _collect_shared_at_quant(rings, q)
        shared_edge_pairs += hits
        for a, nbrs in part.items():
            shared[a].update(nbrs)

    method_by_edge: Dict[Tuple[int, int], str] = {}
    for a, nbrs in shared.items():
        for b in nbrs:
            method_by_edge[(min(a, b), max(a, b))] = "shared_edge"

    # Centroids for KNN fallback
    cents: Dict[int, Tuple[float, float]] = {pid: _centroid(ring) for pid, ring in rings.items()}
    land_ids = [pid for pid in rings if not water.get(pid, False)]
    water_ids = [pid for pid in rings if water.get(pid, False)]

    knn_added = 0
    near_vertex_added = 0
    orphans_before_near = [pid for pid in land_ids if len(shared.get(pid) or set()) == 0]

    # Geometry residual: near-vertex touch for cracked shared-edge miss
    if near_vertex_touch and near_vertex_touch > 0 and orphans_before_near:
        near_links = _near_vertex_links(
            rings,
            orphans_before_near,
            land_ids,
            touch_dist=float(near_vertex_touch),
            max_nbrs=int(near_vertex_max_nbrs),
        )
        for a, nbrs in near_links.items():
            for b in nbrs:
                if b not in shared[a]:
                    shared[a].add(b)
                    shared[b].add(a)
                    method_by_edge[(min(a, b), max(a, b))] = "near_vertex"
                    near_vertex_added += 1

    orphans_before = [pid for pid in land_ids if len(shared.get(pid) or set()) == 0]

    def knn_fill(pid: int, candidates: List[int], k: int) -> List[int]:
        cx, cy = cents.get(pid, (0.0, 0.0))
        dists = []
        for oid in candidates:
            if oid == pid:
                continue
            ox, oy = cents.get(oid, (0.0, 0.0))
            d = (cx - ox) ** 2 + (cy - oy) ** 2
            dists.append((d, oid))
        dists.sort()
        return [oid for _, oid in dists[:k]]

    adj: Dict[int, Set[int]] = {pid: set(shared.get(pid) or set()) for pid in rings}

    # Land orphans: KNN to land (and one sea if coastal-ish)
    for pid in orphans_before:
        for nb in knn_fill(pid, land_ids, knn_k):
            if nb not in adj[pid]:
                adj[pid].add(nb)
                adj[nb].add(pid)
                method_by_edge[(min(pid, nb), max(pid, nb))] = "knn_fallback"
                knn_added += 1
        # optional sea link for coastal feel
        if water_ids:
            for nb in knn_fill(pid, water_ids, 1):
                if nb not in adj[pid]:
                    adj[pid].add(nb)
                    adj.setdefault(nb, set()).add(pid)
                    method_by_edge[(min(pid, nb), max(pid, nb))] = "knn_fallback"
                    knn_added += 1

    # Water with zero neighbors: KNN among water + nearest land
    for pid in water_ids:
        if len(adj.get(pid) or set()) > 0:
            continue
        for nb in knn_fill(pid, water_ids, max(2, knn_k // 2)):
            adj.setdefault(pid, set()).add(nb)
            adj.setdefault(nb, set()).add(pid)
            method_by_edge[(min(pid, nb), max(pid, nb))] = "knn_fallback"
            knn_added += 1
        if land_ids:
            for nb in knn_fill(pid, land_ids, 1):
                adj.setdefault(pid, set()).add(nb)
                adj.setdefault(nb, set()).add(pid)
                method_by_edge[(min(pid, nb), max(pid, nb))] = "knn_fallback"
                knn_added += 1

    # Serialize adjacency
    adjacency: Dict[str, List[int]] = {}
    for pid in sorted(rings.keys()):
        adjacency[str(pid)] = sorted(int(x) for x in (adj.get(pid) or set()))

    land_orphan_after = [
        pid for pid in land_ids if len(adj.get(pid) or set()) == 0
    ]
    degrees = [len(v) for v in adjacency.values()]
    shared_only_degs = [len(shared.get(pid) or set()) for pid in land_ids]
    land_with_shared = sum(1 for pid in land_ids if len(shared.get(pid) or set()) > 0)
    method_tag = "shared_edge_plus_knn_fallback"
    if near_vertex_added:
        method_tag = "shared_edge_near_vertex_plus_knn"

    return {
        "version": 2,
        "method": method_tag,
        "source": "shared_edge_adjacency_product",
        "quant": quant,
        "knn_k": knn_k,
        "near_vertex_touch": float(near_vertex_touch or 0.0),
        "adjacency": adjacency,
        "stats": {
            "province_n": len(rings),
            "land_n": len(land_ids),
            "water_n": len(water_ids),
            "shared_edge_pairs": shared_edge_pairs // 2 if shared_edge_pairs else 0,
            "land_with_shared_edge": land_with_shared,
            "land_shared_coverage": land_with_shared / max(1, len(land_ids)),
            "orphan_land_before_near_vertex": len(orphans_before_near),
            "near_vertex_edges_added": near_vertex_added,
            "orphan_land_before_knn": len(orphans_before),
            "orphan_land_after": len(land_orphan_after),
            "knn_edges_added": knn_added,
            "degree_min": min(degrees) if degrees else 0,
            "degree_max": max(degrees) if degrees else 0,
            "degree_mean": (sum(degrees) / len(degrees)) if degrees else 0.0,
            "land_shared_degree_mean": (sum(shared_only_degs) / len(shared_only_degs)) if shared_only_degs else 0.0,
            "better_than_knn_alone": land_with_shared > 0 and land_with_shared / max(1, len(land_ids)) >= 0.5,
        },
        "empty": False,
    }


def adjacency_integrity(data_dir: Path | str) -> Dict[str, Any]:
    data_dir = Path(data_dir)
    path = data_dir / "province_adjacency.json"
    if not path.is_file():
        return {"ok": False, "summary": "missing province_adjacency.json", "empty": True}
    data = json.loads(path.read_text(encoding="utf-8"))
    adj = data.get("adjacency") or {}
    method = str(data.get("method") or "")
    stats = data.get("stats") or {}
    if not stats and method:
        # recompute light stats
        degs = [len(v) for v in adj.values() if isinstance(v, list)]
        stats = {
            "province_n": len(adj),
            "degree_mean": (sum(degs) / len(degs)) if degs else 0,
            "orphan_land_after": 0,
        }
    rings, water = load_board_geometry(data_dir)
    land_ids = [pid for pid in rings if not water.get(pid, False)]
    orphan_land = []
    for pid in land_ids:
        nbrs = adj.get(str(pid)) or adj.get(pid) or []
        if not nbrs:
            orphan_land.append(pid)
    # Symmetric check sample
    asym = 0
    checked = 0
    for pid_s, nbrs in list(adj.items())[:500]:
        pid = int(pid_s)
        for n in nbrs:
            checked += 1
            back = adj.get(str(n)) or adj.get(n) or []
            if pid not in back and int(pid) not in [int(x) for x in back]:
                asym += 1
    is_shared = "shared_edge" in method
    coverage = float(stats.get("land_shared_coverage") or 0.0)
    if not coverage and is_shared:
        coverage = float(stats.get("land_with_shared_edge") or 0) / max(1, len(land_ids))
    land_with = int(stats.get("land_with_shared_edge") or 0)
    # Pilot densify should hit ≥0.5 shared coverage; scaffold world_full may be lower but
    # must still be shared_edge-primary (not pure KNN) with zero land orphans.
    coverage_ok = coverage >= 0.5 or (coverage >= 0.35 and land_with >= max(200, len(land_ids) // 4))
    ok = (
        len(adj) >= max(100, int(0.9 * len(rings)))
        and len(orphan_land) == 0
        and is_shared
        and coverage_ok
        and asym == 0
        and method != "k_nearest_centroid"
    )
    return {
        "ok": ok,
        "method": method,
        "province_n": len(adj),
        "land_n": len(land_ids),
        "orphan_land": len(orphan_land),
        "asymmetric_edges_sample": asym,
        "stats": stats,
        "summary": "Adjacency integrity %s · method=%s · orphans=%d · coverage≈%.2f"
        % ("PASS" if ok else "FAIL", method or "unknown", len(orphan_land), coverage),
        "empty": False,
    }


def write_shared_edge_adjacency(
    data_dir: Path | str,
    *,
    quant: float = 0.5,
    knn_k: int = 4,
    near_vertex_touch: float = 0.0,
    near_vertex_max_nbrs: int = 6,
    multi_quant: bool = True,
) -> Dict[str, Any]:
    data_dir = Path(data_dir)
    rings, water = load_board_geometry(data_dir)
    built = build_shared_edge_adjacency(
        rings,
        water,
        quant=quant,
        knn_k=knn_k,
        multi_quant=multi_quant,
        near_vertex_touch=near_vertex_touch,
        near_vertex_max_nbrs=near_vertex_max_nbrs,
    )
    out_path = data_dir / "province_adjacency.json"
    payload = {
        "version": built["version"],
        "method": built["method"],
        "source": built["source"],
        "quant": built["quant"],
        "knn_k": built["knn_k"],
        "near_vertex_touch": built.get("near_vertex_touch", 0.0),
        "stats": built["stats"],
        "adjacency": built["adjacency"],
    }
    out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    gate = adjacency_integrity(data_dir)
    return {
        "ok": bool(gate.get("ok")),
        "path": str(out_path),
        "stats": built["stats"],
        "integrity": gate,
        "summary": "Wrote shared-edge adjacency · %s · %s"
        % (data_dir.name, gate.get("summary")),
    }


def write_pilot_and_world() -> Dict[str, Any]:
    results = {}
    for rel, quant in (
        ("data/provinces_pilot_europe", 0.35),  # denser verts → finer quant
        ("data/provinces_world_full", 2.0),  # scaffold rings need coarser quant + multi-pass
    ):
        d = ROOT / rel
        if d.is_dir() and (d / "provinces_geometry.json").is_file():
            results[rel] = write_shared_edge_adjacency(d, quant=quant, knn_k=4)
    ok = all(bool(v.get("ok")) for v in results.values()) if results else False
    return {"ok": ok, "boards": results, "summary": "shared-edge boards %s" % ("PASS" if ok else "FAIL")}
