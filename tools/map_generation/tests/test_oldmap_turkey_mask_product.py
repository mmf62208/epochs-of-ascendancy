#!/usr/bin/env python3
"""OLDMAP_TURKEY: uncovered USSR-west mask stays off province rings and is mounted."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from oldmap_turkey_mask_product import (  # noqa: E402
    MASK_PATH,
    full_bbox_land_ring,
    load_mask,
    load_province_rings,
    overlap_samples,
    renderer_mount_ok,
    witness_report,
)


class TestOldmapTurkeyMaskProduct(unittest.TestCase):
    def test_committed_mask_misses_province_rings(self) -> None:
        self.assertTrue(MASK_PATH.is_file(), MASK_PATH)
        mask = load_mask()
        self.assertEqual(mask.get("space"), "canvas")
        self.assertTrue(mask.get("subtracted_province_rings"))
        self.assertGreater(len(mask.get("land") or []), 0)
        self.assertGreater(len(mask.get("sea") or []), 0)
        provinces = load_province_rings()
        report = witness_report(mask, provinces)
        self.assertTrue(report["kiev_in_land"], report)
        self.assertIsNone(report["kiev_in_province"], report)
        self.assertTrue(report["crimea_in_land"], report)
        self.assertTrue(report["black_sea_in_sea"], report)
        self.assertFalse(report["black_sea_in_land"], report)
        self.assertEqual(report["owned_centroid_hits"], 0, report)
        self.assertEqual(report["overlap_samples"], 0, report)

    def test_unsubtracted_window_fails_overlap_guard(self) -> None:
        """Mutant geometry: the bbox itself, province rings not removed."""
        provinces = load_province_rings()
        hits = overlap_samples([full_bbox_land_ring()], provinces, step=8.0)
        self.assertGreater(len(hits), 20, "unsubtracted mask must fail the overlap guard")

    def test_renderer_mounts_mask_under_fills(self) -> None:
        mount = renderer_mount_ok()
        self.assertTrue(mount["ok"], mount)
        self.assertEqual(mount["mask_z"], -14)


if __name__ == "__main__":
    unittest.main()
