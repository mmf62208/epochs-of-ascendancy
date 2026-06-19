#!/usr/bin/env python3
"""Add minimal sea zone entries to phase1 adjacency for naval routing tests."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default="data/provinces_phase1_test")
    args = parser.parse_args()
    data_dir = ROOT / args.dir
    geom_path = data_dir / "provinces_geometry.json"
    adj_path = data_dir / "province_adjacency.json"
    terrain_path = data_dir / "province_terrain_layer.json"

    geom = json.loads(geom_path.read_text())
    adj_payload = json.loads(adj_path.read_text())
    terrain = json.loads(terrain_path.read_text()).get("provinces", {})
    adj = adj_payload.get("adjacency", {})

    geom_ids = {int(p["id"]) for p in geom.get("provinces", [])}
    coastal = [int(k) for k, v in terrain.items() if v.get("terrain") == "coastal" and int(k) in geom_ids]
    if not coastal:
        print("No coastal provinces found; skipping sea zones")
        return

    # Reserve sea ids above 9500
    next_sea = 9500
    added = 0
    while str(next_sea) in adj or next_sea in geom_ids:
        next_sea += 1

    sea_id = next_sea
    # Simple rectangular sea poly NW of Europe canvas (Baltic/North Sea proxy)
    sea_poly = {
        "id": sea_id,
        "points": [[1800, 200], [2400, 200], [2400, 700], [1800, 700]],
        "label_anchor": [2100, 450],
        "is_sea": True,
        "name": "North Sea Zone (prototype)",
    }
    geom["provinces"].append(sea_poly)
    geom_ids.add(sea_id)

    sea_neighbors = sorted(set(coastal[: min(12, len(coastal))]))
    adj[str(sea_id)] = sea_neighbors
    for cid in sea_neighbors:
        adj.setdefault(str(cid), [])
        if sea_id not in adj[str(cid)]:
            adj[str(cid)].append(sea_id)

    adj_payload["adjacency"] = adj
    terrain[str(sea_id)] = {"terrain": "sea", "movement_cost": 1.0, "combat_modifier": -0.5, "is_sea": True}

    geom_path.write_text(json.dumps(geom, indent=2), encoding="utf-8")
    adj_path.write_text(json.dumps(adj_payload, indent=2), encoding="utf-8")
    terrain_full = json.loads(terrain_path.read_text())
    terrain_full["provinces"] = terrain
    terrain_path.write_text(json.dumps(terrain_full, indent=2), encoding="utf-8")
    print(f"Added sea zone {sea_id} linked to {len(sea_neighbors)} coastal provinces")


if __name__ == "__main__":
    main()
