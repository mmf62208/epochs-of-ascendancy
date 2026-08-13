#!/usr/bin/env python3
"""Strategic map (chokes/supply/resources) + multi-front assault on world_accurate."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from world_accurate_front_assault_product import (  # noqa: E402
    build_world_accurate_front_assault_product,
    world_accurate_front_assault_integrity,
)
from world_accurate_multi_front_execute_product import (  # noqa: E402
    build_world_accurate_multi_front_execute_product,
    world_accurate_multi_front_execute_integrity,
)
from world_accurate_strategic_map_product import (  # noqa: E402
    build_world_accurate_strategic_map_product,
    world_accurate_strategic_map_integrity,
)

D = ROOT / "data" / "provinces_world_accurate"
PAINT = ROOT / "tools" / "map_generation" / "scripts" / "paint_world_accurate_strategic_resources.py"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate missing")
class TestWorldAccurateStrategicMap(unittest.TestCase):
    def test_strategic_map_product(self) -> None:
        p = build_world_accurate_strategic_map_product()
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        self.assertGreaterEqual(int(p.get("choke_n") or 0), 15)
        self.assertIsNotNone(p.get("ger_supply_path"))
        self.assertGreaterEqual(len(p.get("ger_supply_path") or []), 2)
        usa = (p.get("major_resources") or {}).get("USA") or {}
        self.assertGreaterEqual(int(usa.get("oil") or 0), 20)
        sov = (p.get("major_resources") or {}).get("SOV") or {}
        self.assertGreaterEqual(int(sov.get("oil") or 0), 5)

    def test_integrity(self) -> None:
        self.assertTrue(world_accurate_strategic_map_integrity().get("ok"))

    def test_resources_layer_has_oil_meta(self) -> None:
        doc = json.loads((D / "province_resources_layer.json").read_text())
        meta = doc.get("meta") or {}
        self.assertIn("oil", str(meta.get("resources") or meta))
        # Spot-check Baku / Texas oil paint
        res = doc.get("provinces") or {}
        baku = res.get("904831") or {}
        self.assertGreaterEqual(int(baku.get("oil") or 0), 2)
        self.assertTrue(PAINT.is_file())


@unittest.skipUnless(D.is_dir(), "board missing")
class TestWorldAccurateFrontAssault(unittest.TestCase):
    def test_front_assault_ranks_real_edges(self) -> None:
        p = build_world_accurate_front_assault_product(attacker_tag="GER")
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        self.assertGreaterEqual(int(p.get("targets_n") or 0), 4)
        self.assertGreater(int(p.get("best_province_id") or 0), 0)
        ranked = p.get("ranked") or {}
        ids = [int(t.get("province_id") or 0) for t in (ranked.get("all") or ranked.get("targets") or [])]
        self.assertIn(710739, ids)  # Bas-Rhin on Maginot front

    def test_integrity(self) -> None:
        self.assertTrue(world_accurate_front_assault_integrity().get("ok"))

    def test_multi_front_execute_package(self) -> None:
        p = build_world_accurate_multi_front_execute_product(attacker_tag="GER")
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        ids = p.get("assault_province_ids") or []
        self.assertGreaterEqual(len(ids), 2)
        # Maginot defender or Polish defender should appear in package/rank pool
        self.assertTrue(
            710739 in ids
            or any(
                int(q.get("province_id") or 0) > 710000
                for q in (p.get("apply_queue") or [])
                if isinstance(q, dict) and q.get("action_id") == "apply_assault"
            )
        )
        self.assertTrue(world_accurate_multi_front_execute_integrity().get("ok"))

    def test_mapmanager_live_border_api_in_source(self) -> None:
        mm = (ROOT / "scripts" / "map" / "MapManager.gd").read_text(encoding="utf-8")
        self.assertIn("func collect_live_border_assault_targets", mm)
        self.assertIn("Enemy land provinces on our borders", mm)
        self.assertIn("world_accurate_fronts", mm)
        self.assertIn("best_assault_province_id", mm)
        headless = ROOT / "scripts" / "core" / "HeadlessWorldAccurateMultiFrontAssaultTest.gd"
        self.assertTrue(headless.is_file())
        ht = headless.read_text(encoding="utf-8")
        self.assertIn("710739", ht)
        self.assertIn("711073", ht)
        self.assertIn("collect_live_border_assault_targets", ht)


if __name__ == "__main__":
    unittest.main()
