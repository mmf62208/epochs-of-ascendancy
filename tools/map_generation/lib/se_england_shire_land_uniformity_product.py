"""FEED-9 SE England shire land-area uniformity — Mike province-sizing bar #1.

Default ``world_accurate`` NUTS-3 cells in SE England shires are not
operationally uniform: Oxfordshire is a giant (~231 canvas area) while
neighboring shires sit near the theater median (~33). This product is a
**one-theater proof** (not a Europe remesh, not Maginot, not Flanders,
not Greater London grow):

* Split giant Oxfordshire ``711438`` (axis-balanced). Parent ID stays on
  the inland historic-core piece (centroid closer to the original
  Oxfordshire centroid — Maginot default keep, not Flanders coastal
  keep). Children are **append-only** Europe IDs starting at ``711523``
  (after Flanders secondary ``711522``). Never reuse ``711514–711522``.
* Optional **one** secondary split of the remaining in-window Oxfordshire
  keep if post-primary max/median is still ``> ~5``. No grow-pass.
  Do not split the second giant (Central Hampshire ``711449``).

Write: tools/map_generation/scripts/apply_se_england_shire_land_uniformity.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence, Tuple

from maginot_land_uniformity_product import (
    _bump_adj_stats,
    _clone_layer_rows,
    _insert_hierarchy_and_ownership,
    _insert_state_and_region_ids,
    _is_water,
    _open_ring,
    _replace_parent_population,
    _rewrite_adj_for_theater,
    best_axis_split,
    canvas_to_lonlat,
    compass_suffix,
    load_board,
    polygon_area,
    polygon_centroid,
    rings_touch,
    surgical_append_geometry_provinces,
    surgical_insert_adjacency_keys,
    surgical_replace_adjacency_keys,
    surgical_replace_geometry_provinces,
    theater_metrics,
)

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

# Tight operational SE England shire corridor (label-anchor lon/lat).
# Excludes Maginot FEED-2 6.0–8.8°E / 47.55–49.45°N and Flanders
# FEED-7 2.5–4.8°E / 50.3–51.6°N land meshes.
THEATER_LONLAT = (-1.5, 50.5, 1.8, 52.2)
MAGINOT_THEATER_LONLAT = (6.0, 47.55, 8.8, 49.45)
FLANDERS_THEATER_LONLAT = (2.5, 50.3, 4.8, 51.6)

# Greater London urban pinpricks — exclude from shire metrics; do not grow.
LONDON_BOX = (-0.5, 51.3, 0.3, 51.7)
LONDON_AREA_MAX = 8.0

# Frozen pre-FEED diagnosis (tight window, shire-only land) — 1388a3e board.
PRE_FEED_METRICS: Dict[str, float] = {
    "n": 38.0,
    "min": 1.45,
    "p25": 11.38,
    "median": 33.35,
    "p75": 88.3,
    "max": 231.07,
    "max_over_median": 6.93,
    "max_over_min": 159.04,
}

OXFORDSHIRE_ID = 711438
HAMPSHIRE_ID = 711449  # second giant — out of scope unless Oxfordshire keep
LONDON_CAPITAL_ID = 711414  # Camden and City of London — no grow-pass
NORD_ID = 710734
NORD_EAST_ID = 711521
NORD_SOUTH_ID = 711522
GIBRALTAR_ID = 711520
LIGURIAN_ID = 950119
MAGINOT_GER_ID = 710173
MAGINOT_FRA_ID = 710739

# Tip-frozen meshes that this FEED must not rewrite.
FROZEN_MESH_AREA: Dict[int, float] = {
    NORD_ID: 125.48,
    NORD_EAST_ID: 241.54,
    NORD_SOUTH_ID: 130.16,
    MAGINOT_GER_ID: 48.06,
    MAGINOT_FRA_ID: 201.70,
    GIBRALTAR_ID: 1.0,  # island key; area check is name + presence
    LIGURIAN_ID: 1340.58,
    HAMPSHIRE_ID: 215.21,
    LONDON_CAPITAL_ID: 2.43,
}

# Append-only Europe NUTS after Flanders secondary. Never reuse Maginot /
# Gibraltar / Flanders children.
NEW_ID_START = 711523
PRIMARY_CHILD_ID = 711523
SECONDARY_CHILD_ID = 711524
RESERVED_PRIOR_IDS: Tuple[int, ...] = tuple(range(711514, 711523))

SECONDARY_MAX_OVER_MEDIAN = 5.0
MAGINOT_CLASS_MAX = 290.0

FEED_META = "v1_se_england_shire_land_uniform"

Ring = List[List[float]]


def is_greater_london_pinprick(name: Any, area: float, lon: float, lat: float) -> bool:
    """Shire-only filter: Greater London urban pinpricks are not the bar."""
    if "London" in str(name or ""):
        return True
    lon0, lat0, lon1, lat1 = LONDON_BOX
    return lon0 <= lon <= lon1 and lat0 <= lat <= lat1 and float(area) < LONDON_AREA_MAX


def theater_land_rows(
    base: Mapping[int, Mapping[str, Any]],
    geo: Mapping[int, Mapping[str, Any]],
    window: Sequence[float] = THEATER_LONLAT,
    *,
    shire_only: bool = True,
) -> List[Dict[str, Any]]:
    lon0, lat0, lon1, lat1 = (float(x) for x in window)
    rows: List[Dict[str, Any]] = []
    for pid, p in base.items():
        if _is_water(p):
            continue
        g = geo.get(int(pid)) or {}
        pts = g.get("points") or []
        la = g.get("label_anchor") or list(polygon_centroid(pts))
        if not isinstance(la, (list, tuple)) or len(la) < 2:
            continue
        lon, lat = canvas_to_lonlat(float(la[0]), float(la[1]))
        if lon0 <= lon <= lon1 and lat0 <= lat <= lat1:
            area = polygon_area(pts)
            if shire_only and is_greater_london_pinprick(p.get("name"), area, lon, lat):
                continue
            rows.append(
                {
                    "id": int(pid),
                    "name": p.get("name"),
                    "area": area,
                    "lon": lon,
                    "lat": lat,
                    "cntr": p.get("cntr_code"),
                }
            )
    return rows


def _label_lonlat(ring: Sequence[Sequence[float]]) -> Tuple[float, float]:
    cx, cy = polygon_centroid(ring)
    return canvas_to_lonlat(cx, cy)


def _in_window(ring: Sequence[Sequence[float]], window: Sequence[float] = THEATER_LONLAT) -> bool:
    lon, lat = _label_lonlat(ring)
    lon0, lat0, lon1, lat1 = (float(x) for x in window)
    return lon0 <= lon <= lon1 and lat0 <= lat <= lat1


def _choose_shire_keep(
    pieces: Sequence[Ring],
    original_centroid: Sequence[float],
) -> Tuple[Ring, Ring]:
    """Keep the piece closer to the original Oxfordshire centroid.

    Inland shire analog of Flanders coastal/Channel keep and Maginot's
    default keep: parent ID stays on the historic name-bearing core.
    Oxfordshire has no Channel-sea relationship, so distance-to-sea is
    the wrong keep signal.
    """
    a, b = pieces[0], pieces[1]
    ocx, ocy = float(original_centroid[0]), float(original_centroid[1])
    ac = polygon_centroid(a)
    bc = polygon_centroid(b)
    da = math.hypot(ac[0] - ocx, ac[1] - ocy)
    db = math.hypot(bc[0] - ocx, bc[1] - ocy)
    if da <= db:
        return a, b
    return b, a


def _unique_child_name(
    parent_name: str,
    keep_c: Sequence[float],
    child_c: Sequence[float],
    used: Sequence[str],
) -> str:
    suffix = compass_suffix(keep_c, child_c)
    name = f"{parent_name} {suffix}"
    if name not in used:
        return name
    dx = float(child_c[0]) - float(keep_c[0])
    dy = float(child_c[1]) - float(keep_c[1])
    if abs(dx) >= abs(dy):
        alt = "South" if dy > 0 else "North"
    else:
        alt = "East" if dx > 0 else "West"
    name = f"{parent_name} {alt}"
    if name not in used:
        return name
    n = 2
    while f"{parent_name} {suffix} {n}" in used:
        n += 1
    return f"{parent_name} {suffix} {n}"


def _split_spec(
    parent_id: int,
    child_id: int,
    parent_name: str,
    keep: Ring,
    child: Ring,
    parent_area_before: float,
    used_names: List[str],
) -> Dict[str, Any]:
    kcx, kcy = polygon_centroid(keep)
    ccx, ccy = polygon_centroid(child)
    child_name = _unique_child_name(parent_name, (kcx, kcy), (ccx, ccy), used_names)
    used_names.append(child_name)
    return {
        "parent_id": int(parent_id),
        "child_id": int(child_id),
        "parent_name": parent_name,
        "child_name": child_name,
        "keep_ring": keep,
        "child_ring": child,
        "keep_area": polygon_area(keep),
        "child_area": polygon_area(child),
        "parent_area_before": float(parent_area_before),
        "keep_lonlat": list(_label_lonlat(keep)),
        "child_lonlat": list(_label_lonlat(child)),
        "child_in_window": _in_window(child),
        "keep_in_window": _in_window(keep),
        "keep_rule": "original_centroid",
    }


def _metrics_with_rings(
    base: Mapping[int, Mapping[str, Any]],
    geo: Mapping[int, Mapping[str, Any]],
    replaced: Mapping[int, Ring],
) -> Dict[str, float]:
    """Shire-only theater metrics, including new child rings not yet in base."""
    rows: List[Dict[str, Any]] = []
    seen: set[int] = set()
    lon0, lat0, lon1, lat1 = THEATER_LONLAT

    def _maybe_add(pid: int, name: Any, ring: Sequence[Sequence[float]]) -> None:
        if not ring:
            return
        la = list(polygon_centroid(ring))
        lon, lat = canvas_to_lonlat(float(la[0]), float(la[1]))
        if not (lon0 <= lon <= lon1 and lat0 <= lat <= lat1):
            return
        area = polygon_area(ring)
        if is_greater_london_pinprick(name, area, lon, lat):
            return
        rows.append({"id": int(pid), "area": area})
        seen.add(int(pid))

    for pid, p in base.items():
        if _is_water(p):
            continue
        ring = replaced.get(int(pid))
        if ring is None:
            g = geo.get(int(pid)) or {}
            ring = g.get("points") or []
        _maybe_add(int(pid), p.get("name"), ring)
    for pid, ring in replaced.items():
        if int(pid) in seen:
            continue
        _maybe_add(int(pid), (base.get(int(pid)) or {}).get("name") or "child", ring)
    return theater_metrics(rows)


def plan_se_england_shire_land_uniformity(board_dir: str = "") -> Dict[str, Any]:
    """Compute Oxfordshire split rings (+ optional secondary). Does not write."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    already = int(PRIMARY_CHILD_ID) in base and int(PRIMARY_CHILD_ID) in geo
    if already:
        return _static_plan_from_board(base, geo)

    ox_geo = geo[OXFORDSHIRE_ID]
    ox_pts = ox_geo.get("points") or []
    parent_name = str(
        (base.get(OXFORDSHIRE_ID) or {}).get("name") or ox_geo.get("name") or "Oxfordshire"
    )
    original_c = polygon_centroid(ox_pts)
    p1, p2 = best_axis_split(ox_pts)
    keep, child = _choose_shire_keep((p1, p2), original_c)
    used_names: List[str] = []
    splits: List[Dict[str, Any]] = [
        _split_spec(
            OXFORDSHIRE_ID,
            PRIMARY_CHILD_ID,
            parent_name,
            keep,
            child,
            polygon_area(ox_pts),
            used_names,
        )
    ]
    replaced: Dict[int, Ring] = {OXFORDSHIRE_ID: keep, PRIMARY_CHILD_ID: child}
    post_primary = _metrics_with_rings(base, geo, replaced)
    secondary = False
    if float(post_primary.get("max_over_median") or 0.0) > SECONDARY_MAX_OVER_MEDIAN:
        s1, s2 = best_axis_split(keep)
        keep2, child2 = _choose_shire_keep((s1, s2), original_c)
        splits.append(
            _split_spec(
                OXFORDSHIRE_ID,
                SECONDARY_CHILD_ID,
                parent_name,
                keep2,
                child2,
                polygon_area(keep),
                used_names,
            )
        )
        keep = keep2
        replaced[OXFORDSHIRE_ID] = keep
        replaced[SECONDARY_CHILD_ID] = child2
        secondary = True

    new_ids = [int(s["child_id"]) for s in splits]
    return {
        "already_applied": False,
        "splits": splits,
        "grows": [],
        "new_ids": new_ids,
        "secondary": secondary,
        "post_primary_metrics": post_primary,
        "keep_rule": "original_centroid",
        "preserved_ids": [OXFORDSHIRE_ID, HAMPSHIRE_ID, LONDON_CAPITAL_ID, GIBRALTAR_ID],
        "reserved_prior_ids": list(RESERVED_PRIOR_IDS),
    }


