#!/usr/bin/env python3
"""Gates: quality gap close — custom template registration + asset fill path."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from quality_gap_close_product import (  # noqa
    close_quality_gaps,
    quality_gap_close_integrity,
    check_custom_template_registration_wired,
    check_asset_fill_integrity,
)


class TestQualityGapClose(unittest.TestCase):
    def test_registration_wired(self):
        r = check_custom_template_registration_wired()
        self.assertTrue(r.get("ok"), msg=r)
        for k, v in (r.get("checks") or {}).items():
            self.assertTrue(v, msg="check failed: %s" % k)

    def test_asset_fill_tool_exists(self):
        a = check_asset_fill_integrity()
        self.assertTrue(a.get("ok"), msg=a)
        tool = ROOT / "tools" / "fill_referenced_icons.py"
        self.assertTrue(tool.is_file())
        # tool exposes real CLI entry
        text = tool.read_text(encoding="utf-8")
        self.assertIn("collect_refs", text)
        self.assertIn("make_icon", text)

    def test_close_product(self):
        r = close_quality_gaps()
        self.assertTrue(r.get("ok"), msg=r)
        self.assertIn("custom_template_registration", r.get("closed") or [])

    def test_gamedata_loader_wired(self):
        g = quality_gap_close_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        dd = (ROOT / "scripts" / "core" / "DesignDataLoader.gd").read_text()
        self.assertIn("apply_quality_gap_close_live", gd)
        self.assertIn("quality_gap_close_live=1", sl)
        self.assertIn("func register_runtime_template", dd)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_quality_gap_close_product.py", ci)


if __name__ == "__main__":
    unittest.main(verbosity=2)
