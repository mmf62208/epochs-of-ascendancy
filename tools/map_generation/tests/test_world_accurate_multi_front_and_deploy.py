#!/usr/bin/env python3
"""Multi-front map + HOI station deploy + 60d + industrial hubs on world_accurate."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from formation_station_resolver import resolve_stations_hoi_deploy  # noqa: E402
from world_accurate_industrial_hub_product import (  # noqa: E402
    build_world_accurate_industrial_hub_product,
    world_accurate_industrial_hub_integrity,
)
from world_accurate_multi_front_product import (  # noqa: E402
    build_world_accurate_multi_front_product,
    border_provinces_for_tag,
    world_accurate_multi_front_integrity,
)
from world_accurate_60day_campaign_product import (  # noqa: E402
    build_world_accurate_60day_campaign_product,
    world_accurate_60day_campaign_integrity,
)

D = ROOT / "data" / "provinces_world_accurate"
SC = ROOT / "data" / "scenarios" / "world_accurate.json"
SPAWNER = ROOT / "scripts" / "formations" / "FormationSpawner.gd"
LOADER = ROOT / "scripts" / "core" / "ScenarioLoader.gd"


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate missing")
class TestWorldAccurateMultiFront(unittest.TestCase):
    def test_multi_front_product(self) -> None:
        p = build_world_accurate_multi_front_product()
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        self.assertGreaterEqual(int(p.get("active_n") or 0), 4)
        fronts = {f["id"]: f for f in p.get("fronts") or []}
        self.assertIn("rhineland_maginot", fronts)
        self.assertGreaterEqual(int(fronts["rhineland_maginot"]["edge_n"]), 8)
        self.assertTrue(fronts["rhineland_maginot"]["must_edge_ok"])
        self.assertGreaterEqual(int(fronts["polish_border"]["edge_n"]), 6)

    def test_integrity(self) -> None:
        self.assertTrue(world_accurate_multi_front_integrity().get("ok"))


@unittest.skipUnless(D.is_dir() and SC.is_file(), "board/scenario missing")
class TestHoiStationDeploy(unittest.TestCase):
    def test_hoi_deploy_prefers_capital_hubs_borders(self) -> None:
        sc = json.loads(SC.read_text())
        ger = next(c for c in sc["countries"] if c["tag"] == "GER")
        own = json.loads((D / "province_ownership_1936.json").read_text())["owners"]
        owned = [int(k) for k, v in own.items() if v == "GER"]
        adj = json.loads((D / "province_adjacency.json").read_text())["adjacency"]
        owners = {str(k): str(v) for k, v in own.items()}
        borders = border_provinces_for_tag(adj, owners, "GER", foreign_tags=["FRA", "POL"])
        keys = list(ger.get("key_provinces") or [])
        stations = resolve_stations_hoi_deploy(
            8,
            int(ger["capital_province_id"]),
            owned,
            key_provinces=keys,
            border_provinces=borders[:12],
        )
        self.assertEqual(stations[0], int(ger["capital_province_id"]))
        # At least one non-capital key hub in first stations
        self.assertTrue(any(s in keys and s != stations[0] for s in stations[:5]))
        # Border representation when available
        if borders:
            self.assertTrue(
                any(s in borders for s in stations),
                msg="expected a border station in HOI deploy list",
            )

    def test_gd_spawner_has_hoi_deploy(self) -> None:
        text = SPAWNER.read_text(encoding="utf-8")
        self.assertIn("resolve_stations_hoi_deploy", text)
        self.assertIn("key_provinces", text)
        self.assertIn("border_provinces", text)
        loader = LOADER.read_text(encoding="utf-8")
        self.assertIn("_get_key_provinces_for_tag", loader)
        self.assertIn("_collect_border_land_ids_for_tag", loader)
        self.assertIn("key_hubs", loader)


@unittest.skipUnless(D.is_dir(), "board missing")
class TestIndustrialHubsAnd60d(unittest.TestCase):
    def test_industrial_hubs(self) -> None:
        p = build_world_accurate_industrial_hub_product()
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        self.assertGreaterEqual(int(p.get("hub_n") or 0), 24)
        self.assertTrue(world_accurate_industrial_hub_integrity().get("ok"))

    def test_60day_product(self) -> None:
        p = build_world_accurate_60day_campaign_product(days=60, player_tag="GER")
        self.assertTrue(p.get("ok"), msg=p.get("plain") or p)
        self.assertEqual(int(p.get("days") or 0), 60)
        self.assertGreaterEqual(int(p.get("ai_ok_days") or 0), 48)
        self.assertTrue(world_accurate_60day_campaign_integrity().get("ok"))


if __name__ == "__main__":
    unittest.main()
