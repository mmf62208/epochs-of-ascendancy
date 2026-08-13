#!/usr/bin/env python3
"""Gates: War economy civilian↔war primary command package (E1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from war_economy_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    LIVE_PRIMARY_ACTION_IDS,
    PRIMARY_ACTION_IDS,
    PRIMARY_COMMAND_STEPS,
    SURFACE_KEYS,
    apply_war_economy_primary_command_step,
    build_war_economy_primary_command_product,
    close_war_economy_primary_command_package,
    primary_command_dead_audit,
    war_economy_primary_command_integrity,
)


class TestWarEconomyPrimaryCommand(unittest.TestCase):
    def test_five_surfaces_e1_flow(self):
        self.assertEqual(len(SURFACE_KEYS), 5)
        self.assertEqual(
            list(SURFACE_KEYS),
            [
                "war_economy_primary_board",
                "war_economy_primary_convert_to_war",
                "war_economy_primary_convert_to_civ",
                "war_economy_primary_stockpile_check",
                "war_economy_primary_close",
            ],
        )
        p = build_war_economy_primary_command_product()
        for key in SURFACE_KEYS:
            self.assertIn(key, p.get("majors_ok") or {})
            self.assertTrue((p.get("majors_ok") or {}).get(key), msg="major not ok: %s" % key)
        self.assertEqual(int(p.get("majors_ok_n") or 0), 5)
        self.assertTrue(p.get("all_majors_ok"))

    def test_e1_step_names(self):
        self.assertEqual(
            list(PRIMARY_COMMAND_STEPS),
            [
                "board",
                "convert_to_war",
                "convert_to_civ",
                "stockpile_check",
                "close",
            ],
        )
        p = build_war_economy_primary_command_product()
        self.assertEqual(list(p.get("step_ids") or []), list(PRIMARY_COMMAND_STEPS))
        self.assertEqual(len(p.get("steps") or []), 5)

    def test_dead_n_zero_full_live_set(self):
        audit = primary_command_dead_audit()
        self.assertEqual(int(audit.get("dead_n", 1)), 0)
        self.assertTrue(audit.get("ok"))
        p = build_war_economy_primary_command_product()
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertTrue(p.get("dead_ok"))
        bad = primary_command_dead_audit(
            ["apply_economy_civ_board", "not_a_real_action"]
        )
        self.assertEqual(int(bad.get("dead_n", 0)), 1)
        self.assertFalse(bad.get("ok"))

    def test_live_api_strings_real_method_names(self):
        p = build_war_economy_primary_command_product()
        live_map = p.get("live_api_by_step") or LIVE_API_BY_STEP
        self.assertEqual(live_map["board"], "apply_economy_civ_board")
        self.assertEqual(live_map["convert_to_war"], "apply_economy_war_convert")
        self.assertEqual(live_map["convert_to_civ"], "apply_economy_conversion_live")
        self.assertEqual(live_map["stockpile_check"], "apply_economy_stockpile_sustain")
        self.assertEqual(live_map["close"], "apply_war_economy_conversion_close_day")
        blob = " ".join(str(live_map[s]) for s in PRIMARY_COMMAND_STEPS)
        self.assertIn("apply_economy_civ_board", blob)
        self.assertIn("apply_economy_war_convert", blob)
        self.assertIn("apply_economy_conversion_live", blob)
        self.assertIn("apply_economy_stockpile_sustain", blob)
        self.assertIn("apply_war_economy_conversion_close_day", blob)
        for row in p.get("steps") or []:
            self.assertTrue(str(row.get("live_api") or ""), msg=row)
            self.assertEqual(
                str(row.get("live_api")), LIVE_API_BY_STEP[str(row["step"])]
            )
        self.assertIn("apply_war_economy_conversion_product", PRIMARY_ACTION_IDS)
        self.assertIn("apply_war_economy_mobilization_product", PRIMARY_ACTION_IDS)
        self.assertIn("apply_war_economy_board", PRIMARY_ACTION_IDS)
        self.assertIn("apply_war_economy_allocate", PRIMARY_ACTION_IDS)
        self.assertIn("apply_war_economy_mobilization_close_day", PRIMARY_ACTION_IDS)

        # Verify GameData still hosts these method names (read-only honesty)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)
        for api in (
            "apply_war_economy_conversion_product",
            "apply_war_economy_mobilization_product",
            "apply_war_economy_board",
            "apply_war_economy_allocate",
            "apply_war_economy_sustain",
            "apply_war_economy_mobilization_close_day",
            "apply_economy_civ_board_day",
            "apply_economy_war_convert_day",
            "apply_economy_stockpile_sustain_day",
        ):
            self.assertIn("func %s" % api, gd, msg="missing GameData leaf: %s" % api)

    def test_structural_no_apply_focus(self):
        """E1 steps must NOT list apply_focus (honest conversion leaves)."""
        p = build_war_economy_primary_command_product()
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
        p = build_war_economy_primary_command_product(
            province_id=2,
            factories=16,
            convert_frac=0.32,
            months=4,
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
            "war_economy_primary_command_product", p.get("integration") or []
        )
        self.assertIn("E1", p.get("integration") or [])
        self.assertIn("war_economy_conversion_product", p.get("integration") or [])
        self.assertIn("war_economy_mobilization_product", p.get("integration") or [])
        self.assertIn("civilian_war_conversion", p.get("integration") or [])
        self.assertIn("stockpile_check", p.get("integration") or [])
        self.assertIsInstance(p.get("conversion"), dict)
        self.assertIsInstance(p.get("mobilization"), dict)
        self.assertIsInstance(p.get("board"), dict)
        self.assertFalse(bool((p.get("conversion") or {}).get("empty")))
        self.assertFalse(bool((p.get("mobilization") or {}).get("empty")))
        self.assertGreaterEqual(int(p.get("factories") or 0), 1)
        self.assertGreaterEqual(int(p.get("converted") or 0), 1)
        self.assertGreaterEqual(int(p.get("reconverted") or 0), 1)
        self.assertGreaterEqual(int(p.get("stockpile_delta") or 0), 1)
        self.assertEqual(int(p.get("months") or 0), 4)

    def test_step_apply_and_close(self):
        for step in PRIMARY_COMMAND_STEPS:
            res = apply_war_economy_primary_command_step(step, province_id=3)
            self.assertTrue(res.get("ok"), msg=res)
            self.assertEqual(res.get("step"), step)
            self.assertTrue(str(res.get("live_api") or ""))
            self.assertEqual(res.get("live_api"), LIVE_API_BY_STEP[step])
        # Aliases resolve
        alias = apply_war_economy_primary_command_step("civ_board", province_id=1)
        self.assertEqual(alias.get("step"), "board")
        alias2 = apply_war_economy_primary_command_step("convert", province_id=1)
        self.assertEqual(alias2.get("step"), "convert_to_war")
        alias3 = apply_war_economy_primary_command_step("demobilize", province_id=1)
        self.assertEqual(alias3.get("step"), "convert_to_civ")
        alias4 = apply_war_economy_primary_command_step("stockpile", province_id=1)
        self.assertEqual(alias4.get("step"), "stockpile_check")
        closed = close_war_economy_primary_command_package(1)
        self.assertTrue(closed.get("ok"), msg=closed)
        self.assertEqual(int(closed.get("applied_n") or 0), len(PRIMARY_COMMAND_STEPS))
        self.assertEqual(int(closed.get("dead_n", 1)), 0)
        self.assertTrue(war_economy_primary_command_integrity().get("ok"))

    def test_primary_actions_subset_of_live(self):
        for aid in PRIMARY_ACTION_IDS:
            self.assertIn(aid, LIVE_PRIMARY_ACTION_IDS)

    def test_bidirectional_conversion_and_months(self):
        war_heavy = build_war_economy_primary_command_product(
            factories=20, convert_frac=0.45, months=6
        )
        civ_lean = build_war_economy_primary_command_product(
            factories=10, convert_frac=0.1, months=2
        )
        self.assertGreaterEqual(float(war_heavy.get("score") or 0), 0.35)
        self.assertGreaterEqual(float(civ_lean.get("score") or 0), 0.35)
        # Bidirectional: both war convert and civ reconvert present
        self.assertGreaterEqual(int(war_heavy.get("converted") or 0), 1)
        self.assertGreaterEqual(int(war_heavy.get("reconverted") or 0), 1)
        self.assertEqual(
            str((war_heavy.get("convert_to_war") or {}).get("direction") or ""),
            "civ_to_war",
        )
        self.assertEqual(
            str((war_heavy.get("convert_to_civ") or {}).get("direction") or ""),
            "war_to_civ",
        )
        # Multi-month stockpile parameter accepted
        multi = build_war_economy_primary_command_product(months=12)
        self.assertEqual(int(multi.get("months") or 0), 12)
        self.assertGreaterEqual(float(multi.get("score") or 0), 0.35)
        stock = multi.get("stockpile_check") or {}
        self.assertEqual(int(stock.get("months") or 0), 12)
        self.assertTrue(stock.get("stockpile_ok") or int(stock.get("stockpile_delta") or 0) >= 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
