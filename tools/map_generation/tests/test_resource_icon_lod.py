#!/usr/bin/env python3
"""Pure gates for resource icon zoom LOD (InfrastructureOverlayLayer)."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INFRA = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"


class TestResourceIconLOD(unittest.TestCase):
    def setUp(self) -> None:
        self.src = INFRA.read_text(encoding="utf-8")

    def test_constants_and_helper_exist(self) -> None:
        self.assertIn("RESOURCE_ZOOM_STRATEGIC", self.src)
        self.assertIn("RESOURCE_ZOOM_BULK", self.src)
        self.assertIn("func resource_icon_min_zoom_for", self.src)
        # Strategic earlier than bulk
        m_s = re.search(r"RESOURCE_ZOOM_STRATEGIC\s*:=\s*([0-9.]+)", self.src)
        m_b = re.search(r"RESOURCE_ZOOM_BULK\s*:=\s*([0-9.]+)", self.src)
        self.assertIsNotNone(m_s)
        self.assertIsNotNone(m_b)
        self.assertLess(float(m_s.group(1)), float(m_b.group(1)))
        self.assertLessEqual(float(m_s.group(1)), 0.40)

    def test_draw_path_uses_helper(self) -> None:
        self.assertIn("resource_icon_min_zoom_for(primary)", self.src)
        self.assertIn("oil", self.src)
        self.assertIn("uranium", self.src)
        self.assertIn("_draw_resource_icons_culled", self.src)
        self.assertIn("max_resource_icons_for_board", self.src)
        self.assertIn("var show_resource_icons: bool = false", self.src)
        self.assertIn("func set_map_mode_for_glyphs", self.src)
        draw_i = self.src.find("func _draw():")
        draw_slice = self.src[draw_i : draw_i + 900]
        self.assertIn("if show_resource_icons:", draw_slice)
        culled = self.src[self.src.find("func _draw_resource_icons_culled") :]
        culled = culled[: culled.find("\nfunc ", 1)]
        self.assertIn("if not show_resource_icons:", culled)
        self.assertNotIn("draw_circle", culled)
        self.assertNotIn("draw_string", culled)


if __name__ == "__main__":
    unittest.main(verbosity=2)
