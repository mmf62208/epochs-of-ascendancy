#!/usr/bin/env python3
"""Gates: supply hub brief ranks capital/key hubs for a front (HOI logistics depth)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_supply_hub_brief_product import (  # noqa: E402
    build_map_supply_hub_brief_product,
    collect_hub_candidates,
    compute_fuel_score,
    format_hub_brief_toast,
    map_supply_hub_brief_integrity,
    pick_best_hub,
    score_hub_to_front,
)

RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
SC = ROOT / "data" / "scenarios" / "world_accurate.json"


class TestMapSupplyHubBriefProduct(unittest.TestCase):
    def test_ger_brief_on_board(self) -> None:
        p = build_map_supply_hub_brief_product(tag="GER", front_id=710173)
        self.assertTrue(p.get("ok"), msg=p)
        best = p.get("best") or {}
        self.assertGreater(int(best.get("hub_id") or 0), 0)
        self.assertGreaterEqual(int(best.get("hops") or -1), 0)
        self.assertGreaterEqual(len(p.get("candidates") or []), 2)
        self.assertTrue(p.get("multi_hub"))
        self.assertIn("G corridor", str(p.get("toast") or ""))
        # All candidates scored
        self.assertEqual(len(p.get("scored") or []), len(p.get("candidates") or []))

    def test_integrity(self) -> None:
        g = map_supply_hub_brief_integrity(tag="GER", front_id=710173)
        self.assertTrue(g.get("ok"), msg=g)
        self.assertTrue(g.get("multi_hub"))

    def test_pick_best_prefers_shorter_hops(self) -> None:
        cands = [
            {"province_id": 1, "role": "capital", "name": "A"},
            {"province_id": 2, "role": "key_hub", "name": "B"},
        ]
        scored = [
            {"ok": True, "hub_id": 1, "hops": 10, "score": 10.0, "mean_infra": 5.0, "fuel_score": 0.9},
            {"ok": True, "hub_id": 2, "hops": 3, "score": 2.8, "mean_infra": 4.0, "fuel_score": 0.1},
        ]
        best = pick_best_hub(cands, scored)
        self.assertIsNotNone(best)
        self.assertEqual(int(best["hub_id"]), 2)
        self.assertEqual(best.get("name"), "B")

    def test_score_unreachable(self) -> None:
        r = score_hub_to_front({}, 1, 99, limit=3)
        self.assertFalse(r.get("ok"))
        self.assertIn("fuel_score", r)
        self.assertIn("mean_infra", r)

    def test_toast_format(self) -> None:
        t = format_hub_brief_toast(
            {"name": "Berlin", "role": "capital", "hops": 11, "hub_id": 710300},
            710173,
            front_name="Baden-Baden",
        )
        self.assertIn("Berlin", t)
        self.assertIn("11 hops", t)
        self.assertIn("G corridor", t)
        # No fuel_score key → no fuel snippet (backward compatible)
        self.assertNotIn("fuel ", t)

    def test_toast_includes_fuel_when_present(self) -> None:
        t = format_hub_brief_toast(
            {
                "name": "Berlin",
                "role": "capital",
                "hops": 11,
                "hub_id": 710300,
                "fuel_score": 0.72,
            },
            710173,
            front_name="Baden",
        )
        self.assertIn("Berlin", t)
        self.assertIn("11 hops", t)
        self.assertIn("fuel 0.72", t)
        self.assertIn("G corridor", t)
        # Order: hops · fuel · G corridor
        self.assertLess(t.index("11 hops"), t.index("fuel 0.72"))
        self.assertLess(t.index("fuel 0.72"), t.index("G corridor"))

    def test_product_best_has_fuel_score(self) -> None:
        p = build_map_supply_hub_brief_product(tag="GER", front_id=710173)
        self.assertTrue(p.get("ok"), msg=p)
        best = p.get("best") or {}
        self.assertIn("fuel_score", best)
        self.assertIn("mean_infra", best)
        self.assertIsInstance(best.get("fuel_score"), (int, float))
        self.assertGreaterEqual(float(best.get("fuel_score") or 0), 0.0)
        # Optional path_fuel on scored/best rows
        self.assertIn("path_fuel", best)
        for row in p.get("scored") or []:
            if row.get("ok"):
                self.assertIn("fuel_score", row)
                self.assertIn("mean_infra", row)
                self.assertIn("path_fuel", row)
        # Toast from live product should include fuel snippet
        toast = str(p.get("toast") or "")
        self.assertIn("G corridor", toast)
        self.assertIn("fuel ", toast)

    def test_fuel_score_path_and_depot(self) -> None:
        path = [1, 2, 3]
        resources = {
            1: {"oil": 8, "coal": 1},
            2: {"rubber": 4},
            3: {"steel": 9},
        }
        eco = {1: {"factories": 10, "infrastructure": 8}}
        f = compute_fuel_score(path, 1, resources_by_pid=resources, eco_by_pid=eco)
        self.assertGreater(float(f["path_fuel"]), 0.0)
        self.assertGreater(float(f["fuel_score"]), 0.0)
        self.assertGreater(float(f["depot_strength"]), 0.0)
        # Higher depot should not drop fuel_score below oil-less baseline with same path empty
        f_empty = compute_fuel_score(path, 1, resources_by_pid={}, eco_by_pid=eco)
        self.assertGreaterEqual(float(f["fuel_score"]), float(f_empty["fuel_score"]))

    def test_collect_hubs_from_scenario(self) -> None:
        import json

        sc = json.loads(SC.read_text(encoding="utf-8"))
        hubs = collect_hub_candidates(sc, "GER")
        self.assertGreaterEqual(len(hubs), 2)
        self.assertEqual(hubs[0].get("role"), "capital")

    def test_renderer_prefers_best_hub_for_corridor(self) -> None:
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn("func _resolve_corridor_source_for_tag", ren)
        self.assertIn("func _pick_best_supply_hub_for_front", ren)
        self.assertIn("key_provinces", ren)
        self.assertIn("Supply hub", ren)
        self.assertIn("highlight_corridor_capital_to_selected", ren)


if __name__ == "__main__":
    unittest.main()
