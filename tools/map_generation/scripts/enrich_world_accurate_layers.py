#!/usr/bin/env python3
"""Enrich provinces_world_accurate with states, super-regions, economy/city stubs, era indexes.

Does not renumber IDs. Safe to re-run.

  python3 tools/map_generation/scripts/enrich_world_accurate_layers.py --write
"""
from __future__ import annotations

import argparse
import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"
NUTS = ROOT / "data" / "provinces_pilot_europe_nuts3"
WORLD = ROOT / "data" / "provinces_world_full"

# US state FIPS → name (partial; unknowns use STATE code)
US_STATE_NAMES = {
    "01": "Alabama", "02": "Alaska", "04": "Arizona", "05": "Arkansas", "06": "California",
    "08": "Colorado", "09": "Connecticut", "10": "Delaware", "11": "District of Columbia",
    "12": "Florida", "13": "Georgia", "15": "Hawaii", "16": "Idaho", "17": "Illinois",
    "18": "Indiana", "19": "Iowa", "20": "Kansas", "21": "Kentucky", "22": "Louisiana",
    "23": "Maine", "24": "Maryland", "25": "Massachusetts", "26": "Michigan", "27": "Minnesota",
    "28": "Mississippi", "29": "Missouri", "30": "Montana", "31": "Nebraska", "32": "Nevada",
    "33": "New Hampshire", "34": "New Jersey", "35": "New Mexico", "36": "New York",
    "37": "North Carolina", "38": "North Dakota", "39": "Ohio", "40": "Oklahoma", "41": "Oregon",
    "42": "Pennsylvania", "44": "Rhode Island", "45": "South Carolina", "46": "South Dakota",
    "47": "Tennessee", "48": "Texas", "49": "Utah", "50": "Vermont", "51": "Virginia",
    "53": "Washington", "54": "West Virginia", "55": "Wisconsin", "56": "Wyoming",
    "72": "Puerto Rico",
}

