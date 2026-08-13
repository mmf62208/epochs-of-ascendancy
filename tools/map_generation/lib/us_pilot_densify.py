"""US densify pilot — parallel board with locked 8-band Tier-3 regions.

IDs 800000+ (no world_full renumber). Source: world_full theater=north_america.
Geometry: median-split densify + edge densify (interim, not TIGER GIS).
"""
from __future__ import annotations

import json
from collections import defaultdict
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
WORLD_DIR = ROOT / "data" / "provinces_world_full"
PILOT_DIR_NAME = "provinces_pilot_us"
PILOT_ID_BASE = 800000
WATER_DOMAINS = frozenset({"sea", "strait", "lake"})

# Locked 8-band US strategic regions (product decision).
US_EIGHT_BANDS = (
    "Northeast",
    "Mid-Atlantic",
    "Southeast",
    "Midwest",
    "Great Plains",
    "Southwest",
    "Mountain West",
    "Pacific",
)

# State name catalogs per band (real place / US-state style).
US_BAND_STATES: Dict[str, List[str]] = {
    "Northeast": [
        "Maine", "New Hampshire", "Vermont", "Massachusetts", "Rhode Island",
        "Connecticut", "Upstate New York", "Hudson Valley", "Cape Cod", "Berkshires",
        "Adirondacks", "Finger Lakes", "Western Massachusetts", "Southern Maine",
    ],
    "Mid-Atlantic": [
        "Pennsylvania", "New Jersey", "Delaware", "Maryland", "District of Columbia",
        "Virginia", "West Virginia", "Philadelphia Basin", "Chesapeake", "Shenandoah",
        "Allegheny", "Tidewater", "Northern Virginia", "Piedmont Virginia",
    ],
    "Southeast": [
        "North Carolina", "South Carolina", "Georgia", "Florida", "Alabama",
        "Mississippi", "Tennessee", "Kentucky", "Florida Panhandle", "Atlanta Plateau",
        "Appalachian South", "Gulf Coast East", "Bluegrass", "Smoky Mountains",
    ],
    "Midwest": [
        "Ohio", "Indiana", "Illinois", "Michigan", "Wisconsin", "Minnesota",
        "Iowa", "Missouri", "Chicago Belt", "Detroit Corridor", "Twin Cities",
        "Ozarks North", "Great Lakes West", "Corn Belt East",
    ],
    "Great Plains": [
        "North Dakota", "South Dakota", "Nebraska", "Kansas", "Oklahoma",
        "High Plains North", "High Plains South", "Red River Valley", "Flint Hills",
        "Oklahoma Panhandle", "Badlands", "Platte Valley",
    ],
    "Southwest": [
        "Texas", "New Mexico", "Arizona", "West Texas", "Rio Grande",
        "Sonoran Rim", "Llano Estacado", "Hill Country", "Gulf Coast Texas",
        "Chihuahuan Desert", "Four Corners South", "Trans-Pecos",
    ],
    "Mountain West": [
        "Montana", "Idaho", "Wyoming", "Colorado", "Utah", "Nevada",
        "Rocky Mountains", "Front Range", "Great Basin", "Yellowstone Country",
        "Wasatch", "Snake River Plain", "Colorado Plateau North",
    ],
    "Pacific": [
        "California", "Oregon", "Washington", "Alaska", "Hawaii",
        "Cascadia", "Central Valley", "Bay Area", "Southern California",
        "Puget Sound", "Willamette", "Sierra Nevada", "Olympic Peninsula",
    ],
}


def is_water(p: Dict[str, Any]) -> bool:
    return str(p.get("domain") or "land") in WATER_DOMAINS or bool(p.get("is_sea"))


def classify_us_band(cx: float, cy: float) -> str:
    """Map world-canvas centroid to locked 8-band region.

    NA land spans roughly x∈[650,2700], y∈[620,1870] on the equirectangular world canvas.
    Low x = west, high x = east; low y = north, high y = south.
    """
    nx = max(0.0, min(1.0, (cx - 650.0) / 2050.0))
    ny = max(0.0, min(1.0, (cy - 620.0) / 1250.0))
    # West third / middle / east third × north / south
    if nx < 0.28:
        # Far west
        if ny < 0.45:
            return "Pacific"
        if ny < 0.72:
            return "Mountain West"
        return "Southwest"
    if nx < 0.55:
        # Interior west-central
        if ny < 0.40:
            return "Pacific" if nx < 0.38 else "Mountain West"
        if ny < 0.65:
            return "Great Plains" if nx > 0.40 else "Mountain West"
        return "Southwest" if nx < 0.48 else "Great Plains"
    if nx < 0.72:
        # Central
        if ny < 0.38:
            return "Midwest"
        if ny < 0.62:
            return "Midwest" if ny < 0.52 else "Great Plains"
        return "Southeast" if nx > 0.62 else "Southwest"
    # East
    if ny < 0.32:
        return "Northeast"
    if ny < 0.48:
        return "Mid-Atlantic" if nx > 0.82 else "Midwest"
    if ny < 0.70:
        return "Mid-Atlantic" if nx > 0.78 else "Southeast"
    return "Southeast"


