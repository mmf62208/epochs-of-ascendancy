#!/usr/bin/env python3
"""Gates: multi-faction strategic AI daily depth for non-humans."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from multi_faction_ai_daily_depth_product import (  # noqa
    close_multi_faction_ai_daily,
    multi_faction_ai_daily_depth_integrity,
    apply_ai_daily_round,
    _new_runtime,
)


class TestMultiFactionAiDailyDepth(unittest.TestCase):
    def test_close(self):
        r = close_multi_faction_ai_daily()
        self.assertTrue(r.get("ok"), msg=r)
        self.assertGreaterEqual(int(r["runtime"].get("ai_applied_total") or 0), 4)
        self.assertGreaterEqual(int(r["runtime"].get("human_skipped") or 0), 1)

    def test_skips_human(self):
        rt = _new_runtime()
        res = apply_ai_daily_round(rt, 1)
        self.assertTrue(res.get("ok"))
        human_skips = [x for x in res.get("results") or [] if x.get("skipped") and x.get("reason") == "human"]
        self.assertGreaterEqual(len(human_skips), 1)

    def test_wired(self):
        g = multi_faction_ai_daily_depth_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("apply_multi_faction_ai_daily_depth_live", gd)
        self.assertIn("strategic_ai_multi_faction_daily_live=1", sl)
        self.assertIn("apply_vision_close_live", gd)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_multi_faction_ai_daily_depth_product.py", ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
