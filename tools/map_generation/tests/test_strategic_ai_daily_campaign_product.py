#!/usr/bin/env python3
"""Gates: strategic AI daily campaign product (major #11 / deferred AI day tick)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from strategic_ai_daily_campaign_product import (  # noqa: E402
    PRODUCT_STEPS,
    budget_ai_day_actions,
    build_strategic_ai_daily_campaign_product,
    close_strategic_ai_daily_campaign_product_loop,
    execute_strategic_ai_daily_step,
    recommend_daily_ai_step,
    strategic_ai_daily_campaign_integrity,
)
from multi_faction_strategic_ai_product import build_multi_faction_strategic_ai_product  # noqa: E402
from gis_coastline_ingest import load_geometry_payload  # noqa: E402

GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"
WF = ROOT / "data" / "provinces_world_full"


class TestGis(unittest.TestCase):
    def test_ne_full_or_pilot_floor(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(
            1
            for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_daily_product_board_and_budget(self):
        p = build_strategic_ai_daily_campaign_product(player_tag="GER", max_ai_actions=4)
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("faction_count", 0)), 5)
        # Player GER skipped from AI day budget
        self.assertEqual(str(p.get("player_tag")), "GER")
        self.assertGreaterEqual(int(p.get("budget_count", 0)), 2)
        self.assertLessEqual(int(p.get("budget_count", 0)), 4)
        tags = [str(x.get("faction", "")) for x in (p.get("budget") or {}).get("queue") or []]
        self.assertNotIn("GER", tags)
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 3)
        for s in PRODUCT_STEPS:
            e = execute_strategic_ai_daily_step(s, 1, player_tag="GER")
            self.assertTrue(e.get("ok"), msg=s)
        self.assertTrue(strategic_ai_daily_campaign_integrity().get("ok"))
        self.assertTrue(close_strategic_ai_daily_campaign_product_loop().get("ok"))

    def test_player_skip_and_recommend(self):
        board = build_multi_faction_strategic_ai_product()
        factions = board.get("factions") or []
        with_player = budget_ai_day_actions(factions, player_tag="ENG", max_actions=7)
        no_skip = budget_ai_day_actions(factions, player_tag="", max_actions=7)
        self.assertGreaterEqual(int(no_skip.get("selected_count", 0)), int(with_player.get("selected_count", 0)))
        for item in with_player.get("queue") or []:
            self.assertNotEqual(str(item.get("faction", "")).upper(), "ENG")
        rec_empty = recommend_daily_ai_step(0)
        self.assertEqual(rec_empty.get("step"), "board")
        rec_ready = recommend_daily_ai_step(7, budget_count=3, apply_ready=True)
        self.assertEqual(rec_ready.get("step"), "apply_ai")


class TestLive(unittest.TestCase):
    def test_composition_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("static func strategic_ai_daily_campaign_product(", fmt)
        self.assertIn("static func budget_ai_day_actions(", fmt)
        self.assertIn("static func execute_strategic_ai_daily_step(", fmt)
        start = fmt.find("static func strategic_ai_daily_campaign_product(")
        body = fmt[start : start + 4500]
        for h in (
            "multi_faction_strategic_ai_product",
            "budget_ai_day_actions",
            "recommend_strategic_ai_daily_step",
            "strategic_ai_daily_board",
        ):
            self.assertIn(h, body, msg=h)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func strategic_ai_daily_campaign_product_live", mm)
        self.assertIn("func apply_strategic_ai_daily_campaign_product", mm)
        self.assertIn("func apply_strategic_ai_daily_step_for_province", mm)
        self.assertIn("func apply_strategic_ai_daily_campaign_product", gd)
        self.assertIn("func apply_strategic_ai_daily_board", gd)
        self.assertIn("func apply_strategic_ai_daily_budget", gd)
        self.assertIn("func apply_strategic_ai_daily_apply", gd)
        self.assertIn("strategic_ai_daily", gd)
        self.assertIn("run_daily_theater_auto_tick_multi", gd)
        self.assertIn("Strategic AI daily campaign (major #11)", panel)
        self.assertIn("strategic_ai_daily_campaign_product_live", panel)
        self.assertIn("strategic_ai_daily_board", panel)
        self.assertIn("strategic_ai_daily_apply", panel)
        self.assertIn("build_strategic_ai_daily_campaign_product_chip_bbcode", pi)
        self.assertIn("strategic_ai_daily_campaign_product", fmt)
        self.assertIn("test_strategic_ai_daily_campaign_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "strategic ai daily campaign",
            "strategic ai daily board",
            "major #11",
            "strategic ai",
            "daily campaign",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
