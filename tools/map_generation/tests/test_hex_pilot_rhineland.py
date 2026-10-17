#!/usr/bin/env python3
"""HEXP3 Rhineland hex pilot gates (T1–T6 + source mutants, reverted)."""
from __future__ import annotations

import importlib
import json
import sys
import unittest
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

import hex_author_pilot as hap  # noqa: E402
import hexgrid  # noqa: E402

HEXGRID_PY = ROOT / "tools" / "map_generation" / "lib" / "hexgrid.py"
PILOT_PY = ROOT / "tools" / "map_generation" / "scripts" / "hex_author_pilot.py"
CFG = ROOT / "tools" / "map_generation" / "config" / "hex_pilot_rhineland.json"
BASE = "61a804330304aa709a65055127744e5b984cea45"
LAND_BLOCK_MAX = 905848
SEA_BLOCK_MAX = 950339


def _reload() -> Tuple[Any, Any]:
    importlib.reload(hexgrid)
    importlib.reload(hap)
    return hexgrid, hap


def _swap(path: Path, old: str, new: str) -> str:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise AssertionError("mutant needle missing in %s: %r" % (path, old))
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return text


class TestHexPilotRhineland(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.cfg = hap.load_config(CFG)
        cls.rows = hap.load_pilot_provinces(cls.cfg)
        cls.report = hap.build_report(cls.cfg, write_png=False, emit_preview=True, persist=False)

    def test_t1_pilot_set_180_id_diff_zero(self) -> None:
        prefixes = list(self.cfg["nuts_prefixes"])
        base_ids = {int(p["id"]) for p in self.rows}
        self.assertEqual(len(base_ids), 180)
        self.assertEqual(int(self.report["pid_count"]), 180)
        self.assertEqual(int(self.report["id_diff"]), 0)
        self.assertEqual(set(int(k) for k in self.report["pids"]), base_ids)
        self.assertTrue(all(hap.nuts_prefix_match(p["nuts_id"], prefixes) for p in self.rows))

    def test_t2_coverage_180_of_180(self) -> None:
        self.assertEqual(self.report["coverage"], "180/180")
        self.assertEqual(int(self.report["coverage_n"]), 180)
        for pid, row in self.report["pids"].items():
            self.assertGreaterEqual(int(row["sample_n"]), 1, msg="pid %s has no sample" % pid)

    def test_t3_adjacency_vs_gis_and_explained_v2(self) -> None:
        adj = self.report["adjacency"]
        self.assertEqual(int(adj["v2_internal_n"]), 602)
        self.assertTrue(adj["v2_internal_match_expected"])
        self.assertGreaterEqual(float(adj["hex_vs_gis_agree_frac"]), 0.90)
        self.assertTrue(adj["v2_only"], "disagreement list must be non-empty or explained")
        self.assertGreaterEqual(int(len(adj["knn_suspects"])), 1)
        agree = float(adj["agree_frac"])
        knn_frac = float(len(adj["v2_only_knn"])) / float(adj["v2_internal_n"])
        self.assertTrue(
            agree >= 0.90 or (agree + knn_frac >= 0.90),
            msg="vs-v2 %.4f + knn-explained %.4f < 0.90" % (agree, knn_frac),
        )
        self.assertTrue(adj["agree_ge_90_vs_gis_or_explained"])

    def test_t4_determinism_byte_identical_json(self) -> None:
        a = hap.build_report(self.cfg, write_png=False, emit_preview=False, persist=False)
        b = hap.build_report(self.cfg, write_png=False, emit_preview=False, persist=False)
        da = {k: v for k, v in a.items() if not str(k).startswith("_")}
        db = {k: v for k, v in b.items() if not str(k).startswith("_")}
        ta = json.dumps(hap.round_floats(da), sort_keys=True, indent=2, ensure_ascii=False)
        tb = json.dumps(hap.round_floats(db), sort_keys=True, indent=2, ensure_ascii=False)
        self.assertNotIn("_assigned", ta)
        self.assertEqual(ta, tb)

    def test_t5_git_diff_has_no_data_or_scripts(self) -> None:
        guard = hap.git_guard_paths(str(self.cfg.get("git_base") or BASE))
        self.assertTrue(guard["ok"], msg="banned paths: %s" % guard.get("banned"))
        for p in guard.get("banned") or []:
            self.assertFalse(p.startswith("data/") or p.startswith("scripts/"))

    def test_t6_append_only_checker(self) -> None:
        preview = self.report.get("bake_preview") or {}
        self.assertTrue(preview.get("id_diff_ok"), msg=preview)
        adj_chk = preview.get("id_diff_adjacency") or {}
        ter_chk = preview.get("id_diff_terrain") or {}
        self.assertTrue(adj_chk.get("ok"), msg=adj_chk)
        self.assertTrue(ter_chk.get("ok"), msg=ter_chk)
        self.assertEqual(adj_chk.get("removed"), [])
        self.assertEqual(adj_chk.get("added"), [])

        old = {710000, 710001, 710002}
        removed = hap.check_append_only(
            old, {710000, 710001}, land_block_max=LAND_BLOCK_MAX, sea_block_max=SEA_BLOCK_MAX
        )
        self.assertFalse(removed["ok"], msg="must fail when an id is removed")
        self.assertEqual(removed["removed"], [710002])

        low = hap.check_append_only(
            old,
            {710000, 710001, 710002, 100},
            land_block_max=LAND_BLOCK_MAX,
            sea_block_max=SEA_BLOCK_MAX,
            allow_new=[100],
        )
        self.assertFalse(low["ok"], msg="must fail when a new id is <= block max")
        self.assertIn(100, low["added_below_block_max"])

    def test_mutant_drop_subsample_fails_t2(self) -> None:
        orig = _swap(HEXGRID_PY, "SUBSAMPLE_ENABLED: bool = True", "SUBSAMPLE_ENABLED: bool = False")
        try:
            _reload()
            cfg = hap.load_config(CFG)
            report = hap.build_report(cfg, write_png=False, emit_preview=False, persist=False)
            with self.assertRaises(AssertionError):
                self.assertEqual(int(report["coverage_n"]), 180)
                self.assertEqual(report["coverage"], "180/180")
        finally:
            HEXGRID_PY.write_text(orig, encoding="utf-8")
            _reload()

    def test_mutant_random_origin_fails_t4(self) -> None:
        orig = _swap(
            HEXGRID_PY,
            "RANDOM_ORIGIN_PER_RUN: bool = False",
            "RANDOM_ORIGIN_PER_RUN: bool = True",
        )
        try:
            _reload()
            cfg = hap.load_config(CFG)
            a = hap.build_report(cfg, write_png=False, emit_preview=False, persist=False)
            b = hap.build_report(cfg, write_png=False, emit_preview=False, persist=False)
            da = {k: v for k, v in a.items() if not str(k).startswith("_")}
            db = {k: v for k, v in b.items() if not str(k).startswith("_")}
            ta = json.dumps(hap.round_floats(da), sort_keys=True, indent=2)
            tb = json.dumps(hap.round_floats(db), sort_keys=True, indent=2)
            with self.assertRaises(AssertionError):
                self.assertEqual(ta, tb)
        finally:
            HEXGRID_PY.write_text(orig, encoding="utf-8")
            _reload()

    def test_mutant_checker_ignores_removed_fails_t6(self) -> None:
        orig = _swap(PILOT_PY, "CHECK_REMOVED_IDS: bool = True", "CHECK_REMOVED_IDS: bool = False")
        try:
            _reload()
            chk = hap.check_append_only({1, 2, 3}, {1, 2}, land_block_max=LAND_BLOCK_MAX)
            with self.assertRaises(AssertionError):
                self.assertFalse(chk["ok"])
        finally:
            PILOT_PY.write_text(orig, encoding="utf-8")
            _reload()

    def test_mutant_preview_into_data_fails_t5(self) -> None:
        orig = _swap(
            PILOT_PY,
            "PREVIEW_DIR_OVERRIDE: Optional[str] = None",
            'PREVIEW_DIR_OVERRIDE: Optional[str] = "data/provinces_world_accurate"',
        )
        leaked: List[Path] = []
        try:
            _reload()
            self.assertEqual(
                hap.PREVIEW_DIR_OVERRIDE, "data/provinces_world_accurate"
            )
            cfg = hap.load_config(CFG)
            hap.build_report(cfg, write_png=False, emit_preview=True, persist=False)
            guard = hap.git_guard_paths(str(cfg.get("git_base") or BASE))
            for rel in (
                "data/provinces_world_accurate/preview_terrain_mix.json",
                "data/provinces_world_accurate/preview_adjacency_v3.json",
            ):
                p = ROOT / rel
                if p.exists():
                    leaked.append(p)
            with self.assertRaises(AssertionError):
                self.assertTrue(guard["ok"], msg=guard)
                self.assertFalse(any(x.startswith("data/") for x in guard.get("banned") or []))
        finally:
            PILOT_PY.write_text(orig, encoding="utf-8")
            for p in leaked:
                if p.exists():
                    p.unlink()
            _reload()
            # leftover data/ files must be gone so T5 on the clean tree still holds
            self.assertFalse((ROOT / "data/provinces_world_accurate/preview_terrain_mix.json").exists())
            self.assertFalse((ROOT / "data/provinces_world_accurate/preview_adjacency_v3.json").exists())


if __name__ == "__main__":
    unittest.main()
