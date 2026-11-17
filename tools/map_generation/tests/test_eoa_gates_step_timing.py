#!/usr/bin/env python3
"""Unit tests for eoa-gates per-step timing / summary formatting."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))

from eoa_gates_step_timing import (  # noqa: E402
    emit_report,
    format_seconds,
    format_step_time_line,
    format_summary_lines,
    parse_timing_rows,
    sort_steps_slowest_first,
    timing_payload,
    write_timing_json,
)


class TestEoaGatesStepTiming(unittest.TestCase):
    def test_step_time_line_pass_and_fail(self) -> None:
        self.assertEqual(
            format_step_time_line("unit_board_play_path", 110.029, True),
            "TIME unit_board_play_path 110.029s passed=true",
        )
        self.assertEqual(
            format_step_time_line("headless_tutorial1", 12.4, False),
            "TIME headless_tutorial1 12.400s passed=false",
        )
        line = format_step_time_line("headless_orders_perf1", 70.0, False)
        self.assertNotIn("FAIL", line)
        self.assertNotIn("[eoa-gates] FAIL", line)

    def test_summary_sorted_slowest_first(self) -> None:
        steps = [
            {"name": "map_qc", "seconds": 1.5, "passed": True},
            {"name": "headless_orders_perf1", "seconds": 70.25, "passed": True},
            {"name": "unit_board_play_path", "seconds": 110.029, "passed": False},
            {"name": "air_physics_p1", "seconds": 0.002, "passed": True},
        ]
        lines = format_summary_lines(steps)
        self.assertEqual(lines[0], "[eoa-gates] TIMING SUMMARY (slowest first)")
        self.assertEqual(
            lines[1],
            "[eoa-gates]    110.029s  fail  unit_board_play_path",
        )
        self.assertEqual(
            lines[2],
            "[eoa-gates]     70.250s  pass  headless_orders_perf1",
        )
        self.assertEqual(lines[3], "[eoa-gates]      1.500s  pass  map_qc")
        self.assertEqual(lines[4], "[eoa-gates]      0.002s  pass  air_physics_p1")
        self.assertEqual(len(lines), 5)
        joined = "\n".join(lines)
        self.assertNotIn("[eoa-gates] FAIL", joined)
        self.assertNotIn("ALL PASSED (quick)", joined)
        self.assertNotIn("FAILED (quick)", joined)

    def test_empty_summary(self) -> None:
        lines = format_summary_lines([])
        self.assertEqual(
            lines,
            [
                "[eoa-gates] TIMING SUMMARY (slowest first)",
                "[eoa-gates]   (no timed steps)",
            ],
        )

    def test_parse_rows_and_json_sidecar(self) -> None:
        text = "\n".join(
            [
                "unit_board_play_path\t110.029\ttrue",
                "headless_garrison1\t45.5\tpass",
                "headless_tutorial1\t12\tfalse",
                "",
                "# comment",
            ]
        )
        steps = parse_timing_rows(text)
        self.assertEqual(len(steps), 3)
        self.assertEqual(steps[0]["name"], "unit_board_play_path")
        self.assertAlmostEqual(float(steps[0]["seconds"]), 110.029)
        self.assertIs(steps[0]["passed"], True)
        self.assertIs(steps[1]["passed"], True)
        self.assertIs(steps[2]["passed"], False)

        ordered = sort_steps_slowest_first(steps)
        self.assertEqual(
            [str(row["name"]) for row in ordered],
            ["unit_board_play_path", "headless_garrison1", "headless_tutorial1"],
        )

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "eoa-gates-step-timings.json"
            write_timing_json(path, steps)
            payload = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(payload["step_count"], 3)
        self.assertAlmostEqual(payload["total_seconds"], 167.529)
        self.assertEqual(payload["steps"][0]["name"], "unit_board_play_path")
        self.assertEqual(payload["sorted_by_seconds_desc"][0]["name"], "unit_board_play_path")
        self.assertFalse(payload["sorted_by_seconds_desc"][2]["passed"])

    def test_emit_report_writes_json_and_summary(self) -> None:
        steps = timing_payload(
            [{"name": "map_qc", "seconds": 2.0, "passed": True}]
        )["steps"]
        self.assertEqual(format_seconds(2), "2.000")
        with tempfile.TemporaryDirectory() as tmp:
            json_path = Path(tmp) / "run" / "eoa-gates-step-timings.json"
            stream_path = Path(tmp) / "stdout.txt"
            with stream_path.open("w", encoding="utf-8") as stream:
                emit_report(steps, json_path, stream=stream)
            printed = stream_path.read_text(encoding="utf-8")
            self.assertTrue(json_path.is_file())
            data = json.loads(json_path.read_text(encoding="utf-8"))
        self.assertIn("[eoa-gates] TIMING SUMMARY (slowest first)", printed)
        self.assertIn("map_qc", printed)
        self.assertIn("[eoa-gates] TIMING JSON ", printed)
        self.assertEqual(data["step_count"], 1)
        self.assertNotIn("[eoa-gates] FAIL", printed)


if __name__ == "__main__":
    unittest.main()
