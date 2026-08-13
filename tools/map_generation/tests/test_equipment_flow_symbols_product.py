"""Pure tests for CP3 EquipmentFlow map symbols product."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from equipment_flow_symbols_product import (
    MODE_SYMBOL,
    build_equipment_flow_symbols_primary_command_product,
    primary_command_dead_audit,
)


class TestEquipmentFlowSymbols(unittest.TestCase):
    def test_mode_symbol_table(self):
        self.assertEqual(MODE_SYMBOL["rail"], "train")
        self.assertEqual(MODE_SYMBOL["road"], "truck")
        self.assertEqual(MODE_SYMBOL["sealift"], "merchant")

    def test_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_equipment_flow_symbols_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_equipment_flow_symbols_primary_live", gd)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("equipment_flow_symbols_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
