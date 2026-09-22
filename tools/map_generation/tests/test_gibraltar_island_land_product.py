#!/usr/bin/env python3
"""FEED-3: Gibraltar dedicated island-scale land on world_accurate."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gibraltar_island_land_product import (  # noqa: E402
    CADIZ_ID,
    CEUTA_ID,
    GIBRALTAR_ID,
    ISLAND_AREA_MAX,
    ISLAND_AREA_MIN,
    STRAIT_ID,
    build_gibraltar_island_land_product,
    gibraltar_island_land_integrity,
    polygon_area,
)

D = ROOT / "data" / "provinces_world_accurate"
DOC = ROOT / "docs" / "MAP_GIBRALTAR_ISLAND_LAND.md"
WF = ROOT / "data" / "provinces_world_full"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestGibraltarIslandLandProduct(unittest.TestCase):
    def test_product_carves_island_scale_rock(self) -> None:
        p = build_gibraltar_island_land_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertFalse(p.get("renumbered"))
        self.assertEqual(list(p.get("new_ids") or []), [GIBRALTAR_ID])
        area = float(p.get("gibraltar_area") or 0.0)
        self.assertGreaterEqual(area, ISLAND_AREA_MIN)
        self.assertLessEqual(area, ISLAND_AREA_MAX)

    def test_integrity(self) -> None:
        g = gibraltar_island_land_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_existing_ids_preserved_and_gibraltar_appended(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertEqual(base[CADIZ_ID]["name"], "Cádiz")
        self.assertEqual(base[CEUTA_ID]["name"], "Ceuta")
        self.assertEqual(base[STRAIT_ID]["name"], "Gibraltar Strait Zone")
        self.assertEqual(str(base[STRAIT_ID].get("domain")), "strait")
        self.assertIn(GIBRALTAR_ID, base)
        self.assertIn(GIBRALTAR_ID, geo)
        self.assertEqual(base[GIBRALTAR_ID]["name"], "Gibraltar")
        self.assertEqual(str(base[GIBRALTAR_ID].get("domain")), "land")
        self.assertLess(int(GIBRALTAR_ID), 800000)
        self.assertGreaterEqual(int(GIBRALTAR_ID), 711520)
        area = polygon_area(geo[GIBRALTAR_ID].get("points") or [])
        cadiz_area = polygon_area(geo[CADIZ_ID].get("points") or [])
        self.assertGreaterEqual(area, ISLAND_AREA_MIN)
        self.assertLess(area, cadiz_area)

    def test_isthmus_and_strait_adjacency(self) -> None:
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        gib = [int(x) for x in (adj.get(str(GIBRALTAR_ID)) or [])]
        self.assertIn(CADIZ_ID, gib)
        self.assertIn(STRAIT_ID, gib)
        self.assertNotIn(CEUTA_ID, gib)
        self.assertIn(GIBRALTAR_ID, [int(x) for x in (adj.get(str(CADIZ_ID)) or [])])
        self.assertIn(GIBRALTAR_ID, [int(x) for x in (adj.get(str(STRAIT_ID)) or [])])

    def test_gibraltar_id_not_hong_kong_and_no_world_full_write(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertNotEqual(str(base[GIBRALTAR_ID].get("name") or "").lower(), "hong kong")
        if WF.is_dir():
            wf_ids = {
                int(p["id"])
                for p in json.loads((WF / "provinces_base.json").read_text(encoding="utf-8")).get("provinces")
                or []
            }
            self.assertNotIn(GIBRALTAR_ID, wf_ids)

    def test_design_note_documents_id_rule(self) -> None:
        self.assertTrue(DOC.is_file(), DOC)
        body = DOC.read_text(encoding="utf-8")
        self.assertIn("FEED-3", body)
        self.assertIn("Never renumber", body)
        self.assertIn("711520", body)
        self.assertIn("950019", body)
        self.assertIn("710671", body)
        self.assertIn("island-scale", body)
        self.assertIn("Hong Kong", body)


if __name__ == "__main__":
    unittest.main()
