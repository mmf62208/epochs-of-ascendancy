#!/usr/bin/env python3
"""Pure: post-load conquest loop — execute assault, seized prod, field acquired design."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCapturePostLoadConquestLoopWiring(unittest.TestCase):
    def test_managers_save_conquest_state(self) -> None:
        dm = (ROOT / "scripts" / "production" / "DesignManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_save_data", dm)
        self.assertIn("func apply_save_data", dm)
        self.assertIn("has_acquired_design", dm)
        self.assertIn("country_may_use_design", dm)
        fm = (ROOT / "scripts" / "production" / "FactoryManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_save_data", fm)
        self.assertIn("func apply_save_data", fm)
        self.assertIn("capture_province_factories", fm)
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn('"design_id"', lm)
        self.assertIn("stationed_province_id", lm)

    def test_production_and_combat_apis(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func bootstrap_line_on_factory", pm)
        self.assertIn("func advance_days", pm)
        self.assertIn("func request_equipment_for_unit", pm)
        self.assertIn("func get_formation_equipment_combat_stats", pm)
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func execute_province_assault", bm)
        self.assertIn("func can_assault_province", bm)
        sl = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        self.assertIn("func _serialize_map_state", sl)
        self.assertIn("func _apply_map_state", sl)

    def test_world_full_edge_ownership(self) -> None:
        adj = json.loads((WF / "province_adjacency.json").read_text()).get("adjacency") or {}
        self.assertIn(TO_PID, [int(x) for x in adj.get(str(FROM_PID), [])])
        owners = {
            int(p["id"]): str(p.get("owner_tag") or "").upper()
            for p in json.loads(SCEN.read_text()).get("provinces") or []
            if isinstance(p, dict)
        }
        self.assertEqual(owners.get(FROM_PID), "GER")
        self.assertEqual(owners.get(TO_PID), "FRA")

    def test_headless_drives_postload_conquest_loop(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCapturePostLoadConquestLoopTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "_serialize_map_state",
            "_apply_map_state",
            "get_save_data",
            "apply_save_data",
            "execute_province_assault",
            "bootstrap_line_on_factory",
            "advance_days",
            "has_acquired_design",
            "country_may_use_design",
            "request_equipment_for_unit",
            "get_formation_equipment_combat_stats",
            "design_id",
            "9276",
            "9281",
            "e1",
            "e2",
            "e3",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
