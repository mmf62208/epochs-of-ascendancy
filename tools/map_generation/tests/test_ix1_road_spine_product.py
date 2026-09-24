#!/usr/bin/env python3
"""Gates: IX-1 Road Spine player order → edges + cheaper move cost."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from ix1_road_spine_product import (  # noqa: E402
    BONN_ID,
    ESSEN_CONTROL_ID,
    GER_1936_DAY0_MANDATE,
    HUB_ID,
    IX1_FIRST_SESSION_MANDATE_COST,
    LEVERKUSEN_ID,
    SLICE_NAME,
    apply_road_spine_order,
    board_has_edge,
    build_ix1_road_spine_product,
    corridor_is_owned_adjacent,
    empty_board,
    ix1_day0_mandate_gate,
    ix1_day_tick_unblocked,
    ix1_province_select_under_garrison,
    ix1_road_spine_mandate_cost,
    ix1_search_go_live_path,
    ix1_search_go_live_signals,
    ix1_search_go_resolve,
    ix1_search_go_spine_visible,
    load_ix1_spec,
    movement_cost,
    shipped_api_integrity,
)


class TestIx1RoadSpineProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_ix1_road_spine_product()
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(p.get("slice"), SLICE_NAME)
        self.assertEqual(p.get("hub_id"), HUB_ID)
        self.assertEqual(sorted(p.get("corridor_ids") or []), [BONN_ID, HUB_ID, LEVERKUSEN_ID])
        self.assertLess(float(p.get("move_cost_after")), float(p.get("move_cost_before")))
        self.assertLess(float(p.get("move_cost_after")), float(p.get("control_move_cost")))

    def test_spec_and_adjacency(self) -> None:
        spec = load_ix1_spec()
        self.assertEqual(spec.get("slice"), SLICE_NAME)
        adj = corridor_is_owned_adjacent(spec)
        self.assertTrue(adj.get("ok"), msg=adj)
        self.assertEqual(adj.get("n"), 3)

    def test_apply_order_edges_and_cost(self) -> None:
        board = empty_board(infra=4, development_level=2)
        pre = movement_cost(4, 2, "plains", 0)
        applied = apply_road_spine_order(board, HUB_ID)
        self.assertTrue(applied.get("ok"), msg=applied)
        post = applied.get("board") or {}
        self.assertTrue(board_has_edge(post, HUB_ID, BONN_ID))
        self.assertTrue(board_has_edge(post, HUB_ID, LEVERKUSEN_ID))
        self.assertFalse(board_has_edge(post, HUB_ID, ESSEN_CONTROL_ID))
        self.assertEqual(int(post[HUB_ID]["infrastructure"]), 5)
        self.assertLess(float(applied["move_cost_after"]), pre)
        self.assertLess(float(applied["move_cost_after"]), float(applied["control_move_cost"]))
        # Essen control stays at starting infra / no roads.
        self.assertEqual(int(post[ESSEN_CONTROL_ID]["infrastructure"]), 4)
        self.assertEqual(post[ESSEN_CONTROL_ID]["built_road_neighbors"], [])

    def test_endpoint_order_is_one_edge_only(self) -> None:
        board = empty_board()
        applied = apply_road_spine_order(board, BONN_ID)
        self.assertTrue(applied.get("ok"), msg=applied)
        post = applied.get("board") or {}
        self.assertTrue(board_has_edge(post, BONN_ID, HUB_ID))
        self.assertFalse(board_has_edge(post, HUB_ID, LEVERKUSEN_ID))

    def test_rejects_off_corridor(self) -> None:
        applied = apply_road_spine_order(empty_board(), ESSEN_CONTROL_ID)
        self.assertFalse(applied.get("ok"))
        self.assertEqual(applied.get("reason"), "not_on_ix1_corridor")

    def test_shipped_apis(self) -> None:
        g = shipped_api_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_ger_1936_day0_mandate_gate(self) -> None:
        spec = load_ix1_spec()
        self.assertEqual(int(spec.get("first_session_mandate_cost", -1)), IX1_FIRST_SESSION_MANDATE_COST)
        self.assertEqual(ix1_road_spine_mandate_cost(spec), 0)
        self.assertEqual(GER_1936_DAY0_MANDATE, 0)
        gate = ix1_day0_mandate_gate(GER_1936_DAY0_MANDATE, spec)
        self.assertTrue(gate.get("ok"), msg=gate)
        self.assertEqual(int(gate.get("mandate")), 0)
        self.assertLessEqual(int(gate.get("cost")), int(gate.get("mandate")))
        self.assertLess(int(gate.get("cost")), int(gate.get("generic_koeln_invest_cost")))
        p = build_ix1_road_spine_product()
        self.assertIn("day0_mandate_gate", p.get("passes") or [])

    def test_day_tick_unblocked_with_spine_in_progress(self) -> None:
        tick = ix1_day_tick_unblocked()
        self.assertTrue(tick.get("ok"), msg=tick)
        p = build_ix1_road_spine_product()
        self.assertIn("day_tick_unblocked", p.get("passes") or [])
        self.assertIn("day0_mandate_gate", p.get("passes") or [])

    def test_province_select_under_garrison(self) -> None:
        gate = ix1_province_select_under_garrison()
        self.assertTrue(gate.get("ok"), msg=gate)
        self.assertEqual(int(gate.get("hub_id")), HUB_ID)
        self.assertEqual(sorted(gate.get("corridor_ids") or []), [BONN_ID, HUB_ID, LEVERKUSEN_ID])
        p = build_ix1_road_spine_product()
        self.assertIn("province_select_under_garrison", p.get("passes") or [])

    def test_search_go_live_resolve_koln_aliases(self) -> None:
        # Play MIXED fc6c7ca: Cologne/Koln Search+Go was a silent no-op.
        for q in ("Köln", "koln", "koeln", "Cologne", "cologne", "710417"):
            self.assertEqual(ix1_search_go_resolve(q), HUB_ID, msg=q)
        live = ix1_search_go_live_path()
        self.assertTrue(live.get("ok"), msg=live)
        p = build_ix1_road_spine_product()
        self.assertIn("search_go_live_resolve", p.get("passes") or [])

    def test_search_go_live_signals_wired(self) -> None:
        # Play MIXED e36825b: resolve PASS, live LineEdit+Go was a dead control.
        gate = ix1_search_go_live_signals()
        self.assertTrue(gate.get("ok"), msg=gate)
        p = build_ix1_road_spine_product()
        self.assertIn("search_go_live_signals", p.get("passes") or [])

    def test_search_go_spine_visible_on_koln_inspector(self) -> None:
        # Play MIXED 5732d34: Köln panel opened, Build Road Spine absent among facility rows.
        gate = ix1_search_go_spine_visible()
        self.assertTrue(gate.get("ok"), msg=gate)
        self.assertEqual(int(gate.get("hub_id")), HUB_ID)
        p = build_ix1_road_spine_product()
        self.assertIn("search_go_spine_visible", p.get("passes") or [])

    def test_live_f5_equiv_gate_not_playtest_clock(self) -> None:
        tick = ix1_day_tick_unblocked()
        self.assertTrue(tick.get("ok"), msg=tick)
        self.assertNotIn("live_equiv_uses_playtest_clock", tick.get("missing") or [])
        self.assertNotIn("simulate_live_f5_day_advance", tick.get("missing") or [])
        self.assertNotIn("pick_full_board_scan", tick.get("missing") or [])
        self.assertNotIn("graphical_play_gate", tick.get("missing") or [])
        self.assertNotIn("live_equiv_past_plus6", tick.get("missing") or [])
        self.assertNotIn("live_f5_autosave_skip", tick.get("missing") or [])


if __name__ == "__main__":
    unittest.main()
