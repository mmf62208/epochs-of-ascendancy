#!/usr/bin/env python3
"""FEED-7: Flanders/Nord corridor land cells more uniform on world_accurate."""
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
    GIBRALTAR_ID,
    NORD_ID,
    PAS_DE_CALAIS_ID,
    PRIMARY_CHILD_ID,
    RESERVED_PRIOR_IDS,
    SECONDARY_CHILD_ID,
    THEATER_LONLAT,
    build_flanders_nord_land_uniformity_product,
    flanders_nord_land_uniformity_integrity,
    polygon_area,
)
from gibraltar_island_land_product import build_gibraltar_island_land_product  # noqa: E402
from great_lakes_water_province_product import build_great_lakes_water_province_product  # noqa: E402
from hong_kong_island_land_product import build_hong_kong_island_land_product  # noqa: E402
from maginot_land_uniformity_product import build_maginot_land_uniformity_product  # noqa: E402
from seas_coarsen_feed4_product import build_seas_coarsen_feed4_product  # noqa: E402

D = ROOT / "data" / "provinces_world_accurate"
DOC = ROOT / "docs" / "MAP_FLANDERS_NORD_LAND_UNIFORMITY.md"
WF = ROOT / "data" / "provinces_world_full"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestFlandersNordLandUniformityProduct(unittest.TestCase):
    def test_product_reduces_theater_extremes(self) -> None:
        p = build_flanders_nord_land_uniformity_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertFalse(p.get("renumbered"))
        self.assertIn(PRIMARY_CHILD_ID, list(p.get("new_ids") or []))
        self.assertGreaterEqual(int(p.get("theater_n") or 0), 26)
        metrics = p.get("metrics") or {}
        self.assertLess(float(metrics.get("max") or 999), 290.0)
        self.assertLessEqual(float(metrics.get("max_over_median") or 99), 5.35)

    def test_integrity(self) -> None:
        g = flanders_nord_land_uniformity_integrity()
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
        self.assertIn(NORD_ID, base)
        self.assertIn(NORD_ID, geo)
        self.assertEqual(base[NORD_ID]["name"], "Nord")
        self.assertEqual(str(base[NORD_ID].get("domain")), "land")
        self.assertIn(PAS_DE_CALAIS_ID, base)
        self.assertEqual(base[PAS_DE_CALAIS_ID]["name"], "Pas-de-Calais")
        self.assertEqual(base[GIBRALTAR_ID]["name"], "Gibraltar")
        self.assertIn(PRIMARY_CHILD_ID, base)
        self.assertIn(PRIMARY_CHILD_ID, geo)
        self.assertEqual(str(base[PRIMARY_CHILD_ID].get("domain")), "land")
        self.assertLess(int(PRIMARY_CHILD_ID), 800000)
        self.assertGreaterEqual(int(PRIMARY_CHILD_ID), 711521)
        self.assertNotIn(PRIMARY_CHILD_ID, set(RESERVED_PRIOR_IDS))
        for pid in RESERVED_PRIOR_IDS:
            self.assertIn(int(pid), base, pid)
            self.assertIn(int(pid), geo, pid)
        if SECONDARY_CHILD_ID in base:
            self.assertEqual(str(base[SECONDARY_CHILD_ID].get("domain")), "land")
            self.assertGreaterEqual(int(SECONDARY_CHILD_ID), 711521)
            self.assertNotIn(SECONDARY_CHILD_ID, set(RESERVED_PRIOR_IDS))

    def test_no_ruhr_grow_and_nord_family_adjacent(self) -> None:
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        nord_nbrs = [int(x) for x in (adj.get(str(NORD_ID)) or [])]
        child_nbrs = [int(x) for x in (adj.get(str(PRIMARY_CHILD_ID)) or [])]
        self.assertTrue(
            PRIMARY_CHILD_ID in nord_nbrs or NORD_ID in child_nbrs,
            (nord_nbrs, child_nbrs),
        )
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        # No Ruhr/NRW grow-pass: West-Noord-Brabant stays its own cell, not a donor.
        if 711028 in geo:
            self.assertGreater(polygon_area(geo[711028].get("points") or []), 80.0)

    def test_prior_feed_products_still_pass(self) -> None:
        self.assertTrue(build_maginot_land_uniformity_product().get("ok"))
        self.assertTrue(build_gibraltar_island_land_product().get("ok"))
        self.assertTrue(build_seas_coarsen_feed4_product().get("ok"))
        self.assertTrue(build_hong_kong_island_land_product().get("ok"))
        self.assertTrue(build_great_lakes_water_province_product().get("ok"))
        self.assertTrue(build_caribbean_island_sizing_product().get("ok"))

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

    def test_design_note_documents_metrics_and_id_rule(self) -> None:
        self.assertTrue(DOC.is_file(), DOC)
        body = DOC.read_text(encoding="utf-8")
        self.assertIn("FEED-7", body)
        self.assertIn("Never renumber", body)
        self.assertIn("711521", body)
        self.assertIn("710734", body)
        self.assertIn("2.5", body)
        self.assertIn("50.3", body)
        self.assertIn("max / median", body)
        self.assertIn("Flanders", body)
        lon0, lat0, lon1, lat1 = THEATER_LONLAT
        self.assertIn(str(lon0), body)
        self.assertIn(str(lat0), body)
        self.assertIn(str(lon1), body)
        self.assertIn(str(lat1), body)


if __name__ == "__main__":
    unittest.main()
