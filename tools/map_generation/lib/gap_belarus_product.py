"""GAP-BELARUS checks that do not import shapely.

Named-city hits and the Moscow–Vitebsk adjacency are read from the committed
board. The generator owns geometry; this module is the gate-facing audit.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"

BLR_IDS = list(range(905807, 905827))
MOSCOW_ID = 903534
VITEBSK_ID = 905809
POLOTSK_ID = 905807
NAMED = {
    905807: "Polotsk",
    905808: "Pinsk",
    905809: "Vitebsk",
    905810: "Mozyr",
    905811: "Stolin",
    905812: "Borisov",
    905813: "Brest",
    905814: "Grodno",
    905815: "Gomel",
    905816: "Vileyka",
    905817: "Braslaw",
    905818: "Minsk",
    905819: "Bobruisk",
    905820: "Mogilev",
    905821: "Molodechno",
    905822: "Slutsk",
    905823: "Baranovichi",
    905824: "Klimovichi",
    905825: "Lida",
    905826: "Orsha",
}
CITIES = {
    "Minsk": (27.5615, 53.9023),
    "Gomel": (30.988, 52.441),
    "Vitebsk": (30.204, 55.190),
    "Mogilev": (30.331, 53.901),
    "Polotsk": (28.784, 55.485),
}

Point = Tuple[float, float]
Ring = Sequence[Sequence[float]]


def prefer_named_belarus() -> bool:
    return True  # GAP_BELARUS_NAMED


def canvas_to_lonlat(x: float, y: float) -> Point:
    lon = -180.0 + (float(x) / 8191.0) * 360.0
    lat = 83.0 - (float(y) / 4095.0) * 139.0
    return lon, lat


def lonlat_to_canvas(lon: float, lat: float) -> Point:
    x = (float(lon) - (-180.0)) / 360.0 * 8191.0
    y = (83.0 - float(lat)) / 139.0 * 4095.0
    return x, y


def _open_ring(ring: Ring) -> List[Point]:
    pts = [(float(p[0]), float(p[1])) for p in ring if len(p) >= 2]
    if len(pts) >= 2 and pts[0] == pts[-1]:
        pts = pts[:-1]
    return pts


def point_in_ring(x: float, y: float, ring: Ring) -> bool:
    pts = _open_ring(ring)
    n = len(pts)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y):
            den = (yj - yi) if (yj - yi) != 0.0 else 1e-12
            if x < (xj - xi) * (y - yi) / den + xi:
                inside = not inside
        j = i
    return inside


def load_geometry_rings() -> Dict[int, List[List[float]]]:
    doc = json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))
    out: Dict[int, List[List[float]]] = {}
    for row in doc.get("provinces") or []:
        out[int(row["id"])] = row.get("points") or []
    return out


def load_base_names() -> Dict[int, str]:
    doc = json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))
    return {int(p["id"]): str(p.get("name") or "") for p in doc.get("provinces") or []}


def city_hits(rings: Dict[int, Ring] | None = None) -> dict:
    rings = rings if rings is not None else load_geometry_rings()
    names = load_base_names()
    hits = {}
    misses = []
    for name, (lon, lat) in CITIES.items():
        x, y = lonlat_to_canvas(lon, lat)
        found = None
        for pid, ring in rings.items():
            if pid not in NAMED:
                continue
            if point_in_ring(x, y, ring):
                found = pid
                break
        hits[name] = found
        if found is None or names.get(found) != name:
            misses.append(name)
    return {"hits": hits, "misses": misses, "ok": not misses}


def moscow_borders_vitebsk() -> bool:
    adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
    nbs = [int(x) for x in adj.get(str(MOSCOW_ID), [])]
    back = [int(x) for x in adj.get(str(VITEBSK_ID), [])]
    return VITEBSK_ID in nbs and MOSCOW_ID in back


def selected_city_hits() -> dict:
    live = load_geometry_rings()
    if prefer_named_belarus():
        return city_hits(live)
    # Mutant path: pretend the rings still have the tiny ADM2 placeholders
    # by requiring every named city to miss.
    return {"hits": {name: None for name in CITIES}, "misses": list(CITIES), "ok": False}
