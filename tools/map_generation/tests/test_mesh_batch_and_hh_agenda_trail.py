#!/usr/bin/env python3
"""Gates: world-board mesh batch decision + HH multi-month agenda trail."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from hh_agenda_trail import (  # noqa: E402
    DEFAULT_TRAIL_CAPACITY,
    append_hh_agenda_trail,
    format_hh_agenda_trail,
    signal_to_trail_entry,
)

GD_LOD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"
GD_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
GD_GAMEDATA = ROOT / "scripts" / "autoload" / "GameData.gd"


class TestMeshBatchDecision(unittest.TestCase):
    def test_board_aware_batch_rules_from_source(self) -> None:
        src = GD_LOD.read_text(encoding="utf-8")
        self.assertIn("func use_batched_mesh_fills", src)
        self.assertIn("func use_batched_mesh_fills_for_board", src)
        m = re.search(r"WORLD_BOARD_CULL_THRESHOLD:\s*int\s*=\s*(\d+)", src)
        self.assertIsNotNone(m)
        world_thr = int(m.group(1))
        self.assertGreaterEqual(world_thr, 2200)

        # Mirror shipped decision: world board → strategic+operational; else strategic only.
        def use_batch(tier: str, count: int) -> bool:
            if count >= world_thr:
                return tier in ("STRATEGIC", "OPERATIONAL")
            return tier == "STRATEGIC"

        self.assertTrue(use_batch("STRATEGIC", 100))
        self.assertFalse(use_batch("OPERATIONAL", 100))
        self.assertFalse(use_batch("TACTICAL", 100))
        # World board prefers batch at operational too
        self.assertTrue(use_batch("STRATEGIC", 2665))
        self.assertTrue(use_batch("OPERATIONAL", 2665))
        self.assertFalse(use_batch("TACTICAL", 2665))

    def test_renderer_batch_sync_and_stats(self) -> None:
        src = GD_RENDERER.read_text(encoding="utf-8")
        self.assertIn("func _should_use_batched_mesh_fills", src)
        self.assertIn("func _sync_batched_mesh_fills", src)
        self.assertIn("func get_batched_mesh_stats", src)
        self.assertIn("func is_batched_mesh_fills_active", src)
        self.assertIn("use_batched_mesh_fills_for_board", src)
        self.assertIn("batch_preferred", src)
        self.assertIn("province_count", src)


class TestHHAgendaTrail(unittest.TestCase):
    def test_append_capacity_and_order(self) -> None:
        trail: list = []
        months = [
            (1936, 1, "sabotage", "Berlin"),
            (1936, 2, "economic_pressure", "Paris"),
            (1936, 3, "infiltration", "Rome"),
            (1936, 4, "sabotage", "Madrid"),
        ]
        for y, m, action, name in months:
            primary = {
                "year": y,
                "month": m,
                "province_id": m,
                "province_name": name,
                "action_class": action,
                "title": "Hidden Hand %s" % action,
                "marker": "!",
                "label": "! Hidden Hand %s" % action,
                "active": True,
            }
            secondary = {
                "year": y,
                "month": m,
                "province_id": m + 100,
                "province_name": name + " Harbor",
                "action_class": "infiltration" if action != "infiltration" else "sabotage",
                "title": "Hidden Hand secondary",
                "marker": "◈",
                "is_secondary": True,
                "active": True,
            }
            trail = append_hh_agenda_trail(trail, primary, secondary, capacity=6)
        self.assertGreaterEqual(len(trail), 3)
        self.assertLessEqual(len(trail), DEFAULT_TRAIL_CAPACITY)
        # Newest entries at end
        self.assertEqual(trail[-1]["province_name"], "Madrid Harbor")
        classes = [e["action_class"] for e in trail]
        self.assertTrue(any(c == "sabotage" for c in classes))
        self.assertTrue(any(c == "economic_pressure" for c in classes))
        self.assertTrue(any(c == "infiltration" for c in classes))
        formatted = format_hh_agenda_trail(trail, max_lines=6)
        self.assertGreaterEqual(formatted["count"], 3)
        self.assertFalse(formatted["empty"])
        self.assertTrue(all(str(ln).strip() for ln in formatted["lines"]))
        self.assertIn("primary", formatted["plain"])
        # Summaries include action labels
        joined = formatted["plain"]
        self.assertTrue(
            "sabotage" in joined or "economic" in joined or "infiltration" in joined
        )

    def test_signal_to_entry_and_format(self) -> None:
        e = signal_to_trail_entry(
            {
                "year": 1936,
                "month": 6,
                "province_id": 1,
                "province_name": "Vienna",
                "action_class": "infiltration",
                "title": "Hidden Hand infiltration",
                "marker": "◈",
            }
        )
        self.assertEqual(e["action_class"], "infiltration")
        self.assertIn("infiltration", e["summary"])
        self.assertIn("Vienna", e["summary"])
        fmt = format_hh_agenda_trail([e])
        self.assertEqual(fmt["count"], 1)
        self.assertIn("◈", fmt["bbcode"])

    def test_gamedata_trail_wiring(self) -> None:
        gd = GD_GAMEDATA.read_text(encoding="utf-8")
        self.assertIn("hh_agenda_trail", gd)
        self.assertIn("_append_hh_agenda_trail", gd)
        self.assertIn("func get_hh_agenda_trail", gd)
        self.assertIn("func format_hh_agenda_trail_plain", gd)
        self.assertIn("HH_AGENDA_TRAIL_CAPACITY", gd)
        # Monthly path appends trail after signals stored
        self.assertIn("_append_hh_agenda_trail(sig", gd)
        self.assertIn("process_hh_monthly_map_feedback", gd)


if __name__ == "__main__":
    unittest.main(verbosity=2)
