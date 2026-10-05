#!/usr/bin/env python3
"""Gate: Begin tip, Fill%/TOE readout, empty-land distant card."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from first_session_readability_product import (  # noqa: E402
    TIP_TEXT,
    build_first_session_readability_product,
)


class TestFirstSessionReadabilityProduct(unittest.TestCase):
    def test_product_ok(self) -> None:
        p = build_first_session_readability_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS")
        self.assertEqual(p.get("tip_text"), TIP_TEXT)
        wiring = p.get("wiring") or {}
        for key in (
            "begin_tip_pass_through",
            "fill_toe_card_readable",
            "selected_land_chip_fill_toe",
            "empty_land_hit_disk_only",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))


if __name__ == "__main__":
    unittest.main()
