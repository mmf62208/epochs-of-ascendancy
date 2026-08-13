#!/usr/bin/env python3
"""Gates: next-50 ops/mutation day packages (10) + GIS×753 + live GD wiring."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next50_ops_mutation import (  # noqa: E402
    OPS_MUTATION_DAY_IDS,
    factory_risk_day,
    trade_chain_day,
    war_path_urgency_day,
    combat_morale_day,
    choke_sea_day,
    redeploy_route_day,
    theater_report_day,
    best_station_day,
    best_assault_day,
    theater_mutation_day,
    close_next50_ops_mutation_loop,
    ops_mutation_integrity,
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
    factory_risk_day,
    trade_chain_day,
    war_path_urgency_day,
    combat_morale_day,
    choke_sea_day,
    redeploy_route_day,
    theater_report_day,
    best_station_day,
    best_assault_day,
    theater_mutation_day,
]


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_ten_ids(self) -> None:
        self.assertEqual(len(OPS_MUTATION_DAY_IDS), 10)
        self.assertEqual(len(DAY_FUNCS), 10)

    def test_each_nonempty_queue(self) -> None:
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"), msg=fn.__name__)
                self.assertTrue(str(day.get("summary", "")).strip())
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                aid = str((day.get("actions") or [{}])[0].get("action_id", ""))
                self.assertIn(aid, OPS_MUTATION_DAY_IDS)

    def test_close_loop(self) -> None:
        loop = close_next50_ops_mutation_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 10)
        self.assertTrue(ops_mutation_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")

        for aid in OPS_MUTATION_DAY_IDS:
            self.assertIn("func %s" % aid, fmt, msg="MPF missing %s" % aid)
            self.assertIn(aid, gd, msg="GameData missing %s" % aid)
            self.assertIn(aid, panel, msg="panel missing %s" % aid)

        for name in (
            "factory_risk_day_for_province",
            "trade_chain_day_for_province",
            "war_path_urgency_day_live",
            "combat_morale_day_for_province",
            "choke_sea_day_for_province",
            "redeploy_route_day_for_province",
            "theater_report_day_for_province",
            "best_station_day_for_province",
            "best_assault_day_for_province",
            "theater_mutation_day_for_province",
        ):
            self.assertIn("func %s" % name, mm, msg="MM missing %s" % name)

        for name in (
            "apply_factory_risk_day",
            "apply_trade_chain_day",
            "apply_war_path_urgency_day",
            "apply_combat_morale_day",
            "apply_choke_sea_day",
            "apply_redeploy_route_day",
            "apply_theater_report_day",
            "apply_best_station_day",
            "apply_best_assault_day",
            "apply_theater_mutation_day",
        ):
            self.assertIn("func %s" % name, gd, msg="GD apply missing %s" % name)

        self.assertIn("factory_risk_day", pi)
        self.assertIn("best_assault_day", pi)
        self.assertIn("theater_mutation_day", pi)

        self.assertIn("test_next20_ops_mutation_days.py", CI.read_text(encoding="utf-8"))

        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "factory risk day",
                "trade chain day",
                "war path urgency day",
                "combat morale day",
                "choke sea day",
                "redeploy route day",
                "theater report day",
                "best station day",
                "best assault day",
                "theater mutation day",
                "next-50 ops",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
