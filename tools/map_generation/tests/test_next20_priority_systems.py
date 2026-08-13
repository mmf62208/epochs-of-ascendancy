#!/usr/bin/env python3
"""Gates: priorities P1–P9 depth pilots — order UX, combat UI, fleet AI, HH, agents, industry, saves, GPU, GIS×480."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from priority_systems import (  # noqa: E402
    order_panel_ux_model,
    multi_phase_combat_ui,
    fleet_ai_ops_package,
    hh_agenda_screen_package,
    agent_campaign_depth,
    industry_economy_depth,
    save_slot_browser_package,
    gpu_pan_zoom_profile,
    priority_integrity_gate,
    close_priority_systems_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_TIB = ROOT / "scripts" / "ui" / "TopInfoBar.gd"
GD_SL = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"

CLEAR = {"precip_intensity": 0.0, "visibility": 1.0, "ground_state": "dry"}
FOUL = {"precip_intensity": 0.9, "visibility": 0.2, "ground_state": "mud", "wind": 0.85}


class TestGis480(unittest.TestCase):
    def test_stamped_gt_408(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 480)
        self.assertGreater(stamped, 408)


class TestPrioritySystems(unittest.TestCase):
    def test_all_priorities_weather_empty(self) -> None:
        # P1 order UX
        empty_ux = order_panel_ux_model([], -1, CLEAR)
        self.assertTrue(empty_ux.get("empty"))
        ux = order_panel_ux_model(
            [5, 6, 7],
            6,
            CLEAR,
            [{"class": "sabotage"}],
            {"action_id": "execute_one", "ok": True},
            {6: "Berlin"},
        )
        self.assertFalse(ux.get("empty"))
        self.assertEqual(int(ux.get("selected_province_id")), 6)
        self.assertEqual(len(ux.get("options") or []), 3)
        self.assertIn("Berlin", str((ux.get("options") or [{}])[1].get("label", "")))
        self.assertIn("Last:", ux.get("plain", ""))
        aids = {str(a.get("action_id")) for a in (ux.get("actions") or []) if isinstance(a, dict)}
        self.assertIn("apply_hh_commit", aids)
        self.assertIn("apply_agent_dispatch", aids)

        # P2 combat UI
        c_clear = multi_phase_combat_ui(weather=CLEAR)
        c_foul = multi_phase_combat_ui(weather=FOUL)
        self.assertFalse(c_clear.get("empty"))
        self.assertIn("ribbon", c_clear)
        self.assertIn("actions", c_clear)
        self.assertNotAlmostEqual(float(c_clear["score"]), float(c_foul["score"]), places=3)

        # P3 fleet AI
        fleet = fleet_ai_ops_package([1, 2, 3], fuel_level=0.7)
        self.assertFalse(fleet.get("empty"))
        self.assertLessEqual(float(fleet["score"]), 1.01)
        self.assertGreaterEqual(len(fleet.get("actions") or []), 1)

        # P5 HH empty trail
        self.assertTrue(hh_agenda_screen_package([]).get("empty"))
        hh = hh_agenda_screen_package([{"class": "sabotage", "influence": 0.55}])
        self.assertFalse(hh.get("empty"))
        self.assertIn("apply_hh_commit", {a.get("action_id") for a in (hh.get("actions") or [])})

        # P6 agents
        agent = agent_campaign_depth()
        self.assertFalse(agent.get("empty"))
        self.assertIn(
            "apply_agent_dispatch",
            {a.get("action_id") for a in (agent.get("actions") or [])},
        )

        # P7 industry weather
        ind_c = industry_economy_depth(weather=CLEAR)
        ind_f = industry_economy_depth(weather=FOUL)
        self.assertTrue(ind_c.get("sole_mult"))
        self.assertNotAlmostEqual(float(ind_c["score"]), float(ind_f["score"]), places=3)
        self.assertIn(
            "apply_production",
            {a.get("action_id") for a in (ind_c.get("actions") or [])},
        )

        # P8 saves
        saves = save_slot_browser_package(
            [{"slot": "autosave", "metadata": {"scenario_id": "world_full"}}]
        )
        self.assertFalse(saves.get("empty"))
        self.assertGreaterEqual(int(saves.get("count", 0)), 3)
        self.assertGreaterEqual(int(saves.get("occupied_count", 0)), 1)
        self.assertTrue(
            any(str(a.get("action_id", "")).startswith("save_slot:") for a in (saves.get("actions") or []))
        )

        # P9 GPU advisory
        gpu = gpu_pan_zoom_profile(zoom=0.4)
        self.assertFalse(gpu.get("empty"))
        self.assertTrue(gpu.get("deferred_hard_gate"))

        gate = priority_integrity_gate(priority_mult=1.12)
        self.assertTrue(gate.get("ok"), msg=gate.get("summary"))

        loop = close_priority_systems_loop(
            [10, 20, 30], CLEAR, [{"class": "economic_pressure"}]
        )
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)


class TestLiveWiring(unittest.TestCase):
    def test_gd_priority_surfaces_and_panel(self) -> None:
        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("class_name OrderCommandPanel", panel)
        self.assertIn("_province_option", panel)
        self.assertIn("_last_result", panel)
        self.assertIn("_on_province_selected", panel)
        self.assertIn("_on_map_province_selected", panel)
        self.assertIn("_province_label", panel)
        self.assertTrue(
            "Multi-phase combat" in panel or "multi_phase_combat" in panel,
            msg="panel must surface multi-phase combat",
        )
        self.assertTrue(
            "Fleet AI" in panel or "fleet_autonomy" in panel,
            msg="panel must surface fleet AI/autonomy",
        )
        self.assertIn("HH agenda", panel)
        self.assertTrue(
            "Agent AI" in panel or "Agent campaign" in panel or "apply_agent_dispatch" in panel,
            msg="panel must surface agent AI",
        )
        self.assertIn("Industry / economy", panel)
        self.assertIn("Save slots", panel)
        self.assertIn("GPU / pan-zoom", panel)
        # Also require GIS floor soft label somewhere in docs
        _todo_gis = TODO.read_text(encoding="utf-8")
        self.assertTrue(any(n in _todo_gis for n in ("480", "528", "564")))
        self.assertIn("apply_order_panel_action", panel)
        self.assertIn("save_slot:", panel)
        self.assertIn("load_slot:", panel)
        self.assertIn("apply_hh_commit", panel)
        self.assertIn("apply_agent_dispatch", panel)

        tib = GD_TIB.read_text(encoding="utf-8")
        self.assertIn("_on_orders_pressed", tib)
        self.assertIn("OrderCommandPanel", tib)

        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func fleet_ai_ops_for_tag", mm)
        self.assertIn("func industry_economy_depth_for_province", mm)
        self.assertIn("func gpu_pan_zoom_profile_live", mm)
        self.assertIn("func collect_live_theater_province_ids", mm)
        self.assertIn("apply_hh_commit", mm)
        self.assertIn("apply_agent_dispatch", mm)
        self.assertIn("apply_supply", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_multi_phase_combat_ui_plain", gd)
        self.assertIn("func format_hh_agenda_screen_package_plain", gd)
        self.assertRegex(
            gd,
            r"func format_hh_agenda_screen_package_plain[\s\S]{0,120}if trail\.is_empty\(\):\s*\n\s*return \"\"",
        )
        self.assertIn("func format_agent_campaign_depth_plain", gd)
        self.assertIn("func format_save_slot_browser_plain", gd)
        self.assertIn("func format_gpu_pan_zoom_profile_plain", gd)
        self.assertIn("list_slots_for_ui", gd)
        self.assertIn("apply_hh_commit", gd)
        self.assertIn("apply_agent_dispatch", gd)
        self.assertIn("save_slot:", gd)
        self.assertIn("load_slot:", gd)
        self.assertIn("apply_supply_route_mutation", gd)

        sl = GD_SL.read_text(encoding="utf-8")
        self.assertIn("func list_slots_for_ui", sl)
        self.assertIn("func save_game_detailed", sl)
        self.assertIn("func load_game_detailed", sl)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func estimate_multi_phase_combat", fmt)
        self.assertIn("func format_combat_phase_ribbon_plain", fmt)

        todo = TODO.read_text(encoding="utf-8")
        summary = SUMMARY.read_text(encoding="utf-8")
        roadmap = ROADMAP.read_text(encoding="utf-8")
        self.assertTrue(any(n in todo for n in ("480", "528", "564")))
        self.assertTrue(any(n in summary for n in ("480", "528", "564")))
        for label in (
            "order panel ux",
            "multi-phase combat ui",
            "fleet ai ops",
            "hh agenda screen",
            "agent campaign depth",
            "industry economy",
            "save slot browser",
            "gpu pan/zoom profile",
        ):
            self.assertIn(label, todo.lower(), msg="TODO must name: %s" % label)
            self.assertIn(label, summary.lower(), msg="Summary must name: %s" % label)
            self.assertIn(label, roadmap.lower(), msg="Roadmap must name: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
