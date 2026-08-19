#!/usr/bin/env python3
"""Gate: designer finalize/field lands a selectable map unit."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from designer_field_map_unit_product import (  # noqa: E402
    build_designer_field_map_unit_product,
    designer_field_map_unit_integrity,
)


class TestDesignerFieldMapUnitProduct(unittest.TestCase):
    def test_product_wiring(self) -> None:
        p = build_designer_field_map_unit_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        wiring = p.get("wiring") or {}
        for key in (
            "leader_field_api",
            "design_manager_wrap",
            "designer_popup_fields",
            "field_seed_lands_chip",
            "harness_designer_field",
            "on_official_quick",
        ):
            self.assertTrue(wiring.get(key), msg=(key, p))

    def test_integrity(self) -> None:
        i = designer_field_map_unit_integrity()
        self.assertTrue(i.get("ok"), msg=i)


if __name__ == "__main__":
    unittest.main()
