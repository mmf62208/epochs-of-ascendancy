#!/usr/bin/env python3
"""Apply ENG-MAP-FINISH-2 leftover geometry and Gulf of America rename.

  python3 tools/map_generation/scripts/apply_eng_map_finish2.py --dry-run
  python3 tools/map_generation/scripts/apply_eng_map_finish2.py
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from canada_hole_measure import measure_canada_holes  # noqa: E402
from eng_map_finish2_product import (  # noqa: E402
    DEFAULT_DIR,
    GULF_NEW,
    GULF_OLD,
    HAMILTON_NIAGARA_ID,
    LAKE_ERIE_ID,
    LONDON_ID,
    NY_WEST_ID,
    WINDSOR_SARNIA_ID,
    absorb_hole_into,
    build_plan,
    choose_absorb_target,
    clip_leftover_erie_tails,
    gulf_name_hits,
    speck_holes,
)
from gap_eng1_product import ring_is_raw_invalid  # noqa: E402


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
    blob = json.dumps([[p[0], p[1]] for p in points], separators=(",", ":"))
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


def write_geometry(board: Path, rings, anchors, metas, changed, original_geo) -> None:
    text = (board / "provinces_geometry.json").read_text(encoding="utf-8")
    original = text
    for pid in sorted(changed):
        text = _replace_span(text, pid, rings[pid], anchors[pid], metas[pid])
    written = json.loads(text)
    if [int(g["id"]) for g in written["provinces"]] != [int(g["id"]) for g in original_geo["provinces"]]:
        raise RuntimeError("province id order changed")
    old_by = {int(g["id"]): g for g in original_geo["provinces"]}
    for g in written["provinces"]:
        pid = int(g["id"])
        if pid in changed:
            continue
        if g.get("points") != old_by[pid].get("points"):
            raise RuntimeError("untouched province %s points changed" % pid)
    if text == original:
        raise RuntimeError("geometry text did not change")
    (board / "provinces_geometry.json").write_text(text, encoding="utf-8")


def rename_gulf() -> list:
    done = []
    for path in (
        ROOT / "data" / "provinces_world_accurate" / "provinces_base.json",
        ROOT / "data" / "provinces_world_full" / "provinces_base.json",
        ROOT / "data" / "provinces_grand_theater" / "provinces_base.json",
        ROOT / "data" / "provinces_pilot_global_density" / "provinces_base.json",
        ROOT / "tools" / "map_generation" / "scripts" / "expand_grand_theater_provinces.py",
    ):
        text = path.read_text(encoding="utf-8")
        if GULF_OLD not in text:
            continue
        n = text.count(GULF_OLD)
        path.write_text(text.replace(GULF_OLD, GULF_NEW), encoding="utf-8")
        done.append({"path": str(path.relative_to(ROOT)), "count": n})
    leftover = gulf_name_hits()
    if leftover:
        raise RuntimeError("Gulf of Mexico still present: %s" % leftover)
    return done


def load_rings(board: Path):
    geo = json.loads((board / "provinces_geometry.json").read_text(encoding="utf-8"))
    rings = {}
    anchors = {}
    metas = {}
    for g in geo["provinces"]:
        pid = int(g["id"])
        pts = g.get("points") or []
        if len(pts) >= 3:
            rings[pid] = [(float(p[0]), float(p[1])) for p in pts]
        anchors[pid] = [float(g["label_anchor"][0]), float(g["label_anchor"][1])]
        metas[pid] = dict(g.get("meta") or {})
    return geo, rings, anchors, metas


def absorb_specks(board: Path, rings, anchors, metas, changed, skip_targets=()) -> list:
    report = measure_canada_holes(board, use_natural_earth=True)
    absorbed = []
    skip = set(skip_targets)
    for hole in speck_holes(report):
        target = choose_absorb_target(hole)
        surround = {int(s.get("id") or 0) for s in hole.get("surrounding") or []}
        if target is None or target in skip:
            # West Erie corridor: never Hamilton, never back onto London.
            if WINDSOR_SARNIA_ID in surround and LAKE_ERIE_ID in surround:
                target = WINDSOR_SARNIA_ID
            elif target in skip:
                continue
            else:
                raise RuntimeError("no absorb target for speck %.1f at %s" % (hole["area_px2"], hole["centroid"]))
        if target in skip:
            continue
        if target not in rings:
            raise RuntimeError("speck target %s missing" % target)
        try:
            absorb_hole_into(rings, anchors, target, hole["ring"])
        except RuntimeError:
            if target == NY_WEST_ID:
                continue
            raise
        metas[target]["eng_map_finish2_speck"] = "face_%.1f" % hole["area_px2"]
        changed[target] = (changed.get(target) or "") + " absorb speck %.1f" % hole["area_px2"]
        absorbed.append({"area_px2": hole["area_px2"], "target": target, "kind": hole.get("kind"), "lon": hole["lon"], "lat": hole["lat"]})
    return absorbed


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply ENG-MAP-FINISH-2 leftover faces and Gulf rename")
    parser.add_argument("--dir", type=Path, default=DEFAULT_DIR)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--names-only", action="store_true")
    parser.add_argument("--specks-only", action="store_true")
    parser.add_argument("--erie-tails-only", action="store_true")
    args = parser.parse_args()
    if args.names_only:
        if args.dry_run:
            print("gulf hits", gulf_name_hits())
            return 0
        print("renamed", rename_gulf())
        return 0
    if args.specks_only:
        geo, rings, anchors, metas = load_rings(args.dir)
        changed = {}
        specks = absorb_specks(args.dir, rings, anchors, metas, changed)
        print("specks", specks)
        if args.dry_run or not specks:
            return 0
        write_geometry(args.dir, rings, anchors, metas, changed, geo)
        return 0
    if args.erie_tails_only:
        geo, rings, anchors, metas = load_rings(args.dir)
        changed = {}
        clipped = clip_leftover_erie_tails(rings, anchors, metas, changed)
        print("erie_tails", clipped)
        if args.dry_run:
            return 0
        if clipped:
            write_geometry(args.dir, rings, anchors, metas, changed, geo)
        specks = absorb_specks(
            args.dir,
            rings,
            anchors,
            metas,
            changed,
            skip_targets=(HAMILTON_NIAGARA_ID, LONDON_ID),
        )
        print("erie_tail_specks", specks)
        if specks:
            geo2 = json.loads((args.dir / "provinces_geometry.json").read_text(encoding="utf-8"))
            write_geometry(args.dir, rings, anchors, metas, {row["target"] for row in specks}, geo2)
        return 0
    plan = build_plan(args.dir)
    print("phase1 changed", len(plan["changed"]))
    for pid, why in sorted(plan["changed"].items()):
        print(" ", pid, why, "verts", len(plan["rings"][pid]), "invalid", ring_is_raw_invalid(plan["rings"][pid]))
    print("dc_absorbed", plan["dc_absorbed"])
    print("clipped", plan["clipped"])
    if args.dry_run:
        print("gulf hits", gulf_name_hits())
        return 0
    geo_before = json.loads((args.dir / "provinces_geometry.json").read_text(encoding="utf-8"))
    write_geometry(args.dir, plan["rings"], plan["anchors"], plan["metas"], plan["changed"], geo_before)
    all_specks = []
    for _round in range(3):
        specks = absorb_specks(args.dir, plan["rings"], plan["anchors"], plan["metas"], plan["changed"])
        print("specks round", _round + 1, specks)
        if not specks:
            break
        geo_mid = json.loads((args.dir / "provinces_geometry.json").read_text(encoding="utf-8"))
        speck_changed = {row["target"] for row in specks}
        write_geometry(args.dir, plan["rings"], plan["anchors"], plan["metas"], speck_changed, geo_mid)
        all_specks.extend(specks)
    print("specks total", len(all_specks))
    erie_clipped = clip_leftover_erie_tails(plan["rings"], plan["anchors"], plan["metas"], plan["changed"])
    print("erie_tails", erie_clipped)
    if erie_clipped:
        geo_tail = json.loads((args.dir / "provinces_geometry.json").read_text(encoding="utf-8"))
        write_geometry(
            args.dir,
            plan["rings"],
            plan["anchors"],
            plan["metas"],
            {row["id"] for row in erie_clipped},
            geo_tail,
        )
        tail_specks = absorb_specks(
            args.dir,
            plan["rings"],
            plan["anchors"],
            plan["metas"],
            plan["changed"],
            skip_targets=(HAMILTON_NIAGARA_ID, LONDON_ID),
        )
        print("erie_tail_specks", tail_specks)
        if tail_specks:
            geo_speck = json.loads((args.dir / "provinces_geometry.json").read_text(encoding="utf-8"))
            write_geometry(
                args.dir,
                plan["rings"],
                plan["anchors"],
                plan["metas"],
                {row["target"] for row in tail_specks},
                geo_speck,
            )
    print("renamed", rename_gulf())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
