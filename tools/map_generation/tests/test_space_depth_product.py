"""Pure tests: multi-site Sol, loft staging, space power threat, independence, spotting."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from space_depth_product import (  # noqa: E402
    build_space_depth_primary_command_product,
    primary_command_dead_audit,
)
from space_layer_product import (  # noqa: E402
    asteroid_caps,
    compute_space_power_index,
    independence_years_to_breakaway,
    loft_cost_mult,
    multi_site_sol_ok,
    spotting_detect_chance,
)


class TestSpaceDepth(unittest.TestCase):
    def test_multi_site_sol(self):
        s = multi_site_sol_ok()
        self.assertTrue(s["ok"])
        self.assertGreaterEqual(s["luna_sites"], 6)
        self.assertGreaterEqual(s["mars_sites"], 8)
        self.assertGreaterEqual(s["ceres_sites"], 4)

    def test_asteroid_size_caps(self):
        tiny = asteroid_caps("tiny")
        dwarf = asteroid_caps("dwarf")
        self.assertLess(tiny["max_pop"], dwarf["max_pop"])
        self.assertLess(tiny["max_building_slots"], dwarf["max_building_slots"])

    def test_staging_and_power(self):
        self.assertLess(loft_cost_mult(via_luna=True), loft_cost_mult())
        weak = compute_space_power_index({"fleet_strength": 2, "orbital_defenses": 5})
        strong = compute_space_power_index({
            "fleet_strength": 50, "bombardment_capable_ships": 5, "orbital_weapons": 2,
            "orbital_defenses": 0, "stations": 3,
        })
        self.assertTrue(strong["bombardment_threat"])
        self.assertTrue(strong["undefended_surface_penalty"])
        self.assertGreater(strong["effective_space_threat"], weak["space_power_index"])

    def test_independence_generation(self):
        raw = independence_years_to_breakaway(40, False)
        mit = independence_years_to_breakaway(40, True)
        self.assertGreaterEqual(raw["generation_years"], 20)
        self.assertLess(mit["autonomy_after_neglect"], raw["autonomy_after_neglect"])

    def test_spotting_range(self):
        near = spotting_detect_chance(0.2, True, True, False)
        far = spotting_detect_chance(4.0, True, False, True)
        self.assertGreater(near, far)

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_space_depth_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_space_depth_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("space_depth_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
