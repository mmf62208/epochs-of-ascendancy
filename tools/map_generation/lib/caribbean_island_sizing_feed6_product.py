"""FEED-6 Caribbean ordinary-island sizing — Mike province-sizing bar #2.

Survey of the Lesser Antilles / nearby strip on world_accurate found some
dedicated small island lands (Tobago, Dominica, St Croix, Martinique,
Guadeloupe, Aruba, Curaçao) but the short Windward chain between Martinique
and Trinidad is **void**: Grenada, Saint Vincent, Saint Lucia, Barbados.

This product is a **one-theater proof** (not whole-Caribbean remesh, not
Pacific/Japan, not Gibraltar/HK/Alboran/Maginot/Great Lakes):

* Append RoW IDs **905845–905848** as dedicated island-scale land cells.
* Keep existing island and mainland IDs (no reshape of Martinique /
  Guadeloupe / Trinidad / Tobago / Dominica).
* Wire a theater-only land chain + Mid-Atlantic sea on the south end.
* Do not write world_full.

Write: tools/map_generation/scripts/apply_caribbean_island_sizing_feed6.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence, Tuple

from gibraltar_island_land_product import (
    _has_json_key,
    _insert_id_after_in_int_array,
    _insert_object_key_after,
    _insert_simple_key_after,
    _insert_simple_key_after_each,
    canvas_to_lonlat,
    load_board,
    lonlat_to_canvas,
    point_in_ring,
    polygon_area,
    polygon_centroid,
    surgical_append_geometry_provinces,
    surgical_insert_adjacency_keys,
    surgical_replace_adjacency_keys,
    surgical_replace_geometry_provinces,
)
from hong_kong_island_land_product import HONG_KONG_ID, YUEN_LONG_ID

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

BARBADOS_ID = 905845
SAINT_LUCIA_ID = 905846
SAINT_VINCENT_ID = 905847
GRENADA_ID = 905848
NEW_IDS: Tuple[int, ...] = (BARBADOS_ID, SAINT_LUCIA_ID, SAINT_VINCENT_ID, GRENADA_ID)

MARTINIQUE_ID = 710804
GUADELOUPE_ID = 710803
DOMINICA_ID = 902406
TOBAGO_ID = 902405
TRINIDAD_ID = 902398
SAINT_CROIX_ID = 902407
ARUBA_ID = 902302
CURACAO_ID = 902301
SEA_ID = 950134
DONOR_ID = TOBAGO_ID
STATE_SIBLING_ID = TRINIDAD_ID

GIBRALTAR_ID = 711520
CADIZ_ID = 710671
CEUTA_ID = 710679
STRAIT_ID = 950019
ALBORAN_ID = 950128
GER_MAGINOT_ID = 710173
FRA_MAGINOT_ID = 710739
GREAT_LAKE_IDS: Tuple[int, ...] = (950333, 950334, 950335, 950336, 950337)

MAINLAND_COMPARE_IDS: Tuple[int, ...] = (903792, 900332, 800039)  # VEN North, Guyana North, Florida South
EXISTING_STRIP_IDS: Tuple[int, ...] = (
    GUADELOUPE_ID,
    MARTINIQUE_ID,
    DOMINICA_ID,
    TOBAGO_ID,
    TRINIDAD_ID,
    SAINT_CROIX_ID,
    ARUBA_ID,
    CURACAO_ID,
)

# id, name, lon, lat, dlon, dlat — hex rings centered on the town sample.
ISLAND_SPECS: Tuple[Tuple[int, str, float, float, float, float], ...] = (
    (BARBADOS_ID, "Barbados", -59.61, 13.10, 0.100, 0.082),
    (SAINT_LUCIA_ID, "Saint Lucia", -61.00, 14.01, 0.088, 0.100),
    (SAINT_VINCENT_ID, "Saint Vincent", -61.23, 13.16, 0.082, 0.095),
    (GRENADA_ID, "Grenada", -61.75, 12.05, 0.088, 0.082),
)
ISLAND_SAMPLES: Dict[int, Tuple[float, float]] = {
    BARBADOS_ID: (-59.61, 13.10),
    SAINT_LUCIA_ID: (-61.00, 14.01),
    SAINT_VINCENT_ID: (-61.23, 13.16),
    GRENADA_ID: (-61.75, 12.05),
}
ISLAND_NAMES: Dict[int, str] = {pid: name for pid, name, _lon, _lat, _dlon, _dlat in ISLAND_SPECS}

ISLAND_AREA_MIN = 4.0
ISLAND_AREA_MAX = 25.0
MAINLAND_AREA_FLOOR = 2000.0
THEATER_LON_WINDOW = (-63.5, -58.5)
THEATER_LAT_WINDOW = (11.6, 14.4)

FEED_META = "v1_caribbean_island_sizing_feed6"
PRESERVED_IDS: Tuple[int, ...] = (
    MARTINIQUE_ID,
    GUADELOUPE_ID,
    DOMINICA_ID,
    TOBAGO_ID,
    TRINIDAD_ID,
    SAINT_CROIX_ID,
    HONG_KONG_ID,
    YUEN_LONG_ID,
    GIBRALTAR_ID,
    CADIZ_ID,
    CEUTA_ID,
    STRAIT_ID,
    ALBORAN_ID,
    GER_MAGINOT_ID,
    FRA_MAGINOT_ID,
)

Ring = List[List[float]]


def _hex_lonlat(lon: float, lat: float, dlon: float, dlat: float) -> Tuple[Tuple[float, float], ...]:
    return (
        (lon, lat + dlat),
        (lon + 0.85 * dlon, lat + 0.5 * dlat),
        (lon + 0.85 * dlon, lat - 0.5 * dlat),
        (lon, lat - dlat),
        (lon - 0.85 * dlon, lat - 0.5 * dlat),
        (lon - 0.85 * dlon, lat + 0.5 * dlat),
    )


def island_design_ring(pid: int) -> Ring:
    for spec_id, _name, lon, lat, dlon, dlat in ISLAND_SPECS:
        if int(spec_id) == int(pid):
            return [list(lonlat_to_canvas(lo, la)) for lo, la in _hex_lonlat(lon, lat, dlon, dlat)]
    raise KeyError(f"unknown island id {pid}")


def _geo_object(old: Mapping[str, Any], pid: int, name: str, ring: Ring, extra_meta: Mapping[str, Any]) -> Dict[str, Any]:
    cx, cy = polygon_centroid(ring)
    obj = dict(old)
    obj["id"] = int(pid)
    obj["name"] = name
    obj["points"] = [[float(p[0]), float(p[1])] for p in ring]
    obj["label_anchor"] = [cx, cy]
    meta = dict(obj.get("meta") or {})
    meta.pop("gibraltar_land_feed", None)
    meta.pop("hong_kong_land_feed", None)
    meta["caribbean_island_feed"] = FEED_META
    meta["vertex_n"] = len(ring)
    meta["area"] = polygon_area(ring)
    meta.update(dict(extra_meta))
    obj["meta"] = meta
    return obj


def _planned_adj(existing: Mapping[int, Sequence[int]]) -> Dict[int, List[int]]:
    """Theater adjacency: Windward land chain + Mid-Atlantic on the south end."""
    adj: Dict[int, List[int]] = {int(k): [int(x) for x in (v or [])] for k, v in existing.items()}

    def _add(a: int, b: int) -> None:
        sa = set(adj.get(a) or [])
        sa.add(int(b))
        adj[a] = sorted(sa)
        sb = set(adj.get(b) or [])
        sb.add(int(a))
        adj[b] = sorted(sb)

    _add(SAINT_LUCIA_ID, MARTINIQUE_ID)
    _add(SAINT_LUCIA_ID, SAINT_VINCENT_ID)
    _add(SAINT_VINCENT_ID, GRENADA_ID)
    _add(SAINT_VINCENT_ID, BARBADOS_ID)
    _add(GRENADA_ID, TRINIDAD_ID)
    _add(GRENADA_ID, SEA_ID)
    _add(BARBADOS_ID, SEA_ID)
    return adj


def plan_caribbean_island_sizing(board_dir: str = "") -> Dict[str, Any]:
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    already = all(int(pid) in base and int(pid) in geo for pid in NEW_IDS)
    rings: Dict[int, Ring] = {}
    areas: Dict[int, float] = {}
    for pid, name, _lon, _lat, _dlon, _dlat in ISLAND_SPECS:
        stored = (geo.get(int(pid)) or {}).get("points") or []
        ring = [[float(p[0]), float(p[1])] for p in stored] if (already and stored) else island_design_ring(int(pid))
        rings[int(pid)] = ring
        areas[int(pid)] = polygon_area(ring)
        _ = name
    mainland_areas = {
        int(pid): polygon_area((geo.get(int(pid)) or {}).get("points") or []) for pid in MAINLAND_COMPARE_IDS
    }
    existing_areas = {
        int(pid): polygon_area((geo.get(int(pid)) or {}).get("points") or []) for pid in EXISTING_STRIP_IDS
    }
    return {
        "already_applied": already,
        "new_ids": list(NEW_IDS),
        "rings": rings,
        "areas": areas,
        "mainland_areas": mainland_areas,
        "existing_areas": existing_areas,
        "preserved_ids": list(PRESERVED_IDS),
        "sea_id": SEA_ID,
        "sea_name": str((base.get(SEA_ID) or {}).get("name") or "Mid-Atlantic Waters"),
    }


def apply_caribbean_island_sizing(board_dir: str = "") -> Dict[str, Any]:
    """Write Windward dedicated island lands. Existing IDs stay. No Caribbean remesh."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    plan = plan_caribbean_island_sizing(str(d))
    already = bool(plan.get("already_applied"))
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    adj: Dict[int, List[int]] = board["adj"]

    if DONOR_ID not in geo:
        raise KeyError("missing Eastern Tobago 902405 donor for Windward clone")
    donor_old = dict(geo[DONOR_ID])
    child_objs: List[Dict[str, Any]] = []
    for pid, name, _lon, _lat, _dlon, _dlat in ISLAND_SPECS:
        ring: Ring = plan["rings"][int(pid)]
        child = _geo_object(
            donor_old,
            int(pid),
            name,
            ring,
            {
                "split_parent": DONOR_ID,
                "role": "ordinary_island",
                "adm0_a3": "ENG",
                "admin": name,
            },
        )
        geo[int(pid)] = child
        child_objs.append(child)

    adj = _planned_adj(adj)
    touch_existing = (MARTINIQUE_ID, TRINIDAD_ID, SEA_ID)
    if already:
        surgical_replace_geometry_provinces(d / "provinces_geometry.json", {int(o["id"]): o for o in child_objs})
        surgical_replace_adjacency_keys(
            d / "province_adjacency.json",
            {pid: adj[pid] for pid in list(touch_existing) + list(NEW_IDS)},
        )
    else:
        surgical_append_geometry_provinces(d / "provinces_geometry.json", child_objs)
        surgical_replace_adjacency_keys(
            d / "province_adjacency.json",
            {pid: adj[pid] for pid in touch_existing},
        )
        surgical_insert_adjacency_keys(d / "province_adjacency.json", {pid: adj[pid] for pid in NEW_IDS})

    _append_base_islands(d, base)
    _clone_layer_rows(d)
    _insert_hierarchy_and_ownership(d)
    _insert_state_and_region_ids(d)
    if not already:
        _bump_manifest(d, added=len(NEW_IDS))
        _bump_adj_stats(d, added=len(NEW_IDS))

    return {
        "ok": True,
        "already_applied": already,
        "board_dir": str(d),
        "new_ids": list(NEW_IDS),
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "world_full_touched": False,
        "areas": {str(pid): round(float(plan["areas"][pid]), 2) for pid in NEW_IDS},
        "existing_areas": {str(pid): round(float(a), 2) for pid, a in plan["existing_areas"].items()},
        "mainland_areas": {str(pid): round(float(a), 2) for pid, a in plan["mainland_areas"].items()},
    }


