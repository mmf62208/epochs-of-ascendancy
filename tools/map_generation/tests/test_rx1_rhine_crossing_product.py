#!/usr/bin/env python3
"""Gates: RX-1 Rhine Crossing — shared borders, alignment, edge penalties."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from rx1_rhine_crossing_product import (  # noqa: E402
    BONN_ID,
    DUSSELDORF_ID,
    DUISBURG_ID,
    ESSEN_ID,
    KOELN_ID,
    METTMANN_ID,
    NEUSS_ID,
    RHINE_BRIDGED_ATTACK_MALUS,
    RHINE_BRIDGED_MOVE_MULT,
    RHINE_UNBRIDGED_ATTACK_MALUS,
    RHINE_UNBRIDGED_MOVE_MULT,
    SLICE_NAME,
    attack_malus,
    attack_power_after,
    build_rx1_rhine_crossing_product,
    fresh_checkout_launch,
    hop_eta_days,
    knn_has_koeln_essen,
    listed_edges,
    load_rx1_spec,
    move_mult,
    shared_border_guard,
    visibility_order,
)


class TestRx1RhineCrossingProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_rx1_rhine_crossing_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("slice"), SLICE_NAME)
        self.assertGreaterEqual(len(p.get("edges") or []), 4)
        self.assertTrue(p.get("unbridged"), msg=p)
        self.assertTrue(p.get("bridged"), msg=p)

    def test_constants(self) -> None:
        spec = load_rx1_spec()
        c = spec.get("constants") or {}
        self.assertEqual(float(c["RHINE_UNBRIDGED_MOVE_MULT"]), RHINE_UNBRIDGED_MOVE_MULT)
        self.assertEqual(float(c["RHINE_BRIDGED_MOVE_MULT"]), RHINE_BRIDGED_MOVE_MULT)
        self.assertEqual(float(c["RHINE_UNBRIDGED_ATTACK_MALUS"]), RHINE_UNBRIDGED_ATTACK_MALUS)
        self.assertEqual(float(c["RHINE_BRIDGED_ATTACK_MALUS"]), RHINE_BRIDGED_ATTACK_MALUS)

    def test_shared_border_guard_rejects_knn(self) -> None:
        # Do not use adjacency.json (shared_edge + kNN). Köln–Essen must never
        # be a listed crossing even if some boards still list that kNN pair.
        _ = knn_has_koeln_essen()
        guard = shared_border_guard()
        self.assertTrue(guard.get("ok"), msg=guard)
        keys = set(guard.get("checked") or [])
        self.assertNotIn("%d-%d" % (min(KOELN_ID, ESSEN_ID), max(KOELN_ID, ESSEN_ID)), keys)

    def test_neuss_mettmann_unbridged_longer_eta_and_weaker_attack(self) -> None:
        spec = load_rx1_spec()
        edges = listed_edges(spec)
        self.assertIn((min(NEUSS_ID, METTMANN_ID), max(NEUSS_ID, METTMANN_ID)), edges)
        un_eta = hop_eta_days(1.0, NEUSS_ID, METTMANN_ID, False, spec)
        br_eta = hop_eta_days(1.0, NEUSS_ID, DUSSELDORF_ID, True, spec)
        self.assertGreater(un_eta, br_eta)
        self.assertAlmostEqual(un_eta, 2.0)
        self.assertAlmostEqual(br_eta, 1.15)
        un_atk = attack_power_after(100.0, NEUSS_ID, METTMANN_ID, False, spec)
        br_atk = attack_power_after(100.0, NEUSS_ID, DUSSELDORF_ID, True, spec)
        self.assertLess(un_atk, br_atk)
        self.assertAlmostEqual(un_atk, 70.0)
        self.assertAlmostEqual(br_atk, 90.0)
        self.assertEqual(move_mult(ESSEN_ID, KOELN_ID, False, spec), 1.0)
        self.assertEqual(attack_malus(ESSEN_ID, KOELN_ID, False, spec), 0.0)

    def test_alignment_and_course(self) -> None:
        spec = load_rx1_spec()
        align = spec.get("alignment") or {}
        self.assertTrue(align.get("cities_on_banks"), msg=align)
        self.assertTrue(align.get("essen_off_river"), msg=align)
        cities = align.get("city_distances_canvas") or {}
        self.assertLess(float(cities["Köln"]["rhine_dist"]), 1.0)
        self.assertLess(float(cities["Bonn"]["rhine_dist"]), 1.0)
        self.assertLess(float(cities["Düsseldorf"]["rhine_dist"]), 1.0)
        self.assertLess(float(cities["Duisburg"]["rhine_dist"]), 2.0)
        self.assertGreater(float(cities["Essen"]["rhine_dist"]), 4.0)
        course = (spec.get("course") or {}).get("points") or []
        self.assertGreaterEqual(len(course), 16)
        theater = {BONN_ID, KOELN_ID, DUSSELDORF_ID, DUISBURG_ID}
        names = {int(e[0]) for e in listed_edges(spec)} | {int(e[1]) for e in listed_edges(spec)}
        self.assertTrue(theater & names)

    def test_visibility_order_above_unit_counters(self) -> None:
        vis = visibility_order()
        self.assertTrue(vis.get("ok"), msg=vis)
        self.assertGreater(int(vis.get("rhine_z", -1)), int(vis.get("unit_z", 99)))
        self.assertGreater(int(vis.get("road_z", -1)), int(vis.get("unit_z", 99)))
        self.assertTrue(vis.get("spine_ok"), msg=vis)

    def test_fresh_checkout_launch_imports_class_cache(self) -> None:
        fresh = fresh_checkout_launch()
        self.assertTrue(fresh.get("ok"), msg=fresh)
        self.assertTrue(fresh.get("import_gate"), msg=fresh)
        self.assertTrue(fresh.get("preload"), msg=fresh)


if __name__ == "__main__":
    unittest.main()
