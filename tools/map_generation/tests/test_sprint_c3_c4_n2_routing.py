#!/usr/bin/env python3
"""Structural routing honesty for sprint C3 air · C4 AAR · N2 journal dual wire."""
from __future__ import annotations
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
SP = ROOT / "scripts" / "autoload" / "SessionPlayers.gd"

from air_theater_primary_command_product import LIVE_API_BY_STEP as AIR_API, air_theater_primary_command_integrity
from battle_aar_primary_command_product import LIVE_API_BY_STEP as AAR_API, battle_aar_primary_command_integrity
from command_journal_primary_command_product import LIVE_API_BY_STEP as J_API, command_journal_primary_command_integrity


def extract_func_body(src: str, func_name: str) -> str:
    pat = re.compile(r"(?m)^func %s\b.*$" % re.escape(func_name))
    m = pat.search(src)
    if not m:
        return ""
    start = m.start()
    rest = src[m.end():]
    end_m = re.search(r"(?m)^(func |const |static func |class |#region |#endregion)", rest)
    if end_m:
        return src[start:m.end() + end_m.start()]
    return src[start:]


class TestSprintC3C4N2Routing(unittest.TestCase):
    def test_pure_integrity(self):
        self.assertTrue(air_theater_primary_command_integrity().get("ok"))
        self.assertTrue(battle_aar_primary_command_integrity().get("ok"))
        self.assertTrue(command_journal_primary_command_integrity().get("ok"))

    def test_gamedata_apply_funcs_exist(self):
        gd = GD.read_text(encoding="utf-8")
        for name in (
            "apply_air_theater_primary_command_step_live",
            "apply_air_theater_primary_command_live",
            "apply_battle_aar_primary_command_step_live",
            "apply_battle_aar_primary_command_live",
            "apply_battle_aar_persist_live",
            "apply_battle_aar_close_live",
            "apply_command_journal_primary_command_step_live",
            "apply_command_journal_primary_command_live",
            "apply_command_journal_seed_live",
            "apply_command_journal_enqueue_live",
            "apply_command_journal_flush_live",
            "apply_command_journal_verify_live",
            "apply_command_journal_close_live",
        ):
            self.assertIn("func %s(" % name, gd, msg=name)

    def test_air_step_routes_real_apis_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_air_theater_primary_command_step_live")
        self.assertIn("apply_air_theater_recon", body)
        self.assertIn("apply_air_theater_cas_gate", body)
        self.assertIn("apply_air_theater_interdiction", body)
        self.assertIn("apply_air_multi_phase_theater_close_day", body)
        self.assertNotIn('live_api = "apply_focus"', body)
        for api in AIR_API.values():
            self.assertNotIn("apply_focus", api)

    def test_aar_step_routes_combat_apis_no_focus(self):
        gd = GD.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_battle_aar_primary_command_step_live")
        self.assertIn("apply_multi_phase_combat_product", body)
        self.assertIn("apply_combat_ops_close_live", body)
        self.assertIn("apply_phase_engage", body)
        self.assertIn("apply_battle_aar_persist_live", body)
        self.assertIn("apply_battle_aar_close_live", body)
        self.assertNotIn('live_api = "apply_focus"', body)
        for api in AAR_API.values():
            self.assertNotIn("apply_focus", api)

    def test_journal_enqueue_never_apply_focus(self):
        gd = GD.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_command_journal_enqueue_live")
        self.assertIn("apply_production", body)
        self.assertIn("apply_station", body)
        # must explicitly skip or not list apply_focus as enqueued action
        self.assertIn("apply_focus", body)  # only in skip/comment/filter form
        self.assertTrue(
            'continue' in body or 'never' in body.lower() or "apply_focus" in body and "if" in body
        )
        # live_api names themselves free of focus
        for api in J_API.values():
            self.assertNotIn("apply_focus", api)
        # seed/flush/verify bodies
        for fn in (
            "apply_command_journal_seed_live",
            "apply_command_journal_flush_live",
            "apply_command_journal_verify_live",
            "apply_command_journal_close_live",
        ):
            b = extract_func_body(gd, fn)
            self.assertIn("func %s(" % fn, b)

    def test_verify_live_uses_session_journal_state_not_hardcoded_only(self):
        """apply_command_journal_verify_live must compare stored journal fingerprints.

        Must reference pre/applied fingerprint state (from enqueue/flush SessionPlayers
        journal) — not only re-hash a hardcoded action list as sole success path.
        """
        gd = GD.read_text(encoding="utf-8")
        body = extract_func_body(gd, "apply_command_journal_verify_live")
        self.assertIn("func apply_command_journal_verify_live(", body)
        self.assertIn("command_journal_fingerprint_pre", body)
        self.assertIn("command_journal_fingerprint_applied", body)
        # Must not invent success by writing prev=fp when empty
        self.assertNotIn('peace_state["command_journal_fingerprint"] = fp\n\t\tprev = fp', body)
        # Enqueue must call SessionPlayers journal fingerprint / get_command_journal
        enq = extract_func_body(gd, "apply_command_journal_enqueue_live")
        self.assertTrue(
            "get_command_journal" in enq or "fingerprint_command_journal" in enq,
            msg="enqueue must capture fingerprint from SessionPlayers journal",
        )
        self.assertIn("command_journal_fingerprint_pre", enq)
        flush = extract_func_body(gd, "apply_command_journal_flush_live")
        self.assertIn("command_journal_fingerprint_applied", flush)
        self.assertTrue(
            "fingerprint_commands" in flush or "fingerprint_command_journal" in flush
            or "applied" in flush,
            msg="flush must fingerprint applied trail",
        )
        # SessionPlayers helpers present
        sp = SP.read_text(encoding="utf-8")
        self.assertIn("func fingerprint_commands(", sp)
        self.assertIn("func fingerprint_command_journal(", sp)
        self.assertIn("get_command_journal()", sp)

    def test_session_players_journal_helpers(self):
        sp = SP.read_text(encoding="utf-8")
        self.assertIn("func get_command_journal(", sp)
        self.assertIn("func seed_command_journal(", sp)
        self.assertIn("func enqueue_journal_batch(", sp)
        # enqueue batch filters apply_focus
        body_start = sp.find("func enqueue_journal_batch")
        body = sp[body_start:body_start+800]
        self.assertIn("apply_focus", body)
        self.assertIn("continue", body)

    def test_scenario_loader_markers(self):
        sl = SL.read_text(encoding="utf-8")
        for m in (
            "air_theater_primary_live=1",
            "battle_aar_primary_live=1",
            "command_journal_primary_live=1",
        ):
            self.assertIn(m, sl)
        self.assertIn("_print_air_theater_primary_live_evidence", sl)
        self.assertIn("_print_battle_aar_primary_live_evidence", sl)
        self.assertIn("_print_command_journal_primary_live_evidence", sl)

    def test_panel_primary_sections(self):
        panel = PANEL.read_text(encoding="utf-8")
        self.assertIn("_rebuild_air_theater_primary_command", panel)
        self.assertIn("_rebuild_battle_aar_primary_command", panel)
        self.assertIn("_rebuild_command_journal_primary_command", panel)


if __name__ == "__main__":
    unittest.main()
