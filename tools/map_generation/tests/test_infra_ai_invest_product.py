#!/usr/bin/env python3
"""Gates: budgeted AI infra invest + days_remaining tick + save roundtrip."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from infra_ai_invest_product import (  # noqa: E402
    HARD_MAX_STARTS_PER_DAY,
    INFRA_LEVEL_MAX,
    SAVE_KEYS,
    apply_active_projects,
    build_infra_ai_invest_product,
    infra_ai_invest_integrity,
    personality_invest_weight,
    plan_ai_infra_invest_day,
    roundtrip_active_projects,
    serialize_active_projects,
    should_ai_invest,
    start_project_from_pick,
    tick_active_projects,
)


def _fixture() -> list:
    return [
        {
            "pid": 10,
            "tag": "GER",
            "infra": 2,
            "near_capital": True,
            "on_live_border": False,
        },
        {
            "pid": 11,
            "tag": "GER",
            "infra": 9,
            "near_capital": False,
            "on_live_border": True,
        },
        {
            "pid": 20,
            "tag": "FRA",
            "infra": 3,
            "near_capital": True,
            "on_live_border": True,
        },
        {
            "pid": 30,
            "tag": "SOV",
            "infra": 1,
            "near_capital": True,
            "on_live_border": False,
        },
        {
            "pid": 40,
            "tag": "USA",
            "infra": 2,
            "near_capital": True,
            "on_live_border": False,
        },
    ]


class TestInfraAiInvestProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_infra_ai_invest_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("killswitch"), "EOA_AI_INFRA=0")

    def test_integrity(self) -> None:
        g = infra_ai_invest_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_day_budget_one(self) -> None:
        self.assertEqual(HARD_MAX_STARTS_PER_DAY, 1)
        plan = plan_ai_infra_invest_day(_fixture(), player_tag="USA")
        self.assertEqual(int(plan.get("started_n") or 0), 1)
        self.assertEqual(plan.get("max_starts"), 1)
        self.assertEqual(plan.get("live_api"), "try_start_infrastructure_investment")

    def test_skip_player_tag(self) -> None:
        plan = plan_ai_infra_invest_day(_fixture(), player_tag="GER")
        self.assertGreaterEqual(int(plan.get("started_n") or 0), 1)
        for pick in plan.get("picks") or []:
            self.assertNotEqual(pick.get("tag"), "GER")

    def test_prefer_low_infra_near_capital_or_border(self) -> None:
        ger_land = [p for p in _fixture() if p["tag"] == "GER"]
        plan = plan_ai_infra_invest_day(ger_land, player_tag="USA")
        self.assertEqual(int(plan.get("started_n") or 0), 1)
        pick = plan["picks"][0]
        # GER capital infra 2 beats GER border infra 9.
        self.assertEqual(pick["tag"], "GER")
        self.assertEqual(int(pick["pid"]), 10)
        self.assertTrue(pick.get("near_capital") or pick.get("on_live_border"))

    def test_tick_completes_and_bumps(self) -> None:
        proj = start_project_from_pick(
            {"pid": 10, "tag": "GER", "infra": 4, "days_remaining": 3}
        )
        mid = tick_active_projects({10: proj}, infra_levels={10: 4}, days=1)
        self.assertEqual(int(mid.get("completed_n") or 0), 0)
        left = (mid.get("active_projects") or {}).get(10, {}).get("days_remaining")
        self.assertEqual(int(left), 2)

        done = tick_active_projects(
            mid.get("active_projects") or {},
            infra_levels=mid.get("infra_levels") or {10: 4},
            days=2,
        )
        self.assertEqual(int(done.get("completed_n") or 0), 1)
        self.assertEqual(int((done.get("infra_levels") or {}).get(10, 0)), 5)
        self.assertNotIn(10, done.get("active_projects") or {})

    def test_tick_clamps_infra_level(self) -> None:
        proj = start_project_from_pick(
            {"pid": 1, "tag": "GER", "infra": INFRA_LEVEL_MAX, "days_remaining": 1}
        )
        done = tick_active_projects({1: proj}, infra_levels={1: INFRA_LEVEL_MAX}, days=1)
        self.assertEqual(
            int((done.get("infra_levels") or {}).get(1, -1)), INFRA_LEVEL_MAX
        )

    def test_roundtrip_same_keys(self) -> None:
        proj = start_project_from_pick(
            {"pid": 710173, "tag": "FRA", "infra": 3, "days_remaining": 9}
        )
        rt = roundtrip_active_projects({710173: proj})
        self.assertTrue(rt.get("ok"), msg=rt)
        self.assertTrue(rt.get("same_keys"), msg=rt)
        restored = rt.get("restored") or {}
        row = restored.get(710173) or restored.get("710173") or {}
        for key in SAVE_KEYS:
            self.assertIn(key, row)
        self.assertEqual(int(row["pid"]), 710173)
        self.assertEqual(row["tag"], "FRA")
        self.assertEqual(row["kind"], "infrastructure")
        self.assertEqual(int(row["days_remaining"]), 9)

        blob = serialize_active_projects({710173: proj})
        applied = apply_active_projects(blob)
        again = serialize_active_projects(applied.get("active_projects") or {})
        self.assertEqual(
            blob["active_projects"]["710173"]["days_remaining"],
            again["active_projects"]["710173"]["days_remaining"],
        )

    def test_personality_ger_sov_and_fra(self) -> None:
        self.assertGreaterEqual(personality_invest_weight("GER"), personality_invest_weight("FRA"))
        self.assertGreaterEqual(personality_invest_weight("SOV"), 0.70)
        self.assertTrue(should_ai_invest("FRA", "GER"))
        self.assertTrue(should_ai_invest("GER", "USA"))
        self.assertFalse(should_ai_invest("GER", "GER"))
        fra = plan_ai_infra_invest_day(
            [p for p in _fixture() if p["tag"] == "FRA"],
            player_tag="GER",
        )
        self.assertEqual(int(fra.get("started_n") or 0), 1)
        self.assertEqual(fra["picks"][0]["tag"], "FRA")


if __name__ == "__main__":
    unittest.main()
