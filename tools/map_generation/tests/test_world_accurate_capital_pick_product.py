#!/usr/bin/env python3
"""Director D4.3 — accurate capital pick sample product gates."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from world_accurate_capital_pick_product import (  # noqa: E402
    build_world_accurate_capital_pick_product,
    world_accurate_capital_pick_integrity,
)

D = ROOT / "data" / "provinces_world_accurate"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestWorldAccurateCapitalPickProduct(unittest.TestCase):
    def test_product_pass_on_shipped_board(self) -> None:
        p = build_world_accurate_capital_pick_product()
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        self.assertEqual(int(p.get("sample_n") or 0), 8)
        # Post US + full RoW sparse merge ~3520; was ~4683 / ~5670 / ~8761
        self.assertGreaterEqual(int(p.get("province_count") or 0), 3000)
        tags = {s["tag"] for s in p.get("samples") or []}
        for t in ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL"):
            self.assertIn(t, tags)
        # Capitals are land + owned + have centroids
        for s in p.get("samples") or []:
            self.assertFalse(s.get("is_water"), s)
            self.assertEqual(s.get("owner"), s.get("tag"), s)
            self.assertIsNotNone(s.get("centroid"), s)
            self.assertGreaterEqual(int(s.get("point_n") or 0), 3)

    def test_integrity(self) -> None:
        g = world_accurate_capital_pick_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_scaffold_dual_note(self) -> None:
        p = build_world_accurate_capital_pick_product()
        note = str(p.get("dual_note") or "")
        self.assertIn("world_full", note)
        self.assertIn("map_manager_pick_harness", note)
        self.assertIn("map_manager_pick_harness_accurate", note)

    def test_accurate_gd_harness_shipped(self) -> None:
        gd = ROOT / "tools" / "map_manager_pick_harness_accurate.gd"
        self.assertTrue(gd.is_file(), gd)
        text = gd.read_text(encoding="utf-8")
        self.assertIn("provinces_world_accurate", text)
        self.assertIn("world_accurate.json", text)
        self.assertIn("get_province_at_world_pos", text)

    def test_settle_title_uses_name_and_capital_snap(self) -> None:
        """Play extra: Settle London/Devon by name; click near capital star picks capital."""
        mm = (ROOT / "scripts" / "map" / "MapManager.gd").read_text(encoding="utf-8")
        ren = (ROOT / "scripts" / "map" / "MapRenderer.gd").read_text(encoding="utf-8")
        self.assertIn("func prefer_capital_province_at", mm)
        self.assertIn("prefer_capital_province_at(world_pos, prefer_land_province_at", mm)
        self.assertIn("711467", mm)
        self.assertIn("711414", mm)
        self.assertIn("func _capital_star_snap_radius_sq", mm)
        self.assertIn("_get_camera_zoom", mm)
        self.assertIn("func _capital_star_pid_at", ren)
        self.assertIn("_capital_star_pid_at(world_pos_arm)", ren)
        self.assertIn('Settle %s', ren)
        self.assertNotIn('Settle #%d', ren)

    def test_nested_city_capitals_are_named_and_tiny(self) -> None:
        """City-within-city capitals must exist as named land owned by the major."""
        p = build_world_accurate_capital_pick_product()
        by_tag = {s["tag"]: s for s in p.get("samples") or []}
        eng = by_tag["ENG"]
        usa = by_tag["USA"]
        ita = by_tag["ITA"]
        self.assertEqual(int(eng["province_id"]), 711414)
        self.assertIn("london", str(eng.get("name") or "").lower())
        self.assertEqual(int(usa["province_id"]), 800792)
        self.assertIn("columbia", str(usa.get("name") or "").lower())
        self.assertEqual(int(ita["province_id"]), 710963)
        self.assertIn("roma", str(ita.get("name") or "").lower())
        self.assertFalse(eng.get("is_water"))
        self.assertFalse(usa.get("is_water"))
        self.assertFalse(ita.get("is_water"))

    def test_key_provinces_are_owned_land_hubs(self) -> None:
        """HOI-style key industrial hubs must be land + owned by the scenario tag."""
        sc = json.loads((ROOT / "data" / "scenarios" / "world_accurate.json").read_text())
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text())["provinces"]
        }
        owners = json.loads((D / "province_ownership_1936.json").read_text()).get("owners") or {}
        water = {"sea", "ocean", "water", "lake"}
        for c in sc.get("countries") or []:
            tag = c["tag"]
            keys = list(c.get("key_provinces") or [])
            self.assertGreaterEqual(len(keys), 2 if tag != "SOV" else 2, tag)
            self.assertIn(int(c["capital_province_id"]), keys, tag)
            for pid in keys:
                p = base[int(pid)]
                terr = str(p.get("terrain", "")).lower()
                self.assertNotIn(terr, water, f"{tag} key {pid}")
                self.assertEqual(owners.get(str(pid)), tag, f"{tag} key {pid} owner")


if __name__ == "__main__":
    unittest.main()
