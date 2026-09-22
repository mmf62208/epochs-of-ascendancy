"""FEED-5 Hong Kong island-scale land key — Mike province-sizing bar #2.

The accurate board already has ENG land 902486 "Yuen Long" (HKG / Hong Kong
S.A.R.) covering the NW New Territories at island-scale area ~10. That cell
is not the harbor rock: Hong Kong Island, Kowloon, and Victoria Harbor are
void. This product is a **one-theater proof** (not other keys, not seas
coarsening, not Gibraltar/Alboran/Maginot/Great Lakes remesh):

* Append RoW/Asia ID **905844** "Hong Kong" as a dedicated island-scale land
  cell covering the island + Kowloon, readable like Malta / Gibraltar.
* Keep Yuen Long 902486 / CHN South 902598+902633 IDs and names (no clip
  needed — they do not overlap the rock ring).
* Wire adjacency: Hong Kong ↔ Yuen Long (NT land) and Hong Kong ↔ 950011
  (South China Sea Zone). Do not write world_full.

Write: tools/map_generation/scripts/apply_hong_kong_island_land.py
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

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

HONG_KONG_ID = 905844
YUEN_LONG_ID = 902486
CHN_SOUTH_A = 902598
CHN_SOUTH_B = 902633
SEA_ID = 950011
GIBRALTAR_ID = 711520
CADIZ_ID = 710671
CEUTA_ID = 710679
STRAIT_ID = 950019
ALBORAN_ID = 950128
GER_MAGINOT_ID = 710173
FRA_MAGINOT_ID = 710739
GREAT_LAKE_IDS: Tuple[int, ...] = (950333, 950334, 950335, 950336, 950337)

# Island + Kowloon WGS84. Island-key ring is Malta/Gibraltar-like (readable).
ROCK_LONLAT = (114.169, 22.278)
KOWLOON_LONLAT = (114.174, 22.319)
HARBOR_LONLAT = (114.173, 22.293)
YUEN_LONG_SAMPLE = (114.03, 22.44)
# Clockwise from NW Kowloon. Covers HK Island + Kowloon; stays south of Yuen Long.
HONG_KONG_LONLAT_RING: Tuple[Tuple[float, float], ...] = (
    (114.110, 22.358),
    (114.248, 22.354),
    (114.265, 22.284),
    (114.212, 22.230),
    (114.125, 22.234),
    (114.098, 22.296),
)

ISLAND_AREA_MIN = 4.0
ISLAND_AREA_MAX = 25.0
YUEN_LONG_AREA_FLOOR = 8.0
ROCK_LON_WINDOW = (114.05, 114.30)
ROCK_LAT_WINDOW = (22.22, 22.36)

FEED_META = "v1_hong_kong_island_land"
PRESERVED_IDS: Tuple[int, ...] = (
    YUEN_LONG_ID,
    CHN_SOUTH_A,
    CHN_SOUTH_B,
    SEA_ID,
    GIBRALTAR_ID,
    CADIZ_ID,
    CEUTA_ID,
    STRAIT_ID,
    ALBORAN_ID,
    GER_MAGINOT_ID,
    FRA_MAGINOT_ID,
)

Ring = List[List[float]]


def hong_kong_design_ring() -> Ring:
    return [list(lonlat_to_canvas(lon, lat)) for lon, lat in HONG_KONG_LONLAT_RING]


def _geo_object(old: Mapping[str, Any], pid: int, name: str, ring: Ring, extra_meta: Mapping[str, Any]) -> Dict[str, Any]:
    cx, cy = polygon_centroid(ring)
    obj = dict(old)
    obj["id"] = int(pid)
    obj["name"] = name
    obj["points"] = [[float(p[0]), float(p[1])] for p in ring]
    obj["label_anchor"] = [cx, cy]
    meta = dict(obj.get("meta") or {})
    meta.pop("gibraltar_land_feed", None)
    meta["hong_kong_land_feed"] = FEED_META
    meta["vertex_n"] = len(ring)
    meta["area"] = polygon_area(ring)
    meta.update(dict(extra_meta))
    obj["meta"] = meta
    return obj


def plan_hong_kong_island_land(board_dir: str = "") -> Dict[str, Any]:
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    already = int(HONG_KONG_ID) in base and int(HONG_KONG_ID) in geo
    rock_ring = hong_kong_design_ring()
    yl_stored = (geo.get(YUEN_LONG_ID) or {}).get("points") or []
    if already:
        stored_rock = (geo.get(HONG_KONG_ID) or {}).get("points") or []
        if stored_rock:
            rock_ring = [[float(p[0]), float(p[1])] for p in stored_rock]
    return {
        "already_applied": already,
        "hong_kong_id": HONG_KONG_ID,
        "yuen_long_id": YUEN_LONG_ID,
        "sea_id": SEA_ID,
        "hong_kong_ring": rock_ring,
        "hong_kong_area": polygon_area(rock_ring),
        "yuen_long_area": polygon_area(yl_stored),
        "new_ids": [HONG_KONG_ID],
        "preserved_ids": list(PRESERVED_IDS),
        "yuen_long_name": str((base.get(YUEN_LONG_ID) or {}).get("name") or "Yuen Long"),
        "sea_name": str((base.get(SEA_ID) or {}).get("name") or "South China Sea Zone"),
    }


def apply_hong_kong_island_land(board_dir: str = "") -> Dict[str, Any]:
    """Write Hong Kong Island land. Existing IDs stay. No mainland remesh."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    plan = plan_hong_kong_island_land(str(d))
    already = bool(plan.get("already_applied"))
    board = load_board(d)
    base: Dict[int, dict] = board["base"]
    geo: Dict[int, dict] = board["geo"]
    adj: Dict[int, List[int]] = board["adj"]

    if YUEN_LONG_ID not in geo:
        raise KeyError("missing Yuen Long 902486 donor for Hong Kong clone")
    yl_old = dict(geo[YUEN_LONG_ID])
    rock_ring: Ring = plan["hong_kong_ring"]
    child_obj = _geo_object(
        yl_old,
        HONG_KONG_ID,
        "Hong Kong",
        rock_ring,
        {
            "split_parent": YUEN_LONG_ID,
            "role": "island_key",
            "adm0_a3": "HKG",
            "admin": "Hong Kong S.A.R.",
        },
    )
    geo[HONG_KONG_ID] = child_obj

    yl_nbrs = set(adj.get(YUEN_LONG_ID) or [])
    yl_nbrs.add(HONG_KONG_ID)
    adj[YUEN_LONG_ID] = sorted(yl_nbrs)
    sea_nbrs = set(adj.get(SEA_ID) or [])
    sea_nbrs.add(HONG_KONG_ID)
    adj[SEA_ID] = sorted(sea_nbrs)
    adj[HONG_KONG_ID] = sorted({YUEN_LONG_ID, SEA_ID})

    if already:
        surgical_replace_geometry_provinces(d / "provinces_geometry.json", {HONG_KONG_ID: child_obj})
        surgical_replace_adjacency_keys(
            d / "province_adjacency.json",
            {YUEN_LONG_ID: adj[YUEN_LONG_ID], SEA_ID: adj[SEA_ID], HONG_KONG_ID: adj[HONG_KONG_ID]},
        )
    else:
        surgical_append_geometry_provinces(d / "provinces_geometry.json", [child_obj])
        surgical_replace_adjacency_keys(
            d / "province_adjacency.json",
            {YUEN_LONG_ID: adj[YUEN_LONG_ID], SEA_ID: adj[SEA_ID]},
        )
        surgical_insert_adjacency_keys(d / "province_adjacency.json", {HONG_KONG_ID: adj[HONG_KONG_ID]})

    _append_base_hong_kong(d, base)
    _clone_layer_rows(d)
    _insert_hierarchy_and_ownership(d)
    _insert_state_and_region_ids(d)
    if not already:
        _bump_manifest(d)
        _bump_adj_stats(d)

    return {
        "ok": True,
        "already_applied": already,
        "board_dir": str(d),
        "new_ids": [HONG_KONG_ID],
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "world_full_touched": False,
        "hong_kong_area": round(float(plan["hong_kong_area"]), 2),
        "yuen_long_area": round(float(plan["yuen_long_area"]), 2),
    }


