#!/usr/bin/env python3
"""Gates: next-10 ordered pilots (GIS expand, fleet-ops, HH panel, combat phases, counterplay, data dir)."""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import (  # noqa: E402
    geometry_stats,
    province_id_set,
    run_align_pipeline,
    load_geometry_payload,
    load_gis_features,
)
from naval_fleet_ops import (  # noqa: E402
    format_fleet_station_preference,
    rank_fleet_station_candidates,
    score_fleet_station_candidate,
)
from naval_basing import compute_naval_basing  # noqa: E402
from hh_agenda_trail import append_hh_agenda_trail, format_hh_agenda_panel  # noqa: E402
from combat_phase_estimate import (  # noqa: E402
    estimate_multi_phase_combat,
    estimate_phase,
)
from agent_counterplay import counterplay_options_for_signal  # noqa: E402
from play_data_dir import resolve_play_data_dir, DEFAULT_PLAY_DIR  # noqa: E402

WF = ROOT / "data" / "provinces_world_full"
FIXTURE = ROOT / "tools" / "map_generation" / "fixtures" / "gis_coastline_pilot_rings.json"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_BM = ROOT / "scripts" / "combat" / "BattleManager.gd"


class TestGisExpandPilot(unittest.TestCase):
    def test_shipped_geometry_expanded_pilot(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom.get("provinces") or []), 2665)
        stamped = [
            p
            for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_pilot")
        ]
        self.assertGreaterEqual(len(stamped), 48, msg="GIS expand should stamp ≥48 coastal pilots")
        stats = geometry_stats(geom["provinces"])
        self.assertEqual(stats["triangles"], 0)
        self.assertGreaterEqual(stats["min"], 16)
        # Fixture expanded
        feats = load_gis_features(FIXTURE)
        self.assertGreaterEqual(len(feats), 48)
        # Align dry-run remains id_stable
        dry = run_align_pipeline(geom, feats[:12], apply_write=False)
        self.assertTrue(dry["id_stable"])
        self.assertGreaterEqual(dry["matched"], 1)


class TestFleetOpsPilot(unittest.TestCase):
    def test_major_beats_anchorage(self) -> None:
        anch = compute_naval_basing(domain="coastal_land", province_id=1)
        major = compute_naval_basing(
            domain="coastal_land",
            has_naval_shipyard=True,
            port_tier=3,
            is_chokepoint=True,
            province_id=2,
        )
        s_a = score_fleet_station_candidate(anch)
        s_m = score_fleet_station_candidate(major)
        self.assertGreater(s_m["score"], s_a["score"])
        ranked = rank_fleet_station_candidates(
            [
                {"province_id": 1, "basing": anch, "is_owned": True},
                {"province_id": 2, "basing": major, "is_owned": True},
            ]
        )
        self.assertEqual(ranked["best_province_id"], 2)
        self.assertEqual(ranked["best_level"], "major_base")
        self.assertIn("Fleet basing prefer", format_fleet_station_preference(ranked))


