#!/usr/bin/env python3
"""Gates for sea-zone theater prototype + select-flair naval cues."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from build_sea_zone_theaters import build, MIN_ZONES, MIN_SEA_ASSIGNED  # noqa: E402

WF = ROOT / "data" / "provinces_world_full"
MM = ROOT / "scripts" / "map" / "MapManager.gd"
HELPERS = ROOT / "scripts" / "map" / "MapNextListHelpers.gd"
INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


class TestSeaZoneBuild(unittest.TestCase):
    def test_build_pure(self) -> None:
        payload = build(WF)
        self.assertGreaterEqual(payload["meta"]["zone_count"], MIN_ZONES)
        self.assertGreaterEqual(payload["meta"]["sea_province_count"], MIN_SEA_ASSIGNED)
        self.assertEqual(
            len(payload["province_to_zone"]),
            payload["meta"]["sea_province_count"],
        )
        names = {z["name"] for z in payload["zones"]}
        # Core theaters expected on a world board
        for must in ("Mediterranean Sea", "North Atlantic", "Indian Ocean", "Central Pacific"):
            self.assertIn(must, names, msg=names)

    def test_shipped_json(self) -> None:
        path = WF / "sea_zone_theaters.json"
        self.assertTrue(path.is_file())
        data = json.loads(path.read_text(encoding="utf-8"))
        self.assertGreaterEqual(int(data["meta"]["zone_count"]), MIN_ZONES)
        self.assertGreaterEqual(len(data.get("province_to_zone") or {}), MIN_SEA_ASSIGNED)
        # Sample ids exist on board
        base_ids = {
            int(p["id"])
            for p in json.loads((WF / "provinces_base.json").read_text())["provinces"]
        }
        for pid_s in list((data.get("province_to_zone") or {}).keys())[:20]:
            self.assertIn(int(pid_s), base_ids)


class TestSeaZoneWiring(unittest.TestCase):
    def test_mapmanager_apis(self) -> None:
        src = MM.read_text(encoding="utf-8")
        for needle in (
            "_load_sea_zone_theaters",
            "func get_sea_zone_name",
            "func has_sea_zone",
            "sea_zone_theaters.json",
        ):
            self.assertIn(needle, src, msg=needle)

    def test_insight_and_select_flair(self) -> None:
        insight = INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_sea_zone_badge_bbcode", insight)
        helpers = HELPERS.read_text(encoding="utf-8")
        self.assertIn("sea_zone_name", helpers)
        self.assertIn("is_chokepoint", helpers)
        self.assertIn("is_coastal", helpers)
        renderer = RENDERER.read_text(encoding="utf-8")
        self.assertIn("get_sea_zone_name", renderer)
        self.assertIn("has_strategic_chokepoint", renderer)
        self.assertIn("_sea_zone_theater_color", renderer)
        self.assertIn("_province_is_coastal_land", renderer)
        overlay = (ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn("_draw_naval_chokepoint_marker", overlay)
        self.assertIn("get_country_color", overlay)
        toolbar = (ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn('"naval"', toolbar)


if __name__ == "__main__":
    unittest.main(verbosity=2)
