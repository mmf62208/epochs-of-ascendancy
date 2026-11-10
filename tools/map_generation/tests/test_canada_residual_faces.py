#!/usr/bin/env python3
"""MAP-2a residual: Canadian enclosed faces at or over 5 px² stay closed.

The #159 pass closed every face over 100 px². Showcase zoom still showed the
Great Lakes, St Lawrence, and border slivers between 5 and 100 px². This
guard fails while any of those faces is still an enclosed hole. No new
province id.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from canada_hole_measure import choose_absorb_target, measure_canada_holes  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"


class CanadaResidualFaceTest(unittest.TestCase):
    def test_ids_stay_in_order(self) -> None:
        base = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))
        geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
        base_ids = [int(p["id"]) for p in base["provinces"]]
        geo_ids = [int(g["id"]) for g in geo["provinces"]]
        self.assertEqual(geo_ids, base_ids)
        self.assertEqual(len(geo_ids), 3596)
        self.assertLess(max(i for i in geo_ids if i < 950000), 906139)

    def test_no_residual_face_at_or_over_5(self) -> None:
        report = measure_canada_holes(BOARD, use_natural_earth=False)
        self.assertEqual(report["province_count"], 3596)
        big = [h for h in report["holes"] if h["area_px2"] >= 5.0]
        self.assertEqual(
            [(h["area_px2"], h["centroid"]) for h in big],
            [],
        )

    def test_border_and_lake_choices(self) -> None:
        # Quebec–Maine height of land, equal edges: near-tie stays with Canada
        # even when the US neighbour is listed first.
        maine = {
            "kind": "gap",
            "lon": -70.072,
            "lat": 46.342,
            "water_name": "",
            "surrounding": [
                {"id": 800270, "domain": "land", "adm0": "", "edge_px": 19.0, "name": "Maine South"},
                {"id": 903030, "domain": "land", "adm0": "CAN", "edge_px": 19.0, "name": "Chaudière-Appalaches"},
                {"id": 802629, "domain": "land", "adm0": "", "edge_px": 8.0, "name": "Maine North"},
            ],
        }
        self.assertEqual(choose_absorb_target(maine), 903030)
        # Quebec–Vermont 45th, the #159 near-tie (Vermont 44.7, Estrie 44.0).
        vermont = {
            "kind": "gap",
            "lon": -72.5,
            "lat": 45.0,
            "water_name": "",
            "surrounding": [
                {"id": 800648, "domain": "land", "adm0": "", "edge_px": 44.7, "name": "Vermont"},
                {"id": 903031, "domain": "land", "adm0": "CAN", "edge_px": 44.0, "name": "Estrie"},
            ],
        }
        self.assertEqual(choose_absorb_target(vermont), 903031)
        # Lake Huron already has 950335 on the border, so the lake wins over
        # the longer land edge.
        huron = {
            "kind": "water",
            "lon": -83.567,
            "lat": 46.201,
            "water_name": "Lake Huron",
            "surrounding": [
                {"id": 903053, "domain": "land", "adm0": "CAN", "edge_px": 27.9, "name": "Northeast / Nord-est"},
                {"id": 800283, "domain": "land", "adm0": "", "edge_px": 13.6, "name": "Michigan North"},
                {"id": 950335, "domain": "lake", "adm0": "", "edge_px": 13.3, "name": "Lake Huron"},
            ],
        }
        self.assertEqual(choose_absorb_target(huron), 950335)
        # Lake Saint Clair has no lake province. Longest bordering land edge.
        clair = {
            "kind": "water",
            "lon": -82.583,
            "lat": 42.407,
            "water_name": "Lake Saint Clair",
            "surrounding": [
                {"id": 903051, "domain": "land", "adm0": "CAN", "edge_px": 17.8, "name": "Windsor--Sarnia"},
                {"id": 800284, "domain": "land", "adm0": "", "edge_px": 7.2, "name": "Michigan South"},
            ],
        }
        self.assertEqual(choose_absorb_target(clair), 903051)
        # Whitefish Bay water whose lake ring does not share an edge. A bridge
        # would cross Michigan. Longest land edge is Northeast / Nord-est.
        superior_gap = {
            "kind": "water",
            "lon": -84.561,
            "lat": 46.861,
            "water_name": "Lake Superior",
            "surrounding": [
                {"id": 903053, "domain": "land", "adm0": "CAN", "edge_px": 7.0, "name": "Northeast / Nord-est"},
                {"id": 800283, "domain": "land", "adm0": "", "edge_px": 5.0, "name": "Michigan North"},
            ],
        }
        self.assertEqual(choose_absorb_target(superior_gap), 903053)


if __name__ == "__main__":
    unittest.main()
