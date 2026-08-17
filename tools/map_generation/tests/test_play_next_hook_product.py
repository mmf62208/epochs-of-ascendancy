#!/usr/bin/env python3
"""Gates: play-strip / map Next hook."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from play_next_hook_product import (  # noqa: E402
    build_play_next_hook_product,
    recommend_from_hook,
)


class TestPlayNextHookProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_play_next_hook_product()
        self.assertTrue(p.get("ok"), msg=p)

    def test_recommend_from_hook(self) -> None:
        self.assertEqual(recommend_from_hook("Reinforcement arrives tomorrow"), "hold")
        self.assertEqual(recommend_from_hook("They break tomorrow"), "press")


if __name__ == "__main__":
    unittest.main()
