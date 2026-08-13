"""Europe densify pilot — pure geometry transforms for world-class map path.

Creates denser landform-coherent provinces from world_full europe_core land
without renumbering shipped world_full IDs (pilot uses 700000+ namespace).
"""
from __future__ import annotations

import json
import math
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
WORLD_DIR = ROOT / "data" / "provinces_world_full"
PILOT_DIR_NAME = "provinces_pilot_europe"
PILOT_ID_BASE = 700000
WATER_DOMAINS = frozenset({"sea", "strait", "lake"})

# Strategic region labels for Europe pilot (designer naming).
EUROPE_STRAT_REGIONS = (
    ("British Isles", ( -10.0, 49.0, 2.0, 61.0)),  # lon/lat approx unused — use canvas bands
    ("Iberia", None),
    ("France", None),
    ("Low Countries", None),
    ("Germany", None),
    ("Italy", None),
    ("Nordic", None),
    ("Balkans", None),
    ("Eastern Frontiers", None),
    ("Central Europe", None),
    ("Western Mediterranean", None),
    ("Baltic Rim", None),
)


def _centroid(pts: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not pts:
        return 0.0, 0.0
    ring = list(pts)
    if len(ring) >= 2 and float(ring[0][0]) == float(ring[-1][0]) and float(ring[0][1]) == float(ring[-1][1]):
        ring = ring[:-1]
    n = len(ring)
    if n < 1:
        return 0.0, 0.0
    return sum(float(p[0]) for p in ring) / n, sum(float(p[1]) for p in ring) / n


def _bbox(pts: Sequence[Sequence[float]]) -> Tuple[float, float, float, float]:
    xs = [float(p[0]) for p in pts]
    ys = [float(p[1]) for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def _poly_area(pts: Sequence[Sequence[float]]) -> float:
    ring = list(pts)
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    n = len(ring)
    if n < 3:
        return 0.0
    a = 0.0
    for i in range(n):
        x0, y0 = float(ring[i][0]), float(ring[i][1])
        x1, y1 = float(ring[(i + 1) % n][0]), float(ring[(i + 1) % n][1])
        a += x0 * y1 - x1 * y0
    return abs(a) * 0.5


def densify_ring(pts: Sequence[Sequence[float]], max_edge: float = 12.0, min_verts: int = 28) -> List[List[float]]:
    """Subdivide edges until min_verts reached (and respect max_edge)."""
    if not pts:
        return []
    ring = [[float(p[0]), float(p[1])] for p in pts]
    if len(ring) >= 2 and ring[0][0] == ring[-1][0] and ring[0][1] == ring[-1][1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return ring
    # Force subdivision: put enough samples on every edge so total >= min_verts
    n = len(ring)
    need = max(min_verts, n)
    # samples per edge (even)
    per_edge = max(1, int(math.ceil(need / float(n))))
    out: List[List[float]] = []
    for i in range(n):
        a = ring[i]
        b = ring[(i + 1) % n]
        out.append([a[0], a[1]])
        # also respect max_edge
        dist = math.hypot(b[0] - a[0], b[1] - a[1])
        steps_edge = max(per_edge, int(math.ceil(dist / max(max_edge, 1.0))))
        for s in range(1, steps_edge):
            t = s / float(steps_edge)
            out.append([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t])
    return out


def split_polygon_median(pts: Sequence[Sequence[float]], axis: str = "auto") -> Tuple[List[List[float]], List[List[float]]]:
    """Split polygon into two by cutting bbox at median axis (deterministic)."""
    ring = [[float(p[0]), float(p[1])] for p in pts]
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return ring, []
    minx, miny, maxx, maxy = _bbox(ring)
    w, h = maxx - minx, maxy - miny
    if axis == "auto":
        axis = "x" if w >= h else "y"
    cx, cy = _centroid(ring)
    left: List[List[float]] = []
    right: List[List[float]] = []
    if axis == "x":
        cut = cx
        for p in ring:
            (left if p[0] <= cut else right).append(p)
        # inject cut edge samples for both halves
        for y in (miny, cy, maxy):
            left.append([cut, y])
            right.append([cut, y])
    else:
        cut = cy
        for p in ring:
            (left if p[1] <= cut else right).append(p)
        for x in (minx, cx, maxx):
            left.append([x, cut])
            right.append([x, cut])
    # order by angle around centroid for valid-ish rings
    def order(poly: List[List[float]]) -> List[List[float]]:
        if len(poly) < 3:
            return poly
        ox, oy = _centroid(poly)
        return sorted(poly, key=lambda p: math.atan2(p[1] - oy, p[0] - ox))

    a, b = order(left), order(right)
    if len(a) < 3:
        a = densify_ring(ring, 16.0, 20)
    if len(b) < 3:
        b = densify_ring(ring, 16.0, 20)
    return a, b


def classify_europe_region(cx: float, cy: float, world_w: float = 8192.0, world_h: float = 4096.0) -> str:
    """Canvas-space regional labels for Europe pilot (equirectangular world canvas).

    World_full europe_core centroids span roughly x∈[3500,5200], y∈[900,2100].
    Quantize into ≥10 named strategic regions for hierarchy density.
    """
    # Normalize to 0..1 within typical Europe box
    nx = max(0.0, min(1.0, (cx - 3500.0) / 1700.0))
    ny = max(0.0, min(1.0, (cy - 900.0) / 1200.0))
    # 4x3 grid of named regions
    col = min(3, int(nx * 4.0))
    row = min(2, int(ny * 3.0))
    grid = [
        ["British Isles", "Low Countries", "Nordic", "Baltic Rim"],
        ["Iberia", "France", "Germany", "Eastern Frontiers"],
        ["Western Mediterranean", "Italy", "Balkans", "Central Europe"],
    ]
    return grid[row][col]


def is_water(p: Dict[str, Any]) -> bool:
    return str(p.get("domain") or "land") in WATER_DOMAINS


def load_world_europe_core(world_dir: Path = WORLD_DIR) -> Tuple[List[Dict[str, Any]], Dict[int, List[List[float]]], Dict[str, str]]:
    base = json.loads((world_dir / "provinces_base.json").read_text(encoding="utf-8"))
    geom = json.loads((world_dir / "provinces_geometry.json").read_text(encoding="utf-8"))
    own = {}
    op = world_dir / "province_ownership_1936.json"
    if op.is_file():
        own = json.loads(op.read_text(encoding="utf-8")).get("owners") or {}
    gmap = {int(g["id"]): g.get("points") or [] for g in geom["provinces"]}
    selected = []
    for p in base["provinces"]:
        th = str(p.get("theater") or "")
        # europe densify pilot: europe_core + nearby dense
        if th not in ("europe_core",) and not (th == "mena_africa" and not is_water(p)):
            # include only europe_core for pure densify
            if th != "europe_core":
                continue
        if th != "europe_core":
            continue
        selected.append(p)
    return selected, gmap, {str(k): str(v) for k, v in own.items()}


def densify_europe_provinces(
    parents: List[Dict[str, Any]],
    gmap: Dict[int, List],
    owners: Dict[str, str],
    splits_per_parent: int = 3,
    max_edge: float = 16.0,
) -> Dict[str, Any]:
    """Return pilot provinces_base, geometry, ownership, hierarchy."""
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
        owner = owners.get(str(pid), "")
        is_w = is_water(p)
        # water: keep 1:1 densified only (no split)
        if is_w:
            ring = densify_ring(pts, max_edge=max_edge * 1.5, min_verts=16)
            entry = deepcopy(p)
            entry["id"] = next_id
            entry["parent_world_id"] = pid
            entry["name"] = p.get("name") or ("Sea %d" % next_id)
            entry["theater"] = "europe_core"
            base_out.append(entry)
            geom_out.append({
                "id": next_id,
                "points": ring,
                "meta": {
                    "pilot": True,
                    "parent_world_id": pid,
                    "densified": True,
                    "split": False,
                },
            })
            if owner:
                own_out[str(next_id)] = owner
            parent_map[str(next_id)] = pid
            next_id += 1
            continue

        # land: recursive median splits
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
            ring = densify_ring(piece, max_edge=min(max_edge, 10.0), min_verts=32)
            if len(ring) < 3:
                continue
            cx, cy = _centroid(ring)
            reg = classify_europe_region(cx, cy)
            entry = deepcopy(p)
            entry["id"] = next_id
            entry["parent_world_id"] = pid
            entry["name"] = "%s · %s-%d" % (reg, owner or "NEU", i + 1)
            entry["theater"] = "europe_core"
            entry["strategic_region_hint"] = reg
            entry["population_base"] = max(50000, int(p.get("population_base") or 100000) // max(1, len(pieces)))
            base_out.append(entry)
            geom_out.append({
                "id": next_id,
                "points": ring,
                "name": entry["name"],
                "meta": {
                    "pilot": True,
                    "parent_world_id": pid,
                    "densified": True,
                    "split": True,
                    "split_index": i,
                    "strategic_region_hint": reg,
                    "vertex_n": len(ring),
                    "area": _poly_area(ring),
                },
            })
            if owner:
                own_out[str(next_id)] = owner
            parent_map[str(next_id)] = pid
            next_id += 1

    land_after = sum(1 for p in base_out if not is_water(p))
    # Hierarchy states/regions
    states, regions, p2s, p2r, super_regions = _build_pilot_hierarchy(base_out, geom_out, own_out)

    densify_ratio = land_after / max(1, land_before)
    return {
        "provinces_base": {"provinces": base_out, "meta": {"pilot": True, "source": "europe_pilot_densify"}},
        "provinces_geometry": {
            "meta": {
                "version": 1,
                "phase": "pilot_europe_densify",
                "source": "europe_pilot_densify.py",
                "geometry_space": "world",
                "parent_board": "provinces_world_full",
                "id_base": PILOT_ID_BASE,
                "land_before": land_before,
                "land_after": land_after,
                "densify_ratio": densify_ratio,
                "pilot": True,
            },
            "provinces": geom_out,
        },
        "ownership": {
            "meta": {
                "era_year": 1936,
                "seed_only": True,
                "pilot": True,
                "source": "inherited from parent world_full 1936 via parent_world_id",
                "player_agency": {
                    "seed_on_scenario_load": True,
                    "reapply_on_year_tick": False,
                },
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
            "mean_verts": sum(len(g["points"]) for g in geom_out) / max(1, len(geom_out)),
        },
        "empty": False,
        "ok": land_after > land_before * 1.5 and densify_ratio >= 1.5,
    }


def _build_pilot_hierarchy(base_out, geom_out, own_out):
    from collections import defaultdict
    gcent = {int(g["id"]): _centroid(g["points"]) for g in geom_out}
    by_reg: Dict[str, List[int]] = defaultdict(list)
    for p in base_out:
        if is_water(p):
            continue
        pid = int(p["id"])
        cx, cy = gcent.get(pid, (0.0, 0.0))
        reg = str(p.get("strategic_region_hint") or classify_europe_region(cx, cy))
        by_reg[reg].append(pid)

    regions = []
    p2r: Dict[str, int] = {}
    rid = 1
    for name, pids in sorted(by_reg.items(), key=lambda kv: -len(kv[1])):
        regions.append({
            "id": rid,
            "name": name,
            "province_ids": sorted(pids),
            "province_n": len(pids),
            "theater": "europe_core",
        })
        for pid in pids:
            p2r[str(pid)] = rid
        rid += 1

    # States: owner + region chunks of ~10 — real place names (not TAG · Area N).
    from state_name_gazetteer import assign_state_name  # type: ignore

    states = []
    p2s: Dict[str, int] = {}
    sid = 1
    by_own_reg: Dict[Tuple[str, str], List[int]] = defaultdict(list)
    for p in base_out:
        if is_water(p):
            continue
        pid = int(p["id"])
        tag = own_out.get(str(pid), "NEU") or "NEU"
        reg = str(p.get("strategic_region_hint") or "Central Europe")
        by_own_reg[(tag, reg)].append(pid)
    # Track per-region name index so names stay unique across owner buckets.
    reg_name_idx: Dict[str, int] = defaultdict(int)
    for (tag, reg), pids in sorted(by_own_reg.items()):
        pids = sorted(pids)
        chunk = 10
        for i in range(0, len(pids), chunk):
            part = pids[i : i + chunk]
            ni = reg_name_idx[reg]
            reg_name_idx[reg] = ni + 1
            name = assign_state_name(reg, ni, owner_hint=tag)
            states.append({
                "id": sid,
                "name": name,
                "owner_hint": tag,
                "region_hint": reg,
                "province_ids": part,
                "province_n": len(part),
            })
            for pid in part:
                p2s[str(pid)] = sid
            sid += 1

    super_regions = [{
        "id": 1,
        "name": "Europe",
        "region_ids": [r["id"] for r in regions],
        "theater": "europe_core",
    }]
    return states, regions, p2s, p2r, super_regions


def write_pilot_dir(out: Dict[str, Any], pilot_dir: Path) -> Dict[str, Any]:
    pilot_dir.mkdir(parents=True, exist_ok=True)
    (pilot_dir / "provinces_base.json").write_text(
        json.dumps(out["provinces_base"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (pilot_dir / "provinces_geometry.json").write_text(
        json.dumps(out["provinces_geometry"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    # Ownership tables for all eras: inherit 1936 parent mapping for non-1936
    own1936 = out["ownership"]
    (pilot_dir / "province_ownership_1936.json").write_text(
        json.dumps(own1936, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    # Remap other eras via parent_map
    parent_map = out["parent_map"]  # pilot_id -> world_id
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
        payload = {
            "meta": {
                "era_year": era,
                "seed_only": True,
                "pilot": True,
                "source": "remapped via parent_world_id from world_full",
                "player_agency": {"reapply_on_year_tick": False, "seed_on_scenario_load": True},
            },
            "owners": mapped,
            "capitals": {},
        }
        (pilot_dir / ("province_ownership_%d.json" % era)).write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    # hierarchy
    (pilot_dir / "province_states.json").write_text(
        json.dumps({"version": 2, "source": "europe_pilot_densify", "states": out["states"]}, indent=2) + "\n",
        encoding="utf-8",
    )
    (pilot_dir / "strategic_regions.json").write_text(
        json.dumps({"version": 4, "source": "europe_pilot_densify", "regions": out["regions"]}, indent=2) + "\n",
        encoding="utf-8",
    )
    (pilot_dir / "super_regions.json").write_text(
        json.dumps({"version": 1, "super_regions": out["super_regions"]}, indent=2) + "\n",
        encoding="utf-8",
    )
    # All pilot land maps to super-region Europe (id=1).
    p2super = {str(pid): 1 for pid in out["province_to_state"].keys()}
    (pilot_dir / "hierarchy_scaffold.json").write_text(
        json.dumps({
            "version": 2,
            "pilot": True,
            "province_to_state": out["province_to_state"],
            "province_to_region": out["province_to_region"],
            "province_to_super_region": p2super,
            "state_n": len(out["states"]),
            "region_n": len(out["regions"]),
            "super_region_n": len(out["super_regions"]),
            "four_tier": True,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    # minimal economy/terrain stubs for loader
    econ = {}
    terrain = {}
    for p in out["provinces_base"]["provinces"]:
        pid = str(p["id"])
        econ[pid] = {
            "development_level": 3 if not is_water(p) else 0,
            "infrastructure": 2 if not is_water(p) else 0,
            "population": int(p.get("population_base") or 100000),
            "factories": 1 if not is_water(p) else 0,
        }
        terrain[pid] = {"terrain": "plains" if not is_water(p) else "sea", "domain": p.get("domain", "land")}
    (pilot_dir / "province_economy_layer.json").write_text(json.dumps(econ, indent=2) + "\n", encoding="utf-8")
    (pilot_dir / "province_terrain_layer.json").write_text(json.dumps(terrain, indent=2) + "\n", encoding="utf-8")
    # adjacency naive from centroid distance
    adj = _build_adjacency(out["provinces_geometry"]["provinces"])
    (pilot_dir / "province_adjacency.json").write_text(json.dumps(adj, indent=2) + "\n", encoding="utf-8")
    # ownership era index
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
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    (pilot_dir / "manifest_pilot_europe.json").write_text(
        json.dumps({
            "name": "provinces_pilot_europe",
            "parent": "provinces_world_full",
            "stats": out["stats"],
            "id_base": PILOT_ID_BASE,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    return {"path": str(pilot_dir), "stats": out["stats"], "ok": out.get("ok")}


def _build_adjacency(geom_provs: List[Dict[str, Any]], k: int = 5) -> Dict[str, Any]:
    cents = []
    for g in geom_provs:
        c = _centroid(g.get("points") or [])
        cents.append((int(g["id"]), c[0], c[1]))
    adj: Dict[str, List[int]] = {}
    for i, (pid, x, y) in enumerate(cents):
        dists = []
        for j, (pid2, x2, y2) in enumerate(cents):
            if i == j:
                continue
            d = (x - x2) ** 2 + (y - y2) ** 2
            dists.append((d, pid2))
        dists.sort()
        adj[str(pid)] = [pid2 for _, pid2 in dists[:k]]
    return {"version": 1, "adjacency": adj, "method": "k_nearest_centroid", "k": k}


def build_and_write_europe_pilot(
    world_dir: Path = WORLD_DIR,
    pilot_rel: str = PILOT_DIR_NAME,
    splits: int = 3,
) -> Dict[str, Any]:
    parents, gmap, owners = load_world_europe_core(world_dir)
    out = densify_europe_provinces(parents, gmap, owners, splits_per_parent=splits)
    pilot_dir = ROOT / "data" / pilot_rel
    written = write_pilot_dir(out, pilot_dir)
    written["ok"] = bool(out.get("ok")) and written.get("ok", True)
    written["stats"] = out["stats"]
    return written


def europe_pilot_integrity(pilot_dir: Path | None = None) -> Dict[str, Any]:
    pilot_dir = pilot_dir or (ROOT / "data" / PILOT_DIR_NAME)
    geom_p = pilot_dir / "provinces_geometry.json"
    if not geom_p.is_file():
        return {"ok": False, "summary": "Europe pilot missing", "empty": True}
    geom = json.loads(geom_p.read_text(encoding="utf-8"))
    meta = geom.get("meta") or {}
    land_before = int(meta.get("land_before") or 0)
    land_after = int(meta.get("land_after") or 0)
    n = len(geom.get("provinces") or [])
    verts = [len(p.get("points") or []) for p in geom.get("provinces") or []]
    mean_v = sum(verts) / max(1, len(verts))
    states = json.loads((pilot_dir / "province_states.json").read_text()).get("states") or []
    regions = json.loads((pilot_dir / "strategic_regions.json").read_text()).get("regions") or []
    own2026 = pilot_dir / "province_ownership_2026.json"
    from state_name_gazetteer import assert_names_shippable  # type: ignore

    names = [str(s.get("name", "")) for s in states]
    name_gate = assert_names_shippable(names)
    hs = {}
    hsp = pilot_dir / "hierarchy_scaffold.json"
    if hsp.is_file():
        hs = json.loads(hsp.read_text(encoding="utf-8"))
    has_super_bind = bool(hs.get("province_to_super_region")) or bool(hs.get("four_tier"))
    ok = (
        n >= 600
        and land_after >= int(land_before * 1.5)
        and mean_v >= 18
        and len(states) >= 40
        and len(regions) >= 6
        and own2026.is_file()
        and bool(name_gate.get("ok"))
        and has_super_bind
    )
    return {
        "ok": ok,
        "province_n": n,
        "land_before": land_before,
        "land_after": land_after,
        "densify_ratio": land_after / max(1, land_before),
        "mean_verts": mean_v,
        "state_n": len(states),
        "region_n": len(regions),
        "summary": "Europe pilot integrity %s · n=%d land %d→%d states=%d regions=%d"
        % ("PASS" if ok else "FAIL", n, land_before, land_after, len(states), len(regions)),
        "empty": False,
    }
