#!/usr/bin/env python3
"""P1 air-physics product: presets in band, Me 262 §5, variant pairs, golden."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from air_physics_p1 import (  # noqa: E402
    CAL_BAND_HI,
    CAL_BAND_LO,
    GOLDEN_PATH,
    PRESETS_PATH,
    STORE_CLASS_EXPONENT,
    build_golden,
    calibration_row,
    compare_golden,
    default_loadouts,
    evaluate,
    load_json,
    load_presets,
    me262_cases,
    p51_bc_to_d_pair,
    p51_tank_pair,
    rato_overload_check,
    typhoon_tank_pair,
)


class TestAirPhysicsP1Product(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.presets = load_presets(PRESETS_PATH)
        cls.golden = load_json(GOLDEN_PATH)

    def test_twelve_presets(self) -> None:
        self.assertEqual(len(self.presets), 12)
        for pid in (
            "bf109e",
            "spitfire_mk1",
            "p51d",
            "p47d",
            "typhoon_ib",
            "b17g",
            "me262_a1a",
            "f86a",
            "f16c",
            "f35a",
            "fw190a",
            "a6m2_zero",
        ):
            self.assertIn(pid, self.presets)

    def test_presets_in_band(self) -> None:
        for pid, block in self.presets.items():
            row = calibration_row(block)
            self.assertGreaterEqual(row["result_km"] + 1e-9, row["sourced_km"], msg=pid)
            self.assertGreaterEqual(row["ratio"], CAL_BAND_LO, msg=(pid, row))
            self.assertLessEqual(row["ratio"], CAL_BAND_HI, msg=(pid, row))
            self.assertTrue(row["in_band"], msg=(pid, row))

    def test_me262_exactly_1071(self) -> None:
        row = calibration_row(self.presets["me262_a1a"])
        self.assertAlmostEqual(row["result_km"], 1071.0, places=6)
        self.assertAlmostEqual(row["ratio"], 1.020, places=6)

    def test_store_class_exponent_linear(self) -> None:
        self.assertEqual(STORE_CLASS_EXPONENT, 1.0)

    def test_rato_stub(self) -> None:
        r = rato_overload_check(7533.0, 7130.0)
        self.assertIs(r["allowed"], False)
        self.assertEqual(r["deferred"], "P2")

    def test_variant_pairs(self) -> None:
        pairs = {
            "p51_tank": p51_tank_pair(),
            "p51_bc_to_d": p51_bc_to_d_pair(),
            "typhoon_tanks": typhoon_tank_pair(),
        }
        for name, p in pairs.items():
            self.assertLessEqual(abs(p["error"]), 0.05, msg=(name, p))

    def test_me262_cases(self) -> None:
        cases = me262_cases(self.presets["me262_a1a"])
        clean = cases["clean"]
        self.assertAlmostEqual(clean["w_i_kg"], 6473.0, delta=0.0)
        self.assertAlmostEqual(clean["mtow_delta_kg"], 657.0, delta=0.0)
        self.assertAlmostEqual(clean["range_loaded_km"], 1071.0, delta=1.0)
        self.assertEqual(clean["range_loaded_hexes"], 44)
        self.assertEqual(clean["radius_hexes"], 17)
        self.assertAlmostEqual(clean["v_max_loaded_kmh"], 870.0, delta=1.0)
        self.assertAlmostEqual(clean["agility"], 1.0, delta=0.005)
        self.assertAlmostEqual(clean["takeoff_lo_m"], 914.0, delta=5.0)
        self.assertAlmostEqual(clean["takeoff_hi_m"], 1189.0, delta=5.0)

        sc = cases["sc500"]
        self.assertAlmostEqual(sc["w_i_kg"], 7033.0, delta=0.0)
        self.assertAlmostEqual(sc["mtow_delta_kg"], 97.0, delta=0.0)
        self.assertAlmostEqual(sc["range_loaded_km"], 731.0, delta=1.0)
        self.assertEqual(sc["range_loaded_hexes"], 30)
        self.assertEqual(sc["radius_hexes"], 13)
        self.assertEqual(sc["two_leg_radius_hexes"], 16)
        self.assertAlmostEqual(sc["v_max_loaded_kmh"], 753.0, delta=1.0)
        self.assertAlmostEqual(sc["agility"], 0.690, delta=0.005)
        self.assertAlmostEqual(sc["takeoff_lo_m"], 1079.0, delta=5.0)
        self.assertAlmostEqual(sc["takeoff_hi_m"], 1404.0, delta=5.0)

        kg = cases["kg1000_full"]
        self.assertTrue(kg["over_mtow"])
        self.assertAlmostEqual(kg["w_i_kg"], 7533.0, delta=0.0)
        self.assertAlmostEqual(kg["mtow_delta_kg"], -403.0, delta=0.0)
        self.assertAlmostEqual(kg["range_loaded_km"], 451.0, delta=1.0)
        self.assertEqual(kg["range_loaded_hexes"], 19)
        self.assertEqual(kg["radius_hexes"], 6)
        self.assertAlmostEqual(kg["v_max_loaded_kmh"], 615.0, delta=1.0)
        self.assertAlmostEqual(kg["agility"], 0.430, delta=0.005)
        self.assertAlmostEqual(kg["fuel_cut_L"], 1514.0, delta=2.0)
        self.assertEqual(kg["fuel_cut_radius_hexes"], 4)
        ids = [w["id"] for w in kg["warnings"]]
        self.assertIn("overweight", ids)
        overweight = [w for w in kg["warnings"] if w["id"] == "overweight"][0]
        self.assertGreaterEqual(len(overweight["fixes"]), 3)

        cut = cases["kg1000_fuel_cut"]
        self.assertAlmostEqual(cut["w_i_kg"], 7130.0, delta=0.0)
        self.assertAlmostEqual(cut["range_loaded_km"], 339.0, delta=1.0)
        self.assertEqual(cut["range_loaded_hexes"], 14)
        self.assertEqual(cut["radius_hexes"], 4)
        self.assertAlmostEqual(cut["agility"], 0.454, delta=0.005)
        self.assertAlmostEqual(cut["w_fuel_kg"], 1257.0, delta=0.5)

    def test_f35_light_strike_radius_42(self) -> None:
        ev = evaluate(
            self.presets["f35a"],
            {"id": "clean", "payload_kg": 0.0, "store_class": 0.0},
            "strike_light",
        )
        self.assertEqual(ev["radius_hexes"], 42)

    def test_golden_regenerate(self) -> None:
        computed = build_golden(self.presets)
        n, max_rel, fails = compare_golden(computed, self.golden, 1e-9)
        self.assertGreater(n, 20)
        self.assertEqual(fails, [], msg=fails)
        self.assertLessEqual(max_rel, 1e-9)

    def test_p47_pending_flag(self) -> None:
        cal = self.presets["p47d"]["calibration"]
        self.assertTrue(cal.get("pending_source"))
        self.assertEqual(cal.get("source_id"), "P1-1")

    def test_f16_combat_derived(self) -> None:
        block = self.presets["f16c"]
        self.assertEqual(block["profile"], "ferry")
        los = {lo["id"]: lo for lo in default_loadouts(block)}
        combat = evaluate(block, los["clean"], "escort")
        ferry = evaluate(block, los["ferry_2tanks"], "ferry")
        self.assertGreater(ferry["range_loaded_km"], combat["range_loaded_km"])
        self.assertTrue(los["clean"].get("derived_combat"))

    def test_no_rng_in_math_sources(self) -> None:
        banned = ("randf", "randi", "RandomNumberGenerator", "Time.get", "OS.get_ticks")
        paths = [
            ROOT / "scripts" / "units" / "UnitPhysics.gd",
            ROOT / "scripts" / "units" / "DesignCalculator.gd",
            ROOT / "scripts" / "ui" / "AirPhysicsReadoutPanel.gd",
            ROOT / "tools" / "map_generation" / "lib" / "air_physics_p1.py",
        ]
        for path in paths:
            text = path.read_text(encoding="utf-8")
            for token in banned:
                self.assertNotIn(token, text, msg=(path, token))


if __name__ == "__main__":
    unittest.main()
