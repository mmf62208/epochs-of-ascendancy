#!/usr/bin/env python3
"""Gates: occupation resistance/compliance product (major #29)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from occupation_resistance_compliance_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_occupation_resistance_compliance_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 3)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_occupation_resistance_step(s).get("ok"))
        self.assertTrue(occupation_resistance_compliance_integrity().get("ok"))
        self.assertTrue(close_occupation_resistance_compliance_product_loop().get("ok"))
        self.assertIn("harsh", POLICIES)

    def test_state(self):
        harsh = compute_occupation_state(policy="harsh", resistance_level=0.7, compliance_level=0.3)
        lenient = compute_occupation_state(policy="lenient", resistance_level=0.7, compliance_level=0.3)
        self.assertEqual(harsh.get("policy"), "harsh")
        self.assertGreaterEqual(float(lenient.get("compliance_level", 0)), float(harsh.get("compliance_level", 0)) - 0.01)


class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("static func occupation_resistance_compliance_product(", fmt)
        self.assertIn("func occupation_resistance_compliance_product_live", mm)
        self.assertIn("func apply_occupation_policy_live", gd)
        self.assertIn("func apply_occupation_daily_tick_live", gd)
        self.assertIn("Occupation resistance/compliance (major #29)", panel)
        self.assertIn("build_occupation_resistance_compliance_product_chip_bbcode", pi)
        self.assertIn("phase2_conquest_live", sl)
        self.assertIn("test_occupation_resistance_compliance_product.py", (ROOT / "tools/run_map_ci.sh").read_text())

    def test_docs(self):
        for path in (ROOT / "TODO.md", ROOT / "Project_State_Summary.md", ROOT / "Next_30_Days_Roadmap.md", ROOT / "GAME_STATUS_ASSESSMENT.md"):
            low = path.read_text().lower()
            for lab in ("occupation resistance", "resistance/compliance", "major #29", "phase2_conquest"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
