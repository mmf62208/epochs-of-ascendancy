#!/usr/bin/env python3
"""Static STARTUP-PARITY inventory: board IDs + file hashes. No Godot."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from startup_parity_inventory_product import (  # noqa: E402
    BERLIN_PID,
    EMPTY_BOARD_GARRISONS,
    MANIFEST_PROVINCES,
    build_startup_parity_inventory_product,
    inventory_world_accurate_board,
)

D = ROOT / "data" / "provinces_world_accurate"


class TestStartupParityInventory(unittest.TestCase):
    def test_inventory_ok_on_shipped_board(self) -> None:
        inv = inventory_world_accurate_board(D)
        self.assertTrue(inv.get("ok"), msg=inv)
        self.assertEqual(inv.get("province_ids_n"), MANIFEST_PROVINCES)
        self.assertTrue(inv.get("has_berlin_710300"))
        self.assertEqual(inv.get("manifest_provinces"), MANIFEST_PROVINCES)
        hashes = inv.get("file_sha256") or {}
        self.assertEqual(len(hashes), 5)
        for name, digest in hashes.items():
            self.assertEqual(len(digest), 64, msg=name)
            self.assertTrue(all(c in "0123456789abcdef" for c in digest), msg=name)
        self.assertEqual(inv["garrison_575"]["empty_board_targets"], EMPTY_BOARD_GARRISONS)
        self.assertEqual(inv["seed_20fe9063"]["expect_prefix"], "20fe9063")

    def test_product_wraps_inventory(self) -> None:
        p = build_startup_parity_inventory_product(D)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS")
        self.assertEqual(p["inventory"]["has_berlin_710300"], True)
        self.assertEqual(BERLIN_PID, 710300)
        self.assertEqual(EMPTY_BOARD_GARRISONS, 576)

    def test_missing_dir_fails(self) -> None:
        inv = inventory_world_accurate_board(ROOT / "data" / "does_not_exist_startup_parity")
        self.assertFalse(inv.get("ok"))
        self.assertIn("data_dir_missing", inv.get("fail") or [])


if __name__ == "__main__":
    unittest.main()
