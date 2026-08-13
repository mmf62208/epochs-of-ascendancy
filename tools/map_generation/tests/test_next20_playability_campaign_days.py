#!/usr/bin/env python3
"""Gates: next-300 playability campaign (20) + GIS + composed GD wiring + panel body."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next300_playability_campaign import (  # noqa: E402
    PLAYABILITY_CAMPAIGN_DAY_IDS,
    DAY_FUNCS,
    close_next300_playability_campaign_loop,
    playability_campaign_integrity,
    air_ops_sortie_depth_day,
    focus_pick_depth_day,
    order_execute_session_day,
    play_session_campaign_close_day,
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
    "air_ops_sortie_depth_day",
    "air_forecast_planning_depth_day",
    "convoy_escort_campaign_depth_day",
    "air_land_campaign_depth_day",
    "air_convoy_campaign_close_day",
    "focus_pick_depth_day",
    "focus_order_path_day",
    "focus_war_path_depth_day",
    "focus_intel_leader_close_day",
    "order_execute_session_day",
    "campaign_decision_session_day",
    "theater_ai_session_joint_day",
    "play_session_campaign_close_day",
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
        self.assertEqual(len(PLAYABILITY_CAMPAIGN_DAY_IDS), 20)
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
        a = air_ops_sortie_depth_day()
        self.assertIn("air", a)
        self.assertGreater(float(a.get("air_score", a.get("score", 0))), 0.1)
        f = focus_pick_depth_day()
        self.assertIn("picks", f)
        o = order_execute_session_day()
        self.assertIn("execute", o)
        c = play_session_campaign_close_day()
        self.assertTrue(c.get("ok") or c.get("gates"))

    def test_close(self):
        loop = close_next300_playability_campaign_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(playability_campaign_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find(
            "Composes existing GD theme helpers (air/convoy / focus-intel-leader / session)"
        )
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in (
            "air_ops_day_package",
            "air_ops_package",
            "weather_forecast_planning_day",
            "air_sortie_weather_readiness",
            "convoy_package_day",
            "air_land_campaign_day",
            "air_front_readiness_day",
            "rank_focus_picks",
            "focus_pick_day",
            "focus_order_path",
            "focus_war_path_day",
            "counterintel_board_ops_day",
            "order_execute_day",
            "next_day_feedback",
            "campaign_decision_day",
            "theater_command_product",
            "strategic_ai_daily_campaign_product",
            "force_readiness_day",
            "fleet_multi_day_autonomy_product",
            "war_economy_day_package",
        ):
            self.assertIn(h, sec, msg=h)
        body = sec[
            sec.find("static func air_ops_sortie_depth_day") : sec.find(
                "static func air_ops_sortie_depth_day"
            )
            + 700
        ]
        self.assertIn("air_ops_day_package", body)
        self.assertNotIn("var score := 0.55", body)
        for aid in PLAYABILITY_CAMPAIGN_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next300_live_day", mm)
        self.assertIn("air_score", mm)
        self.assertIn("focus_score", mm)
        self.assertIn("session_score", mm)

    def test_wiring(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gdt = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        for aid in PLAYABILITY_CAMPAIGN_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gdt)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gdt)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
            self.assertIn(aid, pi)
        self.assertIn("func _rebuild_playability_campaign_section", panel)
        self.assertIn("— Next-300 playability campaign (20) —", panel)
        self.assertIn("format_play_session_campaign_close_day_plain", panel)
        self.assertGreaterEqual(panel.count("_rebuild_playability_campaign_section"), 2)
        self.assertIn("test_next20_playability_campaign_days.py", CI.read_text(encoding="utf-8"))
        labels = [
            "air ops sortie depth day",
            "air forecast planning depth day",
            "air sortie weather gate day",
            "convoy escort campaign depth day",
            "air land campaign depth day",
            "air front readiness depth day",
            "air convoy campaign close day",
            "focus pick depth day",
            "focus order path day",
            "focus war path depth day",
            "war path urgency depth day",
            "intel counter depth campaign day",
            "leader campaign assign day",
            "focus intel leader close day",
            "order execute session day",
            "next day feedback session day",
            "campaign decision session day",
            "theater ai session joint day",
            "force readiness session day",
            "play session campaign close day",
            "next-300 playability",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
