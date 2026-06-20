#!/usr/bin/env python3
"""Reposition + expand British Isles provinces on the phase1 Europe canvas.

Fixes compressed 6-blob UK: adds Scotland, Wales, Ireland provinces and places
England city names at geographically consistent canvas positions (north→south,
west→east). Regenerates adjacency for touched provinces and strategic regions.

Run from repo root:
  python3 tools/map_generation/carve_british_isles_provinces.py
  python3 tools/map_generation/build_curated_strategic_regions.py
"""
from __future__ import annotations

import json
import math
from copy import deepcopy
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "provinces_phase1_test"

# Existing England children of parent 5
ENG_IDS = [9270, 9271, 9272, 9273, 9274, 9275]
NEW_IDS = [9510, 9511, 9512, 9513, 9514]

# Canvas layout (5000×2000 pre-theater-scale coords). Lower Y ≈ north.
LAYOUT: dict[int, dict[str, Any]] = {
    # Scotland (cy < 410)
    9511: {"name": "Aberdeen", "tags": ["SCO"], "owner": "ENG", "cx": 2075, "cy": 398, "hw": 14, "hh": 10, "vp": 2},
    9510: {"name": "Edinburgh", "tags": ["SCO"], "owner": "ENG", "cx": 2045, "cy": 405, "hw": 16, "hh": 10, "vp": 5},
    # Wales (west)
    9512: {"name": "Cardiff", "tags": ["WLS"], "owner": "ENG", "cx": 1998, "cy": 432, "hw": 14, "hh": 12, "vp": 3},
    # Northern England — north→south order on canvas
    9272: {"name": "Newcastle", "tags": ["ENG"], "owner": "ENG", "cx": 2068, "cy": 418, "hw": 14, "hh": 10, "vp": 3},
    9271: {"name": "Leeds", "tags": ["ENG"], "owner": "ENG", "cx": 2045, "cy": 420, "hw": 14, "hh": 10, "vp": 4},
    9270: {"name": "Liverpool", "tags": ["ENG"], "owner": "ENG", "cx": 2022, "cy": 422, "hw": 15, "hh": 10, "vp": 4},
    # Midlands + south
    9274: {"name": "Birmingham", "tags": ["ENG"], "owner": "ENG", "cx": 2040, "cy": 437, "hw": 15, "hh": 10, "vp": 8},
    9275: {"name": "London", "tags": ["ENG"], "owner": "ENG", "cx": 2055, "cy": 446, "hw": 16, "hh": 11, "vp": 25},
    9273: {"name": "Southampton", "tags": ["ENG"], "owner": "ENG", "cx": 2068, "cy": 458, "hw": 14, "hh": 10, "vp": 2},
    # Ireland (west island — separated from Wales/Liverpool by Irish Sea gap)
    9513: {"name": "Dublin", "tags": ["IRL"], "owner": "ENG", "cx": 1968, "cy": 448, "hw": 14, "hh": 11, "vp": 8},
    9514: {"name": "Cork", "tags": ["IRL"], "owner": "ENG", "cx": 1960, "cy": 462, "hw": 13, "hh": 10, "vp": 2},
}


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
    # edge midpoints rough
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


def merge_adjacency(existing: dict[str, list[int]], rebuilt: dict[str, list[int]], touched: set[int]) -> dict[str, list[int]]:
    out = deepcopy(existing)
    for pid in touched:
        key = str(pid)
        out[key] = rebuilt.get(key, [])
    # Neighbors of touched may need refresh too
    refresh: set[int] = set(touched)
    for pid in touched:
        for n in existing.get(str(pid), []):
            refresh.add(int(n))
    for pid in refresh:
        key = str(pid)
        if key in rebuilt:
            out[key] = rebuilt[key]
    return out


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

    touched: set[int] = set(LAYOUT.keys())
    new_geom: dict[int, list[list[float]]] = {}

    for pid, spec in LAYOUT.items():
        pts = quad(spec["cx"], spec["cy"], spec["hw"], spec["hh"])
        new_geom[pid] = pts
        if pid in geo_by_id:
            geo_by_id[pid]["points"] = pts
            geo_by_id[pid]["label_anchor"] = [spec["cx"], spec["cy"]]
            geo_by_id[pid]["notes"] = "British Isles carve v1 — geo-aligned placement"
            if pid in NEW_IDS:
                geo_by_id[pid]["parent_id"] = 5
        else:
            geo_list.append(
                {
                    "id": pid,
                    "parent_id": 5,
                    "points": pts,
                    "label_anchor": [spec["cx"], spec["cy"]],
                    "notes": "British Isles carve v1 — new province",
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
    geo_data["meta"]["british_isles_carve"] = "v1_geo_aligned"
    save_json(geo_path, geo_data)

    base_data["provinces"] = sorted(base_data["provinces"], key=lambda p: p["id"])
    save_json(base_path, base_data)

    # Layers for new provinces
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

    # Rebuild full land adjacency from geometry (authoritative for carve)
    all_geom = {p["id"]: p["points"] for p in geo_data["provinces"]}
    adj_data["adjacency"] = rebuild_adjacency(all_geom, touch_dist=10.0)
    adj_data["_british_isles_carve"] = "v1"
    save_json(adj_path, adj_data)

    print("\n=== British Isles QC ===")

    def classify_eng_split(cx: float, cy: float) -> int:
        if cy < 410:
            return 3
        if cx < 2008 and 418 <= cy <= 472:
            return 4
        if cx < 1995 and cy >= 400:
            return 5
        if cy >= 436:
            return 1
        return 2

    for pid in sorted(LAYOUT.keys()):
        spec = LAYOUT[pid]
        pts = new_geom[pid]
        cx, cy = centroid(pts)
        if "SCO" in spec["tags"]:
            exp = 3
        elif "WLS" in spec["tags"]:
            exp = 4
        elif "IRL" in spec["tags"]:
            exp = 5
        elif "ENG" in spec["tags"]:
            exp = classify_eng_split(cx, cy)
        else:
            exp = -1
        print(f"  {pid:5} {spec['name']:<12} ({cx:6.0f},{cy:5.0f}) tags={spec['tags']} region_id={exp}")

    eng_order = sorted(ENG_IDS, key=lambda p: centroid(new_geom[p])[1])
    print("\n  England north→south:", " → ".join(LAYOUT[p]["name"] for p in eng_order))
    print("  Done. Run build_curated_strategic_regions.py next.")


if __name__ == "__main__":
    main()
