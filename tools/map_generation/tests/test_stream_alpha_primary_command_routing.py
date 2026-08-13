#!/usr/bin/env python3
"""Gates: Stream α primary command dual wiring honesty (GD live routing)."""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from stream_alpha_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    PRIMARY_COMMAND_STEPS,
    build_stream_alpha_primary_command_product,
    stream_alpha_primary_command_integrity,
)

GD_PATH = ROOT / "scripts" / "autoload" / "GameData.gd"
SL_PATH = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
FMT_PATH = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
MM_PATH = ROOT / "scripts" / "map" / "MapManager.gd"
PANEL_PATH = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"


def extract_func_body(src: str, func_name: str) -> str:
    """Extract GDScript function body by name until next top-level func/const/endregion."""
    pat = re.compile(
        r"(?m)^func %s\b.*$" % re.escape(func_name)
    )
    m = pat.search(src)
    if not m:
        return ""
    start = m.start()
    # next top-level declaration after this func
    rest = src[m.end() :]
    end_m = re.search(
        r"(?m)^(func |const |static func |class |#region |#endregion)",
        rest,
    )
    if end_m:
        return src[start : m.end() + end_m.start()]
    return src[start:]


class TestStreamAlphaPrimaryCommandRouting(unittest.TestCase):
    def test_pure_integrity_still_ok(self):
        self.assertTrue(stream_alpha_primary_command_integrity().get("ok"))
        p = build_stream_alpha_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 4)

    def test_gamedata_apply_functions_exist(self):
        gd = GD_PATH.read_text(encoding="utf-8")
        self.assertIn("const STREAM_ALPHA_STEPS", gd)
        self.assertIn("func apply_stream_alpha_primary_command_step_live(", gd)
        self.assertIn("func apply_stream_alpha_primary_command_live(", gd)
        self.assertIn("func format_stream_alpha_primary_command_product_plain(", gd)
        self.assertIn("func apply_stream_alpha_primary_command_product(", gd)
        for step in PRIMARY_COMMAND_STEPS:
            self.assertIn('"%s"' % step, gd, msg="missing step in STREAM_ALPHA_STEPS: %s" % step)

    def test_medium_horizon_routes_to_oob_not_apply_focus(self):
        """medium_horizon steps must call apply_oob_horizon_*, never apply_focus."""
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_stream_alpha_primary_command_step_live")
        self.assertIn("func apply_stream_alpha_primary_command_step_live(", body)
        self.assertIn('s == "medium_line_scan"', body)
        self.assertIn("apply_medium_tank_oob_product", body)
        self.assertIn('s == "medium_horizon_60d"', body)
        self.assertIn("apply_oob_horizon_60d", body)
        self.assertIn('s == "medium_horizon_100d"', body)
        self.assertIn("apply_oob_horizon_100d", body)
        # Honesty: no apply_focus leaf for medium block
        self.assertNotIn('leaf = "apply_focus"', body)
        self.assertNotIn('live_api = "apply_focus"', body)
        # Pure product contract
        self.assertEqual(LIVE_API_BY_STEP["medium_horizon_60d"], "apply_oob_horizon_60d")
        self.assertEqual(LIVE_API_BY_STEP["medium_horizon_100d"], "apply_oob_horizon_100d")
        self.assertEqual(LIVE_API_BY_STEP["medium_line_scan"], "apply_medium_tank_oob_product")

    def test_save_browser_resume_routes_honest(self):
        """save_browser_resume must call apply_save_browser_resume, not apply_focus."""
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_stream_alpha_primary_command_step_live")
        self.assertIn('s == "save_browser_list"', body)
        self.assertIn("save_browser_campaign_product_live", body)
        self.assertIn('s == "save_browser_resume"', body)
        self.assertIn("apply_save_browser_resume", body)
        self.assertIn('s == "save_checkpoint"', body)
        self.assertIn("apply_save_browser_checkpoint", body)
        self.assertNotIn('leaf = "apply_focus"', body)
        self.assertEqual(LIVE_API_BY_STEP["save_browser_resume"], "apply_save_browser_resume")
        self.assertEqual(LIVE_API_BY_STEP["save_checkpoint"], "apply_save_browser_checkpoint")

    def test_combat_and_hh_route_close_live(self):
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_stream_alpha_primary_command_step_live")
        self.assertIn("apply_combat_ops_close_live", body)
        self.assertIn("apply_hh_agenda_close_live", body)
        self.assertIn('s == "combat_phase_engage"', body)
        self.assertIn('s == "hh_monthly_commit"', body)

    def test_formatter_mapmanager_panel_loader_wired(self):
        fmt = FMT_PATH.read_text(encoding="utf-8")
        mm = MM_PATH.read_text(encoding="utf-8")
        panel = PANEL_PATH.read_text(encoding="utf-8")
        sl = SL_PATH.read_text(encoding="utf-8")
        gd = GD_PATH.read_text(encoding="utf-8")
        self.assertIn("static func stream_alpha_primary_command_product(", fmt)
        self.assertIn("func stream_alpha_primary_command_product_live(", mm)
        self.assertIn("func apply_stream_alpha_primary_command_product(", mm)
        self.assertIn("_rebuild_stream_alpha_primary_command", panel)
        self.assertIn("stream_alpha_primary_command_product", panel)
        self.assertIn("stream_alpha_primary_live=1", sl)
        self.assertIn("_print_stream_alpha_primary_live_evidence", sl)
        self.assertIn("stream_alpha_primary_command_product", gd)
        self.assertIn("apply_stream_alpha_primary_command_live", gd)
        # priority registration
        self.assertIn('"stream_alpha_primary_command_product": 164', fmt)

    def test_live_package_ok_contract(self):
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_stream_alpha_primary_command_live")
        self.assertIn("majors_ok >= 4", body)
        self.assertIn("dead_n == 0", body)
        self.assertIn("stream_alpha_primary_ticks", body)
        # peace_state key present
        self.assertIn('"stream_alpha_primary"', gd)
        self.assertIn("stream_alpha_primary_ticks", gd)
        self.assertIn("peace_state[\"stream_alpha_primary\"]", gd)


if __name__ == "__main__":
    unittest.main(verbosity=2)
