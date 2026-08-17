#!/usr/bin/env python3
"""Gates: fielded-template land combat power (infantry ≠ armor)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_combat_power_product import (  # noqa: E402
    ARMOR_SPEED,
    INFANTRY_SPEED,
    build_land_combat_power_product,
    combat_power,
    land_combat_power_integrity,
    template_kind,
    template_speed,
)


def _form(design_id: str, **kw):
    out = {
        "design_id": design_id,
        "name": design_id,
        "organization": 1.0,
        "strength": 1.0,
        "readiness": 1.0,
    }
    out.update(kw)
    return out


class TestLandCombatPowerProduct(unittest.TestCase):
    def test_product_ok(self) -> None:
        p = build_land_combat_power_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS", msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        g = land_combat_power_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_armor_plains_stronger_than_infantry(self) -> None:
        inf = combat_power(_form("infantry_division"), "plains")
        arm = combat_power(_form("panzer_division", name="1st Panzer"), "plains")
        self.assertGreater(arm, inf)

    def test_armor_mountain_not_greater_than_infantry_or_mtn_inf_higher(self) -> None:
        inf = combat_power(_form("infantry_division"), "mountain")
        arm = combat_power(_form("panzer_division"), "mountain")
        mtn = combat_power(_form("mountain_infantry"), "mountain")
        self.assertTrue(arm <= inf or mtn > arm, msg=(inf, arm, mtn))

    def test_missing_formation_zero(self) -> None:
        self.assertEqual(combat_power(None, "plains"), 0.0)

    def test_kinds_and_speeds(self) -> None:
        self.assertEqual(template_kind(_form("infantry_division")), "infantry")
        self.assertEqual(template_kind(_form("panzer_iii_medium")), "armor")
        self.assertEqual(template_kind(_form("mountain_infantry")), "mountain_infantry")
        self.assertEqual(template_speed(_form("infantry_division")), INFANTRY_SPEED)
        self.assertEqual(template_speed(_form("armor_division")), ARMOR_SPEED)
        self.assertEqual(template_speed(_form("mountain_infantry")), INFANTRY_SPEED)

    def test_gd_helper_file(self) -> None:
        path = ROOT / "scripts" / "combat" / "LandCombatPower.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        self.assertIn("class_name LandCombatPower", src)
        self.assertIn("static func template_kind", src)
        self.assertIn("static func template_speed", src)
        self.assertIn("static func combat_power", src)


if __name__ == "__main__":
    unittest.main()
