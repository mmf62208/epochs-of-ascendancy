"""GIS coastline align + pilot write helpers (pure; id-stable).

Matches GIS-shaped rings to existing province ids via centroid-in-polygon
and/or explicit province_id hints. Never renumbers play ids.
"""
from __future__ import annotations

import json
import math
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Set, Tuple

Point = List[float]
Ring = List[Point]


def polygon_centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    # Drop closing duplicate if present
    ring = list(points)
    if len(ring) >= 2 and float(ring[0][0]) == float(ring[-1][0]) and float(ring[0][1]) == float(ring[-1][1]):
        ring = ring[:-1]
    if not ring:
        return 0.0, 0.0
    # Prefer area-weighted centroid for non-degenerate rings; fall back to mean.
    area = 0.0
    cx = 0.0
    cy = 0.0
    n = len(ring)
    for i in range(n):
        x0, y0 = float(ring[i][0]), float(ring[i][1])
        x1, y1 = float(ring[(i + 1) % n][0]), float(ring[(i + 1) % n][1])
        cross = x0 * y1 - x1 * y0
        area += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    area *= 0.5
    if abs(area) < 1e-9:
        sx = sum(float(p[0]) for p in ring)
        sy = sum(float(p[1]) for p in ring)
        return sx / float(n), sy / float(n)
    cx /= 6.0 * area
    cy /= 6.0 * area
    return cx, cy


def point_in_polygon(x: float, y: float, points: Sequence[Sequence[float]]) -> bool:
    """Ray-cast PIP. Open or closed rings accepted."""
    ring = [[float(p[0]), float(p[1])] for p in points]
    if len(ring) >= 2 and ring[0][0] == ring[-1][0] and ring[0][1] == ring[-1][1]:
        ring = ring[:-1]
    n = len(ring)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-15) + xi
        ):
            inside = not inside
        j = i
    return inside


def province_id_set(provinces: Sequence[Mapping[str, Any]]) -> Set[int]:
    return {int(p["id"]) for p in provinces if "id" in p}


def index_provinces_by_id(
    provinces: Sequence[Mapping[str, Any]],
) -> Dict[int, Mapping[str, Any]]:
    return {int(p["id"]): p for p in provinces if "id" in p}


