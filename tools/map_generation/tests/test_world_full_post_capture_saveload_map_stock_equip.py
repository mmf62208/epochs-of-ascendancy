#!/usr/bin/env python3
"""Pure: post-capture map owner + stockpile + unit equip save/load wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureSaveLoadMapStockEquipWiring(unittest.TestCase):
    def test_saveload_map_serialize_owner_controller(self) -> None:
        sl = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        self.assertIn("func _serialize_map_state", sl)
        self.assertIn("func _apply_map_state", sl)
        self.assertIn("owner_tag", sl)
        self.assertIn("controller_tag", sl)
        self.assertIn("update_province_owner", sl)
        self.assertIn("func validate_map_save_payload", sl)

    def test_production_saves_stockpiles_and_unit_equip(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_save_data", pm)
        self.assertIn("func apply_save_data", pm)
        self.assertIn("country_equipment_stockpiles", pm)
        self.assertIn("unit_equipment_stock", pm)
        self.assertIn("func set_unit_equipment_stock", pm)
        self.assertIn("func get_formation_equipment_combat_stats", pm)

    def test_capture_non_skip_owner_update(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("update_province_owner(target_pid, attacker_tag, attacker_tag, false)", bm)

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

    def test_headless_drives_capture_and_saveload(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCaptureSaveLoadMapStockEquipTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "_serialize_map_state",
            "_apply_map_state",
            "get_save_data",
            "apply_save_data",
            "country_equipment_stockpile",
            "set_unit_equipment_stock",
            "apply_combat_outcome",
            "execute_province_assault",
            "9276",
            "9281",
            "e1",
            "e2",
            "e3",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
