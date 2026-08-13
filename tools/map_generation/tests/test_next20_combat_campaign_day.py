#!/usr/bin/env python3
"""Gates: combat ops day, move path day, combat campaign day, GIS×564."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from combat_campaign_day import (  # noqa: E402
    combat_ops_day,
    move_path_day,
    combat_campaign_day,
    combat_campaign_integrity,
    close_combat_campaign_day_loop,
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

CLEAR = {"precip_intensity": 0.0, "visibility": 1.0, "ground_state": "dry"}
FOUL = {"precip_intensity": 0.85, "visibility": 0.3, "ground_state": "mud", "wind": 0.8}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 564)


class TestCombat(unittest.TestCase):
    def test_ops_queue(self) -> None:
        day = combat_ops_day(weather=CLEAR, attacker_supply=0.9)
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
        low = combat_ops_day(weather=FOUL, attacker_supply=0.4)
        self.assertTrue(
            any(q.get("action_id") == "apply_supply" for q in low.get("apply_queue") or [])
        )


class TestMove(unittest.TestCase):
    def test_costly_path(self) -> None:
        easy = move_path_day(weather=CLEAR, supply_health=1.0, base_cost=1.0)
        hard = move_path_day(weather=FOUL, supply_health=0.35, base_cost=1.2)
        self.assertFalse(easy.get("empty"))
        self.assertFalse(hard.get("empty"))
        self.assertGreaterEqual(float(hard.get("path_cost", 0)), float(easy.get("path_cost", 0)) - 0.01)
        self.assertGreaterEqual(float(hard.get("score", 0)), float(easy.get("score", 0)) - 0.01)


class TestCompose(unittest.TestCase):
    def test_combat_campaign(self) -> None:
        day = combat_campaign_day(weather=CLEAR)
        self.assertFalse(day.get("empty"))
        self.assertIn("combat", day)
        self.assertIn("move", day)
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        self.assertTrue(combat_campaign_integrity().get("ok"))
        loop = close_combat_campaign_day_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreaterEqual(float(loop.get("weather_score_shift", 0)), 0.0)
        self.assertGreaterEqual(float(loop.get("move_score_shift", 0)), 0.0)


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func combat_ops_day_for_province", mm)
        self.assertIn("func move_path_day_for_province", mm)
        self.assertIn("func combat_campaign_day_for_tag", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func apply_combat_campaign_day", gd)
        self.assertIn("func apply_combat_ops_day", gd)
        self.assertIn("func apply_move_path_day", gd)
        self.assertIn("combat_campaign_day", gd)
        self.assertIn("combat_ops_day", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("combat_campaign_day", panel)
        self.assertIn("combat_ops_day", panel)
        self.assertIn("move_path_day", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func combat_ops_day", fmt)
        self.assertIn("func move_path_day", fmt)
        self.assertIn("func combat_campaign_day", fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_combat_ops_day_chip_bbcode", insight)
        self.assertIn("build_combat_campaign_day_chip_bbcode", insight)

        self.assertIn("test_next20_combat_campaign_day.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "combat ops day",
                "move path day",
                "combat campaign day",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
