#!/usr/bin/env python3
"""Gates: WORLD_CLASS_MAP_REVIEW + director docs reconciled (honest hierarchy)."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REVIEW = ROOT / "docs" / "WORLD_CLASS_MAP_REVIEW.md"
SNAPSHOT = ROOT / "docs" / "GAME_STATUS_SNAPSHOT.md"
DIRECTOR = ROOT / "docs" / "GAME_DIRECTOR_PLAN.md"
MAP_ACC = ROOT / "docs" / "MAP_ACCURACY_BUILD.md"
ROADMAP = ROOT / "docs" / "WORLD_CLASS_MAP_ROADMAP_AND_DELIVERABLES.md"
D = ROOT / "data" / "provinces_world_accurate"


class TestWorldClassMapReviewDocs(unittest.TestCase):
    def test_review_artifact_inventories_accurate_board(self) -> None:
        self.assertTrue(REVIEW.is_file(), REVIEW)
        body = REVIEW.read_text(encoding="utf-8")
        for needle in (
            "world_accurate",
            "provinces_world_accurate",
            "province_states",
            "strategic_regions",
            "naval_chokepoints",
            "hierarchy",
            "shared_edge",
            "HOI4",
            "Victoria",
        ):
            self.assertIn(needle, body, needle)
        # Province scale mentioned (historical 8761 and/or post US-merge ~5670)
        self.assertTrue(
            "8761" in body
            or "5670" in body
            or "3520" in body
            or "5.5" in body
            or "5500" in body
            or "3.5" in body,
            msg="review should state board province scale",
        )
        self.assertIn("state", body.lower())
        self.assertIn("strategic region", body.lower())
        self.assertIn("Landed vs gap", body)
        self.assertIn("human", body.lower())
        self.assertIn("FPS", body)
        for mode in ("political", "resources", "supply", "terrain"):
            self.assertIn(mode, body.lower(), mode)
        self.assertIn("Maginot", body)
        self.assertTrue(
            "multi-front" in body.lower() or "multi front" in body.lower()
        )
        self.assertIn("M0", body)
        self.assertIn("M1", body)
        self.assertIn("M6", body)
        self.assertIn("Open", body)
        # Honest hierarchy: live 31 regions
        self.assertIn("31", body)
        self.assertNotIn("429 states · 61 regions · 4 super · full membership", body)

    def test_live_membership_matches_review_numbers(self) -> None:
        """Drive shipped membership JSON — not hard-coded review fiction."""
        mem = json.loads((D / "hierarchy_membership_1936.json").read_text(encoding="utf-8"))
        p2r = mem.get("province_to_region") or {}
        p2s = mem.get("province_to_state") or {}
        region_ids = {int(v) for v in p2r.values() if int(v or 0) > 0}
        state_ids = {int(v) for v in p2s.values() if int(v or 0) > 0}
        self.assertEqual(len(region_ids), 31, msg=sorted(region_ids)[:10])
        self.assertEqual(len(state_ids), 429)
        base_n = len(
            json.loads((D / "provinces_base.json").read_text(encoding="utf-8")).get("provinces")
            or []
        )
        land_n = len(p2s)
        self.assertEqual(len(p2r), base_n)
        self.assertEqual(land_n, base_n - 340)  # seas stay 340
        self.assertGreaterEqual(base_n, 5000)
        # Post US merge ~5670; docs may still mention historical 8761

        sr = json.loads((D / "strategic_regions.json").read_text(encoding="utf-8"))
        rows = sr.get("regions") or []
        names = [str(r.get("name") or "") for r in rows]
        # M0: file rebuilt to match membership
        self.assertEqual(len(rows), 31)
        self.assertEqual(len(set(names)), 31)
        from collections import defaultdict

        p2 = defaultdict(list)
        for r in rows:
            rid = int(r.get("id") or 0)
            for pid in r.get("province_ids") or []:
                p2[int(pid)].append(rid)
        multi = sum(1 for v in p2.values() if len(v) > 1)
        self.assertEqual(multi, 0)
        na = next(r for r in rows if int(r.get("id") or 0) == 2)
        self.assertEqual(str(na.get("name")), "North America")
        self.assertGreaterEqual(len(na.get("province_ids") or []), 70)

        body = REVIEW.read_text(encoding="utf-8")
        self.assertIn("31", body)
        self.assertIn("North America", body)
        snap = SNAPSHOT.read_text(encoding="utf-8")
        self.assertIn("31", snap)
        self.assertNotIn("61** strategic regions → **4** super-regions (full membership)", snap)

    def test_snapshot_and_director_agree_with_review(self) -> None:
        snap = SNAPSHOT.read_text(encoding="utf-8")
        dirp = DIRECTOR.read_text(encoding="utf-8")
        self.assertIn("WORLD_CLASS_MAP_REVIEW", snap)
        self.assertIn("world_accurate", snap)
        self.assertTrue(
            "8761" in snap
            or "5670" in snap
            or "3520" in snap
            or "US merge" in snap
            or "1–4" in snap
            or "RoW sparse" in snap
            or "sparse" in snap.lower(),
            msg="snapshot should state board scale or US merge",
        )
        self.assertIn("human", snap.lower())
        self.assertIn("FPS", snap)
        self.assertIn("WORLD_CLASS_MAP_REVIEW", dirp)
        self.assertIn("M1", dirp)
        self.assertIn("D5.6", dirp)
        # M0 done claims after continue goal
        self.assertTrue(
            "M0" in snap and ("done" in snap.lower() or "31" in snap),
            msg="snapshot should reflect M0/31 regions",
        )

    def test_map_accuracy_links_review_and_adj_cov(self) -> None:
        body = MAP_ACC.read_text(encoding="utf-8")
        self.assertIn("WORLD_CLASS_MAP_REVIEW", body)
        self.assertIn("429", body)
        self.assertIn("31", body)
        self.assertIn("0.971", body)
        self.assertNotIn("~0.92 @ quant 5.0", body)

    def test_legacy_roadmap_superseded_banner(self) -> None:
        body = ROADMAP.read_text(encoding="utf-8")
        self.assertIn("Superseded", body)
        self.assertIn("WORLD_CLASS_MAP_REVIEW", body)
        self.assertIn("world_accurate", body)

    def test_board_still_has_hierarchy_files_for_review_claims(self) -> None:
        """Structural: review claims map to real shipped files."""
        self.assertTrue((D / "province_states.json").is_file())
        self.assertTrue((D / "strategic_regions.json").is_file())
        self.assertTrue((D / "super_regions.json").is_file())
        self.assertTrue((D / "hierarchy_membership_1936.json").is_file())
        self.assertTrue((D / "province_resources_layer.json").is_file())
        self.assertTrue((D / "naval_chokepoints.json").is_file())
        self.assertTrue((D / "province_adjacency.json").is_file())


if __name__ == "__main__":
    unittest.main()
