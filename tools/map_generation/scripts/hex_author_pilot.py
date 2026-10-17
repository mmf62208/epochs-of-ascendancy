#!/usr/bin/env python3
"""HEXP3 Rhineland / Benelux hidden-hex authoring pilot (report only).

Lays a 15-mi flat-top lattice (5-mi × 9 subsamples) over NUTS3 prefixes
DEA/DEB/DEC/BE/NL/LU, assigns sample centres from the Eurostat GIS polygons,
and writes a coverage / adjacency / ring-fidelity report. Never writes
``data/``. Hexes never reach runtime.

  python3 tools/map_generation/scripts/hex_author_pilot.py
  python3 tools/map_generation/scripts/hex_author_pilot.py --emit-bake-preview

Mutant hooks (tests edit these, then revert):
  CHECK_REMOVED_IDS — append-only must reject removed ids; ignoring them fails T6.
  PREVIEW_DIR_OVERRIDE — non-None dumps the bake preview here; data/ fails T5.
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

import hexgrid as _hexgrid  # noqa: E402
from hexgrid import (  # noqa: E402
    HEX_DIRECTIONS,
    KM_TO_M,
    LAEA,
    MILES_TO_M,
    apply_origin_shift,
    hausdorff_m,
    hex_area_m2,
    hex_corners,
    hex_to_pixel,
    hexes_covering_bbox,
    lattice_origin_shift_m,
    pixel_to_hex,
    point_in_polygon_with_holes,
    point_in_ring,
    ring_bbox,
    shoelace_area_m2,
    size_from_flat_to_flat_m,
    subsample_axials,
    unique_sorted_pairs,
)
from ne_full_geometry_align import lonlat_to_canvas  # noqa: E402

# --- mutant hooks ---
CHECK_REMOVED_IDS: bool = True
PREVIEW_DIR_OVERRIDE: Optional[str] = None

DEFAULT_CONFIG = ROOT / "tools" / "map_generation" / "config" / "hex_pilot_rhineland.json"
RASTER_SUFFIXES = (".tif", ".tiff", ".asc", ".img", ".hgt", ".nc", ".gpkg", ".grd")

Point = Tuple[float, float]
Axial = Tuple[int, int]
Poly = Tuple[List[Point], List[List[Point]], Tuple[float, float, float, float], float]


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_config(path: Optional[Path] = None) -> Dict[str, Any]:
    cfg_path = Path(path) if path is not None else DEFAULT_CONFIG
    if not cfg_path.is_absolute():
        cfg_path = ROOT / cfg_path
    cfg = _load_json(cfg_path)
    cfg["_config_path"] = str(cfg_path)
    return cfg


def _repo_path(rel: str) -> Path:
    p = Path(rel)
    return p if p.is_absolute() else ROOT / p


def nuts_prefix_match(nuts_id: str, prefixes: Sequence[str]) -> bool:
    n = str(nuts_id or "")
    return any(n.startswith(p) for p in prefixes)


def load_pilot_provinces(cfg: Mapping[str, Any]) -> List[Dict[str, Any]]:
    base = _load_json(_repo_path(str(cfg["paths"]["base"])))
    prefixes = list(cfg["nuts_prefixes"])
    rows = [
        p
        for p in base.get("provinces") or []
        if isinstance(p, dict) and nuts_prefix_match(str(p.get("nuts_id") or ""), prefixes)
    ]
    rows.sort(key=lambda p: int(p["id"]))
    expected = int(cfg["expected_pid_count"])
    if len(rows) != expected:
        raise SystemExit(
            "HEXP3 FAIL: pilot set is %d pids, expected %d (prefixes=%s)"
            % (len(rows), expected, prefixes)
        )
    return rows


def _geojson_polygons_lonlat(geom: Mapping[str, Any]) -> List[Tuple[List[Point], List[List[Point]]]]:
    gtype = str(geom.get("type") or "")
    coords = geom.get("coordinates") or []
    polys_raw: List[Any]
    if gtype == "Polygon":
        polys_raw = [coords]
    elif gtype == "MultiPolygon":
        polys_raw = list(coords)
    else:
        return []
    out: List[Tuple[List[Point], List[List[Point]]]] = []
    for poly in polys_raw:
        if not poly:
            continue
        exterior = [(float(p[0]), float(p[1])) for p in poly[0]]
        holes = [[(float(p[0]), float(p[1])) for p in ring] for ring in poly[1:]]
        out.append((exterior, holes))
    return out


def _project_ring(proj: LAEA, ring: Sequence[Point], shift: Point) -> List[Point]:
    out: List[Point] = []
    for lon, lat in ring:
        x, y = proj.forward(lon, lat)
        out.append(apply_origin_shift(x, y, shift))
    return out


def load_gis_polygons(
    cfg: Mapping[str, Any],
    nuts_to_pid: Mapping[str, int],
    proj: LAEA,
) -> Dict[int, List[Poly]]:
    """GIS in unshifted LAEA. The hex lattice may carry an origin shift (T4 mutant)."""
    gis = _load_json(_repo_path(str(cfg["paths"]["nuts_gis"])))
    zero: Point = (0.0, 0.0)
    by_pid: Dict[int, List[Poly]] = {}
    for feat in gis.get("features") or []:
        props = feat.get("properties") or {}
        nid = str(props.get("NUTS_ID") or "")
        if nid not in nuts_to_pid:
            continue
        pid = int(nuts_to_pid[nid])
        polys: List[Poly] = []
        for ext_ll, holes_ll in _geojson_polygons_lonlat(feat.get("geometry") or {}):
            ext = _project_ring(proj, ext_ll, zero)
            holes = [_project_ring(proj, h, zero) for h in holes_ll]
            bbox = ring_bbox(ext)
            area = shoelace_area_m2(ext) - sum(shoelace_area_m2(h) for h in holes)
            polys.append((ext, holes, bbox, float(area)))
        if polys:
            by_pid.setdefault(pid, []).extend(polys)
    missing = sorted(set(nuts_to_pid.values()) - set(by_pid.keys()))
    if missing:
        raise SystemExit("HEXP3 FAIL: GIS polygons missing for pids %s" % missing[:12])
    return by_pid


def _pid_at_point(
    x: float,
    y: float,
    index: Sequence[Tuple[int, Poly]],
) -> Optional[int]:
    hits: List[Tuple[float, int]] = []
    for pid, poly in index:
        ext, holes, bbox, area = poly
        if x < bbox[0] or x > bbox[2] or y < bbox[1] or y > bbox[3]:
            continue
        if point_in_polygon_with_holes(x, y, ext, holes):
            hits.append((area, pid))
    if not hits:
        return None
    hits.sort()
    return int(hits[0][1])


def load_canvas_rings(cfg: Mapping[str, Any], pids: Set[int]) -> Dict[int, List[Point]]:
    geom = _load_json(_repo_path(str(cfg["paths"]["geometry"])))
    out: Dict[int, List[Point]] = {}
    for row in geom.get("provinces") or []:
        pid = int(row.get("id"))
        if pid not in pids:
            continue
        pts = row.get("points") or []
        out[pid] = [(float(p[0]), float(p[1])) for p in pts]
    return out


def _canvas_pid(cx: float, cy: float, rings: Mapping[int, Sequence[Point]]) -> Optional[int]:
    for pid, ring in rings.items():
        if len(ring) < 3:
            continue
        bx0, by0, bx1, by1 = ring_bbox(ring)
        if cx < bx0 or cx > bx1 or cy < by0 or cy > by1:
            continue
        if point_in_ring(cx, cy, ring):
            return int(pid)
    return None


def find_terrain_raster(gis_dir: Path) -> Optional[str]:
    if not gis_dir.is_dir():
        return None
    for p in sorted(gis_dir.iterdir()):
        if p.is_file() and p.suffix.lower() in RASTER_SUFFIXES:
            return str(p.relative_to(ROOT))
    return None


def round_floats(obj: Any, nd: int = 6) -> Any:
    if isinstance(obj, float):
        if not math.isfinite(obj):
            return None
        return round(obj, nd)
    if isinstance(obj, dict):
        return {str(k): round_floats(obj[k], nd) for k in sorted(obj.keys(), key=lambda x: str(x))}
    if isinstance(obj, list):
        return [round_floats(x, nd) for x in obj]
    return obj


def dump_canonical(obj: Any, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(round_floats(obj), sort_keys=True, indent=2, ensure_ascii=False) + "\n"
    path.write_text(text, encoding="utf-8")


def check_append_only(
    old_ids: Iterable[int],
    new_ids: Iterable[int],
    land_block_max: int = 905848,
    sea_block_max: int = 950339,
    allow_new: Optional[Iterable[int]] = None,
) -> Dict[str, Any]:
    """ID-diff / append-only: old − new == ∅; new ids must exceed the block max."""
    old_s = {int(x) for x in old_ids}
    new_s = {int(x) for x in new_ids}
    removed = sorted(old_s - new_s)
    added = sorted(new_s - old_s)
    allow = {int(x) for x in allow_new} if allow_new is not None else None
    below: List[int] = []
    unexpected: List[int] = []
    errors: List[str] = []
    if CHECK_REMOVED_IDS and removed:
        errors.append("removed_ids=%s" % removed[:20])
    for nid in added:
        if allow is not None and nid not in allow:
            unexpected.append(nid)
        if nid >= 950000:
            if nid <= int(sea_block_max):
                below.append(nid)
        else:
            if nid <= int(land_block_max):
                below.append(nid)
    if unexpected:
        errors.append("unexpected_new_ids=%s" % unexpected[:20])
    if below:
        errors.append("ids_at_or_below_block_max=%s" % below[:20])
    return {
        "ok": len(errors) == 0,
        "removed": removed,
        "added": added,
        "added_below_block_max": below,
        "unexpected_new": unexpected,
        "errors": errors,
        "old_minus_new_empty": len(removed) == 0,
        "check_removed_ids": bool(CHECK_REMOVED_IDS),
    }


def _v2_internal_edges(adj: Mapping[str, Any], pids: Set[int]) -> Set[Tuple[int, int]]:
    edges: Set[Tuple[int, int]] = set()
    for a in pids:
        for b in adj.get(str(a), []) or []:
            bi = int(b)
            if bi in pids and bi != a:
                edges.add((min(a, bi), max(a, bi)))
    return edges


def _seg_dist(a: Point, b: Point, c: Point, d: Point) -> float:
    def dist_pt_seg(px: float, py: float, x1: float, y1: float, x2: float, y2: float) -> float:
        vx, vy = x2 - x1, y2 - y1
        wx, wy = px - x1, py - y1
        vv = vx * vx + vy * vy
        if vv < 1e-18:
            return math.hypot(px - x1, py - y1)
        t = max(0.0, min(1.0, (wx * vx + wy * vy) / vv))
        return math.hypot(px - (x1 + t * vx), py - (y1 + t * vy))

    return min(
        dist_pt_seg(a[0], a[1], c[0], c[1], d[0], d[1]),
        dist_pt_seg(b[0], b[1], c[0], c[1], d[0], d[1]),
        dist_pt_seg(c[0], c[1], a[0], a[1], b[0], b[1]),
        dist_pt_seg(d[0], d[1], a[0], a[1], b[0], b[1]),
    )


def _gis_shared_edges(
    gis: Mapping[int, Sequence[Poly]],
    pids: Set[int],
    thr_m: float = 50.0,
) -> Set[Tuple[int, int]]:
    """True NUTS GIS neighbours: any ring segments within thr_m (equal-area metres)."""
    segs: Dict[int, List[Tuple[Point, Point]]] = {}
    bboxes: Dict[int, Tuple[float, float, float, float]] = {}
    for pid in pids:
        ss: List[Tuple[Point, Point]] = []
        xs: List[float] = []
        ys: List[float] = []
        for ext, holes, bbox, _area in gis[pid]:
            for ring in [ext, *list(holes)]:
                n = len(ring)
                for i in range(n):
                    ss.append((ring[i], ring[(i + 1) % n]))
            xs.extend((bbox[0], bbox[2]))
            ys.extend((bbox[1], bbox[3]))
        segs[pid] = ss
        bboxes[pid] = (min(xs), min(ys), max(xs), max(ys))
    pad = float(thr_m)
    plist = sorted(pids)
    edges: Set[Tuple[int, int]] = set()
    for i, a in enumerate(plist):
        ax0, ay0, ax1, ay1 = bboxes[a]
        for b in plist[i + 1 :]:
            bx0, by0, bx1, by1 = bboxes[b]
            if ax1 + pad < bx0 or bx1 + pad < ax0 or ay1 + pad < by0 or by1 + pad < ay0:
                continue
            best = 1e99
            for a1, a2 in segs[a]:
                for b1, b2 in segs[b]:
                    d = _seg_dist(a1, a2, b1, b2)
                    if d < best:
                        best = d
                    if best <= pad:
                        break
                if best <= pad:
                    break
            if best <= pad:
                edges.add((a, b))
    return edges


def _hex_shared_edges(owner: Mapping[Axial, int], pids: Set[int]) -> Set[Tuple[int, int]]:
    edges: Set[Tuple[int, int]] = set()
    for (q, r), pid in owner.items():
        if pid not in pids:
            continue
        for dq, dr in HEX_DIRECTIONS:
            oid = owner.get((q + dq, r + dr))
            if oid is None or oid == pid or oid not in pids:
                continue
            edges.add((min(pid, oid), max(pid, oid)))
    return edges


def _centroid_xy(polys: Sequence[Poly]) -> Point:
    # Area-weighted average of exterior ring vertices (GIS 20M rings are tiny).
    sx = 0.0
    sy = 0.0
    w = 0.0
    for ext, _holes, _bbox, area in polys:
        a = max(abs(area), 1.0)
        cx = sum(p[0] for p in ext) / float(len(ext))
        cy = sum(p[1] for p in ext) / float(len(ext))
        sx += cx * a
        sy += cy * a
        w += a
    if w <= 0.0:
        ext = polys[0][0]
        return ext[0]
    return sx / w, sy / w


def assign_samples(
    cfg: Mapping[str, Any],
    pids: Set[int],
    gis: Mapping[int, List[Poly]],
    canvas_rings: Mapping[int, Sequence[Point]],
    proj: LAEA,
    shift: Point,
    size15: float,
    size5: float,
) -> Dict[str, Any]:
    index: List[Tuple[int, Poly]] = []
    minx = miny = float("inf")
    maxx = maxy = float("-inf")
    for pid, polys in gis.items():
        for poly in polys:
            index.append((pid, poly))
            bbox = poly[2]
            minx = min(minx, bbox[0])
            miny = min(miny, bbox[1])
            maxx = max(maxx, bbox[2])
            maxy = max(maxy, bbox[3])
    parents = hexes_covering_bbox(minx, miny, maxx, maxy, size15, pad_hex=2)
    owner: Dict[Axial, int] = {}
    samples_by_pid: Dict[int, List[Dict[str, Any]]] = {pid: [] for pid in pids}
    hexes_by_pid: Dict[int, Set[Axial]] = {pid: set() for pid in pids}
    canvas_agree = 0
    canvas_disagree = 0
    canvas_none = 0

    for pq, pr in parents:
        for q5, r5 in subsample_axials(pq, pr):
            x, y = apply_origin_shift(*hex_to_pixel(q5, r5, size5), shift)
            pid = _pid_at_point(x, y, index)
            if pid is None:
                continue
            if (q5, r5) not in owner:
                owner[(q5, r5)] = pid
            hexes_by_pid[pid].add((q5, r5))
            lon, lat = proj.inverse(x, y)
            cx, cy = lonlat_to_canvas(lon, lat)
            cpid = _canvas_pid(cx, cy, canvas_rings)
            rec = {
                "q": q5,
                "r": r5,
                "parent_q": pq,
                "parent_r": pr,
                "override": False,
                "canvas_pid": cpid,
            }
            samples_by_pid[pid].append(rec)
            if cpid is None:
                canvas_none += 1
            elif int(cpid) == int(pid):
                canvas_agree += 1
            else:
                canvas_disagree += 1

    override_pids: List[int] = []
    if _hexgrid.SUBSAMPLE_ENABLED:
        for pid in sorted(pids):
            if samples_by_pid[pid]:
                continue
            cx, cy = _centroid_xy(gis[pid])
            q5, r5 = pixel_to_hex(cx - shift[0], cy - shift[1], size5)
            if (q5, r5) not in owner:
                owner[(q5, r5)] = pid
            hexes_by_pid[pid].add((q5, r5))
            lon, lat = proj.inverse(cx, cy)
            can_x, can_y = lonlat_to_canvas(lon, lat)
            cpid = _canvas_pid(can_x, can_y, canvas_rings)
            samples_by_pid[pid].append(
                {
                    "q": q5,
                    "r": r5,
                    "parent_q": None,
                    "parent_r": None,
                    "override": True,
                    "canvas_pid": cpid,
                }
            )
            override_pids.append(pid)
            if cpid is None:
                canvas_none += 1
            elif int(cpid) == int(pid):
                canvas_agree += 1
            else:
                canvas_disagree += 1

    return {
        "owner": owner,
        "samples_by_pid": samples_by_pid,
        "hexes_by_pid": hexes_by_pid,
        "override_pids": override_pids,
        "bbox": (minx, miny, maxx, maxy),
        "parent_n": len(parents),
        "canvas_agree": canvas_agree,
        "canvas_disagree": canvas_disagree,
        "canvas_none": canvas_none,
    }


def ring_fidelity(
    pids: Sequence[int],
    gis: Mapping[int, List[Poly]],
    hexes_by_pid: Mapping[int, Set[Axial]],
    size5: float,
    shift: Point,
) -> Dict[int, Dict[str, float]]:
    hex_a = hex_area_m2(size5)
    out: Dict[int, Dict[str, float]] = {}
    for pid in pids:
        gis_area = sum(abs(p[3]) for p in gis[pid])
        hexes = hexes_by_pid.get(pid) or set()
        hex_area = float(len(hexes)) * hex_a
        if gis_area <= 0.0:
            err = 0.0
        else:
            err = (hex_area - gis_area) / gis_area * 100.0
        gis_pts: List[Point] = []
        for ext, holes, _bbox, _area in gis[pid]:
            gis_pts.extend(ext)
            for h in holes:
                gis_pts.extend(h)
        hex_pts: List[Point] = []
        for q, r in hexes:
            for px, py in hex_corners(q, r, size5):
                hex_pts.append(apply_origin_shift(px, py, shift))
        hd = hausdorff_m(gis_pts, hex_pts) if hex_pts and gis_pts else 0.0
        out[pid] = {
            "gis_area_km2": gis_area / (KM_TO_M * KM_TO_M),
            "hex_area_km2": hex_area / (KM_TO_M * KM_TO_M),
            "area_error_pct": err,
            "hausdorff_km": hd / KM_TO_M,
        }
    return out


def _pid_color(pid: int) -> Tuple[int, int, int]:
    h = (int(pid) * 2654435761) & 0xFFFFFFFF
    return 70 + (h & 127), 70 + ((h >> 8) & 127), 70 + ((h >> 16) & 127)


def render_overlay_png(
    path: Path,
    gis: Mapping[int, List[Poly]],
    owner: Mapping[Axial, int],
    size5: float,
    shift: Point,
    bbox: Tuple[float, float, float, float],
    v2_only: Sequence[Sequence[int]],
    hex_only: Sequence[Sequence[int]],
    names: Mapping[int, str],
    centroids: Mapping[int, Point],
) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as exc:
        raise SystemExit(
            "HEXP3 FAIL: Pillow required for PNG (pip install --user pillow). %s" % exc
        ) from exc

    minx, miny, maxx, maxy = bbox
    pad = 20000.0
    minx -= pad
    miny -= pad
    maxx += pad
    maxy += pad
    w, h = 1600, 1400
    margin = 36

    def to_pix(x: float, y: float) -> Tuple[int, int]:
        sx = (w - 2 * margin) / max(maxx - minx, 1.0)
        sy = (h - 2 * margin) / max(maxy - miny, 1.0)
        s = min(sx, sy)
        px = margin + (x - minx) * s
        py = h - margin - (y - miny) * s
        return int(round(px)), int(round(py))

    img = Image.new("RGB", (w, h), (248, 248, 244))
    draw = ImageDraw.Draw(img, "RGBA")
    for (q, r), pid in owner.items():
        corners = hex_corners(q, r, size5)
        pix = [to_pix(*apply_origin_shift(x, y, shift)) for x, y in corners]
        col = _pid_color(pid)
        draw.polygon(pix, fill=col + (110,), outline=(40, 40, 40, 80))
    for pid, polys in gis.items():
        for ext, _holes, _bbox, _area in polys:
            pix = [to_pix(x, y) for x, y in ext]
            if len(pix) >= 2:
                draw.line(pix + [pix[0]], fill=(20, 20, 20, 220), width=1)
    for a, b in v2_only:
        if a in centroids and b in centroids:
            draw.line([to_pix(*centroids[a]), to_pix(*centroids[b])], fill=(200, 30, 30, 255), width=2)
    for a, b in hex_only:
        if a in centroids and b in centroids:
            draw.line([to_pix(*centroids[a]), to_pix(*centroids[b])], fill=(30, 80, 200, 220), width=1)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    label_pids = []
    for pid, name in names.items():
        low = name.lower()
        if any(k in low for k in ("köln", "essen", "aachen", "liège", "rotterdam", "speyer", "luxembourg")):
            label_pids.append(pid)
    for pid in label_pids:
        if pid not in centroids:
            continue
        px, py = to_pix(*centroids[pid])
        label = names[pid].split(",")[0][:18]
        draw.text((px + 3, py + 3), label, fill=(0, 0, 0, 255), font=font)
    legend = [
        "HEXP3 Rhineland / Benelux  15-mi hex + 5-mi x9",
        "black = GIS NUTS3   fill = hex owner",
        "red = v2-only (knn-suspect)   blue = hex-only",
        "game stays province-based; no data/ write",
    ]
    y = 8
    for line in legend:
        draw.text((12, y), line, fill=(10, 10, 10, 255), font=font)
        y += 14
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)


def emit_bake_preview(
    cfg: Mapping[str, Any],
    pids: Set[int],
    hex_edges: Set[Tuple[int, int]],
    terrain_by_pid: Mapping[int, str],
    names: Mapping[int, str],
) -> Dict[str, Any]:
    adj_path = _repo_path(str(cfg["paths"]["adjacency"]))
    ter_path = _repo_path(str(cfg["paths"]["terrain"]))
    adj_doc = _load_json(adj_path)
    ter_doc = _load_json(ter_path)
    old_adj_ids = {int(k) for k in (adj_doc.get("adjacency") or {})}
    old_ter_ids = {int(k) for k in (ter_doc.get("provinces") or {})}

    hex_nbs: Dict[int, Set[int]] = {pid: set() for pid in pids}
    for a, b in hex_edges:
        hex_nbs[a].add(b)
        hex_nbs[b].add(a)

    new_adj = dict(adj_doc.get("adjacency") or {})
    for pid in pids:
        keep: List[int] = []
        seen: Set[int] = set()
        for b in new_adj.get(str(pid), []) or []:
            bi = int(b)
            if bi not in pids and bi not in seen:
                keep.append(bi)
                seen.add(bi)
        for b in sorted(hex_nbs.get(pid) or []):
            if b not in seen:
                keep.append(int(b))
                seen.add(int(b))
        new_adj[str(pid)] = keep

    preview_adj = {
        "version": 3,
        "method": "hex_shared_edge",
        "source": "hex_author_pilot.py rhineland P3 dry-run",
        "note": "candidate only; lives under tools/map_generation/output/; not loaded by the game",
        "straits": adj_doc.get("straits"),
        "adjacency": new_adj,
    }

    new_ter = dict(ter_doc.get("provinces") or {})
    for pid in pids:
        row = dict(new_ter.get(str(pid)) or {})
        word = str(terrain_by_pid.get(pid) or row.get("terrain") or "plains")
        row["terrain"] = word
        row["terrain_mix"] = {word: 1.0}
        row["terrain_mix_source"] = "existing_majority_raster_missing"
        new_ter[str(pid)] = row
    preview_ter = {
        "note": "candidate terrain_mix; raster missing so mix is 100% current word",
        "raster": "missing",
        "provinces": new_ter,
    }

    out_dir = Path(PREVIEW_DIR_OVERRIDE) if PREVIEW_DIR_OVERRIDE else None
    if out_dir is not None and not out_dir.is_absolute():
        out_dir = ROOT / out_dir
    ter_out = _repo_path(str(cfg["preview_terrain"]))
    adj_out = _repo_path(str(cfg["preview_adjacency"]))
    if out_dir is not None:
        ter_out = out_dir / ter_out.name
        adj_out = out_dir / adj_out.name
    dump_canonical(preview_ter, ter_out)
    dump_canonical(preview_adj, adj_out)

    new_adj_ids = {int(k) for k in preview_adj["adjacency"]}
    new_ter_ids = {int(k) for k in preview_ter["provinces"]}
    chk_adj = check_append_only(
        old_adj_ids,
        new_adj_ids,
        land_block_max=int(cfg["land_block_max"]),
        sea_block_max=int(cfg["sea_block_max"]),
        allow_new=[],
    )
    chk_ter = check_append_only(
        old_ter_ids,
        new_ter_ids,
        land_block_max=int(cfg["land_block_max"]),
        sea_block_max=int(cfg["sea_block_max"]),
        allow_new=[],
    )
    return {
        "terrain_path": str(ter_out.relative_to(ROOT)),
        "adjacency_path": str(adj_out.relative_to(ROOT)),
        "id_diff_adjacency": chk_adj,
        "id_diff_terrain": chk_ter,
        "ok": bool(chk_adj.get("ok") and chk_ter.get("ok")),
        "pilot_new_ids": 0,
        "names_touched": [names[p] for p in sorted(pids) if p in names][:8],
    }


def build_report(
    cfg: Mapping[str, Any],
    write_png: bool = True,
    emit_preview: bool = False,
) -> Dict[str, Any]:
    rows = load_pilot_provinces(cfg)
    pids = {int(p["id"]) for p in rows}
    names = {int(p["id"]): str(p.get("name") or "") for p in rows}
    nuts = {int(p["id"]): str(p.get("nuts_id") or "") for p in rows}
    nuts_to_pid = {str(p.get("nuts_id")): int(p["id"]) for p in rows}
    terrain_by_pid = {int(p["id"]): str(p.get("terrain") or "plains") for p in rows}

    proj_cfg = cfg.get("projection") or {}
    proj = LAEA(float(proj_cfg.get("lon0", 6.0)), float(proj_cfg.get("lat0", 50.0)))
    shift = lattice_origin_shift_m()
    size15 = size_from_flat_to_flat_m(float(cfg["hex_flat_to_flat_miles"]) * MILES_TO_M)
    size5 = size_from_flat_to_flat_m(float(cfg["subsample_flat_to_flat_miles"]) * MILES_TO_M)

    gis = load_gis_polygons(cfg, nuts_to_pid, proj)
    canvas_rings = load_canvas_rings(cfg, pids)
    assigned = assign_samples(cfg, pids, gis, canvas_rings, proj, shift, size15, size5)

    adj_doc = _load_json(_repo_path(str(cfg["paths"]["adjacency"])))
    v2_edges = _v2_internal_edges(adj_doc.get("adjacency") or {}, pids)
    hex_edges = _hex_shared_edges(assigned["owner"], pids)
    gis_edges = _gis_shared_edges(gis, pids, thr_m=50.0)
    agree = v2_edges & hex_edges
    v2_only = v2_edges - hex_edges
    hex_only = hex_edges - v2_edges
    v2_only_knn = v2_only - gis_edges
    v2_only_missed_true = v2_only & gis_edges
    hex_vs_gis = hex_edges & gis_edges
    v2_n = len(v2_edges)
    gis_n = len(gis_edges)
    agree_frac = (float(len(agree)) / float(v2_n)) if v2_n else 1.0
    hex_vs_gis_frac = (float(len(hex_vs_gis)) / float(gis_n)) if gis_n else 1.0

    fid = ring_fidelity(sorted(pids), gis, assigned["hexes_by_pid"], size5, shift)
    errs = [fid[p]["area_error_pct"] for p in sorted(pids)]
    hds = [fid[p]["hausdorff_km"] for p in sorted(pids)]
    errs_s = sorted(errs)
    hds_s = sorted(hds)

    gis_dir = _repo_path(str(cfg["paths"]["gis_dir"]))
    raster = find_terrain_raster(gis_dir)
    if raster is None:
        terrain_mix: Dict[str, Any] = {
            "raster": "missing",
            "note": "no DEM or land-cover raster in data/gis/; mix step stopped",
            "fallback_majority_counts": {},
        }
        terrain_mix["fallback_majority_counts"] = dict(Counter(terrain_by_pid.values()))
    else:
        terrain_mix = {"raster": raster, "note": "present but unused in this report-only pilot"}

    pid_rows: Dict[str, Any] = {}
    for pid in sorted(pids):
        samples = assigned["samples_by_pid"][pid]
        hexes = assigned["hexes_by_pid"][pid]
        canvas_hit = sum(1 for s in samples if s.get("canvas_pid") == pid)
        pid_rows[str(pid)] = {
            "name": names[pid],
            "nuts_id": nuts[pid],
            "hex_n": len(hexes),
            "sample_n": len(samples),
            "override": pid in assigned["override_pids"],
            "terrain": terrain_by_pid[pid],
            "canvas_agree_n": canvas_hit,
            "canvas_disagree_n": len(samples) - canvas_hit,
            **fid[pid],
        }

    covered = sum(1 for pid in pids if assigned["samples_by_pid"][pid])
    adj_agree_ok = hex_vs_gis_frac >= 0.90
    v2_n_ok = v2_n == int(cfg["expected_v2_internal_edges"])
    v2_explained_ok = (agree_frac >= 0.90) or (
        agree_frac + (float(len(v2_only_knn)) / float(v2_n) if v2_n else 0.0) >= 0.90
        and len(v2_only) > 0
    )

    # Honest go/no-go from this report (P4 bakes stay Mike-gated).
    p4_mix = "NO-GO" if raster is None else "CONDITIONAL GO"
    p4_adj = "CONDITIONAL GO" if adj_agree_ok else "NO-GO"
    p4_rings = "NO-GO"
    go = {
        "p3_report": "GO",
        "p4_terrain_mix_field": p4_mix,
        "p4_adjacency_v3": p4_adj,
        "p4_rings": p4_rings,
        "notes": {
            "p4_terrain_mix_field": "raster missing — cannot bake a real mix; majority word is already on the layer",
            "p4_adjacency_v3": "seed-moving; Mike-gated. hex-vs-GIS shared-edge is the quality bar; vs-v2 shortfall is knn suspects",
            "p4_rings": "hexes coarser than NUTS3 (73/180 sub-15-mi); ring rebuild ripples through ~20 coordinate readers",
        },
    }

    report: Dict[str, Any] = {
        "pilot": cfg.get("name"),
        "bc_id": cfg.get("bc_id"),
        "hex_flat_to_flat_miles": cfg["hex_flat_to_flat_miles"],
        "subsample_miles": cfg["subsample_flat_to_flat_miles"],
        "subsamples_per_hex": cfg["subsamples_per_hex"],
        "subsample_enabled": bool(_hexgrid.SUBSAMPLE_ENABLED),
        "projection": {
            "kind": "laea",
            "lon0": proj.lon0_deg,
            "lat0": proj.lat0_deg,
        },
        "pid_count": len(pids),
        "id_diff": 0,
        "coverage_n": covered,
        "coverage": "%d/%d" % (covered, len(pids)),
        "override_pids": sorted(int(x) for x in assigned["override_pids"]),
        "pids": pid_rows,
        "adjacency": {
            "v2_internal_n": v2_n,
            "v2_internal_expected": int(cfg["expected_v2_internal_edges"]),
            "v2_internal_match_expected": v2_n_ok,
            "hex_internal_n": len(hex_edges),
            "agree_n": len(agree),
            "agree_frac": agree_frac,
            "agree_ge_90_vs_v2": agree_frac >= 0.90,
            "agree_ge_90_vs_gis_or_explained": v2_explained_ok,
            "gis_internal_n": gis_n,
            "hex_vs_gis_agree_n": len(hex_vs_gis),
            "hex_vs_gis_agree_frac": hex_vs_gis_frac,
            "hex_vs_gis_ge_90": adj_agree_ok,
            "v2_only": unique_sorted_pairs(v2_only),
            "v2_only_knn": unique_sorted_pairs(v2_only_knn),
            "v2_only_missed_true": unique_sorted_pairs(v2_only_missed_true),
            "hex_only": unique_sorted_pairs(hex_only),
            "knn_suspects": unique_sorted_pairs(v2_only_knn),
        },
        "terrain_mix": terrain_mix,
        "ring_fidelity_summary": {
            "median_area_error_pct": errs_s[len(errs_s) // 2] if errs_s else 0.0,
            "median_hausdorff_km": hds_s[len(hds_s) // 2] if hds_s else 0.0,
            "max_hausdorff_km": hds_s[-1] if hds_s else 0.0,
            "max_abs_area_error_pct": max((abs(x) for x in errs), default=0.0),
            "sub_15mi_hex_n": sum(1 for p in pids if fid[p]["gis_area_km2"] < 505.0),
        },
        "canvas_compare": {
            "agree_n": assigned["canvas_agree"],
            "disagree_n": assigned["canvas_disagree"],
            "none_n": assigned["canvas_none"],
        },
        "go_nogo": go,
        "parent_hex_n": assigned["parent_n"],
        "assigned_hex_n": len(assigned["owner"]),
    }

    preview_info: Optional[Dict[str, Any]] = None
    if emit_preview:
        preview_info = emit_bake_preview(cfg, pids, hex_edges, terrain_by_pid, names)
        report["bake_preview"] = {
            "terrain_path": preview_info["terrain_path"],
            "adjacency_path": preview_info["adjacency_path"],
            "id_diff_ok": preview_info["ok"],
            "id_diff_adjacency": preview_info["id_diff_adjacency"],
            "id_diff_terrain": preview_info["id_diff_terrain"],
        }

    out_json = _repo_path(str(cfg["report_json"]))
    dump_canonical(report, out_json)
    if write_png:
        centroids = {pid: _centroid_xy(gis[pid]) for pid in pids}
        render_overlay_png(
            _repo_path(str(cfg["report_png"])),
            gis,
            assigned["owner"],
            size5,
            shift,
            assigned["bbox"],
            report["adjacency"]["v2_only"],
            report["adjacency"]["hex_only"],
            names,
            centroids,
        )
    report["_assigned"] = assigned
    report["_preview"] = preview_info
    report["_json_path"] = str(out_json)
    return report


def git_guard_paths(base: str) -> Dict[str, Any]:
    """T5: no data/ or scripts/ (Godot) in the diff vs base. Also flags untracked."""
    diff = subprocess.check_output(
        ["git", "diff", "--name-only", base],
        cwd=str(ROOT),
        text=True,
    )
    untracked = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=str(ROOT),
        text=True,
    )
    names = [ln.strip() for ln in (diff + "\n" + untracked).splitlines() if ln.strip()]
    banned = [
        n
        for n in names
        if n.startswith("data/") or n.startswith("scripts/")
    ]
    return {
        "ok": len(banned) == 0,
        "banned": banned,
        "all": names,
        "base": base,
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", default=str(DEFAULT_CONFIG))
    ap.add_argument("--emit-bake-preview", action="store_true")
    ap.add_argument("--skip-png", action="store_true")
    args = ap.parse_args(list(argv) if argv is not None else None)
    cfg = load_config(Path(args.config))
    report = build_report(cfg, write_png=not args.skip_png, emit_preview=bool(args.emit_bake_preview))
    adj = report["adjacency"]
    print("HEXP3 Rhineland pilot")
    print("  pids %s coverage %s id_diff %s" % (report["pid_count"], report["coverage"], report["id_diff"]))
    print(
        "  adjacency agree %s/%s (%.4f) v2-only %s hex-only %s"
        % (
            adj["agree_n"],
            adj["v2_internal_n"],
            adj["agree_frac"],
            len(adj["v2_only"]),
            len(adj["hex_only"]),
        )
    )
    print("  terrain_mix raster=%s" % report["terrain_mix"].get("raster"))
    print(
        "  ring median |area err| skipped; median hausdorff_km=%.3f max=%.3f"
        % (
            report["ring_fidelity_summary"]["median_hausdorff_km"],
            report["ring_fidelity_summary"]["max_hausdorff_km"],
        )
    )
    print("  go/no-go %s" % report["go_nogo"])
    print("  wrote %s" % report["_json_path"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
