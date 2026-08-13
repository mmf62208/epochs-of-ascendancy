#!/usr/bin/env python3
"""Spot-check major capital-ish provinces have finite centroids on world_full."""
from __future__ import annotations

import json
import math
import unittest
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"

# Name substrings expected on a world_class board (post name polish).
CAPITAL_KEYS = [
    "Berlin",
    "Paris",
    "London",
    "Tokyo",
    "Washington",
    "Moscow",
    "Beijing",
    "Rome",
    "Madrid",
    "Cairo",
]


def centroid(points: List) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    sx = sum(float(p[0]) for p in points)
    sy = sum(float(p[1]) for p in points)
    n = float(len(points))
    return sx / n, sy / n


class TestCapitalCentroidSpotcheck(unittest.TestCase):
    def test_capitals_resolve_and_have_centroids(self) -> None:
        base = json.loads((WF / "provinces_base.json").read_text())["provinces"]
        geom = {
            int(g["id"]): g
            for g in json.loads((WF / "provinces_geometry.json").read_text())["provinces"]
        }
        found: Dict[str, Tuple[int, float, float]] = {}
        for p in base:
            name = str(p.get("name") or "")
            for key in CAPITAL_KEYS:
                if key.lower() in name.lower() and key not in found:
                    pid = int(p["id"])
                    g = geom.get(pid) or {}
                    pts = g.get("points") or []
                    if g.get("label_anchor") and len(g["label_anchor"]) >= 2:
                        cx, cy = float(g["label_anchor"][0]), float(g["label_anchor"][1])
                    else:
                        cx, cy = centroid(pts)
                    self.assertTrue(math.isfinite(cx) and math.isfinite(cy), msg=name)
                    self.assertGreater(len(pts), 3, msg=name)
                    found[key] = (pid, cx, cy)
        # Require majority of capital keys present on board
        self.assertGreaterEqual(len(found), 7, msg=f"found={list(found)}")
        # Centroids must not all collapse to origin
        nonzero = sum(1 for _, (_, x, y) in found.items() if abs(x) + abs(y) > 1.0)
        self.assertGreaterEqual(nonzero, 7)


if __name__ == "__main__":
    unittest.main(verbosity=2)
