#!/usr/bin/env python3
"""Gates: Research queue primary command dual wiring honesty (GD live routing)."""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from research_queue_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    PRIMARY_COMMAND_STEPS,
    build_research_queue_primary_command_product,
    research_queue_primary_command_integrity,
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


class TestResearchQueuePrimaryCommandRouting(unittest.TestCase):
    def test_pure_integrity_still_ok(self):
        self.assertTrue(research_queue_primary_command_integrity().get("ok"))
        p = build_research_queue_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)

    def test_gamedata_apply_functions_exist(self):
        gd = GD_PATH.read_text(encoding="utf-8")
        self.assertIn("const RESEARCH_QUEUE_PRIMARY_STEPS", gd)
        self.assertIn("func apply_research_queue_primary_command_step_live(", gd)
        self.assertIn("func apply_research_queue_primary_command_live(", gd)
        self.assertIn("func format_research_queue_primary_command_product_plain(", gd)
        self.assertIn("func apply_research_queue_primary_command_product(", gd)
        for step in PRIMARY_COMMAND_STEPS:
            self.assertIn(
                '"%s"' % step,
                gd,
                msg="missing step in RESEARCH_QUEUE_PRIMARY_STEPS: %s" % step,
            )

    def test_open_and_close_route_real_apis(self):
        """open_queue/close must call catalog/research_close, never apply_focus."""
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_research_queue_primary_command_step_live")
        self.assertIn("func apply_research_queue_primary_command_step_live(", body)
        self.assertIn('s == "open_queue"', body)
        self.assertIn("apply_tech_research_catalog", body)
        self.assertIn('s == "close"', body)
        self.assertIn("apply_tech_research_close_day", body)
        self.assertNotIn('leaf = "apply_focus"', body)
        self.assertNotIn('live_api = "apply_focus"', body)
        self.assertEqual(
            LIVE_API_BY_STEP["open_queue"], "apply_tech_research_catalog"
        )
        self.assertEqual(
            LIVE_API_BY_STEP["close"], "apply_tech_research_close_day"
        )
        self.assertIn("func apply_tech_research_catalog(", gd)
        self.assertIn("func apply_tech_research_close_day(", gd)

    def test_enqueue_gate_advance_route_real_apis(self):
        """enqueue/gate/advance must call real tech live APIs."""
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_research_queue_primary_command_step_live")
        self.assertIn('s == "enqueue_branch"', body)
        self.assertIn("apply_tech_branch_live", body)
        self.assertIn('s == "gate_check"', body)
        self.assertIn("apply_tech_tree_branches", body)
        self.assertIn('s == "advance_month"', body)
        self.assertIn("apply_tech_research_priority", body)
        self.assertEqual(LIVE_API_BY_STEP["enqueue_branch"], "apply_tech_branch_live")
        self.assertEqual(
            LIVE_API_BY_STEP["gate_check"], "apply_tech_tree_branches"
        )
        self.assertEqual(
            LIVE_API_BY_STEP["advance_month"], "apply_tech_research_priority"
        )
        self.assertIn("func apply_tech_branch_live(", gd)
        self.assertIn("func apply_tech_tree_branches(", gd)
        self.assertIn("func apply_tech_research_priority(", gd)

    def test_formatter_mapmanager_panel_loader_wired(self):
        fmt = FMT_PATH.read_text(encoding="utf-8")
        mm = MM_PATH.read_text(encoding="utf-8")
        panel = PANEL_PATH.read_text(encoding="utf-8")
        sl = SL_PATH.read_text(encoding="utf-8")
        gd = GD_PATH.read_text(encoding="utf-8")
        self.assertIn("static func research_queue_primary_command_product(", fmt)
        self.assertIn("func research_queue_primary_command_product_live(", mm)
        self.assertIn("func apply_research_queue_primary_command_product(", mm)
        self.assertIn("_rebuild_research_queue_primary_command", panel)
        self.assertIn("research_queue_primary_command_product", panel)
        self.assertIn("research_queue_primary_live=1", sl)
        self.assertIn("_print_research_queue_primary_live_evidence", sl)
        self.assertIn("research_queue_primary_command_product", gd)
        self.assertIn("apply_research_queue_primary_command_live", gd)
        # priority registration
        self.assertIn('"research_queue_primary_command_product": 169', fmt)

    def test_live_package_ok_contract(self):
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_research_queue_primary_command_live")
        self.assertIn("majors_ok >= 5", body)
        self.assertIn("dead_n == 0", body)
        self.assertIn("research_queue_primary_ticks", body)
        self.assertIn('"research_queue_primary"', gd)
        self.assertIn("research_queue_primary_ticks", gd)
        self.assertIn('peace_state["research_queue_primary"]', gd)

    def test_prior_dual_markers_not_broken(self):
        """Regression: occupation, peace, fleet, stream_alpha, next20, hotseat, map_perf still present."""
        gd = GD_PATH.read_text(encoding="utf-8")
        panel = PANEL_PATH.read_text(encoding="utf-8")
        sl = SL_PATH.read_text(encoding="utf-8")
        self.assertIn("func apply_stream_alpha_primary_command_live(", gd)
        self.assertIn("const STREAM_ALPHA_STEPS", gd)
        self.assertIn("func apply_fleet_autonomy_primary_command_live(", gd)
        self.assertIn("const FLEET_AUTONOMY_PRIMARY_STEPS", gd)
        self.assertIn("func apply_peace_conference_primary_command_live(", gd)
        self.assertIn("const PEACE_CONFERENCE_PRIMARY_STEPS", gd)
        self.assertIn("func apply_occupation_primary_command_live(", gd)
        self.assertIn("const OCCUPATION_PRIMARY_STEPS", gd)
        self.assertIn("const NEXT20_STEPS", gd)
        self.assertIn("func apply_next20_completion_live(", gd)
        self.assertIn("_rebuild_stream_alpha_primary_command", panel)
        self.assertIn("_rebuild_fleet_autonomy_primary_command", panel)
        self.assertIn("_rebuild_peace_conference_primary_command", panel)
        self.assertIn("_rebuild_occupation_primary_command", panel)
        self.assertIn("stream_alpha_primary_live=1", sl)
        self.assertIn("fleet_autonomy_primary_live=1", sl)
        self.assertIn("peace_conference_primary_live=1", sl)
        self.assertIn("occupation_primary_live=1", sl)
        self.assertIn("next20_completion_live=1", sl)
        self.assertIn("hotseat_turn_banner_live=1", sl)
        self.assertIn("map_perf_fps_harness_live=1", sl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
