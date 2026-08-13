#!/usr/bin/env python3
"""Gates: save-browser campaign product (major #4) + major #2 sequence wiring."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from save_browser_campaign_product import (  # noqa: E402
    build_save_browser_campaign_product,
    execute_save_browser_action,
    recommend_resume_slot,
    recommend_checkpoint_slot,
    save_browser_campaign_product_integrity,
    close_save_browser_campaign_product_loop,
)
from gis_coastline_ingest import load_geometry_payload  # noqa: E402

GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
CI = ROOT / "tools" / "run_map_ci.sh"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
WF = ROOT / "data" / "provinces_world_full"


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product_resume_checkpoint(self):
        p = build_save_browser_campaign_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("count", 0)), 5)
        self.assertGreaterEqual(int(p.get("occupied_count", 0)), 1)
        self.assertFalse((p.get("resume") or {}).get("empty"))
        self.assertEqual(str((p.get("checkpoint") or {}).get("slot")), "autosave")
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 3)
        aids = [str(a.get("action_id")) for a in (p.get("actions") or [])]
        self.assertIn("save_browser_campaign_product", aids)

    def test_execute_actions(self):
        rs = execute_save_browser_action("resume")
        self.assertTrue(rs.get("ok"))
        self.assertTrue(str(rs.get("action_id", "")).startswith("load_slot:"))
        self.assertEqual(rs.get("api"), "load_game_detailed")
        cp = execute_save_browser_action("checkpoint")
        self.assertTrue(cp.get("ok"))
        self.assertEqual(cp.get("slot"), "autosave")
        self.assertEqual(cp.get("api"), "save_game_detailed")
        blocked = execute_save_browser_action("load_slot:autosave")
        self.assertFalse(blocked.get("ok"))

    def test_recommend_helpers(self):
        rows = [
            {"slot": "a", "occupied": True, "can_load": True, "metadata": {"timestamp": "1"}},
            {"slot": "b", "occupied": True, "can_load": True, "metadata": {"timestamp": "9"}},
            {"slot": "autosave", "occupied": False, "can_save": True},
        ]
        r = recommend_resume_slot(rows)
        self.assertEqual(r.get("slot"), "b")
        c = recommend_checkpoint_slot(rows)
        self.assertEqual(c.get("slot"), "autosave")

    def test_integrity_close(self):
        self.assertTrue(save_browser_campaign_product_integrity().get("ok"))
        self.assertTrue(close_save_browser_campaign_product_loop().get("ok"))


class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("static func save_browser_campaign_product(", fmt)
        self.assertIn("static func recommend_resume_slot(", fmt)
        self.assertIn("static func recommend_checkpoint_slot(", fmt)
        start = fmt.find("static func save_browser_campaign_product(")
        body = fmt[start : start + 5000]
        self.assertIn("save_slot_browser_flair", body)
        self.assertIn("execution_integrity_gate", body)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func save_browser_campaign_product_live", gd)
        self.assertIn("func apply_save_browser_campaign_product", gd)
        self.assertIn("func apply_save_browser_resume", gd)
        self.assertIn("func apply_save_browser_checkpoint", gd)
        self.assertIn("format_save_browser_campaign_product_plain", gd)
        # major #2 sequence still present
        self.assertIn("func apply_fleet_multi_day_sequence", mm)
        self.assertIn("func apply_fleet_multi_day_sequence", gd)
        self.assertIn("fleet_multi_day_sequence", panel)
        sec_i = panel.find("func _rebuild_saves_section")
        sec = panel[sec_i : sec_i + 2800]
        self.assertIn("Save browser campaign product (major #4)", sec)
        self.assertIn("save_browser_campaign_product_live", sec)
        self.assertIn("save_browser_resume", sec)
        self.assertIn("save_browser_checkpoint", sec)
        self.assertIn("save_slot:", sec)
        self.assertIn("load_slot:", sec)
        self.assertGreaterEqual(panel.count("_rebuild_saves_section"), 2)
        self.assertIn("build_save_browser_campaign_product_chip_bbcode", pi)
        self.assertIn("test_save_browser_campaign_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "save browser campaign",
            "save browser resume",
            "save browser checkpoint",
            "major #4",
            "fleet multi-day sequence",
            "major #2",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
