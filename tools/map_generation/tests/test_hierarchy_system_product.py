#!/usr/bin/env python3
"""Gates: complete 4-tier hierarchy system product + US/Europe samples."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from hierarchy_system_product import (  # noqa
    hierarchy_system_integrity,
    write_all_samples,
    build_us_midwest_sample,
    build_europe_core_sample,
    reassign_province,
    state_size_stats,
    SUPER_REGION_CATALOG,
    SAMPLES_DIR,
)
from state_name_gazetteer import assert_names_shippable  # noqa


class TestHierarchySystem(unittest.TestCase):
    def test_integrity(self):
        g = hierarchy_system_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_us_midwest_structure(self):
        pack = build_us_midwest_sample()
        self.assertEqual(pack["meta"]["state_n"], 4)
        self.assertEqual(pack["meta"]["province_n"], 24)
        names = [s["name"] for s in pack["states"]]
        self.assertEqual(set(names), {"Ohio", "Indiana", "Illinois", "Michigan"})
        self.assertEqual(pack["regions"][0]["name"], "Midwest")
        self.assertEqual(pack["super_regions"][0]["name"], "North America")
        sz = state_size_stats(pack["states"])
        self.assertTrue(sz.get("ok"), msg=sz)
        gate = assert_names_shippable(names)
        self.assertTrue(gate.get("ok"), msg=gate)
        binds = pack["hierarchy_scaffold"]
        self.assertTrue(binds.get("four_tier"))
        self.assertEqual(len(binds["province_to_super_region"]), 24)

    def test_europe_sample_structure(self):
        pack = build_europe_core_sample()
        names = [s["name"] for s in pack["states"]]
        self.assertIn("Flanders", names)
        self.assertIn("Bavaria", names)
        self.assertIn("Île-de-France", names)
        self.assertTrue(assert_names_shippable(names).get("ok"))
        sz = state_size_stats(pack["states"])
        self.assertTrue(sz.get("ok"), msg=sz)
        self.assertEqual(pack["super_regions"][0]["name"], "Europe")

    def test_dynamic_reassign(self):
        pack = build_us_midwest_sample()
        binds = pack["hierarchy_scaffold"]
        # Move Cuyahoga from Ohio(801) to Indiana(802) — gory border
        r = reassign_province(binds, 800001, 802, 704, 7)
        self.assertTrue(r["ok"])
        self.assertEqual(r["before"]["state_id"], 801)
        self.assertEqual(r["after"]["state_id"], 802)
        self.assertEqual(r["after"]["super_region_id"], 7)

    def test_samples_written(self):
        write_all_samples()
        us = SAMPLES_DIR / "us_midwest_sample"
        eu = SAMPLES_DIR / "europe_core_sample"
        for d in (us, eu):
            for f in (
                "province_states.json",
                "strategic_regions.json",
                "super_regions.json",
                "hierarchy_scaffold.json",
                "hierarchy_membership_1936.json",
            ):
                self.assertTrue((d / f).is_file(), msg=f"{d}/{f}")
        cat = json.loads((SAMPLES_DIR / "catalog.json").read_text())
        self.assertGreaterEqual(len(cat.get("super_region_catalog") or []), 10)
        self.assertGreaterEqual(len(SUPER_REGION_CATALOG), 10)

    def test_docs_and_ci(self):
        self.assertTrue((ROOT / "docs" / "MAP_HIERARCHY_SYSTEM_DESIGN.md").is_file())
        self.assertTrue((ROOT / "docs" / "MAP_HIERARCHY_JSON_SCHEMA.md").is_file())
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_hierarchy_system_product.py", ci)
        # Loader four-tier remains wired
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("super_region_id", sl)
        self.assertIn("get_province_super_region_id", sl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
