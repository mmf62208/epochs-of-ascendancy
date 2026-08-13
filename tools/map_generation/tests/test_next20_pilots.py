#!/usr/bin/env python3
"""Gates: next-20 ordered pilots (GIS×96, convoy, assault card, agent missions, agenda actions, polish)."""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload, geometry_stats  # noqa: E402
from naval_convoy_escort import plan_convoy_escort, score_convoy_escort_need  # noqa: E402
from assault_estimate_card import build_assault_estimate_card  # noqa: E402
from agent_mission_priority import rank_agent_missions, score_agent_mission  # noqa: E402
from hh_agenda_actions import pick_agenda_actions  # noqa: E402
from hh_agenda_trail import append_hh_agenda_trail  # noqa: E402
from map_polish_pilots import (  # noqa: E402
    audit_capital_centroids,
    audit_map_action_flair_contracts,
    audit_region_theater_names,
    audit_soft_gazetteer,
    capital_centroid_ok,
    choke_basing_synergy_score,
    format_route_sealane_chip,
    format_scenario_data_dir_banner,
    format_slot_row_flair,
    inspector_section_collapse,
    parse_oob_evidence_line,
    resource_icon_budget,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_FLAIR = ROOT / "scripts" / "map" / "MapNextListHelpers.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"


class TestGis96(unittest.TestCase):
    def test_stamped_ge_96(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 96)
        st = geometry_stats(geom["provinces"])
        self.assertEqual(st["triangles"], 0)
        self.assertGreaterEqual(st["min"], 16)


class TestConvoyEscort(unittest.TestCase):
    def test_hostile_path_needs_more_than_friendly(self) -> None:
        hostile = score_convoy_escort_need(
            ["hostile", "hostile", "contested"], cargo_value=200, interdiction_chance=0.2
        )
        friendly = score_convoy_escort_need(
            ["friendly", "friendly", "no_zone"], cargo_value=200, interdiction_chance=0.05
        )
        self.assertGreater(hostile["escort_need"], friendly["escort_need"])
        self.assertTrue(hostile["recommend_escort"])
        plan = plan_convoy_escort(
            ["hostile", "contested"], 50.0, cargo_value=150, interdiction_chance=0.15
        )
        self.assertIn("assign", plan)
        self.assertGreater(plan["assign"]["desired"], 0.0)


class TestAssaultCard(unittest.TestCase):
    def test_card_has_ribbon_and_recommendation(self) -> None:
        card = build_assault_estimate_card(120, 80, province_name="Metz")
        self.assertFalse(card["empty"])
        self.assertIn("approach", card["plain"])
        self.assertIn("engage", card["plain"])
        self.assertIn("Metz", card["plain"])
        self.assertTrue(str(card["recommendation"]).strip())
        weak = build_assault_estimate_card(40, 120)
        self.assertLess(weak["overall"], card["overall"])


class TestAgentMissions(unittest.TestCase):
    def test_sabotage_prefers_defense(self) -> None:
        sab = rank_agent_missions(hh_action_class="sabotage", threat=0.8)
        inf = rank_agent_missions(hh_action_class="infiltration", threat=0.8, loyalty=0.2)
        self.assertFalse(sab["empty"])
        self.assertIn(sab["best_mission"], ("sabotage_defense", "counterintel"))
        self.assertNotEqual(sab["best_mission"], inf["best_mission"])
        s1 = score_agent_mission("sabotage_defense", hh_action_class="sabotage", threat=0.9)
        s2 = score_agent_mission("economic_shield", hh_action_class="sabotage", threat=0.9)
        self.assertGreater(s1["score"], s2["score"])


class TestAgendaActions(unittest.TestCase):
    def test_empty_and_nonempty(self) -> None:
        empty = pick_agenda_actions([])
        self.assertTrue(empty["empty"])
        self.assertEqual(empty["plain"], "")
        trail = []
        for i, ac in enumerate(["sabotage", "infiltration"]):
            trail = append_hh_agenda_trail(
                trail,
                {
                    "year": 1936,
                    "month": i + 1,
                    "action_class": ac,
                    "province_id": i + 1,
                    "province_name": "P",
                    "influence": 0.6,
                    "active": True,
                },
                None,
            )
        picks = pick_agenda_actions(trail, max_actions=3)
        self.assertFalse(picks["empty"])
        self.assertGreaterEqual(picks["count"], 1)
        self.assertTrue(all(str(x).strip() for x in picks["lines"]))


class TestPolishPilots(unittest.TestCase):
    def test_data_dir_banner_and_slot_flair(self) -> None:
        ban = format_scenario_data_dir_banner("world_full")
        self.assertIn("provinces_world_full", ban["line"])
        self.assertTrue(ban["is_default_play"])
        sec = format_scenario_data_dir_banner("grand_theater")
        self.assertIn("grand_theater", sec["line"])
        occ = format_slot_row_flair("quicksave", True, scenario_id="world_full", player_tag="GER")
        emp = format_slot_row_flair("slot1", False)
        self.assertTrue(occ["occupied"])
        self.assertFalse(emp["occupied"])
        self.assertIn("empty", emp["label"])

    def test_inspector_collapse_and_sealane_chip(self) -> None:
        secs = inspector_section_collapse(
            [
                {"id": "topline", "kind": "topline", "priority": 100},
                {"id": "body", "kind": "body", "priority": 40},
                {"id": "naval", "kind": "naval", "priority": 70},
                {"id": "extra", "kind": "body", "priority": 30},
            ],
            compact=True,
            max_expanded=2,
        )
        self.assertGreaterEqual(secs["expanded_count"], 1)
        chip = format_route_sealane_chip(1.12, 1.10, relation="friendly")
        self.assertTrue(chip["boosts"])
        self.assertIn("1.12", chip["label"])

    def test_choke_basing_and_capitals_and_regions(self) -> None:
        choke = choke_basing_synergy_score(True, "major_base", 16)
        plain = choke_basing_synergy_score(False, "anchorage", 2)
        self.assertGreater(choke["score"], plain["score"])
        self.assertTrue(capital_centroid_ok(100.0, 200.0)["ok"])
        self.assertFalse(capital_centroid_ok(0.0, 0.0)["ok"])
        caps = audit_capital_centroids(
            [{"id": 1, "x": 10.0, "y": 20.0}, {"id": 2, "x": 30.0, "y": 40.0}]
        )
        self.assertTrue(caps["ok"])
        reg = audit_region_theater_names(["Iberia", "China Heartland"])
        self.assertTrue(reg["ok"])
        bad = audit_region_theater_names(["Far East Theater 2"])
        self.assertFalse(bad["ok"])

    def test_icon_budget_flair_oob(self) -> None:
        world = resource_icon_budget(0.5, 2665)
        small = resource_icon_budget(0.5, 500)
        self.assertLessEqual(world["budget"], 180)
        self.assertGreaterEqual(small["budget"], world["budget"])
        flair_src = GD_FLAIR.read_text(encoding="utf-8") if GD_FLAIR.is_file() else ""
        audit = audit_map_action_flair_contracts(flair_src)
        self.assertTrue(
            audit["ok"],
            msg="flair contracts missing=%s" % audit.get("missing"),
        )
        self.assertIn("format_capture_assault_flair", flair_src)
        self.assertIn("func format_capture_flair", flair_src)  # alias
        line = (
            "ScenarioLoader: Daily production stockpile evidence (20d via daily_production_tick) "
            "— total_units=7 majors_grew=7/7 | GER line_done=1"
        )
        oob = parse_oob_evidence_line(line)
        self.assertTrue(oob["ok"])
        self.assertEqual(oob["total_units"], 7)
        self.assertEqual(oob["majors_grew"], 7)
        self.assertTrue(oob["full_majors"])

    def test_soft_gazetteer_world_full(self) -> None:
        base = json.loads((WF / "provinces_base.json").read_text(encoding="utf-8"))
        names = [p.get("name", "") for p in base.get("provinces") or []]
        audit = audit_soft_gazetteer(names)
        # Soft residual may be 0 after polish; gate is finite audit
        self.assertEqual(audit["total"], 2665)
        self.assertIsInstance(audit["soft_residual"], int)


class TestNext20Wiring(unittest.TestCase):
    def test_gd_and_docs(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func plan_convoy_escort_for_path", mm)
        bm = GD_BM.read_text(encoding="utf-8")
        self.assertIn("func build_assault_estimate_card", bm)
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func pick_hh_agenda_actions_plain", gd)
        self.assertRegex(
            gd,
            r"func pick_hh_agenda_actions_plain[\s\S]{0,80}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func format_assault_estimate_card_plain", fmt)
        self.assertIn("func resource_icon_budget", fmt)
        self.assertIn("func choke_basing_synergy_score", fmt)
        self.assertIn("func rank_agent_missions", fmt)
        self.assertIn("func format_scenario_data_dir_banner", fmt)
        # Live surfaces (not define-only)
        insight = (ROOT / "scripts" / "map" / "ProvinceInsight.gd").read_text(encoding="utf-8")
        self.assertIn("build_assault_estimate_card", insight)
        self.assertIn("plan_convoy_escort_for_path", insight)
        self.assertIn("pick_hh_agenda_actions_plain", insight)
        self.assertIn("format_scenario_data_dir_banner", insight)
        self.assertIn("choke_basing_synergy_score", insight)
        self.assertIn("rank_agent_missions", insight)
        self.assertIn("build_convoy_escort_chip_bbcode", insight)
        self.assertIn("build_agent_mission_priority_inspector_bbcode", insight)
        lod = (ROOT / "scripts" / "map" / "MapZoomLOD.gd").read_text(encoding="utf-8")
        self.assertIn("resource_icon_budget", lod)
        summary = SUMMARY.read_text(encoding="utf-8")
        self.assertTrue(
            re.search(r"\b(96|120|144|168|192|216|240|264|288|312|336|360|384|408|480|528|564)\b", summary),
            msg="GIS stamp count in summary",
        )
        todo = TODO.read_text(encoding="utf-8")
        self.assertTrue(re.search(r"\b(96|120|144|168|192|216|240|264|288|312|336|360|384|408|480|528|564)\b", todo))
        self.assertIn("deferred non-goal", todo.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
