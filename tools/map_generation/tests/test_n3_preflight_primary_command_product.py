#!/usr/bin/env python3
"""Routing + honesty gate for N3 preflight (not full netcode)."""
from __future__ import annotations
import re
import unittest
import sys
from pathlib import Path

LIB = Path(__file__).resolve().parents[1] / "lib"
PROJECT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(LIB))

from n3_preflight_primary_command_product import (  # noqa: E402
    LIVE_API_BY_STEP,
    PRIMARY_COMMAND_STEPS,
    build_n3_preflight_primary_command_product,
    apply_n3_preflight_primary_command_step,
)


def body(src: str, name: str) -> str:
    m = re.search(
        r"func %s\b.*?(?=\nfunc |\nconst |\n#region|\n#endregion|\Z)" % re.escape(name),
        src,
        re.S,
    )
    return m.group(0) if m else ""


class TestN3PreflightHonesty(unittest.TestCase):
    def test_build_order_seed_enqueue_flush_verify(self):
        p = build_n3_preflight_primary_command_product()
        self.assertEqual(int(p["majors_ok_n"]), 5)
        self.assertEqual(int(p["dead_n"]), 0)
        self.assertTrue(p.get("not_full_n3"))
        self.assertFalse(p.get("netcode_ready"))
        steps = list(PRIMARY_COMMAND_STEPS)
        self.assertEqual(steps, ["n3p_lobby", "n3p_seed", "n3p_enqueue", "n3p_flush", "n3p_verify"])
        self.assertEqual(LIVE_API_BY_STEP["n3p_seed"], "apply_command_journal_seed_live")
        self.assertEqual(LIVE_API_BY_STEP["n3p_enqueue"], "apply_command_journal_enqueue_live")
        self.assertEqual(LIVE_API_BY_STEP["n3p_flush"], "apply_command_journal_flush_live")
        self.assertEqual(LIVE_API_BY_STEP["n3p_verify"], "apply_command_journal_verify_live")
        # verify must come after flush
        self.assertLess(steps.index("n3p_flush"), steps.index("n3p_verify"))
        self.assertLess(steps.index("n3p_enqueue"), steps.index("n3p_flush"))
        self.assertTrue(p.get("requires_seed_enqueue_flush_verify"))

    def test_gamedata_compose_and_live_result_ok_gating(self):
        gd = (PROJECT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
        for api in LIVE_API_BY_STEP.values():
            self.assertIn("func %s" % api, gd, api)
        step_b = body(gd, "apply_n3_preflight_primary_step_live")
        self.assertIn("apply_command_journal_enqueue_live", step_b)
        self.assertIn("apply_command_journal_flush_live", step_b)
        self.assertIn("apply_command_journal_verify_live", step_b)
        # majors only when leaf ok
        self.assertIn("step_ok", step_b)
        self.assertIn("major_credit", step_b)
        live_b = body(gd, "apply_n3_preflight_primary_live")
        self.assertIn("failed_n", live_b)
        self.assertIn("step_ok", live_b)
        self.assertIn("n3p_primary_enqueue", live_b)
        self.assertIn("n3p_primary_flush", live_b)
        self.assertIn("n3p_primary_verify", live_b)
        # no credit without live_result ok
        self.assertIn('major_credit := major if step_ok else ""', step_b)
        domain = (PROJECT / "scripts/core/N3PreflightDomain.gd").read_text(encoding="utf-8")
        self.assertIn("n3p_primary_enqueue", domain)
        self.assertIn("n3p_primary_flush", domain)
        sl = (PROJECT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("n3_preflight_primary_live=1", sl)
        self.assertIn("netcode_ready=false", sl)

    def test_steps(self):
        for s in PRIMARY_COMMAND_STEPS:
            self.assertTrue(apply_n3_preflight_primary_command_step(s)["ok"])


if __name__ == "__main__":
    unittest.main()
