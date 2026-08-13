#!/usr/bin/env python3
"""Gates: multi-faction strategic AI product (major #9 / deferred AI first slice)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from multi_faction_strategic_ai_product import (  # noqa: E402
    MAJOR_TAGS,
    PRODUCT_STEPS,
    build_multi_faction_strategic_ai_product,
    execute_strategic_ai_step,
    multi_faction_strategic_ai_integrity,
    close_multi_faction_strategic_ai_product_loop,
    plan_faction_ai,
)
from gis_coastline_ingest import load_geometry_payload  # noqa: E402

GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"
WF = ROOT / "data" / "provinces_world_full"


class TestGis(unittest.TestCase):
    def test_ne_full_or_pilot_floor(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(
            1
            for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_seven_majors_board(self):
        p = build_multi_faction_strategic_ai_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("faction_count", 0)), 5)
        tags = [str(f.get("tag")) for f in (p.get("factions") or [])]
        self.assertGreaterEqual(len(set(tags)), 5)
        self.assertIn(str(p.get("top_faction")), list(MAJOR_TAGS) + tags)
        self.assertGreaterEqual(len(p.get("board_lines") or []), 5)
        self.assertGreaterEqual(len(p.get("day_rows") or []), 3)
        for s in PRODUCT_STEPS:
            e = execute_strategic_ai_step(s, 1)
            self.assertTrue(e.get("ok"))
        self.assertTrue(multi_faction_strategic_ai_integrity().get("ok"))
        self.assertTrue(close_multi_faction_strategic_ai_product_loop().get("ok"))

    def test_doctrine_shifts_top(self):
        eng = plan_faction_ai("ENG", province_id=2)
        ger = plan_faction_ai("GER", province_id=3)
        self.assertEqual(eng.get("tag"), "ENG")
        self.assertEqual(ger.get("tag"), "GER")
        self.assertIn(eng.get("top_domain"), ("combat", "fleet", "industry", "hh", "agent"))
        thin = build_multi_faction_strategic_ai_product(["GER", "FRA"])
        full = build_multi_faction_strategic_ai_product()
        self.assertGreaterEqual(float(full.get("score", 0)), float(thin.get("score", 0)) * 0.85)


class TestLive(unittest.TestCase):
    def test_composition_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("static func multi_faction_strategic_ai_product(", fmt)
        self.assertIn("static func plan_faction_ai(", fmt)
        self.assertIn("static func execute_strategic_ai_step(", fmt)
        start = fmt.find("static func multi_faction_strategic_ai_product(")
        body = fmt[start : start + 4500]
        for h in ("plan_faction_ai", "recommend_strategic_ai_step", "strategic_ai_scan"):
            self.assertIn(h, body, msg=h)
        plan_start = fmt.find("static func plan_faction_ai(")
        plan_body = fmt[plan_start : plan_start + 2500]
        self.assertIn("theater_command_product", plan_body)
        self.assertIn("faction_ai_doctrine", plan_body)
        self.assertNotIn("var score := 0.55", body)
        self.assertNotIn("var score := 0.55", plan_body)
        self.assertIn("func multi_faction_strategic_ai_product_live", mm)
        self.assertIn("func apply_multi_faction_strategic_ai_product", mm)
        self.assertIn("func apply_multi_faction_strategic_ai_product", gd)
        self.assertIn("func apply_strategic_ai_scan", gd)
        self.assertIn("func apply_strategic_ai_rank", gd)
        self.assertIn("func apply_strategic_ai_execute", gd)
        self.assertIn("Multi-faction strategic AI (major #9)", panel)
        self.assertIn("multi_faction_strategic_ai_product_live", panel)
        self.assertIn("strategic_ai_scan", panel)
        self.assertIn("build_multi_faction_strategic_ai_product_chip_bbcode", pi)
        self.assertIn("test_multi_faction_strategic_ai_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "multi-faction strategic ai",
            "strategic ai scan",
            "major #9",
            "strategic ai",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
