#!/usr/bin/env python3
"""FEED-4: one Med basin (Alboran) coarser than leftover seed + coastal land."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from seas_coarsen_feed4_product import (  # noqa: E402
    ALBORAN_AREA_MIN,
    ALBORAN_ID,
    CADIZ_ID,
    CEUTA_ID,
    GIBRALTAR_ID,
    GREAT_LAKE_IDS,
    PRE_ALBORAN_AREA,
    PRE_THEATER_MEDIAN,
    STRAIT_ID,
    build_seas_coarsen_feed4_product,
    polygon_area,
    seas_coarsen_feed4_integrity,
)

D = ROOT / "data" / "provinces_world_accurate"
DOC = ROOT / "docs" / "MAP_SEAS_COARSEN_FEED4.md"
WF = ROOT / "data" / "provinces_world_full"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestSeasCoarsenFeed4Product(unittest.TestCase):
    def test_product_coarsens_alboran_basin(self) -> None:
        p = build_seas_coarsen_feed4_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertFalse(p.get("renumbered"))
        self.assertEqual(list(p.get("reused_ids") or []), [ALBORAN_ID])
        self.assertEqual(list(p.get("new_ids") or []), [])
        area = float(p.get("alboran_area") or 0.0)
        self.assertGreaterEqual(area, ALBORAN_AREA_MIN)
        self.assertGreater(area, PRE_ALBORAN_AREA)
        metrics = p.get("metrics") or {}
        self.assertGreater(float(metrics.get("median") or 0.0), PRE_THEATER_MEDIAN)
        self.assertGreater(area, float(p.get("iberian_coastal_median") or 0.0))

    def test_integrity(self) -> None:
        g = seas_coarsen_feed4_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_existing_ids_preserved_and_alboran_reused(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertEqual(base[ALBORAN_ID]["name"], "Alboran Sea")
        self.assertEqual(str(base[ALBORAN_ID].get("domain")), "sea")
        self.assertEqual(base[STRAIT_ID]["name"], "Gibraltar Strait Zone")
        self.assertEqual(str(base[STRAIT_ID].get("domain")), "strait")
        self.assertEqual(base[CADIZ_ID]["name"], "Cádiz")
        self.assertEqual(base[CEUTA_ID]["name"], "Ceuta")
        self.assertEqual(base[GIBRALTAR_ID]["name"], "Gibraltar")
        self.assertEqual(str(base[GIBRALTAR_ID].get("domain")), "land")
        area = polygon_area(geo[ALBORAN_ID].get("points") or [])
        self.assertGreaterEqual(area, ALBORAN_AREA_MIN)
        self.assertLess(polygon_area(geo[GIBRALTAR_ID].get("points") or []), 25.0)

    def test_strait_choke_and_alboran_adjacency(self) -> None:
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        alb = [int(x) for x in (adj.get(str(ALBORAN_ID)) or [])]
        st = [int(x) for x in (adj.get(str(STRAIT_ID)) or [])]
        self.assertIn(STRAIT_ID, alb)
        self.assertIn(ALBORAN_ID, st)
        self.assertIn(GIBRALTAR_ID, st)
        gib = [int(x) for x in (adj.get(str(GIBRALTAR_ID)) or [])]
        self.assertIn(CADIZ_ID, gib)
        self.assertIn(STRAIT_ID, gib)
        self.assertNotIn(CEUTA_ID, gib)
        choke = json.loads((D / "naval_chokepoints.json").read_text(encoding="utf-8"))
        self.assertIn(STRAIT_ID, [int(x) for x in (choke.get("chokepoint_province_ids") or [])])

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
        if WF.is_dir():
            wf_ids = {
                int(p["id"])
                for p in json.loads((WF / "provinces_base.json").read_text(encoding="utf-8")).get("provinces")
                or []
            }
            # Dual scaffold must not be rewritten; Alboran ID may already exist there.
            self.assertNotIn(GIBRALTAR_ID, wf_ids)

    def test_design_note_documents_mike_bar_and_metrics(self) -> None:
        self.assertTrue(DOC.is_file(), DOC)
        body = DOC.read_text(encoding="utf-8")
        self.assertIn("FEED-4", body)
        self.assertIn("Never renumber", body)
        self.assertIn("950128", body)
        self.assertIn("950019", body)
        self.assertIn("711520", body)
        self.assertIn("Alboran", body)
        self.assertIn("before", body.lower())
        self.assertIn("after", body.lower())


if __name__ == "__main__":
    unittest.main()
