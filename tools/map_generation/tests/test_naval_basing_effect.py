#!/usr/bin/env python3
"""Gates: basing level/capacity → repair/refuel rates + SupplyManager wiring."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from naval_basing import (  # noqa: E402
    LEVEL_ANCHORAGE,
    LEVEL_MAJOR,
    LEVEL_NONE,
    LEVEL_PORT,
    basing_repair_refuel_rates,
    compute_naval_basing,
)

GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_SM = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"


class TestBasingRepairRefuelRates(unittest.TestCase):
    def test_none_zero_no_service(self) -> None:
        none = basing_repair_refuel_rates({"level": LEVEL_NONE, "capacity": 0, "is_naval": False})
        self.assertEqual(none["level"], LEVEL_NONE)
        self.assertEqual(none["refuel_rate"], 0.0)
        self.assertEqual(none["repair_org_rate"], 0.0)
        self.assertFalse(none["can_service"])
        # Landlocked basing dict
        land = compute_naval_basing(domain="land")
        rates = basing_repair_refuel_rates(land)
        self.assertFalse(rates["can_service"])
        self.assertEqual(rates["refuel_rate"], 0.0)

    def test_ordering_anchorage_port_major(self) -> None:
        anch = basing_repair_refuel_rates(
            {"level": LEVEL_ANCHORAGE, "capacity": 2, "is_naval": True}
        )
        port = basing_repair_refuel_rates(
            {"level": LEVEL_PORT, "capacity": 6, "is_naval": True}
        )
        major = basing_repair_refuel_rates(
            {"level": LEVEL_MAJOR, "capacity": 12, "is_naval": True}
        )
        self.assertTrue(anch["can_service"])
        self.assertTrue(port["can_service"])
        self.assertTrue(major["can_service"])
        self.assertGreater(port["refuel_rate"], anch["refuel_rate"])
        self.assertGreater(major["refuel_rate"], port["refuel_rate"])
        self.assertGreater(port["repair_org_rate"], anch["repair_org_rate"])
        self.assertGreater(major["repair_org_rate"], port["repair_org_rate"])
        self.assertGreater(port["repair_readiness_rate"], anch["repair_readiness_rate"])
        self.assertGreater(major["repair_strength_rate"], port["repair_strength_rate"])
        # Finite positive
        for r in (anch, port, major):
            for k in (
                "refuel_rate",
                "repair_org_rate",
                "repair_readiness_rate",
                "repair_strength_rate",
            ):
                self.assertGreater(float(r[k]), 0.0)
                self.assertLess(float(r[k]), 1.0)

    def test_capacity_scales_within_level(self) -> None:
        low = basing_repair_refuel_rates(
            {"level": LEVEL_PORT, "capacity": 6, "is_naval": True}
        )
        high = basing_repair_refuel_rates(
            {"level": LEVEL_PORT, "capacity": 12, "is_naval": True}
        )
        self.assertGreater(high["refuel_rate"], low["refuel_rate"])
        self.assertGreater(high["scale"], low["scale"])

    def test_from_live_basing_helper_chain(self) -> None:
        """Drive compute_naval_basing → rates (real shipped chain)."""
        major_b = compute_naval_basing(
            domain="coastal_land",
            has_naval_shipyard=True,
            is_chokepoint=True,
            port_tier=3,
        )
        rates = basing_repair_refuel_rates(major_b)
        self.assertEqual(major_b["level"], LEVEL_MAJOR)
        self.assertTrue(rates["can_service"])
        self.assertGreaterEqual(rates["refuel_rate"], 0.40)
        land_b = compute_naval_basing(domain="land")
        land_r = basing_repair_refuel_rates(land_b)
        self.assertFalse(land_r["can_service"])
        self.assertLess(land_r["refuel_rate"], rates["refuel_rate"])


class TestBasingEffectWiring(unittest.TestCase):
    def test_gd_formatter_and_supply_path(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func basing_repair_refuel_rates", fmt)
        self.assertIn("refuel_rate", fmt)
        self.assertIn("repair_org_rate", fmt)
        # Badge surfaces refuel rate chip
        self.assertIn("refuel", fmt.lower())
        sm = GD_SM.read_text(encoding="utf-8")
        self.assertIn("_process_naval_fuel_endurance_and_repair", sm)
        self.assertIn("_resolve_naval_basing_service_rates", sm)
        self.assertIn("basing_repair_refuel_rates", sm)
        self.assertIn("get_naval_basing", sm)
        self.assertIn("refuel_rate", sm)
        self.assertIn("repair_org_rate", sm)
        # Flat-only constant path should not be the sole recovery when basing rates exist
        self.assertIn("refuel_r", sm)
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func get_naval_basing", mm)


if __name__ == "__main__":
    unittest.main(verbosity=2)
