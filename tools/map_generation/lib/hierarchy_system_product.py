"""Complete 4-tier hierarchical map division product for EOA.

Province → State (5–20) → Region → Super-Region / Theater.

Supports:
- Schema validation / integrity
- Sample US + Europe hierarchy packs
- Membership bind builders
- Dynamic change helpers (pure; no Godot)
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
SAMPLES_DIR = ROOT / "data" / "hierarchy_samples"

# Hard / soft bounds for state membership (design target 5–20).
STATE_SIZE_SOFT_MIN = 5
STATE_SIZE_SOFT_MAX = 20
STATE_SIZE_HARD_MIN = 3
STATE_SIZE_HARD_MAX = 30

PRODUCT_STEPS = (
    "schema",
    "bind",
    "us_sample",
    "europe_sample",
    "integrity",
    "dynamic_rules",
)

# --- Super-region catalog (Phase 1) ---
SUPER_REGION_CATALOG: List[Dict[str, Any]] = [
    {"id": 1, "name": "Europe", "theaters": ["europe_core"], "slug": "europe"},
    {"id": 2, "name": "MENA", "theaters": ["mena_africa"], "slug": "mena"},
    {"id": 3, "name": "Africa", "theaters": ["africa"], "slug": "africa"},
    {"id": 4, "name": "South Asia", "theaters": ["south_asia"], "slug": "south_asia"},
    {"id": 5, "name": "East Asia", "theaters": ["far_east"], "slug": "east_asia"},
    {"id": 6, "name": "SE Asia–Pacific", "theaters": ["pacific", "se_asia"], "slug": "se_asia_pacific"},
    {"id": 7, "name": "North America", "theaters": ["north_america"], "slug": "north_america"},
    {"id": 8, "name": "Latin America", "theaters": ["south_america", "central_america"], "slug": "latin_america"},
    {"id": 9, "name": "Central Asia–Siberia", "theaters": ["central_asia"], "slug": "central_asia_siberia"},
    {"id": 10, "name": "Oceania", "theaters": ["oceania"], "slug": "oceania"},
    {"id": 11, "name": "Global Seas", "theaters": ["sea"], "slug": "global_seas"},
    {"id": 12, "name": "Arctic", "theaters": ["arctic"], "slug": "arctic"},
]

# US geographic regions (Tier 3) — grand strategy set.
US_REGIONS: List[Tuple[int, str, List[str]]] = [
    (701, "Northeast", ["ME", "NH", "VT", "MA", "RI", "CT", "NY"]),
    (702, "Mid-Atlantic", ["PA", "NJ", "DE", "MD", "DC", "VA", "WV"]),
    (703, "Southeast", ["NC", "SC", "GA", "FL", "AL", "MS", "TN", "KY"]),
    (704, "Midwest", ["OH", "IN", "IL", "MI", "WI", "MN", "IA", "MO"]),
    (705, "Great Plains", ["ND", "SD", "NE", "KS", "OK"]),
    (706, "Southwest", ["TX", "NM", "AZ"]),
    (707, "Mountain West", ["MT", "ID", "WY", "CO", "UT", "NV"]),
    (708, "Pacific", ["CA", "OR", "WA", "AK", "HI"]),
]

# Europe strategic regions (Tier 3) — align with pilot naming where possible.
EUROPE_REGIONS: List[Tuple[int, str]] = [
    (101, "British Isles"),
    (102, "Iberia"),
    (103, "France"),
    (104, "Low Countries"),
    (105, "Germany"),
    (106, "Italy"),
    (107, "Nordic"),
    (108, "Balkans"),
    (109, "Central Europe"),
    (110, "Eastern Frontiers"),
    (111, "Western Mediterranean"),
]


def build_bindings(
    states: Sequence[Dict[str, Any]],
    regions: Sequence[Dict[str, Any]],
    super_regions: Sequence[Dict[str, Any]],
) -> Dict[str, Any]:
    """Build province_to_state / region / super_region maps from group lists."""
    p2s: Dict[str, int] = {}
    p2r: Dict[str, int] = {}
    p2sr: Dict[str, int] = {}

    state_to_region: Dict[int, int] = {}
    for r in regions:
        rid = int(r["id"])
        for sid in r.get("state_ids") or []:
            state_to_region[int(sid)] = rid
        for pid in r.get("province_ids") or []:
            p2r[str(int(pid))] = rid

    region_to_super: Dict[int, int] = {}
    for sr in super_regions:
        srid = int(sr["id"])
        for rid in sr.get("region_ids") or []:
            region_to_super[int(rid)] = srid

    for s in states:
        sid = int(s["id"])
        rid = int(s.get("region_id") or state_to_region.get(sid) or 0)
        for pid in s.get("province_ids") or []:
            p2s[str(int(pid))] = sid
            if rid > 0:
                p2r.setdefault(str(int(pid)), rid)

    for pid_s, rid in p2r.items():
        srid = int(region_to_super.get(int(rid) or 0) or 0)
        if srid > 0:
            p2sr[pid_s] = srid
        # fallback: state region_id → super
        elif pid_s in p2s:
            sid = p2s[pid_s]
            rid2 = int(state_to_region.get(sid) or 0)
            srid2 = int(region_to_super.get(rid2) or 0)
            if srid2 > 0:
                p2sr[pid_s] = srid2

    return {
        "version": 2,
        "four_tier": True,
        "province_to_state": p2s,
        "province_to_region": p2r,
        "province_to_super_region": p2sr,
        "state_n": len(states),
        "region_n": len(regions),
        "super_region_n": len(super_regions),
        "land_n": len(p2s),
    }


def state_size_stats(states: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    sizes = [len(s.get("province_ids") or []) for s in states]
    if not sizes:
        return {"ok": False, "n": 0}
    in_soft = sum(1 for n in sizes if STATE_SIZE_SOFT_MIN <= n <= STATE_SIZE_SOFT_MAX)
    in_hard = sum(1 for n in sizes if STATE_SIZE_HARD_MIN <= n <= STATE_SIZE_HARD_MAX)
    return {
        "ok": in_hard == len(sizes) and in_soft >= max(1, int(0.6 * len(sizes))),
        "n": len(sizes),
        "mean": sum(sizes) / len(sizes),
        "min": min(sizes),
        "max": max(sizes),
        "in_soft_band": in_soft,
        "in_hard_band": in_hard,
        "soft_band": [STATE_SIZE_SOFT_MIN, STATE_SIZE_SOFT_MAX],
        "hard_band": [STATE_SIZE_HARD_MIN, STATE_SIZE_HARD_MAX],
    }


def reassign_province(
    binds: Dict[str, Any],
    province_id: int,
    new_state_id: int,
    new_region_id: Optional[int] = None,
    new_super_id: Optional[int] = None,
) -> Dict[str, Any]:
    """Pure helper: gory border / admin reform — move one province between groups."""
    out = {
        "province_to_state": dict(binds.get("province_to_state") or {}),
        "province_to_region": dict(binds.get("province_to_region") or {}),
        "province_to_super_region": dict(binds.get("province_to_super_region") or {}),
    }
    key = str(int(province_id))
    old = {
        "state_id": out["province_to_state"].get(key),
        "region_id": out["province_to_region"].get(key),
        "super_region_id": out["province_to_super_region"].get(key),
    }
    out["province_to_state"][key] = int(new_state_id)
    if new_region_id is not None:
        out["province_to_region"][key] = int(new_region_id)
    if new_super_id is not None:
        out["province_to_super_region"][key] = int(new_super_id)
    return {
        "ok": True,
        "province_id": int(province_id),
        "before": old,
        "after": {
            "state_id": out["province_to_state"].get(key),
            "region_id": out["province_to_region"].get(key),
            "super_region_id": out["province_to_super_region"].get(key),
        },
        "binds": out,
        "change_type": "province_reassign",
    }


def transfer_state_ownership_hint(
    states: List[Dict[str, Any]],
    state_id: int,
    new_owner_hint: str,
) -> Dict[str, Any]:
    """Clean border: whole state ownership hint flip (seed metadata)."""
    for s in states:
        if int(s.get("id") or 0) == int(state_id):
            old = s.get("owner_hint")
            s["owner_hint"] = str(new_owner_hint).upper()
            return {"ok": True, "state_id": state_id, "before": old, "after": s["owner_hint"]}
    return {"ok": False, "error": "state_not_found", "state_id": state_id}


# ---------------------------------------------------------------------------
# Sample packs (Phase 3) — concrete US Midwest + Europe Low Countries / Germany
# ---------------------------------------------------------------------------

def build_us_midwest_sample() -> Dict[str, Any]:
    """Counties → OH/IN/IL/MI → Midwest region → North America super.

    IDs in 800000+ pilot namespace (does not touch world_full).
    """
    # ~6 counties each → 4 states → 1 region → 1 super (sizes in 5–8 band)
    counties = {
        "OH": [
            (800001, "Cuyahoga"),
            (800002, "Franklin"),
            (800003, "Hamilton"),
            (800004, "Summit"),
            (800005, "Lucas"),
            (800006, "Montgomery"),
        ],
        "IN": [
            (800011, "Marion"),
            (800012, "Lake"),
            (800013, "Allen"),
            (800014, "Hamilton IN"),
            (800015, "St. Joseph"),
            (800016, "Vanderburgh"),
        ],
        "IL": [
            (800021, "Cook"),
            (800022, "DuPage"),
            (800023, "Lake IL"),
            (800024, "Will"),
            (800025, "Kane"),
            (800026, "Sangamon"),
        ],
        "MI": [
            (800031, "Wayne"),
            (800032, "Oakland"),
            (800033, "Macomb"),
            (800034, "Kent"),
            (800035, "Genesee"),
            (800036, "Washtenaw"),
        ],
    }
    state_meta = {
        "OH": (801, "Ohio", 800002),
        "IN": (802, "Indiana", 800011),
        "IL": (803, "Illinois", 800021),
        "MI": (804, "Michigan", 800031),
    }
    states = []
    all_pids: List[int] = []
    for abbr, meta in state_meta.items():
        sid, name, cap = meta
        pids = [c[0] for c in counties[abbr]]
        all_pids.extend(pids)
        states.append({
            "id": sid,
            "name": name,
            "province_ids": pids,
            "province_n": len(pids),
            "capital_province_id": cap,
            "region_id": 704,
            "owner_hint": "USA",
            "theater": "north_america",
            "tags": ["us_state", "sample"],
            "postal_code": abbr,
        })
    provinces = []
    for abbr, rows in counties.items():
        for pid, pname in rows:
            provinces.append({
                "id": pid,
                "name": pname,
                "domain": "land",
                "theater": "north_america",
                "state_postal": abbr,
                "sample": True,
            })
    regions = [{
        "id": 704,
        "name": "Midwest",
        "province_ids": all_pids,
        "state_ids": [801, 802, 803, 804],
        "super_region_id": 7,
        "theater": "north_america",
        "notes": "US Midwest sample (OH/IN/IL/MI)",
    }]
    supers = [{
        "id": 7,
        "name": "North America",
        "region_ids": [704],
        "theaters": ["north_america"],
        "province_n": len(all_pids),
    }]
    binds = build_bindings(states, regions, supers)
    binds["sample"] = "us_midwest"
    binds["id_namespace"] = "800000+"
    return {
        "provinces": provinces,
        "states": states,
        "regions": regions,
        "super_regions": supers,
        "hierarchy_scaffold": binds,
        "meta": {
            "sample": "us_midwest",
            "province_n": len(provinces),
            "state_n": len(states),
            "region_n": 1,
            "super_region_n": 1,
            "design": "county→state→Midwest→North America",
        },
    }


def build_europe_core_sample() -> Dict[str, Any]:
    """Districts → Flanders/Brabant/Bavaria/Île-de-France → regions → Europe.

    IDs illustrative 700900+ (sample-only; not replacing densify pilot mesh).
    """
    groups = {
        (201, "Flanders", 104, "Low Countries", "BEL"): [
            (700901, "Antwerp District"),
            (700902, "Ghent District"),
            (700903, "Bruges District"),
            (700904, "Leuven District"),
            (700905, "Mechelen District"),
            (700906, "Hasselt District"),
        ],
        (202, "Brabant", 104, "Low Countries", "BEL"): [
            (700911, "Brussels District"),
            (700912, "Nivelles District"),
            (700913, "Louvain Outer"),
            (700914, "Wavre District"),
            (700915, "Halle District"),
        ],
        (203, "Bavaria", 105, "Germany", "GER"): [
            (700921, "Munich District"),
            (700922, "Nuremberg District"),
            (700923, "Augsburg District"),
            (700924, "Regensburg District"),
            (700925, "Würzburg District"),
            (700926, "Passau District"),
            (700927, "Ingolstadt District"),
        ],
        (204, "Île-de-France", 103, "France", "FRA"): [
            (700931, "Paris"),
            (700932, "Seine-et-Marne"),
            (700933, "Yvelines"),
            (700934, "Essonne"),
            (700935, "Hauts-de-Seine"),
            (700936, "Seine-Saint-Denis"),
            (700937, "Val-de-Marne"),
            (700938, "Val-d'Oise"),
        ],
    }
    states = []
    provinces = []
    region_pids: Dict[int, List[int]] = defaultdict(list)
    region_sids: Dict[int, List[int]] = defaultdict(list)
    region_names = {104: "Low Countries", 105: "Germany", 103: "France"}
    for (sid, sname, rid, _rname, owner), rows in groups.items():
        pids = [r[0] for r in rows]
        states.append({
            "id": sid,
            "name": sname,
            "province_ids": pids,
            "province_n": len(pids),
            "capital_province_id": pids[0],
            "region_id": rid,
            "region_hint": region_names[rid],
            "owner_hint": owner,
            "theater": "europe_core",
            "tags": ["historical_province", "sample"],
        })
        region_pids[rid].extend(pids)
        region_sids[rid].append(sid)
        for pid, pname in rows:
            provinces.append({
                "id": pid,
                "name": pname,
                "domain": "land",
                "theater": "europe_core",
                "sample": True,
            })
    regions = []
    for rid, rname in region_names.items():
        regions.append({
            "id": rid,
            "name": rname,
            "province_ids": region_pids[rid],
            "state_ids": region_sids[rid],
            "super_region_id": 1,
            "theater": "europe_core",
        })
    supers = [{
        "id": 1,
        "name": "Europe",
        "region_ids": list(region_names.keys()),
        "theaters": ["europe_core"],
        "province_n": len(provinces),
    }]
    binds = build_bindings(states, regions, supers)
    binds["sample"] = "europe_core"
    binds["id_namespace"] = "700900+"
    return {
        "provinces": provinces,
        "states": states,
        "regions": regions,
        "super_regions": supers,
        "hierarchy_scaffold": binds,
        "meta": {
            "sample": "europe_core",
            "province_n": len(provinces),
            "state_n": len(states),
            "region_n": len(regions),
            "super_region_n": 1,
            "design": "district→historical state→strategic region→Europe",
        },
    }


def write_sample_pack(pack: Dict[str, Any], out_dir: Path) -> Dict[str, Any]:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "provinces_sample.json").write_text(
        json.dumps({"provinces": pack["provinces"], "meta": pack.get("meta")}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (out_dir / "province_states.json").write_text(
        json.dumps({
            "version": 3,
            "source": "hierarchy_system_product",
            "naming": "sample",
            "states": pack["states"],
        }, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (out_dir / "strategic_regions.json").write_text(
        json.dumps({"version": 4, "source": "hierarchy_system_product", "regions": pack["regions"]}, indent=2)
        + "\n",
        encoding="utf-8",
    )
    (out_dir / "super_regions.json").write_text(
        json.dumps({"version": 1, "super_regions": pack["super_regions"]}, indent=2) + "\n",
        encoding="utf-8",
    )
    (out_dir / "hierarchy_scaffold.json").write_text(
        json.dumps(pack["hierarchy_scaffold"], indent=2) + "\n",
        encoding="utf-8",
    )
    # Example membership era: same binds (placeholder for 1910 colonial reorg diffs).
    (out_dir / "hierarchy_membership_1936.json").write_text(
        json.dumps({
            "version": 1,
            "era_year": 1936,
            "seed_only": True,
            "note": "Sample default membership equals scaffold; real eras only store diffs.",
            "province_to_state": pack["hierarchy_scaffold"]["province_to_state"],
            "province_to_region": pack["hierarchy_scaffold"]["province_to_region"],
            "province_to_super_region": pack["hierarchy_scaffold"]["province_to_super_region"],
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    return {"path": str(out_dir), "meta": pack.get("meta"), "ok": True}


def write_all_samples(base: Path = SAMPLES_DIR) -> Dict[str, Any]:
    us = write_sample_pack(build_us_midwest_sample(), base / "us_midwest_sample")
    eu = write_sample_pack(build_europe_core_sample(), base / "europe_core_sample")
    catalog = {
        "version": 1,
        "super_region_catalog": SUPER_REGION_CATALOG,
        "us_regions": [{"id": a, "name": b, "states": c} for a, b, c in US_REGIONS],
        "europe_regions": [{"id": a, "name": b} for a, b in EUROPE_REGIONS],
        "state_size_soft": [STATE_SIZE_SOFT_MIN, STATE_SIZE_SOFT_MAX],
        "state_size_hard": [STATE_SIZE_HARD_MIN, STATE_SIZE_HARD_MAX],
        "global_province_target": {"v1": [4000, 7000], "stretch": [8000, 12000]},
    }
    base.mkdir(parents=True, exist_ok=True)
    (base / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    return {"us": us, "europe": eu, "catalog": str(base / "catalog.json"), "ok": True}


def sample_integrity(sample_dir: Path) -> Dict[str, Any]:
    from state_name_gazetteer import assert_names_shippable  # type: ignore

    st = json.loads((sample_dir / "province_states.json").read_text(encoding="utf-8"))
    states = st.get("states") or []
    names = [str(s.get("name", "")) for s in states]
    name_gate = assert_names_shippable(names)
    size = state_size_stats(states)
    hs = json.loads((sample_dir / "hierarchy_scaffold.json").read_text(encoding="utf-8"))
    p2s = hs.get("province_to_state") or {}
    p2r = hs.get("province_to_region") or {}
    p2sr = hs.get("province_to_super_region") or {}
    four = bool(p2s) and bool(p2r) and bool(p2sr) and set(p2s.keys()) == set(p2r.keys()) == set(p2sr.keys())
    ok = bool(name_gate.get("ok")) and bool(size.get("ok")) and four and bool(hs.get("four_tier"))
    return {
        "ok": ok,
        "path": str(sample_dir),
        "name_gate": name_gate,
        "state_size": size,
        "four_tier_bind": four,
        "province_n": len(p2s),
        "summary": "Sample integrity %s · %s · states %d · prov %d"
        % ("PASS" if ok else "FAIL", sample_dir.name, len(states), len(p2s)),
    }


def hierarchy_system_integrity() -> Dict[str, Any]:
    """Full product gate: samples + optional shipped board name hygiene."""
    write_all_samples()
    us = sample_integrity(SAMPLES_DIR / "us_midwest_sample")
    eu = sample_integrity(SAMPLES_DIR / "europe_core_sample")
    # Dynamic change pure check
    binds = json.loads((SAMPLES_DIR / "us_midwest_sample" / "hierarchy_scaffold.json").read_text())
    dyn = reassign_province(binds, 800001, 802, 704, 7)
    ok = bool(us.get("ok")) and bool(eu.get("ok")) and bool(dyn.get("ok"))
    return {
        "ok": ok,
        "us": us,
        "europe": eu,
        "dynamic_reassign": dyn.get("after"),
        "super_catalog_n": len(SUPER_REGION_CATALOG),
        "summary": "Hierarchy system %s · US %s · EU %s · supers %d"
        % (
            "PASS" if ok else "FAIL",
            "ok" if us.get("ok") else "FAIL",
            "ok" if eu.get("ok") else "FAIL",
            len(SUPER_REGION_CATALOG),
        ),
        "empty": False,
        "integration": ["map_hierarchy", "four_tier", "us_sample", "europe_sample", "world_class_map"],
    }
