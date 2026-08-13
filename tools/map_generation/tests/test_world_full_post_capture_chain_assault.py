#!/usr/bin/env python3
"""Pure: post-capture chain/flank assault API wiring."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"
SCEN = ROOT / "data" / "scenarios" / "world_full.json"
FROM_PID, TO_PID = 9276, 9281


class TestWorldFullPostCaptureChainAssaultWiring(unittest.TestCase):
    def test_bm_chain_api_stages_from_captured(self) -> None:
        bm = (ROOT / "scripts" / "combat" / "BattleManager.gd").read_text(encoding="utf-8")
        self.assertIn("func execute_chain_assault_or_flank", bm)
        self.assertIn("func execute_province_assault", bm)
        self.assertIn("func can_assault_province", bm)
        self.assertIn("province_control_change", bm)
        # Follow-on stages from captured target, not only old border.
        self.assertIn("current_from", bm)
        self.assertIn("target_province_id", bm)
        self.assertIn("Follow-on assault", bm)
        # Still uses execute for each step
        self.assertGreaterEqual(bm.count("execute_province_assault"), 2)

    def test_world_full_edge_ownership(self) -> None:
        adj = json.loads((WF / "province_adjacency.json").read_text()).get("adjacency") or {}
        self.assertIn(TO_PID, [int(x) for x in adj.get(str(FROM_PID), [])])
        owners = {
            int(p["id"]): str(p.get("owner_tag") or "").upper()
            for p in json.loads(SCEN.read_text()).get("provinces") or []
            if isinstance(p, dict)
        }
        self.assertEqual(owners.get(FROM_PID), "GER")
        self.assertEqual(owners.get(TO_PID), "FRA")

    def test_headless_drives_chain_api_not_only_bare_execute(self) -> None:
        path = ROOT / "scripts" / "core" / "HeadlessWorldFullPostCaptureChainAssaultTest.gd"
        self.assertTrue(path.is_file())
        src = path.read_text(encoding="utf-8")
        self.assertIn("execute_chain_assault_or_flank", src)
        for needle in (
            "9276",
            "9281",
            "92991",
            "province_control_change",
            "daily_formation_reinforce_from_stockpile",
            "from_province_id",
        ):
            self.assertIn(needle, src, msg=needle)
        # Must assert multi-result chain
        self.assertTrue(
            "size" in src.lower() or "≥2" in src or ">= 2" in src or "last_size" in src,
            msg="headless should assert chain result length",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
