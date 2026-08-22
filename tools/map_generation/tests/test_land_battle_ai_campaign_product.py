#!/usr/bin/env python3
"""Gates: AI own-land march to a live border + one follow-on start after a win."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_battle_ai_campaign_product import (  # noqa: E402
    CHI_FRONT,
    GER_FRONT_STAGING,
    HARD_MAX_FOLLOW_ON,
    HARD_MAX_MARCHES_PER_DAY,
    HARD_MAX_STARTS_PER_DAY,
    JAP_FRONT,
    build_land_battle_ai_campaign_product,
    ger_rear_march_opp,
    land_battle_ai_campaign_integrity,
    plan_follow_on,
    plan_marches,
    score_march_to_front,
    should_enqueue_march,
    should_follow_on,
)


class TestLandBattleAiCampaignProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_land_battle_ai_campaign_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("killswitch"), "EOA_AI_LAND_BATTLES=0")
        self.assertEqual(p.get("policy"), "spare_march_to_front_plus_one_follow_on_start")
        self.assertIn("jap_chi_live_border", p.get("pass") or [])
        self.assertIn("harness_second_theater_owner", p.get("pass") or [])
        self.assertEqual(JAP_FRONT, 903981)
        self.assertEqual(CHI_FRONT, 902598)
        self.assertNotEqual(CHI_FRONT, 710739)

    def test_integrity(self) -> None:
        g = land_battle_ai_campaign_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_budgets_stay_one(self) -> None:
        self.assertEqual(HARD_MAX_MARCHES_PER_DAY, 1)
        self.assertEqual(HARD_MAX_FOLLOW_ON, 1)
        self.assertEqual(HARD_MAX_STARTS_PER_DAY, 1)

    def test_spare_ger_rear_marches_to_710173(self) -> None:
        plan = plan_marches([ger_rear_march_opp()], player_tag="USA")
        self.assertEqual(int(plan.get("marched_n") or 0), 1)
        self.assertEqual(int(plan["picks"][0]["dest_id"]), GER_FRONT_STAGING)
        self.assertEqual(plan.get("live_api"), "enqueue_own_land_march")
        ranked = score_march_to_front([ger_rear_march_opp()], player_tag="USA")
        self.assertEqual(int(ranked[0]["dest_id"]), 710173)

    def test_player_tag_never_marched(self) -> None:
        plan = plan_marches([ger_rear_march_opp()], player_tag="GER")
        self.assertEqual(int(plan.get("marched_n") or 0), 0)
        self.assertFalse(
            should_enqueue_march(ger_rear_march_opp(), player_tag="GER")
        )

    def test_follow_on_after_attacker_win(self) -> None:
        aar = {
            "winner": "attacker",
            "next_pid": 710740,
            "fid": "ger_1",
            "tag": "GER",
            "from_id": 710739,
        }
        self.assertTrue(should_follow_on(aar, player_tag="USA", expected_fid="ger_1"))
        plan = plan_follow_on(aar, player_tag="USA")
        self.assertEqual(int(plan.get("started_n") or 0), 1)
        self.assertEqual(int(plan["picks"][0]["to_id"]), 710740)
        self.assertEqual(plan["picks"][0]["formation_id"], "ger_1")
        self.assertEqual(plan.get("live_api"), "start_land_battle")

    def test_no_follow_on_on_defender_win(self) -> None:
        aar = {
            "winner": "defender",
            "next_pid": 710740,
            "fid": "ger_1",
            "tag": "GER",
            "from_id": 710173,
        }
        self.assertFalse(should_follow_on(aar, player_tag="USA"))
        plan = plan_follow_on(aar, player_tag="USA")
        self.assertEqual(int(plan.get("started_n") or 0), 0)


if __name__ == "__main__":
    unittest.main()
