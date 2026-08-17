#!/usr/bin/env python3
"""Gates: 7-day calendar autosave for 20–60d 1936 sessions."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from calendar_autosave_product import (  # noqa: E402
    INTERVAL_DAYS,
    build_calendar_autosave_product,
    calendar_autosave_integrity,
    next_autosave_day,
    should_calendar_autosave,
)


class TestCalendarAutosaveProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_calendar_autosave_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(int(p.get("interval_days") or 0), INTERVAL_DAYS)

    def test_integrity(self) -> None:
        self.assertTrue(calendar_autosave_integrity().get("ok"))

    def test_schedule(self) -> None:
        self.assertFalse(should_calendar_autosave(0))
        self.assertFalse(should_calendar_autosave(6))
        self.assertTrue(should_calendar_autosave(7))
        self.assertTrue(should_calendar_autosave(56))
        self.assertEqual(next_autosave_day(1), 7)


if __name__ == "__main__":
    unittest.main()
