#!/usr/bin/env python3
"""Gates: multi-phase combat product surface (major #1) — pure + live wiring + panel body."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from combat_multi_phase_product import (  # noqa: E402
    build_multi_phase_combat_product,
    execute_combat_phase_plan,
    recommend_combat_phase_step,
    multi_phase_combat_product_integrity,
    close_multi_phase_combat_product_loop,
)
from gis_coastline_ingest import load_geometry_payload  # noqa: E402

GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
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


class TestPureProduct(unittest.TestCase):
    def test_build_has_three_phases_and_actions(self):
        p = build_multi_phase_combat_product(100.0, 80.0, attacker_supply=0.85, weather_mult=0.9, province_id=7)
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("phase_count", 0)), 3)
        self.assertGreaterEqual(len(p.get("apply_queue") or []), 3)
        self.assertIn("recommendation", p)
        phases = [str(r.get("phase")) for r in (p.get("phase_actions") or [])]
        self.assertIn("approach", phases)
        self.assertIn("engage", phases)
        self.assertIn("disengage", phases)
        aids = [str(a.get("action_id")) for a in (p.get("actions") or [])]
        self.assertIn("multi_phase_combat_product", aids)
        self.assertIn("phase_engage", aids)
        # leaf queue maps correctly
        leaves = {str(q.get("phase")): str(q.get("action_id")) for q in (p.get("apply_queue") or [])}
        self.assertEqual(leaves.get("approach"), "apply_supply")
        self.assertEqual(leaves.get("engage"), "apply_assault")
        self.assertEqual(leaves.get("disengage"), "apply_station")

    def test_execute_phases(self):
        for phase, leaf in (("approach", "apply_supply"), ("engage", "apply_assault"), ("disengage", "apply_station")):
            e = execute_combat_phase_plan(phase, province_id=3)
            self.assertEqual(str(e.get("leaf_action")), leaf)
            self.assertEqual(str(e.get("phase")), phase)
            self.assertFalse(e.get("empty"))
            self.assertGreaterEqual(len(e.get("apply_queue") or []), 1)

    def test_recommend_and_weather_shift(self):
        rec = recommend_combat_phase_step(0.6, engage_win=0.55, approach_win=0.5)
        self.assertEqual(rec.get("step"), "press")
        rec2 = recommend_combat_phase_step(0.2, engage_win=0.2, approach_win=0.3)
        self.assertEqual(rec2.get("step"), "disengage")
        clear = build_multi_phase_combat_product(100.0, 80.0, weather_mult=1.0)
        foul = build_multi_phase_combat_product(100.0, 80.0, weather_mult=0.55)
        self.assertGreater(abs(float(clear.get("overall", 0)) - float(foul.get("overall", 0))), 0.01)

    def test_integrity_close(self):
        self.assertTrue(multi_phase_combat_product_integrity().get("ok"))
        loop = close_multi_phase_combat_product_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreater(float(loop.get("wx_shift", 0)), 0.01)


class TestLiveWiring(unittest.TestCase):
    def test_gd_composes_helpers(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("static func multi_phase_combat_product(", fmt)
        self.assertIn("static func recommend_combat_phase_step(", fmt)
        self.assertIn("static func execute_combat_phase_plan(", fmt)
        idx = fmt.find("static func multi_phase_combat_product(")
        body = fmt[idx : idx + 2500]
        self.assertIn("multi_phase_combat_ui_product", body)
        self.assertIn("estimate_multi_phase_combat", body)
        self.assertIn("phase_approach", body)
        self.assertIn("phase_engage", body)
        self.assertIn("phase_disengage", body)
        self.assertNotIn("var score := 0.55", body)

    def test_live_stack(self):
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        bm = GD_BM.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("func multi_phase_combat_product_for_province", mm)
        self.assertIn("func apply_combat_phase_for_province", mm)
        self.assertIn("func apply_multi_phase_combat_product", mm)
        self.assertIn("func apply_multi_phase_combat_product", gd)
        self.assertIn("func apply_phase_approach", gd)
        self.assertIn("func apply_phase_engage", gd)
        self.assertIn("func apply_phase_disengage", gd)
        self.assertIn("format_multi_phase_combat_product_plain", gd)
        self.assertIn("func build_multi_phase_combat_product", bm)
        self.assertIn("func apply_combat_phase", bm)
        # Panel section uses product path and per-phase buttons
        self.assertIn("func _rebuild_combat_section", panel)
        sec_i = panel.find("func _rebuild_combat_section")
        sec = panel[sec_i : sec_i + 2000]
        self.assertIn("multi_phase_combat_product_for_province", sec)
        self.assertIn("phase_approach", sec)
        self.assertIn("phase_engage", sec)
        self.assertIn("phase_disengage", sec)
        self.assertIn("Multi-phase combat product (major #1)", sec)
        self.assertGreaterEqual(panel.count("_rebuild_combat_section"), 2)
        self.assertIn("build_multi_phase_combat_product_chip_bbcode", pi)
        self.assertIn("multi_phase_combat_product", pi)

    def test_ci_and_docs(self):
        self.assertIn("test_multi_phase_combat_product.py", CI.read_text(encoding="utf-8"))
        labels = [
            "multi-phase combat product",
            "phase approach",
            "phase engage",
            "phase disengage",
            "major #1",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
