#!/usr/bin/env python3
"""Gates: day apply audit, save-slot flair, infra/site consistency, GIS×753."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from week2_core_polish import (  # noqa: E402
    day_package_apply_audit,
    save_slot_browser_flair,
    infra_site_consistency_skim,
    close_week2_core_polish_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_SL = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestApplyAudit(unittest.TestCase):
    def test_live_sources_pass(self) -> None:
        panel = GD_PANEL.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        audit = day_package_apply_audit(panel, gd)
        self.assertFalse(audit.get("empty"))
        self.assertTrue(audit.get("ok"), msg="dead routes: %s" % audit.get("dead"))
        self.assertEqual(int(audit.get("dead_count", -1)), 0)
        self.assertGreaterEqual(int(audit.get("routed_count", 0)), 10)
        # Ship key routes
        for aid in ("day_ops_integrated", "combat_campaign_day", "fleet_campaign_day", "hh_player_path"):
            self.assertIn(aid, audit.get("routed") or [])


class TestSaveFlair(unittest.TestCase):
    def test_markers(self) -> None:
        flair = save_slot_browser_flair()
        self.assertFalse(flair.get("empty"))
        rows = flair.get("rows") or []
        self.assertGreaterEqual(len(rows), 2)
        marks = {str(r.get("marker")) for r in rows}
        self.assertTrue(marks & {"○", "●", "★", "⚡"})
        self.assertGreaterEqual(int(flair.get("empty_count", 0)) + int(flair.get("occupied_count", 0)), 2)


class TestInfraSite(unittest.TestCase):
    def test_issues(self) -> None:
        good = infra_site_consistency_skim(infrastructure=60.0, site_count=1, facility_tier="full")
        bad = infra_site_consistency_skim(
            infrastructure=10.0, site_count=2, site_damaged=2, project_active=1, facility_tier="none"
        )
        self.assertTrue(good.get("ok"))
        self.assertFalse(bad.get("ok"))
        self.assertGreaterEqual(int(bad.get("issue_count", 0)), 1)


class TestClose(unittest.TestCase):
    def test_loop(self) -> None:
        panel = GD_PANEL.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        loop = close_week2_core_polish_loop(panel, gd)
        self.assertFalse(loop.get("empty"))
        self.assertTrue((loop.get("audit") or {}).get("ok"))


class TestLive(unittest.TestCase):
    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func day_package_apply_audit", fmt)
        self.assertIn("func save_slot_browser_flair", fmt)
        self.assertIn("func infra_site_consistency_skim", fmt)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_day_package_apply_audit_plain", gd)
        self.assertIn("func format_save_slot_flair_plain", gd)
        self.assertIn("func format_infra_site_consistency_plain", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("format_day_package_apply_audit_plain", panel)
        self.assertIn("format_save_slot_flair_plain", panel)
        self.assertIn("flair_label", panel)

        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func infra_site_consistency_skim_for_province", mm)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_infra_site_consistency_chip_bbcode", insight)

        sl = GD_SL.read_text(encoding="utf-8")
        self.assertIn("func list_slots_for_ui", sl)

        self.assertIn("test_next20_week2_core_polish.py", CI.read_text(encoding="utf-8"))
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for label in (
                "day apply audit",
                "save-slot flair",
                "infra/site consistency",
            ):
                self.assertIn(label, low, msg="%s missing %s" % (path.name, label))


if __name__ == "__main__":
    unittest.main(verbosity=2)
