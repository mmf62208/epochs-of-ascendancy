#!/usr/bin/env python3
"""Gates: naval basing level/capacity pure helper + inspector/MapManager wiring."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from naval_basing import (  # noqa: E402
    CAPACITY_ANCHORAGE,
    CAPACITY_MAJOR,
    CAPACITY_NONE,
    CAPACITY_PORT,
    LEVEL_ANCHORAGE,
    LEVEL_MAJOR,
    LEVEL_NONE,
    LEVEL_PORT,
    basing_from_province_signals,
    compute_naval_basing,
    format_naval_basing_badge,
    level_rank,
)

WF = ROOT / "data" / "provinces_world_full"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
LIB = ROOT / "tools" / "map_generation" / "lib" / "naval_basing.py"


class TestNavalBasingPure(unittest.TestCase):
    def test_landlocked_none_zero(self) -> None:
        b = compute_naval_basing(domain="land")
        self.assertEqual(b["level"], LEVEL_NONE)
        self.assertEqual(b["capacity"], CAPACITY_NONE)
        self.assertFalse(b["is_naval"])
        self.assertEqual(format_naval_basing_badge(b), "")

    def test_coastal_anchorage_gt_landlocked(self) -> None:
        land = compute_naval_basing(domain="land")
        coast = compute_naval_basing(domain="coastal_land")
        self.assertEqual(coast["level"], LEVEL_ANCHORAGE)
        self.assertGreater(coast["capacity"], land["capacity"])
        self.assertGreaterEqual(coast["capacity"], CAPACITY_ANCHORAGE)
        badge = format_naval_basing_badge(coast)
        self.assertIn("Naval basing", badge)
        self.assertIn("anchorage", badge.lower())
        self.assertIn("capacity", badge.lower())

    def test_port_and_major_distinct(self) -> None:
        anch = compute_naval_basing(domain="coastal_land")
        port = compute_naval_basing(domain="coastal_land", has_port=True, port_tier=2)
        major = compute_naval_basing(
            domain="coastal_land",
            has_port=True,
            port_tier=3,
            has_naval_shipyard=True,
            is_chokepoint=True,
        )
        self.assertEqual(port["level"], LEVEL_PORT)
        self.assertEqual(major["level"], LEVEL_MAJOR)
        self.assertGreater(port["capacity"], anch["capacity"])
        self.assertGreater(major["capacity"], port["capacity"])
        self.assertGreaterEqual(port["capacity"], CAPACITY_PORT)
        self.assertGreaterEqual(major["capacity"], CAPACITY_MAJOR)
        self.assertGreater(level_rank(major["level"]), level_rank(port["level"]))
        self.assertGreater(level_rank(port["level"]), level_rank(anch["level"]))

    def test_choke_strait_raises_tier(self) -> None:
        plain_coast = compute_naval_basing(domain="coastal_land")
        choke_port = compute_naval_basing(
            domain="coastal_land", is_chokepoint=True, has_port=True, port_tier=2
        )
        strait = compute_naval_basing(domain="strait")
        self.assertGreaterEqual(level_rank(choke_port["level"]), level_rank(LEVEL_PORT))
        self.assertGreater(choke_port["capacity"], plain_coast["capacity"])
        # Strait alone is at least port-class
        self.assertGreaterEqual(level_rank(strait["level"]), level_rank(LEVEL_PORT))
        self.assertTrue(all(isinstance(x["capacity"], int) for x in (plain_coast, choke_port, strait)))
        self.assertTrue(all(x["capacity"] >= 0 for x in (plain_coast, choke_port, strait)))

    def test_open_sea_without_infra_none(self) -> None:
        sea = compute_naval_basing(domain="sea", is_sea=True)
        self.assertEqual(sea["level"], LEVEL_NONE)
        self.assertEqual(sea["capacity"], 0)

    def test_facility_full_coastal_is_port(self) -> None:
        b = compute_naval_basing(domain="coastal_land", facility_tier="full")
        self.assertEqual(b["level"], LEVEL_PORT)
        self.assertGreaterEqual(b["capacity"], CAPACITY_PORT)


class TestNavalBasingWorldSample(unittest.TestCase):
    def test_world_full_coastal_sample_non_none(self) -> None:
        """Batch real world_full coastal/choke signals → ≥1 non-none basing."""
        self.assertTrue(WF.is_dir())
        terrain = json.loads((WF / "province_terrain_layer.json").read_text(encoding="utf-8"))
        provs = terrain.get("provinces") or {}
        choke_ids = set(
            int(x)
            for x in (
                json.loads((WF / "naval_chokepoints.json").read_text(encoding="utf-8")).get(
                    "chokepoint_province_ids"
                )
                or []
            )
        )
        sea = json.loads((WF / "sea_zone_theaters.json").read_text(encoding="utf-8"))
        in_zone = set()
        for z in sea.get("zones") or []:
            for pid in z.get("province_ids") or []:
                in_zone.add(int(pid))

        non_none = 0
        samples = []
        for pid_s, row in list(provs.items())[:800]:
            if not isinstance(row, dict):
                continue
            pid = int(pid_s)
            sig = {
                "province_id": pid,
                "domain": str(row.get("domain", "")),
                "facility_tier": str(row.get("facility_tier", "")),
                "is_chokepoint": pid in choke_ids,
                "in_sea_zone": pid in in_zone,
                "is_coastal": str(row.get("domain", "")).startswith("coast"),
            }
            b = basing_from_province_signals(sig)
            if b["is_naval"]:
                non_none += 1
                if len(samples) < 5:
                    samples.append((pid, b["level"], b["capacity"]))
        # Also force known choke ids through helper
        for pid in list(choke_ids)[:10]:
            row = provs.get(str(pid)) or provs.get(pid) or {}
            b = compute_naval_basing(
                province_id=pid,
                domain=str(row.get("domain", "coastal_land")),
                is_chokepoint=True,
                facility_tier=str(row.get("facility_tier", "")),
                in_sea_zone=pid in in_zone,
            )
            if b["is_naval"]:
                non_none += 1
        self.assertGreaterEqual(
            non_none,
            1,
            msg="expected ≥1 non-none basing from world_full coastal/choke sample; got %s %s"
            % (non_none, samples),
        )


class TestNavalBasingWiring(unittest.TestCase):
    def test_lib_and_gd_shipped(self) -> None:
        self.assertTrue(LIB.is_file())
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func compute_naval_basing", fmt)
        self.assertIn("func format_naval_basing_badge", fmt)
        self.assertIn("major_base", fmt)
        self.assertIn("anchorage", fmt)
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func get_naval_basing", mm)
        self.assertIn("func get_naval_basing_for_province", mm)
        self.assertIn("compute_naval_basing", mm)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("build_naval_basing_badge_bbcode", insight)
        self.assertIn("get_naval_basing", insight)
        self.assertIn("format_naval_basing_badge", insight)
        # Called from full inspector path
        self.assertIn("build_naval_basing_badge_bbcode(province)", insight)


if __name__ == "__main__":
    unittest.main(verbosity=2)
