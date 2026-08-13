#!/usr/bin/env python3
"""Merge US TIGER counties on world_accurate into 1–4 playable provinces per state.

Plan product: tools/map_generation/lib/us_state_province_density_product.py
Target: ~90–160 US land cells (not 3221 counties, not 52-only).

Does **not** renumber world_full. Surviving US IDs stay in 800000+ block;
obsolete county IDs are removed and remapped to survivors.

  # Dry-run (plan + counts only)
  python3 tools/map_generation/scripts/merge_us_counties_to_state_provinces.py

  # Write board (backup + remap + adjacency rebuild)
  python3 tools/map_generation/scripts/merge_us_counties_to_state_provinces.py --write

  # Skip slow adjacency (rebuild later via polish_world_accurate_board)
  python3 tools/map_generation/scripts/merge_us_counties_to_state_provinces.py --write --skip-adj
"""
from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from us_state_province_density_product import (  # noqa: E402
    DEFAULT_DIR,
    build_us_state_province_density_product,
    provinces_for_state_size,
    us_county_ids,
)

SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"
WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean"})
MAX_HULL_VERTS = 48


def _is_water(p: dict) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER_T or dom in WATER_D


def _centroid(pts: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not pts:
        return 0.0, 0.0
    ring = list(pts)
    if len(ring) >= 2 and float(ring[0][0]) == float(ring[-1][0]) and float(ring[0][1]) == float(ring[-1][1]):
        ring = ring[:-1]
    if not ring:
        return 0.0, 0.0
    return (
        sum(float(p[0]) for p in ring) / len(ring),
        sum(float(p[1]) for p in ring) / len(ring),
    )


def _cross(o: Sequence[float], a: Sequence[float], b: Sequence[float]) -> float:
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _convex_hull(points: List[List[float]]) -> List[List[float]]:
    uniq: List[List[float]] = []
    seen: Set[Tuple[float, float]] = set()
    for p in points:
        if not isinstance(p, (list, tuple)) or len(p) < 2:
            continue
        key = (round(float(p[0]), 3), round(float(p[1]), 3))
        if key in seen:
            continue
        seen.add(key)
        uniq.append([float(p[0]), float(p[1])])
    if len(uniq) <= 3:
        return list(uniq)
    p0 = min(uniq, key=lambda p: (p[1], p[0]))

    def polar_angle(p: List[float]) -> float:
        return math.atan2(p[1] - p0[1], p[0] - p0[0])

    sorted_pts = sorted(uniq, key=polar_angle)
    hull: List[List[float]] = []
    for p in sorted_pts:
        while len(hull) >= 2 and _cross(hull[-2], hull[-1], p) <= 0:
            hull.pop()
        hull.append(p)
    return hull


def _simplify_ring(ring: List[List[float]], max_verts: int = MAX_HULL_VERTS) -> List[List[float]]:
    if len(ring) <= max_verts:
        return ring
    # Even subsample + close
    step = max(1, len(ring) // max_verts)
    out = [ring[i] for i in range(0, len(ring), step)][:max_verts]
    if len(out) < 3:
        return ring[:max_verts]
    if out[0] != out[-1]:
        # keep open; consumers close as needed
        pass
    return out


def _dist2(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def _kmeans(
    points: List[Tuple[float, float]],
    k: int,
    *,
    iters: int = 40,
    seed: int = 42,
) -> List[int]:
    if not points:
        return []
    k = max(1, min(k, len(points)))
    if k == 1:
        return [0] * len(points)
    rng = random.Random(seed)
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
        for i, p in enumerate(points):
            labels[i] = min(range(k), key=lambda j: _dist2(p, centers[j]))
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
    return labels


def _bbox_area(points: List) -> float:
    xs = []
    ys = []
    for p in points or []:
        if isinstance(p, (list, tuple)) and len(p) >= 2:
            xs.append(float(p[0]))
            ys.append(float(p[1]))
    if len(xs) < 2:
        return 0.0
    return max(0.0, (max(xs) - min(xs)) * (max(ys) - min(ys)))


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, doc: Any) -> None:
    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _protected_us_ids(board_dir: Path) -> Set[int]:
    protected: Set[int] = set()
    if SCENARIO.is_file():
        sc = _load_json(SCENARIO)
        for c in sc.get("countries") or []:
            for key in ("capital_province_id",):
                pid = int(c.get(key) or 0)
                if 800000 <= pid < 900000:
                    protected.add(pid)
            for pid in c.get("key_provinces") or []:
                ip = int(pid)
                if 800000 <= ip < 900000:
                    protected.add(ip)
    # Always protect District of Columbia if present
    base = _load_json(board_dir / "provinces_base.json")
    for p in base.get("provinces") or []:
        if str(p.get("name") or "") == "District of Columbia":
            protected.add(int(p["id"]))
    return protected


def _pick_survivor(cluster_ids: List[int], protected: Set[int]) -> int:
    hits = [pid for pid in cluster_ids if pid in protected]
    if hits:
        return min(hits)
    return min(cluster_ids)


def _cardinal_name(cx: float, cy: float, state_cx: float, state_cy: float, n: int, idx: int) -> str:
    if n <= 1:
        return ""
    dx = cx - state_cx
    dy = cy - state_cy
    # Canvas Y often increases downward; treat higher cy as south-ish
    if abs(dx) >= abs(dy):
        return " West" if dx < 0 else " East"
    return " North" if dy < 0 else " South"


def _aggregate_economy(rows: List[dict]) -> dict:
    out = {
        "population": 0,
        "factories": 0,
        "infrastructure": 0,
        "development_level": 0,
    }
    infra_vals = []
    dev_vals = []
    for r in rows:
        out["population"] += int(r.get("population") or 0)
        out["factories"] += int(r.get("factories") or 0)
        if r.get("infrastructure") is not None:
            infra_vals.append(int(r.get("infrastructure") or 0))
        if r.get("development_level") is not None:
            dev_vals.append(int(r.get("development_level") or 0))
    if infra_vals:
        out["infrastructure"] = max(infra_vals)
    if dev_vals:
        out["development_level"] = max(dev_vals)
    return out


def _aggregate_resources(rows: List[dict]) -> dict:
    totals: Dict[str, float] = defaultdict(float)
    for r in rows:
        for k, v in (r or {}).items():
            if k in ("id", "province_id", "name"):
                continue
            try:
                totals[k] += float(v or 0)
            except (TypeError, ValueError):
                continue
    # Round to ints for board paint
    return {k: int(round(v)) for k, v in totals.items() if v > 0}


def _best_city(rows: List[dict]) -> Optional[dict]:
    best = None
    best_tier = -1
    for r in rows:
        if not r:
            continue
        tier = int(r.get("tier") or 0)
        name = str(r.get("city_name") or r.get("name") or "")
        if tier > best_tier or (tier == best_tier and name and best and name < str(best.get("city_name") or "")):
            best = dict(r)
            best_tier = tier
    return best


def build_merge_plan(board_dir: Path) -> Dict[str, Any]:
    """Return clusters + remap without writing."""
    base_list = _load_json(board_dir / "provinces_base.json")["provinces"]
    base = {int(p["id"]): p for p in base_list}
    geo_list = _load_json(board_dir / "provinces_geometry.json")["provinces"]
    geo = {int(g["id"]): g for g in geo_list}
    mem = _load_json(board_dir / "hierarchy_membership_1936.json")
    p2s = {int(k): int(v) for k, v in (mem.get("province_to_state") or {}).items()}
    state_names = {
        int(s.get("id") or 0): str(s.get("name") or "")
        for s in (_load_json(board_dir / "province_states.json").get("states") or [])
    }
    protected = _protected_us_ids(board_dir)
    counties = us_county_ids(base)

    by_state: Dict[int, List[int]] = defaultdict(list)
    for pid in counties:
        sid = int(p2s.get(pid) or 0)
        if sid > 0:
            by_state[sid].append(pid)

    state_area: Dict[int, float] = {}
    for sid, pids in by_state.items():
        a = 0.0
        for pid in pids:
            a += _bbox_area((geo.get(pid) or {}).get("points") or [])
        state_area[sid] = a
    areas = sorted(state_area.values())
    median_area = areas[len(areas) // 2] if areas else 1.0

    clusters: List[Dict[str, Any]] = []
    remap: Dict[int, int] = {}
    survivors: Set[int] = set()

    for sid in sorted(by_state.keys()):
        pids = sorted(by_state[sid])
        n_play = provinces_for_state_size(len(pids), state_area[sid], median_area)
        n_play = max(1, min(n_play, len(pids)))
        cents = []
        for pid in pids:
            pts = (geo.get(pid) or {}).get("points") or []
            cents.append(_centroid(pts))
        labels = _kmeans(cents, n_play, seed=sid * 17 + 7)
        groups: Dict[int, List[int]] = defaultdict(list)
        for pid, lab in zip(pids, labels):
            groups[int(lab)].append(pid)
        # Ensure protected IDs each land in a cluster (already are) and become survivors
        # If multiple protected in same cluster, only one survives; others remapped
        state_cx = sum(c[0] for c in cents) / len(cents) if cents else 0.0
        state_cy = sum(c[1] for c in cents) / len(cents) if cents else 0.0
        state_name = state_names.get(sid) or ("US State %d" % sid)
        group_items = sorted(groups.items(), key=lambda kv: min(kv[1]))
        for gi, (_lab, members) in enumerate(group_items):
            surv = _pick_survivor(members, protected)
            survivors.add(surv)
            for pid in members:
                remap[pid] = surv
            # centroid of cluster for naming
            mcents = [_centroid((geo.get(pid) or {}).get("points") or []) for pid in members]
            cx = sum(c[0] for c in mcents) / len(mcents)
            cy = sum(c[1] for c in mcents) / len(mcents)
            suffix = _cardinal_name(cx, cy, state_cx, state_cy, len(group_items), gi)
            if surv in protected and str((base.get(surv) or {}).get("name") or "") == "District of Columbia":
                display = "District of Columbia"
            elif len(group_items) == 1:
                display = state_name
            else:
                display = ("%s%s" % (state_name, suffix)).strip()
            clusters.append(
                {
                    "state_id": sid,
                    "state_name": state_name,
                    "survivor_id": surv,
                    "member_ids": members,
                    "name": display,
                    "playable_index": gi,
                    "playable_n": len(group_items),
                }
            )

    dead = sorted(pid for pid in counties if remap.get(pid, pid) != pid)
    # Identity for non-US
    for pid in base:
        if pid not in remap:
            remap[pid] = pid

    return {
        "counties_n": len(counties),
        "states_n": len(by_state),
        "clusters": clusters,
        "survivors_n": len(survivors),
        "dead_n": len(dead),
        "dead_ids": dead,
        "remap": {str(k): v for k, v in remap.items()},
        "protected": sorted(protected),
        "planned_playable_us_n": len(survivors),
    }


def apply_merge(
    board_dir: Path,
    plan: Dict[str, Any],
    *,
    skip_adj: bool = False,
    quant: float = 5.0,
) -> Dict[str, Any]:
    remap_int = {int(k): int(v) for k, v in (plan.get("remap") or {}).items()}
    clusters = plan["clusters"]
    dead_set = set(int(x) for x in plan.get("dead_ids") or [])
    survivor_meta = {int(c["survivor_id"]): c for c in clusters}

    base_doc = _load_json(board_dir / "provinces_base.json")
    geo_doc = _load_json(board_dir / "provinces_geometry.json")
    base_by = {int(p["id"]): p for p in base_doc["provinces"]}
    geo_by = {int(g["id"]): g for g in geo_doc["provinces"]}

    econ_doc = _load_json(board_dir / "province_economy_layer.json")
    city_doc = _load_json(board_dir / "province_city_layer.json")
    res_doc = _load_json(board_dir / "province_resources_layer.json")
    terr_doc = _load_json(board_dir / "province_terrain_layer.json")
    econ = econ_doc.get("provinces") or {}
    city = city_doc.get("provinces") or {}
    res = res_doc.get("provinces") or {}
    terr = terr_doc.get("provinces") or {}

    # Build new base/geo for survivors
    new_base_rows: List[dict] = []
    new_geo_rows: List[dict] = []
    kept_ids: Set[int] = set()

    for pid, prow in base_by.items():
        if pid in dead_set:
            continue
        if pid in survivor_meta:
            cl = survivor_meta[pid]
            members = [int(x) for x in cl["member_ids"]]
            # Geometry: convex hull of all member rings
            all_pts: List[List[float]] = []
            for mid in members:
                pts = (geo_by.get(mid) or {}).get("points") or []
                for pt in pts:
                    if isinstance(pt, (list, tuple)) and len(pt) >= 2:
                        all_pts.append([float(pt[0]), float(pt[1])])
            hull = _convex_hull(all_pts)
            if len(hull) < 3:
                # fallback to survivor original ring
                hull = [
                    [float(pt[0]), float(pt[1])]
                    for pt in ((geo_by.get(pid) or {}).get("points") or [])
                    if isinstance(pt, (list, tuple)) and len(pt) >= 2
                ]
            hull = _simplify_ring(hull)
            cx, cy = _centroid(hull)
            bp = dict(prow)
            bp["id"] = pid
            bp["name"] = cl["name"]
            bp["domain"] = "land"
            if not bp.get("terrain"):
                bp["terrain"] = "plains"
            meta = dict(bp.get("meta") or {}) if isinstance(bp.get("meta"), dict) else {}
            meta["us_merge"] = {
                "state_id": cl["state_id"],
                "state_name": cl["state_name"],
                "merged_county_n": len(members),
                "merged_from": members[:12],
                "source": "merge_us_counties_to_state_provinces",
            }
            # Preserve tiger geoid of survivor when single county remains
            if len(members) == 1:
                pass
            else:
                meta["merged_playable"] = True
            bp["meta"] = meta
            # Aggregate population_base
            pop = 0
            for mid in members:
                pop += int((base_by.get(mid) or {}).get("population_base") or 0)
            if pop:
                bp["population_base"] = pop
            # natural resources sum
            nr: Dict[str, float] = defaultdict(float)
            for mid in members:
                for k, v in ((base_by.get(mid) or {}).get("natural_resources") or {}).items():
                    try:
                        nr[k] += float(v or 0)
                    except (TypeError, ValueError):
                        pass
            if nr:
                bp["natural_resources"] = {k: int(round(v)) for k, v in nr.items() if v > 0}

            gp = dict(geo_by.get(pid) or {"id": pid})
            gp["id"] = pid
            gp["points"] = hull
            gp["name"] = cl["name"]
            gp["label_anchor"] = [cx, cy]
            gmeta = dict(gp.get("meta") or {}) if isinstance(gp.get("meta"), dict) else {}
            gmeta["us_merge"] = meta["us_merge"]
            gp["meta"] = gmeta

            new_base_rows.append(bp)
            new_geo_rows.append(gp)
            kept_ids.add(pid)

            # Layer aggregates
            econ_rows = [econ.get(str(m)) or {} for m in members if isinstance(econ.get(str(m)), dict)]
            econ[str(pid)] = _aggregate_economy(econ_rows)
            res_rows = [res.get(str(m)) or {} for m in members if isinstance(res.get(str(m)), dict)]
            res[str(pid)] = _aggregate_resources(res_rows)
            city_rows = [city.get(str(m)) or {} for m in members if isinstance(city.get(str(m)), dict)]
            best = _best_city(city_rows)
            if best:
                # Keep Washington label on DC
                if cl["name"] == "District of Columbia":
                    best["city_name"] = "Washington"
                    best["tier"] = max(int(best.get("tier") or 0), 4)
                elif not best.get("city_name"):
                    best["city_name"] = cl["name"]
                city[str(pid)] = best
            else:
                city[str(pid)] = {"city_name": cl["name"], "tier": 2}
            # terrain majority
            terr_counts = Counter()
            for m in members:
                trow = terr.get(str(m)) or {}
                t = str(trow.get("terrain") or (base_by.get(m) or {}).get("terrain") or "plains")
                terr_counts[t] += 1
            top_t = terr_counts.most_common(1)[0][0] if terr_counts else "plains"
            terr[str(pid)] = {"terrain": top_t, "domain": "land"}
            bp["terrain"] = top_t
        else:
            # Non-US or non-merged keep as-is
            new_base_rows.append(prow)
            if pid in geo_by:
                new_geo_rows.append(geo_by[pid])
            kept_ids.add(pid)

    # Drop dead from layers
    for ds in (econ, city, res, terr):
        for did in dead_set:
            ds.pop(str(did), None)

    new_base_rows.sort(key=lambda p: int(p["id"]))
    new_geo_rows.sort(key=lambda p: int(p["id"]))
    base_doc["provinces"] = new_base_rows
    geo_doc["provinces"] = new_geo_rows
    econ_doc["provinces"] = econ
    city_doc["provinces"] = city
    res_doc["provinces"] = res
    terr_doc["provinces"] = terr

    # Ownership eras
    own_files = sorted(board_dir.glob("province_ownership_*.json"))
    for opath in own_files:
        if "era_index" in opath.name:
            continue
        odoc = _load_json(opath)
        owners = odoc.get("owners") or {}
        new_owners: Dict[str, str] = {}
        for pid_s, tag in owners.items():
            pid = int(pid_s)
            if pid in dead_set:
                continue
            new_owners[str(pid)] = tag
        # Ensure survivors keep USA (or prior owner of survivor)
        for cl in clusters:
            sid = str(int(cl["survivor_id"]))
            if sid not in new_owners:
                # take first member owner
                for m in cl["member_ids"]:
                    if str(m) in owners:
                        new_owners[sid] = owners[str(m)]
                        break
                else:
                    new_owners[sid] = "USA"
        odoc["owners"] = new_owners
        meta = dict(odoc.get("meta") or {})
        meta["us_merge"] = {"dead_n": len(dead_set), "survivors_n": plan["survivors_n"]}
        odoc["meta"] = meta
        _write_json(opath, odoc)

    # Hierarchy membership eras
    for mpath in sorted(board_dir.glob("hierarchy_membership_*.json")):
        mdoc = _load_json(mpath)
        for key in ("province_to_state", "province_to_region", "province_to_super_region"):
            mapping = mdoc.get(key) or {}
            new_map: Dict[str, int] = {}
            for pid_s, val in mapping.items():
                pid = int(pid_s)
                if pid in dead_set:
                    continue
                new_map[str(pid)] = int(val)
            # survivors already present
            mdoc[key] = new_map
        _write_json(mpath, mdoc)

    # Adjacency: rewrite via remap then optional full rebuild
    adj_path = board_dir / "province_adjacency.json"
    adj_doc = _load_json(adj_path)
    old_adj = adj_doc.get("adjacency") or {}
    # Remap-time adjacency (sets) — full shared-edge rebuild may replace below
    tmp: Dict[int, Set[int]] = defaultdict(set)
    for pid_s, nbrs in old_adj.items():
        pid = int(pid_s)
        p2 = remap_int.get(pid, pid)
        if p2 in dead_set:
            continue
        for n in nbrs or []:
            n2 = remap_int.get(int(n), int(n))
            if n2 == p2 or n2 in dead_set:
                continue
            tmp[p2].add(n2)
            tmp[n2].add(p2)
    adj_doc["adjacency"] = {str(k): sorted(v) for k, v in sorted(tmp.items())}
    adj_doc["method"] = str(adj_doc.get("method") or "shared_edge") + "+us_merge_remap"
    stats = dict(adj_doc.get("stats") or {})
    stats["us_merge_dead"] = len(dead_set)
    stats["us_merge_survivors"] = plan["survivors_n"]
    adj_doc["stats"] = stats

    # project_sites if any province ids
    ps_path = board_dir / "project_sites.json"
    if ps_path.is_file():
        ps = _load_json(ps_path)
        # best-effort: drop dead keys if dict
        if isinstance(ps, dict):
            for k in list(ps.keys()):
                if k.isdigit() and int(k) in dead_set:
                    ps.pop(k, None)
            _write_json(ps_path, ps)

    # Write core files
    _write_json(board_dir / "provinces_base.json", base_doc)
    _write_json(board_dir / "provinces_geometry.json", geo_doc)
    _write_json(board_dir / "province_economy_layer.json", econ_doc)
    _write_json(board_dir / "province_city_layer.json", city_doc)
    _write_json(board_dir / "province_resources_layer.json", res_doc)
    _write_json(board_dir / "province_terrain_layer.json", terr_doc)

    land_n = sum(1 for p in new_base_rows if not _is_water(p))
    sea_n = len(new_base_rows) - land_n

    if not skip_adj:
        from shared_edge_adjacency_product import build_shared_edge_adjacency, load_board_geometry

        rings, water = load_board_geometry(board_dir)
        # Hull merges need generous near_vertex so land_shared_coverage ≥ 0.95
        nvt = max(20.0, quant * 4.0)
        res_adj = build_shared_edge_adjacency(
            rings=rings,
            water=water,
            quant=quant,
            knn_k=6,
            multi_quant=True,
            near_vertex_touch=nvt,
            near_vertex_max_nbrs=8,
        )
        adj_doc = {
            "version": 2,
            "method": res_adj.get("method") or "shared_edge_near_vertex_plus_knn",
            "source": "merge_us_counties_to_state_provinces",
            "quant": quant,
            "knn_k": 6,
            "near_vertex_touch": nvt,
            "stats": res_adj.get("stats") or {},
            "adjacency": res_adj.get("adjacency") or {},
        }
        # ensure GER-FRA edge if present
        a = adj_doc["adjacency"]
        if "710173" in a and 710739 not in [int(x) for x in a.get("710173") or []]:
            # soft warn only
            stats = dict(adj_doc.get("stats") or {})
            stats["warn_missing_ger_fra"] = True
            adj_doc["stats"] = stats

    _write_json(adj_path, adj_doc)

    # Remap table
    remap_path = board_dir / "us_county_to_playable_remap.json"
    remap_doc = {
        "version": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "board": str(board_dir.name),
        "counties_n": plan["counties_n"],
        "survivors_n": plan["survivors_n"],
        "dead_n": plan["dead_n"],
        "protected": plan["protected"],
        "remap": plan["remap"],
        "clusters": [
            {
                "survivor_id": c["survivor_id"],
                "state_id": c["state_id"],
                "state_name": c["state_name"],
                "name": c["name"],
                "member_ids": c["member_ids"],
            }
            for c in clusters
        ],
        "notes": "Obsolete US county IDs map to playable survivor; non-US identity remaps omitted from dead list.",
    }
    _write_json(remap_path, remap_doc)

    # Manifest
    man_path = board_dir / "manifest_world_accurate.json"
    if man_path.is_file():
        man = _load_json(man_path)
        man["stats"] = {
            "provinces": len(new_base_rows),
            "land": land_n,
            "sea": sea_n,
        }
        blocks = dict(man.get("blocks") or {})
        blocks["us_tiger"] = plan["survivors_n"]
        blocks["us_tiger_pre_merge"] = plan["counties_n"]
        man["blocks"] = blocks
        man["us_merge"] = {
            "method": "1_to_4_per_state_kmeans_hull",
            "survivors_n": plan["survivors_n"],
            "dead_n": plan["dead_n"],
            "remap_file": "us_county_to_playable_remap.json",
        }
        man["geometry_quality"] = str(man.get("geometry_quality") or "") + "+us_merge_v1"
        notes = man.get("notes")
        if isinstance(notes, list):
            notes.append("US TIGER counties merged to 1–4 playable provinces per state (2026-07-25).")
        elif isinstance(notes, str):
            man["notes"] = notes + " | US merge 1–4/state"
        else:
            man["notes"] = ["US TIGER counties merged to 1–4 playable provinces per state."]
        _write_json(man_path, man)

    # hierarchy scaffold: rebuild maps from membership + sea state 0
    hs_path = board_dir / "hierarchy_scaffold.json"
    if hs_path.is_file():
        hs = _load_json(hs_path)
        mem1936 = _load_json(board_dir / "hierarchy_membership_1936.json")
        kept_str = {str(pid) for pid in kept_ids}
        p2s = {
            k: int(v)
            for k, v in (mem1936.get("province_to_state") or {}).items()
            if k in kept_str
        }
        for pid in kept_str:
            if int(pid) >= 950000 and pid not in p2s:
                p2s[pid] = 0
        hs["province_to_state"] = p2s
        for key in ("province_to_region", "province_to_super_region"):
            hs[key] = {
                k: int(v)
                for k, v in (mem1936.get(key) or {}).items()
                if k in kept_str
            }
        hs["province_n"] = len(new_base_rows)
        hs["land_n"] = land_n
        hs["us_playable_n"] = plan["survivors_n"]
        hs["four_tier"] = True
        _write_json(hs_path, hs)

    # Rebuild strategic_regions province_ids from membership (drop dead counties)
    mem1936 = _load_json(board_dir / "hierarchy_membership_1936.json")
    p2r_live = {
        int(k): int(v) for k, v in (mem1936.get("province_to_region") or {}).items()
    }
    by_region: Dict[int, List[int]] = defaultdict(list)
    for pid, rid in sorted(p2r_live.items()):
        by_region[rid].append(pid)
    sr_path = board_dir / "strategic_regions.json"
    if sr_path.is_file():
        sr = _load_json(sr_path)
        for r in sr.get("regions") or []:
            rid = int(r.get("id") or 0)
            r["province_ids"] = by_region.get(rid, [])
        _write_json(sr_path, sr)

    return {
        "provinces": len(new_base_rows),
        "land": land_n,
        "sea": sea_n,
        "us_survivors": plan["survivors_n"],
        "dead": plan["dead_n"],
        "remap_path": str(remap_path),
        "skip_adj": skip_adj,
        "adj_method": adj_doc.get("method"),
        "adj_stats": adj_doc.get("stats"),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", type=Path, default=DEFAULT_DIR, help="Board directory")
    ap.add_argument("--write", action="store_true", help="Apply merge (default dry-run)")
    ap.add_argument("--skip-adj", action="store_true", help="Skip full shared-edge rebuild")
    ap.add_argument("--quant", type=float, default=4.0, help="Adjacency quant (4.0 + nvt 20 works post-hull)")
    ap.add_argument("--backup", action="store_true", default=True, help="Backup before write (default on)")
    ap.add_argument("--no-backup", action="store_true", help="Skip backup")
    args = ap.parse_args()
    board_dir: Path = args.dir
    if not board_dir.is_dir():
        print("FAIL: board dir missing", board_dir)
        return 2

    # Gate: plan product should be ok before merge
    prod = build_us_state_province_density_product(board_dir=str(board_dir))
    print("[plan product]", prod.get("summary"))
    if not prod.get("ok"):
        # Allow re-run if already merged? Check survivors
        us_n = int(prod.get("us_county_n") or 0)
        if us_n < 500:
            print("Board already looks merged (us cells < 500). Abort.")
            return 1
        print("WARN: density product not ok:", prod.get("fail"))

    plan = build_merge_plan(board_dir)
    print(
        "Merge plan: counties=%d → playable=%d (states=%d) dead=%d protected=%s"
        % (
            plan["counties_n"],
            plan["survivors_n"],
            plan["states_n"],
            plan["dead_n"],
            plan["protected"],
        )
    )
    # Validate capital protection
    for pid in plan["protected"]:
        if plan["remap"].get(str(pid), pid) != pid:
            print("FAIL: protected id remapped away", pid)
            return 1
        # survivor must equal itself
        if int(plan["remap"].get(str(pid), pid)) != int(pid):
            print("FAIL: protected not survivor", pid)
            return 1

    if not args.write:
        print("Dry-run only. Pass --write to apply.")
        # sample clusters
        for c in plan["clusters"][:5]:
            print("  sample", c["name"], "surv", c["survivor_id"], "n", len(c["member_ids"]))
        return 0

    if not args.no_backup:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        bak = board_dir.parent / ("provinces_world_accurate.bak_pre_us_merge_%s" % stamp)
        if bak.exists():
            shutil.rmtree(bak)
        print("Backup →", bak)
        shutil.copytree(
            board_dir,
            bak,
            ignore=shutil.ignore_patterns("*.bak*", "*.bak"),
        )

    result = apply_merge(board_dir, plan, skip_adj=args.skip_adj, quant=args.quant)
    print("WRITE OK", json.dumps(result, indent=2))
    # Post check capital
    base = {int(p["id"]): p for p in _load_json(board_dir / "provinces_base.json")["provinces"]}
    if 800792 not in base:
        print("FAIL: USA capital 800792 missing after merge")
        return 1
    if base[800792].get("name") != "District of Columbia":
        print("WARN: DC name now", base[800792].get("name"))
    us_left = sum(1 for pid in base if 800000 <= pid < 900000)
    print("US block remaining:", us_left)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
