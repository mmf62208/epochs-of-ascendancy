#!/usr/bin/env python3
"""Gates: map visual gap-closure product (Phase 1 signal/occupation/perf/CI)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from map_visual_gap_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_map_visual_gap_product()
        self.assertFalse(p.get("empty"))
        self.assertTrue(p.get("complete"), msg=p.get("summary"))
        self.assertGreaterEqual(len(p.get("day_rows") or []), 4)
        self.assertTrue(close_map_visual_gap_product_loop().get("ok"))
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_map_gap_step(s).get("ok"))
        self.assertTrue(map_visual_gap_integrity().get("ok"))
        fp = p.get("fingerprint") or {}
        self.assertTrue(fp.get("ok"))
        self.assertTrue(str(fp.get("fingerprint", "")).startswith("mvg1-"))

class TestLive(unittest.TestCase):
    def test_stack(self):
        mr = (ROOT / "scripts/map/MapRenderer.gd").read_text()
        ol = (ROOT / "scripts/map/OccupationOverlayLayer.gd").read_text()
        perf = (ROOT / "scripts/map/MapRendererPerf.gd").read_text()
        harness = (ROOT / "scripts/debug/SignalGraphHarness.gd").read_text()
        tib = (ROOT / "scripts/ui/TopInfoBar.gd").read_text()
        dbg = (ROOT / "scripts/ui/DebugOverlay.gd").read_text()
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("class_name OccupationOverlayLayer", ol)
        self.assertIn("class_name MapRendererPerf", perf)
        self.assertIn("class_name SignalGraphHarness", harness)
        self.assertIn("_setup_occupation_layer", mr)
        self.assertIn("enable_perf_profile", mr)
        self.assertIn("KEY_F11", tib)
        self.assertIn("Signal Graph", dbg)
        self.assertIn("Occupation Overlay", dbg)
        self.assertIn("Map Perf", dbg)
        self.assertIn("map_gap_closure_live", sl)
        self.assertIn("test_map_visual_gap_product.py", (ROOT / "tools/run_map_ci.sh").read_text())

    def test_docs(self):
        for path in (ROOT / "TODO.md", ROOT / "Next_30_Days_Roadmap.md", ROOT / "GAME_STATUS_ASSESSMENT.md", ROOT / "docs" / "MAP_RENDERER_PERF.md"):
            self.assertTrue(path.is_file(), msg=str(path))
            low = path.read_text().lower()
            for lab in ("map gap", "occupation overlay", "signal graph", "map_gap_closure"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
