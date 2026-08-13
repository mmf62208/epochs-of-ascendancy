#!/usr/bin/env python3
"""Gates for inspector top-line, era-band infra density, special-site map visual pulse."""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from era_infra_profile import (  # noqa: E402
    era_band_for_year,
    era_infra_profile_for_year,
    profile_is_sparser,
)
from map_polish_formatters import (  # noqa: E402
    format_inspector_topline,
    special_site_map_visual,
    site_state_icon,
)

WF = ROOT / "data" / "provinces_world_full"
GD_FORMATTERS = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
GD_OVERLAY = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"


class TestInspectorTopline(unittest.TestCase):
    def test_format_land_and_sea_fields(self) -> None:
        land = format_inspector_topline("Berlin", "GER", "Germany", "")
        self.assertEqual(land["title"], "Berlin")
        self.assertIn("GER", land["owner_line"])
        self.assertTrue(land["has_region"])
        self.assertIn("Germany", land["region_line"])
        self.assertFalse(land["has_sea_zone"])
        self.assertIn("Berlin", land["plain_summary"])
        self.assertIn("GER", land["plain_summary"])
        self.assertIn("Germany", land["plain_summary"])

        sea = format_inspector_topline(
            "North Sea Approaches",
            "",
            "Atlantic Approaches",
            "North Sea",
        )
        self.assertEqual(sea["owner"], "Unowned")
        self.assertTrue(sea["has_sea_zone"])
        self.assertIn("North Sea", sea["sea_zone_line"])
        self.assertIn("North Sea", sea["plain_summary"])
        self.assertIn("⚓", sea["bbcode"])

    def test_shipped_world_full_ids_drive_topline(self) -> None:
        """Drive real shipped province + region + sea-zone JSON (not invented theater)."""
        base = {
            int(p["id"]): p
            for p in json.loads((WF / "provinces_base.json").read_text())["provinces"]
        }
        owners = json.loads((WF / "province_ownership_1936.json").read_text()).get(
            "owners"
        ) or {}
        reg = json.loads((WF / "strategic_regions.json").read_text())
        pid_to_region: dict[int, str] = {}
        for r in reg.get("regions") or []:
            rname = str(r.get("name") or "")
            for pid in r.get("province_ids") or []:
                pid_to_region[int(pid)] = rname
        sea = json.loads((WF / "sea_zone_theaters.json").read_text())
        p2z = sea.get("province_to_zone") or {}

        # Land: first owned land province with a region name
        land_pid = None
        for pid, p in base.items():
            domain = str(p.get("domain") or "").lower()
            if domain in ("sea", "strait", "lake"):
                continue
            if int(pid) not in pid_to_region:
                continue
            tag = str(owners.get(str(pid), owners.get(pid, "")) or "")
            if not tag:
                continue
            land_pid = int(pid)
            land_p = p
            land_tag = tag
            break
        self.assertIsNotNone(land_pid)
        land_top = format_inspector_topline(
            str(land_p.get("name")),
            land_tag,
            pid_to_region[land_pid],
            "",
        )
        self.assertTrue(land_top["title"])
        self.assertNotEqual(land_top["owner"], "Unowned")
        self.assertTrue(land_top["has_region"])

        # Sea: first sea-zone pid
        sea_pid_s = next(iter(p2z.keys()))
        sea_pid = int(sea_pid_s)
        sea_p = base.get(sea_pid) or {"name": "Sea"}
        sea_top = format_inspector_topline(
            str(sea_p.get("name") or "Sea"),
            str(owners.get(str(sea_pid), "") or ""),
            pid_to_region.get(sea_pid, ""),
            str(p2z[sea_pid_s]),
        )
        self.assertTrue(sea_top["has_sea_zone"])
        self.assertEqual(sea_top["sea_zone"], str(p2z[sea_pid_s]))

    def test_gd_wiring_topline(self) -> None:
        fmt = GD_FORMATTERS.read_text(encoding="utf-8")
        self.assertIn("func format_inspector_topline", fmt)
        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("func build_inspector_topline", insight)
        self.assertIn("format_inspector_topline", insight)
        renderer = GD_RENDERER.read_text(encoding="utf-8")
        self.assertIn("build_inspector_topline", renderer)
        self.assertIn("region_line", renderer)
        self.assertIn("sea_zone_line", renderer)


