#!/usr/bin/env python3
"""Replace NLD 1936 placeholder rings with geoBoundaries admin rings.

Source GeoJSON is gbOpen simplified geometry, downloaded into
~/gapnld1/scratch/geoboundaries (not committed). Numpy only.

  python3 tools/map_generation/scripts/apply_gap_nld1.py
  python3 tools/map_generation/scripts/apply_gap_nld1.py --apply

Matching keeps the admin name after diacritics and a trailing "area" are
stripped. Kabupaten/Kota are stripped only when that is the unique hit, so
Kota Sukabumi does not replace Sukabumi. A multipolygon keeps its main
island: the largest part of at least 1 px whose centroid is within
max(80 px, 1.5 radii) of the province. A nearer speck is not used.

New rings win overlapping land pixels (real neighbours are notched, never
deleted). Sea zones keep their pixels. Old placeholder pixels that covered
no other province stay with the province. Placeholder circles that belong
to a later slice are not rewritten; the new ring is clipped out of them.
A contour stair that leaves two new rings sharing more than one pixel is
shaved here: the lower id keeps the pixel. The France clipper is unchanged.
"""
from __future__ import annotations

import argparse
import inspect
import json
import math
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

import apply_gap_fra1 as fra  # noqa: E402
from apply_gap_ussr_west2 import (  # noqa: E402
    _canvas_ring,
    _is_water,
)
from gap_nld1_product import (  # noqa: E402
    META_RING,
    META_YIELD,
    SCOPE_PLACEHOLDER_IDS,
    UNKNOWN_PLACEHOLDER_IDS,
    UNKNOWN_REASONS,
    audit_changed,
    norm_name,
    norm_name_keep,
)
from gap_ussr_west2_product import (  # noqa: E402
    is_placeholder_ring,
    open_ring,
    ring_area,
    vertex_count,
)
from ne_full_geometry_align import lonlat_to_canvas, polygon_centroid  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"
GEO_PATH = BOARD / "provinces_geometry.json"
ADJ_PATH = BOARD / "province_adjacency.json"
SRC = Path.home() / "gapnld1" / "scratch" / "geoboundaries"
EVIDENCE = Path.home() / "gapnld1" / "evidence"
MIN_PART_AREA = 1.0
# Later slices still expect these circles. They keep their pixels.
GARRISON_CAPITALS = {
    "GER": 710300,
    "FRA": 710707,
    "ENG": 711414,
    "USA": 800792,
    "SOV": 903534,
    "ITA": 710963,
    "JAP": 903995,
    "POL": 711112,
    "CZE": 710146,
}
GARRISON_EXTRA = {"POL": 711054}
# lon_min, lat_min, lon_max, lat_max
CROPS = (
    ("sumatra", (94.8, -6.2, 106.6, 5.8)),
    ("java", (105.1, -8.9, 114.7, -5.6)),
    ("borneo", (108.4, -4.5, 119.4, 7.4)),
    ("sulawesi", (118.6, -6.0, 125.4, 2.2)),
    ("new_guinea", (129.8, -9.5, 141.3, 0.8)),
    ("timor", (123.6, -10.6, 127.6, -8.0)),
    ("suriname", (-58.2, 1.8, -53.8, 6.2)),
)


def _outers(geom: dict):
    gtype = str(geom.get("type") or "")
    coords = geom.get("coordinates") or []
    if gtype == "Polygon":
        if coords and coords[0]:
            yield coords[0]
    elif gtype == "MultiPolygon":
        for poly in coords:
            if poly and poly[0]:
                yield poly[0]


