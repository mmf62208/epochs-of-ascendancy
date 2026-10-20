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
        # The three Black Sea zones now tile the window's water, so the
        # cosmetic sea list is empty. Galicia / Bessarabia keep the land list.
        provinces = load_province_rings()
        report = witness_report(mask, provinces)
        # GAP-USSR-WEST filled Kiev, Crimea, and the Black Sea witness.
        # GAP-BELARUS filled Minsk and Vitebsk. Galicia / Bessarabia holes
        # keep the land mask nonempty.
        self.assertFalse(report["kiev_in_land"], report)
        self.assertEqual(report["kiev_in_province"], 905889, report)
        self.assertFalse(report["crimea_in_land"], report)
        self.assertEqual(report["crimea_in_province"], 905896, report)
        self.assertFalse(report["black_sea_in_sea"], report)
        self.assertFalse(report["black_sea_in_land"], report)
        self.assertIn(report["black_sea_in_province"], (950006, 950123, 950124), report)
        self.assertEqual(report["owned_centroid_hits"], 0, report)
        self.assertEqual(report["overlap_samples"], 0, report)
        self.assertGreater(report["land_rings"], 0, report)
        self.assertEqual(report["sea_rings"], 0, report)

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
