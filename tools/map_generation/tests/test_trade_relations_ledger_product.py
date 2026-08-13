"""Pure tests for Strategic Compact Ledger (trade valuation + relations)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from trade_relations_ledger_product import (  # noqa: E402
    band_for_crs,
    build_trade_relations_primary_command_product,
    crs_from_vectors,
    docking_suu,
    equipment_suu,
    evaluate_concerns,
    load_relation_rules,
    load_value_rules,
    primary_command_dead_audit,
    province_suu,
    resource_suu,
)


class TestTradeRelationsLedger(unittest.TestCase):
    def test_rules_model(self):
        self.assertEqual(load_value_rules().get("model"), "strategic_compact_ledger")
        self.assertEqual(load_relation_rules().get("model"), "strategic_compact_ledger")
        self.assertGreaterEqual(len(load_relation_rules().get("vectors", [])), 5)

    def test_province_dominates_equipment(self):
        tank = equipment_suu(110)
        peri = province_suu(8, 8, False, 50, 1)
        core = province_suu(20, 20, True, 200, 4, True, True)
        self.assertGreater(peri, tank * 10)
        self.assertGreater(core, peri)
        self.assertGreater(docking_suu(12, True), resource_suu("steel", 50, {"steel": 100}))

    def test_crs_and_bands(self):
        crs = crs_from_vectors({"public": 60, "elite": 60, "military": 60, "alignment": 60, "trust": 60})
        band = band_for_crs(crs)
        self.assertIn(band["id"], ("partner", "ally_ready", "cordial"))

    def test_concern_flags_hard_blocks(self):
        self.assertTrue(evaluate_concerns(["docking_rights"], -20)["hard_block"])
        self.assertTrue(evaluate_concerns(["design"], 10)["hard_block"])
        self.assertFalse(evaluate_concerns(["resource"], 40)["hard_block"])

    def test_primary_and_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_trade_relations_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        self.assertTrue(p["value_ok"])
        self.assertTrue(p["flags_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_trade_relations_primary_live", gd)
        self.assertIn("RelationsManager", (ROOT / "project.godot").read_text(encoding="utf-8"))
        doc = (ROOT / "docs" / "TRADE_RELATIONS_STRATEGIC_DESIGN.md").read_text(encoding="utf-8")
        self.assertIn("strategic_compact_ledger", doc)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("trade_relations_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
