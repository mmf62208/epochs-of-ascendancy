"""Pure tests for EquipmentFlow CP1 + stock/reinforce CP2 products."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from equipment_flow_product import (
    amount_after_interdict,
    build_equipment_flow_primary_command_product,
    build_equipment_stock_reinforce_primary_command_product,
    demand_deficit,
    effective_interdict_loss,
    esr_primary_command_dead_audit,
    primary_command_dead_audit,
    stock_units_on_complete,
    symbol_for_mode,
)

class TestEquipmentFlow(unittest.TestCase):
    def test_interdict_math(self):
        loss = effective_interdict_loss(0.4, 0.1, False)
        self.assertGreater(loss, 0.1)
        esc = effective_interdict_loss(0.4, 0.1, True)
        self.assertLess(esc, loss)
        s = amount_after_interdict(10, 0.4)
        self.assertEqual(s["lost"] + s["delivered"], 10)
        self.assertEqual(symbol_for_mode("rail"), "train")
        self.assertEqual(symbol_for_mode("sealift"), "merchant")

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_equipment_flow_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_equipment_flow_primary_live", gd)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("equipment_flow_primary_live=1", sl)
        pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func create_equipment_flow", pm)
        self.assertIn("func interdict_equipment_flow", pm)
        self.assertIn("func ship_and_reinforce_unit", pm)

    def test_cp2_stock_scale_and_deficit(self):
        self.assertEqual(stock_units_on_complete("tank", 3), 3)
        self.assertEqual(stock_units_on_complete("truck", 1), 4)
        self.assertEqual(stock_units_on_complete("drone_swarm", 2), 12)
        self.assertEqual(stock_units_on_complete("tank", 1, batch_size=2), 2)
        self.assertEqual(demand_deficit(2, 8), 6)
        self.assertEqual(demand_deficit(10, 4), 0)

    def test_cp2_stock_reinforce_product(self):
        self.assertTrue(esr_primary_command_dead_audit()["ok"])
        p = build_equipment_stock_reinforce_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        self.assertTrue(p["scale_ok"])
        self.assertTrue(p["hooks_ok"])
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_equipment_stock_reinforce_primary_live", gd)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("equipment_stock_reinforce_primary_live=1", sl)
        pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func credit_production_complete_to_stockpile", pm)
        self.assertIn("func demand_reinforce_tick_via_flow", pm)

if __name__ == "__main__":
    unittest.main()
