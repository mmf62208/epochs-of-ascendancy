"""Pure tests: basing graph grant/query/expire + docking SUU + live hooks."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from trade_basing_product import (  # noqa: E402
    basing_board,
    build_trade_basing_primary_command_product,
    docking_suu,
    grant_to_graph,
    has_basing_access,
    make_basing_edge,
    primary_command_dead_audit,
    tick_basing_graph,
)


class TestTradeBasing(unittest.TestCase):
    def test_docking_suu_major_premium(self):
        major = docking_suu(12, True)
        minor = docking_suu(12, False)
        self.assertGreater(major, minor)
        self.assertGreater(major, 100.0)

    def test_grant_and_query(self):
        e = make_basing_edge("ENG", "GER", 42, 18, True)
        g = grant_to_graph({}, e)
        self.assertTrue(has_basing_access(g, "GER", "ENG", 42))
        self.assertTrue(has_basing_access(g, "GER", "ENG"))
        self.assertFalse(has_basing_access(g, "FRA", "ENG", 42))
        self.assertFalse(has_basing_access(g, "GER", "ENG", 99))  # different province, host-wide=0 only

    def test_host_wide_province_zero(self):
        e = make_basing_edge("USA", "ITA", 0, 6, False)
        g = grant_to_graph({}, e)
        self.assertTrue(has_basing_access(g, "ITA", "USA", 123))

    def test_expire(self):
        e = make_basing_edge("ENG", "GER", 7, 3, True)
        g = grant_to_graph({}, e)
        t = tick_basing_graph(g, 3)
        self.assertGreaterEqual(t["expired"], 1)
        self.assertFalse(has_basing_access(t["graph"], "GER", "ENG", 7))
        b = basing_board(g, "GER")
        self.assertGreaterEqual(b["active_n"], 1)

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_trade_basing_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_trade_basing_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("trade_basing_primary_live=1", sl)
        tm = (ROOT / "scripts" / "national" / "TradeManager.gd").read_text(encoding="utf-8")
        self.assertIn("func grant_basing_rights", tm)
        self.assertIn("func has_basing_access", tm)
        self.assertIn("_write_basing_graph_for_accepted_offer", tm)


if __name__ == "__main__":
    unittest.main()
