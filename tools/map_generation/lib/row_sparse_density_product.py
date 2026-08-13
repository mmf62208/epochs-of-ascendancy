"""RoW sparse densify — pure plan product (Africa / Oceania / LATAM / India / sparse Asia).

Companion to US `us_state_province_density_product`: measure 900k geoBoundaries cells,
plan merge-to-playable counts inside regional bands. Does **not** write the board.

Write step: tools/map_generation/scripts/merge_row_sparse_to_playable.py
"""
from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

# Planning bands (playable land targets after merge) — match prep product.
REGION_TARGETS: Dict[str, Dict[str, int]] = {
    "africa": {"min_playable": 80, "max_playable": 220},
    "central_america": {"min_playable": 25, "max_playable": 80},
    "south_america": {"min_playable": 60, "max_playable": 160},
    "australia": {"min_playable": 12, "max_playable": 40},
    "oceania_islands": {"min_playable": 8, "max_playable": 40},
    "india": {"min_playable": 40, "max_playable": 120},
    "siberia_mongolia_sparse_china": {"min_playable": 40, "max_playable": 140},
}

# ISO3 → planning region. Only RoW 900k–949999 is considered.
ADM0_TO_REGION: Dict[str, str] = {}
for _iso in (
    "EGY", "NGA", "ZAF", "COD", "ETH", "KEN", "DZA", "MAR", "SDN", "AGO",
    "TZA", "UGA", "GHA", "MDG", "TCD", "LBY", "TUN", "BFA", "GIN", "MOZ",
    "ZWE", "ZMB", "MWI", "CMR", "CIV", "SEN", "MLI", "NER", "RWA", "BDI",
    "SOM", "ERI", "DJI", "GAB", "COG", "CAF", "SSD", "BWA", "NAM", "LSO",
    "SWZ", "LBR", "SLE", "GNB", "TGO", "BEN", "MRT", "GMB", "GNQ", "STP",
    "CPV", "COM", "SYC", "MUS", "ESH", "ZAN",
):
    ADM0_TO_REGION[_iso] = "africa"
for _iso in (
    "MEX", "GTM", "HND", "SLV", "NIC", "CRI", "PAN", "CUB", "DOM", "HTI",
    "JAM", "BLZ", "BHS", "TTO", "BRB", "GRD", "LCA", "VCT", "ATG", "DMA",
    "KNA", "PRI", "CYM",
):
    ADM0_TO_REGION[_iso] = "central_america"
for _iso in (
    "BRA", "ARG", "CHL", "COL", "PER", "VEN", "BOL", "ECU", "PRY", "URY",
    "GUY", "SUR", "GUF", "FLK",
):
    ADM0_TO_REGION[_iso] = "south_america"
ADM0_TO_REGION["AUS"] = "australia"
for _iso in (
    "NZL", "PNG", "SLB", "VUT", "NCL", "PYF", "FJI", "WSM", "TON", "KIR",
    "FSM", "PLW", "MHL", "NRU", "TUV", "GUM", "ASM", "COK", "NIU",
):
    ADM0_TO_REGION[_iso] = "oceania_islands"
for _iso in ("IND", "PAK", "BGD", "LKA", "NPL", "BTN", "MDV"):
    ADM0_TO_REGION[_iso] = "india"
for _iso in ("RUS", "MNG", "CHN", "KAZ", "KGZ", "TJK", "TKM", "UZB"):
    ADM0_TO_REGION[_iso] = "siberia_mongolia_sparse_china"

# Tranche 1 default scopes for first write (board merge).
TRANCHE1_REGIONS = ("australia", "oceania_islands", "africa")

ROW_LO = 900000
ROW_HI = 950000  # exclusive


def _bbox_area(points: Sequence) -> float:
    xs: List[float] = []
    ys: List[float] = []
    for p in points or []:
        if isinstance(p, (list, tuple)) and len(p) >= 2:
            xs.append(float(p[0]))
            ys.append(float(p[1]))
    if len(xs) < 2:
        return 0.0
    return max(0.0, (max(xs) - min(xs)) * (max(ys) - min(ys)))


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def row_ids(base: Dict[int, dict]) -> List[int]:
    return sorted(pid for pid in base if ROW_LO <= pid < ROW_HI)


def adm0_of(prow: dict) -> str:
    meta = prow.get("meta") or {}
    if isinstance(meta, dict):
        a = meta.get("adm0_a3") or meta.get("adm0") or meta.get("iso3")
        if a:
            return str(a).upper()
    return ""


