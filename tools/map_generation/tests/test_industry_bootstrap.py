#!/usr/bin/env python3
"""Pure tests: world_full industrial bootstrap (capitals, ownership, starting_oob)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from industry_bootstrap import (  # noqa: E402
    pick_shipyard_province,
    primary_land_design,
    resolve_industrial_province_ids,
    starting_oob_designs,
)

SCEN = ROOT / "data" / "scenarios" / "world_full.json"
WF = ROOT / "data" / "provinces_world_full"
MAJORS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP")


class TestIndustryPure(unittest.TestCase):
    def test_resolve_prefers_capital_and_keys(self) -> None:
        ids = resolve_industrial_province_ids(10, [20, 10, 30], [10, 20, 30, 40])
        self.assertEqual(ids[0], 10)
        self.assertIn(20, ids)
        self.assertIn(30, ids)
        # invalid keys filtered
        ids2 = resolve_industrial_province_ids(10, [99, 20], [10, 20])
        self.assertEqual(ids2, [10, 20])

    def test_shipyard_prefers_industrial_port(self) -> None:
        self.assertEqual(pick_shipyard_province([1, 2, 3], [3, 9]), 3)
        self.assertEqual(pick_shipyard_province([1], [5, 6]), 5)
        self.assertIsNone(pick_shipyard_province([1], []))


class TestShippedWorldFullIndustry(unittest.TestCase):
    def test_majors_capitals_owned_land_with_oob(self) -> None:
        scen = json.loads(SCEN.read_text())
        base = {
            int(p["id"]): p
            for p in json.loads((WF / "provinces_base.json").read_text())["provinces"]
        }
        owners = {
            int(p["id"]): str(p.get("owner_tag") or "").upper()
            for p in scen.get("provinces") or []
            if isinstance(p, dict)
        }
        countries = {str(c["tag"]).upper(): c for c in scen["countries"]}
        for m in MAJORS:
            self.assertIn(m, countries)
            c = countries[m]
            cap = int(c["capital_province_id"])
            self.assertIn(cap, base, msg=f"{m} capital missing")
            self.assertNotIn(
                str(base[cap].get("domain") or "land"),
                ("sea", "strait", "lake"),
                msg=f"{m} capital is water",
            )
            self.assertEqual(owners.get(cap), m, msg=f"{m} capital not owned")
            designs = starting_oob_designs(c)
            self.assertTrue(designs, msg=f"{m} empty starting_oob")
            self.assertTrue(primary_land_design(c), msg=f"{m} no land design")
            # industrial resolve
            keys = [int(x) for x in (c.get("key_provinces") or [])]
            owned_land = [
                pid
                for pid, ot in owners.items()
                if ot == m and str(base.get(pid, {}).get("domain")) not in ("sea", "strait", "lake")
            ]
            ind = resolve_industrial_province_ids(cap, keys, owned_land)
            self.assertTrue(ind)
            self.assertEqual(ind[0], cap)
            self.assertTrue(all(pid in owned_land for pid in ind))

    def test_majors_have_port_eligible_owned_land_or_documented(self) -> None:
        """Naval majors should have ≥1 owned coastal/port-ish land for shipyards."""
        scen = json.loads(SCEN.read_text())
        base = {
            int(p["id"]): p
            for p in json.loads((WF / "provinces_base.json").read_text())["provinces"]
        }
        owners = {
            int(p["id"]): str(p.get("owner_tag") or "").upper()
            for p in scen.get("provinces") or []
        }
        adj = json.loads((WF / "province_adjacency.json").read_text()).get("adjacency") or {}
        sea = {
            pid
            for pid, p in base.items()
            if p.get("domain") in ("sea", "strait", "lake") or p.get("terrain") == "sea"
        }
        countries = {str(c["tag"]).upper(): c for c in scen["countries"]}
        for m in MAJORS:
            c = countries[m]
            if not c.get("naval_power"):
                continue
            ports = []
            for pid, ot in owners.items():
                if ot != m:
                    continue
                p = base.get(pid) or {}
                if p.get("domain") == "coastal_land":
                    ports.append(pid)
                    continue
                neigh = adj.get(str(pid), [])
                if any(int(n) in sea for n in neigh):
                    ports.append(pid)
            self.assertTrue(ports, msg=f"naval major {m} has no port-eligible owned land")

    def test_gd_wiring_no_obsolete_demo_pids(self) -> None:
        spawner = (ROOT / "scripts" / "scenarios" / "ScenarioFactorySpawner.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn("resolve_industrial_provinces", spawner)
        self.assertIn("resolve_shipyard_provinces", spawner)
        self.assertIn("ScenarioFactorySpawner: majors", spawner)
        self.assertNotIn("FALLBACK_PORT_PROVINCES", spawner)
        loader = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("_resolve_factory_id_for_country", loader)
        self.assertIn("_print_industry_bootstrap_evidence", loader)
        self.assertIn("oob_%s_%s", loader)
        self.assertIn("bootstrap_line_on_factory", loader)
        self.assertIn("_run_oob_production_evidence_advance", loader)
        # obsolete demo pids for GER→2 must not be the assignment path
        self.assertNotIn('"GER": 2', loader)
        self.assertNotIn("demo_factory_pids", loader)


if __name__ == "__main__":
    unittest.main(verbosity=2)