def _append_base_islands(d: Path, base: Mapping[int, Mapping[str, Any]]) -> None:
    path = d / "provinces_base.json"
    raw = path.read_text(encoding="utf-8")
    parent = dict(base[DONOR_ID])
    blobs: List[str] = []
    for pid, name, _lon, _lat, _dlon, _dlat in ISLAND_SPECS:
        if re.search(r'"id":\s*' + str(int(pid)), raw):
            continue
        child = dict(parent)
        child["id"] = int(pid)
        child["name"] = name
        child["terrain"] = "plains"
        child["domain"] = "land"
        child["core_for_tags"] = ["ENG"]
        child["island_class"] = "island"
        child["population_base"] = 80000
        child["facility_tier"] = 2
        child["special_features"] = ["port"]
        meta = dict(child.get("meta") or {})
        meta["source"] = "ne_10m_admin_1"
        meta["adm0_a3"] = "ENG"
        meta["admin"] = name
        meta["caribbean_island_feed"] = FEED_META
        meta.pop("row_merge", None)
        meta.pop("merged_playable", None)
        child["meta"] = meta
        blob = json.dumps(child, indent=2)
        lines = blob.splitlines()
        indented = "    " + lines[0] + "\n" + "\n".join("    " + ln if ln else ln for ln in lines[1:])
        blobs.append(indented)
    if not blobs:
        return
    close = raw.rfind("]")
    if close < 0:
        raise ValueError("provinces_base.json missing array close")
    path.write_text(raw[:close].rstrip() + ",\n" + ",\n".join(blobs) + "\n  ]\n}\n", encoding="utf-8")


