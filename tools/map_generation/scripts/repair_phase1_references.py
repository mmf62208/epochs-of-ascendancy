#!/usr/bin/env python3
"""Repair states, regions, project_sites, adjacency to match authoritative geometry."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List, Set

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_REMAP = (
    ROOT
    / "tools/map_generation/output/phase1_europe/merged_v3_closest_wiring/id_remap.json"
)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, indent=2), encoding="utf-8")
    print(f"  Wrote {path.relative_to(ROOT)}")


def build_parent_children(remap: Dict[str, int]) -> Dict[int, List[int]]:
    out: Dict[int, List[int]] = {}
    for old_key, new_id in remap.items():
        if "_c" not in old_key:
            continue
        parent = int(old_key.split("_c")[0])
        out.setdefault(parent, []).append(int(new_id))
    for pid in out:
        out[pid].sort()
    return out


def expand_pid(pid: int, geom_ids: Set[int], parent_children: Dict[int, List[int]]) -> List[int]:
    if pid in geom_ids:
        return [pid]
    if pid in parent_children:
        return [c for c in parent_children[pid] if c in geom_ids]
    return []


def repair_states(states: List[Dict], geom_ids: Set[int], parent_children: Dict[int, List[int]]) -> List[Dict]:
    repaired: List[Dict] = []
    for st in states:
        new_ids: List[int] = []
        for pid in st.get("province_ids", []):
            new_ids.extend(expand_pid(int(pid), geom_ids, parent_children))
        new_ids = sorted(set(new_ids))
        if not new_ids:
            continue
        hub = int(st.get("supply_hub_province_id", new_ids[0]))
        if hub not in new_ids:
            hub = new_ids[len(new_ids) // 2]
        repaired.append(
            {
                **st,
                "province_ids": new_ids,
                "supply_hub_province_id": hub,
            }
        )
    return repaired


def repair_regions(regions: List[Dict], geom_ids: Set[int], parent_children: Dict[int, List[int]]) -> List[Dict]:
    repaired: List[Dict] = []
    for rg in regions:
        new_ids: List[int] = []
        for pid in rg.get("province_ids", []):
            new_ids.extend(expand_pid(int(pid), geom_ids, parent_children))
        new_ids = sorted(set(new_ids))
        if not new_ids:
            continue
        repaired.append({**rg, "province_ids": new_ids})
    return repaired


def repair_adjacency(adjacency: Dict[str, List], geom_ids: Set[int]) -> Dict[str, List[int]]:
    out: Dict[str, List[int]] = {}
    for sid, neigh in adjacency.items():
        a = int(sid)
        if a not in geom_ids:
            continue
        filtered = sorted({int(n) for n in neigh if int(n) in geom_ids})
        out[str(a)] = filtered
    return out


def repair_project_sites(sites: List[Dict], geom_ids: Set[int], parent_children: Dict[int, List[int]]) -> List[Dict]:
    out: List[Dict] = []
    seen: Set[tuple] = set()
    for site in sites:
        pid = int(site.get("province_id", -1))
        targets = expand_pid(pid, geom_ids, parent_children)
        if not targets:
            continue
        for t in targets[:1]:
            key = (t, site.get("project_type", ""))
            if key in seen:
                continue
            seen.add(key)
            out.append({**site, "province_id": t})
    return out


def repair_dir(data_dir: Path, remap_path: Path) -> None:
    geom_ids = {
        int(p["id"])
        for p in load_json(data_dir / "provinces_geometry.json").get("provinces", [])
    }
    remap_raw = load_json(remap_path)
    parent_children = build_parent_children(remap_raw.get("old_to_new", remap_raw.get("id_remap", {})))

    states_path = data_dir / "province_states.json"
    states_payload = load_json(states_path)
    states_payload["states"] = repair_states(states_payload.get("states", []), geom_ids, parent_children)
    save_json(states_path, states_payload)

    regions_path = data_dir / "strategic_regions.json"
    regions_payload = load_json(regions_path)
    regions_payload["regions"] = repair_regions(regions_payload.get("regions", []), geom_ids, parent_children)
    save_json(regions_path, regions_payload)

    adj_path = data_dir / "province_adjacency.json"
    adj_payload = load_json(adj_path)
    adj_payload["adjacency"] = repair_adjacency(adj_payload.get("adjacency", {}), geom_ids)
    save_json(adj_path, adj_payload)

    sites_path = data_dir / "project_sites.json"
    if sites_path.exists():
        sites_payload = load_json(sites_path)
        sites_payload["sites"] = repair_project_sites(sites_payload.get("sites", []), geom_ids, parent_children)
        save_json(sites_path, sites_payload)

    print(f"  Repaired layers for {len(geom_ids)} geometry provinces in {data_dir.name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default="data/provinces_phase1_test")
    parser.add_argument("--remap", default=str(DEFAULT_REMAP.relative_to(ROOT)))
    args = parser.parse_args()
    repair_dir(ROOT / args.dir, ROOT / args.remap)


if __name__ == "__main__":
    main()
