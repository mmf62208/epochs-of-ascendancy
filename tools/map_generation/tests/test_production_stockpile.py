#!/usr/bin/env python3
"""Pure tests: factory→line→stockpile production loop for world_full OOB majors."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from industry_bootstrap import (  # noqa: E402
    min_evidence_advance_days,
    primary_land_design,
    stockpile_delta,
    template_base_production_days,
)

SCEN = ROOT / "data" / "scenarios" / "world_full.json"
TEMPLATES = ROOT / "data" / "unit_templates"
MAJORS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP")
# Must match ScenarioLoader.OOB_PRODUCTION_EVIDENCE_DAYS
EVIDENCE_DAYS = 100.0


class TestStockpileMath(unittest.TestCase):
    def test_min_evidence_covers_slow_tanks(self) -> None:
        # somua 68d mass layer: ~59 needed / 0.95 output ≈ 62 + margin
        need = min_evidence_advance_days([68.0, 62.0, 35.0])
        self.assertLessEqual(need, EVIDENCE_DAYS)
        self.assertGreater(need, 50.0)

    def test_stockpile_delta_detects_growth(self) -> None:
        before = {"panzer_iii_j_medium": 1200}
        after = {"panzer_iii_j_medium": 1202, "bf109g_fighter": 100}
        d = stockpile_delta(before, after)
        self.assertEqual(d["panzer_iii_j_medium"], 2)
        self.assertEqual(d["bf109g_fighter"], 100)
        self.assertEqual(stockpile_delta(before, before), {})


class TestShippedWorldFullDesigns(unittest.TestCase):
    def test_major_primary_land_templates_exist_and_fit_evidence_window(self) -> None:
        scen = json.loads(SCEN.read_text(encoding="utf-8"))
        countries = {str(c["tag"]).upper(): c for c in scen["countries"]}
        days_list = []
        for m in MAJORS:
            self.assertIn(m, countries)
            design = primary_land_design(countries[m])
            self.assertTrue(design, msg=f"{m} missing land design")
            path = TEMPLATES / f"{design}.json"
            self.assertTrue(path.is_file(), msg=f"{m} template missing: {design}")
            tpl = json.loads(path.read_text(encoding="utf-8"))
            days = template_base_production_days(tpl)
            days_list.append(days)
            self.assertGreater(days, 0.0)
            self.assertLessEqual(days, 90.0, msg=f"{m} {design} days={days} too long for short evidence")
        need = min_evidence_advance_days(days_list)
        self.assertLessEqual(
            need,
            EVIDENCE_DAYS,
            msg=f"evidence window {EVIDENCE_DAYS}d < required {need:.1f}d for majors {days_list}",
        )


class TestGdWiring(unittest.TestCase):
    def test_production_manager_bootstrap_and_stockpile_sink(self) -> None:
        pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        self.assertIn("func bootstrap_line_on_factory", pm)
        self.assertIn("production_completed.emit(line_id, template_id, 1)", pm)
        self.assertIn("add_to_country_equipment_stockpile", pm)
        self.assertIn("func advance_days", pm)
        self.assertIn("func get_country_equipment_stockpile", pm)
        # unit_completed → stockpile (not only PP path)
        self.assertIn("Deposit completed unit into country stockpile", pm)
        # bootstrap seeds tooling so first units finish inside evidence window
        self.assertIn("tooling_efficiency", pm)

    def test_scenario_loader_evidence_advance(self) -> None:
        loader = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("bootstrap_line_on_factory", loader)
        self.assertIn("_run_oob_production_evidence_advance", loader)
        self.assertIn("OOB_PRODUCTION_EVIDENCE_DAYS", loader)
        # Evidence uses real daily tick path (TimeManager day entry), not only ad-hoc advance_days
        self.assertIn("Daily production stockpile evidence", loader)
        self.assertIn("daily_production_tick", loader)
        self.assertIn("headless", loader)
        # must not run long advance on graphical F5 by default
        self.assertIn('DisplayServer.get_name() == "headless"', loader)
        # constant matches pure test gate
        self.assertIn("100.0", loader)
        self.assertNotIn("advance_days(45.0)", loader)

    def test_headless_factory_stockpile_test_drives_shipped_apis(self) -> None:
        """GD headless entry must call real ProductionManager/FactoryManager APIs (not reimplement)."""
        path = ROOT / "scripts" / "core" / "HeadlessFactoryStockpileTest.gd"
        self.assertTrue(path.is_file(), msg="HeadlessFactoryStockpileTest.gd missing")
        src = path.read_text(encoding="utf-8")
        for needle in (
            "advance_days",
            "bootstrap_line_on_factory",
            "get_country_equipment_stockpile",
            "register_factory",
            "create_line",
            "empty",
            "unassigned",
            '_autoload("ProductionManager")',
            '_autoload("FactoryManager")',
        ):
            self.assertIn(needle, src, msg=f"missing shipped API usage: {needle}")
        # ProductionLineTest suite also includes the same stockpile advance gate
        plt = (ROOT / "scripts" / "core" / "ProductionLineTest.gd").read_text(encoding="utf-8")
        self.assertIn("_test_factory_line_stockpile_advance", plt)
        self.assertIn("bootstrap_line_on_factory", plt)
        self.assertIn("get_country_equipment_stockpile", plt)


if __name__ == "__main__":
    unittest.main(verbosity=2)
