#!/usr/bin/env python3
"""Pure FAC-1a needles: seeds, tier-4 def, layer safety, mipmaps, RH-1 untouched."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LAYER = ROOT / "scripts" / "map" / "FacilityIconLayer.gd"
REN = ROOT / "scripts" / "map" / "MapRenderer.gd"
OL = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"
LOADER = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
TIER4 = ROOT / "data" / "map" / "special_sites" / "airfield_tier_4.json"
FAC_DIR = ROOT / "assets" / "graphics" / "icons" / "facilities"
ACCURATE = ROOT / "data" / "provinces_world_accurate" / "project_sites.json"
PILOT = ROOT / "data" / "provinces_pilot_europe_nuts3" / "project_sites.json"

SEED_PIDS = {710416, 710418, 710417, 710413}
SEED_TIERS = {710416: 1, 710418: 2, 710417: 3, 710413: 4}


class TestFac1aAirfieldIcons(unittest.TestCase):
    def test_tier4_def(self) -> None:
        data = json.loads(TIER4.read_text(encoding="utf-8"))
        self.assertEqual(data.get("id"), "airfield_tier_4")
        self.assertEqual(str(data.get("site_type", "")).lower(), "airfield")
        self.assertEqual(int(data.get("tier", 0)), 4)

    def test_board_seeds(self) -> None:
        for path in (ACCURATE, PILOT):
            data = json.loads(path.read_text(encoding="utf-8"))
            sites = data.get("sites", [])
            air = [
                s
                for s in sites
                if str(s.get("project_type", s.get("site_id", ""))).lower().startswith("airfield")
            ]
            self.assertEqual(len(air), 4, path)
            got = {int(s["province_id"]): int(s.get("tier", 0)) for s in air}
            self.assertEqual(got, SEED_TIERS, path)
            self.assertEqual(set(got), SEED_PIDS)

    def test_art_and_mipmaps(self) -> None:
        for level in (1, 2, 3, 4):
            for px in (32, 64):
                png = FAC_DIR / f"airfield_l{level}_intact_{px}.png"
                self.assertTrue(png.is_file(), png)
                imp = Path(str(png) + ".import")
                self.assertTrue(imp.is_file(), imp)
                text = imp.read_text(encoding="utf-8")
                self.assertIn("mipmaps/generate=true", text)
        for level in (1, 2, 3, 4, 5):
            self.assertTrue((FAC_DIR / f"level_badge_l{level}_16.png").is_file())
            self.assertTrue((FAC_DIR / f"level_pips_l{level}_32.png").is_file())
            self.assertIn(
                "mipmaps/generate=true",
                (FAC_DIR / f"level_badge_l{level}_16.png.import").read_text(encoding="utf-8"),
            )

    def test_layer_draw_safety(self) -> None:
        src = LAYER.read_text(encoding="utf-8")
        self.assertIn("class_name FacilityIconLayer", src)
        self.assertIn("draw_texture_rect", src)
        self.assertIn("var show_facilities: bool = true", src)
        self.assertIn("func rebuild_icon_list", src)
        self.assertIn("CORRIDOR_OFFSET_SCREEN_PX", src)
        self.assertIn("_landward_draw_world", src)
        self.assertNotIn("Line2D.new", src)
        proc = src[src.find("func _process") : src.find("func _unhandled_input")]
        self.assertNotIn("rebuild_icon_list", proc)
        self.assertIn("queue_redraw", proc)

    def test_renderer_wiring_leaves_rh1(self) -> None:
        ren = REN.read_text(encoding="utf-8")
        self.assertIn("func _setup_facility_icon_layer", ren)
        self.assertIn("_setup_facility_icon_layer()", ren)
        start = ren.find("func set_map_mode")
        end = ren.find("\nfunc ", start + 10)
        body = ren[start:end]
        self.assertIn('ol_res.call("set_map_mode_for_glyphs", m)', body)
        self.assertNotIn("FacilityIconLayer", body)
        apply = ren[ren.find("func _apply_map_mode_visuals") : ren.find("func _apply_map_mode_visuals") + 2500]
        self.assertIn("FacilityIconLayer", apply)

    def test_old_sites_layer_untouched(self) -> None:
        ol = OL.read_text(encoding="utf-8")
        self.assertIn("func rebuild_sites_layer", ol)
        loader = LOADER.read_text(encoding="utf-8")
        self.assertIn("func apply_seeded_special_sites_to_provinces", loader)


if __name__ == "__main__":
    unittest.main(verbosity=2)
