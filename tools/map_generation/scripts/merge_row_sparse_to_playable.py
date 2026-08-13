#!/usr/bin/env python3
"""Merge sparse RoW geoBoundaries cells on world_accurate into playable provinces.

Plan product: tools/map_generation/lib/row_sparse_density_product.py
Default tranche 1: australia + oceania_islands + africa (prep priority).

Does **not** renumber world_full. Surviving RoW IDs stay in 900000–949999;
obsolete ADM2 IDs are removed and remapped to survivors.

  # Dry-run (plan + counts only)
  python3 tools/map_generation/scripts/merge_row_sparse_to_playable.py

  # Write board (backup + remap + adjacency rebuild)
  python3 tools/map_generation/scripts/merge_row_sparse_to_playable.py --write

  # Specific scopes
  python3 tools/map_generation/scripts/merge_row_sparse_to_playable.py --write \\
      --scopes australia,oceania_islands,africa

  # Skip slow adjacency (rebuild later)
  python3 tools/map_generation/scripts/merge_row_sparse_to_playable.py --write --skip-adj
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

from row_sparse_density_product import (  # noqa: E402
    ADM0_TO_REGION,
    DEFAULT_DIR,
    REGION_TARGETS,
    ROW_HI,
    ROW_LO,
    TRANCHE1_REGIONS,
    adm0_of,
    build_row_sparse_density_product,
    provinces_for_group_size,
    row_ids,
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
    if (
        len(ring) >= 2
        and float(ring[0][0]) == float(ring[-1][0])
        and float(ring[0][1]) == float(ring[-1][1])
    ):
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
    step = max(1, len(ring) // max_verts)
    out = [ring[i] for i in range(0, len(ring), step)][:max_verts]
    if len(out) < 3:
        return ring[:max_verts]
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


def _protected_row_ids(board_dir: Path) -> Set[int]:
    protected: Set[int] = set()
    if SCENARIO.is_file():
        sc = _load_json(SCENARIO)
        for c in sc.get("countries") or []:
            for key in ("capital_province_id",):
                pid = int(c.get(key) or 0)
                if ROW_LO <= pid < ROW_HI:
                    protected.add(pid)
            for pid in c.get("key_provinces") or []:
                ip = int(pid)
                if ROW_LO <= ip < ROW_HI:
                    protected.add(ip)
    # High-tier cities (Tokyo/Moscow etc.)
    city_path = board_dir / "province_city_layer.json"
    if city_path.is_file():
        city = _load_json(city_path).get("provinces") or {}
        for pid_s, row in city.items():
            try:
                pid = int(pid_s)
            except (TypeError, ValueError):
                continue
            if not (ROW_LO <= pid < ROW_HI):
                continue
            if int((row or {}).get("tier") or 0) >= 4:
                protected.add(pid)
    return protected


def _pick_survivor(cluster_ids: List[int], protected: Set[int], base: Dict[int, dict]) -> int:
    hits = [pid for pid in cluster_ids if pid in protected]
    if hits:
        return min(hits)
    # Prefer highest population_base, then min id
    def score(pid: int) -> Tuple[int, int]:
        pop = int((base.get(pid) or {}).get("population_base") or 0)
        return (-pop, pid)

    return min(cluster_ids, key=score)


def _cardinal_name(cx: float, cy: float, g_cx: float, g_cy: float, n: int) -> str:
    if n <= 1:
        return ""
    dx = cx - g_cx
    dy = cy - g_cy
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
    return {k: int(round(v)) for k, v in totals.items() if v > 0}


def _best_city(rows: List[dict]) -> Optional[dict]:
    best = None
    best_tier = -1
    for r in rows:
        if not r:
            continue
        tier = int(r.get("tier") or 0)
        name = str(r.get("city_name") or r.get("name") or "")
        if tier > best_tier or (
            tier == best_tier and name and best and name < str(best.get("city_name") or "")
        ):
            best = dict(r)
            best_tier = tier
    return best


def build_merge_plan(
    board_dir: Path,
    *,
    scopes: Sequence[str],
) -> Dict[str, Any]:
    """Return clusters + remap without writing."""
    scope_set = set(scopes)
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
    protected = _protected_row_ids(board_dir)
    all_row = set(row_ids(base))

    # Groups in scope
    by_group: Dict[Tuple[str, int, str], List[int]] = defaultdict(list)
    for pid in sorted(all_row):
        prow = base[pid]
        adm0 = adm0_of(prow) or "UNK"
        region = ADM0_TO_REGION.get(adm0, "")
        if region not in scope_set:
            continue
        sid = int(p2s.get(pid) or 0)
        by_group[(region, sid, adm0)].append(pid)

    group_area: Dict[Tuple[str, int, str], float] = {}
    for key, pids in by_group.items():
        a = 0.0
        for pid in pids:
            a += _bbox_area((geo.get(pid) or {}).get("points") or [])
        group_area[key] = a
    areas = sorted(group_area.values())
    median_area = areas[len(areas) // 2] if areas else 1.0

    # Regions already in band → identity keep
    current_by_region: Dict[str, int] = Counter()
    for (region, _sid, _adm0), pids in by_group.items():
        current_by_region[region] += len(pids)
    keep_regions: Set[str] = set()
    for region, cur in current_by_region.items():
        band = REGION_TARGETS.get(region) or {}
        if band and int(band["min_playable"]) <= cur <= int(band["max_playable"]):
            keep_regions.add(region)

    clusters: List[Dict[str, Any]] = []
    remap: Dict[int, int] = {}
    survivors: Set[int] = set()
    merge_cell_ids: Set[int] = set()

    for key in sorted(by_group.keys(), key=lambda k: (k[0], k[2], k[1])):
        region, sid, adm0 = key
        pids = sorted(by_group[key])
        merge_cell_ids.update(pids)
        group_name = state_names.get(sid) or adm0 or ("state_%d" % sid)

        if region in keep_regions:
            # Identity: each cell is its own survivor
            for pid in pids:
                survivors.add(pid)
                remap[pid] = pid
                clusters.append(
                    {
                        "region": region,
                        "state_id": sid,
                        "state_name": group_name,
                        "adm0": adm0,
                        "survivor_id": pid,
                        "member_ids": [pid],
                        "name": str((base.get(pid) or {}).get("name") or group_name),
                        "playable_index": 0,
                        "playable_n": 1,
                        "strategy": "already_in_band_keep",
                    }
                )
            continue

        n_play = provinces_for_group_size(
            len(pids), group_area[key], median_area, region=region
        )
        n_play = max(1, min(n_play, len(pids)))
        # Forced singleton clusters for protected capitals/key hubs
        prot_here = sorted(pid for pid in pids if pid in protected)
        free = sorted(pid for pid in pids if pid not in protected)
        n_forced = len(prot_here)
        n_k = max(0, n_play - n_forced)
        if n_k == 0 and free:
            # Still need at least one free cluster if free members remain
            n_k = 1 if free else 0
        # Cap total clusters to available cells
        while n_forced + n_k > len(pids) and n_k > 0:
            n_k -= 1

        groups: Dict[int, List[int]] = {}
        next_lab = 0
        for pp in prot_here:
            groups[next_lab] = [pp]
            next_lab += 1
        if free and n_k > 0:
            free_cents = [
                _centroid((geo.get(pid) or {}).get("points") or []) for pid in free
            ]
            labels = _kmeans(
                free_cents, min(n_k, len(free)), seed=sid * 31 + hash(adm0) % 997 + 11
            )
            free_groups: Dict[int, List[int]] = defaultdict(list)
            for pid, lab in zip(free, labels):
                free_groups[int(lab)].append(pid)
            for members in free_groups.values():
                groups[next_lab] = members
                next_lab += 1
        elif free:
            # No free budget: attach free members to nearest protected centroid
            if prot_here:
                prot_cents = {
                    pp: _centroid((geo.get(pp) or {}).get("points") or [])
                    for pp in prot_here
                }
                for pid in free:
                    c = _centroid((geo.get(pid) or {}).get("points") or [])
                    nearest = min(
                        prot_here, key=lambda pp: _dist2(c, prot_cents[pp])
                    )
                    # find lab for that protected
                    for lab, mems in groups.items():
                        if nearest in mems:
                            mems.append(pid)
                            break
            else:
                groups[next_lab] = free

        all_cents = [
            _centroid((geo.get(pid) or {}).get("points") or []) for pid in pids
        ]
        g_cx = sum(c[0] for c in all_cents) / len(all_cents) if all_cents else 0.0
        g_cy = sum(c[1] for c in all_cents) / len(all_cents) if all_cents else 0.0
        group_items = sorted(groups.items(), key=lambda kv: min(kv[1]))
        for gi, (_lab, members) in enumerate(group_items):
            surv = _pick_survivor(members, protected, base)
            survivors.add(surv)
            for pid in members:
                remap[pid] = surv
            mcents = [
                _centroid((geo.get(pid) or {}).get("points") or []) for pid in members
            ]
            cx = sum(c[0] for c in mcents) / len(mcents)
            cy = sum(c[1] for c in mcents) / len(mcents)
            suffix = _cardinal_name(cx, cy, g_cx, g_cy, len(group_items))
            if len(group_items) == 1:
                display = group_name
            else:
                display = ("%s%s" % (group_name, suffix)).strip()
            if len(members) == 1:
                display = str((base.get(surv) or {}).get("name") or display)
            clusters.append(
                {
                    "region": region,
                    "state_id": sid,
                    "state_name": group_name,
                    "adm0": adm0,
                    "survivor_id": surv,
                    "member_ids": members,
                    "name": display,
                    "playable_index": gi,
                    "playable_n": len(group_items),
                    "strategy": "merge_kmeans_hull",
                }
            )

    dead = sorted(pid for pid in merge_cell_ids if remap.get(pid, pid) != pid)
    # Identity for everything not in merge set
    for pid in base:
        if pid not in remap:
            remap[pid] = pid

    # Protected must survive
    for pid in protected:
        if pid in merge_cell_ids and remap.get(pid, pid) != pid:
            # Force protect: re-home cluster to protected id if same group members
            # Handled by _pick_survivor; if still remapped, fail later in main
            pass

    by_region_play: Dict[str, int] = Counter()
    for c in clusters:
        by_region_play[str(c["region"])] += 1

    return {
        "scopes": sorted(scope_set),
        "cells_n": len(merge_cell_ids),
        "groups_n": len(by_group),
        "clusters": clusters,
        "survivors_n": len(survivors),
        "dead_n": len(dead),
        "dead_ids": dead,
        "remap": {str(k): v for k, v in remap.items()},
        "protected": sorted(protected),
        "planned_playable_n": len(survivors),
        "planned_by_region": dict(by_region_play),
        "current_by_region": dict(current_by_region),
        "keep_regions": sorted(keep_regions),
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
    # Only clusters that actually merge (member_n > 1) need hull rewrite
    survivor_meta = {
        int(c["survivor_id"]): c
        for c in clusters
        if len(c.get("member_ids") or []) > 1 or str(c.get("strategy") or "") == "merge_kmeans_hull"
    }
    # Also include multi-member only for geometry rebuild; single identity keep unchanged
    merge_survivors = {
        int(c["survivor_id"]): c
        for c in clusters
        if len(c.get("member_ids") or []) > 1
    }

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

    new_base_rows: List[dict] = []
    new_geo_rows: List[dict] = []
    kept_ids: Set[int] = set()

    for pid, prow in base_by.items():
        if pid in dead_set:
            continue
        if pid in merge_survivors:
            cl = merge_survivors[pid]
            members = [int(x) for x in cl["member_ids"]]
            all_pts: List[List[float]] = []
            for mid in members:
                pts = (geo_by.get(mid) or {}).get("points") or []
                for pt in pts:
                    if isinstance(pt, (list, tuple)) and len(pt) >= 2:
                        all_pts.append([float(pt[0]), float(pt[1])])
            hull = _convex_hull(all_pts)
            if len(hull) < 3:
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
            meta["row_merge"] = {
                "region": cl["region"],
                "state_id": cl["state_id"],
                "state_name": cl["state_name"],
                "adm0": cl["adm0"],
                "merged_cell_n": len(members),
                "merged_from": members[:12],
                "source": "merge_row_sparse_to_playable",
            }
            meta["merged_playable"] = True
            # Preserve adm0 for future scopes
            if cl.get("adm0"):
                meta["adm0_a3"] = cl["adm0"]
                meta["admin"] = cl["adm0"]
            bp["meta"] = meta
            pop = 0
            for mid in members:
                pop += int((base_by.get(mid) or {}).get("population_base") or 0)
            if pop:
                bp["population_base"] = pop
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
            gmeta["row_merge"] = meta["row_merge"]
            if cl.get("adm0"):
                gmeta["adm0_a3"] = cl["adm0"]
            gp["meta"] = gmeta

            new_base_rows.append(bp)
            new_geo_rows.append(gp)
            kept_ids.add(pid)

            econ_rows = [econ.get(str(m)) or {} for m in members if isinstance(econ.get(str(m)), dict)]
            econ[str(pid)] = _aggregate_economy(econ_rows)
            res_rows = [res.get(str(m)) or {} for m in members if isinstance(res.get(str(m)), dict)]
            res[str(pid)] = _aggregate_resources(res_rows)
            city_rows = [city.get(str(m)) or {} for m in members if isinstance(city.get(str(m)), dict)]
            best = _best_city(city_rows)
            if best:
                if not best.get("city_name"):
                    best["city_name"] = cl["name"]
                city[str(pid)] = best
            else:
                city[str(pid)] = {"city_name": cl["name"], "tier": 2}
            terr_counts = Counter()
            for m in members:
                trow = terr.get(str(m)) or {}
                t = str(trow.get("terrain") or (base_by.get(m) or {}).get("terrain") or "plains")
                terr_counts[t] += 1
            top_t = terr_counts.most_common(1)[0][0] if terr_counts else "plains"
            terr[str(pid)] = {"terrain": top_t, "domain": "land"}
            bp["terrain"] = top_t
        else:
            new_base_rows.append(prow)
            if pid in geo_by:
                new_geo_rows.append(geo_by[pid])
            kept_ids.add(pid)

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
        for cl in clusters:
            if len(cl.get("member_ids") or []) <= 1:
                continue
            sid = str(int(cl["survivor_id"]))
            if sid not in new_owners:
                for m in cl["member_ids"]:
                    if str(m) in owners:
                        new_owners[sid] = owners[str(m)]
                        break
        odoc["owners"] = new_owners
        meta = dict(odoc.get("meta") or {})
        meta["row_merge"] = {
            "dead_n": len(dead_set),
            "survivors_n": plan["survivors_n"],
            "scopes": plan.get("scopes"),
        }
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
            mdoc[key] = new_map
        _write_json(mpath, mdoc)

    # Adjacency remap then optional rebuild
    adj_path = board_dir / "province_adjacency.json"
    adj_doc = _load_json(adj_path)
    old_adj = adj_doc.get("adjacency") or {}
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
    adj_doc["method"] = str(adj_doc.get("method") or "shared_edge") + "+row_merge_remap"
    stats = dict(adj_doc.get("stats") or {})
    stats["row_merge_dead"] = len(dead_set)
    stats["row_merge_survivors"] = plan["survivors_n"]
    adj_doc["stats"] = stats

    ps_path = board_dir / "project_sites.json"
    if ps_path.is_file():
        ps = _load_json(ps_path)
        if isinstance(ps, dict):
            for k in list(ps.keys()):
                if k.isdigit() and int(k) in dead_set:
                    ps.pop(k, None)
            _write_json(ps_path, ps)

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
            "source": "merge_row_sparse_to_playable",
            "quant": quant,
            "knn_k": 6,
            "near_vertex_touch": nvt,
            "stats": res_adj.get("stats") or {},
            "adjacency": res_adj.get("adjacency") or {},
        }

    _write_json(adj_path, adj_doc)

    # Remap table
    remap_path = board_dir / "row_sparse_to_playable_remap.json"
    remap_doc = {
        "version": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "board": str(board_dir.name),
        "scopes": plan.get("scopes"),
        "cells_n": plan["cells_n"],
        "survivors_n": plan["survivors_n"],
        "dead_n": plan["dead_n"],
        "protected": plan["protected"],
        "planned_by_region": plan.get("planned_by_region"),
        "remap": {str(k): v for k, v in remap_int.items() if int(k) != int(v)},
        "clusters": [
            {
                "survivor_id": c["survivor_id"],
                "region": c["region"],
                "state_id": c["state_id"],
                "state_name": c["state_name"],
                "adm0": c["adm0"],
                "name": c["name"],
                "member_ids": c["member_ids"],
            }
            for c in clusters
            if len(c.get("member_ids") or []) > 1
        ],
        "notes": "Obsolete RoW ADM2 IDs map to playable survivors; Europe/US/seas untouched.",
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
        blocks["row_geoboundaries"] = sum(
            1 for p in new_base_rows if ROW_LO <= int(p["id"]) < ROW_HI
        )
        blocks["row_geoboundaries_pre_sparse_merge"] = plan["cells_n"] + (
            sum(1 for p in new_base_rows if ROW_LO <= int(p["id"]) < ROW_HI)
            - plan["survivors_n"]
        )
        man["blocks"] = blocks
        man["row_sparse_merge"] = {
            "method": "kmeans_hull_by_adm0_state",
            "scopes": plan.get("scopes"),
            "survivors_n": plan["survivors_n"],
            "dead_n": plan["dead_n"],
            "remap_file": "row_sparse_to_playable_remap.json",
            "planned_by_region": plan.get("planned_by_region"),
        }
        man["geometry_quality"] = str(man.get("geometry_quality") or "") + "+row_sparse_merge_v1"
        notes = man.get("notes")
        note_line = (
            "RoW sparse merge tranche scopes=%s survivors=%d dead=%d (2026-07-29)."
            % (",".join(plan.get("scopes") or []), plan["survivors_n"], plan["dead_n"])
        )
        if isinstance(notes, list):
            notes.append(note_line)
        elif isinstance(notes, str):
            man["notes"] = notes + " | " + note_line
        else:
            man["notes"] = [note_line]
        _write_json(man_path, man)

    # hierarchy scaffold
    hs_path = board_dir / "hierarchy_scaffold.json"
    if hs_path.is_file():
        hs = _load_json(hs_path)
        mem1936 = _load_json(board_dir / "hierarchy_membership_1936.json")
        kept_str = {str(pid) for pid in kept_ids}
        p2s_map = {
            k: int(v)
            for k, v in (mem1936.get("province_to_state") or {}).items()
            if k in kept_str
        }
        for pid in kept_str:
            if int(pid) >= 950000 and pid not in p2s_map:
                p2s_map[pid] = 0
        hs["province_to_state"] = p2s_map
        for key in ("province_to_region", "province_to_super_region"):
            hs[key] = {
                k: int(v)
                for k, v in (mem1936.get(key) or {}).items()
                if k in kept_str
            }
        hs["province_n"] = len(new_base_rows)
        hs["land_n"] = land_n
        hs["row_playable_n"] = plan["survivors_n"]
        hs["four_tier"] = True
        _write_json(hs_path, hs)

    # Rebuild strategic_regions province_ids
    mem1936 = _load_json(board_dir / "hierarchy_membership_1936.json")
    p2r_live = {int(k): int(v) for k, v in (mem1936.get("province_to_region") or {}).items()}
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
        "row_survivors": plan["survivors_n"],
        "dead": plan["dead_n"],
        "remap_path": str(remap_path),
        "skip_adj": skip_adj,
        "adj_method": adj_doc.get("method"),
        "adj_stats": adj_doc.get("stats"),
        "scopes": plan.get("scopes"),
        "planned_by_region": plan.get("planned_by_region"),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", type=Path, default=DEFAULT_DIR, help="Board directory")
    ap.add_argument("--write", action="store_true", help="Apply merge (default dry-run)")
    ap.add_argument("--skip-adj", action="store_true", help="Skip full shared-edge rebuild")
    ap.add_argument("--quant", type=float, default=4.0, help="Adjacency quant")
    ap.add_argument(
        "--scopes",
        type=str,
        default=",".join(TRANCHE1_REGIONS),
        help="Comma regions: africa,australia,oceania_islands,...",
    )
    ap.add_argument("--no-backup", action="store_true", help="Skip backup")
    args = ap.parse_args()
    board_dir: Path = args.dir
    if not board_dir.is_dir():
        print("FAIL: board dir missing", board_dir)
        return 2

    scopes = [s.strip() for s in args.scopes.split(",") if s.strip()]
    for s in scopes:
        if s not in REGION_TARGETS:
            print("FAIL: unknown scope", s, "known", sorted(REGION_TARGETS))
            return 2

    prod = build_row_sparse_density_product(board_dir=str(board_dir), scopes=scopes)
    print("[plan product]", prod.get("summary"))
    if not prod.get("ok"):
        print("WARN: density product not ok:", prod.get("fail"))
        # Allow write only if needs_write and planned roughly in band for some regions
        if not prod.get("needs_write") and not any(
            r in (prod.get("already_in_band_regions") or []) for r in scopes
        ):
            print("Abort: product fail and nothing to write.")
            return 1

    # Skip if all scoped regions already merged into band
    if not prod.get("needs_write"):
        print("Scoped regions already in band. Nothing to merge.")
        return 0

    plan = build_merge_plan(board_dir, scopes=scopes)
    print(
        "Merge plan: cells=%d → playable=%d dead=%d scopes=%s by_region=%s"
        % (
            plan["cells_n"],
            plan["survivors_n"],
            plan["dead_n"],
            plan["scopes"],
            plan["planned_by_region"],
        )
    )

    for pid in plan["protected"]:
        mapped = int(plan["remap"].get(str(pid), pid))
        if mapped != int(pid):
            # Only fail if this protected cell is in the merge set
            if any(int(pid) in [int(x) for x in (c.get("member_ids") or [])] for c in plan["clusters"]):
                print("FAIL: protected id remapped away", pid, "→", mapped)
                return 1

    if not args.write:
        print("Dry-run only. Pass --write to apply.")
        for c in plan["clusters"][:8]:
            if len(c.get("member_ids") or []) > 1:
                print(
                    "  sample",
                    c["name"],
                    "surv",
                    c["survivor_id"],
                    "n",
                    len(c["member_ids"]),
                    c["adm0"],
                )
        return 0

    if not args.no_backup:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        bak = board_dir.parent / ("provinces_world_accurate.bak_pre_row_merge_%s" % stamp)
        if bak.exists():
            shutil.rmtree(bak)
        print("Backup →", bak)
        shutil.copytree(
            board_dir,
            bak,
            ignore=shutil.ignore_patterns("*.bak*", "*.bak"),
        )

    result = apply_merge(board_dir, plan, skip_adj=args.skip_adj, quant=args.quant)
    print("WRITE OK", json.dumps(result, indent=2, default=str))

    # Post check
    base = {int(p["id"]): p for p in _load_json(board_dir / "provinces_base.json")["provinces"]}
    for pid in plan["protected"]:
        if pid in plan.get("dead_ids", []):
            print("FAIL: protected in dead list", pid)
            return 1
        # protected may have been outside scopes
        if ROW_LO <= pid < ROW_HI and pid not in base:
            # was it in merge set?
            if any(pid in (c.get("member_ids") or []) for c in plan["clusters"]):
                print("FAIL: protected missing after merge", pid)
                return 1

    row_left = sum(1 for pid in base if ROW_LO <= pid < ROW_HI)
    total = len(base)
    print("RoW block remaining:", row_left, "total provinces:", total)

    post = build_row_sparse_density_product(board_dir=str(board_dir), scopes=scopes)
    print("[post product]", post.get("summary"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
