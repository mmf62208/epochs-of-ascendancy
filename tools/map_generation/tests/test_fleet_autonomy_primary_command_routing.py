#!/usr/bin/env python3
"""Gates: Fleet autonomy primary command dual wiring honesty (GD live routing)."""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from fleet_autonomy_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    PRIMARY_COMMAND_STEPS,
    build_fleet_autonomy_primary_command_product,
    fleet_autonomy_primary_command_integrity,
)

GD_PATH = ROOT / "scripts" / "autoload" / "GameData.gd"
SL_PATH = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
FMT_PATH = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
MM_PATH = ROOT / "scripts" / "map" / "MapManager.gd"
PANEL_PATH = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"


def extract_func_body(src: str, func_name: str) -> str:
    """Extract GDScript function body by name until next top-level func/const/endregion."""
    pat = re.compile(r"(?m)^func %s\b.*$" % re.escape(func_name))
    m = pat.search(src)
    if not m:
        return ""
    start = m.start()
    rest = src[m.end() :]
    end_m = re.search(
        r"(?m)^(func |const |static func |class |#region |#endregion)",
        rest,
    )
    if end_m:
        return src[start : m.end() + end_m.start()]
    return src[start:]


class TestFleetAutonomyPrimaryCommandRouting(unittest.TestCase):
    def test_pure_integrity_still_ok(self):
        self.assertTrue(fleet_autonomy_primary_command_integrity().get("ok"))
        p = build_fleet_autonomy_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 4)

    def test_gamedata_apply_functions_exist(self):
        gd = GD_PATH.read_text(encoding="utf-8")
        self.assertIn("const FLEET_AUTONOMY_PRIMARY_STEPS", gd)
        self.assertIn("func apply_fleet_autonomy_primary_command_step_live(", gd)
        self.assertIn("func apply_fleet_autonomy_primary_command_live(", gd)
        self.assertIn("func format_fleet_autonomy_primary_command_product_plain(", gd)
        self.assertIn("func apply_fleet_autonomy_primary_command_product(", gd)
        for step in PRIMARY_COMMAND_STEPS:
            self.assertIn('"%s"' % step, gd, msg="missing step in FLEET_AUTONOMY_PRIMARY_STEPS: %s" % step)

    def test_fleet_day_routes_honest_live_apis(self):
        """Day steps must call apply_fleet_day_*, never apply_focus."""
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_fleet_autonomy_primary_command_step_live")
        self.assertIn("func apply_fleet_autonomy_primary_command_step_live(", body)
        self.assertIn('s == "fleet_posture_day"', body)
        self.assertIn("apply_fleet_day_posture", body)
        self.assertIn('s == "fleet_station_escort"', body)
        self.assertIn("apply_fleet_day_station_escort", body)
        self.assertIn('s == "fleet_follow_through"', body)
        self.assertIn("apply_fleet_day_follow_through", body)
        # Honesty: no apply_focus leaf for fleet block
        self.assertNotIn('leaf = "apply_focus"', body)
        self.assertNotIn('live_api = "apply_focus"', body)
        # Pure product contract
        self.assertEqual(LIVE_API_BY_STEP["fleet_posture_day"], "apply_fleet_day_posture")
        self.assertEqual(
            LIVE_API_BY_STEP["fleet_station_escort"], "apply_fleet_day_station_escort"
        )
        self.assertEqual(
            LIVE_API_BY_STEP["fleet_follow_through"], "apply_fleet_day_follow_through"
        )

    def test_autonomy_close_routes_naval_ops(self):
        """fleet_autonomy_close must call apply_naval_ops_close_live."""
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_fleet_autonomy_primary_command_step_live")
        self.assertIn('s == "fleet_autonomy_close"', body)
        self.assertIn("apply_naval_ops_close_live", body)
        self.assertEqual(LIVE_API_BY_STEP["fleet_autonomy_close"], "apply_naval_ops_close_live")
        # Real GameData methods exist
        self.assertIn("func apply_fleet_day_posture(", gd)
        self.assertIn("func apply_fleet_day_station_escort(", gd)
        self.assertIn("func apply_fleet_day_follow_through(", gd)
        self.assertIn("func apply_naval_ops_close_live(", gd)

    def test_formatter_mapmanager_panel_loader_wired(self):
        fmt = FMT_PATH.read_text(encoding="utf-8")
        mm = MM_PATH.read_text(encoding="utf-8")
        panel = PANEL_PATH.read_text(encoding="utf-8")
        sl = SL_PATH.read_text(encoding="utf-8")
        gd = GD_PATH.read_text(encoding="utf-8")
        self.assertIn("static func fleet_autonomy_primary_command_product(", fmt)
        self.assertIn("func fleet_autonomy_primary_command_product_live(", mm)
        self.assertIn("func apply_fleet_autonomy_primary_command_product(", mm)
        self.assertIn("_rebuild_fleet_autonomy_primary_command", panel)
        self.assertIn("fleet_autonomy_primary_command_product", panel)
        self.assertIn("fleet_autonomy_primary_live=1", sl)
        self.assertIn("_print_fleet_autonomy_primary_live_evidence", sl)
        self.assertIn("fleet_autonomy_primary_command_product", gd)
        self.assertIn("apply_fleet_autonomy_primary_command_live", gd)
        # priority registration
        self.assertIn('"fleet_autonomy_primary_command_product": 165', fmt)

    def test_live_package_ok_contract(self):
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_fleet_autonomy_primary_command_live")
        self.assertIn("majors_ok >= 4", body)
        self.assertIn("dead_n == 0", body)
        self.assertIn("fleet_autonomy_primary_ticks", body)
        # peace_state key present
        self.assertIn('"fleet_autonomy_primary"', gd)
        self.assertIn("fleet_autonomy_primary_ticks", gd)
        self.assertIn('peace_state["fleet_autonomy_primary"]', gd)

    def test_stream_alpha_and_next20_not_broken(self):
        """Regression: stream_alpha dual and next20 still present."""
        gd = GD_PATH.read_text(encoding="utf-8")
        panel = PANEL_PATH.read_text(encoding="utf-8")
        sl = SL_PATH.read_text(encoding="utf-8")
        self.assertIn("func apply_stream_alpha_primary_command_live(", gd)
        self.assertIn("const STREAM_ALPHA_STEPS", gd)
        self.assertIn("const NEXT20_STEPS", gd)
        self.assertIn("func apply_next20_completion_live(", gd)
        self.assertIn("_rebuild_stream_alpha_primary_command", panel)
        self.assertIn("stream_alpha_primary_live=1", sl)
        self.assertIn("next20_completion_live=1", sl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
