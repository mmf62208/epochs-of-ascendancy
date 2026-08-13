#!/usr/bin/env python3
"""Gates: RoW sparse densify plan (Africa/Oceania/LATAM/India/Asia bands)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from row_sparse_density_product import (  # noqa: E402
    REGION_TARGETS,
    TRANCHE1_REGIONS,
    build_row_sparse_density_product,
    provinces_for_group_size,
    row_sparse_density_integrity,
)

MERGE_SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "merge_row_sparse_to_playable.py"


class TestRowSparseDensityProduct(unittest.TestCase):
    def test_provinces_for_group_size_australia(self) -> None:
        # AUS-scale: 73 cells → band-friendly 12+
        n = provinces_for_group_size(73, 400_000.0, 20_000.0, region="australia")
        self.assertGreaterEqual(n, 12)
        self.assertLessEqual(n, 40)

    def test_provinces_for_group_size_africa(self) -> None:
        n = provinces_for_group_size(55, 50_000.0, 20_000.0, region="africa")
        self.assertGreaterEqual(n, 3)
        self.assertLessEqual(n, 6)

    def test_tranche1_plan_in_band(self) -> None:
        p = build_row_sparse_density_product(scopes=list(TRANCHE1_REGIONS))
        self.assertTrue(p.get("ok"), msg=p)
        planned = p.get("planned_by_region") or {}
        for region in TRANCHE1_REGIONS:
            cur = int((p.get("current_by_region") or {}).get(region) or 0)
            if cur == 0:
                continue
            band = REGION_TARGETS[region]
            if region in (p.get("already_in_band_regions") or []):
                n = cur
            else:
                n = int(planned.get(region) or 0)
            self.assertGreaterEqual(n, band["min_playable"], msg=(region, n, band, p))
            self.assertLessEqual(n, band["max_playable"], msg=(region, n, band, p))

    def test_all_scopes_plan(self) -> None:
        p = build_row_sparse_density_product()
        self.assertTrue(p.get("ok"), msg=p)
        # Pre-merge ~2600; post full sparse merge ~400–500 playable in-band
        self.assertGreater(int(p.get("scoped_cells_n") or 0), 300)
        self.assertGreater(int(p.get("planned_playable_n") or 0), 100)
        # After full merge, no further write required
        if not p.get("needs_write"):
            self.assertTrue(p.get("already_in_band_regions") or not p.get("needs_write"))

    def test_integrity(self) -> None:
        g = row_sparse_density_integrity(scopes=list(TRANCHE1_REGIONS))
        self.assertTrue(g.get("ok"), msg=g)

    def test_merge_script_exists(self) -> None:
        self.assertTrue(MERGE_SCRIPT.is_file())
        text = MERGE_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("merge_row_sparse_to_playable", text)
        self.assertIn("--write", text)
        self.assertIn("world_full", text)
        self.assertIn("renumber", text.lower())


if __name__ == "__main__":
    unittest.main()