def _static_plan_from_board(
    base: Mapping[int, Mapping[str, Any]],
    geo: Mapping[int, Mapping[str, Any]],
) -> Dict[str, Any]:
    child_ids = [PRIMARY_CHILD_ID]
    if int(SECONDARY_CHILD_ID) in base:
        child_ids.append(SECONDARY_CHILD_ID)
    splits = []
    for child_id in child_ids:
        splits.append(
            {
                "parent_id": OXFORDSHIRE_ID,
                "child_id": int(child_id),
                "parent_name": (base.get(OXFORDSHIRE_ID) or {}).get("name"),
                "child_name": (base.get(int(child_id)) or {}).get("name"),
                "keep_ring": _open_ring((geo.get(OXFORDSHIRE_ID) or {}).get("points") or []),
                "child_ring": _open_ring((geo.get(int(child_id)) or {}).get("points") or []),
                "keep_area": polygon_area((geo.get(OXFORDSHIRE_ID) or {}).get("points") or []),
                "child_area": polygon_area((geo.get(int(child_id)) or {}).get("points") or []),
            }
        )
    return {
        "already_applied": True,
        "splits": splits,
        "grows": [],
        "new_ids": child_ids,
        "secondary": SECONDARY_CHILD_ID in child_ids,
        "keep_rule": "original_centroid",
        "preserved_ids": [OXFORDSHIRE_ID, HAMPSHIRE_ID, LONDON_CAPITAL_ID, GIBRALTAR_ID],
        "reserved_prior_ids": list(RESERVED_PRIOR_IDS),
    }


