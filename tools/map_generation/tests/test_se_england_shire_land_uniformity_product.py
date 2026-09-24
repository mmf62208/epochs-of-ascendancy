#!/usr/bin/env python3
"""FEED-9: SE England shire corridor land cells more uniform on world_accurate."""
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
from seas_coarsen_feed8_ligurian_product import build_seas_coarsen_feed8_ligurian_product  # noqa: E402
from se_england_shire_land_uniformity_product import (  # noqa: E402
    FROZEN_MESH_AREA,
    GIBRALTAR_ID,
    HAMPSHIRE_ID,
    LIGURIAN_ID,
    LONDON_CAPITAL_ID,
    OXFORDSHIRE_ID,
    PRIMARY_CHILD_ID,
    RESERVED_PRIOR_IDS,
    SECONDARY_CHILD_ID,
    THEATER_LONLAT,
    build_se_england_shire_land_uniformity_product,
    polygon_area,
    se_england_shire_land_uniformity_integrity,
)
from unit_card_fill_toe_visibility_product import (  # noqa: E402
    build_unit_card_fill_toe_visibility_product,
)

D = ROOT / "data" / "provinces_world_accurate"
DOC = ROOT / "docs" / "MAP_SE_ENGLAND_SHIRE_LAND_UNIFORMITY.md"
WF = ROOT / "data" / "provinces_world_full"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestSeEnglandShireLandUniformityProduct(unittest.TestCase):
    def test_product_reduces_theater_extremes(self) -> None:
        p = build_se_england_shire_land_uniformity_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertFalse(p.get("renumbered"))
        self.assertIn(PRIMARY_CHILD_ID, list(p.get("new_ids") or []))
        self.assertGreaterEqual(int(p.get("theater_n") or 0), 35)
        metrics = p.get("metrics") or {}
        self.assertLess(float(metrics.get("max") or 999), 290.0)
        self.assertLessEqual(float(metrics.get("max_over_median") or 99), 5.35)
        pre = p.get("pre_feed_metrics") or {}
        self.assertEqual(int(pre.get("n") or 0), 38)
        self.assertAlmostEqual(float(pre.get("max") or 0), 231.07, places=1)
        self.assertAlmostEqual(float(pre.get("median") or 0), 33.35, places=1)
        self.assertAlmostEqual(float(pre.get("max_over_median") or 0), 6.93, places=2)

    def test_integrity(self) -> None:
        g = se_england_shire_land_uniformity_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_existing_ids_preserved_and_children_appended(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertIn(OXFORDSHIRE_ID, base)
        self.assertIn(OXFORDSHIRE_ID, geo)
        self.assertEqual(base[OXFORDSHIRE_ID]["name"], "Oxfordshire")
        self.assertEqual(str(base[OXFORDSHIRE_ID].get("domain")), "land")
        self.assertIn(HAMPSHIRE_ID, base)
        self.assertEqual(base[HAMPSHIRE_ID]["name"], "Central Hampshire")
        self.assertEqual(base[GIBRALTAR_ID]["name"], "Gibraltar")
        self.assertIn(PRIMARY_CHILD_ID, base)
        self.assertIn(PRIMARY_CHILD_ID, geo)
        self.assertEqual(str(base[PRIMARY_CHILD_ID].get("domain")), "land")
        self.assertLess(int(PRIMARY_CHILD_ID), 800000)
        self.assertGreaterEqual(int(PRIMARY_CHILD_ID), 711523)
        self.assertNotIn(PRIMARY_CHILD_ID, set(RESERVED_PRIOR_IDS))
        for pid in RESERVED_PRIOR_IDS:
            self.assertIn(int(pid), base, pid)
            self.assertIn(int(pid), geo, pid)
        if SECONDARY_CHILD_ID in base:
            self.assertEqual(str(base[SECONDARY_CHILD_ID].get("domain")), "land")
            self.assertGreaterEqual(int(SECONDARY_CHILD_ID), 711523)
            self.assertNotIn(SECONDARY_CHILD_ID, set(RESERVED_PRIOR_IDS))

    def test_no_london_grow_and_oxfordshire_family_adjacent(self) -> None:
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        ox_nbrs = [int(x) for x in (adj.get(str(OXFORDSHIRE_ID)) or [])]
        child_nbrs = [int(x) for x in (adj.get(str(PRIMARY_CHILD_ID)) or [])]
        self.assertTrue(
            PRIMARY_CHILD_ID in ox_nbrs or OXFORDSHIRE_ID in child_nbrs,
            (ox_nbrs, child_nbrs),
        )
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertAlmostEqual(
            polygon_area(geo[HAMPSHIRE_ID].get("points") or []),
            FROZEN_MESH_AREA[HAMPSHIRE_ID],
            places=1,
        )
        self.assertAlmostEqual(
            polygon_area(geo[LONDON_CAPITAL_ID].get("points") or []),
            FROZEN_MESH_AREA[LONDON_CAPITAL_ID],
            places=1,
        )
        self.assertAlmostEqual(
            polygon_area(geo[LIGURIAN_ID].get("points") or []),
            FROZEN_MESH_AREA[LIGURIAN_ID],
            places=1,
        )

    def test_prior_feed_products_and_fill_toe_still_pass(self) -> None:
        self.assertTrue(build_great_lakes_water_province_product().get("ok"))
        self.assertTrue(build_maginot_land_uniformity_product().get("ok"))
        self.assertTrue(build_gibraltar_island_land_product().get("ok"))
        self.assertTrue(build_seas_coarsen_feed4_product().get("ok"))
        self.assertTrue(build_hong_kong_island_land_product().get("ok"))
        self.assertTrue(build_caribbean_island_sizing_product().get("ok"))
        self.assertTrue(build_flanders_nord_land_uniformity_product().get("ok"))
        self.assertTrue(build_seas_coarsen_feed8_ligurian_product().get("ok"))
        self.assertTrue(build_unit_card_fill_toe_visibility_product().get("ok"))

    def test_world_full_not_required_and_europe_append_only(self) -> None:
        if WF.is_dir():
            wf_ids = {
                int(p["id"])
                for p in json.loads((WF / "provinces_base.json").read_text(encoding="utf-8")).get(
                    "provinces"
                )
                or []
            }
            self.assertNotIn(PRIMARY_CHILD_ID, wf_ids)
            self.assertNotIn(SECONDARY_CHILD_ID, wf_ids)

    def test_pale_map_and_design_note(self) -> None:
        self.assertTrue(RENDERER.is_file(), RENDERER)
        self.assertIn("pale-map residual", RENDERER.read_text(encoding="utf-8"))
        self.assertTrue(DOC.is_file(), DOC)
        body = DOC.read_text(encoding="utf-8")
        self.assertIn("FEED-9", body)
        self.assertIn("Never renumber", body)
        self.assertIn("711523", body)
        self.assertIn("711438", body)
        self.assertIn("original_centroid", body)
        self.assertIn("HOLD merge", body)
        self.assertIn("max / median", body)
        lon0, lat0, lon1, lat1 = THEATER_LONLAT
        self.assertIn(str(lon0), body)
        self.assertIn(str(lat0), body)
        self.assertIn(str(lon1), body)
        self.assertIn(str(lat1), body)


if __name__ == "__main__":
    unittest.main()
