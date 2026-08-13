#!/usr/bin/env python3
"""Gates: year multi-AI campaign plan (all nations as AI agents)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from year_multi_ai_campaign_product import (  # noqa: E402
    build_year_multi_ai_campaign_product,
    collect_owner_tags,
    year_multi_ai_campaign_integrity,
)

GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SP = ROOT / "scripts" / "autoload" / "SessionPlayers.gd"
HEADLESS = ROOT / "scripts" / "core" / "HeadlessYearMultiAiCampaignTest.gd"
SHELL = ROOT / "tools" / "eoa_year_multi_ai_test.sh"


class TestYearMultiAiCampaignProduct(unittest.TestCase):
    def test_collect_owner_tags(self) -> None:
        tags = collect_owner_tags()
        self.assertGreaterEqual(len(tags), 8)
        self.assertIn("GER", tags)
        self.assertIn("USA", tags)

    def test_plan_full_year(self) -> None:
        p = build_year_multi_ai_campaign_product(days=365)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertEqual(int(p.get("days") or 0), 365)
        self.assertGreaterEqual(int(p.get("factions_n") or 0), 8)
        self.assertTrue(p.get("all_ai"))
        self.assertIn("setup_all_ai", str(p.get("pass") or []))

    def test_plan_majors_smoke(self) -> None:
        p = build_year_multi_ai_campaign_product(days=30, majors_only=True)
        self.assertTrue(p.get("ok"), msg=p)
        self.assertLessEqual(int(p.get("factions_n") or 0), 8)
        self.assertGreaterEqual(int(p.get("factions_n") or 0), 4)

    def test_integrity(self) -> None:
        g = year_multi_ai_campaign_integrity(days=365)
        self.assertTrue(g.get("ok"), msg=g)

    def test_live_wiring(self) -> None:
        self.assertTrue(HEADLESS.is_file())
        self.assertTrue(SHELL.is_file())
        gd = GD.read_text(encoding="utf-8")
        sp = SP.read_text(encoding="utf-8")
        self.assertIn("func apply_year_multi_ai_campaign_live", gd)
        self.assertIn("major_apply_sum", gd)
        self.assertIn("func setup_all_ai", sp)
        ht = HEADLESS.read_text(encoding="utf-8")
        self.assertIn("apply_year_multi_ai_campaign_live", ht)
        self.assertIn("setup_all_ai", ht)
        self.assertIn("major_apply_sum", ht)
        self.assertIn("year_multi_ai_campaign_evidence", ht)
        sh = SHELL.read_text(encoding="utf-8")
        self.assertIn("SCRIPT ERROR", sh)
        self.assertIn("end ok=true", sh)
        self.assertIn("EOA_YEAR_MULTI_AI", sh)


if __name__ == "__main__":
    unittest.main()
