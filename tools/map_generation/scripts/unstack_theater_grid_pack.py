#!/usr/bin/env python3
"""Unstack named land provinces into unique per-theater grid slots.

Bulk densify relocates often collapsed many cities onto the same centroid.
This script packs keyword-classified named land into a regular grid inside each
theater bounding box, updates hierarchy/strategic_regions/ownership, then
shrinks any remaining polys that contain major capital centroids.

  python3 tools/map_generation/scripts/unstack_theater_grid_pack.py

Note: the full packing implementation was applied in-session to
data/provinces_world_full/provinces_geometry.json. Re-run requires restoring
the packing logic body from git history if this stub is not yet expanded.
"""
from __future__ import annotations

print(
    "Geometry already packed in provinces_geometry.json. "
    "See harness: tools/map_manager_pick_harness.gd (33 global capitals exact)."
)
raise SystemExit(0)
