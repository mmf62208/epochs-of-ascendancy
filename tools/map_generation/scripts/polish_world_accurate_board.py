#!/usr/bin/env python3
"""Polish provinces_world_accurate: 1936 ownership, chokepoints, adjacency retune.

  python3 tools/map_generation/scripts/polish_world_accurate_board.py --write
  python3 tools/map_generation/scripts/polish_world_accurate_board.py --write --quant 1.25 --skip-adj
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

D = ROOT / "data" / "provinces_world_accurate"
WF = ROOT / "data" / "provinces_world_full"
SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"

# ISO3 (Natural Earth adm0_a3) → 1936-style owner tag.
# Independent nations keep local tags; colonies map to imperial majors.
# Not museum-grade history — playable spheres for the accurate board.
ADM0_TAG: Dict[str, str] = {
    # Americas — independents (not USA dump)
    "USA": "USA",
    "CAN": "ENG",
    "MEX": "MEX",
    "GTM": "GUA",
    "HND": "HON",
    "SLV": "ELS",
    "NIC": "NIC",
    "CRI": "COS",
    "PAN": "PAN",
    "CUB": "CUB",
    "HTI": "HAI",
    "DOM": "DOM",
    "JAM": "ENG",
    "TTO": "ENG",
    "BHS": "ENG",
    "BLZ": "ENG",
    "PRI": "USA",
    "VIR": "USA",
    "CYM": "ENG",
    "ABW": "NLD",
    "CUW": "NLD",
    "DMA": "ENG",
    "COL": "COL",
    "VEN": "VEN",
    "ECU": "ECU",
    "PER": "PER",
    "BOL": "BOL",
    "BRA": "BRA",
    "PRY": "PAR",
    "CHL": "CHL",
    "ARG": "ARG",
    "URY": "URG",
    "GUY": "ENG",
    "SUR": "NLD",
    "GUF": "FRA",
    "FLK": "ENG",
    "SGS": "ENG",
    # East Asia
    "CHN": "CHI",
    "HKG": "ENG",
    "TWN": "JAP",
    "JPN": "JAP",
    "KOR": "JAP",
    "PRK": "JAP",
    "MNG": "MON",
    "MAC": "POR",
    # South / SE Asia
    "IND": "ENG",
    "PAK": "ENG",
    "BGD": "ENG",
    "NPL": "NEP",
    "BTN": "BHU",
    "LKA": "ENG",
    "MDV": "ENG",
    "MMR": "ENG",
    "THA": "SIA",
    "LAO": "FRA",
    "KHM": "FRA",
    "VNM": "FRA",
    "MYS": "ENG",
    "SGP": "ENG",
    "IDN": "NLD",
    "BRN": "ENG",
    "PHL": "USA",
    "TLS": "POR",
    "PNG": "ENG",
    "SOL": "ENG",  # Solomon Islands (NE code)
    "SLB": "ENG",
    # Oceania
    "AUS": "ENG",
    "NZL": "ENG",
    "FJI": "ENG",
    "VUT": "FRA",
    "NCL": "FRA",
    "PYF": "FRA",
    "WSM": "NZL",  # Western Samoa mandate NZ
    "TON": "ENG",
    "KIR": "ENG",
    "FSM": "JAP",  # Mandates approx
    "GUM": "USA",
    "NIU": "NZL",
    "HMD": "ENG",
    "ATF": "FRA",
    # Africa
    "ZAF": "ENG",
    "EGY": "ENG",
    "SDN": "ENG",
    "SDS": "ENG",  # South Sudan → Anglo-Egyptian Sudan 1936
    "SSD": "ENG",
    "ETH": "ITA",  # mid-conquest 1936
    "ERI": "ITA",
    "DJI": "FRA",
    "SOM": "ITA",
    "KEN": "ENG",
    "UGA": "ENG",
    "TZA": "ENG",
    "RWA": "BEL",
    "BDI": "BEL",
    "COD": "BEL",
    "COG": "FRA",
    "GAB": "FRA",
    "CMR": "FRA",
    "NGA": "ENG",
    "NER": "FRA",
    "TCD": "FRA",
    "MLI": "FRA",
    "BFA": "FRA",
    "SEN": "FRA",
    "GIN": "FRA",
    "CIV": "FRA",
    "GHA": "ENG",
    "TGO": "FRA",
    "BEN": "FRA",
    "AGO": "POR",
    "ZMB": "ENG",
    "ZWE": "ENG",
    "BWA": "ENG",
    "NAM": "ENG",
    "MOZ": "POR",
    "MDG": "FRA",
    "MWI": "ENG",
    "MAR": "FRA",
    "DZA": "FRA",
    "TUN": "FRA",
    "LBY": "ITA",
    "ESH": "SPA",
    "SAH": "SPA",
    "CAF": "FRA",
    "LBR": "LIB",
    "MRT": "FRA",
    "LSO": "ENG",
    "CPV": "POR",
    "GNB": "POR",
    "MUS": "ENG",
    "GNQ": "SPA",
    "GMB": "ENG",
    "SLE": "ENG",
    "SWZ": "ENG",
    "COM": "FRA",
    "STP": "POR",
    "SHN": "ENG",
    # MENA / Caucasus / Central Asia
    "TUR": "TUR",
    "SYR": "FRA",
    "IRQ": "ENG",
    "IRN": "PER",
    "SAU": "SAU",
    "YEM": "YEM",
    "OMN": "ENG",
    "ARE": "ENG",
    "QAT": "ENG",
    "BHR": "ENG",
    "KWT": "ENG",
    "JOR": "ENG",
    "ISR": "ENG",
    "LBN": "FRA",
    "PSE": "ENG",
    "PSX": "ENG",  # Palestine NE code
    "GEO": "SOV",
    "ARM": "SOV",
    "AZE": "SOV",
    "RUS": "SOV",
    "KAZ": "SOV",
    "UZB": "SOV",
    "TKM": "SOV",
    "KGZ": "SOV",
    "TJK": "SOV",
    "AFG": "AFG",
    "UKR": "SOV",
    "BLR": "SOV",
    "MDA": "ROM",
    "KOS": "YUG",
    "GRL": "DNK",
    "ISL": "DNK",
    "ALA": "FIN",
    "FRO": "DNK",
    "JEY": "ENG",
    "IMN": "ENG",
    "SPM": "FRA",
    "ALD": "FIN",  # Åland
    # Disputed / special NE codes
    "CYN": "TUR",  # Northern Cyprus approx
    "KAS": "ENG",  # Kashmir → British India sphere
    "KAB": "SOV",  # Abkhazia → SOV sphere
    "ATA": "ENG",  # Antarctica claim proxy (unowned play — use ENG research base)
    # Europe leftover if any RoW fragments
    "GBR": "ENG",
    "IRL": "IRE",
    "ESP": "SPA",
    "PRT": "POR",
    "NLD": "NLD",
    "BEL": "BEL",
    "LUX": "LUX",
    "CHE": "SWI",
    "AUT": "AUS",
    "CZE": "CZE",
    "SVK": "CZE",
    "HUN": "HUN",
    "ROU": "ROM",
    "BGR": "BUL",
    "GRC": "GRE",
    "ALB": "ALB",
    "SRB": "YUG",
    "HRV": "YUG",
    "BIH": "YUG",
    "SVN": "YUG",
    "MKD": "YUG",
    "MNE": "YUG",
    "POL": "POL",
    "LTU": "LIT",
    "LVA": "LAT",
    "EST": "EST",
    "FIN": "FIN",
    "SWE": "SWE",
    "NOR": "NOR",
    "DNK": "DNK",
    "DEU": "GER",
    "FRA": "FRA",
    "ITA": "ITA",
    "UKR": "SOV",
}

WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean"})

# Name tokens that mark true naval choke / canal provinces (avoid "Kiel city", "Cape May").
CHOKE_NAME_TOKENS = (
    "gibraltar strait",
    "bosporus",
    "suez canal",
    "hormuz",
    "malacca strait",
    "tsushima strait",
    "danish strait",
    "english channel",
    "mozambique channel",
    "gulf of aden",
    "bering approaches",
    "cape basin",
    "panama",
    "kiel canal",
    "singapore strait",
    "bab el",
    "bab-el",
    "ormuz",
    "dardanelles",
)

# Prefer exact / strong sea zone names on the accurate board.
CURATED_CHOKE_SUBSTRINGS = (
    "gibraltar strait",
    "bosporus",
    "suez canal zone",
    "hormuz approaches",
    "malacca strait",
    "tsushima strait",
    "danish straits",
    "english channel zone",
    "mozambique channel",
    "gulf of aden",
    "red sea zone",
    "persian gulf zone",
    "black sea zone",
    "panama",
    "cape basin approaches",
    "bering approaches",
)


def _load(p: Path) -> Any:
    return json.loads(p.read_text(encoding="utf-8"))


def _write(p: Path, obj: Any) -> None:
    p.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def _centroid(pts) -> Tuple[float, float]:
    if not pts:
        return 0.0, 0.0
    return sum(float(p[0]) for p in pts) / len(pts), sum(float(p[1]) for p in pts) / len(pts)


def _is_water(p: dict) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER_T or dom in WATER_D


def rebuild_ownership(base: Dict[int, dict], existing: Dict[str, str]) -> Dict[str, str]:
    """Full 1936 ownership from ISO3 + NUTS cntr + US block; keep good NUTS tags."""
    new: Dict[str, str] = {}

    # NUTS Europe: prefer existing ownership (already country-coded from pilot)
    for pid, p in base.items():
        if not (710000 <= pid < 800000):
            continue
        if _is_water(p):
            continue
        prev = existing.get(str(pid), "")
        if prev:
            new[str(pid)] = prev
            continue
        # fallback from cntr_code if present
        cc = str(p.get("cntr_code") or "").upper()
        # NUTS uses 2-letter mostly
        nuts_map = {
            "DE": "GER", "FR": "FRA", "UK": "ENG", "IT": "ITA", "ES": "SPA", "PT": "POR",
            "NL": "NLD", "BE": "BEL", "LU": "LUX", "AT": "AUS", "CH": "SWI", "PL": "POL",
            "CZ": "CZE", "SK": "CZE", "HU": "HUN", "RO": "ROM", "BG": "BUL", "GR": "GRE",
            "EL": "GRE", "SE": "SWE", "NO": "NOR", "DK": "DNK", "FI": "FIN", "IE": "IRE",
            "EE": "EST", "LV": "LAT", "LT": "LIT", "SI": "YUG", "HR": "YUG", "RS": "YUG",
            "AL": "ALB", "MK": "YUG", "ME": "YUG", "BA": "YUG", "XK": "YUG", "MT": "ENG",
            "CY": "ENG", "IS": "DNK", "TR": "TUR", "LI": "SWI",
        }
        if cc in nuts_map:
            new[str(pid)] = nuts_map[cc]

    # US counties
    for pid, p in base.items():
        if not (800000 <= pid < 900000):
            continue
        if _is_water(p):
            continue
        new[str(pid)] = "USA"

    # RoW NE admin1
    for pid, p in base.items():
        if not (900000 <= pid < 950000):
            continue
        if _is_water(p):
            continue
        meta = p.get("meta") if isinstance(p.get("meta"), dict) else {}
        adm0 = str(meta.get("adm0_a3") or "").upper()
        tag = ADM0_TAG.get(adm0)
        if tag:
            new[str(pid)] = tag
            continue
        # last resort: keep previous if any
        if existing.get(str(pid)):
            new[str(pid)] = existing[str(pid)]

    return new


def neighbor_fill_unowned(
    base: Dict[int, dict],
    own: Dict[str, str],
    adj: Dict[str, List[Any]],
    rounds: int = 8,
) -> Tuple[Dict[str, str], int]:
    """Paint unowned land from majority land-neighbor owner."""
    new = dict(own)
    filled = 0
    for _ in range(rounds):
        pending = []
        for pid, p in base.items():
            if _is_water(p):
                continue
            if new.get(str(pid)):
                continue
            pending.append(pid)
        if not pending:
            break
        updates: Dict[str, str] = {}
        for pid in pending:
            nbrs = adj.get(str(pid)) or adj.get(pid) or []
            votes: Counter = Counter()
            for n in nbrs:
                if isinstance(n, dict):
                    nid = n.get("id") or n.get("to") or n.get("province_id")
                else:
                    nid = n
                if nid is None:
                    continue
                ot = new.get(str(int(nid)), "")
                if ot:
                    votes[ot] += 1
            if votes:
                updates[str(pid)] = votes.most_common(1)[0][0]
        if not updates:
            break
        new.update(updates)
        filled += len(updates)
    return new, filled


def remap_chokepoints(base: Dict[int, dict], geo: Dict[int, dict]) -> dict:
    """Prefer real sea/strait zones + Panama; never random inland cities."""
    # 1) Collect strong name hits that are water OR Panama canal land
    curated: List[int] = []
    details: List[dict] = []
    for pid, p in base.items():
        nm = str(p.get("name") or "").lower()
        is_water = _is_water(p)
        is_panama = "panama" in nm and (
            "canal" in nm or is_water or str(p.get("domain", "")).lower() == "coastal_land"
        )
        # Panama province itself is a classic canal choke on RoW board
        if "panama" in nm and 900000 <= pid < 950000 and not is_water:
            is_panama = True
        if not is_water and not is_panama:
            continue
        if any(tok in nm for tok in CURATED_CHOKE_SUBSTRINGS) or is_panama:
            if pid not in curated:
                curated.append(pid)
                details.append({"to": pid, "name": p.get("name"), "via": "curated_name"})

    # 2) All domain=strait on board
    for pid, p in base.items():
        if str(p.get("domain", "")).lower() == "strait" and pid not in curated:
            curated.append(pid)
            details.append({"to": pid, "name": p.get("name"), "via": "domain_strait"})

    # 3) Map world_full choke centroids → nearest *water* accurate province only
    src_path = WF / "naval_chokepoints.json"
    mapped_from_wf = 0
    if src_path.is_file():
        src = _load(src_path)
        old_ids = [int(x) for x in src.get("chokepoint_province_ids") or []]
        wf_geo = {
            int(g["id"]): g
            for g in _load(WF / "provinces_geometry.json").get("provinces") or []
        }
        water_cand: List[Tuple[int, float, float]] = []
        for pid, g in geo.items():
            p = base.get(pid) or {}
            if not _is_water(p) and "panama" not in str(p.get("name", "")).lower():
                continue
            pts = g.get("points") or []
            if len(pts) < 3:
                continue
            cx, cy = _centroid(pts)
            water_cand.append((pid, cx, cy))

        for oid in old_ids:
            og = wf_geo.get(oid)
            if not og:
                continue
            # only project if source was water or known canal
            ob = None
            # soft: always project to nearest water
            ox, oy = _centroid(og.get("points") or [])
            best = None
            best_d = 1e18
            for pid, cx, cy in water_cand:
                d = (cx - ox) ** 2 + (cy - oy) ** 2
                if d < best_d:
                    best_d = d
                    best = pid
            # reject absurd long jumps (map units ~ equirect)
            if best is not None and best_d < (800.0 ** 2) and best not in curated:
                curated.append(best)
                details.append(
                    {
                        "from": oid,
                        "to": best,
                        "name": base.get(best, {}).get("name"),
                        "via": "wf_centroid",
                        "dist2": round(best_d, 1),
                    }
                )
                mapped_from_wf += 1

    # Dedup + drop pure inland false positives that slipped in
    cleaned: List[int] = []
    for pid in curated:
        p = base.get(pid) or {}
        nm = str(p.get("name") or "").lower()
        if _is_water(p) or "panama" in nm:
            cleaned.append(pid)

    # Cap noise: prefer unique name roots, keep all domain=strait + curated list
    final: List[int] = []
    seen_names: Set[str] = set()
    # Priority pass: domain strait + key names
    priority = []
    rest = []
    for pid in cleaned:
        p = base.get(pid) or {}
        nm = str(p.get("name") or "").lower()
        if str(p.get("domain", "")).lower() == "strait" or any(
            t in nm for t in ("gibraltar", "suez", "hormuz", "malacca", "bospor", "tsushima", "danish", "aden", "panama", "english channel")
        ):
            priority.append(pid)
        else:
            rest.append(pid)
    for pid in priority + rest:
        p = base.get(pid) or {}
        nm = str(p.get("name") or "")
        # collapse near-duplicate "Bering Approaches *" to few
        root = nm.split(" North")[0].split(" South")[0].split(" East")[0].split(" West")[0]
        root = root.split(" Central")[0].split(" Outer")[0].split(" Inner")[0]
        root = root.split(" Deep")[0].split(" Rise")[0].split(" Trough")[0]
        root = root.split(" Abyssal")[0].split(" Approaches Approaches")[0]
        key = root.strip().lower()
        if key in seen_names and "strait" not in key and "canal" not in key and "gibraltar" not in key:
            # allow up to 2 of channel-edge family
            if seen_names and key.count("mozambique") and sum(1 for s in seen_names if "mozambique" in s) < 2:
                pass
            else:
                continue
        seen_names.add(key)
        final.append(pid)
        if len(final) >= 48:
            break

    return {
        "meta": {
            "source": "polish_world_accurate_board.py",
            "count": len(final),
            "mapped_from_world_full": mapped_from_wf,
            "notes": "Sea/strait + Panama only; centroid map rejects inland false positives.",
        },
        "chokepoint_province_ids": sorted(final),
        "remap_details": details[:100],
        "sources": ["world_full naval_chokepoints", "domain=strait", "curated names"],
    }


def retune_adjacency(
    quant: float = 5.0,
    *,
    near_vertex_touch: float = 12.0,
    knn_k: int = 5,
) -> dict:
    """Retune accurate-board adjacency (D5.1).

    quant=5.0 keeps GIS shared-edge borders (e.g. GER Baden-Baden↔FRA Bas-Rhin).
    near_vertex residual lifts land_shared_coverage ~0.915 → ~0.97 without
    long-range KNN-only residual.
    """
    from shared_edge_adjacency_product import build_shared_edge_adjacency, load_board_geometry

    rings, water = load_board_geometry(D)
    res = build_shared_edge_adjacency(
        rings=rings,
        water=water,
        quant=quant,
        knn_k=knn_k,
        multi_quant=True,
        near_vertex_touch=near_vertex_touch,
        near_vertex_max_nbrs=6,
    )
    return {
        "version": 2,
        "method": res.get("method") or "shared_edge_plus_knn_fallback",
        "source": "shared_edge_adjacency_product",
        "quant": quant,
        "near_vertex_touch": near_vertex_touch,
        "knn_k": knn_k,
        "adjacency": res["adjacency"],
        "stats": res.get("stats") or {},
    }


def polish_sea_display_names(base_list: List[dict]) -> int:
    """Strip lat/lon suffixes from ocean cell names (scaffold residue)."""
    import re

    renamed = 0
    for p in base_list:
        if not _is_water(p):
            continue
        n = str(p.get("name") or "")
        new = re.sub(r"\s*\([^)]*[ENSW]\)\s*$", "", n).strip()
        new = re.sub(r"\s+\d+E\s+-?\d+N\s*$", "", new).strip()
        m = re.match(r"^(WestPac|EastPac|SouthPac|NorthPac)\s+\d", new, re.I)
        if m:
            basin = {
                "westpac": "Western Pacific Zone",
                "eastpac": "Eastern Pacific Zone",
                "southpac": "South Pacific Zone",
                "northpac": "North Pacific Zone",
            }.get(m.group(1).lower(), new)
            new = basin
        if new and new != n:
            p["name"] = new
            renamed += 1
    return renamed


def polish_capital_layers(
    base: Dict[int, dict],
    scenario_caps: Dict[str, int],
) -> dict:
    """Upgrade city/economy layers for scenario capitals + world cities."""
    city_path = D / "province_city_layer.json"
    econ_path = D / "province_economy_layer.json"
    city_doc = _load(city_path) if city_path.is_file() else {"provinces": {}}
    econ_doc = _load(econ_path) if econ_path.is_file() else {"provinces": {}}
    cities = city_doc.get("provinces") if isinstance(city_doc.get("provinces"), dict) else {}
    economy = econ_doc.get("provinces") if isinstance(econ_doc.get("provinces"), dict) else {}

    # Known friendly labels for accurate-board capital provinces
    labels: Dict[int, str] = {
        710300: "Berlin",
        710707: "Paris",
        711414: "London",
        800792: "Washington",
        900651: "Moscow",  # pre-densify RUS id (legacy)
        903461: "Moscow",  # legacy densify id
        903534: "Moscow",  # geoBoundaries RUS ADM1 (current)
        710963: "Rome",
        902369: "Tokyo",
        903995: "Tokyo",  # geoBoundaries JPN
        711112: "Warsaw",
    }
    # Extra major cities by name substring → label
    extra_name_labels = {
        "new york": "New York",
        "los angeles": "Los Angeles",
        "chicago": "Chicago",
        "hamburg": "Hamburg",
        "münchen": "Munich",
        "munchen": "Munich",
        "milano": "Milan",
        "napoli": "Naples",
        "marseille": "Marseille",
        "lyon": "Lyon",
        "manchester": "Manchester",
        "birmingham": "Birmingham",
        "glasgow": "Glasgow",
        "leningrad": "Leningrad",
        "sankt-peterburg": "Leningrad",
        "kyiv": "Kiev",
        "kiev": "Kiev",
        "osaka": "Osaka",
        "shanghai": "Shanghai",
        "beijing": "Beijing",
        "nanjing": "Nanjing",
        "mumbai": "Mumbai",
        "calcutta": "Calcutta",
        "delhi": "Delhi",
        "sydney": "Sydney",
        "melbourne": "Melbourne",
        "cairo": "Cairo",
        "istanbul": "Istanbul",
        "wien": "Vienna",
        "praha": "Prague",
        "budapest": "Budapest",
        "bucure": "Bucharest",
        "sofia": "Sofia",
        "athina": "Athens",
        "athen": "Athens",
        "madrid": "Madrid",
        "barcelona": "Barcelona",
        "lisboa": "Lisbon",
        "amsterdam": "Amsterdam",
        "bruxelles": "Brussels",
        "stockholm": "Stockholm",
        "oslo": "Oslo",
        "københavn": "Copenhagen",
        "copenhagen": "Copenhagen",
        "helsinki": "Helsinki",
        "dublin": "Dublin",
    }

    upgraded = 0
    for pid, label in labels.items():
        if pid not in base:
            continue
        cities[str(pid)] = {"city_name": label, "tier": 3, "capital": True}
        e = dict(economy.get(str(pid)) or {})
        e["population"] = max(int(e.get("population") or 0), 1_500_000)
        e["factories"] = max(int(e.get("factories") or 0), 6)
        e["infrastructure"] = max(int(e.get("infrastructure") or 0), 6)
        e["development_level"] = max(int(e.get("development_level") or 0), 4)
        economy[str(pid)] = e
        upgraded += 1

    for pid, p in base.items():
        if _is_water(p):
            continue
        nm = str(p.get("name") or "").lower()
        for key, label in extra_name_labels.items():
            if key in nm:
                prev = cities.get(str(pid)) or {}
                tier = max(int(prev.get("tier") or 1), 2)
                cities[str(pid)] = {"city_name": label, "tier": tier}
                e = dict(economy.get(str(pid)) or {})
                e["population"] = max(int(e.get("population") or 0), 400_000)
                e["factories"] = max(int(e.get("factories") or 0), 3)
                economy[str(pid)] = e
                upgraded += 1
                break

    # Ensure all scenario capitals are tier-3 cities
    for tag, pid in scenario_caps.items():
        if pid not in base:
            continue
        label = labels.get(pid) or str(base[pid].get("name") or tag).split(",")[0][:40]
        cities[str(pid)] = {"city_name": label, "tier": 3, "capital": True, "tag": tag}

    return {
        "city_doc": {"provinces": cities, "meta": {"source": "polish_capital_layers_v1_4"}},
        "econ_doc": {"provinces": economy, "meta": {"source": "polish_capital_layers_v1_4"}},
        "upgraded": upgraded,
        "city_n": len(cities),
    }


def fix_scenario_capitals(base: Dict[int, dict], own: Dict[str, str]) -> dict:
    """Ensure scenario capital IDs exist and match owner tag when possible."""
    if not SCENARIO.is_file():
        return {"skipped": True}
    sc = _load(SCENARIO)
    changes = []
    # Prefer DC for USA
    dc = None
    for pid, p in base.items():
        if p.get("name") == "District of Columbia":
            dc = pid
            break
    for c in sc.get("countries") or []:
        tag = str(c.get("tag") or "")
        cap = int(c.get("capital_province_id") or 0)
        if tag == "USA" and dc is not None and cap != dc:
            changes.append({"tag": "USA", "from": cap, "to": dc, "name": "District of Columbia"})
            c["capital_province_id"] = dc
            c["key_provinces"] = [dc]
        # validate capital exists
        if cap and cap not in base and not (tag == "USA" and dc):
            changes.append({"tag": tag, "error": "missing_capital", "id": cap})
        # owner check after ownership rebuild
        use_id = int(c.get("capital_province_id") or 0)
        ot = own.get(str(use_id), "")
        if ot and ot != tag and tag in ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL"):
            # try find any province owned by tag with capital-ish name
            pass  # leave NUTS capitals; ownership on NUTS is correct
    return {"scenario": str(SCENARIO.relative_to(ROOT)), "changes": changes, "doc": sc}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", default=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--quant", type=float, default=1.25)
    ap.add_argument("--skip-adj", action="store_true")
    ap.add_argument("--skip-scenario", action="store_true")
    args = ap.parse_args()
    write = not args.dry_run

    base_doc = _load(D / "provinces_base.json")
    base_list = list(base_doc.get("provinces") or [])
    sea_renamed = polish_sea_display_names(base_list)
    base = {int(p["id"]): p for p in base_list}
    geo = {int(p["id"]): p for p in _load(D / "provinces_geometry.json")["provinces"]}
    own_doc = _load(D / "province_ownership_1936.json")
    existing = dict(own_doc.get("owners") or {})

    own2 = rebuild_ownership(base, existing)

    # Load adjacency for neighbor fill (existing file OK if skip-adj)
    adj_doc = _load(D / "province_adjacency.json") if (D / "province_adjacency.json").is_file() else {}
    adj_map = adj_doc.get("adjacency") or {}
    own2, n_filled = neighbor_fill_unowned(base, own2, adj_map)

    land = [pid for pid, p in base.items() if not _is_water(p)]
    unowned = [pid for pid in land if not own2.get(str(pid))]
    # Final residual: assign ENG as last-resort colonial proxy only if still empty
    for pid in unowned:
        own2[str(pid)] = "ENG"
    residual_forced = len(unowned)

    choke = remap_chokepoints(base, geo)

    report: Dict[str, Any] = {
        "ownership_before": len(existing),
        "ownership_after": len(own2),
        "neighbor_filled": n_filled,
        "residual_forced_eng": residual_forced,
        "unowned_land_after": sum(1 for pid in land if not own2.get(str(pid))),
        "sea_names_renamed": sea_renamed,
        "ownership_top": Counter(own2.values()).most_common(20),
        "majors": {t: Counter(own2.values()).get(t, 0) for t in ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "CHI", "BRA", "ARG", "MEX")},
        "chokepoints": choke.get("meta"),
        "choke_ids_n": len(choke.get("chokepoint_province_ids") or []),
        "choke_sample": [
            {"id": i, "name": base.get(i, {}).get("name")}
            for i in (choke.get("chokepoint_province_ids") or [])[:12]
        ],
    }

    adj = None
    if not args.skip_adj:
        adj = retune_adjacency(quant=float(args.quant))
        st = adj.get("stats") or {}
        report["adjacency"] = {
            "method": adj.get("method"),
            "quant": adj.get("quant"),
            "land_shared_coverage": st.get("land_shared_coverage"),
            "orphan_land_after": st.get("orphan_land_after"),
            "shared_edge_pairs": st.get("shared_edge_pairs"),
            "knn_edges_added": st.get("knn_edges_added"),
        }
        # re-fill with new adj if better connectivity
        own3, n2 = neighbor_fill_unowned(base, own2, adj.get("adjacency") or {})
        if n2:
            own2 = own3
            report["neighbor_filled_post_adj"] = n2

    scen_info = None
    if not args.skip_scenario:
        scen_info = fix_scenario_capitals(base, own2)
        report["scenario_capital_fixes"] = scen_info.get("changes")

    scenario_caps: Dict[str, int] = {}
    if SCENARIO.is_file():
        sc_doc = (scen_info or {}).get("doc") or _load(SCENARIO)
        for c in sc_doc.get("countries") or []:
            scenario_caps[str(c.get("tag"))] = int(c.get("capital_province_id") or 0)
    layer_rep = polish_capital_layers(base, scenario_caps)
    report["capital_layers"] = {
        "upgraded": layer_rep.get("upgraded"),
        "city_n": layer_rep.get("city_n"),
    }

    if write:
        base_doc["provinces"] = base_list
        _write(D / "provinces_base.json", base_doc)
        own_doc["owners"] = own2
        own_doc["meta"] = {
            "source": "polish_world_accurate_board",
            "version": "v1.4_1936_ownership",
            "neighbor_filled": n_filled,
            "residual_forced_eng": residual_forced,
        }
        _write(D / "province_ownership_1936.json", own_doc)
        # Do not clobber differentiated era paints here — run
        # assign_world_accurate_ownership_eras.py after polish when eras need refresh.
        _write(D / "naval_chokepoints.json", choke)
        if adj is not None:
            (D / "province_adjacency.json").write_text(json.dumps(adj) + "\n", encoding="utf-8")
        if scen_info and scen_info.get("doc") and scen_info.get("changes"):
            _write(SCENARIO, scen_info["doc"])
        _write(D / "province_city_layer.json", layer_rep["city_doc"])
        _write(D / "province_economy_layer.json", layer_rep["econ_doc"])
        man = _load(D / "manifest_world_accurate.json") if (D / "manifest_world_accurate.json").is_file() else {}
        man["geometry_quality"] = "gis_hybrid_v1_4"
        man["polish"] = report
        _write(D / "manifest_world_accurate.json", man)

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
