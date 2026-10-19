#!/usr/bin/env python3
"""GAP-HAWAII: 800094 stays Oahu. The other islands and Hawaiian Waters are new.

Mutants edit the generator source, reload it, and write only a temp copy of
the board. The live board is audited as committed.
"""
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "generate_gap_hawaii.py"
D = ROOT / "data" / "provinces_world_accurate"
ORIGINAL = SCRIPT.read_text(encoding="utf-8")

OAHU = 800094
KAUAI = 905849
MAUI = 905850
HAWAII = 905851
WATERS = 950340
NEW = (KAUAI, MAUI, HAWAII, WATERS)
LAND = (KAUAI, MAUI, HAWAII)
YEARS = (1910, 1918, 1936, 1945, 2026)
# Far links that must not come back, plus the two ocean keeps ADJ-V3 left on Oahu.
FAR = (
    800023, 800024, 800519, 802049,
    950190, 950197, 950205, 950206, 950213,
    902396, 902397,
)
RESERVED = set(range(905852, 905889)) | {950341, 950342}
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
    "us_county_to_playable_remap.json",
    "provinces_base.json",
    "provinces_geometry.json",
    "province_city_layer.json",
    "province_states.json",
    "province_adjacency.json",
)


def _load_mod(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load gap hawaii generator")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@contextmanager
def _mutated(old: str, new: str, name: str):
    text = SCRIPT.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise AssertionError("mutant needle missing or not unique: %r" % old)
    SCRIPT.write_text(text.replace(old, new, 1), encoding="utf-8")
    try:
        yield _load_mod(name)
    finally:
        SCRIPT.write_text(text, encoding="utf-8")


def _read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _audit(board: Path) -> set:
    """Empty means the board matches the GAP-HAWAII bars."""
    fails = set()
    base_doc = _read(board / "provinces_base.json")
    by_id = {int(p["id"]): p for p in base_doc["provinces"]}
    ids = set(by_id)
    if OAHU not in ids or str(by_id[OAHU].get("name")) != "Oahu":
        fails.add("oahu_missing")
    if by_id.get(OAHU, {}).get("terrain") != "plains":
        fails.add("oahu_terrain")
    for pid in NEW:
        if pid not in ids:
            fails.add("new_ids")
    if ids & RESERVED:
        fails.add("reserved")
    for pid, terrain in ((KAUAI, "mountains"), (MAUI, "mountains"), (HAWAII, "mountains")):
        if by_id.get(pid, {}).get("terrain") != terrain:
            fails.add("island_terrain")
    if str(by_id.get(WATERS, {}).get("domain") or "") != "sea":
        fails.add("waters_domain")
    ocean = ((by_id.get(WATERS) or {}).get("meta") or {}).get("ocean") or {}
    if int(ocean.get("nearest_sea") or 0) != 950198:
        fails.add("ocean_exit")
    if ocean.get("marquesas_902396") != "UNKNOWN" or ocean.get("kiribati_902397") != "UNKNOWN":
        fails.add("ocean_unknown")

    for year in YEARS:
        own = _read(board / ("province_ownership_%d.json" % year)).get("owners") or {}
        mem = _read(board / ("hierarchy_membership_%d.json" % year))
        reg = mem.get("province_to_region") or {}
        st = mem.get("province_to_state") or {}
        sup = mem.get("province_to_super_region") or {}
        for pid in (OAHU, KAUAI, MAUI, HAWAII, WATERS):
            if own.get(str(pid)) != "USA":
                fails.add("era_owner")
        for pid in (OAHU, KAUAI, MAUI, HAWAII):
            if int(reg.get(str(pid)) or 0) != 150 or int(st.get(str(pid)) or 0) != 222:
                fails.add("era_membership")
            if int(sup.get(str(pid)) or 0) != 2:
                fails.add("era_membership")
        if int(reg.get(str(WATERS)) or 0) != 10 or int(sup.get(str(WATERS)) or 0) != 4:
            fails.add("era_sea")
        if str(WATERS) in st:
            fails.add("era_sea")

    adj = _read(board / "province_adjacency.json").get("adjacency") or {}
    if OAHU not in {int(k) for k in adj} or str(OAHU) not in adj:
        fails.add("renumber")
    oahu = sorted(int(x) for x in adj.get(str(OAHU), []))
    if oahu != [KAUAI, MAUI, WATERS]:
        fails.add("oahu_neighbours")
    if sorted(int(x) for x in adj.get(str(HAWAII), [])) != [WATERS]:
        fails.add("big_island")
    if 950198 not in [int(x) for x in adj.get(str(WATERS), [])]:
        fails.add("ocean_exit")
    for bad in FAR:
        nbs = [int(x) for x in adj.get(str(OAHU), [])]
        back = [int(x) for x in adj.get(str(bad), [])]
        if bad in nbs or OAHU in back:
            fails.add("bogus")
            break
    for a_s, nbs in adj.items():
        if not nbs:
            fails.add("orphan")
            break
    for a_s, nbs in adj.items():
        a = int(a_s)
        for b in nbs:
            if a not in [int(x) for x in adj.get(str(int(b)), [])]:
                fails.add("asymmetry")
                break
        if "asymmetry" in fails:
            break
    for pid in (902396, 902397):
        if not adj.get(str(pid)):
            fails.add("orphan")

    eco = _read(board / "province_economy_layer.json").get("provinces") or {}
    pop = sum(int((eco.get(str(pid)) or {}).get("population") or 0) for pid in (OAHU,) + LAND)
    if pop != 103439:
        fails.add("population")
    if int((eco.get(str(OAHU)) or {}).get("factories") or 0) != 10:
        fails.add("factories")
    for pid in LAND:
        if int((eco.get(str(pid)) or {}).get("factories") or 0) != 0:
            fails.add("factories")
    res = _read(board / "province_resources_layer.json").get("provinces") or {}
    coal = sum(int((res.get(str(pid)) or {}).get("coal") or 0) for pid in (OAHU,) + LAND)
    if coal != 5:
        fails.add("coal")

    city = _read(board / "province_city_layer.json").get("provinces") or {}
    if (city.get(str(OAHU)) or {}).get("city_name") != "Honolulu":
        fails.add("honolulu")
    if any(
        isinstance(row, dict) and row.get("city_name") == "Hilo" for row in city.values()
    ):
        fails.add("hilo")

    states = _read(board / "province_states.json").get("states") or []
    hawaii_state = next((s for s in states if int(s.get("id") or 0) == 222), {})
    state_ids = [int(x) for x in (hawaii_state.get("province_ids") or [])]
    for pid in (800094, 800841, 800842, 802156, 802984, KAUAI, MAUI, HAWAII):
        if pid not in state_ids:
            fails.add("state")
            break

    remap = _read(board / "us_county_to_playable_remap.json")
    table = remap.get("remap") or {}
    expect = {
        "802984": OAHU,
        "800842": KAUAI,
        "800094": MAUI,
        "802156": MAUI,
        "800841": HAWAII,
    }
    for key, pid in expect.items():
        if int(table.get(key) or 0) != pid:
            fails.add("remap")
            break
    if int(remap.get("survivors_n") or 0) != 133 or "survivors" in remap:
        fails.add("remap")
    return fails


def _scratch() -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="gap-hawaii-"))
    for name in LAYER_NAMES:
        shutil.copy(D / name, tmp / name)
    for year in YEARS:
        own_path = tmp / ("province_ownership_%d.json" % year)
        own = _read(own_path)
        mem_path = tmp / ("hierarchy_membership_%d.json" % year)
        mem = _read(mem_path)
        for pid in NEW:
            (own.get("owners") or {}).pop(str(pid), None)
            for key in ("province_to_region", "province_to_state", "province_to_super_region"):
                (mem.get(key) or {}).pop(str(pid), None)
        own_path.write_text(json.dumps(own), encoding="utf-8")
        mem_path.write_text(json.dumps(mem), encoding="utf-8")
    return tmp


