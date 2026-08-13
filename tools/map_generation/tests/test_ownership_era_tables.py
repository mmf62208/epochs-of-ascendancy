#!/usr/bin/env python3
"""Gates: multi-era ownership tables including 2026 + player agency policy."""
from __future__ import annotations
import sys, unittest, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from ownership_era_product import *  # noqa

DATA = ROOT / "data" / "provinces_world_full"

class TestEras(unittest.TestCase):
    def test_2026_exists(self):
        p = ownership_table_path(DATA, 2026)
        self.assertTrue(p.is_file(), msg=str(p))
        tab = load_ownership_table(p)
        self.assertTrue(tab.get("ok"))
        self.assertGreaterEqual(len(tab.get("owners") or {}), 1000)
        self.assertEqual(int((tab.get("meta") or {}).get("era_year") or 0), 2026)
        self.assertTrue(bool((tab.get("meta") or {}).get("seed_only")))

    def test_resolve(self):
        self.assertEqual(resolve_ownership_era(2026), 2026)
        self.assertEqual(resolve_ownership_era(2020), 1945)  # largest era year <= 2020
        self.assertEqual(resolve_ownership_era(1936), 1936)
        self.assertEqual(resolve_ownership_era(1900), 1910)

    def test_agency(self):
        pol = player_agency_policy()
        self.assertFalse(pol.get("reapply_on_year_tick"))
        self.assertFalse(pol.get("reapply_on_daily_tick"))
        self.assertTrue(pol.get("seed_on_scenario_load"))
        self.assertTrue(pol.get("player_conquest_preserved"))

    def test_index(self):
        idx_path = DATA / "ownership_era_index.json"
        self.assertTrue(idx_path.is_file())
        idx = json.loads(idx_path.read_text())
        years = [e["year"] for e in idx.get("eras") or []]
        self.assertIn(2026, years)
        self.assertIn(1936, years)
        self.assertFalse((idx.get("policy") or {}).get("reapply_on_year_tick"))

    def test_integrity(self):
        self.assertTrue(ownership_era_integrity(DATA).get("ok"))

    def test_scenario_loader_seed(self):
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("_apply_era_ownership_seed", sl)
        self.assertIn("ownership_era_seed", sl)
        self.assertIn("player_agency", sl)
        self.assertIn("seed_only", sl)

if __name__ == "__main__":
    unittest.main(verbosity=2)
