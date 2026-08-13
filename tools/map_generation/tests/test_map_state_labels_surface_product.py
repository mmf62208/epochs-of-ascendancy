#!/usr/bin/env python3
"""Stream 2 gate: state name labels on states mapmode @ operational zoom."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_state_labels_surface_product import (  # noqa: E402
    build_map_state_labels_surface_product,
    build_state_label_rows,
    europe_theater_label_count,
    maginot_theater_named_hits,
    map_state_labels_surface_integrity,
    select_state_labels_for_budget,
    show_state_labels_for_context,
    state_label_font_px_for_tier,
)

LABELS_GD = ROOT / "scripts" / "map" / "MapPoliticalLabelsLayer.gd"


class TestMapStateLabelsSurface(unittest.TestCase):
    def test_visibility_policy(self) -> None:
        self.assertTrue(show_state_labels_for_context("operational", "states"))
        self.assertFalse(show_state_labels_for_context("strategic", "states"))
        self.assertFalse(show_state_labels_for_context("operational", "political"))
        self.assertFalse(show_state_labels_for_context("tactical", "states"))
        self.assertGreaterEqual(state_label_font_px_for_tier("operational"), 14)

    def test_board_rows_named(self) -> None:
        rows = build_state_label_rows(max_labels=96)
        self.assertGreaterEqual(len(rows), 20)
        self.assertTrue(any(not str(r.get("name") or "").startswith("State ") for r in rows))
        r0 = rows[0]
        self.assertIn("cx", r0)
        self.assertIn("cy", r0)
        self.assertGreater(int(r0.get("province_n") or 0), 0)

    def test_budget_keeps_europe_and_maginot_theater(self) -> None:
        """Skeptic: pure province_n cap starved Europe; require NUTS theater after budget."""
        rows = build_state_label_rows(max_labels=72)
        eu_n = europe_theater_label_count(rows)
        self.assertGreaterEqual(eu_n, 12, msg="europe_label_n=%d rows sample=%s" % (eu_n, [r.get("name") for r in rows[:12]]))
        hits = maginot_theater_named_hits(rows)
        self.assertGreaterEqual(
            len(hits),
            2,
            msg="Maginot/Polish theater names missing after budget: %s (eu=%d)" % (hits, eu_n),
        )
        # Ensure we did not only pick RoW mega-states
        names = [str(r.get("name") or "") for r in rows]
        mega = sum(1 for n in names if n in ("CHN", "BRA", "IND", "IDN", "RUS"))
        self.assertLess(mega, eu_n, msg="mega=%d eu=%d names=%s" % (mega, eu_n, names[:20]))

    def test_select_budget_prefers_europe_over_mega(self) -> None:
        fake = [
            {"state_id": 1, "name": "CHN", "cx": 6000, "cy": 1400, "province_n": 173, "is_europe_nuts": False},
            {"state_id": 2, "name": "BRA", "cx": 2800, "cy": 2800, "province_n": 127, "is_europe_nuts": False},
            {"state_id": 58, "name": "Alsace", "cx": 4113, "cy": 1034, "province_n": 8, "is_europe_nuts": True},
            {"state_id": 69, "name": "Rhineland", "cx": 4283, "cy": 1027, "province_n": 8, "is_europe_nuts": True},
            {"state_id": 78, "name": "Baden", "cx": 4353, "cy": 974, "province_n": 8, "is_europe_nuts": True},
        ]
        picked = select_state_labels_for_budget(fake, max_labels=3, europe_quota=3)
        names = {str(r.get("name")) for r in picked}
        self.assertIn("Alsace", names)
        self.assertIn("Rhineland", names)
        self.assertIn("Baden", names)
        self.assertNotIn("CHN", names)

    def test_product_visible_on_states_operational(self) -> None:
        p = build_map_state_labels_surface_product(tier="operational", map_mode="states", max_labels=96)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertTrue(p.get("show"))
        self.assertGreaterEqual(int(p.get("label_n") or 0), 20)
        self.assertGreaterEqual(int(p.get("europe_label_n") or 0), 12)
        self.assertGreaterEqual(int(p.get("maginot_theater_hit_n") or 0), 2)
        self.assertEqual(str(p.get("hotkey") or ""), "Shift+F9")
        p2 = build_map_state_labels_surface_product(tier="operational", map_mode="political")
        self.assertFalse(p2.get("show"))

    def test_integrity_wiring(self) -> None:
        g = map_state_labels_surface_integrity()
        self.assertTrue(g.get("ok"), msg=g)
        gd = LABELS_GD.read_text(encoding="utf-8")
        self.assertIn("_select_state_labels_for_budget", gd)
        self.assertIn("europe_nuts", gd)
        self.assertIn("_geo_grid_pick_state_rows", gd)


if __name__ == "__main__":
    unittest.main()
