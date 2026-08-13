#!/usr/bin/env python3
"""Tests for map action flair + HH counterplay pure helpers (next EOA outline slice).

Drives tools/map_generation/lib/map_next_list_helpers.py — shipped contract mirrored by
MapNextListHelpers.gd and used by MapRenderer / GameData / AgentManager.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_next_list_helpers import (  # noqa: E402
    apply_hh_counterplay,
    format_hh_monthly_map_signal,
    format_infra_project_flair,
    format_province_select_flair,
)

GD_HELPERS = ROOT / "scripts" / "map" / "MapNextListHelpers.gd"
GD_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
GD_GAMEDATA = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_AGENTS = ROOT / "scripts" / "agents" / "AgentManager.gd"


class TestMapActionFlair(unittest.TestCase):
    def test_select_flair_nonempty(self) -> None:
        flair = format_province_select_flair(
            "Gibraltar Strait Zone", "ENG", "Mediterranean", "strait", "", False
        )
        self.assertTrue(flair["toast"])
        self.assertIn("Gibraltar", flair["toast"])
        self.assertIn("Selected", flair["toast"])
        self.assertIn("ENG", flair["toast"])
        self.assertIn("Selected", flair["tooltip_chip"])
        self.assertEqual(flair["sfx"], "select")
        self.assertGreater(flair["duration"], 0.5)

    def test_select_flair_damage_and_hh_context(self) -> None:
        flair = format_province_select_flair(
            "Berlin", "GER", "Germany", "urban", "Infrastructure sabotage", True
        )
        self.assertIn("Infrastructure sabotage", flair["toast"])
        self.assertIn("Hand activity", flair["toast"])

    def test_select_flair_naval_chokepoint_and_sea_zone(self) -> None:
        choke = format_province_select_flair(
            "Gibraltar Strait Zone",
            "ENG",
            "Anatolia & Straits",
            "strait",
            "",
            False,
            True,
            "",
        )
        self.assertIn("chokepoint", choke["toast"].lower())
        self.assertEqual(choke["sfx"], "confirm")
        self.assertTrue(choke["is_chokepoint"])
        sea = format_province_select_flair(
            "North Atlantic Deep",
            "",
            "",
            "sea",
            "",
            False,
            False,
            "North Atlantic",
        )
        self.assertIn("North Atlantic", sea["toast"])
        self.assertEqual(sea["sfx"], "confirm")
        self.assertEqual(sea["sea_zone_name"], "North Atlantic")
        coast = format_province_select_flair(
            "Brest",
            "FRA",
            "France",
            "plains",
            "",
            False,
            False,
            "",
            True,
        )
        self.assertIn("Coast", coast["toast"])
        self.assertEqual(coast["sfx"], "confirm")
        self.assertTrue(coast["is_coastal"])

    def test_invest_start_and_complete_flair(self) -> None:
        start = format_infra_project_flair("Paris", "start", 0, 18, 45)
        self.assertIn("started", start["toast"].lower())
        self.assertIn("Paris", start["toast"])
        self.assertIn("18", start["toast"])
        self.assertIn("45", start["toast"])
        self.assertEqual(start["sfx"], "confirm")

        done = format_infra_project_flair("Paris", "complete", 6)
        self.assertIn("complete", done["toast"].lower())
        self.assertIn("level 6", done["toast"])
        self.assertEqual(done["sfx"], "achievement")
        self.assertTrue(done["news_headline"])

    def test_renderer_wires_flair(self) -> None:
        text = GD_RENDERER.read_text(encoding="utf-8")
        self.assertIn("_play_map_action_flair_select", text)
        self.assertIn("format_province_select_flair", text)
        self.assertIn("format_infra_project_flair", text)
        self.assertIn("_play_map_sfx", text)
        self.assertIn("Select.wav", text)
        helpers = GD_HELPERS.read_text(encoding="utf-8")
        self.assertIn("func format_province_select_flair", helpers)
        self.assertIn("func format_infra_project_flair", helpers)


class TestHHCounterplay(unittest.TestCase):
    def test_counterplay_reduces_influence(self) -> None:
        sig = format_hh_monthly_map_signal(1936, 3, 20105, "Gibraltar", "sabotage", 0.55, "ENG")
        self.assertTrue(sig["active"])
        result = apply_hh_counterplay(0.55, sig, method="counter_intel", clear_signal=True, reduction=0.12)
        self.assertTrue(result["success"])
        self.assertLess(result["new_influence"], result["old_influence"])
        self.assertAlmostEqual(result["old_influence"], 0.55, places=2)
        self.assertAlmostEqual(result["new_influence"], 0.43, places=2)
        self.assertTrue(result["signal_cleared"])
        self.assertFalse(result["updated_signal"].get("active", True))
        self.assertIn("Counter-intel", result["toast"])
        self.assertIn("Gibraltar", result["toast"])
        self.assertTrue(result["inspector_line"])
        self.assertTrue(result["news_headline"])

    def test_counterplay_without_signal_still_reduces(self) -> None:
        result = apply_hh_counterplay(0.3, None, method="policy", clear_signal=True, reduction=0.08)
        self.assertLess(result["new_influence"], 0.3)
        self.assertFalse(result["signal_cleared"])
        self.assertIn("influence", result["toast"].lower())

    def test_counterplay_floors_at_zero(self) -> None:
        result = apply_hh_counterplay(0.05, {}, method="counter_intel", reduction=0.5)
        self.assertEqual(result["new_influence"], 0.0)
        self.assertTrue(result["success"])

    def test_shipped_gamedata_and_agent_wire(self) -> None:
        gd = GD_GAMEDATA.read_text(encoding="utf-8")
        self.assertIn("func apply_hh_counterplay", gd)
        self.assertIn("hh_last_map_signal", gd)
        self.assertIn("MapNextListHelpers", gd)
        agents = GD_AGENTS.read_text(encoding="utf-8")
        self.assertIn("apply_hh_counterplay", agents)
        helpers = GD_HELPERS.read_text(encoding="utf-8")
        self.assertIn("func apply_hh_counterplay", helpers)


if __name__ == "__main__":
    unittest.main(verbosity=2)
