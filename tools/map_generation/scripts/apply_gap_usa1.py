#!/usr/bin/env python3
"""Replace USA 1936 placeholder rings with geoBoundaries admin rings.

Source GeoJSON is gbOpen simplified geometry, downloaded into
~/mapusa/scratch/geoboundaries (not committed). Numpy only.

  python3 tools/map_generation/scripts/apply_gap_usa1.py
  python3 tools/map_generation/scripts/apply_gap_usa1.py --apply

Matching keeps the admin name after diacritics, a trailing "area", and
"County" are stripped. A multipolygon keeps its main part: the largest
part of at least 1 px whose centroid is within max(80 px, 1.5 radii) of
the province. A nearer islet is not used, and unmatched islets do not
become provinces.

New rings win overlapping land pixels against USA neighbours (those
neighbours are notched, never deleted). Sea zones keep their pixels.
A non-USA province is clipped out of the new ring and is never notched.
Old placeholder pixels that covered no other province stay with the
province. The NLD stair shave runs on the France clipper.

--apply also writes meta gap_sia1_yield="exempt:gap_usa1" on each USA
re-ring and notch. That is the area exemption the NLD and SIA checks
already recognize. It is not a Siam notch. See docs/MAP_2C_USA.md.
"""
from __future__ import annotations

import argparse
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
import apply_gap_nld1 as nld  # noqa: E402
from apply_gap_ussr_west2 import (  # noqa: E402
    _canvas_ring,
    _is_water,
)
from gap_usa1_product import (  # noqa: E402
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
SRC = Path.home() / "mapusa" / "scratch" / "geoboundaries"
EVIDENCE = Path.home() / "mapusa" / "evidence"
MIN_PART_AREA = 1.0
# Same capitals the NLD slice uses to preview the garrison border set.
GARRISON_CAPITALS = nld.GARRISON_CAPITALS
GARRISON_EXTRA = nld.GARRISON_EXTRA
# Stop if the new rings add and remove more than this many undirected edges.
ADJ_EDGE_STOP = 40
# NLD area_change_ok exempts a later slice only when meta has gap_sia1 or
# gap_sia1_yield. SIA area_change_ok exempts only those two keys. Both
# products are outside this slice's fence, so each USA re-ring and notch
# also carries gap_sia1_yield. The value is an exemption mark for this
# slice. It is not a Siam notch. gap_sia1 stays unset, so SIA's ring audit
# does not adopt these provinces.
EXEMPT_KEY = "gap_sia1_yield"
EXEMPT_VALUE = "exempt:gap_usa1"
# lon_min, lat_min, lon_max, lat_max
CROPS = (
    ("northeast", (-80.5, 37.5, -66.8, 47.6)),
    ("southeast", (-92.0, 24.4, -75.4, 37.6)),
    ("midwest", (-104.2, 36.0, -80.4, 49.4)),
    ("texas", (-106.8, 25.6, -93.4, 36.6)),
    ("west", (-125.0, 31.2, -102.0, 49.2)),
    ("alaska", (-170.0, 51.0, -129.0, 71.5)),
    ("hawaii", (-160.6, 18.6, -154.6, 22.4)),
    ("philippines", (116.4, 4.2, 127.2, 21.2)),
    ("puerto_rico", (-67.6, 17.6, -65.1, 18.6)),
    ("guam", (144.5, 13.2, 145.0, 13.7)),
)


def _outers(geom: dict):
    return nld._outers(geom)


def _source_levels(adm: str, level: str) -> List[Tuple[str, str]]:
    """Admin files whose granularity can match this province, then USA ADM1.

    Philippine provinces are PHL ADM2. Guam is the GUM ADM0 island (GUM
    ADM1 is a 404; GUM ADM2 is villages). Puerto Rico has no PRI ADM0 or
    ADM1; the USA ADM1 commonwealth outline is the same-name unit.
    """
    order: List[Tuple[str, str]] = []
    if adm == "PHL":
        order = [("PHL", "ADM2"), ("PHL", "ADM1")]
    elif adm == "GUM":
        order = [("GUM", "ADM0"), ("GUM", "ADM2"), ("GUM", "ADM1")]
    elif adm == "PRI":
        order = [("PRI", "ADM1"), ("PRI", "ADM0"), ("PRI", "ADM2")]
    elif level in ("ADM0", "ADM1", "ADM2"):
        order = [(adm, level)]
        for lv in ("ADM2", "ADM1", "ADM0"):
            if (adm, lv) not in order:
                order.append((adm, lv))
    else:
        order = [(adm, "ADM2"), (adm, "ADM1"), (adm, "ADM0")]
    if ("USA", "ADM1") not in order:
        order.append(("USA", "ADM1"))
    return order


def load_parts() -> Dict[Tuple[str, str], List[dict]]:
    out: Dict[Tuple[str, str], List[dict]] = defaultdict(list)
    paths = sorted(SRC.glob("geoBoundaries-*_simplified.geojson"))
    if not paths:
        raise SystemExit("geoBoundaries cache missing under ~/mapusa/scratch/geoboundaries")
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
    """Name match, then the main part inside the distance limit."""
    options = {}
    skipped = []
    considered = []
    for pid in SCOPE_PLACEHOLDER_IDS:
        if owners.get(str(pid)) != "USA":
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
        used_level = ""
        for adm_i, lv in _source_levels(adm, level):
            chosen = _within(parts.get((adm_i, lv)) or [], "keep", keep, px, py, limit)
            if chosen:
                how = "keep"
                used_level = "%s-%s" % (adm_i, lv)
                break
        if not chosen:
            for adm_i, lv in _source_levels(adm, level):
                chosen = _within(parts.get((adm_i, lv)) or [], "norm", folded, px, py, limit)
                if chosen:
                    how = "strip-admin"
                    used_level = "%s-%s" % (adm_i, lv)
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
                    "reason": "ambiguous after stripping County: %s" % ", ".join(sorted(names)),
                }
            )
            continue
        # Main part, not the islet whose centroid happens to be nearer.
        chosen.sort(key=lambda row: (-row[0]["area"], row[1]))
        part, dist = chosen[0]
        options[pid] = [(part, dist, used_level)]
    matched = {}
    used = set()
    for pid, hits in options.items():
        part, dist, used_level = hits[0]
        if part["part_id"] in used:
            skipped.append(
                {"id": pid, "name": base[pid]["name"], "reason": "admin part already used by a closer province"}
            )
            continue
        used.add(part["part_id"])
        matched[pid] = {
            "canvas": part["canvas"],
            "adm": part["part_id"][0],
            "level": part["level"],
            "dist": dist,
            "src_name": part["name"],
            "src_n": part["src_n"],
            "source_level": used_level,
        }
    skipped.sort(key=lambda row: row["id"])
    print("matched", len(matched), "unknown", len(skipped), "open", len(considered), flush=True)
    return matched, skipped


