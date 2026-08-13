"""Pure tests: AI accept floor, hard block, nuclear placate, propose spec, live hooks."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from trade_ai_product import (  # noqa: E402
    ai_accept_decision,
    build_trade_ai_primary_command_product,
    placate_delta_from_matchup,
    primary_command_dead_audit,
    propose_resource_swap_spec,
)


class TestTradeAI(unittest.TestCase):
    def test_fair_accept_and_poor_refuse(self):
        fair = ai_accept_decision(1.0, accept_floor=0.95)
        self.assertEqual(fair["decision"], "accept")
        poor = ai_accept_decision(0.7, accept_floor=0.95)
        self.assertEqual(poor["decision"], "refuse")
        self.assertEqual(poor["reason"], "below_floor")

    def test_hard_block(self):
        d = ai_accept_decision(2.0, accept_floor=0.75, hard_block=True)
        self.assertEqual(d["decision"], "refuse")
        self.assertEqual(d["reason"], "hard_block")

    def test_nuclear_placate_lowers_floor(self):
        pd = placate_delta_from_matchup(hopeless=True, nuclear_asymmetry=True)
        self.assertLess(pd, -0.2)
        # Score below normal refuse_below (0.85) but above placated floor
        d = ai_accept_decision(0.80, accept_floor=0.95, placate_delta=pd)
        self.assertEqual(d["decision"], "accept")
        self.assertTrue(d["placate"] or d["threshold"] < 0.85)
        # Same score without placate refuses at neutral floor 0.95
        d2 = ai_accept_decision(0.80, accept_floor=0.95, placate_delta=0.0)
        self.assertEqual(d2["decision"], "refuse")

    def test_propose_spec(self):
        p = propose_resource_swap_spec("ger", "fra", "steel", 40, "fuel", 30)
        self.assertEqual(p["from_tag"], "GER")
        self.assertEqual(p["to_tag"], "FRA")
        self.assertEqual(p["kind"], "ai_monthly_resource_swap")

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_trade_ai_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        self.assertTrue(p["propose_ok"])
        self.assertTrue(p["accept_ok"])
        self.assertTrue(p["refuse_ok"])
        self.assertTrue(p["placate_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_trade_ai_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("trade_ai_primary_live=1", sl)
        tm = (ROOT / "scripts" / "national" / "TradeManager.gd").read_text(encoding="utf-8")
        self.assertIn("func ai_decide_accept", tm)
        self.assertIn("func process_monthly_ai_trade", tm)


if __name__ == "__main__":
    unittest.main()
