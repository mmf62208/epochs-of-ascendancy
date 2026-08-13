#!/usr/bin/env python3
"""Gates: inspector chip budget, resource/damage skim, sealane contest, GIS×753."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload, geometry_stats  # noqa: E402
from inspector_product_depth import (  # noqa: E402
    budget_product_depth_chips,
    resource_damage_operational_skim,
    sealane_contest_skim,
    close_inspector_product_depth_loop,
    chip_priority,
)

WF = ROOT / "data" / "provinces_world_full"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"


class TestGis(unittest.TestCase):
    def test_stamped_ge_753(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)
        stats = geometry_stats(geom["provinces"])
        self.assertEqual(stats.get("triangles"), 0)
        self.assertGreaterEqual(int(stats.get("min") or 0), 16)


class TestChipBudget(unittest.TestCase):
    def test_caps_and_always(self) -> None:
        chips = [
            {"id": "forecast_day", "bbcode": "f"},
            {"id": "naval_skim", "bbcode": "n"},
            {"id": "hh_player_path", "bbcode": "h"},
            {"id": "combat_campaign_day", "bbcode": "c"},
            {"id": "fleet_campaign_day", "bbcode": "fl"},
            {"id": "weather_crisis_day", "bbcode": "w"},
            {"id": "industry_surge_day", "bbcode": "i"},
            {"id": "agent_campaign_day", "bbcode": "a"},
            {"id": "convoy_pkg", "bbcode": "cv"},
            {"id": "war_cabinet", "bbcode": "cab"},
            {"id": "air_ops_day", "bbcode": "air"},
        ]
        b = budget_product_depth_chips(chips, max_chips=8, compact=True)
        self.assertEqual(int(b.get("shown", 0)), 8)
        self.assertEqual(int(b.get("total", 0)), 11)
        ids = b.get("selected_ids") or []
        self.assertIn("naval_skim", ids)
        self.assertIn("hh_player_path", ids)
        self.assertIn("combat_campaign_day", ids)
        self.assertIn("fleet_campaign_day", ids)
        self.assertGreater(chip_priority("naval_skim"), chip_priority("forecast_day"))
        full = budget_product_depth_chips(chips, max_chips=8, compact=False)
        self.assertEqual(int(full.get("shown", 0)), 11)


class TestResDmg(unittest.TestCase):
    def test_zoom_and_sabo(self) -> None:
        far = resource_damage_operational_skim(zoom=0.2, sabotage=False)
        op = resource_damage_operational_skim(zoom=0.45, sabotage=True, resource_level=0.3)
        self.assertFalse(far.get("icons_visible"))
        self.assertTrue(op.get("icons_visible"))
        self.assertGreaterEqual(float(op.get("urgency", 0)), float(far.get("urgency", 0)))


class TestSealane(unittest.TestCase):
    def test_contest(self) -> None:
        calm = sealane_contest_skim(zone_relation="friendly", is_choke=False, escort_coverage=1.0)
        foul = sealane_contest_skim(zone_relation="hostile", is_choke=True, escort_coverage=0.3)
        self.assertGreaterEqual(float(foul.get("contest", 0)), float(calm.get("contest", 0)))


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        loop = close_inspector_product_depth_loop()
        self.assertFalse(loop.get("empty"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func budget_product_depth_chips", fmt)
        self.assertIn("func resource_damage_operational_skim", fmt)
        self.assertIn("func sealane_contest_skim", fmt)

        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func resource_damage_skim_for_province", mm)
        self.assertIn("func sealane_contest_skim_for_province", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_resource_damage_skim_plain", gd)
        self.assertIn("func format_sealane_contest_skim_plain", gd)
        self.assertIn("func format_inspector_chip_budget_plain", gd)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("budget_product_depth_chips", insight)
        self.assertIn("build_resource_damage_skim_chip_bbcode", insight)
        self.assertIn("build_sealane_contest_skim_chip_bbcode", insight)
        self.assertIn("_append_budgeted_product_depth_chips", insight)

        self.assertIn("test_next20_inspector_product_depth.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "inspector product-depth",
                "resource/damage skim",
                "sealane contest skim",
                "gis×753",
            ):
                # allow variants
                ok = label in low or label.replace("×", "x") in low or label.replace("/", " ") in low
                if not ok and "753" in label:
                    ok = "753" in low
                if not ok and "inspector product-depth" in label:
                    ok = "product-depth" in low and "inspector" in low
                if not ok and "resource/damage" in label:
                    ok = "resource" in low and "damage" in low and "skim" in low
                if not ok and "sealane contest" in label:
                    ok = "sealane contest" in low
                self.assertTrue(ok, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
