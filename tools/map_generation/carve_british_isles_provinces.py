#!/usr/bin/env python3
"""Reposition + expand British Isles provinces on the phase1 Europe canvas.

Fixes compressed 6-blob UK: adds Scotland, Wales, Ireland provinces and places
England city names at geographically consistent canvas positions derived from
real WGS84 anchors via lonlat_to_pixel (same bbox as world_map_layers.yaml).

Run from repo root:
  python3 tools/map_generation/carve_british_isles_provinces.py
  python3 tools/map_generation/build_curated_strategic_regions.py
  python3 tools/map_generation/qc_british_isles_geography.py
"""
from __future__ import annotations

import json
import math
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "map_generation"))
from lib.map_layer_utils import lonlat_to_pixel  # noqa: E402

DATA = ROOT / "data" / "provinces_phase1_test"

# Existing England children of parent 5
ENG_IDS = [9270, 9271, 9272, 9273, 9274, 9275]
NEW_IDS = [9510, 9511, 9512, 9513, 9514]

# Phase-1 Europe grand-theater canvas (world_map_layers.yaml / MapCanvasConfig BASE_GRAND_SIZE)
EUROPE_BBOX = (-25.0, 28.0, 45.0, 72.0)  # lon_min, lat_min, lon_max, lat_max
CANVAS_SIZE = (5000, 2000)

# City anchors: (lat, lon) WGS84. hw/hh = half-width/height in canvas pixels.
CITY_ANCHORS: dict[int, dict[str, Any]] = {
    9511: {"name": "Aberdeen", "lat": 57.15, "lon": -2.09, "tags": ["SCO"], "owner": "ENG", "hw": 14, "hh": 10, "vp": 2},
    9510: {"name": "Edinburgh", "lat": 55.95, "lon": -3.19, "tags": ["SCO"], "owner": "ENG", "hw": 16, "hh": 10, "vp": 5},
    9512: {"name": "Cardiff", "lat": 51.48, "lon": -3.18, "tags": ["WLS"], "owner": "ENG", "hw": 14, "hh": 12, "vp": 3},
    9272: {"name": "Newcastle", "lat": 54.98, "lon": -1.61, "tags": ["ENG"], "owner": "ENG", "hw": 14, "hh": 10, "vp": 3},
    9271: {"name": "Leeds", "lat": 53.80, "lon": -1.55, "tags": ["ENG"], "owner": "ENG", "hw": 14, "hh": 10, "vp": 4},
    9270: {"name": "Liverpool", "lat": 53.41, "lon": -2.98, "tags": ["ENG"], "owner": "ENG", "hw": 15, "hh": 10, "vp": 4},
    9274: {"name": "Birmingham", "lat": 52.48, "lon": -1.90, "tags": ["ENG"], "owner": "ENG", "hw": 15, "hh": 10, "vp": 8},
    9275: {"name": "London", "lat": 51.51, "lon": -0.13, "tags": ["ENG"], "owner": "ENG", "hw": 16, "hh": 11, "vp": 25},
    9273: {"name": "Southampton", "lat": 50.91, "lon": -1.40, "tags": ["ENG"], "owner": "ENG", "hw": 14, "hh": 10, "vp": 2},
    9513: {"name": "Dublin", "lat": 53.35, "lon": -6.26, "tags": ["IRL"], "owner": "ENG", "hw": 14, "hh": 11, "vp": 8},
    9514: {"name": "Cork", "lat": 51.90, "lon": -8.47, "tags": ["IRL"], "owner": "ENG", "hw": 13, "hh": 10, "vp": 2},
}


def build_layout_from_anchors() -> dict[int, dict[str, Any]]:
    layout: dict[int, dict[str, Any]] = {}
    for pid, spec in CITY_ANCHORS.items():
        cx, cy = lonlat_to_pixel(spec["lon"], spec["lat"], EUROPE_BBOX, CANVAS_SIZE, use_mercator_y=False)
        layout[pid] = {
            "name": spec["name"],
            "tags": spec["tags"],
            "owner": spec["owner"],
            "cx": float(cx),
            "cy": float(cy),
            "hw": spec["hw"],
            "hh": spec["hh"],
            "vp": spec.get("vp", 1),
            "lat": spec["lat"],
            "lon": spec["lon"],
        }
    return layout


LAYOUT = build_layout_from_anchors()


def load_json(path: Path) -> Any:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, obj: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")
    print(f"  Wrote {path.relative_to(ROOT)}")


