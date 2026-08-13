#!/usr/bin/env python3
"""Gates for multi-theater grand province dataset."""
from __future__ import annotations

import json
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GT = ROOT / "data" / "provinces_grand_theater"


class TestGrandTheater(unittest.TestCase):
    def test_dataset_exists_and_scale(self) -> None:
        self.assertTrue((GT / "provinces_base.json").exists())
        self.assertTrue((GT / "provinces_geometry.json").exists())
        base = json.loads((GT / "provinces_base.json").read_text())
        geom = json.loads((GT / "provinces_geometry.json").read_text())
        provs = base["provinces"]
        gprovs = geom["provinces"]
        self.assertEqual(len(provs), len(gprovs))
        self.assertGreaterEqual(len(provs), 700)
        self.assertEqual({p["id"] for p in provs}, {g["id"] for g in gprovs})

    def test_facility_and_domain_fields(self) -> None:
        provs = json.loads((GT / "provinces_base.json").read_text())["provinces"]
        for p in provs:
            self.assertIn(p.get("facility_tier"), ("full", "limited", "anchor_only", "none"))
            self.assertIn(
                p.get("domain"),
                ("land", "sea", "strait", "lake", "coastal_land", "coastal"),
            )
        sea = sum(1 for p in provs if p.get("domain") in ("sea", "strait"))
        self.assertGreaterEqual(sea / len(provs), 0.08)
        theaters = Counter(p.get("theater") for p in provs)
        self.assertIn("europe_core", theaters)
        self.assertIn("mena_africa", theaters)
        self.assertIn("far_east", theaters)
        self.assertIn("sea", theaters)

    def test_scenario_points_here(self) -> None:
        scen = ROOT / "data" / "scenarios" / "grand_theater.json"
        self.assertTrue(scen.exists())
        data = json.loads(scen.read_text())
        self.assertEqual(data.get("use_province_data_dir"), "provinces_grand_theater")

    def test_no_triangles(self) -> None:
        geom = json.loads((GT / "provinces_geometry.json").read_text())["provinces"]
        sizes = [len(g.get("points") or []) for g in geom]
        self.assertEqual(sum(1 for s in sizes if s < 3), 0)
        self.assertGreaterEqual(sorted(sizes)[len(sizes) // 2], 12)


if __name__ == "__main__":
    unittest.main(verbosity=2)
