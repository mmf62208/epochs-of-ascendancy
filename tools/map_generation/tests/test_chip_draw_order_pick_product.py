#!/usr/bin/env python3
"""Gate: overlapping chip clicks follow drawn CanvasItem z."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from chip_draw_order_pick_product import (  # noqa: E402
    build_chip_draw_order_pick_product,
)


class TestChipDrawOrderPickProduct(unittest.TestCase):
    def test_product_ok(self) -> None:
        p = build_chip_draw_order_pick_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS")
        self.assertEqual(list(p.get("fail") or []), [])


if __name__ == "__main__":
    unittest.main()
