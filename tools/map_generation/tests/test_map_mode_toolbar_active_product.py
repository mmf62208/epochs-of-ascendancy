#!/usr/bin/env python3
"""Gates: MapMode toolbar active-mode id → exclusive chip pressed state."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_mode_toolbar_active_product import (  # noqa: E402
    TOOLBAR_MODES,
    build_map_mode_toolbar_active_product,
    map_mode_toolbar_active_integrity,
    normalize_toolbar_mode,
    pressed_mode_id,
    toolbar_pressed_state,
)

TOOLBAR = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"


class TestMapModeToolbarActiveProduct(unittest.TestCase):
    def test_active_mode_id_to_pressed_state(self) -> None:
        first = toolbar_pressed_state("political")
        self.assertTrue(first["political"])
        self.assertEqual(sum(1 for v in first.values() if v), 1)

        after_f2 = toolbar_pressed_state("strain")
        self.assertTrue(after_f2["strain"])
        self.assertFalse(after_f2["political"])
        self.assertEqual(pressed_mode_id(after_f2), "strain")
        self.assertEqual(sum(1 for v in after_f2.values() if v), 1)

        after_terrain = toolbar_pressed_state("terrain")
        self.assertTrue(after_terrain["terrain"])
        self.assertFalse(after_terrain["political"])
        self.assertFalse(after_terrain["strain"])

    def test_unknown_mode_falls_back_political(self) -> None:
        self.assertEqual(normalize_toolbar_mode("Nope"), "political")
        state = toolbar_pressed_state("Nope")
        self.assertTrue(state["political"])
        self.assertEqual(pressed_mode_id(state), "political")

    def test_modes_match_sot(self) -> None:
        src = TOOLBAR.read_text(encoding="utf-8")
        for mode in TOOLBAR_MODES:
            self.assertIn('"%s"' % mode, src)
        self.assertIn("ButtonGroup", src)
        self.assertIn("set_pressed_no_signal", src)
        self.assertIn("func _sync_mode_chip_pressed", src)
        self.assertIn("func get_mode_pressed_state", src)

    def test_product_ok(self) -> None:
        p = build_map_mode_toolbar_active_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS")

    def test_integrity(self) -> None:
        g = map_mode_toolbar_active_integrity()
        self.assertTrue(g.get("ok"), msg=g)


if __name__ == "__main__":
    unittest.main()
