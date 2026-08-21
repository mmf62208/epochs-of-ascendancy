#!/usr/bin/env python3
"""Gates: HOI-like unit counter chrome (plate + org/str + docked card)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_counter_chrome_product import (  # noqa: E402
    build_unit_counter_chrome_product,
    unit_counter_chrome_integrity,
)


class TestUnitCounterChromeProduct(unittest.TestCase):
    def test_product_wiring(self) -> None:
        p = build_unit_counter_chrome_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        wiring = p.get("wiring") or {}
        for key in (
            "strategic_cull",
            "lod_strategic_cull",
            "lod_compact_fn",
            "stat_bars",
            "nation_plate",
            "chrome_on_rebuild",
            "docked_unit_card",
            "card_has_stats",
            "pick_skips_hidden_only",
            "shift_u_before_plain_u",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))

    def test_integrity(self) -> None:
        g = unit_counter_chrome_integrity(check_wiring=True)
        self.assertTrue(g.get("ok"), msg=g)


if __name__ == "__main__":
    unittest.main()
