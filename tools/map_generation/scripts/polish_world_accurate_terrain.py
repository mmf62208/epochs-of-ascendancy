#!/usr/bin/env python3
"""Terrain + resource heuristics for provinces_world_accurate.

Lat/lon + adm0 + name based — not DEM. Safe re-run.

  python3 tools/map_generation/scripts/polish_world_accurate_terrain.py --write
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"

W, H = 8192.0, 4096.0
LON0, LAT0 = -180.0, 83.0
LON1, LAT1 = 180.0, -56.0

WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean"})

DESERT_ADM0 = {
    "SAU", "ARE", "OMN", "YEM", "QAT", "BHR", "KWT", "JOR", "IRQ", "LBY", "EGY",
    "SDN", "SDS", "NER", "MLI", "TCD", "MRT", "ESH", "SAH", "DZA", "TUN", "MAR",
    "AFG", "TKM", "UZB", "KAZ",
}
JUNGLE_ADM0 = {
    "BRA", "COD", "COG", "GAB", "CMR", "CAF", "GIN", "CIV", "GHA", "NGA", "IDN",
    "MYS", "BRN", "PNG", "COL", "PER", "ECU", "VEN", "GUY", "SUR", "THA", "LAO",
    "KHM", "VNM", "MMR", "PHL",
}
MOUNTAIN_NAME = (
    "alps", "himal", "andes", "rocky", "tibet", "caucas", "atlas", "pyrene",
    "carpath", "zagros", "hindu kush", "pamir", "altai", "urals", "appalach",
    "sierra", "cascade", "alpen", "berg", "montblanc", "tirol", "tyrol",
)


def _load(p: Path) -> Any:
    return json.loads(p.read_text(encoding="utf-8"))


def _write(p: Path, obj: Any) -> None:
    p.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def _is_water(p: dict) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER_T or dom in WATER_D


def _centroid(pts) -> Tuple[float, float]:
    if not pts:
        return 0.0, 0.0
    return sum(float(p[0]) for p in pts) / len(pts), sum(float(p[1]) for p in pts) / len(pts)


def canvas_to_latlon(x: float, y: float) -> Tuple[float, float]:
    lon = LON0 + (x / W) * (LON1 - LON0)
    lat = LAT0 + (y / H) * (LAT1 - LAT0)
    return lat, lon


def polish(write: bool = True) -> dict:
    base_doc = _load(D / "provinces_base.json")
    base_list: List[dict] = list(base_doc.get("provinces") or [])
    geo = {int(g["id"]): g for g in _load(D / "provinces_geometry.json").get("provinces") or []}
    terr_doc = _load(D / "province_terrain_layer.json") if (D / "province_terrain_layer.json").is_file() else {"provinces": {}}
    res_doc = _load(D / "province_resources_layer.json") if (D / "province_resources_layer.json").is_file() else {"provinces": {}}
    terrain: Dict[str, dict] = dict(terr_doc.get("provinces") or {})
    resources: Dict[str, dict] = dict(res_doc.get("provinces") or {})

    changed = 0
    oil_n = 0
    for p in base_list:
        pid = int(p["id"])
        if _is_water(p):
            terrain[str(pid)] = {
                "terrain": str(p.get("terrain") or "sea"),
                "domain": str(p.get("domain") or "sea"),
            }
            resources[str(pid)] = {}
            continue
        meta = p.get("meta") if isinstance(p.get("meta"), dict) else {}
        adm0 = str(meta.get("adm0_a3") or "").upper()
        nm = str(p.get("name") or "").lower()
        g = geo.get(pid) or {}
        cx, cy = _centroid(g.get("points") or [])
        lat, _lon = canvas_to_latlon(cx, cy)

        new_terr = str(p.get("terrain") or "plains")
        if new_terr in WATER_T:
            new_terr = "plains"

        if any(k in nm for k in MOUNTAIN_NAME) or "mountain" in nm:
            new_terr = "mountains"
        elif adm0 in DESERT_ADM0 and abs(lat) < 40:
            new_terr = "desert"
        elif adm0 in JUNGLE_ADM0 and abs(lat) < 15:
            new_terr = "jungle"
        elif adm0 in JUNGLE_ADM0 and abs(lat) < 25:
            new_terr = "forest"
        elif lat > 65 or lat < -55:
            new_terr = "tundra"
        elif lat > 55 or lat < -45:
            new_terr = "forest"

        if 710000 <= pid < 800000:
            if any(k in nm for k in ("alpen", "berg", "tirol", "savoie", "valais", "tyrol", "graub")):
                new_terr = "mountains"
        if 800000 <= pid < 900000:
            st = str(meta.get("statefp") or "")
            if st == "02":
                new_terr = "tundra" if lat > 60 else "forest"
            elif st in ("08", "16", "30", "32", "35", "49", "56", "04"):
                new_terr = "mountains"
            elif st in ("06", "41", "53") and any(
                k in nm for k in ("sierra", "mountain", "inyo", "mono", "plumas")
            ):
                new_terr = "mountains"

        if new_terr != str(p.get("terrain") or "plains"):
            changed += 1
        p["terrain"] = new_terr
        p["domain"] = "land"
        terrain[str(pid)] = {"terrain": new_terr, "domain": "land"}

        res = dict(resources.get(str(pid)) or {})
        if new_terr == "desert" and adm0 in (
            "SAU", "IRQ", "IRN", "KWT", "ARE", "LBY", "VEN", "KAZ",
        ):
            res["oil"] = max(int(res.get("oil") or 0), 3)
        if new_terr == "mountains":
            res["steel"] = max(int(res.get("steel") or 0), 1)
            res["coal"] = max(int(res.get("coal") or 0), 1)
        if 710000 <= pid < 800000 and str(p.get("cntr_code") or "") == "DE":
            res["coal"] = max(int(res.get("coal") or 0), 2)
            res["steel"] = max(int(res.get("steel") or 0), 2)
        if 800000 <= pid < 900000:
            st = str(meta.get("statefp") or "")
            if st in ("48", "40", "22", "05"):
                res["oil"] = max(int(res.get("oil") or 0), 2)
            if st in ("42", "54", "21", "39", "18"):
                res["coal"] = max(int(res.get("coal") or 0), 2)
        if adm0 in ("RUS", "UKR", "CHN"):
            res["coal"] = max(int(res.get("coal") or 0), 1)
            res["steel"] = max(int(res.get("steel") or 0), 1)
        if adm0 == "ZAF":
            res["steel"] = max(int(res.get("steel") or 0), 2)
        if int(res.get("oil") or 0) > 0:
            oil_n += 1
        resources[str(pid)] = res

    dist = Counter(
        p.get("terrain")
        for p in base_list
        if not _is_water(p)
    )
    report = {
        "terrain_changed": changed,
        "oil_provinces": oil_n,
        "terrain_dist": dist.most_common(),
    }
    if write:
        base_doc["provinces"] = base_list
        _write(D / "provinces_base.json", base_doc)
        _write(
            D / "province_terrain_layer.json",
            {"provinces": terrain, "meta": {"source": "polish_world_accurate_terrain"}},
        )
        _write(
            D / "province_resources_layer.json",
            {"provinces": resources, "meta": {"source": "polish_world_accurate_terrain"}},
        )
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", default=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    rep = polish(write=not args.dry_run)
    print(json.dumps(rep, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
