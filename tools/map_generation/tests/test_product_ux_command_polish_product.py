#!/usr/bin/env python3
"""Gates: product UX command polish product (major #32)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from product_ux_command_polish_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_product_ux_command_polish_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreaterEqual(int(p.get("max_chips", 0)), 8)
        self.assertGreaterEqual(int(p.get("bind_n", 0)), 6)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_product_ux_step(s).get("ok"))
        self.assertTrue(product_ux_command_polish_integrity().get("ok"))
        self.assertTrue(close_product_ux_command_polish_product_loop().get("ok"))


class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("static func product_ux_command_polish_product(", fmt)
        self.assertIn("func product_ux_command_polish_product_live", mm)
        self.assertIn("func apply_product_ux_polish_live", gd)
        self.assertIn("Product UX command polish (major #32)", panel)
        self.assertIn("build_product_ux_command_polish_product_chip_bbcode", pi)
        self.assertIn("phase3_depth_live", sl)
        self.assertIn("test_product_ux_command_polish_product.py", (ROOT / "tools/run_map_ci.sh").read_text())

    def test_docs(self):
        for path in (ROOT / "TODO.md", ROOT / "Project_State_Summary.md", ROOT / "Next_30_Days_Roadmap.md", ROOT / "GAME_STATUS_ASSESSMENT.md"):
            low = path.read_text().lower()
            for lab in ("product ux", "major #32", "phase3_depth", "hotkeys"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
