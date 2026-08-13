#!/usr/bin/env python3
"""Gates: next-290 full-game campaign pillars (20) + GIS + composed GD wiring + panel body."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next290_full_game_campaign import (  # noqa: E402
    FULL_GAME_CAMPAIGN_DAY_IDS,
    DAY_FUNCS,
    close_next290_full_game_campaign_loop,
    full_game_campaign_integrity,
    strategic_ai_urgency_board_day,
    designer_catalog_depth_day,
    theater_ai_command_joint_day,
    full_game_campaign_close_day,
)

WF = ROOT / "data" / "provinces_world_full"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"

LIVE = {
    "strategic_ai_doctrine_depth_day",
    "strategic_ai_urgency_board_day",
    "strategic_ai_budget_depth_day",
    "strategic_ai_campaign_close_day",
    "designer_catalog_depth_day",
    "designer_seed_production_day",
    "oob_horizon_joint_day",
    "designer_industry_close_day",
    "theater_ai_command_joint_day",
    "fleet_ai_campaign_depth_day",
    "agent_ai_campaign_depth_day",
    "combat_ai_phase_depth_day",
    "full_game_campaign_close_day",
}


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(
            1
            for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(FULL_GAME_CAMPAIGN_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)

    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(
                    str((day.get("actions") or [{}])[0].get("action_id", "")), fn.__name__
                )

    def test_theme_helpers_shipped(self):
        a = strategic_ai_urgency_board_day()
        self.assertIn("board", a)
        self.assertGreater(float(a.get("ai_score", a.get("score", 0))), 0.1)
        d = designer_catalog_depth_day()
        self.assertIn("designer", d)
        self.assertGreater(float(d.get("industry_score", d.get("score", 0))), 0.1)
        t = theater_ai_command_joint_day()
        self.assertIn("theater", t)
        c = full_game_campaign_close_day()
        self.assertTrue(c.get("ok") or c.get("gates"))

    def test_close(self):
        loop = close_next290_full_game_campaign_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(full_game_campaign_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find(
            "Composes existing GD theme helpers (strategic AI / designers / theater products)"
        )
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in (
            "plan_faction_ai",
            "faction_ai_doctrine",
            "multi_faction_strategic_ai_product",
            "budget_ai_day_actions",
            "strategic_ai_daily_campaign_product",
            "designer_suite_product",
            "execute_designer_suite_step",
            "recommend_designer_domain",
            "medium_tank_oob_product",
            "theater_command_product",
            "fleet_multi_day_autonomy_product",
            "agent_campaign_product",
            "multi_phase_combat_product",
            "save_browser_campaign_product",
        ):
            self.assertIn(h, sec, msg=h)
        body = sec[
            sec.find("static func strategic_ai_urgency_board_day") : sec.find(
                "static func strategic_ai_urgency_board_day"
            )
            + 900
        ]
        self.assertIn("multi_faction_strategic_ai_product", body)
        self.assertNotIn("var score := 0.55", body)
        des = sec[
            sec.find("static func designer_catalog_depth_day") : sec.find(
                "static func designer_catalog_depth_day"
            )
            + 700
        ]
        self.assertIn("designer_suite_product", des)
        for aid in FULL_GAME_CAMPAIGN_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next290_live_day", mm)
        self.assertIn("ai_score", mm)
        self.assertIn("industry_score", mm)
        self.assertIn("campaign_score", mm)

    def test_wiring(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gdt = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        for aid in FULL_GAME_CAMPAIGN_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gdt)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gdt)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
            self.assertIn(aid, pi)
        self.assertIn("func _rebuild_full_game_campaign_section", panel)
        self.assertIn("— Next-290 full-game campaign (20) —", panel)
        self.assertIn("format_full_game_campaign_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_full_game_campaign_section"), 2)
        self.assertNotIn("RetrowaveTheme.has_method(", panel)
        self.assertIn("test_next20_full_game_campaign_days.py", CI.read_text(encoding="utf-8"))
        labels = [
            "strategic ai doctrine depth day",
            "strategic ai urgency board day",
            "strategic ai player skip day",
            "strategic ai budget depth day",
            "strategic ai domain weight day",
            "strategic ai daily joint day",
            "strategic ai campaign close day",
            "designer catalog depth day",
            "designer seed production day",
            "designer domain balance day",
            "oob horizon joint day",
            "production line bootstrap day",
            "industry design joint day",
            "designer industry close day",
            "theater ai command joint day",
            "fleet ai campaign depth day",
            "agent ai campaign depth day",
            "combat ai phase depth day",
            "save session ai joint day",
            "full game campaign close day",
            "next-290 full-game",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
