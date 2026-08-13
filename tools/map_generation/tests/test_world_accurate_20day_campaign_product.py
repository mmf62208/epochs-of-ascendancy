#!/usr/bin/env python3
"""Director D2.4 machine proxy — 20-day campaign on world_accurate."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from world_accurate_20day_campaign_product import (  # noqa: E402
    build_world_accurate_20day_campaign_product,
    world_accurate_20day_campaign_integrity,
)

D = ROOT / "data" / "provinces_world_accurate"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestWorldAccurate20DayCampaign(unittest.TestCase):
    def test_20day_product_pass(self) -> None:
        p = build_world_accurate_20day_campaign_product(days=20, player_tag="GER")
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        self.assertEqual(int(p.get("days") or 0), 20)
        self.assertGreaterEqual(int(p.get("ai_ok_days") or 0), 16)
        self.assertTrue(p.get("ger_fra_edge"))
        self.assertGreaterEqual(float(p.get("land_shared_coverage") or 0), 0.95)
        self.assertEqual(len(p.get("day_rows") or []), 20)

    def test_short_roll_5d(self) -> None:
        p = build_world_accurate_20day_campaign_product(days=5, player_tag="FRA", province_id=710707)
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        self.assertEqual(int(p.get("days") or 0), 5)

    def test_integrity(self) -> None:
        g = world_accurate_20day_campaign_integrity()
        self.assertTrue(g.get("ok"), msg=g)


if __name__ == "__main__":
    unittest.main()
