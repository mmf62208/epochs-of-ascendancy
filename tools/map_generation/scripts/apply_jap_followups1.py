#!/usr/bin/env python3
"""Apply JAP-FOLLOWUPS-1: clip 950247 off land, re-ring Kinmen 903981.

  python3 tools/map_generation/scripts/apply_jap_followups1.py --measure-only
  python3 tools/map_generation/scripts/apply_jap_followups1.py --dry-run
  python3 tools/map_generation/scripts/apply_jap_followups1.py

Kinmen source is ~/jap_followups/scratch/sources/geoBoundaries-TWN-ADM1_simplified.geojson
(not committed). Numpy only.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from canada_hole_measure import _area, _winding  # noqa: E402
from gap_jap1_product import META_RING  # noqa: E402
from gap_ussr_west2_product import open_ring, overlap_px, point_in_ring, ring_area  # noqa: E402
from jap_followups1_product import (  # noqa: E402
    CHI_FUJIAN_ID,
    DEFAULT_DIR,
    KINMEN_ADM1_SHA256,
    KINMEN_ADM1_URL,
    KINMEN_ID,
    KINMEN_SOURCE_NAME,
    POLY_OVERLAP_MAX,
    SEA_ID,
    all_land_rings,
    clip_sea_off_land,
    kinmen_main_ring,
    kinmen_parts_from_geojson,
    land_rings_overlapping_sea,
    measure_report,
    notch_chi_for_kinmen,
    poly_overlap,
)

BOARD = DEFAULT_DIR
GEO_PATH = BOARD / "provinces_geometry.json"
SRC = Path.home() / "jap_followups" / "scratch" / "sources" / "geoBoundaries-TWN-ADM1_simplified.geojson"
SCRATCH = Path.home() / "jap_followups" / "scratch"


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


def _as_lists(ring):
    return [[float(p[0]), float(p[1])] for p in ring]


def build(board: Path, source: Path) -> dict:
    geo = json.loads((board / "provinces_geometry.json").read_text(encoding="utf-8"))
    base = json.loads((board / "provinces_base.json").read_text(encoding="utf-8"))
    domains = {int(p["id"]): str(p.get("domain") or "land") for p in base["provinces"]}
    by_id = {int(g["id"]): g for g in geo["provinces"]}
    rings = {pid: open_ring(g["points"]) for pid, g in by_id.items()}
    anchors = {pid: list(g.get("label_anchor") or [0, 0]) for pid, g in by_id.items()}
    metas = {pid: dict(g.get("meta") or {}) for pid, g in by_id.items()}
    changed = {}

    land_hits = land_rings_overlapping_sea(geo["provinces"], domains, SEA_ID)
    window_land = all_land_rings(geo["provinces"], domains)
    clipped = clip_sea_off_land(
        rings[SEA_ID],
        [pts for _pid, pts in land_hits],
        window_land,
    )
    rings[SEA_ID] = clipped["ring"]
    anchors[SEA_ID] = clipped["anchor"]
    metas[SEA_ID]["jap_followups1"] = "clip_land_overlap"
    metas[SEA_ID]["vertex_n"] = clipped["verts"]
    metas[SEA_ID]["area"] = clipped["area"]
    changed[SEA_ID] = "clip land overlap; join water comps %s" % clipped["components_joined"]

    parts = kinmen_parts_from_geojson(source, KINMEN_ADM1_SHA256)
    kin = kinmen_main_ring(parts)
    if abs(_area(kin)) < 4.0:
        raise RuntimeError("Kinmen main island below clickable floor")
    new_chi = notch_chi_for_kinmen(rings[CHI_FUJIAN_ID], kin)
    if not point_in_ring(float(anchors[CHI_FUJIAN_ID][0]), float(anchors[CHI_FUJIAN_ID][1]), new_chi):
        # Keep Fujian pickable: fall back to a point still inside the C.
        found = None
        for p in new_chi:
            if _winding(new_chi, p[0], p[1]) != 0:
                found = [round(p[0], 4), round(p[1], 4)]
                break
        cx = sum(p[0] for p in new_chi) / len(new_chi)
        cy = sum(p[1] for p in new_chi) / len(new_chi)
        if _winding(new_chi, cx, cy) != 0:
            found = [round(cx, 4), round(cy, 4)]
        if found is None:
            raise RuntimeError("notched CHI lost its label anchor")
        anchors[CHI_FUJIAN_ID] = found
    rings[CHI_FUJIAN_ID] = new_chi
    metas[CHI_FUJIAN_ID]["jap_followups1_yield"] = "notch_kinmen_%s" % KINMEN_ID
    metas[CHI_FUJIAN_ID]["vertex_n"] = len(new_chi)
    metas[CHI_FUJIAN_ID]["area"] = round(abs(_area(new_chi)), 2)
    changed[CHI_FUJIAN_ID] = "C-notch for Kinmen"

    kcx = sum(p[0] for p in kin) / len(kin)
    kcy = sum(p[1] for p in kin) / len(kin)
    if _winding(kin, kcx, kcy) == 0:
        raise RuntimeError("Kinmen centroid is not inside its ring")
    rings[KINMEN_ID] = kin
    anchors[KINMEN_ID] = [round(kcx, 4), round(kcy, 4)]
    metas[KINMEN_ID][META_RING] = KINMEN_SOURCE_NAME
    metas[KINMEN_ID]["jap_followups1"] = KINMEN_SOURCE_NAME
    metas[KINMEN_ID]["jap_followups1_url"] = KINMEN_ADM1_URL
    metas[KINMEN_ID]["jap_followups1_sha256"] = KINMEN_ADM1_SHA256
    metas[KINMEN_ID]["source"] = "geoboundaries"
    metas[KINMEN_ID]["adm0_a3"] = "TWN"
    metas[KINMEN_ID]["level"] = "ADM1"
    metas[KINMEN_ID]["vertex_n"] = len(kin)
    metas[KINMEN_ID]["area"] = round(abs(_area(kin)), 4)
    changed[KINMEN_ID] = "rering Kinmen County ADM1"

    if poly_overlap(rings[SEA_ID], rings[KINMEN_ID]) > POLY_OVERLAP_MAX:
        raise RuntimeError("sea clip overlapped Kinmen")
    if poly_overlap(rings[CHI_FUJIAN_ID], rings[KINMEN_ID]) > POLY_OVERLAP_MAX:
        raise RuntimeError("CHI still overlaps Kinmen")
    if overlap_px(rings[CHI_FUJIAN_ID], rings[KINMEN_ID]) > 1:
        raise RuntimeError("CHI still overlaps Kinmen pixels")
    if not point_in_ring(anchors[SEA_ID][0], anchors[SEA_ID][1], rings[SEA_ID]):
        raise RuntimeError("sea label anchor not inside clipped ring")

    return {
        "geo": geo,
        "rings": rings,
        "anchors": anchors,
        "metas": metas,
        "changed": changed,
        "clip": clipped,
        "kinmen_area": round(abs(_area(kin)), 4),
        "kinmen_verts": len(kin),
        "chi_area": round(abs(_area(new_chi)), 2),
        "chi_verts": len(new_chi),
    }


def write_board(board: Path, built: dict) -> None:
    text = (board / "provinces_geometry.json").read_text(encoding="utf-8")
    original = text
    for pid in sorted(built["changed"]):
        text = _replace_span(
            text,
            pid,
            _as_lists(built["rings"][pid]),
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", type=Path, default=BOARD)
    parser.add_argument("--source", type=Path, default=SRC)
    parser.add_argument("--measure-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--out", type=Path, default=SCRATCH / "before.json")
    args = parser.parse_args()
    if args.measure_only:
        report = measure_report(args.dir)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        sea = report["sea_950247"]
        print("wrote", args.out)
        print("950247 land overlaps", sea["land_overlap_n_over_1"], "of", len(sea["land_overlaps"]))
        for row in sea["land_overlaps"]:
            print(" ", row["id"], row["name"], "poly", row["poly_px2"], "px", row["px"])
        kin = report["kinmen_903981"]
        print("kinmen verts", kin["verts"], "area", kin["area"], "placeholder", kin["placeholder"])
        jag = report["jaggedness"]
        print("jaggedness sharp", jag["sharp_gt150"], "short", jag["short_spikes"], "max_turn", jag["max_turn_deg"])
        return 0
    if not args.source.is_file():
        raise SystemExit("Kinmen source missing: %s" % args.source)
    built = build(args.dir, args.source)
    print("changed", len(built["changed"]))
    for pid, why in sorted(built["changed"].items()):
        print(" ", pid, why, "verts", len(built["rings"][pid]), "area", round(abs(_area(built["rings"][pid])), 2))
    if args.dry_run:
        return 0
    write_board(args.dir, built)
    after = measure_report(args.dir)
    (SCRATCH / "after.json").write_text(json.dumps(after, indent=2) + "\n", encoding="utf-8")
    sea = after["sea_950247"]
    print("after 950247 land overlaps over 1:", sea["land_overlap_n_over_1"])
    for row in sea["land_overlaps"]:
        print(" ", row["id"], row["name"], "poly", row["poly_px2"], "px", row["px"])
    kin = after["kinmen_903981"]
    print("after kinmen verts", kin["verts"], "area", kin["area"], "placeholder", kin["placeholder"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
