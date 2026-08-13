#!/usr/bin/env python3
"""Paint HOI-style strategic resources onto provinces_world_accurate.

Existing layer only has coal/steel on densify leftovers — majors like SOV/JAP have
zero strategic paint. This script adds oil / rubber / aluminum / chromium / tungsten
using ownership + meta (TIGER statefp, geoBoundaries adm0) + curated name hits.

Does not renumber IDs. Safe to re-run (merges into existing resource dicts).

  python3 tools/map_generation/scripts/paint_world_accurate_strategic_resources.py --write
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Set

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"

# US TIGER state FIPS → oil / coal / aluminum bias (1936 strategic)
US_OIL_FIPS = {"48", "40", "22", "05", "35", "06", "04", "08", "30", "56"}  # TX OK LA AR NM CA AZ CO MT WY
US_STEEL_FIPS = {"42", "39", "17", "18", "26", "21"}  # PA OH IL IN MI KY
US_ALUM_FIPS = {"53", "41", "16", "30"}  # WA OR ID MT

# geoBoundaries / adm0 strategic resources (1936-ish spheres use ownership not only adm0)
ADM0_OIL = {
    "SAU": 3, "IRQ": 3, "IRN": 3, "KWT": 3, "VEN": 3, "IDN": 2, "MYS": 1,
    "AZE": 3, "MEX": 2, "COL": 1, "ROU": 2, "EGY": 1, "LBY": 1, "NGA": 1,
    "USA": 0,  # handled via FIPS
}
ADM0_RUBBER = {"IDN": 3, "MYS": 3, "THA": 2, "VNM": 1, "LBR": 2, "COD": 1, "BRA": 1}
ADM0_CHROMIUM = {"TUR": 2, "ZAF": 2, "ZWE": 2, "ALB": 1, "IND": 1, "PHL": 1}
ADM0_TUNGSTEN = {"CHN": 2, "BOL": 2, "PRT": 1, "ESP": 1, "KOR": 1, "MMR": 1}
ADM0_ALUMINUM = {"SUR": 2, "GUY": 1, "JAM": 2, "HUN": 1, "FRA": 1, "YUG": 1}

# Name substrings → resource boosts (case-insensitive)
NAME_OIL = ("baku", "ploie", "texas", "oklahoma", "louisiana", "maracaibo", "kirkuk", "abadan", "dhahran")
NAME_RUBBER = ("sumatra", "borneo", "java", "malaya", "singapore", "ceylon")


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _write(path: Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def _add(row: Dict[str, Any], key: str, amount: int) -> None:
    if amount <= 0:
        return
    cur = int(row.get(key) or 0)
    row[key] = max(cur, int(amount))


def paint(write: bool = False) -> dict:
    base_list = _load(D / "provinces_base.json")["provinces"]
    base = {int(p["id"]): p for p in base_list}
    own = _load(D / "province_ownership_1936.json").get("owners") or {}
    res_doc = _load(D / "province_resources_layer.json")
    provs: Dict[str, Dict[str, Any]] = dict(res_doc.get("provinces") or {})

    # Ensure every province has a dict
    for pid in base:
        provs.setdefault(str(pid), {})

    counts = Counter()
    for pid, p in base.items():
        row = dict(provs.get(str(pid)) or {})
        meta = p.get("meta") if isinstance(p.get("meta"), dict) else {}
        name = str(p.get("name") or "").lower()
        tag = str(own.get(str(pid)) or "").upper()
        adm0 = str(meta.get("adm0_a3") or "").upper()
        statefp = str(meta.get("statefp") or "")
        domain = str(p.get("domain") or "land").lower()
        is_sea = domain in ("sea", "strait", "lake", "ocean") or str(p.get("terrain") or "").lower() in (
            "sea", "ocean", "water", "lake"
        )
        if is_sea:
            # seas keep empty strategic land resources
            provs[str(pid)] = row
            continue

        # Preserve existing coal/steel; bump floors for majors
        if tag == "GER":
            _add(row, "coal", 2)
            _add(row, "steel", 2)
        if tag in ("ENG", "FRA", "ITA", "POL"):
            _add(row, "coal", 1)
            _add(row, "steel", 1)
        if tag == "USA" and statefp in US_STEEL_FIPS:
            _add(row, "steel", 2)
            _add(row, "coal", 2)
        if tag == "USA" and statefp in US_OIL_FIPS:
            _add(row, "oil", 2)
        if tag == "USA" and statefp in US_ALUM_FIPS:
            _add(row, "aluminum", 2)
        if tag == "SOV":
            _add(row, "coal", 1)
            _add(row, "steel", 1)
            # Volga/Urals/Siberia-ish: densify RUS blocks
            if adm0 in ("RUS", "AZE", "KAZ", "UKR") or "baku" in name:
                _add(row, "oil", 2 if "baku" in name or adm0 == "AZE" else 1)
            if adm0 in ("RUS", "UKR"):
                _add(row, "steel", 2)
        if tag == "JAP":
            _add(row, "steel", 1)
            _add(row, "coal", 1)
            _add(row, "aluminum", 1)
        if tag == "CHI":
            _add(row, "coal", 1)
            _add(row, "tungsten", 1)

        # ADM0 paints (ownership may be colonial ENG etc.)
        if adm0 in ADM0_OIL:
            _add(row, "oil", ADM0_OIL[adm0])
        if adm0 in ADM0_RUBBER:
            _add(row, "rubber", ADM0_RUBBER[adm0])
        if adm0 in ADM0_CHROMIUM:
            _add(row, "chromium", ADM0_CHROMIUM[adm0])
        if adm0 in ADM0_TUNGSTEN:
            _add(row, "tungsten", ADM0_TUNGSTEN[adm0])
        if adm0 in ADM0_ALUMINUM:
            _add(row, "aluminum", ADM0_ALUMINUM[adm0])

        for n in NAME_OIL:
            if n in name:
                _add(row, "oil", 3)
        for n in NAME_RUBBER:
            if n in name:
                _add(row, "rubber", 2)

        # ENG/FRA colonial rubber from owned tropical adm0 already handled
        # Romanian oil often under SOV/GER ownership paint — name + ROU missing: use Ploiești name
        if "ploie" in name or "prahova" in name:
            _add(row, "oil", 3)

        for k, v in row.items():
            if isinstance(v, (int, float)) and float(v) > 0:
                counts[k] += 1
        provs[str(pid)] = row

    report = {
        "provinces": len(provs),
        "resource_province_counts": dict(counts),
        "majors": {},
    }
    for tag in ("GER", "USA", "SOV", "ENG", "FRA", "JAP", "ITA", "POL", "CHI"):
        tc = Counter()
        for pid, p in base.items():
            if own.get(str(pid)) != tag:
                continue
            row = provs.get(str(pid)) or {}
            for k, v in row.items():
                try:
                    if float(v) > 0:
                        tc[k] += 1
                except (TypeError, ValueError):
                    pass
        report["majors"][tag] = dict(tc)

    if write:
        res_doc["provinces"] = provs
        res_doc["meta"] = {
            "source": "paint_world_accurate_strategic_resources.py",
            "version": "hoi_strategic_v1",
            "resources": sorted(counts.keys()),
            "report": report,
        }
        _write(D / "province_resources_layer.json", res_doc)
        man_path = D / "manifest_world_accurate.json"
        if man_path.is_file():
            man = _load(man_path)
            man["strategic_resources"] = {
                "version": "hoi_strategic_v1",
                "resource_province_counts": dict(counts),
            }
            _write(man_path, man)

    print(json.dumps(report, indent=2))
    return report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    paint(write=bool(args.write))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
