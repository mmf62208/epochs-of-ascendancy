"""FAC-1a FIX #2: world-space interior airfield anchors (polylabel).

Pole-of-inaccessibility for a province ring, then a clearance push so the
point stays inside the polygon and away from:
  - the province centroid / label (unit-counter footprint)
  - a reserved Rhine / gold-spine corridor (Bonn–Köln–Leverkusen)

Precomputed once (never per frame). Never renumbers IDs.
"""
from __future__ import annotations

import heapq
import json
import math
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
GEO_PATH = ROOT / "data" / "provinces_world_accurate" / "provinces_geometry.json"
ANCHOR_ACCURATE = ROOT / "data" / "provinces_world_accurate" / "facility_icon_anchors.json"
ANCHOR_PILOT = ROOT / "data" / "provinces_pilot_europe_nuts3" / "facility_icon_anchors.json"
SITES_ACCURATE = ROOT / "data" / "provinces_world_accurate" / "project_sites.json"
SITES_PILOT = ROOT / "data" / "provinces_pilot_europe_nuts3" / "project_sites.json"
LAYER_GD = ROOT / "scripts" / "map" / "FacilityIconLayer.gd"
CITY_LAYER = ROOT / "data" / "provinces_world_accurate" / "province_city_layer.json"

# FIX #2b Rhineland reseed (never renumber). NRW west of ~7.6°E / south of
# the Ruhr + northern Rheinland-Pfalz. Off Köln / Bonn / Leverkusen and off
# LUX-border (Aachen / Trier-Saarburg). Euskirchen is Bonn-adjacent so a
# Köln counter exercises clearance. Forced interiors cluster at mid 0.99
# and split at ≥1.9.
VIERSEN = 710414
OBERBERGISCHER = 710423
EUSKIRCHEN = 710421
MAYEN_KOBLENZ = 710459
# Aliases kept so older test imports resolve to the live FIX #2b seeds.
AACHEN = VIERSEN
TRIER_SAARBURG = OBERBERGISCHER
BORKEN = EUSKIRCHEN
SIEGEN = MAYEN_KOBLENZ
EMSLAND = VIERSEN
ORTENAU = OBERBERGISCHER
GOTTINGEN = EUSKIRCHEN
ANSBACH = MAYEN_KOBLENZ
SEED_TIERS: Dict[int, int] = {
    VIERSEN: 1,
    OBERBERGISCHER: 2,
    EUSKIRCHEN: 3,
    MAYEN_KOBLENZ: 4,
}
SEED_NAMES: Dict[int, str] = {
    VIERSEN: "Viersen",
    OBERBERGISCHER: "Oberbergischer Kreis",
    EUSKIRCHEN: "Euskirchen",
    MAYEN_KOBLENZ: "Mayen-Koblenz",
}
# World-space interiors (raw). Pair Euskirchen–Mayen ~19.2 and
# Mayen–Oberbergisch ~19.8 cluster at 0.99 and split at 1.9. All four
# clear an 80×56 Köln counter at zoom 2.27.
SEED_FORCE_RAW: Dict[int, Tuple[float, float]] = {
    VIERSEN: (4237.92, 934.46),
    EUSKIRCHEN: (4243.90, 957.97),
    OBERBERGISCHER: (4270.07, 943.80),
    MAYEN_KOBLENZ: (4262.61, 962.15),
}
CLUSTER_PAIR: Tuple[int, int] = (EUSKIRCHEN, MAYEN_KOBLENZ)
KOELN_PID = 710417
BONN_PID = 710416

# Gold-spine / Rhine corridor (centroids of the IX-1 / RX-1 walk). Not sampled as
# S1 gold-cover — that walk never included Neuss, which is why FIX #1 false-passed.
SPINE_PIDS: Tuple[int, ...] = (710416, 710417, 710418)
RHINE_WALK_PIDS: Tuple[int, ...] = (710416, 710417, 710401, 710402)

THEATER_SCALE = 1.728
COUNTER_CLEAR_FRAC = 0.38
EDGE_MARGIN_FRAC = 0.12
MIN_PAIR_WORLD = 16.0
CLUSTER_PAIR_MIN = 17.0
CLUSTER_PAIR_MAX = 20.5


