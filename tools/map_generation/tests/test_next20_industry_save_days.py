#!/usr/bin/env python3
"""Gates: next-120 industry/save/live-apply loops (20) + GIS×753 + composed GD wiring."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from next120_industry_save import (  # noqa: E402
    INDUSTRY_SAVE_DAY_IDS,
    DAY_FUNCS,
    close_next120_industry_save_loop,
    industry_save_integrity,
    prod_mut_apply_day,
    daily_prod_auto_live_day,
    save_slot_surface_day,
    industry_save_close_day,
)

WF = ROOT / "data" / "provinces_world_full"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_PI = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TODO = ROOT / "TODO.md"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"

LIVE = {
    "prod_mut_apply_day", "supply_mut_apply_day", "execute_prod_live_day",
    "day_budget_apply_day", "apply_audit_live_day", "live_apply_results_day",
    "mutation_gate_apply_day", "daily_prod_auto_live_day", "theater_prod_live_day",
    "save_slot_surface_day", "save_browser_live_day", "campaign_continuity_day",
    "industry_save_close_day", "execution_gate_cont_day",
}


class TestGis(unittest.TestCase):
    def test_stamped(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)


class TestPackages(unittest.TestCase):
    def test_twenty(self) -> None:
        self.assertEqual(len(INDUSTRY_SAVE_DAY_IDS), 20)
        self.assertEqual(len(DAY_FUNCS), 20)

    def test_each(self) -> None:
        for fn in DAY_FUNCS:
            with self.subTest(fn=fn.__name__):
                day = fn()
                self.assertFalse(day.get("empty"), fn.__name__)
                self.assertGreaterEqual(len(day.get("apply_queue") or []), 1, fn.__name__)
                acts = day.get("actions") or []
                self.assertTrue(isinstance(acts, list) and len(acts) >= 1)
                self.assertEqual(str(acts[0].get("action_id", "")), fn.__name__)

    def test_theme_helpers_shipped(self) -> None:
        prod = prod_mut_apply_day()
        self.assertFalse(prod.get("empty"))
        self.assertIn("mutation", prod)
        auto = daily_prod_auto_live_day()
        self.assertFalse(auto.get("empty"))
        self.assertIn("plan", auto)
        save = save_slot_surface_day()
        self.assertFalse(save.get("empty"))
        self.assertIn("slots", save)
        close = industry_save_close_day()
        self.assertFalse(close.get("empty"))
        self.assertTrue(close.get("ok") or close.get("gate"))

    def test_close(self) -> None:
        loop = close_next120_industry_save_loop()
        self.assertTrue(loop.get("ok"))
        self.assertGreaterEqual(int(loop.get("non_empty", 0)), 20)
        self.assertTrue(industry_save_integrity().get("ok"))


class TestLive(unittest.TestCase):
    def test_mpf_composes_theme_helpers(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        idx = fmt.find("Composes existing GD theme helpers (production / save / apply)")
        self.assertGreaterEqual(idx, 0, "composed next120 section missing")
        sec = fmt[idx:]
        for h in (
            "production_priority_mutation",
            "supply_route_mutation",
            "mutation_integrity_gate",
            "execution_integrity_gate",
            "day_package_apply_audit",
            "save_slot_browser_flair",
            "oob_factory_risk_loop",
            "production_order_resolve",
        ):
            self.assertIn(h, sec, msg="missing composed helper %s" % h)
        body = sec[sec.find("static func prod_mut_apply_day"): sec.find("static func prod_mut_apply_day") + 900]
        self.assertIn("production_priority_mutation", body)
        self.assertNotIn("var score := 0.55", body)
        save_body = sec[sec.find("static func save_slot_surface_day"): sec.find("static func save_slot_surface_day") + 800]
        self.assertIn("save_slot_browser_flair", save_body)
        self.assertIn("_next120_live_day", mm)
        self.assertIn("production_score", mm)
        self.assertIn("slot_count", mm)

    def test_wiring(self) -> None:
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        for aid in INDUSTRY_SAVE_DAY_IDS:
            self.assertIn("func %s" % aid, fmt, msg="MPF %s" % aid)
            self.assertIn(aid, gd, msg="GD %s" % aid)
            self.assertIn(aid, panel, msg="panel %s" % aid)
            self.assertIn("func apply_%s" % aid, gd)
            live = ("%s_live" % aid) if aid in LIVE else ("%s_for_province" % aid)
            self.assertIn("func %s" % live, mm, msg="MM %s" % live)
        for key in ("prod_mut_apply_day", "daily_prod_auto_live_day", "save_slot_surface_day", "industry_save_close_day"):
            self.assertIn(key, pi)
        self.assertIn("test_next20_industry_save_days.py", CI.read_text(encoding="utf-8"))
        labels = [
            "prod mut apply day", "supply mut apply day", "execute prod live day",
            "day budget apply day", "apply audit live day", "live apply results day",
            "mutation gate apply day", "daily prod auto live day", "theater prod live day",
            "prod campaign risk day", "prod wx stack day", "factory risk live day",
            "depot prod stack day", "industry close loop day", "save slot surface day",
            "save browser live day", "campaign continuity day", "ops dash continuity day",
            "execution gate cont day", "industry save close day", "next-120 industry",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
