#!/usr/bin/env python3
"""GAP-BELARUS: named 1936-style provinces on ids 905807–905826.

Mutants edit generator or product source, reload it, and do not write the board.
"""
from __future__ import annotations

import json
import unittest
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "generate_gap_belarus.py"
PRODUCT = ROOT / "tools" / "map_generation" / "lib" / "gap_belarus_product.py"
D = ROOT / "data" / "provinces_world_accurate"
GEN_ORIGINAL = SCRIPT.read_text(encoding="utf-8")
PROD_ORIGINAL = PRODUCT.read_text(encoding="utf-8")

BLR_IDS = list(range(905807, 905827))
YEARS = (1910, 1918, 1936, 1945, 2026)
WESTERN = {
    905808,
    905811,
    905813,
    905814,
    905816,
    905817,
    905821,
    905823,
    905825,
}
EXPECT_OWNER = {
    1910: ("RUS", "RUS"),
    1918: ("POL", "SOV"),
    1936: ("POL", "SOV"),
    1945: ("SOV", "SOV"),
    2026: ("BLR", "BLR"),
}
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


class TestGapBelarus(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.base = {int(p["id"]): p for p in _read("provinces_base.json")["provinces"]}
        cls.geo = {int(g["id"]): g for g in _read("provinces_geometry.json")["provinces"]}
        cls.adj = _read("province_adjacency.json")["adjacency"]

    def test_kept_ids_and_names(self) -> None:
        self.assertEqual(sorted(i for i in self.base if 905807 <= i <= 905826), BLR_IDS)
        self.assertNotIn(905900, self.base)
        self.assertEqual(self.base[905818]["name"], "Minsk")
        self.assertEqual(self.base[905815]["name"], "Gomel")
        self.assertEqual(self.base[905809]["name"], "Vitebsk")
        self.assertEqual(self.base[905820]["name"], "Mogilev")
        self.assertEqual(self.base[905807]["name"], "Polotsk")
        self.assertEqual(self.base[903534]["name"], "Moscow")
        self.assertEqual(self.base[905897]["name"], "Smolensk")
        for pid in BLR_IDS:
            self.assertEqual(self.base[pid]["domain"], "land")
            self.assertGreaterEqual(len(self.geo[pid]["points"]), 3)
            self.assertGreater(int(self._eco()[str(pid)]["population"]), 0)

    def test_owners_use_existing_tags_only(self) -> None:
        for year, (west, east) in EXPECT_OWNER.items():
            owners = _read("province_ownership_%d.json" % year)["owners"]
            for pid in BLR_IDS:
                tag = owners[str(pid)]
                self.assertNotEqual(tag, "UKR")
                want = west if pid in WESTERN else east
                self.assertEqual(tag, want, (year, pid, tag, want))
            self.assertEqual(owners["903534"], "SOV" if year != 2026 else "RUS")

    def test_layers_and_hierarchy_pins(self) -> None:
        for name in LAYER_NAMES:
            self.assertTrue((D / name).is_file(), name)
        for year in YEARS:
            mem = _read("hierarchy_membership_%d.json" % year)
            for pid in BLR_IDS:
                self.assertEqual(mem["province_to_state"][str(pid)], 279)
                self.assertEqual(mem["province_to_region"][str(pid)], 8)
                self.assertEqual(mem["province_to_super_region"][str(pid)], 2)
        states = _read("province_states.json")["states"]
        self.assertEqual(len(states), 429)
        state = next(s for s in states if int(s["id"]) == 279)
        for pid in BLR_IDS:
            self.assertIn(pid, [int(x) for x in state["province_ids"]])
        cities = _read("province_city_layer.json")["provinces"]
        self.assertEqual(cities["905818"]["city_name"], "Minsk")
        self.assertEqual(cities["905809"]["city_name"], "Vitebsk")
        self.assertTrue(cities["903534"].get("is_capital"))

    def test_no_zero_neighbour_moscow_borders_vitebsk(self) -> None:
        affected = BLR_IDS + [903534, 905897]
        for pid in affected:
            nbs = [int(x) for x in self.adj.get(str(pid)) or []]
            self.assertGreaterEqual(len(nbs), 1, pid)
            for other in nbs:
                back = [int(x) for x in self.adj.get(str(other)) or []]
                self.assertIn(pid, back, (pid, other))
        self.assertIn(905809, [int(x) for x in self.adj.get("903534") or []])
        self.assertIn(903534, [int(x) for x in self.adj.get("905809") or []])
        self.assertIn(905807, [int(x) for x in self.adj.get("905809") or []])

    def test_named_cities_hit(self) -> None:
        prod = _load_mod(PRODUCT, "gap_blr_hits")
        report = prod.selected_city_hits()
        self.assertTrue(report["ok"], report)
        self.assertTrue(prod.moscow_borders_vitebsk())

    def test_mutant_placeholder_cities_miss(self) -> None:
        needle = "return True  # GAP_BELARUS_NAMED"
        with _mutated(
            PRODUCT,
            PROD_ORIGINAL,
            needle,
            "return False  # GAP_BELARUS_NAMED",
            "gap_blr_blob",
        ) as prod:
            report = prod.selected_city_hits()
            self.assertFalse(report["ok"], report)
            self.assertGreaterEqual(len(report["misses"]), 4, report)
        self.assertEqual(PRODUCT.read_text(encoding="utf-8"), PROD_ORIGINAL)

    def test_mutant_ukr_owner_rejected(self) -> None:
        needle = '1910: "RUS",  # GAP_BELARUS_OWNER_1910'
        with _mutated(
            SCRIPT,
            GEN_ORIGINAL,
            needle,
            '1910: "UKR",  # GAP_BELARUS_OWNER_1910',
            "gap_blr_ukr",
        ) as gen:
            self.assertEqual(gen.owner_for(1910, "Minsk"), "UKR")
            self.assertFalse(gen.owner_allowed(1910, gen.owner_for(1910, "Minsk")))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), GEN_ORIGINAL)

    def test_mutant_id_block_moves(self) -> None:
        needle = "905807, 905827))  # GAP_BELARUS_ID_START"
        # The live needle is on BLR_IDS assignment.
        live = SCRIPT.read_text(encoding="utf-8")
        if live.count("905807, 905827)") != 1:
            needle = "list(range(905807, 905827))"
        with _mutated(
            SCRIPT,
            GEN_ORIGINAL,
            "list(range(905807, 905827))",
            "list(range(905000, 905020))",
            "gap_blr_id",
        ) as gen:
            self.assertEqual(gen.keep_id_block()[0], 905000)
            self.assertNotEqual(gen.keep_id_block(), BLR_IDS)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), GEN_ORIGINAL)

    def test_mutant_skip_mirror_leaves_one_way_edge(self) -> None:
        needle = "_ussr()._mirror_pairs(adj)  # GAP_BELARUS_MIRROR_CALL"
        with _mutated(
            SCRIPT,
            GEN_ORIGINAL,
            needle,
            "return  # GAP_BELARUS_MIRROR_CALL",
            "gap_blr_mirror",
        ) as gen:
            adj = {"1": [2], "2": []}
            gen.mirror_adjacency(adj)
            self.assertNotIn(1, [int(x) for x in adj.get("2") or []])
        live = _load_mod(SCRIPT, "gap_blr_mirror_live")
        adj = {"1": [2], "2": []}
        live.mirror_adjacency(adj)
        self.assertIn(1, [int(x) for x in adj["2"]])
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), GEN_ORIGINAL)

    def _eco(self) -> dict:
        return _read("province_economy_layer.json")["provinces"]


if __name__ == "__main__":
    unittest.main()
