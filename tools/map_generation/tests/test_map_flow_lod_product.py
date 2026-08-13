"""Pure tests for map flow LOD + toggle product."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from map_flow_lod_product import (
    build_map_flow_lod_primary_command_product,
    primary_command_dead_audit,
)


class TestMapFlowLod(unittest.TestCase):
    def test_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_map_flow_lod_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        self.assertTrue(p["hooks_ok"])
        lod = (ROOT / "scripts/map/MapZoomLOD.gd").read_text(encoding="utf-8")
        self.assertIn("func equipment_flow_glyph_policy", lod)
        ren = (ROOT / "scripts/map/MapRenderer.gd").read_text(encoding="utf-8")
        self.assertIn("func toggle_equipment_flow_glyphs", ren)
        self.assertIn("func get_equipment_flow_glyph_query", ren)


if __name__ == "__main__":
    unittest.main()