class TestEraInfraDensity(unittest.TestCase):
    def test_pure_profiles_sparse_stricter_than_1936(self) -> None:
        self.assertEqual(era_band_for_year(1918), 0)
        self.assertEqual(era_band_for_year(1936), 1)
        self.assertEqual(era_band_for_year(2026), 2)
        sparse = era_infra_profile_for_year(1918)
        base = era_infra_profile_for_year(1936)
        dense = era_infra_profile_for_year(2026)
        self.assertEqual(sparse["label"], "sparse_1918")
        self.assertEqual(base["label"], "standard_1936")
        self.assertTrue(profile_is_sparser(sparse, base), msg=(sparse, base))
        self.assertGreater(float(sparse["road_infra_min"]), float(base["road_infra_min"]))
        self.assertGreater(float(sparse["city_dev_min"]), float(base["city_dev_min"]))
        self.assertLess(float(dense["road_infra_min"]), float(base["road_infra_min"]))

    def test_shipped_overlay_matches_pure_and_uses_profile(self) -> None:
        src = GD_OVERLAY.read_text(encoding="utf-8")
        self.assertIn("func _get_era_band", src)
        self.assertIn("func _get_era_infra_profile", src)
        self.assertIn("func era_band_for_year", src)
        self.assertIn("func era_infra_profile_for_year", src)
        self.assertIn("sparse_1918", src)
        self.assertIn("standard_1936", src)
        self.assertIn("_get_era_infra_profile()", src)
        # Rebuild path uses profile for roads/cities
        self.assertIn("road_infra_min", src)
        self.assertIn("city_dev_min", src)
        # Parse sparse vs baseline mins from shipped GD match blocks
        m_sparse_road = re.search(
            r'"label":\s*"sparse_1918"[\s\S]*?"road_infra_min":\s*([0-9.]+)',
            src,
        )
        m_base_road = re.search(
            r'"label":\s*"standard_1936"[\s\S]*?"road_infra_min":\s*([0-9.]+)',
            src,
        )
        self.assertIsNotNone(m_sparse_road)
        self.assertIsNotNone(m_base_road)
        self.assertGreater(float(m_sparse_road.group(1)), float(m_base_road.group(1)))
        # Pure mirror stays aligned with shipped static values
        self.assertEqual(
            float(era_infra_profile_for_year(1918)["road_infra_min"]),
            float(m_sparse_road.group(1)),
        )


class TestSpecialSitePulse(unittest.TestCase):
    def test_visual_contract_distinct_states(self) -> None:
        uc = special_site_map_visual(
            completed=False, under_construction=True, damaged=False, construction_progress=0.4
        )
        self.assertEqual(uc["tint_key"], "under_construction")
        self.assertTrue(uc["pulse"])
        self.assertTrue(uc["progress_ring"])
        self.assertAlmostEqual(float(uc["ring_progress"]), 0.4, places=2)
        self.assertFalse(uc["show_damage_cracks"])

        done = special_site_map_visual(completed=True, under_construction=False, damaged=False)
        self.assertEqual(done["tint_key"], "complete")
        self.assertTrue(done["completion_pulse"])
        self.assertTrue(done["show_effect_chip"])
        self.assertFalse(done["show_damage_cracks"])

        dmg = special_site_map_visual(completed=True, under_construction=False, damaged=True)
        self.assertEqual(dmg["tint_key"], "damaged")
        self.assertTrue(dmg["show_damage_cracks"])
        self.assertFalse(dmg["completion_pulse"])
        self.assertFalse(dmg["show_effect_chip"])
        # Damaged icon distinct from complete
        self.assertEqual(site_state_icon(damaged=True), "💥")
        self.assertEqual(site_state_icon(completed=True), "✓")
        self.assertNotEqual(dmg["icon"], done["icon"])

    def test_overlay_wires_visual_contract(self) -> None:
        src = GD_OVERLAY.read_text(encoding="utf-8")
        self.assertIn("special_site_map_visual", src)
        self.assertIn("completion_pulse", src)
        self.assertIn("show_damage_cracks", src)
        fmt = GD_FORMATTERS.read_text(encoding="utf-8")
        self.assertIn("func special_site_map_visual", fmt)


if __name__ == "__main__":
    unittest.main(verbosity=2)
