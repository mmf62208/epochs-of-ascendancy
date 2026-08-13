#!/usr/bin/env python3
"""Gates: HH third map-visible class (infiltration) + chokepoint contest state."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_next_list_helpers import (  # noqa: E402
    HH_MAP_VISIBLE_CLASSES,
    format_hh_monthly_map_signal,
    pick_hh_action_class,
    pick_hh_secondary_action_class,
)
from map_polish_formatters import (  # noqa: E402
    compute_chokepoint_contest,
    format_chokepoint_contest_badge,
    load_chokepoint_id_set,
)

WF = ROOT / "data" / "provinces_world_full"
GD_HELPERS = ROOT / "scripts" / "map" / "MapNextListHelpers.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_OVERLAY = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"
GD_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


class TestHHThirdClass(unittest.TestCase):
    def test_three_map_visible_fingerprints_distinct(self) -> None:
        sab = format_hh_monthly_map_signal(1936, 3, 1, "A", "sabotage", 0.5, "GER")
        econ = format_hh_monthly_map_signal(1936, 4, 2, "B", "economic_pressure", 0.5, "FRA")
        inf = format_hh_monthly_map_signal(1936, 5, 3, "C", "infiltration", 0.5, "SOV")
        self.assertEqual(sab["action_class"], "sabotage")
        self.assertEqual(econ["action_class"], "economic_pressure")
        self.assertEqual(inf["action_class"], "infiltration")
        # Distinct marker / tint / map_effect triples
        triples = {
            (sab["marker"], sab["tint_key"], sab["map_effect"]),
            (econ["marker"], econ["tint_key"], econ["map_effect"]),
            (inf["marker"], inf["tint_key"], inf["map_effect"]),
        }
        self.assertEqual(len(triples), 3)
        self.assertEqual(inf["tint_key"], "loyalty_strain")
        self.assertEqual(inf["map_effect"], "loyalty_infiltration")
        self.assertEqual(inf["marker"], "◈")
        self.assertIn("infiltration", inf["title"].lower())

    def test_pick_selects_infiltration(self) -> None:
        # m%3==2 and hand>=0.30 → infiltration
        self.assertEqual(pick_hh_action_class(5, 0.35), "infiltration")
        self.assertEqual(pick_hh_action_class(2, 0.40), "infiltration")
        # Still preserve sabotage / economic_pressure
        self.assertEqual(pick_hh_action_class(3, 0.5), "sabotage")
        self.assertEqual(pick_hh_action_class(4, 0.4), "economic_pressure")
        self.assertEqual(set(HH_MAP_VISIBLE_CLASSES), {"sabotage", "economic_pressure", "infiltration"})

    def test_secondary_complements_with_infiltration(self) -> None:
        self.assertEqual(
            pick_hh_secondary_action_class(3, 0.5, "sabotage"), "infiltration"
        )
        self.assertEqual(
            pick_hh_secondary_action_class(4, 0.35, "economic_pressure"), "infiltration"
        )
        self.assertIn(
            pick_hh_secondary_action_class(5, 0.45, "infiltration"),
            ("sabotage", "economic_pressure"),
        )

    def test_gd_wiring_infiltration(self) -> None:
        helpers = GD_HELPERS.read_text(encoding="utf-8")
        self.assertIn("infiltration", helpers)
        self.assertIn("loyalty_strain", helpers)
        self.assertIn("loyalty_infiltration", helpers)
        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("infiltration", gd)
        self.assertIn("loyalty_strain", gd)
        renderer = GD_RENDERER.read_text(encoding="utf-8")
        self.assertIn("loyalty_strain", renderer)


class TestChokepointContest(unittest.TestCase):
    def test_controlled_contested_unowned(self) -> None:
        controlled = compute_chokepoint_contest(
            province_id=1, controller_tag="ENG", owner_tag="ENG"
        )
        self.assertEqual(controlled["state"], "controlled")
        self.assertTrue(controlled["controlled"])
        self.assertFalse(controlled["contested"])
        self.assertIn("ENG", controlled["summary"])

        contested = compute_chokepoint_contest(
            province_id=2, controller_tag="GER", owner_tag="ENG"
        )
        self.assertEqual(contested["state"], "contested")
        self.assertTrue(contested["contested"])
        badge_c = format_chokepoint_contest_badge(contested)
        self.assertIn("contested", badge_c.lower())

        unowned = compute_chokepoint_contest(province_id=3, controller_tag="", owner_tag="")
        self.assertEqual(unowned["state"], "unowned")
        self.assertTrue(unowned["unowned"])
        badge_u = format_chokepoint_contest_badge(unowned)
        self.assertIn("unowned", badge_u.lower())

    def test_shipped_chokepoint_ids(self) -> None:
        payload = json.loads((WF / "naval_chokepoints.json").read_text(encoding="utf-8"))
        ids = load_chokepoint_id_set(payload)
        self.assertGreaterEqual(len(ids), 30)
        owners = json.loads((WF / "province_ownership_1936.json").read_text()).get(
            "owners"
        ) or {}
        # At least one choke with ownership → controlled (owner fills controller)
        found_controlled = False
        for pid in list(ids)[:40]:
            tag = str(owners.get(str(pid), owners.get(pid, "")) or "")
            if not tag:
                continue
            c = compute_chokepoint_contest(
                province_id=int(pid), controller_tag="", owner_tag=tag
            )
            if c["state"] == "controlled":
                found_controlled = True
                self.assertEqual(c["controller"], tag.upper())
                break
        self.assertTrue(found_controlled, msg="expected at least one owned choke")

    def test_gd_wiring_contest(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func get_chokepoint_contest_state", mm)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("get_chokepoint_contest_state", insight)
        self.assertIn("format_chokepoint_contest_badge", insight)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func compute_chokepoint_contest", fmt)
        self.assertIn("func format_chokepoint_contest_badge", fmt)
        overlay = GD_OVERLAY.read_text(encoding="utf-8")
        self.assertIn("get_chokepoint_contest_state", overlay)
        self.assertIn("contested", overlay)


if __name__ == "__main__":
    unittest.main(verbosity=2)
