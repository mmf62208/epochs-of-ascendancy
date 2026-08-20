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
    LEADER_BONUS_CAP,
    LEADER_DEFEND_ATTACK_SCALE,
    absorb_mult,
    build_land_combat_power_product,
    combat_power,
    hardness_mix,
    land_combat_power_integrity,
    leader_power_mult,
    template_kind,
    template_speed,
    xp_power_mult,
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

    def test_no_leader_mult_is_one(self) -> None:
        self.assertAlmostEqual(leader_power_mult(_form("infantry_division")), 1.0)

    def test_attack_0_2_is_about_1_2(self) -> None:
        self.assertAlmostEqual(
            leader_power_mult(_form("infantry_division", attack_modifier=0.2)),
            1.2,
            places=5,
        )

    def test_leader_bonus_clamps_at_1_25(self) -> None:
        self.assertAlmostEqual(
            leader_power_mult(_form("infantry_division", attack_modifier=0.5)),
            1.0 + LEADER_BONUS_CAP,
        )
        self.assertAlmostEqual(
            leader_power_mult(_form("infantry_division", leader={"attack": 0.9})),
            1.25,
        )

    def test_defender_uses_defense_else_attack_scaled(self) -> None:
        self.assertAlmostEqual(
            leader_power_mult(
                _form("infantry_division", attack_modifier=0.2, defense_modifier=0.1),
                "plains",
                "defend",
            ),
            1.1,
        )
        self.assertAlmostEqual(
            leader_power_mult(
                _form("infantry_division", attack_modifier=0.2),
                "plains",
                "defend",
            ),
            1.0 + 0.2 * LEADER_DEFEND_ATTACK_SCALE,
        )

    def test_hardness_and_breakthrough(self) -> None:
        self.assertGreater(hardness_mix(3.0, 0.3, 0.0), hardness_mix(3.0, 0.3, 0.80))
        self.assertGreater(absorb_mult("attack", 3.0, 1.0), absorb_mult("attack", 0.4, 1.0))
        self.assertGreater(absorb_mult("defend", 0.4, 3.0), absorb_mult("attack", 0.4, 3.0))
        inf = _form(
            "infantry_kit",
            soft=3.0,
            hard=0.3,
            breakthrough=0.4,
            defense=3.0,
            hardness=0.0,
        )
        vs_soft = combat_power(inf, "plains", "attack", {"hardness": 0.0, "armor": 0.0})
        vs_hard = combat_power(inf, "plains", "attack", {"hardness": 0.80, "armor": 0.70})
        self.assertGreater(vs_soft, vs_hard)
        self.assertNotEqual(
            combat_power(inf, "plains", "attack"),
            combat_power(inf, "plains", "defend"),
        )

    def test_combat_power_multiplies_leader(self) -> None:
        base = combat_power(_form("infantry_division"), "plains")
        led = combat_power(_form("infantry_division", attack_modifier=0.2), "plains")
        self.assertAlmostEqual(led, base * 1.2)

    def test_gd_helper_file(self) -> None:
        path = ROOT / "scripts" / "combat" / "LandCombatPower.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        self.assertIn("class_name LandCombatPower", src)
        self.assertIn("static func template_kind", src)
        self.assertIn("static func template_speed", src)
        self.assertIn("static func combat_power", src)
        self.assertIn("static func leader_power_mult", src)
        self.assertIn("LEADER_BONUS_CAP", src)
        self.assertIn("get_attack_modifier", src)
        self.assertIn("get_defense_modifier", src)
        form = ROOT / "scripts" / "formations" / "Formation.gd"
        self.assertTrue(form.is_file())
        fsrc = form.read_text(encoding="utf-8")
        self.assertIn("assigned_leader_id", fsrc)
        self.assertIn("assigned_leader", fsrc)


if __name__ == "__main__":
    unittest.main()
