#!/usr/bin/env python3
"""Gates: Agent network map + mission board primary command package (I1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from agent_mission_board_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    LIVE_PRIMARY_ACTION_IDS,
    PRIMARY_ACTION_IDS,
    PRIMARY_COMMAND_STEPS,
    SURFACE_KEYS,
    agent_mission_board_primary_command_integrity,
    apply_agent_mission_board_primary_command_step,
    build_agent_mission_board_primary_command_product,
    close_agent_mission_board_primary_command_package,
    primary_command_dead_audit,
)


class TestAgentMissionBoardPrimaryCommand(unittest.TestCase):
    def test_five_surfaces_i1_flow(self):
        self.assertEqual(len(SURFACE_KEYS), 5)
        self.assertEqual(
            list(SURFACE_KEYS),
            [
                "agent_primary_board_surface",
                "agent_primary_dispatch",
                "agent_primary_resolve",
                "agent_primary_counter_intel",
                "agent_primary_close",
            ],
        )
        p = build_agent_mission_board_primary_command_product()
        for key in SURFACE_KEYS:
            self.assertIn(key, p.get("majors_ok") or {})
            self.assertTrue((p.get("majors_ok") or {}).get(key), msg="major not ok: %s" % key)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))

    def test_i1_step_names(self):
        self.assertEqual(
            list(PRIMARY_COMMAND_STEPS),
            [
                "board_surface",
                "dispatch_mission",
                "resolve_mission",
                "counter_intel",
                "close",
            ],
        )
        p = build_agent_mission_board_primary_command_product()
        self.assertEqual(list(p.get("step_ids") or []), list(PRIMARY_COMMAND_STEPS))
        self.assertEqual(len(p.get("steps") or []), 5)

    def test_dead_n_zero_full_live_set(self):
        audit = primary_command_dead_audit()
        self.assertEqual(int(audit.get("dead_n", 1)), 0)
        self.assertTrue(audit.get("ok"))
        p = build_agent_mission_board_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertTrue(p.get("dead_ok"))
        bad = primary_command_dead_audit(
            ["apply_agent_product_board", "not_a_real_action"]
        )
        self.assertEqual(int(bad.get("dead_n", 0)), 1)
        self.assertFalse(bad.get("ok"))

    def test_live_api_strings_real_method_names(self):
        p = build_agent_mission_board_primary_command_product()
        live_map = p.get("live_api_by_step") or LIVE_API_BY_STEP
        self.assertEqual(live_map["board_surface"], "apply_agent_product_board")
        self.assertEqual(live_map["dispatch_mission"], "apply_agent_product_dispatch")
        self.assertEqual(live_map["resolve_mission"], "apply_agent_missions_day")
        self.assertEqual(live_map["counter_intel"], "apply_agent_product_counterplay")
        self.assertEqual(live_map["close"], "apply_agent_hh_close_day")
        blob = " ".join(str(live_map[s]) for s in PRIMARY_COMMAND_STEPS)
        self.assertIn("apply_agent_product_board", blob)
        self.assertIn("apply_agent_product_dispatch", blob)
        self.assertIn("apply_agent_missions_day", blob)
        self.assertIn("apply_agent_product_counterplay", blob)
        self.assertIn("apply_agent_hh_close_day", blob)
        for row in p.get("steps") or []:
            self.assertTrue(str(row.get("live_api") or ""), msg=row)
            self.assertEqual(
                str(row.get("live_api")), LIVE_API_BY_STEP[str(row["step"])]
            )
        self.assertIn("apply_agent_campaign_product", PRIMARY_ACTION_IDS)
        self.assertIn("apply_agent_campaign_sequence", PRIMARY_ACTION_IDS)
        self.assertIn("apply_agent_ai_board_day", PRIMARY_ACTION_IDS)
        self.assertIn("apply_counterplay_campaign_day", PRIMARY_ACTION_IDS)
        self.assertIn("apply_agent_mission_ops_day", PRIMARY_ACTION_IDS)

        # Verify GameData still hosts these method names (read-only honesty)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)
        for api in (
            "apply_agent_campaign_product",
            "apply_agent_campaign_sequence",
            "apply_agent_ai_board_day",
            "apply_counterplay_campaign_day",
            "apply_agent_mission_ops_day",
        ):
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)

    def test_structural_no_apply_focus(self):
        """I1 steps must NOT list apply_focus (honest agent mission leaves)."""
        p = build_agent_mission_board_primary_command_product()
        for row in p.get("steps") or []:
            live = str(row.get("live_api") or "")
            leaf = str(row.get("leaf_action") or "")
            self.assertNotIn("apply_focus", live)
            self.assertNotIn("apply_focus", leaf)
        for step, api in LIVE_API_BY_STEP.items():
            self.assertNotEqual(api, "apply_focus")
            self.assertNotIn("apply_focus", api)
        for item in p.get("apply_queue") or []:
            self.assertNotEqual(str(item.get("action_id")), "apply_focus")

    def test_full_build_plain_score_range(self):
        p = build_agent_mission_board_primary_command_product(
            province_id=2,
            available_agents=5,
            network_strength=0.4,
            loyalty=0.5,
            max_dispatches=3,
        )
        self.assertFalse(p.get("empty"))
        plain = str(p.get("plain") or "")
        summary = str(p.get("summary") or "")
        self.assertTrue(plain.strip())
        self.assertTrue(summary.strip())
        score = float(p.get("score") or 0)
        self.assertGreaterEqual(score, 0.35)
        self.assertLessEqual(score, 1.0)
        self.assertEqual(len(p.get("steps") or []), 5)
        self.assertEqual(len(p.get("apply_queue") or []), 5)
        self.assertIn(
            "agent_mission_board_primary_command_product", p.get("integration") or []
        )
        self.assertIn("I1", p.get("integration") or [])
        self.assertIn("agent_campaign_product", p.get("integration") or [])
        self.assertIn("intelligence_network_product", p.get("integration") or [])
        self.assertIn("intel_cell_network_product", p.get("integration") or [])
        self.assertIn("MissionPickerPopup", p.get("integration") or [])
        self.assertIsInstance(p.get("agent"), dict)
        self.assertIsInstance(p.get("intel"), dict)
        self.assertIsInstance(p.get("cells"), dict)
        self.assertFalse(bool((p.get("agent") or {}).get("empty")))
        self.assertFalse(bool((p.get("intel") or {}).get("empty")))
        self.assertGreaterEqual(int(p.get("signal_count") or 0), 1)
        self.assertTrue(str(p.get("best_mission") or ""))

    def test_step_apply_and_close(self):
        for step in PRIMARY_COMMAND_STEPS:
            res = apply_agent_mission_board_primary_command_step(step, province_id=3)
            self.assertTrue(res.get("ok"), msg=res)
            self.assertEqual(res.get("step"), step)
            self.assertTrue(str(res.get("live_api") or ""))
            self.assertEqual(res.get("live_api"), LIVE_API_BY_STEP[step])
        # Aliases resolve
        alias_board = apply_agent_mission_board_primary_command_step("board", province_id=1)
        self.assertEqual(alias_board.get("step"), "board_surface")
        alias_disp = apply_agent_mission_board_primary_command_step("dispatch", province_id=1)
        self.assertEqual(alias_disp.get("step"), "dispatch_mission")
        alias_res = apply_agent_mission_board_primary_command_step("resolve", province_id=1)
        self.assertEqual(alias_res.get("step"), "resolve_mission")
        alias_cp = apply_agent_mission_board_primary_command_step("counterplay", province_id=1)
        self.assertEqual(alias_cp.get("step"), "counter_intel")
        alias_close = apply_agent_mission_board_primary_command_step("toast", province_id=1)
        self.assertEqual(alias_close.get("step"), "close")
        closed = close_agent_mission_board_primary_command_package(1)
        self.assertTrue(closed.get("ok"), msg=closed)
        self.assertEqual(int(closed.get("applied_n") or 0), len(PRIMARY_COMMAND_STEPS))
        self.assertEqual(int(closed.get("dead_n", 1)), 0)
        self.assertTrue(str(closed.get("toast") or ""))
        self.assertTrue(agent_mission_board_primary_command_integrity().get("ok"))

    def test_primary_actions_subset_of_live(self):
        for aid in PRIMARY_ACTION_IDS:
            self.assertIn(aid, LIVE_PRIMARY_ACTION_IDS)

    def test_agents_compose_campaign_product(self):
        thin = build_agent_mission_board_primary_command_product(
            available_agents=2, network_strength=0.25, max_dispatches=1
        )
        rich = build_agent_mission_board_primary_command_product(
            available_agents=6, network_strength=0.6, max_dispatches=4
        )
        self.assertGreaterEqual(float(thin.get("score") or 0), 0.35)
        self.assertGreaterEqual(float(rich.get("score") or 0), 0.35)
        self.assertGreaterEqual(int(thin.get("available_agents") or 0), 1)
        self.assertGreaterEqual(int(rich.get("available_agents") or 0), 1)
        agent_thin = float((thin.get("agent") or {}).get("score") or 0)
        agent_rich = float((rich.get("agent") or {}).get("score") or 0)
        self.assertGreaterEqual(agent_thin, 0.35)
        self.assertGreaterEqual(agent_rich, 0.35)


if __name__ == "__main__":
    unittest.main(verbosity=2)
