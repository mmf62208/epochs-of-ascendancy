#!/usr/bin/env python3
"""Gates: inspector decision (#7) + theater command (#8) products + medium complete window."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from inspector_decision_product import (  # noqa: E402
    PRODUCT_STEPS as INSP_STEPS,
    build_inspector_decision_product,
    execute_inspector_product_step,
    inspector_decision_product_integrity,
    close_inspector_decision_product_loop,
)
from theater_command_product import (  # noqa: E402
    PRODUCT_STEPS as TH_STEPS,
    build_theater_command_product,
    execute_theater_command_step,
    theater_command_product_integrity,
    close_theater_command_product_loop,
)
from gis_coastline_ingest import load_geometry_payload  # noqa: E402

GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"
WF = ROOT / "data" / "provinces_world_full"


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestInspectorPure(unittest.TestCase):
    def test_product_collapse(self):
        p = build_inspector_decision_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("primary_count", 0)), 2)
        self.assertGreaterEqual(int(p.get("hidden", 0)), 2)
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        for s in INSP_STEPS:
            e = execute_inspector_product_step(s, 1)
            self.assertTrue(e.get("ok"))
        self.assertTrue(inspector_decision_product_integrity().get("ok"))
        self.assertTrue(close_inspector_decision_product_loop().get("ok"))


class TestTheaterPure(unittest.TestCase):
    def test_product_domains(self):
        p = build_theater_command_product(1)
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("domain_count", 0)), 4)
        self.assertGreaterEqual(len(p.get("strip_lines") or []), 4)
        self.assertIn(str(p.get("top_domain")), {"combat", "fleet", "industry", "hh", "agent"})
        for s in TH_STEPS:
            e = execute_theater_command_step(s, 1)
            self.assertTrue(e.get("ok"))
        self.assertTrue(theater_command_product_integrity().get("ok"))
        self.assertTrue(close_theater_command_product_loop().get("ok"))


class TestLive(unittest.TestCase):
    def test_composition_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        sl = GD_SL.read_text(encoding="utf-8")
        self.assertIn("static func inspector_decision_product(", fmt)
        self.assertIn("static func theater_command_product(", fmt)
        start = fmt.find("static func inspector_decision_product(")
        body = fmt[start : start + 4000]
        for h in ("budget_product_depth_chips", "execution_decision_strip", "campaign_decision_strip"):
            self.assertIn(h, body, msg=h)
        self.assertNotIn("var score := 0.55", body)
        tstart = fmt.find("static func theater_command_product(")
        tbody = fmt[tstart : tstart + 4500]
        for h in (
            "multi_phase_combat_product",
            "fleet_multi_day_autonomy_product",
            "medium_tank_oob_product",
            "hh_multi_month_agenda_product",
            "agent_campaign_product",
        ):
            self.assertIn(h, tbody, msg=h)
        # Priorities for major products
        self.assertIn('inspector_decision_product":106', fmt.replace(" ", ""))
        self.assertIn("func inspector_decision_product_live", mm)
        self.assertIn("func theater_command_product_live", mm)
        self.assertIn("func apply_inspector_decision_product", gd)
        self.assertIn("func apply_theater_command_product", gd)
        self.assertIn("Theater command product (major #8)", panel)
        self.assertIn("Inspector decision product (major #7)", panel)
        self.assertIn("theater_command_product_live", panel)
        self.assertIn("inspector_decision_product_live", panel)
        self.assertIn("build_inspector_decision_product_chip_bbcode", pi)
        self.assertIn("build_theater_command_product_chip_bbcode", pi)
        self.assertIn("EOA_MEDIUM_OOB_EVIDENCE_DAYS", sl)
        self.assertIn("_run_medium_complete_window_evidence", sl)
        self.assertIn("test_inspector_theater_command_products.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "inspector decision product",
            "theater command product",
            "major #7",
            "major #8",
            "medium complete window",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
