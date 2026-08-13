#!/usr/bin/env python3
"""Gates: interactive multi-AI day plan (budgeted non-player majors for F5 light sim)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from interactive_multi_ai_day_product import (  # noqa: E402
    DEFAULT_MAJOR_TAGS,
    DEFAULT_MAX_PRODUCTION,
    DEFAULT_MAX_SOFT_TICKS,
    HARD_MAX_PRODUCTION,
    build_interactive_multi_ai_day_product,
    build_interactive_multi_ai_day_queue,
    interactive_multi_ai_day_integrity,
    non_player_majors,
    personality_aggression,
    personality_rank_order,
    resolve_tag_scoped_apply_ops,
    round_robin_order,
    simulate_tag_stockpile_applies,
)

GD = ROOT / "scripts" / "autoload" / "GameData.gd"
TM = ROOT / "scripts" / "autoload" / "TimeManager.gd"


class TestInteractiveMultiAiDayProduct(unittest.TestCase):
    def test_non_player_majors_excludes_player(self) -> None:
        tags = non_player_majors(DEFAULT_MAJOR_TAGS, "USA")
        self.assertNotIn("USA", tags)
        self.assertIn("GER", tags)
        self.assertEqual(len(tags), len(DEFAULT_MAJOR_TAGS) - 1)

    def test_round_robin_rotates(self) -> None:
        cands = ["GER", "FRA", "ENG", "SOV"]
        o0 = round_robin_order(cands, 0)
        o1 = round_robin_order(cands, 1)
        self.assertEqual(o0[0], "GER")
        self.assertEqual(o1[0], "FRA")
        self.assertEqual(set(o0), set(cands))

    def test_queue_budget_and_player_skip(self) -> None:
        q = build_interactive_multi_ai_day_queue(
            DEFAULT_MAJOR_TAGS,
            "USA",
            day_index=0,
            max_production=3,
            max_soft_ticks=1,
            day_budget=4,
        )
        self.assertTrue(q.get("integrity_ok"), msg=q)
        self.assertTrue(q.get("ok"), msg=q)
        self.assertEqual(int(q.get("production_n") or 0), 3)
        self.assertEqual(int(q.get("soft_n") or 0), 1)
        self.assertLessEqual(len(q.get("queue") or []), 4)
        for item in q.get("queue") or []:
            if item.get("kind") == "production":
                self.assertNotEqual(item.get("tag"), "USA")
        self.assertIn("GER", q.get("prod_tags") or [])

    def test_hard_cap_four(self) -> None:
        q = build_interactive_multi_ai_day_queue(
            DEFAULT_MAJOR_TAGS,
            "USA",
            day_index=0,
            max_production=99,
            max_soft_ticks=1,
            day_budget=99,
        )
        self.assertLessEqual(int(q.get("production_n") or 0), HARD_MAX_PRODUCTION)
        self.assertTrue(q.get("integrity_ok"), msg=q)

    def test_empty_when_only_player(self) -> None:
        q = build_interactive_multi_ai_day_queue(
            ["USA"],
            "USA",
            day_index=0,
        )
        self.assertTrue(q.get("integrity_ok"), msg=q)
        self.assertTrue(q.get("empty"))
        self.assertEqual(int(q.get("production_n") or 0), 0)

    def test_product_and_integrity(self) -> None:
        p = build_interactive_multi_ai_day_product(day_index=2)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertIn("queue_integrity", p.get("pass") or [])
        self.assertEqual(int(p.get("defaults", {}).get("max_production") or 0), DEFAULT_MAX_PRODUCTION)
        self.assertEqual(int(p.get("defaults", {}).get("max_soft_ticks") or 0), DEFAULT_MAX_SOFT_TICKS)
        g = interactive_multi_ai_day_integrity(day_index=2)
        self.assertTrue(g.get("ok"), msg=g)
        self.assertEqual(g.get("killswitch"), "EOA_INTERACTIVE_MULTI_AI=0")

    def test_live_wiring(self) -> None:
        self.assertTrue(GD.is_file())
        self.assertTrue(TM.is_file())
        gd = GD.read_text(encoding="utf-8")
        tm = TM.read_text(encoding="utf-8")
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_interactive_multi_ai_day_live", gd)
        self.assertIn("EOA_INTERACTIVE_MULTI_AI", gd)
        self.assertIn("func apply_production_for_tag", gd)
        self.assertIn("func advance_days_for_country", pm)
        self.assertIn("apply_interactive_multi_ai_day_live", tm)
        self.assertIn("_should_run_interactive_multi_ai", tm)
        self.assertIn("EOA_INTERACTIVE_MULTI_AI", tm)
        # Must not re-enable full daily AI combat for interactive light sim
        self.assertIn("func _should_run_daily_ai_combat", tm)
        self.assertIn("is_interactive_light_sim", tm)
        # Year multi-AI campaign live path stays on GameData
        self.assertIn("func apply_year_multi_ai_campaign_live", gd)
        # Personality-weighted ordering on live path (this goal close)
        self.assertTrue(
            "aggression" in gd or "personality" in gd.lower(),
            msg="GameData interactive multi-AI must reference personality/aggression",
        )
        # Live multi-AI must call tag-scoped apply, not player apply_production
        live_idx = gd.find("func apply_interactive_multi_ai_day_live")
        self.assertGreaterEqual(live_idx, 0)
        live_body = gd[live_idx : live_idx + 4500]
        self.assertIn("apply_production_for_tag", live_body)
        import re

        self.assertIsNone(
            re.search(
                r'apply_order_panel_action\s*\(\s*["\']apply_production["\']',
                live_body,
            ),
            msg="interactive multi-AI must not call player-scoped apply_production",
        )

    def test_prod_tags_drive_tag_scoped_stock_sim(self) -> None:
        """Honest path: planned prod_tags → apply_ops → stock deltas on those tags only."""
        q = build_interactive_multi_ai_day_queue(
            ["FRA", "GER", "JAP", "ENG"],
            "USA",
            day_index=0,
            max_production=2,
            max_soft_ticks=0,
            day_budget=2,
            use_personality=True,
        )
        self.assertEqual(q.get("prod_tags"), ["GER", "JAP"])
        ops = resolve_tag_scoped_apply_ops(q.get("queue") or [])
        self.assertEqual(len(ops), 2)
        for op in ops:
            self.assertEqual(op.get("live_api"), "apply_production_for_tag")
            self.assertEqual(op.get("scoped_tag"), op.get("tag"))
            self.assertNotEqual(op.get("tag"), "USA")
        sim = simulate_tag_stockpile_applies(
            ops, stockpiles={"USA": 10, "GER": 0, "JAP": 0, "FRA": 0}, player_tag="USA"
        )
        self.assertTrue(sim.get("ok"), msg=sim)
        self.assertEqual(int(sim.get("player_delta", -999)), 0)
        self.assertEqual(int((sim.get("deltas") or {}).get("GER", 0)), 1)
        self.assertEqual(int((sim.get("deltas") or {}).get("JAP", 0)), 1)
        self.assertEqual(int((sim.get("deltas") or {}).get("FRA", 0)), 0)
        # Forbidden bare apply_production would bump player — prove detector works
        bad = simulate_tag_stockpile_applies(
            [{"live_api": "apply_production", "tag": "GER", "scoped_tag": "GER"}],
            stockpiles={"USA": 5, "GER": 0},
            player_tag="USA",
        )
        self.assertFalse(bad.get("ok"))
        self.assertEqual(int(bad.get("player_delta") or 0), 1)

    def test_personality_rank_prefers_aggressive(self) -> None:
        # GER 0.88 > JAP 0.75 > FRA 0.45 — day 0 should lead with GER among these
        ranked = personality_rank_order(["FRA", "GER", "JAP"], 0, use_personality=True)
        self.assertEqual(ranked[0], "GER")
        self.assertGreater(personality_aggression("GER"), personality_aggression("FRA"))
        # Day 0 queue with personality: GER should be in production batch when player is USA
        q = build_interactive_multi_ai_day_queue(
            ["FRA", "GER", "JAP", "ENG"],
            "USA",
            day_index=0,
            max_production=2,
            max_soft_ticks=0,
            day_budget=2,
            use_personality=True,
        )
        self.assertTrue(q.get("ok"), msg=q)
        self.assertEqual(q.get("prod_tags"), ["GER", "JAP"])
        self.assertTrue(q.get("use_personality"))
        # Queue items carry aggression for live telemetry
        first = (q.get("queue") or [{}])[0]
        self.assertIn("aggression", first)
        self.assertGreaterEqual(float(first.get("aggression") or 0), 0.8)


if __name__ == "__main__":
    unittest.main()
