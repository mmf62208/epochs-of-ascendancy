#!/usr/bin/env python3
"""Gates: map action feedback contracts — select, invest, capture, HH signal."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_next_list_helpers import (  # noqa: E402
    format_capture_assault_flair,
    format_hh_monthly_map_signal,
    format_infra_project_flair,
    format_province_select_flair,
)

GD_HELPERS = ROOT / "scripts" / "map" / "MapNextListHelpers.gd"
GD_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
GD_GAMEDATA = ROOT / "scripts" / "autoload" / "GameData.gd"


class TestMapActionFeedbackContracts(unittest.TestCase):
    def test_four_kinds_distinguishable(self) -> None:
        select = format_province_select_flair("Berlin", "GER", "Germany", "urban")
        invest = format_infra_project_flair("Berlin", "complete", 5)
        invest_start = format_infra_project_flair("Berlin", "start", 0, 12, 40)
        capture = format_capture_assault_flair(
            "Paris", "GER", "FRA", True, "victory", "attacker"
        )
        hh = format_hh_monthly_map_signal(
            1936, 3, 9287, "Berlin", "sabotage", 0.5, "GER"
        )

        for payload, kind in (
            (select, "select"),
            (invest, "invest_complete"),
            (invest_start, "invest_start"),
            (capture, "capture"),
            (hh, "hh_signal"),
        ):
            self.assertTrue(str(payload.get("toast", "")).strip(), msg=kind)
            self.assertTrue(str(payload.get("sfx", "")).strip(), msg=kind)
            self.assertEqual(payload.get("action_kind"), kind)

        # Distinguishing toast / sfx fingerprints across the four player actions
        kinds = {
            select["action_kind"]: (select["sfx"], "Selected" in select["toast"]),
            invest["action_kind"]: (invest["sfx"], "complete" in invest["toast"].lower()),
            capture["action_kind"]: (capture["sfx"], "captured" in capture["toast"].lower()),
            hh["action_kind"]: (hh["sfx"], "Hidden Hand" in hh["toast"]),
        }
        self.assertEqual(len(kinds), 4)
        # SFX not all identical across kinds
        sfx_set = {select["sfx"], invest["sfx"], capture["sfx"], hh["sfx"]}
        self.assertGreaterEqual(len(sfx_set), 2)
        self.assertEqual(select["sfx"], "select")
        self.assertEqual(invest["sfx"], "achievement")
        self.assertEqual(capture["sfx"], "achievement")
        self.assertEqual(hh["sfx"], "error")  # sabotage class
        # Capture vs invest both achievement but toast/action_kind differ
        self.assertNotEqual(capture["action_kind"], invest["action_kind"])
        self.assertNotEqual(capture["toast"], invest["toast"])

    def test_capture_hold_repulse(self) -> None:
        held = format_capture_assault_flair("Warsaw", "GER", "POL", False, "stalemate", "defender")
        self.assertEqual(held["action_kind"], "assault_hold")
        self.assertIn("held", held["toast"].lower())
        self.assertEqual(held["sfx"], "map")
        rep = format_capture_assault_flair("Warsaw", "GER", "POL", False, "repulse", "attacker")
        self.assertEqual(rep["action_kind"], "assault_repulse")
        self.assertIn("repulsed", rep["toast"].lower())

    def test_hh_map_visible_sfx_and_tooltip(self) -> None:
        econ = format_hh_monthly_map_signal(
            1936, 4, 1, "Ruhr", "economic_pressure", 0.4, "GER"
        )
        self.assertEqual(econ["action_kind"], "hh_signal")
        self.assertEqual(econ["sfx"], "confirm")
        self.assertTrue(econ.get("tooltip_chip") or econ.get("inspector_line"))
        inf = format_hh_monthly_map_signal(
            1936, 5, 2, "Moscow", "infiltration", 0.4, "SOV"
        )
        self.assertEqual(inf["sfx"], "map")

    def test_wiring_shipped_sources(self) -> None:
        helpers = GD_HELPERS.read_text(encoding="utf-8")
        for needle in (
            "func format_province_select_flair",
            "func format_infra_project_flair",
            "func format_capture_assault_flair",
            "func format_hh_monthly_map_signal",
            "action_kind",
        ):
            self.assertIn(needle, helpers, msg=needle)
        renderer = GD_RENDERER.read_text(encoding="utf-8")
        self.assertIn("format_province_select_flair", renderer)
        self.assertIn("format_infra_project_flair", renderer)
        self.assertIn("format_capture_assault_flair", renderer)
        self.assertIn("_play_map_sfx", renderer)
        self.assertIn('"select"', renderer)
        self.assertIn('"achievement"', renderer)
        gd = GD_GAMEDATA.read_text(encoding="utf-8")
        self.assertIn("format_hh_monthly_map_signal", gd)
        self.assertIn("process_hh_monthly_map_feedback", gd)
        self.assertIn('sig.get("sfx"', gd) or 'sig.get("sfx"' in gd or 'get("sfx"' in gd


if __name__ == "__main__":
    unittest.main(verbosity=2)
