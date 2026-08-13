#!/usr/bin/env python3
"""Gates: HOI full-test gap matrix drives real shipped products; open P0 == 0."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from hoi_full_test_gap_matrix_product import (  # noqa: E402
    P0_PILLARS,
    build_hoi_full_test_gap_matrix_product,
    hoi_full_test_gap_matrix_integrity,
)

REVIEW = ROOT / "docs" / "HOI4_EOA_GAP_REVIEW.md"


class TestHoiFullTestGapMatrix(unittest.TestCase):
    def test_review_artifact_exists_with_pillars(self) -> None:
        self.assertTrue(REVIEW.is_file(), REVIEW)
        body = REVIEW.read_text(encoding="utf-8")
        self.assertIn("Open P0 count: 0", body)
        for needle in (
            "Industry",
            "Research",
            "Politics",
            "multi-front",
            "Supply",
            "Air",
            "naval",
            "Espionage",
            "OOB",
            "M6",
            "3520",
        ):
            self.assertIn(needle.lower() if needle.islower() else needle, body if needle[0].isupper() else body.lower())

    def test_matrix_product_zero_open_p0(self) -> None:
        p = build_hoi_full_test_gap_matrix_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertIn("open_p0_n", p)
        self.assertEqual(int(p["open_p0_n"]), 0, msg=p.get("open_p0") or p)
        self.assertGreaterEqual(int(p.get("landed_n") or 0), 15)
        self.assertEqual(int(p.get("pillar_n") or 0), len(P0_PILLARS))
        # Each row must have called a real builder
        for row in p.get("rows") or []:
            self.assertEqual(row.get("status"), "LANDED", msg=row)
            self.assertTrue(row.get("product_ok"), msg=row)

    def test_integrity(self) -> None:
        g = hoi_full_test_gap_matrix_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        self.assertIn("open_p0_n", g)
        self.assertEqual(int(g["open_p0_n"]), 0)

    def test_pillars_import_real_modules(self) -> None:
        lib = ROOT / "tools" / "map_generation" / "lib"
        for _pid, _label, mod_name, fn_name, _kw in P0_PILLARS:
            path = lib / ("%s.py" % mod_name)
            self.assertTrue(path.is_file(), path)
            text = path.read_text(encoding="utf-8")
            self.assertIn("def %s" % fn_name, text)


if __name__ == "__main__":
    unittest.main()