def load_parts() -> Dict[Tuple[str, str], List[dict]]:
    out: Dict[Tuple[str, str], List[dict]] = defaultdict(list)
    paths = sorted(SRC.glob("geoBoundaries-*_simplified.geojson"))
    if not paths:
        raise SystemExit("geoBoundaries cache missing under ~/gapnld1/scratch/geoboundaries")
    for path in paths:
        body = path.name[len("geoBoundaries-") : -len("_simplified.geojson")]
        adm0, level = body.split("-")
        doc = json.loads(path.read_text(encoding="utf-8"))
        n = 0
        for feat_i, feat in enumerate(doc.get("features") or []):
            props = feat.get("properties") if isinstance(feat.get("properties"), dict) else {}
            name = str(props.get("shapeName") or props.get("name") or "")
            folded = norm_name(name)
            kept = norm_name_keep(name)
            if not folded and not kept:
                continue
            for part_i, outer in enumerate(_outers(feat.get("geometry") or {})):
                lonlat = [[float(p[0]), float(p[1])] for p in outer]
                if len(lonlat) >= 2 and lonlat[0] == lonlat[-1]:
                    lonlat = lonlat[:-1]
                if len(lonlat) < 3:
                    continue
                canvas = _canvas_ring(lonlat)
                if len(open_ring(canvas)) < 3:
                    continue
                area = ring_area(canvas)
                if area < 0.05:
                    continue
                cx, cy = polygon_centroid(canvas)
                out[(adm0, level)].append(
                    {
                        "name": name,
                        "norm": folded,
                        "keep": kept,
                        "canvas": canvas,
                        "cx": float(cx),
                        "cy": float(cy),
                        "area": area,
                        "src_n": len(lonlat),
                        "part_id": (adm0, level, feat_i, part_i),
                        "level": level,
                    }
                )
                n += 1
        print("loaded", adm0, level, "parts", n, flush=True)
    return out


def _levels(level: str) -> List[str]:
    if level == "ADM1":
        return ["ADM1", "ADM2"]
    return ["ADM2", "ADM1"]


def _within(parts, field: str, key: str, px: float, py: float, limit: float) -> List[tuple]:
    if not key:
        return []
    hits = []
    for part in parts:
        if part.get(field) != key:
            continue
        dist = math.hypot(part["cx"] - px, part["cy"] - py)
        if dist > limit or part["area"] < MIN_PART_AREA:
            continue
        hits.append((part, dist))
    return hits


def match_provinces(base, geo, owners, parts) -> Tuple[dict, List[dict]]:
    """Name match, then the main island inside the distance limit."""
    options = {}
    skipped = []
    considered = []
    for pid in SCOPE_PLACEHOLDER_IDS:
        if owners.get(str(pid)) != "NLD":
            continue
        if pid >= 950000 or _is_water(pid, base.get(pid, {})):
            continue
        g = geo.get(pid)
        if g is None:
            continue
        meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
        if meta.get(META_RING):
            continue
        considered.append(pid)
        if pid in UNKNOWN_PLACEHOLDER_IDS:
            skipped.append(
                {"id": pid, "name": base[pid]["name"], "reason": UNKNOWN_REASONS.get(pid, "unknown")}
            )
            continue
        adm = str(meta.get("adm0_a3") or "")
        level = str(meta.get("level") or "")
        pts = open_ring(g.get("points") or [])
        px, py = polygon_centroid(pts)
        limit = max(80.0, 1.5 * math.sqrt(max(ring_area(pts), 1.0) / math.pi))
        keep = norm_name_keep(base[pid]["name"])
        folded = norm_name(base[pid]["name"])
        chosen = []
        how = ""
        for lv in _levels(level):
            chosen = _within(parts.get((adm, lv)) or [], "keep", keep, px, py, limit)
            if chosen:
                how = "keep"
                break
        if not chosen:
            for lv in _levels(level):
                chosen = _within(parts.get((adm, lv)) or [], "norm", folded, px, py, limit)
                if chosen:
                    how = "strip-admin"
                    break
        if not chosen:
            skipped.append(
                {
                    "id": pid,
                    "name": base[pid]["name"],
                    "adm0": adm,
                    "reason": "no %s name within %.1f px" % (adm or "?", limit),
                }
            )
            continue
        names = {part["name"] for part, _dist in chosen}
        if how == "strip-admin" and len(names) > 1:
            skipped.append(
                {
                    "id": pid,
                    "name": base[pid]["name"],
                    "adm0": adm,
                    "reason": "ambiguous after stripping Kabupaten/Kota: %s" % ", ".join(sorted(names)),
                }
            )
            continue
        # Main island, not the speck whose centroid happens to be nearer.
        chosen.sort(key=lambda row: (-row[0]["area"], row[1]))
        options[pid] = chosen[:4]
    matched = {}
    used = set()
    pool = []
    for pid, hits in options.items():
        for part, dist in hits:
            pool.append((dist, -part["area"], pid, part))
    pool.sort()
    claimed = set()
    for dist, _neg, pid, part in pool:
        if pid in claimed or part["part_id"] in used:
            continue
        claimed.add(pid)
        used.add(part["part_id"])
        matched[pid] = {
            "canvas": part["canvas"],
            "adm": part["part_id"][0],
            "level": part["level"],
            "dist": dist,
            "src_name": part["name"],
            "src_n": part["src_n"],
        }
    for pid in options:
        if pid not in matched:
            skipped.append(
                {"id": pid, "name": base[pid]["name"], "reason": "admin part already used by a closer province"}
            )
    skipped.sort(key=lambda row: row["id"])
    print("matched", len(matched), "unknown", len(skipped), "open", len(considered), flush=True)
    return matched, skipped