class TestHHAgendaPanel(unittest.TestCase):
    def test_panel_from_trail_nonempty_ordered(self) -> None:
        trail = []
        for i, ac in enumerate(["sabotage", "economic_pressure", "infiltration"]):
            trail = append_hh_agenda_trail(
                trail,
                {
                    "year": 1936,
                    "month": i + 1,
                    "province_id": i,
                    "province_name": "P%d" % i,
                    "action_class": ac,
                    "title": "HH %s" % ac,
                    "active": True,
                },
                None,
                capacity=6,
            )
        panel = format_hh_agenda_panel(trail, max_lines=6)
        self.assertFalse(panel["empty"])
        self.assertGreaterEqual(panel["count"], 3)
        self.assertIn("sabotage", panel["class_order"])
        self.assertIn("infiltration", panel["class_order"])
        self.assertIn("Hidden Hand Agenda", panel["plain"])
        self.assertTrue(all(str(x).strip() for x in panel["lines"]))

    def test_empty_trail_panel_is_empty_string(self) -> None:
        """Empty trail must not emit zero-action header (inspector spam)."""
        panel = format_hh_agenda_panel([], max_lines=6)
        self.assertTrue(panel["empty"])
        self.assertEqual(panel["plain"], "")
        self.assertEqual(panel["bbcode"], "")
        self.assertEqual(panel["count"], 0)
        self.assertEqual(panel["lines"], [])
        # GD GameData mirror: early-return "" when trail empty
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_agenda_panel_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_agenda_panel_plain[\s\S]{0,200}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        # Summary must not claim GIS pilot is only 24 coasts (live expand ≥48, now 72)
        summary = (ROOT / "Project_State_Summary.md").read_text(encoding="utf-8")
        self.assertTrue(
            re.search(r"\b(48|72|96|120|144|168|192|216|240|264|288|312|336|360|384)\b", summary),
            msg="summary should mention GIS pilot stamp count 48+",
        )
        self.assertNotRegex(
            summary,
            r"(?i)GIS \*\*pilot\*\* 24 coasts|24 coastal rings via",
        )
        self.assertNotRegex(
            summary,
            r"(?i)no GIS coasts,",
        )


class TestCombatPhasePilot(unittest.TestCase):
    def test_phases_distinct_and_chain(self) -> None:
        approach = estimate_phase("approach", 100, 80)
        engage = estimate_phase("engage", 100, 80)
        self.assertNotEqual(approach["attacker_effective"], engage["attacker_effective"])
        multi = estimate_multi_phase_combat(120, 90)
        self.assertEqual(len(multi["phases"]), 3)
        self.assertIn("approach", multi["phase_names"])
        self.assertIn("engage", multi["phase_names"])
        self.assertNotEqual(multi["approach_win_chance"], multi["engage_win_chance"])
        self.assertGreater(multi["overall_attacker_win_chance"], 0.0)
        self.assertLess(multi["overall_attacker_win_chance"], 1.0)


class TestAgentCounterplay(unittest.TestCase):
    def test_options_by_class(self) -> None:
        sab = counterplay_options_for_signal(
            {"action_class": "sabotage", "province_id": 10, "influence": 0.7}
        )
        inf = counterplay_options_for_signal(
            {"action_class": "infiltration", "province_id": 11, "influence": 0.6}
        )
        self.assertGreaterEqual(sab["count"], 2)
        self.assertGreaterEqual(inf["count"], 2)
        self.assertNotEqual(sab["options"][0]["id"], inf["options"][0]["id"])
        self.assertIn("Counterplay", sab["summary"])
        # Priority ordered descending
        prios = [float(o["priority"]) for o in sab["options"]]
        self.assertEqual(prios, sorted(prios, reverse=True))


class TestPlayDataDir(unittest.TestCase):
    def test_default_world_full(self) -> None:
        r = resolve_play_data_dir("world_full")
        self.assertEqual(r["data_dir"], DEFAULT_PLAY_DIR)
        self.assertTrue(r["is_default_play"])
        sec = resolve_play_data_dir("grand_theater")
        self.assertEqual(sec["data_dir"], "provinces_grand_theater")
        self.assertFalse(sec["is_default_play"])
        self.assertTrue(sec["warning"])


class TestNext10Wiring(unittest.TestCase):
    def test_gd_surfaces(self) -> None:
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_hh_agenda_panel_plain", gd)
        self.assertIn("func get_hh_agenda_panel", gd)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_hh_agenda_panel_inspector_bbcode", insight)
        self.assertIn("build_agent_counterplay_inspector_bbcode", insight)
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func get_preferred_fleet_station", mm)
        self.assertIn("score_fleet_station_candidate", mm)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func score_fleet_station_candidate", fmt)
        self.assertIn("func estimate_multi_phase_combat", fmt)
        self.assertIn("func resolve_play_data_dir", fmt)
        bm = GD_BM.read_text(encoding="utf-8")
        self.assertIn("func estimate_multi_phase_combat", bm)


if __name__ == "__main__":
    unittest.main(verbosity=2)
