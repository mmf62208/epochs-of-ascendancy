#!/usr/bin/env python3
"""Phase C gate: live border fronts surface (pure format + board + GD wiring)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_live_border_fronts_surface_product import (  # noqa: E402
    build_map_live_border_fronts_surface_product,
    format_live_border_fronts_surface,
    map_live_border_fronts_surface_integrity,
)


class TestMapLiveBorderFrontsSurface(unittest.TestCase):
    def test_format_empty_honest(self) -> None:
        s = format_live_border_fronts_surface([], country_tag="GER")
        self.assertTrue(s.get("ok"))
        self.assertTrue(s.get("empty"))
        self.assertEqual(int(s.get("count", -1)), 0)
        self.assertIn("no enemy border", str(s.get("plain") or "").lower())

    def test_format_rows(self) -> None:
        s = format_live_border_fronts_surface(
            [
                {
                    "province_id": 710739,
                    "from_province_id": 710173,
                    "defender_tag": "FRA",
                    "defender_power": 70.0,
                    "name": "Bas-Rhin",
                },
                {
                    "province_id": 711112,
                    "from_province_id": 710300,
                    "defender_tag": "POL",
                    "name": "Warsaw",
                },
            ],
            country_tag="GER",
        )
        self.assertFalse(s.get("empty"))
        self.assertEqual(int(s.get("count") or 0), 2)
        self.assertEqual(int(s.get("best_province_id") or 0), 710739)
        self.assertIn("Bas-Rhin", str(s.get("plain") or ""))
        self.assertIn("FRA", str(s.get("toast") or ""))
        self.assertEqual(str(s.get("hotkey") or ""), "B")
        self.assertEqual(str(s.get("action") or ""), "show_live_border_fronts")

    def test_product_on_shipped_board(self) -> None:
        p = build_map_live_border_fronts_surface_product(country_tag="GER", max_count=8)
        self.assertTrue(p.get("board_ok"), msg=p)
        self.assertGreaterEqual(int(p.get("count") or 0), 1)
        self.assertGreater(int(p.get("best_province_id") or 0), 0)
        # Prefer Maginot or Polish when present
        plain = str(p.get("plain") or "")
        self.assertTrue(
            p.get("has_fra_edge") or p.get("has_pol_edge") or "vs" in plain.lower(),
            msg=p,
        )

    def test_integrity_wiring(self) -> None:
        g = map_live_border_fronts_surface_integrity()
        self.assertTrue(g.get("ok"), msg=g)


if __name__ == "__main__":
    unittest.main()
