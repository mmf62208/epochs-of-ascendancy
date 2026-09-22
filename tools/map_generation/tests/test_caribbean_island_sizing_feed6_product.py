#!/usr/bin/env python3
"""FEED-6: Windward ordinary islands smaller than mainland on world_accurate."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from caribbean_island_sizing_feed6_product import (  # noqa: E402
    ALBORAN_ID,
    BARBADOS_ID,
    CADIZ_ID,
    CEUTA_ID,
    FRA_MAGINOT_ID,
    GER_MAGINOT_ID,
    GIBRALTAR_ID,
    GREAT_LAKE_IDS,
    GRENADA_ID,
    ISLAND_AREA_MAX,
    ISLAND_AREA_MIN,
    ISLAND_SAMPLES,
    MAINLAND_AREA_FLOOR,
    MAINLAND_COMPARE_IDS,
    MARTINIQUE_ID,
    NEW_IDS,
    SAINT_LUCIA_ID,
    SAINT_VINCENT_ID,
    SEA_ID,
    STRAIT_ID,
    TRINIDAD_ID,
    build_caribbean_island_sizing_product,
    caribbean_island_sizing_integrity,
    lonlat_to_canvas,
    point_in_ring,
    polygon_area,
)
from gibraltar_island_land_product import build_gibraltar_island_land_product  # noqa: E402
from hong_kong_island_land_product import HONG_KONG_ID, build_hong_kong_island_land_product  # noqa: E402
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
DOC = ROOT / "docs" / "MAP_CARIBBEAN_ISLAND_SIZING_FEED6.md"
WF = ROOT / "data" / "provinces_world_full"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestCaribbeanIslandSizingFeed6Product(unittest.TestCase):
    def test_product_carves_small_dedicated_islands(self) -> None:
        p = build_caribbean_island_sizing_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertFalse(p.get("renumbered"))
        self.assertEqual(list(p.get("new_ids") or []), list(NEW_IDS))
        areas = p.get("areas") or {}
        for pid in NEW_IDS:
            area = float(areas.get(str(int(pid))) or 0.0)
            self.assertGreaterEqual(area, ISLAND_AREA_MIN)
            self.assertLessEqual(area, ISLAND_AREA_MAX)

    def test_integrity(self) -> None:
        g = caribbean_island_sizing_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_existing_ids_preserved_and_islands_appended(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
        }
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        self.assertEqual(base[MARTINIQUE_ID]["name"], "Martinique")
        self.assertEqual(base[TRINIDAD_ID]["name"], "Trinidad and Tobago South")
        self.assertEqual(base[SEA_ID]["name"], "Mid-Atlantic Waters")
        self.assertEqual(str(base[SEA_ID].get("domain")), "sea")
        self.assertEqual(base[HONG_KONG_ID]["name"], "Hong Kong")
        self.assertEqual(base[GIBRALTAR_ID]["name"], "Gibraltar")
        self.assertEqual(base[BARBADOS_ID]["name"], "Barbados")
        self.assertEqual(base[SAINT_LUCIA_ID]["name"], "Saint Lucia")
        self.assertEqual(base[SAINT_VINCENT_ID]["name"], "Saint Vincent")
        self.assertEqual(base[GRENADA_ID]["name"], "Grenada")
        mainland = [polygon_area(geo[pid].get("points") or []) for pid in MAINLAND_COMPARE_IDS]
        self.assertTrue(all(a >= MAINLAND_AREA_FLOOR for a in mainland), mainland)
        for pid in NEW_IDS:
            self.assertIn(pid, base)
            self.assertIn(pid, geo)
            self.assertEqual(str(base[pid].get("domain")), "land")
            self.assertEqual(str(base[pid].get("island_class")), "island")
            area = polygon_area(geo[pid].get("points") or [])
            self.assertGreaterEqual(area, ISLAND_AREA_MIN)
            self.assertLessEqual(area, ISLAND_AREA_MAX)
            self.assertTrue(all(area < m for m in mainland), (pid, area, mainland))

    def test_pickable_void_samples_and_chain_adjacency(self) -> None:
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        for pid, sample in ISLAND_SAMPLES.items():
            ring = geo[int(pid)].get("points") or []
            x, y = lonlat_to_canvas(sample[0], sample[1])
            self.assertTrue(point_in_ring(x, y, ring), pid)
            self.assertFalse(point_in_ring(x, y, geo[MARTINIQUE_ID].get("points") or []))
            self.assertFalse(point_in_ring(x, y, geo[TRINIDAD_ID].get("points") or []))
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        lucia = [int(x) for x in (adj.get(str(SAINT_LUCIA_ID)) or [])]
        self.assertIn(MARTINIQUE_ID, lucia)
        self.assertIn(SAINT_VINCENT_ID, lucia)
        gren = [int(x) for x in (adj.get(str(GRENADA_ID)) or [])]
        self.assertIn(TRINIDAD_ID, gren)
        self.assertIn(SEA_ID, gren)
        self.assertIn(SAINT_LUCIA_ID, [int(x) for x in (adj.get(str(MARTINIQUE_ID)) or [])])
        self.assertIn(GRENADA_ID, [int(x) for x in (adj.get(str(TRINIDAD_ID)) or [])])

    def test_prior_feeds_and_bans_untouched(self) -> None:
        self.assertTrue(build_hong_kong_island_land_product().get("ok"))
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
            for pid in NEW_IDS:
                self.assertNotIn(int(pid), wf_ids)
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
        self.assertIn("FEED-6", body)
        self.assertIn("Never renumber", body)
        self.assertIn("905845", body)
        self.assertIn("ordinary islands", body)
        self.assertIn("711520", body)
        self.assertIn("905844", body)
        self.assertIn("Mike bar", body)


if __name__ == "__main__":
    unittest.main()
