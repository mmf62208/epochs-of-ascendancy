#!/usr/bin/env python3
from __future__ import annotations
import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GD = ROOT / "scripts" / "autoload" / "GameData.gd"
SL = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
SA = ROOT / "scripts" / "core" / "StreamAlphaDomain.gd"
HH = ROOT / "scripts" / "core" / "HhMultiMonthDomain.gd"
AT = ROOT / "scripts" / "core" / "AirTheaterDomain.gd"


def body(src: str, name: str) -> str:
    m = re.search(r"func %s\b.*?(?=\nfunc |\nconst |\n#region|\n#endregion|\Z)" % re.escape(name), src, re.S)
    return m.group(0) if m else ""


class TestSprintSaHhAtG0(unittest.TestCase):
    def test_domain_files(self):
        for p, name in [
            (SA, "StreamAlphaDomain"),
            (HH, "HhMultiMonthDomain"),
            (AT, "AirTheaterDomain"),
        ]:
            self.assertTrue(p.exists(), name)
            self.assertIn("class_name %s" % name, p.read_text(encoding="utf-8"))

    def test_stream_alpha_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_stream_alpha_primary_command_step_live")
        self.assertIn("StreamAlphaDomain", b)
        self.assertIn("var leaf", b)
        self.assertIn("live_api_final", b)
        # ternary "else leaf" is OK only when leaf is declared above (bug was undeclared leaf)
        self.assertIn("var live_api_final: String = live_api if not live_api.is_empty() else leaf", b)
        b2 = body(gd, "apply_stream_alpha_primary_command_live")
        self.assertIn("StreamAlphaDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_hh_multi_month_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_hh_multi_month_primary_step_live")
        self.assertIn("HhMultiMonthDomain", b)
        self.assertIn("live_api_final", b)
        self.assertNotIn("else leaf", b)
        b2 = body(gd, "apply_hh_multi_month_primary_live")
        self.assertIn("HhMultiMonthDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_air_theater_g0(self):
        gd = GD.read_text(encoding="utf-8")
        b = body(gd, "apply_air_theater_primary_command_step_live")
        self.assertIn("AirTheaterDomain", b)
        self.assertIn("live_api_final", b)
        self.assertNotIn("else leaf", b)
        b2 = body(gd, "apply_air_theater_primary_command_live")
        self.assertIn("AirTheaterDomain", b2)
        self.assertIn("majors_ok_count", b2)

    def test_scenario_markers(self):
        sl = SL.read_text(encoding="utf-8")
        self.assertIn("stream_alpha_primary_live=1", sl)
        self.assertIn("hh_multi_month_primary_live=1", sl)
        self.assertIn("air_theater_primary_live=1", sl)

    def test_no_focus_step_live_api(self):
        gd = GD.read_text(encoding="utf-8")
        for fn in (
            "apply_stream_alpha_primary_command_step_live",
            "apply_hh_multi_month_primary_step_live",
            "apply_air_theater_primary_command_step_live",
        ):
            b = body(gd, fn)
            self.assertNotIn('live_api = "apply_focus"', b)


if __name__ == "__main__":
    unittest.main()