def _append_base_hong_kong(d: Path, base: Mapping[int, Mapping[str, Any]]) -> None:
    path = d / "provinces_base.json"
    raw = path.read_text(encoding="utf-8")
    if re.search(r'"id":\s*' + str(HONG_KONG_ID), raw):
        return
    parent = dict(base[YUEN_LONG_ID])
    child = dict(parent)
    child["id"] = HONG_KONG_ID
    child["name"] = "Hong Kong"
    child["terrain"] = "mountains"
    child["domain"] = "land"
    child["core_for_tags"] = ["ENG"]
    child["island_class"] = "island"
    child["population_base"] = 250000
    child["facility_tier"] = 3
    child["special_features"] = ["naval_base", "port"]
    meta = dict(child.get("meta") or {})
    meta["source"] = "ne_10m_admin_1"
    meta["adm0_a3"] = "HKG"
    meta["admin"] = "Hong Kong S.A.R."
    meta["hong_kong_land_feed"] = FEED_META
    child["meta"] = meta
    blob = json.dumps(child, indent=2)
    lines = blob.splitlines()
    indented = "    " + lines[0] + "\n" + "\n".join("    " + ln if ln else ln for ln in lines[1:])
    close = raw.rfind("]")
    if close < 0:
        raise ValueError("provinces_base.json missing array close")
    path.write_text(raw[:close].rstrip() + ",\n" + indented + "\n  ]\n}\n", encoding="utf-8")


