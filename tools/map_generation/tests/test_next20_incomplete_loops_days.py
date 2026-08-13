#!/usr/bin/env python3
"""Gates: next-110 incomplete play loops (20) + GIS×753 + live GD wiring.

Advances live mutation/feedback, multi-phase combat surface, fleet/HH path.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next110_incomplete_loops import (  # noqa: E402
    INCOMPLETE_LOOP_DAY_IDS,
    DAY_FUNCS,
    close_next110_incomplete_loops_loop,
    incomplete_loop_integrity,
    # shipped helpers exercised via packages
    live_mut_board_day,
    combat_surface_stack_day,
    hh_path_stack_day,
    fleet_path_stack_day,
)

WF = ROOT / "data" / "provinces_world_full"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"

LIVE = {
    "live_mut_board_day", "feedback_chain_day", "mut_close_stack_day",
    "dual_domain_mutate_day", "assault_mut_fb_day", "agent_mut_log_day",
    "supply_mut_fb_day", "hh_path_stack_day", "hh_trail_counter_day",
    "agent_mission_path_day", "incomplete_loop_close_day",
}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_twenty(self) -> None:
        self.assertEqual(len(INCOMPLETE_LOOP_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)

    def test_each(self) -> None:
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"), fn.__name__)
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1, fn.__name__)
                acts = day.get("actions") or []
                self.assertTrue(isinstance(acts, list) and len(acts) >= 1, fn.__name__)
                aid = str(acts[0].get("action_id", ""))
                self.assertIn(aid, INCOMPLETE_LOOP_DAY_IDS)
                self.assertEqual(aid, fn.__name__)

    def test_theme_helpers_shipped(self) -> None:
        """Drive real theme packages (mutation / combat surface / fleet / HH)."""
        mut = live_mut_board_day()
        self.assertFalse(mut.get("empty"))
        self.assertIn("gate", mut)
        combat = combat_surface_stack_day()
        self.assertFalse(combat.get("empty"))
        self.assertIn("estimate", combat)
        self.assertIn("card", combat)
        self.assertIn("ribbon", combat)
        fleet = fleet_path_stack_day()
        self.assertFalse(fleet.get("empty"))
        self.assertIn("task_group", fleet)
        hh = hh_path_stack_day()
        self.assertFalse(hh.get("empty"))
        self.assertIn("order", hh)
        self.assertGreaterEqual(float(hh.get("score", 0)), 0.5)

    def test_close(self) -> None:
        loop = close_next110_incomplete_loops_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(incomplete_loop_integrity().get("ok"))


class TestLive(unittest.TestCase):

    def test_mpf_composes_theme_helpers(self) -> None:
        """MPF next110 formatters must compose real GD helpers (not score:=0.55 stubs)."""
        fmt = GD_FMT.read_text(encoding="utf-8")
        # Isolate composed next110 day package section
        marker = "## Next-110 incomplete play loop day packages (20)"
        idx = fmt.find(marker)
        self.assertGreaterEqual(idx, 0)
        # Prefer the composed section header when present
        composed = fmt.find("Composes existing GD theme helpers")
        if composed >= 0:
            idx = composed
        sec = fmt[idx:]
        # No generic identical stub body for live_mut_board
        self.assertIn("mutation_integrity_gate", sec)
        self.assertIn("mutation_decision_strip", sec)
        self.assertIn("estimate_multi_phase_combat", sec)
        self.assertIn("hh_order_commit", sec)
        self.assertIn("compose_fleet_task_group", sec)
        self.assertIn("fleet_station_mutation", sec)
        self.assertIn("joint_combat_timeline", sec)
        self.assertIn("next_day_mutation_feedback", sec)
        # live_mut_board_day body must call gate (not only hardcode score 0.55)
        live_i = sec.find("static func live_mut_board_day")
        self.assertGreaterEqual(live_i, 0)
        live_body = sec[live_i: live_i + 900]
        self.assertIn("mutation_integrity_gate", live_body)
        self.assertNotIn("var score := 0.55", live_body)
        combat_i = sec.find("static func combat_surface_stack_day")
        combat_body = sec[combat_i: combat_i + 900]
        self.assertIn("estimate_multi_phase_combat", combat_body)
        hh_i = sec.find("static func hh_path_stack_day")
        hh_body = sec[hh_i: hh_i + 900]
        self.assertIn("hh_order_commit", hh_body)
        # MapManager must surface live metadata, not bare passthrough only
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("_next110_live_day", mm)
        self.assertIn("gate_ok", mm)
        self.assertIn("hh_order", mm)
        self.assertIn("win_chance", mm)

    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        for aid in INCOMPLETE_LOOP_DAY_IDS:
            self.assertIn("func %s" % aid, fmt, msg="MPF %s" % aid)
            self.assertIn(aid, gd, msg="GD %s" % aid)
            self.assertIn(aid, panel, msg="panel %s" % aid)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm, msg="MM %s" % live)
        for key in (
            "live_mut_board_day",
            "combat_surface_stack_day",
            "fleet_path_stack_day",
            "hh_path_stack_day",
            "incomplete_loop_close_day",
        ):
            self.assertIn(key, pi)
        self.assertIn("test_next20_incomplete_loops_days.py", CI.read_text(encoding="utf-8"))
        labels = [
            "live mut board day", "feedback chain day", "mut close stack day",
            "dual domain mutate day", "assault mut fb day", "agent mut log day",
            "supply mut fb day", "combat surface stack day", "phase timeline stack day",
            "assault rank card day", "joint naval land day", "multi front surface day",
            "combat depth strip day", "phase estimate ribbon day", "fleet path stack day",
            "basing mission day", "hh path stack day", "hh trail counter day",
            "agent mission path day", "incomplete loop close day", "next-110 incomplete",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