Pt = Tuple[float, float]


def _ring(points: Sequence[Sequence[float]]) -> List[Pt]:
    out: List[Pt] = []
    for p in points:
        if len(p) < 2:
            continue
        out.append((float(p[0]), float(p[1])))
    if len(out) >= 2 and (abs(out[0][0] - out[-1][0]) < 1e-9 and abs(out[0][1] - out[-1][1]) < 1e-9):
        out = out[:-1]
    return out


def _centroid(ring: Sequence[Pt]) -> Pt:
    if not ring:
        return (0.0, 0.0)
    return (sum(p[0] for p in ring) / len(ring), sum(p[1] for p in ring) / len(ring))


def point_in_ring(x: float, y: float, ring: Sequence[Pt]) -> bool:
    inside = False
    n = len(ring)
    if n < 3:
        return False
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-18) + xi):
            inside = not inside
        j = i
    return inside


def dist_point_seg(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx, dy = bx - ax, by - ay
    den = dx * dx + dy * dy
    if den <= 1e-18:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / den))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def signed_edge_distance(x: float, y: float, ring: Sequence[Pt]) -> float:
    if len(ring) < 2:
        return -1e9
    best = 1e18
    n = len(ring)
    for i in range(n):
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % n]
        best = min(best, dist_point_seg(x, y, ax, ay, bx, by))
    if not point_in_ring(x, y, ring):
        return -best
    return best


def dist_to_polyline(x: float, y: float, line: Sequence[Pt]) -> float:
    if len(line) < 2:
        return 1e18
    best = 1e18
    for i in range(len(line) - 1):
        best = min(best, dist_point_seg(x, y, line[i][0], line[i][1], line[i + 1][0], line[i + 1][1]))
    return best


def polylabel(ring: Sequence[Pt], precision: float = 0.2) -> Tuple[float, float, float]:
    """Mapbox-style pole of inaccessibility. Returns (x, y, radius)."""
    if len(ring) < 3:
        c = _centroid(ring)
        return (c[0], c[1], 0.0)
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    width, height = maxx - minx, maxy - miny
    cell = min(width, height)
    if cell <= 1e-9:
        c = _centroid(ring)
        return (c[0], c[1], 0.0)
    h = cell / 2.0
    best = _centroid(ring)
    best_d = signed_edge_distance(best[0], best[1], ring)
    heap: List[Tuple[float, float, float, float, float]] = []

    def push(x: float, y: float, half: float) -> None:
        d = signed_edge_distance(x, y, ring)
        pot = d + half * math.sqrt(2.0)
        heapq.heappush(heap, (-pot, x, y, half, d))

    x = minx + h
    while x < maxx:
        y = miny + h
        while y < maxy:
            push(x, y, h)
            y += cell
        x += cell

    while heap:
        neg_pot, x, y, half, d = heapq.heappop(heap)
        if d > best_d:
            best = (x, y)
            best_d = d
        if -neg_pot - best_d <= precision:
            continue
        nh = half / 2.0
        if nh < precision * 0.5:
            continue
        push(x - nh, y - nh, nh)
        push(x + nh, y - nh, nh)
        push(x - nh, y + nh, nh)
        push(x + nh, y + nh, nh)
    return (best[0], best[1], max(0.0, best_d))


def _bbox(ring: Sequence[Pt]) -> Tuple[float, float, float, float]:
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return min(xs), min(ys), max(xs), max(ys)


