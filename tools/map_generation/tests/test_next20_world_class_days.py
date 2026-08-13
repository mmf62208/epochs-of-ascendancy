#!/usr/bin/env python3
"""Gates: next-100 world-class depth (20 day packages) + GIS×753 + live GD wiring."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next100_world_class import (  # noqa: E402
    WORLD_CLASS_DAY_IDS,
    DAY_FUNCS,
    close_next100_world_class_loop,
    world_class_integrity,
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
    "best_assault_live_day", "best_station_live_day", "execute_one_live_day",
    "daily_fleet_auto_day", "daily_combat_auto_day", "daily_agent_auto_day",
    "daily_supply_auto_day", "hh_secondary_trail_day", "agent_campaign_live_day",
    "campaign_risk_live_day",
}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_twenty(self) -> None:
        self.assertEqual(len(WORLD_CLASS_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)

    def test_each(self) -> None:
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"), fn.__name__)
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1, fn.__name__)
                acts = day.get("actions") or []
                self.assertTrue(isinstance(acts, list) and len(acts) >= 1, fn.__name__)
                aid = str(acts[0].get("action_id", ""))
                self.assertIn(aid, WORLD_CLASS_DAY_IDS)

    def test_close(self) -> None:
        loop = close_next100_world_class_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(world_class_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        for aid in WORLD_CLASS_DAY_IDS:
            self.assertIn("func %s" % aid, fmt, msg="MPF %s" % aid)
            self.assertIn(aid, gd, msg="GD %s" % aid)
            self.assertIn(aid, panel, msg="panel %s" % aid)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm, msg="MM %s" % live)
        for key in ("best_assault_live_day", "convoy_wx_window_day", "hh_secondary_trail_day", "agent_campaign_live_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_world_class_days.py", CI.read_text(encoding="utf-8"))
        labels = [
            "best assault live day", "best station live day", "execute one live day",
            "basing fuel loop day", "fleet wx package day", "convoy wx window day",
            "focus wx score day", "morale wx day", "campaign risk live day", "depot wx live day",
            "daily fleet auto day", "daily combat auto day", "daily agent auto day",
            "daily supply auto day", "basing signals day", "basing rates day",
            "combat wx mult day", "sea zone trade day", "hh secondary trail day",
            "agent campaign live day", "next-100 world-class",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
