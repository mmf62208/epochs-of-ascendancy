#!/usr/bin/env python3
"""ENG-MAP-FINISH-2: leftover faces closed, Gulf of America names, no new ids.

Fails on the merge-forward base: New York West still covers Lake Ontario,
Washington still has uncovered land triangles over 20 px², St Lawrence / ON-QC
specks at or over 1 px² remain, and the live sea is still named Gulf of Mexico
Zone. Passes once those rings and names are fixed. Province ids stay 3596 in
the same order. Nothing is renamed Lake America.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from canada_hole_measure import (  # noqa: E402
    _area,
    _clean,
    _winding,
    adjacency_asymmetric,
    count_invalid_polygons,
    count_land_sea_overlaps,
    measure_canada_holes,
)
from eng_map_finish2_product import (  # noqa: E402
    DC_FACE_MIN,
    DC_ID,
    ERIE_TAIL_BAND_PX,
    GULF_ACCURATE_ID,
    GULF_FULL_ID,
    GULF_NEW,
    GULF_OLD,
    HAMILTON_NIAGARA_ID,
    LAKE_AMERICA,
    LAKE_ERIE_ID,
    LAKE_ONTARIO_ID,
    LEFTOVER_LAND_IDS,
    NY_WEST_ID,
    OVERLAP_PX_MAX,
    erie_shore_tail_indices,
    gulf_name_hits,
    lake_america_hits,
    land_water_overlap_px,
    measure_washington_faces,
    ny_west_city_hits,
    speck_holes,
)
from great_lakes_water_province_product import lonlat_to_canvas  # noqa: E402

BOARD = ROOT / "data" / "provinces_world_accurate"


def _load():
    geo = json.loads((BOARD / "provinces_geometry.json").read_text(encoding="utf-8"))
    base = json.loads((BOARD / "provinces_base.json").read_text(encoding="utf-8"))
    adj = json.loads((BOARD / "province_adjacency.json").read_text(encoding="utf-8"))["adjacency"]
    return geo, base, adj


class EngMapFinish2Test(unittest.TestCase):
    def test_ids_gulf_name_and_no_lake_america(self) -> None:
        geo, base, adj = _load()
        geo_ids = [int(g["id"]) for g in geo["provinces"]]
        base_ids = [int(p["id"]) for p in base["provinces"]]
        self.assertEqual(geo_ids, base_ids)
        self.assertEqual(len(geo_ids), 3596)
        self.assertEqual(geo_ids[0], 710000)
        self.assertEqual(geo_ids[-1], 906138)
        names = {int(p["id"]): p.get("name") for p in base["provinces"]}
        domains = {int(p["id"]): p.get("domain") for p in base["provinces"]}
        self.assertEqual(names[LAKE_ONTARIO_ID], "Lake Ontario")
        self.assertEqual(domains[LAKE_ONTARIO_ID], "lake")
        self.assertEqual(names[GULF_ACCURATE_ID], GULF_NEW)
        self.assertNotEqual(names[GULF_ACCURATE_ID], GULF_OLD)
        self.assertEqual(lake_america_hits(BOARD), [])
        self.assertEqual(gulf_name_hits(), [])
        full = json.loads((ROOT / "data" / "provinces_world_full" / "provinces_base.json").read_text(encoding="utf-8"))
        full_names = {int(p["id"]): p.get("name") for p in full["provinces"]}
        self.assertEqual(full_names[GULF_FULL_ID], GULF_NEW)
        self.assertEqual(len(adj), 3596)
        self.assertEqual(adjacency_asymmetric(BOARD), [])

    def test_ontario_and_ny_west_agree(self) -> None:
        geo, base, _adj = _load()
        rings = {}
        anchors = {}
        for g in geo["provinces"]:
            pts = _clean([(float(p[0]), float(p[1])) for p in (g.get("points") or [])])
            if len(pts) >= 3:
                rings[int(g["id"])] = pts
            anchors[int(g["id"])] = [float(g["label_anchor"][0]), float(g["label_anchor"][1])]
        ont = rings[LAKE_ONTARIO_ID]
        ny = rings[NY_WEST_ID]
        erie = rings[LAKE_ERIE_ID]
        self.assertGreaterEqual(len(ont), 64)
        self.assertGreater(abs(_area(ont)), 1000.0)
        self.assertLessEqual(land_water_overlap_px(ny, ont), OVERLAP_PX_MAX)
        self.assertLessEqual(land_water_overlap_px(ny, erie), OVERLAP_PX_MAX)
        ax, ay = anchors[NY_WEST_ID]
        self.assertNotEqual(_winding(ny, ax, ay), 0)
        self.assertEqual(_winding(ont, ax, ay), 0)
        self.assertEqual(_winding(erie, ax, ay), 0)
        cities = ny_west_city_hits(ny)
        self.assertTrue(all(cities.values()), msg=cities)
        # Toronto city is land, not inside the lake ring.
        tx, ty = lonlat_to_canvas(-79.38, 43.65)
        self.assertEqual(_winding(ont, tx, ty), 0)
        # Design basin centroid stays water.
        dx, dy = lonlat_to_canvas(-77.90, 43.70)
        self.assertNotEqual(_winding(ont, dx, dy), 0)

    def test_leftover_faces_closed(self) -> None:
        dc = measure_washington_faces(BOARD)
        big_dc = [h for h in dc["holes"] if h["area_px2"] >= DC_FACE_MIN]
        self.assertEqual([(h["area_px2"], h["centroid"]) for h in big_dc], [])
        report = measure_canada_holes(BOARD, use_natural_earth=True)
        specks = speck_holes(report)
        self.assertEqual(
            [(h["area_px2"], h.get("kind"), h["centroid"]) for h in specks],
            [],
        )

    def test_map_integrity_not_up(self) -> None:
        inv = count_invalid_polygons(BOARD)
        our = {
            NY_WEST_ID,
            LAKE_ONTARIO_ID,
            DC_ID,
            801515,
            800273,
            HAMILTON_NIAGARA_ID,
            903047,
            903045,
            903044,
            903046,
            903050,
        }
        bad_ours = [row for row in inv.get("ids") or [] if int(row.get("id") or 0) in our]
        self.assertEqual(bad_ours, [])
        overlaps = count_land_sea_overlaps(BOARD, min_px=2)
        lake_pairs = [
            row
            for row in overlaps.get("pairs") or []
            if int(row.get("water") or 0) == LAKE_ONTARIO_ID and int(row.get("px") or 0) > OVERLAP_PX_MAX
        ]
        self.assertEqual(lake_pairs, [])

    def test_hamilton_niagara_not_in_erie(self) -> None:
        """Fails on 2e1e6f98: #903049 sends a thin tail along Erie to Windsor."""
        geo, _base, _adj = _load()
        rings = {}
        anchors = {}
        for g in geo["provinces"]:
            pts = _clean([(float(p[0]), float(p[1])) for p in (g.get("points") or [])])
            if len(pts) >= 3:
                rings[int(g["id"])] = pts
            anchors[int(g["id"])] = [float(g["label_anchor"][0]), float(g["label_anchor"][1])]
        erie = rings[LAKE_ERIE_ID]
        ham = rings[HAMILTON_NIAGARA_ID]
        tails = erie_shore_tail_indices(ham, erie, anchors[HAMILTON_NIAGARA_ID])
        self.assertEqual(tails, [])
        west_x = min(p[0] for p in ham)
        # Peninsula stays east of London ON / Long Point; Windsor is ~2204.
        self.assertGreater(west_x, 2250.0)
        ax, ay = anchors[HAMILTON_NIAGARA_ID]
        self.assertNotEqual(_winding(ham, ax, ay), 0)
        self.assertEqual(_winding(erie, ax, ay), 0)
        self.assertLessEqual(land_water_overlap_px(ham, erie), OVERLAP_PX_MAX)
        hx, hy = lonlat_to_canvas(-79.87, 43.26)
        nx, ny = lonlat_to_canvas(-79.08, 43.09)
        self.assertNotEqual(_winding(ham, hx, hy), 0)
        self.assertNotEqual(_winding(ham, nx, ny), 0)
        self.assertEqual(_winding(erie, hx, hy), 0)
        leftover_tails = []
        probe = anchors[HAMILTON_NIAGARA_ID]
        for pid in LEFTOVER_LAND_IDS:
            if pid not in rings or pid == LAKE_ONTARIO_ID:
                continue
            hits = erie_shore_tail_indices(rings[pid], erie, probe, band=ERIE_TAIL_BAND_PX)
            if hits:
                leftover_tails.append((pid, hits))
        self.assertEqual(leftover_tails, [])


if __name__ == "__main__":
    unittest.main()
