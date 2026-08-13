#!/usr/bin/env python3
"""Gates: full hierarchy membership eras 1910/1918/1936/2026 (primary)."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from membership_era_product import (  # noqa
    PRIMARY_MEMBERSHIP_ERAS,
    membership_era_integrity,
    membership_era_policy,
    resolve_membership_era,
    write_all_board_membership_eras,
    write_membership_era_files,
)

WORLD = ROOT / "data" / "provinces_world_full"
PILOT = ROOT / "data" / "provinces_pilot_europe"
SAMPLES = ROOT / "data" / "hierarchy_samples"


class TestMembershipEras(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Ensure full primary snapshots exist on boards + samples
        write_all_board_membership_eras()

    def test_primary_eras_locked(self):
        self.assertEqual(list(PRIMARY_MEMBERSHIP_ERAS), [1910, 1918, 1936, 2026])
        pol = membership_era_policy()
        self.assertEqual(pol["primary_eras"], [1910, 1918, 1936, 2026])
        self.assertEqual(pol["primary_eras_mode"], "full")
        self.assertFalse(pol["reapply_on_year_tick"])
        self.assertEqual(pol["global_province_target_v1"], 6000)
        self.assertEqual(pol["us_region_set"], "8_band")
        self.assertEqual(pol["fps_gate"], 60)

    def test_resolve(self):
        self.assertEqual(resolve_membership_era(1936), 1936)
        self.assertEqual(resolve_membership_era(2026), 2026)
        self.assertEqual(resolve_membership_era(2020), 1936)
        self.assertEqual(resolve_membership_era(1905), 1910)
        self.assertEqual(resolve_membership_era(1914), 1910)
        self.assertEqual(resolve_membership_era(1919), 1918)

    def test_world_full_primary_full(self):
        g = membership_era_integrity(WORLD)
        self.assertTrue(g.get("ok"), msg=g)
        for d in g.get("details") or []:
            self.assertEqual(d.get("mode"), "full")
            self.assertGreater(int(d.get("province_n") or 0), 1000)
            self.assertTrue(d.get("keys_aligned"))

    def test_pilot_primary_full(self):
        g = membership_era_integrity(PILOT)
        self.assertTrue(g.get("ok"), msg=g)
        for year in PRIMARY_MEMBERSHIP_ERAS:
            snap = json.loads((PILOT / ("hierarchy_membership_%d.json" % year)).read_text())
            self.assertEqual(snap.get("mode"), "full")
            self.assertTrue(snap.get("seed_only"))
            self.assertGreaterEqual(int(snap.get("province_n") or 0), 600)
            # Full maps present
            self.assertTrue(snap.get("province_to_state"))
            self.assertTrue(snap.get("province_to_region"))
            self.assertTrue(snap.get("province_to_super_region"))
            self.assertTrue(snap.get("states"))

    def test_samples_primary_full(self):
        for sub in ("us_midwest_sample", "europe_core_sample"):
            d = SAMPLES / sub
            g = membership_era_integrity(d)
            self.assertTrue(g.get("ok"), msg=(sub, g))
            for year in PRIMARY_MEMBERSHIP_ERAS:
                self.assertTrue((d / ("hierarchy_membership_%d.json" % year)).is_file())

    def test_catalog_decisions(self):
        cat = json.loads((SAMPLES / "catalog.json").read_text())
        dec = cat.get("decisions") or {}
        self.assertEqual(dec.get("us_region_set"), "8_band")
        self.assertEqual(len(dec.get("us_regions") or []), 8)
        self.assertEqual(dec.get("global_province_target_v1"), 6000)
        self.assertEqual(dec.get("fps_gate_first"), 60)
        self.assertEqual(dec.get("membership_primary_eras"), [1910, 1918, 1936, 2026])
        self.assertEqual(dec.get("membership_primary_mode"), "full")

    def test_loader_wiring(self):
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("_apply_era_membership_seed", sl)
        self.assertIn("membership_era_seed", sl)
        self.assertIn("mode=full", sl)
        self.assertIn("primary_eras=1910,1918,1936,2026", sl)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_membership_era_product.py", ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
