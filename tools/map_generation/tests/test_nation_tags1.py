#!/usr/bin/env python3
"""NATION-TAGS-1: UKR/MDA/PRC/MAN resolve, 1945 Poland owns cc=PL, gap provinces exist.

Fails on a board that still has no catalog, no 1945 Poland, and no 906000–906020.
Also fails if those 21 ids sit in the GAP clash window 905849–905888 or collide
with a province id used on any scanned origin branch (land through 905908,
seas 950340–950342).
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from nation_tags1_product import ERA_YEARS, GAPS, NEW_TAGS, audit  # noqa: E402

# Clash window reserved by GAP-HAWAII / GAP-IBS / GAP-CHINA (PRs #122–#124).
# Inclusive end is 905888. The low bound is written as 905848+1 so a remap of
# the nation-tags block cannot rewrite this guard into the new ids.
CLASH_LO = 905848 + 1
CLASH_HI = 905888

# Highest land id in provinces_base.json on any refs/remotes/origin ref,
# scanned 2026-10-26 (182 refs). PR #128 gap-west-ukr owns 905900-905908.
# PR #126 GAP-USSR-WEST owns 905889-905899 (the prompt count was UNKNOWN,
# roughly 10-14; the branch used 11). Seas added on that stack: 950340,
# 950341, 950342. 950343 is reserved for a Black Sea split and is absent.
# Natural Earth cache coordinates are not province ids.
SCANNED_LAND_HI = 905908
SCANNED_SEAS = (950340, 950341, 950342)

_GAP_NAMES = (
    "Kiev",
    "Odessa",
    "Kharkiv",
    "Dnipropetrovsk",
    "Crimean ASSR",
    "Lviv",
    "Lutsk",
    "Chernivtsi",
    "Chisinau",
    "Harbin",
    "Changchun",
    "Qiqihar",
    "Hailar",
    "Chongqing",
    "Guangzhou",
    "Chengdu",
    "Fuzhou",
    "Zhengzhou",
    "Taiyuan",
    "Guiyang",
    "Hohhot",
)


class TestNationTags1(unittest.TestCase):
    def test_1936_column_is_not_a_new_tag(self) -> None:
        idx = ERA_YEARS.index(1936)
        for spec in GAPS:
            self.assertNotIn(spec.owners[idx], NEW_TAGS, spec.pid)

    def test_board_has_tags_poland_1945_and_gap_provinces(self) -> None:
        report = audit()
        self.assertTrue(report["ok"], "\n".join(report["failures"]))

    def test_gap_ids_miss_clash_window_and_scanned_branches(self) -> None:
        ids = [spec.pid for spec in GAPS]
        self.assertEqual(len(ids), 21)
        self.assertEqual([spec.name for spec in GAPS], list(_GAP_NAMES))
        self.assertEqual(ids, list(range(ids[0], ids[0] + 21)))
        clash = set(range(CLASH_LO, CLASH_HI + 1))
        scanned = set(range(CLASH_LO, SCANNED_LAND_HI + 1)) | set(SCANNED_SEAS)
        self.assertEqual(sorted(set(ids) & clash), [])
        self.assertEqual(sorted(set(ids) & scanned), [])
        self.assertGreater(min(ids), SCANNED_LAND_HI)
        self.assertLess(max(ids), min(SCANNED_SEAS))
        base = json.loads(
            (ROOT / "data" / "provinces_world_accurate" / "provinces_base.json").read_text(
                encoding="utf-8"
            )
        )
        board_ids = {int(row["id"]) for row in base["provinces"]}
        self.assertTrue(set(ids) <= board_ids)
        self.assertEqual(sorted(board_ids & scanned), [])
        full = json.loads(
            (ROOT / "data" / "provinces_world_full" / "provinces_base.json").read_text(
                encoding="utf-8"
            )
        )
        full_ids = {int(row["id"]) for row in full["provinces"]}
        self.assertTrue(set(ids).isdisjoint(full_ids))

    def test_reconcile_west_ids_start_at_906100_and_miss_clash(self) -> None:
        """MAP-RECONCILE-1 unique #126/#128 names. Fails while they are absent
        or if any of them lands in 905849–905908 or 906000–906020.
        """
        names = (
            "Vinnytsia",
            "Chernihiv",
            "Donetsk",
            "Smolensk",
            "Kursk",
            "Tula",
            "Stanislawow",
            "Tarnopol",
            "Rovno",
            "Drohobych",
            "Kovel",
        )
        base = json.loads(
            (ROOT / "data" / "provinces_world_accurate" / "provinces_base.json").read_text(
                encoding="utf-8"
            )
        )
        by_name = {}
        board_ids = set()
        for row in base["provinces"]:
            pid = int(row["id"])
            board_ids.add(pid)
            by_name.setdefault(str(row.get("name")), pid)
        got = []
        for name in names:
            self.assertIn(name, by_name, name)
            got.append(by_name[name])
        self.assertEqual(got, list(range(906100, 906100 + len(names))))
        clash_land = set(range(CLASH_LO, SCANNED_LAND_HI + 1))
        clash_tags = set(range(906000, 906021))
        self.assertEqual(sorted(set(got) & clash_land), [])
        self.assertEqual(sorted(set(got) & clash_tags), [])
        self.assertEqual(sorted(board_ids & clash_land), [])
        self.assertTrue(set(SCANNED_SEAS).isdisjoint(board_ids))
        self.assertNotIn(950343, board_ids)
        self.assertTrue(set(got).isdisjoint(set(range(905849, 905909))))


if __name__ == "__main__":
    unittest.main()
