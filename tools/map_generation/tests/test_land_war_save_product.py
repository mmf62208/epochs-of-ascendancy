#!/usr/bin/env python3
"""Gates: persist open land battles + march queues."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from land_war_save_product import (  # noqa: E402
    apply_land_war_save_blob,
    build_land_war_save_product,
    land_war_save_integrity,
    roundtrip_land_war,
    validate_saved_battle,
    validate_saved_march,
)


class TestLandWarSaveProduct(unittest.TestCase):
    def test_product(self) -> None:
        p = build_land_war_save_product()
        self.assertTrue(p.get("ok"), msg=p)

    def test_integrity(self) -> None:
        g = land_war_save_integrity()
        self.assertTrue(g.get("ok"), msg=g)

    def test_roundtrip_keeps_stance_and_path(self) -> None:
        rt = roundtrip_land_war(
            battles=[
                {
                    "id": "lb_3",
                    "from_id": 710173,
                    "to_id": 710739,
                    "att_tag": "GER",
                    "def_tag": "FRA",
                    "att_fid": "ger_1",
                    "def_fid": "fra_1",
                    "att_org": 0.5,
                    "def_org": 0.4,
                    "days_elapsed": 3,
                    "att_stance": "hold",
                }
            ],
            marches={
                "ger_2": {
                    "formation_id": "ger_2",
                    "country_tag": "GER",
                    "path": [710173, 710180],
                    "hop_index": 1,
                    "progress": 0.2,
                    "dest_id": 710180,
                    "from_id": 710173,
                }
            },
        )
        self.assertTrue(rt.get("ok"), msg=rt)
        battles = (rt.get("restored") or {}).get("open_battles") or []
        self.assertEqual(battles[0]["att_stance"], "hold")
        self.assertEqual(battles[0]["days_elapsed"], 3)

    def test_legacy_missing_blob_is_ok(self) -> None:
        restored = apply_land_war_save_blob(None)
        self.assertTrue(restored.get("ok"))
        self.assertTrue(restored.get("empty"))

    def test_validators(self) -> None:
        self.assertFalse(validate_saved_battle({"id": "x"}))
        self.assertFalse(validate_saved_march({"formation_id": "a"}))


if __name__ == "__main__":
    unittest.main()
