#!/usr/bin/env python3
"""Gates: Occupation mapmode + laws + garrison primary command package (O1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from occupation_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    LIVE_PRIMARY_ACTION_IDS,
    PRIMARY_ACTION_IDS,
    PRIMARY_COMMAND_STEPS,
    SURFACE_KEYS,
    apply_occupation_primary_command_step,
    build_occupation_primary_command_product,
    close_occupation_primary_command_package,
    occupation_primary_command_integrity,
    primary_command_dead_audit,
)


class TestOccupationPrimaryCommand(unittest.TestCase):
    def test_five_surfaces_o1_flow(self):
        self.assertEqual(len(SURFACE_KEYS), 5)
        self.assertEqual(
            list(SURFACE_KEYS),
            [
                "occupation_primary_mapmode",
                "occupation_primary_law",
                "occupation_primary_garrison",
                "occupation_primary_rc_pulse",
                "occupation_primary_close",
            ],
        )
        p = build_occupation_primary_command_product()
        for key in SURFACE_KEYS:
            self.assertIn(key, p.get("majors_ok") or {})
            self.assertTrue((p.get("majors_ok") or {}).get(key), msg="major not ok: %s" % key)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))

    def test_o1_step_names(self):
        self.assertEqual(
            list(PRIMARY_COMMAND_STEPS),
            [
                "mapmode_surface",
                "set_law",
                "garrison",
                "resistance_compliance_pulse",
                "occupation_close",
            ],
        )
        p = build_occupation_primary_command_product()
        self.assertEqual(list(p.get("step_ids") or []), list(PRIMARY_COMMAND_STEPS))
        self.assertEqual(len(p.get("steps") or []), 5)

    def test_dead_n_zero_full_live_set(self):
        audit = primary_command_dead_audit()
        self.assertEqual(int(audit.get("dead_n", 1)), 0)
        self.assertTrue(audit.get("ok"))
        p = build_occupation_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertTrue(p.get("dead_ok"))
        bad = primary_command_dead_audit(
            ["apply_occupation_resistance_board", "not_a_real_action"]
        )
        self.assertEqual(int(bad.get("dead_n", 0)), 1)
        self.assertFalse(bad.get("ok"))

    def test_live_api_strings_real_method_names(self):
        p = build_occupation_primary_command_product()
        live_map = p.get("live_api_by_step") or LIVE_API_BY_STEP
        self.assertEqual(
            live_map["mapmode_surface"], "apply_occupation_resistance_board"
        )
        self.assertEqual(live_map["set_law"], "apply_occupation_policy_live")
        self.assertEqual(live_map["garrison"], "apply_occupation_revolt_garrison")
        self.assertEqual(
            live_map["resistance_compliance_pulse"], "apply_occupation_daily_tick_live"
        )
        self.assertEqual(
            live_map["occupation_close"], "apply_occupation_resistance_close_day"
        )
        blob = " ".join(str(live_map[s]) for s in PRIMARY_COMMAND_STEPS)
        self.assertIn("apply_occupation_resistance_board", blob)
        self.assertIn("apply_occupation_policy_live", blob)
        self.assertIn("apply_occupation_revolt_garrison", blob)
        self.assertIn("apply_occupation_daily_tick_live", blob)
        self.assertIn("apply_occupation_resistance_close_day", blob)
        for row in p.get("steps") or []:
            self.assertTrue(str(row.get("live_api") or ""), msg=row)
            self.assertEqual(
                str(row.get("live_api")), LIVE_API_BY_STEP[str(row["step"])]
            )
        self.assertIn(
            "apply_occupation_resistance_compliance_product", PRIMARY_ACTION_IDS
        )
        self.assertIn("apply_occupation_revolt_garrison_product", PRIMARY_ACTION_IDS)
        self.assertIn("apply_occupation_garrison_standard", PRIMARY_ACTION_IDS)
        self.assertIn("apply_occupation_policy_moderate", PRIMARY_ACTION_IDS)
        self.assertIn(
            "apply_occupation_revolt_garrison_close_day", PRIMARY_ACTION_IDS
        )

        # Verify GameData still hosts these method names (read-only honesty)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)
        for api in (
            "apply_occupation_resistance_compliance_product",
            "apply_occupation_revolt_garrison_product",
            "apply_occupation_garrison_standard",
            "apply_occupation_policy_moderate",
            "apply_occupation_revolt_garrison_close_day",
        ):
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)

    def test_structural_no_apply_focus(self):
        """O1 steps must NOT list apply_focus (honest occupation leaves)."""
        p = build_occupation_primary_command_product()
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
        p = build_occupation_primary_command_product(
            province_id=2,
            resistance_level=0.6,
            compliance_level=0.35,
            policy="moderate",
            garrison_mode="standard",
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
            "occupation_primary_command_product", p.get("integration") or []
        )
        self.assertIn("O1", p.get("integration") or [])
        self.assertIn(
            "occupation_resistance_compliance_product", p.get("integration") or []
        )
        self.assertIn(
            "occupation_revolt_garrison_product", p.get("integration") or []
        )
        self.assertIn("occupation_control_product", p.get("integration") or [])
        self.assertIsInstance(p.get("rc"), dict)
        self.assertIsInstance(p.get("revolt"), dict)
        self.assertIsInstance(p.get("control"), dict)
        self.assertFalse(bool((p.get("rc") or {}).get("empty")))
        self.assertFalse(bool((p.get("revolt") or {}).get("empty")))
        self.assertGreaterEqual(float(p.get("resistance_level") or 0), 0.0)
        self.assertLessEqual(float(p.get("resistance_level") or 0), 1.0)
        self.assertGreaterEqual(float(p.get("compliance_level") or 0), 0.0)
        self.assertLessEqual(float(p.get("compliance_level") or 0), 1.0)

    def test_step_apply_and_close(self):
        for step in PRIMARY_COMMAND_STEPS:
            res = apply_occupation_primary_command_step(step, province_id=3)
            self.assertTrue(res.get("ok"), msg=res)
            self.assertEqual(res.get("step"), step)
            self.assertTrue(str(res.get("live_api") or ""))
            self.assertEqual(res.get("live_api"), LIVE_API_BY_STEP[step])
        # Aliases resolve
        alias_map = apply_occupation_primary_command_step("board", province_id=1)
        self.assertEqual(alias_map.get("step"), "mapmode_surface")
        alias_law = apply_occupation_primary_command_step("policy", province_id=1)
        self.assertEqual(alias_law.get("step"), "set_law")
        alias_garr = apply_occupation_primary_command_step(
            "deploy_garrison", province_id=1
        )
        self.assertEqual(alias_garr.get("step"), "garrison")
        alias_pulse = apply_occupation_primary_command_step("tick", province_id=1)
        self.assertEqual(alias_pulse.get("step"), "resistance_compliance_pulse")
        alias_close = apply_occupation_primary_command_step("close", province_id=1)
        self.assertEqual(alias_close.get("step"), "occupation_close")
        closed = close_occupation_primary_command_package(1)
        self.assertTrue(closed.get("ok"), msg=closed)
        self.assertEqual(int(closed.get("applied_n") or 0), len(PRIMARY_COMMAND_STEPS))
        self.assertEqual(int(closed.get("dead_n", 1)), 0)
        self.assertTrue(occupation_primary_command_integrity().get("ok"))

    def test_primary_actions_subset_of_live(self):
        for aid in PRIMARY_ACTION_IDS:
            self.assertIn(aid, LIVE_PRIMARY_ACTION_IDS)

    def test_policy_composes_rc_product(self):
        moderate = build_occupation_primary_command_product(policy="moderate")
        harsh = build_occupation_primary_command_product(
            policy="harsh", resistance_level=0.7, compliance_level=0.25
        )
        self.assertGreaterEqual(float(moderate.get("score") or 0), 0.35)
        self.assertGreaterEqual(float(harsh.get("score") or 0), 0.35)
        self.assertEqual(str(moderate.get("policy")), "moderate")
        self.assertEqual(str(harsh.get("policy")), "harsh")
        rc_mod = float((moderate.get("rc") or {}).get("score") or 0)
        rc_harsh = float((harsh.get("rc") or {}).get("score") or 0)
        self.assertGreaterEqual(rc_mod, 0.35)
        self.assertGreaterEqual(rc_harsh, 0.35)


if __name__ == "__main__":
    unittest.main(verbosity=2)