def _clone_layer_rows(d: Path) -> None:
    layer_files = (
        "province_terrain_layer.json",
        "province_resources_layer.json",
        "province_economy_layer.json",
        "province_city_layer.json",
    )
    after = str(STATE_SIBLING_ID)
    for pid, name, _lon, _lat, _dlon, _dlat in ISLAND_SPECS:
        overlays: Dict[str, Dict[str, Any]] = {
            "province_terrain_layer.json": {"terrain": "plains", "domain": "land"},
            "province_resources_layer.json": {},
            "province_economy_layer.json": {
                "population": 80000,
                "factories": 1,
                "infrastructure": 3,
                "development_level": 2,
            },
            "province_city_layer.json": {"city_name": name, "tier": 2},
        }
        for fn in layer_files:
            path = d / fn
            raw = path.read_text(encoding="utf-8")
            if _has_json_key(raw, str(int(pid))):
                continue
            src = overlays[fn]
            blob = json.dumps(src, indent=2)
            lines = blob.splitlines()
            if len(lines) <= 1:
                obj_text = blob
            else:
                body = "\n".join("    " + ln for ln in lines[1:])
                obj_text = "{\n" + body
            raw = _insert_object_key_after(raw, after, str(int(pid)), obj_text)
            path.write_text(raw, encoding="utf-8")
        after = str(int(pid))


