#!/usr/bin/env python3
"""Pure: seized factory production credits attacker stockpile wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureSeizedFactoryProductionWiring(unittest.TestCase):
    def test_line_owner_from_factory_owner(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func _get_line_owner_tag", pm)
        self.assertIn("return factory.owner_tag", pm)
        self.assertIn("func bootstrap_line_on_factory", pm)
        self.assertIn("func advance_days", pm)
        self.assertIn("add_to_country_equipment_stockpile(owner_tag, design_id, count)", pm)

    def test_capture_non_skip_factory_path(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("update_province_owner(target_pid, attacker_tag, attacker_tag, false)", bm)
        mm = (ROOT / "scripts" / "map" / "MapManager.gd").read_text(encoding="utf-8")
        self.assertIn("FactoryManager.capture_province_factories", mm)
        fm = (ROOT / "scripts" / "production" / "FactoryManager.gd").read_text(encoding="utf-8")
        self.assertIn("f.is_seized = true", fm)
        self.assertIn("f.owner_tag = new_owner", fm)

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

    def test_headless_drives_capture_bootstrap_advance_stockpile(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCaptureSeizedFactoryProductionTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "apply_combat_outcome",
            "execute_province_assault",
            "register_factory",
            "bootstrap_line_on_factory",
            "advance_days",
            "get_country_equipment_stockpile",
            "is_seized",
            "daily_formation_reinforce_from_stockpile",
            "9276",
            "9281",
            "cv33_tankette",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
