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


if __name__ == "__main__":
    unittest.main()
