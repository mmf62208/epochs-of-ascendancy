#!/usr/bin/env python3
"""
Rebuild provinces_base.json so it matches the authoritative geometry set exactly.
Used for provinces_phase1_test / provinces_full_europe (471 dense Europe children).

Inherits parent catalog attributes for subdivided children via id_remap.json.
"""
from __future__ import annotations

import argparse
import json
import shutil
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

ROOT = Path(__file__).resolve().parents[3]
LEGACY_BASE = ROOT / "data" / "provinces" / "provinces_base.json"
DEFAULT_REMAP = (
    ROOT
    / "tools/map_generation/output/phase1_europe/merged_v3_closest_wiring/id_remap.json"
)


def load_json(path: Path) -> Any:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
    print(f"  Wrote {path.relative_to(ROOT)}")


def build_child_to_parent(remap: Dict[str, int]) -> Dict[int, int]:
    out: Dict[int, int] = {}
    for old_key, new_id in remap.items():
        if "_c" in old_key:
            parent_str = old_key.split("_c")[0]
            try:
                out[int(new_id)] = int(parent_str)
            except ValueError:
                continue
    return out


def index_base(base_payload: Dict[str, Any]) -> Dict[int, Dict[str, Any]]:
    return {int(p["id"]): p for p in base_payload.get("provinces", [])}


def split_resources(resources: Dict[str, Any], idx: int, total: int) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for key, val in resources.items():
        try:
            n = int(val)
        except (TypeError, ValueError):
            continue
        share = max(0, int(n * (0.55 + 0.15 * idx) / max(1, total)))
        if share > 0:
            out[key] = share
    return out


def make_entry(
    pid: int,
    parent_id: Optional[int],
    legacy: Dict[int, Dict[str, Any]],
    terrain_layer: Dict[str, Any],
    economy_layer: Dict[str, Any],
    resources_layer: Dict[str, Any],
    city_layer: Dict[str, Any],
    child_index: int = 0,
    child_total: int = 1,
) -> Dict[str, Any]:
    parent = legacy.get(parent_id, {}) if parent_id is not None else {}
    terr = terrain_layer.get(str(pid), terrain_layer.get(str(parent_id or pid), {}))
    econ = economy_layer.get(str(pid), {})
    res = resources_layer.get(str(pid), {})
    cities = city_layer.get(str(pid), {}).get("cities", [])

    terrain = str(terr.get("terrain", parent.get("terrain", "plains")))
    natural = res if res else split_resources(parent.get("natural_resources", {}), child_index, child_total)
    if not natural and econ.get("resources"):
        natural = dict(econ.get("resources", {}))

    pop = int(econ.get("population", econ.get("pop", parent.get("population_base", 500000))))
    name = parent.get("name", f"Province {pid}")
    if pid >= 9000 and parent_id is not None:
        suffix = f" ({child_index + 1}/{child_total})" if child_total > 1 else ""
        name = f"{parent.get('name', f'Province {parent_id}')}{suffix}"

    if cities:
        name = str(cities[0].get("name", name))

    special = list(parent.get("special_features", []))
    if terr.get("terrain") == "coastal" and "port" not in " ".join(special).lower():
        special.append("coastal_access")

    entry: Dict[str, Any] = {
        "id": pid,
        "name": name,
        "terrain": terrain,
        "core_for_tags": list(parent.get("core_for_tags", [])),
        "natural_resources": natural,
        "population_base": pop,
        "special_features": special,
        "special_levels": dict(parent.get("special_levels", {})),
    }
    if terr.get("terrain") in ("sea", "ocean") or terr.get("is_sea") or bool(parent.get("is_sea", False)):
        entry["is_sea"] = True
    return entry


def sync_base_catalog(data_dir: Path, remap_path: Path, backup: bool = True) -> int:
    geom_payload = load_json(data_dir / "provinces_geometry.json")
    geom_ids: List[int] = sorted(int(p["id"]) for p in geom_payload.get("provinces", []))

    legacy_payload = load_json(LEGACY_BASE)
    legacy = index_base(legacy_payload)

    terrain_layer = load_json(data_dir / "province_terrain_layer.json").get("provinces", {})
    economy_layer = load_json(data_dir / "province_economy_layer.json").get("provinces", {})
    resources_layer = load_json(data_dir / "province_resources_layer.json").get("provinces", {})
    city_layer = load_json(data_dir / "province_city_layer.json").get("provinces", {})

    child_to_parent: Dict[int, int] = {}
    if remap_path.exists():
        remap_raw = load_json(remap_path)
        child_to_parent = build_child_to_parent(
            remap_raw.get("old_to_new", remap_raw.get("id_remap", {}))
        )

    # Count siblings per parent for naming/resource split
    siblings: Dict[int, List[int]] = {}
    for cid, par in child_to_parent.items():
        siblings.setdefault(par, []).append(cid)
    for par in siblings:
        siblings[par].sort()

    entries: List[Dict[str, Any]] = []
    for pid in geom_ids:
        parent_id = child_to_parent.get(pid, pid if pid in legacy else None)
        if parent_id is None and pid not in legacy:
            parent_id = None
        child_index = 0
        child_total = 1
        if pid in child_to_parent:
            sibs = siblings.get(child_to_parent[pid], [pid])
            child_index = sibs.index(pid) if pid in sibs else 0
            child_total = len(sibs)
        entries.append(
            make_entry(
                pid,
                parent_id if pid >= 9000 or pid not in legacy else pid,
                legacy,
                terrain_layer,
                economy_layer,
                resources_layer,
                city_layer,
                child_index,
                child_total,
            )
        )

    out_path = data_dir / "provinces_base.json"
    if backup and out_path.exists():
        bak = out_path.with_suffix(".json.bak")
        shutil.copy(out_path, bak)
        print(f"  Backup -> {bak.relative_to(ROOT)}")

    payload = {
        "meta": {
            "version": 2,
            "source": "sync_phase1_base_catalog.py",
            "province_count": len(entries),
            "geometry_authoritative": True,
        },
        "provinces": entries,
    }
    save_json(out_path, payload)
    print(f"  Synced {len(entries)} base entries (geometry={len(geom_ids)})")
    return len(entries)


def main() -> None:
    parser = argparse.ArgumentParser(description="Sync provinces_base.json to geometry set")
    parser.add_argument(
        "--dir",
        default="data/provinces_phase1_test",
        help="Province data directory relative to project root",
    )
    parser.add_argument(
        "--remap",
        default=str(DEFAULT_REMAP.relative_to(ROOT)),
        help="id_remap.json path relative to project root",
    )
    parser.add_argument("--no-backup", action="store_true")
    args = parser.parse_args()

    data_dir = ROOT / args.dir
    remap_path = ROOT / args.remap
    if not (data_dir / "provinces_geometry.json").exists():
        raise SystemExit(f"Missing geometry in {data_dir}")
    count = sync_base_catalog(data_dir, remap_path, backup=not args.no_backup)
    print(f"DONE: {count} provinces in {data_dir / 'provinces_base.json'}")


if __name__ == "__main__":
    main()