def _assign_state_name(band: str, index: int) -> str:
    from state_name_gazetteer import pick_state_names  # type: ignore

    catalog = US_BAND_STATES.get(band) or []
    if catalog:
        from state_name_gazetteer import _expand_catalog  # type: ignore

        names = _expand_catalog(catalog, index + 1)
        return names[index]
    names = pick_state_names("north_america", index + 1)
    return names[index]


def load_world_north_america(world_dir: Path = WORLD_DIR):
    base = json.loads((world_dir / "provinces_base.json").read_text(encoding="utf-8"))
    geom = json.loads((world_dir / "provinces_geometry.json").read_text(encoding="utf-8"))
    own = {}
    op = world_dir / "province_ownership_1936.json"
    if op.is_file():
        own = json.loads(op.read_text(encoding="utf-8")).get("owners") or {}
    gmap = {int(g["id"]): g.get("points") or [] for g in geom["provinces"]}
    selected = [p for p in base["provinces"] if str(p.get("theater") or "") == "north_america"]
    return selected, gmap, {str(k): str(v) for k, v in own.items()}


def densify_us_provinces(
    parents: List[Dict[str, Any]],
    gmap: Dict[int, List],
    owners: Dict[str, str],
    splits_per_parent: int = 4,
    max_edge: float = 14.0,
) -> Dict[str, Any]:
    from europe_pilot_densify import densify_ring, split_polygon_median, _centroid, _poly_area  # type: ignore

    base_out: List[Dict[str, Any]] = []
    geom_out: List[Dict[str, Any]] = []
    own_out: Dict[str, str] = {}
    parent_map: Dict[str, int] = {}
    next_id = PILOT_ID_BASE
    land_before = sum(1 for p in parents if not is_water(p))

    for p in parents:
        pid = int(p["id"])
        pts = gmap.get(pid) or []
        if len(pts) < 3:
            continue
        owner = owners.get(str(pid), "") or "USA"
        if is_water(p):
            ring = densify_ring(pts, max_edge=max_edge * 1.5, min_verts=16)
            entry = deepcopy(p)
            entry["id"] = next_id
            entry["parent_world_id"] = pid
            entry["name"] = p.get("name") or ("Sea %d" % next_id)
            entry["theater"] = "north_america"
            base_out.append(entry)
            geom_out.append({
                "id": next_id,
                "points": ring,
                "meta": {"pilot": True, "us_pilot": True, "parent_world_id": pid, "densified": True},
            })
            own_out[str(next_id)] = owner
            parent_map[str(next_id)] = pid
            next_id += 1
            continue

        pieces = [list(pts)]
        for s in range(max(1, splits_per_parent - 1)):
            new_pieces: List[List] = []
            for piece in pieces:
                a, b = split_polygon_median(piece, "auto" if s % 2 == 0 else "y")
                if len(a) >= 3:
                    new_pieces.append(a)
                if len(b) >= 3:
                    new_pieces.append(b)
            pieces = new_pieces if new_pieces else pieces

        for i, piece in enumerate(pieces):
            ring = densify_ring(piece, max_edge=min(max_edge, 12.0), min_verts=28)
            if len(ring) < 3:
                continue
            cx, cy = _centroid(ring)
            band = classify_us_band(cx, cy)
            entry = deepcopy(p)
            entry["id"] = next_id
            entry["parent_world_id"] = pid
            entry["name"] = "%s · %s-%d" % (band, owner or "USA", i + 1)
            entry["theater"] = "north_america"
            entry["strategic_region_hint"] = band
            entry["population_base"] = max(40000, int(p.get("population_base") or 100000) // max(1, len(pieces)))
            base_out.append(entry)
            geom_out.append({
                "id": next_id,
                "points": ring,
                "name": entry["name"],
                "meta": {
                    "pilot": True,
                    "us_pilot": True,
                    "parent_world_id": pid,
                    "densified": True,
                    "split": True,
                    "split_index": i,
                    "strategic_region_hint": band,
                    "us_band": band,
                    "vertex_n": len(ring),
                    "area": _poly_area(ring),
                },
            })
            own_out[str(next_id)] = owner
            parent_map[str(next_id)] = pid
            next_id += 1

    land_after = sum(1 for p in base_out if not is_water(p))
    states, regions, p2s, p2r, super_regions = _build_us_hierarchy(base_out, geom_out, own_out)
    densify_ratio = land_after / max(1, land_before)
    return {
        "provinces_base": {
            "provinces": base_out,
            "meta": {"pilot": True, "us_pilot": True, "source": "us_pilot_densify", "eight_band": True},
        },
        "provinces_geometry": {
            "meta": {
                "version": 1,
                "phase": "pilot_us_densify",
                "source": "us_pilot_densify.py",
                "geometry_space": "world",
                "parent_board": "provinces_world_full",
                "id_base": PILOT_ID_BASE,
                "land_before": land_before,
                "land_after": land_after,
                "densify_ratio": densify_ratio,
                "pilot": True,
                "us_pilot": True,
                "geometry_quality": "procedural_interim",
                "eight_band": list(US_EIGHT_BANDS),
            },
            "provinces": geom_out,
        },
        "ownership": {
            "meta": {
                "era_year": 1936,
                "seed_only": True,
                "pilot": True,
                "us_pilot": True,
                "player_agency": {"seed_on_scenario_load": True, "reapply_on_year_tick": False},
            },
            "owners": own_out,
            "capitals": {},
        },
        "parent_map": parent_map,
        "states": states,
        "regions": regions,
        "super_regions": super_regions,
        "province_to_state": p2s,
        "province_to_region": p2r,
        "stats": {
            "province_n": len(base_out),
            "land_before": land_before,
            "land_after": land_after,
            "densify_ratio": densify_ratio,
            "state_n": len(states),
            "region_n": len(regions),
            "bands_present": sorted({str(p.get("strategic_region_hint") or "") for p in base_out if not is_water(p)}),
            "mean_verts": sum(len(g["points"]) for g in geom_out) / max(1, len(geom_out)),
        },
        "empty": False,
        "ok": land_after > land_before * 1.5 and densify_ratio >= 1.5,
    }


def _build_us_hierarchy(base_out, geom_out, own_out):
    from europe_pilot_densify import _centroid  # type: ignore

    gcent = {int(g["id"]): _centroid(g["points"]) for g in geom_out}
    by_band: Dict[str, List[int]] = defaultdict(list)
    for p in base_out:
        if is_water(p):
            continue
        pid = int(p["id"])
        cx, cy = gcent.get(pid, (0.0, 0.0))
        band = str(p.get("strategic_region_hint") or classify_us_band(cx, cy))
        if band not in US_EIGHT_BANDS:
            band = classify_us_band(cx, cy)
        by_band[band].append(pid)

    # Ensure all 8 bands exist even if empty → place at least empty skip; require all present for integrity
    regions = []
    p2r: Dict[str, int] = {}
    rid = 1
    band_to_rid: Dict[str, int] = {}
    for band in US_EIGHT_BANDS:
        pids = sorted(by_band.get(band) or [])
        band_to_rid[band] = rid
        regions.append({
            "id": rid,
            "name": band,
            "province_ids": pids,
            "province_n": len(pids),
            "theater": "north_america",
            "super_region_id": 7,
            "us_band": True,
        })
        for pid in pids:
            p2r[str(pid)] = rid
        rid += 1

    states = []
    p2s: Dict[str, int] = {}
    sid = 1
    by_own_band: Dict[Tuple[str, str], List[int]] = defaultdict(list)
    for p in base_out:
        if is_water(p):
            continue
        pid = int(p["id"])
        tag = own_out.get(str(pid), "USA") or "USA"
        band = str(p.get("strategic_region_hint") or "Midwest")
        by_own_band[(tag, band)].append(pid)

    band_idx: Dict[str, int] = defaultdict(int)
    for (tag, band), pids in sorted(by_own_band.items()):
        pids = sorted(pids)
        chunk = 10
        for i in range(0, len(pids), chunk):
            part = pids[i : i + chunk]
            ni = band_idx[band]
            band_idx[band] = ni + 1
            name = _assign_state_name(band, ni)
            rid = band_to_rid.get(band, 1)
            states.append({
                "id": sid,
                "name": name,
                "owner_hint": tag,
                "region_id": rid,
                "region_hint": band,
                "theater": "north_america",
                "province_ids": part,
                "province_n": len(part),
                "capital_province_id": part[0],
                "tags": ["us_pilot", "us_band_state"],
            })
            for pid in part:
                p2s[str(pid)] = sid
            sid += 1

    super_regions = [{
        "id": 7,
        "name": "North America",
        "region_ids": [r["id"] for r in regions],
        "theaters": ["north_america"],
        "theater": "north_america",
    }]
    return states, regions, p2s, p2r, super_regions


def write_us_pilot_dir(out: Dict[str, Any], pilot_dir: Path) -> Dict[str, Any]:
    pilot_dir.mkdir(parents=True, exist_ok=True)
    (pilot_dir / "provinces_base.json").write_text(
        json.dumps(out["provinces_base"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (pilot_dir / "provinces_geometry.json").write_text(
        json.dumps(out["provinces_geometry"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    own1936 = out["ownership"]
    (pilot_dir / "province_ownership_1936.json").write_text(
        json.dumps(own1936, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    parent_map = out["parent_map"]
    for era in (1910, 1918, 1945, 2026):
        wpath = WORLD_DIR / ("province_ownership_%d.json" % era)
        if not wpath.is_file():
            continue
        wown = json.loads(wpath.read_text(encoding="utf-8")).get("owners") or {}
        mapped = {}
        for pid_s, world_id in parent_map.items():
            tag = wown.get(str(world_id), "")
            if tag:
                mapped[pid_s] = tag
            else:
                mapped[pid_s] = own1936["owners"].get(pid_s, "USA")
        payload = {
            "meta": {
                "era_year": era,
                "seed_only": True,
                "pilot": True,
                "us_pilot": True,
                "player_agency": {"reapply_on_year_tick": False, "seed_on_scenario_load": True},
            },
            "owners": mapped,
            "capitals": {},
        }
        (pilot_dir / ("province_ownership_%d.json" % era)).write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )

    (pilot_dir / "province_states.json").write_text(
        json.dumps({
            "version": 3,
            "source": "us_pilot_densify",
            "naming": "us_band_states",
            "eight_band": list(US_EIGHT_BANDS),
            "states": out["states"],
        }, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (pilot_dir / "strategic_regions.json").write_text(
        json.dumps({
            "version": 4,
            "source": "us_pilot_densify",
            "eight_band": True,
            "regions": out["regions"],
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    (pilot_dir / "super_regions.json").write_text(
        json.dumps({"version": 1, "super_regions": out["super_regions"]}, indent=2) + "\n",
        encoding="utf-8",
    )
    p2super = {str(pid): 7 for pid in out["province_to_state"].keys()}
    (pilot_dir / "hierarchy_scaffold.json").write_text(
        json.dumps({
            "version": 2,
            "pilot": True,
            "us_pilot": True,
            "eight_band": True,
            "province_to_state": out["province_to_state"],
            "province_to_region": out["province_to_region"],
            "province_to_super_region": p2super,
            "state_n": len(out["states"]),
            "region_n": len(out["regions"]),
            "super_region_n": 1,
            "four_tier": True,
        }, indent=2) + "\n",
        encoding="utf-8",
    )

    econ = {}
    terrain = {}
    resources = {}
    for p in out["provinces_base"]["provinces"]:
        pid = str(p["id"])
        wet = is_water(p)
        econ[pid] = {
            "development_level": 4 if not wet else 0,
            "infrastructure": 3 if not wet else 0,
            "population": int(p.get("population_base") or 100000),
            "factories": 1 if not wet else 0,
        }
        terrain[pid] = {"terrain": "plains" if not wet else "sea", "domain": p.get("domain", "land")}
        resources[pid] = {"resources": {}}
    (pilot_dir / "province_economy_layer.json").write_text(json.dumps(econ, indent=2) + "\n", encoding="utf-8")
    (pilot_dir / "province_terrain_layer.json").write_text(json.dumps(terrain, indent=2) + "\n", encoding="utf-8")
    (pilot_dir / "province_resources_layer.json").write_text(json.dumps(resources, indent=2) + "\n", encoding="utf-8")
    (pilot_dir / "province_city_layer.json").write_text(json.dumps({}, indent=2) + "\n", encoding="utf-8")
    (pilot_dir / "project_sites.json").write_text(json.dumps({"sites": []}, indent=2) + "\n", encoding="utf-8")

    eras = []
    for y in (1910, 1918, 1936, 1945, 2026):
        fp = pilot_dir / ("province_ownership_%d.json" % y)
        if fp.is_file():
            o = json.loads(fp.read_text())
            eras.append({"year": y, "path": fp.name, "owner_n": len(o.get("owners") or {}), "ok": True})
    (pilot_dir / "ownership_era_index.json").write_text(
        json.dumps({
            "version": 1,
            "policy": {"seed_on_scenario_load": True, "reapply_on_year_tick": False, "player_conquest_preserved": True},
            "eras": eras,
            "pilot": True,
            "us_pilot": True,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    (pilot_dir / "manifest_pilot_us.json").write_text(
        json.dumps({
            "name": "provinces_pilot_us",
            "parent": "provinces_world_full",
            "stats": out["stats"],
            "id_base": PILOT_ID_BASE,
            "eight_band": list(US_EIGHT_BANDS),
            "geometry_quality": "procedural_interim",
            "pilot_banner": True,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    return {"path": str(pilot_dir), "stats": out["stats"], "ok": out.get("ok")}


def build_and_write_us_pilot(
    world_dir: Path = WORLD_DIR,
    pilot_rel: str = PILOT_DIR_NAME,
    splits: int = 4,
) -> Dict[str, Any]:
    parents, gmap, owners = load_world_north_america(world_dir)
    out = densify_us_provinces(parents, gmap, owners, splits_per_parent=splits)
    pilot_dir = ROOT / "data" / pilot_rel
    written = write_us_pilot_dir(out, pilot_dir)
    # Shared-edge adjacency
    from shared_edge_adjacency_product import write_shared_edge_adjacency  # type: ignore

    adj = write_shared_edge_adjacency(pilot_dir, quant=0.4, knn_k=4)
    # Full membership eras 1910/1918/1936/2026
    from membership_era_product import write_membership_era_files, PRIMARY_MEMBERSHIP_ERAS  # type: ignore

    mem = write_membership_era_files(pilot_dir, PRIMARY_MEMBERSHIP_ERAS, regroup_by_owner=True)
    written["adjacency"] = adj
    written["membership"] = mem
    written["ok"] = bool(out.get("ok")) and bool(adj.get("ok")) and bool(mem.get("ok"))
    written["stats"] = out["stats"]
    return written


def us_pilot_integrity(pilot_dir: Path | None = None) -> Dict[str, Any]:
    from state_name_gazetteer import assert_names_shippable  # type: ignore
    from shared_edge_adjacency_product import adjacency_integrity  # type: ignore

    pilot_dir = pilot_dir or (ROOT / "data" / PILOT_DIR_NAME)
    geom_p = pilot_dir / "provinces_geometry.json"
    if not geom_p.is_file():
        return {"ok": False, "summary": "US pilot missing", "empty": True}
    geom = json.loads(geom_p.read_text(encoding="utf-8"))
    meta = geom.get("meta") or {}
    land_before = int(meta.get("land_before") or 0)
    land_after = int(meta.get("land_after") or 0)
    n = len(geom.get("provinces") or [])
    states = json.loads((pilot_dir / "province_states.json").read_text()).get("states") or []
    regions = json.loads((pilot_dir / "strategic_regions.json").read_text()).get("regions") or []
    rnames = [str(r.get("name") or "") for r in regions]
    names = [str(s.get("name") or "") for s in states]
    name_gate = assert_names_shippable(names)
    bands_ok = all(b in rnames for b in US_EIGHT_BANDS)
    # IDs
    ids = [int(g["id"]) for g in geom.get("provinces") or []]
    id_ok = all(i >= PILOT_ID_BASE for i in ids) and len(ids) == len(set(ids))
    adj = adjacency_integrity(pilot_dir)
    mem_ok = all((pilot_dir / ("hierarchy_membership_%d.json" % y)).is_file() for y in (1910, 1918, 1936, 2026))
    if mem_ok:
        for y in (1910, 1918, 1936, 2026):
            snap = json.loads((pilot_dir / ("hierarchy_membership_%d.json" % y)).read_text())
            if snap.get("mode") != "full":
                mem_ok = False
                break
    ok = (
        n >= 400
        and land_after >= int(land_before * 1.5)
        and len(states) >= 20
        and bands_ok
        and bool(name_gate.get("ok"))
        and id_ok
        and bool(adj.get("ok"))
        and mem_ok
        and (pilot_dir / "province_ownership_1936.json").is_file()
        and (pilot_dir / "super_regions.json").is_file()
    )
    return {
        "ok": ok,
        "province_n": n,
        "land_before": land_before,
        "land_after": land_after,
        "state_n": len(states),
        "region_n": len(regions),
        "bands": rnames,
        "name_gate": name_gate,
        "adjacency": adj.get("summary"),
        "membership_full": mem_ok,
        "summary": "US pilot integrity %s · n=%d land %d→%d bands=%d states=%d"
        % ("PASS" if ok else "FAIL", n, land_before, land_after, len(rnames), len(states)),
        "empty": False,
    }