def _insert_hierarchy_and_ownership(d: Path) -> None:
    after = str(STATE_SIBLING_ID)
    for pid in NEW_IDS:
        for path in sorted(d.glob("hierarchy_membership_*.json")):
            raw = path.read_text(encoding="utf-8")
            if _has_json_key(raw, str(int(pid))):
                continue
            raw = _insert_simple_key_after_each(raw, after, str(int(pid)), None)
            path.write_text(raw, encoding="utf-8")
        for path in sorted(d.glob("province_ownership_*.json")):
            raw = path.read_text(encoding="utf-8")
            if _has_json_key(raw, str(int(pid))):
                continue
            raw = _insert_simple_key_after(raw, after, str(int(pid)), '"ENG"')
            path.write_text(raw, encoding="utf-8")
        after = str(int(pid))


def _insert_state_and_region_ids(d: Path) -> None:
    after_id = int(STATE_SIBLING_ID)
    for pid in NEW_IDS:
        for fn in ("province_states.json", "strategic_regions.json"):
            path = d / fn
            raw = path.read_text(encoding="utf-8")
            if re.search(r"(^|[^\d])" + str(int(pid)) + r"([^\d]|$)", raw):
                continue
            raw = _insert_id_after_in_int_array(raw, after_id, int(pid))
            path.write_text(raw, encoding="utf-8")
        after_id = int(pid)


def _bump_manifest(d: Path, added: int) -> None:
    path = d / "manifest_world_accurate.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    stats = doc.setdefault("stats", {})
    stats["provinces"] = int(stats.get("provinces") or 0) + int(added)
    stats["land"] = int(stats.get("land") or 0) + int(added)
    blocks = doc.setdefault("blocks", {})
    if "row_geoboundaries" in blocks:
        blocks["row_geoboundaries"] = int(blocks["row_geoboundaries"]) + int(added)
    gq = str(doc.get("geometry_quality") or "")
    if FEED_META not in gq:
        doc["geometry_quality"] = (gq + "+" + FEED_META) if gq else FEED_META
    path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def _bump_adj_stats(d: Path, added: int) -> None:
    path = d / "province_adjacency.json"
    raw = path.read_text(encoding="utf-8")

    def _bump(key: str) -> None:
        nonlocal raw
        m = re.search(r'"' + re.escape(key) + r'"\s*:\s*(\d+)', raw)
        if not m:
            return
        raw = raw[: m.start(1)] + str(int(m.group(1)) + int(added)) + raw[m.end(1) :]

    _bump("province_n")
    _bump("land_n")
    path.write_text(raw, encoding="utf-8")


