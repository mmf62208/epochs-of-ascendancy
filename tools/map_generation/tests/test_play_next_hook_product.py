#!/usr/bin/env python3
"""Gates: play-strip / map Next hook."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from play_next_hook_product import (  # noqa: E402
    build_play_next_hook_product,
    capture_economy_sentence,
    rank_next_beat,
    recommend_from_hook,
)


class TestPlayNextHookProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_play_next_hook_product()
        self.assertTrue(p.get("ok"), msg=p)

    def test_recommend_from_hook(self) -> None:
        self.assertEqual(recommend_from_hook("Reinforcement arrives tomorrow"), "hold")
        self.assertEqual(recommend_from_hook("They break tomorrow"), "press")

    def test_rank_beats_idle(self) -> None:
        idle = rank_next_beat({})
        self.assertEqual(idle.get("action"), "unpause")
        train = rank_next_beat({"training": [{"fid": "u1", "days_left": 1}]})
        self.assertEqual(train.get("action"), "send_trained")
        self.assertEqual(train.get("source"), "organize")
        dry = rank_next_beat({"dry_fuel": [{"fid": "u2"}], "fuel_stock": 0, "oil_stock": 0})
        self.assertEqual(dry.get("action"), "refuel")
        war = rank_next_beat(
            {
                "has_open_battle": True,
                "battle_hook": "They break tomorrow",
                "training": [{"fid": "u1", "days_left": 1}],
            }
        )
        self.assertEqual(war.get("action"), "press")

    def test_capture_economy_sentence(self) -> None:
        occupied = capture_economy_sentence({"oil": 3.0}, 1936, "FRA", "GER")
        self.assertIn("oil", occupied.lower())
        self.assertIn("pumping", occupied)
        self.assertIn("0.65", occupied)
        own = capture_economy_sentence({"steel": 2.0}, 1936, "GER", "GER")
        self.assertIn("steel", own.lower())
        self.assertNotIn("0.65", own)
        self.assertEqual(capture_economy_sentence({}, 1936, "FRA", "GER"), "")
        hidden = capture_economy_sentence({"uranium": 2.0}, 1936, "FRA", "GER")
        self.assertEqual(hidden, "")
        eco = rank_next_beat(
            {
                "aar_economy": "Now pumping oil (occupied ×0.65).",
                "training": [{"fid": "u1", "days_left": 1}],
            }
        )
        self.assertEqual(eco.get("source"), "aar")
        self.assertIn("oil", str(eco.get("label", "")).lower())
        nxt = rank_next_beat(
            {
                "aar_next_pid": 710000,
                "aar_economy": "Now pumping oil (occupied ×0.65).",
                "aar_line": (
                    "Took Bas-Rhin · 1 day — Press Haguenau next? "
                    "Now pumping oil (occupied ×0.65)."
                ),
            }
        )
        self.assertEqual(nxt.get("action"), "next_hex")
        self.assertEqual(nxt.get("source"), "aar")
        self.assertIn("oil", str(nxt.get("hint", "")).lower())

    def test_completing_bars_rank(self) -> None:
        tech = rank_next_beat({"research_days_left": 1})
        self.assertEqual(tech.get("action"), "tech_done")
        self.assertEqual(tech.get("source"), "research")
        self.assertIn("research", str(tech.get("label", "")).lower())
        foc = rank_next_beat({"focus_days_left": 1})
        self.assertEqual(foc.get("action"), "focus_done")
        self.assertEqual(foc.get("source"), "focus")
        idle = rank_next_beat({"research_days_left": 5, "focus_days_left": 12})
        self.assertEqual(idle.get("source"), "idle")
        war = rank_next_beat(
            {
                "has_open_battle": True,
                "battle_hook": "They break tomorrow — Press",
                "research_days_left": 1,
                "focus_days_left": 1,
            }
        )
        self.assertEqual(war.get("action"), "press")
        short = rank_next_beat(
            {
                "steel_stock": 0.0,
                "has_vehicle": True,
                "research_days_left": 1,
            }
        )
        self.assertEqual(short.get("action"), "shortage")
        train = rank_next_beat(
            {
                "training": [{"fid": "u1", "days_left": 1}],
                "research_days_left": 1,
            }
        )
        self.assertEqual(train.get("action"), "send_trained")


if __name__ == "__main__":
    unittest.main()
