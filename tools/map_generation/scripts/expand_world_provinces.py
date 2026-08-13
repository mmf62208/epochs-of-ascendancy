#!/usr/bin/env python3
"""Build full-world province set: data/provinces_world_full.

1) Takes grand_theater (Europe densified + MENA/Far East stubs + seas)
2) Reprojects all geometry into world equirectangular canvas (8192×4096 base)
3) Adds Americas, full Africa depth, Central Asia, Oceania, global oceans
4) Densify + strategic regions

geometry meta: geometry_space=world so MapManager skips Europe-local remap.

Usage:
  python3 tools/map_generation/scripts/expand_world_provinces.py --write
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from island_viability import classify_island, polygon_area  # noqa: E402

SOURCE = ROOT / "data" / "provinces_grand_theater"
OUT = ROOT / "data" / "provinces_world_full"
ID_BASE = 40000
WORLD_W = 8192.0
WORLD_H = 4096.0
# Europe theater placement on world (unscaled, matches MapCanvasConfig BASE_EU_*)
EU_X0, EU_Y0 = 3526.0, 979.0
EU_W, EU_H = 1593.0, 1372.0
GRAND_LOCAL_W, GRAND_LOCAL_H = 5000.0, 2000.0


def lonlat_to_world(lon: float, lat: float) -> Tuple[float, float]:
    """Equirectangular to unscaled world canvas (8192×4096)."""
    x = (float(lon) + 180.0) / 360.0 * WORLD_W
    y = (90.0 - float(lat)) / 180.0 * WORLD_H
    return x, y


def europe_local_to_world(px: float, py: float) -> Tuple[float, float]:
    """Map Europe-theater local points into world canvas Europe slot (unscaled)."""
    wx = EU_X0 + (float(px) / GRAND_LOCAL_W) * EU_W
    wy = EU_Y0 + (float(py) / GRAND_LOCAL_H) * EU_H
    return wx, wy


def reproject_geom_entry(entry: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(entry)
    pts = entry.get("points") or []
    new_pts = []
    for p in pts:
        wx, wy = europe_local_to_world(float(p[0]), float(p[1]))
        new_pts.append([wx, wy])
    out["points"] = new_pts
    if entry.get("label_anchor") and len(entry["label_anchor"]) >= 2:
        la = entry["label_anchor"]
        out["label_anchor"] = list(europe_local_to_world(float(la[0]), float(la[1])))
    elif new_pts:
        cx = sum(p[0] for p in new_pts) / len(new_pts)
        cy = sum(p[1] for p in new_pts) / len(new_pts)
        out["label_anchor"] = [cx, cy]
    return out


def cell(cx: float, cy: float, half: float) -> List[List[float]]:
    return [
        [cx, cy - half],
        [cx + half * 0.85, cy - half * 0.4],
        [cx + half * 0.85, cy + half * 0.4],
        [cx, cy + half],
        [cx - half * 0.85, cy + half * 0.4],
        [cx - half * 0.85, cy - half * 0.4],
    ]


def add_seed(
    seeds: List[Dict[str, Any]],
    name: str,
    lon: float,
    lat: float,
    *,
    domain: str = "land",
    island_class: str = "mainland",
    theater: str = "world",
    half: float = 32.0,
    critical: bool = False,
    satellites: int = 0,
) -> None:
    seeds.append(
        {
            "name": name,
            "lon": lon,
            "lat": lat,
            "domain": domain,
            "island_class": island_class,
            "theater": theater,
            "half": half,
            "critical": critical,
        }
    )
    # Army-depth satellites
    for i, (dlon, dlat) in enumerate(
        [(1.5, 0), (-1.5, 0), (0, 1.2), (0, -1.2), (1.1, 1.1), (-1.1, -1.1)][:satellites]
    ):
        seeds.append(
            {
                "name": f"{name} Sector {chr(65 + i)}",
                "lon": lon + dlon,
                "lat": lat + dlat,
                "domain": domain,
                "island_class": island_class,
                "theater": theater,
                "half": half * 0.72,
                "critical": False,
            }
        )


def world_seed_defs() -> List[Dict[str, Any]]:
    seeds: List[Dict[str, Any]] = []

    # —— North America ——
    na = [
        ("New York", -74.0, 40.7, 4),
        ("Washington DC Theater", -77.0, 38.9, 3),
        ("Boston", -71.1, 42.4, 2),
        ("Chicago", -87.6, 41.9, 3),
        ("Detroit", -83.0, 42.3, 2),
        ("Atlanta", -84.4, 33.7, 2),
        ("Miami", -80.2, 25.8, 2),
        ("New Orleans", -90.1, 29.9, 2),
        ("Houston Theater", -95.4, 29.8, 3),
        ("Dallas", -96.8, 32.8, 2),
        ("Denver", -105.0, 39.7, 2),
        ("Phoenix", -112.1, 33.4, 2),
        ("Los Angeles", -118.2, 34.1, 3),
        ("San Francisco", -122.4, 37.8, 3),
        ("Seattle", -122.3, 47.6, 2),
        ("Vancouver", -123.1, 49.3, 2),
        ("Toronto", -79.4, 43.7, 2),
        ("Montreal", -73.6, 45.5, 2),
        ("Winnipeg", -97.1, 49.9, 1),
        ("Calgary", -114.1, 51.0, 1),
        ("Alaska Anchorage", -149.9, 61.2, 1),
        ("Mexico City", -99.1, 19.4, 3),
        ("Veracruz", -96.1, 19.2, 1),
        ("Monterrey", -100.3, 25.7, 1),
        ("Guadalajara", -103.3, 20.7, 1),
        ("Havana", -82.4, 23.1, 1),
        ("Kingston Jamaica", -76.8, 18.0, 0),
        ("Panama Canal Zone", -79.5, 9.0, 1),
        ("Great Lakes West", -87.0, 44.0, 1),
        ("Great Plains North", -100.0, 45.0, 1),
        ("Appalachia", -82.0, 37.0, 1),
        ("Texas West", -102.0, 32.0, 1),
        ("Quebec City", -71.2, 46.8, 1),
        ("Halifax", -63.6, 44.6, 1),
    ]
    for name, lon, lat, sat in na:
        add_seed(
            seeds,
            name,
            lon,
            lat,
            domain="coastal_land" if abs(lon) > 70 else "land",
            theater="north_america",
            half=36.0,
            satellites=sat,
        )

    # —— South America ——
    sa = [
        ("Bogota", -74.1, 4.7, 2),
        ("Caracas", -66.9, 10.5, 2),
        ("Lima", -77.0, -12.0, 2),
        ("Quito", -78.5, -0.2, 1),
        ("La Paz", -68.1, -16.5, 1),
        ("Santiago Chile", -70.7, -33.4, 2),
        ("Buenos Aires", -58.4, -34.6, 3),
        ("Cordoba AR", -64.2, -31.4, 1),
        ("Montevideo", -56.2, -34.9, 1),
        ("Sao Paulo", -46.6, -23.5, 3),
        ("Rio de Janeiro", -43.2, -22.9, 2),
        ("Brasilia", -47.9, -15.8, 2),
        ("Recife", -34.9, -8.1, 1),
        ("Manaus", -60.0, -3.1, 2),
        ("Belem", -48.5, -1.5, 1),
        ("Asuncion", -57.6, -25.3, 1),
        ("Patagonia North", -68.0, -45.0, 1),
        ("Falklands Approaches", -59.0, -51.7, 0),
    ]
    for name, lon, lat, sat in sa:
        add_seed(
            seeds,
            name,
            lon,
            lat,
            domain="coastal_land",
            theater="south_america",
            half=38.0,
            satellites=sat,
        )

    # —— Sub-Saharan Africa fill (beyond MENA slice) ——
    af = [
        ("Dakar", -17.4, 14.7, 1),
        ("Bamako", -8.0, 12.6, 1),
        ("Accra", -0.2, 5.6, 1),
        ("Abidjan", -4.0, 5.3, 1),
        ("Lagos Deep", 3.4, 6.5, 2),
        ("Kano", 8.5, 12.0, 1),
        ("Kinshasa", 15.3, -4.3, 2),
        ("Lubumbashi", 27.5, -11.7, 1),
        ("Luanda", 13.2, -8.8, 1),
        ("Nairobi", 36.8, -1.3, 2),
        ("Kampala", 32.6, 0.3, 1),
        ("Dar es Salaam", 39.3, -6.8, 1),
        ("Addis Deep", 38.7, 9.0, 1),
        ("Johannesburg", 28.0, -26.2, 2),
        ("Pretoria", 28.2, -25.7, 1),
        ("Cape Interior", 22.0, -32.0, 1),
        ("Windhoek", 17.1, -22.6, 1),
        ("Harare", 31.1, -17.8, 1),
        ("Lusaka", 28.3, -15.4, 1),
        ("Antananarivo", 47.5, -18.9, 1),
        ("Maputo", 32.6, -25.9, 1),
        ("Sahel East", 20.0, 15.0, 1),
        ("Congo Basin North", 20.0, 2.0, 1),
        ("Horn of Africa", 45.0, 8.0, 1),
    ]
    for name, lon, lat, sat in af:
        add_seed(
            seeds,
            name,
            lon,
            lat,
            domain="coastal_land",
            theater="africa",
            half=40.0,
            satellites=sat,
        )

    # —— Central / North Asia ——
    asia = [
        ("Novosibirsk", 82.9, 55.0, 1),
        ("Irkutsk", 104.3, 52.3, 1),
        ("Yakutsk", 129.7, 62.0, 0),
        ("Vladivostok Deep", 131.9, 43.1, 1),
        ("Ulaanbaatar", 106.9, 47.9, 1),
        ("Almaty", 76.9, 43.2, 1),
        ("Tashkent", 69.2, 41.3, 1),
        ("Ashgabat", 58.4, 37.9, 1),
        ("Bishkek", 74.6, 42.9, 0),
        ("Urumqi", 87.6, 43.8, 1),
        ("Lhasa", 91.1, 29.7, 1),
        ("Chengdu", 104.1, 30.7, 2),
        ("Xian", 108.9, 34.3, 1),
        ("Nanjing", 118.8, 32.1, 1),
        ("Tianjin", 117.2, 39.1, 1),
        ("Shenyang", 123.4, 41.8, 1),
        ("Harbin Deep", 126.6, 45.8, 1),
        ("Pyongyang", 125.8, 39.0, 1),
        ("Busan", 129.1, 35.2, 1),
        ("Sapporo", 141.4, 43.1, 1),
        ("Fukuoka", 130.4, 33.6, 1),
        ("Okinawa", 127.7, 26.2, 0),
        ("Ulaan Interior", 100.0, 45.0, 0),
        ("Siberia Central", 90.0, 60.0, 0),
        ("Kamchatka", 158.6, 53.0, 0),
    ]
    for name, lon, lat, sat in asia:
        add_seed(
            seeds,
            name,
            lon,
            lat,
            domain="land",
            theater="central_asia",
            half=42.0,
            satellites=sat,
        )

    # —— Oceania densify ——
    oc = [
        ("Melbourne", 144.9, -37.8, 2),
        ("Brisbane", 153.0, -27.5, 1),
        ("Perth", 115.9, -32.0, 1),
        ("Adelaide", 138.6, -34.9, 1),
        ("Alice Springs", 133.9, -23.7, 0),
        ("Auckland", 174.8, -36.8, 1),
        ("Wellington", 174.8, -41.3, 1),
        ("Christchurch", 172.6, -43.5, 1),
        ("Fiji", 178.0, -18.1, 0),
        ("Samoa", -171.8, -13.8, 0),
        ("Tahiti", -149.6, -17.6, 0),
        ("Port Moresby", 147.2, -9.5, 1),
    ]
    for name, lon, lat, sat in oc:
        add_seed(
            seeds,
            name,
            lon,
            lat,
            domain="coastal_land",
            theater="oceania",
            half=34.0,
            satellites=sat,
            island_class="large" if "Fiji" in name or "Samoa" in name or "Tahiti" in name else "mainland",
        )

    # —— Global ocean grid (raise sea share) ——
    # Atlantic densify
    for lon in range(-60, 0, 10):
        for lat in range(-40, 60, 12):
            seeds.append(
                {
                    "name": f"Atlantic Basin {lon}_{lat}",
                    "lon": float(lon),
                    "lat": float(lat),
                    "domain": "sea",
                    "island_class": "none",
                    "theater": "sea",
                    "half": 80.0,
                    "critical": False,
                }
            )
    # Pacific densify
    for lon in list(range(-180, -100, 12)) + list(range(140, 180, 12)):
        for lat in range(-40, 50, 12):
            seeds.append(
                {
                    "name": f"Pacific Basin {lon}_{lat}",
                    "lon": float(lon),
                    "lat": float(lat),
                    "domain": "sea",
                    "island_class": "none",
                    "theater": "sea",
                    "half": 85.0,
                    "critical": False,
                }
            )
    # Indian densify
    for lon in range(40, 110, 12):
        for lat in range(-40, 25, 12):
            seeds.append(
                {
                    "name": f"Indian Basin {lon}_{lat}",
                    "lon": float(lon),
                    "lat": float(lat),
                    "domain": "sea",
                    "island_class": "none",
                    "theater": "sea",
                    "half": 80.0,
                    "critical": False,
                }
            )
    # Southern Ocean + Arctic
    for lon in range(-180, 180, 30):
        seeds.append(
            {
                "name": f"Southern Ocean {lon}",
                "lon": float(lon),
                "lat": -55.0,
                "domain": "sea",
                "island_class": "none",
                "theater": "sea",
                "half": 90.0,
                "critical": False,
            }
        )
        seeds.append(
            {
                "name": f"Arctic Ocean {lon}",
                "lon": float(lon),
                "lat": 75.0,
                "domain": "sea",
                "island_class": "none",
                "theater": "sea",
                "half": 70.0,
                "critical": False,
            }
        )

    # Great Lakes as lakes
    for name, lon, lat in [
        ("Lake Superior", -87.5, 47.7),
        ("Lake Michigan", -87.0, 44.0),
        ("Lake Huron", -82.5, 44.5),
        ("Lake Erie", -81.2, 42.2),
        ("Lake Ontario", -77.9, 43.7),
        ("Caspian Sea", 50.0, 42.0),
        ("Lake Victoria", 33.0, -1.0),
    ]:
        seeds.append(
            {
                "name": name,
                "lon": lon,
                "lat": lat,
                "domain": "lake",
                "island_class": "none",
                "theater": "sea",
                "half": 40.0,
                "critical": False,
            }
        )

    return seeds


def build_world_entries(start_id: int) -> Tuple[List[Dict], List[Dict], Dict[str, Any]]:
    base_out: List[Dict[str, Any]] = []
    geom_out: List[Dict[str, Any]] = []
    terrain: Dict[str, Any] = {}
    pid = start_id
    for seed in world_seed_defs():
        lon, lat = float(seed["lon"]), float(seed["lat"])
        cx, cy = lonlat_to_world(lon, lat)
        half = float(seed.get("half", 32.0))
        domain = str(seed["domain"])
        pts = cell(cx, cy, half)
        area = polygon_area(pts)
        viability = classify_island(
            area,
            domain=domain,
            critical=bool(seed.get("critical")),
            explicit_class=seed.get("island_class"),
        )
        if not viability["keep_as_province"]:
            continue
        dom = domain if domain in ("sea", "strait", "lake") else viability["domain"]
        entry = {
            "id": pid,
            "name": seed["name"],
            "terrain": "sea" if dom in ("sea", "strait", "lake") else "plains",
            "core_for_tags": [],
            "natural_resources": {},
            "population_base": 0 if dom in ("sea", "strait", "lake") else 400000,
            "special_features": ["lake"] if dom == "lake" else [],
            "special_levels": {},
            "domain": dom,
            "island_class": viability["island_class"] if dom not in ("sea", "strait", "lake") else "none",
            "facility_tier": "none" if dom in ("sea", "strait", "lake") else viability["facility_tier"],
            "theater": seed.get("theater", "world"),
            "naval_importance": 2 if dom == "sea" else 0,
        }
        base_out.append(entry)
        geom_out.append({"id": pid, "points": pts, "label_anchor": [cx, cy]})
        terrain[str(pid)] = {
            "terrain": entry["terrain"],
            "movement_cost": 0.5 if dom in ("sea", "strait", "lake") else 1.0,
            "source": "expand_world_provinces",
            "domain": dom,
            "island_class": entry["island_class"],
            "facility_tier": entry["facility_tier"],
        }
        pid += 1
    return base_out, geom_out, terrain


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def build(write: bool = False) -> Dict[str, Any]:
    if not SOURCE.exists():
        raise FileNotFoundError(f"Missing source {SOURCE} — run expand_grand_theater first")

    base = load_json(SOURCE / "provinces_base.json")
    geom = load_json(SOURCE / "provinces_geometry.json")

    # Reproject existing grand theater → world canvas
    reproj = [reproject_geom_entry(g) for g in geom["provinces"]]
    for p in base["provinces"]:
        if "domain" not in p:
            p["domain"] = "land"
        if "facility_tier" not in p:
            p["facility_tier"] = "full" if p.get("domain") not in ("sea", "strait") else "none"
        if "theater" not in p:
            p["theater"] = "europe_core"

    new_base, new_geom, new_terr = build_world_entries(ID_BASE)
    base["provinces"] = list(base["provinces"]) + new_base
    geom["provinces"] = reproj + new_geom

    meta_b = dict(base.get("meta") or {})
    meta_b.update(
        {
            "world_full": True,
            "geometry_space": "world",
            "geometry_world_native": True,
            "province_count": len(base["provinces"]),
            "world_expansion_added": len(new_base),
            "source": "expand_world_provinces.py",
        }
    )
    base["meta"] = meta_b
    meta_g = dict(geom.get("meta") or {})
    meta_g.update(
        {
            "geometry_space": "world",
            "geometry_world_native": True,
            "world_canvas": [WORLD_W, WORLD_H],
            "total": len(geom["provinces"]),
            "world_expansion_added": len(new_geom),
            "source": "expand_world_provinces.py",
        }
    )
    geom["meta"] = meta_g

    # Adjacency NN
    cents: Dict[int, Tuple[float, float]] = {}
    for g in geom["provinces"]:
        pts = g["points"]
        cents[int(g["id"])] = (
            sum(p[0] for p in pts) / len(pts),
            sum(p[1] for p in pts) / len(pts),
        )
    adj_src = load_json(SOURCE / "province_adjacency.json") if (SOURCE / "province_adjacency.json").exists() else {"adjacency": {}}
    adjacency: Dict[str, List[int]] = {
        str(k): list(v) for k, v in (adj_src.get("adjacency") or {}).items()
    }
    new_ids = [int(p["id"]) for p in new_base]
    all_ids = list(cents.keys())
    for nid in new_ids:
        cx, cy = cents[nid]
        ranked = sorted(
            (oid for oid in all_ids if oid != nid),
            key=lambda oid: (cents[oid][0] - cx) ** 2 + (cents[oid][1] - cy) ** 2,
        )[:3]
        adjacency[str(nid)] = ranked
        for oid in ranked:
            k = str(oid)
            adjacency.setdefault(k, [])
            if nid not in adjacency[k]:
                adjacency[k].append(nid)

    # Terrain
    terr = load_json(SOURCE / "province_terrain_layer.json") if (SOURCE / "province_terrain_layer.json").exists() else {"provinces": {}}
    tmap = terr.get("provinces") if isinstance(terr.get("provinces"), dict) else {}
    for k, v in new_terr.items():
        tmap[k] = v
    terr["provinces"] = tmap
    terr["count"] = len(tmap)

    def extend_layer(name: str, factory):
        p = SOURCE / name
        if p.exists():
            data = load_json(p)
        else:
            data = {"provinces": {}}
        if "provinces" in data and isinstance(data["provinces"], dict):
            for e in new_base:
                sid = str(e["id"])
                if sid not in data["provinces"]:
                    data["provinces"][sid] = factory()
        return data

    economy = extend_layer(
        "province_economy_layer.json",
        lambda: {"development_level": 2, "infrastructure": 2, "factories": 0},
    )
    resources = extend_layer("province_resources_layer.json", lambda: {})
    cities = extend_layer("province_city_layer.json", lambda: {"cities": []})

    stats = {
        "total": len(base["provinces"]),
        "added_world": len(new_base),
        "from_grand_theater": len(base["provinces"]) - len(new_base),
        "sea_strait_lake": sum(
            1 for p in base["provinces"] if p.get("domain") in ("sea", "strait", "lake")
        ),
    }

    if not write:
        return stats

    OUT.mkdir(parents=True, exist_ok=True)
    write_json(OUT / "provinces_base.json", base)
    write_json(OUT / "provinces_geometry.json", geom)
    write_json(OUT / "province_adjacency.json", {"adjacency": adjacency})
    write_json(OUT / "province_terrain_layer.json", terr)
    write_json(OUT / "province_economy_layer.json", economy)
    write_json(OUT / "province_resources_layer.json", resources)
    write_json(OUT / "province_city_layer.json", cities)
    if (SOURCE / "province_states.json").exists():
        shutil.copy2(SOURCE / "province_states.json", OUT / "province_states.json")
    if (SOURCE / "naval_chokepoints.json").exists():
        shutil.copy2(SOURCE / "naval_chokepoints.json", OUT / "naval_chokepoints.json")
    if (SOURCE / "project_sites.json").exists():
        shutil.copy2(SOURCE / "project_sites.json", OUT / "project_sites.json")
    write_json(OUT / "manifest_world_full.json", {"phase": "world_full_v1", "stats": stats})

    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))
    from densify_province_geometry import run_on_dir as densify_dir
    from rebuild_strategic_regions import run_on_dir as regions_dir

    dstat = densify_dir(OUT, write=True, max_edge=18.0, min_vertices=12)
    rstat = regions_dir(OUT, write=True, k=24, seed=11)
    stats["densify"] = dstat["after"]
    stats["regions"] = rstat["gates"]
    return stats


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    write = bool(args.write) and not args.dry_run
    stats = build(write=write)
    mode = "WROTE" if write else "DRY-RUN"
    print(f"[{mode}] {OUT}")
    print("  stats:", stats)
    total = stats.get("total", 0)
    sea = stats.get("sea_strait_lake", 0)
    ok = total >= 1500 and sea / max(total, 1) >= 0.10
    print(
        "PASS world full gates" if ok else "FAIL world full gates",
        file=sys.stdout if ok else sys.stderr,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
