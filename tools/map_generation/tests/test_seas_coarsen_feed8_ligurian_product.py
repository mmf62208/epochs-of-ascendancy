#!/usr/bin/env python3
"""FEED-8: one Med basin (Ligurian) on the real Genoa gulf, not leftover seed."""
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
from seas_coarsen_feed4_product import build_seas_coarsen_feed4_product  # noqa: E402
from seas_coarsen_feed8_ligurian_product import (  # noqa: E402
    ALBORAN_ID,
    CORE_COAST_IDS,
    GENOVA_ID,
    GREAT_LAKE_IDS,
    LIGURIAN_AREA_MIN,
    LIGURIAN_ID,
    LIGURIAN_SAMPLE_LONLAT,
    PRE_LIGURIAN_AREA,
    PRE_LIGURIAN_LONLAT,
    PRE_THEATER_MEDIAN,
    STALE_CLUSTER_SEAS,
    STRAIT_ID,
    TYRRHENIAN_ID,
    build_seas_coarsen_feed8_ligurian_product,
    canvas_to_lonlat,
    lonlat_to_canvas,
    point_in_ring,
    polygon_area,
    polygon_centroid,
    seas_coarsen_feed8_ligurian_integrity,
)

D = ROOT / "data" / "provinces_world_accurate"
DOC = ROOT / "docs" / "MAP_SEAS_COARSEN_FEED8_LIGURIAN.md"
WF = ROOT / "data" / "provinces_world_full"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestSeasCoarsenFeed8LigurianProduct(unittest.TestCase):
    def test_product_coarsens_ligurian_basin(self) -> None:
        p = build_seas_coarsen_feed8_ligurian_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertFalse(p.get("renumbered"))
        self.assertEqual(list(p.get("reused_ids") or []), [LIGURIAN_ID])
        self.assertEqual(list(p.get("new_ids") or []), [])
        area = float(p.get("ligurian_area") or 0.0)
        self.assertGreaterEqual(area, LIGURIAN_AREA_MIN)
        self.assertGreater(area, PRE_LIGURIAN_AREA)
        metrics = p.get("metrics") or {}
        self.assertGreater(float(metrics.get("median") or 0.0), PRE_THEATER_MEDIAN)
        self.assertGreater(area, float(p.get("liguria_provence_coastal_median") or 0.0))

    def test_integrity(self) -> None:
        g = seas_coarsen_feed8_ligurian_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_existing_ids_preserved_and_ligurian_reused(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertEqual(base[LIGURIAN_ID]["name"], "Ligurian Sea")
        self.assertEqual(str(base[LIGURIAN_ID].get("domain")), "sea")
        self.assertEqual(base[TYRRHENIAN_ID]["name"], "Tyrrhenian Sea")
        self.assertEqual(str(base[TYRRHENIAN_ID].get("domain")), "sea")
        self.assertEqual(base[ALBORAN_ID]["name"], "Alboran Sea")
        self.assertEqual(base[STRAIT_ID]["name"], "Gibraltar Strait Zone")
        self.assertEqual(base[GENOVA_ID]["name"], "Genova")
        self.assertEqual(str(base[GENOVA_ID].get("domain")), "land")
        area = polygon_area(geo[LIGURIAN_ID].get("points") or [])
        self.assertGreaterEqual(area, LIGURIAN_AREA_MIN)
        cx, cy = polygon_centroid(geo[LIGURIAN_ID].get("points") or [])
        lon, lat = canvas_to_lonlat(cx, cy)
        self.assertGreaterEqual(lon, 7.5)
        self.assertLessEqual(lon, 10.5)
        self.assertGreaterEqual(lat, 43.0)
        self.assertLessEqual(lat, 44.6)
        leftover_x, leftover_y = lonlat_to_canvas(PRE_LIGURIAN_LONLAT[0], PRE_LIGURIAN_LONLAT[1])
        self.assertFalse(point_in_ring(leftover_x, leftover_y, geo[LIGURIAN_ID].get("points") or []))
        for slon, slat in LIGURIAN_SAMPLE_LONLAT:
            sx, sy = lonlat_to_canvas(slon, slat)
            self.assertTrue(point_in_ring(sx, sy, geo[LIGURIAN_ID].get("points") or []), (slon, slat))

    def test_theater_adjacency_coast_only(self) -> None:
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        lig = [int(x) for x in (adj.get(str(LIGURIAN_ID)) or [])]
        for pid in CORE_COAST_IDS:
            self.assertIn(pid, lig, pid)
            self.assertIn(LIGURIAN_ID, [int(x) for x in (adj.get(str(pid)) or [])], pid)
        for pid in STALE_CLUSTER_SEAS:
            self.assertNotIn(pid, lig, pid)
            self.assertNotIn(LIGURIAN_ID, [int(x) for x in (adj.get(str(pid)) or [])], pid)
        self.assertNotIn(ALBORAN_ID, lig)
        self.assertNotIn(STRAIT_ID, lig)

    def test_bans_untouched_and_no_world_full_write(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        sea_block = sum(1 for pid in base if int(pid) >= 950000)
        self.assertEqual(sea_block, 340)
        for pid in GREAT_LAKE_IDS:
            self.assertEqual(str(base[pid].get("domain")), "lake")
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        self.assertIn(710739, [int(x) for x in (adj.get("710173") or [])])
        self.assertEqual(base[710734]["name"], "Nord")
        if WF.is_dir():
            wf_ids = {
                int(p["id"])
                for p in json.loads((WF / "provinces_base.json").read_text(encoding="utf-8")).get("provinces")
                or []
            }
            self.assertNotIn(711520, wf_ids)

    def test_prior_feed_products_still_pass(self) -> None:
        self.assertTrue(build_seas_coarsen_feed4_product().get("ok"))
        self.assertTrue(build_flanders_nord_land_uniformity_product().get("ok"))
        self.assertTrue(build_maginot_land_uniformity_product().get("ok"))
        self.assertTrue(build_great_lakes_water_province_product().get("ok"))
        self.assertTrue(build_gibraltar_island_land_product().get("ok"))
        self.assertTrue(build_hong_kong_island_land_product().get("ok"))
        self.assertTrue(build_caribbean_island_sizing_product().get("ok"))

    def test_design_note_documents_mike_bar_and_metrics(self) -> None:
        self.assertTrue(DOC.is_file(), DOC)
        body = DOC.read_text(encoding="utf-8")
        self.assertIn("FEED-8", body)
        self.assertIn("Never renumber", body)
        self.assertIn("950119", body)
        self.assertIn("Ligurian", body)
        self.assertIn("7.5", body)
        self.assertIn("43.0", body)
        self.assertIn("Mike bar", body)
        self.assertIn("before", body.lower())
        self.assertIn("after", body.lower())
        self.assertIn("FEED-4", body)


if __name__ == "__main__":
    unittest.main()
