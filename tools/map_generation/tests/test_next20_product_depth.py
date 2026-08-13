#!/usr/bin/env python3
"""Gates: combat UI product, fleet AI autonomy, agent AI (×2), GIS NE pilot ≥528."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from product_depth import (  # noqa: E402
    multi_phase_combat_ui_product,
    fleet_autonomy_plan,
    agent_ai_board,
    agent_ai_decision_quality,
    product_depth_integrity,
    close_product_depth_loop,
)

WF = ROOT / "data" / "provinces_world_full"
GD_MM = ROOT / "scripts" / "map" / "MapManager.gd"
GD_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
GD_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
GD_FMT = ROOT / "scripts" / "map" / "MapPolishFormatters.gd"
SUMMARY = ROOT / "Project_State_Summary.md"
TODO = ROOT / "TODO.md"
ROADMAP = ROOT / "Next_30_Days_Roadmap.md"
CI = ROOT / "tools" / "run_map_ci.sh"

CLEAR = {"precip_intensity": 0.0, "visibility": 1.0, "ground_state": "dry"}
FOUL = {"precip_intensity": 0.9, "visibility": 0.2, "ground_state": "mud", "wind": 0.85}


class TestGisNePilot(unittest.TestCase):
    def test_stamped_gt_480(self) -> None:
        geom = load_geometry_payload(WF / "provinces_geometry.json")
        self.assertEqual(len(geom["provinces"]), 2665)
        stamped = sum(1 for p in geom["provinces"] if (p.get("meta") or {}).get("gis_pilot"))
        self.assertGreaterEqual(stamped, 528)
        self.assertGreater(stamped, 480)


class TestCombatUiProduct(unittest.TestCase):
    def test_ordered_phases_and_weather(self) -> None:
        c = multi_phase_combat_ui_product(weather=CLEAR)
        f = multi_phase_combat_ui_product(weather=FOUL)
        self.assertFalse(c.get("empty"))
        self.assertEqual(int(c.get("phase_count", 0)), 3)
        phases = [r["phase"] for r in (c.get("phase_rows") or [])]
        self.assertEqual(phases, ["approach", "engage", "disengage"])
        self.assertIn("ribbon", c)
        self.assertTrue(any(a.get("action_id") == "apply_assault" for a in (c.get("actions") or [])))
        self.assertNotAlmostEqual(float(c["score"]), float(f["score"]), places=3)
        # Each phase row has win_chance
        for row in c["phase_rows"]:
            self.assertIn("win_chance", row)
            self.assertIn("label", row)


class TestFleetAutonomy(unittest.TestCase):
    def test_plan_apply_and_fuel_degrade(self) -> None:
        empty = fleet_autonomy_plan([])
        self.assertTrue(empty.get("empty"))
        self.assertFalse(empty.get("apply_ready", True))

        ok = fleet_autonomy_plan([1, 2, 3], fuel_level=0.75, basing_level="port")
        self.assertFalse(ok.get("empty"))
        self.assertTrue(ok.get("apply_ready"))
        self.assertTrue(any(a.get("action_id") for a in (ok.get("actions") or [])))

        low = fleet_autonomy_plan([1, 2, 3], fuel_level=0.15)
        self.assertLess(float(low["score"]), float(ok["score"]))
        self.assertFalse(low.get("apply_ready"))


class TestAgentAi(unittest.TestCase):
    def test_empty_signal_and_board(self) -> None:
        self.assertTrue(agent_ai_board({}).get("empty"))
        self.assertTrue(agent_ai_board({"active": False}).get("empty"))
        board = agent_ai_board(
            {
                "active": True,
                "action_class": "sabotage",
                "influence": 0.65,
                "province_id": 9,
            }
        )
        self.assertFalse(board.get("empty"))
        self.assertTrue(board.get("best_mission"))
        aids = {a.get("action_id") for a in (board.get("actions") or [])}
        self.assertIn("apply_agent_dispatch", aids)
        self.assertIn("apply_counterplay", aids)

    def test_quality_affinity_pass2(self) -> None:
        empty_q = agent_ai_decision_quality([])
        self.assertTrue(empty_q.get("empty"))
        q = agent_ai_decision_quality(
            [
                {
                    "active": True,
                    "action_class": "sabotage",
                    "influence": 0.7,
                    "province_id": 1,
                },
                {
                    "active": True,
                    "action_class": "economic_pressure",
                    "influence": 0.55,
                    "province_id": 2,
                },
            ]
        )
        self.assertFalse(q.get("empty"))
        self.assertGreaterEqual(float(q.get("affinity", 0)), 0.5)
        by = {d["action_class"]: d["best_mission"] for d in (q.get("decisions") or [])}
        self.assertIn("sabotage", by)
        self.assertIn("economic_pressure", by)
        # Not a single hard-coded mission for all classes
        self.assertNotEqual(by.get("sabotage"), by.get("economic_pressure"))


class TestCloseAndIntegrity(unittest.TestCase):
    def test_loop_and_integrity(self) -> None:
        gate = product_depth_integrity()
        self.assertTrue(gate.get("ok"), msg=gate.get("summary"))
        loop = close_product_depth_loop()
        self.assertFalse(loop.get("empty"))
        self.assertGreater(float(loop.get("weather_score_shift", 0)), 0.01)
        self.assertTrue(loop["agent_empty"].get("empty"))


class TestLiveWiring(unittest.TestCase):
    def test_gd_surfaces_and_docs(self) -> None:
        mm = GD_MM.read_text(encoding="utf-8")
        self.assertIn("func multi_phase_combat_ui_for_province", mm)
        self.assertIn("phase_rows", mm)
        self.assertIn("func fleet_autonomy_tick_for_tag", mm)
        self.assertIn("func agent_ai_board_for_signal", mm)

        gd = GD_GD.read_text(encoding="utf-8")
        self.assertIn("func format_multi_phase_combat_ui_plain", gd)
        self.assertIn("func apply_fleet_autonomy_tick", gd)
        self.assertIn("func format_agent_ai_board_plain", gd)
        self.assertIn("func format_agent_ai_quality_plain", gd)
        self.assertIn("fleet_autonomy", gd)
        self.assertIn("apply_agent_dispatch", gd)
        self.assertIn("apply_assault", gd)

        panel = GD_PANEL.read_text(encoding="utf-8")
        self.assertIn("phase_rows", panel)
        self.assertIn("fleet_autonomy", panel)
        self.assertIn("Agent AI", panel)
        self.assertIn("apply_assault", panel)

        fmt = GD_FMT.read_text(encoding="utf-8")
        self.assertIn("func multi_phase_combat_ui_product", fmt)
        self.assertIn("func fleet_autonomy_plan", fmt)
        self.assertIn("func agent_ai_board", fmt)
        self.assertIn("func agent_ai_decision_quality", fmt)

        ci = CI.read_text(encoding="utf-8")
        self.assertIn("test_next20_product_depth.py", ci)

        todo = TODO.read_text(encoding="utf-8").lower()
        summary = SUMMARY.read_text(encoding="utf-8").lower()
        roadmap = ROADMAP.read_text(encoding="utf-8").lower()
        todo_txt = TODO.read_text(encoding="utf-8")
        summary_txt = SUMMARY.read_text(encoding="utf-8")
        self.assertTrue(any(n in todo_txt for n in ("528", "564")))
        self.assertTrue(any(n in summary_txt for n in ("528", "564")))
        for label in (
            "combat ui",
            "fleet ai autonomy",
            "agent ai",
            "gis",
        ):
            self.assertIn(label, todo, msg="TODO: %s" % label)
            self.assertIn(label, summary, msg="Summary: %s" % label)
            self.assertIn(label, roadmap, msg="Roadmap: %s" % label)


if __name__ == "__main__":
    unittest.main(verbosity=2)
