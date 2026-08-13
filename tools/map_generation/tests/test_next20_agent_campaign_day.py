#!/usr/bin/env python3
"""Gates: agent response day, HH campaign day, agent campaign day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from agent_campaign_day import (  # noqa: E402
    agent_response_day,
    hh_campaign_day,
    agent_campaign_day,
    agent_campaign_integrity,
    close_agent_campaign_day_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestAgent(unittest.TestCase):
    def test_response_queue(self) -> None:
        day = agent_response_day(
            {"action_class": "sabotage", "province_id": 9, "influence": 0.7},
            province_id=9,
        )
        self.assertFalse(day.get("empty"))
        self.assertTrue(
            any(q.get("action_id") == "apply_agent_dispatch" for q in day.get("apply_queue") or [])
        )


class TestHH(unittest.TestCase):
    def test_empty_and_trail(self) -> None:
        empty = hh_campaign_day(trail=[])
        self.assertTrue(empty.get("empty"))
        day = hh_campaign_day(trail=[{"class": "economic_pressure", "influence": 0.4}])
        self.assertFalse(day.get("empty"))
        self.assertTrue(
            any(q.get("action_id") == "apply_hh_commit" for q in day.get("apply_queue") or [])
        )


class TestCompose(unittest.TestCase):
    def test_agent_campaign(self) -> None:
        day = agent_campaign_day()
        self.assertFalse(day.get("empty"))
        self.assertIn("agent", day)
        self.assertIn("hh", day)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(agent_campaign_integrity().get("ok"))
        loop = close_agent_campaign_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertTrue(loop["empty_hh"].get("empty"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func agent_response_day_for_tag", mm)
        self.assertIn("func hh_campaign_day_for_tag", mm)
        self.assertIn("func agent_campaign_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_agent_campaign_day", gd)
        self.assertIn("func apply_agent_response_day", gd)
        self.assertIn("func apply_hh_campaign_day", gd)
        self.assertIn("agent_campaign_day", gd)
        self.assertIn("agent_response_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("agent_campaign_day", panel)
        self.assertIn("agent_response_day", panel)
        self.assertIn("hh_campaign_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func agent_response_day", fmt)
        self.assertIn("func hh_campaign_day", fmt)
        self.assertIn("func agent_campaign_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_agent_response_day_chip_bbcode", insight)
        self.assertIn("build_agent_campaign_day_chip_bbcode", insight)

        self.assertIn("test_next20_agent_campaign_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "agent response day",
                "hh campaign day",
                "agent campaign day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
