#!/usr/bin/env python3
"""Pure tests: FIRST20-P2 F7 mapmode toggle + strip overflow state."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from first20_p2_mapmode_toggle_product import (  # noqa: E402
    INTENSITY_LABELS,
    build_first20_p2_mapmode_toggle_product,
    chips_fit_in_rows,
    first20_p2_mapmode_toggle_integrity,
    toggle_map_mode,
    toolbar_flow_max_width,
)


class TestFirst20P2MapmodeToggle(unittest.TestCase):
    def test_f2_toggles_political(self) -> None:
        mode, prior = toggle_map_mode("political", "strain")
        self.assertEqual(mode, "strain")
        self.assertEqual(prior, "political")
        back, _p = toggle_map_mode(mode, "strain", prior)
        self.assertEqual(back, "political")

    def test_peer_fkey_toggles_prior(self) -> None:
        mode, prior = toggle_map_mode("political", "vitality")
        self.assertEqual((mode, prior), ("vitality", "political"))
        mode, prior = toggle_map_mode("vitality", "infra", "political")
        self.assertEqual(mode, "infra")
        back, _p = toggle_map_mode("infra", "infra", "vitality")
        self.assertEqual(back, "vitality")

    def test_f1_does_not_leave_political(self) -> None:
        mode, prior = toggle_map_mode("political", "political", "strain")
        self.assertEqual(mode, "political")
        self.assertEqual(prior, "strain")

    def test_mutant_stuck_on_strain_fails(self) -> None:
        # Old set_map_mode("strain") + same-mode early return stays on strain.
        stuck = "strain"
        if stuck == "strain":
            stuck_again = "strain"
        self.assertNotEqual(
            toggle_map_mode("strain", "strain", "political")[0],
            stuck_again,
        )

    def test_strip_overflow_and_width(self) -> None:
        self.assertEqual(toolbar_flow_max_width(1024), 976.0)
        self.assertEqual(toolbar_flow_max_width(1280), 1232.0)
        self.assertEqual(toolbar_flow_max_width(1920), 1872.0)
        kept, overflow = chips_fit_in_rows([72.0] * 30, 572.0, 2, 4.0)
        self.assertGreater(overflow, 0)
        self.assertGreaterEqual(kept, 8)
        kept2, overflow2 = chips_fit_in_rows([72.0] * 3, 572.0, 2, 4.0)
        self.assertEqual(overflow2, 0)
        self.assertEqual(kept2, 3)

    def test_intensity_labels(self) -> None:
        self.assertEqual(INTENSITY_LABELS, ("Low", "Med", "High", "Max"))

    def test_product(self) -> None:
        p = build_first20_p2_mapmode_toggle_product()
        self.assertTrue(p.get("ok"), msg=p)
        g = first20_p2_mapmode_toggle_integrity()
        self.assertTrue(g.get("ok"), msg=g)


if __name__ == "__main__":
    unittest.main()
