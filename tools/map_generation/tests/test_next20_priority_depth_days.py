#!/usr/bin/env python3
"""Gates: next-20 priority depth day packages (10) + GIS×753 + live GD wiring."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next20_priority_depth import (  # noqa: E402
    PRIORITY_DAY_IDS,
    order_panel_ux_day,
    multi_phase_combat_ui_day,
    fleet_ai_ops_day,
    hh_agenda_package_day,
    agent_campaign_depth_day,
    industry_economy_day,
    save_slot_browser_day,
    basing_logistics_day,
    assault_follow_on_day,
    joint_ops_loop_day,
    close_next20_priority_depth_loop,
    priority_depth_integrity,
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

DAY_FUNCS = [
    order_panel_ux_day,
    multi_phase_combat_ui_day,
    fleet_ai_ops_day,
    hh_agenda_package_day,
    agent_campaign_depth_day,
    industry_economy_day,
    save_slot_browser_day,
    basing_logistics_day,
    assault_follow_on_day,
    joint_ops_loop_day,
]


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_ten_ids(self) -> None:
        self.assertEqual(len(PRIORITY_DAY_IDS), 10)
        self.assertEqual(len(DAY_FUNCS), 10)

    def test_each_nonempty_queue(self) -> None:
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"), msg=fn.__name__)
                self.assertTrue(str(day.get("summary", "")).strip(), msg=fn.__name__)
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1, msg=fn.__name__)
                aid = str((day.get("actions") or [{}])[0].get("action_id", ""))
                self.assertIn(aid, PRIORITY_DAY_IDS, msg="%s aid %s" % (fn.__name__, aid))

    def test_hh_empty_trail_without_seed(self) -> None:
        empty = hh_agenda_package_day(trail=[], seed_if_empty=False)
        self.assertTrue(empty.get("empty"))

    def test_combat_ui_wx(self) -> None:
        clear = multi_phase_combat_ui_day(
            weather={"precip_intensity": 0.0, "visibility": 1.0},
            attacker_supply=0.9,
        )
        foul = multi_phase_combat_ui_day(
            weather={"precip_intensity": 0.9, "visibility": 0.3},
            attacker_supply=0.5,
        )
        self.assertFalse(clear.get("empty"))
        self.assertFalse(foul.get("empty"))

    def test_joint_compose(self) -> None:
        day = joint_ops_loop_day()
        self.assertFalse(day.get("empty"))
        self.assertIn("basing", day)
        self.assertIn("follow", day)

    def test_close_loop(self) -> None:
        loop = close_next20_priority_depth_loop()
        self.assertFalse(loop.get("empty"))
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 10)
        self.assertTrue(priority_depth_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")

        for aid in PRIORITY_DAY_IDS:
            self.assertIn("func %s" % aid, fmt, msg="MPF missing %s" % aid)
            self.assertIn(aid, gd, msg="GameData missing %s" % aid)
            self.assertIn(aid, panel, msg="panel missing %s" % aid)

        for name in (
            "order_panel_ux_day_live",
            "multi_phase_combat_ui_day_for_province",
            "fleet_ai_ops_day_for_tag",
            "hh_agenda_package_day_live",
            "agent_campaign_depth_day_live",
            "industry_economy_day_for_province",
            "save_slot_browser_day_live",
            "basing_logistics_day_for_province",
            "assault_follow_on_day_for_province",
            "joint_ops_loop_day_for_province",
        ):
            self.assertIn("func %s" % name, mm, msg="MM missing %s" % name)

        for name in (
            "apply_order_panel_ux_day",
            "apply_multi_phase_combat_ui_day",
            "apply_fleet_ai_ops_day",
            "apply_hh_agenda_package_day",
            "apply_agent_campaign_depth_day",
            "apply_industry_economy_day",
            "apply_save_slot_browser_day",
            "apply_basing_logistics_day",
            "apply_assault_follow_on_day",
            "apply_joint_ops_loop_day",
        ):
            self.assertIn("func %s" % name, gd, msg="GD apply missing %s" % name)

        self.assertIn("fleet_ai_ops_day", pi)
        self.assertIn("industry_economy_day", pi)
        self.assertIn("joint_ops_loop_day", pi)

        self.assertIn("test_next20_priority_depth_days.py", CI.read_text(encoding="utf-8"))

        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "order panel ux day",
                "multi-phase combat ui day",
                "fleet ai ops day",
                "hh agenda package day",
                "agent campaign depth day",
                "industry economy day",
                "save slot browser day",
                "basing logistics day",
                "assault follow-on day",
                "joint ops loop day",
                "next-20 priority",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
