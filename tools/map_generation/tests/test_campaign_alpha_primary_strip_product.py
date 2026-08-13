#!/usr/bin/env python3
"""Gates: Campaign Alpha primary command strip (Phase 1 playability)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from campaign_alpha_primary_strip_product import *  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa


class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(
            1
            for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product(self):
        p = build_campaign_alpha_primary_strip_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(len(p.get("primary_actions") or []), 6)
        self.assertLessEqual(len(p.get("primary_actions") or []), 8)
        self.assertEqual(int(p.get("dead_n", 1)), 0)
        self.assertTrue(p.get("dead_ok"))
        self.assertLessEqual(int(p.get("max_expanded", 99)), 1)
        rec = p.get("recommendation") or {}
        self.assertIn(str(rec.get("action_id")), LIVE_PRIMARY_ACTION_IDS)
        for s in PRODUCT_STEPS:
            self.assertTrue(execute_campaign_alpha_step(s).get("ok"))
        self.assertTrue(campaign_alpha_primary_strip_integrity().get("ok"))
        self.assertTrue(close_campaign_alpha_primary_strip_loop().get("ok"))

    def test_dead_audit_fails_unknown(self):
        bad = primary_strip_dead_audit(["apply_station", "not_a_real_action"])
        self.assertEqual(int(bad.get("dead_n", 0)), 1)
        self.assertFalse(bad.get("ok"))


class TestLive(unittest.TestCase):
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        mm = (ROOT / "scripts/map/MapManager.gd").read_text()
        gd = (ROOT / "scripts/autoload/GameData.gd").read_text()
        panel = (ROOT / "scripts/ui/OrderCommandPanel.gd").read_text()
        pi = (ROOT / "scripts/map/ProvinceInsight.gd").read_text()
        sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text()
        self.assertIn("static func campaign_alpha_primary_strip_product(", fmt)
        self.assertIn("func campaign_alpha_primary_strip_product_live", mm)
        self.assertIn("func apply_campaign_alpha_primary_strip_live", gd)
        self.assertIn("Campaign Alpha primary strip", panel)
        self.assertIn("_rebuild_campaign_alpha_primary_strip", panel)
        self.assertIn("build_campaign_alpha_primary_strip_product_chip_bbcode", pi)
        self.assertIn("campaign_alpha_primary_live", sl)
        for aid in LIVE_PRIMARY_ACTION_IDS:
            self.assertIn(aid, gd, msg="primary action missing from GameData: %s" % aid)
            self.assertIn('"%s"' % aid, panel, msg="primary action missing from panel catalogue: %s" % aid)
        ci = (ROOT / "tools/run_map_ci.sh").read_text()
        self.assertIn("test_campaign_alpha_primary_strip_product.py", ci)

    def test_docs(self):
        for path in (
            ROOT / "TODO.md",
            ROOT / "Project_State_Summary.md",
            ROOT / "Next_30_Days_Roadmap.md",
            ROOT / "GAME_STATUS_ASSESSMENT.md",
            ROOT / "docs/COMPLETION_PLAN.md",
        ):
            low = path.read_text().lower()
            for lab in ("campaign alpha", "primary strip", "phase1_alpha"):
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