def _clone_layer_rows(d: Path) -> None:
    layer_files = (
        "province_terrain_layer.json",
        "province_resources_layer.json",
        "province_economy_layer.json",
        "province_city_layer.json",
    )
    overlays: Dict[str, Dict[str, Any]] = {
        "province_terrain_layer.json": {"terrain": "mountains", "domain": "land"},
        "province_resources_layer.json": {},
        "province_economy_layer.json": {
            "population": 250000,
            "factories": 3,
            "infrastructure": 6,
            "development_level": 3,
        },
        "province_city_layer.json": {"city_name": "Hong Kong", "tier": 3},
    }
    after_keys = {
        "province_terrain_layer.json": str(YUEN_LONG_ID),
        "province_resources_layer.json": str(YUEN_LONG_ID),
        "province_economy_layer.json": str(YUEN_LONG_ID),
        "province_city_layer.json": "902487",
    }
    for fn in layer_files:
        path = d / fn
        raw = path.read_text(encoding="utf-8")
        if _has_json_key(raw, str(HONG_KONG_ID)):
            continue
        src = overlays[fn]
        blob = json.dumps(src, indent=2)
        lines = blob.splitlines()
        if len(lines) <= 1:
            obj_text = blob
        else:
            body = "\n".join("    " + ln for ln in lines[1:])
            obj_text = "{\n" + body
        raw = _insert_object_key_after(raw, after_keys[fn], str(HONG_KONG_ID), obj_text)
        path.write_text(raw, encoding="utf-8")


def _insert_hierarchy_and_ownership(d: Path) -> None:
    for path in sorted(d.glob("hierarchy_membership_*.json")):
        raw = path.read_text(encoding="utf-8")
        if _has_json_key(raw, str(HONG_KONG_ID)):
            continue
        raw = _insert_simple_key_after_each(raw, str(YUEN_LONG_ID), str(HONG_KONG_ID), None)
        path.write_text(raw, encoding="utf-8")
    for path in sorted(d.glob("province_ownership_*.json")):
        raw = path.read_text(encoding="utf-8")
        if _has_json_key(raw, str(HONG_KONG_ID)):
            continue
        # British HK 1841–1997; follow Yuen Long / Gibraltar ENG convention.
        raw = _insert_simple_key_after(raw, str(YUEN_LONG_ID), str(HONG_KONG_ID), '"ENG"')
        path.write_text(raw, encoding="utf-8")


def _insert_state_and_region_ids(d: Path) -> None:
    for fn in ("province_states.json", "strategic_regions.json"):
        path = d / fn
        raw = path.read_text(encoding="utf-8")
        if re.search(r"(^|[^\d])" + str(HONG_KONG_ID) + r"([^\d]|$)", raw):
            continue
        raw = _insert_id_after_in_int_array(raw, YUEN_LONG_ID, HONG_KONG_ID)
        path.write_text(raw, encoding="utf-8")


def _bump_manifest(d: Path) -> None:
    path = d / "manifest_world_accurate.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    stats = doc.setdefault("stats", {})
    stats["provinces"] = int(stats.get("provinces") or 0) + 1
    stats["land"] = int(stats.get("land") or 0) + 1
    blocks = doc.setdefault("blocks", {})
    if "row_geoboundaries" in blocks:
        blocks["row_geoboundaries"] = int(blocks["row_geoboundaries"]) + 1
    gq = str(doc.get("geometry_quality") or "")
    if FEED_META not in gq:
        doc["geometry_quality"] = (gq + "+" + FEED_META) if gq else FEED_META
    path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def _bump_adj_stats(d: Path) -> None:
    path = d / "province_adjacency.json"
    raw = path.read_text(encoding="utf-8")

    def _bump(key: str) -> None:
        nonlocal raw
        m = re.search(r'"' + re.escape(key) + r'"\s*:\s*(\d+)', raw)
        if not m:
            return
        raw = raw[: m.start(1)] + str(int(m.group(1)) + 1) + raw[m.end(1) :]

    _bump("province_n")
    _bump("land_n")
    path.write_text(raw, encoding="utf-8")


