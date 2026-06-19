#!/usr/bin/env python3
"""Export data-driven naval chokepoint province ids from naval_analysis."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import naval_analysis  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dir",
        default="data/provinces_phase1_test",
        help="Province data directory relative to project root",
    )
    parser.add_argument(
        "--out",
        default="data/provinces_phase1_test/naval_chokepoints.json",
        help="Output JSON path relative to project root",
    )
    args = parser.parse_args()

    data_dir = ROOT / args.dir
    layers = naval_analysis.load_all_layers(data_dir)
    adj = layers["adjacency"]
    chokepoints = naval_analysis.find_potential_chokepoints(adj, min_degree=2, max_degree=3)
    coastal = naval_analysis.get_coastal_provinces(layers)
    straits = naval_analysis.get_major_strait_connections(adj)

    geom_ids = {int(p["id"]) for p in layers["geometry"].get("provinces", [])}
    adj_map = {int(k): [int(n) for n in v] for k, v in adj.get("adjacency", {}).items()}

    # Tight filter: low-degree articulation candidates that are coastal or curated straits
    choke_ids = sorted(
        pid
        for pid in chokepoints
        if pid in geom_ids and pid in coastal and len(adj_map.get(pid, [])) <= 3
    )
    strait_pids: set[int] = set()
    for info in straits.values():
        if info.get("protected"):
            strait_pids.add(int(info.get("province_a", -1)))
            strait_pids.add(int(info.get("province_b", -1)))
    strait_pids = {pid for pid in strait_pids if pid in geom_ids and pid in coastal}

    # Sites tagged as strait/chokepoint in project_sites
    sites_path = data_dir / "project_sites.json"
    site_pids: set[int] = set()
    if sites_path.exists():
        sites = json.loads(sites_path.read_text())["sites"]
        for s in sites:
            pt = str(s.get("project_type", "")).lower()
            if any(k in pt for k in ("strait", "choke")):
                pid = int(s.get("province_id", -1))
                if pid in geom_ids:
                    site_pids.add(pid)

    all_pids = sorted(set(choke_ids) | strait_pids | site_pids)

    out = {
        "meta": {"source": "export_naval_chokepoints.py", "count": len(all_pids)},
        "chokepoint_province_ids": all_pids,
        "articulation_chokepoints": choke_ids,
        "strait_provinces": sorted(strait_pids),
        "naval_site_provinces": sorted(site_pids),
        "coastal_count": len(coastal & geom_ids),
    }
    out_path = ROOT / args.out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"Wrote {len(all_pids)} chokepoint ids -> {out_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
