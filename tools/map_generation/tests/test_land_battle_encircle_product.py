#!/usr/bin/env python3
"""Gates: encirclement / pocket supply for land battles."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_battle_encircle_product import (  # noqa: E402
    SUPPLY_CONNECTED,
    SUPPLY_POCKET,
    SUPPLY_THIN,
    build_land_battle_encircle_product,
    land_battle_encircle_integrity,
    org_drain_extra,
    supply_state,
)


class TestLandBattleEncircleProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_land_battle_encircle_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        self.assertTrue(land_battle_encircle_integrity().get("ok"))

    def test_states(self) -> None:
        adj = {1: [2], 2: [1, 4], 3: [4], 4: [2, 3]}
        owner = {1: "GER", 2: "GER", 3: "GER", 4: "FRA"}
        self.assertEqual(
            supply_state(pid=1, tag="GER", capital=1, adj=adj, owner=owner)["supply"],
            SUPPLY_CONNECTED,
        )
        self.assertEqual(
            supply_state(pid=2, tag="GER", capital=1, adj=adj, owner=owner)["kind"],
            "thin",
        )
        pk = supply_state(pid=3, tag="GER", capital=1, adj=adj, owner=owner)
        self.assertTrue(pk["pocket"])
        self.assertEqual(pk["supply"], SUPPLY_POCKET)
        self.assertGreater(org_drain_extra("pocket"), org_drain_extra("encircled"))
        self.assertEqual(org_drain_extra("connected"), 0.0)
        self.assertEqual(SUPPLY_THIN, 0.75)


if __name__ == "__main__":
    unittest.main()
