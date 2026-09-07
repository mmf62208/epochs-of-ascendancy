#!/usr/bin/env python3
"""Gates: inspector Settle button uses province name; create path is not generic."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from settle_title_product import (  # noqa: E402
    GENERIC_CREATE_TITLE,
    NAMED_TITLE_MARK,
    build_settle_title_product,
    format_settle_button_title,
    settle_title_integrity,
)

RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


class TestSettleTitleProduct(unittest.TestCase):
    def test_format_named_and_id_fallback(self) -> None:
        self.assertEqual(
            format_settle_button_title("London", 1.25, 711414),
            "🏠 Settle London (+0.35, now 1.25)",
        )
        self.assertEqual(
            format_settle_button_title("  ", 0.0, 711467),
            "🏠 Settle #711467 (+0.35, now 0.00)",
        )

    def test_product_ok(self) -> None:
        p = build_settle_title_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("status"), "PASS")

    def test_integrity(self) -> None:
        g = settle_title_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_renderer_source_lock(self) -> None:
        src = RENDERER.read_text(encoding="utf-8")
        self.assertIn(NAMED_TITLE_MARK, src)
        self.assertNotIn(GENERIC_CREATE_TITLE, src)
        p = build_settle_title_product()
        for key in (
            "named_title",
            "no_generic_create",
            "hide_on_sea",
            "hide_on_null",
            "create_hidden",
            "name_fallback_id",
        ):
            self.assertTrue(p.get("wiring", {}).get(key), msg=(key, p.get("wiring"), p.get("fail")))


if __name__ == "__main__":
    unittest.main()
