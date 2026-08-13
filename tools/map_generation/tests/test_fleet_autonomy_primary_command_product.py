#!/usr/bin/env python3
"""Gates: Fleet multi-day autonomy primary command package (C2 / A2)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from fleet_autonomy_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    LIVE_PRIMARY_ACTION_IDS,
    PRIMARY_ACTION_IDS,
    PRIMARY_COMMAND_STEPS,
    SURFACE_KEYS,
    apply_fleet_autonomy_primary_command_step,
    build_fleet_autonomy_primary_command_product,
    close_fleet_autonomy_primary_command_package,
    fleet_autonomy_primary_command_integrity,
    primary_command_dead_audit,
)


class TestFleetAutonomyPrimaryCommand(unittest.TestCase):
    def test_four_majors_surface(self):
        self.assertEqual(len(SURFACE_KEYS), 4)
        self.assertEqual(
            list(SURFACE_KEYS),
            [
                "fleet_primary_posture",
                "fleet_primary_station_escort",
                "fleet_primary_follow_through",
                "fleet_primary_autonomy_close",
            ],
        )
        p = build_fleet_autonomy_primary_command_product()
        for key in SURFACE_KEYS:
            self.assertIn(key, p.get("majors_ok") or {})
            self.assertTrue((p.get("majors_ok") or {}).get(key), msg="major not ok: %s" % key)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 4)
        self.assertTrue(p.get("all_majors_ok"))

    def test_next20_step_names(self):
        self.assertEqual(
            list(PRIMARY_COMMAND_STEPS),
            [
                "fleet_posture_day",
                "fleet_station_escort",
                "fleet_follow_through",
                "fleet_autonomy_close",
            ],
        )
        p = build_fleet_autonomy_primary_command_product()
        self.assertEqual(list(p.get("step_ids") or []), list(PRIMARY_COMMAND_STEPS))
        self.assertEqual(len(p.get("steps") or []), 4)

    def test_dead_n_zero_full_live_set(self):
        audit = primary_command_dead_audit()
        self.assertEqual(int(audit.get("dead_n", 1)), 0)
        self.assertTrue(audit.get("ok"))
        p = build_fleet_autonomy_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertTrue(p.get("dead_ok"))
        bad = primary_command_dead_audit(
            ["apply_fleet_day_posture", "not_a_real_action"]
        )
        self.assertEqual(int(bad.get("dead_n", 0)), 1)
        self.assertFalse(bad.get("ok"))

    def test_live_api_strings_real_method_names(self):
        p = build_fleet_autonomy_primary_command_product()
        live_map = p.get("live_api_by_step") or LIVE_API_BY_STEP
        self.assertEqual(live_map["fleet_posture_day"], "apply_fleet_day_posture")
        self.assertEqual(
            live_map["fleet_station_escort"], "apply_fleet_day_station_escort"
        )
        self.assertEqual(
            live_map["fleet_follow_through"], "apply_fleet_day_follow_through"
        )
        self.assertEqual(live_map["fleet_autonomy_close"], "apply_naval_ops_close_live")
        blob = " ".join(str(live_map[s]) for s in PRIMARY_COMMAND_STEPS)
        self.assertIn("apply_fleet_day_posture", blob)
        self.assertIn("apply_fleet_day_station_escort", blob)
        self.assertIn("apply_fleet_day_follow_through", blob)
        self.assertIn("apply_naval_ops_close_live", blob)
        for row in p.get("steps") or []:
            self.assertTrue(str(row.get("live_api") or ""), msg=row)
            self.assertEqual(
                str(row.get("live_api")), LIVE_API_BY_STEP[str(row["step"])]
            )
        # Primary action set includes multi-day product + sequence
        self.assertIn("apply_fleet_multi_day_autonomy_product", PRIMARY_ACTION_IDS)
        self.assertIn("apply_fleet_multi_day_sequence", PRIMARY_ACTION_IDS)

    def test_structural_no_apply_focus(self):
        """Fleet day + naval close steps must NOT list apply_focus."""
        p = build_fleet_autonomy_primary_command_product()
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
        p = build_fleet_autonomy_primary_command_product(province_id=2, fuel_level=0.7)
        self.assertFalse(p.get("empty"))
        plain = str(p.get("plain") or "")
        summary = str(p.get("summary") or "")
        self.assertTrue(plain.strip())
        self.assertTrue(summary.strip())
        score = float(p.get("score") or 0)
        self.assertGreaterEqual(score, 0.35)
        self.assertLessEqual(score, 1.0)
        self.assertEqual(len(p.get("steps") or []), 4)
        self.assertEqual(len(p.get("apply_queue") or []), 4)
        self.assertIn("fleet_autonomy_primary_command_product", p.get("integration") or [])
        self.assertIn("C2", p.get("integration") or [])
        self.assertIn("A2", p.get("integration") or [])
        self.assertIn("fleet_multi_day_autonomy_product", p.get("integration") or [])
        self.assertIn("naval_multi_phase_campaign_product", p.get("integration") or [])
        # Composed products present
        self.assertIsInstance(p.get("fleet"), dict)
        self.assertIsInstance(p.get("naval"), dict)
        self.assertFalse(bool((p.get("fleet") or {}).get("empty")))

    def test_step_apply_and_close(self):
        for step in PRIMARY_COMMAND_STEPS:
            res = apply_fleet_autonomy_primary_command_step(step, province_id=3)
            self.assertTrue(res.get("ok"), msg=res)
            self.assertEqual(res.get("step"), step)
            self.assertTrue(str(res.get("live_api") or ""))
            self.assertEqual(res.get("live_api"), LIVE_API_BY_STEP[step])
        # Aliases resolve
        alias = apply_fleet_autonomy_primary_command_step("posture", province_id=1)
        self.assertEqual(alias.get("step"), "fleet_posture_day")
        closed = close_fleet_autonomy_primary_command_package(1)
        self.assertTrue(closed.get("ok"), msg=closed)
        self.assertEqual(int(closed.get("applied_n") or 0), len(PRIMARY_COMMAND_STEPS))
        self.assertEqual(int(closed.get("dead_n", 1)), 0)
        self.assertTrue(fleet_autonomy_primary_command_integrity().get("ok"))

    def test_primary_actions_subset_of_live(self):
        for aid in PRIMARY_ACTION_IDS:
            self.assertIn(aid, LIVE_PRIMARY_ACTION_IDS)

    def test_fuel_composes_fleet_product(self):
        full = build_fleet_autonomy_primary_command_product(fuel_level=0.75)
        low = build_fleet_autonomy_primary_command_product(fuel_level=0.25)
        # Underlying fleet product should feel fuel; package scores remain valid
        self.assertGreaterEqual(float(full.get("score") or 0), 0.35)
        self.assertGreaterEqual(float(low.get("score") or 0), 0.35)
        fleet_full = float((full.get("fleet") or {}).get("score") or 0)
        fleet_low = float((low.get("fleet") or {}).get("score") or 0)
        self.assertGreater(fleet_full, fleet_low)


if __name__ == "__main__":
    unittest.main(verbosity=2)
