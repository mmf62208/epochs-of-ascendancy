#!/usr/bin/env python3
"""Gate: starved player factories become map markers (exception-first)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_factory_shortage_surface_product import (  # noqa: E402
    GER_INDUSTRY_DEFAULT,
    MAX_MARKERS,
    build_map_factory_shortage_surface_product,
    cap_shortage_markers,
    factory_shortage_marker,
    outline_for_fill_ratio,
    worst_missing_key,
)

LAYER = ROOT / "scripts" / "map" / "FactoryStatusLayer.gd"


class TestMapFactoryShortageSurface(unittest.TestCase):
    def test_worst_missing_prefers_oil(self) -> None:
        self.assertEqual(worst_missing_key({"steel": 1.0, "oil": 0.5}), "oil")
        self.assertEqual(worst_missing_key({"fuel": 2.0}), "oil")
        self.assertEqual(worst_missing_key({}), "")

    def test_outline(self) -> None:
        self.assertEqual(outline_for_fill_ratio(0.0), "stopped")
        self.assertEqual(outline_for_fill_ratio(0.4), "short")
        self.assertEqual(outline_for_fill_ratio(1.0), "ok")

    def test_marker_player_only(self) -> None:
        ger = factory_shortage_marker(
            pid=GER_INDUSTRY_DEFAULT,
            missing={"oil": 3.0},
            fill_ratio=0.0,
            owner_tag="GER",
            player_tag="GER",
        )
        self.assertTrue(ger.get("ok"), msg=ger)
        self.assertEqual(ger.get("missing_key"), "oil")
        self.assertEqual(ger.get("outline"), "stopped")
        self.assertEqual(ger.get("action"), "shortage")
        fra = factory_shortage_marker(
            pid=GER_INDUSTRY_DEFAULT,
            missing={"oil": 3.0},
            fill_ratio=0.0,
            owner_tag="FRA",
            player_tag="GER",
        )
        self.assertFalse(fra.get("ok"))
        ok_fill = factory_shortage_marker(
            pid=GER_INDUSTRY_DEFAULT,
            missing={"oil": 3.0},
            fill_ratio=1.0,
            owner_tag="GER",
            player_tag="GER",
        )
        self.assertFalse(ok_fill.get("ok"))

    def test_cap(self) -> None:
        rows = [
            {
                "pid": 710300 + i,
                "missing": {"steel": 1.0},
                "fill_ratio": 0.2,
                "owner_tag": "GER",
                "player_tag": "GER",
            }
            for i in range(40)
        ]
        capped = cap_shortage_markers(rows, max_n=MAX_MARKERS)
        self.assertEqual(len(capped), MAX_MARKERS)

    def test_product_integrity(self) -> None:
        p = build_map_factory_shortage_surface_product()
        self.assertTrue(p.get("ok"), msg=p)
        lyr = LAYER.read_text(encoding="utf-8")
        self.assertIn("func _draw", lyr)
        self.assertNotIn("ColorRect", lyr)
        self.assertNotIn("Control", lyr)

    def test_industry_marks_zoom_child_not_parent_draw(self) -> None:
        infra = (ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd").read_text(
            encoding="utf-8"
        )
        draw_i = infra.find("func _draw(")
        nxt = infra.find("\nfunc ", draw_i + 1)
        draw_slice = infra[draw_i : nxt if nxt > 0 else draw_i + 2500]
        vis_i = infra.find("func _update_sub_layer_visibilities")
        nxt = infra.find("\nfunc ", vis_i + 1)
        vis_slice = infra[vis_i : nxt if nxt > 0 else vis_i + 2500]
        self.assertIn("class IndustryMarksDraw", infra)
        self.assertIn("PlayerIndustryMarks", infra)
        self.assertNotIn("_draw_player_industry_marks", draw_slice)
        self.assertIn("industry_layer.visible", vis_slice)
        self.assertIn("site_z", vis_slice)
        sites_i = infra.find("func rebuild_sites_layer")
        nxt = infra.find("\nfunc ", sites_i + 1)
        sites_slice = infra[sites_i : nxt if nxt > 0 else sites_i + 8000]
        self.assertNotIn("ColorRect.new()", sites_slice)


if __name__ == "__main__":
    unittest.main()
