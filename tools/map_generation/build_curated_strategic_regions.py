#!/usr/bin/env python3
"""Build curated strategic_regions.json for phase1/world theater maps.

Vic3/HOI4-style macro regions with UK split into 5 (not 1).
Run from repo root: python3 tools/map_generation/build_curated_strategic_regions.py
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = ROOT / "data" / "provinces_phase1_test"
OUT_PATH = DATA_DIR / "strategic_regions.json"

REGION_META: dict[int, tuple[str, str]] = {
    1: ("Southern England", "London, Home Counties, south coast."),
    2: ("Northern England & Midlands", "Industrial north, Midlands corridor."),
    3: ("Scotland", "Highlands, Central Belt, northern Britain."),
    4: ("Wales", "Western Britain, Welsh valleys."),
    5: ("Ireland", "Republic + Northern Ireland (provinces stay separate)."),
    6: ("Low Countries", "Netherlands, Belgium, Luxembourg."),
    7: ("Western Germany", "Rhineland, Ruhr, Saar."),
    8: ("Central Germany", "Berlin, Saxony, Bohemia edge."),
    9: ("Scandinavia", "Norway, Sweden, Denmark, Finland north."),
    10: ("Baltic Littoral", "Baltic states, East Prussia, Polish coast."),
    11: ("Poland & Silesia", "Core Poland, Silesia."),
    12: ("France & Paris Basin", "Northern France, Paris, Maginot."),
    13: ("Iberia", "Spain and Portugal."),
    14: ("Alpine & North Italy", "Po valley, Venice, Alps."),
    15: ("Southern Italy & Sicily", "Rome south, Sicily (multi-prov island)."),
    16: ("Western Mediterranean", "Corsica, Sardinia, Balearics; Malta stays solo prov."),
    17: ("Balkans", "Yugoslavia, Romania, Bulgaria."),
    18: ("Greece & Aegean", "Greece, Crete (multi-prov), Aegean."),
    19: ("Anatolia & Straits", "Turkey, Bosporus/Dardanelles."),
    20: ("North Africa", "Maghreb, Libya coast."),
    21: ("Eastern Europe & Ukraine", "Ukraine, Belarus approaches."),
    22: ("Western Russia", "Leningrad, Karelia, Moscow west."),
    23: ("Arctic & Atlantic Approaches", "Iceland, Faroes, Barents convoys."),
    24: ("Middle East & Levant", "Levant, Mesopotamia fringe."),
    25: ("Persia & Gulf", "Iran, Persian Gulf."),
    26: ("Central Asia & Caucasus", "Caucasus, Caspian, steppe."),
    27: ("South Asia", "Indian subcontinent."),
    28: ("East Asia", "China, Korea, Japan approaches."),
    29: ("Southeast Asia", "Indochina, Indonesia, Pacific."),
    30: ("West & Central Africa", "Nigeria, Sahel, Congo."),
    31: ("East Africa & Horn", "Horn, East African coast."),
    32: ("Southern Africa", "South Africa, Rhodesia."),
    33: ("North America — East", "US East, industrial northeast."),
    34: ("North America — West", "US West, Canada."),
    35: ("Central America & Caribbean", "Mexico south, Caribbean."),
    36: ("South America", "Andes, Brazil, River Plate."),
    37: ("Oceania", "Australia, New Zealand, Pacific."),
}

TAG_TO_REGION: dict[str, int] = {
    "ENG": 0, "GBR": 0, "SCO": 3, "WLS": 4, "IRL": 5, "NIR": 5,
    "NLD": 6, "BEL": 6, "LUX": 6,
    "GER": 7, "FRA": 12, "SPA": 13, "POR": 13,
    "ITA": 14, "CHE": 14, "AUT": 14,
    "NOR": 9, "SWE": 9, "DNK": 9, "FIN": 9,
    "POL": 11, "CZE": 8, "HUN": 17, "ROM": 17, "BUL": 17, "YUG": 17,
    "GRC": 18, "CRE": 18, "SIC": 15, "MLT": 16, "COR": 16, "SAR": 16, "BAL": 16, "CYP": 24, "TUR": 19,
    "EGY": 20, "LBA": 20, "ALG": 20, "TUN": 20, "MAR": 20,
    "UKR": 21, "BLR": 21,
    "RUS": 22, "SOV": 22,
    "IRQ": 24, "SYR": 24, "ISR": 24, "PAL": 24, "JOR": 24, "LBN": 24,
    "IRN": 25, "SAU": 25, "UAE": 25, "KWT": 25, "QAT": 25,
    "AZE": 26, "GEO": 26, "ARM": 26, "KAZ": 26,
    "IND": 27, "PAK": 27, "BGD": 27,
    "CHN": 28, "KOR": 28, "PRK": 28, "JPN": 28, "TWN": 28,
    "THA": 29, "VIE": 29, "MYS": 29, "IDN": 29, "PHL": 29, "SGP": 29,
    "NGA": 30, "GHA": 30, "CIV": 30, "CMR": 30,
    "ETH": 31, "KEN": 31, "SOM": 31,
    "SAF": 32, "ZWE": 32, "ZAF": 32,
    "USA": 33, "CAN": 34,
    "MEX": 35, "CUB": 35, "PAN": 35, "COL": 35,
    "BRA": 36, "ARG": 36, "CHL": 36, "VEN": 36, "PER": 36,
    "AUS": 37, "NZL": 37,
}


def prov_info(p: dict, geo_by_id: dict) -> dict | None:
    pid = p["id"]
    pts = geo_by_id.get(pid, {}).get("points", [])
    if len(pts) < 3:
        return None
    cx = sum(pt[0] for pt in pts) / len(pts)
    cy = sum(pt[1] for pt in pts) / len(pts)
    xs = [pt[0] for pt in pts]
    ys = [pt[1] for pt in pts]
    return {
        "id": pid,
        "cx": cx,
        "cy": cy,
        "w": max(xs) - min(xs),
        "h": max(ys) - min(ys),
        "name": p.get("name", ""),
        "tags": p.get("core_for_tags", []),
    }


def classify_eng_split(info: dict) -> int:
    cx, cy = info["cx"], info["cy"]
    # Thresholds aligned with lon/lat-anchored British Isles (bbox -25..45, 28..72, 5000×2000).
    if cy < 760:
        return 3
    if cy >= 905:
        return 1
    return 2


def classify_by_geography(info: dict) -> int:
    cx, cy = info["cx"], info["cy"]

    if 1150 <= cx <= 1790 and 660 <= cy <= 975:
        return classify_eng_split(info)
    if 2088 <= cx <= 2168 and 400 <= cy <= 468:
        return 6
    if 2100 <= cx <= 2225 and 420 <= cy <= 525:
        return 7
    if 2180 <= cx <= 2360 and 420 <= cy <= 545:
        return 8
    if 2120 <= cx <= 2420 and cy < 385:
        return 9
    if 2350 <= cx <= 2555 and 350 <= cy <= 485:
        return 10
    if 2280 <= cx <= 2525 and 485 <= cy <= 625:
        return 11
    if 1620 <= cx <= 2420 and 930 <= cy <= 1340:
        return 12
    if 2035 <= cx <= 2125 and 455 <= cy <= 585:
        return 12
    if 2280 <= cx <= 2720 and 1170 <= cy <= 1320:
        return 14
    if 2550 <= cx <= 3040 and 1280 <= cy <= 1450:
        return 15
    if 1100 <= cx <= 2100 and 1320 <= cy <= 1620:
        return 13
    if 1900 <= cx <= 2105 and 580 <= cy <= 785:
        return 13
    if 4080 <= cx <= 4220 and 1630 <= cy <= 1730:
        return 24
    if 2100 <= cx <= 2285 and 520 <= cy <= 685:
        return 14
    if 2180 <= cx <= 2425 and 640 <= cy <= 825:
        return 15
    if 2050 <= cx <= 2260 and 580 <= cy <= 730 and max(info["w"], info["h"]) < 200:
        return 16
    if 2350 <= cx <= 2660 and 580 <= cy <= 785:
        return 17
    if 2450 <= cx <= 2760 and 720 <= cy <= 905:
        return 18
    if 2350 <= cx <= 2710 and 540 <= cy <= 725:
        return 19
    if 2100 <= cx <= 2510 and 780 <= cy <= 985:
        return 20
    if 2520 <= cx <= 2920 and 480 <= cy <= 725:
        return 21
    if 2700 <= cx <= 3210 and 280 <= cy <= 525:
        return 22
    if cx >= 2050 and cy < 310:
        return 23
    if 2500 <= cx <= 2810 and 680 <= cy <= 905:
        return 24
    if 2550 <= cx <= 2860 and 600 <= cy <= 785:
        return 25
    if 2700 <= cx <= 3110 and 520 <= cy <= 685:
        return 26
    if 2800 <= cx <= 3320 and 780 <= cy <= 1105:
        return 27
    if 3200 <= cx <= 3920 and 480 <= cy <= 905:
        return 28
    if 3300 <= cx <= 3920 and 905 <= cy <= 1210:
        return 29
    if 2000 <= cx <= 2510 and 900 <= cy <= 1210:
        return 30
    if 2500 <= cx <= 2910 and 900 <= cy <= 1210:
        return 31
    if 2300 <= cx <= 2720 and 1200 <= cy <= 1510:
        return 32
    if cx < 1200 and 900 <= cy <= 1400:
        return 33
    if cx < 1400 and cy < 1300:
        return 34
    if 1200 <= cx <= 1700 and 900 <= cy <= 1300:
        return 35
    if cx < 1700 and cy >= 1200:
        return 36
    if cx >= 3400:
        return 37
    if cx < 1500:
        return 36 if cy > 1100 else 33
    if cx < 2500:
        return 30
    if cx < 3200:
        return 27
    return 37


def classify(info: dict) -> int:
    tags = info["tags"]
    for tag in tags:
        t = str(tag).upper()
        if t in ("ENG", "GBR"):
            return classify_eng_split(info)
        if t in TAG_TO_REGION:
            rid = TAG_TO_REGION[t]
            if t == "GER" and info["cx"] >= 2190:
                return 8
            if t == "ITA":
                if info["cy"] >= 1280:
                    return 15
                return 14
            if t == "RUS" and info["cy"] >= 400:
                return 21 if info["cx"] < 2800 else 22
            return rid
    return classify_by_geography(info)


def main() -> None:
    base = json.loads((DATA_DIR / "provinces_base.json").read_text())
    geo_data = json.loads((DATA_DIR / "provinces_geometry.json").read_text())
    geo_by_id = {p["id"]: p for p in geo_data.get("provinces", [])}

    regions = {
        rid: {"id": rid, "name": REGION_META[rid][0], "notes": REGION_META[rid][1], "province_ids": []}
        for rid in REGION_META
    }

    for p in base["provinces"]:
        info = prov_info(p, geo_by_id)
        if info is None:
            continue
        rid = classify(info)
        regions[rid]["province_ids"].append(info["id"])

    out_regions = []
    for rid in sorted(regions.keys()):
        r = regions[rid]
        r["province_ids"] = sorted(r["province_ids"])
        out_regions.append({k: r[k] for k in ("id", "name", "notes", "province_ids")})

    out = {
        "_comment": "Curated Vic3/HOI4-style strategic regions. UK split into 5. Regenerate via tools/map_generation/build_curated_strategic_regions.py",
        "version": 2,
        "regions": out_regions,
    }
    OUT_PATH.write_text(json.dumps(out, indent=2) + "\n")
    print(f"Wrote {OUT_PATH}")
    for r in out_regions:
        print(f"  {r['id']:2d} {r['name']:32s} {len(r['province_ids']):3d}")
    for rid in (1, 2, 3, 4, 5):
        print(f"  UK {rid}: {regions[rid]['province_ids']}")


if __name__ == "__main__":
    main()
