#!/usr/bin/env python3
"""Gates: formation march own-land hops + pin lerp wiring (PR 4)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from formation_march_product import (  # noqa: E402
    MARCH_TOAST_PREFIX,
    build_formation_march_product,
    formation_march_integrity,
)

MAP_MANAGER = ROOT / "scripts" / "map" / "MapManager.gd"
BATTLE_MANAGER = ROOT / "scripts" / "combat" / "BattleManager.gd"
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
FORMATION_MOVEMENT = ROOT / "scripts" / "formations" / "FormationMovement.gd"
SAVE_LOAD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"


class TestFormationMarchProduct(unittest.TestCase):
    def test_product_wiring(self) -> None:
        p = build_formation_march_product(check_wiring=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(list(p.get("fail") or []), [], msg=p)
        wiring = p.get("wiring") or {}
        for key in (
            "find_land_path_own_land_only",
            "own_land_bfs_gate",
            "station_formation_on_province",
            "issue_march_order",
            "tick_marches_for_day",
            "day_tick_connect",
            "renderer_issue_march",
            "march_toast",
            "pin_lerp",
            "path_line_budget_8",
            "no_full_board_on_hop",
            "formation_movement_issue_march",
            "save_marches_blob",
            "block_on_battles_not_flag",
        ):
            self.assertTrue(wiring.get(key), msg=(key, wiring, p.get("fail")))

    def test_integrity(self) -> None:
        g = formation_march_integrity(check_wiring=True)
        self.assertTrue(g.get("ok"), msg=g)

    def test_map_manager_own_land_arg(self) -> None:
        mm = MAP_MANAGER.read_text(encoding="utf-8")
        self.assertIn("own_land_only", mm)
        self.assertIn("func find_land_path", mm)
        # Default false so G / corridor callers stay unchanged.
        flp_i = mm.find("func find_land_path")
        flp = mm[flp_i : flp_i + 1200]
        next_fn = flp.find("\nfunc ", 1)
        if next_fn > 0:
            flp = flp[:next_fn]
        self.assertIn("own_land_only: bool = false", flp)
        self.assertIn("if own_land_only", flp)

    def test_battle_manager_march_apis(self) -> None:
        bm = BATTLE_MANAGER.read_text(encoding="utf-8")
        for name in (
            "func station_formation_on_province",
            "func issue_march_order",
            "func tick_marches_for_day",
            "func cancel_march_order",
            "func get_march_order",
            "var _marches",
        ):
            self.assertIn(name, bm, msg=name)
        self.assertIn("game_day_advanced", bm)
        # Must not block on is_in_combat alone in issue_march_order.
        i = bm.find("func issue_march_order")
        self.assertGreaterEqual(i, 0)
        slice_ = bm[i : i + 3500]
        next_fn = slice_.find("\nfunc ", 1)
        if next_fn > 0:
            slice_ = slice_[:next_fn]
        self.assertIn("_formation_in_active_battle", slice_)
        self.assertNotIn("is_in_combat", slice_)
        self.assertIn("station_formation_on_province", slice_)
        self.assertIn("instant", slice_)

    def test_renderer_march_path(self) -> None:
        ren = MAP_RENDERER.read_text(encoding="utf-8")
        self.assertIn("issue_march_order", ren)
        self.assertIn(MARCH_TOAST_PREFIX, ren)
        self.assertIn("_update_march_visuals", ren)
        self.assertIn("MARCH_PATH_LINE_BUDGET", ren)
        self.assertIn("func _try_move_selected_unit_to_province", ren)
        move_i = ren.find("func _try_move_selected_unit_to_province")
        move = ren[move_i : move_i + 2500]
        next_fn = move.find("\nfunc ", 1)
        if next_fn > 0:
            move = move[:next_fn]
        self.assertIn("issue_march_order", move)

    def test_formation_movement_and_save(self) -> None:
        fm = FORMATION_MOVEMENT.read_text(encoding="utf-8")
        self.assertIn("func issue_march", fm)
        self.assertIn("issue_march_order", fm)
        sl = SAVE_LOAD.read_text(encoding="utf-8")
        self.assertIn('"marches"', sl)
        self.assertIn("BattleManager", sl)

    def test_corridor_still_uses_default_find_land_path(self) -> None:
        """G/corridor callers must not be forced to pass own_land_only."""
        ren = MAP_RENDERER.read_text(encoding="utf-8")
        # Corridor path uses find_land_path without requiring 5th arg.
        self.assertIn("find_land_path(hub, front_id, tag)", ren)
        self.assertIn("find_land_path(from_id, to_id, owner_tag)", ren)


if __name__ == "__main__":
    unittest.main()