def _frozen_ids(geo) -> set:
    """Circles this slice must not rewrite, plus the Curaçao unknown."""
    frozen = set(UNKNOWN_PLACEHOLDER_IDS)
    scope = set(SCOPE_PLACEHOLDER_IDS)
    for pid, g in geo.items():
        if pid in scope:
            continue
        if is_placeholder_ring(g.get("points") or []):
            frozen.add(pid)
    return frozen


def _garrison_targets(owners, domains, adj) -> Dict[str, set]:
    borders = fra._garrison_borders(owners, domains, adj)
    out = {}
    for tag, ids in borders.items():
        have = {int(pid) for pid in ids}
        cap = GARRISON_CAPITALS.get(tag)
        if cap and owners.get(str(cap)) == tag:
            have.add(cap)
        extra = GARRISON_EXTRA.get(tag)
        if extra and owners.get(str(extra)) == tag:
            have.add(extra)
        out[tag] = have
    return out


def _print_garrison_delta(before: Dict[str, set], after: Dict[str, set]) -> None:
    tags = sorted(set(before) | set(after))
    total_b = sum(len(before.get(t) or ()) for t in tags)
    total_a = sum(len(after.get(t) or ()) for t in tags)
    print("garrison targets", total_b, "->", total_a, flush=True)
    for tag in tags:
        b = before.get(tag) or set()
        a = after.get(tag) or set()
        if b == a:
            continue
        print(
            "garrison",
            tag,
            len(b),
            "->",
            len(a),
            "added",
            sorted(a - b),
            "removed",
            sorted(b - a),
            flush=True,
        )


def _crop_window(box) -> Tuple[int, int, int, int]:
    lon0, lat0, lon1, lat1 = box
    x_west, y_south = lonlat_to_canvas(lon0, lat0)
    x_east, y_north = lonlat_to_canvas(lon1, lat1)
    x0 = int(math.floor(min(x_west, x_east)))
    y0 = int(math.floor(min(y_south, y_north)))
    x1 = int(math.ceil(max(x_west, x_east)))
    y1 = int(math.ceil(max(y_south, y_north)))
    return x0, y0, x1, y1


