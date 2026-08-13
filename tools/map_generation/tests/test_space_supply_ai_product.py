"""Pure hooks for space_supply_ai."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from space_supply_ai_product import build_space_supply_ai_primary_command_product, primary_command_dead_audit

class TestSpaceSupplyAi(unittest.TestCase):
    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_space_supply_ai_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_space_supply_ai_primary_live", gd)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("space_supply_ai_primary_live=1", sl)

if __name__ == "__main__":
    unittest.main()
