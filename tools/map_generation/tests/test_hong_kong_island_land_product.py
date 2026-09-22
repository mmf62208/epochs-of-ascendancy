#!/usr/bin/env python3
"""FEED-5: Hong Kong dedicated island-scale land on world_accurate."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from hong_kong_island_land_product import (  # noqa: E402
    ALBORAN_ID,
    CADIZ_ID,
    CEUTA_ID,
    FRA_MAGINOT_ID,
    GER_MAGINOT_ID,
    GIBRALTAR_ID,
    GREAT_LAKE_IDS,
    HONG_KONG_ID,
    ISLAND_AREA_MAX,
    ISLAND_AREA_MIN,
    SEA_ID,
    STRAIT_ID,
    YUEN_LONG_ID,
    build_hong_kong_island_land_product,
    hong_kong_island_land_integrity,
    lonlat_to_canvas,
    point_in_ring,
    polygon_area,
)
from gibraltar_island_land_product import build_gibraltar_island_land_product  # noqa: E402
from maginot_land_uniformity_product import build_maginot_land_uniformity_product  # noqa: E402
from seas_coarsen_feed4_product import build_seas_coarsen_feed4_product  # noqa: E402

try:
    import numpy  # noqa: F401
    from PIL import Image  # noqa: F401
    from map_accuracy_qc import run_qc  # noqa: E402
    from ne_full_geometry_align import DEFAULT_NE_LAND  # noqa: E402

    HAS_NE_QC = True
except ImportError:
    HAS_NE_QC = False

D = ROOT / "data" / "provinces_world_accurate"
DOC = ROOT / "docs" / "MAP_HONG_KONG_ISLAND_LAND.md"
WF = ROOT / "data" / "provinces_world_full"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestHongKongIslandLandProduct(unittest.TestCase):
    def test_product_carves_island_scale_key(self) -> None:
        p = build_hong_kong_island_land_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertFalse(p.get("renumbered"))
        self.assertEqual(list(p.get("new_ids") or []), [HONG_KONG_ID])
        area = float(p.get("hong_kong_area") or 0.0)
        self.assertGreaterEqual(area, ISLAND_AREA_MIN)
        self.assertLessEqual(area, ISLAND_AREA_MAX)

    def test_integrity(self) -> None:
        g = hong_kong_island_land_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_existing_ids_preserved_and_hong_kong_appended(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertEqual(base[YUEN_LONG_ID]["name"], "Yuen Long")
        self.assertEqual(base[SEA_ID]["name"], "South China Sea Zone")
        self.assertEqual(str(base[SEA_ID].get("domain")), "sea")
        self.assertEqual(base[GIBRALTAR_ID]["name"], "Gibraltar")
        self.assertEqual(base[STRAIT_ID]["name"], "Gibraltar Strait Zone")
        self.assertEqual(base[ALBORAN_ID]["name"], "Alboran Sea")
        self.assertIn(HONG_KONG_ID, base)
        self.assertIn(HONG_KONG_ID, geo)
        self.assertEqual(base[HONG_KONG_ID]["name"], "Hong Kong")
        self.assertEqual(str(base[HONG_KONG_ID].get("domain")), "land")
        self.assertGreaterEqual(int(HONG_KONG_ID), 900000)
        self.assertLess(int(HONG_KONG_ID), 950000)
        area = polygon_area(geo[HONG_KONG_ID].get("points") or [])
        self.assertGreaterEqual(area, ISLAND_AREA_MIN)
        self.assertLessEqual(area, ISLAND_AREA_MAX)
        self.assertLess(area, polygon_area(geo[CADIZ_ID].get("points") or []))

    def test_pickable_island_and_nt_adjacency(self) -> None:
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        ring = geo[HONG_KONG_ID].get("points") or []
        ix, iy = lonlat_to_canvas(114.169, 22.278)
        kx, ky = lonlat_to_canvas(114.174, 22.319)
        self.assertTrue(point_in_ring(ix, iy, ring))
        self.assertTrue(point_in_ring(kx, ky, ring))
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        hk = [int(x) for x in (adj.get(str(HONG_KONG_ID)) or [])]
        self.assertIn(YUEN_LONG_ID, hk)
        self.assertIn(SEA_ID, hk)
        self.assertIn(HONG_KONG_ID, [int(x) for x in (adj.get(str(YUEN_LONG_ID)) or [])])
        self.assertIn(HONG_KONG_ID, [int(x) for x in (adj.get(str(SEA_ID)) or [])])

    def test_prior_feeds_and_bans_untouched(self) -> None:
        self.assertTrue(build_gibraltar_island_land_product().get("ok"))
        self.assertTrue(build_maginot_land_uniformity_product().get("ok"))
        self.assertTrue(build_seas_coarsen_feed4_product().get("ok"))
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertEqual(base[CADIZ_ID]["name"], "Cádiz")
        self.assertEqual(base[CEUTA_ID]["name"], "Ceuta")
        self.assertEqual(str(base[GER_MAGINOT_ID].get("domain") or "land"), "land")
        self.assertEqual(str(base[FRA_MAGINOT_ID].get("domain") or "land"), "land")
        for pid in GREAT_LAKE_IDS:
            self.assertEqual(str(base[pid].get("domain")), "lake")
        if WF.is_dir():
            wf_ids = {
                int(p["id"])
                for p in json.loads((WF / "provinces_base.json").read_text(encoding="utf-8")).get("provinces")
                or []
            }
            self.assertNotIn(HONG_KONG_ID, wf_ids)
            self.assertNotIn(GIBRALTAR_ID, wf_ids)

    @unittest.skipUnless(HAS_NE_QC, "numpy+Pillow required for map_accuracy_qc")
    def test_map_accuracy_qc_still_hard_ok(self) -> None:
        report = run_qc(D, ne_path=Path(DEFAULT_NE_LAND), sample_limit=0)
        self.assertTrue(report.get("ok_hard"), report.get("errors"))
        self.assertEqual(report.get("orphan_base_only_count"), 0)
        self.assertEqual(report.get("orphan_geo_only_count"), 0)
        self.assertGreaterEqual(int(report.get("matched") or 0), 3000)
        self.assertGreaterEqual(float(report.get("ne_land_hit_rate") or 0.0), 0.90)

    def test_design_note_documents_id_rule(self) -> None:
        self.assertTrue(DOC.is_file(), DOC)
        body = DOC.read_text(encoding="utf-8")
        self.assertIn("FEED-5", body)
        self.assertIn("Never renumber", body)
        self.assertIn("905844", body)
        self.assertIn("902486", body)
        self.assertIn("711520", body)
        self.assertIn("island-scale", body)
        self.assertIn("Mike bar", body)


if __name__ == "__main__":
    unittest.main()