def provinces_for_group_size(
    cell_n: int,
    area: float,
    median_area: float,
    *,
    region: str = "",
) -> int:
    """Playable provinces for one adm0/state group.

    Australia keeps more cells (continent = one adm0). Africa/LATAM merge harder
    so continental totals land in REGION_TARGETS bands.
    """
    if cell_n <= 0:
        return 0
    if cell_n <= 2:
        return cell_n
    rel = area / median_area if median_area > 1e-6 else 1.0

    # Continent-as-single-adm0: keep playable state-scale density
    if region == "australia":
        if cell_n <= 20:
            return min(cell_n, 6)
        if cell_n <= 50:
            return min(cell_n, 10 if rel < 1.5 else 12)
        # AUS 73 → ~14–18 (band 12–40)
        return min(cell_n, 14 if rel < 2.5 else 18)

    # Sparse island chains: light merge
    if region == "oceania_islands":
        if cell_n <= 6:
            return min(cell_n, 2)
        if cell_n <= 15:
            return min(cell_n, 3 if rel < 1.5 else 4)
        return min(cell_n, 5)

    # India / South America: slightly denser majors (band floors need more cells)
    dense_regions = {"india", "south_america", "siberia_mongolia_sparse_china"}
    if region in dense_regions:
        if cell_n <= 5:
            return min(cell_n, 2 if rel >= 0.5 else 1)
        if cell_n <= 12:
            return min(cell_n, 3 if rel < 1.2 else 4)
        if cell_n <= 30:
            return min(cell_n, 5 if rel < 1.4 else 6)
        if cell_n <= 55:
            return min(cell_n, 7 if rel < 1.8 else 8)
        if cell_n <= 90:
            return min(cell_n, 9 if rel < 2.0 else 11)
        if cell_n <= 140:
            # BRA / IND / CHN mid
            return min(cell_n, 14 if rel < 2.0 else 16)
        return min(cell_n, 18 if rel < 2.5 else 22)

    # Africa / Central America — HOI-like 1–6 per country-state
    if cell_n <= 5:
        return min(cell_n, 2 if rel >= 0.5 else 1)
    if cell_n <= 10:
        return min(cell_n, 2 if rel < 1.3 else 3)
    if cell_n <= 18:
        return min(cell_n, 3 if rel < 1.5 else 4)
    if cell_n <= 30:
        return min(cell_n, 3 if rel < 1.2 else 4)
    if cell_n <= 55:
        return min(cell_n, 4 if rel < 1.8 else 5)
    if cell_n <= 90:
        return min(cell_n, 5 if rel < 2.0 else 6)
    if cell_n <= 140:
        return min(cell_n, 8 if rel < 2.0 else 10)
    return min(cell_n, 12 if rel < 2.5 else 16)


def _group_key(pid: int, prow: dict, p2s: Dict[int, int]) -> Tuple[str, int, str]:
    """(region, state_id, adm0) — group by state when present else adm0."""
    adm0 = adm0_of(prow) or "UNK"
    region = ADM0_TO_REGION.get(adm0, "")
    sid = int(p2s.get(pid) or 0)
    return region, sid, adm0


