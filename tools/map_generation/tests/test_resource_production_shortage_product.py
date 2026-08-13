#!/usr/bin/env python3
"""Pure + structural tests for strategic resource shortage (shipped rules + GD path)."""
from __future__ import annotations
import re
import unittest
import sys
from pathlib import Path

LIB = Path(__file__).resolve().parents[1] / "lib"
PROJECT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(LIB))

from resource_production_shortage_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    RULES_PATH,
    build_resource_production_primary_command_product,
    compute_resource_outcome,
    compute_shortage_multipliers,
    compute_weighted_fill_ratio,
    get_major_resources,
    load_production_cost_rules,
    resolve_daily_resource_cost,
    scenario_pair,
)


class TestResourceProductionShortage(unittest.TestCase):
    def test_rules_file_is_shipped_source(self):
        self.assertTrue(RULES_PATH.exists(), str(RULES_PATH))
        rules = load_production_cost_rules()
        self.assertIn("resource_costs_per_day", rules)
        self.assertIn("resource_shortage", rules)
        self.assertIn("major_resources", rules)
        self.assertEqual(rules.get("integration_model"), "strategic_stockpile_soft_shortage")
        majors = get_major_resources(rules)
        self.assertEqual(len(majors), 8)
        for need in (
            "steel",
            "aluminum",
            "energy",
            "fuel",
            "rubber",
            "electronics",
            "specials",
            "fissiles",
        ):
            self.assertIn(need, majors)
        # Coal is an Energy source, not a player major
        self.assertNotIn("coal", majors)
        # Fissiles separate from specials; uranium is alias not major id
        self.assertNotIn("uranium", majors)
        self.assertNotIn("rare_earth", majors)
        fiss = rules["major_resources"]["fissiles"]
        self.assertTrue(fiss.get("hidden_until_unlocked"))
        self.assertIn("uranium", fiss.get("aliases", []))
        energy = rules["major_resources"]["energy"]
        self.assertIn("coal", energy.get("aliases", []))
        self.assertIn("plastics_improves_efficiency", rules["major_resources"]["rubber"].get("tech_modifiers", []))
        self.assertIn("ops_resources", rules)
        self.assertIn("manpower", rules["ops_resources"])
        self.assertIn("supplies", rules["ops_resources"])
        self.assertIn("endgame_resources", rules)

    def test_full_supply_full_speed(self):
        rules = load_production_cost_rules()
        needed = resolve_daily_resource_cost("medium_tank", rules)
        have = {k: float(v) * 5 for k, v in needed.items()}
        out = compute_resource_outcome(needed, have, rules=rules)
        self.assertGreaterEqual(float(out["fill_ratio"]), 0.999)
        self.assertAlmostEqual(float(out["output_multiplier"]), 1.0, places=3)
        self.assertTrue(out["afforded"])

    def test_shortage_reduces_throughput(self):
        full, short = scenario_pair("medium_tank")
        self.assertAlmostEqual(float(full["output_multiplier"]), 1.0, places=2)
        self.assertLess(float(short["output_multiplier"]), float(full["output_multiplier"]) - 0.05)
        self.assertGreaterEqual(float(short["output_multiplier"]), 0.55 - 1e-6)
        self.assertFalse(short["afforded"])
        self.assertTrue(short["partial"] or float(short["fill_ratio"]) == 0.0)

    def test_critical_resource_hurts_more_than_common_at_same_ratio(self):
        rules = load_production_cost_rules()
        # Same 50% fill: steel-only vs electronics-only (electronics is critical)
        fill_steel = compute_weighted_fill_ratio({"steel": 10.0}, {"steel": 5.0}, rules=rules)
        fill_elec = compute_weighted_fill_ratio({"electronics": 10.0}, {"electronics": 5.0}, rules=rules)
        # Critical uses power curve → lower effective fill than linear 0.5
        self.assertAlmostEqual(fill_steel, 0.5, places=3)
        self.assertLess(fill_elec, fill_steel - 0.01)
        m_steel = compute_shortage_multipliers(fill_steel, rules=rules)
        m_elec = compute_shortage_multipliers(fill_elec, rules=rules)
        self.assertLess(float(m_elec["speed"]), float(m_steel["speed"]))

    def test_product_shortage_matters_and_no_focus(self):
        p = build_resource_production_primary_command_product()
        self.assertTrue(p.get("shortage_matters"))
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        for api in LIVE_API_BY_STEP.values():
            self.assertNotEqual(api, "apply_focus")
            self.assertTrue(api.startswith("apply_resource_production_"))

    def test_gamedata_live_path_wired(self):
        gd = (PROJECT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s" % api, gd, api)
        self.assertIn("func apply_resource_production_primary_live", gd)
        self.assertIn("ProductionCostCalculator.compute_resource_outcome", gd)
        calc = (PROJECT / "scripts/production/ProductionCostCalculator.gd").read_text(encoding="utf-8")
        self.assertIn("func compute_weighted_fill_ratio", calc)
        self.assertIn("func compute_shortage_multipliers", calc)
        self.assertIn("func compute_resource_outcome", calc)
        pm = (PROJECT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("ProductionCostCalculator.compute_weighted_fill_ratio", pm)
        self.assertIn("ProductionCostCalculator.compute_shortage_multipliers", pm)
        sl = (PROJECT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("resource_production_primary_live=1", sl)
        design = (PROJECT / "docs/RESOURCE_PRODUCTION_STRATEGIC_DESIGN.md").read_text(encoding="utf-8")
        self.assertIn("HOI4", design)
        self.assertIn("Stellaris", design)
        self.assertTrue("Victoria" in design or "Vic3" in design)
        self.assertIn("strategic_stockpile_soft_shortage", design)


if __name__ == "__main__":
    unittest.main()
