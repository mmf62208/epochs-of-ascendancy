#!/usr/bin/env python3
"""Gates: month/year calendar autosave + EOA_CALENDAR_AUTOSAVE killswitch."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from calendar_autosave_product import (  # noqa: E402
    CADENCE_DEFAULT,
    KILLSWITCH,
    build_calendar_autosave_product,
    calendar_autosave_integrity,
    should_calendar_autosave,
)


class TestCalendarAutosaveProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_calendar_autosave_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(str(p.get("cadence_default") or ""), CADENCE_DEFAULT)
        self.assertEqual(str(p.get("killswitch") or ""), KILLSWITCH)
        self.assertEqual(str(p.get("policy") or ""), "month_year_autosave_rotator")

    def test_integrity(self) -> None:
        self.assertTrue(calendar_autosave_integrity().get("ok"))

    def test_schedule(self) -> None:
        self.assertFalse(should_calendar_autosave("off", "month"))
        self.assertFalse(should_calendar_autosave("off", "year"))
        self.assertTrue(should_calendar_autosave("monthly", "month"))
        self.assertFalse(should_calendar_autosave("monthly", "year"))
        self.assertTrue(should_calendar_autosave("yearly", "year"))
        self.assertFalse(should_calendar_autosave("yearly", "month"))


if __name__ == "__main__":
    unittest.main()
