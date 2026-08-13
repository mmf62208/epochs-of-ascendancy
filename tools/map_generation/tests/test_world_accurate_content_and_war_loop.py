#!/usr/bin/env python3
"""Director D1/D2 pure tests: leaders, capitals/OOB, war-loop wiring on accurate IDs.

Drives shipped scenario/ownership/adjacency JSON + GD API surfaces — no reimplemented loaders.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from equipment_flow_product import (  # noqa: E402
    build_equipment_stock_reinforce_primary_command_product,
    stock_units_on_complete,
)
from industry_bootstrap import primary_land_design, template_base_production_days  # noqa: E402

D = ROOT / "data" / "provinces_world_accurate"
SCEN = ROOT / "data" / "scenarios" / "world_accurate.json"
LEADERS_ALIAS = ROOT / "data" / "leaders" / "historical_leaders_world_accurate.json"
LEADERS_1936 = ROOT / "data" / "leaders" / "historical_leaders_1936.json"
LM = ROOT / "scripts" / "leaders" / "LeaderManager.gd"
TM = ROOT / "scripts" / "technology" / "TechnologyManager.gd"
BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
HEADLESS = ROOT / "scripts" / "core" / "HeadlessWorldAccurateAssaultEntryTest.gd"
TEMPLATES = ROOT / "data" / "unit_templates"

# Real GIS edge: GER Baden-Baden → FRA Bas-Rhin (ownership 1936 + shared-edge adj)
GER_FROM = 710173
FRA_TO = 710739
MAJORS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL")


def _nbrs(adj: dict, pid: int) -> list[int]:
    raw = adj.get(str(pid)) or []
    out: list[int] = []
    for n in raw:
        if isinstance(n, dict):
            out.append(int(n.get("id") or n.get("to") or 0))
        else:
            out.append(int(n))
    return [x for x in out if x > 0]


class TestWorldAccurateD1Content(unittest.TestCase):
    def test_leaders_roster_resolves_for_world_accurate(self) -> None:
        self.assertTrue(LEADERS_ALIAS.is_file(), LEADERS_ALIAS)
        self.assertTrue(LEADERS_1936.is_file())
        alias = json.loads(LEADERS_ALIAS.read_text(encoding="utf-8"))
        leaders = alias.get("leaders") or []
        self.assertGreaterEqual(len(leaders), 50)
        tags = {str(L.get("country_tag") or L.get("tag") or "").upper() for L in leaders}
        for m in ("GER", "FRA", "ENG", "USA", "SOV"):
            self.assertIn(m, tags, msg=f"no leaders for {m}")
        lm = LM.read_text(encoding="utf-8")
        self.assertIn('"world_accurate"', lm)
        self.assertIn("HISTORICAL_LEADERS_1936_PATH", lm)
        # Chain entry maps world_accurate to 1936 roster paths
        self.assertRegex(
            lm,
            r'"world_accurate"\s*:\s*\[.*HISTORICAL_LEADERS_1936',
        )

    def test_starting_tech_aliases_world_accurate_to_1936(self) -> None:
        tm = TM.read_text(encoding="utf-8")
        self.assertIn('sn == "world_accurate"', tm)
        start = ROOT / "data" / "technology" / "starting" / "1936.json"
        self.assertTrue(start.is_file())

    def test_eight_major_capitals_land_owned_on_accurate_board(self) -> None:
        base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text())["provinces"]
        }
        own = json.loads((D / "province_ownership_1936.json").read_text()).get("owners") or {}
        sc = json.loads(SCEN.read_text(encoding="utf-8"))
        by_tag = {str(c["tag"]).upper(): c for c in sc["countries"]}
        for tag in MAJORS:
            self.assertIn(tag, by_tag)
            pid = int(by_tag[tag]["capital_province_id"])
            self.assertIn(pid, base, msg=f"{tag} capital {pid} missing")
            p = base[pid]
            terr = str(p.get("terrain", "")).lower()
            dom = str(p.get("domain", "land")).lower()
            self.assertNotIn(terr, ("sea", "ocean", "water", "lake"))
            self.assertNotIn(dom, ("sea", "strait", "ocean"))
            self.assertEqual(own.get(str(pid)), tag, msg=f"{tag} capital owner")

    def test_major_starting_oob_designs_have_templates(self) -> None:
        sc = json.loads(SCEN.read_text(encoding="utf-8"))
        by_tag = {str(c["tag"]).upper(): c for c in sc["countries"]}
        for tag in MAJORS:
            design = primary_land_design(by_tag[tag])
            self.assertTrue(design, msg=f"{tag} missing land design in starting_oob")
            path = TEMPLATES / f"{design}.json"
            self.assertTrue(path.is_file(), msg=path)
            days = template_base_production_days(json.loads(path.read_text()))
            self.assertGreater(days, 0.0)
            # Stageable neighborhood: capital has owned land or self
            own = json.loads((D / "province_ownership_1936.json").read_text())["owners"]
            cap = int(by_tag[tag]["capital_province_id"])
            owned = [int(k) for k, v in own.items() if v == tag]
            self.assertGreaterEqual(len(owned), 1, msg=f"{tag} no owned land")
            self.assertIn(cap, owned)


class TestWorldAccurateD2WarLoop(unittest.TestCase):
    def test_ger_fra_land_edge_on_accurate_adjacency(self) -> None:
        adj = json.loads((D / "province_adjacency.json").read_text()).get("adjacency") or {}
        own = json.loads((D / "province_ownership_1936.json").read_text()).get("owners") or {}
        self.assertEqual(own.get(str(GER_FROM)), "GER")
        self.assertEqual(own.get(str(FRA_TO)), "FRA")
        self.assertIn(FRA_TO, _nbrs(adj, GER_FROM))

    def test_battle_manager_assault_apis_and_headless_accurate_driver(self) -> None:
        bm = BM.read_text(encoding="utf-8")
        self.assertIn("func can_assault_province", bm)
        self.assertIn("func execute_province_assault", bm)
        self.assertIn("stationed_province_id", bm)
        self.assertTrue(HEADLESS.is_file(), HEADLESS)
        src = HEADLESS.read_text(encoding="utf-8")
        for needle in (
            "can_assault_province",
            "execute_province_assault",
            "provinces_world_accurate",
            str(GER_FROM),
            str(FRA_TO),
            "daily_formation_reinforce_from_stockpile",
        ):
            self.assertIn(needle, src, msg=needle)

    def test_equipment_stock_reinforce_product_on_accurate_capital_id(self) -> None:
        # GER capital on accurate board — product binds province_id into apply queue
        prod = build_equipment_stock_reinforce_primary_command_product(province_id=710300)
        self.assertTrue(prod.get("all_majors_ok") or prod.get("hooks_ok"))
        self.assertEqual(int(prod.get("province_id") or 0), 710300)
        self.assertGreaterEqual(int(prod.get("majors_ok_n") or 0), 1)
        # Production complete scale for land design still HOI-like tank=1 unit
        self.assertEqual(stock_units_on_complete("tank", 1), 1)
        self.assertEqual(stock_units_on_complete("truck", 1), 4)

    def test_world_accurate_scenario_stockpiles_seed_production_loop(self) -> None:
        sc = json.loads(SCEN.read_text(encoding="utf-8"))
        by_tag = {str(c["tag"]).upper(): c for c in sc["countries"]}
        ger = by_tag["GER"]
        stock = ger.get("starting_equipment_stockpile") or {}
        design = primary_land_design(ger)
        self.assertIn(design, stock)
        self.assertGreaterEqual(int(stock[design]), 1)
        # GD production sink still wired
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func bootstrap_line_on_factory", pm)
        self.assertIn("add_to_country_equipment_stockpile", pm)


if __name__ == "__main__":
    unittest.main(verbosity=2)
