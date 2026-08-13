#!/usr/bin/env python3
"""Gates: global density pilot toward ~6k land (IDs 900000+)."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from global_density_pilot import (  # noqa
    ID_BASE,
    PILOT,
    global_density_integrity,
    build_and_write_global_density,
)

PILOT_DIR = ROOT / "data" / PILOT
WORLD = ROOT / "data" / "provinces_world_full"


class TestGlobalDensityPilot(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (PILOT_DIR / "provinces_geometry.json").is_file():
            build_and_write_global_density(splits=2)

    def test_integrity(self):
        g = global_density_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        self.assertGreaterEqual(int(g.get("land_after") or 0), 4000)

    def test_id_namespace(self):
        geom = json.loads((PILOT_DIR / "provinces_geometry.json").read_text())
        world_ids = {int(p["id"]) for p in json.loads((WORLD / "provinces_geometry.json").read_text())["provinces"]}
        for p in geom["provinces"]:
            pid = int(p["id"])
            self.assertGreaterEqual(pid, ID_BASE)
            self.assertNotIn(pid, world_ids)

    def test_toward_6k_band(self):
        meta = json.loads((PILOT_DIR / "provinces_geometry.json").read_text()).get("meta") or {}
        land = int(meta.get("land_after") or 0)
        # 5–7k target band; require ≥4k densify progress from scaffold land
        self.assertGreaterEqual(land, 4000)
        self.assertLessEqual(land, 9000)
        self.assertGreaterEqual(float(meta.get("densify_ratio") or 0), 1.5)

    def test_adjacency_and_membership(self):
        adj = json.loads((PILOT_DIR / "province_adjacency.json").read_text())
        self.assertIn("shared_edge", str(adj.get("method")))
        for y in (1910, 1918, 1936, 2026):
            snap = json.loads((PILOT_DIR / ("hierarchy_membership_%d.json" % y)).read_text())
            self.assertEqual(snap.get("mode"), "full")

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_global_density_pilot.py", ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
