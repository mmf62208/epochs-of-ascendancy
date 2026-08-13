#!/usr/bin/env python3
"""Gates: Agent mission board primary command dual wiring honesty (GD live routing)."""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from agent_mission_board_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    PRIMARY_COMMAND_STEPS,
    agent_mission_board_primary_command_integrity,
    build_agent_mission_board_primary_command_product,
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


class TestAgentMissionBoardPrimaryCommandRouting(unittest.TestCase):
    def test_pure_integrity_still_ok(self):
        self.assertTrue(agent_mission_board_primary_command_integrity().get("ok"))
        p = build_agent_mission_board_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)

    def test_gamedata_apply_functions_exist(self):
        gd = GD_PATH.read_text(encoding="utf-8")
        self.assertIn("const AGENT_MISSION_BOARD_PRIMARY_STEPS", gd)
        self.assertIn("func apply_agent_mission_board_primary_command_step_live(", gd)
        self.assertIn("func apply_agent_mission_board_primary_command_live(", gd)
        self.assertIn("func format_agent_mission_board_primary_command_product_plain(", gd)
        self.assertIn("func apply_agent_mission_board_primary_command_product(", gd)
        for step in PRIMARY_COMMAND_STEPS:
            self.assertIn(
                '"%s"' % step,
                gd,
                msg="missing step in AGENT_MISSION_BOARD_PRIMARY_STEPS: %s" % step,
            )

    def test_board_and_close_route_real_apis(self):
        """board_surface/close must call product_board/hh_close, never apply_focus."""
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_agent_mission_board_primary_command_step_live")
        self.assertIn("func apply_agent_mission_board_primary_command_step_live(", body)
        self.assertIn('s == "board_surface"', body)
        self.assertIn("apply_agent_product_board", body)
        self.assertIn('s == "close"', body)
        self.assertIn("apply_agent_hh_close_day", body)
        self.assertNotIn('leaf = "apply_focus"', body)
        self.assertNotIn('live_api = "apply_focus"', body)
        self.assertEqual(
            LIVE_API_BY_STEP["board_surface"], "apply_agent_product_board"
        )
        self.assertEqual(
            LIVE_API_BY_STEP["close"], "apply_agent_hh_close_day"
        )
        self.assertIn("func apply_agent_product_board(", gd)
        self.assertIn("func apply_agent_hh_close_day(", gd)

    def test_dispatch_resolve_counter_route_real_apis(self):
        """dispatch/resolve/counter must call real agent live APIs."""
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_agent_mission_board_primary_command_step_live")
        self.assertIn('s == "dispatch_mission"', body)
        self.assertIn("apply_agent_product_dispatch", body)
        self.assertIn('s == "resolve_mission"', body)
        self.assertIn("apply_agent_missions_day", body)
        self.assertIn('s == "counter_intel"', body)
        self.assertIn("apply_agent_product_counterplay", body)
        self.assertEqual(
            LIVE_API_BY_STEP["dispatch_mission"], "apply_agent_product_dispatch"
        )
        self.assertEqual(
            LIVE_API_BY_STEP["resolve_mission"], "apply_agent_missions_day"
        )
        self.assertEqual(
            LIVE_API_BY_STEP["counter_intel"], "apply_agent_product_counterplay"
        )
        self.assertIn("func apply_agent_product_dispatch(", gd)
        self.assertIn("func apply_agent_missions_day(", gd)
        self.assertIn("func apply_agent_product_counterplay(", gd)

    def test_formatter_mapmanager_panel_loader_wired(self):
        fmt = FMT_PATH.read_text(encoding="utf-8")
        mm = MM_PATH.read_text(encoding="utf-8")
        panel = PANEL_PATH.read_text(encoding="utf-8")
        sl = SL_PATH.read_text(encoding="utf-8")
        gd = GD_PATH.read_text(encoding="utf-8")
        self.assertIn("static func agent_mission_board_primary_command_product(", fmt)
        self.assertIn("func agent_mission_board_primary_command_product_live(", mm)
        self.assertIn("func apply_agent_mission_board_primary_command_product(", mm)
        self.assertIn("_rebuild_agent_mission_board_primary_command", panel)
        self.assertIn("agent_mission_board_primary_command_product", panel)
        self.assertIn("agent_mission_board_primary_live=1", sl)
        self.assertIn("_print_agent_mission_board_primary_live_evidence", sl)
        self.assertIn("agent_mission_board_primary_command_product", gd)
        self.assertIn("apply_agent_mission_board_primary_command_live", gd)
        # priority registration
        self.assertIn('"agent_mission_board_primary_command_product": 168', fmt)

    def test_live_package_ok_contract(self):
        gd = GD_PATH.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_agent_mission_board_primary_command_live")
        self.assertIn("majors_ok >= 5", body)
        self.assertIn("dead_n == 0", body)
        self.assertIn("agent_mission_board_primary_ticks", body)
        self.assertIn('"agent_mission_board_primary"', gd)
        self.assertIn("agent_mission_board_primary_ticks", gd)
        self.assertIn('peace_state["agent_mission_board_primary"]', gd)

    def test_prior_dual_markers_not_broken(self):
        """Regression: research, occupation, peace, fleet, stream_alpha, next20, hotseat, map_perf."""
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
        self.assertIn("func apply_research_queue_primary_command_live(", gd)
        self.assertIn("const RESEARCH_QUEUE_PRIMARY_STEPS", gd)
        self.assertIn("const NEXT20_STEPS", gd)
        self.assertIn("func apply_next20_completion_live(", gd)
        self.assertIn("_rebuild_stream_alpha_primary_command", panel)
        self.assertIn("_rebuild_fleet_autonomy_primary_command", panel)
        self.assertIn("_rebuild_peace_conference_primary_command", panel)
        self.assertIn("_rebuild_occupation_primary_command", panel)
        self.assertIn("_rebuild_research_queue_primary_command", panel)
        self.assertIn("stream_alpha_primary_live=1", sl)
        self.assertIn("fleet_autonomy_primary_live=1", sl)
        self.assertIn("peace_conference_primary_live=1", sl)
        self.assertIn("occupation_primary_live=1", sl)
        self.assertIn("research_queue_primary_live=1", sl)
        self.assertIn("next20_completion_live=1", sl)
        self.assertIn("hotseat_turn_banner_live=1", sl)
        self.assertIn("map_perf_fps_harness_live=1", sl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
