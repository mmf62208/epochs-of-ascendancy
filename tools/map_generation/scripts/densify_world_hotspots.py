#!/usr/bin/env python3
"""Add land density in under-covered world theaters.

Wave 1: China, India, US East, Brazil.
Wave 2: Sub-Saharan Africa, SE Asia, Pacific island chains, Andes/Southern Cone,
        Central Asia, Oceania, West Africa — not Europe rework.
Wave 3: MENA depth, US West/Mexico, more Africa interior, Korea/Japan coast,
        more Pacific/Oceania — push toward ≥2200 board (not Europe rework).

Appends satellite provinces around named hubs in provinces_world_full,
using world equirectangular canvas. Preserves world-native meta.

Usage:
  python3 tools/map_generation/scripts/densify_world_hotspots.py --dir data/provinces_world_full --write
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from island_viability import classify_island, polygon_area  # noqa: E402

WORLD_W, WORLD_H = 8192.0, 4096.0
ID_BASE = 50000

# Hotspot hubs: (name_prefix, lon, lat, theater, ring_count)
# Existing names are skipped on re-run so wave 2 can append safely.
HOTSPOTS: List[Tuple[str, float, float, str, int]] = [
    # --- Wave 1: China / India / US East / Brazil ---
    ("China North China Plain", 116.4, 38.0, "far_east", 8),
    ("China Yangtze Corridor", 118.0, 32.0, "far_east", 8),
    ("China Pearl River", 113.3, 23.1, "far_east", 6),
    ("China Sichuan Basin", 104.1, 30.7, "far_east", 5),
    ("China Manchuria", 125.0, 43.0, "far_east", 5),
    ("India Gangetic Plain", 80.0, 27.0, "far_east", 8),
    ("India Deccan", 78.0, 18.0, "far_east", 6),
    ("India Punjab", 75.0, 31.0, "far_east", 5),
    ("India Bengal", 88.4, 23.0, "far_east", 5),
    ("India South Coast", 80.3, 11.0, "far_east", 4),
    ("USA Northeast Corridor", -74.0, 40.5, "north_america", 8),
    ("USA Midwest Industrial", -87.0, 41.5, "north_america", 6),
    ("USA South Atlantic", -81.0, 33.0, "north_america", 5),
    ("USA Great Lakes", -83.0, 43.0, "north_america", 4),
    ("Brazil Southeast", -46.0, -23.0, "south_america", 6),
    ("Brazil Northeast", -38.0, -8.0, "south_america", 4),
    ("Brazil Interior", -48.0, -15.0, "south_america", 4),
    # --- Wave 2: under-served theaters (not Europe) ---
    # Sub-Saharan Africa
    ("Africa Nigeria Coast", 5.5, 6.5, "africa", 10),
    ("Africa Gold Coast", -1.0, 6.0, "africa", 6),
    ("Africa Senegal Corridor", -16.0, 14.5, "africa", 5),
    ("Africa Sahel Belt", 2.0, 15.0, "africa", 8),
    ("Africa Congo Basin", 18.0, -2.0, "africa", 10),
    ("Africa Katanga", 27.0, -11.0, "africa", 6),
    ("Africa Kenya Highlands", 37.0, -1.3, "africa", 8),
    ("Africa Ethiopia Plateau", 38.7, 9.0, "africa", 6),
    ("Africa Mozambique Corridor", 35.0, -18.0, "africa", 5),
    ("Africa South Africa Highveld", 28.0, -26.0, "africa", 8),
    ("Africa Cape Approaches", 18.5, -33.9, "africa", 5),
    ("Africa Angola Coast", 13.2, -8.8, "africa", 5),
    ("Africa Rhodesia Plateau", 31.0, -17.8, "africa", 5),
    ("Africa Cameroons", 11.5, 3.9, "africa", 5),
    # SE Asia (far_east theater tag for campaign board)
    ("SE Asia Indochina", 106.0, 16.0, "far_east", 10),
    ("SE Asia Mekong Delta", 106.5, 10.5, "far_east", 6),
    ("SE Asia Malaya", 101.7, 3.1, "far_east", 7),
    ("SE Asia Sumatra", 100.5, 0.0, "far_east", 7),
    ("SE Asia Java", 110.0, -7.5, "far_east", 7),
    ("SE Asia Borneo", 114.0, 1.0, "far_east", 6),
    ("SE Asia Philippines Luzon", 121.0, 15.0, "far_east", 7),
    ("SE Asia Philippines Visayas", 123.0, 10.5, "far_east", 5),
    ("SE Asia Burma Corridor", 96.0, 20.0, "far_east", 6),
    ("SE Asia Thailand Plain", 100.5, 14.0, "far_east", 5),
    ("SE Asia Celebes", 120.0, -2.0, "far_east", 4),
    # Pacific island chains
    ("Pacific Marianas", 145.7, 15.2, "pacific", 6),
    ("Pacific Carolines", 150.0, 7.0, "pacific", 6),
    ("Pacific Marshalls", 171.0, 7.0, "pacific", 5),
    ("Pacific Solomons", 160.0, -9.0, "pacific", 6),
    ("Pacific New Guinea North", 145.0, -5.0, "pacific", 7),
    ("Pacific New Guinea South", 147.0, -9.5, "pacific", 5),
    ("Pacific Gilberts", 173.0, 1.5, "pacific", 4),
    ("Pacific Fiji Cluster", 178.0, -18.0, "pacific", 5),
    ("Pacific New Britain", 152.0, -5.5, "pacific", 4),
    # Oceania / Australia densify
    ("Oceania SE Australia", 151.0, -33.9, "oceania", 7),
    ("Oceania Victoria", 145.0, -37.8, "oceania", 6),
    ("Oceania Queensland Coast", 153.0, -27.5, "oceania", 6),
    ("Oceania NZ North", 174.8, -36.8, "oceania", 5),
    ("Oceania NZ South", 172.6, -43.5, "oceania", 4),
    ("Oceania Tasmania", 147.3, -42.9, "oceania", 3),
    ("Oceania Perth Coast", 115.9, -32.0, "oceania", 4),
    # South America beyond Brazil wave-1
    ("SA Argentina Pampas", -58.4, -34.6, "south_america", 10),
    ("SA Argentina Northwest", -65.0, -26.0, "south_america", 5),
    ("SA Chile Central", -70.7, -33.4, "south_america", 6),
    ("SA Peru Coast", -77.0, -12.0, "south_america", 6),
    ("SA Colombia Andes", -74.1, 4.7, "south_america", 6),
    ("SA Venezuela Coast", -66.9, 10.5, "south_america", 5),
    ("SA Uruguay", -56.2, -34.9, "south_america", 4),
    ("SA Bolivia Altiplano", -68.1, -16.5, "south_america", 5),
    ("SA Paraguay", -57.6, -25.3, "south_america", 4),
    # Central Asia / steppe depth
    ("CA Kazakhstan Steppe", 71.4, 51.2, "central_asia", 7),
    ("CA Uzbekistan Oasis", 69.2, 41.3, "central_asia", 6),
    ("CA Turkmen Corridor", 58.4, 38.0, "central_asia", 5),
    ("CA Xinjiang West", 87.6, 43.8, "central_asia", 6),
    ("CA Afghanistan Hindu Kush", 69.2, 34.5, "central_asia", 6),
    ("CA Mongolia Steppe", 106.9, 47.9, "central_asia", 6),
    ("CA Tajik Pamirs", 68.8, 38.6, "central_asia", 4),
    # --- Wave 3: densify toward ≥2200 (under-served / front-density, not Europe) ---
    # MENA depth (mena_africa theater)
    ("MENA Levant Coast", 35.5, 33.5, "mena_africa", 8),
    ("MENA Anatolia Plateau", 32.8, 39.9, "mena_africa", 8),
    ("MENA Mesopotamia", 44.4, 33.3, "mena_africa", 7),
    ("MENA Nile Delta", 31.2, 30.5, "mena_africa", 7),
    ("MENA Nile Upper", 32.9, 24.1, "mena_africa", 5),
    ("MENA Arabia Hejaz", 39.2, 21.4, "mena_africa", 6),
    ("MENA Persia Plateau", 51.4, 32.7, "mena_africa", 6),
    ("MENA Maghreb Interior", 3.0, 32.0, "mena_africa", 6),
    ("MENA Cyrenaica", 20.1, 32.1, "mena_africa", 5),
    ("MENA Caucasus South", 44.8, 41.7, "mena_africa", 5),
    # North America west / Mexico
    ("USA California Coast", -122.4, 37.8, "north_america", 8),
    ("USA Pacific Northwest", -122.7, 45.5, "north_america", 6),
    ("USA Texas Corridor", -97.7, 30.3, "north_america", 7),
    ("USA Rocky Mountain", -105.0, 39.7, "north_america", 5),
    ("USA Great Plains", -100.0, 41.0, "north_america", 5),
    ("Mexico Central Plateau", -99.1, 19.4, "north_america", 6),
    ("Mexico Gulf Coast", -96.1, 19.2, "north_america", 4),
    ("Canada St Lawrence", -73.6, 45.5, "north_america", 5),
    # Africa interior densify
    ("Africa Sudan Nile", 32.5, 15.5, "africa", 6),
    ("Africa Lake Chad Basin", 14.5, 13.0, "africa", 5),
    ("Africa Madagascar Highlands", 47.5, -18.9, "africa", 5),
    ("Africa Zambia Copperbelt", 28.3, -12.8, "africa", 4),
    ("Africa Ghana Interior", -1.5, 9.4, "africa", 4),
    # Far East Korea / Japan / North China depth
    ("FE Korea Peninsula", 127.0, 37.5, "far_east", 8),
    ("FE Japan Honshu", 139.7, 35.7, "far_east", 8),
    ("FE Japan Kyushu", 130.4, 33.6, "far_east", 5),
    ("FE Taiwan Strait", 121.0, 24.0, "far_east", 5),
    ("FE Indochina Highlands", 103.8, 21.0, "far_east", 5),
    # Pacific / Oceania push
    ("Pacific Hawaii Cluster", -157.8, 21.3, "pacific", 5),
    ("Pacific Samoa Cluster", -170.7, -14.3, "pacific", 4),
    ("Pacific New Caledonia", 166.5, -22.3, "pacific", 4),
    ("Oceania Adelaide Coast", 138.6, -34.9, "oceania", 4),
    ("Oceania Brisbane Interior", 152.0, -26.5, "oceania", 4),
    # South America Amazon / Andes depth
    ("SA Amazon Mouth", -48.5, -1.5, "south_america", 5),
    ("SA Amazon Manaus", -60.0, -3.1, "south_america", 5),
    ("SA Ecuador Andes", -78.5, -0.2, "south_america", 4),
]


def lonlat_to_world(lon: float, lat: float) -> Tuple[float, float]:
    return (lon + 180.0) / 360.0 * WORLD_W, (90.0 - lat) / 180.0 * WORLD_H


def cell(cx: float, cy: float, half: float) -> List[List[float]]:
    return [
        [cx, cy - half],
        [cx + half * 0.85, cy - half * 0.4],
        [cx + half * 0.85, cy + half * 0.4],
        [cx, cy + half],
        [cx - half * 0.85, cy + half * 0.4],
        [cx - half * 0.85, cy - half * 0.4],
    ]


def ring_offsets(n: int) -> List[Tuple[float, float]]:
    """Lon/lat offsets for ring density."""
    out: List[Tuple[float, float]] = []
    # two rings
    for ring, scale in ((1, 1.2), (2, 2.4)):
        step = max(4, n // 2)
        for i in range(step):
            ang = (i / step) * 6.28318
            import math

            out.append((math.cos(ang) * scale, math.sin(ang) * scale * 0.85))
        if len(out) >= n:
            break
    return out[:n]


def apply_hotspots(
    base_provinces: List[Dict[str, Any]],
    geometry_provinces: List[Dict[str, Any]],
    start_id: int = ID_BASE,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], int]:
    existing_names = {str(p.get("name", "")).lower() for p in base_provinces}
    new_base: List[Dict[str, Any]] = []
    new_geom: List[Dict[str, Any]] = []
    pid = start_id
    # avoid id collision
    max_id = max(int(p["id"]) for p in base_provinces)
    if pid <= max_id:
        pid = max_id + 1

    for prefix, lon, lat, theater, count in HOTSPOTS:
        for i, (dlon, dlat) in enumerate(ring_offsets(count)):
            name = f"{prefix} {i + 1}"
            if name.lower() in existing_names:
                continue
            cx, cy = lonlat_to_world(lon + dlon, lat + dlat)
            half = 22.0
            pts = cell(cx, cy, half)
            area = polygon_area(pts)
            viab = classify_island(area, domain="land", explicit_class="mainland")
            if not viab["keep_as_province"]:
                continue
            new_base.append(
                {
                    "id": pid,
                    "name": name,
                    "terrain": "plains",
                    "core_for_tags": [],
                    "natural_resources": {},
                    "population_base": 350000,
                    "special_features": [],
                    "special_levels": {},
                    "domain": "land",
                    "island_class": "mainland",
                    "facility_tier": "full",
                    "theater": theater,
                    "naval_importance": 0,
                    "hotspot_densify": True,
                }
            )
            new_geom.append({"id": pid, "points": pts, "label_anchor": [cx, cy]})
            existing_names.add(name.lower())
            pid += 1
    return new_base, new_geom, len(new_base)


def run_on_dir(data_dir: Path, write: bool = False) -> Dict[str, Any]:
    base_path = data_dir / "provinces_base.json"
    geom_path = data_dir / "provinces_geometry.json"
    base = json.loads(base_path.read_text(encoding="utf-8"))
    geom = json.loads(geom_path.read_text(encoding="utf-8"))
    before = len(base["provinces"])
    new_base, new_geom, added = apply_hotspots(base["provinces"], geom["provinces"])
    if not write:
        return {"before": before, "would_add": added, "after": before + added}

    base["provinces"] = list(base["provinces"]) + new_base
    geom["provinces"] = list(geom["provinces"]) + new_geom
    meta = dict(base.get("meta") or {})
    prev_added = int(meta.get("hotspot_densify_added") or 0)
    meta["hotspot_densify_added"] = prev_added + added
    meta["hotspot_densify_last_wave"] = added
    meta["province_count"] = len(base["provinces"])
    meta["geometry_space"] = "world"
    meta["geometry_world_native"] = True
    meta["world_full"] = True
    base["meta"] = meta
    gmeta = dict(geom.get("meta") or {})
    gmeta["total"] = len(geom["provinces"])
    gmeta["geometry_space"] = "world"
    gmeta["geometry_world_native"] = True
    gmeta["hotspot_densify_added"] = prev_added + added
    gmeta["hotspot_densify_last_wave"] = added
    geom["meta"] = gmeta

    # Extend adjacency for new ids (nearest 3)
    adj_path = data_dir / "province_adjacency.json"
    adj = json.loads(adj_path.read_text(encoding="utf-8")) if adj_path.exists() else {"adjacency": {}}
    adjacency: Dict[str, List[int]] = {
        str(k): list(v) for k, v in (adj.get("adjacency") or {}).items()
    }
    cents: Dict[int, Tuple[float, float]] = {}
    for g in geom["provinces"]:
        pts = g["points"]
        cents[int(g["id"])] = (
            sum(float(p[0]) for p in pts) / len(pts),
            sum(float(p[1]) for p in pts) / len(pts),
        )
    for e in new_base:
        nid = int(e["id"])
        cx, cy = cents[nid]
        ranked = sorted(
            (oid for oid in cents if oid != nid),
            key=lambda oid: (cents[oid][0] - cx) ** 2 + (cents[oid][1] - cy) ** 2,
        )[:3]
        adjacency[str(nid)] = ranked
        for oid in ranked:
            adjacency.setdefault(str(oid), [])
            if nid not in adjacency[str(oid)]:
                adjacency[str(oid)].append(nid)

    # Terrain stubs
    terr_path = data_dir / "province_terrain_layer.json"
    terr = json.loads(terr_path.read_text(encoding="utf-8")) if terr_path.exists() else {"provinces": {}}
    tmap = terr.get("provinces") if isinstance(terr.get("provinces"), dict) else {}
    for e in new_base:
        tmap[str(e["id"])] = {
            "terrain": "plains",
            "movement_cost": 1.0,
            "source": "densify_world_hotspots",
            "domain": "land",
            "facility_tier": "full",
            "island_class": "mainland",
        }
    terr["provinces"] = tmap
    terr["count"] = len(tmap)

    base_path.write_text(json.dumps(base, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    geom_path.write_text(json.dumps(geom, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    adj_path.write_text(json.dumps({"adjacency": adjacency}, indent=2) + "\n", encoding="utf-8")
    terr_path.write_text(json.dumps(terr, indent=2) + "\n", encoding="utf-8")

    # densify + regions
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))
    from densify_province_geometry import run_on_dir as densify_dir
    from rebuild_strategic_regions import run_on_dir as regions_dir

    dstat = densify_dir(data_dir, write=True, max_edge=18.0, min_vertices=12)
    rstat = regions_dir(data_dir, write=True, k=40, seed=13)
    return {
        "before": before,
        "added": added,
        "after": len(base["provinces"]),
        "densify": dstat["after"],
        "regions": rstat["gates"],
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    write = bool(args.write) and not args.dry_run
    stats = run_on_dir(data_dir, write=write)
    print(("[WROTE]" if write else "[DRY-RUN]"), stats)
    after = int(stats.get("after") or 0)
    if not after:
        after = int(stats.get("before", 0)) + int(stats.get("would_add", 0))
    added = int(stats.get("added") or stats.get("would_add") or 0)
    # Pass if board already at densify milestone scale, or this run adds a meaningful wave.
    ok = after >= 2200 or added >= 40
    print("PASS hotspot densify" if ok else "FAIL hotspot densify", file=sys.stdout if ok else sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
