#!/usr/bin/env python3
"""Gates: US county→state density plan for HOI/V3-readable map."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from us_state_province_density_product import (  # noqa: E402
    MAX_US_PLAY,
    MIN_US_PLAY,
    build_us_state_province_density_product,
    us_state_province_density_integrity,
)

RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


class TestUsStateProvinceDensityProduct(unittest.TestCase):
    def test_plan_counties_to_1_4_per_state(self) -> None:
        p = build_us_state_province_density_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(int(p.get("us_state_n") or 0), 52)
        play = int(p.get("planned_playable_us_n") or 0)
        self.assertGreaterEqual(play, MIN_US_PLAY)
        self.assertLessEqual(play, MAX_US_PLAY)
        # 1–4 per state → more than 52, far less than raw counties
        self.assertGreater(play, 52)
        self.assertLess(play, 2000)
        hist = p.get("split_hist") or {}
        self.assertIn(1, hist)
        us_n = int(p.get("us_county_n") or 0)
        if p.get("already_merged"):
            # Post merge_us_counties_to_state_provinces write
            self.assertGreaterEqual(us_n, MIN_US_PLAY)
            self.assertLessEqual(us_n, MAX_US_PLAY)
            self.assertIn("already", str(p.get("recommendation") or "").lower())
        else:
            self.assertGreaterEqual(us_n, 3000)
            self.assertTrue(any(int(hist.get(k, 0)) > 0 for k in (2, 3, 4)))
            self.assertGreater(float(p.get("reduction_pct") or 0), 90.0)
            self.assertIn("1–4", str(p.get("recommendation") or ""))
            self.assertIn("merge_us_counties_to_state_provinces", str(p.get("next_write_step") or ""))

    def test_integrity(self) -> None:
        g = us_state_province_density_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        self.assertEqual(int(g.get("us_state_n") or 0), 52)
        self.assertGreaterEqual(int(g.get("planned_playable_us_n") or 0), MIN_US_PLAY)

    def test_renderer_map_and_toast_wires(self) -> None:
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn('debug_tint_mode == "strain"', ren)
        self.assertIn("_resolve_map_content_bounds", ren)
        self.assertIn("KEY_HOME", ren)
        self.assertIn("KEY_END", ren)
        self.assertIn("ensure_world_navigation_ready", ren)
        self.assertIn("fit_camera_to_full_world", ren)
        self.assertIn("enable_map_wrap: bool = false", ren)
        self.assertIn("world_min_zoom", ren)
        toast = (ROOT / "scripts" / "ui" / "LeaderEventUI.gd").read_text(encoding="utf-8")
        self.assertIn("style_detail_panel_flat", toast)
        self.assertIn("ornamented 9-slice", toast)


if __name__ == "__main__":
    unittest.main()
