#!/usr/bin/env python3
"""Pure: world_full assault entry wiring + major-major land adjacency fixture."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281  # GER→FRA capital edge


class TestWorldFullAssaultWiring(unittest.TestCase):
    def test_battle_manager_stationed_oob_lookup(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func can_assault_province", bm)
        self.assertIn("func execute_province_assault", bm)
        self.assertIn("_land_formations_stationed_at", bm)
        self.assertIn("stationed_province_id", bm)
        sm = (ROOT / "scripts" / "supply" / "SupplyManager.gd").read_text(encoding="utf-8")
        self.assertIn("stationed_province_id", sm)
        self.assertIn("TYPE_DIVISION", sm)

    def test_world_full_ger_fra_land_edge(self) -> None:
        adj = json.loads((WF / "province_adjacency.json").read_text()).get("adjacency") or {}
        neigh = [int(x) for x in adj.get(str(FROM_PID), [])]
        self.assertIn(TO_PID, neigh, msg=f"{FROM_PID} should neighbor {TO_PID}")
        owners = {
            int(p["id"]): str(p.get("owner_tag") or "").upper()
            for p in json.loads(SCEN.read_text()).get("provinces") or []
            if isinstance(p, dict)
        }
        self.assertEqual(owners.get(FROM_PID), "GER")
        self.assertEqual(owners.get(TO_PID), "FRA")

    def test_headless_drives_public_assault_apis(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessWorldFullAssaultEntryTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "can_assault_province",
            "execute_province_assault",
            "daily_formation_reinforce_from_stockpile",
            "apply_combat_equipment_loss",
            "9276",
            "9281",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