def _frozen_ids(geo, owners) -> set:
    """Non-USA rings, the unknown list, and later slices' placeholder circles.

    A non-USA province is subtracted from the new ring inside clip_batch
    and is never yielded. Sea zones are non-USA here as well.
    """
    frozen = set(UNKNOWN_PLACEHOLDER_IDS)
    scope = set(SCOPE_PLACEHOLDER_IDS)
    for pid, g in geo.items():
        owner = owners.get(str(pid))
        if owner != "USA":
            frozen.add(pid)
            continue
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
            elif owners.get(str(pid)) == "USA":
                color = (40, 120, 70)
            else:
                color = (150, 132, 96)
            poly = [((p[0] - x0) * scale, (p[1] - y0) * scale) for p in pts]
            draw.polygon(poly, fill=color, outline=(20, 20, 20))
            drawn += 1
        path = EVIDENCE / ("%s_%s.png" % (tag, name))
        img.save(path)
        print("crop", path, "provinces", drawn, flush=True)


def _edge_delta(adj_changes) -> Tuple[set, set]:
    added, removed = set(), set()
    for row in adj_changes:
        pid = int(row["id"])
        for oid in row["added"]:
            added.add((min(pid, int(oid)), max(pid, int(oid))))
        for oid in row["dropped"]:
            removed.add((min(pid, int(oid)), max(pid, int(oid))))
    return added, removed


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
    if not (EVIDENCE / "before_northeast.png").is_file():
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
        if apply and not match_only:
            return stamp_area_exemption()
        return 0
    fra.FROZEN = _frozen_ids(geo, owners)
    print("frozen", len(fra.FROZEN), flush=True)
    nld._install_nld_clip()
    new_rings, yields, stolen_from, _fm, _ym = fra.clip_batch(matched, base, geo)
    updates = {}
    updates.update(new_rings)
    updates.update(yields)
    id_set = set(id_order)
    if set(updates) - id_set:
        print("refuse: new id", sorted(set(updates) - id_set))
        return 2
    foreign_updates = sorted(pid for pid in updates if owners.get(str(pid)) != "USA")
    if foreign_updates:
        print("refuse: non-USA geometry", foreign_updates)
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
    added_edges, removed_edges = _edge_delta(adj_changes)
    print(
        "adjacency undirected +%d -%d total %d"
        % (len(added_edges), len(removed_edges), len(added_edges) + len(removed_edges)),
        flush=True,
    )
    if len(added_edges) + len(removed_edges) > ADJ_EDGE_STOP:
        print(
            "STOP adjacency +%d -%d exceeds %d"
            % (len(added_edges), len(removed_edges), ADJ_EDGE_STOP),
            flush=True,
        )
        (EVIDENCE / "adjacency_stop.json").write_text(
            json.dumps(
                {
                    "added": [list(p) for p in sorted(added_edges)],
                    "removed": [list(p) for p in sorted(removed_edges)],
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        return 3
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
                "source_level": matched[pid]["source_level"],
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
                "owner": owners.get(str(pid)),
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
        json.dumps(
            {
                "changes": adj_changes,
                "undirected_added": len(added_edges),
                "undirected_removed": len(removed_edges),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    summary = {
        "matched": len(new_rings),
        "yields": len(yields),
        "unknown": unknown,
        "adjacency_rows": len(adj_changes),
        "adjacency_added": len(added_edges),
        "adjacency_removed": len(removed_edges),
        "max_centroid_shift_px": max((row["centroid_shift_px"] for row in rows if row["role"] == "rering"), default=0),
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
    if stamp_area_exemption() != 0:
        return 2
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


def _insert_meta_key(raw: str, pid: int, insertion: str) -> str:
    """Insert a compact key before the closing brace of this province's meta."""
    start, end = fra._find_object(raw, pid)
    chunk = raw[start:end]
    token = '"meta":'
    at = chunk.find(token)
    if at < 0:
        raise RuntimeError("missing meta %s" % pid)
    val_at = at + len(token)
    if chunk[val_at] != "{":
        raise RuntimeError("meta not object %s" % pid)
    depth = 0
    in_str = False
    esc = False
    k = val_at
    while k < len(chunk):
        ch = chunk[k]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    else:
        raise RuntimeError("unclosed meta %s" % pid)
    new_chunk = chunk[:k] + insertion + chunk[k:]
    return raw[:start] + new_chunk + raw[end:]


def stamp_area_exemption() -> int:
    """Mark USA re-rings and notches so the NLD and SIA area checks exempt them.

    Touches only provinces that already carry gap_usa1 or gap_usa1_yield.
    Other province objects stay byte-identical.
    """
    owners = json.loads((BOARD / "province_ownership_1936.json").read_text(encoding="utf-8"))["owners"]
    raw = GEO_PATH.read_text(encoding="utf-8")
    doc = json.loads(raw)
    targets = []
    for g in doc["provinces"]:
        pid = int(g["id"])
        meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
        if not (meta.get(META_RING) or meta.get(META_YIELD)):
            continue
        if owners.get(str(pid)) != "USA":
            print("refuse: exemption on non-USA", pid)
            return 2
        if meta.get("gap_sia1"):
            print("refuse: gap_sia1 already set", pid)
            return 2
        existing = meta.get(EXEMPT_KEY)
        if existing == EXEMPT_VALUE:
            continue
        if existing not in (None, ""):
            print("refuse: gap_sia1_yield already", pid, existing)
            return 2
        targets.append(pid)
    insertion = ',"%s":"%s"' % (EXEMPT_KEY, EXEMPT_VALUE)
    for pid in sorted(targets, reverse=True):
        raw = _insert_meta_key(raw, pid, insertion)
    if targets:
        check = json.loads(raw)
        if [int(g["id"]) for g in check["provinces"]] != [int(g["id"]) for g in doc["provinces"]]:
            print("refuse: exemption changed id order")
            return 2
        by_id = {int(g["id"]): g for g in check["provinces"]}
        for pid in targets:
            meta = by_id[pid].get("meta") or {}
            if meta.get(EXEMPT_KEY) != EXEMPT_VALUE:
                print("refuse: stamp missing", pid)
                return 2
            if not (meta.get(META_RING) or meta.get(META_YIELD)):
                print("refuse: stamp dropped usa meta", pid)
                return 2
        GEO_PATH.write_text(raw, encoding="utf-8")
    print("exemption stamped", len(targets), flush=True)
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
