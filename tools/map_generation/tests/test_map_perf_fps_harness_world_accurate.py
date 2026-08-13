#!/usr/bin/env python3
"""Director D4.1 — world_accurate pilot in map FPS harness product."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_perf_fps_harness_product import (  # noqa: E402
    build_map_perf_fps_harness_product,
    map_perf_fps_harness_integrity,
    pilot_budget_plan,
    resolve_pilot_tag,
)


class TestMapPerfWorldAccuratePilot(unittest.TestCase):
    def test_pilot_plan_world_accurate(self) -> None:
        plan = pilot_budget_plan("world_accurate")
        self.assertEqual(plan.get("pilot_tag"), "world_accurate")
        self.assertGreaterEqual(int(plan.get("province_count") or 0), 3000)
        self.assertGreaterEqual(int(plan.get("land_n") or 0), 3000)
        self.assertEqual(int(plan.get("target_fps_primary") or 0), 30)
        summ = str(plan.get("summary") or "")
        self.assertTrue(
            "3520" in summ
            or "5670" in summ
            or "8761" in summ
            or "world_accurate" in summ
        )

    def test_aliases(self) -> None:
        for name in ("accurate", "gis", "provinces_world_accurate", "default"):
            self.assertEqual(
                pilot_budget_plan(name).get("pilot_tag"),
                "world_accurate",
                name,
            )

    def test_resolve_by_count(self) -> None:
        self.assertEqual(resolve_pilot_tag(province_count=8761), "world_accurate")
        self.assertEqual(resolve_pilot_tag(land_n=8421), "world_accurate")
        self.assertEqual(resolve_pilot_tag(province_count=5670), "world_accurate")
        self.assertEqual(resolve_pilot_tag(land_n=5330), "world_accurate")
        self.assertEqual(resolve_pilot_tag(province_count=3520), "world_accurate")
        self.assertEqual(resolve_pilot_tag(land_n=3180), "world_accurate")
        self.assertEqual(resolve_pilot_tag(province_count=2665), "world_full")
        self.assertEqual(resolve_pilot_tag(land_n=4650), "density")

    def test_empty_honest_on_accurate(self) -> None:
        p = build_map_perf_fps_harness_product(
            pilot_name="world_accurate",
            province_count=5670,
            frame_times_ms=[],
        )
        self.assertTrue(p.get("empty"), msg=p)
        self.assertFalse(p.get("ok"))
        self.assertFalse(p.get("budget_ok_30"))
        self.assertEqual(p.get("status"), "EMPTY")
        self.assertEqual(p.get("pilot_tag"), "world_accurate")
        self.assertIn("world_full", str(p.get("dual_note") or ""))
        self.assertIn("world_accurate", str(p.get("dual_note") or ""))

    def test_simulated_pass_30_on_accurate(self) -> None:
        # Soft-path synthetic: 28ms mean → pass 30, fail 60
        p = build_map_perf_fps_harness_product(
            pilot_name="world_accurate",
            province_count=5670,
            land_n=5330,
            simulated_budgets=28.0,
        )
        self.assertFalse(p.get("empty"))
        self.assertTrue(p.get("budget_ok_30"), msg=p)
        self.assertFalse(p.get("budget_ok_60"))
        self.assertEqual(p.get("status"), "PASS_30")
        self.assertEqual(p.get("pilot_tag"), "world_accurate")

    def test_integrity_includes_accurate(self) -> None:
        g = map_perf_fps_harness_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        self.assertEqual(g.get("resolve_8761"), "world_accurate")
        self.assertEqual(g.get("resolve_8421"), "world_accurate")
        self.assertGreaterEqual(int(g.get("world_accurate_province_count") or 0), 3000)


if __name__ == "__main__":
    unittest.main()
