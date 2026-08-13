#!/usr/bin/env python3
"""Gates: play session campaign product (major #12)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from play_session_campaign_product import (  # noqa: E402
    PRODUCT_STEPS,
    build_play_session_campaign_product,
    close_play_session_campaign_product_loop,
    execute_play_session_step,
    play_session_campaign_integrity,
    recommend_play_session_step,
)
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
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(
            1
            for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product_three_steps(self):
        p = build_play_session_campaign_product(player_tag="GER")
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 3)
        self.assertIn((p.get("recommendation") or {}).get("step"), PRODUCT_STEPS)
        for s in PRODUCT_STEPS:
            e = execute_play_session_step(s, 1, player_tag="GER")
            self.assertTrue(e.get("ok"), msg=s)
        self.assertTrue(play_session_campaign_integrity().get("ok"))
        self.assertTrue(close_play_session_campaign_product_loop().get("ok"))

    def test_recommend_progression(self):
        r0 = recommend_play_session_step(brief_ready=False)
        self.assertEqual(r0.get("step"), "brief")
        r1 = recommend_play_session_step(brief_ready=True, execute_done=False)
        self.assertEqual(r1.get("step"), "execute")
        r2 = recommend_play_session_step(brief_ready=True, execute_done=True, resolve_ready=True)
        self.assertEqual(r2.get("step"), "resolve")


class TestLive(unittest.TestCase):
    def test_composition_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("static func play_session_campaign_product(", fmt)
        self.assertIn("static func execute_play_session_step(", fmt)
        start = fmt.find("static func play_session_campaign_product(")
        body = fmt[start : start + 5000]
        for h in (
            "theater_command_product",
            "order_execute_day",
            "strategic_ai_daily_campaign_product",
            "next_day_feedback",
            "campaign_decision_day",
        ):
            self.assertIn(h, body, msg=h)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func play_session_campaign_product_live", mm)
        self.assertIn("func apply_play_session_campaign_product", mm)
        self.assertIn("func apply_play_session_campaign_product", gd)
        self.assertIn("func apply_play_session_brief", gd)
        self.assertIn("func apply_play_session_resolve", gd)
        self.assertIn("Play session campaign (major #12)", panel)
        self.assertIn("play_session_campaign_product_live", panel)
        self.assertIn("play_session_brief", panel)
        self.assertIn("build_play_session_campaign_product_chip_bbcode", pi)
        self.assertIn("test_play_session_campaign_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "play session campaign",
            "play session brief",
            "play session execute",
            "major #12",
            "play session",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
