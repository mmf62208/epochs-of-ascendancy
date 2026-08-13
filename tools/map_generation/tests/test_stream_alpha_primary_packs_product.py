#!/usr/bin/env python3
"""Gates: Stream α primary packs C/E/F/G (playability UI paths)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from stream_alpha_primary_packs_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(
            1 for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_stream_alpha_primary_packs_product()
        self.assertFalse(p.get("empty"))
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertGreaterEqual(len(p.get("day_rows") or []), 4)
        self.assertTrue(stream_alpha_primary_packs_integrity().get("ok"))
        self.assertTrue(close_stream_alpha_primary_packs_loop().get("ok"))


class TestLive(unittest.TestCase):
    def test_stack(self):
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        prod = (ROOT / "scripts/ui/ProductionAssignmentScreen.gd").read_text()
        top = (ROOT / "scripts/ui/TopInfoBar.gd").read_text()
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        # Pack C — combat ribbon + close-live
        self.assertIn("combat_ops_close", panel)
        self.assertIn("phase_approach", panel)
        self.assertIn("func apply_combat_ops_close_live", gd)
        self.assertIn('aid == "combat_ops_close"', gd)
        # Pack E — OOB on production screen
        self.assertIn("apply_oob_horizon_60d", prod)
        self.assertIn("apply_oob_horizon_100d", prod)
        self.assertIn("medium_tank_oob", prod)
        # Pack F — HH TopInfoBar
        self.assertIn("HH Agenda", top)
        self.assertIn("apply_hh_agenda_close_live", gd)
        self.assertIn('aid == "hh_agenda_close"', gd)
        # Pack G — save via product APIs
        self.assertIn("apply_save_browser_resume", top)
        self.assertIn("apply_save_browser_checkpoint", top)
        self.assertIn("static func stream_alpha_primary_packs_product(", fmt)
        ci = (ROOT / "tools/run_map_ci.sh").read_text()
        self.assertIn("test_stream_alpha_primary_packs_product.py", ci)

    def test_docs(self):
        for path in (
            ROOT / "TODO.md",
            ROOT / "docs/MASTER_COMPLETION_PLAN.md",
            ROOT / "docs/COMPLETION_PLAN.md",
        ):
            low = path.read_text().lower()
            self.assertTrue(
                "stream_alpha" in low or "stream α" in low or ("stream" in low and "pack" in low),
                msg="%s missing stream alpha pack labels" % path.name,
            )
            self.assertTrue("combat" in low or "primary" in low)

if __name__ == "__main__":
    unittest.main(verbosity=2)
