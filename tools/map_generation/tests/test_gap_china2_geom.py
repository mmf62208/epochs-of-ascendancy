#!/usr/bin/env python3
"""GAP-CHINA-2 outlines 906111–906138 stay simple and off their land neighbours.

Fails when any of those rings crosses itself, or overlaps another land
province by more than 1 px². Sea zones are coarse and are not checked here.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gap_china2_outline import NEW_HI, NEW_LO, audit_outlines  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"


class GapChina2GeomTest(unittest.TestCase):
    def test_new_outlines_are_simple_and_do_not_overlap_land(self) -> None:
        geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
        base = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))
        domains = {int(p["id"]): p.get("domain") for p in base["provinces"]}
        ids = {int(g["id"]) for g in geo["provinces"]}
        self.assertTrue(set(range(NEW_LO, NEW_HI + 1)) <= ids)
        problems = audit_outlines(geo["provinces"], domains)
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
