#!/usr/bin/env python3
"""Gates: map visual Phase 2 + Phase 3 gap-closure."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from map_visual_phase23_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_map_visual_phase23_product()
        self.assertFalse(p.get("empty"))
        self.assertTrue(p.get("complete"), msg=p.get("summary"))
        self.assertEqual(len(p.get("day_rows") or []), 8)
        self.assertTrue(close_map_visual_phase23_product_loop().get("ok"))
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_map_phase23_step(s).get("ok"))
        self.assertTrue(map_visual_phase23_integrity().get("ok"))
        fp = p.get("fingerprint") or {}
        self.assertTrue(str(fp.get("fingerprint", "")).startswith("mvp23-"))

class TestLive(unittest.TestCase):
    def test_stack(self):
        mr = (ROOT / "scripts/map/MapRenderer.gd").read_text()
        for needle in (
            "_setup_strategic_flow_layer",
            "_setup_battle_indicator_layer",
            "_setup_domain_ops_layer",
            "_setup_construction_progress_layer",
            "_setup_leader_station_layer",
            "get_phase23_overlay_stats",
            "KEY_J", "KEY_U", "KEY_K",
        ):
            self.assertIn(needle, mr)
        lod = (ROOT / "scripts/map/MapZoomLOD.gd").read_text()
        self.assertIn("use_lower_vert_fallback", lod)
        self.assertIn("target_frame_ms_mid_hardware", lod)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("map_phase23_live", sl)
        self.assertIn("test_map_visual_phase23_product.py", (ROOT / "tools/run_map_ci.sh").read_text())
        dbg = (ROOT / "scripts/ui/DebugOverlay.gd").read_text()
        self.assertIn("Phase 2/3", dbg)

    def test_docs(self):
        for path in (ROOT / "TODO.md", ROOT / "Next_30_Days_Roadmap.md", ROOT / "docs" / "MAP_RENDERER_PERF.md", ROOT / "GAME_STATUS_ASSESSMENT.md"):
            low = path.read_text().lower()
            for lab in ("phase2", "phase3", "battle indicator", "supply flow", "map_phase23"):
                self.assertIn(lab, low, msg=f"{path.name} {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
