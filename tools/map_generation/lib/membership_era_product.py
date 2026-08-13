"""Hierarchy membership eras — full snapshots for primary years.

Locked product decisions (2026-07-13):
- US Tier-3: **8-band** geographic set (Northeast … Pacific)
- Global land target: **~6k** within 5–7k band; 60 fps first
- Membership eras **1910, 1918, 1936, 2026** are FULL (not sparse delta)
- 1945 remains optional secondary (may be full or thin)

Membership is orthogonal to ownership:
- ownership = country tag on province
- membership = province → state → region → super-region

Policy: seed on scenario load only; never reapply on year tick.
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

# Primary eras — always full snapshots, most content investment.
PRIMARY_MEMBERSHIP_ERAS: Tuple[int, ...] = (1910, 1918, 1936, 2026)
# Secondary — may exist; not required to be as rich as primary.
SECONDARY_MEMBERSHIP_ERAS: Tuple[int, ...] = (1945,)

STATE_CHUNK = 10  # target provinces per era-state within a region


def _load_json(path: Path) -> Dict[str, Any]:
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def membership_era_policy() -> Dict[str, Any]:
    return {
        "seed_on_scenario_load": True,
        "reapply_on_year_tick": False,
        "reapply_on_daily_tick": False,
        "player_membership_edits_preserved": True,
        "primary_eras_mode": "full",
        "primary_eras": list(PRIMARY_MEMBERSHIP_ERAS),
        "secondary_eras": list(SECONDARY_MEMBERSHIP_ERAS),
        "global_province_target_v1": 6000,
        "global_province_band": [5000, 7000],
        "fps_gate": 60,
        "us_region_set": "8_band",
    }


def resolve_membership_era(start_year: int, eras: Sequence[int] = PRIMARY_MEMBERSHIP_ERAS) -> int:
    """Largest primary era year <= start_year (fallback to earliest)."""
    eras_sorted = sorted(int(e) for e in eras)
    if not eras_sorted:
        return 1936
    chosen = eras_sorted[0]
    for e in eras_sorted:
        if e <= int(start_year):
            chosen = e
    return chosen


def _owners_for_year(data_dir: Path, year: int) -> Dict[str, str]:
    path = data_dir / ("province_ownership_%d.json" % year)
    data = _load_json(path)
    owners = data.get("owners") or {}
    return {str(k): str(v).upper() for k, v in owners.items() if v}


def _base_binds(data_dir: Path) -> Dict[str, Any]:
    hs = _load_json(data_dir / "hierarchy_scaffold.json")
    if not hs.get("province_to_state"):
        # rebuild from province_states
        st = _load_json(data_dir / "province_states.json")
        p2s = {}
        for s in st.get("states") or []:
            sid = int(s.get("id") or 0)
            for pid in s.get("province_ids") or []:
                p2s[str(int(pid))] = sid
        hs["province_to_state"] = p2s
    if not hs.get("province_to_region"):
        reg = _load_json(data_dir / "strategic_regions.json")
        if not reg.get("regions"):
            reg = _load_json(data_dir / "strategic_regions_scaffold.json")
        p2r = {}
        for r in reg.get("regions") or []:
            rid = int(r.get("id") or 0)
            for pid in r.get("province_ids") or []:
                p2r[str(int(pid))] = rid
        hs["province_to_region"] = p2r
    if not hs.get("province_to_super_region"):
        # leave empty; builder fills from super file
        hs["province_to_super_region"] = {}
    return hs


def _region_meta(data_dir: Path) -> Dict[int, Dict[str, Any]]:
    reg = _load_json(data_dir / "strategic_regions.json")
    if not reg.get("regions"):
        reg = _load_json(data_dir / "strategic_regions_scaffold.json")
    out: Dict[int, Dict[str, Any]] = {}
    for r in reg.get("regions") or []:
        rid = int(r.get("id") or 0)
        if rid > 0:
            out[rid] = r
    return out


def _super_by_region(data_dir: Path, region_meta: Dict[int, Dict[str, Any]]) -> Dict[int, int]:
    """region_id → super_region_id."""
    r2s: Dict[int, int] = {}
    super_data = _load_json(data_dir / "super_regions.json")
    for sr in super_data.get("super_regions") or []:
        srid = int(sr.get("id") or 0)
        for rid in sr.get("region_ids") or []:
            r2s[int(rid)] = srid
        theaters = set(str(t) for t in (sr.get("theaters") or []))
        if theaters:
            for rid, r in region_meta.items():
                th = str(r.get("theater") or "")
                if th and th in theaters:
                    r2s.setdefault(rid, srid)
    # explicit super_region_id on regions
    for rid, r in region_meta.items():
        if r.get("super_region_id"):
            r2s[rid] = int(r["super_region_id"])
    return r2s


def build_full_membership_for_era(
    data_dir: Path | str,
    year: int,
    *,
    regroup_by_owner: bool = True,
) -> Dict[str, Any]:
    """Build a FULL membership snapshot for one year.

    - region + super_region geography stays stable
    - states regroup by (region, owner) when regroup_by_owner and ownership table exists
    - otherwise copy scaffold state binds (still full maps)
    """
    from state_name_gazetteer import assign_state_name, pick_state_names, _expand_catalog  # type: ignore

    # Prefer US 8-band catalogs when region is a locked US band name.
    try:
        from us_pilot_densify import US_BAND_STATES, US_EIGHT_BANDS  # type: ignore
    except Exception:
        US_BAND_STATES = {}
        US_EIGHT_BANDS = ()

    def _era_state_name(region_name: str, index: int, owner_hint: str = "") -> str:
        if region_name in US_BAND_STATES:
            names = _expand_catalog(US_BAND_STATES[region_name], index + 1)
            return names[index]
        return assign_state_name(region_name, index, owner_hint=owner_hint)

    data_dir = Path(data_dir)
    year = int(year)
    base = _base_binds(data_dir)
    p2r_base: Dict[str, int] = {str(k): int(v) for k, v in (base.get("province_to_region") or {}).items()}
    p2s_base: Dict[str, int] = {str(k): int(v) for k, v in (base.get("province_to_state") or {}).items()}
    region_meta = _region_meta(data_dir)
    r2super = _super_by_region(data_dir, region_meta)
    owners = _owners_for_year(data_dir, year)

    # Ensure every state-bound province has a region (from base or 0)
    all_pids = sorted(set(p2s_base.keys()) | set(p2r_base.keys()) | set(owners.keys()), key=lambda x: int(x))
    # Prefer land keys from scaffold
    if p2s_base:
        all_pids = sorted(p2s_base.keys(), key=lambda x: int(x))

    p2r: Dict[str, int] = {}
    p2sr: Dict[str, int] = {}
    for pid_s in all_pids:
        rid = int(p2r_base.get(pid_s) or 0)
        p2r[pid_s] = rid
        p2sr[pid_s] = int(r2super.get(rid) or base.get("province_to_super_region", {}).get(pid_s) or 0)

    states: List[Dict[str, Any]] = []
    p2s: Dict[str, int] = {}

    if regroup_by_owner and owners:
        # Group provinces by (region_id, owner)
        buckets: Dict[Tuple[int, str], List[int]] = defaultdict(list)
        for pid_s in all_pids:
            rid = int(p2r.get(pid_s) or 0)
            tag = owners.get(pid_s) or "NEU"
            buckets[(rid, tag)].append(int(pid_s))

        # State ID namespace: era*100000 + serial (keeps eras non-colliding in pure data)
        sid = year * 100000 + 1
        reg_name_idx: Dict[str, int] = defaultdict(int)
        for (rid, tag), pids in sorted(buckets.items(), key=lambda kv: (kv[0][0], kv[0][1])):
            pids = sorted(pids)
            rname = str((region_meta.get(rid) or {}).get("name") or "Central Europe")
            for i in range(0, len(pids), STATE_CHUNK):
                chunk = pids[i : i + STATE_CHUNK]
                ni = reg_name_idx[rname]
                reg_name_idx[rname] = ni + 1
                name = _era_state_name(rname, ni, owner_hint=tag)
                states.append({
                    "id": sid,
                    "name": name,
                    "owner_hint": tag,
                    "region_id": rid,
                    "region_hint": rname,
                    "province_ids": chunk,
                    "province_n": len(chunk),
                    "capital_province_id": chunk[0],
                    "era_year": year,
                })
                for pid in chunk:
                    p2s[str(pid)] = sid
                sid += 1
    else:
        # Copy scaffold states fully
        st = _load_json(data_dir / "province_states.json")
        for s in st.get("states") or []:
            states.append(dict(s))
            sid = int(s.get("id") or 0)
            for pid in s.get("province_ids") or []:
                p2s[str(int(pid))] = sid
        if not p2s:
            p2s = dict(p2s_base)

    # Fill any missing super from region
    for pid_s, rid in p2r.items():
        if int(p2sr.get(pid_s) or 0) <= 0:
            p2sr[pid_s] = int(r2super.get(int(rid) or 0) or 0)

    return {
        "version": 1,
        "era_year": year,
        "mode": "full",
        "seed_only": True,
        "primary": year in PRIMARY_MEMBERSHIP_ERAS,
        "policy": {
            "seed_on_scenario_load": True,
            "reapply_on_year_tick": False,
        },
        "province_to_state": p2s,
        "province_to_region": p2r,
        "province_to_super_region": p2sr,
        "states": states,
        "state_n": len(states),
        "province_n": len(p2s),
        "region_n": len(set(p2r.values())),
        "super_region_n": len(set(v for v in p2sr.values() if int(v) > 0)),
        "source": "membership_era_product",
        "notes": "Full membership snapshot — not sparse delta. Primary eras: %s"
        % ",".join(str(e) for e in PRIMARY_MEMBERSHIP_ERAS),
    }


def write_membership_era_files(
    data_dir: Path | str,
    eras: Optional[Sequence[int]] = None,
    *,
    regroup_by_owner: bool = True,
) -> Dict[str, Any]:
    """Write full hierarchy_membership_{year}.json for primary (+ optional secondary) eras."""
    data_dir = Path(data_dir)
    eras = list(eras) if eras is not None else list(PRIMARY_MEMBERSHIP_ERAS)
    written = []
    for year in eras:
        snap = build_full_membership_for_era(data_dir, year, regroup_by_owner=regroup_by_owner)
        path = data_dir / ("hierarchy_membership_%d.json" % year)
        # Compact: drop huge states array optional? Keep for primary richness.
        path.write_text(json.dumps(snap, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        written.append({
            "year": year,
            "path": path.name,
            "mode": "full",
            "province_n": snap.get("province_n"),
            "state_n": snap.get("state_n"),
            "primary": year in PRIMARY_MEMBERSHIP_ERAS,
            "ok": int(snap.get("province_n") or 0) > 0,
        })

    index = {
        "version": 1,
        "policy": membership_era_policy(),
        "eras": written,
        "primary_eras": list(PRIMARY_MEMBERSHIP_ERAS),
        "secondary_eras": list(SECONDARY_MEMBERSHIP_ERAS),
        "source": "membership_era_product",
    }
    idx_path = data_dir / "membership_era_index.json"
    idx_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    return {
        "ok": all(e.get("ok") for e in written) and len(written) >= 4,
        "data_dir": str(data_dir),
        "eras": written,
        "index": str(idx_path),
        "summary": "Membership eras %s · %s"
        % ("PASS" if all(e.get("ok") for e in written) else "FAIL", data_dir.name),
    }


def write_sample_membership_eras(sample_dir: Path | str) -> Dict[str, Any]:
    """Full membership for primary eras on a hierarchy sample pack."""
    sample_dir = Path(sample_dir)
    # Samples may lack ownership tables — still write full maps from scaffold.
    # Fabricate lightweight ownership from state owner_hint for regroup flavor.
    st = _load_json(sample_dir / "province_states.json")
    hs = _load_json(sample_dir / "hierarchy_scaffold.json")
    for year in PRIMARY_MEMBERSHIP_ERAS:
        # Synthetic owners for sample: use state owner_hint
        owners: Dict[str, str] = {}
        for s in st.get("states") or []:
            tag = str(s.get("owner_hint") or "NEU").upper()
            for pid in s.get("province_ids") or []:
                owners[str(int(pid))] = tag
        # Historical flavor: 1910/1918 shift a few tags on Europe sample
        if "europe" in sample_dir.name and year in (1910, 1918):
            # Bavaria districts under GER stays; nothing heavy — keep full
            pass
        if "us_" in sample_dir.name and year == 1910:
            # all USA still
            pass
        # Write ownership sidecar for sample era so regroup works
        (sample_dir / ("province_ownership_%d.json" % year)).write_text(
            json.dumps({
                "meta": {"era_year": year, "seed_only": True, "sample": True},
                "owners": owners,
            }, indent=2) + "\n",
            encoding="utf-8",
        )
    return write_membership_era_files(sample_dir, PRIMARY_MEMBERSHIP_ERAS, regroup_by_owner=True)


def membership_era_integrity(data_dir: Path | str) -> Dict[str, Any]:
    data_dir = Path(data_dir)
    idx = _load_json(data_dir / "membership_era_index.json")
    policy = idx.get("policy") or {}
    missing = []
    thin = []
    details = []
    for year in PRIMARY_MEMBERSHIP_ERAS:
        path = data_dir / ("hierarchy_membership_%d.json" % year)
        if not path.is_file():
            missing.append(year)
            continue
        snap = _load_json(path)
        mode = str(snap.get("mode") or "")
        p2s = snap.get("province_to_state") or {}
        p2r = snap.get("province_to_region") or {}
        p2sr = snap.get("province_to_super_region") or {}
        is_full = mode == "full" and len(p2s) > 0 and len(p2r) > 0 and len(p2sr) > 0
        if not is_full:
            thin.append(year)
        details.append({
            "year": year,
            "mode": mode,
            "province_n": len(p2s),
            "state_n": snap.get("state_n") or len(snap.get("states") or []),
            "full": is_full,
            "keys_aligned": set(p2s.keys()) == set(p2r.keys()) == set(p2sr.keys()),
        })
    ok = (
        not missing
        and not thin
        and policy.get("reapply_on_year_tick") is False
        and list(policy.get("primary_eras") or PRIMARY_MEMBERSHIP_ERAS) == list(PRIMARY_MEMBERSHIP_ERAS)
        and all(d.get("full") and d.get("keys_aligned") for d in details)
    )
    return {
        "ok": ok,
        "missing_primary": missing,
        "thin_primary": thin,
        "details": details,
        "resolve_1936": resolve_membership_era(1936),
        "resolve_2020": resolve_membership_era(2020),
        "resolve_2026": resolve_membership_era(2026),
        "resolve_1905": resolve_membership_era(1905),
        "summary": "Membership era integrity %s · primary full %s"
        % ("PASS" if ok else "FAIL", PRIMARY_MEMBERSHIP_ERAS),
        "empty": False,
    }


def write_all_board_membership_eras() -> Dict[str, Any]:
    """Write primary full membership eras for world_full + pilot + samples."""
    results = {}
    for rel in (
        "data/provinces_world_full",
        "data/provinces_pilot_europe",
    ):
        d = ROOT / rel
        if d.is_dir():
            results[rel] = write_membership_era_files(d, PRIMARY_MEMBERSHIP_ERAS, regroup_by_owner=True)
    samples = ROOT / "data" / "hierarchy_samples"
    for sub in ("us_midwest_sample", "europe_core_sample"):
        sd = samples / sub
        if sd.is_dir():
            results[str(sd.relative_to(ROOT))] = write_sample_membership_eras(sd)
    # Refresh catalog product decisions
    cat_path = samples / "catalog.json"
    cat = _load_json(cat_path) if cat_path.is_file() else {}
    cat["decisions"] = {
        "us_region_set": "8_band",
        "us_regions": [
            "Northeast", "Mid-Atlantic", "Southeast", "Midwest",
            "Great Plains", "Southwest", "Mountain West", "Pacific",
        ],
        "global_province_target_v1": 6000,
        "global_province_band": [5000, 7000],
        "fps_gate_first": 60,
        "membership_primary_eras": list(PRIMARY_MEMBERSHIP_ERAS),
        "membership_primary_mode": "full",
        "membership_secondary_eras": list(SECONDARY_MEMBERSHIP_ERAS),
    }
    samples.mkdir(parents=True, exist_ok=True)
    cat_path.write_text(json.dumps(cat, indent=2) + "\n", encoding="utf-8")
    ok = all(bool(v.get("ok")) for v in results.values()) if results else False
    return {"ok": ok, "boards": results, "summary": "All board membership eras %s" % ("PASS" if ok else "FAIL")}
