#!/usr/bin/env python3
"""GAP-USSR-WEST: UkrSSR oblasts, Moscow/Leningrad re-ring, Black Sea tile.

Mutants edit generator or product source, reload it, and do not write the board.
"""
from __future__ import annotations

import json
import unittest
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "generate_gap_ussr_west.py"
PRODUCT = ROOT / "tools" / "map_generation" / "lib" / "gap_ussr_west_product.py"
D = ROOT / "data" / "provinces_world_accurate"
GEN_ORIGINAL = SCRIPT.read_text(encoding="utf-8")
PROD_ORIGINAL = PRODUCT.read_text(encoding="utf-8")

NEW_IDS = list(range(905889, 905900))
SEA_IDS = (950124, 950006, 950123)
YEARS = (1910, 1918, 1936, 1945, 2026)
EXPECT_OWNER = {1910: "RUS", 1918: "SOV", 1936: "SOV", 1945: "SOV", 2026: "RUS"}
LAYER_NAMES = (
    "province_ownership_1910.json",
    "province_ownership_1918.json",
    "province_ownership_1936.json",
    "province_ownership_1945.json",
    "province_ownership_2026.json",
    "hierarchy_membership_1910.json",
    "hierarchy_membership_1918.json",
    "hierarchy_membership_1936.json",
    "hierarchy_membership_1945.json",
    "hierarchy_membership_2026.json",
    "province_terrain_layer.json",
    "province_economy_layer.json",
    "province_resources_layer.json",
    "strategic_regions.json",
    "hierarchy_scaffold.json",
    "provinces_base.json",
    "provinces_geometry.json",
    "province_city_layer.json",
    "province_states.json",
    "province_adjacency.json",
)


def _load_mod(path: Path, name: str):
    # exec avoids a same-second .pyc reuse when mutants rewrite the source.
    import types

    src = path.read_text(encoding="utf-8")
    mod = types.ModuleType(name)
    mod.__file__ = str(path)
    exec(compile(src, str(path), "exec"), mod.__dict__)
    return mod


@contextmanager
def _mutated(path: Path, original: str, old: str, new: str, name: str):
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise AssertionError("mutant needle missing or not unique: %r" % old)
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    try:
        yield _load_mod(path, name)
    finally:
        path.write_text(original, encoding="utf-8")


def _read(name: str):
    return json.loads((D / name).read_text(encoding="utf-8"))


