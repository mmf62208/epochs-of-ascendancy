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
    lines_for,
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
            "gd_strip",
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
        self.assertEqual(lines_for({"strength": 1.0}), ["XP Regular", "Strength 100%"])
        self.assertEqual(
            lines_for({"combat_experience": 12.0, "planning": 0.5, "strength": 0.4}),
            ["XP Green", "Planning 50%", "Strength 40%"],
        )
        self.assertEqual(
            lines_for(
                {
                    "combat_experience": 72.0,
                    "entrenchment": 80.0,
                    "last_equip_loss_plain": "",
                    "strength": 1.0,
                }
            ),
            ["XP Seasoned", "Entrenchment 80%", "Strength 100%"],
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

    def test_gd_greps(self) -> None:
        path = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        self.assertIn("class_name UnitCardCombatStrip", src)
        self.assertIn("func lines_for", src)
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
