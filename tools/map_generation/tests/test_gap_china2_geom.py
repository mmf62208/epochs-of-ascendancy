#!/usr/bin/env python3
"""GAP-CHINA-2 outlines stay simple, and the China play gaps stay closed.

Fails when any of 906111–906138 crosses itself or overlaps another land
province by more than 1 px² (even-odd). Also fails the 908fee18 play gaps
and the 1bf83066 residuals: a CHI×CHI nonzero overlap over 1 px², an
enclosed China hole over 500 px², or a hairline sliver between neighbouring
CHI provinces. Coarse sea overlaps are not counted.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gap_china2_outline import NEW_HI, NEW_LO, audit_outlines, audit_play_gaps  # noqa: E402

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

    def test_play_gaps_closed_and_labels_are_wide(self) -> None:
        geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
        base = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))
        domains = {int(p["id"]): p.get("domain") for p in base["provinces"]}
        problems = audit_play_gaps(geo["provinces"], domains)
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