def build_row_sparse_density_product(
    board_dir: str = "",
    *,
    scopes: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Plan merge for selected RoW regions (default: all REGION_TARGETS)."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []
    scope_set = set(scopes) if scopes else set(REGION_TARGETS.keys())

    base_list = _load_json(d / "provinces_base.json")["provinces"]
    base = {int(p["id"]): p for p in base_list}
    geo_list = _load_json(d / "provinces_geometry.json")["provinces"]
    geo = {int(g["id"]): g for g in geo_list}
    mem = _load_json(d / "hierarchy_membership_1936.json")
    p2s = {int(k): int(v) for k, v in (mem.get("province_to_state") or {}).items()}
    states_doc = _load_json(d / "province_states.json")
    state_names = {
        int(s.get("id") or 0): str(s.get("name") or "")
        for s in (states_doc.get("states") or [])
    }

    rows = row_ids(base)
    if len(rows) < 500:
        fails.append("row_block_too_small=%d" % len(rows))
    else:
        passes.append("row_block_n=%d" % len(rows))

    # Collect cells in scope
    by_group: Dict[Tuple[str, int, str], List[int]] = defaultdict(list)
    current_by_region: Dict[str, int] = Counter()
    unscoped = 0
    for pid in rows:
        prow = base[pid]
        region, sid, adm0 = _group_key(pid, prow, p2s)
        if not region or region not in scope_set:
            unscoped += 1
            continue
        by_group[(region, sid, adm0)].append(pid)
        current_by_region[region] += 1

    if not by_group:
        fails.append("no_scoped_groups")
    else:
        passes.append("groups_n=%d" % len(by_group))

    # Area proxies
    group_area: Dict[Tuple[str, int, str], float] = {}
    for key, pids in by_group.items():
        a = 0.0
        for pid in pids:
            a += _bbox_area((geo.get(pid) or {}).get("points") or [])
        group_area[key] = a
    areas = sorted(group_area.values())
    median_area = areas[len(areas) // 2] if areas else 1.0

    plan_rows: List[Dict[str, Any]] = []
    planned_by_region: Dict[str, int] = Counter()
    split_hist: Dict[int, int] = Counter()
    total_cells = 0
    total_play = 0
    already_in_band_regions: List[str] = []

    for key in sorted(by_group.keys(), key=lambda k: (k[0], k[2], k[1])):
        region, sid, adm0 = key
        pids = sorted(by_group[key])
        n = len(pids)
        total_cells += n
        # If region already within band, plan identity (no merge) for that region
        band = REGION_TARGETS.get(region) or {}
        cur = int(current_by_region.get(region) or 0)
        if band and int(band["min_playable"]) <= cur <= int(band["max_playable"]):
            n_play = n
            strategy = "already_in_band_keep"
            if region not in already_in_band_regions:
                already_in_band_regions.append(region)
        else:
            n_play = provinces_for_group_size(
                n, group_area[key], median_area, region=region
            )
            n_play = max(1, min(n_play, n))
            strategy = "merge_kmeans_hull_%d" % n_play
        split_hist[n_play] += 1
        total_play += n_play
        planned_by_region[region] += n_play
        plan_rows.append(
            {
                "region": region,
                "state_id": sid,
                "state_name": state_names.get(sid) or adm0 or ("state_%d" % sid),
                "adm0": adm0,
                "cell_n": n,
                "area_proxy": round(group_area[key], 1),
                "playable_provinces": n_play,
                "sample_ids": pids[:3],
                "strategy": strategy,
            }
        )

    # Band checks for scoped regions that have cells
    for region in sorted(scope_set):
        if region not in REGION_TARGETS:
            continue
        cur = int(current_by_region.get(region) or 0)
        if cur == 0:
            continue
        band = REGION_TARGETS[region]
        planned = int(planned_by_region.get(region) or 0)
        if region in already_in_band_regions:
            passes.append("%s_already_in_band=%d" % (region, cur))
            continue
        if int(band["min_playable"]) <= planned <= int(band["max_playable"]):
            passes.append("%s_planned_in_band=%d" % (region, planned))
        else:
            fails.append(
                "%s_planned_out_of_band=%d (want %d–%d, current=%d)"
                % (region, planned, band["min_playable"], band["max_playable"], cur)
            )

    reduction_pct = 100.0 * (1.0 - float(total_play) / float(max(1, total_cells)))
    if total_cells > total_play and reduction_pct >= 30.0:
        passes.append("reduction_pct=%.1f" % reduction_pct)
    elif total_cells == total_play and already_in_band_regions:
        passes.append("no_reduction_needed")
    elif total_cells > 0 and total_play < total_cells:
        passes.append("reduction_pct=%.1f" % reduction_pct)

    needs_write = any(
        r not in already_in_band_regions and int(current_by_region.get(r) or 0) > 0
        for r in scope_set
        if r in REGION_TARGETS
    )
    if needs_write:
        next_step = (
            "Run merge_row_sparse_to_playable.py --write --scopes "
            + ",".join(sorted(r for r in scope_set if r in current_by_region))
            + " (backup + remap + adjacency rebuild; never renumber world_full)."
        )
    else:
        next_step = "Scoped regions already in band; no board write needed."

    ok = len(fails) == 0 and total_cells > 0
    label = (
        "RoW sparse density · cells=%d → playable≈%d (scopes=%s) · reduce ~%.0f%% · %s"
        % (
            total_cells,
            total_play,
            ",".join(sorted(r for r in scope_set if current_by_region.get(r))),
            reduction_pct,
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "ok": ok,
        "empty": total_cells == 0,
        "status": "PASS" if ok else "FAIL",
        "row_block_n": len(rows),
        "scoped_cells_n": total_cells,
        "planned_playable_n": total_play,
        "current_by_region": dict(current_by_region),
        "planned_by_region": dict(planned_by_region),
        "already_in_band_regions": already_in_band_regions,
        "needs_write": needs_write,
        "reduction_pct": reduction_pct,
        "split_hist": {int(k): int(v) for k, v in sorted(split_hist.items())},
        "targets": REGION_TARGETS,
        "scopes": sorted(scope_set),
        "unscoped_row_n": unscoped,
        "plan_rows": plan_rows,
        "plan_rows_n": len(plan_rows),
        "pass": passes,
        "fail": fails,
        "summary": label,
        "next_write_step": next_step,
        "integration": [
            "row_sparse_density_product",
            "row_sparse_densify_prep_product",
            "merge_row_sparse_to_playable",
            "world_accurate",
        ],
        "constraints": [
            "never_renumber_world_full_ids",
            "keep_dual_board",
            "adjacency_land_shared_floor_0_97",
            "preserve_strait_chokepoints",
        ],
    }


def row_sparse_density_integrity(
    board_dir: str = "",
    *,
    scopes: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    p = build_row_sparse_density_product(board_dir=board_dir, scopes=scopes)
    return {
        "ok": bool(p.get("ok")),
        "scoped_cells_n": p.get("scoped_cells_n"),
        "planned_playable_n": p.get("planned_playable_n"),
        "planned_by_region": p.get("planned_by_region"),
        "needs_write": p.get("needs_write"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": bool(p.get("empty")),
    }
