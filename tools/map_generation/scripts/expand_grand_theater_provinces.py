#!/usr/bin/env python3
"""Build data/provinces_grand_theater from densified Europe + multi-theater seeds.

Copies provinces_full_europe layers, then appends land/sea/island seed provinces
for MENA, North Africa, Far East stubs, Pacific critical islands, and sea zones.
Applies island_viability facility tiers.

Usage:
  python3 tools/map_generation/scripts/expand_grand_theater_provinces.py [--write]
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from island_viability import classify_island, polygon_area  # noqa: E402

# Canvas fit (same as assign_europe_province_names)
_X_COEF = (11.3987280, -0.812649346, 2081.84412)
_Y_COEF = (-0.0681278226, -10.9240726, 1004.31052)

SOURCE_DIR = ROOT / "data" / "provinces_full_europe"
OUT_DIR = ROOT / "data" / "provinces_grand_theater"
ID_BASE = 20000  # expansion id space


def lonlat_to_canvas(lon: float, lat: float) -> Tuple[float, float]:
    x = _X_COEF[0] * lon + _X_COEF[1] * lat + _X_COEF[2]
    y = _Y_COEF[0] * lon + _Y_COEF[1] * lat + _Y_COEF[2]
    return x, y


def make_cell_polygon(cx: float, cy: float, half: float = 28.0) -> List[List[float]]:
    """Axis-aligned diamond-ish hex for visibility (6 points)."""
    return [
        [cx, cy - half],
        [cx + half * 0.85, cy - half * 0.4],
        [cx + half * 0.85, cy + half * 0.4],
        [cx, cy + half],
        [cx - half * 0.85, cy + half * 0.4],
        [cx - half * 0.85, cy - half * 0.4],
    ]


def make_sea_polygon(cx: float, cy: float, half: float = 55.0) -> List[List[float]]:
    """Larger sea zone cell."""
    return make_cell_polygon(cx, cy, half=half)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def seed_defs() -> List[Dict[str, Any]]:
    """Hardcoded seeds (mirrors grand_theater.yaml expansion_seeds)."""
    seeds: List[Dict[str, Any]] = []
    mena = [
        ("Cairo", 31.2, 30.0, "coastal_land", "mainland", False),
        ("Alexandria Coast", 29.9, 31.2, "coastal_land", "mainland", False),
        ("Suez", 32.5, 30.0, "coastal_land", "mainland", False),
        ("Jerusalem Theater", 35.2, 31.8, "coastal_land", "mainland", False),
        ("Damascus Theater", 36.3, 33.5, "land", "mainland", False),
        ("Baghdad Theater", 44.4, 33.3, "land", "mainland", False),
        ("Basra", 47.8, 30.5, "coastal_land", "mainland", False),
        ("Riyadh Heartland", 46.7, 24.7, "land", "mainland", False),
        ("Jeddah", 39.2, 21.5, "coastal_land", "mainland", False),
        ("Tehran Theater", 51.4, 35.7, "land", "mainland", False),
        ("Isfahan", 51.7, 32.7, "land", "mainland", False),
        ("Ankara Deep", 32.9, 39.9, "land", "mainland", False),
        ("Izmir Coast", 27.1, 38.4, "coastal_land", "mainland", False),
        ("Tripoli Maghreb", 13.2, 32.9, "coastal_land", "mainland", False),
        ("Tunis", 10.2, 36.8, "coastal_land", "mainland", False),
        ("Algiers", 3.1, 36.8, "coastal_land", "mainland", False),
        ("Casablanca", -7.6, 33.6, "coastal_land", "mainland", False),
        ("Oran", -0.6, 35.7, "coastal_land", "mainland", False),
        ("Benghazi", 20.1, 32.1, "coastal_land", "mainland", False),
        ("Khartoum", 32.5, 15.5, "land", "mainland", False),
        ("Addis Ababa", 38.7, 9.0, "land", "mainland", False),
        ("Mombasa", 39.7, -4.0, "coastal_land", "mainland", False),
        ("Lagos Coast", 3.4, 6.5, "coastal_land", "mainland", False),
        ("Cape Town", 18.4, -33.9, "coastal_land", "mainland", False),
        ("Durban", 31.0, -29.9, "coastal_land", "mainland", False),
        # Ring cells around key hubs for army depth
        ("Nile Delta East", 32.0, 30.8, "coastal_land", "mainland", False),
        ("Sinai", 33.8, 30.0, "land", "mainland", False),
        ("Levant Coast", 35.5, 33.0, "coastal_land", "mainland", False),
        ("Upper Egypt", 32.5, 26.0, "land", "mainland", False),
        ("Western Desert", 27.0, 30.0, "land", "mainland", False),
        ("Cyrenaica", 21.0, 32.0, "coastal_land", "mainland", False),
        ("Fezzan", 15.0, 26.0, "land", "mainland", False),
        ("Atlas Interior", 0.0, 33.0, "land", "mainland", False),
        ("Morocco South", -8.0, 30.0, "land", "mainland", False),
        ("Kuwait", 47.9, 29.3, "coastal_land", "mainland", False),
        ("Mosul", 43.1, 36.3, "land", "mainland", False),
        ("Aleppo", 37.1, 36.2, "land", "mainland", False),
        ("Amman", 35.9, 31.9, "land", "mainland", False),
        ("Muscat", 58.5, 23.6, "coastal_land", "mainland", False),
        ("Aden", 45.0, 12.8, "coastal_land", "mainland", False),
        ("Hormuz Coast", 56.3, 27.1, "coastal_land", "mainland", False),
        ("Shiraz", 52.5, 29.6, "land", "mainland", False),
        ("Tabriz", 46.3, 38.1, "land", "mainland", False),
        ("Kabul Approaches", 69.2, 34.5, "land", "mainland", False),
        ("Karachi", 67.0, 24.9, "coastal_land", "mainland", False),
        ("Delhi Theater", 77.2, 28.6, "land", "mainland", False),
        ("Bombay Coast", 72.9, 19.1, "coastal_land", "mainland", False),
        ("Calcutta", 88.4, 22.6, "coastal_land", "mainland", False),
        ("Madras Coast", 80.3, 13.1, "coastal_land", "mainland", False),
    ]
    for name, lon, lat, domain, ic, crit in mena:
        seeds.append(
            {
                "name": name,
                "lon": lon,
                "lat": lat,
                "domain": domain,
                "island_class": ic,
                "critical": crit,
                "theater": "mena_africa",
                "half": 26.0,
            }
        )

    far = [
        ("Shanghai Coast", 121.5, 31.2, "coastal_land", "mainland", False),
        ("Beijing Theater", 116.4, 39.9, "land", "mainland", False),
        ("Guangzhou", 113.3, 23.1, "coastal_land", "mainland", False),
        ("Wuhan", 114.3, 30.6, "land", "mainland", False),
        ("Manchuria South", 123.4, 41.8, "land", "mainland", False),
        ("Manila", 121.0, 14.6, "coastal_land", "large", False),
        ("Singapore", 103.8, 1.3, "coastal_land", "medium", True),
        ("Jakarta", 106.8, -6.2, "coastal_land", "large", False),
        ("Saigon", 106.7, 10.8, "coastal_land", "mainland", False),
        ("Hanoi", 105.8, 21.0, "coastal_land", "mainland", False),
        ("Bangkok", 100.5, 13.8, "coastal_land", "mainland", False),
        ("Rangoon", 96.2, 16.8, "coastal_land", "mainland", False),
        ("Tokyo Theater", 139.7, 35.7, "coastal_land", "large", False),
        ("Osaka", 135.5, 34.7, "coastal_land", "large", False),
        ("Seoul Theater", 127.0, 37.6, "coastal_land", "mainland", False),
        ("Taiwan North", 121.5, 25.0, "coastal_land", "large", False),
        ("Hong Kong Approaches", 114.2, 22.3, "coastal_land", "medium", True),
        ("Vladivostok", 131.9, 43.1, "coastal_land", "mainland", False),
        ("Harbin", 126.6, 45.8, "land", "mainland", False),
        ("Chongqing", 106.5, 29.6, "land", "mainland", False),
        ("Kunming", 102.7, 25.0, "land", "mainland", False),
        ("Hainan", 109.5, 19.2, "coastal_land", "medium", False),
        ("Borneo North", 116.0, 6.0, "coastal_land", "large", False),
        ("New Guinea North", 147.0, -5.0, "coastal_land", "large", False),
        ("Australia Darwin", 130.8, -12.5, "coastal_land", "mainland", False),
        ("Australia Sydney", 151.2, -33.9, "coastal_land", "mainland", False),
        ("New Zealand North", 174.8, -36.8, "coastal_land", "large", False),
    ]
    for name, lon, lat, domain, ic, crit in far:
        seeds.append(
            {
                "name": name,
                "lon": lon,
                "lat": lat,
                "domain": domain,
                "island_class": ic,
                "critical": crit,
                "theater": "far_east",
                "half": 30.0,
            }
        )

    pacific = [
        ("Midway", -177.4, 28.2, "coastal_land", "micro", True, 18.0),
        ("Guam", 144.8, 13.4, "coastal_land", "small", True, 22.0),
        ("Wake", 166.6, 19.3, "coastal_land", "micro", True, 16.0),
        ("Hawaii Oahu", -157.9, 21.3, "coastal_land", "medium", True, 28.0),
        ("Solomon Islands", 160.0, -9.0, "coastal_land", "small", False, 22.0),
        ("New Caledonia", 166.5, -22.3, "coastal_land", "medium", False, 24.0),
        ("Saipan", 145.7, 15.2, "coastal_land", "small", True, 20.0),
        ("Iwo Jima", 141.3, 24.8, "coastal_land", "micro", True, 15.0),
        ("Tarawa", 173.0, 1.4, "coastal_land", "micro", True, 14.0),
        ("Rabaul", 152.2, -4.2, "coastal_land", "medium", False, 24.0),
    ]
    for name, lon, lat, domain, ic, crit, half in pacific:
        seeds.append(
            {
                "name": name,
                "lon": lon,
                "lat": lat,
                "domain": domain,
                "island_class": ic,
                "critical": crit,
                "theater": "pacific",
                "half": half,
            }
        )

    seas = [
        ("North Sea Zone", 3.0, 56.0, "sea", 60),
        ("English Channel Zone", 1.0, 50.5, "strait", 40),
        ("Baltic Sea Zone", 19.0, 56.0, "sea", 55),
        ("Western Mediterranean", 5.0, 39.0, "sea", 58),
        ("Central Mediterranean", 15.0, 36.0, "sea", 58),
        ("Eastern Mediterranean", 28.0, 34.0, "sea", 58),
        ("Black Sea Zone", 34.0, 43.0, "sea", 55),
        ("Red Sea Zone", 38.0, 20.0, "sea", 50),
        ("Persian Gulf Zone", 52.0, 27.0, "sea", 45),
        ("Arabian Sea Zone", 60.0, 18.0, "sea", 70),
        ("Bay of Bengal Zone", 90.0, 15.0, "sea", 70),
        ("South China Sea Zone", 114.0, 12.0, "sea", 65),
        ("East China Sea Zone", 125.0, 30.0, "sea", 55),
        ("Sea of Japan Zone", 135.0, 40.0, "sea", 50),
        ("Philippine Sea Zone", 135.0, 18.0, "sea", 70),
        ("Coral Sea Zone", 155.0, -15.0, "sea", 70),
        ("Central Pacific Zone", -170.0, 15.0, "sea", 80),
        ("North Atlantic Zone", -30.0, 50.0, "sea", 80),
        ("Mid Atlantic Zone", -30.0, 30.0, "sea", 80),
        ("Gibraltar Strait Zone", -5.5, 36.0, "strait", 35),
        ("Bosporus Approaches", 29.0, 41.1, "strait", 32),
        ("Suez Canal Zone", 32.3, 30.5, "strait", 32),
        ("Hormuz Approaches", 56.5, 26.5, "strait", 32),
        ("Malacca Strait Zone", 100.0, 3.0, "strait", 40),
        ("Tsushima Strait Zone", 129.5, 34.5, "strait", 35),
        ("Danish Straits Zone", 12.0, 55.5, "strait", 35),
        ("Indian Ocean Central", 70.0, -10.0, "sea", 85),
        ("South Atlantic Zone", -10.0, -20.0, "sea", 80),
        ("Caribbean Zone", -70.0, 15.0, "sea", 60),
        ("Gulf of Mexico Zone", -90.0, 25.0, "sea", 55),
    ]
    for name, lon, lat, domain, half in seas:
        seeds.append(
            {
                "name": name,
                "lon": lon,
                "lat": lat,
                "domain": domain,
                "island_class": "none",
                "critical": False,
                "theater": "sea",
                "half": float(half),
            }
        )
    # Extra blue-water grid for naval room (raise sea share toward design band)
    ocean_grid = []
    # Pacific grid
    for lon in range(-170, -120, 15):
        for lat in range(0, 40, 12):
            ocean_grid.append((f"Pacific {lon}E {lat}N", float(lon), float(lat), 75))
    for lon in range(130, 180, 15):
        for lat in range(-20, 40, 12):
            ocean_grid.append((f"WestPac {lon}E {lat}N", float(lon), float(lat), 70))
    # Atlantic
    for lon in range(-50, -5, 12):
        for lat in range(-30, 55, 14):
            ocean_grid.append((f"Atlantic {lon}E {lat}N", float(lon), float(lat), 75))
    # Indian
    for lon in range(50, 100, 12):
        for lat in range(-30, 20, 12):
            ocean_grid.append((f"Indian {lon}E {lat}N", float(lon), float(lat), 70))
    # Med/Black densify coastal seas
    for lon, lat, n in [
        (9, 42, "Ligurian Sea"), (12, 40, "Tyrrhenian Sea"), (18, 40, "Adriatic Sea"),
        (25, 36, "Aegean Sea"), (32, 44, "Black Sea East"), (28, 42, "Black Sea West"),
        (5, 55, "North Sea West"), (8, 58, "Norwegian Sea"), (-5, 48, "Bay of Biscay"),
        (0, 36, "Alboran Sea"), (20, 34, "Ionian Sea"), (30, 32, "Levantine Sea"),
    ]:
        ocean_grid.append((n, float(lon), float(lat), 48))
    for name, lon, lat, half in ocean_grid:
        seeds.append({
            "name": name,
            "lon": lon,
            "lat": lat,
            "domain": "sea",
            "island_class": "none",
            "critical": False,
            "theater": "sea",
            "half": float(half),
        })
    # Satellite cells around hubs for army depth (HOI4-like front width)
    satellites = []
    for s in list(seeds):
        if s.get("domain") in ("sea", "strait"):
            continue
        if s.get("theater") not in ("mena_africa", "far_east"):
            continue
        lon, lat = float(s["lon"]), float(s["lat"])
        for i, (dlon, dlat) in enumerate(
            [(1.2, 0.0), (-1.2, 0.0), (0.0, 1.0), (0.0, -1.0), (0.9, 0.9), (-0.9, -0.9)]
        ):
            satellites.append(
                {
                    "name": f"{s['name']} Sector {chr(65+i)}",
                    "lon": lon + dlon,
                    "lat": lat + dlat,
                    "domain": s["domain"],
                    "island_class": s.get("island_class", "mainland"),
                    "critical": False,
                    "theater": s.get("theater"),
                    "half": max(18.0, float(s.get("half", 26.0)) * 0.75),
                }
            )
    seeds.extend(satellites)
    return seeds


def build_expansion_entries(
    start_id: int,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], Dict[str, Any], List[Dict[str, Any]]]:
    """Returns base_entries, geom_entries, terrain_map, economy snippets."""
    base_out: List[Dict[str, Any]] = []
    geom_out: List[Dict[str, Any]] = []
    terrain: Dict[str, Any] = {}
    excluded: List[Dict[str, Any]] = []
    pid = start_id
    for seed in seed_defs():
        cx, cy = lonlat_to_canvas(float(seed["lon"]), float(seed["lat"]))
        half = float(seed.get("half", 28.0))
        domain = str(seed["domain"])
        if domain in ("sea", "strait", "lake"):
            pts = make_sea_polygon(cx, cy, half=half)
        else:
            pts = make_cell_polygon(cx, cy, half=half)
        area = polygon_area(pts)
        # Scale area for micro islands: small half → small area → viability rules fire
        viability = classify_island(
            area,
            domain=domain,
            critical=bool(seed.get("critical")),
            explicit_class=seed.get("island_class"),
        )
        if not viability["keep_as_province"]:
            excluded.append({"name": seed["name"], "reason": viability["reason"], "area": area})
            continue

        entry = {
            "id": pid,
            "name": seed["name"],
            "terrain": "sea" if domain in ("sea", "strait") else "plains",
            "core_for_tags": [],
            "natural_resources": {},
            "population_base": 0 if domain in ("sea", "strait") else 500000,
            "special_features": [],
            "special_levels": {},
            "domain": viability["domain"] if domain not in ("sea", "strait") else domain,
            "island_class": viability["island_class"],
            "facility_tier": viability["facility_tier"],
            "theater": seed.get("theater", "unknown"),
            "naval_importance": 10 if domain == "strait" else (3 if domain == "sea" else 0),
        }
        if domain == "strait":
            entry["special_features"] = ["strait", "chokepoint"]
        if seed.get("critical"):
            entry["special_features"] = list(set(entry.get("special_features", []) + ["critical_island"]))

        geom_entry = {
            "id": pid,
            "points": pts,
            "label_anchor": [cx, cy],
        }
        base_out.append(entry)
        geom_out.append(geom_entry)
        terrain[str(pid)] = {
            "terrain": entry["terrain"],
            "movement_cost": 0.5 if domain in ("sea", "strait") else 1.0,
            "height_proxy": 0.0,
            "veg_strength": 0.0,
            "snow_potential": 0.0,
            "source": "grand_theater_expand",
            "domain": entry["domain"],
            "island_class": entry["island_class"],
            "facility_tier": entry["facility_tier"],
        }
        pid += 1
    return base_out, geom_out, terrain, excluded


def merge_layers(
    source: Path,
    out: Path,
    new_base: List[Dict[str, Any]],
    new_geom: List[Dict[str, Any]],
    new_terrain: Dict[str, Any],
) -> Dict[str, Any]:
    base = load_json(source / "provinces_base.json")
    geom = load_json(source / "provinces_geometry.json")
    # Tag existing Europe provinces with facility metadata if missing
    for p in base["provinces"]:
        if "domain" not in p:
            p["domain"] = "land"
        if "island_class" not in p:
            p["island_class"] = "mainland"
        if "facility_tier" not in p:
            p["facility_tier"] = "full"
        if "theater" not in p:
            p["theater"] = "europe_core"

    base["provinces"] = list(base["provinces"]) + new_base
    geom["provinces"] = list(geom["provinces"]) + new_geom
    meta_b = dict(base.get("meta") or {})
    meta_b["grand_theater"] = True
    meta_b["province_count"] = len(base["provinces"])
    meta_b["expansion_added"] = len(new_base)
    meta_b["source"] = "expand_grand_theater_provinces.py"
    base["meta"] = meta_b
    meta_g = dict(geom.get("meta") or {})
    meta_g["grand_theater"] = True
    meta_g["total"] = len(geom["provinces"])
    meta_g["expansion_added"] = len(new_geom)
    geom["meta"] = meta_g

    # Adjacency: copy + connect new seeds to nearest existing centroid (weak but playable)
    adj_path = source / "province_adjacency.json"
    adj = load_json(adj_path) if adj_path.exists() else {"adjacency": {}}
    adjacency: Dict[str, List[int]] = {
        str(k): list(v) for k, v in (adj.get("adjacency") or {}).items()
    }

    # Build centroid index for nearest-neighbor adjacency of new nodes
    cents: Dict[int, Tuple[float, float]] = {}
    for g in geom["provinces"]:
        pts = g["points"]
        cents[int(g["id"])] = (
            sum(p[0] for p in pts) / len(pts),
            sum(p[1] for p in pts) / len(pts),
        )

    new_ids = [int(p["id"]) for p in new_base]
    all_ids = list(cents.keys())
    for nid in new_ids:
        cx, cy = cents[nid]
        # nearest 3 existing (prefer europe + new)
        ranked = sorted(
            (oid for oid in all_ids if oid != nid),
            key=lambda oid: (cents[oid][0] - cx) ** 2 + (cents[oid][1] - cy) ** 2,
        )[:3]
        adjacency[str(nid)] = ranked
        for oid in ranked:
            key = str(oid)
            if key not in adjacency:
                adjacency[key] = []
            if nid not in adjacency[key]:
                adjacency[key].append(nid)

    # Terrain layer
    terr_path = source / "province_terrain_layer.json"
    if terr_path.exists():
        terr = load_json(terr_path)
        # normalize to provinces dict
        if "provinces" in terr and isinstance(terr["provinces"], dict):
            tmap = terr["provinces"]
        elif "province_terrain_layer" in terr:
            # weird schema
            tmap = terr.get("provinces") or {}
        else:
            tmap = {}
        for k, v in new_terrain.items():
            tmap[k] = v
        terr["provinces"] = tmap
        terr["count"] = len(tmap)
        terr["source"] = "grand_theater_expand"
    else:
        terr = {"version": 1, "provinces": new_terrain, "count": len(new_terrain)}

    # Copy other layers shallowly and extend empty dicts for new ids
    def extend_dict_layer(name: str, default_factory) -> Any:
        p = source / name
        if not p.exists():
            return {"provinces": {str(x["id"]): default_factory() for x in new_base}}
        data = load_json(p)
        key = "provinces" if "provinces" in data else None
        if key and isinstance(data[key], dict):
            for e in new_base:
                sid = str(e["id"])
                if sid not in data[key]:
                    data[key][sid] = default_factory()
        return data

    economy = extend_dict_layer(
        "province_economy_layer.json",
        lambda: {"development_level": 2, "infrastructure": 2, "factories": 0},
    )
    resources = extend_dict_layer("province_resources_layer.json", lambda: {})
    cities = extend_dict_layer("province_city_layer.json", lambda: {"cities": []})
    states = load_json(source / "province_states.json") if (source / "province_states.json").exists() else {"states": []}

    # Naval chokepoints from strait domains
    choke_ids = [int(p["id"]) for p in new_base if p.get("domain") == "strait"]
    # plus any existing
    old_choke = source / "naval_chokepoints.json"
    if old_choke.exists():
        oc = load_json(old_choke)
        choke_ids = list(dict.fromkeys(list(oc.get("chokepoint_province_ids") or []) + choke_ids))

    stats = {
        "total": len(base["provinces"]),
        "added": len(new_base),
        "europe_base": len(base["provinces"]) - len(new_base),
        "sea_or_strait": sum(1 for p in base["provinces"] if p.get("domain") in ("sea", "strait")),
        "landish": sum(1 for p in base["provinces"] if p.get("domain") not in ("sea", "strait")),
    }

    # Write
    out.mkdir(parents=True, exist_ok=True)
    write_json(out / "provinces_base.json", base)
    write_json(out / "provinces_geometry.json", geom)
    write_json(out / "province_adjacency.json", {"adjacency": adjacency})
    write_json(out / "province_terrain_layer.json", terr)
    write_json(out / "province_economy_layer.json", economy)
    write_json(out / "province_resources_layer.json", resources)
    write_json(out / "province_city_layer.json", cities)
    write_json(out / "province_states.json", states)
    write_json(
        out / "naval_chokepoints.json",
        {
            "meta": {"source": "expand_grand_theater_provinces.py"},
            "chokepoint_province_ids": choke_ids,
        },
    )
    # Copy strategic regions then rebuild will refresh
    if (source / "strategic_regions.json").exists():
        shutil.copy2(source / "strategic_regions.json", out / "strategic_regions.json")
    if (source / "project_sites.json").exists():
        shutil.copy2(source / "project_sites.json", out / "project_sites.json")

    write_json(out / "manifest_grand_theater.json", {
        "phase": "grand_theater_v1",
        "stats": stats,
        "id_base_expansion": ID_BASE,
        "source_europe": str(source.relative_to(ROOT)),
    })
    return stats


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--source", default=str(SOURCE_DIR.relative_to(ROOT)))
    ap.add_argument("--out", default=str(OUT_DIR.relative_to(ROOT)))
    args = ap.parse_args(argv)
    source = ROOT / args.source
    out = ROOT / args.out
    write = bool(args.write) and not args.dry_run

    new_base, new_geom, new_terr, excluded = build_expansion_entries(ID_BASE)
    print(f"Expansion candidates kept: {len(new_base)}, excluded micros: {len(excluded)}")
    for e in excluded[:10]:
        print(f"  exclude {e['name']}: {e['reason']} area={e['area']:.1f}")

    if not write:
        total = len(load_json(source / "provinces_base.json")["provinces"]) + len(new_base)
        sea = sum(1 for p in new_base if p.get("domain") in ("sea", "strait"))
        print(f"[DRY-RUN] would produce total≈{total} (added {len(new_base)}, sea/strait new {sea})")
        print(f"  out={out}")
        ok = total >= 700 and len(new_base) >= 80
        print("PASS dry-run gates" if ok else "FAIL dry-run gates", file=sys.stdout if ok else sys.stderr)
        return 0 if ok else 1

    stats = merge_layers(source, out, new_base, new_geom, new_terr)
    print(f"[WROTE] {out} stats={stats}")

    # Post-process: densify new geometry only would re-densify all — run densify script
    # Regions rebuild
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))
    from densify_province_geometry import run_on_dir as densify_dir  # type: ignore
    from rebuild_strategic_regions import run_on_dir as regions_dir  # type: ignore

    dstat = densify_dir(out, write=True, max_edge=16.0, min_vertices=10)
    print("  densify:", dstat["after"])
    rstat = regions_dir(out, write=True, k=18, seed=7)
    print("  regions:", rstat["gates"])

    ok = stats["total"] >= 700 and rstat["gates"]["full_coverage"]
    print("PASS grand theater v1" if ok else "FAIL grand theater v1", file=sys.stdout if ok else sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
