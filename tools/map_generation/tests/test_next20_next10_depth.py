#!/usr/bin/env python3
"""Gates: next-10 depth day packages (10) + GIS×753 + live GD wiring."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next10_depth import (  # noqa: E402
    NEXT10_DAY_IDS,
    multi_phase_combat_day,
    combat_air_naval_day,
    agent_auto_day,
    focus_pick_day,
    production_priority_day,
    convoy_escort_day,
    next_day_feedback_day,
    map_effect_day,
    theater_brief_day,
    campaign_decision_day,
    close_next10_depth_loop,
    next10_integrity,
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
    multi_phase_combat_day,
    combat_air_naval_day,
    agent_auto_day,
    focus_pick_day,
    production_priority_day,
    convoy_escort_day,
    next_day_feedback_day,
    map_effect_day,
    theater_brief_day,
    campaign_decision_day,
]


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_ten_ids(self) -> None:
        self.assertEqual(len(NEXT10_DAY_IDS), 10)
        self.assertEqual(len(DAY_FUNCS), 10)

    def test_each_nonempty_queue(self) -> None:
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"), msg=fn.__name__)
                self.assertTrue(str(day.get("summary", "")).strip(), msg=fn.__name__)
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1, msg=fn.__name__)
                self.assertGreaterEqual(len(day.get("actions") or []), 1, msg=fn.__name__)
                aid = str((day.get("actions") or [{}])[0].get("action_id", ""))
                self.assertIn(aid, NEXT10_DAY_IDS, msg="%s aid %s" % (fn.__name__, aid))

    def test_multi_phase_wx(self) -> None:
        clear = multi_phase_combat_day(attacker_supply=0.9, weather_mult=1.0)
        foul = multi_phase_combat_day(attacker_supply=0.5, weather_mult=0.55)
        self.assertFalse(clear.get("empty"))
        self.assertFalse(foul.get("empty"))
        # Foul should not be wildly better than clear
        self.assertGreaterEqual(
            float(clear.get("win_chance", 0)),
            float(foul.get("win_chance", 0)) - 0.05,
        )

    def test_agent_seeded(self) -> None:
        day = agent_auto_day()
        self.assertFalse(day.get("empty"))
        self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)

    def test_convoy_gap(self) -> None:
        thin = convoy_escort_day(
            ["hostile", "hostile", "contested"],
            available_fleet_strength=5.0,
            interdiction_chance=0.4,
        )
        self.assertFalse(thin.get("empty"))
        self.assertLessEqual(float(thin.get("coverage", 1.0)), 1.0)

    def test_feedback_trends(self) -> None:
        up = next_day_feedback_day(before_score=0.3, after_score=0.7)
        down = next_day_feedback_day(before_score=0.7, after_score=0.3)
        self.assertEqual(up.get("trend"), "improved")
        self.assertEqual(down.get("trend"), "worsened")

    def test_close_loop(self) -> None:
        loop = close_next10_depth_loop()
        self.assertFalse(loop.get("empty"))
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 10)
        gate = next10_integrity()
        self.assertTrue(gate.get("ok"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")

        for aid in NEXT10_DAY_IDS:
            self.assertIn("func %s" % aid, fmt, msg="MPF missing %s" % aid)
            self.assertIn(aid, gd, msg="GameData missing %s" % aid)
            self.assertIn(aid, panel, msg="panel missing %s" % aid)

        # Live MapManager entry points (at least core set)
        for name in (
            "multi_phase_combat_day_for_province",
            "combat_air_naval_day_for_province",
            "agent_auto_day_live",
            "focus_pick_day_live",
            "production_priority_day_for_province",
            "convoy_escort_day_for_province",
            "next_day_feedback_day_live",
            "map_effect_day_for_province",
            "theater_brief_day_for_province",
            "campaign_decision_day_live",
        ):
            self.assertIn("func %s" % name, mm, msg="MM missing %s" % name)

        for name in (
            "apply_multi_phase_combat_day",
            "apply_combat_air_naval_day",
            "apply_agent_auto_day",
            "apply_focus_pick_day",
            "apply_production_priority_day",
            "apply_convoy_escort_day",
            "apply_next_day_feedback_day",
            "apply_map_effect_day",
            "apply_theater_brief_day",
            "apply_campaign_decision_day",
        ):
            self.assertIn("func %s" % name, gd, msg="GD apply missing %s" % name)

        # Inspector chips (budgeted product-depth or always-on next10 skim)
        self.assertIn("multi_phase_combat_day", pi)
        self.assertIn("theater_brief_day", pi)
        self.assertIn("campaign_decision_day", pi)

        self.assertIn("test_next20_next10_depth.py", CI.read_text(encoding="utf-8"))

        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "multi-phase combat day",
                "combat air-naval day",
                "agent auto day",
                "focus pick day",
                "production priority day",
                "convoy escort day",
                "next-day feedback day",
                "map effect day",
                "theater brief day",
                "campaign decision day",
                "next-10 depth",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
