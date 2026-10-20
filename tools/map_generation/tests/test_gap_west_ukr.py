#!/usr/bin/env python3
"""GAP-WEST-UKR: Galicia / Volhynia / Bessarabia on 905900–905908."""
from __future__ import annotations

import json
import unittest
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "generate_gap_west_ukr.py"
PRODUCT = ROOT / "tools" / "map_generation" / "lib" / "gap_west_ukr_product.py"
D = ROOT / "data" / "provinces_world_accurate"
GEN_ORIGINAL = SCRIPT.read_text(encoding="utf-8")
PROD_ORIGINAL = PRODUCT.read_text(encoding="utf-8")

NEW_IDS = list(range(905900, 905909))
YEARS = (1910, 1918, 1936, 1945, 2026)
POL_IDS = {905900, 905901, 905902, 905903, 905905, 905906, 905907}
ROM_IDS = {905904, 905908}
AUS_1910 = {905900, 905902, 905903, 905906, 905908}


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


class TestGapWestUkr(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.base = {int(p["id"]): p for p in _read("provinces_base.json")["provinces"]}
        cls.geo = {int(g["id"]): g for g in _read("provinces_geometry.json")["provinces"]}
        cls.adj = _read("province_adjacency.json")["adjacency"]

    def test_new_block_and_names(self) -> None:
        self.assertEqual(sorted(i for i in self.base if 905900 <= i <= 905908), NEW_IDS)
        self.assertEqual(self.base[905900]["name"], "Lviv")
        self.assertEqual(self.base[905901]["name"], "Lutsk")
        self.assertEqual(self.base[905902]["name"], "Stanislawow")
        self.assertEqual(self.base[905903]["name"], "Tarnopol")
        self.assertEqual(self.base[905904]["name"], "Chisinau")
        self.assertEqual(self.base[905818]["name"], "Minsk")
        for pid in NEW_IDS:
            self.assertEqual(self.base[pid]["domain"], "land")
            self.assertGreaterEqual(len(self.geo[pid]["points"]), 3)

    def test_owners_use_existing_tags_only(self) -> None:
        for year in YEARS:
            owners = _read("province_ownership_%d.json" % year)["owners"]
            for pid in NEW_IDS:
                self.assertNotEqual(owners[str(pid)], "UKR")
            if year == 1910:
                for pid in AUS_1910:
                    self.assertEqual(owners[str(pid)], "AUS")
                self.assertEqual(owners["905901"], "RUS")
                self.assertEqual(owners["905904"], "RUS")
            elif year in (1918, 1936):
                for pid in POL_IDS:
                    self.assertEqual(owners[str(pid)], "POL")
                for pid in ROM_IDS:
                    self.assertEqual(owners[str(pid)], "ROM")
            elif year == 1945:
                for pid in NEW_IDS:
                    self.assertEqual(owners[str(pid)], "SOV")
            else:
                self.assertEqual(owners["905904"], "ROM")
                self.assertEqual(owners["905900"], "RUS")

    def test_layers_and_hierarchy(self) -> None:
        for year in YEARS:
            mem = _read("hierarchy_membership_%d.json" % year)
            self.assertEqual(mem["province_to_state"]["905900"], 388)
            self.assertEqual(mem["province_to_region"]["905900"], 5)
            self.assertEqual(mem["province_to_state"]["905904"], 357)
            self.assertEqual(mem["province_to_region"]["905904"], 8)
        states = _read("province_states.json")["states"]
        self.assertEqual(len(states), 429)
        rus = next(s for s in states if int(s["id"]) == 388)
        mda = next(s for s in states if int(s["id"]) == 357)
        for pid in POL_IDS | {905908}:
            self.assertIn(pid, [int(x) for x in rus["province_ids"]])
        self.assertIn(905904, [int(x) for x in mda["province_ids"]])
        cities = _read("province_city_layer.json")["provinces"]
        self.assertEqual(cities["905900"]["city_name"], "Lviv")
        self.assertEqual(cities["905904"]["city_name"], "Chisinau")

    def test_no_zero_neighbour_and_symmetric(self) -> None:
        for pid in NEW_IDS:
            nbs = [int(x) for x in self.adj.get(str(pid)) or []]
            self.assertGreaterEqual(len(nbs), 1, pid)
            for other in nbs:
                back = [int(x) for x in self.adj.get(str(other)) or []]
                self.assertIn(pid, back, (pid, other))

    def test_named_cities_hit(self) -> None:
        prod = _load_mod(PRODUCT, "gap_wukr_hits")
        report = prod.selected_city_hits()
        self.assertTrue(report["ok"], report)

    def test_mutant_placeholder_cities_miss(self) -> None:
        needle = "return True  # GAP_WEST_UKR_NAMED"
        with _mutated(
            PRODUCT,
            PROD_ORIGINAL,
            needle,
            "return False  # GAP_WEST_UKR_NAMED",
            "gap_wukr_blob",
        ) as prod:
            report = prod.selected_city_hits()
            self.assertFalse(report["ok"], report)
        self.assertEqual(PRODUCT.read_text(encoding="utf-8"), PROD_ORIGINAL)

    def test_mutant_ukr_owner_rejected(self) -> None:
        needle = "if year == 1910:  # GAP_WEST_UKR_OWNER_1910"
        with _mutated(
            SCRIPT,
            GEN_ORIGINAL,
            '        if name in AUSTRIAN_1910:\n            return "AUS"\n        return "RUS"',
            '        if name in AUSTRIAN_1910:\n            return "UKR"\n        return "UKR"',
            "gap_wukr_ukr",
        ) as gen:
            self.assertEqual(gen.owner_for(1910, "Lviv"), "UKR")
            self.assertFalse(gen.owner_allowed(1910, gen.owner_for(1910, "Lviv")))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), GEN_ORIGINAL)

    def test_mutant_id_block_moves(self) -> None:
        with _mutated(
            SCRIPT,
            GEN_ORIGINAL,
            "905900  # GAP_WEST_UKR_NEW_ID",
            "905000  # GAP_WEST_UKR_NEW_ID",
            "gap_wukr_id",
        ) as gen:
            self.assertEqual(gen.new_id_block()[0], 905000)
            self.assertNotEqual(gen.new_id_block(), NEW_IDS)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), GEN_ORIGINAL)

    def test_mutant_skip_mirror_leaves_one_way_edge(self) -> None:
        needle = "_ussr()._mirror_pairs(adj)  # GAP_WEST_UKR_MIRROR_CALL"
        with _mutated(
            SCRIPT,
            GEN_ORIGINAL,
            needle,
            "return  # GAP_WEST_UKR_MIRROR_CALL",
            "gap_wukr_mirror",
        ) as gen:
            adj = {"1": [2], "2": []}
            gen.mirror_adjacency(adj)
            self.assertNotIn(1, [int(x) for x in adj.get("2") or []])
        live = _load_mod(SCRIPT, "gap_wukr_mirror_live")
        adj = {"1": [2], "2": []}
        live.mirror_adjacency(adj)
        self.assertIn(1, [int(x) for x in adj["2"]])
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), GEN_ORIGINAL)


if __name__ == "__main__":
    unittest.main()
