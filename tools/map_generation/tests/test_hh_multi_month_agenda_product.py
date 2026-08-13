#!/usr/bin/env python3
"""Gates: HH multi-month agenda product (major #5)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from hh_multi_month_agenda_product import (  # noqa: E402
    MONTH_STEPS,
    build_hh_multi_month_agenda_product,
    execute_hh_month_step,
    recommend_hh_month_step,
    filter_trail_by_class,
    hh_multi_month_agenda_product_integrity,
    close_hh_multi_month_agenda_product_loop,
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
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product_three_steps(self):
        p = build_hh_multi_month_agenda_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("trail_count", 0)), 3)
        self.assertGreaterEqual(int(p.get("months_covered", 0)), 2)
        self.assertGreaterEqual(len(p.get("class_order") or []), 2)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 3)
        self.assertIn("recommendation", p)
        steps = [str(r.get("step")) for r in (p.get("day_rows") or [])]
        self.assertEqual(steps, list(MONTH_STEPS))
        aids = [str(a.get("action_id")) for a in (p.get("actions") or [])]
        self.assertIn("hh_multi_month_agenda_product", aids)

    def test_filter_execute_recommend(self):
        p = build_hh_multi_month_agenda_product()
        sab = build_hh_multi_month_agenda_product(action_class_filter="sabotage")
        self.assertGreaterEqual(len(sab.get("trail") or []), 1)
        for s in MONTH_STEPS:
            e = execute_hh_month_step(s, 2)
            self.assertEqual(str(e.get("step")), s)
            self.assertTrue(e.get("ok"))
        rec = recommend_hh_month_step(0)
        self.assertEqual(rec.get("step"), "trail_board")
        filtered = filter_trail_by_class(p.get("trail") or [], "sabotage")
        self.assertTrue(all(str(e.get("action_class")) == "sabotage" for e in filtered))

    def test_integrity_close(self):
        self.assertTrue(hh_multi_month_agenda_product_integrity().get("ok"))
        loop = close_hh_multi_month_agenda_product_loop()
        self.assertTrue(loop.get("ok"))


class TestLive(unittest.TestCase):
    def test_composition_and_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("static func hh_multi_month_agenda_product(", fmt)
        self.assertIn("static func recommend_hh_month_step(", fmt)
        self.assertIn("static func execute_hh_month_step(", fmt)
        start = fmt.find("static func hh_multi_month_agenda_product(")
        body = fmt[start : start + 5500]
        for h in (
            "hh_agenda_product_screen",
            "hh_agenda_player_path",
            "format_hh_quarterly_rollup_from_trail",
            "format_hh_agenda_commitments_from_trail",
            "filter_trail_by_class",
        ):
            self.assertIn(h, body, msg=h)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func hh_multi_month_agenda_product_live", mm)
        self.assertIn("func apply_hh_month_step_for_province", mm)
        self.assertIn("func apply_hh_multi_month_agenda_product", mm)
        self.assertIn("func apply_hh_multi_month_agenda_product", gd)
        self.assertIn("func apply_hh_month_trail_board", gd)
        self.assertIn("func apply_hh_month_brief", gd)
        self.assertIn("func apply_hh_month_quarterly_counter", gd)
        self.assertIn("format_hh_multi_month_agenda_product_plain", gd)
        sec_i = panel.find("func _rebuild_hh_section")
        sec = panel[sec_i : sec_i + 2800]
        self.assertIn("HH multi-month agenda product (major #5)", sec)
        self.assertIn("hh_multi_month_agenda_product_live", sec)
        self.assertIn("hh_month_trail_board", sec)
        self.assertIn("hh_month_brief", sec)
        self.assertIn("hh_month_quarterly_counter", sec)
        self.assertGreaterEqual(panel.count("_rebuild_hh_section"), 2)
        self.assertIn("build_hh_multi_month_agenda_product_chip_bbcode", pi)
        self.assertIn("test_hh_multi_month_agenda_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "hh multi-month agenda",
            "hh month trail",
            "hh month brief",
            "major #5",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
