#!/usr/bin/env python3
"""FEED-2: Maginot corridor land cells more uniform on world_accurate."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from maginot_land_uniformity_product import (  # noqa: E402
    FRA_MAGINOT_ID,
    GER_MAGINOT_ID,
    GROW_SPECS,
    NEW_CHILD_IDS,
    SPLIT_PARENT_IDS,
    build_maginot_land_uniformity_product,
    maginot_land_uniformity_integrity,
    polygon_area,
)

D = ROOT / "data" / "provinces_world_accurate"
DOC = ROOT / "docs" / "MAP_MAGINOT_LAND_UNIFORMITY.md"
WF = ROOT / "data" / "provinces_world_full"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestMaginotLandUniformityProduct(unittest.TestCase):
    def test_product_reduces_theater_extremes(self) -> None:
        p = build_maginot_land_uniformity_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertFalse(p.get("renumbered"))
        self.assertEqual(list(p.get("new_ids") or []), list(NEW_CHILD_IDS))
        self.assertGreaterEqual(int(p.get("theater_n") or 0), 40)
        metrics = p.get("metrics") or {}
        self.assertLess(float(metrics.get("max") or 999), 290.0)
        self.assertLess(float(metrics.get("max_over_median") or 99), 6.0)

    def test_integrity(self) -> None:
        g = maginot_land_uniformity_integrity()
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
        for pid in list(SPLIT_PARENT_IDS) + [GER_MAGINOT_ID, FRA_MAGINOT_ID]:
            self.assertIn(int(pid), base, pid)
            self.assertIn(int(pid), geo, pid)
        self.assertEqual(base[GER_MAGINOT_ID]["name"], "Baden-Baden, Stadtkreis")
        self.assertEqual(base[FRA_MAGINOT_ID]["name"], "Bas-Rhin")
        for pid in NEW_CHILD_IDS:
            self.assertIn(int(pid), base, pid)
            self.assertIn(int(pid), geo, pid)
            self.assertEqual(str(base[pid].get("domain")), "land")
            self.assertLess(int(pid), 800000)
            self.assertGreaterEqual(int(pid), 711514)

    def test_combat_edge_and_grown_front_cells(self) -> None:
        adj = json.loads((D / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency") or {}
        self.assertIn(FRA_MAGINOT_ID, [int(x) for x in (adj.get(str(GER_MAGINOT_ID)) or [])])
        geo = {
            int(g["id"]): g
            for g in json.loads((D / "provinces_geometry.json").read_text(encoding="utf-8"))["provinces"]
        }
        for spec in GROW_SPECS:
            area = polygon_area((geo[int(spec["tiny_id"])].get("points") or []))
            self.assertGreaterEqual(area, 20.0, spec)

    def test_world_full_not_required_and_europe_append_only(self) -> None:
        # Dual scaffold must not be rewritten by this theater proof.
        if WF.is_dir():
            wf_ids = {
                int(p["id"])
                for p in json.loads((WF / "provinces_base.json").read_text(encoding="utf-8")).get("provinces") or []
            }
            for pid in NEW_CHILD_IDS:
                self.assertNotIn(int(pid), wf_ids, pid)

    def test_design_note_documents_metrics_and_id_rule(self) -> None:
        self.assertTrue(DOC.is_file(), DOC)
        body = DOC.read_text(encoding="utf-8")
        self.assertIn("FEED-2", body)
        self.assertIn("Never renumber", body)
        self.assertIn("711514", body)
        self.assertIn("710173", body)
        self.assertIn("710739", body)
        self.assertIn("max / median", body)
        self.assertIn("Alsace", body)


if __name__ == "__main__":
    unittest.main()
