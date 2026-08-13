"""Pure tests: power matchup, nuclear, transit attribution, spy, discounts."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from trade_power_intel_product import (  # noqa: E402
    ai_placate_delta,
    attribution_plain,
    build_trade_power_intel_primary_command_product,
    compute_power_index,
    delivery_ratio,
    matchup,
    primary_command_dead_audit,
    relationship_discounts,
    spy_clarity,
)


class TestTradePowerIntel(unittest.TestCase):
    def test_nuclear_makes_hopeless_matchup(self):
        small = compute_power_index({"factories": 5, "steel": 80, "tech_flags": []})
        nuke = compute_power_index({
            "factories": 50, "steel": 3000, "fuel": 2000, "electronics": 500,
            "equipment_units": 800, "tech_flags": ["nuclear_fuel", "nuclear_warhead"],
            "fissiles_stock": 40,
        })
        self.assertTrue(nuke["nuclear_armed"])
        self.assertGreaterEqual(nuke["danger_multiplier"], 3.0)
        mu = matchup(small, nuke)
        self.assertTrue(mu["hopeless"])
        self.assertTrue(mu["nuclear_asymmetry"])
        self.assertLess(ai_placate_delta(mu), -0.1)

    def test_relationship_discounts(self):
        ally = relationship_discounts("ally_ready", True, 6)
        neut = relationship_discounts("neutral", False, 0)
        self.assertLess(ally["trade_suu_mult"], neut["trade_suu_mult"])
        self.assertTrue(ally["long_term"])

    def test_transit_attribution_and_ratio(self):
        p = attribution_plain("submarine", 99, "USA", "ENG")
        self.assertIn("Submarines in province 99", p)
        self.assertIn("USA", p)
        self.assertAlmostEqual(delivery_ratio(100, 50), 0.5)

    def test_spy_clarity(self):
        self.assertGreaterEqual(spy_clarity(True, True), 0.55)
        self.assertLess(spy_clarity(False, False), 0.5)

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_trade_power_intel_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_trade_power_intel_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("trade_power_intel_primary_live=1", sl)
        tm = (ROOT / "scripts" / "national" / "TradeManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_bilateral_transit_health", tm)
        self.assertIn("func spy_relation_and_trade_intel", tm)


if __name__ == "__main__":
    unittest.main()
