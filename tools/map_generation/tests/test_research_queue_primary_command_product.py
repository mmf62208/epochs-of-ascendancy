#!/usr/bin/env python3
"""Gates: Research queue UI primary command package (T1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from research_queue_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    LIVE_PRIMARY_ACTION_IDS,
    PRIMARY_ACTION_IDS,
    PRIMARY_COMMAND_STEPS,
    SURFACE_KEYS,
    apply_research_queue_primary_command_step,
    build_research_queue_primary_command_product,
    close_research_queue_primary_command_package,
    primary_command_dead_audit,
    research_queue_primary_command_integrity,
)


class TestResearchQueuePrimaryCommand(unittest.TestCase):
    def test_five_surfaces_t1_flow(self):
        self.assertEqual(len(SURFACE_KEYS), 5)
        self.assertEqual(
            list(SURFACE_KEYS),
            [
                "research_primary_open_queue",
                "research_primary_enqueue_branch",
                "research_primary_gate_check",
                "research_primary_advance_month",
                "research_primary_close",
            ],
        )
        p = build_research_queue_primary_command_product()
        for key in SURFACE_KEYS:
            self.assertIn(key, p.get("majors_ok") or {})
            self.assertTrue((p.get("majors_ok") or {}).get(key), msg="major not ok: %s" % key)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))

    def test_t1_step_names(self):
        self.assertEqual(
            list(PRIMARY_COMMAND_STEPS),
            [
                "open_queue",
                "enqueue_branch",
                "gate_check",
                "advance_month",
                "close",
            ],
        )
        p = build_research_queue_primary_command_product()
        self.assertEqual(list(p.get("step_ids") or []), list(PRIMARY_COMMAND_STEPS))
        self.assertEqual(len(p.get("steps") or []), 5)

    def test_dead_n_zero_full_live_set(self):
        audit = primary_command_dead_audit()
        self.assertEqual(int(audit.get("dead_n", 1)), 0)
        self.assertTrue(audit.get("ok"))
        p = build_research_queue_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertTrue(p.get("dead_ok"))
        bad = primary_command_dead_audit(
            ["apply_tech_research_catalog", "not_a_real_action"]
        )
        self.assertEqual(int(bad.get("dead_n", 0)), 1)
        self.assertFalse(bad.get("ok"))

    def test_live_api_strings_real_method_names(self):
        p = build_research_queue_primary_command_product()
        live_map = p.get("live_api_by_step") or LIVE_API_BY_STEP
        self.assertEqual(live_map["open_queue"], "apply_tech_research_catalog")
        self.assertEqual(live_map["enqueue_branch"], "apply_tech_branch_live")
        self.assertEqual(live_map["gate_check"], "apply_tech_tree_branches")
        self.assertEqual(live_map["advance_month"], "apply_tech_research_priority")
        self.assertEqual(live_map["close"], "apply_tech_research_close_day")
        blob = " ".join(str(live_map[s]) for s in PRIMARY_COMMAND_STEPS)
        self.assertIn("apply_tech_research_catalog", blob)
        self.assertIn("apply_tech_branch_live", blob)
        self.assertIn("apply_tech_tree_branches", blob)
        self.assertIn("apply_tech_research_priority", blob)
        self.assertIn("apply_tech_research_close_day", blob)
        for row in p.get("steps") or []:
            self.assertTrue(str(row.get("live_api") or ""), msg=row)
            self.assertEqual(
                str(row.get("live_api")), LIVE_API_BY_STEP[str(row["step"])]
            )
        self.assertIn("apply_tech_research_campaign_product", PRIMARY_ACTION_IDS)
        self.assertIn("apply_tech_tree_branching_product", PRIMARY_ACTION_IDS)
        self.assertIn("apply_tech_tree_path", PRIMARY_ACTION_IDS)
        self.assertIn("apply_tech_tree_branching_close_day", PRIMARY_ACTION_IDS)
        self.assertIn("apply_tech_branch_armor", PRIMARY_ACTION_IDS)

        # Verify GameData still hosts these method names (read-only honesty)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)
        for api in (
            "apply_tech_research_campaign_product",
            "apply_tech_tree_branching_product",
            "apply_tech_tree_path",
            "apply_tech_tree_field",
            "apply_tech_tree_branching_close_day",
            "apply_tech_branch_armor",
            "apply_tech_research_field",
        ):
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)

    def test_structural_no_apply_focus(self):
        """T1 steps must NOT list apply_focus (honest research leaves)."""
        p = build_research_queue_primary_command_product()
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
        p = build_research_queue_primary_command_product(
            province_id=2,
            era_year=1939,
            preferred="armor",
            resource_level=0.7,
            months_ahead=3,
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
            "research_queue_primary_command_product", p.get("integration") or []
        )
        self.assertIn("T1", p.get("integration") or [])
        self.assertIn("tech_research_campaign_product", p.get("integration") or [])
        self.assertIn("tech_tree_branching_product", p.get("integration") or [])
        self.assertIn("branch_locks", p.get("integration") or [])
        self.assertIn("resource_gates", p.get("integration") or [])
        self.assertIsInstance(p.get("tech"), dict)
        self.assertIsInstance(p.get("branch"), dict)
        self.assertIsInstance(p.get("board"), dict)
        self.assertFalse(bool((p.get("tech") or {}).get("empty")))
        self.assertFalse(bool((p.get("branch") or {}).get("empty")))
        self.assertGreaterEqual(int(p.get("catalog_count") or 0), 4)
        self.assertGreaterEqual(int(p.get("open_n") or 0), 3)
        self.assertEqual(int(p.get("era_year") or 0), 1939)
        self.assertEqual(str(p.get("path_branch") or ""), "armor")

    def test_step_apply_and_close(self):
        for step in PRIMARY_COMMAND_STEPS:
            res = apply_research_queue_primary_command_step(step, province_id=3)
            self.assertTrue(res.get("ok"), msg=res)
            self.assertEqual(res.get("step"), step)
            self.assertTrue(str(res.get("live_api") or ""))
            self.assertEqual(res.get("live_api"), LIVE_API_BY_STEP[step])
        # Aliases resolve
        alias = apply_research_queue_primary_command_step("catalog", province_id=1)
        self.assertEqual(alias.get("step"), "open_queue")
        alias2 = apply_research_queue_primary_command_step("priority", province_id=1)
        self.assertEqual(alias2.get("step"), "advance_month")
        alias3 = apply_research_queue_primary_command_step("path", province_id=1)
        self.assertEqual(alias3.get("step"), "enqueue_branch")
        closed = close_research_queue_primary_command_package(1)
        self.assertTrue(closed.get("ok"), msg=closed)
        self.assertEqual(int(closed.get("applied_n") or 0), len(PRIMARY_COMMAND_STEPS))
        self.assertEqual(int(closed.get("dead_n", 1)), 0)
        self.assertTrue(research_queue_primary_command_integrity().get("ok"))

    def test_primary_actions_subset_of_live(self):
        for aid in PRIMARY_ACTION_IDS:
            self.assertIn(aid, LIVE_PRIMARY_ACTION_IDS)

    def test_resource_and_year_compose_branch_gates(self):
        full = build_research_queue_primary_command_product(
            era_year=1941, resource_level=0.85, preferred="armor"
        )
        early = build_research_queue_primary_command_product(
            era_year=1920, resource_level=0.25, preferred="infantry"
        )
        self.assertGreaterEqual(float(full.get("score") or 0), 0.35)
        self.assertGreaterEqual(float(early.get("score") or 0), 0.35)
        # Later year should open more branches
        self.assertGreaterEqual(int(full.get("open_n") or 0), int(early.get("open_n") or 0))
        # Multi-month (12+) player loop parameter accepted
        multi = build_research_queue_primary_command_product(months_ahead=12)
        self.assertEqual(int(multi.get("months_ahead") or 0), 12)
        self.assertGreaterEqual(float(multi.get("score") or 0), 0.35)
        adv = multi.get("advance_month") or {}
        self.assertEqual(int(adv.get("months_ahead") or 0), 12)
        gate = full.get("gate_check") or {}
        self.assertTrue(gate.get("gates_ok") or float(gate.get("gate_score") or 0) >= 0.35)


if __name__ == "__main__":
    unittest.main(verbosity=2)