def quad(cx: float, cy: float, hw: float, hh: float) -> list[list[float]]:
    return [
        [round(cx - hw, 2), round(cy - hh, 2)],
        [round(cx + hw, 2), round(cy - hh, 2)],
        [round(cx + hw, 2), round(cy + hh, 2)],
        [round(cx - hw, 2), round(cy + hh, 2)],
    ]


def centroid(points: list[list[float]]) -> tuple[float, float]:
    return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)


def min_poly_distance(a: list[list[float]], b: list[list[float]]) -> float:
    best = float("inf")
    for pa in a:
        for pb in b:
            d = math.hypot(pa[0] - pb[0], pa[1] - pb[1])
            best = min(best, d)
    for i in range(len(a)):
        ma = [(a[i][0] + a[(i + 1) % len(a)][0]) / 2, (a[i][1] + a[(i + 1) % len(a)][1]) / 2]
        for j in range(len(b)):
            mb = [(b[j][0] + b[(j + 1) % len(b)][0]) / 2, (b[j][1] + b[(j + 1) % len(b)][1]) / 2]
            d = math.hypot(ma[0] - mb[0], ma[1] - mb[1])
            best = min(best, d)
    return best


def rebuild_adjacency(geom_by_id: dict[int, list[list[float]]], touch_dist: float = 12.0) -> dict[str, list[int]]:
    ids = sorted(geom_by_id.keys())
    adj: dict[str, list[int]] = {str(i): [] for i in ids}
    for i, a in enumerate(ids):
        for b in ids[i + 1 :]:
            if min_poly_distance(geom_by_id[a], geom_by_id[b]) <= touch_dist:
                adj[str(a)].append(b)
                adj[str(b)].append(a)
    for k in adj:
        adj[k] = sorted(set(adj[k]))
    return adj


def template_base_entry(pid: int, spec: dict[str, Any], donor: dict[str, Any]) -> dict[str, Any]:
    pop = int(donor.get("population_base", 400000) * (0.55 if pid in NEW_IDS[:2] else 0.45))
    return {
        "id": pid,
        "name": spec["name"],
        "terrain": "urban" if spec["name"] in ("London", "Birmingham", "Dublin", "Edinburgh") else "plains",
        "core_for_tags": spec["tags"],
        "owner_tag": spec["owner"],
        "controller_tag": spec["owner"],
        "natural_resources": deepcopy(donor.get("natural_resources", {"resources": {"coal": 40}, "resource_score": 40, "primary_resource": "coal"})),
        "population_base": max(120000, pop),
        "victory_points": spec.get("vp", 1),
        "special_features": [],
        "special_levels": {},
    }


def layer_entry(donor: dict[str, Any], idx_scale: float = 0.5) -> dict[str, Any]:
    out = deepcopy(donor)
    for key in ("population", "factories", "infrastructure", "development_level"):
        if key in out:
            try:
                out[key] = max(1, int(float(out[key]) * idx_scale))
            except (TypeError, ValueError):
                pass
    return out


def classify_eng_split(cx: float, cy: float) -> int:
    """Match build_curated_strategic_regions.classify_eng_split thresholds."""
    if cy < 760:
        return 3
    if cy >= 905:
        return 1
    return 2


def expected_region(spec: dict[str, Any], cx: float, cy: float) -> int:
    if "SCO" in spec["tags"]:
        return 3
    if "WLS" in spec["tags"]:
        return 4
    if "IRL" in spec["tags"]:
        return 5
    if "ENG" in spec["tags"]:
        return classify_eng_split(cx, cy)
    return -1


