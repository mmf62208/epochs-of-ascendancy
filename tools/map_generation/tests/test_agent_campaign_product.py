#!/usr/bin/env python3
"""Gates: agent campaign product (major #6 / high-priority) + medium-tank progress evidence wiring."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from agent_campaign_product import (  # noqa: E402
    PRODUCT_STEPS,
    build_agent_campaign_product,
    execute_agent_product_step,
    recommend_agent_product_step,
    agent_campaign_product_integrity,
    close_agent_campaign_product_loop,
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


class TestPure(unittest.TestCase):
    def test_product_three_steps(self):
        p = build_agent_campaign_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("signal_count", 0)), 2)
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 3)
        self.assertIn("recommendation", p)
        steps = [str(r.get("step")) for r in (p.get("day_rows") or [])]
        self.assertEqual(steps, list(PRODUCT_STEPS))
        aids = [str(a.get("action_id")) for a in (p.get("actions") or [])]
        self.assertIn("agent_campaign_product", aids)

    def test_execute_and_signal_shift(self):
        for s in PRODUCT_STEPS:
            e = execute_agent_product_step(s, 2)
            self.assertEqual(str(e.get("step")), s)
            self.assertTrue(e.get("ok"))
        rich = build_agent_campaign_product(
            [
                {"action_class": "sabotage", "influence": 0.7, "province_id": 1, "active": True},
                {"action_class": "infiltration", "influence": 0.65, "province_id": 2, "active": True},
                {"action_class": "economic_pressure", "influence": 0.6, "province_id": 3, "active": True},
            ]
        )
        thin = build_agent_campaign_product(
            [{"action_class": "sabotage", "influence": 0.25, "province_id": 1, "active": True}]
        )
        self.assertGreater(float(rich.get("score", 0)), float(thin.get("score", 0)))
        rec = recommend_agent_product_step(0)
        self.assertEqual(rec.get("step"), "board")
        empty = build_agent_campaign_product([])
        self.assertTrue(empty.get("empty"))

    def test_integrity_close(self):
        self.assertTrue(agent_campaign_product_integrity().get("ok"))
        loop = close_agent_campaign_product_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreater(float(loop.get("signal_shift", 0)), 0.01)


class TestLive(unittest.TestCase):
    def test_composition_and_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        sl = GD_SL.read_text(encoding="utf-8")
        self.assertIn("static func agent_campaign_product(", fmt)
        self.assertIn("static func recommend_agent_product_step(", fmt)
        self.assertIn("static func execute_agent_product_step(", fmt)
        start = fmt.find("static func agent_campaign_product(")
        body = fmt[start : start + 5500]
        for h in (
            "agent_ai_board",
            "agent_ai_decision_quality",
            "plan_agent_coverage",
            "agent_campaign_response",
            "agent_auto_dispatch_day",
        ):
            self.assertIn(h, body, msg=h)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func agent_campaign_product_live", mm)
        self.assertIn("func apply_agent_product_step_for_province", mm)
        self.assertIn("func apply_agent_campaign_product", mm)
        self.assertIn("func apply_agent_campaign_product", gd)
        self.assertIn("func apply_agent_product_board", gd)
        self.assertIn("func apply_agent_product_dispatch", gd)
        self.assertIn("func apply_agent_product_counterplay", gd)
        self.assertIn("format_agent_campaign_product_plain", gd)
        sec_i = panel.find("func _rebuild_agent_section")
        sec = panel[sec_i : sec_i + 2500]
        self.assertIn("Agent campaign product (major #6)", sec)
        self.assertIn("agent_campaign_product_live", sec)
        self.assertIn("agent_product_board", sec)
        self.assertIn("agent_product_dispatch", sec)
        self.assertIn("agent_product_counterplay", sec)
        self.assertGreaterEqual(panel.count("_rebuild_agent_section"), 2)
        self.assertIn("build_agent_campaign_product_chip_bbcode", pi)
        self.assertIn("_print_medium_tank_line_progress_evidence", sl)
        self.assertIn("Medium-tank OOB progress evidence", sl)
        self.assertIn("test_agent_campaign_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "agent campaign product",
            "agent product board",
            "agent product dispatch",
            "major #6",
            "medium-tank oob progress",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
