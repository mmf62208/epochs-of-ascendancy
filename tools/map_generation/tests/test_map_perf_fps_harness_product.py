#!/usr/bin/env python3
"""Gates: M3 map perf FPS harness product (shipped pure API only)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_perf_fps_harness_product import (  # noqa: E402
    BUDGET_MS_30,
    BUDGET_MS_60,
    build_map_perf_fps_harness_product,
    map_perf_fps_harness_integrity,
    measure_frame_budget,
    pilot_budget_plan,
    resolve_pilot_tag,
)


class TestMapPerfFpsHarnessProduct(unittest.TestCase):
    def test_measure_empty_not_ok(self) -> None:
        m = measure_frame_budget([], target_fps=30)
        self.assertTrue(m.get("empty"))
        self.assertFalse(m.get("budget_ok"))
        self.assertFalse(m.get("ok"))
        self.assertEqual(m.get("sample_n"), 0)
        self.assertEqual(m.get("estimated_fps"), 0.0)

    def test_measure_pass_30_fail_60(self) -> None:
        # ~25ms mean → 40 fps: under 33.3 (30fps), over 16.67 (60fps)
        times = [24.0, 25.0, 26.0, 25.0, 24.5, 25.5, 26.0, 25.0]
        m30 = measure_frame_budget(times, target_fps=30)
        m60 = measure_frame_budget(times, target_fps=60)
        self.assertFalse(m30.get("empty"))
        self.assertTrue(m30.get("budget_ok"), msg=m30)
        self.assertFalse(m60.get("budget_ok"), msg=m60)
        self.assertGreater(m30.get("mean_ms"), 0)
        self.assertLessEqual(m30.get("mean_ms"), BUDGET_MS_30)
        self.assertGreater(m60.get("mean_ms"), BUDGET_MS_60)
        self.assertGreater(m30.get("estimated_fps"), 30.0)
        self.assertLess(m30.get("estimated_fps"), 60.0)
        self.assertGreaterEqual(m30.get("p95_ms"), m30.get("min_ms"))
        self.assertLessEqual(m30.get("p95_ms"), m30.get("max_ms"))

    def test_measure_pass_60(self) -> None:
        times = [12.0, 14.0, 13.5, 15.0, 14.2, 13.0]
        m60 = measure_frame_budget(times, target_fps=60)
        self.assertTrue(m60.get("budget_ok"), msg=m60)
        self.assertGreaterEqual(m60.get("estimated_fps"), 60.0)

    def test_product_synthetic_pass_30_fail_60(self) -> None:
        times = [22.0, 24.0, 26.0, 25.0, 23.5, 24.5, 25.5, 24.0] * 4
        p = build_map_perf_fps_harness_product(
            land_n=4650,
            pilot_name="density",
            frame_times_ms=times,
            target_fps=30,
        )
        self.assertFalse(p.get("empty"), msg=p)
        self.assertTrue(p.get("budget_ok_30"), msg=p)
        self.assertFalse(p.get("budget_ok_60"), msg=p)
        self.assertEqual(p.get("pilot_tag"), "density")
        self.assertEqual(p.get("land_n"), 4650)
        self.assertIn("mean_ms", p)
        self.assertIn("p95_ms", p)
        self.assertIn("min_ms", p)
        self.assertIn("max_ms", p)
        self.assertIn("estimated_fps", p)
        self.assertIn("plain", p)
        self.assertIn("score", p)
        self.assertGreater(float(p.get("score") or 0), 0.0)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS_30")
        self.assertIn("Map FPS harness", p.get("summary") or "")

    def test_product_empty_times_not_ok(self) -> None:
        p = build_map_perf_fps_harness_product(
            province_count=1514,
            pilot_name="nuts3",
            frame_times_ms=[],
        )
        self.assertTrue(p.get("empty"), msg=p)
        self.assertFalse(p.get("budget_ok_30"))
        self.assertFalse(p.get("budget_ok_60"))
        self.assertFalse(p.get("ok"))
        self.assertIn("score", p)
        self.assertEqual(float(p["score"]), 0.0)
        self.assertEqual(p.get("status"), "EMPTY")
        self.assertEqual(p.get("pilot_tag"), "nuts3")

    def test_product_none_times_empty(self) -> None:
        p = build_map_perf_fps_harness_product(frame_times_ms=None)
        self.assertTrue(p.get("empty"))
        self.assertFalse(p.get("budget_ok_30"))
        self.assertFalse(p.get("budget_ok_60"))

    def test_simulated_budgets_path(self) -> None:
        # Single float expands; 25ms → pass 30 fail 60
        p = build_map_perf_fps_harness_product(
            land_n=1514,
            pilot_name="nuts3",
            simulated_budgets=25.0,
        )
        self.assertFalse(p.get("empty"))
        self.assertTrue(p.get("simulated"))
        self.assertTrue(p.get("budget_ok_30"))
        self.assertFalse(p.get("budget_ok_60"))

    def test_pilot_budget_plan_keys(self) -> None:
        dens = pilot_budget_plan("density")
        nuts = pilot_budget_plan("nuts3")
        world = pilot_budget_plan("world_full")
        accurate = pilot_budget_plan("world_accurate")
        self.assertEqual(dens.get("pilot_tag"), "density")
        self.assertEqual(nuts.get("pilot_tag"), "nuts3")
        self.assertIn("land_n", dens)
        self.assertIn("land_n", nuts)
        self.assertIn("province_count", dens)
        self.assertIn("soft_budget_ms_30", dens)
        self.assertIn("soft_budget_ms_60", dens)
        self.assertGreaterEqual(int(dens.get("land_n") or 0), 4000)
        self.assertLessEqual(int(dens.get("land_n") or 0), 9000)
        self.assertGreaterEqual(int(nuts.get("land_n") or 0), 1000)
        self.assertLessEqual(int(nuts.get("land_n") or 0), 2000)
        self.assertEqual(int(world.get("province_count") or 0), 2665)
        self.assertGreaterEqual(int(accurate.get("province_count") or 0), 3000)
        self.assertGreaterEqual(int(accurate.get("land_n") or 0), 3000)
        # Aliases
        self.assertEqual(pilot_budget_plan("global_density").get("pilot_tag"), "density")
        self.assertEqual(pilot_budget_plan("europe_nuts3").get("pilot_tag"), "nuts3")
        self.assertEqual(pilot_budget_plan("accurate").get("pilot_tag"), "world_accurate")

    def test_resolve_pilot_tag_by_count(self) -> None:
        self.assertEqual(resolve_pilot_tag(land_n=4650), "density")
        self.assertEqual(resolve_pilot_tag(land_n=1514), "nuts3")
        self.assertEqual(resolve_pilot_tag(province_count=2665), "world_full")
        self.assertEqual(resolve_pilot_tag(province_count=8761), "world_accurate")
        self.assertEqual(resolve_pilot_tag(land_n=8421), "world_accurate")
        self.assertEqual(resolve_pilot_tag(province_count=5670), "world_accurate")
        self.assertEqual(resolve_pilot_tag(land_n=5330), "world_accurate")
        self.assertEqual(resolve_pilot_tag(province_count=3520), "world_accurate")
        self.assertEqual(resolve_pilot_tag(land_n=3180), "world_accurate")
        self.assertEqual(resolve_pilot_tag(pilot_name="density"), "density")
        self.assertEqual(resolve_pilot_tag(pilot_name="nuts3"), "nuts3")
        self.assertEqual(resolve_pilot_tag(pilot_name="world_accurate"), "world_accurate")

    def test_integrity(self) -> None:
        g = map_perf_fps_harness_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        self.assertTrue(g.get("empty_honest"))
        self.assertTrue(g.get("mid_pass_30_fail_60"))

    def test_shipped_module_path(self) -> None:
        mod = ROOT / "tools" / "map_generation" / "lib" / "map_perf_fps_harness_product.py"
        self.assertTrue(mod.is_file())
        text = mod.read_text(encoding="utf-8")
        self.assertIn("def build_map_perf_fps_harness_product", text)
        self.assertIn("def measure_frame_budget", text)
        self.assertIn("def pilot_budget_plan", text)
        self.assertIn("EOA_MAP_PERF", text)

    def test_dual_live_wiring_honest_empty(self) -> None:
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_map_perf_fps_harness_live", gd)
        # Honesty: dual must not invent PASS budgets without samples
        self.assertIn("empty", gd[gd.index("func apply_map_perf_fps_harness_live") :])
        self.assertIn("measured", gd[gd.index("func apply_map_perf_fps_harness_live") :])
        self.assertIn("map_perf_fps_harness_live=1", sl)
        self.assertIn("apply_map_perf_fps_harness_live", sl)
        self.assertIn("empty=true", sl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
