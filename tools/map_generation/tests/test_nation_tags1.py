#!/usr/bin/env python3
"""NATION-TAGS-1: UKR/MDA/PRC/MAN resolve, 1945 Poland owns cc=PL, gap provinces exist.

Fails on a board that still has no catalog, no 1945 Poland, and no 905849–905869.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from nation_tags1_product import ERA_YEARS, GAPS, NEW_TAGS, audit  # noqa: E402


class TestNationTags1(unittest.TestCase):
    def test_1936_column_is_not_a_new_tag(self) -> None:
        idx = ERA_YEARS.index(1936)
        for spec in GAPS:
            self.assertNotIn(spec.owners[idx], NEW_TAGS, spec.pid)

    def test_board_has_tags_poland_1945_and_gap_provinces(self) -> None:
        report = audit()
        self.assertTrue(report["ok"], "\n".join(report["failures"]))


if __name__ == "__main__":
    unittest.main()
