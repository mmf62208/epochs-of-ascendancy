#!/usr/bin/env python3
"""Tests for next-list helpers: DebugOverlay split, damage/sabotage visuals, HH monthly map signal.

Drives tools/map_generation/lib/map_next_list_helpers.py (shipped pure contract mirrored by
MapNextListHelpers.gd and used by DebugOverlay / ProvinceInsight / MapRenderer / GameData).
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_next_list_helpers import (  # noqa: E402
    DEV_HARNESS_SECTION_TITLES,
    classify_map_damage,
    default_harness_visible,
    default_player_map_visible,
    format_hh_monthly_map_signal,
    is_dev_harness_section,
    pick_hh_action_class,
    section_kind,
    section_start_collapsed,
)

GD_HELPERS = ROOT / "scripts" / "map" / "MapNextListHelpers.gd"
GD_OVERLAY = ROOT / "scripts" / "ui" / "DebugOverlay.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
GD_INFRA_OL = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"
GD_GAMEDATA = ROOT / "scripts" / "autoload" / "GameData.gd"


class TestDebugOverlaySplitDefaults(unittest.TestCase):
    def test_harness_defaults_hidden(self) -> None:
        self.assertFalse(default_harness_visible())
        self.assertTrue(default_player_map_visible())

    def test_known_harness_sections_collapsed(self) -> None:
        for title in DEV_HARNESS_SECTION_TITLES:
            self.assertTrue(is_dev_harness_section(title), title)
            self.assertTrue(section_start_collapsed(title), title)
            self.assertEqual(section_kind(title), "dev_harness")

    def test_player_map_sections_expanded(self) -> None:
        for title in (
            "Infrastructure Projects",
            "Time & Simulation",
            "Quick Actions",
            "Player Map",
            "Map Modes",
        ):
            self.assertFalse(is_dev_harness_section(title), title)
            self.assertFalse(section_start_collapsed(title), title)
            self.assertEqual(section_kind(title), "player_map")

    def test_heuristic_harness_names(self) -> None:
        self.assertTrue(is_dev_harness_section("My Playtest Harness Extra"))
        self.assertTrue(is_dev_harness_section("Province Border Editor (In-Game)"))
        self.assertFalse(is_dev_harness_section("Infrastructure Projects"))

    def test_debug_overlay_wires_split(self) -> None:
        text = GD_OVERLAY.read_text(encoding="utf-8")
        self.assertIn("MapNextListHelpers.gd", text)
        self.assertIn("_apply_player_harness_defaults", text)
        self.assertIn("BtnToggleDevHarness", text)
        self.assertIn("Show Dev Harness", text)
        self.assertIn("MAP TOOLS", text)
        self.assertIn("default_harness_visible", text)


class TestMapDamageVisualClassification(unittest.TestCase):
    def test_clean_province(self) -> None:
        d = classify_map_damage({})
        self.assertFalse(d["is_damaged"])
        self.assertEqual(d["tint_key"], "clean")
        self.assertEqual(d["strength"], 0.0)
        self.assertEqual(d["marker"], "")

    def test_infra_sabotage_distinct_from_clean(self) -> None:
        clean = classify_map_damage({"infrastructure": 40})
        sabo = classify_map_damage(
            {
                "under_infra_sabotage": True,
                "infrastructure": 10,
                "agent_pressure_kind": "sabotage",
            }
        )
        self.assertTrue(sabo["is_damaged"])
        self.assertEqual(sabo["tint_key"], "infra_sabotage")
        self.assertEqual(sabo["marker"], "⚠")
        self.assertGreater(sabo["strength"], clean["strength"])
        self.assertIn("sabotage", sabo["label"].lower())

    def test_depot_and_site_damage(self) -> None:
        depot = classify_map_damage({"depot_sabotage_level": 0.35})
        self.assertTrue(depot["is_damaged"])
        self.assertEqual(depot["tint_key"], "depot_sabotage")
        self.assertEqual(depot["marker"], "⛟")
        self.assertGreater(depot["strength"], 0.2)

        site = classify_map_damage({"site_damaged_count": 2})
        self.assertTrue(site["is_damaged"])
        self.assertEqual(site["tint_key"], "site_damage")
        self.assertEqual(site["marker"], "💥")
        self.assertIn("2", site["label"])

    def test_project_sabotaged(self) -> None:
        p = classify_map_damage({"project_sabotaged": True})
        self.assertTrue(p["is_damaged"])
        self.assertEqual(p["tint_key"], "project_sabotage")
        self.assertIn("project", p["label"].lower())

    def test_shipped_wiring_map_damage(self) -> None:
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("classify_province_map_damage", insight)
        self.assertIn("build_map_damage_state", insight)
        renderer = GD_RENDERER.read_text(encoding="utf-8")
        self.assertIn("_apply_map_damage_visual_tint", renderer)
        overlay = GD_INFRA_OL.read_text(encoding="utf-8")
        self.assertIn("_draw_damage_sabotage_marker", overlay)
        self.assertIn("classify_province_map_damage", overlay)


class TestHHMonthlyMapSignal(unittest.TestCase):
    def test_format_signal_nonempty_player_payload(self) -> None:
        sig = format_hh_monthly_map_signal(
            1936, 3, 20105, "Gibraltar Strait Zone", "sabotage", 0.5, "ENG"
        )
        self.assertTrue(sig["active"])
        self.assertEqual(sig["province_id"], 20105)
        self.assertEqual(sig["action_class"], "sabotage")
        self.assertIn("Hidden Hand", sig["title"])
        self.assertTrue(sig["toast"])
        self.assertTrue(sig["news_headline"])
        self.assertTrue(sig["inspector_line"])
        self.assertIn("Gibraltar", sig["toast"])
        self.assertEqual(sig["tint_key"], "infra_sabotage")
        self.assertGreater(sig["strength"], 0.2)
        self.assertEqual(sig["marker"], "⚠")

    def test_propaganda_and_influence_classes(self) -> None:
        prop = format_hh_monthly_map_signal(1936, 1, 10, "Berlin", "propaganda", 0.2)
        self.assertEqual(prop["action_class"], "propaganda")
        self.assertEqual(prop["marker"], "📢")
        self.assertEqual(prop["tint_key"], "hh_influence")
        inf = format_hh_monthly_map_signal(1936, 2, 11, "Paris", "influence", 0.1)
        self.assertEqual(inf["marker"], "👁")
        self.assertIn("Paris", inf["inspector_line"])

    def test_pick_action_class_deterministic(self) -> None:
        a = pick_hh_action_class(3, 0.5)
        b = pick_hh_action_class(3, 0.5)
        self.assertEqual(a, b)
        self.assertIn(
            a,
            (
                "sabotage",
                "propaganda",
                "influence",
                "black_market",
                "economic_pressure",
                "infiltration",
            ),
        )
        # High influence + month%3==0 → sabotage
        self.assertEqual(pick_hh_action_class(3, 0.5), "sabotage")
        # High influence + month%3==1 → economic_pressure (second map-visible class)
        self.assertEqual(pick_hh_action_class(4, 0.4), "economic_pressure")
        # High influence + month%3==2 → infiltration (third map-visible class)
        self.assertEqual(pick_hh_action_class(5, 0.35), "infiltration")

    def test_economic_pressure_and_secondary_pick(self) -> None:
        from map_next_list_helpers import pick_hh_secondary_action_class  # noqa: WPS433

        econ = format_hh_monthly_map_signal(1936, 4, 42, "Ruhr", "economic_pressure", 0.4, "GER")
        self.assertEqual(econ["action_class"], "economic_pressure")
        self.assertEqual(econ["map_effect"], "industrial_pressure")
        self.assertEqual(econ["tint_key"], "supply_pressure")
        self.assertIn("economic", econ["title"].lower())
        # Secondary complements primary (prefer third map class when hand high)
        self.assertIn(
            pick_hh_secondary_action_class(3, 0.5, "sabotage"),
            ("economic_pressure", "infiltration"),
        )
        self.assertNotEqual(
            pick_hh_secondary_action_class(1, 0.2, "propaganda"), "propaganda"
        )

    def test_shipped_gamedata_and_map_hh_path(self) -> None:
        gd = GD_GAMEDATA.read_text(encoding="utf-8")
        self.assertIn("process_hh_monthly_map_feedback", gd)
        self.assertIn("hh_last_map_signal", gd)
        self.assertIn("hh_secondary_map_signal", gd)
        self.assertIn("_apply_hh_map_effect", gd)
        self.assertIn("economic_pressure", gd)
        self.assertIn("format_hh_monthly_map_signal", gd)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_hh_map_signal_inspector_line", insight)
        renderer = GD_RENDERER.read_text(encoding="utf-8")
        self.assertIn("_apply_hh_map_signal_tint", renderer)
        overlay = GD_INFRA_OL.read_text(encoding="utf-8")
        self.assertIn("_draw_hh_map_signal_marker", overlay)
        self.assertIn("hh_last_map_signal", overlay)
        self.assertIn("hh_secondary_map_signal", overlay)
        helpers = GD_HELPERS.read_text(encoding="utf-8")
        self.assertIn("func format_hh_monthly_map_signal", helpers)
        self.assertIn("func pick_hh_secondary_action_class", helpers)
        self.assertIn("economic_pressure", helpers)
        self.assertIn("func classify_map_damage", helpers)
        self.assertIn("func section_start_collapsed", helpers)


if __name__ == "__main__":
    unittest.main(verbosity=2)
