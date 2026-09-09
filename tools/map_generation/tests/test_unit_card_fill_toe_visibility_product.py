#!/usr/bin/env python3
"""Gates: first-session unit card promotes Fill%/TOE above the clip fold."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_card_combat_strip_product import (  # noqa: E402
    fill_toe_fold_line,
    lines_for,
    tooltip_lines_for,
)
from unit_card_fill_toe_visibility_product import (  # noqa: E402
    build_unit_card_fill_toe_visibility_product,
    fill_fold_color_token,
    unit_card_fill_toe_visibility_integrity,
)

RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
STRIP = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"


class TestUnitCardFillToeVisibilityProduct(unittest.TestCase):
    def test_fill_color_threshold(self) -> None:
        self.assertEqual(fill_fold_color_token(0.5), "SUCCESS")
        self.assertEqual(fill_fold_color_token(0.8), "SUCCESS")
        self.assertEqual(fill_fold_color_token(0.49), "WARNING")
        self.assertEqual(fill_fold_color_token(0.0), "WARNING")

    def test_product_ok(self) -> None:
        p = build_unit_card_fill_toe_visibility_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS")
        wiring = p.get("wiring") or {}
        for key in (
            "fill_color_threshold",
            "promoted_fill_label_before_body",
            "fill_font_15_or_16",
            "fill_warning_success_color",
            "clip_false_or_min_height_360",
            "speed_armor_men_tooltip_not_body",
            "combat_log_not_card_body",
            "fold_fill_toe_first",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))

    def test_integrity(self) -> None:
        g = unit_card_fill_toe_visibility_integrity(check_wiring=True)
        self.assertTrue(g.get("ok"), msg=g)

    def test_fold_order_not_regressed(self) -> None:
        land = {
            "strength": 1.0,
            "toe_fill": 0.80,
            "equipment": {"infantry_equipment": 80, "tanks": 12},
            "speed": 4.0,
            "armor": 0.12,
            "manpower": 10000,
            "width": 9.0,
            "fuel_level": 0.7,
            "combat_log": [
                {"date": "1936-01", "outcome": "skirmish"},
                {"date": "1936-02", "result": "hold"},
                {"date": "1936-03", "outcome": "advance"},
            ],
        }
        fold = lines_for(land)
        text = "\n".join(fold)
        self.assertTrue(fold and fold[0].startswith("Fill"), msg=fold)
        self.assertIn("Fill 80%", text)
        self.assertIn("TOE", text)
        self.assertNotIn("Speed", text)
        self.assertNotIn("1936-01", text)
        self.assertNotIn("1936-03", text)
        self.assertEqual(
            fill_toe_fold_line(land),
            "Fill 80% · TOE infantry 80 · tanks 12",
        )
        tips = tooltip_lines_for(land)
        tip_text = "\n".join(tips)
        self.assertIn("Speed 4.0", tip_text)
        self.assertIn("Armor", tip_text)
        self.assertIn("1936-03", tip_text)

    def test_renderer_source_lock(self) -> None:
        src = RENDERER.read_text(encoding="utf-8")
        self.assertIn("func _show_unit_detail_popup", src)
        self.assertIn("fill_lbl", src)
        self.assertIn("font_size", src)
        self.assertIn("RetrowaveTheme.WARNING", src)
        strip = STRIP.read_text(encoding="utf-8")
        self.assertIn("_fill_toe_fold_line", strip)
        self.assertIn("_fill_ratio_for", strip)
        self.assertIn("func tooltip_lines_for", strip)


if __name__ == "__main__":
    unittest.main()
