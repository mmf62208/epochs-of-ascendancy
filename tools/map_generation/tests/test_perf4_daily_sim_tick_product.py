#!/usr/bin/env python3
"""Gates: PERF-4 daily sim-tick hitch (peace_state peek + owner index + timers)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from perf4_daily_sim_tick_product import (  # noqa: E402
    AIM_FRAME_BUDGET_MS,
    DAY_TICK_FRAME_BUDGET_MS,
    build_perf4_daily_sim_tick_product,
    extract_gd_func_body,
    perf4_daily_sim_tick_integrity,
)


class TestPerf4DailySimTickProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_perf4_daily_sim_tick_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(int(p.get("budget_ms") or 0), DAY_TICK_FRAME_BUDGET_MS)
        self.assertEqual(int(p.get("aim_ms") or 0), AIM_FRAME_BUDGET_MS)

    def test_integrity(self) -> None:
        g = perf4_daily_sim_tick_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_budget_constants(self) -> None:
        self.assertEqual(DAY_TICK_FRAME_BUDGET_MS, 500)
        self.assertLess(AIM_FRAME_BUDGET_MS, DAY_TICK_FRAME_BUDGET_MS)

    def test_get_peace_state_body_has_no_deepcopy(self) -> None:
        src = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        body = extract_gd_func_body(src, "get_peace_state")
        self.assertIn("peek_peace_state", body)
        self.assertNotIn("duplicate(true)", body)


if __name__ == "__main__":
    unittest.main()
