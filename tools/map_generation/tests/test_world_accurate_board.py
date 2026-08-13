#!/usr/bin/env python3
"""Integrity tests for provinces_world_accurate GIS hybrid board.

Drives real shipped JSON + map_accuracy_qc.run_qc (not a reimplemented checker).
"""
from __future__ import annotations

import json
import sys
import unittest
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_accuracy_qc import run_qc  # noqa: E402
from ne_full_geometry_align import DEFAULT_NE_LAND  # noqa: E402

D = ROOT / "data" / "provinces_world_accurate"
SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"
TEST_RUNNER = ROOT / "scripts" / "core" / "TestRunner.gd"
DIRECTOR_DOCS = (
    ROOT / "docs" / "GAME_STATUS_SNAPSHOT.md",
    ROOT / "docs" / "GAME_DIRECTOR_PLAN.md",
    ROOT / "docs" / "WORLD_CLASS_MAP_REVIEW.md",
)

WATER_T = frozenset({"sea", "ocean", "water", "lake"})
WATER_D = frozenset({"sea", "strait", "lake", "ocean"})


def _is_water(p: dict) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER_T or dom in WATER_D


@unittest.skipUnless(D.is_dir(), "provinces_world_accurate not built")
class TestWorldAccurateBoard(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.base = {
            int(p["id"]): p
            for p in json.loads((D / "provinces_base.json").read_text())["provinces"]
        }
        cls.own = json.loads((D / "province_ownership_1936.json").read_text()).get("owners") or {}

    def test_orphans_and_ne_land(self) -> None:
        report = run_qc(D, ne_path=Path(DEFAULT_NE_LAND), sample_limit=0)
        self.assertTrue(report.get("ok_hard"), report.get("errors"))
        self.assertEqual(report.get("orphan_base_only_count"), 0)
        self.assertEqual(report.get("orphan_geo_only_count"), 0)
        # Pre-US-merge ~8761; post US+full RoW sparse merge ~3.5k
        self.assertGreaterEqual(int(report.get("matched") or 0), 3000)
        rate = report.get("ne_land_hit_rate")
        self.assertIsNotNone(rate)
        self.assertGreaterEqual(float(rate), 0.90, rate)

    def test_hierarchy_and_adjacency_files(self) -> None:
        base = set(self.base)
        mem = json.loads((D / "hierarchy_membership_1936.json").read_text())
        p2r = mem.get("province_to_region") or {}
        assigned = sum(1 for pid in base if int(p2r.get(str(pid), 0) or 0) > 0)
        self.assertEqual(assigned, len(base))

        sr = json.loads((D / "strategic_regions.json").read_text())["regions"]
        for r in sr:
            n = str(r.get("name", ""))
            self.assertTrue(n and not n.startswith("Strategic Region "), n)

        adj = json.loads((D / "province_adjacency.json").read_text())
        method = str(adj.get("method") or "")
        self.assertIn("shared_edge", method)
        a = adj.get("adjacency") or {}
        cover = sum(1 for pid in base if str(pid) in a)
        self.assertEqual(cover, len(base))
        zeros = sum(1 for pid in base if not a.get(str(pid)))
        self.assertEqual(zeros, 0)
        stats = adj.get("stats") or {}
        if "land_shared_coverage" in stats:
            # D5.1 near_vertex residual: floor raised from 0.90 → 0.95
            self.assertGreaterEqual(float(stats["land_shared_coverage"]), 0.95)
        self.assertEqual(int(stats.get("orphan_land_after", 0) or 0), 0)
        # GER Baden-Baden ↔ FRA Bas-Rhin assault edge must survive retune
        a = adj.get("adjacency") or {}
        ger_nbrs = [int(x) for x in (a.get("710173") or [])]
        self.assertIn(710739, ger_nbrs)

        states = json.loads((D / "province_states.json").read_text()).get("states") or []
        self.assertGreaterEqual(len(states), 400)

        choke = json.loads((D / "naval_chokepoints.json").read_text())
        ids = choke.get("chokepoint_province_ids") or []
        self.assertGreaterEqual(len(ids), 10)
        for pid in ids:
            self.assertIn(int(pid), base)

    def test_testrunner_default_scenario_is_world_accurate(self) -> None:
        """Shipped TestRunner default must load the accurate GIS board."""
        self.assertTrue(TEST_RUNNER.is_file(), TEST_RUNNER)
        text = TEST_RUNNER.read_text(encoding="utf-8")
        # Real default assignment (not comments): var scenario_to_load := "world_accurate"
        self.assertRegex(
            text,
            r'var\s+scenario_to_load\s*:=\s*"world_accurate"',
            "TestRunner default scenario must be world_accurate",
        )
        sc = json.loads(SCENARIO.read_text(encoding="utf-8"))
        self.assertEqual(sc.get("use_province_data_dir"), "provinces_world_accurate")
        # D4 log cleanup: ready banner must not claim phase1 471 as the only board.
        self.assertIn("world_accurate GIS hybrid", text)
        self.assertIn("%d-province polygons rendered", text)
        self.assertNotIn(
            "Playtest harness ready: Full Europe map (471 provinces",
            text,
        )

    def test_director_status_docs_present(self) -> None:
        for path in DIRECTOR_DOCS:
            self.assertTrue(path.is_file(), path)
            body = path.read_text(encoding="utf-8")
            self.assertIn("world_accurate", body)
            self.assertIn("8761", body)

    def test_root_status_docs_not_stale_default_board(self) -> None:
        """Root play-entry docs must not claim world_full/phase1 as F5 default."""
        checks = {
            ROOT / "README.md": (
                "world_accurate",
                "8761",
                "phase1_europe_test",  # must NOT appear as Default quick-start
            ),
            ROOT / "TODO.md": ("world_accurate", "8761", None),
            ROOT / "Project_State_Summary.md": ("world_accurate", "8761", None),
            ROOT / "Next_30_Days_Roadmap.md": ("world_accurate", "8761", None),
        }
        for path, (need_a, need_b, forbid_default_line) in checks.items():
            self.assertTrue(path.is_file(), path)
            body = path.read_text(encoding="utf-8")
            self.assertIn(need_a, body, path.name)
            self.assertIn(need_b, body, path.name)
            # Present-tense default must not be world_full alone without accurate
            if path.name == "README.md":
                self.assertNotIn("Default: **phase1_europe_test**", body)
            if path.name == "TODO.md":
                self.assertNotIn("**Default F5:** scenario **`world_full`**", body)
            if path.name == "Project_State_Summary.md":
                self.assertNotIn(
                    "**Default scenario:** `world_full` → `data/provinces_world_full`",
                    body,
                )
            if path.name == "Next_30_Days_Roadmap.md":
                # Historical catalogue may mention world_full; must state accurate default
                self.assertIn("world_accurate", body)
                self.assertIn("supersedes older headers", body.lower())

    def test_id_blocks_present(self) -> None:
        ids = set(self.base)
        # Europe NUTS, US counties, RoW, seas
        self.assertTrue(any(710000 <= i < 800000 for i in ids))
        self.assertTrue(any(800000 <= i < 900000 for i in ids))
        self.assertTrue(any(900000 <= i < 950000 for i in ids))
        self.assertTrue(any(i >= 950000 for i in ids))
        # Post US + full RoW sparse merge ~3520 (was ~4683 T1 / ~5670 / ~8761)
        self.assertGreaterEqual(len(ids), 3000)
        us_n = sum(1 for i in ids if 800000 <= i < 900000)
        self.assertGreaterEqual(us_n, 80)
        self.assertLessEqual(us_n, 200)  # playable merge band (not raw 3221 counties)
        row_n = sum(1 for i in ids if 900000 <= i < 950000)
        self.assertGreaterEqual(row_n, 1200)
        # Count adm0 from any RoW meta (geoboundaries or NE admin1 survivors)
        by_adm0: dict = {}
        geo_or_row = 0
        for pid, p in self.base.items():
            if not (900000 <= int(pid) < 950000):
                continue
            meta = p.get("meta") if isinstance(p.get("meta"), dict) else {}
            a = str(meta.get("adm0_a3") or "")
            if a:
                by_adm0[a] = by_adm0.get(a, 0) + 1
                geo_or_row += 1
        self.assertGreaterEqual(geo_or_row, 1200)
        # Sparse-merged majors: playable floors (not raw ADM2 densify)
        for code, floor in (
            ("CHN", 10),
            ("IND", 10),
            ("BRA", 10),
            ("AUS", 12),
            ("NGA", 2),
            ("EGY", 2),
            ("MEX", 3),
            ("ARG", 5),
            ("RUS", 5),
            ("PAK", 4),
            ("COL", 4),
            # Still-dense SE Asia (not in sparse scopes)
            ("JPN", 10),
            ("THA", 10),
            ("PHL", 10),
            ("AFG", 8),
        ):
            self.assertGreaterEqual(
                by_adm0.get(code, 0),
                floor,
                f"missing playable coverage for {code}",
            )
        self.assertGreaterEqual(len(by_adm0), 90)

    def test_land_ownership_full_coverage(self) -> None:
        land = [pid for pid, p in self.base.items() if not _is_water(p)]
        # Post US + full RoW sparse merge: land ~3.2k (was ~4.3k / ~5.3k / ~8.4k)
        self.assertGreaterEqual(len(land), 3000)
        unowned = [pid for pid in land if not self.own.get(str(pid))]
        self.assertEqual(unowned, [], f"unowned sample {unowned[:20]}")

    def test_1936_major_spheres_not_usa_blob(self) -> None:
        """LATAM/China must not be painted entirely as USA/JAP empire dump."""
        counts = Counter(self.own.values())
        # US: either raw TIGER (~3k counties) or merged playable (~80–180)
        usa_n = int(counts.get("USA", 0) or 0)
        self.assertGreaterEqual(usa_n, 80)
        self.assertLess(usa_n, 3500)  # not all Americas
        us_block = sum(1 for pid in self.base if 800000 <= pid < 900000)
        self.assertGreaterEqual(us_block, 80)
        self.assertLessEqual(us_block, 3300)
        self.assertGreaterEqual(counts.get("BRA", 0), 8)
        self.assertGreaterEqual(counts.get("ARG", 0), 5)
        self.assertGreaterEqual(counts.get("MEX", 0), 4)
        self.assertGreaterEqual(counts.get("CHI", 0), 10)
        self.assertGreaterEqual(counts.get("GER", 0), 200)
        self.assertGreaterEqual(counts.get("ENG", 0), 400)
        self.assertGreaterEqual(counts.get("SOV", 0), 100)
        # China mainland should be CHI, not fully JAP
        chi_land = 0
        jap_on_chn = 0
        for pid, p in self.base.items():
            meta = p.get("meta") if isinstance(p.get("meta"), dict) else {}
            if meta.get("adm0_a3") == "CHN":
                tag = self.own.get(str(pid), "")
                if tag == "CHI":
                    chi_land += 1
                elif tag == "JAP":
                    jap_on_chn += 1
        self.assertGreater(chi_land, jap_on_chn)

    def test_chokepoints_are_water_or_panama(self) -> None:
        choke = json.loads((D / "naval_chokepoints.json").read_text())
        ids = choke.get("chokepoint_province_ids") or []
        self.assertGreaterEqual(len(ids), 15)
        names_lower = []
        for pid in ids:
            p = self.base[int(pid)]
            nm = str(p.get("name") or "").lower()
            names_lower.append(nm)
            ok = _is_water(p) or "panama" in nm
            self.assertTrue(ok, f"inland choke {pid} {p.get('name')}")
        blob = " ".join(names_lower)
        for must in ("gibraltar", "suez", "malacca", "hormuz", "bospor"):
            self.assertIn(must, blob, f"missing choke family {must}")

    def test_scenario_capitals_exist_and_owned(self) -> None:
        self.assertTrue(SCENARIO.is_file())
        sc = json.loads(SCENARIO.read_text())
        for c in sc.get("countries") or []:
            tag = c.get("tag")
            pid = int(c.get("capital_province_id") or 0)
            self.assertIn(pid, self.base, f"{tag} capital {pid} missing")
            self.assertFalse(_is_water(self.base[pid]), f"{tag} capital is water")
            owner = self.own.get(str(pid), "")
            self.assertEqual(owner, tag, f"{tag} capital owner={owner} name={self.base[pid].get('name')}")
        # USA capital should be District of Columbia on accurate board
        usa = next(x for x in sc["countries"] if x["tag"] == "USA")
        self.assertEqual(self.base[int(usa["capital_province_id"])]["name"], "District of Columbia")

    def test_capital_city_layer_labels(self) -> None:
        city = json.loads((D / "province_city_layer.json").read_text()).get("provinces") or {}
        # Stable NUTS / US capitals
        expect = {
            710300: "Berlin",
            710707: "Paris",
            711414: "London",
            800792: "Washington",
            710963: "Rome",
            711112: "Warsaw",
        }
        for pid, label in expect.items():
            row = city.get(str(pid)) or {}
            self.assertEqual(row.get("city_name"), label, pid)
            self.assertGreaterEqual(int(row.get("tier") or 0), 3)
        # RoW densify may renumber SOV/JAP capitals — resolve from scenario
        sc = json.loads(SCENARIO.read_text())
        for tag, label in (("SOV", "Moscow"), ("JAP", "Tokyo")):
            row_c = next(x for x in sc["countries"] if x["tag"] == tag)
            pid = int(row_c["capital_province_id"])
            crow = city.get(str(pid)) or {}
            self.assertEqual(crow.get("city_name"), label, f"{tag} {pid}")
            self.assertGreaterEqual(int(crow.get("tier") or 0), 3)

    def test_ownership_eras_cover_land(self) -> None:
        land = [pid for pid, p in self.base.items() if not _is_water(p)]
        for era in (1910, 1918, 1936, 1945, 2026):
            path = D / f"province_ownership_{era}.json"
            self.assertTrue(path.is_file(), era)
            owners = json.loads(path.read_text()).get("owners") or {}
            unowned = [pid for pid in land if not owners.get(str(pid))]
            self.assertEqual(unowned, [], f"era {era} unowned {unowned[:10]}")
        # Era deltas should differ from 1936 for at least some provinces
        o36 = json.loads((D / "province_ownership_1936.json").read_text())["owners"]
        o10 = json.loads((D / "province_ownership_1910.json").read_text())["owners"]
        o45 = json.loads((D / "province_ownership_1945.json").read_text())["owners"]
        o26 = json.loads((D / "province_ownership_2026.json").read_text())["owners"]
        diff_10 = sum(1 for k, v in o36.items() if o10.get(k) != v)
        diff_45 = sum(1 for k, v in o36.items() if o45.get(k) != v)
        diff_26 = sum(1 for k, v in o36.items() if o26.get(k) != v)
        self.assertGreater(diff_10, 50)
        self.assertGreater(diff_45, 50)
        self.assertGreater(diff_26, 200)


if __name__ == "__main__":
    unittest.main()
