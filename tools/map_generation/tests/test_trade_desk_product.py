"""Pure tests: auto interdict math, tariff skim, Trade Desk board shape, live hooks."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from trade_desk_product import (  # noqa: E402
    apply_tariff_skim,
    build_trade_desk_primary_command_product,
    desk_board_shape,
    monthly_hit_chance,
    monthly_loss_fraction,
    pick_interdict_cause,
    primary_command_dead_audit,
)


class TestTradeDesk(unittest.TestCase):
    def test_monthly_interdict_math(self):
        self.assertAlmostEqual(monthly_hit_chance(0.0), 0.02)
        self.assertAlmostEqual(monthly_hit_chance(1.0), 0.45)
        self.assertGreater(monthly_hit_chance(0.4), 0.15)
        loss = monthly_loss_fraction(0.5, 0.6)
        self.assertGreaterEqual(loss, 0.08)
        self.assertLessEqual(loss, 0.65)
        self.assertEqual(pick_interdict_cause(0.4, 0.3), "submarine")
        self.assertEqual(pick_interdict_cause(0.1, 0.8), "surface_raider")

    def test_tariff_skim(self):
        t = apply_tariff_skim(100.0, import_tariff=0.25)
        self.assertAlmostEqual(t["net_amount"], 75.0)
        self.assertAlmostEqual(t["skimmed"], 25.0)
        free = apply_tariff_skim(80.0, import_tariff=0.0)
        self.assertAlmostEqual(free["net_amount"], 80.0)
        # Subsidy halves effective tariff
        sub = apply_tariff_skim(100.0, import_tariff=0.25, import_subsidy=0.2)
        self.assertAlmostEqual(sub["tariff_rate"], 0.15)
        emb = apply_tariff_skim(50.0, embargo=True)
        self.assertEqual(emb["net_amount"], 0.0)

    def test_desk_board_shape(self):
        b = desk_board_shape(delivery_pct=40, import_tariff=0.3, power_label="outmatched")
        self.assertEqual(b["model"], "strategic_compact_ledger")
        self.assertEqual(b["desk_version"], 1)
        self.assertGreaterEqual(b["warning_n"], 1)
        self.assertIn("policy", b)
        self.assertIn("transit_plain", b)

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_trade_desk_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        self.assertTrue(p["interdict_ok"])
        self.assertTrue(p["tariff_ok"])
        self.assertTrue(p["desk_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_trade_desk_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("trade_desk_primary_live=1", sl)
        tm = (ROOT / "scripts" / "national" / "TradeManager.gd").read_text(encoding="utf-8")
        self.assertIn("func process_monthly_trade_risks", tm)
        self.assertIn("func build_trade_desk_board", tm)
        self.assertIn("func _apply_import_tariff_skim", tm)
        ui = (ROOT / "scripts" / "ui" / "TradeMarketView.gd").read_text(encoding="utf-8")
        self.assertIn("_refresh_trade_desk", ui)
        self.assertIn("build_trade_desk_board", ui)


if __name__ == "__main__":
    unittest.main()
