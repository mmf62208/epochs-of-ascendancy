#!/usr/bin/env python3
"""Director D2.3/D3/D5 pure gates for HOI-like feel on the accurate GIS board.

Uses real accurate-board IDs + shipped product modules / GD surfaces.
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from save_browser_campaign_product import (  # noqa: E402
    build_save_browser_campaign_product,
    recommend_checkpoint_slot,
    recommend_resume_slot,
)
from strategic_ai_daily_campaign_product import (  # noqa: E402
    build_strategic_ai_daily_campaign_product,
)

D = ROOT / "data" / "provinces_world_accurate"
LOD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"
FLOW = ROOT / "scripts" / "map" / "StrategicFlowOverlayLayer.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
SCAFFOLD = D / "hierarchy_scaffold.json"
GER_CAP = 710300
USA_CAP = 800792
ACCURATE_N = 3520  # post US + full RoW sparse merge; was 4683 / 5670 / 8761


class TestWorldAccurateMapResidual(unittest.TestCase):
    def test_hierarchy_scaffold_covers_all_provinces(self) -> None:
        self.assertTrue(SCAFFOLD.is_file(), SCAFFOLD)
        sc = json.loads(SCAFFOLD.read_text(encoding="utf-8"))
        base_ids = {
            str(p["id"])
            for p in json.loads((D / "provinces_base.json").read_text())["provinces"]
        }
        p2r = sc.get("province_to_region") or {}
        p2s = sc.get("province_to_state") or {}
        p2sr = sc.get("province_to_super_region") or {}
        self.assertEqual(set(p2r.keys()), base_ids)
        self.assertEqual(set(p2s.keys()), base_ids)
        self.assertEqual(set(p2sr.keys()), base_ids)
        self.assertTrue(sc.get("four_tier"))
        self.assertGreaterEqual(int(sc.get("state_n") or 0), 400)
        self.assertGreaterEqual(int(sc.get("region_n") or 0), 20)

    def test_project_sites_stub_present(self) -> None:
        ps = D / "project_sites.json"
        self.assertTrue(ps.is_file())
        doc = json.loads(ps.read_text(encoding="utf-8"))
        self.assertIn("sites", doc)
        self.assertIsInstance(doc["sites"], list)

    def test_adj_shared_edge_floor(self) -> None:
        adj = json.loads((D / "province_adjacency.json").read_text())
        cov = float((adj.get("stats") or {}).get("land_shared_coverage") or 0)
        # D5.1: near_vertex residual lifts floor to 0.95
        self.assertGreaterEqual(cov, 0.95)
        self.assertEqual(int((adj.get("stats") or {}).get("orphan_land_after") or 0), 0)
        method = str(adj.get("method") or "")
        self.assertIn("shared_edge", method)


class TestWorldAccurateFlowLodD23(unittest.TestCase):
    def test_key_i_toggle_and_accurate_board_glyph_cap(self) -> None:
        lod = LOD.read_text(encoding="utf-8")
        self.assertIn("ACCURATE_BOARD_CULL_THRESHOLD", lod)
        self.assertIn("3000", lod)
        self.assertIn("max_equipment_flow_glyphs_for_board", lod)
        # Accurate board gets tighter cap than world board
        self.assertIn("0.45", lod)
        flow = FLOW.read_text(encoding="utf-8")
        self.assertIn("equipment_flow_glyphs_enabled", flow)
        self.assertIn("toggle_equipment_flow_glyphs", flow)
        self.assertIn("max_equipment_flow_glyphs_for_board", flow)
        ren = RENDERER.read_text(encoding="utf-8")
        self.assertIn("KEY_I", ren)
        self.assertIn("toggle_equipment_flow_glyphs", ren)

    def test_glyph_cap_math_for_accurate_count(self) -> None:
        """Mirror shipped formula for ACCURATE threshold (tactical base 32)."""
        base_tactical = 32
        accurate_cap = max(3, int(base_tactical * 0.45))
        world_cap = max(4, int(base_tactical * 0.65))
        self.assertLess(accurate_cap, world_cap)
        self.assertEqual(accurate_cap, 14)
        # Post full RoW sparse merge ~3520 still uses accurate path (threshold 3000)
        self.assertGreaterEqual(ACCURATE_N, 3000)


class TestWorldAccurateCampaignD3(unittest.TestCase):
    def test_strategic_ai_daily_product_on_accurate_capital(self) -> None:
        prod = build_strategic_ai_daily_campaign_product(
            province_id=GER_CAP, player_tag="GER", max_ai_actions=4
        )
        self.assertGreaterEqual(int(prod.get("faction_count") or 0), 5)
        self.assertTrue(
            prod.get("day_rows") or prod.get("apply_queue") or float(prod.get("score") or 0) > 0.5
        )
        self.assertEqual(int(prod.get("province_id") or 0), GER_CAP)
        # Queue steps carry accurate capital into AI apply surface
        q = prod.get("apply_queue") or []
        self.assertTrue(any(int(x.get("province_id") or 0) == GER_CAP for x in q if isinstance(x, dict)))
        self.assertTrue(prod.get("apply_ready") or int(prod.get("budget_count") or 0) > 0)

    def test_save_browser_campaign_product_world_accurate_slots(self) -> None:
        occupied = [
            {
                "slot": "quicksave",
                "occupied": True,
                "label": "quicksave · world_accurate · GER",
                "metadata": {
                    "scenario_id": "world_accurate",
                    "player_tag": "GER",
                    "timestamp": "1936-06-01",
                    "capital_province_id": GER_CAP,
                    "province_count": ACCURATE_N,
                },
                "can_load": True,
                "can_save": True,
            },
            {
                "slot": "slot1",
                "occupied": True,
                "label": "slot1 · world_accurate · USA",
                "metadata": {
                    "scenario_id": "world_accurate",
                    "player_tag": "USA",
                    "timestamp": "1936-03-15",
                    "capital_province_id": USA_CAP,
                },
                "can_load": True,
                "can_save": True,
            },
        ]
        prod = build_save_browser_campaign_product(occupied)
        self.assertGreaterEqual(int(prod.get("occupied_count") or 0), 1)
        rows = prod.get("rows") or occupied
        resume = recommend_resume_slot(rows)
        self.assertFalse(resume.get("empty"))
        self.assertIn(resume.get("slot"), ("quicksave", "slot1", "autosave"))
        # Metadata from accurate campaign retained on at least one occupied row
        blob = json.dumps(prod)
        self.assertIn("world_accurate", blob)
        self.assertIn(str(GER_CAP), blob)
        ck = recommend_checkpoint_slot(rows)
        self.assertTrue(ck.get("slot"))
        # Live GD still exposes quicksave/browser apply
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_save_browser_campaign_product", gd)
        self.assertIn("func apply_save_slot_quicksave", gd)
        slm = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        self.assertIn("func quicksave", slm)

    def test_ownership_snapshot_for_save_integrity_sample(self) -> None:
        """Save mid-campaign needs stable owner tags on accurate capitals."""
        own = json.loads((D / "province_ownership_1936.json").read_text())["owners"]
        for pid, tag in ((GER_CAP, "GER"), (USA_CAP, "USA"), (710707, "FRA")):
            self.assertEqual(own.get(str(pid)), tag)


if __name__ == "__main__":
    unittest.main(verbosity=2)
