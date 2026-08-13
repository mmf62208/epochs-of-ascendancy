"""Pure tests for CP4 munitions + drone product."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from munitions_drone_product import (
    build_munitions_drone_primary_command_product,
    consume_amount,
    primary_command_dead_audit,
    stock_units,
)


class TestMunitionsDrone(unittest.TestCase):
    def test_scale(self):
        self.assertEqual(stock_units("missile", 5), 5)
        self.assertEqual(stock_units("drone_swarm", 1), 6)
        self.assertEqual(stock_units("munition", 1), 10)
        self.assertEqual(consume_amount("missile", 3), 3)

    def test_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_munitions_drone_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        self.assertTrue(p["missile_ok"])
        self.assertTrue(p["drone_ok"])


if __name__ == "__main__":
    unittest.main()