def pick_cleared_interior(
    ring: Sequence[Pt],
    forbidden: Sequence[Sequence[Pt]],
    *,
    counter_pt: Optional[Pt] = None,
) -> Dict[str, Any]:
    pole_x, pole_y, pole_r = polylabel(ring, precision=0.15)
    minx, miny, maxx, maxy = _bbox(ring)
    min_dim = min(maxx - minx, maxy - miny)
    edge_need = max(0.35, min_dim * EDGE_MARGIN_FRAC)
    counter = counter_pt if counter_pt is not None else _centroid(ring)
    counter_need = max(1.2, min_dim * COUNTER_CLEAR_FRAC)

    def score(x: float, y: float) -> float:
        edge = signed_edge_distance(x, y, ring)
        if edge < edge_need * 0.55:
            return -1e9
        cd = math.hypot(x - counter[0], y - counter[1])
        fd = 1e18
        for line in forbidden:
            fd = min(fd, dist_to_polyline(x, y, line))
        return edge * 1.4 + min(cd, counter_need * 2.0) * 1.1 + min(fd, 8.0) * 0.8

    best = (pole_x, pole_y)
    best_s = score(pole_x, pole_y)
    step = max(0.35, min_dim / 10.0)
    x = minx + step * 0.5
    while x < maxx:
        y = miny + step * 0.5
        while y < maxy:
            if point_in_ring(x, y, ring):
                s = score(x, y)
                if s > best_s:
                    best_s = s
                    best = (x, y)
            y += step
        x += step
    return {
        "x": best[0],
        "y": best[1],
        "pole_x": pole_x,
        "pole_y": pole_y,
        "pole_r": pole_r,
        "edge_dist": signed_edge_distance(best[0], best[1], ring),
        "counter_dist": math.hypot(best[0] - counter[0], best[1] - counter[1]),
        "inside": point_in_ring(best[0], best[1], ring),
        "score": best_s,
    }


def _load_geo() -> Dict[int, Dict[str, Any]]:
    data = json.loads(GEO_PATH.read_text(encoding="utf-8"))
    out: Dict[int, Dict[str, Any]] = {}
    for rec in data.get("provinces", []):
        out[int(rec["id"])] = rec
    return out


def _line_from_pids(geo: Mapping[int, Mapping[str, Any]], pids: Sequence[int]) -> List[Pt]:
    line: List[Pt] = []
    for pid in pids:
        rec = geo.get(int(pid))
        if rec is None:
            continue
        ring = _ring(rec.get("points") or [])
        if not ring:
            continue
        la = rec.get("label_anchor") or []
        if isinstance(la, (list, tuple)) and len(la) >= 2:
            line.append((float(la[0]), float(la[1])))
        else:
            line.append(_centroid(ring))
    return line


