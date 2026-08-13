#!/usr/bin/env python3
"""Structural tests for map viewport culling helpers and SaveLoad map keys (shipped source)."""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class TestMapZoomLODCulling(unittest.TestCase):
    def test_use_viewport_culling_for_board_in_source(self) -> None:
        src = (ROOT / "scripts" / "map" / "MapZoomLOD.gd").read_text(encoding="utf-8")
        self.assertIn("func use_viewport_culling_for_board", src)
        self.assertIn("HIGH_PROVINCE_CULL_THRESHOLD", src)
        self.assertIn("func cull_rect_margin_px", src)
        # Threshold at 800+ enables operational culling
        self.assertIn("province_count >= HIGH_PROVINCE_CULL_THRESHOLD", src)
        self.assertIn("Tier.OPERATIONAL", src)

    def test_map_renderer_uses_board_culling(self) -> None:
        src = (ROOT / "scripts" / "map" / "MapRenderer.gd").read_text(encoding="utf-8")
        self.assertIn("use_viewport_culling_for_board", src)
        self.assertIn("cull_rect_margin_px", src)

    def test_culling_logic_pure_python_mirror(self) -> None:
        """Drive the same decision rules as MapZoomLOD (source of truth is the .gd constants)."""
        # Parse thresholds from shipped file so we don't hard-code divergent values.
        src = (ROOT / "scripts" / "map" / "MapZoomLOD.gd").read_text(encoding="utf-8")
        m = re.search(r"HIGH_PROVINCE_CULL_THRESHOLD:\s*int\s*=\s*(\d+)", src)
        self.assertIsNotNone(m)
        thr = int(m.group(1))
        m2 = re.search(r"WORLD_BOARD_CULL_THRESHOLD:\s*int\s*=\s*(\d+)", src)
        self.assertIsNotNone(m2)
        world_thr = int(m2.group(1))
        self.assertIn("func max_resource_icons_for_board", src)
        self.assertIn("func max_province_labels_for_board", src)
        self.assertIn("func city_marker_min_zoom_for_board", src)
        self.assertIn("func site_marker_min_zoom_for_board", src)
        self.assertIn("ACCURATE_BOARD_CULL_THRESHOLD", src)

        def use_cull(tier: str, count: int) -> bool:
            if count >= world_thr:
                return True
            if count >= thr:
                return tier in ("STRATEGIC", "OPERATIONAL")
            return tier == "STRATEGIC"

        self.assertTrue(use_cull("STRATEGIC", 100))
        self.assertFalse(use_cull("OPERATIONAL", 100))
        self.assertTrue(use_cull("OPERATIONAL", thr))
        self.assertTrue(use_cull("STRATEGIC", thr + 500))
        self.assertFalse(use_cull("TACTICAL", thr + 500))
        # world_full 2665: cull at tactical too
        self.assertTrue(use_cull("TACTICAL", world_thr))
        self.assertTrue(use_cull("TACTICAL", 2665))

        # Parse world-board polish budgets from shipped source (not hard-coded theater).
        m_res = re.search(
            r"static func max_resource_icons_for_board[\s\S]*?"
            r"if province_count >= WORLD_BOARD_CULL_THRESHOLD:\s*\n\s*return\s+(\d+)",
            src,
        )
        self.assertIsNotNone(m_res)
        world_icon_cap = int(m_res.group(1))
        self.assertLessEqual(world_icon_cap, 220)
        self.assertGreaterEqual(world_icon_cap, 100)

        m_margin = re.search(
            r"static func cull_rect_margin_px[\s\S]*?"
            r"if province_count >= WORLD_BOARD_CULL_THRESHOLD:\s*\n\s*return\s+([0-9.]+)",
            src,
        )
        self.assertIsNotNone(m_margin)
        self.assertGreaterEqual(float(m_margin.group(1)), 160.0)

        m_lab = re.search(
            r"static func max_province_labels_for_board[\s\S]*?"
            r"if province_count >= WORLD_BOARD_CULL_THRESHOLD:\s*\n\s*return\s+(\d+)",
            src,
        )
        self.assertIsNotNone(m_lab)
        self.assertLessEqual(int(m_lab.group(1)), 200)

        m_city_z = re.search(
            r"static func city_marker_min_zoom_for_board[\s\S]*?"
            r"if province_count >= WORLD_BOARD_CULL_THRESHOLD:\s*\n\s*return\s+([0-9.]+)",
            src,
        )
        self.assertIsNotNone(m_city_z)
        self.assertLessEqual(float(m_city_z.group(1)), 0.55)

    def test_renderer_and_overlay_wire_new_lod(self) -> None:
        renderer = (ROOT / "scripts" / "map" / "MapRenderer.gd").read_text(encoding="utf-8")
        self.assertIn("max_province_labels_for_board", renderer)
        overlay = (ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd").read_text(
            encoding="utf-8"
        )
        self.assertIn("city_marker_min_zoom_for_board", overlay)
        self.assertIn("site_marker_min_zoom_for_board", overlay)
        self.assertIn("max_resource_icons_for_board", overlay)


class TestSaveLoadMapKeys(unittest.TestCase):
    def test_serialize_includes_settlement_and_built(self) -> None:
        src = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        for key in (
            "settlement_level",
            "built_road_neighbors",
            "built_rail_neighbors",
            "infrastructure",
            "infrastructure_projects",
            "map_province_required_keys",
            "validate_map_save_payload",
        ):
            self.assertIn(key, src, msg=f"missing {key}")

    def test_validate_map_save_payload_logic(self) -> None:
        """Replicate validate_map_save_payload rules against sample payloads (real required keys from source)."""
        src = (ROOT / "scripts" / "autoload" / "SaveLoadManager.gd").read_text(encoding="utf-8")
        # Extract keys listed in map_province_required_keys PackedStringArray block
        block = re.search(
            r"func map_province_required_keys\(\)[\s\S]*?return PackedStringArray\(\[([\s\S]*?)\]\)",
            src,
        )
        self.assertIsNotNone(block)
        keys = re.findall(r'"([^"]+)"', block.group(1))
        self.assertIn("settlement_level", keys)
        self.assertIn("built_road_neighbors", keys)
        self.assertIn("built_rail_neighbors", keys)

        def validate(map_data: dict, full_save: dict | None = None) -> dict:
            missing = []
            if "provinces" not in map_data:
                return {"ok": False, "missing": ["map.provinces"]}
            for entry in map_data["provinces"]:
                if not isinstance(entry, dict):
                    missing.append("non_dict")
                    continue
                for k in keys:
                    if k not in entry:
                        missing.append(f"province.{k}")
                        break
            if full_save is not None and "infrastructure_projects" not in full_save:
                missing.append("infrastructure_projects")
            return {"ok": len(missing) == 0, "missing": missing}

        good_entry = {k: ([] if "neighbors" in k else 0) for k in keys}
        good_entry["id"] = 1
        good_entry["owner_tag"] = "GER"
        good_entry["controller_tag"] = "GER"
        good = {"provinces": [good_entry]}
        self.assertTrue(validate(good, {"infrastructure_projects": {}})["ok"])
        bad = {"provinces": [{"id": 1}]}
        self.assertFalse(validate(bad)["ok"])
        self.assertFalse(validate(good, {})["ok"])  # missing infrastructure_projects


if __name__ == "__main__":
    unittest.main(verbosity=2)
