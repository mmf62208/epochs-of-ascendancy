#!/usr/bin/env python3
"""Gate: first-session play surface composer calls real shipped builders."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LIB = ROOT / "tools" / "map_generation" / "lib"
sys.path.insert(0, str(LIB))

from first_session_play_surface_product import (  # noqa: E402
    build_first_session_play_surface_product,
)
from save_resume_primary_command_product import (  # noqa: E402
    build_save_resume_primary_command_product,
)

CHILD_NAMES = (
    "capital_pick",
    "fronts",
    "war_path",
    "corridor",
    "save",
    "hotkeys",
    "assault",
    "play_strip",
    "unit_pick",
    "unit_chrome",
)


class TestFirstSessionPlaySurfaceProduct(unittest.TestCase):
    def test_real_builder_ands_shipped_children(self) -> None:
        p = build_first_session_play_surface_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS")
        self.assertEqual(list(p.get("fail") or []), [])
        children = p.get("children") or {}
        self.assertEqual(set(children), set(CHILD_NAMES))
        for name in CHILD_NAMES:
            row = children[name]
            self.assertTrue(row.get("ok"), msg=(name, row))
            self.assertTrue(str(row.get("summary") or "").strip(), msg=name)
            self.assertIn(name, p.get("pass") or [])

    def test_save_pass_bit_is_not_ok_key(self) -> None:
        raw = build_save_resume_primary_command_product(province_id=1)
        self.assertNotIn("ok", raw)
        self.assertTrue(raw.get("all_majors_ok"), msg=raw)
        self.assertEqual(int(raw.get("dead_n") or 0), 0)
        p = build_first_session_play_surface_product()
        self.assertTrue((p.get("children") or {}).get("save", {}).get("ok"), msg=p)

    def test_composer_source_is_thin_call_table(self) -> None:
        src = (LIB / "first_session_play_surface_product.py").read_text(encoding="utf-8")
        for fn in (
            "build_world_accurate_capital_pick_product",
            "build_map_live_border_fronts_surface_product",
            "build_map_war_path_surface_product",
            "build_supply_corridor_product",
            "build_save_resume_primary_command_product",
            "build_first_session_hotkeys_product",
            "build_first_session_assault_surface_product",
            "build_order_panel_play_strip_product",
            "build_unit_centric_pick_product",
            "build_unit_counter_chrome_product",
        ):
            self.assertIn(fn, src)
        self.assertNotIn("map_supply_hub_brief_product", src)
        self.assertNotIn("_integrity", src)


if __name__ == "__main__":
    unittest.main()