def build_caribbean_island_sizing_product(board_dir: str = "") -> Dict[str, Any]:
    """QC shipped accurate board: Windward ordinary islands are small dedicated lands."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []
    if not (d / "provinces_base.json").is_file():
        return {"ok": False, "summary": "missing world_accurate board", "empty": True}
    board = load_board(d)
    base = board["base"]
    geo = board["geo"]
    adj = board["adj"]

    kept_names = {
        MARTINIQUE_ID: "Martinique",
        GUADELOUPE_ID: "Guadeloupe",
        DOMINICA_ID: "Saint Andrew",
        TOBAGO_ID: "Eastern Tobago",
        TRINIDAD_ID: "Trinidad and Tobago South",
        SAINT_CROIX_ID: "Saint Croix",
        HONG_KONG_ID: "Hong Kong",
        YUEN_LONG_ID: "Yuen Long",
        GIBRALTAR_ID: "Gibraltar",
        CADIZ_ID: "Cádiz",
        CEUTA_ID: "Ceuta",
        STRAIT_ID: "Gibraltar Strait Zone",
        ALBORAN_ID: "Alboran Sea",
    }
    for pid, want_name in kept_names.items():
        row = base.get(int(pid)) or {}
        if int(pid) not in base or int(pid) not in geo:
            fails.append(f"lost_existing_id {pid}")
        elif str(row.get("name") or "") != want_name:
            fails.append(f"{pid} renamed {row.get('name')!r}")
        else:
            passes.append(f"kept_{pid}")

    if str((base.get(SEA_ID) or {}).get("domain") or "").lower() != "sea":
        fails.append("mid_atlantic_domain_changed")
    else:
        passes.append("sea_950134_still_sea")

    island_areas: Dict[int, float] = {}
    for pid, name, _lon, _lat, _dlon, _dlat in ISLAND_SPECS:
        if int(pid) not in base or int(pid) not in geo:
            fails.append(f"missing_append_id {pid}")
            continue
        passes.append(f"append_id={pid}")
        row = base[int(pid)]
        if str(row.get("name") or "") != name:
            fails.append(f"{pid}_name={row.get('name')!r}")
        if str(row.get("domain") or "").lower() != "land":
            fails.append(f"{pid}_not_land domain={row.get('domain')}")
        if str(row.get("island_class") or "") != "island":
            fails.append(f"{pid}_island_class={row.get('island_class')!r}")
        if not (900000 <= int(pid) < 950000):
            fails.append(f"{pid}_left_row_block")
        area = polygon_area((geo.get(int(pid)) or {}).get("points") or [])
        island_areas[int(pid)] = area
        if area < ISLAND_AREA_MIN or area > ISLAND_AREA_MAX:
            fails.append(f"{name}_not_island_scale area={area:.2f}")
        else:
            passes.append(f"{name}_area={area:.2f}")
        cx, cy = polygon_centroid((geo.get(int(pid)) or {}).get("points") or [])
        lon, lat = canvas_to_lonlat(cx, cy)
        if not (THEATER_LON_WINDOW[0] <= lon <= THEATER_LON_WINDOW[1] and THEATER_LAT_WINDOW[0] <= lat <= THEATER_LAT_WINDOW[1]):
            fails.append(f"{name}_centroid_off_theater lonlat=({lon:.3f},{lat:.3f})")
        else:
            passes.append(f"{name}_centroid=({lon:.3f},{lat:.3f})")
        ring = (geo.get(int(pid)) or {}).get("points") or []
        sx, sy = lonlat_to_canvas(*ISLAND_SAMPLES[int(pid)])
        if not point_in_ring(sx, sy, ring):
            fails.append(f"{name}_sample_not_inside")
        else:
            passes.append(f"{name}_sample_inside")
        # Must not steal existing dedicated islands.
        for exist_pid in (MARTINIQUE_ID, GUADELOUPE_ID, DOMINICA_ID, TOBAGO_ID, TRINIDAD_ID):
            epts = (geo.get(int(exist_pid)) or {}).get("points") or []
            if point_in_ring(sx, sy, epts):
                fails.append(f"{name}_sample_inside_existing_{exist_pid}")
        if point_in_ring(sx, sy, (geo.get(SEA_ID) or {}).get("points") or []):
            fails.append(f"{name}_sample_still_sea")

    mainland_areas = {
        int(pid): polygon_area((geo.get(int(pid)) or {}).get("points") or []) for pid in MAINLAND_COMPARE_IDS
    }
    for mid, marea in mainland_areas.items():
        if marea < MAINLAND_AREA_FLOOR:
            fails.append(f"mainland_{mid}_shrunk area={marea:.1f}")
        for iid, iarea in island_areas.items():
            if iarea >= marea:
                fails.append(f"island_{iid}_not_smaller_than_mainland_{mid}")
        passes.append(f"mainland_{mid}_area={marea:.1f}")

    nbrs_lucia = set(int(x) for x in (adj.get(SAINT_LUCIA_ID) or []))
    if MARTINIQUE_ID not in nbrs_lucia or SAINT_VINCENT_ID not in nbrs_lucia:
        fails.append("saint_lucia_chain_broken")
    else:
        passes.append("adj_lucia_chain")
    nbrs_gren = set(int(x) for x in (adj.get(GRENADA_ID) or []))
    if TRINIDAD_ID not in nbrs_gren or SEA_ID not in nbrs_gren:
        fails.append("grenada_south_adj_broken")
    else:
        passes.append("adj_grenada_south")
    if SAINT_LUCIA_ID not in set(int(x) for x in (adj.get(MARTINIQUE_ID) or [])):
        fails.append("martinique_missing_saint_lucia")
    if GRENADA_ID not in set(int(x) for x in (adj.get(TRINIDAD_ID) or [])):
        fails.append("trinidad_missing_grenada")

    # Existing dedicated strip islands stay small vs mainland (already-present proof kept).
    for pid in (TOBAGO_ID, DOMINICA_ID, SAINT_CROIX_ID, MARTINIQUE_ID, GUADELOUPE_ID):
        area = polygon_area((geo.get(int(pid)) or {}).get("points") or [])
        if min(mainland_areas.values()) <= area:
            fails.append(f"existing_strip_{pid}_not_smaller_than_mainland area={area:.1f}")
        else:
            passes.append(f"existing_strip_{pid}_still_small={area:.2f}")

    gib_area = polygon_area((geo.get(GIBRALTAR_ID) or {}).get("points") or [])
    if abs(gib_area - 13.67) > 0.2:
        fails.append(f"gibraltar_land_remeshed area={gib_area:.2f}")
    else:
        passes.append("gibraltar_land_untouched")
    hk_area = polygon_area((geo.get(HONG_KONG_ID) or {}).get("points") or [])
    if abs(hk_area - 11.74) > 0.3:
        fails.append(f"hong_kong_land_remeshed area={hk_area:.2f}")
    else:
        passes.append("hong_kong_land_untouched")
    alb_area = polygon_area((geo.get(ALBORAN_ID) or {}).get("points") or [])
    if alb_area < 1500.0:
        fails.append(f"alboran_sea_remeshed area={alb_area:.1f}")
    else:
        passes.append("alboran_untouched")
    mag_adj = set(int(x) for x in (adj.get(GER_MAGINOT_ID) or []))
    if FRA_MAGINOT_ID not in mag_adj:
        fails.append("maginot_combat_edge_lost")
    else:
        passes.append("maginot_edge_kept")
    for pid in GREAT_LAKE_IDS:
        row = base.get(int(pid)) or {}
        if str(row.get("domain") or "").lower() != "lake":
            fails.append(f"great_lake_domain {pid}")
    else:
        passes.append("great_lakes_untouched")

    sea_block = sum(1 for pid in base if int(pid) >= 950000)
    if sea_block != 340:
        fails.append(f"sea_block_changed n={sea_block}")
    else:
        passes.append("seas_340_unchanged")

    n_board = len(base)
    if n_board < 3510 or n_board > 3545:
        fails.append(f"board_scale_left_3520_band n={n_board}")
    else:
        passes.append(f"board_n={n_board}")

    own_path = d / "province_ownership_1936.json"
    if own_path.is_file():
        owners = json.loads(own_path.read_text(encoding="utf-8")).get("owners") or {}
        for pid in NEW_IDS:
            if str(owners.get(str(int(pid))) or "") != "ENG":
                fails.append(f"{pid}_owner_1936={owners.get(str(int(pid)))!r}")
        if str(owners.get(str(TRINIDAD_ID)) or "") != "ENG":
            fails.append("trinidad_owner_changed")
        if str(owners.get(str(MARTINIQUE_ID)) or "") != "FRA":
            fails.append("martinique_owner_changed")
        if str(owners.get(str(HONG_KONG_ID)) or "") != "ENG":
            fails.append("hong_kong_owner_changed")
        else:
            passes.append("owners_1936_kept")

    mem_path = d / "hierarchy_membership_1936.json"
    if mem_path.is_file():
        mem = json.loads(mem_path.read_text(encoding="utf-8"))
        p2r = mem.get("province_to_region") or {}
        p2s = mem.get("province_to_state") or {}
        for pid in NEW_IDS:
            if int(p2r.get(str(int(pid)), 0) or 0) <= 0:
                fails.append(f"{pid}_missing_region")
            if int(p2s.get(str(int(pid)), 0) or 0) <= 0:
                fails.append(f"{pid}_missing_state")
        state_ids = {int(v) for v in p2s.values() if int(v or 0) > 0}
        if len(state_ids) != 429:
            fails.append(f"state_id_count={len(state_ids)}")
        else:
            passes.append("states_429_reused")
        if int(p2s.get(str(BARBADOS_ID), 0) or 0) != 414:
            fails.append("windward_not_in_trinidad_state")
        else:
            passes.append("state_414_trinidad")

    choke_path = d / "naval_chokepoints.json"
    if choke_path.is_file():
        choke = json.loads(choke_path.read_text(encoding="utf-8"))
        ids = [int(x) for x in (choke.get("chokepoint_province_ids") or [])]
        if len(ids) != 34:
            fails.append(f"choke_count={len(ids)}")
        else:
            passes.append("chokes_34")
        if GIBRALTAR_ID in ids or any(pid in ids for pid in NEW_IDS):
            fails.append("choke_ids_rewritten")
        if STRAIT_ID not in ids:
            fails.append("gibraltar_strait_choke_lost")

    world_full = ROOT / "data" / "provinces_world_full"
    if world_full.is_dir():
        wf_ids = {
            int(p["id"])
            for p in json.loads((world_full / "provinces_base.json").read_text(encoding="utf-8")).get("provinces") or []
        }
        for pid in NEW_IDS:
            if int(pid) in wf_ids:
                fails.append(f"world_full_received_{pid}")
        if HONG_KONG_ID in wf_ids or GIBRALTAR_ID in wf_ids:
            fails.append("world_full_received_prior_feed_ids")
        else:
            passes.append("world_full_untouched")
    else:
        passes.append("world_full_dir_absent_ok")

    doc = ROOT / "docs" / "MAP_CARIBBEAN_ISLAND_SIZING_FEED6.md"
    if doc.is_file():
        body = doc.read_text(encoding="utf-8")
        if (
            "FEED-6" in body
            and "Never renumber" in body
            and "905845" in body
            and "ordinary islands" in body
            and "711520" in body
            and "905844" in body
        ):
            passes.append("design_note")
        else:
            fails.append("design_note_thin")
    else:
        fails.append("design_note_missing")

    ok = not fails
    return {
        "ok": ok,
        "summary": "PASS caribbean ordinary-island sizing" if ok else "FAIL " + "; ".join(fails[:6]),
        "passes": passes,
        "fails": fails,
        "new_ids": list(NEW_IDS),
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "world_full_dir_exists": world_full.is_dir(),
        "areas": {str(pid): round(float(a), 2) for pid, a in island_areas.items()},
        "mainland_areas": {str(pid): round(float(a), 2) for pid, a in mainland_areas.items()},
        "board_n": n_board,
        "sea_block": sea_block,
    }


def caribbean_island_sizing_integrity(board_dir: str = "") -> Dict[str, Any]:
    return build_caribbean_island_sizing_product(board_dir)
