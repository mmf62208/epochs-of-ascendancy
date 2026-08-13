#!/usr/bin/env python3
"""Gates: Stream α primary player-command package (C1/P1/S1/L1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from stream_alpha_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    LIVE_PRIMARY_ACTION_IDS,
    PRIMARY_ACTION_IDS,
    PRIMARY_COMMAND_STEPS,
    SURFACE_KEYS,
    apply_stream_alpha_primary_command_step,
    build_stream_alpha_primary_command_product,
    close_stream_alpha_primary_command_package,
    primary_command_dead_audit,
    stream_alpha_primary_command_integrity,
)


class TestStreamAlphaPrimaryCommand(unittest.TestCase):
    def test_four_majors_surface(self):
        self.assertEqual(len(SURFACE_KEYS), 4)
        self.assertEqual(
            list(SURFACE_KEYS),
            [
                "combat_primary_ribbon",
                "oob_primary_honesty",
                "save_primary_browser",
                "hh_primary_agenda",
            ],
        )
        p = build_stream_alpha_primary_command_product()
        for key in SURFACE_KEYS:
            self.assertIn(key, p.get("majors_ok") or {})
            self.assertTrue((p.get("majors_ok") or {}).get(key), msg="major not ok: %s" % key)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 4)
        self.assertTrue(p.get("all_majors_ok"))

    def test_dead_n_zero_full_live_set(self):
        audit = primary_command_dead_audit()
        self.assertEqual(int(audit.get("dead_n", 1)), 0)
        self.assertTrue(audit.get("ok"))
        p = build_stream_alpha_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertTrue(p.get("dead_ok"))
        # Unknown action is dead
        bad = primary_command_dead_audit(["apply_combat_ops_close_live", "not_a_real_action"])
        self.assertEqual(int(bad.get("dead_n", 0)), 1)
        self.assertFalse(bad.get("ok"))

    def test_live_api_strings_real_method_names(self):
        p = build_stream_alpha_primary_command_product()
        live_map = p.get("live_api_by_step") or LIVE_API_BY_STEP
        # Combat close-live / multi-phase routing
        combat_apis = " ".join(
            str(live_map[s]) for s in PRIMARY_COMMAND_STEPS if s.startswith("combat_")
        )
        self.assertIn("apply_combat_ops_close_live", combat_apis)
        # OOB horizons + medium product
        oob_blob = " ".join(
            str(live_map[s])
            for s in PRIMARY_COMMAND_STEPS
            if s.startswith("medium_")
        )
        self.assertIn("apply_medium_tank_oob_product", oob_blob)
        self.assertIn("apply_oob_horizon_60d", oob_blob)
        self.assertIn("apply_oob_horizon_100d", oob_blob)
        # Save browser
        save_blob = " ".join(
            str(live_map[s]) for s in PRIMARY_COMMAND_STEPS if s.startswith("save_")
        )
        self.assertIn("save_browser_campaign_product_live", save_blob)
        self.assertIn("apply_save_browser_resume", save_blob)
        self.assertIn("apply_save_browser_checkpoint", save_blob)
        # HH agenda
        hh_blob = " ".join(
            str(live_map[s]) for s in PRIMARY_COMMAND_STEPS if s.startswith("hh_")
        )
        self.assertIn("apply_hh_agenda_close_live", hh_blob)
        # Every step row carries live_api
        for row in p.get("steps") or []:
            self.assertTrue(str(row.get("live_api") or ""), msg=row)
            self.assertEqual(str(row.get("live_api")), LIVE_API_BY_STEP[str(row["step"])])

    def test_structural_no_apply_focus_on_oob_or_save(self):
        """Medium OOB steps and save steps must NOT list apply_focus."""
        p = build_stream_alpha_primary_command_product()
        for row in p.get("steps") or []:
            major = str(row.get("major") or "")
            live = str(row.get("live_api") or "")
            leaf = str(row.get("leaf_action") or "")
            if major == "oob_primary_honesty":
                self.assertNotIn("apply_focus", live)
                self.assertNotIn("apply_focus", leaf)
            if major == "save_primary_browser":
                self.assertNotIn("apply_focus", live)
                self.assertNotIn("apply_focus", leaf)
        for step, api in LIVE_API_BY_STEP.items():
            if step.startswith("medium_") or step.startswith("save_"):
                self.assertNotEqual(api, "apply_focus")
                self.assertNotIn("apply_focus", api)
        # apply_queue honesty for those majors
        for item in p.get("apply_queue") or []:
            if str(item.get("major")) in ("oob_primary_honesty", "save_primary_browser"):
                self.assertNotEqual(str(item.get("action_id")), "apply_focus")

    def test_full_build_plain_score_range(self):
        p = build_stream_alpha_primary_command_product(province_id=2)
        self.assertFalse(p.get("empty"))
        plain = str(p.get("plain") or "")
        summary = str(p.get("summary") or "")
        self.assertTrue(plain.strip())
        self.assertTrue(summary.strip())
        score = float(p.get("score") or 0)
        self.assertGreaterEqual(score, 0.35)
        self.assertLessEqual(score, 1.0)
        self.assertGreaterEqual(len(p.get("steps") or []), 12)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 12)
        self.assertIn("stream_alpha_primary_command_product", p.get("integration") or [])
        self.assertIn("C1", p.get("integration") or [])
        self.assertIn("P1", p.get("integration") or [])
        self.assertIn("S1", p.get("integration") or [])
        self.assertIn("L1", p.get("integration") or [])

    def test_step_apply_and_close(self):
        for step in PRIMARY_COMMAND_STEPS:
            res = apply_stream_alpha_primary_command_step(step, province_id=3)
            self.assertTrue(res.get("ok"), msg=res)
            self.assertEqual(res.get("step"), step)
            self.assertTrue(str(res.get("live_api") or ""))
        closed = close_stream_alpha_primary_command_package(1)
        self.assertTrue(closed.get("ok"), msg=closed)
        self.assertEqual(int(closed.get("applied_n") or 0), len(PRIMARY_COMMAND_STEPS))
        self.assertEqual(int(closed.get("dead_n", 1)), 0)
        self.assertTrue(stream_alpha_primary_command_integrity().get("ok"))

    def test_primary_actions_subset_of_live(self):
        for aid in PRIMARY_ACTION_IDS:
            self.assertIn(aid, LIVE_PRIMARY_ACTION_IDS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
