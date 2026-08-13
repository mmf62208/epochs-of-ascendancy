#!/usr/bin/env python3
"""Director D3.3 — ownership/political mapmode readability pure gates."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from ownership_mapmode_readability_product import (  # noqa: E402
    build_ownership_mapmode_readability_product,
    color_distance,
    ownership_mapmode_readability_integrity,
)

D = ROOT / "data" / "provinces_world_accurate"
SC = ROOT / "data" / "scenarios" / "world_accurate.json"


@unittest.skipUnless(D.is_dir() and SC.is_file(), "accurate board/scenario missing")
class TestOwnershipMapmodeReadability(unittest.TestCase):
    def test_product_pass(self) -> None:
        p = build_ownership_mapmode_readability_product()
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        self.assertEqual(p.get("status"), "PASS")
        # Post full RoW sparse + US playable merge: land ~3180
        self.assertGreaterEqual(int(p.get("land_n") or 0), 3000)
        self.assertEqual(p.get("collisions"), [])
        spheres = p.get("sphere_counts") or {}
        self.assertGreaterEqual(int(spheres.get("USA") or 0), 80)
        self.assertGreaterEqual(int(spheres.get("GER") or 0), 150)

    def test_ger_sov_colors_distinct(self) -> None:
        p = build_ownership_mapmode_readability_product()
        colors = p.get("major_colors") or {}
        self.assertIn("GER", colors)
        self.assertIn("SOV", colors)
        self.assertNotEqual(colors["GER"], colors["SOV"])
        self.assertGreaterEqual(color_distance(colors["GER"], colors["SOV"]), 35.0)

    def test_integrity(self) -> None:
        g = ownership_mapmode_readability_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_sov_color_not_dark_red_collision(self) -> None:
        """Regression: SOV must not share GER #8B0000 (political map unreadable)."""
        body = SC.read_text(encoding="utf-8")
        # Find SOV block color
        import re

        m = re.search(
            r'"tag"\s*:\s*"SOV"[\s\S]*?"color"\s*:\s*"([^"]+)"',
            body,
        )
        self.assertIsNotNone(m)
        self.assertNotEqual(m.group(1).upper(), "#8B0000")


if __name__ == "__main__":
    unittest.main()