def render_crops(tag: str, scope: Sequence[int]) -> None:
    """Write one PNG per theater from the geometry currently on disk."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("crops skipped: Pillow missing", flush=True)
        return
    geo = {
        int(g["id"]): g
        for g in json.loads(GEO_PATH.read_text(encoding="utf-8"))["provinces"]
    }
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    scope_set = set(int(pid) for pid in scope)
    for name, box in CROPS:
        x0, y0, x1, y1 = _crop_window(box)
        w, h = x1 - x0, y1 - y0
        if w < 8 or h < 8 or w * h > 4_000_000:
            print("crop skip", name, w, h, flush=True)
            continue
        scale = 1
        if max(w, h) < 420:
            scale = 2
        img = Image.new("RGB", (w * scale, h * scale), (18, 38, 58))
        draw = ImageDraw.Draw(img)
        drawn = 0
        for pid, g in geo.items():
            if pid >= 950000:
                continue
            pts = open_ring(g.get("points") or [])
            if len(pts) < 3:
                continue
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            if max(xs) < x0 or min(xs) > x1 or max(ys) < y0 or min(ys) > y1:
                continue
            if pid in scope_set:
                color = (64, 196, 96) if tag == "after" else (210, 84, 64)
            elif owners.get(str(pid)) == "NLD":
                color = (40, 120, 70)
            else:
                color = (150, 132, 96)
            poly = [((p[0] - x0) * scale, (p[1] - y0) * scale) for p in pts]
            draw.polygon(poly, fill=color, outline=(20, 20, 20))
            drawn += 1
        path = EVIDENCE / ("%s_%s.png" % (tag, name))
        img.save(path)
        print("crop", path, "provinces", drawn, flush=True)


_FRA_CLIP_SOURCE = inspect.getsource(fra.clip_batch)
_OVERLAP_RAISE = 'raise RuntimeError("OVERLAPS %s" % (problems[:12],))'


def _ring_points(pid: int, new_rings, yields, geo):
    if pid in new_rings:
        return open_ring(new_rings[pid])
    if pid in yields:
        return open_ring(yields[pid])
    return open_ring(geo[pid].get("points") or [])


def _nld_shave_pair_overlaps(new_rings, yields, geo, base):
    """Drop contour stairs. The lower id keeps a shared pixel.

    clip_batch already makes the masks exclusive, then the pixel contour
    can bulge back across the shared edge by a couple of pixels. That is
    the only overlap this shave is allowed to clear.
    """
    from apply_gap_ussr_west2 import _ring_from_mask, _subtract
    from gap_ussr_west2_product import (
        _bboxes_overlap,
        integer_bounds,
        overlap_px,
        rasterize_centers,
    )

    def problems():
        land = {}
        for pid, g in geo.items():
            if fra._is_water(pid, base.get(pid, {})):
                continue
            if pid in new_rings:
                pts = open_ring(new_rings[pid])
            elif pid in yields:
                pts = open_ring(yields[pid])
            else:
                pts = open_ring(g.get("points") or [])
            if len(pts) >= 3:
                land[pid] = pts
        boxes = {pid: integer_bounds(pts, 0) for pid, pts in land.items()}
        found = []
        for pid in new_rings:
            ring = land[pid]
            box = boxes[pid]
            for oid, other in land.items():
                if oid == pid or not _bboxes_overlap(box, boxes[oid]):
                    continue
                ov = overlap_px(ring, other)
                if ov > 1:
                    found.append((ov, pid, oid))
        found.sort(reverse=True)
        return found

    for pass_i in range(4):
        found = problems()
        if not found:
            print("new-ring shave ok", pass_i, flush=True)
            return new_rings
        print("new-ring shave pass", pass_i, found[:8], flush=True)
        victims = {}
        for _ov, pid, oid in found:
            if pid in new_rings and oid in new_rings:
                hi, lo = (pid, oid) if pid > oid else (oid, pid)
            elif pid in new_rings:
                hi, lo = pid, oid
            elif oid in new_rings:
                hi, lo = oid, pid
            else:
                continue
            victims.setdefault(hi, set()).add(lo)
        dilate = pass_i >= 1
        for hi, lows in victims.items():
            ring = open_ring(new_rings[hi])
            bb = integer_bounds(ring, 2)
            mask = rasterize_centers(ring, bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1])
            for lo in sorted(lows):
                other = _ring_points(lo, new_rings, yields, geo)
                ob = integer_bounds(other, 2)
                om = rasterize_centers(other, ob[0], ob[1], ob[2] - ob[0], ob[3] - ob[1])
                if dilate:
                    grown = om.copy()
                    grown[1:, :] |= om[:-1, :]
                    grown[:-1, :] |= om[1:, :]
                    grown[:, 1:] |= om[:, :-1]
                    grown[:, :-1] |= om[:, 1:]
                    om = grown
                cleared = _subtract(bb, mask, ob, om)
                print("shave", hi, "minus", lo, "px", cleared, "dilate", int(dilate), flush=True)
            if int(mask.sum()) < 3:
                raise RuntimeError("shave emptied %s" % hi)
            new_rings[hi] = _ring_from_mask(mask, bb)
    found = problems()
    if found:
        raise RuntimeError("OVERLAPS %s" % (found[:12],))
    print("new-ring shave ok", 4, flush=True)
    return new_rings


def _install_nld_clip() -> None:
    """Point the France clipper's overlap raise at the NLD stair shave."""
    if _FRA_CLIP_SOURCE.count(_OVERLAP_RAISE) != 1:
        raise SystemExit("clip_batch overlap raise is not the expected single line")
    src = _FRA_CLIP_SOURCE.replace(
        _OVERLAP_RAISE,
        "new_rings = _nld_shave_pair_overlaps(new_rings, yields, geo, base)",
        1,
    )
    fra._nld_shave_pair_overlaps = _nld_shave_pair_overlaps
    exec(src, fra.__dict__)