class TestGapUssrWest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.base = {int(p["id"]): p for p in _read("provinces_base.json")["provinces"]}
        cls.geo = {int(g["id"]): g for g in _read("provinces_geometry.json")["provinces"]}
        cls.adj = _read("province_adjacency.json")["adjacency"]

    def test_new_block_and_kept_ids(self) -> None:
        self.assertEqual(sorted(i for i in self.base if 905889 <= i <= 905899), NEW_IDS)
        self.assertNotIn(950343, self.base)
        self.assertEqual(self.base[903534]["name"], "Moscow")
        self.assertEqual(self.base[903532]["name"], "Leningrad oblast")
        self.assertEqual(self.base[905836]["name"], "Transnistria")
        self.assertEqual(self.base[950006]["name"], "Black Sea Zone")
        self.assertEqual(self.base[950123]["name"], "Black Sea East")
        self.assertEqual(self.base[950124]["name"], "Black Sea West")
        for pid in NEW_IDS:
            self.assertEqual(self.base[pid]["domain"], "land")
            self.assertGreaterEqual(len(self.geo[pid]["points"]), 3)
            self.assertGreater(int((self._eco()[str(pid)]["population"])), 0)

    def test_owners_use_existing_tags_only(self) -> None:
        for year, tag in EXPECT_OWNER.items():
            owners = _read("province_ownership_%d.json" % year)["owners"]
            for pid in NEW_IDS:
                self.assertEqual(owners[str(pid)], tag)
                self.assertNotEqual(owners[str(pid)], "UKR")
            self.assertEqual(owners["905836"], "ROM")
            self.assertEqual(owners["903534"], "SOV" if year != 2026 else "RUS")

    def test_layers_and_hierarchy_pins(self) -> None:
        for name in LAYER_NAMES:
            self.assertTrue((D / name).is_file(), name)
        for year in YEARS:
            mem = _read("hierarchy_membership_%d.json" % year)
            for pid in NEW_IDS:
                self.assertEqual(mem["province_to_state"][str(pid)], 388)
                self.assertEqual(mem["province_to_region"][str(pid)], 5)
                self.assertEqual(mem["province_to_super_region"][str(pid)], 3)
        states = _read("province_states.json")["states"]
        self.assertEqual(len(states), 429)
        state = next(s for s in states if int(s["id"]) == 388)
        for pid in NEW_IDS:
            self.assertIn(pid, [int(x) for x in state["province_ids"]])
        regions = _read("strategic_regions.json")["regions"]
        self.assertEqual(len(regions), 31)
        region = next(r for r in regions if int(r["id"]) == 5)
        for pid in NEW_IDS:
            self.assertIn(pid, [int(x) for x in region["province_ids"]])
        scaffold = _read("hierarchy_scaffold.json")
        for pid in NEW_IDS:
            self.assertEqual(scaffold["province_to_state"][str(pid)], 388)
        cities = _read("province_city_layer.json")["provinces"]
        self.assertEqual(cities["905889"]["city_name"], "Kiev")
        self.assertEqual(cities["903534"]["city_name"], "Moscow")
        self.assertTrue(cities["903534"].get("is_capital"))

    def test_no_zero_neighbour_and_symmetric(self) -> None:
        affected = NEW_IDS + [903492, 903493, 903532, 903534, 950006, 950123, 950124]
        for pid in affected:
            nbs = [int(x) for x in self.adj.get(str(pid)) or []]
            self.assertGreaterEqual(len(nbs), 1, pid)
            for other in nbs:
                back = [int(x) for x in self.adj.get(str(other)) or []]
                self.assertIn(pid, back, (pid, other))

    def test_black_sea_coverage(self) -> None:
        prod = _load_mod(PRODUCT, "gap_ussr_cov")
        report = prod.selected_black_sea_coverage()
        # Numerator: water samples inside a zone ring.
        # Denominator: NE water samples in BLACK_SEA_BBOX, Marmara excluded.
        self.assertGreaterEqual(report["rate"], 0.98, report)
        self.assertGreater(report["water"], 1000, report)
        self.assertGreater(report["hit"], int(report["water"] * 0.98) - 1)

    def test_mutant_black_sea_blobs_miss_coverage(self) -> None:
        needle = "return True  # GAP_USSR_BLACK_SEA"
        with _mutated(
            PRODUCT,
            PROD_ORIGINAL,
            needle,
            "return False  # GAP_USSR_BLACK_SEA",
            "gap_ussr_blob",
        ) as prod:
            report = prod.selected_black_sea_coverage()
            self.assertLess(report["rate"], 0.98, report)
            self.assertLess(report["hit"], report["water"] // 2, report)
        self.assertEqual(PRODUCT.read_text(encoding="utf-8"), PROD_ORIGINAL)

    def test_mutant_ukr_owner_rejected(self) -> None:
        needle = '1910: "RUS",  # GAP_USSR_OWNER_1910'
        with _mutated(
            SCRIPT,
            GEN_ORIGINAL,
            needle,
            '1910: "UKR",  # GAP_USSR_OWNER_1910',
            "gap_ussr_ukr",
        ) as gen:
            self.assertEqual(gen.owner_for(1910), "UKR")
            self.assertFalse(gen.owner_allowed(1910, gen.owner_for(1910)))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), GEN_ORIGINAL)

    def test_mutant_id_block_moves(self) -> None:
        needle = "905889  # GAP_USSR_NEW_ID"
        with _mutated(SCRIPT, GEN_ORIGINAL, needle, "905000  # GAP_USSR_NEW_ID", "gap_ussr_id") as gen:
            self.assertEqual(gen.new_id_block()[0], 905000)
            self.assertNotEqual(gen.new_id_block(), NEW_IDS)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), GEN_ORIGINAL)

    def test_mutant_skip_mirror_leaves_one_way_edge(self) -> None:
        needle = "_mirror_pairs(adj)  # GAP_USSR_MIRROR_CALL"
        with _mutated(SCRIPT, GEN_ORIGINAL, needle, "return  # GAP_USSR_MIRROR_CALL", "gap_ussr_mirror") as gen:
            adj = {"1": [2], "2": []}
            gen.mirror_adjacency(adj)
            self.assertNotIn(1, [int(x) for x in adj.get("2") or []])
        live = _load_mod(SCRIPT, "gap_ussr_mirror_live")
        adj = {"1": [2], "2": []}
        live.mirror_adjacency(adj)
        self.assertIn(1, [int(x) for x in adj["2"]])
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), GEN_ORIGINAL)

    def _eco(self) -> dict:
        return _read("province_economy_layer.json")["provinces"]


if __name__ == "__main__":
    unittest.main()
