"""Pure + hooks for colony CRS, range, independence, landing/bombardment, save."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from space_colony_product import (  # noqa: E402
    build_space_colony_primary_command_product,
    can_bombard,
    can_land,
    independence_ready,
    parent_crs,
    primary_command_dead_audit,
    range_can_interact,
)


class TestSpaceColony(unittest.TestCase):
    def test_parent_crs(self):
        self.assertAlmostEqual(parent_crs({"public": 20, "elite": 20, "military": 20, "trust": 20}), 20.0)

    def test_range(self):
        self.assertTrue(range_can_interact(1.0, 0.5))
        self.assertFalse(range_can_interact(0.5, 5.0))
        self.assertTrue(range_can_interact(0.1, 99.0, True))

    def test_independence_and_combat(self):
        self.assertTrue(independence_ready(100, 25))
        self.assertFalse(independence_ready(99, 25))
        self.assertTrue(can_land(1, True))
        self.assertFalse(can_land(0, True))
        self.assertTrue(can_bombard(0, 2, True))

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_space_colony_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_space_colony_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("space_colony_primary_live=1", sl)
        slm = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        self.assertIn("space_layer", slm)


if __name__ == "__main__":
    unittest.main()