def main() -> None:
    geo_path = DATA / "provinces_geometry.json"
    base_path = DATA / "provinces_base.json"
    adj_path = DATA / "province_adjacency.json"

    geo_data = load_json(geo_path)
    base_data = load_json(base_path)
    adj_data = load_json(adj_path)

    geo_list: list[dict] = geo_data["provinces"]
    geo_by_id = {p["id"]: p for p in geo_list}
    base_by_id = {p["id"]: p for p in base_data["provinces"]}
    donor_eng = base_by_id.get(9275, base_by_id.get(9270, {}))

    # Snapshot before centroids for summary
    before_centroids: dict[int, tuple[float, float]] = {}
    for pid in LAYOUT:
        if pid in geo_by_id and geo_by_id[pid].get("points"):
            before_centroids[pid] = centroid(geo_by_id[pid]["points"])

    new_geom: dict[int, list[list[float]]] = {}

    for pid, spec in LAYOUT.items():
        pts = quad(spec["cx"], spec["cy"], spec["hw"], spec["hh"])
        new_geom[pid] = pts
        if pid in geo_by_id:
            geo_by_id[pid]["points"] = pts
            geo_by_id[pid]["label_anchor"] = [spec["cx"], spec["cy"]]
            geo_by_id[pid]["notes"] = (
                f"British Isles carve v2 — lon/lat anchor ({spec['lat']:.2f}N, {spec['lon']:.2f}E)"
            )
            if pid in NEW_IDS:
                geo_by_id[pid]["parent_id"] = 5
        else:
            geo_list.append(
                {
                    "id": pid,
                    "parent_id": 5,
                    "points": pts,
                    "label_anchor": [spec["cx"], spec["cy"]],
                    "notes": f"British Isles carve v2 — new province ({spec['lat']:.2f}N, {spec['lon']:.2f}E)",
                    "river_aware": False,
                }
            )
            geo_by_id[pid] = geo_list[-1]

        if pid in base_by_id:
            base_by_id[pid]["name"] = spec["name"]
            base_by_id[pid]["core_for_tags"] = spec["tags"]
            base_by_id[pid]["owner_tag"] = spec["owner"]
            base_by_id[pid]["controller_tag"] = spec["owner"]
            base_by_id[pid]["victory_points"] = spec.get("vp", base_by_id[pid].get("victory_points", 1))
        else:
            base_data["provinces"].append(template_base_entry(pid, spec, donor_eng))
            base_by_id[pid] = base_data["provinces"][-1]

    geo_data["provinces"] = sorted(geo_list, key=lambda p: p["id"])
    geo_data["meta"]["british_isles_carve"] = "v2_lonlat_anchored"
    geo_data["meta"]["british_isles_bbox"] = list(EUROPE_BBOX)
    geo_data["meta"]["british_isles_canvas"] = list(CANVAS_SIZE)
    save_json(geo_path, geo_data)

    base_data["provinces"] = sorted(base_data["provinces"], key=lambda p: p["id"])
    save_json(base_path, base_data)

    for layer_file, inner_key in [
        ("province_economy_layer.json", "provinces"),
        ("province_terrain_layer.json", "provinces"),
        ("province_resources_layer.json", "provinces"),
    ]:
        lp = DATA / layer_file
        if not lp.exists():
            continue
        layer = load_json(lp)
        prov_map = layer.get(inner_key, layer)
        donor_key = "9275"
        donor_layer = prov_map.get(donor_key, prov_map.get("9275", {}))
        for pid in NEW_IDS:
            key = str(pid)
            if key not in prov_map and donor_layer:
                prov_map[key] = layer_entry(donor_layer, 0.45 if pid in (9511, 9514) else 0.55)
        save_json(lp, layer)

    all_geom = {p["id"]: p["points"] for p in geo_data["provinces"]}
    adj_data["adjacency"] = rebuild_adjacency(all_geom, touch_dist=10.0)
    adj_data["_british_isles_carve"] = "v2"
    save_json(adj_path, adj_data)

    print("\n=== British Isles QC (inline) ===")
    print(f"  BBox lon {EUROPE_BBOX[0]}..{EUROPE_BBOX[2]}, lat {EUROPE_BBOX[1]}..{EUROPE_BBOX[3]}")
    print(f"  Canvas {CANVAS_SIZE[0]}×{CANVAS_SIZE[1]} (linear lat, y=0 north)")

    for pid in sorted(LAYOUT.keys()):
        spec = LAYOUT[pid]
        pts = new_geom[pid]
        cx, cy = centroid(pts)
        rid = expected_region(spec, cx, cy)
        before = before_centroids.get(pid)
        before_s = f"was ({before[0]:.0f},{before[1]:.0f})" if before else "new"
        print(
            f"  {pid:5} {spec['name']:<12} ({cx:6.0f},{cy:5.0f}) "
            f"anchor {spec['lat']:.2f}N {spec['lon']:.2f}E  {before_s}  region={rid}"
        )

    eng_order = sorted(ENG_IDS, key=lambda p: centroid(new_geom[p])[1])
    print("\n  England north→south (by cy):", " → ".join(LAYOUT[p]["name"] for p in eng_order))

    liv_pts = new_geom[9270]
    dub_pts = new_geom[9513]
    sea_gap = min_poly_distance(liv_pts, dub_pts)
    adj_liv = adj_data["adjacency"].get("9270", [])
    adj_dub = adj_data["adjacency"].get("9513", [])
    print(f"\n  Irish Sea: Liverpool↔Dublin min_dist={sea_gap:.1f}px adjacent={9513 in adj_liv}")
    if 9513 in adj_liv:
        print("  WARNING: Dublin adjacent to Liverpool — widen Irish Sea gap")

    print("  Done. Run build_curated_strategic_regions.py + qc_british_isles_geography.py next.")


if __name__ == "__main__":
    main()
