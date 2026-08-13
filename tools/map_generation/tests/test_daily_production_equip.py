#!/usr/bin/env python3
"""Pure/static tests: daily production tick wiring + formation equip-on-load for world_full."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from industry_bootstrap import primary_land_design  # noqa: E402

SCEN = ROOT / "data" / "scenarios" / "world_full.json"
MAJORS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP")


class TestDailyTickWiring(unittest.TestCase):
    def test_daily_production_tick_uses_advance_days(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func daily_production_tick", pm)
        self.assertIn("func _on_game_day_advanced", pm)
        self.assertIn("game_day_advanced", pm)
        # Body of daily_production_tick must call advance_days (stockpile path)
        idx = pm.find("func daily_production_tick")
        self.assertGreaterEqual(idx, 0)
        slice_ = pm[idx : idx + 280]
        self.assertIn("advance_days", slice_)
        # Still has PP path for direct callers
        self.assertIn("func advance_production", pm)

    def test_headless_daily_test_drives_shipped_apis(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessDailyProductionStockpileTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        for needle in (
            "daily_production_tick",
            "bootstrap_line_on_factory",
            "get_country_equipment_stockpile",
            "register_factory",
            "empty",
            "unassigned",
        ):
            self.assertIn(needle, src, msg=needle)


class TestEquipOnLoadWiring(unittest.TestCase):
    def test_scenario_loader_equip_helpers(self) -> None:
        loader = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("_equip_formations_from_country_stockpiles", loader)
        self.assertIn("_resolve_formation_equip_design", loader)
        self.assertIn("Formation equip (land from stockpile)", loader)
        self.assertIn("daily_production_tick", loader)
        self.assertIn("Daily production stockpile evidence", loader)
        self.assertIn("Formation equip evidence", loader)

    def test_majors_primary_land_in_starting_stockpile(self) -> None:
        scen = json.loads(SCEN.read_text(encoding="utf-8"))
        for c in scen["countries"]:
            tag = str(c.get("tag", "")).upper()
            if tag not in MAJORS:
                continue
            design = primary_land_design(c)
            self.assertTrue(design, msg=f"{tag} no land design")
            stock = c.get("starting_equipment_stockpile") or c.get("starting_stockpile") or {}
            self.assertIn(design, stock, msg=f"{tag} stockpile missing {design}")
            self.assertGreater(int(stock[design]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
