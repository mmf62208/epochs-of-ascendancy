#!/usr/bin/env python3
"""Pure tests for land-leader → land-formation assignment (no double-assign)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from leader_formation_assigner import (  # noqa: E402
    active_land_leaders_from_rosters,
    assign_leaders_to_land_formations,
    pick_leader_for_land_formation,
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


class TestPickerPure(unittest.TestCase):
    def test_prefers_same_tag_land_leader(self) -> None:
        leaders = [
            {
                "leader_id": "ger_a",
                "country_tag": "GER",
                "leader_type": "general",
                "attack_skill": 5,
                "defense_skill": 5,
                "planning_skill": 5,
                "organization_skill": 5,
            },
            {
                "leader_id": "fra_a",
                "country_tag": "FRA",
                "leader_type": "general",
                "attack_skill": 9,
                "defense_skill": 9,
                "planning_skill": 9,
                "organization_skill": 9,
            },
        ]
        pick = pick_leader_for_land_formation("GER", "division", leaders, set())
        self.assertEqual(pick, "ger_a")

    def test_skips_admiral_for_land(self) -> None:
        leaders = [
            {
                "leader_id": "ger_adm",
                "country_tag": "GER",
                "leader_type": "admiral",
                "attack_skill": 9,
                "defense_skill": 9,
                "planning_skill": 9,
                "organization_skill": 9,
            },
            {
                "leader_id": "ger_gen",
                "country_tag": "GER",
                "leader_type": "general",
                "attack_skill": 4,
                "defense_skill": 4,
                "planning_skill": 4,
                "organization_skill": 4,
            },
        ]
        self.assertEqual(pick_leader_for_land_formation("GER", "division", leaders, set()), "ger_gen")

    def test_no_double_assign(self) -> None:
        leaders = [
            {
                "leader_id": "g1",
                "country_tag": "GER",
                "leader_type": "general",
                "attack_skill": 8,
                "defense_skill": 8,
                "planning_skill": 8,
                "organization_skill": 8,
            },
            {
                "leader_id": "g2",
                "country_tag": "GER",
                "leader_type": "general",
                "attack_skill": 5,
                "defense_skill": 5,
                "planning_skill": 5,
                "organization_skill": 5,
            },
        ]
        forms = [
            {"formation_id": "GER_formation_0", "country_tag": "GER", "formation_type": "division"},
            {"formation_id": "GER_formation_1", "country_tag": "GER", "formation_type": "division"},
            {"formation_id": "GER_formation_2", "country_tag": "GER", "formation_type": "garrison"},
        ]
        r1 = assign_leaders_to_land_formations(forms, leaders)
        self.assertEqual(len(r1["assignments"]), 2)
        self.assertEqual(set(r1["assignments"].values()), {"g1", "g2"})
        # Second pass with already-assigned leader_ids → no extra double assigns
        forms2 = []
        for f in forms:
            f2 = dict(f)
            f2["leader_id"] = r1["assignments"].get(f["formation_id"], "")
            forms2.append(f2)
        r2 = assign_leaders_to_land_formations(forms2, leaders)
        self.assertEqual(r2["assignments"], {})

    def test_empty_roster_no_crash(self) -> None:
        forms = [{"formation_id": "X", "country_tag": "GER", "formation_type": "division"}]
        r = assign_leaders_to_land_formations(forms, [])
        self.assertEqual(r["assignments"], {})

    def test_skill_order_deterministic(self) -> None:
        leaders = [
            {
                "leader_id": "low",
                "country_tag": "USA",
                "leader_type": "general",
                "attack_skill": 3,
                "defense_skill": 3,
                "planning_skill": 3,
                "organization_skill": 3,
            },
            {
                "leader_id": "high",
                "country_tag": "USA",
                "leader_type": "general",
                "attack_skill": 8,
                "defense_skill": 8,
                "planning_skill": 8,
                "organization_skill": 8,
            },
        ]
        self.assertEqual(pick_leader_for_land_formation("USA", "division", leaders, set()), "high")


class TestShippedRosterMajors(unittest.TestCase):
    def test_majors_have_at_least_three_active_land_leaders(self) -> None:
        land = active_land_leaders_from_rosters(_load_merged_roster(), 1936)
        by = {}
        for e in land:
            t = str(e.get("country_tag") or "")
            by[t] = by.get(t, 0) + 1
        for m in MAJORS:
            self.assertGreaterEqual(by.get(m, 0), 3, msg=f"{m} has {by.get(m, 0)} land leaders")

    def test_major_land_formations_get_three_commanders(self) -> None:
        """Simulate major OOB land slots (5 land of 8) against live roster."""
        land_leaders = active_land_leaders_from_rosters(_load_merged_roster(), 1936)
        for m in MAJORS:
            leaders = [e for e in land_leaders if e.get("country_tag") == m]
            forms = [
                {"formation_id": f"{m}_formation_{i}", "country_tag": m, "formation_type": ft}
                for i, ft in enumerate(
                    ["division", "division", "fleet", "air_wing", "garrison", "task_force", "division", "division"]
                )
            ]
            r = assign_leaders_to_land_formations(forms, leaders)
            land_with = sum(
                1
                for f in forms
                if f["formation_type"] in ("division", "garrison")
                and (
                    f["formation_id"] in r["assignments"]
                    or str(f.get("leader_id") or "")
                )
            )
            self.assertGreaterEqual(land_with, 3, msg=f"{m} land_with={land_with} assigns={r['assignments']}")

    def test_gd_wiring_exists(self) -> None:
        lm = (ROOT / "scripts" / "leaders" / "LeaderManager.gd").read_text(encoding="utf-8")
        self.assertIn("func pick_leader_id_for_land_formation", lm)
        self.assertIn("func auto_assign_land_leaders_for_country", lm)
        self.assertIn("func auto_assign_land_leaders_for_all_countries", lm)
        sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
        self.assertIn("auto_assign_land_leaders_for_all_countries", sl)
        self.assertIn("_print_land_leader_assign_evidence", sl)
        self.assertIn("Land formation commanders", sl)


if __name__ == "__main__":
    unittest.main(verbosity=2)
