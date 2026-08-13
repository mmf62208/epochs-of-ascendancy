#!/usr/bin/env python3
"""Light historical ownership eras for provinces_world_accurate.

Starts from polished 1936 ownership and applies coarse era deltas
(1910 / 1918 / 1945 / 2026). Not museum-grade borders.

  python3 tools/map_generation/scripts/assign_world_accurate_ownership_eras.py --write
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"

WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean"})


def _load(p: Path) -> Any:
    return json.loads(p.read_text(encoding="utf-8"))


def _write(p: Path, obj: Any) -> None:
    p.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def _is_water(p: dict) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER_T or dom in WATER_D


def _adm0(p: dict) -> str:
    meta = p.get("meta") if isinstance(p.get("meta"), dict) else {}
    return str(meta.get("adm0_a3") or "").upper()


def _cntr(p: dict) -> str:
    return str(p.get("cntr_code") or "").upper()


def paint_era(year: int, base: Dict[int, dict], own1936: Dict[str, str]) -> Dict[str, str]:
    o = dict(own1936)
    for pid, p in base.items():
        if _is_water(p):
            continue
        a = _adm0(p)
        cc = _cntr(p)

        if year == 1910:
            if 710000 <= pid < 800000:
                if cc in ("AT", "HU", "CZ", "SK", "SI", "HR", "BA"):
                    o[str(pid)] = "AUS"
                if cc == "PL":
                    o[str(pid)] = "RUS" if pid % 2 == 0 else "GER"
            if a == "TUR" or cc == "TR":
                o[str(pid)] = "TUR"
            if a in ("TZA", "NAM", "CMR", "TGO", "PNG", "WSM"):
                o[str(pid)] = "GER"
            if a in ("KOR", "TWN"):
                o[str(pid)] = "JAP"
            if a == "PHL":
                o[str(pid)] = "USA"

        elif year == 1918:
            if 710000 <= pid < 800000 and cc == "AT":
                o[str(pid)] = "AUS"
            if 710000 <= pid < 800000 and cc == "HU":
                o[str(pid)] = "HUN"
            if 710000 <= pid < 800000 and cc in ("CZ", "SK"):
                o[str(pid)] = "CZE"
            if 710000 <= pid < 800000 and cc == "PL":
                o[str(pid)] = "POL"
            if 710000 <= pid < 800000 and cc in ("SI", "HR", "BA", "RS", "ME", "MK"):
                o[str(pid)] = "YUG"
            if a in ("SYR", "LBN"):
                o[str(pid)] = "FRA"
            if a in ("ISR", "PSE", "PSX", "JOR", "IRQ"):
                o[str(pid)] = "ENG"

        elif year == 1945:
            if 710000 <= pid < 800000 and cc in (
                "EE",
                "LV",
                "LT",
                "PL",
                "RO",
                "BG",
                "HU",
                "CZ",
                "SK",
            ):
                o[str(pid)] = "SOV"
            if a == "PRK":
                o[str(pid)] = "SOV"
            if a == "KOR":
                o[str(pid)] = "USA"
            if a == "TWN":
                o[str(pid)] = "CHI"
            if a == "JPN":
                o[str(pid)] = "USA"  # occupation

        elif year == 2026:
            modern = {
                "IND": "IND",
                "PAK": "PAK",
                "BGD": "BGD",
                "LKA": "SRL",
                "IDN": "IDN",
                "VNM": "VIE",
                "KHM": "CAM",
                "LAO": "LAO",
                "MMR": "BRM",
                "MYS": "MAL",
                "SGP": "SIN",
                "PHL": "PHI",
                "KOR": "ROK",
                "PRK": "DPR",
                "TWN": "TWN",
                "CHN": "CHI",
                "JPN": "JAP",
                "AUS": "AST",
                "NZL": "NZL",
                "ZAF": "SAF",
                "EGY": "EGY",
                "NGA": "NGA",
                "KEN": "KEN",
                "ETH": "ETH",
                "DZA": "ALG",
                "MAR": "MOR",
                "TUN": "TUN",
                "LBY": "LBA",
                "IRQ": "IRQ",
                "IRN": "PER",
                "SAU": "SAU",
                "ISR": "ISR",
                "TUR": "TUR",
                "UKR": "UKR",
                "BLR": "BLR",
                "KAZ": "KAZ",
                "RUS": "RUS",
                "CAN": "CAN",
                "MEX": "MEX",
                "BRA": "BRA",
                "ARG": "ARG",
                "CHL": "CHL",
                "COL": "COL",
                "PER": "PER",
                "VEN": "VEN",
                "CUB": "CUB",
                "THA": "SIA",
                "GHA": "GHA",
                "SEN": "SEN",
                "CIV": "CIV",
                "CMR": "CMR",
                "COD": "COG",
                "AGO": "ANG",
                "MOZ": "MOZ",
                "TZA": "TZA",
                "UGA": "UGA",
                "SDN": "SUD",
                "SDS": "SSD",
                "AFG": "AFG",
                "YEM": "YEM",
                "GEO": "GEO",
                "ARM": "ARM",
                "AZE": "AZE",
                "UZB": "UZB",
                "TKM": "TKM",
                "KGZ": "KGZ",
                "TJK": "TJK",
                "MNG": "MON",
            }
            if a in modern:
                o[str(pid)] = modern[a]
            if 710000 <= pid < 800000:
                modern_eu = {
                    "DE": "GER",
                    "FR": "FRA",
                    "UK": "ENG",
                    "IT": "ITA",
                    "ES": "SPA",
                    "PT": "POR",
                    "NL": "NLD",
                    "BE": "BEL",
                    "PL": "POL",
                    "CZ": "CZE",
                    "SK": "SVK",
                    "HU": "HUN",
                    "RO": "ROM",
                    "BG": "BUL",
                    "GR": "GRE",
                    "EL": "GRE",
                    "SE": "SWE",
                    "NO": "NOR",
                    "DK": "DNK",
                    "FI": "FIN",
                    "IE": "IRE",
                    "EE": "EST",
                    "LV": "LAT",
                    "LT": "LIT",
                    "SI": "SLV",
                    "HR": "CRO",
                    "RS": "SER",
                    "AL": "ALB",
                    "AT": "AUS",
                    "CH": "SWI",
                    "UA": "UKR",
                    "TR": "TUR",
                }
                if cc in modern_eu:
                    o[str(pid)] = modern_eu[cc]
            if 800000 <= pid < 900000:
                o[str(pid)] = "USA"
            if o.get(str(pid)) == "SOV":
                o[str(pid)] = "RUS"

    return o


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", default=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    write = not args.dry_run

    base = {int(p["id"]): p for p in _load(D / "provinces_base.json")["provinces"]}
    own1936 = _load(D / "province_ownership_1936.json").get("owners") or {}
    report = {}
    for year in (1910, 1918, 1945, 2026):
        owners = paint_era(year, base, own1936)
        land = [pid for pid, p in base.items() if not _is_water(p)]
        unowned = sum(1 for pid in land if not owners.get(str(pid)))
        top = Counter(owners.values()).most_common(10)
        report[year] = {"owned": len(owners), "unowned_land": unowned, "top": top}
        if write:
            _write(
                D / f"province_ownership_{year}.json",
                {
                    "owners": owners,
                    "meta": {
                        "source": "assign_world_accurate_ownership_eras",
                        "era": year,
                        "note": "Light historical differentiation from 1936 base.",
                        "unowned_land": unowned,
                        "top": top,
                    },
                },
            )
    if write:
        _write(
            D / "ownership_era_index.json",
            {
                "eras": [1910, 1918, 1936, 1945, 2026],
                "default": 1936,
                "files": {
                    str(e): f"province_ownership_{e}.json"
                    for e in (1910, 1918, 1936, 1945, 2026)
                },
                "meta": {"source": "assign_world_accurate_ownership_eras"},
            },
        )
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
