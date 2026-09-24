#!/usr/bin/env python3
"""FEED-10: one Med basin (Tyrrhenian) on the real west-Italy basin, not leftover seed."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from caribbean_island_sizing_feed6_product import (  # noqa: E402
    build_caribbean_island_sizing_product,
)
from flanders_nord_land_uniformity_product import (  # noqa: E402
    build_flanders_nord_land_uniformity_product,
)
from gibraltar_island_land_product import build_gibraltar_island_land_product  # noqa: E402
from great_lakes_water_province_product import build_great_lakes_water_province_product  # noqa: E402
from hong_kong_island_land_product import build_hong_kong_island_land_product  # noqa: E402
from maginot_land_uniformity_product import build_maginot_land_uniformity_product  # noqa: E402
from se_england_shire_land_uniformity_product import (  # noqa: E402
    build_se_england_shire_land_uniformity_product,
)
from seas_coarsen_feed4_product import build_seas_coarsen_feed4_product  # noqa: E402
from seas_coarsen_feed8_ligurian_product import build_seas_coarsen_feed8_ligurian_product  # noqa: E402
from seas_coarsen_feed10_tyrrhenian_product import (  # noqa: E402
    ALBORAN_ID,
    CORE_COAST_IDS,
    GREAT_LAKE_IDS,
    HAMPSHIRE_ID,
    LIGURIAN_ID,
    OXFORDSHIRE_EAST_ID,
    OXFORDSHIRE_ID,
    OXFORDSHIRE_NORTH_ID,
    PRE_TYRRHENIAN_AREA,
    PRE_TYRRHENIAN_LONLAT,
    PRE_THEATER_MEDIAN,
    ROMA_ID,
    STALE_CLUSTER_SEAS,
    STRAIT_ID,
    TYRRHENIAN_AREA_MIN,
    TYRRHENIAN_ID,
    TYRRHENIAN_SAMPLE_LONLAT,
    build_seas_coarsen_feed10_tyrrhenian_product,
    canvas_to_lonlat,
    lonlat_to_canvas,
    point_in_ring,
    polygon_area,
    polygon_centroid,
    seas_coarsen_feed10_tyrrhenian_integrity,
)

D = ROOT / "data" / "provinces_world_accurate"
DOC = ROOT / "docs" / "MAP_SEAS_COARSEN_FEED10_TYRRHENIAN.md"
WF = ROOT / "data" / "provinces_world_full"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestSeasCoarsenFeed10TyrrhenianProduct(unittest.TestCase):
    def test_product_coarsens_tyrrhenian_basin(self) -> None:
        p = build_seas_coarsen_feed10_tyrrhenian_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertFalse(p.get("renumbered"))
        self.assertEqual(list(p.get("reused_ids") or []), [TYRRHENIAN_ID])
        self.assertEqual(list(p.get("new_ids") or []), [])
        area = float(p.get("tyrrhenian_area") or 0.0)
        self.assertGreaterEqual(area, TYRRHENIAN_AREA_MIN)
        self.assertGreater(area, PRE_TYRRHENIAN_AREA)
        metrics = p.get("metrics") or {}
        self.assertGreater(float(metrics.get("median") or 0.0), PRE_THEATER_MEDIAN)
        self.assertGreaterEqual(area, 3.0 * float(p.get("west_italy_coastal_median") or 0.0))

    def test_integrity(self) -> None:
        g = seas_coarsen_feed10_tyrrhenian_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_existing_ids_preserved_and_tyrrhenian_reused(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertEqual(base[TYRRHENIAN_ID]["name"], "Tyrrhenian Sea")
        self.assertEqual(str(base[TYRRHENIAN_ID].get("domain")), "sea")
        self.assertEqual(base[LIGURIAN_ID]["name"], "Ligurian Sea")
        self.assertEqual(str(base[LIGURIAN_ID].get("domain")), "sea")
        self.assertEqual(base[ALBORAN_ID]["name"], "Alboran Sea")
        self.assertEqual(base[STRAIT_ID]["name"], "Gibraltar Strait Zone")
        self.assertEqual(base[ROMA_ID]["name"], "Roma")
        self.assertEqual(str(base[ROMA_ID].get("domain")), "land")
        area = polygon_area(geo[TYRRHENIAN_ID].get("points") or [])
        self.assertGreaterEqual(area, TYRRHENIAN_AREA_MIN)
        cx, cy = polygon_centroid(geo[TYRRHENIAN_ID].get("points") or [])
        lon, lat = canvas_to_lonlat(cx, cy)
        self.assertGreaterEqual(lon, 9.5)
        self.assertLessEqual(lon, 15.0)
        self.assertGreaterEqual(lat, 38.2)
        self.assertLessEqual(lat, 42.5)
        leftover_x, leftover_y = lonlat_to_canvas(PRE_TYRRHENIAN_LONLAT[0], PRE_TYRRHENIAN_LONLAT[1])
        self.assertFalse(point_in_ring(leftover_x, leftover_y, geo[TYRRHENIAN_ID].get("points") or []))
        leftover_user_x, leftover_user_y = lonlat_to_canvas(5.48, 37.00)
        self.assertFalse(point_in_ring(leftover_user_x, leftover_user_y, geo[TYRRHENIAN_ID].get("points") or []))
        for slon, slat in TYRRHENIAN_SAMPLE_LONLAT:
            sx, sy = lonlat_to_canvas(slon, slat)
            self.assertTrue(point_in_ring(sx, sy, geo[TYRRHENIAN_ID].get("points") or []), (slon, slat))

    def test_theater_adjacency_coast_only(self) -> None:
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        tyr = [int(x) for x in (adj.get(str(TYRRHENIAN_ID)) or [])]
        for pid in CORE_COAST_IDS:
            self.assertIn(pid, tyr, pid)
            self.assertIn(TYRRHENIAN_ID, [int(x) for x in (adj.get(str(pid)) or [])], pid)
        for pid in STALE_CLUSTER_SEAS:
            self.assertNotIn(pid, tyr, pid)
            self.assertNotIn(TYRRHENIAN_ID, [int(x) for x in (adj.get(str(pid)) or [])], pid)
        self.assertNotIn(LIGURIAN_ID, tyr)
        self.assertNotIn(ALBORAN_ID, tyr)
        self.assertNotIn(STRAIT_ID, tyr)

    def test_bans_untouched_and_no_world_full_write(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        sea_block = sum(1 for pid in base if int(pid) >= 950000)
        self.assertEqual(sea_block, 340)
        self.assertEqual(len(base), 3536)
        for pid in GREAT_LAKE_IDS:
            self.assertEqual(str(base[pid].get("domain")), "lake")
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        self.assertIn(710739, [int(x) for x in (adj.get("710173") or [])])
        self.assertEqual(base[710734]["name"], "Nord")
        self.assertAlmostEqual(polygon_area(geo[LIGURIAN_ID].get("points") or []), 1340.58, delta=2.0)
        self.assertAlmostEqual(polygon_area(geo[ALBORAN_ID].get("points") or []), 1881.05, delta=2.0)
        self.assertAlmostEqual(polygon_area(geo[OXFORDSHIRE_ID].get("points") or []), 58.22, delta=0.5)
        self.assertAlmostEqual(polygon_area(geo[HAMPSHIRE_ID].get("points") or []), 215.21, delta=0.5)
        self.assertAlmostEqual(polygon_area(geo[OXFORDSHIRE_NORTH_ID].get("points") or []), 113.73, delta=0.5)
        self.assertAlmostEqual(polygon_area(geo[OXFORDSHIRE_EAST_ID].get("points") or []), 59.12, delta=0.5)
        if WF.is_dir():
            wf_ids = {
                int(p["id"])
                for p in json.loads((WF / "provinces_base.json").read_text(encoding="utf-8")).get("provinces")
                or []
            }
            self.assertNotIn(711520, wf_ids)

    def test_prior_feed_products_still_pass(self) -> None:
        self.assertTrue(build_seas_coarsen_feed8_ligurian_product().get("ok"))
        self.assertTrue(build_seas_coarsen_feed4_product().get("ok"))
        self.assertTrue(build_se_england_shire_land_uniformity_product().get("ok"))
        self.assertTrue(build_flanders_nord_land_uniformity_product().get("ok"))
        self.assertTrue(build_maginot_land_uniformity_product().get("ok"))
        self.assertTrue(build_great_lakes_water_province_product().get("ok"))
        self.assertTrue(build_gibraltar_island_land_product().get("ok"))
        self.assertTrue(build_hong_kong_island_land_product().get("ok"))
        self.assertTrue(build_caribbean_island_sizing_product().get("ok"))

    def test_design_note_documents_mike_bar_and_metrics(self) -> None:
        self.assertTrue(DOC.is_file(), DOC)
        body = DOC.read_text(encoding="utf-8")
        self.assertIn("FEED-10", body)
        self.assertIn("Never renumber", body)
        self.assertIn("950120", body)
        self.assertIn("Tyrrhenian", body)
        self.assertIn("9.5", body)
        self.assertIn("38.2", body)
        self.assertIn("Mike bar", body)
        self.assertIn("before", body.lower())
        self.assertIn("after", body.lower())
        self.assertIn("FEED-8", body)


if __name__ == "__main__":
    unittest.main()
