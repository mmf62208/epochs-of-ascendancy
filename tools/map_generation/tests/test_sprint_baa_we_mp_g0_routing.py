#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
BAA = ROOT / "scripts" / "core" / "BattleAarDomain.gd"
WE = ROOT / "scripts" / "core" / "WarEconomyDomain.gd"
MP = ROOT / "scripts" / "core" / "MapPerfMeasuredDomain.gd"


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#region|\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintBaaWeMpG0(unittest.TestCase):
    def test_domain_files(self):
        for p, name in [(BAA, "BattleAarDomain"), (WE, "WarEconomyDomain"), (MP, "MapPerfMeasuredDomain")]:
            self.assertTrue(p.exists(), name)
            self.assertIn("class_name %s" % name, p.read_text(encoding="utf-8"))

    def test_battle_aar_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_battle_aar_primary_command_step_live")
        self.assertIn("BattleAarDomain", b)
        b2 = body(gd, "apply_battle_aar_primary_command_live")
        self.assertIn("BattleAarDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_war_economy_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_war_economy_primary_command_step_live")
        self.assertIn("WarEconomyDomain", b)
        b2 = body(gd, "apply_war_economy_primary_command_live")
        self.assertIn("WarEconomyDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_map_perf_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_map_perf_measured_primary_step_live")
        self.assertIn("MapPerfMeasuredDomain", b)
        b2 = body(gd, "apply_map_perf_measured_primary_live")
        self.assertIn("MapPerfMeasuredDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_scenario_markers(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("battle_aar_primary_live=1", sl)
        self.assertIn("war_economy_primary_live=1", sl)
        self.assertIn("map_perf_measured_primary_live=1", sl)

    def test_no_focus_step_live_api(self):
        gd = GD.read_text(encoding="utf-8")
        for fn in (
            "apply_battle_aar_primary_command_step_live",
            "apply_war_economy_primary_command_step_live",
            "apply_map_perf_measured_primary_step_live",
        ):
            b = body(gd, fn)
            self.assertNotIn('live_api = "apply_focus"', b)


if __name__ == "__main__":
    unittest.main()
