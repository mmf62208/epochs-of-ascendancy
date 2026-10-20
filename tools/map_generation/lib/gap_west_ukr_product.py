"""GAP-WEST-UKR checks that do not import shapely."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"

NEW_IDS = list(range(905900, 905909))
NAMED = {
    905900: "Lviv",
    905901: "Lutsk",
    905902: "Stanislawow",
    905903: "Tarnopol",
    905904: "Chisinau",
    905905: "Rovno",
    905906: "Drohobych",
    905907: "Kovel",
    905908: "Chernivtsi",
}
CITIES = {
    "Lviv": (24.0297, 49.8397),
    "Lutsk": (25.3424, 50.7472),
    "Stanislawow": (24.7111, 48.9226),
    "Tarnopol": (25.5948, 49.5535),
    "Chisinau": (28.8575, 47.0105),
}

Point = Tuple[float, float]
Ring = Sequence[Sequence[float]]


def prefer_named_west_ukr() -> bool:
    return True  # GAP_WEST_UKR_NAMED


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


def selected_city_hits() -> dict:
    live = load_geometry_rings()
    if prefer_named_west_ukr():
        return city_hits(live)
    return {"hits": {name: None for name in CITIES}, "misses": list(CITIES), "ok": False}