def build(apply: bool, limit: int, id_filter: Sequence[int], match_only: bool) -> int:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    fra.META_RING = META_RING
    fra.META_YIELD = META_YIELD
    fra.EVIDENCE = EVIDENCE
    base_rows = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    base = {int(p["id"]): p for p in base_rows}
    geo_doc = json.loads(GEO_PATH.read_text(encoding="utf-8"))
    geo = {int(g["id"]): g for g in geo_doc["provinces"]}
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    domains = {pid: row.get("domain") for pid, row in base.items()}
    if len(base) != 3596 or len(geo_doc["provinces"]) != 3596:
        print("refuse: province count", len(base), len(geo_doc["provinces"]))
        return 2
    id_order = [int(g["id"]) for g in geo_doc["provinces"]]
    if len(set(id_order)) != 3596:
        print("refuse: duplicate ids")
        return 2
    adj_doc_now = json.loads(ADJ_PATH.read_text(encoding="utf-8"))
    adj_now = {k: [int(n) for n in v] for k, v in adj_doc_now["adjacency"].items()}
    before_path = EVIDENCE / "garrison_border_before.json"
    if not before_path.is_file():
        before_path.write_text(
            json.dumps(fra._garrison_borders(owners, domains, adj_now)) + "\n",
            encoding="utf-8",
        )
        print("wrote", before_path, flush=True)
    if not (EVIDENCE / "before_sumatra.png").is_file():
        render_crops("before", SCOPE_PLACEHOLDER_IDS)
    parts = load_parts()
    matched, unknown = match_provinces(base, geo, owners, parts)
    (EVIDENCE / "unknown.json").write_text(
        json.dumps({"rows": unknown}, indent=2) + "\n", encoding="utf-8"
    )
    honest_unknown = {int(row["id"]) for row in unknown}
    extra_unknown = sorted(honest_unknown - set(UNKNOWN_PLACEHOLDER_IDS))
    if extra_unknown:
        print("REFUSE extra unknown", extra_unknown, flush=True)
        for row in unknown:
            if int(row["id"]) in extra_unknown:
                print(" ", row, flush=True)
        return 2
    if id_filter:
        want = {int(i) for i in id_filter}
        matched = {pid: info for pid, info in matched.items() if pid in want}
    ids = sorted(matched)
    if limit > 0:
        ids = ids[:limit]
        matched = {pid: matched[pid] for pid in ids}
    print("batch", len(matched), flush=True)
    if match_only or not matched:
        print("match-only" if match_only else "nothing to do")
        return 0
    fra.FROZEN = _frozen_ids(geo)
    print("frozen", len(fra.FROZEN), flush=True)
    _install_nld_clip()
    new_rings, yields, stolen_from, _fm, _ym = fra.clip_batch(matched, base, geo)
    updates = {}
    updates.update(new_rings)
    updates.update(yields)
    id_set = set(id_order)
    if set(updates) - id_set:
        print("refuse: new id", sorted(set(updates) - id_set))
        return 2

    adj = {k: [int(n) for n in v] for k, v in adj_doc_now["adjacency"].items()}
    old_rings = {}
    new_ring_map = {}
    for pid, g in geo.items():
        pts = open_ring(g.get("points") or [])
        if len(pts) >= 3:
            old_rings[pid] = pts
            new_ring_map[pid] = pts
    for pid, ring in updates.items():
        new_ring_map[pid] = open_ring(ring)
    adj_changes = []
    for pid in sorted(updates):
        old_list = list(adj.get(str(pid), []))
        before_touch = fra._touches(pid, old_rings[pid], old_rings)
        after_touch = fra._touches(pid, new_ring_map[pid], new_ring_map)
        gained = after_touch - before_touch
        lost = before_touch - after_touch
        new_set = (set(old_list) - lost) | gained
        if not new_set:
            print("refuse: zero neighbours", pid)
            return 2
        updated, added, dropped = fra._order_preserving(old_list, new_set)
        if added or dropped:
            adj_changes.append(
                {"id": pid, "added": added, "dropped": dropped, "name": base[pid]["name"]}
            )
            adj[str(pid)] = updated
            for oid in dropped:
                adj[str(oid)] = [n for n in adj.get(str(oid), []) if n != pid]
            for oid in added:
                cur = list(adj.get(str(oid), []))
                if pid not in cur:
                    adj[str(oid)] = cur + [pid]
            print("adj", pid, "add", added, "drop", dropped, flush=True)
    for pid in updates:
        for nid in adj[str(pid)]:
            if pid not in adj.get(str(nid), []):
                print("refuse: asymmetric", pid, nid)
                return 2
    before_targets = _garrison_targets(owners, domains, adj_now)
    after_targets = _garrison_targets(owners, domains, adj)
    _print_garrison_delta(before_targets, after_targets)

    rows = []
    for pid, ring in sorted(new_rings.items()):
        rows.append(
            {
                "id": pid,
                "name": base[pid]["name"],
                "role": "rering",
                "verts_before": vertex_count(geo[pid]["points"]),
                "verts_after": len(open_ring(ring)),
                "area_before": round(ring_area(geo[pid]["points"]), 2),
                "area_after": round(ring_area(ring), 2),
                "source": "geoBoundaries-%s-%s:%s"
                % (matched[pid]["adm"], matched[pid]["level"], matched[pid]["src_name"]),
                "centroid_shift_px": round(matched[pid]["dist"], 2),
                "adm0": matched[pid]["adm"],
            }
        )
    for pid, ring in sorted(yields.items()):
        rows.append(
            {
                "id": pid,
                "name": base[pid]["name"],
                "role": "yield",
                "verts_before": vertex_count(geo[pid]["points"]),
                "verts_after": len(open_ring(ring)),
                "area_before": round(ring_area(geo[pid]["points"]), 2),
                "area_after": round(ring_area(ring), 2),
                "stole_for": stolen_from[pid],
            }
        )
    (EVIDENCE / "rering_table.json").write_text(
        json.dumps({"rows": rows}, indent=2) + "\n", encoding="utf-8"
    )
    (EVIDENCE / "adjacency.json").write_text(
        json.dumps({"changes": adj_changes}, indent=2) + "\n", encoding="utf-8"
    )
    added_n = sum(len(row["added"]) for row in adj_changes)
    dropped_n = sum(len(row["dropped"]) for row in adj_changes)
    summary = {
        "matched": len(new_rings),
        "yields": len(yields),
        "unknown": unknown,
        "adjacency_rows": len(adj_changes),
        "adjacency_added": added_n,
        "adjacency_removed": dropped_n,
        "garrison_before": {tag: len(ids) for tag, ids in before_targets.items()},
        "garrison_after": {tag: len(ids) for tag, ids in after_targets.items()},
    }
    (EVIDENCE / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    patched = []
    for g in geo_doc["provinces"]:
        pid = int(g["id"])
        if pid not in updates:
            patched.append(g)
            continue
        g2 = dict(g)
        g2["points"] = updates[pid]
        meta = dict(g.get("meta") or {})
        if pid in new_rings:
            meta[META_RING] = "batch"
        else:
            meta[META_YIELD] = "notch"
        g2["meta"] = meta
        patched.append(g2)
    if [int(g["id"]) for g in patched] != id_order:
        print("refuse: id order changed")
        return 2
    audit_problems = audit_changed(patched, domains, adj, sorted(new_rings))
    if audit_problems:
        print("AUDIT", audit_problems)
        return 2
    print("audit ok", flush=True)
    print("evidence", EVIDENCE, "changes", len(adj_changes), flush=True)
    if not apply:
        print("dry-run: geometry not written")
        return 0
    fra._write_geometry(updates, new_rings, matched)
    fra._write_adjacency(adj, adj_changes)
    written = json.loads(GEO_PATH.read_text(encoding="utf-8"))
    if [int(g["id"]) for g in written["provinces"]] != id_order:
        print("refuse: written id order changed")
        return 2
    borders = fra._garrison_borders(owners, domains, adj)
    (EVIDENCE / "garrison_border_after.json").write_text(
        json.dumps(borders) + "\n", encoding="utf-8"
    )
    render_crops("after", SCOPE_PLACEHOLDER_IDS)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--ids", default="")
    ap.add_argument("--match-only", action="store_true")
    args = ap.parse_args()
    id_filter = [int(x) for x in args.ids.split(",") if x.strip()]
    return build(args.apply, args.limit, id_filter, args.match_only)


if __name__ == "__main__":
    raise SystemExit(main())