def _geo_object(
    old: Mapping[str, Any],
    pid: int,
    name: str,
    ring: Ring,
    extra_meta: Mapping[str, Any],
) -> Dict[str, Any]:
    cx, cy = polygon_centroid(ring)
    obj = dict(old)
    obj["id"] = int(pid)
    obj["name"] = name
    obj["points"] = [[float(p[0]), float(p[1])] for p in ring]
    obj["label_anchor"] = [cx, cy]
    meta = dict(obj.get("meta") or {})
    meta["se_england_shire_land_feed"] = FEED_META
    meta["vertex_n"] = len(ring)
    meta["area"] = polygon_area(ring)
    meta.update(dict(extra_meta))
    obj["meta"] = meta
    return obj


def _append_oxfordshire_base_children(
    d: Path,
    plan: Mapping[str, Any],
    base: Mapping[int, Mapping[str, Any]],
) -> None:
    """Clone Oxfordshire onto children; allocate population by final piece area."""
    path = d / "provinces_base.json"
    raw = path.read_text(encoding="utf-8")
    parent = dict(base[OXFORDSHIRE_ID])
    parent_pop = int(parent.get("population_base") or 0)
    final_keep = float((plan.get("splits") or [{}])[-1].get("keep_area") or 0.0)
    child_areas = [float(s.get("child_area") or 0.0) for s in (plan.get("splits") or [])]
    total = final_keep + sum(child_areas)
    allocated = 0
    new_objs: List[str] = []
    for spec in plan.get("splits") or []:
        child = dict(parent)
        child["id"] = int(spec["child_id"])
        child["name"] = spec["child_name"]
        ratio = float(spec["child_area"]) / max(total, 1e-6)
        child["population_base"] = max(1, int(round(parent_pop * ratio)))
        allocated += int(child["population_base"])
        new_objs.append(json.dumps(child, indent=2))
    keep_pop = max(1, parent_pop - allocated)
    raw = _replace_parent_population(raw, OXFORDSHIRE_ID, keep_pop)
    indented = []
    for blob in new_objs:
        lines = blob.splitlines()
        indented.append("    " + lines[0] + "\n" + "\n".join("    " + ln if ln else ln for ln in lines[1:]))
    insert = ",\n" + ",\n".join(indented)
    close = raw.rfind("]")
    if close < 0:
        raise ValueError("provinces_base.json missing array close")
    path.write_text(raw[:close].rstrip() + insert + "\n  ]\n}\n", encoding="utf-8")


