#!/usr/bin/env python3
"""Generate multi-era ownership tables for provinces_world_full (seed-only).

Produces province_ownership_{year}.json for 1910, 1918, 1936, 1945, 2026.
Scenario load seeds owners once; never reapplied on year tick (player agency).

Usage:
  python3 tools/map_generation/scripts/assign_world_ownership_era.py --year 2026 --write
  python3 tools/map_generation/scripts/assign_world_ownership_era.py --all --write
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

# Reuse pure geometry loaders + quality gates from 1936 assigner
from assign_world_ownership_1936 import (  # type: ignore
    DEFAULT_CAPITALS,
    EXTRA_ANCHORS,
    MAJORS,
    WATER_DOMAINS,
    is_water,
    load_provinces,
    quality_gates,
    assign_ownership as assign_ownership_1936_core,
)

from ownership_era_product import (  # type: ignore
    ERA_YEARS,
    ownership_table_path,
    player_agency_policy,
    write_era_index,
)

# Per-era theater eligibility (world_full tag set only).
THEATER_BY_ERA: Dict[int, Dict[str, List[str]]] = {
    1910: {
        "europe_core": ["GER", "FRA", "ENG", "SOV", "ITA", "NLD", "BEL", "SWE", "NOR", "DNK"],
        "mena_africa": ["ENG", "FRA", "ITA", "SOV"],
        "africa": ["ENG", "FRA", "ITA", "BEL"],
        "far_east": ["JAP", "SOV", "ENG", "USA", "FRA"],
        "north_america": ["USA", "ENG"],
        "south_america": ["USA", "ENG", "FRA"],
        "central_asia": ["SOV", "ENG"],
        "pacific": ["JAP", "USA", "ENG"],
        "oceania": ["ENG", "USA"],
        "sea": [],
    },
    1918: {
        "europe_core": ["GER", "FRA", "ENG", "SOV", "ITA", "POL", "FIN", "NLD", "BEL", "SWE", "NOR", "DNK"],
        "mena_africa": ["ENG", "FRA", "ITA"],
        "africa": ["ENG", "FRA", "ITA", "BEL"],
        "far_east": ["JAP", "SOV", "ENG", "USA"],
        "north_america": ["USA", "ENG"],
        "south_america": ["USA", "ENG"],
        "central_asia": ["SOV", "ENG"],
        "pacific": ["JAP", "USA", "ENG"],
        "oceania": ["ENG", "USA"],
        "sea": [],
    },
    1936: {
        "europe_core": ["GER", "FRA", "ENG", "SOV", "ITA", "POL", "FIN", "NOR", "SWE", "DNK", "NLD", "BEL"],
        "mena_africa": ["ENG", "FRA", "ITA", "SOV"],
        "africa": ["ENG", "FRA", "ITA", "BEL"],
        "far_east": ["JAP", "SOV", "ENG", "USA", "FRA"],
        "north_america": ["USA", "ENG"],
        "south_america": ["USA", "ENG", "FRA"],
        "central_asia": ["SOV", "ENG"],
        "pacific": ["JAP", "USA", "ENG"],
        "oceania": ["ENG", "USA"],
        "sea": [],
    },
    1945: {
        "europe_core": ["SOV", "USA", "ENG", "FRA", "POL", "GER", "ITA", "FIN", "NLD", "BEL", "SWE", "NOR", "DNK"],
        "mena_africa": ["ENG", "FRA", "USA", "SOV"],
        "africa": ["ENG", "FRA", "BEL", "USA"],
        "far_east": ["USA", "SOV", "JAP", "ENG", "FRA"],
        "north_america": ["USA", "ENG"],
        "south_america": ["USA", "ENG"],
        "central_asia": ["SOV"],
        "pacific": ["USA", "JAP", "ENG"],
        "oceania": ["USA", "ENG"],
        "sea": [],
    },
    # 2026: decolonized spheres — USA global, SOV/Russia-ish, GER reunified Europe weight, ENG/FRA reduced colonies
    2026: {
        "europe_core": ["GER", "FRA", "ENG", "POL", "ITA", "SOV", "FIN", "SWE", "NOR", "DNK", "NLD", "BEL", "USA"],
        "mena_africa": ["USA", "FRA", "ENG", "SOV", "ITA"],
        "africa": ["USA", "FRA", "ENG", "BEL"],
        "far_east": ["USA", "JAP", "SOV", "ENG"],
        "north_america": ["USA"],
        "south_america": ["USA", "BRA"] if False else ["USA"],  # BRA not in world_full tags
        "central_asia": ["SOV"],
        "pacific": ["USA", "JAP"],
        "oceania": ["USA", "ENG"],
        "sea": [],
    },
}

MAJOR_HOME_BY_ERA: Dict[int, Dict[str, Set[str]]] = {
    1910: {
        "GER": {"europe_core"},
        "FRA": {"europe_core", "mena_africa", "africa"},
        "ENG": {"europe_core", "mena_africa", "africa", "far_east", "oceania", "pacific"},
        "USA": {"north_america", "pacific"},
        "SOV": {"europe_core", "central_asia", "far_east"},
        "ITA": {"europe_core", "mena_africa"},
        "JAP": {"far_east", "pacific"},
    },
    1918: {
        "GER": {"europe_core"},
        "FRA": {"europe_core", "mena_africa", "africa"},
        "ENG": {"europe_core", "mena_africa", "africa", "far_east", "oceania", "pacific"},
        "USA": {"north_america", "pacific", "europe_core"},
        "SOV": {"europe_core", "central_asia"},
        "ITA": {"europe_core", "mena_africa"},
        "JAP": {"far_east", "pacific"},
        "POL": {"europe_core"},
    },
    1936: {
        "GER": {"europe_core"},
        "FRA": {"europe_core", "mena_africa", "africa"},
        "ENG": {"europe_core", "mena_africa", "africa", "far_east", "oceania", "pacific"},
        "USA": {"north_america", "pacific", "far_east"},
        "SOV": {"europe_core", "central_asia", "far_east"},
        "ITA": {"europe_core", "mena_africa", "africa"},
        "JAP": {"far_east", "pacific"},
    },
    1945: {
        "GER": {"europe_core"},
        "FRA": {"europe_core", "africa"},
        "ENG": {"europe_core", "mena_africa", "oceania"},
        "USA": {"north_america", "pacific", "far_east", "europe_core", "oceania"},
        "SOV": {"europe_core", "central_asia", "far_east"},
        "ITA": {"europe_core"},
        "JAP": {"far_east"},
        "POL": {"europe_core"},
    },
    2026: {
        "GER": {"europe_core"},
        "FRA": {"europe_core"},
        "ENG": {"europe_core"},
        "USA": {"north_america", "pacific", "far_east", "oceania", "south_america", "mena_africa", "africa"},
        "SOV": {"central_asia", "europe_core", "far_east"},
        "ITA": {"europe_core"},
        "JAP": {"far_east", "pacific"},
        "POL": {"europe_core"},
    },
}

# Distance multipliers applied when scoring anchors (lower = preferred).
ERA_TAG_DISTANCE_BIAS: Dict[int, Dict[str, float]] = {
    2026: {
        "USA": 0.72,
        "SOV": 0.88,
        "GER": 0.85,
        "ENG": 1.15,  # decolonized — less overseas pull
        "FRA": 1.12,
        "JAP": 0.95,
        "POL": 0.9,
    },
    1945: {
        "USA": 0.78,
        "SOV": 0.75,
        "ENG": 0.95,
        "FRA": 1.0,
        "GER": 1.25,
        "JAP": 1.2,
    },
    1910: {
        "ENG": 0.85,
        "FRA": 0.9,
        "GER": 0.88,
        "SOV": 0.9,
        "USA": 0.95,
    },
}


def assign_ownership_era(
    provinces: List[Dict[str, Any]],
    centroids: Dict[int, Tuple[float, float]],
    capitals: Dict[str, int],
    tags: Sequence[str],
    era_year: int,
) -> Dict[str, Any]:
    """Voronoi-ish assignment with era-specific theater eligibility + bias."""
    tag_set = {str(t).strip().upper() for t in tags if str(t).strip()}
    caps = {str(k).upper(): int(v) for k, v in capitals.items() if str(k).upper() in tag_set}
    by_id = {int(p["id"]): p for p in provinces}
    for tag, pid in list(caps.items()):
        if pid not in by_id or is_water(by_id[pid]):
            raise ValueError("Capital for %s id=%d missing or water" % (tag, pid))

    theater_tags = THEATER_BY_ERA.get(int(era_year)) or THEATER_BY_ERA[1936]
    home = MAJOR_HOME_BY_ERA.get(int(era_year)) or MAJOR_HOME_BY_ERA[1936]
    dist_bias = ERA_TAG_DISTANCE_BIAS.get(int(era_year)) or {}

    anchors: Dict[str, List[Tuple[float, float]]] = {}
    for tag, pid in caps.items():
        pts: List[Tuple[float, float]] = [centroids.get(pid, (0.0, 0.0))]
        for aid in EXTRA_ANCHORS.get(tag, []):
            if aid in by_id and not is_water(by_id[aid]):
                pts.append(centroids.get(aid, (0.0, 0.0)))
        anchors[tag] = pts

    # Colonial overseas anchors — weaker after 1945, very weak 2026 for ENG/FRA
    overseas = {
        "ENG": list(EXTRA_ANCHORS.get("ENG_OVERSEAS", [])),
        "FRA": list(EXTRA_ANCHORS.get("FRA_OVERSEAS", [])),
        "ITA": list(EXTRA_ANCHORS.get("ITA_OVERSEAS", [])),
        "USA": [40000, 20054, 20055],  # NY + Pacific-adjacent pressure
    }
    if int(era_year) >= 2026:
        # Decolonization: transfer colonial pressure to USA
        overseas["ENG"] = []
        overseas["FRA"] = []
        overseas["ITA"] = []
    elif int(era_year) >= 1945:
        overseas["ENG"] = overseas["ENG"][:2]
        overseas["FRA"] = overseas["FRA"][:1]

    for tag, aids in overseas.items():
        if tag not in anchors:
            continue
        for aid in aids:
            if aid in by_id and not is_water(by_id[aid]):
                anchors[tag].append(centroids.get(aid, (0.0, 0.0)))

    owners: Dict[int, str] = {}
    capital_pids = set(caps.values())
    for tag, pid in caps.items():
        owners[pid] = tag
    for tag, aids in EXTRA_ANCHORS.items():
        if tag.endswith("_OVERSEAS") or tag not in caps:
            continue
        for aid in aids:
            if aid in capital_pids and caps.get(tag) != aid:
                continue
            if aid in by_id and not is_water(by_id[aid]):
                owners[aid] = tag

    def nearest_tag(cx: float, cy: float, eligible: List[str], theater: str) -> str:
        best_tag = eligible[0]
        best_d = float("inf")
        for tag in eligible:
            for tx, ty in anchors.get(tag, []):
                mult = 0.80 if theater in home.get(tag, set()) else 1.0
                mult *= float(dist_bias.get(tag, 1.0))
                if tag == "ITA" and theater in ("africa", "mena_africa") and era_year >= 1945:
                    mult *= 1.35
                if tag == "JAP" and theater not in ("far_east", "pacific") and era_year >= 1945:
                    mult *= 1.4
                if tag == "ENG" and theater not in home.get("ENG", set()) and era_year >= 2026:
                    mult *= 1.35
                d = ((cx - tx) ** 2 + (cy - ty) ** 2) * mult
                if d < best_d:
                    best_d = d
                    best_tag = tag
        return best_tag

    for p in provinces:
        pid = int(p["id"])
        if pid in owners:
            continue
        if is_water(p):
            owners[pid] = ""
            continue
        theater = str(p.get("theater") or "europe_core")
        eligible = [t for t in (theater_tags.get(theater) or list(tag_set)) if t in caps]
        if not eligible:
            eligible = [t for t in tag_set if t in caps]
        cx, cy = centroids.get(pid, (0.0, 0.0))
        owners[pid] = nearest_tag(cx, cy, eligible, theater)

    # Europe rebalance
    europe_tags = [t for t in (theater_tags.get("europe_core") or []) if t in caps]
    for p in provinces:
        pid = int(p["id"])
        if is_water(p) or str(p.get("theater") or "") != "europe_core":
            continue
        if pid in capital_pids:
            continue
        cx, cy = centroids.get(pid, (0.0, 0.0))
        owners[pid] = nearest_tag(cx, cy, europe_tags, "europe_core")

    # Central Asia → SOV preferred when available
    if "SOV" in caps:
        for p in provinces:
            pid = int(p["id"])
            if is_water(p) or str(p.get("theater") or "") != "central_asia":
                continue
            if pid == caps.get("SOV"):
                continue
            owners[pid] = "SOV"

    land_ids = [int(p["id"]) for p in provinces if not is_water(p)]
    water_ids = [int(p["id"]) for p in provinces if is_water(p)]
    by_tag: Dict[str, int] = {}
    theater_tag_land: Dict[str, Dict[str, int]] = {}
    for pid in land_ids:
        t = owners.get(pid, "")
        if t:
            by_tag[t] = by_tag.get(t, 0) + 1
            th = str(by_id[pid].get("theater") or "europe_core")
            theater_tag_land.setdefault(th, {})
            theater_tag_land[th][t] = theater_tag_land[th].get(t, 0) + 1
    water_owned = sum(1 for pid in water_ids if owners.get(pid))
    land_owned = sum(1 for pid in land_ids if owners.get(pid))
    land_coverage = land_owned / max(1, len(land_ids))

    owners_str = {str(k): v for k, v in owners.items()}
    return {
        "owners": owners_str,
        "capitals": {k: int(v) for k, v in caps.items()},
        "stats": {
            "province_count": len(provinces),
            "land_count": len(land_ids),
            "water_count": len(water_ids),
            "land_owned": land_owned,
            "land_coverage": land_coverage,
            "water_owned": water_owned,
            "by_tag_land": by_tag,
            "theater_tag_land": theater_tag_land,
            "era_year": int(era_year),
        },
    }


def run_era(
    data_dir: Path,
    era_year: int,
    scenario_path: Path,
    write: bool = False,
) -> Dict[str, Any]:
    provinces, cents = load_provinces(data_dir)
    scen = json.loads(scenario_path.read_text(encoding="utf-8"))
    tags = [str(c["tag"]).upper() for c in scen.get("countries") or []]
    capitals = {t: pid for t, pid in DEFAULT_CAPITALS.items() if t in tags}

    if int(era_year) == 1936:
        # Prefer existing battle-tested 1936 assigner core
        try:
            import assign_world_ownership_1936 as a1936  # type: ignore
            # temporarily patch theater if needed — use era assign for consistency across years
            result = assign_ownership_era(provinces, cents, capitals, tags, 1936)
        except Exception:
            result = assign_ownership_era(provinces, cents, capitals, tags, 1936)
    else:
        result = assign_ownership_era(provinces, cents, capitals, tags, era_year)

    # quality_gates expects owners as str keys already from 1936 style
    gates = quality_gates(result, tags, provinces)
    compact_owners = {k: v for k, v in result["owners"].items() if v}
    payload = {
        "meta": {
            "source": "assign_world_ownership_era.py",
            "era_year": int(era_year),
            "geometry_space": "world",
            "seed_only": True,
            "player_agency": player_agency_policy(),
            "notes": (
                "Approximate %d political spheres for playability; sea unowned; capitals forced. "
                "SEED ONLY at scenario load — never reapplied on year tick."
            ) % int(era_year),
        },
        "capitals": result["capitals"],
        "owners": compact_owners,
        "stats": result["stats"],
        "gates": gates,
    }
    out: Dict[str, Any] = {
        "era_year": int(era_year),
        "stats": result["stats"],
        "gates": gates,
        "owner_n": len(compact_owners),
        "wrote": False,
    }
    if write:
        path = ownership_table_path(data_dir, era_year)
        path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        out["path"] = str(path)
        out["wrote"] = True
    return out


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument("--scenario", default="data/scenarios/world_full.json")
    ap.add_argument("--year", type=int, default=0, help="Single era year")
    ap.add_argument("--all", action="store_true", help="Write all ERA_YEARS")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args(argv)
    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    scen = Path(args.scenario)
    if not scen.is_absolute():
        scen = ROOT / scen
    years = list(ERA_YEARS) if args.all else ([int(args.year)] if args.year else [2026])
    all_ok = True
    for y in years:
        out = run_era(data_dir, y, scen, write=bool(args.write))
        ok = bool(out.get("gates", {}).get("pass"))
        all_ok = all_ok and ok
        print(("[%s] era=%d owners=%d pass=%s" % (
            "WROTE" if out.get("wrote") else "DRY",
            y, out.get("owner_n"), ok,
        )))
        print("  by_tag:", (out.get("stats") or {}).get("by_tag_land"))
    if args.write:
        idx = write_era_index(data_dir)
        print("index:", idx)
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