def _apply(mod) -> Path:
    tmp = _scratch()
    mod.D = tmp
    mod.apply_layers(mod.load_island_groups(), {})
    return tmp


class TestGapHawaii(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_mod("gap_hawaii_product")

    def test_board_matches_spec(self) -> None:
        fails = _audit(D)
        self.assertEqual(fails, set(), msg=sorted(fails))
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_generator_twice_byte_identical(self) -> None:
        before = {name: (D / name).read_bytes() for name in LAYER_NAMES}
        self.assertEqual(self.mod.main(), 0)
        mid = {name: (D / name).read_bytes() for name in LAYER_NAMES}
        self.assertEqual(mid, before)
        self.assertEqual(self.mod.main(), 0)
        after = {name: (D / name).read_bytes() for name in LAYER_NAMES}
        self.assertEqual(after, before)

    def test_mutant_drop_one_era(self) -> None:
        old = "ERA_YEARS = (1910, 1918, 1936, 1945, 2026)"
        new = "ERA_YEARS = (1910, 1918, 1945, 2026)"
        with _mutated(old, new, "gap_hawaii_mut_era") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("era_owner", fails)
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_renumber_oahu(self) -> None:
        old = "return int(pid)  # GAP_HAWAII_PID identity"
        new = "return 800095 if int(pid) == 800094 else int(pid)  # GAP_HAWAII_PID identity"
        with _mutated(old, new, "gap_hawaii_mut_pid") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("renumber", fails)
                base = _read(board / "provinces_base.json")
                oahu = [p for p in base["provinces"] if int(p["id"]) == OAHU]
                self.assertEqual(len(oahu), 1)
                self.assertEqual(oahu[0]["name"], "Oahu")
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_one_way_link(self) -> None:
        old = "    _mirror_pairs(adj)  # GAP_HAWAII_MIRROR_CALL"
        new = "    pass  # GAP_HAWAII_MIRROR_CALL"
        with _mutated(old, new, "gap_hawaii_mut_mirror") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("asymmetry", fails)
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_restore_california_link(self) -> None:
        old = "return ()  # GAP_HAWAII_BOGUS"
        new = "return ((800094, 800023),)  # GAP_HAWAII_BOGUS"
        with _mutated(old, new, "gap_hawaii_mut_bogus") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("bogus", fails)
                base = _read(board / "provinces_base.json")
                oahu = next(p for p in base["provinces"] if int(p["id"]) == OAHU)
                self.assertEqual(oahu["name"], "Oahu")
                adj = _read(board / "province_adjacency.json")["adjacency"]
                self.assertIn(800023, [int(x) for x in adj[str(OAHU)]])
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)


if __name__ == "__main__":
    unittest.main()
