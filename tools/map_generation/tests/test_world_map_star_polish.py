#!/usr/bin/env python3
"""Gates for world map-star polish: names, cities ≥750, chokepoints ≥30."""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

from polish_world_province_names import (  # noqa: E402
    is_residual_label,
    is_robotic,
    polish_names,
    run_on_dir as polish_run,
)
from seed_world_city_layer import run_on_dir as city_run  # noqa: E402
from expand_world_naval_chokepoints import expand, MIN_CHOKEPOINTS  # noqa: E402

WF = ROOT / "data" / "provinces_world_full"
SECTOR_RE = re.compile(r"\bSector\s+[A-Z]\b", re.I)
BASIN_COORD_RE = re.compile(r"Basin\s+-?\d+_-?\d+", re.I)


class TestNamePolish(unittest.TestCase):
    def test_polish_clears_sector_and_basin(self) -> None:
        sample = [
            {"id": 1, "name": "Tunis Sector B"},
            {"id": 2, "name": "Atlantic Basin -60_-40"},
            {"id": 3, "name": "Tokyo Theater"},
            {"id": 4, "name": "Paris"},
        ]
        stats = polish_names(sample)
        self.assertEqual(stats["unique_names"], 4)
        self.assertEqual(stats["robotic_remaining"], 0)
        names = [p["name"] for p in sample]
        self.assertFalse(any(SECTOR_RE.search(n) for n in names))
        self.assertFalse(any(BASIN_COORD_RE.search(n) for n in names))
        self.assertIn("Paris", names)

    def test_shipped_world_names_not_robotic(self) -> None:
        base = json.loads((WF / "provinces_base.json").read_text())["provinces"]
        robotic = [p for p in base if is_robotic(str(p.get("name") or ""))]
        # After write this should be empty; if not yet written, fail loudly
        self.assertEqual(
            len(robotic),
            0,
            msg=f"robotic names remain e.g. {[(p['id'], p.get('name')) for p in robotic[:5]]}",
        )
        names = [str(p.get("name") or "") for p in base]
        self.assertEqual(len(names), len(set(names)))

    def test_shipped_no_numbered_waters_or_district_outliers(self) -> None:
        base = json.loads((WF / "provinces_base.json").read_text())["provinces"]
        residual = [p for p in base if is_residual_label(str(p.get("name") or ""))]
        self.assertEqual(
            residual,
            [],
            msg=f"residual labels remain e.g. {[(p['id'], p.get('name')) for p in residual[:8]]}",
        )
        waters_n = [
            p["name"]
            for p in base
            if re.search(r"Waters\s+\d+\s*$", str(p.get("name") or ""))
        ]
        self.assertEqual(waters_n, [], msg=waters_n[:8])
        # Lake District is the only allowed *District real-world label
        districts = [
            p["name"] for p in base if re.search(r"\bDistrict\s*$", str(p.get("name") or ""))
        ]
        for d in districts:
            self.assertEqual(d, "Lake District")


class TestCityExpansion(unittest.TestCase):
    def test_seed_reaches_750(self) -> None:
        # Drive real seed pipeline (no write) — must hit ≥750 with far=0 on world_full.
        stats = city_run(WF, write=False, min_nonempty=750)
        self.assertGreaterEqual(stats["nonempty_cities"], 750, msg=stats)
        self.assertEqual(stats["cities_far_from_anchor"], 0, msg=stats)

    def test_shipped_city_layer_count(self) -> None:
        city = json.loads((WF / "province_city_layer.json").read_text())
        provs = city.get("provinces") or {}
        nonempty = sum(
            1
            for v in provs.values()
            if isinstance(v, dict) and v.get("cities")
        )
        self.assertGreaterEqual(nonempty, 750, msg=f"shipped nonempty={nonempty}")
        # Stretch aspiration (900) when seed can place without far anchors
        self.assertGreaterEqual(nonempty, 750)


class TestNavalChokepoints(unittest.TestCase):
    def test_expand_min_count(self) -> None:
        out = expand(WF)
        self.assertGreaterEqual(len(out["chokepoint_province_ids"]), MIN_CHOKEPOINTS)

    def test_shipped_chokepoints(self) -> None:
        payload = json.loads((WF / "naval_chokepoints.json").read_text())
        ids = payload.get("chokepoint_province_ids") or []
        self.assertGreaterEqual(len(ids), 30)
        geom_ids = {
            int(p["id"])
            for p in json.loads((WF / "provinces_geometry.json").read_text())["provinces"]
        }
        for pid in ids:
            self.assertIn(int(pid), geom_ids)


if __name__ == "__main__":
    unittest.main(verbosity=2)
