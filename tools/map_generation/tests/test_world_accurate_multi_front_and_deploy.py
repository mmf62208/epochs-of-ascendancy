#!/usr/bin/env python3
"""Multi-front map + HOI station deploy + 60d + industrial hubs on world_accurate."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from formation_station_resolver import (  # noqa: E402
    DEFAULT_FORMATION_TYPES,
    LAND_FORMATION_TYPES,
    land_slot_indices,
    resolve_stations_hoi_deploy,
)
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

# Canonical Maginot edge (world_accurate_multi_front_product.GER_FRA_EDGE).
GER_MAGINOT = 710173  # Baden-Baden
FRA_MAGINOT = 710739  # Bas-Rhin


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

    def test_ger_front_reserve_710173_on_land_slot(self) -> None:
        """GER 8-count with real key_provinces stations Maginot 710173 on a land slot."""
        sc = json.loads(SC.read_text())
        ger = next(c for c in sc["countries"] if c["tag"] == "GER")
        own = json.loads((D / "province_ownership_1936.json").read_text())["owners"]
        owned = [int(k) for k, v in own.items() if v == "GER"]
        self.assertIn(GER_MAGINOT, owned)
        keys = list(ger.get("key_provinces") or [])
        self.assertGreaterEqual(len(keys), 5)
        # Five hubs would consume all land slots without front_reserve.
        stations = resolve_stations_hoi_deploy(
            8,
            int(ger["capital_province_id"]),
            owned,
            key_provinces=keys,
            front_reserve=[GER_MAGINOT],
            formation_types=DEFAULT_FORMATION_TYPES,
        )
        self.assertEqual(len(stations), 8)
        land_idx = land_slot_indices(8, DEFAULT_FORMATION_TYPES)
        self.assertGreaterEqual(len(land_idx), 3)
        # Derived from type cycle — not hard-coded (0,1,4,6,7) in product code.
        land_stations = [stations[i] for i in land_idx]
        self.assertIn(
            GER_MAGINOT,
            land_stations,
            msg=f"expected GER Maginot {GER_MAGINOT} on land slot; land={land_stations}",
        )
        # First land slot is first reserve.
        self.assertEqual(stations[land_idx[0]], GER_MAGINOT)
        # Naval/air must not sit on reserved front pid.
        for i, sid in enumerate(stations):
            ftype = DEFAULT_FORMATION_TYPES[i % len(DEFAULT_FORMATION_TYPES)]
            if ftype not in LAND_FORMATION_TYPES:
                self.assertNotEqual(
                    sid,
                    GER_MAGINOT,
                    msg=f"non-land slot {i} ({ftype}) must not consume front {GER_MAGINOT}",
                )

    def test_fra_front_reserve_710739_on_land_slot(self) -> None:
        sc = json.loads(SC.read_text())
        fra = next(c for c in sc["countries"] if c["tag"] == "FRA")
        own = json.loads((D / "province_ownership_1936.json").read_text())["owners"]
        owned = [int(k) for k, v in own.items() if v == "FRA"]
        self.assertIn(FRA_MAGINOT, owned)
        stations = resolve_stations_hoi_deploy(
            8,
            int(fra["capital_province_id"]),
            owned,
            key_provinces=list(fra.get("key_provinces") or []),
            front_reserve=[FRA_MAGINOT],
            formation_types=DEFAULT_FORMATION_TYPES,
        )
        land_stations = [
            stations[i] for i in land_slot_indices(8, DEFAULT_FORMATION_TYPES)
        ]
        self.assertIn(FRA_MAGINOT, land_stations)

    def test_gd_spawner_has_hoi_deploy(self) -> None:
        text = SPAWNER.read_text(encoding="utf-8")
        self.assertIn("resolve_stations_hoi_deploy", text)
        self.assertIn("key_provinces", text)
        self.assertIn("border_provinces", text)
        self.assertIn("front_reserve", text)
        self.assertIn("LAND_FORMATION_TYPES", text)
        loader = LOADER.read_text(encoding="utf-8")
        self.assertIn("_get_key_provinces_for_tag", loader)
        self.assertIn("_collect_border_land_ids_for_tag", loader)
        self.assertIn("key_hubs", loader)
        self.assertIn("_front_reserve_for_tag", loader)
        self.assertIn("710173", loader)
        self.assertIn("710739", loader)
        self.assertIn("front=", loader)


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
