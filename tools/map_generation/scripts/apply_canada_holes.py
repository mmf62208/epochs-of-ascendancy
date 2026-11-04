#!/usr/bin/env python3
"""Fill enclosed Canadian holes over 100 px².

Land gaps are absorbed into the neighbouring land ring (no new province id).
A real lake or sea that already has a water province is absorbed into that
ring. The 141°W Alaska wedge goes to Alaska West. South of the 49th parallel
goes to the US neighbour. Quebec–Vermont stays with Canada on a near-tie.

Geometry points are rewritten in place. Adjacency gains the new shared edges,
both ways. Province count stays 3596.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from canada_hole_measure import (  # noqa: E402
    DEFAULT_DIR,
    _winding,
    choose_absorb_target,
    measure_canada_holes,
    merge_positive_rings,
)
from gap_china2_outline import _area  # noqa: E402
from gap_eng1_product import ring_is_raw_invalid  # noqa: E402

MIN_AREA = 100.0
# Slivers left by a self-touching source ring. They are not a second province.
SLIVER_AREA = 5.0


def _replace_points(text: str, pid: int, points) -> str:
    # raw_decode's end index is absolute. Splicing at start+end deletes the
    # rest of the file (the 903049 write failed that way before anything landed).
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
    return text[:start] + blob + text[end:]


def _add_link(adj: dict, a: int, b: int) -> bool:
    if a == b:
        return False
    key = str(a)
    cur = [int(x) for x in (adj.get(key) or [])]
    if b in cur:
        return False
    cur.append(b)
    adj[key] = cur
    return True


def absorb(board: Path = DEFAULT_DIR, dry_run: bool = False) -> list:
    report = measure_canada_holes(board, use_natural_earth=True)
    holes = [h for h in report["holes"] if h["area_px2"] > MIN_AREA]
    geo_text = (board / "provinces_geometry.json").read_text(encoding="utf-8")
    geo = json.loads(geo_text)
    by_id = {int(g["id"]): g for g in geo["provinces"]}
    rings = {
        pid: [(float(p[0]), float(p[1])) for p in g["points"]]
        for pid, g in by_id.items()
        if len(g.get("points") or []) >= 3
    }
    done = []
    links = []
    for hole in holes:
        pid = choose_absorb_target(hole)
        if pid is None:
            raise RuntimeError("no absorb target for %.1f px² at %s" % (hole["area_px2"], hole["centroid"]))
        src = rings[pid]
        was_invalid = ring_is_raw_invalid(src)
        hole_ring = [(float(p[0]), float(p[1])) for p in hole["ring"]]
        loops = merge_positive_rings(src, hole_ring)
        if not loops:
            raise RuntimeError("merge produced no ring for %s + hole %.1f" % (pid, hole["area_px2"]))
        kept = [loop for i, loop in enumerate(loops) if i == 0 or abs(_area(loop)) >= SLIVER_AREA]
        if len(kept) != 1:
            raise RuntimeError(
                "merge %s + %.1f left %d loops over %.1f px²"
                % (pid, hole["area_px2"], len(kept), SLIVER_AREA)
            )
        merged = kept[0]
        cx, cy = hole["centroid_exact"]
        ax, ay = by_id[pid]["label_anchor"]
        if _winding(merged, cx, cy) == 0:
            raise RuntimeError("hole centroid left outside %s" % pid)
        if _winding(merged, float(ax), float(ay)) == 0:
            raise RuntimeError("label anchor left outside %s" % pid)
        now_invalid = ring_is_raw_invalid(merged)
        if now_invalid and not was_invalid:
            raise RuntimeError("absorb made %s self-crossing" % pid)
        rings[pid] = merged
        for row in hole["surrounding"]:
            if _add_link_pair(links, pid, int(row["id"])):
                pass
        done.append({
            "area_px2": hole["area_px2"],
            "centroid": hole["centroid"],
            "lon": hole["lon"],
            "lat": hole["lat"],
            "kind": hole.get("kind"),
            "water_name": hole.get("water_name") or "",
            "evidence": hole.get("evidence") or "",
            "target": pid,
            "target_name": (by_id[pid].get("name") or ""),
            "was_invalid": was_invalid,
            "dropped_slivers": [round(abs(_area(loop)), 2) for loop in loops[1:]],
            "surrounding": [s["id"] for s in hole["surrounding"]],
        })
        print(
            "absorb %.1f px² (%s) into %s %s"
            % (hole["area_px2"], hole.get("kind"), pid, by_id[pid].get("name") or "")
        )
    if dry_run:
        return done
    changed = {row["target"] for row in done}
    for row in done:
        pid = row["target"]
        points = [[p[0], p[1]] for p in rings[pid]]
        geo_text = _replace_points(geo_text, pid, points)
    written = json.loads(geo_text)
    if len(written["provinces"]) != len(geo["provinces"]):
        raise RuntimeError(
            "geometry province count %s != %s" % (len(written["provinces"]), len(geo["provinces"]))
        )
    old_by = {int(g["id"]): g for g in geo["provinces"]}
    for g in written["provinces"]:
        pid = int(g["id"])
        if pid not in changed and g.get("points") != old_by[pid].get("points"):
            raise RuntimeError("untouched province %s points changed" % pid)
    (board / "provinces_geometry.json").write_text(geo_text, encoding="utf-8")
    adj_path = board / "province_adjacency.json"
    adj_doc = json.loads(adj_path.read_text(encoding="utf-8"))
    adj = adj_doc["adjacency"]
    added = 0
    for a, b in links:
        if _add_link(adj, a, b):
            added += 1
        if _add_link(adj, b, a):
            added += 1
    adj_path.write_text(json.dumps(adj_doc, indent=2) + "\n", encoding="utf-8")
    print("wrote geometry for %d provinces, adjacency links added %d" % (len(done), added))
    return done


def _add_link_pair(links: list, a: int, b: int) -> bool:
    if a == b:
        return False
    pair = (a, b) if a < b else (b, a)
    if pair in links:
        return False
    links.append(pair)
    return True


def main() -> int:
    dry = "--dry-run" in sys.argv
    absorb(DEFAULT_DIR, dry_run=dry)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
