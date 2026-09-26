"""RX-1 Rhine Crossing — Phase B first vertical (Bonn–Köln–Düsseldorf–Duisburg).

One stretch of the Lower Rhine on the NUTS3 board (id_base 710000).
Crossing edges are REAL GISCO shared borders intersected with a reprojected
Natural Earth Rhine polyline — never province_adjacency.json kNN.

Stored rivers_world.json Rhine id 321 was baked with mercator Y
(use_mercator_y=True on the world_full layer bake). NUTS3 geometry uses
ne_full_geometry_align.lonlat_to_canvas (equirectangular). Step 0 inverts
the stored mercator pixels to lon/lat and reprojects so the line sits on
Köln / Bonn / Düsseldorf / Duisburg (Essen stays off the river).

This product does not renumber IDs, bump Godot, open Dig2 / Maginot /
Hampshire / road tiers / hills, or invent a residual dual package.
IX-1 spine build / paint / move discount stay unchanged.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

from ne_full_geometry_align import lonlat_to_canvas
from nuts3_europe_gis_product import load_nuts3_features, project_ring_lonlat

ROOT = Path(__file__).resolve().parents[3]
SPEC_PATH = ROOT / "data" / "map" / "rx1_rhine_crossings.json"
RIVERS_WORLD = ROOT / "data" / "map" / "rivers_world.json"
ADJ_PATH = ROOT / "data" / "provinces_world_accurate" / "province_adjacency.json"
IDM_GD = ROOT / "scripts" / "map" / "InfrastructureDevelopmentManager.gd"
RULES_GD = ROOT / "scripts" / "map" / "Rx1RhineCrossing.gd"
LAYER_GD = ROOT / "scripts" / "map" / "Rx1RhineLayer.gd"
PROVINCE_GD = ROOT / "scripts" / "data" / "Province.gd"
MOVE_GD = ROOT / "scripts" / "formations" / "FormationMovement.gd"
COMBAT_GD = ROOT / "scripts" / "combat" / "CombatResolver.gd"
BATTLE_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
SUPPLY_GD = ROOT / "scripts" / "supply" / "SupplyPathfinder.gd"
RENDERER_GD = ROOT / "scripts" / "map" / "MapRenderer.gd"
MAP_MANAGER_GD = ROOT / "scripts" / "map" / "MapManager.gd"
INFRA_OVERLAY_GD = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"
GAMEDATA_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
TIME_MANAGER_GD = ROOT / "scripts" / "autoload" / "TimeManager.gd"
TEST_RUNNER_GD = ROOT / "scripts" / "core" / "TestRunner.gd"
GATES_SH = ROOT / "tools" / "eoa_full_test_gates.sh"
HEADLESS_GD = ROOT / "scripts" / "core" / "HeadlessRx1RhineCrossingTest.gd"
LIVE_HARNESS = ROOT / "scripts" / "core" / "HeadlessRx1RhineLiveStayAliveTickTest.gd"
VIS_HARNESS = ROOT / "scripts" / "core" / "HeadlessRx1RhineVisibilityTest.gd"
LIVE_GUARD_SH = ROOT / "tools" / "eoa_rx1_bridge_live_progress_guard.sh"
RUN_GODOT_SH = ROOT / "tools" / "run_godot.sh"

SLICE_NAME = "RX-1 Rhine Crossing"
OWNER_TAG = "GER"
RHINE_RIVER_ID = 321

# Named tunable constants — single config place (mirrored in the JSON spec).
RHINE_UNBRIDGED_MOVE_MULT = 2.0
RHINE_BRIDGED_MOVE_MULT = 1.15
RHINE_UNBRIDGED_ATTACK_MALUS = 0.30
RHINE_BRIDGED_ATTACK_MALUS = 0.10
RX1_FIRST_SESSION_MANDATE_COST = 0

WORLD_BBOX = (-180.0, -56.0, 180.0, 83.0)
WORLD_CANVAS = (8192.0, 4096.0)

# NUTS3 theater (never renumber).
BONN_ID = 710416
KOELN_ID = 710417
LEVERKUSEN_ID = 710418
DUSSELDORF_ID = 710401
DUISBURG_ID = 710402
ESSEN_ID = 710403
METTMANN_ID = 710412
NEUSS_ID = 710413
WESEL_ID = 710415
RBK_ID = 710424
RHEIN_SIEG_ID = 710425

NUTS_TO_PID = {
    "DEA11": DUSSELDORF_ID,
    "DEA12": DUISBURG_ID,
    "DEA13": ESSEN_ID,
    "DEA1C": METTMANN_ID,
    "DEA1D": NEUSS_ID,
    "DEA1F": WESEL_ID,
    "DEA22": BONN_ID,
    "DEA23": KOELN_ID,
    "DEA24": LEVERKUSEN_ID,
    "DEA2B": RBK_ID,
    "DEA2C": RHEIN_SIEG_ID,
}

# Candidates from the approved GO note — keep only those that are real
# GISCO shared borders the Rhine actually sits on (opposite center-banks).
CANDIDATE_EDGES: Tuple[Tuple[int, int], ...] = (
    (NEUSS_ID, METTMANN_ID),
    (NEUSS_ID, DUSSELDORF_ID),
    (KOELN_ID, LEVERKUSEN_ID),
    (KOELN_ID, RBK_ID),
    (BONN_ID, RHEIN_SIEG_ID),
    (DUISBURG_ID, WESEL_ID),
)

# Historical 1936 road bridges at the big cities. Neuss–Mettmann (Monheim
# ferry) is left unbridged so Build Bridge has a target.
SEED_BRIDGED: Tuple[Tuple[int, int], ...] = (
    (NEUSS_ID, DUSSELDORF_ID),
    (KOELN_ID, LEVERKUSEN_ID),
    (KOELN_ID, RBK_ID),
    (BONN_ID, RHEIN_SIEG_ID),
    (DUISBURG_ID, WESEL_ID),
)

CITY_LL = {
    "Köln": (6.9603, 50.9375),
    "Bonn": (7.0990, 50.7374),
    "Düsseldorf": (6.7735, 51.2277),
    "Duisburg": (6.7623, 51.4344),
    "Essen": (7.0116, 51.4556),
    "Leverkusen": (6.9849, 51.0459),
}

NAMES = {
    BONN_ID: "Bonn, Kreisfreie Stadt",
    KOELN_ID: "Köln, Kreisfreie Stadt",
    LEVERKUSEN_ID: "Leverkusen, Kreisfreie Stadt",
    DUSSELDORF_ID: "Düsseldorf, Kreisfreie Stadt",
    DUISBURG_ID: "Duisburg, Kreisfreie Stadt",
    ESSEN_ID: "Essen, Kreisfreie Stadt",
    METTMANN_ID: "Mettmann",
    NEUSS_ID: "Rhein-Kreis Neuss",
    WESEL_ID: "Wesel",
    RBK_ID: "Rheinisch-Bergischer Kreis",
    RHEIN_SIEG_ID: "Rhein-Sieg-Kreis",
}

SHIPPED_API_NEEDLES: Tuple[Tuple[Path, str], ...] = (
    (SPEC_PATH, "RHINE_UNBRIDGED_MOVE_MULT"),
    (SPEC_PATH, "710413"),
    (RULES_GD, "RHINE_UNBRIDGED_MOVE_MULT"),
    (RULES_GD, "func move_mult"),
    (RULES_GD, "func attack_malus"),
    (RULES_GD, "func set_bridged"),
    (LAYER_GD, "class_name Rx1RhineLayer"),
    (LAYER_GD, "func _draw"),
    (LAYER_GD, "ABOVE_UNIT_COUNTERS_Z"),
    (INFRA_OVERLAY_GD, "ROAD_ABOVE_UNIT_COUNTERS_Z"),
    (RENDERER_GD, "inspector_should_show_spine_status"),
    (RENDERER_GD, "_hide_ix1_spine_inspector_chrome"),
    (RUN_GODOT_SH, "class cache missing Rx1RhineCrossing"),
    (GAMEDATA_GD, 'preload("res://scripts/map/Rx1RhineCrossing.gd")'),
    (VIS_HARNESS, "HeadlessRx1RhineVisibilityTest"),
    (IDM_GD, "try_start_rhine_bridge"),
    (IDM_GD, "start_rhine_bridge_project"),
    (IDM_GD, "should_show_build_bridge_button"),
    (IDM_GD, "build_rhine_bridge"),
    (PROVINCE_GD, "is_rx1_crossing_province"),
    (MOVE_GD, "rx1_move_mult"),
    (COMBAT_GD, "rx1_attack_malus"),
    (BATTLE_GD, "rhine_attack_malus"),
    (SUPPLY_GD, "rx1_move_mult"),
    (RENDERER_GD, "BtnBuildRhineBridge"),
    (RENDERER_GD, "_on_build_rhine_bridge_pressed"),
    (RENDERER_GD, "Rhine crossing:"),
    (MAP_MANAGER_GD, "func is_rx1_crossing"),
    (TIME_MANAGER_GD, "_tick_live_construction_on_calendar_day"),
    (TEST_RUNNER_GD, "EOA_SMOKE_RX1_LIVE_PROGRESS"),
    (HEADLESS_GD, "HeadlessRx1RhineCrossingTest"),
    (LIVE_HARNESS, "_tick_live_construction_on_calendar_day"),
    (LIVE_GUARD_SH, "EOA_SMOKE_RX1_LIVE_PROGRESS"),
    (GATES_SH, "HeadlessRx1RhineCrossingTest"),
    (GATES_SH, "HeadlessRx1RhineVisibilityTest"),
    (GATES_SH, "test_rx1_rhine_crossing_product"),
)


def _edge_key(a: int, b: int) -> str:
    lo, hi = (int(a), int(b)) if int(a) < int(b) else (int(b), int(a))
    return "%d-%d" % (lo, hi)


def _edge_key_tuple(a: int, b: int) -> Tuple[int, int]:
    return (int(a), int(b)) if int(a) < int(b) else (int(b), int(a))


def _merc_y(lat: float) -> float:
    lat = max(min(float(lat), 85.05112878), -85.05112878)
    return (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0


def pixel_to_lonlat_merc(x: float, y: float) -> Tuple[float, float]:
    """Invert rivers_world.json world_full bake (mercator Y)."""
    lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
    w, h = WORLD_CANVAS
    lon = lon_min + (float(x) / (w - 1.0)) * (lon_max - lon_min)
    my_max = _merc_y(lat_max)
    my_min = _merc_y(lat_min)
    my = my_max + (float(y) / (h - 1.0)) * (my_min - my_max)
    lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * my))))
    return lon, lat


def point_seg_dist(p: Sequence[float], a: Sequence[float], b: Sequence[float]) -> float:
    ax, ay = float(a[0]), float(a[1])
    bx, by = float(b[0]), float(b[1])
    px, py = float(p[0]), float(p[1])
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 <= 1e-12:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def min_dist_point_poly(p: Sequence[float], ring: Sequence[Sequence[float]]) -> float:
    best = 1e18
    for i in range(len(ring) - 1):
        best = min(best, point_seg_dist(p, ring[i], ring[i + 1]))
    return best


def min_dist_point_line(p: Sequence[float], line: Sequence[Sequence[float]]) -> float:
    best = 1e18
    for i in range(len(line) - 1):
        best = min(best, point_seg_dist(p, line[i], line[i + 1]))
    return best


def centroid(ring: Sequence[Sequence[float]]) -> Tuple[float, float]:
    pts = list(ring)
    if len(pts) >= 2 and pts[0] == pts[-1]:
        pts = pts[:-1]
    if not pts:
        return 0.0, 0.0
    sx = sum(float(p[0]) for p in pts)
    sy = sum(float(p[1]) for p in pts)
    n = float(len(pts))
    return sx / n, sy / n


def shared_border_length(ring_a: Sequence[Sequence[float]], ring_b: Sequence[Sequence[float]], eps: float = 1.6) -> float:
    length = 0.0
    for i in range(len(ring_a) - 1):
        a0, a1 = ring_a[i], ring_a[i + 1]
        if min_dist_point_poly(a0, ring_b) <= eps and min_dist_point_poly(a1, ring_b) <= eps:
            length += math.hypot(float(a1[0]) - float(a0[0]), float(a1[1]) - float(a0[1]))
    return length


def nearest_rhine_index(p: Sequence[float], line: Sequence[Sequence[float]]) -> int:
    best = 1e18
    best_i = 0
    for i in range(max(0, len(line) - 1)):
        d = point_seg_dist(p, line[i], line[i + 1])
        if d < best:
            best = d
            best_i = i
    return best_i


def bank_sign(p: Sequence[float], line: Sequence[Sequence[float]]) -> float:
    """Negative = left/west bank, positive = right/east (downstream = north)."""
    i = nearest_rhine_index(p, line)
    ax, ay = float(line[i][0]), float(line[i][1])
    bx, by = float(line[i + 1][0]), float(line[i + 1][1])
    return (bx - ax) * (float(p[1]) - ay) - (by - ay) * (float(p[0]) - ax)


def bank_name(sign: float) -> str:
    return "left_west" if float(sign) < 0.0 else "right_east"


def load_rhine_reprojected() -> List[List[float]]:
    raw = json.loads(RIVERS_WORLD.read_text(encoding="utf-8"))
    rivers = raw.get("rivers") or []
    rhine = next((r for r in rivers if int(r.get("id", -1)) == RHINE_RIVER_ID), None)
    if rhine is None:
        raise RuntimeError("rivers_world.json missing Rhine id 321")
    out: List[List[float]] = []
    last: Optional[Tuple[float, float]] = None
    for p in rhine.get("points") or []:
        lon, lat = pixel_to_lonlat_merc(float(p[0]), float(p[1]))
        x, y = lonlat_to_canvas(lon, lat)
        xy = (round(float(x), 3), round(float(y), 3))
        if last is not None and abs(xy[0] - last[0]) < 0.05 and abs(xy[1] - last[1]) < 0.05:
            continue
        out.append([xy[0], xy[1], round(lon, 5), round(lat, 5)])
        last = xy
    return out


def clip_theater_course(full: Sequence[Sequence[float]]) -> List[List[float]]:
    """Bonn (~y 950) through Duisburg (~y 930), pad for readability."""
    clip = [p for p in full if 4205.0 <= float(p[0]) <= 4275.0 and 916.0 <= float(p[1]) <= 964.0]
    if len(clip) < 8:
        return [p[:2] for p in full]
    return [[round(float(p[0]), 3), round(float(p[1]), 3)] for p in clip]


def alignment_evidence(course_full: Sequence[Sequence[float]]) -> Dict[str, Any]:
    line = [p[:2] for p in course_full]
    cities: Dict[str, Any] = {}
    for name, (lon, lat) in CITY_LL.items():
        xy = lonlat_to_canvas(lon, lat)
        d = min_dist_point_line(xy, line)
        cities[name] = {
            "lonlat": [lon, lat],
            "canvas": [round(xy[0], 2), round(xy[1], 2)],
            "rhine_dist": round(d, 3),
        }
    return {
        "stored_rivers_world_projection": "mercator_y (build_real_world_map_layers world_full use_mercator_y=True)",
        "nuts3_projection": "ne_full_geometry_align.lonlat_to_canvas equirectangular WORLD_BBOX=(-180,-56,180,83) 8192x4096",
        "action": "invert Rhine id 321 via pixel_to_lonlat mercator_y, reproject with lonlat_to_canvas",
        "city_distances_canvas": cities,
        "essen_off_river": float(cities["Essen"]["rhine_dist"]) > 4.0,
        "cities_on_banks": all(float(cities[n]["rhine_dist"]) < 2.0 for n in ("Köln", "Bonn", "Düsseldorf", "Duisburg")),
        "note": "Stored canvas Y of Rhine 321 (~1781–1864) is the mercator bake; equirect Köln is ~4254,945. After invert+reproject the line sits on the NUTS3 cities.",
    }


def gisco_rings() -> Dict[int, List[List[float]]]:
    feats = load_nuts3_features()
    out: Dict[int, List[List[float]]] = {}
    for f in feats:
        nid = str(f.get("nuts_id") or "")
        if nid not in NUTS_TO_PID:
            continue
        out[int(NUTS_TO_PID[nid])] = project_ring_lonlat(f["ring_ll"])
    return out


def evaluate_edge(
    a: int,
    b: int,
    rings: Mapping[int, Sequence[Sequence[float]]],
    course: Sequence[Sequence[float]],
) -> Dict[str, Any]:
    ra, rb = rings.get(int(a)), rings.get(int(b))
    if not ra or not rb:
        return {"ok": False, "reason": "missing_gisco_ring", "a": int(a), "b": int(b)}
    len_ab = shared_border_length(ra, rb)
    len_ba = shared_border_length(rb, ra)
    slen = max(len_ab, len_ba)
    ca, cb = centroid(ra), centroid(rb)
    sa, sb = bank_sign(ca, course), bank_sign(cb, course)
    mid = [(ca[0] + cb[0]) * 0.5, (ca[1] + cb[1]) * 0.5]
    d_rhine = min_dist_point_line(mid, course)
    # Also measure Rhine vs the shared-border vertices themselves.
    hits = 0
    best_border = 1e18
    for ring in (ra, rb):
        for p in ring:
            if min_dist_point_poly(p, rb if ring is ra else ra) <= 1.6:
                d = min_dist_point_line(p, course)
                best_border = min(best_border, d)
                if d <= 3.5:
                    hits += 1
    opposite = (sa * sb) < 0.0
    real_shared = slen >= 0.8
    on_rhine = best_border <= 3.5 and hits >= 2
    ok = real_shared and opposite and on_rhine
    return {
        "ok": ok,
        "a": int(a),
        "b": int(b),
        "names": [NAMES.get(int(a), str(a)), NAMES.get(int(b), str(b))],
        "shared_border_length": round(slen, 3),
        "rhine_dist_shared": round(best_border if best_border < 1e17 else d_rhine, 3),
        "rhine_hits": hits,
        "banks": [bank_name(sa), bank_name(sb)],
        "bank_signs": [round(sa, 3), round(sb, 3)],
        "opposite_center_banks": opposite,
        "midpoint": [round(mid[0], 2), round(mid[1], 2)],
        "real_shared_border": real_shared,
        "on_rhine": on_rhine,
    }


def historical_note(a: int, b: int) -> str:
    key = _edge_key(a, b)
    notes = {
        _edge_key(NEUSS_ID, DUSSELDORF_ID): (
            "1936 seed BRIDGED: Oberkasseler Brücke (1898), road/tram Rhine bridge "
            "at Düsseldorf. Rheinkniebrücke (1969) is out of era."
        ),
        _edge_key(KOELN_ID, LEVERKUSEN_ID): (
            "1936 seed BRIDGED: Köln road Rhine bridges — Deutzer Brücke (1915) and "
            "Mülheimer Brücke (1929). Hohenzollernbrücke (1911) is rail+pedestrian. "
            "The A1 Leverkusen Autobahn bridge is 1965 and is not this seed."
        ),
        _edge_key(KOELN_ID, RBK_ID): (
            "1936 seed BRIDGED: same Köln city road bridges (Deutz 1915 / Mülheim 1929) "
            "serve the eastern face. Face-bank: Köln centroid is left/west; "
            "Rheinisch-Bergischer Kreis is right/east."
        ),
        _edge_key(BONN_ID, RHEIN_SIEG_ID): (
            "1936 seed BRIDGED: Bonn Rhine bridge (opened 1898; later Friedrich-Ebert-Brücke). "
            "Destroyed 1945 — standing in 1936."
        ),
        _edge_key(DUISBURG_ID, WESEL_ID): (
            "1936 seed BRIDGED: Friedrich-Ebert-Brücke Duisburg (Homberg–Ruhrort, 1907), "
            "road Rhine crossing at the city. Duisburg centroid is right/east; Wesel is left/west here."
        ),
        _edge_key(NEUSS_ID, METTMANN_ID): (
            "1936 UNBRIDGED (Build Bridge target): Neuss–Mettmann / Monheim-am-Rhein stretch. "
            "No road Rhine bridge in 1936; ferry only. Autobahn bridges here are postwar."
        ),
    }
    return notes.get(key, "")


def build_crossings_payload() -> Dict[str, Any]:
    full = load_rhine_reprojected()
    course = clip_theater_course(full)
    rings = gisco_rings()
    align = alignment_evidence(full)
    edges: List[Dict[str, Any]] = []
    fails: List[str] = []
    seed_set = {_edge_key(a, b) for a, b in SEED_BRIDGED}
    for a, b in CANDIDATE_EDGES:
        ev = evaluate_edge(a, b, rings, course)
        if not ev.get("ok"):
            fails.append("%s: %s" % (_edge_key(a, b), ev))
            continue
        key = _edge_key(a, b)
        ev["edge"] = [int(a), int(b)] if int(a) < int(b) else [int(b), int(a)]
        ev["bridged_1936"] = key in seed_set
        ev["historical"] = historical_note(a, b)
        edges.append(ev)
    return {
        "slice": SLICE_NAME,
        "theater": "lower_rhine_bonn_duisburg",
        "owner_tag": OWNER_TAG,
        "id_base": 710000,
        "constants": {
            "RHINE_UNBRIDGED_MOVE_MULT": RHINE_UNBRIDGED_MOVE_MULT,
            "RHINE_BRIDGED_MOVE_MULT": RHINE_BRIDGED_MOVE_MULT,
            "RHINE_UNBRIDGED_ATTACK_MALUS": RHINE_UNBRIDGED_ATTACK_MALUS,
            "RHINE_BRIDGED_ATTACK_MALUS": RHINE_BRIDGED_ATTACK_MALUS,
            "first_session_mandate_cost": RX1_FIRST_SESSION_MANDATE_COST,
        },
        "face_bank_convention": (
            "The Rhine flows north (downstream toward the Netherlands) on this stretch. "
            "Bank sign is the 2D cross product of the downstream tangent with the vector "
            "from the nearest Rhine point to the NUTS3 centroid. Negative = left/west bank, "
            "positive = right/east bank. Cities that span both banks (Köln, Bonn, Düsseldorf, "
            "Duisburg) use their NUTS3 centroid bank — never a dual-bank special case. "
            "A listed crossing is left-bank centroid against right-bank centroid."
        ),
        "alignment": align,
        "course": {
            "source": "data/map/rivers_world.json Rhine id 321 (Natural Earth ne_10m_rivers_lake_centerlines)",
            "reprojected": True,
            "points": course,
        },
        "control_off_river_id": ESSEN_ID,
        "unbridged_build_target": [NEUSS_ID, METTMANN_ID],
        "edges": edges,
        "fails": fails,
        "parked": [
            "bridge blow/capture",
            "rail bridges / pontoons",
            "Mosel / Main / Ruhr / Sieg",
            "hills/relief RL-1",
            "road tiers",
            "Dig2 / Maginot / Hampshire",
        ],
    }


def write_spec(path: Path = SPEC_PATH) -> Dict[str, Any]:
    payload = build_crossings_payload()
    out = {k: v for k, v in payload.items() if k != "fails"}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return payload


def load_rx1_spec(path: Path = SPEC_PATH) -> Dict[str, Any]:
    if not path.is_file():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    return raw if isinstance(raw, dict) else {}


def listed_edges(spec: Optional[Mapping[str, Any]] = None) -> List[Tuple[int, int]]:
    data = spec if spec is not None else load_rx1_spec()
    out: List[Tuple[int, int]] = []
    for row in data.get("edges") or []:
        if not isinstance(row, dict):
            continue
        pair = row.get("edge") or []
        if isinstance(pair, list) and len(pair) >= 2:
            out.append(_edge_key_tuple(int(pair[0]), int(pair[1])))
    return out


def is_seed_bridged(a: int, b: int, spec: Optional[Mapping[str, Any]] = None) -> bool:
    key = _edge_key(a, b)
    data = spec if spec is not None else load_rx1_spec()
    for row in data.get("edges") or []:
        pair = row.get("edge") or []
        if isinstance(pair, list) and len(pair) >= 2 and _edge_key(int(pair[0]), int(pair[1])) == key:
            return bool(row.get("bridged_1936"))
    return False


def move_mult(a: int, b: int, bridged: Optional[bool] = None, spec: Optional[Mapping[str, Any]] = None) -> float:
    data = spec if spec is not None else load_rx1_spec()
    consts = data.get("constants") or {}
    key = _edge_key(a, b)
    listed = {_edge_key(x, y) for x, y in listed_edges(data)}
    if key not in listed:
        return 1.0
    is_b = is_seed_bridged(a, b, data) if bridged is None else bool(bridged)
    if is_b:
        return float(consts.get("RHINE_BRIDGED_MOVE_MULT", RHINE_BRIDGED_MOVE_MULT))
    return float(consts.get("RHINE_UNBRIDGED_MOVE_MULT", RHINE_UNBRIDGED_MOVE_MULT))


def attack_malus(a: int, b: int, bridged: Optional[bool] = None, spec: Optional[Mapping[str, Any]] = None) -> float:
    data = spec if spec is not None else load_rx1_spec()
    consts = data.get("constants") or {}
    key = _edge_key(a, b)
    listed = {_edge_key(x, y) for x, y in listed_edges(data)}
    if key not in listed:
        return 0.0
    is_b = is_seed_bridged(a, b, data) if bridged is None else bool(bridged)
    if is_b:
        return float(consts.get("RHINE_BRIDGED_ATTACK_MALUS", RHINE_BRIDGED_ATTACK_MALUS))
    return float(consts.get("RHINE_UNBRIDGED_ATTACK_MALUS", RHINE_UNBRIDGED_ATTACK_MALUS))


def hop_eta_days(base_hop: float, a: int, b: int, bridged: bool, spec: Optional[Mapping[str, Any]] = None) -> float:
    return float(base_hop) * move_mult(a, b, bridged, spec)


def attack_power_after(base_power: float, a: int, b: int, bridged: bool, spec: Optional[Mapping[str, Any]] = None) -> float:
    return float(base_power) * (1.0 - attack_malus(a, b, bridged, spec))


def knn_has_koeln_essen() -> bool:
    """Adjacency.json is kNN and lists non-touching pairs — do not use it for crossings."""
    if not ADJ_PATH.is_file():
        return False
    raw = json.loads(ADJ_PATH.read_text(encoding="utf-8"))
    adj = raw.get("adjacency") if isinstance(raw, dict) else {}
    nbrs = [int(x) for x in (adj.get(str(KOELN_ID)) or adj.get(KOELN_ID) or [])]
    return ESSEN_ID in nbrs


def shared_border_guard(spec: Optional[Mapping[str, Any]] = None) -> Dict[str, Any]:
    data = spec if spec is not None else load_rx1_spec()
    full = load_rhine_reprojected()
    course = clip_theater_course(full)
    rings = gisco_rings()
    missing: List[str] = []
    checked: List[str] = []
    for a, b in listed_edges(data):
        ev = evaluate_edge(a, b, rings, course)
        checked.append(_edge_key(a, b))
        if not ev.get("real_shared_border"):
            missing.append("%s not a GISCO shared border (len=%s)" % (_edge_key(a, b), ev.get("shared_border_length")))
        if not ev.get("on_rhine"):
            missing.append("%s shared border does not sit on the Rhine" % _edge_key(a, b))
        if not ev.get("opposite_center_banks"):
            missing.append("%s same center-bank (face-bank convention)" % _edge_key(a, b))
    # Köln–Essen is kNN-adjacent but must never be a listed crossing.
    if _edge_key(KOELN_ID, ESSEN_ID) in checked:
        missing.append("koln_essen_listed")
    return {
        "ok": not missing and len(checked) >= 1,
        "checked": checked,
        "missing": missing,
        "knn_lists_koeln_essen": knn_has_koeln_essen(),
    }


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def shipped_api_integrity() -> Dict[str, Any]:
    missing: List[str] = []
    found: List[str] = []
    for path, needle in SHIPPED_API_NEEDLES:
        label = "%s:%s" % (path.name, needle)
        if needle in _read(path):
            found.append(label)
        else:
            missing.append(label)
    return {"ok": not missing, "found": found, "missing": missing}


def _const_int(src: str, name: str) -> int:
    import re

    m = re.search(r"const %s := (\d+)" % name, src)
    return int(m.group(1)) if m else -1


def visibility_order() -> Dict[str, Any]:
    """FIX1: Rhine + built road z above DemoUnitIcon 28; spine chrome not on Neuss."""
    layer = _read(LAYER_GD)
    infra = _read(INFRA_OVERLAY_GD)
    ren = _read(RENDERER_GD)
    rhine_z = _const_int(layer, "ABOVE_UNIT_COUNTERS_Z")
    unit_z = _const_int(layer, "UNIT_COUNTER_Z")
    road_z = _const_int(infra, "ROAD_ABOVE_UNIT_COUNTERS_Z")
    overlay_unit = _const_int(infra, "UNIT_COUNTER_Z")
    spine_ok = (
        "inspector_should_show_spine_status" in ren
        and "_hide_ix1_spine_inspector_chrome" in ren
        and "710413" in ren
        and "710417" in ren
    )
    ok = (
        unit_z == 28
        and overlay_unit == 28
        and rhine_z > unit_z
        and road_z > overlay_unit
        and spine_ok
        and "HALO_WIDTH" in layer
    )
    return {
        "ok": ok,
        "rhine_z": rhine_z,
        "road_z": road_z,
        "unit_z": unit_z,
        "spine_ok": spine_ok,
    }


def fresh_checkout_launch() -> Dict[str, Any]:
    """Launch path imports when class cache lacks Rx1RhineCrossing; autoloads preload."""
    run = _read(RUN_GODOT_SH)
    gd = _read(GAMEDATA_GD)
    mm = _read(MAP_MANAGER_GD)
    idm = _read(IDM_GD)
    preload = 'preload("res://scripts/map/Rx1RhineCrossing.gd")'
    ok = (
        "--headless --import" in run
        and "Rx1RhineCrossing" in run
        and "class cache missing" in run
        and preload in gd
        and preload in mm
        and preload in idm
    )
    return {"ok": ok, "import_gate": "--headless --import" in run and "class cache missing" in run, "preload": preload in gd}


def ix1_unchanged() -> Dict[str, Any]:
    """RX-1 must not strip the IX-1 spine APIs."""
    missing: List[str] = []
    idm = _read(IDM_GD)
    for needle in (
        "try_start_road_spine",
        "link_ix1_road_spine_edges",
        "start_road_spine_project",
        "IX1_FIRST_SESSION_MANDATE_COST",
    ):
        if needle not in idm:
            missing.append(needle)
    if "BtnBuildRoadSpine" not in _read(RENDERER_GD):
        missing.append("BtnBuildRoadSpine")
    if "built_road_neighbors" not in _read(PROVINCE_GD):
        missing.append("built_road_neighbors")
    return {"ok": not missing, "missing": missing}


def build_rx1_rhine_crossing_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    spec = load_rx1_spec()
    if spec.get("slice") == SLICE_NAME:
        passes.append("spec_named_rx1")
    else:
        fails.append("spec_named_rx1")

    consts = spec.get("constants") or {}
    if (
        float(consts.get("RHINE_UNBRIDGED_MOVE_MULT", 0)) == RHINE_UNBRIDGED_MOVE_MULT
        and float(consts.get("RHINE_BRIDGED_MOVE_MULT", 0)) == RHINE_BRIDGED_MOVE_MULT
        and float(consts.get("RHINE_UNBRIDGED_ATTACK_MALUS", 0)) == RHINE_UNBRIDGED_ATTACK_MALUS
        and float(consts.get("RHINE_BRIDGED_ATTACK_MALUS", 0)) == RHINE_BRIDGED_ATTACK_MALUS
    ):
        passes.append("named_constants")
    else:
        fails.append("named_constants")

    align = spec.get("alignment") or {}
    if align.get("cities_on_banks") and align.get("essen_off_river"):
        passes.append("alignment_cities")
    else:
        fails.append("alignment_cities")

    course = (spec.get("course") or {}).get("points") or []
    if isinstance(course, list) and len(course) >= 16:
        passes.append("vector_course")
    else:
        fails.append("vector_course")

    guard = shared_border_guard(spec)
    if guard.get("ok"):
        passes.append("shared_border_guard")
    else:
        fails.append("shared_border_guard")

    edges = listed_edges(spec)
    if len(edges) >= 4:
        passes.append("crossing_count")
    else:
        fails.append("crossing_count")

    unbridged = [e for e in edges if not is_seed_bridged(e[0], e[1], spec)]
    bridged = [e for e in edges if is_seed_bridged(e[0], e[1], spec)]
    if unbridged and bridged:
        passes.append("one_unbridged_seed")
    else:
        fails.append("one_unbridged_seed")

    if _edge_key(NEUSS_ID, METTMANN_ID) in {_edge_key(a, b) for a, b in unbridged}:
        passes.append("neuss_mettmann_unbridged")
    else:
        fails.append("neuss_mettmann_unbridged")

    ua, ub = NEUSS_ID, METTMANN_ID
    ba, bb = NEUSS_ID, DUSSELDORF_ID
    if hop_eta_days(1.0, ua, ub, False, spec) > hop_eta_days(1.0, ba, bb, True, spec) + 0.2:
        passes.append("unbridged_eta_longer")
    else:
        fails.append("unbridged_eta_longer")
    if attack_power_after(100.0, ua, ub, False, spec) < attack_power_after(100.0, ba, bb, True, spec) - 5.0:
        passes.append("unbridged_attack_weaker")
    else:
        fails.append("unbridged_attack_weaker")

    # Stack with IX-1: road-discounted hop * bridged still < same hop * unbridged.
    road_hop = 0.80
    if hop_eta_days(road_hop, ba, bb, True, spec) < hop_eta_days(road_hop, ua, ub, False, spec):
        passes.append("stacks_with_ix1_road")
    else:
        fails.append("stacks_with_ix1_road")

    api = shipped_api_integrity()
    if api.get("ok"):
        passes.append("shipped_apis")
    else:
        fails.append("shipped_apis")

    ix1 = ix1_unchanged()
    if ix1.get("ok"):
        passes.append("ix1_unchanged")
    else:
        fails.append("ix1_unchanged")

    if _edge_key(KOELN_ID, ESSEN_ID) not in {_edge_key(a, b) for a, b in edges}:
        passes.append("no_knn_koeln_essen")
    else:
        fails.append("no_knn_koeln_essen")

    vis = visibility_order()
    if vis.get("ok"):
        passes.append("visibility_order")
    else:
        fails.append("visibility_order")

    fresh = fresh_checkout_launch()
    if fresh.get("ok"):
        passes.append("fresh_checkout_launch")
    else:
        fails.append("fresh_checkout_launch")

    return {
        "ok": not fails,
        "slice": SLICE_NAME,
        "passes": passes,
        "fails": fails,
        "edges": [list(e) for e in edges],
        "bridged": [list(e) for e in bridged],
        "unbridged": [list(e) for e in unbridged],
        "constants": consts,
        "alignment": align,
        "shared_border_guard": guard,
        "shipped": api,
        "ix1_unchanged": ix1,
        "visibility_order": vis,
        "fresh_checkout_launch": fresh,
        "move_unbridged": move_mult(ua, ub, False, spec),
        "move_bridged": move_mult(ba, bb, True, spec),
        "attack_unbridged": attack_malus(ua, ub, False, spec),
        "attack_bridged": attack_malus(ba, bb, True, spec),
    }
