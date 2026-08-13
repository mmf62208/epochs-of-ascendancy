#!/usr/bin/env python3
"""Gates for world_full 1936 political ownership (playable political map)."""
from __future__ import annotations

import json
import sys
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from assign_world_ownership_1936 import (  # noqa: E402
    MAJORS,
    MAJOR_HOME_THEATERS,
    WATER_DOMAINS,
    assign_ownership,
    quality_gates,
    load_provinces,
    DEFAULT_CAPITALS,
)

WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"


class TestOwnershipPure(unittest.TestCase):
    def test_assign_on_live_board(self) -> None:
        provinces, cents = load_provinces(WF)
        scen = json.loads(SCEN.read_text())
        tags = [str(c["tag"]).upper() for c in scen["countries"]]
        capitals = {t: DEFAULT_CAPITALS[t] for t in tags if t in DEFAULT_CAPITALS}
        result = assign_ownership(provinces, cents, capitals, tags)
        gates = quality_gates(result, tags, provinces)
        self.assertTrue(gates["pass"], msg=gates)
        self.assertGreaterEqual(gates["land_coverage"], 0.95)
        self.assertEqual(gates["water_owned"], 0)
        for m in MAJORS:
            self.assertGreaterEqual(gates["by_tag_land"].get(m, 0), 5, msg=m)
        for t in tags:
            self.assertGreaterEqual(gates["by_tag_land"].get(t, 0), 1, msg=t)
            self.assertEqual(result["owners"].get(str(capitals[t])), t)

    def test_tiny_fixture_water_unowned(self) -> None:
        provinces = [
            {"id": 1, "domain": "land", "theater": "europe_core", "name": "A"},
            {"id": 2, "domain": "sea", "theater": "sea", "name": "Ocean"},
            {"id": 3, "domain": "land", "theater": "europe_core", "name": "B"},
        ]
        cents = {1: (0.0, 0.0), 2: (50.0, 50.0), 3: (1.0, 0.0)}
        caps = {"GER": 1, "FRA": 3}
        result = assign_ownership(provinces, cents, caps, ["GER", "FRA"])
        self.assertEqual(result["owners"]["1"], "GER")
        self.assertEqual(result["owners"]["3"], "FRA")
        self.assertEqual(result["owners"]["2"], "")
        self.assertEqual(result["stats"]["water_owned"], 0)


class TestShippedScenarioOwnership(unittest.TestCase):
    def test_world_full_provinces_array_and_capitals(self) -> None:
        scen = json.loads(SCEN.read_text())
        self.assertIsInstance(scen.get("provinces"), list)
        self.assertGreaterEqual(len(scen["provinces"]), 1000)
        by_id = {int(p["id"]): p for p in scen["provinces"]}
        base = {int(p["id"]): p for p in json.loads((WF / "provinces_base.json").read_text())["provinces"]}
        land_ids = [pid for pid, p in base.items() if str(p.get("domain")) not in WATER_DOMAINS]
        water_ids = [pid for pid, p in base.items() if str(p.get("domain")) in WATER_DOMAINS]
        owned_land = sum(1 for pid in land_ids if str((by_id.get(pid) or {}).get("owner_tag") or "").strip())
        self.assertGreaterEqual(owned_land / max(1, len(land_ids)), 0.95)
        # Water should not appear as owned in scenario overrides (we skip water entries)
        for pid in water_ids:
            if pid in by_id:
                self.assertFalse(str(by_id[pid].get("owner_tag") or "").strip())

        tags = [str(c["tag"]).upper() for c in scen["countries"]]
        counts = Counter(str(p.get("owner_tag") or "").upper() for p in scen["provinces"])
        for t in tags:
            self.assertGreaterEqual(counts.get(t, 0), 1, msg=f"tag {t} has no land in scenario overrides")
        for m in MAJORS:
            self.assertGreaterEqual(counts.get(m, 0), 5, msg=m)

        for c in scen["countries"]:
            tag = str(c["tag"]).upper()
            cap = int(c["capital_province_id"])
            self.assertIn(cap, base, msg=f"{tag} capital {cap} missing from base")
            self.assertNotIn(str(base[cap].get("domain")), WATER_DOMAINS)
            self.assertEqual(str((by_id.get(cap) or {}).get("owner_tag") or "").upper(), tag)

        # Theater bias: majors not all piled on one continent
        for m in ("GER", "USA", "JAP"):
            homes = MAJOR_HOME_THEATERS[m]
            home_n = 0
            total = 0
            for p in scen["provinces"]:
                if str(p.get("owner_tag") or "").upper() != m:
                    continue
                total += 1
                bp = base.get(int(p["id"]))
                if bp and str(bp.get("theater") or "") in homes:
                    home_n += 1
            self.assertGreater(total, 0)
            self.assertGreaterEqual(home_n / total, 0.35, msg=f"{m} home_share {home_n}/{total}")

    def test_payload_file_matches_scenario_owners(self) -> None:
        pay_path = WF / "province_ownership_1936.json"
        self.assertTrue(pay_path.exists())
        pay = json.loads(pay_path.read_text())
        scen = json.loads(SCEN.read_text())
        scen_owners = {str(p["id"]): str(p["owner_tag"]).upper() for p in scen["provinces"]}
        for pid, tag in scen_owners.items():
            self.assertEqual(str(pay["owners"].get(pid) or "").upper(), tag)
        self.assertTrue((pay.get("gates") or {}).get("pass") or pay.get("stats", {}).get("land_coverage", 0) >= 0.95)

    def test_scenario_loader_applies_array_path(self) -> None:
        """Structural: ScenarioLoader iterates data['provinces'] as Array of dicts with owner_tag."""
        gd = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn('p.owner_tag = str(p_data.get("owner_tag"', gd)
        self.assertIn('for p_data in data["provinces"]', gd)
        scen = json.loads(SCEN.read_text())
        self.assertIsInstance(scen["provinces"], list)
        self.assertIn("owner_tag", scen["provinces"][0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
