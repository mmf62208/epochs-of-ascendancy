#!/usr/bin/env python3
"""Gates: next-10 round-2 pilots (GIS×72, fleet tasking, phase ribbon, focus pick, agenda screen, gazetteer)."""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload, geometry_stats  # noqa: E402
from naval_fleet_tasking import rank_naval_orders, score_naval_order  # noqa: E402
from combat_phase_ui import format_phase_ribbon  # noqa: E402
from combat_phase_estimate import estimate_multi_phase_combat  # noqa: E402
from focus_pick_priority import rank_focus_picks, score_focus_option  # noqa: E402
from hh_agenda_trail import append_hh_agenda_trail, format_hh_agenda_screen  # noqa: E402
from gazetteer_residual import audit_world_full_names, classify_province_name  # noqa: E402

WF = ROOT / "data" / "provinces_world_full"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"


class TestGisExpand72(unittest.TestCase):
    def test_stamped_at_least_72(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 72)
        stats = geometry_stats(geom["provinces"])
        self.assertEqual(stats["triangles"], 0)
        self.assertGreaterEqual(stats["min"], 16)


class TestFleetTasking(unittest.TestCase):
    def test_major_hostile_prefers_strike_over_anchorage_patrol(self) -> None:
        major = rank_naval_orders(
            {"level": "major_base", "capacity": 16},
            zone_relation="hostile",
            fuel_level=1.0,
        )
        weak = rank_naval_orders(
            {"level": "anchorage", "capacity": 2},
            zone_relation="neutral",
            fuel_level=0.35,
        )
        self.assertFalse(major["empty"])
        self.assertIn(major["best_order"], ("STRIKE", "SEARCH_AND_DESTROY", "ASW", "AMBUSH"))
        # Distinct preferences by context
        self.assertNotEqual(major["best_order"], weak["best_order"])
        s_strike = score_naval_order(
            "STRIKE", basing_level="major_base", basing_capacity=16, zone_relation="hostile"
        )
        s_patrol = score_naval_order(
            "SEARCH_PATROL", basing_level="major_base", basing_capacity=16, zone_relation="hostile"
        )
        self.assertGreater(s_strike["score"], s_patrol["score"])


class TestPhaseRibbon(unittest.TestCase):
    def test_ribbon_has_three_distinct_labels(self) -> None:
        est = estimate_multi_phase_combat(110, 90)
        ribbon = format_phase_ribbon(est)
        self.assertFalse(ribbon["empty"])
        self.assertEqual(len(ribbon["labels"]), 3)
        self.assertIn("approach", ribbon["ribbon_plain"])
        self.assertIn("engage", ribbon["ribbon_plain"])
        self.assertIn("disengage", ribbon["ribbon_plain"])
        self.assertIn("→", ribbon["ribbon_plain"])


class TestFocusPick(unittest.TestCase):
    def test_ranks_available_above_blocked(self) -> None:
        focuses = [
            {"id": "f_locked", "name": "Locked", "cost": 70, "prerequisites": ["need_me"]},
            {"id": "f_ready", "name": "Industrial Push", "cost": 70, "prerequisites": []},
            {"id": "f_done", "name": "Already Done", "cost": 50, "prerequisites": []},
            {"id": "f_era", "name": "Future Tech", "cost": 70, "available_year": 2000},
        ]
        ranked = rank_focus_picks(
            focuses, completed_ids=["f_done"], year=1936, max_picks=3
        )
        self.assertFalse(ranked["empty"])
        self.assertEqual(ranked["best_id"], "f_ready")
        ids = [p["id"] for p in ranked["picks"]]
        self.assertNotIn("f_locked", ids)
        self.assertNotIn("f_done", ids)
        ready = score_focus_option(focuses[1], completed_ids=["f_done"], year=1936)
        locked = score_focus_option(focuses[0], completed_ids=["f_done"], year=1936)
        self.assertGreater(ready["score"], locked["score"])


class TestAgendaScreen(unittest.TestCase):
    def test_screen_sections_and_empty(self) -> None:
        empty = format_hh_agenda_screen([])
        self.assertTrue(empty["empty"])
        self.assertEqual(empty["plain"], "")
        trail = []
        for i, ac in enumerate(["sabotage", "economic_pressure", "infiltration"]):
            trail = append_hh_agenda_trail(
                trail,
                {
                    "year": 1936,
                    "month": i + 1,
                    "action_class": ac,
                    "province_name": "P%d" % i,
                    "active": True,
                },
                None,
            )
        screen = format_hh_agenda_screen(trail, counterplay_summary="Deploy counter-intel")
        self.assertFalse(screen["empty"])
        self.assertIn("recent", screen["section_ids"])
        self.assertIn("by_class", screen["section_ids"])
        self.assertIn("actions", screen["section_ids"])
        self.assertIn("## Recent", screen["plain"])
        self.assertIn("## By class", screen["plain"])
        self.assertIn("sabotage", screen["plain"].lower())


class TestGazetteerResidual(unittest.TestCase):
    def test_world_full_names_clean(self) -> None:
        base = json.loads((WF / "provinces_base.json").read_text(encoding="utf-8"))
        audit = audit_world_full_names(base)
        self.assertEqual(audit["total"], 2665)
        self.assertEqual(audit["robotic"], 0, msg=audit.get("bad_samples"))
        self.assertEqual(audit["placeholder"], 0)
        self.assertTrue(audit["ok"])
        # Classifier catches residual patterns
        bad = classify_province_name("Sector B7")
        self.assertTrue(bad["robotic"])
        good = classify_province_name("Bordeaux")
        self.assertTrue(good["ok"])


class TestRound2Wiring(unittest.TestCase):
    def test_gd_and_docs(self) -> None:
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_agenda_screen_plain", gd)
        self.assertIn("func get_hh_agenda_screen", gd)
        # Empty trail early return on screen
        self.assertRegex(
            gd,
            r"func format_hh_agenda_screen_plain[\s\S]{0,120}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_hh_agenda_screen_inspector_bbcode", insight)
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func rank_fleet_tasking_for_province", mm)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func rank_naval_orders", fmt)
        self.assertIn("func format_phase_ribbon", fmt)
        self.assertIn("func rank_focus_picks", fmt)
        bm = GD_BM.read_text(encoding="utf-8")
        self.assertIn("func format_combat_phase_ribbon", bm)
        summary = SUMMARY.read_text(encoding="utf-8")
        self.assertTrue(
            re.search(r"\b(72|96|120|144|168|192|216|240|264|288|312|336|360|384)\b", summary),
            msg="summary should mention GIS pilot stamp count 72+",
        )
        todo = TODO.read_text(encoding="utf-8")
        self.assertTrue(re.search(r"\b(72|96|120|144|168|192|216|240|264|288|312|336|360|384)\b", todo))


if __name__ == "__main__":
    unittest.main(verbosity=2)
