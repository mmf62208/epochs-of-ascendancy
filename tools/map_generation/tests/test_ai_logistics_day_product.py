"""Pure tests for AI logistics day product."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from ai_logistics_day_product import (
    build_ai_logistics_day_primary_command_product,
    primary_command_dead_audit,
)


class TestAiLogisticsDay(unittest.TestCase):
    def test_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_ai_logistics_day_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        self.assertTrue(p["wire_ok"])
        mm = (ROOT / "scripts/map/MapManager.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_ai_logistics_doctrine_day", mm)
        self.assertIn("ai_select_logistics_doctrine", mm)


if __name__ == "__main__":
    unittest.main()
