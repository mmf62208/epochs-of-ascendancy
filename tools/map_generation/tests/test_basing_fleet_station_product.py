"""Pure tests: treaty basing tips fleet station preference + live hooks."""
from __future__ import annotations
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from basing_fleet_station_product import (  # noqa: E402
    build_basing_fleet_station_primary_command_product,
    primary_command_dead_audit,
)
from naval_basing import compute_naval_basing  # noqa: E402
from naval_fleet_ops import (  # noqa: E402
    score_fleet_station_candidate,
    treaty_basing_beats_unowned_foreign,
)


class TestBasingFleetStation(unittest.TestCase):
    def test_treaty_nearly_owned(self):
        maj = compute_naval_basing(
            domain="coastal_land", has_naval_shipyard=True, port_tier=3, province_id=9,
        )
        raw = score_fleet_station_candidate(maj, is_owned=False, has_treaty_basing=False)
        treaty = score_fleet_station_candidate(maj, is_owned=False, has_treaty_basing=True)
        owned = score_fleet_station_candidate(maj, is_owned=True)
        self.assertGreater(treaty["score"], raw["score"])
        self.assertGreater(owned["score"], treaty["score"])  # owned still slightly better
        self.assertTrue(treaty["has_treaty_basing"])

    def test_treaty_beats_owned_anchorage(self):
        anch = compute_naval_basing(domain="coastal_land", is_coastal=True, province_id=1)
        maj = compute_naval_basing(
            domain="coastal_land", has_naval_shipyard=True, port_tier=3, is_chokepoint=True, province_id=2,
        )
        tip = treaty_basing_beats_unowned_foreign(anch, maj)
        self.assertTrue(tip["ok"])
        self.assertTrue(tip["prefer_treaty"])

    def test_primary_hooks(self):
        self.assertTrue(primary_command_dead_audit()["ok"])
        p = build_basing_fleet_station_primary_command_product()
        self.assertTrue(p["all_majors_ok"])
        gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
        self.assertIn("func apply_basing_fleet_station_primary_live", gd)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("basing_fleet_station_primary_live=1", sl)
        mm = (ROOT / "scripts" / "map" / "MapManager.gd").read_text(encoding="utf-8")
        self.assertIn("func get_fleet_station_access_context", mm)
        self.assertIn("has_treaty_basing", mm)
        fmt = (ROOT / "scripts" / "map" / "MapPolishFormatters.gd").read_text(encoding="utf-8")
        self.assertIn("has_treaty_basing", fmt)


if __name__ == "__main__":
    unittest.main()