# US census divisions → strategic region ids (offset 200+)
US_DIVISIONS = {
    "New England": {"09", "23", "25", "33", "44", "50"},
    "Mid-Atlantic": {"34", "36", "42"},
    "East North Central": {"17", "18", "26", "39", "55"},
    "West North Central": {"19", "20", "27", "29", "31", "38", "46"},
    "South Atlantic": {"10", "11", "12", "13", "24", "37", "45", "51", "54"},
    "East South Central": {"01", "21", "28", "47"},
    "West South Central": {"05", "22", "40", "48"},
    "Mountain": {"04", "08", "16", "30", "32", "35", "49", "56"},
    "Pacific": {"02", "06", "15", "41", "53"},
}


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _write(path: Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def enrich(write: bool = True) -> dict:
    base = {int(p["id"]): p for p in _load(D / "provinces_base.json")["provinces"]}
    geo = {int(p["id"]): p for p in _load(D / "provinces_geometry.json")["provinces"]}
    own = _load(D / "province_ownership_1936.json").get("owners", {})
    sr = _load(D / "strategic_regions.json")
    mem = _load(D / "hierarchy_membership_1936.json")
    p2r = dict(mem.get("province_to_region") or {})

    report = {"provinces": len(base)}

    # --- States ---
    states: List[dict] = []
    p2s: Dict[str, int] = {}
    state_id = 1
    # Europe: copy NUTS states if present
    nuts_states_path = NUTS / "province_states.json"
    if nuts_states_path.is_file():
        ns = _load(nuts_states_path)
        for s in ns.get("states") or []:
            sid = int(s.get("id", 0)) or state_id
            pids = [int(x) for x in s.get("province_ids") or [] if int(x) in base]
            if not pids:
                continue
            states.append({
                "id": state_id,
                "name": str(s.get("name", f"State {state_id}")),
                "province_ids": pids,
                "meta": {"source": "nuts3_states", "orig_id": sid},
            })
            for pid in pids:
                p2s[str(pid)] = state_id
            state_id += 1
    report["europe_states"] = state_id - 1

    # US: group by STATE FIPS from meta.tiger geoid or name
    us_by_state: Dict[str, List[int]] = defaultdict(list)
    for pid, p in base.items():
        if not (800000 <= pid < 900000):
            continue
        meta = p.get("meta") if isinstance(p.get("meta"), dict) else {}
        geoid = str(meta.get("tiger_geoid") or meta.get("geoid") or "")
        st = str(meta.get("statefp") or "")
        if not st and len(geoid) >= 2:
            st = geoid[:2]
        if not st:
            st = "00"
        us_by_state[st].append(pid)
    us_state_start = state_id
    for st, pids in sorted(us_by_state.items()):
        name = US_STATE_NAMES.get(st, f"US State {st}")
        states.append({"id": state_id, "name": name, "province_ids": sorted(pids), "meta": {"statefp": st, "source": "us_fips"}})
        for pid in pids:
            p2s[str(pid)] = state_id
        state_id += 1
    report["us_states"] = state_id - us_state_start

    # RoW: one state per country (adm0)
    row_by: Dict[str, List[int]] = defaultdict(list)
    row_admin: Dict[str, str] = {}
    for pid, p in base.items():
        if pid < 900000 or pid >= 950000:
            continue
        meta = p.get("meta") if isinstance(p.get("meta"), dict) else {}
        adm0 = str(meta.get("adm0_a3") or "XXX")
        row_by[adm0].append(pid)
        row_admin[adm0] = str(meta.get("admin") or adm0)
    row_start = state_id
    for adm0, pids in sorted(row_by.items()):
        states.append({
            "id": state_id,
            "name": row_admin.get(adm0, adm0),
            "province_ids": sorted(pids),
            "meta": {"adm0_a3": adm0, "source": "ne_admin1_country"},
        })
        for pid in pids:
            p2s[str(pid)] = state_id
        state_id += 1
    report["row_states"] = state_id - row_start
    report["states_total"] = len(states)

    # --- Expand strategic regions: US divisions ---
    regions = list(sr.get("regions") or [])
    existing_ids = {int(r.get("id", 0)) for r in regions}
    next_rid = max(existing_ids | {0}) + 1
    # Remove coarse "North America" (id 2) province list if we split US
    us_div_start = next_rid
    for div_name, fips_set in US_DIVISIONS.items():
        pids = []
        for st, plist in us_by_state.items():
            if st in fips_set:
                pids.extend(plist)
        if not pids:
            continue
        rid = next_rid
        next_rid += 1
        regions.append({
            "id": rid,
            "name": div_name,
            "province_ids": sorted(set(pids)),
            "province_count": len(set(pids)),
            "meta": {"source": "us_census_division"},
        })
        for pid in pids:
            p2r[str(pid)] = rid
    # leftover US not in divisions
    div_pids = set()
    for r in regions:
        if (r.get("meta") or {}).get("source") == "us_census_division":
            div_pids.update(int(x) for x in r.get("province_ids") or [])
    leftover_us = [pid for st, plist in us_by_state.items() for pid in plist if pid not in div_pids]
    if leftover_us:
        regions.append({
            "id": next_rid,
            "name": "United States Other",
            "province_ids": sorted(leftover_us),
            "province_count": len(leftover_us),
        })
        for pid in leftover_us:
            p2r[str(pid)] = next_rid
        next_rid += 1

    # Rebuild province lists for non-US coarse regions from p2r
    for r in regions:
        rid = int(r["id"])
        if (r.get("meta") or {}).get("source") == "us_census_division":
            continue
        if rid == 2:  # old North America coarse — clear US counties
            r["province_ids"] = sorted(int(pid) for pid, rr in p2r.items() if int(rr) == 2 and int(pid) < 800000)
            r["province_count"] = len(r["province_ids"])

    report["strategic_regions"] = len(regions)

    # --- Super regions ---
    super_regions = [
        {"id": 1, "name": "Europe Theater", "region_ids": [rid for rid in range(100, 120) if rid in {int(r["id"]) for r in regions}]},
        {"id": 2, "name": "Americas Theater", "region_ids": []},
        {"id": 3, "name": "Afro-Eurasia East Theater", "region_ids": []},
        {"id": 4, "name": "Global Seas", "region_ids": [10]},
    ]
    # classify region ids
    name_to_super = {
        "Europe": 1, "Germany": 1, "France": 1, "Italy": 1, "Balkans": 1, "British Isles": 1,
        "Iberia": 1, "Nordic": 1, "Baltic": 1, "Central Europe": 1, "Low Countries": 1,
        "Eastern Frontiers": 1, "Western Mediterranean": 1,
        "North America": 2, "Latin America": 2, "New England": 2, "Mid-Atlantic": 2,
        "East North Central": 2, "West North Central": 2, "South Atlantic": 2,
        "East South Central": 2, "West South Central": 2, "Mountain": 2, "Pacific": 2,
        "United States": 2,
        "Africa": 3, "Middle East": 3, "South Asia": 3, "East Asia": 3, "Southeast Asia": 3,
        "Oceania": 3, "Central Asia": 3,
        "World Oceans": 4,
    }
    for r in regions:
        rid = int(r["id"])
        nm = str(r.get("name", ""))
        sid = 3
        for key, s in name_to_super.items():
            if key.lower() in nm.lower():
                sid = s
                break
        for s in super_regions:
            if int(s["id"]) == sid and rid not in s["region_ids"]:
                s["region_ids"].append(rid)
    for s in super_regions:
        s["region_ids"] = sorted(s["region_ids"])

    p2sr: Dict[str, int] = {}
    rid_to_super = {}
    for s in super_regions:
        for rid in s["region_ids"]:
            rid_to_super[int(rid)] = int(s["id"])
    for pid_s, rid in p2r.items():
        p2sr[pid_s] = rid_to_super.get(int(rid), 3)

    # --- Economy / city / resources stubs ---
    city = {}
    economy = {}
    resources = {}
    terrain = {}
    for pid, p in base.items():
        g = geo.get(pid) or {}
        pts = g.get("points") or []
        area = 0.0
        if len(pts) >= 3:
            a = 0.0
            n = len(pts)
            for i in range(n):
                x1, y1 = float(pts[i][0]), float(pts[i][1])
                x2, y2 = float(pts[(i + 1) % n][0]), float(pts[(i + 1) % n][1])
                a += x1 * y2 - x2 * y1
            area = abs(a) * 0.5
        terr = str(p.get("terrain", "plains"))
        domain = str(p.get("domain", "land"))
        is_sea = terr.lower() in ("sea", "ocean", "water", "lake")
        pop = 0 if is_sea else int(min(5_000_000, max(20_000, area * 40)))
        factories = 0 if is_sea else (3 if 710000 <= pid < 800000 else (2 if 800000 <= pid < 900000 else 1))
        infra = 1 if is_sea else (4 if 710000 <= pid < 800000 else 3)
        economy[str(pid)] = {
            "population": pop,
            "factories": factories,
            "infrastructure": infra,
            "development_level": 2 if not is_sea else 0,
        }
        resources[str(pid)] = {} if is_sea else {"coal": 1 if factories >= 2 else 0, "steel": 1 if factories >= 3 else 0}
        terrain[str(pid)] = {"terrain": terr, "domain": domain if domain else ("sea" if is_sea else "land")}
        # city layer: mark larger / capital-ish names
        nm = str(p.get("name", ""))
        if not is_sea and (factories >= 2 or any(k in nm for k in ("Paris", "Berlin", "London", "Roma", "Tokyo", "New York", "Warszawa", "Moskov"))):
            city[str(pid)] = {"city_name": nm.split(",")[0][:40], "tier": 2 if factories >= 3 else 1}

    # Ownership era copies
    own1936 = _load(D / "province_ownership_1936.json") if (D / "province_ownership_1936.json").is_file() else {"owners": own}

    if write:
        _write(D / "province_states.json", {"states": states, "meta": {"source": "enrich_world_accurate_layers"}})
        _write(D / "super_regions.json", {"super_regions": super_regions})
        _write(D / "strategic_regions.json", {"regions": regions, "meta": sr.get("meta") or {}})
        for era in (1910, 1918, 1936, 2026, 1945):
            mem_out = {
                "version": 1,
                "era_year": era,
                "mode": "full",
                "seed_only": True,
                "province_to_region": p2r,
                "province_to_state": p2s,
                "province_to_super_region": p2sr,
            }
            _write(D / f"hierarchy_membership_{era}.json", mem_out)
        _write(D / "province_economy_layer.json", {"provinces": economy})
        _write(D / "province_resources_layer.json", {"provinces": resources})
        _write(D / "province_city_layer.json", {"provinces": city})
        _write(D / "province_terrain_layer.json", {"provinces": terrain})
        for era in (1910, 1918, 1945, 2026):
            # start from 1936; light-touch copy (full historical paint is later phase)
            _write(D / f"province_ownership_{era}.json", {
                "owners": dict(own1936.get("owners") or own),
                "meta": {"source": "copy_1936_stub", "era": era},
            })
        _write(D / "ownership_era_index.json", {
            "eras": [1910, 1918, 1936, 1945, 2026],
            "default": 1936,
            "files": {str(e): f"province_ownership_{e}.json" for e in (1910, 1918, 1936, 1945, 2026)},
        })
        _write(D / "membership_era_index.json", {
            "eras": [1910, 1918, 1936, 2026],
            "default": 1936,
            "files": {str(e): f"hierarchy_membership_{e}.json" for e in (1910, 1918, 1936, 2026)},
        })
        # naval chokepoints: copy world_full if exists, remap sea ids if possible
        choke_src = WORLD / "naval_chokepoints.json"
        if choke_src.is_file():
            _write(D / "naval_chokepoints.json", _load(choke_src))
        man = _load(D / "manifest_world_accurate.json") if (D / "manifest_world_accurate.json").is_file() else {}
        man.update({
            "layers": ["states", "super_regions", "economy", "city", "resources", "terrain", "ownership_eras"],
            "states_n": len(states),
            "strategic_regions_n": len(regions),
            "super_regions_n": len(super_regions),
            "geometry_quality": "gis_hybrid_v1_2",
        })
        _write(D / "manifest_world_accurate.json", man)

    report["us_division_regions"] = sum(1 for r in regions if (r.get("meta") or {}).get("source") == "us_census_division")
    report["super_regions"] = len(super_regions)
    report["city_entries"] = len(city)
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", default=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    write = not args.dry_run
    rep = enrich(write=write)
    print(json.dumps(rep, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
