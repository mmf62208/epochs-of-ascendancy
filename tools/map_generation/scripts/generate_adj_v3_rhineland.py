#!/usr/bin/env python3
"""ADJ-V3: GIS-true adjacency for the Rhineland/Benelux pilot.

Two pilot provinces are neighbours when their NUTS RG 20M rings share an
undirected segment after lon/lat are rounded to 6 decimal places (1e-6°).
NUTS RG is topologically clean, so a real border is an identical vertex pair.
A shared vertex with no shared segment also counts. This pilot has one such
point touch: BE336–NL423 (710082–711034).

Edges with both ends in the 180 pilot provinces are replaced by that GIS set.
Every other v2 edge stays, except the named Hawaii and Guam far-ocean links,
which are removed in both directions. If that removal leaves a sea zone with
no neighbour, it is linked to the nearest remaining province by canvas bbox
gap (lowest pid breaks a tie). The removed partner is not eligible, so the
bogus link is not put back.

The hex preview is not a source. load_forbidden_hex_preview() exists only so
mutant (c) can build from it and fail.

  python3 tools/map_generation/scripts/generate_adj_v3_rhineland.py
  python3 tools/map_generation/scripts/generate_adj_v3_rhineland.py --check
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
CONFIG_PATH = ROOT / "tools" / "map_generation" / "config" / "hex_pilot_rhineland.json"

Pair = Tuple[int, int]
METHOD = (
    "gis_shared_segment_rhineland_pilot + v2_elsewhere; "
    "shared_edge retained outside the pilot"
)

# Named far-ocean links. The brief's "15" undercounts this list: 16 distinct
# pairs are present in v2 (Hawaii 9, Guam 7). All 16 come out.
_BOGUS_FAR_LINKS: Tuple[Pair, ...] = (
    (800094, 800023),
    (800094, 800024),
    (800094, 800519),
    (800094, 802049),
    (800094, 950190),
    (800094, 950197),
    (800094, 950205),
    (800094, 950206),
    (800094, 950213),
    (902485, 904667),
    (902485, 904668),
    (902485, 904692),
    (902485, 904712),
    (902485, 904713),
    (902485, 950244),
    (902485, 950253),
)


def load_config(path: Optional[Path] = None) -> Dict[str, Any]:
    return json.loads((path or CONFIG_PATH).read_text(encoding="utf-8"))


def _repo(cfg: Mapping[str, Any], key: str) -> Path:
    rel = str((cfg.get("paths") or {})[key])
    return ROOT / rel


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def norm_pair(a: int, b: int) -> Pair:
    return (a, b) if a < b else (b, a)


def norm_pairs(pairs: Iterable[Pair]) -> Set[Pair]:
    out: Set[Pair] = set()
    for a, b in pairs:
        if int(a) == int(b):
            continue
        out.add(norm_pair(int(a), int(b)))
    return out


def bogus_far_links() -> Tuple[Pair, ...]:
    # ADJ_V3_BOGUS
    return _BOGUS_FAR_LINKS


def emit_pid(pid: int) -> int:
    return int(pid)  # ADJ_V3_PID identity


def pilot_provinces(base: Mapping[str, Any], cfg: Mapping[str, Any]) -> List[Dict[str, Any]]:
    prefixes = tuple(cfg["nuts_prefixes"])
    rows = [
        p
        for p in base.get("provinces") or []
        if isinstance(p, dict)
        and any(str(p.get("nuts_id") or "").startswith(px) for px in prefixes)
    ]
    rows.sort(key=lambda p: int(p["id"]))
    expected = int(cfg["expected_pid_count"])
    if len(rows) != expected:
        raise SystemExit(
            "ADJ-V3 FAIL: pilot set is %d pids, expected %d" % (len(rows), expected)
        )
    return rows


def _rings_lonlat(geom: Mapping[str, Any]) -> List[List[Tuple[float, float]]]:
    gtype = str(geom.get("type") or "")
    coords = geom.get("coordinates") or []
    if gtype == "Polygon":
        polys = [coords]
    elif gtype == "MultiPolygon":
        polys = list(coords)
    else:
        return []
    rings: List[List[Tuple[float, float]]] = []
    for poly in polys:
        if not poly:
            continue
        for ring in poly:
            pts = [(float(p[0]), float(p[1])) for p in ring]
            if len(pts) >= 2 and pts[0] == pts[-1]:
                pts = pts[:-1]
            if len(pts) >= 2:
                rings.append(pts)
    return rings


def load_pilot_rings(
    cfg: Mapping[str, Any], nuts_to_pid: Mapping[str, int]
) -> Dict[int, List[List[Tuple[float, float]]]]:
    gis = _load(_repo(cfg, "nuts_gis"))
    by_pid: Dict[int, List[List[Tuple[float, float]]]] = {}
    for feat in gis.get("features") or []:
        nid = str((feat.get("properties") or {}).get("NUTS_ID") or "")
        if nid not in nuts_to_pid:
            continue
        pid = int(nuts_to_pid[nid])
        rings = _rings_lonlat(feat.get("geometry") or {})
        if rings:
            by_pid.setdefault(pid, []).extend(rings)
    missing = sorted(set(nuts_to_pid.values()) - set(by_pid))
    if missing:
        raise SystemExit("ADJ-V3 FAIL: NUTS rings missing for %s" % missing[:8])
    return by_pid


def _segment_and_touch(
    rings_by_pid: Mapping[int, Sequence[Sequence[Tuple[float, float]]]],
    quant_decimals: int,
) -> Tuple[Set[Pair], Set[Pair]]:
    seg_owners: Dict[Pair, Set[int]] = {}
    vert_owners: Dict[Tuple[float, float], Set[int]] = {}
    for pid, rings in rings_by_pid.items():
        for ring in rings:
            q = [(round(p[0], quant_decimals), round(p[1], quant_decimals)) for p in ring]
            for v in q:
                vert_owners.setdefault(v, set()).add(int(pid))
            n = len(q)
            for i in range(n):
                a = q[i]
                b = q[(i + 1) % n]
                if a == b:
                    continue
                seg = (a, b) if a <= b else (b, a)
                seg_owners.setdefault(seg, set()).add(int(pid))
    segments: Set[Pair] = set()
    for owners in seg_owners.values():
        ordered = sorted(owners)
        for i, a in enumerate(ordered):
            for b in ordered[i + 1 :]:
                segments.add((a, b))
    touches: Set[Pair] = set()
    for owners in vert_owners.values():
        ordered = sorted(owners)
        for i, a in enumerate(ordered):
            for b in ordered[i + 1 :]:
                pair = (a, b)
                if pair not in segments:
                    touches.add(pair)
    return segments, touches


def gis_border_pairs(
    rings_by_pid: Mapping[int, Sequence[Sequence[Tuple[float, float]]]],
    quant_decimals: int = 6,
) -> Set[Pair]:
    segment_pairs, point_touch_pairs = _segment_and_touch(rings_by_pid, quant_decimals)
    # ADJ_V3_GIS_EDGES
    return segment_pairs | point_touch_pairs


def load_forbidden_hex_preview(cfg: Optional[Mapping[str, Any]] = None) -> Set[Pair]:
    """Hex-lattice edges. Mutant (c) returns these instead of NUTS borders."""
    cfg = cfg or load_config()
    path = ROOT / str(cfg["forbidden_hex_preview"])
    doc = _load(path)
    return norm_pairs(tuple(p) for p in doc.get("pairs") or [])


def adjust_gis_edges(edges: Set[Pair]) -> Set[Pair]:
    extra_add: Set[Pair] = set()  # ADJ_V3_EXTRA_ADD
    extra_drop: Set[Pair] = set()  # ADJ_V3_EXTRA_DROP
    edges = set(edges)
    edges |= norm_pairs(extra_add)
    edges -= norm_pairs(extra_drop)
    return edges


def point_touch_pairs(
    rings_by_pid: Mapping[int, Sequence[Sequence[Tuple[float, float]]]],
    quant_decimals: int = 6,
) -> Set[Pair]:
    _segments, touches = _segment_and_touch(rings_by_pid, quant_decimals)
    return touches


def segment_pairs_only(
    rings_by_pid: Mapping[int, Sequence[Sequence[Tuple[float, float]]]],
    quant_decimals: int = 6,
) -> Set[Pair]:
    segments, _touches = _segment_and_touch(rings_by_pid, quant_decimals)
    return segments


def undirected_edges(adj: Mapping[str, Sequence[int]]) -> Set[Pair]:
    edges: Set[Pair] = set()
    for a_s, nbs in adj.items():
        a = int(a_s)
        for b in nbs:
            bi = int(b)
            if bi != a:
                edges.add(norm_pair(a, bi))
    return edges


def internal_edges(adj: Mapping[str, Sequence[int]], pilot: Set[int]) -> Set[Pair]:
    return {p for p in undirected_edges(adj) if p[0] in pilot and p[1] in pilot}


def _desired_lists(
    adj: Mapping[str, Sequence[int]],
    pilot: Set[int],
    gis_edges: Set[Pair],
    bogus: Set[Pair],
) -> Dict[str, List[int]]:
    gis_by: Dict[int, List[int]] = {}
    for a, b in gis_edges:
        gis_by.setdefault(a, []).append(b)
        gis_by.setdefault(b, []).append(a)
    desired: Dict[str, List[int]] = {}
    for a_s, nbs in adj.items():
        a = int(a_s)
        if a in pilot:
            kept = [int(b) for b in nbs if int(b) not in pilot]
            merged = kept + gis_by.get(a, [])
        else:
            merged = []
            for b in nbs:
                bi = int(b)
                if norm_pair(a, bi) in bogus:
                    continue
                merged.append(bi)
        desired[str(a)] = sorted(set(merged))
    return desired


def write_forward(adj: Dict[str, List[int]], desired: Mapping[str, Sequence[int]]) -> None:
    """Write only the higher-id end of each desired edge.

    The reverse end is stale until symmetrize_adjacency runs. Dropping that
    pass leaves every new or removed edge one-way.
    """
    for a_s, nbs in desired.items():
        a = int(a_s)
        adj[a_s] = sorted(int(b) for b in nbs if int(b) > a)


def _mirror_forward_links(adj: Dict[str, List[int]]) -> None:
    adds: List[Tuple[str, int]] = []
    for a_s, nbs in adj.items():
        a = int(a_s)
        for b in list(nbs):
            b_s = str(int(b))
            if a not in [int(x) for x in adj.get(b_s, [])]:
                adds.append((b_s, a))
    for b_s, a in adds:
        adj.setdefault(b_s, []).append(a)
    for a_s in adj:
        adj[a_s] = sorted(set(int(x) for x in adj[a_s]))


def symmetrize_adjacency(adj: Dict[str, List[int]]) -> None:
    # ADJ_V3_SYMMETRY
    _mirror_forward_links(adj)


def _bboxes(geom: Mapping[str, Any]) -> Dict[int, Tuple[float, float, float, float]]:
    out: Dict[int, Tuple[float, float, float, float]] = {}
    for row in geom.get("provinces") or []:
        pts = row.get("points") or []
        if not pts:
            continue
        xs = [float(p[0]) for p in pts]
        ys = [float(p[1]) for p in pts]
        out[int(row["id"])] = (min(xs), min(ys), max(xs), max(ys))
    return out


def _gap2(
    a: Tuple[float, float, float, float], b: Tuple[float, float, float, float]
) -> float:
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    if ax1 >= bx0 and bx1 >= ax0:
        dx = 0.0
    else:
        dx = min(abs(ax1 - bx0), abs(bx1 - ax0))
    if ay1 >= by0 and by1 >= ay0:
        dy = 0.0
    else:
        dy = min(abs(ay1 - by0), abs(by1 - ay0))
    return dx * dx + dy * dy


# GAP-IBS placed Marianas Waters and Saipan closer, by canvas bbox, to the
# Coral Sea orphan 950244 than its pinned partner 950245. That orphan is not
# degree-0 on the shipped graph. Skipping these ids keeps a v2 rebuild on
# the same repair instead of retargeting it.
_REPAIR_SKIP = {905852, 905853, 905854, 950341, 950342}


def choose_repair_target(
    pid: int,
    adj: Mapping[str, Sequence[int]],
    boxes: Mapping[int, Tuple[float, float, float, float]],
    banned: Set[int],
) -> int:
    """Nearest other province by canvas bbox gap. Lowest pid wins a tie."""
    bb = boxes.get(pid)
    best: Optional[Tuple[Tuple[float, int], int]] = None
    for other_s in adj:
        other = int(other_s)
        if other == pid or other in banned or other in _REPAIR_SKIP:
            continue
        ob = boxes.get(other)
        gap = _gap2(bb, ob) if bb is not None and ob is not None else 1e99
        key = (gap, other)
        if best is None or key < best[0]:
            best = (key, other)
    if best is None:
        raise SystemExit("ADJ-V3 FAIL: no repair target for %d" % pid)
    return int(best[1])


def _link_both(adj: Dict[str, List[int]], a: int, b: int) -> None:
    for src, dst in ((a, b), (b, a)):
        nbs = [int(x) for x in adj.get(str(src), [])]
        if dst not in nbs:
            nbs.append(dst)
        adj[str(src)] = sorted(set(nbs))


def water_ids(base: Mapping[str, Any]) -> Set[int]:
    out: Set[int] = set()
    for p in base.get("provinces") or []:
        domain = str(p.get("domain") or "")
        if domain != "land":
            out.add(int(p["id"]))
    return out


def repair_water_orphans(
    adj: Dict[str, List[int]],
    base: Mapping[str, Any],
    geom: Mapping[str, Any],
    bogus: Set[Pair],
) -> List[Pair]:
    """Give a degree-0 water province a nearest neighbour that is not a bogus partner."""
    boxes = _bboxes(geom)
    waters = water_ids(base)
    orphans = sorted(pid for pid in waters if not adj.get(str(pid)))
    linked: List[Pair] = []
    # Targets are chosen against the pre-repair graph so two orphans cannot
    # pick each other solely because an earlier repair changed the gaps.
    # The bogus partner is banned, or the nearest hit would put that link back.
    plan: List[Pair] = []
    for pid in orphans:
        banned: Set[int] = set()
        for a, b in bogus:
            if pid == a:
                banned.add(b)
            elif pid == b:
                banned.add(a)
        plan.append((pid, choose_repair_target(pid, adj, boxes, banned)))
    for pid, target in plan:
        _link_both(adj, pid, target)
        linked.append(norm_pair(pid, target))
    return linked


def maybe_orphan_for_mutant(adj: Dict[str, List[int]]) -> None:
    _orphan_pid = 0  # ADJ_V3_ORPHAN
    if _orphan_pid:
        adj[str(_orphan_pid)] = []


def remap_ids(adj: Dict[str, List[int]]) -> Dict[str, List[int]]:
    identity = all(emit_pid(int(k)) == int(k) for k in adj)
    if identity and all(emit_pid(int(b)) == int(b) for nbs in adj.values() for b in nbs):
        return adj
    out: Dict[str, List[int]] = {}
    order: List[str] = []
    for k, nbs in adj.items():
        nk = str(emit_pid(int(k)))
        if nk not in out:
            order.append(nk)
            out[nk] = []
        out[nk].extend(emit_pid(int(b)) for b in nbs)
    return {k: sorted(set(out[k])) for k in order}


def _degree_stats(
    adj: Mapping[str, Sequence[int]], land_ids: Set[int]
) -> Dict[str, Any]:
    degs = [len(v) for v in adj.values()]
    land_degs = [len(adj[str(pid)]) for pid in land_ids if str(pid) in adj]
    land_zeros = sum(1 for d in land_degs if d == 0)
    return {
        "degree_min": min(degs) if degs else 0,
        "degree_max": max(degs) if degs else 0,
        "degree_mean": (sum(degs) / len(degs)) if degs else 0.0,
        "land_shared_degree_mean": (sum(land_degs) / len(land_degs)) if land_degs else 0.0,
        "orphan_land_after": land_zeros,
        "zero_degree": sum(1 for d in degs if d == 0),
    }


def build_document(
    doc: Mapping[str, Any],
    base: Mapping[str, Any],
    rings_by_pid: Mapping[int, Sequence[Sequence[Tuple[float, float]]]],
    geom: Mapping[str, Any],
    cfg: Mapping[str, Any],
) -> Dict[str, Any]:
    pilot_rows = pilot_provinces(base, cfg)
    pilot = {int(p["id"]) for p in pilot_rows}
    quant = int(cfg.get("quant_decimals") or 6)
    gis = adjust_gis_edges(gis_border_pairs(rings_by_pid, quant))
    touches = point_touch_pairs(rings_by_pid, quant)
    segments = segment_pairs_only(rings_by_pid, quant)
    bogus = norm_pairs(bogus_far_links())
    out = copy.deepcopy(dict(doc))
    adj = {str(k): [int(x) for x in v] for k, v in (out.get("adjacency") or {}).items()}
    desired = _desired_lists(adj, pilot, gis, bogus)
    write_forward(adj, desired)
    symmetrize_adjacency(adj)
    repair_water_orphans(adj, base, geom, bogus)
    maybe_orphan_for_mutant(adj)
    adj = remap_ids(adj)
    out["adjacency"] = adj
    out["version"] = "3"
    out["method"] = METHOD
    stats = dict(out.get("stats") or {})
    land_ids = {int(p["id"]) for p in base.get("provinces") or [] if str(p.get("domain") or "") == "land"}
    degrees = _degree_stats(adj, land_ids)
    stats["degree_min"] = degrees["degree_min"]
    stats["degree_max"] = degrees["degree_max"]
    stats["degree_mean"] = degrees["degree_mean"]
    stats["land_shared_degree_mean"] = degrees["land_shared_degree_mean"]
    stats["orphan_land_after"] = degrees["orphan_land_after"]
    stats["adj_v3"] = {
        "pilot_pids": len(pilot),
        "pilot_prefixes": list(cfg["nuts_prefixes"]),
        "quant_degrees": 10 ** (-quant),
        "point_touch_rule": str(cfg.get("point_touch_rule") or ""),
        "point_touch_pairs": ["%d-%d" % p for p in sorted(touches)],
        "gis_segment_pairs": len(segments),
        "pilot_internal_edges": len(internal_edges(adj, pilot)),
        "bogus_far_links": ["%d-%d" % p for p in sorted(bogus)],
        "brief_stated_total": 15,
        "zero_degree": degrees["zero_degree"],
        "hawaii_800094": list(adj.get("800094") or []),
        "guam_902485": list(adj.get("902485") or []),
        "solingen_710409": list(adj.get("710409") or []),
        "herne_710446": list(adj.get("710446") or []),
    }
    out["stats"] = stats
    return out


def render(doc: Mapping[str, Any]) -> str:
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def build_text(cfg: Optional[Mapping[str, Any]] = None) -> str:
    cfg = cfg or load_config()
    base = _load(_repo(cfg, "base"))
    rows = pilot_provinces(base, cfg)
    nuts_to_pid = {str(p["nuts_id"]): int(p["id"]) for p in rows}
    rings = load_pilot_rings(cfg, nuts_to_pid)
    geom = _load(_repo(cfg, "geometry"))
    doc = _load(_repo(cfg, "adjacency"))
    return render(build_document(doc, base, rings, geom, cfg))


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Write ADJ-V3 Rhineland adjacency")
    parser.add_argument("--check", action="store_true", help="exit 1 if the file would change")
    parser.add_argument("--output", default="", help="write here instead of the board file")
    args = parser.parse_args(list(argv) if argv is not None else None)
    cfg = load_config()
    text = build_text(cfg)
    dest = Path(args.output) if args.output else _repo(cfg, "adjacency")
    if "provinces_world_full" in str(dest):
        raise SystemExit("ADJ-V3 FAIL: refused to write world_full")
    if args.check and not args.output:
        current = dest.read_text(encoding="utf-8")
        if current != text:
            print("ADJ-V3 drift: generator output != %s" % dest)
            return 1
        print("ADJ-V3 check ok")
        return 0
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text, encoding="utf-8")
    doc = json.loads(text)
    info = doc["stats"]["adj_v3"]
    print(
        "ADJ-V3 wrote %s pilot_internal=%s segments=%s touch=%s zero=%s"
        % (
            dest,
            info["pilot_internal_edges"],
            info["gis_segment_pairs"],
            ",".join(info["point_touch_pairs"]),
            info["zero_degree"],
        )
    )
    print("hawaii", info["hawaii_800094"])
    print("guam", info["guam_902485"])
    print("solingen", info["solingen_710409"], "herne", info["herne_710446"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
