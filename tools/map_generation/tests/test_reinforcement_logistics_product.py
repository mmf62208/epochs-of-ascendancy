"""Pure tests for reinforcement logistics RF0/RF1."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from reinforcement_logistics_product import (
    blend_manpower,
    blend_rearm,
    build_reinforcement_logistics_primary_command_product,
    era_band_for_year,
    experience_combat_mult,
    primary_command_dead_audit,
    transit_days,
)


class TestReinforcementLogistics(unittest.TestCase):
    def test_era_bands(self):
        self.assertEqual(era_band_for_year(1914), "rail_age")
        self.assertEqual(era_band_for_year(1942), "motor_air_dawn")
        self.assertEqual(era_band_for_year(1970), "airlift_age")
        self.assertEqual(era_band_for_year(2010), "network_drone")
        self.assertEqual(era_band_for_year(2080), "orbital_support")

    def test_transit_era_and_distance(self):
        slow = transit_days("rail", hops=3, distance_km=1200, year=1916)
        fast = transit_days("airlift", hops=2, distance_km=1200, year=2025, fuel=0.9)
        orbital = transit_days("orbital", hops=1, distance_km=1200, year=2080, fuel=0.9, electronics=0.9)
        self.assertGreater(slow, fast)
        self.assertGreater(fast, orbital)
        near = transit_days("rail", hops=1, distance_km=40, year=1939)
        far = transit_days("rail", hops=1, distance_km=1600, year=1939)
        self.assertGreater(far, near)

    def test_experience_asymmetry(self):
        vet = 85.0
        greens = blend_manpower(vet, 12.0, 0.5)
        rearm = blend_rearm(vet, 0.5, novelty=0.35)
        self.assertLess(greens, vet - 20)
        self.assertGreater(rearm, greens + 15)
        self.assertLess(experience_combat_mult(15), 0.9)
        self.assertGreater(experience_combat_mult(90), 1.1)

    def test_primary_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_reinforcement_logistics_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        self.assertTrue(p["time_ok"])
        self.assertTrue(p["exp_ok"])
        self.assertTrue(p["hub_ok"])
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_reinforcement_logistics_primary_live", gd)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("reinforcement_logistics_primary_live=1", sl)


if __name__ == "__main__":
    unittest.main()
