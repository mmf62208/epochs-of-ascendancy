#!/usr/bin/env python3
"""Gates: designer suite product (major #10 / deferred designers first slice)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from designer_suite_product import (  # noqa: E402
    DOMAINS,
    PRODUCT_STEPS,
    build_designer_suite_product,
    execute_designer_suite_step,
    designer_suite_product_integrity,
    close_designer_suite_product_loop,
    recommend_domain,
    normalize_catalog,
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
    def test_stamped_floor(self):
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        stamped = sum(
            1
            for p in geom["provinces"]
            if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot")
        )
        self.assertGreaterEqual(stamped, 753)


class TestPure(unittest.TestCase):
    def test_product_four_domains(self):
        p = build_designer_suite_product()
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("catalog_count", 0)), 8)
        self.assertEqual(len(p.get("domain_rows") or []), 4)
        self.assertIn((p.get("domain_recommendation") or {}).get("domain"), DOMAINS)
        for s in PRODUCT_STEPS:
            e = execute_designer_suite_step(s, 1)
            self.assertTrue(e.get("ok"))
        self.assertTrue(designer_suite_product_integrity().get("ok"))
        self.assertTrue(close_designer_suite_product_loop().get("ok"))

    def test_pressure_shifts_domain(self):
        cat = normalize_catalog()
        landish = recommend_domain(cat, tank_progress=0.05, naval_pressure=0.15)
        navalish = recommend_domain(cat, tank_progress=0.9, naval_pressure=0.9)
        self.assertIn(landish.get("domain"), DOMAINS)
        self.assertIn(navalish.get("domain"), DOMAINS)
        # At least scores differ under pressure
        self.assertNotEqual(
            float(landish.get("domain_scores", {}).get("naval", 0)),
            float(navalish.get("domain_scores", {}).get("naval", 0)),
        )


class TestLive(unittest.TestCase):
    def test_composition_stack(self):
        fmt = GD_FMT.read_text(encoding="utf-8")
        mm = GD_MM.read_text(encoding="utf-8")
        gd = GD_GD.read_text(encoding="utf-8")
        panel = GD_PANEL.read_text(encoding="utf-8")
        pi = GD_PI.read_text(encoding="utf-8")
        self.assertIn("static func designer_suite_product(", fmt)
        self.assertIn("static func recommend_designer_domain(", fmt)
        self.assertIn("static func execute_designer_suite_step(", fmt)
        start = fmt.find("static func designer_suite_product(")
        body = fmt[start : start + 5500]
        for h in (
            "production_priority_mutation",
            "production_order_resolve",
            "medium_tank_oob_product",
            "recommend_designer_domain",
        ):
            self.assertIn(h, body, msg=h)
        self.assertNotIn("var score := 0.55", body)
        self.assertIn("func designer_suite_product_live", mm)
        self.assertIn("func apply_designer_suite_product", mm)
        self.assertIn("_designer_live_catalog", mm)
        self.assertIn("func apply_designer_suite_product", gd)
        self.assertIn("func apply_designer_suite_catalog", gd)
        self.assertIn("func apply_designer_suite_seed", gd)
        self.assertIn("Designer suite product (major #10)", panel)
        self.assertIn("designer_suite_product_live", panel)
        self.assertIn("designer_domain_land", panel)
        self.assertIn("build_designer_suite_product_chip_bbcode", pi)
        self.assertIn("test_designer_suite_product.py", CI.read_text(encoding="utf-8"))

    def test_docs(self):
        labels = [
            "designer suite product",
            "designer suite catalog",
            "designer domain land",
            "major #10",
            "designers",
        ]
        for path in (TODO, SUMMARY, ROADMAP):
            low = path.read_text(encoding="utf-8").lower()
            for lab in labels:
                self.assertIn(lab, low, msg="%s missing %s" % (path.name, lab))


if __name__ == "__main__":
    unittest.main(verbosity=2)
