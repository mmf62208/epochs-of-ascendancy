#!/usr/bin/env python3
"""Gate: living unit order loop wiring (Maginot chips + march + assault)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from living_unit_order_loop_product import (  # noqa: E402
    CHI_FRONT,
    FRA_FRONT,
    GER_FRONT,
    JAP_FRONT,
    build_living_unit_order_loop_product,
    living_unit_order_loop_integrity,
)


class TestLivingUnitOrderLoopProduct(unittest.TestCase):
    def test_front_ids(self) -> None:
        self.assertEqual(GER_FRONT, 710173)
        self.assertEqual(FRA_FRONT, 710739)
        self.assertEqual(JAP_FRONT, 903951)
        self.assertEqual(CHI_FRONT, 902505)

    def test_product_wiring(self) -> None:
        p = build_living_unit_order_loop_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        wiring = p.get("wiring") or {}
        for key in (
            "park_maginot",
            "world_oob_majors",
            "chip_str_num",
            "inverse_zoom_scale",
            "chip_on_centroid",
            "pin_before_hex",
            "click_own_land_marches",
            "ctrl_click_starts_battle",
            "g_hang_safe",
            "inspector_close_restores",
            "i_hang_safe",
            "resolve_hang_safe",
            "strategic_pick_skip",
            "march_api",
            "battle_api",
            "f5_boot_and_qa",
            "headless_harness",
            "on_official_quick",
        ):
            self.assertTrue(wiring.get(key), msg=(key, p))

    def test_integrity(self) -> None:
        i = living_unit_order_loop_integrity()
        self.assertTrue(i.get("ok"), msg=i)


if __name__ == "__main__":
    unittest.main()
