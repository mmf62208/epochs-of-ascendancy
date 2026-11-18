#!/usr/bin/env python3
"""NAMES-1 board names. (a)–(c) fail on 5d099346 and pass once names are applied.

Non-name fields are compared to the base commit. Duplicate names within one
1936 owner are rejected except groups whose members are all PINNED (the CHN
cardinal blobs asserted by test_nation_tags1).
"""
from __future__ import annotations

import json
import subprocess
import unittest
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
import sys

sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from names1_product import (  # noqa: E402
    ADMIN_HITS,
    AREA_RE,
    NONLATIN_RE,
    ODDITY_RE,
    PINNED_NAME_IDS,
    SEA_ID,
    TAG_DIR_RE,
    UNKNOWN,
    bgn_cyrillic,
    name_categories,
    proposed_name,
)

BASE_SHA = "5d099346af1304eccf71bcf6e0d9c0afb4b715c0"
BOARD = ROOT / "data" / "provinces_world_accurate" / "provinces_base.json"
OWN = ROOT / "data" / "provinces_world_accurate" / "province_ownership_1936.json"


def _load_tip():
    return json.loads(BOARD.read_text(encoding="utf-8"))


def _load_base():
    raw = subprocess.check_output(
        ["git", "show", f"{BASE_SHA}:data/provinces_world_accurate/provinces_base.json"],
        cwd=str(ROOT),
    )
    return json.loads(raw.decode("utf-8"))


def _land(doc):
    return [p for p in doc["provinces"] if int(p["id"]) < SEA_ID]


class TestNames1Classifiers(unittest.TestCase):
    def test_regexes_and_proposals(self) -> None:
        self.assertEqual(name_categories("CHN North"), ["tag-dir"])
        self.assertEqual(name_categories("Gayo Lues area"), ["area"])
        self.assertIn("nonlatin", name_categories("Видин"))
        self.assertIn("area", name_categories("金湖鎮 area"))
        self.assertIn("nonlatin", name_categories("金湖鎮 area"))
        self.assertEqual(name_categories("ATA region"), ["oddity"])
        self.assertEqual(name_categories("Dibër"), [])
        self.assertIsNone(NONLATIN_RE.search("Côte-d’Or"))
        self.assertEqual(bgn_cyrillic("Видин"), "Vidin")
        self.assertEqual(proposed_name(1, {"name": "Gayo Lues area"}, (97.0, 4.0)), "Gayo Lues")
        self.assertEqual(proposed_name(710091, {"name": "Видин"}, (22.9, 43.99)), "Vidin")
        self.assertEqual(proposed_name(903492, {"name": "RUS West"}, (40.0, 55.0)), "RUS West")
        self.assertEqual(
            proposed_name(903981, {"name": "金湖鎮 area"}, (118.4, 24.4)),
            "Jinhu",
        )
        # 199001 is land. Ids at or above 950000 are sea and stay unchanged.
        ADMIN_HITS[199001] = {
            "iso": "IND",
            "adm1": "Rājasthān",
            "adm2": "",
            "lat": 26.0,
            "lon": 74.0,
        }
        try:
            self.assertEqual(
                proposed_name(199001, {"name": "IND North"}, (74.0, 26.0)),
                "Rajputana",
            )
        finally:
            ADMIN_HITS.pop(199001, None)
        self.assertEqual(proposed_name(710734, {"name": "Nord"}, (3.0, 50.6)), "Nord")
        self.assertEqual(
            proposed_name(904687, {"name": "NCR, Fourth District"}, (121.03, 14.47)),
            "Parañaque",
        )
        ADMIN_HITS[199002] = {
            "iso": "CHN",
            "adm1": "Liaoning",
            "adm2": "",
            "lat": 41.8,
            "lon": 123.4,
        }
        try:
            self.assertEqual(
                proposed_name(199002, {"name": "CHN East"}, (123.4, 41.8)),
                "Fengtian",
            )
        finally:
            ADMIN_HITS.pop(199002, None)
        self.assertTrue(TAG_DIR_RE.match("RUS North"))
        self.assertTrue(AREA_RE.search("Gayo Lues area"))
        self.assertTrue(ODDITY_RE.match("NCR, Fourth District"))


class TestNames1Board(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tip = _load_tip()
        cls.base = _load_base()
        cls.owners = json.loads(OWN.read_text(encoding="utf-8"))["owners"]

    def test_a_no_tag_direction_outside_pinned(self) -> None:
        bad = []
        for row in _land(self.tip):
            pid = int(row["id"])
            if pid in PINNED_NAME_IDS or pid in UNKNOWN:
                continue
            if TAG_DIR_RE.match(str(row.get("name") or "")):
                bad.append((pid, row["name"]))
        self.assertEqual(len(bad), 0, f"tag-dir left {len(bad)} e.g. {bad[:3]}")

    def test_b_no_area_suffix(self) -> None:
        bad = []
        for row in _land(self.tip):
            pid = int(row["id"])
            if pid in UNKNOWN:
                continue
            if AREA_RE.search(str(row.get("name") or "")):
                bad.append((pid, row["name"]))
        self.assertEqual(len(bad), 0, f"area left {len(bad)} e.g. {bad[:3]}")

    def test_c_no_nonlatin_outside_unknown(self) -> None:
        bad = []
        for row in _land(self.tip):
            pid = int(row["id"])
            if pid in UNKNOWN:
                continue
            if NONLATIN_RE.search(str(row.get("name") or "")):
                bad.append((pid, row["name"]))
        self.assertEqual(len(bad), 0, f"nonlatin left {len(bad)} e.g. {bad[:3]}")

    def test_d_non_name_fields_match_base(self) -> None:
        tip_rows = self.tip["provinces"]
        base_rows = self.base["provinces"]
        self.assertEqual([int(p["id"]) for p in tip_rows], [int(p["id"]) for p in base_rows])
        self.assertEqual(set(self.tip.keys()), set(self.base.keys()))
        for key in self.tip:
            if key == "provinces":
                continue
            self.assertEqual(self.tip[key], self.base[key])
        for tip, base in zip(tip_rows, base_rows):
            self.assertEqual(set(tip.keys()), set(base.keys()))
            for key, value in tip.items():
                if key == "name":
                    continue
                self.assertEqual(value, base[key], f"id {tip['id']} field {key}")

    def test_e_no_duplicate_names_within_owner(self) -> None:
        groups = defaultdict(list)
        for row in _land(self.tip):
            pid = int(row["id"])
            owner = str(self.owners.get(str(pid), ""))
            groups[(owner, str(row.get("name") or ""))].append(pid)
        bad = []
        for (owner, name), pids in sorted(groups.items()):
            if len(pids) < 2:
                continue
            if all(pid in PINNED_NAME_IDS for pid in pids):
                continue
            bad.append((owner, name, pids))
        self.assertEqual(bad, [])

    def test_unknown_reasons_are_explicit(self) -> None:
        for pid, reason in UNKNOWN.items():
            self.assertIsInstance(pid, int)
            self.assertTrue(str(reason).strip())


if __name__ == "__main__":
    unittest.main()
