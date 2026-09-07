#!/usr/bin/env python3
"""Gates: docked unit-card combat strip + cheap bubble CAS/P chips."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from unit_card_combat_strip_product import (  # noqa: E402
    bbcode_for,
    build_unit_card_combat_strip_product,
    day_label_extras,
    fill_toe_fold_line,
    lines_for,
    tooltip_lines_for,
    unit_card_combat_strip_integrity,
    xp_band,
)


class TestUnitCardCombatStripProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_unit_card_combat_strip_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        wiring = p.get("wiring") or {}
        for key in (
            "default_xp_strength",
            "xp_bands",
            "full_strip",
            "null_empty",
            "day_label_extras",
            "stockpile_toe_line",
            "fold_fill_toe_before_stats",
            "tooltip_speed_width",
            "gd_strip",
            "gd_stockpile_toe",
            "gd_fold_fill_toe_tooltip_stats",
            "gd_bubble_cas_p",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))

    def test_integrity(self) -> None:
        g = unit_card_combat_strip_integrity(check_wiring=True)
        self.assertTrue(g.get("ok"), msg=g)

    def test_xp_bands(self) -> None:
        self.assertEqual(xp_band(0.0), "Green")
        self.assertEqual(xp_band(20.0), "Green")
        self.assertEqual(xp_band(21.0), "Trained")
        self.assertEqual(xp_band(40.0), "Trained")
        self.assertEqual(xp_band(41.0), "Regular")
        self.assertEqual(xp_band(60.0), "Regular")
        self.assertEqual(xp_band(61.0), "Seasoned")
        self.assertEqual(xp_band(80.0), "Seasoned")
        self.assertEqual(xp_band(81.0), "Veteran")
        self.assertEqual(xp_band(100.0), "Veteran")

    def test_lines_for_optional_keys(self) -> None:
        self.assertEqual(lines_for(None), [])
        self.assertEqual(
            lines_for({"strength": 1.0}),
            ["Fill 100%", "XP Regular", "Strength 100%"],
        )
        self.assertEqual(
            lines_for({"combat_experience": 12.0, "planning": 0.5, "strength": 0.4}),
            ["Fill 40%", "XP Green", "Planning 50%", "Strength 40%"],
        )
        self.assertIn("Planning", "\n".join(lines_for({"planning": 0.1})))
        self.assertIn(
            "Training 3/14d",
            "\n".join(
                lines_for(
                    {
                        "is_training": True,
                        "training_progress": 3,
                        "organize_days": 14,
                        "strength": 0.5,
                    }
                )
            ),
        )

    def test_bbcode_and_extras(self) -> None:
        bb = bbcode_for({"combat_experience": 90.0, "strength": 1.0})
        self.assertIn("XP Veteran", bb)
        self.assertIn("Strength 100%", bb)
        self.assertEqual(day_label_extras({"cas_att": 2.0}), "CAS")
        self.assertEqual(day_label_extras({"cas_def": 0.1, "planning_used": True}), "CAS P")
        self.assertEqual(day_label_extras({"planning_used": False}), "")

    def test_fold_promotes_fill_and_toe(self) -> None:
        land = {
            "strength": 1.0,
            "toe_fill": 0.80,
            "equipment": {"infantry_equipment": 80, "tanks": 12},
            "speed": 4.0,
            "armor": 0.12,
            "manpower": 10000,
            "width": 9.0,
            "fuel_level": 0.7,
        }
        fold = lines_for(land)
        text = "\n".join(fold)
        self.assertIn("Fill 80%", text)
        self.assertIn("TOE", text)
        self.assertIn("infantry 80", text)
        self.assertIn("tanks 12", text)
        self.assertTrue(
            text.find("Fill") <= text.find("TOE"),
            msg=text,
        )
        self.assertNotIn("Speed", text)
        self.assertNotIn("Width", text)
        self.assertEqual(
            fill_toe_fold_line(land),
            "Fill 80% · TOE infantry 80 · tanks 12",
        )
        tips = tooltip_lines_for(land)
        tip_text = "\n".join(tips)
        self.assertIn("Speed 4.0", tip_text)
        self.assertIn("Width", tip_text)
        self.assertIn("Fuel", tip_text)
        self.assertIn("Armor", tip_text)

    def test_gd_greps(self) -> None:
        path = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        self.assertIn("class_name UnitCardCombatStrip", src)
        self.assertIn("func lines_for", src)
        self.assertIn("func tooltip_lines_for", src)
        self.assertIn("_fill_toe_fold_line", src)
        self.assertIn("Fill %.0f%%", src)
        self.assertIn("combat_experience", src)
        self.assertTrue(
            "last_equip_loss_plain" in src or "Planning" in src,
            msg="need last_equip_loss_plain or Planning",
        )
        bubble = (ROOT / "scripts" / "map" / "LandBattleBubbleLayer.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn("CAS", bubble)
        self.assertIn("planning_used", bubble)


if __name__ == "__main__":
    unittest.main()
