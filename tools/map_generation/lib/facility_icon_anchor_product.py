"""FAC-1a FIX #3: world-space interior airfield anchors (clearance).

Precomputed once (never per frame). Each seed maximizes clearance from the
real Rhine course, the gold spine, and its own border. Never renumbers IDs.
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

# FIX #3 Rhineland reseed (never renumber). Play MIXED 234e12b8: Neuwied L4
# sits on the Rhine once split; Viersen L1 hangs over the NLD border
# (center click → Midden-Limburg at 0.977). No NUTS3 can contain a 22px
# disc at zoom 0.62 (need ~14 raw inradius; poles are ~2–5). Report those
# cannot-fits; do not cap below 22px (badge/icon spec). Reseed L1/L2/L4 to
# interiors that meet Rhine+spine disc clearance (~24 world) and maximize
# border inset. Cluster is Ober L3 + Siegen L4 (raw ~16.5); splits at ~1.59.
BORKEN = 710430
WARENDORF = 710434
KREUZNACH = WARENDORF
OBERBERGISCHER = 710423
SIEGEN = 710451
# L1/L2/L4 reseeds keep old constant names so tests/aliases still import.
VIERSEN = BORKEN
HUNSRUECK = WARENDORF
NEUWIED = SIEGEN
AHRWEILER = NEUWIED
MAYEN_KOBLENZ = HUNSRUECK
EUSKIRCHEN = NEUWIED
AACHEN = VIERSEN
TRIER_SAARBURG = OBERBERGISCHER
EMSLAND = VIERSEN
ORTENAU = OBERBERGISCHER
GOTTINGEN = NEUWIED
ANSBACH = HUNSRUECK
SEED_TIERS: Dict[int, int] = {
    BORKEN: 1,
    WARENDORF: 2,
    OBERBERGISCHER: 3,
    SIEGEN: 4,
}
SEED_NAMES: Dict[int, str] = {
    BORKEN: "Borken",
    WARENDORF: "Warendorf",
    OBERBERGISCHER: "Oberbergischer Kreis",
    SIEGEN: "Siegen-Wittgenstein",
}
SEED_FORCE_RAW: Dict[int, Tuple[float, float]] = {
    BORKEN: (4254.63, 911.32),
    WARENDORF: (4276.64, 917.21),
    OBERBERGISCHER: (4270.29, 943.16),
    SIEGEN: (4286.75, 941.99),
}
CLUSTER_PAIR: Tuple[int, int] = (OBERBERGISCHER, SIEGEN)
NEIGHBOR_PID = OBERBERGISCHER
KOELN_PID = 710417
BONN_PID = 710416
CANNOT_FIT_PREVIOUS: Tuple[Tuple[int, str, str], ...] = (
    (710460, "Neuwied", "rhine_through_province"),
    (710414, "Viersen", "nld_border_and_full_disc"),
    (710464, "Rhein-Hunsrück-Kreis", "rhine_course_short"),
    (710457, "Bad Kreuznach", "lux_capital_star_disk"),
)

# Gold-spine / Rhine corridor (centroids of the IX-1 / RX-1 walk). Not sampled as
# S1 gold-cover — that walk never included Neuss, which is why FIX #1 false-passed.
SPINE_PIDS: Tuple[int, ...] = (710416, 710417, 710418)
RHINE_WALK_PIDS: Tuple[int, ...] = (710416, 710417, 710401, 710402)

THEATER_SCALE = 1.728
COUNTER_CLEAR_FRAC = 0.38
EDGE_MARGIN_FRAC = 0.12
MIN_PAIR_WORLD = 16.0
CLUSTER_PAIR_MIN = 16.0
CLUSTER_PAIR_MAX = 17.5
ISO_PID = BORKEN
ISO_MIN = 20.7
RX1_COURSE_PATH = ROOT / "data" / "map" / "rx1_rhine_crossings.json"
SITE_MIN_ZOOM = 0.62
MARGIN_PX = 4.0
MID_ICON_PX = 22.0
CLEAR_ZOOMS: Tuple[float, ...] = (0.62, 0.65, 0.77, 0.99, 1.30, 1.59, 1.90, 2.27, 3.0)


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


def icon_screen_px(zoom: float) -> float:
    if zoom >= 2.0:
        return 32.0
    if zoom >= 1.0:
        return 26.0 + 6.0 * (zoom - 1.0)
    return MID_ICON_PX


def disc_need_world(zoom: float, cluster: bool = False) -> float:
    px = icon_screen_px(zoom) + (4.0 if cluster else 0.0)
    half = px * 0.5 + (16.0 * 0.35 if cluster else 0.0)
    return (half + MARGIN_PX) / max(zoom, 0.04)


def max_disc_need_world(cluster: bool = False) -> float:
    return max(disc_need_world(z, cluster) for z in CLEAR_ZOOMS)


def load_rhine_course() -> List[Pt]:
    if not RX1_COURSE_PATH.is_file():
        return []
    data = json.loads(RX1_COURSE_PATH.read_text(encoding="utf-8"))
    raw = ((data.get("course") or {}) if isinstance(data, dict) else {}).get("points") or []
    out: List[Pt] = []
    for p in raw:
        if isinstance(p, (list, tuple)) and len(p) >= 2:
            out.append((float(p[0]), float(p[1])))
    return out


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
    corridor_need_raw: float = 0.0,
    edge_floor: float = 0.7,
) -> Dict[str, Any]:
    pole_x, pole_y, pole_r = polylabel(ring, precision=0.15)
    minx, miny, maxx, maxy = _bbox(ring)
    min_dim = min(maxx - minx, maxy - miny)
    counter = counter_pt if counter_pt is not None else _centroid(ring)
    need = max(0.0, corridor_need_raw)
    step = max(0.18, min_dim / 18.0)
    best: Optional[Pt] = None
    best_s = -1e18
    n_ok = 0
    x = minx + step * 0.4
    while x < maxx:
        y = miny + step * 0.4
        while y < maxy:
            if point_in_ring(x, y, ring):
                edge = signed_edge_distance(x, y, ring)
                if edge < edge_floor:
                    y += step
                    continue
                fd = 1e18
                for line in forbidden:
                    fd = min(fd, dist_to_polyline(x, y, line))
                if need > 0.0 and fd < need:
                    y += step
                    continue
                n_ok += 1
                s = min(edge, fd) * 10.0 + fd * 0.15 + edge * 0.35
                if s > best_s:
                    best_s = s
                    best = (x, y)
            y += step
        x += step
    if best is None:
        best = (pole_x, pole_y)
        best_s = -1.0
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
        "n_ok": n_ok,
        "met_need": n_ok > 0 and need > 0.0,
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
    rhine_walk = _line_from_pids(geo, RHINE_WALK_PIDS)
    course = load_rhine_course()
    forbidden = [spine, course if course else rhine_walk]
    disc_need_raw = max_disc_need_world(False) / THEATER_SCALE
    clus_need_raw = max_disc_need_world(True) / THEATER_SCALE
    anchors: Dict[str, Any] = {}
    ok = True
    reasons: List[str] = []
    worlds: Dict[int, Pt] = {}
    cannot_fit: List[Dict[str, Any]] = []
    for pid, name, why in CANNOT_FIT_PREVIOUS:
        cannot_fit.append({"pid": pid, "name": name, "reason": why})
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
        picked: Dict[str, Any]
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
                "n_ok": 1,
                "met_need": True,
            }
        else:
            picked = pick_cleared_interior(
                ring,
                forbidden,
                counter_pt=counter,
                corridor_need_raw=disc_need_raw,
                edge_floor=0.8,
            )
        worlds[pid] = (picked["x"], picked["y"])
        fd_spine = dist_to_polyline(picked["x"], picked["y"], spine)
        fd_rhine = dist_to_polyline(picked["x"], picked["y"], course if course else rhine_walk)
        edge_w = float(picked["edge_dist"]) * THEATER_SCALE
        full_disc_ok_zooms: List[float] = []
        for z in CLEAR_ZOOMS:
            if edge_w + 1e-6 >= disc_need_world(z, False):
                full_disc_ok_zooms.append(z)
        if not full_disc_ok_zooms:
            cannot_fit.append(
                {
                    "pid": pid,
                    "name": SEED_NAMES[pid],
                    "reason": "full_disc_exceeds_inradius",
                    "edge_world": edge_w,
                    "need_world": max_disc_need_world(False),
                }
            )
        if not picked["inside"]:
            ok = False
            reasons.append("outside_%d" % pid)
        if picked["edge_dist"] < 0.25:
            ok = False
            reasons.append("edge_%d" % pid)
        if fd_rhine * THEATER_SCALE + 0.05 < max_disc_need_world(False):
            ok = False
            reasons.append("rhine_%d" % pid)
        if fd_spine * THEATER_SCALE + 0.05 < max_disc_need_world(False):
            ok = False
            reasons.append("spine_%d" % pid)
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
            "full_disc_ok_zooms": full_disc_ok_zooms,
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
        if ISO_PID in worlds:
            for member in CLUSTER_PAIR:
                if member not in worlds:
                    continue
                d_iso = math.hypot(worlds[ISO_PID][0] - worlds[member][0], worlds[ISO_PID][1] - worlds[member][1])
                if d_iso < ISO_MIN:
                    ok = False
                    reasons.append("iso_%d_%d_%.1f" % (ISO_PID, member, d_iso))
    koel = geo.get(KOELN_PID)
    if koel is not None and NEIGHBOR_PID in worlds:
        kla = koel.get("label_anchor") or []
        kpt = (float(kla[0]), float(kla[1])) if isinstance(kla, (list, tuple)) and len(kla) >= 2 else (0.0, 0.0)
        pt = worlds[NEIGHBOR_PID]
        dx = (pt[0] - kpt[0]) * THEATER_SCALE * 2.27
        dy = (pt[1] - kpt[1]) * THEATER_SCALE * 2.27
        if abs(dx) < 61.6 and abs(dy) < 49.6:
            ok = False
            reasons.append("koeln_counter_%d" % NEIGHBOR_PID)
    blob = {
        "ok": ok,
        "reasons": reasons,
        "source": "fac1a_fix3_rhineland_anchors",
        "cluster_pair_raw": cluster_d,
        "theater_scale": THEATER_SCALE,
        "disc_need_world": max_disc_need_world(False),
        "cluster_need_world": max_disc_need_world(True),
        "cannot_fit": cannot_fit,
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
            "source": "fac1a_rhineland_airfields_fix3",
            "note": (
                "FAC-1a FIX #3 Rhineland seeds: Borken L1, Warendorf L2, "
                "Oberbergischer Kreis L3, Siegen-Wittgenstein L4. Intact. "
                "Default world_accurate. Neuwied/Viersen/Hunsrück/Kreuznach cannot-fit."
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
    "NEIGHBOR_PID",
    "VIERSEN",
    "OBERBERGISCHER",
    "NEUWIED",
    "AHRWEILER",
    "EUSKIRCHEN",
    "HUNSRUECK",
    "MAYEN_KOBLENZ",
    "BORKEN",
    "KREUZNACH",
    "WARENDORF",
    "SIEGEN",
    "CANNOT_FIT_PREVIOUS",
    "polylabel",
    "point_in_ring",
    "pick_cleared_interior",
    "build_facility_icon_anchor_product",
    "apply_seed_files",
    "load_rhine_course",
    "max_disc_need_world",
]
