#!/usr/bin/env python3
"""Pure tests: sparse RoW densify prep bands (no board rebuild)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from row_sparse_densify_prep_product import (  # noqa: E402
    band_ok,
    build_row_sparse_densify_prep_product,
)


class TestRowSparseDensifyPrep(unittest.TestCase):
    def test_bands(self) -> None:
        self.assertTrue(band_ok(100, "africa"))
        self.assertFalse(band_ok(5, "africa"))
        self.assertTrue(band_ok(20, "australia"))

    def test_product(self) -> None:
        p = build_row_sparse_densify_prep_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertIn("africa", p.get("regions", []))
        self.assertIn("prep", str(p.get("status") or ""))
        self.assertTrue(p.get("ok"), msg=p)


if __name__ == "__main__":
    unittest.main()
