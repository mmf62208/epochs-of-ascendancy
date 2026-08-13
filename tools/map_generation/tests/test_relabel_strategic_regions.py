#!/usr/bin/env python3
"""Gates for strategic region Theater N relabel."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from relabel_strategic_regions import (  # noqa: E402
    is_generic_region_name,
    run_on_dir,
)

WF = ROOT / "data" / "provinces_world_full"
INFRA = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"


class TestRelabelStrategicRegions(unittest.TestCase):
    def test_shipped_no_theater_n(self) -> None:
        reg = json.loads((WF / "strategic_regions.json").read_text())
        regions = reg.get("regions") or []
        leftovers = [
            r.get("name")
            for r in regions
            if is_generic_region_name(str(r.get("name") or ""))
        ]
        self.assertEqual(leftovers, [], msg=leftovers)
        self.assertGreaterEqual(len(regions), 12)
        names = [str(r.get("name") or "") for r in regions]
        self.assertEqual(len(names), len(set(names)), "region names must be unique")
        # Explicit Far East Theater leftovers must be gone
        self.assertFalse(any("Far East Theater" in n for n in names), msg=names)

    def test_run_on_dir_idempotent_after_write(self) -> None:
        # Dry run on shipped data should report 0 leftovers
        stats = run_on_dir(WF, write=False)
        self.assertEqual(stats["theater_n_remaining"], 0)


class TestRoadVisibilityPolish(unittest.TestCase):
    def test_road_layer_earlier_zoom(self) -> None:
        src = INFRA.read_text(encoding="utf-8")
        self.assertIn("road_layer.visible = show_roads and z > 0.10", src)
        self.assertIn("rail_layer.visible = show_rails and z > 0.14", src)
        self.assertIn("1.15", src)  # arterial width multiplier


if __name__ == "__main__":
    unittest.main(verbosity=2)
