#!/usr/bin/env python3
"""Gates: apply-queue live managers product (major #28)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from apply_queue_live_managers_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_apply_queue_live_managers_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 6)
        self.assertEqual(p.get("apply_queue_live"), "6/6")
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_apply_queue_live_step(s).get("ok"))
        self.assertTrue(apply_queue_live_managers_integrity().get("ok"))
        self.assertTrue(close_apply_queue_live_managers_product_loop().get("ok"))
    def test_leaves(self):
        self.assertEqual(len(CORE_LEAVES), 6)
        board = build_leaf_contract_board()
        self.assertEqual(len(board.get("rows") or []), 6)

class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("static func apply_queue_live_managers_product(", fmt)
        self.assertIn("func apply_queue_live_managers_product_live", mm)
        self.assertIn("func audit_apply_queue_live_leaves", gd)
        prod_fn = gd.find("func apply_production_priority_mutation")
        self.assertGreaterEqual(prod_fn, 0)
        self.assertIn("daily_production_tick", gd[prod_fn:prod_fn+2000])
        sup_fn = gd.find("func apply_supply_route_mutation")
        self.assertGreaterEqual(sup_fn, 0)
        self.assertIn("advance_supply_day", gd[sup_fn:sup_fn+2000])
        self.assertIn("Apply-queue live managers (major #28)", panel)
        self.assertIn("build_apply_queue_live_managers_product_chip_bbcode", pi)
        self.assertIn("apply_queue_live=", sl)
        self.assertIn("test_apply_queue_live_managers_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
    def test_docs(self):
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md", ROOT/"GAME_STATUS_ASSESSMENT.md"):
            low = path.read_text().lower()
            for lab in ("apply-queue live managers", "apply queue live", "major #28", "apply_queue_live"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
