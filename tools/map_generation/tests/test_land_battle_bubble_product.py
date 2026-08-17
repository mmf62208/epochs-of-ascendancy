#!/usr/bin/env python3
"""Gates: HOI-like land battle bubble layer (org plate + Director SFX aliases)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_battle_bubble_product import (  # noqa: E402
    build_land_battle_bubble_product,
    land_battle_bubble_integrity,
)


class TestLandBattleBubbleProduct(unittest.TestCase):
    def test_product_wiring(self) -> None:
        p = build_land_battle_bubble_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        wiring = p.get("wiring") or {}
        for key in (
            "class_name",
            "setup",
            "set_battles",
            "clear_battles",
            "org_in_draw",
            "no_inspector",
            "z_high",
            "sfx_aliases",
            "renderer_sfx_keys",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))

    def test_integrity(self) -> None:
        g = land_battle_bubble_integrity(check_wiring=True)
        self.assertTrue(g.get("ok"), msg=g)

    def test_director_sfx_keys(self) -> None:
        p = build_land_battle_bubble_product(check_wiring=True)
        sfx = p.get("sfx_director") or {}
        self.assertEqual(sfx.get("order_confirm"), "confirm")
        self.assertEqual(sfx.get("daily_clash"), "map")
        self.assertEqual(sfx.get("capture"), "achievement")
        self.assertEqual(sfx.get("bounce"), "error")


if __name__ == "__main__":
    unittest.main()
