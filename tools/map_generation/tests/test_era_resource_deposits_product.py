#!/usr/bin/env python3
"""Era deposits: 1918 vs 1936 vs 2026, harvest→industry, develop-mine."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from era_resource_deposits_product import (  # noqa: E402
    BAKU_OIL,
    apply_develop_resource,
    build_develop_resource_action,
    build_era_resource_industry_product,
    harvest_factory_feeds,
    harvest_nation,
    icon_px_for_amount,
    scale_deposits_for_year,
)


class TestEraResourceDepositsProduct(unittest.TestCase):
    def test_era_amounts_differ(self) -> None:
        a = scale_deposits_for_year(BAKU_OIL, 1918)
        b = scale_deposits_for_year(BAKU_OIL, 1936)
        c = scale_deposits_for_year(BAKU_OIL, 2026)
        self.assertLess(float(a.get("oil", 0)), float(b.get("oil", 0)))
        self.assertLess(float(b.get("oil", 0)), float(c.get("oil", 0)))
        alum = scale_deposits_for_year({"aluminum": 2.0}, 1918)
        self.assertNotIn("aluminum", alum)
        self.assertGreater(icon_px_for_amount(4.0), icon_px_for_amount(1.0))

    def test_harvest_and_develop(self) -> None:
        h36 = harvest_factory_feeds(BAKU_OIL, year=1936, days=30.0)
        self.assertGreater(float(h36.get("oil", 0)), 0.0)
        h18 = harvest_factory_feeds(BAKU_OIL, year=1918, days=30.0)
        self.assertLess(float(h18.get("oil", 0)), float(h36.get("oil", 0)))
        self.assertFalse(
            build_develop_resource_action({"coal": 3}, "oil", year=1936, stockpile={"steel": 40}).get("ok")
        )
        applied = apply_develop_resource(BAKU_OIL, {}, {"steel": 40.0}, "oil", year=1936)
        self.assertTrue(applied.get("ok"), msg=applied)
        h_dev = harvest_factory_feeds(
            BAKU_OIL, year=1936, development=applied.get("development") or {}, days=30.0
        )
        self.assertGreater(float(h_dev.get("oil", 0)), float(h36.get("oil", 0)))
        nation = harvest_nation(
            [{"resources": BAKU_OIL}, {"resources": {"steel": 3.0, "coal": 3.0, "rubber": 2.0}}],
            year=1936,
            days=365.0,
        )
        self.assertGreater(float(nation.get("steel", 0)), 0.0)
        self.assertGreater(float(nation.get("oil", 0)), 0.0)

    def test_integrity_product(self) -> None:
        p = build_era_resource_industry_product()
        self.assertTrue(p.get("ok"), msg=p)


if __name__ == "__main__":
    unittest.main()
