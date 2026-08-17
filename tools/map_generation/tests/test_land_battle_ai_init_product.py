#!/usr/bin/env python3
"""Gates: budgeted AI start_land_battle on live borders."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_battle_ai_init_product import (  # noqa: E402
    HARD_MAX_STARTS_PER_DAY,
    build_land_battle_ai_init_product,
    land_battle_ai_init_integrity,
    personality_aggression,
    plan_ai_land_battle_day,
    should_initiate,
)


class TestLandBattleAiInitProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_land_battle_ai_init_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("killswitch"), "EOA_AI_LAND_BATTLES=0")

    def test_integrity(self) -> None:
        g = land_battle_ai_init_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_ger_aggression_outranks_fra(self) -> None:
        self.assertGreater(personality_aggression("GER"), personality_aggression("FRA"))

    def test_day_budget(self) -> None:
        self.assertEqual(HARD_MAX_STARTS_PER_DAY, 1)
        plan = plan_ai_land_battle_day(
            [
                {
                    "tag": "GER",
                    "from_id": 1,
                    "to_id": 2,
                    "defender_tag": "FRA",
                    "has_formation": True,
                    "defender_power": 70.0,
                },
                {
                    "tag": "SOV",
                    "from_id": 3,
                    "to_id": 4,
                    "defender_tag": "POL",
                    "has_formation": True,
                    "defender_power": 55.0,
                },
            ],
            player_tag="USA",
        )
        self.assertEqual(int(plan.get("started_n") or 0), 1)
        self.assertEqual(plan.get("live_api"), "start_land_battle")

    def test_player_hex_is_not_started_by_player(self) -> None:
        plan = plan_ai_land_battle_day(
            [
                {
                    "tag": "GER",
                    "from_id": 1,
                    "to_id": 2,
                    "defender_tag": "FRA",
                    "has_formation": True,
                    "defender_power": 70.0,
                }
            ],
            player_tag="GER",
        )
        self.assertEqual(int(plan.get("started_n") or 0), 0)

    def test_should_initiate_needs_formation(self) -> None:
        self.assertFalse(
            should_initiate(
                {"tag": "GER", "defender_tag": "FRA", "has_formation": False, "score": 20.0},
                player_tag="USA",
            )
        )


if __name__ == "__main__":
    unittest.main()
