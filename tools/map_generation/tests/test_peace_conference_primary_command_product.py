#!/usr/bin/env python3
"""Gates: Multi-party peace conference human-flow primary command package (Di1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from peace_conference_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    LIVE_PRIMARY_ACTION_IDS,
    PRIMARY_ACTION_IDS,
    PRIMARY_COMMAND_STEPS,
    SURFACE_KEYS,
    apply_peace_conference_primary_command_step,
    build_peace_conference_primary_command_product,
    close_peace_conference_primary_command_package,
    peace_conference_primary_command_integrity,
    primary_command_dead_audit,
)


class TestPeaceConferencePrimaryCommand(unittest.TestCase):
    def test_five_surfaces_human_flow(self):
        self.assertEqual(len(SURFACE_KEYS), 5)
        self.assertEqual(
            list(SURFACE_KEYS),
            [
                "peace_primary_open",
                "peace_primary_claim",
                "peace_primary_cede",
                "peace_primary_puppet",
                "peace_primary_close",
            ],
        )
        p = build_peace_conference_primary_command_product()
        for key in SURFACE_KEYS:
            self.assertIn(key, p.get("majors_ok") or {})
            self.assertTrue((p.get("majors_ok") or {}).get(key), msg="major not ok: %s" % key)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))

    def test_human_flow_step_names(self):
        self.assertEqual(
            list(PRIMARY_COMMAND_STEPS),
            [
                "open_conference",
                "claim_province",
                "cede_province",
                "puppet_tag",
                "close_conference",
            ],
        )
        p = build_peace_conference_primary_command_product()
        self.assertEqual(list(p.get("step_ids") or []), list(PRIMARY_COMMAND_STEPS))
        self.assertEqual(len(p.get("steps") or []), 5)

    def test_dead_n_zero_full_live_set(self):
        audit = primary_command_dead_audit()
        self.assertEqual(int(audit.get("dead_n", 1)), 0)
        self.assertTrue(audit.get("ok"))
        p = build_peace_conference_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertTrue(p.get("dead_ok"))
        bad = primary_command_dead_audit(
            ["apply_multi_party_peace_board", "not_a_real_action"]
        )
        self.assertEqual(int(bad.get("dead_n", 0)), 1)
        self.assertFalse(bad.get("ok"))

    def test_live_api_strings_real_method_names(self):
        p = build_peace_conference_primary_command_product()
        live_map = p.get("live_api_by_step") or LIVE_API_BY_STEP
        self.assertEqual(live_map["open_conference"], "apply_multi_party_peace_board")
        self.assertEqual(live_map["claim_province"], "apply_peace_demand_annex")
        self.assertEqual(
            live_map["cede_province"], "apply_peace_demand_occupation_zone"
        )
        self.assertEqual(live_map["puppet_tag"], "apply_peace_demand_puppet")
        self.assertEqual(live_map["close_conference"], "apply_multi_party_peace_settle")
        blob = " ".join(str(live_map[s]) for s in PRIMARY_COMMAND_STEPS)
        self.assertIn("apply_multi_party_peace_board", blob)
        self.assertIn("apply_peace_demand_annex", blob)
        self.assertIn("apply_peace_demand_occupation_zone", blob)
        self.assertIn("apply_peace_demand_puppet", blob)
        self.assertIn("apply_multi_party_peace_settle", blob)
        for row in p.get("steps") or []:
            self.assertTrue(str(row.get("live_api") or ""), msg=row)
            self.assertEqual(
                str(row.get("live_api")), LIVE_API_BY_STEP[str(row["step"])]
            )
        self.assertIn("apply_multi_party_peace_live", PRIMARY_ACTION_IDS)
        self.assertIn("apply_peace_conference_settlement_live", PRIMARY_ACTION_IDS)
        self.assertIn("apply_multi_party_peace_conference_product", PRIMARY_ACTION_IDS)

        # Verify GameData still hosts these method names (read-only honesty)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)
        for api in (
            "apply_multi_party_peace_live",
            "apply_peace_conference_settlement_live",
            "apply_multi_party_peace_conference_product",
            "apply_multi_party_peace_wargoals",
        ):
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)

    def test_structural_no_apply_focus(self):
        """Human-flow steps must NOT list apply_focus (honest peace leaves)."""
        p = build_peace_conference_primary_command_product()
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
        p = build_peace_conference_primary_command_product(
            province_id=2,
            winners=["GER", "ITA", "HUN"],
            loser_tag="FRA",
            winner_leverage=0.75,
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
            "peace_conference_primary_command_product", p.get("integration") or []
        )
        self.assertIn("Di1", p.get("integration") or [])
        self.assertIn("multi_party_peace_conference_product", p.get("integration") or [])
        self.assertIn("peace_conference_settlement_product", p.get("integration") or [])
        self.assertIn("diplomacy_peace_campaign_product", p.get("integration") or [])
        self.assertIsInstance(p.get("multi_party"), dict)
        self.assertIsInstance(p.get("settlement"), dict)
        self.assertIsInstance(p.get("diplomacy"), dict)
        self.assertFalse(bool((p.get("multi_party") or {}).get("empty")))
        self.assertGreaterEqual(int(p.get("winner_n") or 0), 2)
        self.assertGreaterEqual(int(p.get("package_n") or 0), 2)

    def test_step_apply_and_close(self):
        for step in PRIMARY_COMMAND_STEPS:
            res = apply_peace_conference_primary_command_step(step, province_id=3)
            self.assertTrue(res.get("ok"), msg=res)
            self.assertEqual(res.get("step"), step)
            self.assertTrue(str(res.get("live_api") or ""))
            self.assertEqual(res.get("live_api"), LIVE_API_BY_STEP[step])
        # Aliases resolve
        alias_open = apply_peace_conference_primary_command_step("board", province_id=1)
        self.assertEqual(alias_open.get("step"), "open_conference")
        alias_claim = apply_peace_conference_primary_command_step("annex", province_id=1)
        self.assertEqual(alias_claim.get("step"), "claim_province")
        alias_cede = apply_peace_conference_primary_command_step(
            "occupation_zone", province_id=1
        )
        self.assertEqual(alias_cede.get("step"), "cede_province")
        alias_puppet = apply_peace_conference_primary_command_step(
            "puppet", province_id=1
        )
        self.assertEqual(alias_puppet.get("step"), "puppet_tag")
        alias_close = apply_peace_conference_primary_command_step("settle", province_id=1)
        self.assertEqual(alias_close.get("step"), "close_conference")
        closed = close_peace_conference_primary_command_package(1)
        self.assertTrue(closed.get("ok"), msg=closed)
        self.assertEqual(int(closed.get("applied_n") or 0), len(PRIMARY_COMMAND_STEPS))
        self.assertEqual(int(closed.get("dead_n", 1)), 0)
        self.assertTrue(peace_conference_primary_command_integrity().get("ok"))

    def test_primary_actions_subset_of_live(self):
        for aid in PRIMARY_ACTION_IDS:
            self.assertIn(aid, LIVE_PRIMARY_ACTION_IDS)

    def test_leverage_composes_settlement(self):
        high = build_peace_conference_primary_command_product(winner_leverage=0.9)
        low = build_peace_conference_primary_command_product(winner_leverage=0.2)
        self.assertGreaterEqual(float(high.get("score") or 0), 0.35)
        self.assertGreaterEqual(float(low.get("score") or 0), 0.35)
        settle_high = float((high.get("settlement") or {}).get("score") or 0)
        settle_low = float((low.get("settlement") or {}).get("score") or 0)
        self.assertGreaterEqual(settle_high, settle_low)


if __name__ == "__main__":
    unittest.main(verbosity=2)
