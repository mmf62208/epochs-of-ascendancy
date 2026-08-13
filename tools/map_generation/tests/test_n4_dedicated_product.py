"""Pure + hooks for N4 dedicated server."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from n4_dedicated_product import (  # noqa: E402
    build_n4_dedicated_primary_command_product,
    primary_command_dead_audit,
    reconnect_resync_ok,
)


class TestN4Dedicated(unittest.TestCase):
    def test_resync_logic(self):
        self.assertTrue(reconnect_resync_ok(2, 5, 5))
        self.assertFalse(reconnect_resync_ok(4, 3, 5))

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_n4_dedicated_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_n4_dedicated_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("n4_dedicated_primary_live=1", sl)
        pg = (ROOT / "project.godot").read_text(encoding="utf-8")
        self.assertIn("NetSessionManager=", pg)


if __name__ == "__main__":
    unittest.main()
