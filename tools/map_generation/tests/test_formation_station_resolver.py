#!/usr/bin/env python3
"""Pure tests for formation station resolution (owned land / capital preference)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from formation_station_resolver import (  # noqa: E402
    owned_land_from_scenario_overrides,
    resolve_station_province_id,
    resolve_stations_for_count,
)

WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
MAJORS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP")


class TestResolverPure(unittest.TestCase):
    def test_prefers_capital_when_owned(self) -> None:
        self.assertEqual(resolve_station_province_id(100, [50, 100, 200]), 100)

    def test_rejects_unowned_capital_uses_sorted_owned(self) -> None:
        self.assertEqual(resolve_station_province_id(999, [50, 200, 100]), 50)

    def test_rejects_empty(self) -> None:
        self.assertEqual(resolve_station_province_id(1, []), -1)
        self.assertEqual(resolve_station_province_id(-1, []), -1)

    def test_rejects_water_via_filter(self) -> None:
        water = {9}
        # capital is water — fall through to owned land
        self.assertEqual(
            resolve_station_province_id(9, [9, 10, 11], water_ids=water),
            10,
        )

    def test_rejects_invalid_ids(self) -> None:
        valid = {5, 6}
        self.assertEqual(
            resolve_station_province_id(1, [1, 5, 6], valid_land_ids=valid),
            5,
        )

    def test_stations_for_count_spreads(self) -> None:
        stations = resolve_stations_for_count(5, 100, [100, 101, 102])
        self.assertEqual(len(stations), 5)
        self.assertEqual(stations[0], 100)
        self.assertTrue(all(s in (100, 101, 102) for s in stations))

    def test_obsolete_demo_pids_not_used_when_unowned(self) -> None:
        """GER demo pid 2 is not on board / not owned — resolver must not invent it."""
        owned = [9287, 3, 9301]
        self.assertEqual(resolve_station_province_id(2, owned), 3)  # 2 not owned → sorted first 3
        self.assertNotEqual(resolve_station_province_id(9287, owned), 2)


class TestShippedWorldFullStations(unittest.TestCase):
    def test_each_country_resolves_owned_capital_or_land(self) -> None:
        scen = json.loads(SCEN.read_text())
        base = {
            int(p["id"]): p
            for p in json.loads((WF / "provinces_base.json").read_text())["provinces"]
        }
        land_ids = {
            pid
            for pid, p in base.items()
            if str(p.get("domain") or "land") not in ("sea", "strait", "lake")
        }
        water_ids = set(base.keys()) - land_ids
        overrides = scen.get("provinces") or []
        self.assertIsInstance(overrides, list)
        self.assertGreaterEqual(len(overrides), 1000)

        for c in scen["countries"]:
            tag = str(c["tag"]).upper()
            cap = int(c["capital_province_id"])
            owned = owned_land_from_scenario_overrides(overrides, tag, base)
            self.assertGreaterEqual(len(owned), 1, msg=tag)
            station = resolve_station_province_id(
                cap, owned, valid_land_ids=land_ids, water_ids=water_ids
            )
            self.assertGreater(station, 0, msg=tag)
            self.assertIn(station, owned)
            self.assertIn(station, land_ids)
            # Capital preferred when capital is owned land
            if cap in owned and cap in land_ids:
                self.assertEqual(station, cap, msg=f"{tag} should station at capital {cap}")

    def test_majors_have_enough_owned_land_for_three_stations(self) -> None:
        scen = json.loads(SCEN.read_text())
        base = {
            int(p["id"]): p
            for p in json.loads((WF / "provinces_base.json").read_text())["provinces"]
        }
        overrides = scen.get("provinces") or []
        for m in MAJORS:
            c = next(x for x in scen["countries"] if str(x["tag"]).upper() == m)
            owned = owned_land_from_scenario_overrides(overrides, m, base)
            self.assertGreaterEqual(len(owned), 5, msg=m)
            stations = resolve_stations_for_count(8, int(c["capital_province_id"]), owned)
            # Land formation slots in spawner pattern for count=8: indices 0,1,4,6,7 are land types
            land_indices = [0, 1, 4, 6, 7]
            land_stations = [stations[i] for i in land_indices]
            self.assertTrue(all(s > 0 and s in owned for s in land_stations), msg=(m, land_stations))
            self.assertGreaterEqual(len(land_stations), 3)

    def test_gd_spawner_has_resolver_no_demo_pids(self) -> None:
        gd = (ROOT / "scripts" / "formations" / "FormationSpawner.gd").read_text(encoding="utf-8")
        self.assertIn("func resolve_station_province_id", gd)
        self.assertIn("resolve_stations_for_count", gd)
        # Obsolete hardcoded demo map must not station GER→2 etc.
        self.assertNotIn('"GER": 2', gd)
        self.assertNotIn("demo_pids", gd)
        loader = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("_collect_owned_land_ids_from_loader", loader)
        self.assertIn("_print_formation_station_evidence", loader)
        self.assertIn("capital_id", loader)


if __name__ == "__main__":
    unittest.main(verbosity=2)
