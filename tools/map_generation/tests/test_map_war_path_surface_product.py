#!/usr/bin/env python3
"""Gate: first-session war path surface (flow + fronts + assault discoverability)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_war_path_surface_product import (  # noqa: E402
    build_map_war_path_surface_product,
    format_first_session_war_path,
    map_war_path_surface_integrity,
)

RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
TOOLBAR = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"


class TestMapWarPathSurface(unittest.TestCase):
    def test_format_steps_and_hotkeys(self) -> None:
        s = format_first_session_war_path(
            country_tag="GER",
            flow_on=True,
            fronts=[
                {
                    "province_id": 710739,
                    "from_province_id": 710173,
                    "defender_tag": "FRA",
                    "name": "Bas-Rhin",
                }
            ],
            best_province_id=710739,
        )
        self.assertTrue(s.get("ok"))
        self.assertEqual(int(s.get("best_province_id") or 0), 710739)
        self.assertIn("I", str(s.get("hotkeys") or {}))
        self.assertIn("B", str((s.get("hotkeys") or {}).get("fronts") or "B"))
        self.assertIn("Ctrl+click", str(s.get("plain") or ""))
        self.assertEqual(str(s.get("action") or ""), "show_first_session_war_path")
        self.assertEqual(str(s.get("toolbar_preset") or ""), "WarLoop")

    def test_product_on_board_fronts(self) -> None:
        p = build_map_war_path_surface_product(country_tag="GER")
        self.assertTrue(p.get("ok"), msg=p)
        self.assertGreaterEqual(int(p.get("front_count") or 0), 1)
        self.assertGreater(int(p.get("best_province_id") or 0), 0)

    def test_integrity_wiring(self) -> None:
        g = map_war_path_surface_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn("func show_first_session_war_path", ren)
        self.assertIn("func toggle_equipment_flow_glyphs", ren)
        self.assertIn("KEY_I", ren)
        tb = TOOLBAR.read_text(encoding="utf-8")
        self.assertIn("WarLoop", tb)
        self.assertIn("show_first_session_war_path", tb)


if __name__ == "__main__":
    unittest.main()
