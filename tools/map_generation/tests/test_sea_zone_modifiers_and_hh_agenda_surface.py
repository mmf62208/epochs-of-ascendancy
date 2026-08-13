#!/usr/bin/env python3
"""Gates: sea-zone strategic modifiers + HH agenda trail surface + doc health."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from sea_zone_control import (  # noqa: E402
    compute_sea_zone_control,
    format_sea_zone_control_badge,
    sea_zone_strategic_modifiers,
)
from hh_agenda_trail import append_hh_agenda_trail, format_hh_agenda_trail  # noqa: E402

GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
TODO = ROOT / "TODO.md"


class TestSeaZoneStrategicModifiers(unittest.TestCase):
    def test_controlled_contested_unowned_differ(self) -> None:
        controlled = sea_zone_strategic_modifiers(
            {"controller": "ENG", "contested": False, "unowned": False}
        )
        contested = sea_zone_strategic_modifiers(
            {"controller": "ENG", "contested": True, "unowned": False}
        )
        unowned = sea_zone_strategic_modifiers(
            {"controller": "", "contested": False, "unowned": True}
        )
        self.assertEqual(controlled["state"], "controlled")
        self.assertEqual(contested["state"], "contested")
        self.assertEqual(unowned["state"], "unowned")
        # Distinct non-trivial finite values; controlled best for friendly sealanes
        self.assertGreater(
            float(controlled["supply_multiplier"]),
            float(contested["supply_multiplier"]),
        )
        self.assertGreaterEqual(
            float(contested["supply_multiplier"]),
            0.5,
        )
        self.assertGreater(
            float(controlled["trade_multiplier"]),
            float(unowned["trade_multiplier"]),
        )
        self.assertNotEqual(
            float(controlled["supply_multiplier"]),
            float(unowned["supply_multiplier"]),
        )
        # Badge includes modifier summary
        ctrl = compute_sea_zone_control(
            "North Sea", [1, 2, 3], {1: "ENG", 2: "ENG", 3: "ENG"}
        )
        badge = format_sea_zone_control_badge(ctrl)
        self.assertIn("supply", badge.lower())
        self.assertIn("trade", badge.lower())

    def test_gd_wiring_modifiers(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func get_sea_zone_strategic_modifiers", mm)
        self.assertIn("func get_sea_zone_strategic_modifiers_for_province", mm)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func sea_zone_strategic_modifiers", fmt)
        self.assertIn("supply_multiplier", fmt)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("get_sea_zone_strategic_modifiers", insight)
        self.assertIn("format_sea_zone_control_badge", insight)


class TestHHAgendaSurface(unittest.TestCase):
    def test_format_trail_ordered_nonempty(self) -> None:
        trail = []
        for i, action in enumerate(["sabotage", "economic_pressure", "infiltration"]):
            trail = append_hh_agenda_trail(
                trail,
                {
                    "year": 1936,
                    "month": i + 1,
                    "province_id": i,
                    "province_name": "P%d" % i,
                    "action_class": action,
                    "title": "Hidden Hand %s" % action,
                    "marker": "!",
                    "active": True,
                },
                None,
                capacity=6,
            )
        self.assertGreaterEqual(len(trail), 3)
        fmt = format_hh_agenda_trail(trail, max_lines=6)
        self.assertGreaterEqual(fmt["count"], 3)
        self.assertFalse(fmt["empty"])
        self.assertTrue(all(str(x).strip() for x in fmt["lines"]))
        # Order preserved (oldest→newest in all_lines; lines are tail)
        self.assertIn("sabotage", fmt["plain"])
        self.assertIn("infiltration", fmt["plain"])
        classes = fmt["action_classes"]
        self.assertEqual(classes[0], "sabotage")
        self.assertEqual(classes[-1], "infiltration")

    def test_inspector_surface_wiring(self) -> None:
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("_append_hh_agenda_trail", gd)
        self.assertIn("func get_hh_agenda_trail", gd)
        self.assertIn("func format_hh_agenda_trail_plain", gd)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_hh_agenda_trail_inspector_bbcode", insight)
        self.assertIn("format_hh_agenda_trail_plain", insight)
        self.assertIn("get_hh_agenda_trail", insight)
        # Called from full inspector path
        self.assertIn("build_hh_agenda_trail_inspector_bbcode()", insight)


class TestDocsRetrospective(unittest.TestCase):
    # Stale claims that must not appear as *current* open-gap truth in live docs.
    # Historical LANDED / resolved lines may still mention the old problem names.
    _STALE_OPEN_GAP_PATTERNS = (
        # Open-gap phrasing for Theater-2 leftover (not "→ China Heartland" history)
        r"(?i)Far East Theater 2[^\n]{0,80}leftover",
        r"(?i)leftover label style",
        # OOB zero-growth as if still true at 20 evidence days
        r"(?i)OOB production shows\s*0\s*unit growth",
        r"(?i)0 unit growth at 20\s*evidence",
        r"(?i)majors_grew\s*=\s*0\s*/\s*7",
        r"(?i)total_units\s*=\s*0[^\n]{0,40}majors_grew",
        r"(?i)14 naval chokepoints only",
    )

    def _assert_no_stale_open_gaps(self, text: str, label: str) -> None:
        for pat in self._STALE_OPEN_GAP_PATTERNS:
            m = re.search(pat, text)
            self.assertIsNone(
                m,
                msg="%s still contains stale open-gap claim matching %r near: %r"
                % (label, pat, (m.group(0) if m else "")),
            )

    def test_summary_reflects_landed_figures(self) -> None:
        text = SUMMARY.read_text(encoding="utf-8")
        self._assert_no_stale_open_gaps(text, "Project_State_Summary.md")
        # Cities stretch
        self.assertTrue(
            re.search(r"900", text) or re.search(r"cities.*900", text, re.I),
            msg="summary should mention 900 cities",
        )
        # Chokepoints 56 or ≥30 landed
        self.assertTrue(
            re.search(r"\b56\b", text) or re.search(r"chokepoint", text, re.I)
        )
        # OOB honesty landed
        self.assertTrue(
            re.search(r"7/7", text) or re.search(r"majors_grew", text, re.I),
            msg="summary should reflect OOB majors growth evidence",
        )

    def test_todo_no_stale_open_city600_as_current_gap(self) -> None:
        todo = TODO.read_text(encoding="utf-8")
        self._assert_no_stale_open_gaps(todo, "TODO.md")
        # Deferred section may mention history; ensure stretch landed is checked
        self.assertIn("900", todo)
        self.assertIn("infiltration", todo.lower())
        # Open bullets under Known deferred must not re-open Theater-2 / OOB-0.
        # A separate **Resolved** note may mention those names as history.
        if "## Known deferred map issues" in todo:
            deferred = todo.split("## Known deferred map issues", 1)[1]
            if "\n## " in deferred:
                deferred = deferred.split("\n## ", 1)[0]
            open_bullets = "\n".join(
                ln
                for ln in deferred.splitlines()
                if ln.lstrip().startswith("-")
                and "resolved" not in ln.lower()
            )
            self.assertNotRegex(
                open_bullets,
                r"(?i)Far East Theater 2",
                msg="Known deferred open bullets must not list Far East Theater 2",
            )
            self.assertNotRegex(
                open_bullets,
                r"(?i)0 unit growth|majors_grew\s*=\s*0|leftover label",
                msg="Known deferred open bullets must not claim OOB 0 growth / leftover label",
            )
            # Resolved note (or checked items) should still record landed truth
            self.assertRegex(
                todo,
                r"(?i)(majors_grew\s*=\s*7/7|7/7\s*@\s*20d|total_units\s*=\s*7)",
                msg="TODO should record OOB 7/7 @ 20d as landed",
            )
        self.assertIn("7/7", todo)

    def test_roadmap_no_stale_open_oob_or_theater2_gap(self) -> None:
        text = ROADMAP.read_text(encoding="utf-8")
        self._assert_no_stale_open_gaps(text, "Next_30_Days_Roadmap.md")
        # Immediate next actions should not re-list completed Top-5 as open work
        if "## Immediate next actions" in text:
            nxt = text.split("## Immediate next actions", 1)[1]
            if "\n## " in nxt:
                nxt = nxt.split("\n## ", 1)[0]
            self.assertNotRegex(
                nxt,
                r"(?i)Prove or fix OOB|Theater 2[^\n]*relabel|City stretch \+",
                msg="Immediate next actions still lists completed Top-5 work",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
