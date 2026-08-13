#!/usr/bin/env python3
"""Pure tests: admiral↔naval, air_marshal↔air assignment (no double-assign / wrong type)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from leader_formation_assigner import (  # noqa: E402
    active_air_leaders_from_rosters,
    active_land_leaders_from_rosters,
    active_naval_leaders_from_rosters,
    assign_leaders_to_branch_formations,
    assign_leaders_to_land_formations,
    pick_leader_for_formation,
)

MAJORS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP")


def _load_merged_roster() -> list:
    merged = {}
    for rel in (
        "data/leaders/historical_leaders_1918.json",
        "data/leaders/historical_leaders_1936.json",
    ):
        for e in json.loads((ROOT / rel).read_text())["leaders"]:
            merged[e["leader_id"]] = e
    return list(merged.values())


class TestBranchPickerPure(unittest.TestCase):
    def test_admiral_fills_fleet_not_general(self) -> None:
        leaders = [
            {
                "leader_id": "g1",
                "country_tag": "GER",
                "leader_type": "general",
                "attack_skill": 9,
                "defense_skill": 9,
                "planning_skill": 9,
                "organization_skill": 9,
            },
            {
                "leader_id": "a1",
                "country_tag": "GER",
                "leader_type": "admiral",
                "attack_skill": 5,
                "defense_skill": 5,
                "planning_skill": 5,
                "organization_skill": 5,
            },
        ]
        self.assertEqual(pick_leader_for_formation("GER", "fleet", leaders, set()), "a1")
        self.assertEqual(pick_leader_for_formation("GER", "division", leaders, set()), "g1")

    def test_air_marshal_fills_air_wing(self) -> None:
        leaders = [
            {
                "leader_id": "adm",
                "country_tag": "ENG",
                "leader_type": "admiral",
                "attack_skill": 8,
                "defense_skill": 8,
                "planning_skill": 8,
                "organization_skill": 8,
            },
            {
                "leader_id": "air",
                "country_tag": "ENG",
                "leader_type": "air_marshal",
                "attack_skill": 4,
                "defense_skill": 4,
                "planning_skill": 4,
                "organization_skill": 4,
            },
        ]
        self.assertEqual(pick_leader_for_formation("ENG", "air_wing", leaders, set()), "air")
        self.assertEqual(pick_leader_for_formation("ENG", "task_force", leaders, set()), "adm")

    def test_no_double_assign_across_branches(self) -> None:
        leaders = [
            {
                "leader_id": "adm1",
                "country_tag": "USA",
                "leader_type": "admiral",
                "attack_skill": 7,
                "defense_skill": 7,
                "planning_skill": 7,
                "organization_skill": 7,
            },
            {
                "leader_id": "air1",
                "country_tag": "USA",
                "leader_type": "air_marshal",
                "attack_skill": 7,
                "defense_skill": 7,
                "planning_skill": 7,
                "organization_skill": 7,
            },
        ]
        forms = [
            {"formation_id": "USA_f0", "country_tag": "USA", "formation_type": "fleet"},
            {"formation_id": "USA_f1", "country_tag": "USA", "formation_type": "task_force"},
            {"formation_id": "USA_a0", "country_tag": "USA", "formation_type": "air_wing"},
        ]
        r = assign_leaders_to_branch_formations(forms, leaders)
        self.assertEqual(len(r["assignments"]), 2)  # one admiral, one air
        self.assertEqual(r["assignments"]["USA_f0"], "adm1")
        self.assertEqual(r["assignments"]["USA_a0"], "air1")
        self.assertNotIn("USA_f1", r["assignments"])
        # second pass no double
        forms2 = []
        for f in forms:
            f2 = dict(f)
            f2["leader_id"] = r["assignments"].get(f["formation_id"], "")
            forms2.append(f2)
        r2 = assign_leaders_to_branch_formations(forms2, leaders)
        self.assertEqual(r2["assignments"], {})

    def test_empty_branch_roster_no_crash(self) -> None:
        forms = [
            {"formation_id": "X_f", "country_tag": "BEL", "formation_type": "fleet"},
            {"formation_id": "X_a", "country_tag": "BEL", "formation_type": "air_wing"},
        ]
        r = assign_leaders_to_branch_formations(forms, [])
        self.assertEqual(r["assignments"], {})


class TestShippedBranchRoster(unittest.TestCase):
    def test_majors_have_active_admiral_and_air_marshal(self) -> None:
        roster = _load_merged_roster()
        nav = active_naval_leaders_from_rosters(roster, 1936)
        air = active_air_leaders_from_rosters(roster, 1936)
        by_nav = {}
        by_air = {}
        for e in nav:
            t = e.get("country_tag")
            by_nav[t] = by_nav.get(t, 0) + 1
        for e in air:
            t = e.get("country_tag")
            by_air[t] = by_air.get(t, 0) + 1
        for m in MAJORS:
            self.assertGreaterEqual(by_nav.get(m, 0), 1, msg=f"{m} admiral count {by_nav.get(m, 0)}")
            self.assertGreaterEqual(by_air.get(m, 0), 1, msg=f"{m} air_marshal count {by_air.get(m, 0)}")

    def test_major_oob_gets_branch_commanders(self) -> None:
        roster = _load_merged_roster()
        for m in MAJORS:
            leaders = [
                e
                for e in roster
                if e.get("country_tag") == m
                and e.get("leader_type") in ("admiral", "air_marshal", "general", "field_marshal")
            ]
            # year filter
            leaders = active_naval_leaders_from_rosters(leaders, 1936) + active_air_leaders_from_rosters(
                leaders, 1936
            ) + active_land_leaders_from_rosters(
                [e for e in roster if e.get("country_tag") == m], 1936
            )
            forms = [
                {"formation_id": f"{m}_formation_{i}", "country_tag": m, "formation_type": ft}
                for i, ft in enumerate(
                    ["division", "division", "fleet", "air_wing", "garrison", "task_force", "division", "division"]
                )
            ]
            land = assign_leaders_to_land_formations(forms, leaders)
            for fid, lid in land["assignments"].items():
                for f in forms:
                    if f["formation_id"] == fid:
                        f["leader_id"] = lid
            branch = assign_leaders_to_branch_formations(forms, leaders)
            # naval: fleet + task_force
            nav_ok = sum(
                1
                for f in forms
                if f["formation_type"] in ("fleet", "task_force", "ship")
                and (f.get("leader_id") or branch["assignments"].get(f["formation_id"]))
            )
            air_ok = sum(
                1
                for f in forms
                if f["formation_type"] in ("air_wing", "air_squadron", "air_group")
                and (f.get("leader_id") or branch["assignments"].get(f["formation_id"]))
            )
            self.assertGreaterEqual(nav_ok, 1, msg=f"{m} naval_ok={nav_ok} {branch}")
            self.assertGreaterEqual(air_ok, 1, msg=f"{m} air_ok={air_ok} {branch}")

    def test_gd_wiring_exists(self) -> None:
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn("func auto_assign_branch_leaders_for_all_countries", lm)
        self.assertIn("func auto_assign_naval_leaders_for_country", lm)
        self.assertIn("func auto_assign_air_leaders_for_country", lm)
        self.assertIn("func pick_leader_id_for_formation", lm)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("auto_assign_branch_leaders_for_all_countries", sl)
        self.assertIn("_print_branch_leader_assign_evidence", sl)
        self.assertIn("Naval formation commanders", sl)
        self.assertIn("Air formation commanders", sl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
