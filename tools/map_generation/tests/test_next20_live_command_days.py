#!/usr/bin/env python3
"""Gates: next-90 live command depth (20 day packages) + GIS×753 + live GD wiring."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next90_live_command import (  # noqa: E402
    LIVE_COMMAND_DAY_IDS,
    DAY_FUNCS,
    close_next90_live_command_loop,
    live_command_integrity,
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
    "mutation_result_day", "mutation_strip_day", "close_mutation_day", "mutation_gate_day",
    "agenda_pick_day", "agenda_actions_day", "hh_commit_order_day", "theater_hh_commit_day",
    "hh_counterplay_day", "day_results_flair_day",
}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_twenty(self) -> None:
        self.assertEqual(len(LIVE_COMMAND_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)

    def test_each(self) -> None:
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"), fn.__name__)
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1, fn.__name__)
                aid = str((day.get("actions") or [{}])[0].get("action_id", ""))
                self.assertIn(aid, LIVE_COMMAND_DAY_IDS)

    def test_close(self) -> None:
        loop = close_next90_live_command_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(live_command_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        for aid in LIVE_COMMAND_DAY_IDS:
            self.assertIn("func %s" % aid, fmt, msg="MPF %s" % aid)
            self.assertIn(aid, gd, msg="GD %s" % aid)
            self.assertIn(aid, panel, msg="panel %s" % aid)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm, msg="MM %s" % live)
        for key in ("mutation_result_day", "agenda_pick_day", "task_group_day", "phase_ribbon_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_live_command_days.py", CI.read_text(encoding="utf-8"))
        labels = [
            "mutation result day", "mutation strip day", "close mutation day", "mutation gate day",
            "agenda pick day", "agenda actions day", "hh commit order day", "theater hh commit day",
            "hh counterplay day", "task group day", "naval basing day", "naval multi phase day",
            "coastal fog gate day", "phase ribbon day", "assault rank day", "joint timeline day",
            "daylight combat day", "production auto day", "production risk alert day",
            "day results flair day", "next-90 live command",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
