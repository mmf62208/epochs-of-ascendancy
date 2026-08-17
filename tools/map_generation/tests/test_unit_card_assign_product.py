#!/usr/bin/env python3
"""Gates: thin unit-card halt / withdraw / assign + start_land_battle."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_card_assign_product import (  # noqa: E402
    build_unit_card_assign_product,
    unit_card_assign_integrity,
)


class TestUnitCardAssignProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_unit_card_assign_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        g = unit_card_assign_integrity(check_wiring=True)
        self.assertTrue(g.get("ok"), msg=g)


if __name__ == "__main__":
    unittest.main()
