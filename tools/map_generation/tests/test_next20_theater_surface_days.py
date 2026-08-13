#!/usr/bin/env python3
"""Gates: next-30 theater surface day packages (10) + GIS×753 + live GD wiring."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next30_theater_surface import (  # noqa: E402
    THEATER_SURFACE_DAY_IDS,
    war_cabinet_day,
    supply_campaign_day,
    force_supply_day,
    counter_ops_day,
    multi_province_live_day,
    order_queue_day,
    agent_ai_board_day,
    fleet_order_day,
    fleet_theater_posture_day,
    campaign_risk_day,
    close_next30_theater_surface_loop,
    theater_surface_integrity,
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
    war_cabinet_day,
    supply_campaign_day,
    force_supply_day,
    counter_ops_day,
    multi_province_live_day,
    order_queue_day,
    agent_ai_board_day,
    fleet_order_day,
    fleet_theater_posture_day,
    campaign_risk_day,
]


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_ten_ids(self) -> None:
        self.assertEqual(len(THEATER_SURFACE_DAY_IDS), 10)
        self.assertEqual(len(DAY_FUNCS), 10)

    def test_each_nonempty_queue(self) -> None:
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"), msg=fn.__name__)
                self.assertTrue(str(day.get("summary", "")).strip(), msg=fn.__name__)
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1, msg=fn.__name__)
                aid = str((day.get("actions") or [{}])[0].get("action_id", ""))
                self.assertIn(aid, THEATER_SURFACE_DAY_IDS, msg="%s aid %s" % (fn.__name__, aid))

    def test_risk_weather(self) -> None:
        clear = campaign_risk_day(
            weather={"visibility": 1.0, "precip_intensity": 0.0, "temp": 15.0},
            month=6,
        )
        foul = campaign_risk_day(
            weather={"visibility": 0.3, "precip_intensity": 0.9, "temp": -5.0},
            month=1,
        )
        self.assertFalse(clear.get("empty"))
        self.assertFalse(foul.get("empty"))
        self.assertGreaterEqual(float(foul.get("risk", 0)), float(clear.get("risk", 0)) - 0.01)

    def test_close_loop(self) -> None:
        loop = close_next30_theater_surface_loop()
        self.assertFalse(loop.get("empty"))
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 10)
        self.assertTrue(theater_surface_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")

        for aid in THEATER_SURFACE_DAY_IDS:
            self.assertIn("func %s" % aid, fmt, msg="MPF missing %s" % aid)
            self.assertIn(aid, gd, msg="GameData missing %s" % aid)
            self.assertIn(aid, panel, msg="panel missing %s" % aid)

        for name in (
            "war_cabinet_day_live",
            "supply_campaign_day_for_province",
            "force_supply_day_for_province",
            "counter_ops_day_live",
            "multi_province_live_day_for_tag",
            "order_queue_day_live",
            "agent_ai_board_day_live",
            "fleet_order_day_for_province",
            "fleet_theater_posture_day_for_tag",
            "campaign_risk_day_for_province",
        ):
            self.assertIn("func %s" % name, mm, msg="MM missing %s" % name)

        for name in (
            "apply_war_cabinet_day",
            "apply_supply_campaign_day",
            "apply_force_supply_day",
            "apply_counter_ops_day",
            "apply_multi_province_live_day",
            "apply_order_queue_day",
            "apply_agent_ai_board_day",
            "apply_fleet_order_day",
            "apply_fleet_theater_posture_day",
            "apply_campaign_risk_day",
        ):
            self.assertIn("func %s" % name, gd, msg="GD apply missing %s" % name)

        self.assertIn("war_cabinet_day", pi)
        self.assertIn("order_queue_day", pi)
        self.assertIn("campaign_risk_day", pi)

        self.assertIn("test_next20_theater_surface_days.py", CI.read_text(encoding="utf-8"))

        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "war cabinet day",
                "supply campaign day",
                "force supply day",
                "counter-ops day",
                "multi-province live day",
                "order queue day",
                "agent ai board day",
                "fleet order day",
                "fleet theater posture day",
                "campaign risk day",
                "next-30 theater",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
