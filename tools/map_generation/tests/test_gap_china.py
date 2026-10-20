#!/usr/bin/env python3
"""GAP-CHINA: 56 1936-style provinces from the 22 CHI blobs.

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
SCRIPT = ROOT / "tools" / "map_generation" / "scripts" / "generate_gap_china.py"
D = ROOT / "data" / "provinces_world_accurate"
ORIGINAL = SCRIPT.read_text(encoding="utf-8")

CHI_BLOBS = (
    902487, 902491, 902493, 902496, 902504, 902505, 902514, 902521, 902523,
    902526, 902534, 902544, 902564, 902566, 902568, 902569, 902590, 902598,
    902601, 902633, 902634, 902646,
)
LEFTOVER = (902487, 902491, 902496, 902505)
KEPT = {
    902493: "Dzungaria (Ili/Tacheng)",
    902514: "Kumul (Hami)",
    902523: "Kashgaria",
    902504: "Aksu-Kucha",
    902534: "Khotan-Lop",
    902569: "Ngari (W. Tibet)",
    902601: "Xikang West (Chamdo)",
    902568: "Qinghai West (Tsaidam)",
    902526: "Gansu Hexi Corridor",
    902566: "Gansu East (Lanzhou)",
    902544: "Suiyuan West (Hetao)",
    902521: "Chahar",
    902564: "Shandong West (Jinan)",
    902590: "Anhui South (Anking)",
    902633: "Fujian South (Amoy)",
    902598: "Hunan North (Changsha)",
    902634: "Yunnan East (Kunming)",
    902646: "Guangxi East (Wuzhou)",
}
NEW_RANGE = set(range(905855, 905889))
YEARS = (1910, 1918, 1936, 1945, 2026)
KINMEN = 903981
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


def _load_mod(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load gap china generator")
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
    fails = set()
    base_doc = _read(board / "provinces_base.json")
    by_id = {int(p["id"]): p for p in base_doc["provinces"]}
    ids = set(by_id)
    names = {int(p["id"]): str(p.get("name") or "") for p in base_doc["provinces"]}
    for pid, want in KEPT.items():
        if names.get(pid) != want:
            fails.add("kept_name")
    china_names = [n for n in names.values() if n in {s[0] for s in _load_mod("gap_china_audit_slots").SLOTS}]
    if len(set(china_names)) < 56:
        fails.add("named_missing")
    used_new = ids & NEW_RANGE
    if len(used_new) != 34:
        fails.add("new_ids")
    for pid in LEFTOVER:
        if pid not in ids:
            fails.add("leftover_unassigned")
        elif names.get(pid, "").startswith("CHN "):
            fails.add("leftover_unassigned")
        elif pid not in names or names[pid] in KEPT.values():
            fails.add("leftover_unassigned")
    for year in YEARS:
        own = _read(board / ("province_ownership_%d.json" % year)).get("owners") or {}
        mem = _read(board / ("hierarchy_membership_%d.json" % year))
        for pid, name in names.items():
            if name in KEPT.values() or pid in NEW_RANGE or pid in LEFTOVER:
                if own.get(str(pid)) != "CHI":
                    fails.add("era_owner")
                    break
                st = int((mem.get("province_to_state") or {}).get(str(pid)) or 0)
                if name in {s[0] for s in _load_mod("gap_china_audit_slots").SLOTS} and st != 289:
                    fails.add("era_membership")
                    break
    adj = _read(board / "province_adjacency.json").get("adjacency") or {}
    if 902598 not in {int(k) for k in adj}:
        fails.add("renumber")
    china_pids = [
        pid for pid, name in names.items()
        if name in {s[0] for s in _load_mod("gap_china_audit_slots").SLOTS}
    ]
    for pid in china_pids:
        if not adj.get(str(pid)):
            fails.add("orphan")
            break
    fujian = next((pid for pid, n in names.items() if n == "Fujian South (Amoy)"), None)
    if fujian is None or KINMEN not in [int(x) for x in adj.get(str(fujian), [])]:
        fails.add("kinmen")
    for a_s, nbs in adj.items():
        a = int(a_s)
        for b in nbs:
            if a not in [int(x) for x in adj.get(str(int(b)), [])]:
                fails.add("asymmetry")
                break
        else:
            continue
        break
    geo = {int(g["id"]): g for g in _read(board / "provinces_geometry.json")["provinces"]}
    for pid in china_pids:
        if len((geo.get(pid) or {}).get("points") or []) < 3:
            fails.add("geometry")
            break
        if not (geo.get(pid) or {}).get("label_anchor"):
            fails.add("anchor")
            break
    city = _read(board / "province_city_layer.json").get("provinces") or {}
    jiangsu = next((pid for pid, n in names.items() if n == "Jiangsu South (Shanghai-Nanking)"), None)
    if jiangsu is None or (city.get(str(jiangsu)) or {}).get("city_name") != "Shanghai":
        fails.add("city")
    hebei = next((pid for pid, n in names.items() if n == "Hebei North (Peiping-Tientsin)"), None)
    if hebei is None or (city.get(str(hebei)) or {}).get("city_name") != "Peiping":
        fails.add("city")
    return fails


def _scratch() -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="gap-china-"))
    for name in LAYER_NAMES:
        shutil.copy(D / name, tmp / name)
    strip = {str(p) for p in CHI_BLOBS} | {str(i) for i in range(905855, 905889)}
    for year in YEARS:
        own_path = tmp / ("province_ownership_%d.json" % year)
        own = _read(own_path)
        mem_path = tmp / ("hierarchy_membership_%d.json" % year)
        mem = _read(mem_path)
        for pid in strip:
            (own.get("owners") or {}).pop(pid, None)
            for key in ("province_to_region", "province_to_state", "province_to_super_region"):
                (mem.get(key) or {}).pop(pid, None)
        own_path.write_text(json.dumps(own), encoding="utf-8")
        mem_path.write_text(json.dumps(mem), encoding="utf-8")
    return tmp


def _apply(mod) -> Path:
    tmp = _scratch()
    mod.D = tmp
    chi = mod.load_chi_rings()
    painted = mod.paint_boxes(chi)
    ids = mod.assign_ids(chi, painted)
    mod.apply_layers(chi, painted, ids)
    return tmp


class TestGapChina(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_mod("gap_china_product")

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
        with _mutated(old, new, "gap_china_mut_era") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("era_owner", fails)
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_renumber_hunan(self) -> None:
        old = "return int(pid)  # GAP_CHINA_PID identity"
        new = "return 999001 if int(pid) == 902598 else int(pid)  # GAP_CHINA_PID identity"
        with _mutated(old, new, "gap_china_mut_pid") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("renumber", fails)
                base = _read(board / "provinces_base.json")
                hunan = [p for p in base["provinces"] if int(p["id"]) == 902598]
                self.assertEqual(len(hunan), 1)
                self.assertEqual(hunan[0]["name"], "Hunan North (Changsha)")
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_one_way_link(self) -> None:
        old = "    _mirror_pairs(adj)  # GAP_CHINA_MIRROR_CALL"
        new = "    pass  # GAP_CHINA_MIRROR_CALL"
        with _mutated(old, new, "gap_china_mut_mirror") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("asymmetry", fails)
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)

    def test_mutant_skip_one_leftover(self) -> None:
        old = "    return True  # GAP_CHINA_LEFTOVER"
        new = "    return False  # GAP_CHINA_LEFTOVER"
        with _mutated(old, new, "gap_china_mut_leftover") as mod:
            board = _apply(mod)
            try:
                fails = _audit(board)
                self.assertIn("leftover_unassigned", fails)
                base = _read(board / "provinces_base.json")
                row = next(p for p in base["provinces"] if int(p["id"]) == 902505)
                self.assertTrue(row.get("name"))
            finally:
                shutil.rmtree(board)
        self.assertEqual(SCRIPT.read_text(encoding="utf-8"), ORIGINAL)


if __name__ == "__main__":
    unittest.main()
