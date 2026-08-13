"""Global density pilot toward ~6k land — parallel dir, IDs 900000+.

Densifies world_full land provinces (2× median-split) without renumbering world_full.
Honesty: procedural_interim densify, not NUTS/GADM GIS.
"""
from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
WORLD = ROOT / "data" / "provinces_world_full"
PILOT = "provinces_pilot_global_density"
ID_BASE = 900000
WATER = frozenset({"sea", "strait", "lake"})


def is_water(p: Dict[str, Any]) -> bool:
    return str(p.get("domain") or "land") in WATER or bool(p.get("is_sea"))


def build_and_write_global_density(splits: int = 2) -> Dict[str, Any]:
    from europe_pilot_densify import densify_ring, split_polygon_median, _centroid  # type: ignore
    from shared_edge_adjacency_product import write_shared_edge_adjacency  # type: ignore
    from membership_era_product import write_membership_era_files, PRIMARY_MEMBERSHIP_ERAS  # type: ignore
    from state_name_gazetteer import assign_state_name  # type: ignore

    base = json.loads((WORLD / "provinces_base.json").read_text(encoding="utf-8"))
    geom = json.loads((WORLD / "provinces_geometry.json").read_text(encoding="utf-8"))
    own1936 = {}
    op = WORLD / "province_ownership_1936.json"
    if op.is_file():
        own1936 = json.loads(op.read_text(encoding="utf-8")).get("owners") or {}
    gmap = {int(g["id"]): g.get("points") or [] for g in geom["provinces"]}

    base_out: List[Dict[str, Any]] = []
    geom_out: List[Dict[str, Any]] = []
    own_out: Dict[str, str] = {}
    parent_map: Dict[str, int] = {}
    next_id = ID_BASE
    land_before = 0

    for p in base.get("provinces") or []:
        pid = int(p["id"])
        pts = gmap.get(pid) or []
        if len(pts) < 3:
            continue
        owner = str(own1936.get(str(pid)) or own1936.get(pid) or "NEU")
        if is_water(p):
            # keep water 1:1 densified ring only (no split) to control count
            ring = densify_ring(pts, max_edge=20.0, min_verts=16)
            entry = deepcopy(p)
            entry["id"] = next_id
            entry["parent_world_id"] = pid
            entry["theater"] = p.get("theater") or "sea"
            base_out.append(entry)
            geom_out.append({"id": next_id, "points": ring, "meta": {"pilot": True, "global_density": True, "parent_world_id": pid}})
            own_out[str(next_id)] = owner
            parent_map[str(next_id)] = pid
            next_id += 1
            continue
        land_before += 1
        pieces = [list(pts)]
        for s in range(max(1, splits - 1)):
            new_pieces = []
            for piece in pieces:
                a, b = split_polygon_median(piece, "auto" if s % 2 == 0 else "y")
                if len(a) >= 3:
                    new_pieces.append(a)
                if len(b) >= 3:
                    new_pieces.append(b)
            pieces = new_pieces or pieces
        for i, piece in enumerate(pieces):
            ring = densify_ring(piece, max_edge=14.0, min_verts=24)
            if len(ring) < 3:
                continue
            entry = deepcopy(p)
            entry["id"] = next_id
            entry["parent_world_id"] = pid
            entry["name"] = "%s · densify-%d" % (p.get("name") or ("L%d" % pid), i + 1)
            entry["theater"] = p.get("theater") or "europe_core"
            base_out.append(entry)
            geom_out.append({
                "id": next_id,
                "points": ring,
                "name": entry["name"],
                "meta": {
                    "pilot": True,
                    "global_density": True,
                    "parent_world_id": pid,
                    "split_index": i,
                },
            })
            own_out[str(next_id)] = owner
            parent_map[str(next_id)] = pid
            next_id += 1

    land_after = sum(1 for p in base_out if not is_water(p))
    # Simple hierarchy: chunk land by theater into states
    from collections import defaultdict

    by_th: Dict[str, List[int]] = defaultdict(list)
    for p in base_out:
        if is_water(p):
            continue
        by_th[str(p.get("theater") or "land")].append(int(p["id"]))
    states = []
    regions = []
    p2s: Dict[str, int] = {}
    p2r: Dict[str, int] = {}
    sid = 1
    rid = 1
    for th, pids in sorted(by_th.items()):
        pids = sorted(pids)
        regions.append({
            "id": rid,
            "name": th.replace("_", " ").title(),
            "province_ids": pids,
            "theater": th,
            "super_region_id": 1,
        })
        for pid in pids:
            p2r[str(pid)] = rid
        # states of ~12
        for i in range(0, len(pids), 12):
            part = pids[i : i + 12]
            name = assign_state_name(th, i // 12)
            states.append({
                "id": sid,
                "name": name,
                "province_ids": part,
                "region_id": rid,
                "theater": th,
                "owner_hint": own_out.get(str(part[0]), "NEU"),
            })
            for pid in part:
                p2s[str(pid)] = sid
            sid += 1
        rid += 1
    supers = [{"id": 1, "name": "Global Density Theater", "region_ids": [r["id"] for r in regions]}]
    p2super = {k: 1 for k in p2s}

    out_dir = ROOT / "data" / PILOT
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "provinces_base.json").write_text(
        json.dumps({"provinces": base_out, "meta": {"pilot": True, "global_density": True, "geometry_quality": "procedural_interim"}}, indent=2) + "\n",
        encoding="utf-8",
    )
    (out_dir / "provinces_geometry.json").write_text(
        json.dumps({
            "meta": {
                "pilot": True,
                "global_density": True,
                "id_base": ID_BASE,
                "land_before": land_before,
                "land_after": land_after,
                "densify_ratio": land_after / max(1, land_before),
                "geometry_quality": "procedural_interim",
                "target_band": [5000, 7000],
            },
            "provinces": geom_out,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    for era in (1910, 1918, 1936, 1945, 2026):
        wown = {}
        wp = WORLD / ("province_ownership_%d.json" % era)
        if wp.is_file():
            wown = json.loads(wp.read_text(encoding="utf-8")).get("owners") or {}
        mapped = {}
        for pid_s, wid in parent_map.items():
            mapped[pid_s] = wown.get(str(wid)) or own_out.get(pid_s) or "NEU"
        (out_dir / ("province_ownership_%d.json" % era)).write_text(
            json.dumps({
                "meta": {"era_year": era, "seed_only": True, "pilot": True, "reapply_on_year_tick": False},
                "owners": mapped,
            }, indent=2) + "\n",
            encoding="utf-8",
        )
    (out_dir / "province_states.json").write_text(
        json.dumps({"version": 3, "source": "global_density_pilot", "states": states}, indent=2) + "\n",
        encoding="utf-8",
    )
    (out_dir / "strategic_regions.json").write_text(
        json.dumps({"version": 4, "regions": regions}, indent=2) + "\n", encoding="utf-8"
    )
    (out_dir / "super_regions.json").write_text(
        json.dumps({"version": 1, "super_regions": supers}, indent=2) + "\n", encoding="utf-8"
    )
    (out_dir / "hierarchy_scaffold.json").write_text(
        json.dumps({
            "version": 2,
            "four_tier": True,
            "pilot": True,
            "global_density": True,
            "province_to_state": p2s,
            "province_to_region": p2r,
            "province_to_super_region": p2super,
            "state_n": len(states),
            "region_n": len(regions),
            "land_n": land_after,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    # layers stubs
    econ, terr, res = {}, {}, {}
    for p in base_out:
        pid = str(p["id"])
        wet = is_water(p)
        econ[pid] = {"development_level": 2 if not wet else 0, "infrastructure": 2 if not wet else 0, "population": 100000, "factories": 0}
        terr[pid] = {"terrain": "sea" if wet else "plains", "domain": p.get("domain", "land")}
        res[pid] = {"resources": {}}
    (out_dir / "province_economy_layer.json").write_text(json.dumps(econ) + "\n", encoding="utf-8")
    (out_dir / "province_terrain_layer.json").write_text(json.dumps(terr) + "\n", encoding="utf-8")
    (out_dir / "province_resources_layer.json").write_text(json.dumps(res) + "\n", encoding="utf-8")
    (out_dir / "province_city_layer.json").write_text("{}\n", encoding="utf-8")
    (out_dir / "project_sites.json").write_text('{"sites":[]}\n', encoding="utf-8")
    (out_dir / "ownership_era_index.json").write_text(
        json.dumps({
            "policy": {"seed_on_scenario_load": True, "reapply_on_year_tick": False},
            "eras": [{"year": y, "path": "province_ownership_%d.json" % y} for y in (1910, 1918, 1936, 1945, 2026)],
            "pilot": True,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    (out_dir / "manifest_pilot_global_density.json").write_text(
        json.dumps({
            "name": PILOT,
            "id_base": ID_BASE,
            "land_before": land_before,
            "land_after": land_after,
            "province_n": len(base_out),
            "geometry_quality": "procedural_interim",
            "target_band": [5000, 7000],
            "pilot_banner": True,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    adj = write_shared_edge_adjacency(out_dir, quant=1.5, knn_k=4)
    mem = write_membership_era_files(out_dir, PRIMARY_MEMBERSHIP_ERAS, regroup_by_owner=True)
    ok = land_after >= 4000 and land_after <= 9000 and bool(adj.get("ok")) and bool(mem.get("ok"))
    return {
        "ok": ok,
        "path": str(out_dir),
        "land_before": land_before,
        "land_after": land_after,
        "province_n": len(base_out),
        "densify_ratio": land_after / max(1, land_before),
        "adjacency": adj.get("summary"),
        "membership": mem.get("summary"),
        "summary": "Global density pilot %s · land %d→%d (target ~6k band)"
        % ("PASS" if ok else "FAIL", land_before, land_after),
    }


def global_density_integrity() -> Dict[str, Any]:
    d = ROOT / "data" / PILOT
    if not (d / "provinces_geometry.json").is_file():
        return {"ok": False, "summary": "missing global density pilot", "empty": True}
    meta = json.loads((d / "provinces_geometry.json").read_text()).get("meta") or {}
    land_after = int(meta.get("land_after") or 0)
    land_before = int(meta.get("land_before") or 0)
    n = len(json.loads((d / "provinces_geometry.json").read_text()).get("provinces") or [])
    ids_ok = all(int(g["id"]) >= ID_BASE for g in json.loads((d / "provinces_geometry.json").read_text())["provinces"])
    ok = land_after >= 4000 and land_after / max(1, land_before) >= 1.5 and ids_ok and n >= land_after
    return {
        "ok": ok,
        "land_before": land_before,
        "land_after": land_after,
        "province_n": n,
        "summary": "Global density integrity %s · land %d→%d"
        % ("PASS" if ok else "FAIL", land_before, land_after),
        "empty": False,
    }
