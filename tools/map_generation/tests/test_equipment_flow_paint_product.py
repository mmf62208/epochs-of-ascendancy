"""Pure tests for CP3 equipment flow map paint product."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from equipment_flow_paint_product import (
    build_equipment_flow_paint_primary_command_product,
    primary_command_dead_audit,
)


class TestEquipmentFlowPaint(unittest.TestCase):
    def test_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_equipment_flow_paint_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)


if __name__ == "__main__":
    unittest.main()
