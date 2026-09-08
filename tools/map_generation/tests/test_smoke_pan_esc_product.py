#!/usr/bin/env python3
"""Gates: smoke pan-from-drag + idle Esc → Command Center walls."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from smoke_pan_esc_product import (  # noqa: E402
    build_smoke_pan_esc_product,
    smoke_pan_esc_integrity,
)


class TestSmokePanEscProduct(unittest.TestCase):
    def test_product_wiring(self) -> None:
        p = build_smoke_pan_esc_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=(p.get("fail"), p.get("wiring")))
        w = p.get("wiring") or {}
        for key in (
            "release_skip_pick_helper",
            "pan_from_slop_helper",
            "area2d_never_pick_on_press",
            "unhandled_release_skip_and_block",
            "coarse_and_title_honor_skip",
            "camera_slop_before_modal",
            "input_motion_pans_from_slop",
            "empty_area_process_armed_to_camera",
            "esc_chain_in_input",
            "esc_idle_calls_menu",
            "dismiss_no_mainmenu_leftover",
            "topbar_uses_esc_chain",
        ):
            self.assertTrue(w.get(key), msg=(key, w, p.get("fail")))

    def test_integrity(self) -> None:
        g = smoke_pan_esc_integrity()
        self.assertTrue(g.get("ok"), msg=g)


if __name__ == "__main__":
    unittest.main()
