#!/usr/bin/env python3
"""Pure FAC-1a needles: spread seeds, interior anchors, layer safety, RH-1 untouched."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from facility_icon_anchor_product import (  # noqa: E402
    CLUSTER_PAIR,
    HUNSRUECK,
    NEUWIED,
    OBERBERGISCHER,
    SEED_NAMES,
    SEED_TIERS,
    VIERSEN,
    build_facility_icon_anchor_product,
    point_in_ring,
    polylabel,
)

LAYER = ROOT / "scripts" / "map" / "FacilityIconLayer.gd"
REN = ROOT / "scripts" / "map" / "MapRenderer.gd"
OL = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"
LOADER = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
TIER4 = ROOT / "data" / "map" / "special_sites" / "airfield_tier_4.json"
FAC_DIR = ROOT / "assets" / "graphics" / "icons" / "facilities"
ACCURATE = ROOT / "data" / "provinces_world_accurate" / "project_sites.json"
PILOT = ROOT / "data" / "provinces_pilot_europe_nuts3" / "project_sites.json"
ANCHOR_JSON = ROOT / "data" / "provinces_world_accurate" / "facility_icon_anchors.json"

SEED_PIDS = set(SEED_TIERS.keys())


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
            self.assertNotIn(710417, got)
            self.assertNotIn(710416, got)
            self.assertNotIn(710418, got)
            self.assertNotIn(710413, got)
            self.assertNotIn(710421, got)
            self.assertNotIn(710459, got)
            self.assertNotIn(710426, got)
            self.assertNotIn(710469, got)
            self.assertNotIn(710455, got)

    def test_interior_anchors_product(self) -> None:
        product = build_facility_icon_anchor_product(write=False)
        self.assertTrue(product.get("ok"), product.get("reasons"))
        self.assertGreaterEqual(float(product.get("min_pair_world_raw") or 0), 16.0)
        cluster_d = float(product.get("cluster_pair_raw") or 0)
        self.assertGreaterEqual(cluster_d, 16.0)
        self.assertLessEqual(cluster_d, 17.5)
        self.assertEqual(tuple(CLUSTER_PAIR), (NEUWIED, OBERBERGISCHER))
        anchors = product.get("anchors") or {}
        v_raw = (anchors.get(str(VIERSEN)) or {}).get("raw") or [0.0, 0.0]
        for member in CLUSTER_PAIR:
            other = (anchors.get(str(member)) or {}).get("raw") or [0.0, 0.0]
            iso = ((float(v_raw[0]) - float(other[0])) ** 2 + (float(v_raw[1]) - float(other[1])) ** 2) ** 0.5
            self.assertGreaterEqual(iso, 20.7, "Viersen vs %s" % member)
        square = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]
        px, py, pr = polylabel(square, precision=0.2)
        self.assertTrue(point_in_ring(px, py, square))
        self.assertGreater(pr, 3.0)
        self.assertTrue(ANCHOR_JSON.is_file())
        blob = json.loads(ANCHOR_JSON.read_text(encoding="utf-8"))
        for pid in (VIERSEN, HUNSRUECK, OBERBERGISCHER, NEUWIED):
            rec = blob["anchors"][str(pid)]
            self.assertEqual(rec["name"], SEED_NAMES[pid])
            self.assertGreater(float(rec["edge_dist"]), 0.4)
            self.assertGreater(float(rec["spine_dist"]), 8.0)
            self.assertGreater(float(rec["rhine_dist"]), 8.0)

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
        self.assertIn("draw_circle", src)
        self.assertIn("var show_facilities: bool = true", src)
        self.assertIn("func rebuild_icon_list", src)
        self.assertIn("const BADGE_PX := 16.0", src)
        self.assertIn("func _polylabel", src)
        self.assertIn("_mean_ring(ring)", src)
        self.assertIn("func _cluster_items", src)
        self.assertIn("SPLIT_GAP_PX", src)
        self.assertNotIn("CORRIDOR_OFFSET_SCREEN_PX", src)
        self.assertNotIn("_landward_draw_world", src)
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