def _bump_shire_manifest(d: Path, added: int) -> None:
    path = d / "manifest_world_accurate.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    stats = doc.setdefault("stats", {})
    stats["provinces"] = int(stats.get("provinces") or 0) + int(added)
    stats["land"] = int(stats.get("land") or 0) + int(added)
    blocks = doc.setdefault("blocks", {})
    if "europe_nuts3" in blocks:
        blocks["europe_nuts3"] = int(blocks["europe_nuts3"]) + int(added)
    gq = str(doc.get("geometry_quality") or "")
    if FEED_META not in gq:
        doc["geometry_quality"] = (gq + "+" + FEED_META) if gq else FEED_META
    path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def apply_se_england_shire_land_uniformity(board_dir: str = "") -> Dict[str, Any]:
    """Write Oxfordshire split geometry + layer clones. Existing IDs stay. No grow."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    plan = plan_se_england_shire_land_uniformity(str(d))
    if plan.get("already_applied"):
        board = load_board(d)
        finish_plan = _static_plan_from_board(board["base"], board["geo"])
        _insert_hierarchy_and_ownership(d, finish_plan)
        _insert_state_and_region_ids(d, finish_plan)
        return {
            "ok": True,
            "already_applied": True,
            "new_ids": list(finish_plan.get("new_ids") or []),
            "renumbered": False,
            "finished_remaining_layers": True,
            "world_full_touched": False,
        }

    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    adj: Dict[int, List[int]] = board["adj"]

    geo_updates: Dict[int, Dict[str, Any]] = {}
    new_geo: List[Dict[str, Any]] = []
    old_ox = dict(geo[OXFORDSHIRE_ID])
    final_keep = plan["splits"][-1]["keep_ring"] if plan["splits"] else []
    geo_updates[OXFORDSHIRE_ID] = _geo_object(
        old_ox,
        OXFORDSHIRE_ID,
        str((base.get(OXFORDSHIRE_ID) or {}).get("name") or "Oxfordshire"),
        final_keep,
        {"split_children": [int(s["child_id"]) for s in plan["splits"]]},
    )
    geo[OXFORDSHIRE_ID] = geo_updates[OXFORDSHIRE_ID]

    for spec in plan["splits"]:
        child_id = int(spec["child_id"])
        child_obj = _geo_object(
            old_ox,
            child_id,
            spec["child_name"],
            spec["child_ring"],
            {"split_parent": OXFORDSHIRE_ID},
        )
        geo[child_id] = child_obj
        new_geo.append(child_obj)

    working_keep = plan["splits"][0]["keep_ring"]
    for spec in plan["splits"]:
        _rewrite_adj_for_theater(
            adj,
            geo,
            OXFORDSHIRE_ID,
            int(spec["child_id"]),
            spec["keep_ring"],
            spec["child_ring"],
        )
        working_keep = spec["keep_ring"]
        geo[OXFORDSHIRE_ID] = _geo_object(
            old_ox,
            OXFORDSHIRE_ID,
            str((base.get(OXFORDSHIRE_ID) or {}).get("name") or "Oxfordshire"),
            working_keep,
            {"split_children": [int(s["child_id"]) for s in plan["splits"]]},
        )
        geo[int(spec["child_id"])] = _geo_object(
            old_ox,
            int(spec["child_id"]),
            spec["child_name"],
            spec["child_ring"],
            {"split_parent": OXFORDSHIRE_ID},
        )

    existing_keys = set(int(k) for k in (board["adj_doc"].get("adjacency") or {}))
    touched_adj: Dict[int, List[int]] = {}
    new_adj: Dict[int, List[int]] = {}
    for pid, nbrs in adj.items():
        if int(pid) in existing_keys:
            touched_adj[int(pid)] = list(nbrs)
        else:
            new_adj[int(pid)] = list(nbrs)

    surgical_replace_geometry_provinces(d / "provinces_geometry.json", geo_updates)
    surgical_append_geometry_provinces(d / "provinces_geometry.json", new_geo)
    if touched_adj:
        surgical_replace_adjacency_keys(d / "province_adjacency.json", touched_adj)
    if new_adj:
        surgical_insert_adjacency_keys(d / "province_adjacency.json", new_adj)

    _append_oxfordshire_base_children(d, plan, base)
    _clone_layer_rows(d, plan)
    _insert_hierarchy_and_ownership(d, plan)
    _insert_state_and_region_ids(d, plan)
    _bump_shire_manifest(d, added=len(plan["splits"]))
    _bump_adj_stats(d, added=len(plan["splits"]))

    return {
        "ok": True,
        "already_applied": False,
        "board_dir": str(d),
        "new_ids": [int(s["child_id"]) for s in plan["splits"]],
        "split_parents": [OXFORDSHIRE_ID],
        "grown_ids": [],
        "donor_ids": [],
        "secondary": bool(plan.get("secondary")),
        "keep_rule": "original_centroid",
        "renumbered": False,
        "world_full_touched": False,
        "post_primary_metrics": plan.get("post_primary_metrics"),
        "splits": [
            {
                "parent_id": int(s["parent_id"]),
                "child_id": int(s["child_id"]),
                "parent_name": s["parent_name"],
                "child_name": s["child_name"],
                "keep_area": round(float(s["keep_area"]), 1),
                "child_area": round(float(s["child_area"]), 1),
                "parent_area_before": round(float(s["parent_area_before"]), 1),
            }
            for s in plan["splits"]
        ],
        "grows": [],
    }


def _mesh_untouched(geo: Mapping[int, Mapping[str, Any]], pid: int, expected: float, slop: float = 0.6) -> bool:
    area = polygon_area((geo.get(int(pid)) or {}).get("points") or [])
    if expected <= 2.0:
        return abs(area - expected) <= 0.35 or (pid == GIBRALTAR_ID and area > 0.2)
    return abs(area - expected) <= slop


def build_se_england_shire_land_uniformity_product(board_dir: str = "") -> Dict[str, Any]:
    """QC shipped accurate board: SE England shire land cells less extreme."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []
    if not (d / "provinces_base.json").is_file():
        return {"ok": False, "summary": "missing world_accurate board", "empty": True}
    board = load_board(d)
    base = board["base"]
    geo = board["geo"]
    adj = board["adj"]
    rows = theater_land_rows(base, geo)
    metrics = theater_metrics(rows)
    pre = PRE_FEED_METRICS

    if int(metrics["n"]) < 35:
        fails.append(f"theater_thin n={metrics['n']}")
    else:
        passes.append(f"theater_n={int(metrics['n'])}")

    if metrics["max"] >= pre["max"] - 1.0:
        fails.append(f"max_not_reduced {metrics['max']:.1f} >= pre {pre['max']:.1f}")
    else:
        passes.append(f"max {pre['max']:.1f}→{metrics['max']:.1f}")

    if metrics["max_over_median"] >= pre["max_over_median"] - 0.15:
        fails.append(
            f"max/med_not_reduced {metrics['max_over_median']:.2f} >= pre {pre['max_over_median']:.2f}"
        )
    else:
        passes.append(f"max/med {pre['max_over_median']:.2f}→{metrics['max_over_median']:.2f}")

    if metrics["max"] > MAGINOT_CLASS_MAX:
        fails.append(f"max_still_extreme {metrics['max']:.1f}")
    else:
        passes.append(f"max_band={metrics['max']:.1f}")

    if metrics["max_over_median"] > SECONDARY_MAX_OVER_MEDIAN + 0.35:
        fails.append(f"max/med_above_maginot_class {metrics['max_over_median']:.2f}")
    else:
        passes.append(f"max/med_band={metrics['max_over_median']:.2f}")

    if int(OXFORDSHIRE_ID) not in base or int(OXFORDSHIRE_ID) not in geo:
        fails.append(f"lost_existing_id {OXFORDSHIRE_ID}")
    else:
        if str((base.get(OXFORDSHIRE_ID) or {}).get("name") or "") != "Oxfordshire":
            fails.append("oxfordshire_renamed")
        else:
            passes.append("oxfordshire_parent_kept")

    if int(HAMPSHIRE_ID) not in base or int(HAMPSHIRE_ID) not in geo:
        fails.append("hampshire_lost")
    else:
        if str((base.get(HAMPSHIRE_ID) or {}).get("name") or "") != "Central Hampshire":
            fails.append("hampshire_renamed")
        elif not _mesh_untouched(geo, HAMPSHIRE_ID, FROZEN_MESH_AREA[HAMPSHIRE_ID]):
            fails.append("hampshire_remeshed")
        else:
            passes.append("hampshire_unsplit")

    if str((base.get(LONDON_CAPITAL_ID) or {}).get("name") or "").find("London") < 0:
        fails.append("london_capital_disturbed")
    elif not _mesh_untouched(geo, LONDON_CAPITAL_ID, FROZEN_MESH_AREA[LONDON_CAPITAL_ID]):
        fails.append("greater_london_grown")
    else:
        passes.append("greater_london_ungrown")

    if str((base.get(GIBRALTAR_ID) or {}).get("name") or "") != "Gibraltar":
        fails.append("gibraltar_711520_disturbed")
    else:
        passes.append("gibraltar_711520")

    for pid in RESERVED_PRIOR_IDS:
        if int(pid) not in base or int(pid) not in geo:
            fails.append(f"lost_reserved_prior_id {pid}")
    if not any(f.startswith("lost_reserved") for f in fails):
        passes.append("reserved_711514_711522_kept")

    new_ids = [PRIMARY_CHILD_ID]
    if int(SECONDARY_CHILD_ID) in base:
        new_ids.append(SECONDARY_CHILD_ID)
    if PRIMARY_CHILD_ID not in base or PRIMARY_CHILD_ID not in geo:
        fails.append(f"missing_append_id {PRIMARY_CHILD_ID}")
    else:
        passes.append(f"append_ids={new_ids}")
        for pid in new_ids:
            if str((base.get(int(pid)) or {}).get("domain") or "land").lower() != "land":
                fails.append(f"child_not_land {pid}")
            if int(pid) >= 800000 or int(pid) < NEW_ID_START:
                fails.append(f"child_id_left_europe_append_block {pid}")
            if int(pid) in RESERVED_PRIOR_IDS:
                fails.append(f"reused_reserved_id {pid}")

    if PRIMARY_CHILD_ID in geo and OXFORDSHIRE_ID in geo:
        ox_pts = _open_ring((geo.get(OXFORDSHIRE_ID) or {}).get("points") or [])
        child_pts = _open_ring((geo.get(PRIMARY_CHILD_ID) or {}).get("points") or [])
        if OXFORDSHIRE_ID not in (adj.get(PRIMARY_CHILD_ID) or []) and PRIMARY_CHILD_ID not in (
            adj.get(OXFORDSHIRE_ID) or []
        ):
            if not rings_touch(ox_pts, child_pts):
                fails.append("oxfordshire_family_not_adjacent")
            else:
                passes.append("oxfordshire_family_rings_touch")
        else:
            passes.append("oxfordshire_family_adj")
        if polygon_area(ox_pts) >= pre["max"] - 1.0:
            fails.append(f"oxfordshire_keep_still_giant {polygon_area(ox_pts):.1f}")
        else:
            passes.append("oxfordshire_keep_shrunk")

    maginot_rows = theater_land_rows(base, geo, MAGINOT_THEATER_LONLAT, shire_only=False)
    if maginot_rows and max(float(r["area"]) for r in maginot_rows) > MAGINOT_CLASS_MAX:
        fails.append("maginot_theater_disturbed")
    else:
        passes.append("maginot_window_untouched")

    flanders_rows = theater_land_rows(base, geo, FLANDERS_THEATER_LONLAT, shire_only=False)
    if flanders_rows and max(float(r["area"]) for r in flanders_rows) > MAGINOT_CLASS_MAX:
        fails.append("flanders_theater_disturbed")
    else:
        passes.append("flanders_window_untouched")

    for pid, expected in FROZEN_MESH_AREA.items():
        if pid == GIBRALTAR_ID:
            continue
        if not _mesh_untouched(geo, pid, expected):
            fails.append(f"frozen_mesh_rewritten {pid}")
    if not any(str(f).startswith("frozen_mesh") for f in fails):
        passes.append("maginot_flanders_ligurian_hampshire_london_meshes")

    if str((base.get(LIGURIAN_ID) or {}).get("name") or "") != "Ligurian Sea":
        fails.append("ligurian_renamed")
    else:
        passes.append("ligurian_950119")

    n_board = len(base)
    if n_board < 3510 or n_board > 3545:
        fails.append(f"board_scale_left_3520_band n={n_board}")
    else:
        passes.append(f"board_n={n_board}")

    world_full = ROOT / "data" / "provinces_world_full"
    if world_full.is_dir() and (world_full / "provinces_base.json").is_file():
        wf_ids = {
            int(p["id"])
            for p in json.loads((world_full / "provinces_base.json").read_text(encoding="utf-8")).get(
                "provinces"
            )
            or []
        }
        for pid in new_ids:
            if int(pid) in wf_ids:
                fails.append(f"world_full_received_{pid}")
        if not any(str(f).startswith("world_full_received") for f in fails):
            passes.append("world_full_untouched")
    else:
        passes.append("world_full_untouched_by_product")

    renderer = ROOT / "scripts" / "map" / "MapRenderer.gd"
    if renderer.is_file() and "pale-map residual" in renderer.read_text(encoding="utf-8"):
        passes.append("pale_map_renderer_untouched")
    else:
        fails.append("pale_map_renderer_missing_marker")

    fill_toe = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"
    if fill_toe.is_file() and "_fill_toe_fold_line" in fill_toe.read_text(encoding="utf-8"):
        passes.append("fill_toe_untouched")
    else:
        fails.append("fill_toe_marker_missing")

    doc = ROOT / "docs" / "MAP_SE_ENGLAND_SHIRE_LAND_UNIFORMITY.md"
    if doc.is_file():
        body = doc.read_text(encoding="utf-8")
        if (
            "FEED-9" in body
            and "Never renumber" in body
            and "711523" in body
            and "711438" in body
            and "-1.5" in body
            and "original_centroid" in body
        ):
            passes.append("design_note")
        else:
            fails.append("design_note_thin")
    else:
        fails.append("design_note_missing")

    ok = not fails
    return {
        "ok": ok,
        "summary": "PASS se england shire land uniformity" if ok else "FAIL " + "; ".join(fails[:6]),
        "passes": passes,
        "fails": fails,
        "metrics": metrics,
        "pre_feed_metrics": pre,
        "new_ids": new_ids,
        "renumbered": False,
        "world_full_dir_exists": world_full.is_dir(),
        "oxfordshire_id": OXFORDSHIRE_ID,
        "keep_rule": "original_centroid",
        "theater_n": int(metrics["n"]),
        "board_n": n_board,
    }


def se_england_shire_land_uniformity_integrity(board_dir: str = "") -> Dict[str, Any]:
    return build_se_england_shire_land_uniformity_product(board_dir)
