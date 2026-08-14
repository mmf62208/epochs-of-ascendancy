#!/usr/bin/env python3
"""Gates: first-session assault discoverability surface."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from first_session_assault_surface_product import (  # noqa: E402
    ASSAULT_STEPS,
    build_first_session_assault_surface_product,
    first_session_assault_surface_integrity,
    format_assault_ready_toast,
)

RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"


class TestFirstSessionAssaultSurfaceProduct(unittest.TestCase):
    def test_toast_mentions_ctrl_click(self) -> None:
        t = format_assault_ready_toast(
            attacker_tag="GER",
            from_province_id=710173,
            to_province_id=710739,
            defender_tag="FRA",
        )
        self.assertIn("Ctrl+click", t)
        self.assertIn("GER", t)
        self.assertIn("Assault", t)

    def test_steps(self) -> None:
        self.assertGreaterEqual(len(ASSAULT_STEPS), 4)
        joined = " ".join(ASSAULT_STEPS)
        self.assertIn("Ctrl+click", joined)

    def test_product_ger(self) -> None:
        p = build_first_session_assault_surface_product(
            country_tag="GER", check_wiring=False
        )
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("country_tag"), "GER")
        self.assertIn("Ctrl+click", p.get("toast") or "")
        self.assertGreaterEqual(len(p.get("steps") or []), 4)

    def test_integrity(self) -> None:
        g = first_session_assault_surface_integrity(check_wiring=False)
        self.assertTrue(g.get("ok"), msg=g)

    def test_wiring_assault_hint(self) -> None:
        ren = RENDERER.read_text(encoding="utf-8")
        panel = PANEL.read_text(encoding="utf-8")
        self.assertIn("toast_assault_surface", ren)
        self.assertIn("apply_assault", panel)
        self.assertIn("EOA_PLAY_STRIP", panel)
        p = build_first_session_assault_surface_product(check_wiring=True)
        self.assertTrue(
            p.get("wiring", {}).get("assault_hint_api")
            or p.get("wiring", {}).get("play_strip_assault"),
            msg=p.get("wiring"),
        )

    def test_hang_class_wiring_ok(self) -> None:
        p = build_first_session_assault_surface_product(check_wiring=True)
        wiring = p.get("wiring") or {}
        for key in (
            "execute_no_info_panel",
            "execute_no_force_border",
            "b_path_no_info_panel",
            "capture_no_full_fill",
            "capture_no_full_icons",
            "notify_uses_target_pid",
            "notify_includes_from_pid",
            "busy_clears_in_post_ui_light",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        self.assertTrue(p.get("ok"), msg=p)

    def test_assault_honesty_wiring(self) -> None:
        p = build_first_session_assault_surface_product(check_wiring=True)
        wiring = p.get("wiring") or {}
        for key in (
            "can_assault_has_formation_id",
            "execute_can_with_fid",
            "map_uses_selected_formation",
            "map_uses_preview_assault",
            "map_no_province_insight_toast",
            "map_march_first_distant",
            "can_honest_no_berlin_fallback",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))


if __name__ == "__main__":
    unittest.main()
