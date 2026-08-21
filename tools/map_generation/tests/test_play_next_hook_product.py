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


if __name__ == "__main__":
    unittest.main()
