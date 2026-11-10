#!/usr/bin/env python3
"""Re-ring ENG leftovers from Natural Earth and close the Oman land gaps.

Island rings replace the 36-vertex circles with the admin-0 map-unit part
that contains the current centroid. Somaliland notches the three coarse
blobs that already cover that outline. Oman faces on NE land are absorbed
into the longest-edge land neighbour. Abu Dhabi's overlap with Central
Indian Basin North is clipped off the sea ring.

No new province id. Adjacency is left as it is: the edited borders were
already linked both ways.

  python3 tools/map_generation/scripts/apply_eng_finish.py --measure-only
  python3 tools/map_generation/scripts/apply_eng_finish.py --dry-run
  python3 tools/map_generation/scripts/apply_eng_finish.py
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from apply_canada_holes import _stitch_shared_vertex  # noqa: E402
from canada_hole_measure import (  # noqa: E402
    _area,
    _interior_point,
    _winding,
    count_invalid_polygons,
    count_land_sea_overlaps,
    merge_positive_rings,
)
from eng_finish_product import (  # noqa: E402
    DEFAULT_DIR,
    MAP_UNITS_SHA256,
    MAP_UNITS_URL,
    OMAN_HOLE_MIN,
    OVERLAP_PAIR,
    POLY_OVERLAP_MAX,
    RERING_ADMIN,
    SOMALILAND_NOTCH,
    avoid_placeholder_vertex_count,
    choose_oman_target,
    ensure_clickable,
    measure_oman_holes,
    pair_overlap_area,
    part_for_centroid,
    placeholder_snapshot,
    snap_ring,
    source_manifest,
)
from gap_china2_outline import _clean, _nz_pair_area, as_points, region_loops  # noqa: E402
from gap_eng1_product import META_RING, META_YIELD, ring_is_raw_invalid  # noqa: E402
from gap_ussr_west2_product import overlap_px, ring_bbox  # noqa: E402

SLIVER_AREA = 5.0
SOMALILAND_ID = 900316


def _replace_span(text: str, pid: int, points, anchor, meta) -> str:
    token = '"id":%d,' % pid
    idx = text.find(token)
    if idx < 0 or text.find(token, idx + 1) >= 0:
        raise RuntimeError("geometry id %s missing or not unique" % pid)
    nxt = text.find('"id":', idx + len(token))
    window_end = nxt if nxt > 0 else len(text)
    rel = text.find('"points":', idx, window_end)
    if rel < 0:
        raise RuntimeError("id %s has no points" % pid)
    start = rel + len('"points":')
    _old, end = json.JSONDecoder().raw_decode(text, start)
    blob = json.dumps(points, separators=(",", ":"))
    text = text[:start] + blob + text[end:]
    # Re-find after the points splice. Anchors and meta sit after points.
    idx = text.find(token)
    nxt = text.find('"id":', idx + len(token))
    window_end = nxt if nxt > 0 else len(text)
    rel = text.find('"label_anchor":', idx, window_end)
    if rel < 0:
        raise RuntimeError("id %s has no label_anchor" % pid)
    start = rel + len('"label_anchor":')
    _old, end = json.JSONDecoder().raw_decode(text, start)
    text = text[:start] + json.dumps(anchor, separators=(",", ":")) + text[end:]
    idx = text.find(token)
    nxt = text.find('"id":', idx + len(token))
    window_end = nxt if nxt > 0 else len(text)
    rel = text.find('"meta":', idx, window_end)
    if rel < 0:
        raise RuntimeError("id %s has no meta" % pid)
    start = rel + len('"meta":')
    _old, end = json.JSONDecoder().raw_decode(text, start)
    text = text[:start] + json.dumps(meta, separators=(",", ":"), ensure_ascii=False) + text[end:]
    return text


def _anchor_inside(ring, anchor) -> bool:
    return _winding(ring, float(anchor[0]), float(anchor[1])) != 0


def _as_ring(loop) -> list:
    return snap_ring(as_points(loop, 6))


def _positive(ring):
    pts = [(float(p[0]), float(p[1])) for p in ring]
    if _area(pts) < 0:
        pts = list(reversed(pts))
    return pts


def _notch(ring, clip) -> list:
    loops = region_loops([_positive(ring)], [_positive(clip)], "difference")
    if not loops:
        raise RuntimeError("notch removed the ring")
    kept = []
    for loop in loops:
        if abs(_area(loop)) < 1.0:
            continue
        kept.append(loop)
    if not kept:
        raise RuntimeError("notch left only slivers")
    if len(kept) != 1:
        areas = [round(abs(_area(loop)), 2) for loop in kept]
        raise RuntimeError("notch left %s loops %s" % (len(kept), areas))
    out = _as_ring(kept[0])
    if len(out) < 3:
        raise RuntimeError("notch ring too short")
    return out


def _absorb(src, hole_ring) -> list:
    loops = merge_positive_rings(src, hole_ring)
    if not loops:
        raise RuntimeError("absorb produced no ring")
    merged = loops[0]
    for loop in loops[1:]:
        if abs(_area(loop)) >= SLIVER_AREA:
            raise RuntimeError("absorb left a %.2f px² loop" % abs(_area(loop)))
        ip = _interior_point(loop)
        if ip is not None and _winding(src, ip[0], ip[1]) != 0:
            stitched = _stitch_shared_vertex(merged, loop)
            if stitched is None:
                raise RuntimeError("absorb pinched off a real lobe")
            merged = stitched
    return _as_ring(merged)


def _clip_sea(sea, land) -> list:
    loops = region_loops([_positive(sea)], [_positive(land)], "difference")
    if not loops:
        raise RuntimeError("sea clip removed the sea ring")
    kept = [loop for loop in loops if abs(_area(loop)) >= 1.0]
    if len(kept) != 1:
        raise RuntimeError("sea clip left %d loops" % len(kept))
    return _as_ring(kept[0])


def _poly(a, b) -> float:
    return float(_nz_pair_area(_clean(a), _clean(b)))


def _centroid(points):
    area = cx = cy = 0.0
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        cross = x1 * y2 - x2 * y1
        area += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    if abs(area) < 1e-12:
        return (sum(p[0] for p in points) / n, sum(p[1] for p in points) / n)
    return (cx / (3.0 * area), cy / (3.0 * area))


def build(board: Path) -> dict:
    geo = json.loads((board / "provinces_geometry.json").read_text(encoding="utf-8"))
    by_id = {int(g["id"]): g for g in geo["provinces"]}
    rings = {
        pid: [(float(p[0]), float(p[1])) for p in g["points"]]
        for pid, g in by_id.items()
        if len(g.get("points") or []) >= 3
    }
    anchors = {pid: [float(g["label_anchor"][0]), float(g["label_anchor"][1])] for pid, g in by_id.items()}
    metas = {pid: dict(g.get("meta") or {}) for pid, g in by_id.items()}
    changed = {}

    def remember(pid, why):
        changed[pid] = why

    # Islands, then Somaliland. Oman is measured on the original board below.
    for pid, admin in RERING_ADMIN.items():
        if pid == SOMALILAND_ID:
            continue
        cx, cy = _centroid(rings[pid])
        ring = part_for_centroid(admin, cx, cy)
        ring = ensure_clickable(ring)
        ring = avoid_placeholder_vertex_count(ring)
        ring = _as_ring(ring)
        if ring_is_raw_invalid(ring):
            raise RuntimeError("NE ring %s %s is self-crossing" % (pid, admin))
        if len(ring) in (36, 72):
            raise RuntimeError("NE ring %s still has a placeholder vertex count" % pid)
        rings[pid] = ring
        if not _anchor_inside(ring, anchors[pid]):
            ip = _interior_point(ring)
            if ip is None:
                raise RuntimeError("no interior for %s" % pid)
            anchors[pid] = [round(ip[0], 4), round(ip[1], 4)]
        meta = metas[pid]
        meta[META_RING] = "ne_10m_admin_0_map_units:%s" % admin
        meta["eng_finish_url"] = MAP_UNITS_URL
        meta["eng_finish_sha256"] = MAP_UNITS_SHA256
        meta["vertex_n"] = len(ring)
        meta["area"] = round(abs(_area(ring)), 2)
        remember(pid, "rering %s" % admin)

    som = part_for_centroid("Somaliland", *_centroid(rings[SOMALILAND_ID]))
    som = _as_ring(avoid_placeholder_vertex_count(som))
    if ring_is_raw_invalid(som):
        raise RuntimeError("Somaliland ring is self-crossing")
    for nid in SOMALILAND_NOTCH:
        was = ring_is_raw_invalid(rings[nid])
        before = rings[nid]
        notched = _notch(before, som)
        # Difference must stay inside the coarse blob. A bulge would steal land.
        if abs(_poly(notched, before) - abs(_area(notched))) > POLY_OVERLAP_MAX:
            raise RuntimeError("notch %s left the original ring" % nid)
        if ring_is_raw_invalid(notched) and not was:
            raise RuntimeError("notch made %s self-crossing" % nid)
        if _poly(notched, som) > POLY_OVERLAP_MAX:
            raise RuntimeError("notch %s still overlaps Somaliland" % nid)
        if not _anchor_inside(notched, anchors[nid]):
            ip = _interior_point(notched)
            if ip is None or _winding(notched, ip[0], ip[1]) == 0:
                raise RuntimeError("notch %s lost its interior" % nid)
            anchors[nid] = [round(ip[0], 4), round(ip[1], 4)]
        rings[nid] = notched
        metas[nid][META_YIELD] = "eng_finish_notch:%s" % SOMALILAND_ID
        remember(nid, "notch for Somaliland")
    if not _anchor_inside(som, anchors[SOMALILAND_ID]):
        ip = _interior_point(som)
        if ip is None:
            raise RuntimeError("Somaliland lost its interior")
        anchors[SOMALILAND_ID] = [round(ip[0], 4), round(ip[1], 4)]
    rings[SOMALILAND_ID] = som
    metas[SOMALILAND_ID][META_RING] = "ne_10m_admin_0_map_units:Somaliland"
    metas[SOMALILAND_ID]["eng_finish_url"] = MAP_UNITS_URL
    metas[SOMALILAND_ID]["eng_finish_sha256"] = MAP_UNITS_SHA256
    metas[SOMALILAND_ID]["vertex_n"] = len(som)
    metas[SOMALILAND_ID]["area"] = round(abs(_area(som)), 2)
    remember(SOMALILAND_ID, "rering Somaliland")

    # Oman faces from the pre-edit board. These rings are not the ones above.
    report = measure_oman_holes(board, use_natural_earth=True)
    absorbed = []
    for hole in report["oman_faces_over_1"]:
        pid = choose_oman_target(hole)
        if pid is None:
            raise RuntimeError("no land target for Oman face %.2f at %s" % (hole["area_px2"], hole["centroid"]))
        if pid in (903053, 903054, 950333, 950335):
            raise RuntimeError("refusing to edit a Canada lake ring %s" % pid)
        src = rings[pid]
        was = ring_is_raw_invalid(src)
        hole_ring = [(float(p[0]), float(p[1])) for p in hole["ring"]]
        merged = _absorb(src, hole_ring)
        if ring_is_raw_invalid(merged) and not was:
            raise RuntimeError("absorb made %s self-crossing" % pid)
        probe = _interior_point(hole_ring)
        if probe is None or _winding(merged, probe[0], probe[1]) == 0:
            raise RuntimeError("hole interior left outside %s" % pid)
        if not _anchor_inside(merged, anchors[pid]):
            raise RuntimeError("label anchor left outside %s" % pid)
        rings[pid] = merged
        metas[pid]["eng_finish_absorb"] = "oman_face_%.1f" % hole["area_px2"]
        metas[pid]["vertex_n"] = len(merged)
        metas[pid]["area"] = round(abs(_area(merged)), 2)
        remember(pid, "absorb %.1f px²" % hole["area_px2"])
        absorbed.append({"area_px2": hole["area_px2"], "target": pid, "lon": hole["lon"], "lat": hole["lat"]})

    land_id, sea_id = OVERLAP_PAIR
    if _poly(rings[land_id], rings[sea_id]) > POLY_OVERLAP_MAX:
        was = ring_is_raw_invalid(rings[sea_id])
        clipped = _clip_sea(rings[sea_id], rings[land_id])
        if ring_is_raw_invalid(clipped) and not was:
            raise RuntimeError("sea clip made %s self-crossing" % sea_id)
        if not _anchor_inside(clipped, anchors[sea_id]):
            ip = _interior_point(clipped)
            if ip is None:
                raise RuntimeError("sea clip lost the interior")
            anchors[sea_id] = [round(ip[0], 4), round(ip[1], 4)]
        if _poly(rings[land_id], clipped) > POLY_OVERLAP_MAX:
            raise RuntimeError("sea clip left overlap %.3f" % _poly(rings[land_id], clipped))
        rings[sea_id] = clipped
        metas[sea_id]["eng_finish_clip"] = "minus_%s" % land_id
        remember(sea_id, "clip overlap with %s" % land_id)

    # Hayma may have grown onto the same sea. Clip again if that overlap exceeds 1.
    for pid, why in list(changed.items()):
        if not str(why).startswith("absorb"):
            continue
        if pid == land_id:
            continue
        land_bb = ring_bbox(rings[pid])
        sea_bb = ring_bbox(rings[sea_id])
        if (
            land_bb[2] < sea_bb[0]
            or sea_bb[2] < land_bb[0]
            or land_bb[3] < sea_bb[1]
            or sea_bb[3] < land_bb[1]
        ):
            continue
        if _poly(rings[pid], rings[sea_id]) > POLY_OVERLAP_MAX:
            clipped = _clip_sea(rings[sea_id], rings[pid])
            if _poly(rings[pid], clipped) > POLY_OVERLAP_MAX:
                raise RuntimeError("second sea clip left overlap on %s" % pid)
            if not _anchor_inside(clipped, anchors[sea_id]):
                ip = _interior_point(clipped)
                anchors[sea_id] = [round(ip[0], 4), round(ip[1], 4)]
            rings[sea_id] = clipped
            metas[sea_id]["eng_finish_clip"] = "minus_%s_and_%s" % (land_id, pid)
            remember(sea_id, "clip overlap with %s" % pid)

    # Yielded neighbours already overlapped their own neighbours. Notching
    # Somaliland out of them cannot be required to clear those old overlaps.
    # The new rings and the absorbed Oman provinces must tile.
    problems = []
    for pid, why in changed.items():
        if not (str(why).startswith("rering") or str(why).startswith("absorb")):
            continue
        ring = rings[pid]
        if pid >= 950000:
            continue
        bb = ring_bbox(ring)
        for oid, other in rings.items():
            if oid == pid or oid >= 950000:
                continue
            ob = ring_bbox(other)
            if bb[2] < ob[0] or ob[2] < bb[0] or bb[3] < ob[1] or ob[3] < bb[1]:
                continue
            area = _poly(ring, other)
            if area > POLY_OVERLAP_MAX:
                problems.append((round(area, 3), pid, oid, why))
            px = overlap_px(ring, other)
            if px > 1:
                problems.append(("px", px, pid, oid, why))
    if problems:
        problems.sort(key=lambda row: -row[0] if isinstance(row[0], (int, float)) else 0)
        raise RuntimeError("land overlap after edit %s" % (problems[:12],))

    return {
        "rings": rings,
        "anchors": anchors,
        "metas": metas,
        "changed": changed,
        "absorbed": absorbed,
        "by_id": by_id,
        "geo": geo,
    }


def write_board(board: Path, built: dict) -> None:
    text = (board / "provinces_geometry.json").read_text(encoding="utf-8")
    original = text
    for pid in sorted(built["changed"]):
        text = _replace_span(
            text,
            pid,
            [[p[0], p[1]] for p in built["rings"][pid]],
            built["anchors"][pid],
            built["metas"][pid],
        )
    written = json.loads(text)
    if [int(g["id"]) for g in written["provinces"]] != [int(g["id"]) for g in built["geo"]["provinces"]]:
        raise RuntimeError("province id order changed")
    old_by = {int(g["id"]): g for g in built["geo"]["provinces"]}
    for g in written["provinces"]:
        pid = int(g["id"])
        if pid in built["changed"]:
            continue
        if g.get("points") != old_by[pid].get("points"):
            raise RuntimeError("untouched province %s points changed" % pid)
    if text == original:
        raise RuntimeError("geometry text did not change")
    (board / "provinces_geometry.json").write_text(text, encoding="utf-8")


def _overlap_summary(report: dict) -> dict:
    pairs = report.get("pairs") or []
    focus = [
        row
        for row in pairs
        if (row.get("land"), row.get("water")) == OVERLAP_PAIR
        or (row.get("land"), row.get("water")) == (OVERLAP_PAIR[1], OVERLAP_PAIR[0])
    ]
    return {
        "count": int(report.get("count") or 0),
        "px_sum": int(sum(int(row.get("px") or 0) for row in pairs)),
        "focus_905734_950283": focus,
        "largest": pairs[:15],
    }


def measure_before(board: Path, dest: Path) -> dict:
    snap = placeholder_snapshot(board)
    oman = measure_oman_holes(board, use_natural_earth=True)
    # Rings are large. The report keeps the summary.
    holes = []
    for hole in oman["holes"]:
        item = dict(hole)
        item.pop("ring", None)
        holes.append(item)
    payload = {
        "base": "e62d692c4d856f4e4d8111cbb02a4ad2c2c14ad5",
        "sources": source_manifest(),
        "placeholders": snap,
        "oman_window": oman["window"],
        "oman_seed_ids": oman["seed_ids"],
        "oman_scope_provinces": oman["scope_provinces"],
        "oman_holes": holes,
        "oman_faces_over_1": [h["area_px2"] for h in oman["oman_faces_over_1"]],
        "overlap_905734_950283": pair_overlap_area(board),
        "invalid_polygons": count_invalid_polygons(board),
        "land_sea_overlaps": _overlap_summary(count_land_sea_overlaps(board)),
    }
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply ENG-MAP-FINISH geometry")
    parser.add_argument("--dir", type=Path, default=DEFAULT_DIR)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--measure-only", action="store_true")
    parser.add_argument(
        "--before",
        type=Path,
        default=Path.home() / "eng_map_finish" / "scratch" / "before.json",
    )
    args = parser.parse_args()
    if args.measure_only:
        payload = measure_before(args.dir, args.before)
        print(
            "before placeholders",
            payload["placeholders"]["remaining_placeholders"],
            "oman>1",
            payload["oman_faces_over_1"],
            "overlap",
            round(payload["overlap_905734_950283"]["poly_px2"], 4),
        )
        return 0
    for row in source_manifest():
        if not row["sha256_ok"]:
            raise SystemExit("source cache missing or hash mismatch: %s" % row["url"])
    built = build(args.dir)
    print("changed", len(built["changed"]))
    for pid, why in sorted(built["changed"].items()):
        print(" ", pid, why, "verts", len(built["rings"][pid]))
    print("absorbed", built["absorbed"])
    if args.dry_run:
        return 0
    write_board(args.dir, built)
    after = pair_overlap_area(args.dir)
    print("overlap after", round(after["poly_px2"], 4), "px", after["px"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