def build_facility_icon_anchor_product(write: bool = False) -> Dict[str, Any]:
    geo = _load_geo()
    spine = _line_from_pids(geo, SPINE_PIDS)
    rhine = _line_from_pids(geo, RHINE_WALK_PIDS)
    forbidden = [spine, rhine]
    anchors: Dict[str, Any] = {}
    ok = True
    reasons: List[str] = []
    worlds: Dict[int, Pt] = {}
    for pid, tier in SEED_TIERS.items():
        rec = geo.get(pid)
        if rec is None:
            ok = False
            reasons.append("missing_geo_%d" % pid)
            continue
        ring = _ring(rec.get("points") or [])
        la = rec.get("label_anchor") or []
        counter = (float(la[0]), float(la[1])) if isinstance(la, (list, tuple)) and len(la) >= 2 else _centroid(ring)
        forced = SEED_FORCE_RAW.get(pid)
        if forced is not None and point_in_ring(forced[0], forced[1], ring):
            picked = {
                "x": forced[0],
                "y": forced[1],
                "pole_x": forced[0],
                "pole_y": forced[1],
                "pole_r": signed_edge_distance(forced[0], forced[1], ring),
                "edge_dist": signed_edge_distance(forced[0], forced[1], ring),
                "counter_dist": math.hypot(forced[0] - counter[0], forced[1] - counter[1]),
                "inside": True,
                "score": 0.0,
            }
        else:
            picked = pick_cleared_interior(ring, forbidden, counter_pt=counter)
        worlds[pid] = (picked["x"], picked["y"])
        fd_spine = dist_to_polyline(picked["x"], picked["y"], spine)
        fd_rhine = dist_to_polyline(picked["x"], picked["y"], rhine)
        if not picked["inside"]:
            ok = False
            reasons.append("outside_%d" % pid)
        if picked["edge_dist"] < 0.25:
            ok = False
            reasons.append("edge_%d" % pid)
        anchors[str(pid)] = {
            "pid": pid,
            "name": SEED_NAMES[pid],
            "tier": tier,
            "raw": [picked["x"], picked["y"]],
            "world": [picked["x"] * THEATER_SCALE, picked["y"] * THEATER_SCALE],
            "centroid_raw": [counter[0], counter[1]],
            "edge_dist": picked["edge_dist"],
            "counter_dist": picked["counter_dist"],
            "spine_dist": fd_spine,
            "rhine_dist": fd_rhine,
        }
    ids = list(SEED_TIERS)
    min_pair = 1e18
    for i, a in enumerate(ids):
        for b in ids[i + 1 :]:
            if a not in worlds or b not in worlds:
                continue
            d = math.hypot(worlds[a][0] - worlds[b][0], worlds[a][1] - worlds[b][1])
            min_pair = min(min_pair, d)
    if min_pair < MIN_PAIR_WORLD:
        ok = False
        reasons.append("pair_too_close_%.1f" % min_pair)
    cluster_d = 0.0
    if CLUSTER_PAIR[0] in worlds and CLUSTER_PAIR[1] in worlds:
        ca = worlds[CLUSTER_PAIR[0]]
        cb = worlds[CLUSTER_PAIR[1]]
        cluster_d = math.hypot(ca[0] - cb[0], ca[1] - cb[1])
        if cluster_d < CLUSTER_PAIR_MIN or cluster_d > CLUSTER_PAIR_MAX:
            ok = False
            reasons.append("cluster_pair_%.1f" % cluster_d)
    koel = geo.get(KOELN_PID)
    if koel is not None:
        kla = koel.get("label_anchor") or []
        kpt = (float(kla[0]), float(kla[1])) if isinstance(kla, (list, tuple)) and len(kla) >= 2 else (0.0, 0.0)
        for pid, pt in worlds.items():
            dx = (pt[0] - kpt[0]) * THEATER_SCALE * 2.27
            dy = (pt[1] - kpt[1]) * THEATER_SCALE * 2.27
            if abs(dx) < 61.6 and abs(dy) < 49.6:
                ok = False
                reasons.append("koeln_counter_%d" % pid)
    blob = {
        "ok": ok,
        "reasons": reasons,
        "source": "fac1a_fix2b_rhineland_anchors",
        "cluster_pair_raw": cluster_d,
        "theater_scale": THEATER_SCALE,
        "seeds": SEED_TIERS,
        "names": SEED_NAMES,
        "min_pair_world_raw": min_pair if min_pair < 1e17 else 0.0,
        "anchors": anchors,
    }
    if write:
        text = json.dumps(blob, indent=2, sort_keys=True) + "\n"
        ANCHOR_ACCURATE.write_text(text, encoding="utf-8")
        ANCHOR_PILOT.write_text(text, encoding="utf-8")
    return blob


def apply_seed_files() -> None:
    sites = []
    for pid, tier in SEED_TIERS.items():
        sites.append(
            {
                "province_id": pid,
                "project_type": "airfield",
                "site_id": "airfield_tier_%d" % tier,
                "tier": tier,
                "construction_state": "COMPLETED",
                "damage_level": 0,
            }
        )
    payload = {
        "sites": sites,
        "meta": {
            "source": "fac1a_rhineland_airfields_fix2b",
            "note": (
                "FAC-1a FIX #2b Rhineland seeds: Viersen L1, Oberbergischer "
                "Kreis L2, Euskirchen L3, Mayen-Koblenz L4. Intact. Default "
                "world_accurate."
            ),
        },
    }
    text = json.dumps(payload, indent=2) + "\n"
    SITES_ACCURATE.write_text(text, encoding="utf-8")
    SITES_PILOT.write_text(text, encoding="utf-8")


__all__ = [
    "SEED_TIERS",
    "SEED_NAMES",
    "SEED_FORCE_RAW",
    "CLUSTER_PAIR",
    "VIERSEN",
    "OBERBERGISCHER",
    "EUSKIRCHEN",
    "MAYEN_KOBLENZ",
    "polylabel",
    "point_in_ring",
    "pick_cleared_interior",
    "build_facility_icon_anchor_product",
    "apply_seed_files",
]