def _land_named_hong_kong(base: Mapping[int, Mapping[str, Any]]) -> List[int]:
    hits: List[int] = []
    for pid, p in base.items():
        name = str(p.get("name") or "").strip().lower()
        if name == "hong kong" and str(p.get("domain") or "land").lower() == "land":
            hits.append(int(pid))
    return hits


def build_hong_kong_island_land_product(board_dir: str = "") -> Dict[str, Any]:
    """QC shipped accurate board: Hong Kong is a dedicated island-scale land key."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []
    if not (d / "provinces_base.json").is_file():
        return {"ok": False, "summary": "missing world_accurate board", "empty": True}
    board = load_board(d)
    base = board["base"]
    geo = board["geo"]
    adj = board["adj"]

    for pid, want_name in (
        (YUEN_LONG_ID, "Yuen Long"),
        (CHN_SOUTH_A, "CHN South"),
        (CHN_SOUTH_B, "CHN South"),
        (SEA_ID, "South China Sea Zone"),
        (GIBRALTAR_ID, "Gibraltar"),
        (CADIZ_ID, "Cádiz"),
        (CEUTA_ID, "Ceuta"),
        (STRAIT_ID, "Gibraltar Strait Zone"),
        (ALBORAN_ID, "Alboran Sea"),
    ):
        row = base.get(int(pid)) or {}
        if int(pid) not in base or int(pid) not in geo:
            fails.append(f"lost_existing_id {pid}")
        elif str(row.get("name") or "") != want_name:
            fails.append(f"{pid} renamed {row.get('name')!r}")
        else:
            passes.append(f"kept_{pid}_{want_name}")

    if str((base.get(SEA_ID) or {}).get("domain") or "").lower() != "sea":
        fails.append("south_china_sea_domain_changed")
    else:
        passes.append("sea_950011_still_sea")

    if HONG_KONG_ID not in base or HONG_KONG_ID not in geo:
        fails.append("missing_append_id 905844")
    else:
        passes.append("append_id=905844")
        hbase = base[HONG_KONG_ID]
        if str(hbase.get("name") or "") != "Hong Kong":
            fails.append(f"hong_kong_name={hbase.get('name')!r}")
        if str(hbase.get("domain") or "").lower() != "land":
            fails.append(f"hong_kong_not_land domain={hbase.get('domain')}")
        if not (900000 <= int(HONG_KONG_ID) < 950000):
            fails.append(f"hong_kong_id_left_row_asia_block {HONG_KONG_ID}")
        if int(HONG_KONG_ID) != 905844:
            fails.append(f"hong_kong_unexpected_id {HONG_KONG_ID}")
        area = polygon_area((geo.get(HONG_KONG_ID) or {}).get("points") or [])
        if area < ISLAND_AREA_MIN or area > ISLAND_AREA_MAX:
            fails.append(f"hong_kong_not_island_scale area={area:.2f}")
        else:
            passes.append(f"hong_kong_area={area:.2f}")
        yl_area = polygon_area((geo.get(YUEN_LONG_ID) or {}).get("points") or [])
        if yl_area < YUEN_LONG_AREA_FLOOR:
            fails.append(f"yuen_long_shrunk_too_far area={yl_area:.1f}")
        cx, cy = polygon_centroid((geo.get(HONG_KONG_ID) or {}).get("points") or [])
        lon, lat = canvas_to_lonlat(cx, cy)
        if not (ROCK_LON_WINDOW[0] <= lon <= ROCK_LON_WINDOW[1] and ROCK_LAT_WINDOW[0] <= lat <= ROCK_LAT_WINDOW[1]):
            fails.append(f"hong_kong_centroid_off_island lonlat=({lon:.3f},{lat:.3f})")
        else:
            passes.append(f"centroid=({lon:.3f},{lat:.3f})")
        ring = (geo.get(HONG_KONG_ID) or {}).get("points") or []
        rx, ry = lonlat_to_canvas(ROCK_LONLAT[0], ROCK_LONLAT[1])
        kx, ky = lonlat_to_canvas(KOWLOON_LONLAT[0], KOWLOON_LONLAT[1])
        hx, hy = lonlat_to_canvas(HARBOR_LONLAT[0], HARBOR_LONLAT[1])
        if not point_in_ring(rx, ry, ring):
            fails.append("hk_island_wgs84_not_inside")
        else:
            passes.append("hk_island_inside")
        if not point_in_ring(kx, ky, ring):
            fails.append("kowloon_wgs84_not_inside")
        else:
            passes.append("kowloon_inside")
        if not point_in_ring(hx, hy, ring):
            fails.append("harbor_wgs84_not_inside")
        else:
            passes.append("harbor_inside")
        yx, yy = lonlat_to_canvas(YUEN_LONG_SAMPLE[0], YUEN_LONG_SAMPLE[1])
        if point_in_ring(yx, yy, ring):
            fails.append("yuen_long_sample_stolen")
        if point_in_ring(rx, ry, (geo.get(YUEN_LONG_ID) or {}).get("points") or []):
            fails.append("island_still_inside_yuen_long")
        nbrs = set(int(x) for x in (adj.get(HONG_KONG_ID) or []))
        if YUEN_LONG_ID not in nbrs:
            fails.append("hong_kong_not_adjacent_yuen_long")
        else:
            passes.append("adj_yuen_long")
        if SEA_ID not in nbrs:
            fails.append("hong_kong_not_adjacent_south_china_sea")
        else:
            passes.append("adj_south_china_sea")
        if HONG_KONG_ID not in set(int(x) for x in (adj.get(YUEN_LONG_ID) or [])):
            fails.append("yuen_long_missing_hong_kong_neighbor")
        if HONG_KONG_ID not in set(int(x) for x in (adj.get(SEA_ID) or [])):
            fails.append("sea_missing_hong_kong_neighbor")

    named = _land_named_hong_kong(base)
    if named != [HONG_KONG_ID] and HONG_KONG_ID in base:
        if not named:
            fails.append("no_land_named_hong_kong")
        elif named != [HONG_KONG_ID]:
            fails.append(f"unexpected_hong_kong_land_ids {named}")
    elif named == [HONG_KONG_ID]:
        passes.append("one_land_hong_kong")

    gib_area = polygon_area((geo.get(GIBRALTAR_ID) or {}).get("points") or [])
    if abs(gib_area - 13.67) > 0.2:
        fails.append(f"gibraltar_land_remeshed area={gib_area:.2f}")
    else:
        passes.append("gibraltar_land_untouched")
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
    if n_board < 3510 or n_board > 3540:
        fails.append(f"board_scale_left_3520_band n={n_board}")
    else:
        passes.append(f"board_n={n_board}")

    own_path = d / "province_ownership_1936.json"
    if own_path.is_file():
        owners = json.loads(own_path.read_text(encoding="utf-8")).get("owners") or {}
        if str(owners.get(str(HONG_KONG_ID)) or "") != "ENG":
            fails.append(f"hong_kong_owner_1936={owners.get(str(HONG_KONG_ID))!r}")
        else:
            passes.append("owner_1936_ENG")
        if str(owners.get(str(YUEN_LONG_ID)) or "") != "ENG":
            fails.append("yuen_long_owner_changed")
        if str(owners.get(str(CHN_SOUTH_A)) or "") != "CHI":
            fails.append("chn_south_owner_changed")

    world_full = ROOT / "data" / "provinces_world_full"
    if world_full.is_dir():
        wf_ids = {
            int(p["id"])
            for p in json.loads((world_full / "provinces_base.json").read_text(encoding="utf-8")).get("provinces") or []
        }
        if HONG_KONG_ID in wf_ids:
            fails.append("world_full_received_905844")
        else:
            passes.append("world_full_untouched")
        if GIBRALTAR_ID in wf_ids:
            fails.append("world_full_received_711520")
    else:
        passes.append("world_full_dir_absent_ok")

    doc = ROOT / "docs" / "MAP_HONG_KONG_ISLAND_LAND.md"
    if doc.is_file():
        body = doc.read_text(encoding="utf-8")
        if "FEED-5" in body and "Never renumber" in body and "905844" in body and "711520" in body:
            passes.append("design_note")
        else:
            fails.append("design_note_thin")
    else:
        fails.append("design_note_missing")

    ok = not fails
    return {
        "ok": ok,
        "summary": "PASS hong kong island-scale land" if ok else "FAIL " + "; ".join(fails[:6]),
        "passes": passes,
        "fails": fails,
        "new_ids": [HONG_KONG_ID],
        "preserved_ids": list(PRESERVED_IDS),
        "renumbered": False,
        "world_full_dir_exists": world_full.is_dir(),
        "hong_kong_area": round(polygon_area((geo.get(HONG_KONG_ID) or {}).get("points") or []), 2),
        "yuen_long_area": round(polygon_area((geo.get(YUEN_LONG_ID) or {}).get("points") or []), 2),
        "board_n": n_board,
        "sea_block": sea_block,
    }


def hong_kong_island_land_integrity(board_dir: str = "") -> Dict[str, Any]:
    return build_hong_kong_island_land_product(board_dir)
