#!/usr/bin/env python3
"""Gates: mid-war 20d save keeps land_war + infra + metadata."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from long_session_save_product import (  # noqa: E402
    REQUIRED_ROOT_KEYS,
    build_long_session_save_product,
    build_mid_war_20d_save,
    empty_land_war_shape,
    land_war_applied_after_leaders,
    long_session_save_integrity,
    validate_long_session_save,
)


class TestLongSessionSaveProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_long_session_save_product()
        self.assertTrue(p.get("ok"), msg=p)

    def test_integrity(self) -> None:
        g = long_session_save_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_required_root_keys(self) -> None:
        self.assertEqual(
            tuple(REQUIRED_ROOT_KEYS),
            (
                "metadata",
                "time",
                "map",
                "leaders",
                "infrastructure_projects",
                "land_war",
                "production",
            ),
        )
        mid = build_mid_war_20d_save()
        for key in REQUIRED_ROOT_KEYS:
            self.assertIn(key, mid)
        v = validate_long_session_save(mid)
        self.assertTrue(v.get("ok"), msg=v)

    def test_land_war_requires_open_battles_key(self) -> None:
        mid = build_mid_war_20d_save()
        mid["land_war"] = {"marches": {}, "version": 1, "next_seq": 1}
        v = validate_long_session_save(mid)
        self.assertFalse(v.get("ok"), msg=v)
        self.assertIn("land_war.open_battles", v.get("missing") or [])

    def test_empty_open_battles_list_ok(self) -> None:
        mid = build_mid_war_20d_save(open_battles=[], marches={})
        self.assertEqual(mid["land_war"]["open_battles"], [])
        v = validate_long_session_save(mid)
        self.assertTrue(v.get("ok"), msg=v)

    def test_metadata_requires_scenario_id_and_game_version(self) -> None:
        mid = build_mid_war_20d_save()
        self.assertIn("scenario_id", mid["metadata"])
        self.assertIn("game_version", mid["metadata"])
        mid["metadata"] = {"player_tag": "GER"}
        v = validate_long_session_save(mid)
        self.assertFalse(v.get("ok"), msg=v)
        missing = set(v.get("missing") or [])
        self.assertIn("metadata.scenario_id", missing)
        self.assertIn("metadata.game_version", missing)

    def test_empty_land_war_shape_has_required_keys(self) -> None:
        shape = empty_land_war_shape()
        self.assertIn("open_battles", shape)
        self.assertIn("marches", shape)
        self.assertEqual(shape["open_battles"], [])
        self.assertEqual(shape["marches"], {})

    def test_apply_order_land_war_after_leaders(self) -> None:
        sl = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(
            encoding="utf-8"
        )
        self.assertTrue(land_war_applied_after_leaders(sl))


if __name__ == "__main__":
    unittest.main()
