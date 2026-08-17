#!/usr/bin/env python3
"""Gates: multi-day land battle equipment attrition (visible, honest)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_battle_attrition_product import (  # noqa: E402
    LOSER_EVEN,
    MINUS,
    NO_STOCK,
    SEV_MAX,
    SEV_MIN,
    WINNER_LEAN,
    build_land_battle_attrition_product,
    daily_severity,
    format_loss_plain,
    land_battle_attrition_integrity,
)


class TestLandBattleAttritionProduct(unittest.TestCase):
    def test_product_ok(self) -> None:
        p = build_land_battle_attrition_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS", msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        g = land_battle_attrition_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_loser_severity_gt_winner(self) -> None:
        win = daily_severity(is_winner_lean=True, days_elapsed=2)
        lose = daily_severity(is_winner_lean=False, days_elapsed=2)
        self.assertGreater(lose, win)
        self.assertAlmostEqual(win, WINNER_LEAN)
        self.assertAlmostEqual(lose, LOSER_EVEN)

    def test_after_day3_and_clamp(self) -> None:
        win_early = daily_severity(is_winner_lean=True, days_elapsed=3)
        win_late = daily_severity(is_winner_lean=True, days_elapsed=4)
        self.assertGreater(win_late, win_early)
        late = daily_severity(is_winner_lean=False, days_elapsed=40)
        self.assertGreaterEqual(late, SEV_MIN)
        self.assertLessEqual(late, SEV_MAX)

    def test_format_loss_plain_empty_mentions_no_stock(self) -> None:
        self.assertIn("no stock", format_loss_plain({}))
        self.assertEqual(format_loss_plain({}), NO_STOCK)
        self.assertIn("no stock", format_loss_plain(None))

    def test_format_loss_plain_rifles_trucks(self) -> None:
        text = format_loss_plain({"infantry_equipment": 12, "trucks": 2})
        self.assertIn("rifles", text)
        self.assertIn("trucks", text)
        self.assertIn(MINUS, text)
        self.assertIn("12", text)
        self.assertIn("2", text)

    def test_gd_has_three_funcs(self) -> None:
        path = ROOT / "scripts" / "combat" / "LandBattleAttrition.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        self.assertIn("class_name LandBattleAttrition", src)
        self.assertIn("static func daily_severity", src)
        self.assertIn("static func format_loss_plain", src)
        self.assertIn("static func apply_daily_to_formation", src)
        self.assertIn("apply_combat_equipment_loss", src)

    def test_pm_has_ensure_demo_combat_stock(self) -> None:
        path = ROOT / "scripts" / "autoload" / "ProductionManager.gd"
        src = path.read_text(encoding="utf-8")
        self.assertIn("func ensure_demo_combat_stock", src)
        self.assertIn("func apply_combat_equipment_loss", src)


if __name__ == "__main__":
    unittest.main()
