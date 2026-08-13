#!/usr/bin/env python3
"""Gates for full-world province dataset."""
from __future__ import annotations

import json
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WF = ROOT / "data" / "provinces_world_full"


class TestWorldFull(unittest.TestCase):
    def test_exists_and_scale(self) -> None:
        self.assertTrue((WF / "provinces_base.json").exists())
        base = json.loads((WF / "provinces_base.json").read_text())
        geom = json.loads((WF / "provinces_geometry.json").read_text())
        self.assertEqual(len(base["provinces"]), len(geom["provinces"]))
        self.assertGreaterEqual(len(base["provinces"]), 2200)
        meta = base.get("meta") or {}
        self.assertTrue(meta.get("world_full") or meta.get("geometry_space") == "world")
        self.assertTrue(meta.get("geometry_world_native") or meta.get("geometry_space") == "world")

    def test_all_major_theaters_present(self) -> None:
        provs = json.loads((WF / "provinces_base.json").read_text())["provinces"]
        theaters = Counter(p.get("theater") for p in provs)
        for t in (
            "europe_core",
            "mena_africa",
            "far_east",
            "north_america",
            "south_america",
            "africa",
            "sea",
            "pacific",
            "oceania",
            "central_asia",
        ):
            self.assertIn(t, theaters, msg=f"missing theater {t}: {theaters}")
            self.assertGreaterEqual(theaters[t], 5)

    def test_underserved_theaters_densified(self) -> None:
        """Wave-2 densify targets non-Europe theaters (africa / SA / pacific / oceania)."""
        provs = json.loads((WF / "provinces_base.json").read_text())["provinces"]
        theaters = Counter(p.get("theater") for p in provs)
        # Pre-wave2 baselines were africa~52, south_america~60, pacific~10, oceania~21
        self.assertGreaterEqual(theaters["africa"], 100)
        self.assertGreaterEqual(theaters["south_america"], 90)
        grown = sum(
            1
            for t in ("africa", "south_america", "pacific", "oceania", "central_asia")
            if theaters.get(t, 0) >= 25
        )
        self.assertGreaterEqual(grown, 2, msg=f"need ≥2 under-served theaters densified: {theaters}")

    def test_sea_share_band(self) -> None:
        provs = json.loads((WF / "provinces_base.json").read_text())["provinces"]
        sea = sum(1 for p in provs if p.get("domain") in ("sea", "strait", "lake"))
        share = sea / len(provs)
        self.assertGreaterEqual(share, 0.10)
        self.assertLessEqual(share, 0.45)

    def test_world_native_geometry_bounds(self) -> None:
        geom = json.loads((WF / "provinces_geometry.json").read_text())["provinces"]
        xs, ys = [], []
        for g in geom:
            for p in g.get("points") or []:
                xs.append(float(p[0]))
                ys.append(float(p[1]))
        # World equirectangular unscaled ~0..8192 x 0..4096 (with margins)
        self.assertLess(min(xs), 2000)
        self.assertGreater(max(xs), 6000)
        self.assertLess(min(ys), 1500)
        self.assertGreater(max(ys), 2500)

    def test_scenario(self) -> None:
        scen = json.loads((ROOT / "data" / "scenarios" / "world_full.json").read_text())
        self.assertEqual(scen.get("use_province_data_dir"), "provinces_world_full")
        self.assertTrue(str(scen.get("start_date", "")).startswith("1936"))

    def test_1936_leader_roster_covers_world_full_tags(self) -> None:
        """world_full uses LeaderManager 1918+1936 chain; every scenario tag needs ≥1 active leader."""
        scen = json.loads((ROOT / "data" / "scenarios" / "world_full.json").read_text())
        tags = {str(c["tag"]) for c in scen.get("countries") or []}
        self.assertTrue(tags)
        merged: dict = {}
        for path in (
            ROOT / "data" / "leaders" / "historical_leaders_1918.json",
            ROOT / "data" / "leaders" / "historical_leaders_1936.json",
        ):
            for entry in json.loads(path.read_text())["leaders"]:
                lid = entry.get("leader_id")
                if lid:
                    merged[lid] = entry
        year = 1936
        by_tag: Counter = Counter()
        for e in merged.values():
            start = int(e.get("start_year") or 0)
            end = int(e.get("end_year") or 0)
            if start > 0 and year < start:
                continue
            if end > 0 and year > end:
                continue
            by_tag[str(e.get("country_tag") or "")] += 1
        for tag in tags:
            self.assertGreaterEqual(by_tag.get(tag, 0), 1, msg=f"tag {tag} has no 1936-active leader")
        for major in ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"):
            if major in tags:
                self.assertGreaterEqual(by_tag.get(major, 0), 2, msg=f"major {major} needs ≥2 leaders")

    def test_leader_manager_maps_world_full_to_1936_chain(self) -> None:
        """Static gate: LeaderManager.gd must chain world_full/grand_theater to 1918+1936 rosters."""
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn('"world_full"', lm)
        self.assertIn('"grand_theater"', lm)
        # Roster chain entries for full-world scenarios
        self.assertIn("world_full", lm)
        self.assertIn("HISTORICAL_LEADERS_1918_PATH", lm)
        self.assertIn("HISTORICAL_LEADERS_1936_PATH", lm)


if __name__ == "__main__":
    unittest.main(verbosity=2)
