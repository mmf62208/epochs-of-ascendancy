#!/usr/bin/env python3
"""Gates: full designer module catalog + icons (real data/modules)."""
from __future__ import annotations
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
from designer_module_catalog import *  # noqa
from designer_module_editor_product import build_designer_module_editor_product, designer_module_editor_integrity  # noqa
from gis_coastline_ingest import load_geometry_payload  # noqa

class TestGis(unittest.TestCase):
    def test_stamped(self):
        geom = load_geometry_payload(ROOT / "data/provinces_world_full/provinces_geometry.json")
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_ne_full") or (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 753)

class TestCatalog(unittest.TestCase):
    def test_integrity(self):
        g = catalog_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        self.assertGreaterEqual(int(g.get("module_n", 0)), 1000)
        self.assertGreaterEqual(int(g.get("ok_domains", 0)), 4)
    def test_domains(self):
        for d in DOMAINS:
            entry = domain_catalog(d)
            self.assertFalse(entry.get("empty"), msg=d)
            self.assertGreaterEqual(int(entry.get("slot_n", 0)), 3, msg=d)
            self.assertGreaterEqual(int(entry.get("option_total", 0)), 12, msg=d)
            loadout = default_loadout(d)
            self.assertGreaterEqual(len(loadout), 3, msg=d)
            for row in loadout:
                mid = str(row.get("module_id", ""))
                self.assertTrue((ROOT / "data" / "modules" / f"{mid}.json").is_file(), msg=f"missing module json {mid}")
                icon = ROOT / "assets" / "graphics" / "icons" / "modules" / f"{mid}.png"
                self.assertTrue(icon.is_file(), msg=f"missing icon {icon}")
    def test_product(self):
        p = build_designer_module_editor_product(domain="land")
        self.assertFalse(p.get("empty"))
        self.assertGreaterEqual(int(p.get("option_total", 0)), 12)
        self.assertGreaterEqual(int(p.get("module_n_global", 0)), 1000)
        self.assertTrue(designer_module_editor_integrity().get("ok"))
    def test_stack(self):
        fmt = (ROOT / "scripts/map/MapPolishFormatters.gd").read_text()
        self.assertIn("catalog 1084", fmt)
        self.assertIn("kwk_38_50mm_gun", fmt)
        self.assertTrue((ROOT / "data/designers/full_module_catalog.json").is_file())
        self.assertTrue((ROOT / "data/designers/module_icon_map.json").is_file())
        icons = list((ROOT / "assets/graphics/icons/modules").glob("*.png"))
        self.assertGreaterEqual(len(icons), 50)

if __name__ == "__main__":
    unittest.main(verbosity=2)
