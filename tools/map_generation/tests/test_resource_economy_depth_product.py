"""Pure tests for resource economy depth (food cohesion, combat rel, plants, fuel)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from resource_economy_depth_product import (  # noqa: E402
    build_resource_economy_depth_primary_command_product,
    combat_reliability_from_production,
    compute_food_cohesion_delta,
    fuel_ops_burn_rate,
    jets_burn_more_than_trucks,
    primary_command_dead_audit,
    recommend_plant_for_resources,
)


class TestResourceEconomyDepth(unittest.TestCase):
    def test_food_cohesion_surplus_and_starve(self):
        sur = compute_food_cohesion_delta(50.0, 100.0)
        starve = compute_food_cohesion_delta(0.0, 1.0)
        self.assertGreater(int(sur["cohesion_delta"]), 0)
        self.assertLess(int(starve["cohesion_delta"]), 0)

    def test_combat_reliability_soft_floor(self):
        full = combat_reliability_from_production(1.0)
        short = combat_reliability_from_production(0.55)
        self.assertAlmostEqual(full, 1.0)
        self.assertGreaterEqual(short, 0.72)
        self.assertLess(short, full)

    def test_jets_burn_more_than_trucks(self):
        self.assertTrue(jets_burn_more_than_trucks())
        self.assertGreater(fuel_ops_burn_rate("rocket"), fuel_ops_burn_rate("jet"))

    def test_plant_recommend_coal(self):
        rec = recommend_plant_for_resources({"coal": 200.0, "iron": 50.0})
        self.assertEqual(rec.get("plant_type"), "coal_plant")
        self.assertGreaterEqual(int(rec.get("size_tier", 0)), 1)

    def test_enrichment_requires_unlock(self):
        bare = recommend_plant_for_resources({"uranium": 100.0}, {})
        self.assertEqual(bare, {})
        unlocked = recommend_plant_for_resources(
            {"uranium": 100.0}, {"rule_flags": ["nuclear_fuel"]}
        )
        self.assertEqual(unlocked.get("plant_type"), "enrichment_plant")

    def test_primary_product(self):
        audit = primary_command_dead_audit()
        self.assertTrue(audit["ok"])
        p = build_resource_economy_depth_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        self.assertTrue(p["food_ok"])
        self.assertTrue(p["combat_ok"])
        self.assertTrue(p["plants_ok"])
        self.assertTrue(p["fuel_ok"])
        self.assertEqual(len(p["steps"]), 5)

    def test_gamedata_and_scenario_loader_hooks(self):
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_resource_economy_depth_primary_live", gd)
        for api in (
            "apply_resource_economy_depth_catalog_live",
            "apply_resource_economy_depth_food_live",
            "apply_resource_economy_depth_combat_live",
            "apply_resource_economy_depth_plants_live",
            "apply_resource_economy_depth_close_live",
        ):
            self.assertIn("func %s" % api, gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("resource_economy_depth_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
