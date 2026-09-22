#!/usr/bin/env python3
"""FEED-1: Great Lakes own distinct water provinces on world_accurate."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from great_lakes_water_province_product import (  # noqa: E402
    GREAT_LAKE_IDS,
    LAKE_ERIE_ID,
    LAKE_HURON_ID,
    LAKE_MICHIGAN_ID,
    LAKE_ONTARIO_ID,
    LAKE_SUPERIOR_ID,
    build_great_lakes_water_province_product,
    great_lakes_water_province_integrity,
)

D = ROOT / "data" / "provinces_world_accurate"
DOC = ROOT / "docs" / "MAP_PROVINCE_SIZING_BAR.md"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestGreatLakesWaterProvinceProduct(unittest.TestCase):
    def test_product_lakes_own_in_basin_water_cells(self) -> None:
        p = build_great_lakes_water_province_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("lake_ids") or []), list(GREAT_LAKE_IDS))
        self.assertFalse(p.get("renumbered"))
        self.assertGreaterEqual(int(p.get("theater_land_n") or 0), 8)

    def test_integrity(self) -> None:
        g = great_lakes_water_province_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        self.assertEqual(len(g.get("lake_ids") or []), 5)

    def test_allocated_ids_not_renumbered(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertEqual(base[LAKE_SUPERIOR_ID]["name"], "Lake Superior")
        self.assertEqual(base[LAKE_MICHIGAN_ID]["name"], "Lake Michigan")
        self.assertEqual(base[LAKE_HURON_ID]["name"], "Lake Huron")
        self.assertEqual(base[LAKE_ERIE_ID]["name"], "Lake Erie")
        self.assertEqual(base[LAKE_ONTARIO_ID]["name"], "Lake Ontario")
        for pid in GREAT_LAKE_IDS:
            self.assertEqual(str(base[pid].get("domain")), "lake")
            self.assertIn("lake", list(base[pid].get("special_features") or []))

    def test_theater_land_ids_stay_in_existing_blocks(self) -> None:
        p = build_great_lakes_water_province_product()
        for pid in p.get("theater_land_ids") or []:
            self.assertTrue(800000 <= int(pid) < 950000, pid)

    def test_design_note_documents_mike_bar_and_id_rule(self) -> None:
        self.assertTrue(DOC.is_file(), DOC)
        body = DOC.read_text(encoding="utf-8")
        self.assertIn("Large lakes get their own water provinces", body)
        self.assertIn("Never renumber", body)
        self.assertIn("950333", body)
        self.assertIn("Great Lakes", body)
        self.assertIn("FEED-1", body)


if __name__ == "__main__":
    unittest.main()
