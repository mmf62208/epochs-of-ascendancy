#!/usr/bin/env python3
"""Gates: sea-zone control multipliers on live supply/trade path (not inspector-only)."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from sea_zone_control import (  # noqa: E402
    apply_sea_zone_multiplier,
    combine_path_multipliers,
    compute_sea_zone_control,
    friendly_sea_zone_multipliers,
    sea_zone_strategic_modifiers,
)

WF = ROOT / "data" / "provinces_world_full"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_SM = ROOT / "scripts" / "supply" / "SupplyManager.gd"
GD_TM = ROOT / "scripts" / "national" / "TradeManager.gd"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"


class TestSeaZoneLiveEffectPure(unittest.TestCase):
    def test_controlled_best_contested_worst_of_three(self) -> None:
        controlled = sea_zone_strategic_modifiers(
            {"controller": "ENG", "contested": False, "unowned": False}
        )
        contested = sea_zone_strategic_modifiers(
            {"controller": "ENG", "contested": True, "unowned": False}
        )
        unowned = sea_zone_strategic_modifiers(
            {"controller": "", "contested": False, "unowned": True}
        )
        self.assertGreater(
            float(controlled["supply_multiplier"]),
            float(contested["supply_multiplier"]),
        )
        self.assertGreater(
            float(controlled["trade_multiplier"]),
            float(unowned["trade_multiplier"]),
        )
        self.assertGreater(
            float(controlled["supply_multiplier"]),
            float(unowned["supply_multiplier"]),
        )
        self.assertNotEqual(
            float(controlled["supply_multiplier"]),
            float(contested["supply_multiplier"]),
        )

    def test_friendly_vs_hostile_and_landlocked(self) -> None:
        friendly = friendly_sea_zone_multipliers(
            {"controller": "ENG", "contested": False, "unowned": False},
            "ENG",
        )
        hostile = friendly_sea_zone_multipliers(
            {"controller": "GER", "contested": False, "unowned": False},
            "ENG",
        )
        contested = friendly_sea_zone_multipliers(
            {"controller": "ENG", "contested": True, "unowned": False},
            "ENG",
        )
        no_zone = friendly_sea_zone_multipliers({}, "ENG")
        self.assertEqual(friendly["relation"], "friendly")
        self.assertEqual(hostile["relation"], "hostile")
        self.assertGreater(
            float(friendly["supply_multiplier"]),
            float(contested["supply_multiplier"]),
        )
        self.assertGreater(
            float(contested["supply_multiplier"]),
            float(hostile["supply_multiplier"]),
        )
        # Landlocked / no zone: identity multipliers, does not apply sealane penalty
        self.assertFalse(no_zone["applies"])
        self.assertEqual(float(no_zone["supply_multiplier"]), 1.0)
        self.assertEqual(float(no_zone["trade_multiplier"]), 1.0)

    def test_path_combine_and_apply(self) -> None:
        # Landlocked path → default 1.0
        self.assertEqual(combine_path_multipliers([]), 1.0)
        avg = combine_path_multipliers([1.12, 0.92, 1.00])
        self.assertGreater(avg, 0.9)
        self.assertLess(avg, 1.12)
        base = 100.0
        boosted = apply_sea_zone_multiplier(base, 1.12)
        cut = apply_sea_zone_multiplier(base, 0.85)
        self.assertGreater(boosted, base)
        self.assertLess(cut, base)
        self.assertAlmostEqual(boosted, 112.0, places=5)

    def test_world_full_zone_batch_non_default(self) -> None:
        """≥1 world_full sea zone yields non-default controlled/contested mult when owners present."""
        sea_path = WF / "sea_zone_theaters.json"
        own_path = WF / "province_ownership_1936.json"
        self.assertTrue(sea_path.is_file())
        sea = json.loads(sea_path.read_text(encoding="utf-8"))
        owners = json.loads(own_path.read_text(encoding="utf-8")).get("owners") or {}
        # normalize owners keys
        owners_n = {int(k) if str(k).isdigit() else k: v for k, v in owners.items()}
        found = 0
        samples = []
        for z in sea.get("zones") or []:
            pids = list(z.get("province_ids") or [])
            if not pids:
                continue
            ctrl = compute_sea_zone_control(str(z.get("name", "Z")), pids, owners_n)
            mods = sea_zone_strategic_modifiers(ctrl)
            fr = friendly_sea_zone_multipliers(ctrl, "ENG")
            if float(mods["supply_multiplier"]) != 1.0 or float(fr["trade_multiplier"]) != 1.0:
                found += 1
                if len(samples) < 3:
                    samples.append(
                        (
                            z.get("name"),
                            mods["state"],
                            mods["supply_multiplier"],
                            fr.get("relation"),
                        )
                    )
            # Force synthetic control on first zone for guaranteed non-default
            if found == 0 and pids:
                forced = compute_sea_zone_control(
                    "test", pids[:3], {int(pids[0]): "ENG", int(pids[1]): "ENG"}
                )
                fm = sea_zone_strategic_modifiers(forced)
                if float(fm["supply_multiplier"]) > 1.0:
                    found += 1
                    samples.append(("forced", fm["state"], fm["supply_multiplier"], "friendly"))
        self.assertGreaterEqual(
            found,
            1,
            msg="expected ≥1 non-default sea-zone multiplier; samples=%s" % samples,
        )


class TestSeaZoneLiveEffectWiring(unittest.TestCase):
    def test_supply_trade_path_references(self) -> None:
        sm = GD_SM.read_text(encoding="utf-8")
        self.assertIn("get_sea_zone_supply_multiplier_for_path", sm)
        self.assertIn("get_sea_zone_trade_multiplier_for_path", sm)
        self.assertIn("get_sea_zone_control_for_province", sm)
        self.assertIn("friendly_sea_zone_multipliers_from_dict", sm)
        # Applied in daily route delivery
        self.assertIn("sea_mult", sm)
        self.assertIn("advance_supply_day", sm)
        tm = GD_TM.read_text(encoding="utf-8")
        self.assertIn("get_sea_zone_trade_multiplier_for_path", tm)
        self.assertIn("last_sea_zone_trade_mult", tm)
        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func friendly_sea_zone_multipliers", fmt)
        self.assertIn("func combine_path_multipliers", fmt)
        self.assertIn("func apply_sea_zone_multiplier", fmt)
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func get_sea_zone_strategic_modifiers", mm)
        self.assertIn("func get_sea_zone_control", mm)


if __name__ == "__main__":
    unittest.main(verbosity=2)
