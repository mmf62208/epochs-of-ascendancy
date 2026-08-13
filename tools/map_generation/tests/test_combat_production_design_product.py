"""Pure tests for combat/production design freeze audit product.

Drives the real product module and asserts the committed design freeze file
contains locked sections — not a re-implementation of game logic.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from combat_production_design_product import (  # noqa: E402
    DESIGN_PATH,
    audit_design_freeze,
    build_combat_production_design_primary_command_product,
    primary_command_dead_audit,
    reinforcement_pipeline_ok,
    stock_units_on_complete,
)


class TestCombatProductionDesign(unittest.TestCase):
    def test_design_file_exists_and_audits(self):
        self.assertTrue(DESIGN_PATH.is_file(), "design freeze missing: %s" % DESIGN_PATH)
        a = audit_design_freeze()
        self.assertTrue(a["ok"], a)
        self.assertEqual(a["missing_markers"], [])
        self.assertIn("COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md", a["path"])

    def test_scale_helpers_match_freeze(self):
        # 1:1 named platforms
        self.assertEqual(stock_units_on_complete("tank", 3), 3)
        self.assertEqual(stock_units_on_complete("fighter", 2), 2)
        self.assertEqual(stock_units_on_complete("missile", 5), 5)
        self.assertEqual(stock_units_on_complete("ship", 1), 1)
        # Batches for mass/swarm
        self.assertEqual(stock_units_on_complete("truck", 1), 4)
        self.assertEqual(stock_units_on_complete("drone_swarm", 2), 12)
        # Explicit batch override
        self.assertEqual(stock_units_on_complete("tank", 1, batch_size=2), 2)

    def test_reinforcement_pipeline_keywords(self):
        self.assertTrue(reinforcement_pipeline_ok())

    def test_primary_product_and_source_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_combat_production_design_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        self.assertTrue(p["scale_ok"])
        self.assertTrue(p["flow_ok"])
        self.assertTrue(p["phases_ok"])
        self.assertEqual(p["model"], "equipment_flow_compact_ledger")
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_combat_production_design_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("combat_production_design_primary_live=1", sl)
        # Freeze must mention peer HOI and EquipmentFlow
        body = DESIGN_PATH.read_text(encoding="utf-8")
        self.assertIn("HOI4", body)
        self.assertIn("EquipmentFlow", body)
        self.assertIn("Map symbol policy", body)


if __name__ == "__main__":
    unittest.main()
