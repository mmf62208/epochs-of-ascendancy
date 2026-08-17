#!/usr/bin/env python3
"""Gates: Press/Hold stance + tomorrow hook."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_battle_stance_product import (  # noqa: E402
    build_land_battle_stance_product,
    days_to_break,
    land_battle_stance_integrity,
    next_hook,
    stance_org_delta,
    stance_power_mult,
)


class TestLandBattleStanceProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_land_battle_stance_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)

    def test_integrity(self) -> None:
        self.assertTrue(land_battle_stance_integrity().get("ok"))

    def test_stance_math(self) -> None:
        self.assertGreater(stance_power_mult("press"), stance_power_mult("hold"))
        self.assertGreater(stance_org_delta("press"), 0.0)
        self.assertLess(stance_org_delta("hold"), 0.0)
        self.assertEqual(days_to_break(0.40, 0.20), 1)
        self.assertIn("tomorrow", next_hook(days_left=1, march_eta=9, ground_hard=False, stance="press").lower())


if __name__ == "__main__":
    unittest.main()
