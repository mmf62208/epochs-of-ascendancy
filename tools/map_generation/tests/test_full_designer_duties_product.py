#!/usr/bin/env python3
"""Gates: full designer duties authoring cycle (all domains)."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from full_designer_duties_product import (  # noqa
    close_full_designer_duties,
    full_designer_duties_integrity,
    apply_designer_duties_step,
    _new_runtime,
    PRODUCT_STEPS,
    DOMAINS_T,
)


class TestFullDesignerDuties(unittest.TestCase):
    def test_close_all_domains(self):
        r = close_full_designer_duties("GER", 1)
        self.assertTrue(r.get("ok"), msg=r)
        self.assertEqual(int(r.get("domains_registered") or 0), 4)
        self.assertEqual(int(r.get("domains_seeded") or 0), 4)
        self.assertTrue(r.get("complete"))

    def test_five_steps_per_domain(self):
        rt = _new_runtime("USA")
        for dom in DOMAINS_T:
            for step in PRODUCT_STEPS:
                res = apply_designer_duties_step(rt, step, dom, 1)
                self.assertTrue(res.get("ok"), msg=res)
        self.assertTrue(rt.get("complete"))

    def test_register_before_seed(self):
        rt = _new_runtime("GER")
        for step in ("catalog", "compose", "freeze", "register"):
            apply_designer_duties_step(rt, step, "land", 1)
        self.assertTrue(rt["domains"]["land"].get("registered"))
        self.assertFalse(rt["domains"]["land"].get("seeded"))
        apply_designer_duties_step(rt, "seed", "land", 1)
        self.assertTrue(rt["domains"]["land"].get("seeded"))

    def test_gamedata_designmanager_loader_wired(self):
        g = full_designer_duties_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text()
        dm = (ROOT / "scripts" / "production" / "DesignManager.gd").read_text()
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text()
        self.assertIn("apply_full_designer_duties_live", gd)
        self.assertIn("apply_designer_duties_live", gd)
        self.assertIn("func register_custom_design", dm)
        self.assertIn("full_designer_duties_live=1", sl)

    def test_ci_hook(self):
        ci = (ROOT / "tools" / "run_map_ci.sh").read_text()
        self.assertIn("test_full_designer_duties_product.py", ci)

    def test_domain_design_popup_exists(self):
        p = ROOT / "scripts" / "ui" / "DomainDesignPopup.gd"
        self.assertTrue(p.is_file())
        text = p.read_text()
        self.assertIn("register_custom_design", text)
        self.assertIn("land", text)
        self.assertIn("naval", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
