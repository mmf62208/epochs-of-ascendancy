"""US province density toward HOI4/Vic3 — pure plan product.

Playtest (2026-07-21): 3221 TIGER counties as combat provinces is too dense.
HOI4 uses multi-province states; Vic3 elevates the state as the economic unit.

**Recommendation (shipped plan):**
  - **1–4 combat provinces per US state** by size (not always 1:1).
  - Small states (RI, DE, VT…): **1** province
  - Medium: **2**
  - Large (TX, CA, MT…): **3**
  - Very large / sparse (AK): **4**
  - Target band: **~90–160** US playable provinces (not 52 only, not 3221)

Does **not** renumber world_full. Write step later builds hulls / splits.
"""
from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

MIN_US_PLAY = 80
MAX_US_PLAY = 180
TARGET_US_PLAY = 120


def _bbox_area(points: List) -> float:
    xs = []
    ys = []
    for p in points or []:
        if isinstance(p, (list, tuple)) and len(p) >= 2:
            xs.append(float(p[0]))
            ys.append(float(p[1]))
    if len(xs) < 2:
        return 0.0
    return max(0.0, (max(xs) - min(xs)) * (max(ys) - min(ys)))


def _load_board(board_dir: Path) -> Dict[str, Any]:
    base = {
        int(p["id"]): p
        for p in json.loads((board_dir / "provinces_base.json").read_text(encoding="utf-8"))[
            "provinces"
        ]
    }
    geo_rows = json.loads((board_dir / "provinces_geometry.json").read_text(encoding="utf-8"))[
        "provinces"
    ]
    geo = {int(r["id"]): r for r in geo_rows}
    mem = json.loads((board_dir / "hierarchy_membership_1936.json").read_text(encoding="utf-8"))
    states_doc = json.loads((board_dir / "province_states.json").read_text(encoding="utf-8"))
    names = {
        int(s.get("id") or 0): str(s.get("name") or "") for s in (states_doc.get("states") or [])
    }
    p2s = {int(k): int(v) for k, v in (mem.get("province_to_state") or {}).items()}
    return {"base": base, "geo": geo, "p2s": p2s, "state_names": names}


def us_county_ids(base: Dict[int, dict]) -> List[int]:
    return sorted(pid for pid in base if 800000 <= pid < 900000)


def provinces_for_state_size(county_n: int, area: float, median_area: float) -> int:
    """1–4 combat provinces from county count + relative bbox area."""
    # Area relative to median state
    rel = area / median_area if median_area > 1e-6 else 1.0
    if county_n <= 5 and rel < 0.35:
        return 1
    if county_n <= 15 and rel < 0.7:
        return 1
    if rel < 0.9 and county_n < 40:
        return 2
    if rel < 1.8 and county_n < 80:
        return 2 if rel < 1.15 else 3
    if rel < 3.5:
        return 3
    return 4  # AK / TX-class


