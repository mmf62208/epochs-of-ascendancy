#!/usr/bin/env python3
"""M5 gates: measured FPS samples ingest + MapRendererPerf session export wiring."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_perf_fps_harness_product import (  # noqa: E402
    build_m5_measured_product,
    load_frame_samples_json,
    map_perf_fps_harness_integrity,
)

RENDERER_PERF = ROOT / "scripts" / "map" / "MapRendererPerf.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
HEADLESS = ROOT / "scripts" / "core" / "HeadlessWorldAccurateMapPerfTest.gd"
SAMPLES = ROOT / "tools" / "map_generation" / "output" / "map_perf_world_accurate_samples.json"
TMP_SAMPLES = Path("/tmp/eoa-map-perf-world-accurate.json")


class TestMapPerfM5Measured(unittest.TestCase):
    def test_integrity_includes_m5(self) -> None:
        g = map_perf_fps_harness_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        self.assertTrue(g.get("m5_helpers_ok"), msg=g)

    def test_empty_load_honest(self) -> None:
        loaded = load_frame_samples_json("/no/such/m5_samples.json")
        self.assertTrue(loaded.get("empty"))
        self.assertFalse(loaded.get("ok"))
        p = build_m5_measured_product(samples_path="/no/such/m5_samples.json")
        self.assertTrue(p.get("empty"))
        self.assertFalse(p.get("measured"))
        self.assertFalse(p.get("budget_ok_30"))

    def test_ingest_synthetic_file(self) -> None:
        # ~28ms → pass 30, fail 60
        payload = {
            "pilot_tag": "world_accurate",
            "measure_kind": "renderer_frame",
            "province_count": 8761,
            "land_n": 8421,
            "frame_times_ms": [27.0, 28.0, 29.0, 28.5, 27.5] * 12,
            "p50_ms": 28.0,
            "p95_ms": 29.0,
        }
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(payload, f)
            path = f.name
        p = build_m5_measured_product(samples_path=path)
        self.assertTrue(p.get("measured"), msg=p)
        self.assertFalse(p.get("empty"))
        self.assertTrue(p.get("budget_ok_30"), msg=p)
        self.assertFalse(p.get("budget_ok_60"))
        self.assertEqual(p.get("status"), "PASS_30")
        self.assertGreater(float(p.get("p50_ms") or 0), 0.0)
        self.assertGreater(float(p.get("p95_ms") or 0), 0.0)
        self.assertEqual(p.get("measure_kind"), "renderer_frame")

    def test_wiring_export_and_headless(self) -> None:
        perf = RENDERER_PERF.read_text(encoding="utf-8")
        self.assertIn("func export_session_json", perf)
        self.assertIn("func session_stats", perf)
        self.assertIn("p50_ms", perf)
        self.assertIn("p95_ms", perf)
        self.assertIn("_session_frame_ms", perf)
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn("export_map_perf_session", ren)
        self.assertIn("export_session_json", ren)
        self.assertTrue(HEADLESS.is_file(), HEADLESS)
        hd = HEADLESS.read_text(encoding="utf-8")
        self.assertIn("map_tick_proxy_headless", hd)
        self.assertIn("export_session_json", hd)
        # Seed or scale comment may mention historical 8761 / 5670; post-sparse floor 3000
        self.assertTrue(
            "8761" in hd or "5670" in hd or "3520" in hd or "3000" in hd or "5000" in hd,
            msg="headless perf test should document board scale",
        )

    def test_live_samples_if_present(self) -> None:
        """If headless M5 already ran, require honest measured product with p50/p95."""
        path = SAMPLES if SAMPLES.is_file() else (TMP_SAMPLES if TMP_SAMPLES.is_file() else None)
        if path is None:
            self.skipTest("no live samples yet — run HeadlessWorldAccurateMapPerfTest")
        p = build_m5_measured_product(samples_path=str(path))
        self.assertTrue(p.get("measured"), msg=p)
        self.assertGreaterEqual(int(p.get("sample_n") or 0), 30)
        self.assertGreater(float(p.get("p50_ms") or 0), 0.0)
        self.assertGreater(float(p.get("p95_ms") or 0), 0.0)
        self.assertIn(str(p.get("measure_kind") or ""), ("map_tick_proxy_headless", "renderer_frame"))


if __name__ == "__main__":
    unittest.main()
