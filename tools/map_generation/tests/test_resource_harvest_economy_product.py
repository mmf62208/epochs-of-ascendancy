"""Pure tests for resource harvest economy (plants, tech, fissiles gate)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LIB = ROOT / "tools" / "map_generation" / "lib"
sys.path.insert(0, str(LIB))

from resource_harvest_economy_product import (  # noqa: E402
    build_resource_harvest_primary_command_product,
    compute_province_daily_income,
    factory_rules_has_plants,
    get_major_resources,
    is_major_visible,
    list_energy_plant_types,
    list_resource_plant_types,
    load_harvest_rules,
    primary_command_dead_audit,
    resource_tech_tree_ok,
    scenario_harvest_pair,
)


class TestResourceHarvestEconomy(unittest.TestCase):
    def test_harvest_rules_present(self):
        h = load_harvest_rules()
        self.assertEqual(h.get("model"), "auto_harvest_province_to_majors")
        self.assertIn("source_to_major", h)
        self.assertIn("energy_plant_types", h)
        self.assertIn("resource_plant_types", h)
        self.assertGreaterEqual(len(list_energy_plant_types(h)), 5)
        self.assertGreaterEqual(len(list_resource_plant_types(h)), 5)

    def test_majors_eight(self):
        majors = get_major_resources()
        for m in ("steel", "aluminum", "energy", "fuel", "rubber", "electronics", "specials", "fissiles"):
            self.assertIn(m, majors)

    def test_fissiles_visibility_gated(self):
        self.assertFalse(is_major_visible("fissiles", {}))
        self.assertTrue(is_major_visible("fissiles", {"rule_flags": ["nuclear_fuel"]}))
        self.assertTrue(is_major_visible("steel", {}))
        self.assertFalse(is_major_visible("helium3", {}))
        self.assertTrue(is_major_visible("helium3", {"rule_flags": ["fusion_power_industry"]}))

    def test_plants_boost_energy(self):
        bare, plants, tech = scenario_harvest_pair()
        self.assertGreater(float(plants.get("energy", 0)), float(bare.get("energy", 0)))
        self.assertGreater(float(plants.get("steel", 0)), float(bare.get("steel", 0)))
        self.assertGreater(float(tech.get("rubber", 0)), float(plants.get("rubber", 0)))
        self.assertIn("fissiles", tech)
        self.assertNotIn("fissiles", bare)

    def test_plastics_tech_bonus(self):
        res = {"rubber": 100.0, "semiconductors": 50.0}
        bare = compute_province_daily_income(res, plants=[], unlocks={})
        with_p = compute_province_daily_income(
            res, plants=[], unlocks={"rule_flags": ["plastics_industry"]}
        )
        self.assertGreater(float(with_p.get("rubber", 0)), float(bare.get("rubber", 0)))
        self.assertGreater(float(with_p.get("electronics", 0)), float(bare.get("electronics", 0)))

    def test_synthetic_fuel_conversion(self):
        res = {"coal": 300.0}
        plants = [{"factory_type": "coal_plant", "size_tier": 2}]
        no_sf = compute_province_daily_income(res, plants=plants, unlocks={})
        with_sf = compute_province_daily_income(
            res, plants=plants, unlocks={"rule_flags": ["synthetic_fuel"]}
        )
        self.assertGreater(float(with_sf.get("fuel", 0)), float(no_sf.get("fuel", 0)))

    def test_factory_rules_and_tech_tree(self):
        self.assertTrue(factory_rules_has_plants())
        tree = resource_tech_tree_ok()
        self.assertTrue(tree["ok"], msg=str(tree))

    def test_primary_product_and_audit(self):
        audit = primary_command_dead_audit()
        self.assertTrue(audit["ok"])
        self.assertEqual(audit["dead_n"], 0)
        p = build_resource_harvest_primary_command_product(province_id=1)
        self.assertFalse(p["empty"])
        self.assertTrue(p["plants_matter"])
        self.assertTrue(p["tech_matters"])
        self.assertTrue(p["fissiles_gated"])
        self.assertTrue(p["all_majors_ok"])
        self.assertEqual(len(p["steps"]), 5)
        for step in p["steps"]:
            self.assertTrue(str(step["live_api"]).startswith("apply_resource_harvest_"))

    def test_gamedata_hooks_exist(self):
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_resource_harvest_primary_live", gd)
        for api in (
            "apply_resource_harvest_catalog_live",
            "apply_resource_harvest_auto_live",
            "apply_resource_harvest_plants_live",
            "apply_resource_harvest_tech_live",
            "apply_resource_harvest_close_live",
        ):
            self.assertIn("func %s" % api, gd)

    def test_scenario_loader_evidence(self):
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("resource_harvest_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
