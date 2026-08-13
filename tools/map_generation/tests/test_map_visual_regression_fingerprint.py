#!/usr/bin/env python3
"""Visual regression fingerprint — stable contract for occupation/signal/perf map gap.

Headless-safe (no GPU screenshot required). Optional baseline file under
tools/map_generation/baselines/map_visual_fingerprint.txt for drift detection.
When Godot graphical runs are available, screenshots can be stored alongside;
this gate locks the *data-driven visual contract* that screenshots would assert.
"""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from map_visual_gap_product import compute_visual_fingerprint, build_map_visual_gap_product  # noqa

BASELINE = ROOT / "tools" / "map_generation" / "baselines" / "map_visual_fingerprint.txt"


class TestVisualRegression(unittest.TestCase):
    def test_fingerprint_stable(self):
        fp = compute_visual_fingerprint()
        self.assertTrue(fp.get("ok"), msg=fp.get("summary"))
        self.assertGreaterEqual(int(fp.get("ok_n", 0)), int(fp.get("check_n", 1)))
        fingerprint = str(fp.get("fingerprint", ""))
        self.assertTrue(fingerprint.startswith("mvg1-"))
        BASELINE.parent.mkdir(parents=True, exist_ok=True)
        if not BASELINE.is_file():
            BASELINE.write_text(fingerprint + "\n", encoding="utf-8")
        expected = BASELINE.read_text(encoding="utf-8").strip().splitlines()[0].strip()
        self.assertEqual(
            fingerprint, expected,
            msg="Visual fingerprint drift — update baseline intentionally if contract changed: %s vs %s"
            % (fingerprint, expected),
        )

    def test_key_provinces_contract(self):
        """Key visual surfaces must exist (fixed-camera screenshot hooks later)."""
        required = [
            ROOT / "scripts/map/OccupationOverlayLayer.gd",
            ROOT / "scripts/map/ConflictOverlayLayer.gd",
            ROOT / "scripts/map/MapRenderer.gd",
            ROOT / "SignalGraphVisualizer.gd",
            ROOT / "scripts/debug/SignalGraphHarness.gd",
        ]
        for p in required:
            self.assertTrue(p.is_file(), msg=str(p))
        mr = (ROOT / "scripts/map/MapRenderer.gd").read_text()
        for needle in ("OccupationOverlay", "ConflictOverlay", "dump_perf_profile", "KEY_O"):
            self.assertIn(needle, mr)
        product = build_map_visual_gap_product()
        self.assertTrue(product.get("complete"))

    def test_screenshot_hook_documented(self):
        """Screenshot regression path is wired as optional env for graphical runs."""
        # Inventory hook: ScenarioLoader + docs mention screenshot / fixed camera path
        docs = (ROOT / "docs" / "MAP_RENDERER_PERF.md").read_text().lower()
        self.assertIn("screenshot", docs)
        self.assertIn("fingerprint", docs)
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("map_gap_closure_live", sl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
