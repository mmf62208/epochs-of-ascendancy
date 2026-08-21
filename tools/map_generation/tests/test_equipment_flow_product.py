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
    build_toe_industry_loop_product,
    demand_deficit,
    effective_interdict_loss,
    esr_primary_command_dead_audit,
    factory_output_keys,
    primary_command_dead_audit,
    produce_to_stockpile,
    reinforce_from_stockpile,
    stock_units_on_complete,
    symbol_for_mode,
)
from unit_composition_combat_product import compose

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

    def test_toe_industry_loop(self):
        designed = compose(
            mobility="truck",
            armor="medium_tank",
            support="artillery",
            infantry_bns=3,
            tank_bns=1,
        )
        toe = designed.get("equipment") or {}
        keys = factory_output_keys(toe)
        for need in ("infantry_equipment", "trucks", "tanks", "artillery"):
            self.assertIn(need, keys)
        res = {"steel": 200.0, "coal": 50.0, "rubber": 40.0, "oil": 40.0, "chromium": 20.0, "tungsten": 20.0}
        stock = {}
        prod = produce_to_stockpile(res, stock, "trucks", 8)
        self.assertTrue(prod["ok"], prod)
        self.assertEqual(int(prod["stock_after"]), 8)
        empty = reinforce_from_stockpile({}, {}, toe, 1.0)
        self.assertEqual(empty.get("moved") or {}, {})
        self.assertLessEqual(float(empty["fill_after"]), float(empty["fill_before"]) + 1e-9)
        short = {k: max(0, int(v) // 5) for k, v in toe.items()}
        filled = reinforce_from_stockpile(short, prod["stock"], toe, 1.0)
        self.assertTrue(filled.get("moved"), filled)
        self.assertGreater(float(filled["fill_after"]), float(filled["fill_before"]))
        no_res = produce_to_stockpile({}, {}, "tanks", 4)
        self.assertFalse(no_res["ok"])
        self.assertEqual(int(no_res["added"]), 0)
        p = build_toe_industry_loop_product()
        self.assertTrue(p.get("ok"), p)
        self.assertEqual(list(p.get("fail") or []), [], p)
        esr = build_equipment_stock_reinforce_primary_command_product()
        self.assertTrue(esr.get("toe_ok"), esr)

if __name__ == "__main__":
    unittest.main()
