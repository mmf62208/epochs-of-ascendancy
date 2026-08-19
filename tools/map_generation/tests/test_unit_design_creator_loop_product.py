#!/usr/bin/env python3
"""Gate: unit designer symbol/strength + type SFX wiring."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_design_creator_loop_product import (  # noqa: E402
    build_unit_design_creator_loop_product,
    unit_design_creator_loop_integrity,
)
from land_battle_bubble_product import (  # noqa: E402
    build_land_battle_bubble_product,
)


class TestUnitDesignCreatorLoopProduct(unittest.TestCase):
    def test_product_wiring(self) -> None:
        p = build_unit_design_creator_loop_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        i = unit_design_creator_loop_integrity()
        self.assertTrue(i.get("ok"), msg=i)

    def test_bubble_sfx_keys_still_green(self) -> None:
        b = build_land_battle_bubble_product(check_wiring=True)
        self.assertTrue(b.get("ok"), msg=b)


if __name__ == "__main__":
    unittest.main()
