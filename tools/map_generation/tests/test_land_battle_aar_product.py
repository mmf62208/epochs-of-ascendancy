#!/usr/bin/env python3
"""Gates: after-action line + next-hex offer."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_battle_aar_product import (  # noqa: E402
    build_land_battle_aar_product,
    format_line,
)


class TestLandBattleAarProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_land_battle_aar_product()
        self.assertTrue(p.get("ok"), msg=p)

    def test_format(self) -> None:
        s = format_line("attacker", "Bas-Rhin", 3, "rifles −14", "Haguenau")
        self.assertIn("Took Bas-Rhin", s)
        self.assertIn("Press Haguenau", s)


if __name__ == "__main__":
    unittest.main()
