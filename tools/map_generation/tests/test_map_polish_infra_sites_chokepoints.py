#!/usr/bin/env python3
"""Real output tests for map polish pure formatters (infra / sites / chokepoints).

Drives tools/map_generation/lib/map_polish_formatters.py — the pure helper contract
mirrored by scripts/map/MapPolishFormatters.gd and used by ProvinceInsight / MapRenderer /
InfrastructureOverlayLayer. Asserts concrete strings and panel state, not symbol greps.
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from map_polish_formatters import (  # noqa: E402
    COLOR_TECH,
    COLOR_WARN,
    format_chokepoint_badge,
    format_invest_panel_state,
    format_investment_status_line,
    format_overlay_effect_chip,
    format_site_effect_bits,
    format_special_site_line,
    format_special_sites_block,
    is_chokepoint_member,
    load_chokepoint_id_set,
    site_state_icon,
)

WORLD = ROOT / "data" / "provinces_world_full"
SITES = ROOT / "data" / "map" / "special_sites"
GD_FORMATTERS = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
GD_INSIGHT = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
GD_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
GD_OVERLAY = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class TestInvestmentStatusFromProjectDict(unittest.TestCase):
    """§1 — progress / cancel / sabo from get_project_status-shaped dicts."""

    def test_empty_and_inactive_yield_empty(self) -> None:
        self.assertEqual(format_investment_status_line({}), "")
        self.assertEqual(format_investment_status_line({"active": False, "progress": 50}), "")

    def test_active_progress_eta_target(self) -> None:
        st = {
            "active": True,
            "progress": 42.4,
            "eta_days": 12,
            "target_level": 5,
            "is_sabotaged": False,
            "work_per_day": 2.5,
            "modifiers": {"engineer": 0.9, "tech": 0.25},
        }
        line = format_investment_status_line(st, default_infra=4)
        self.assertIn("Infra Investment → Lv.5", line)
        self.assertIn("42%", line)
        self.assertIn("ETA 12d", line)
        self.assertIn("2.5/day", line)
        self.assertIn("Eng +0.9", line)
        self.assertIn("Tech +0.2", line)
        self.assertIn(COLOR_TECH, line)
        self.assertNotIn("under sabotage", line)
        self.assertNotIn("Cancel or clear agents", line)

    def test_sabotaged_status_warns_and_mentions_cancel(self) -> None:
        st = {
            "active": True,
            "progress": 18.0,
            "eta_days": 40,
            "target_level": 3,
            "is_sabotaged": True,
            "work_per_day": 0.4,
            "modifiers": {"sabotage": -0.7, "engineer": 0.5},
        }
        line = format_investment_status_line(st, default_infra=2)
        self.assertIn("under sabotage", line)
        self.assertIn(COLOR_WARN, line)
        self.assertIn("Sab -0.7", line)
        self.assertIn("Cancel or clear agents to recover progress rate", line)
        self.assertIn("⚠", line)

    def test_panel_state_shows_cancel_and_progress_when_active(self) -> None:
        st = {
            "active": True,
            "progress": 55.0,
            "eta_days": 8,
            "target_level": 6,
            "is_sabotaged": False,
            "modifiers": {"engineer": 1.0},
        }
        panel = format_invest_panel_state(st, cur_infra=5, cur_dev=3)
        self.assertTrue(panel["has_project"])
        self.assertTrue(panel["show_cancel"])
        self.assertTrue(panel["show_progress"])
        self.assertEqual(panel["progress_pct"], 55)
        self.assertEqual(panel["button_text"], "Project Active")
        self.assertTrue(panel["button_disabled"])
        self.assertIn("55%", panel["label"])
        self.assertIn("Lv.6", panel["label"])
        self.assertIn("Eng +1.0", panel["modifiers_label"])

    def test_panel_state_sabo_flag_and_idle_cancel_hidden(self) -> None:
        sabo = format_invest_panel_state(
            {
                "active": True,
                "progress": 10,
                "eta_days": 99,
                "target_level": 2,
                "is_sabotaged": True,
                "modifiers": {"sabotage": -0.5},
            },
            cur_infra=1,
            cur_dev=0,
        )
        self.assertTrue(sabo["sabotaged"])
        self.assertIn("Sabotage slowing progress", sabo["label"])
        self.assertIn("sabo active", sabo["modifiers_label"])
        self.assertTrue(sabo["show_cancel"])

        idle = format_invest_panel_state({}, cur_infra=4, cur_dev=2)
        self.assertFalse(idle["has_project"])
        self.assertFalse(idle["show_cancel"])
        self.assertFalse(idle["show_progress"])
        self.assertIn("Invest to raise", idle["label"])
        self.assertEqual(idle["button_text"], "Invest in Infrastructure")


class TestSpecialSiteEffectsFromDefs(unittest.TestCase):
    """§2 — site effect bits from shipped JSON defs + construction/damage state."""

    def test_port_tier_2_shipped_def_effects(self) -> None:
        path = SITES / "port_tier_2.json"
        self.assertTrue(path.is_file(), "shipped port_tier_2 definition required")
        defn = _load_json(path)
        effects = defn.get("effects", {})
        bits = format_site_effect_bits(0.0, 0.0, effects)
        # Real def values: supply_throughput_bonus 25, trade_capacity 40, naval_repair_bonus 15
        self.assertIn("+25 supply", bits)
        self.assertIn("+40 trade", bits)
        self.assertIn("+15 naval repair", bits)
        line = format_special_site_line(
            defn["id"],
            defn.get("name", ""),
            int(defn.get("tier", 1)),
            site_state_icon(completed=True),
            bits,
            compact=True,
        )
        self.assertIn("Developed Port", line)
        self.assertIn("+25 supply", line)
        self.assertIn("✓", line)
        block = format_special_sites_block([line], compact=True)
        self.assertTrue(block.startswith("[color=#6eb5ff]Sites:[/color]"))
        self.assertIn("Developed Port", block)

    def test_under_construction_and_damage_bits(self) -> None:
        bits = format_site_effect_bits(
            supply_bonus=10.0,
            trade_capacity=0.0,
            effects={},
            construction_progress=0.35,
            damage_level=2,
        )
        self.assertIn("+10 supply", bits)
        self.assertIn("building 35%", bits)
        self.assertIn("dmg 2", bits)
        self.assertEqual(site_state_icon(under_construction=True), "🚧")
        self.assertEqual(site_state_icon(damaged=True), "💥")

    def test_overlay_effect_chip_matches_map_draw_contract(self) -> None:
        self.assertEqual(format_overlay_effect_chip(25, 40), "+25S +40T")
        self.assertEqual(format_overlay_effect_chip(0, 0), "")
        # Fixture: airfield_tier_1 if present
        af = SITES / "airfield_tier_1.json"
        if af.is_file():
            effects = _load_json(af).get("effects", {})
            supply = float(effects.get("supply_throughput_bonus", 0) or 0)
            trade = float(effects.get("trade_capacity", 0) or 0)
            bits = format_site_effect_bits(0, 0, effects)
            chip = format_overlay_effect_chip(supply, trade)
            if supply > 0 or trade > 0:
                self.assertTrue(bits or chip)
            # Chip only uses supply/trade — must be consistent with bits when those keys exist
            if supply > 0:
                self.assertTrue(any("supply" in b for b in bits))
                self.assertIn("+%dS" % int(supply), chip)

    def test_multiple_shipped_defs_produce_nonempty_effects(self) -> None:
        files = list(SITES.glob("*.json"))
        self.assertGreaterEqual(len(files), 10)
        with_bits = 0
        for path in files:
            defn = _load_json(path)
            effects = defn.get("effects") or {}
            if not isinstance(effects, dict) or not effects:
                continue
            bits = format_site_effect_bits(0.0, 0.0, effects)
            if bits:
                with_bits += 1
                line = format_special_site_line(
                    str(defn["id"]),
                    str(defn.get("name", defn["id"])),
                    int(defn.get("tier", 1)),
                    "✓",
                    bits,
                    compact=False,
                    description=str(defn.get("description", "")),
                )
                self.assertIn(str(defn.get("name", defn["id"])), line)
        self.assertGreaterEqual(with_bits, 5, "need real effect readouts from shipped defs")


class TestNavalChokepointMembership(unittest.TestCase):
    """§3 — membership from live naval_chokepoints.json IDs (not hardcoded stubs)."""

    def test_world_full_chokepoint_set(self) -> None:
        base = _load_json(WORLD / "provinces_base.json")
        provs = base.get("provinces", base) if isinstance(base, dict) else base
        ids = {int(p["id"]) for p in provs}
        payload = _load_json(WORLD / "naval_chokepoints.json")
        choke_ids = load_chokepoint_id_set(payload)
        self.assertGreaterEqual(len(choke_ids), 10)
        for pid in choke_ids:
            self.assertIn(pid, ids, "chokepoint id must exist on world board")
            self.assertTrue(is_chokepoint_member(pid, choke_ids))
        # Non-member
        self.assertFalse(is_chokepoint_member(999999, choke_ids))
        # Badge format + contest control line (controlled / contested)
        badge = format_chokepoint_badge(1.18)
        self.assertIn("Naval chokepoint", badge)
        self.assertIn("×1.18", badge)
        badge_ctrl = format_chokepoint_badge(1.18, "GER", "GER")
        self.assertIn("controlled by GER", badge_ctrl)
        badge_occ = format_chokepoint_badge(1.2, "GER", "FRA")
        self.assertIn("contested", badge_occ.lower())
        self.assertIn("GER", badge_occ)
        self.assertIn("FRA", badge_occ)

        # Named straits present via live base names
        names = {int(p["id"]): str(p.get("name", "")).lower() for p in provs}
        joined = " ".join(names[p] for p in choke_ids)
        for token in ("gibraltar", "suez", "malacca", "danish", "panama"):
            self.assertIn(token, joined, "strategic set missing %s" % token)


class TestShippedWiringUsesFormatters(unittest.TestCase):
    """Structural: runtime paths call MapPolishFormatters (not empty stubs)."""

    def test_gd_mirrors_and_call_sites(self) -> None:
        self.assertTrue(GD_FORMATTERS.is_file())
        fmt = GD_FORMATTERS.read_text(encoding="utf-8")
        for name in (
            "format_investment_status_line",
            "format_invest_panel_state",
            "format_site_effect_bits",
            "format_overlay_effect_chip",
            "format_chokepoint_badge",
            "is_chokepoint_member",
        ):
            self.assertIn("func %s" % name, fmt)

        insight = GD_INSIGHT.read_text(encoding="utf-8")
        self.assertIn("preload(\"res://scripts/map/MapPolishFormatters.gd\")", insight)
        self.assertIn("format_investment_status_line", insight)
        self.assertIn("format_site_effect_bits", insight)
        self.assertIn("format_chokepoint_badge", insight)

        renderer = GD_RENDERER.read_text(encoding="utf-8")
        self.assertIn("preload(\"res://scripts/map/MapPolishFormatters.gd\")", renderer)
        self.assertIn("format_invest_panel_state", renderer)
        self.assertIn("show_cancel", renderer)

        overlay = GD_OVERLAY.read_text(encoding="utf-8")
        self.assertIn("preload(\"res://scripts/map/MapPolishFormatters.gd\")", overlay)
        self.assertIn("format_overlay_effect_chip", overlay)


if __name__ == "__main__":
    unittest.main(verbosity=2)