def geometry_stats(provinces: Sequence[Mapping[str, Any]]) -> Dict[str, Any]:
    sizes = [len(p.get("points") or []) for p in provinces]
    if not sizes:
        return {
            "count": 0,
            "min": 0,
            "max": 0,
            "median": 0,
            "triangles": 0,
            "below_min": 0,
        }
    ordered = sorted(sizes)
    return {
        "count": len(sizes),
        "min": ordered[0],
        "max": ordered[-1],
        "median": ordered[len(ordered) // 2],
        "avg": sum(sizes) / float(len(sizes)),
        "triangles": sum(1 for s in sizes if s == 3),
        "below_12": sum(1 for s in sizes if s < 12),
        "below_16": sum(1 for s in sizes if s < 16),
    }


def load_geometry_payload(path: Path) -> Dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def coastal_province_ids_from_terrain(terrain_payload: Mapping[str, Any]) -> List[int]:
    """Prefer top-level provinces map (world_full 2665) with domain=coastal_land."""
    provs = terrain_payload.get("provinces")
    out: List[int] = []
    if isinstance(provs, dict):
        for pid, row in provs.items():
            if not isinstance(row, dict):
                continue
            dom = str(row.get("domain", "")).strip().lower()
            if dom in ("coastal_land", "coastal"):
                out.append(int(pid))
        return sorted(out)
    # Fallback nested europe-style layer
    nested = terrain_payload.get("province_terrain_layer") or {}
    if isinstance(nested, dict) and isinstance(nested.get("provinces"), dict):
        for pid, row in nested["provinces"].items():
            if isinstance(row, dict) and str(row.get("domain", "")).startswith("coast"):
                out.append(int(pid))
    return sorted(out)


def coastal_province_ids_from_base(base_payload: Mapping[str, Any]) -> List[int]:
    provs = base_payload.get("provinces") or []
    out: List[int] = []
    for p in provs:
        if not isinstance(p, dict):
            continue
        dom = str(p.get("domain", "")).strip().lower()
        if dom in ("coastal_land", "coastal"):
            out.append(int(p["id"]))
    return sorted(out)


_WATER_DOMAINS = frozenset({"sea", "ocean", "water", "strait", "lake", "inland_water"})
_WATER_TERRAINS = frozenset({"sea", "ocean", "water", "lake"})


def _is_water_row(row: Mapping[str, Any]) -> bool:
    if not isinstance(row, dict):
        return False
    dom = str(row.get("domain", "")).strip().lower()
    if dom in _WATER_DOMAINS:
        return True
    terr = str(row.get("terrain", row.get("type", ""))).strip().lower()
    return terr in _WATER_TERRAINS


def water_province_ids_from_terrain(terrain_payload: Mapping[str, Any]) -> List[int]:
    """Sea / lake / strait province ids from terrain layer."""
    provs = terrain_payload.get("provinces")
    out: List[int] = []
    if isinstance(provs, dict):
        for pid, row in provs.items():
            if _is_water_row(row if isinstance(row, dict) else {}):
                out.append(int(pid))
    return sorted(out)


def littoral_province_ids_from_adjacency(
    terrain_payload: Mapping[str, Any],
    adjacency_payload: Mapping[str, Any],
    *,
    exclude_ids: Optional[Sequence[int]] = None,
) -> List[int]:
    """Land provinces adjacent to water but not already tagged coastal_land.

    Expands GIS pilot beyond domain=coastal_land without renumbering ids.
    """
    exclude = {int(x) for x in (exclude_ids or [])}
    coastal = set(coastal_province_ids_from_terrain(terrain_payload))
    water = set(water_province_ids_from_terrain(terrain_payload))
    exclude |= coastal
    exclude |= water

    adj_root = adjacency_payload.get("adjacency") or adjacency_payload.get("neighbors") or adjacency_payload
    if not isinstance(adj_root, dict):
        return []

    out: List[int] = []
    for pid_raw, nbs in adj_root.items():
        try:
            pid = int(pid_raw)
        except (TypeError, ValueError):
            continue
        if pid in exclude:
            continue
        if isinstance(nbs, dict):
            nb_list = nbs.get("neighbors") or nbs.get("ids") or []
        elif isinstance(nbs, (list, tuple)):
            nb_list = nbs
        else:
            continue
        touches_water = False
        for n in nb_list:
            try:
                if int(n) in water:
                    touches_water = True
                    break
            except (TypeError, ValueError):
                continue
        if touches_water:
            out.append(pid)
    return sorted(out)


def _adjacency_root(adjacency_payload: Mapping[str, Any]) -> Mapping[str, Any]:
    root = adjacency_payload.get("adjacency") or adjacency_payload.get("neighbors") or adjacency_payload
    return root if isinstance(root, dict) else {}


def _neighbor_ids(nbs: Any) -> List[int]:
    if isinstance(nbs, dict):
        raw = nbs.get("neighbors") or nbs.get("ids") or []
    elif isinstance(nbs, (list, tuple)):
        raw = nbs
    else:
        return []
    out: List[int] = []
    for n in raw:
        try:
            out.append(int(n))
        except (TypeError, ValueError):
            continue
    return out


def near_coast_inland_ids(
    terrain_payload: Mapping[str, Any],
    adjacency_payload: Mapping[str, Any],
    seed_ids: Sequence[int],
    *,
    exclude_ids: Optional[Sequence[int]] = None,
) -> List[int]:
    """Land provinces adjacent to seed coastal/littoral belt (next inland ring).

    Used for littoral_depth ≥ 2 expansion beyond direct water adjacency.
    Never includes water or seed ids.
    """
    water = set(water_province_ids_from_terrain(terrain_payload))
    seed = {int(x) for x in seed_ids}
    exclude = {int(x) for x in (exclude_ids or [])} | seed | water
    adj_root = _adjacency_root(adjacency_payload)
    out: List[int] = []
    for pid_raw, nbs in adj_root.items():
        try:
            pid = int(pid_raw)
        except (TypeError, ValueError):
            continue
        if pid in exclude:
            continue
        for n in _neighbor_ids(nbs):
            if n in seed:
                out.append(pid)
                break
    return sorted(out)


def expand_coastal_id_pool(
    terrain_payload: Mapping[str, Any],
    adjacency_payload: Optional[Mapping[str, Any]] = None,
    *,
    include_littoral: bool = True,
    littoral_depth: int = 1,
    limit: int = 0,
) -> List[int]:
    """Coastal_land ids plus optional littoral rings (land-near-water / inland belt).

    littoral_depth:
      0 — coastal_land only
      1 — + land adjacent to water (default littoral)
      2+ — successive inland rings adjacent to prior pool (map-feel expand)
    """
    coastal = coastal_province_ids_from_terrain(terrain_payload)
    pool = list(coastal)
    depth = max(0, int(littoral_depth))
    if include_littoral and adjacency_payload is not None and depth >= 1:
        lit = littoral_province_ids_from_adjacency(
            terrain_payload, adjacency_payload, exclude_ids=coastal
        )
        for pid in lit:
            if pid not in pool:
                pool.append(pid)
        # Depth 2+ : near-coast inland belts
        for _ring in range(2, depth + 1):
            extra = near_coast_inland_ids(
                terrain_payload,
                adjacency_payload,
                pool,
                exclude_ids=pool,
            )
            if not extra:
                break
            for pid in extra:
                if pid not in pool:
                    pool.append(pid)
    if limit and limit > 0:
        pool = pool[: int(limit)]
    return pool


def load_gis_features(source_path: Path) -> List[Dict[str, Any]]:
    """Load GIS-shaped features from JSON/GeoJSON-like payload.

    Supported shapes:
      {"features":[{"id":..., "province_id": optional, "points":[[x,y],...]}, ...]}
      {"type":"FeatureCollection","features":[{"properties":{...},"geometry":{"coordinates":[...]}}]}
      [{"id":..., "points":...}, ...]
    """
    raw = json.loads(Path(source_path).read_text(encoding="utf-8"))
    return normalize_gis_features(raw)


def normalize_gis_features(raw: Any) -> List[Dict[str, Any]]:
    feats: List[Any]
    if isinstance(raw, list):
        feats = raw
    elif isinstance(raw, dict):
        feats = list(raw.get("features") or raw.get("rings") or [])
    else:
        raise ValueError("GIS source must be list or object with features")

    out: List[Dict[str, Any]] = []
    for i, f in enumerate(feats):
        if not isinstance(f, dict):
            continue
        # GeoJSON Feature
        geom = f.get("geometry") if isinstance(f.get("geometry"), dict) else None
        props = f.get("properties") if isinstance(f.get("properties"), dict) else {}
        points = f.get("points") or f.get("ring") or f.get("coordinates")
        if geom is not None:
            gtype = str(geom.get("type", ""))
            coords = geom.get("coordinates")
            if gtype == "Polygon" and coords:
                points = coords[0]
            elif gtype == "MultiPolygon" and coords:
                points = coords[0][0]
            elif gtype == "LineString" and coords:
                points = coords
        if not points or len(points) < 3:
            continue
        ring: Ring = [[float(p[0]), float(p[1])] for p in points]
        # Drop closing duplicate
        if len(ring) >= 2 and ring[0][0] == ring[-1][0] and ring[0][1] == ring[-1][1]:
            ring = ring[:-1]
        if len(ring) < 3:
            continue
        fid = f.get("id", props.get("id", props.get("gis_feature_id", f"gis_{i}")))
        pid_hint = f.get("province_id", props.get("province_id", props.get("eoa_province_id")))
        entry: Dict[str, Any] = {
            "id": str(fid),
            "points": ring,
            "name": str(f.get("name", props.get("name", fid))),
        }
        if pid_hint is not None and str(pid_hint).strip() != "":
            entry["province_id"] = int(pid_hint)
        out.append(entry)
    return out


def refine_ring_as_gis(points: Sequence[Sequence[float]], *, pull: float = 0.04) -> Ring:
    """Simulate a GIS-refined coastline: densify midpoints pulled slightly toward centroid.

    Distinct points from the seed ring so a pilot write is observable, without
    renumbering or exploding topology.
    """
    ring: Ring = [[float(p[0]), float(p[1])] for p in points]
    if len(ring) >= 2 and ring[0][0] == ring[-1][0] and ring[0][1] == ring[-1][1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return ring
    cx, cy = polygon_centroid(ring)
    refined: Ring = []
    n = len(ring)
    for i in range(n):
        a = ring[i]
        b = ring[(i + 1) % n]
        refined.append([a[0], a[1]])
        mx = (a[0] + b[0]) * 0.5
        my = (a[1] + b[1]) * 0.5
        # slight inward coastal detail (toward centroid)
        mx = mx * (1.0 - pull) + cx * pull
        my = my * (1.0 - pull) + cy * pull
        refined.append([mx, my])
    # Cap runaway density
    if len(refined) > 96:
        step = max(1, len(refined) // 64)
        refined = refined[::step]
    if len(refined) < 3:
        return ring
    return refined


def build_pilot_fixture_from_geometry(
    provinces: Sequence[Mapping[str, Any]],
    coastal_ids: Sequence[int],
    *,
    limit: int = 24,
    pull: float = 0.04,
) -> List[Dict[str, Any]]:
    """Build offline GIS-like rings from existing coastal province geometry."""
    by_id = index_provinces_by_id(provinces)
    feats: List[Dict[str, Any]] = []
    for pid in list(coastal_ids)[: max(0, int(limit))]:
        prov = by_id.get(int(pid))
        if prov is None:
            continue
        pts = prov.get("points") or []
        if len(pts) < 3:
            continue
        ring = refine_ring_as_gis(pts, pull=pull)
        feats.append(
            {
                "id": "pilot_coast_%s" % pid,
                "province_id": int(pid),
                "name": "pilot coast %s" % pid,
                "points": ring,
            }
        )
    return feats


def match_gis_feature_to_province(
    feature: Mapping[str, Any],
    provinces_by_id: Mapping[int, Mapping[str, Any]],
    *,
    centroids: Optional[Mapping[int, Tuple[float, float]]] = None,
    max_centroid_dist: float = 400.0,
) -> Optional[Dict[str, Any]]:
    """Return match dict or None.

    Priority:
      1. Explicit province_id hint if id exists
      2. Province whose centroid lies inside the GIS ring
      3. Nearest province centroid within max_centroid_dist
    """
    gis_pts = feature.get("points") or []
    if len(gis_pts) < 3:
        return None
    if centroids is None:
        centroids = {
            pid: polygon_centroid(p.get("points") or [])
            for pid, p in provinces_by_id.items()
        }

    hint = feature.get("province_id")
    if hint is not None:
        pid = int(hint)
        if pid in provinces_by_id:
            return {
                "province_id": pid,
                "gis_feature_id": str(feature.get("id", "")),
                "method": "hint",
                "points": [[float(p[0]), float(p[1])] for p in gis_pts],
            }

    # Centroid-in-GIS-ring
    for pid, (cx, cy) in centroids.items():
        if point_in_polygon(cx, cy, gis_pts):
            return {
                "province_id": int(pid),
                "gis_feature_id": str(feature.get("id", "")),
                "method": "centroid_in_gis",
                "points": [[float(p[0]), float(p[1])] for p in gis_pts],
            }

    # Nearest centroid to GIS centroid
    gcx, gcy = polygon_centroid(gis_pts)
    best_pid: Optional[int] = None
    best_d = float("inf")
    for pid, (cx, cy) in centroids.items():
        d = math.hypot(cx - gcx, cy - gcy)
        if d < best_d:
            best_d = d
            best_pid = int(pid)
    if best_pid is not None and best_d <= max_centroid_dist:
        return {
            "province_id": best_pid,
            "gis_feature_id": str(feature.get("id", "")),
            "method": "nearest_centroid",
            "distance": best_d,
            "points": [[float(p[0]), float(p[1])] for p in gis_pts],
        }
    return None


def align_gis_to_provinces(
    gis_features: Sequence[Mapping[str, Any]],
    provinces: Sequence[Mapping[str, Any]],
    *,
    max_centroid_dist: float = 400.0,
) -> Dict[str, Any]:
    """Align GIS features to province ids. Pure; does not mutate geometry."""
    by_id = index_provinces_by_id(provinces)
    existing_ids = province_id_set(provinces)
    centroids = {
        pid: polygon_centroid(p.get("points") or []) for pid, p in by_id.items()
    }
    matches: List[Dict[str, Any]] = []
    orphans: List[str] = []
    claimed: Set[int] = set()
    for feat in gis_features:
        m = match_gis_feature_to_province(
            feat,
            by_id,
            centroids=centroids,
            max_centroid_dist=max_centroid_dist,
        )
        if m is None:
            orphans.append(str(feat.get("id", "?")))
            continue
        pid = int(m["province_id"])
        if pid in claimed:
            # Prefer first match; later GIS rings for same province become orphans
            orphans.append(str(feat.get("id", "?")))
            continue
        claimed.add(pid)
        matches.append(m)

    matched_ids = {int(m["province_id"]) for m in matches}
    unmatched_existing = sorted(existing_ids - matched_ids)
    id_stable = matched_ids.issubset(existing_ids) and len(existing_ids) == len(provinces)
    return {
        "matches": matches,
        "matched": len(matches),
        "matched_ids": sorted(matched_ids),
        "unmatched_existing": unmatched_existing,
        "unmatched_existing_count": len(unmatched_existing),
        "orphan_gis": orphans,
        "orphan_gis_count": len(orphans),
        "id_stable": bool(id_stable),
        "province_count": len(provinces),
        "existing_id_count": len(existing_ids),
        "gis_feature_count": len(list(gis_features)),
    }


def ensure_min_vertices(points: Sequence[Sequence[float]], min_vertices: int = 16) -> Ring:
    """Simple densify: insert midpoints until min vertex count (mirrors densify spirit)."""
    ring: Ring = [[float(p[0]), float(p[1])] for p in points]
    if len(ring) >= 2 and ring[0][0] == ring[-1][0] and ring[0][1] == ring[-1][1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return ring
    guard = 0
    while len(ring) < min_vertices and guard < 10_000:
        guard += 1
        # split longest edge
        best_i = 0
        best_len = -1.0
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            d = math.hypot(a[0] - b[0], a[1] - b[1])
            if d > best_len:
                best_len = d
                best_i = i
        a, b = ring[best_i], ring[(best_i + 1) % n]
        mid = [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5]
        ring.insert(best_i + 1, mid)
    return ring


def apply_pilot_write(
    geom_payload: Mapping[str, Any],
    matches: Sequence[Mapping[str, Any]],
    *,
    min_vertices: int = 16,
    stamp_meta: bool = True,
) -> Dict[str, Any]:
    """Return new geometry payload with matched province points updated.

    Province id set and count are preserved. Non-matched provinces unchanged.
    """
    out = deepcopy(dict(geom_payload))
    provs = [dict(p) for p in (out.get("provinces") or [])]
    by_idx = {int(p["id"]): i for i, p in enumerate(provs)}
    applied: List[int] = []
    for m in matches:
        pid = int(m["province_id"])
        if pid not in by_idx:
            continue
        pts = m.get("points") or []
        if len(pts) < 3:
            continue
        ring = ensure_min_vertices(pts, min_vertices=min_vertices)
        i = by_idx[pid]
        provs[i] = dict(provs[i])
        old_pts = provs[i].get("points") or []
        provs[i]["points"] = ring
        cx, cy = polygon_centroid(ring)
        provs[i]["label_anchor"] = [cx, cy]
        meta = dict(provs[i].get("meta") or {})
        meta["gis_feature_id"] = str(m.get("gis_feature_id", ""))
        meta["gis_align_method"] = str(m.get("method", ""))
        meta["gis_pilot"] = True
        meta["gis_points_before"] = len(old_pts)
        meta["gis_points_after"] = len(ring)
        provs[i]["meta"] = meta
        applied.append(pid)
    out["provinces"] = provs
    if stamp_meta:
        gmeta = dict(out.get("meta") or {})
        gmeta["gis_coastline_pilot"] = True
        gmeta["gis_pilot_applied_ids"] = applied
        gmeta["gis_pilot_count"] = len(applied)
        stats = geometry_stats(provs)
        gmeta["vertex_min"] = stats.get("min")
        gmeta["vertex_median"] = stats.get("median")
        gmeta["triangle_count"] = stats.get("triangles")
        out["meta"] = gmeta
    return out


def points_changed(before: Mapping[str, Any], after: Mapping[str, Any], pid: int) -> bool:
    b = index_provinces_by_id(before.get("provinces") or {})
    a = index_provinces_by_id(after.get("provinces") or {})
    if pid not in b or pid not in a:
        return False
    bp = b[pid].get("points") or []
    ap = a[pid].get("points") or []
    if len(bp) != len(ap):
        return True
    for u, v in zip(bp, ap):
        if abs(float(u[0]) - float(v[0])) > 1e-6 or abs(float(u[1]) - float(v[1])) > 1e-6:
            return True
    return False


def count_changed_provinces(before: Mapping[str, Any], after: Mapping[str, Any]) -> int:
    b = index_provinces_by_id(before.get("provinces") or {})
    a = index_provinces_by_id(after.get("provinces") or {})
    n = 0
    for pid in b:
        if pid in a and points_changed(before, after, pid):
            n += 1
    return n


def run_align_pipeline(
    geom_payload: Mapping[str, Any],
    gis_features: Sequence[Mapping[str, Any]],
    *,
    min_vertices: int = 16,
    max_centroid_dist: float = 400.0,
    apply_write: bool = False,
) -> Dict[str, Any]:
    """Full pure pipeline: align metrics + optional pilot apply."""
    provinces = list(geom_payload.get("provinces") or [])
    align = align_gis_to_provinces(
        gis_features, provinces, max_centroid_dist=max_centroid_dist
    )
    result: Dict[str, Any] = dict(align)
    result["write"] = bool(apply_write)
    result["geometry_before"] = geometry_stats(provinces)
    if apply_write:
        new_payload = apply_pilot_write(
            geom_payload, align["matches"], min_vertices=min_vertices
        )
        result["payload"] = new_payload
        result["geometry_after"] = geometry_stats(new_payload.get("provinces") or [])
        result["changed_provinces"] = count_changed_provinces(geom_payload, new_payload)
        result["id_set_before"] = sorted(province_id_set(provinces))
        result["id_set_after"] = sorted(
            province_id_set(new_payload.get("provinces") or [])
        )
        result["id_set_equal"] = result["id_set_before"] == result["id_set_after"]
        result["id_stable"] = bool(result["id_stable"] and result["id_set_equal"])
    else:
        result["payload"] = None
        result["changed_provinces"] = 0
    return result


def format_metrics_report(metrics: Mapping[str, Any], *, dry_run: bool = True) -> str:
    lines = [
        "[%s] GIS coastline ingest" % ("DRY-RUN" if dry_run else "WRITE"),
        "  province_count: %s" % metrics.get("province_count"),
        "  gis_feature_count: %s" % metrics.get("gis_feature_count"),
        "  matched: %s" % metrics.get("matched"),
        "  unmatched_existing: %s" % metrics.get("unmatched_existing_count", len(metrics.get("unmatched_existing") or [])),
        "  orphan_gis: %s" % metrics.get("orphan_gis_count", len(metrics.get("orphan_gis") or [])),
        "  id_stable: %s" % ("true" if metrics.get("id_stable") else "false"),
        "  write: %s" % ("true" if metrics.get("write") else "false"),
    ]
    if metrics.get("write"):
        lines.append("  changed_provinces: %s" % metrics.get("changed_provinces", 0))
        ga = metrics.get("geometry_after") or {}
        lines.append(
            "  geometry_after: min=%s median=%s triangles=%s"
            % (ga.get("min"), ga.get("median"), ga.get("triangles"))
        )
    return "\n".join(lines)
