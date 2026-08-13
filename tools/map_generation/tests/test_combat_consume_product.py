"""Pure tests for CP5 combat consume product."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/map_generation/lib"))
from combat_consume_product import (
    build_combat_consume_primary_command_product,
    primary_command_dead_audit,
)


class TestCombatConsume(unittest.TestCase):
    def test_product(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_combat_consume_primary_command_product()
        self.assertTrue(p["all_majors_ok"], p)


if __name__ == "__main__":
    unittest.main()
