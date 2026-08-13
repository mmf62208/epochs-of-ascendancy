#!/usr/bin/env python3
"""Gates: next-310 advanced deferred pillars (20)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from next310_advanced_deferred import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

LIVE = set(ADVANCED_DEFERRED_DAY_IDS[:12])

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestPackages(unittest.TestCase):
    def test_twenty(self):
        self.assertEqual(len(ADVANCED_DEFERRED_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)
    def test_each(self):
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"))
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1)
                self.assertEqual(str((day.get("actions") or [{}])[0].get("action_id")), fn.__name__)
    def test_close(self):
        loop = close_next310_advanced_deferred_loop()
        self.assertTrue(loop.get("ok"))
        self.assertTrue(advanced_deferred_integrity().get("ok"))

class TestLive(unittest.TestCase):
    def test_composition(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        idx = fmt.find("Next-310 advanced deferred pillars (20)")
        self.assertGreaterEqual(idx, 0)
        sec = fmt[idx:]
        for h in ("focus_war_path_product", "naval_multi_phase_campaign_product", "designer_suite_product", "strategic_ai_daily_campaign_product", "play_session_campaign_product", "air_ops_campaign_product"):
            self.assertIn(h, sec, msg=h)
        for aid in ADVANCED_DEFERRED_DAY_IDS:
            self.assertEqual(fmt.count("static func %s(" % aid), 1, msg=aid)
        self.assertIn("_next310_live_day", mm)
    def test_wiring(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        for aid in ADVANCED_DEFERRED_DAY_IDS:
            self.assertIn("func %s" % aid, fmt)
            self.assertIn(aid, gd)
            self.assertIn(aid, panel)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm)
            self.assertIn(aid, pi)
        self.assertIn("func _rebuild_advanced_deferred_section", panel)
        self.assertIn("— Next-310 advanced deferred (20) —", panel)
        self.assertIn("test_next20_advanced_deferred_days.py", (ROOT / "tools/run_map_ci.sh").read_text())
        # Catalogue uses hyphen in multi-phase; match doc labels not raw snake conversion
        labels = [
            "focus pick board advanced day",
            "focus war path advanced day",
            "focus commit execute advanced day",
            "focus naval effort advanced day",
            "focus industry army joint day",
            "focus air effort joint day",
            "focus war path close day",
            "naval posture advanced day",
            "naval escort phase advanced day",
            "naval strike phase advanced day",
            "naval fleet fuel advanced day",
            "naval fleet autonomy joint day",
            "naval air joint advanced day",
            "naval multi-phase close day",
            "designer domain advanced day",
            "designer seed advanced day",
            "strategic ai multi-day advanced day",
            "designer ai industry joint day",
            "play session advanced joint day",
            "advanced deferred campaign close day",
            "next-310 advanced",
        ]
        for path in (ROOT/"TODO.md", ROOT/"Project_State_Summary.md", ROOT/"Next_30_Days_Roadmap.md"):
            low = path.read_text().lower()
            for lab in labels:
                self.assertIn(lab, low, msg=f"{path.name} missing {lab}")

if __name__ == "__main__":
    unittest.main(verbosity=2)