def build_us_state_province_density_product(
    board_dir: str = "",
) -> Dict[str, Any]:
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []
    data = _load_board(d)
    base = data["base"]
    geo = data["geo"]
    p2s = data["p2s"]
    names = data["state_names"]

    counties = us_county_ids(base)
    n_county = len(counties)
    # Post-merge board: US block already in playable band (1–4/state ~80–180)
    already_merged = MIN_US_PLAY <= n_county <= MAX_US_PLAY
    if already_merged:
        passes.append("us_already_playable_merged=%d" % n_county)
    elif n_county < 3000:
        fails.append("us_county_n_low=%d" % n_county)
    else:
        passes.append("us_counties=%d" % n_county)

    by_state: Dict[int, List[int]] = defaultdict(list)
    unassigned = 0
    for pid in counties:
        sid = int(p2s.get(pid) or 0)
        if sid <= 0:
            unassigned += 1
            continue
        by_state[sid].append(pid)

    n_states = len(by_state)
    if n_states < 48:
        fails.append("us_states_low=%d" % n_states)
    else:
        passes.append("us_states=%d" % n_states)
    if unassigned:
        fails.append("unassigned_counties=%d" % unassigned)
    else:
        passes.append("all_counties_in_states")

    # State bbox areas (sum of county bboxes — proxy for size)
    state_area: Dict[int, float] = {}
    for sid, pids in by_state.items():
        a = 0.0
        for pid in pids:
            a += _bbox_area((geo.get(pid) or {}).get("points") or [])
        state_area[sid] = a
    areas = sorted(state_area.values())
    median_area = areas[len(areas) // 2] if areas else 1.0

    plan_rows: List[Dict[str, Any]] = []
    total_play = 0
    split_hist = {1: 0, 2: 0, 3: 0, 4: 0}
    for sid in sorted(by_state.keys()):
        pids = by_state[sid]
        n_prov = provinces_for_state_size(len(pids), state_area[sid], median_area)
        split_hist[n_prov] = split_hist.get(n_prov, 0) + 1
        total_play += n_prov
        plan_rows.append(
            {
                "state_id": sid,
                "name": names.get(sid) or ("US State %d" % sid),
                "county_n": len(pids),
                "area_proxy": round(state_area[sid], 1),
                "playable_provinces": n_prov,
                "sample_county_ids": pids[:3],
                "strategy": "merge_counties_then_split_%d" % n_prov,
            }
        )

    if already_merged:
        # Already merged: each "county" cell is a playable province; plan = current
        total_play = n_county
        split_hist = {1: 0, 2: 0, 3: 0, 4: 0}
        for sid, pids in by_state.items():
            # After merge, states typically hold 1–4 playable cells
            n = min(4, max(1, len(pids)))
            split_hist[n] = split_hist.get(n, 0) + 1
        plan_rows = [
            {
                "state_id": sid,
                "name": names.get(sid) or ("US State %d" % sid),
                "county_n": len(pids),
                "area_proxy": round(state_area[sid], 1),
                "playable_provinces": len(pids),
                "sample_county_ids": pids[:3],
                "strategy": "already_merged_playable",
            }
            for sid, pids in sorted(by_state.items())
        ]
        passes.append("planned_playable_in_band=%d" % total_play)
        reduction_pct = 0.0
        rec = (
            "US board already merged to playable density (~%d cells / %d states, band %d–%d)."
            % (total_play, n_states, MIN_US_PLAY, MAX_US_PLAY)
        )
        next_step = "No write needed; board is post merge_us_counties_to_state_provinces."
    else:
        if MIN_US_PLAY <= total_play <= MAX_US_PLAY:
            passes.append("planned_playable_in_band=%d" % total_play)
        else:
            fails.append(
                "planned_playable_out_of_band=%d (want %d–%d)"
                % (total_play, MIN_US_PLAY, MAX_US_PLAY)
            )

        reduction_pct = 100.0 * (1.0 - float(total_play) / float(max(1, n_county)))
        if reduction_pct > 90.0:
            passes.append("reduction_pct=%.1f" % reduction_pct)

        rec = (
            "Recommend 1–4 combat provinces per US state by size (HOI-like), "
            "not 1:1 state-only and not 3221 counties. "
            "Planned ~%d playable (from %d counties / %d states)."
            % (total_play, n_county, n_states)
        )
        next_step = (
            "Implement merge_us_counties_to_state_provinces.py --write --splits 1-4: "
            "per-state hull (or k-means/region split of counties into N polys), "
            "new playable IDs dual-block or collapse 800000+; rebuild adjacency; "
            "keep hierarchy state_id; never renumber world_full."
        )

    passes.append("recommendation_1_to_4")

    ok = len(fails) == 0
    if already_merged:
        label = (
            "US density · already_merged playable=%d states=%d · %s"
            % (total_play, n_states, "PASS" if ok else "FAIL")
        )
    else:
        label = (
            "US density · counties=%d → states=%d → playable≈%d (1–4/state) · reduce ~%.0f%% · %s"
            % (n_county, n_states, total_play, reduction_pct, "PASS" if ok else "FAIL")
        )
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "us_county_n": n_county,
        "us_state_n": n_states,
        "planned_playable_us_n": total_play,
        "current_playable_us_n": n_county,
        "already_merged": already_merged,
        "reduction_pct": reduction_pct,
        "split_hist": split_hist,
        "target_band": [MIN_US_PLAY, MAX_US_PLAY],
        "target_hint": TARGET_US_PLAY,
        "recommendation": rec,
        "plan_rows": plan_rows,
        "plan_rows_n": len(plan_rows),
        "pass": passes,
        "fail": fails,
        "summary": label,
        "next_write_step": next_step,
        "integration": [
            "us_state_province_density_product",
            "map_density",
            "hoi4",
            "vic3",
            "tiger",
            "world_accurate",
        ],
    }


def us_state_province_density_integrity(board_dir: str = "") -> Dict[str, Any]:
    p = build_us_state_province_density_product(board_dir=board_dir)
    return {
        "ok": bool(p.get("ok")),
        "us_county_n": p.get("us_county_n"),
        "us_state_n": p.get("us_state_n"),
        "planned_playable_us_n": p.get("planned_playable_us_n"),
        "split_hist": p.get("split_hist"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
