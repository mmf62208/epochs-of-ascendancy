#!/usr/bin/env python3
"""Gates: reinforce an open land battle + combat width."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_battle_reinforce_product import (  # noqa: E402
    build_land_battle_reinforce_product,
    combat_width_for_terrain,
    engaged_power,
    land_battle_reinforce_integrity,
    reinforce_legal,
    unit_width,
)


class TestLandBattleReinforceProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_land_battle_reinforce_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        self.assertTrue(land_battle_reinforce_integrity().get("ok"))

    def test_width_and_stack(self) -> None:
        self.assertGreater(unit_width("armor"), unit_width("infantry"))
        self.assertGreater(
            combat_width_for_terrain("plains"), combat_width_for_terrain("mountain")
        )
        one = engaged_power([100.0], [2.0], 10.0)
        two = engaged_power([100.0, 100.0], [2.0, 2.0], 10.0)
        self.assertGreater(two, one)

    def test_reinforce_legal(self) -> None:
        self.assertEqual(
            reinforce_legal(
                unit_tag="GER",
                att_tag="GER",
                def_tag="FRA",
                pid=1,
                from_id=1,
                to_id=2,
                already_in=False,
            ),
            "attacker",
        )
        self.assertEqual(
            reinforce_legal(
                unit_tag="GER",
                att_tag="GER",
                def_tag="FRA",
                pid=1,
                from_id=1,
                to_id=2,
                already_in=True,
            ),
            "",
        )


if __name__ == "__main__":
    unittest.main()
