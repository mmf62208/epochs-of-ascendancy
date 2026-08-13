#!/usr/bin/env python3
"""Gates: slot save UI list, GIS coastline design prep, sea-zone control stub."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from save_slot_ui import (  # noqa: E402
    DEFAULT_BROWSER_SLOTS,
    build_save_slot_list,
    format_slot_row,
    slot_list_has_empty_and_occupied,
)
from sea_zone_control import (  # noqa: E402
    compute_sea_zone_control,
    control_for_zones_payload,
    format_sea_zone_control_badge,
)

WF = ROOT / "data" / "provinces_world_full"
GD_SL = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"
GD_MENU = ROOT / "scripts" / "ui" / "MainMenu.gd"
GD_TOP = ROOT / "scripts" / "ui" / "TopInfoBar.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GIS_DOC = ROOT / "docs" / "GIS_COASTLINE_INGEST_DESIGN.md"
GIS_STUB = ROOT / "tools" / "map_generation" / "scripts" / "ingest_gis_coastlines.py"


class TestSlotSaveUi(unittest.TestCase):
    def test_empty_vs_occupied_rows(self) -> None:
        occupied = [
            {
                "slot": "quicksave",
                "metadata": {
                    "timestamp": "2026-07-11T12:00:00",
                    "scenario_id": "world_full",
                    "player_tag": "GER",
                },
            }
        ]
        rows = build_save_slot_list(occupied)
        self.assertGreaterEqual(len(rows), len(DEFAULT_BROWSER_SLOTS))
        flags = slot_list_has_empty_and_occupied(rows)
        self.assertTrue(flags["has_occupied"])
        self.assertTrue(flags["has_empty"])
        qs = next(r for r in rows if r["slot"] == "quicksave")
        self.assertTrue(qs["occupied"])
        self.assertTrue(qs["can_load"])
        self.assertEqual(qs["api_load"], "load_game_detailed")
        self.assertEqual(qs["api_save"], "save_game_detailed")
        empty = next(r for r in rows if r["slot"] == "slot1")
        self.assertFalse(empty["occupied"])
        self.assertFalse(empty["can_load"])
        self.assertIn("empty", empty["label"])

    def test_format_slot_row_apis(self) -> None:
        row = format_slot_row("autosave", False, {})
        self.assertEqual(row["status"], "empty")
        self.assertEqual(row["api_save"], "save_game_detailed")

    def test_shipped_wiring_detailed_apis(self) -> None:
        sl = GD_SL.read_text(encoding="utf-8")
        self.assertIn("func list_saves", sl)
        self.assertIn("func list_slots_for_ui", sl)
        self.assertIn("func save_game_detailed", sl)
        self.assertIn("func load_game_detailed", sl)
        self.assertIn("BROWSER_SLOTS", sl)
        menu = GD_MENU.read_text(encoding="utf-8")
        self.assertIn("list_slots_for_ui", menu)
        self.assertIn("save_game_detailed", menu)
        self.assertIn("load_game_detailed", menu)
        top = GD_TOP.read_text(encoding="utf-8")
        self.assertIn("list_slots_for_ui", top)
        self.assertIn("load_game_detailed", top)
        self.assertIn("save_game_detailed", top)


class TestGisCoastlineDesign(unittest.TestCase):
    def test_design_doc_sections(self) -> None:
        self.assertTrue(GIS_DOC.is_file(), msg="GIS design missing")
        text = GIS_DOC.read_text(encoding="utf-8")
        for heading in (
            "Pipeline entry",
            "Outputs",
            "Id stability",
            "Non-goals",
        ):
            self.assertIn(heading, text, msg=heading)

    def test_ingest_dry_run_real_metrics_write_gated(self) -> None:
        """GIS ingest is past design-only stub: real matched metrics; --write needs --pilot."""
        self.assertTrue(GIS_STUB.is_file())
        r = subprocess.run(
            [
                sys.executable,
                str(GIS_STUB),
                "--dir",
                "data/provinces_world_full",
            ],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(r.returncode, 0, msg=r.stdout + r.stderr)
        self.assertIn("DRY-RUN", r.stdout)
        self.assertIn("id_stable: true", r.stdout)
        self.assertNotIn("stub does not align GIS", r.stdout)
        # Real alignment: matched is not the fixed stub zero line
        self.assertNotRegex(r.stdout, r"matched:\s*0\s*\(stub")
        matched = None
        for line in r.stdout.splitlines():
            if "matched:" in line and "unmatched" not in line:
                try:
                    matched = int(line.split("matched:")[1].strip().split()[0])
                except (IndexError, ValueError):
                    pass
        self.assertIsNotNone(matched)
        self.assertGreaterEqual(matched, 1)
        # --write without --pilot still refused
        r2 = subprocess.run(
            [sys.executable, str(GIS_STUB), "--write"],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(r2.returncode, 2)
        self.assertIn("REFUSED", r2.stderr)


class TestSeaZoneControl(unittest.TestCase):
    def test_compute_control_owned_and_contested(self) -> None:
        pids = [1, 2, 3, 4]
        owners = {1: "ENG", 2: "ENG", 3: "GER", 4: "ENG"}
        ctrl = compute_sea_zone_control("North Sea", pids, owners)
        self.assertEqual(ctrl["controller"], "ENG")
        self.assertFalse(ctrl["unowned"])
        self.assertIn("ENG", ctrl["summary"])

        contested_owners = {1: "ENG", 2: "GER", 3: "GER", 4: "ENG"}
        c2 = compute_sea_zone_control("Channel", pids, contested_owners)
        self.assertTrue(c2["contested"])
        self.assertIn("contested", c2["summary"].lower())

        empty = compute_sea_zone_control("Open", [10, 11], {})
        self.assertTrue(empty["unowned"])
        badge = format_sea_zone_control_badge(empty)
        self.assertIn("unowned", badge.lower())

    def test_shipped_world_full_zones(self) -> None:
        sea = json.loads((WF / "sea_zone_theaters.json").read_text(encoding="utf-8"))
        owners = json.loads((WF / "province_ownership_1936.json").read_text()).get(
            "owners"
        ) or {}
        # Build owners that may include coastal land only — also tag sea pids if present
        zones = sea.get("zones") or []
        results = control_for_zones_payload(zones, owners)
        self.assertGreaterEqual(len(results), 1)
        # At least one zone should produce a non-empty summary string
        self.assertTrue(all(str(r.get("summary", "")) for r in results))
        # Prefer a zone with some ownership signal if any tagged provinces exist in data
        any_ctrl = [r for r in results if not r.get("unowned")]
        # Ownership may not cover open ocean; unowned is valid. If any owned, controller set.
        for r in any_ctrl:
            self.assertTrue(r.get("controller"))
            badge = format_sea_zone_control_badge(r)
            self.assertIn("Sea zone", badge)

        # Force synthetic coastal control on first zone to prove badge path with real zone name
        z0 = zones[0]
        zname = str(z0.get("name"))
        pids = list(z0.get("province_ids") or [])[:4]
        forced = {int(pids[0]): "ENG", int(pids[1]): "ENG"} if len(pids) >= 2 else {}
        if forced:
            c = compute_sea_zone_control(zname, pids, forced)
            self.assertFalse(c["unowned"])
            self.assertEqual(c["controller"], "ENG")
            self.assertIn(zname, c["summary"])

    def test_gd_wiring(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func get_sea_zone_control", mm)
        self.assertIn("func get_sea_zone_control_for_province", mm)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("get_sea_zone_control", insight)
        self.assertIn("format_sea_zone_control_badge", insight)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func format_sea_zone_control_badge", fmt)


if __name__ == "__main__":
    unittest.main(verbosity=2)
