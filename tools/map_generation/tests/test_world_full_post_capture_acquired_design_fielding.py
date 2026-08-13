#!/usr/bin/env python3
"""Pure: post-capture acquired foreign design may-use + produce + field wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureAcquiredDesignFieldingWiring(unittest.TestCase):
    def test_may_use_consults_acquisition(self) -> None:
        dm = (ROOT / "scripts" / "production" / "DesignManager.gd").read_text(encoding="utf-8")
        self.assertIn("func country_may_use_design", dm)
        self.assertIn("func _country_may_use_design", dm)
        self.assertIn("return has_acquired_design(tag, design_id)", dm)
        self.assertIn("func has_acquired_design", dm)
        self.assertIn("try_grant_captured_designs_from_factory", dm)

    def test_produce_owner_from_factory_and_stockpile(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func bootstrap_line_on_factory", pm)
        self.assertIn("func advance_days", pm)
        self.assertIn("return factory.owner_tag", pm)
        self.assertIn("add_to_country_equipment_stockpile(owner_tag, design_id, count)", pm)
        self.assertIn("func request_equipment_for_unit", pm)
        self.assertIn("func get_formation_equipment_combat_stats", pm)
        self.assertIn("has_shortages", pm)

    def test_capture_non_skip_factory_path(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("update_province_owner(target_pid, attacker_tag, attacker_tag, false)", bm)
        fm = (ROOT / "scripts" / "production" / "FactoryManager.gd").read_text(encoding="utf-8")
        self.assertIn("try_grant_captured_designs_from_factory", fm)

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

    def test_headless_drives_all_three_elements(self) -> None:
        path = (
            ROOT
            / "scripts"
            / "core"
            / "HeadlessWorldFullPostCaptureAcquiredDesignFieldingTest.gd"
        )
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "country_may_use_design",
            "has_acquired_design",
            "bootstrap_line_on_factory",
            "advance_days",
            "get_country_equipment_stockpile",
            "request_equipment_for_unit",
            "get_formation_equipment_combat_stats",
            "has_shortages",
            "somua_s35_medium",
            "apply_combat_outcome",
            "execute_province_assault",
            "daily_formation_reinforce_from_stockpile",
            "9276",
            "9281",
            "element1",
            "element2",
            "element3",
        ):
            self.assertIn(needle, src, msg=needle)


if __name__ == "__main__":
    unittest.main(verbosity=2)
