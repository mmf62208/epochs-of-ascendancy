"""Pure + source hooks for SpaceLayerManager claim/habitat/flow."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from space_ops_product import (  # noqa: E402
    build_space_ops_primary_command_product,
    primary_command_dead_audit,
    simulate_claim_and_habitat,
    simulate_spaceflow_interdict,
)


class TestSpaceOps(unittest.TestCase):
    def test_claim_habitat_sim(self):
        s = simulate_claim_and_habitat()
        self.assertTrue(s["can_claim"])
        self.assertTrue(s["can_build"])

    def test_flow_interdict_sim(self):
        f = simulate_spaceflow_interdict(20.0, 0.4)
        self.assertTrue(f["ok"])
        self.assertAlmostEqual(f["ratio"], 0.6)

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_space_ops_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        mgr = (ROOT / "scripts" / "space" / "SpaceLayerManager.gd").read_text(encoding="utf-8")
        self.assertIn("func claim_site", mgr)
        self.assertIn("func build_habitat", mgr)
        self.assertIn("func create_space_flow", mgr)
        self.assertIn("func interdict_space_flow", mgr)
        self.assertIn("func process_monthly_space", mgr)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_space_ops_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("space_ops_primary_live=1", sl)
        pg = (ROOT / "project.godot").read_text(encoding="utf-8")
        self.assertIn("SpaceLayerManager=", pg)


if __name__ == "__main__":
    unittest.main()
