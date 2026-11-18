#!/usr/bin/env python3
"""Format per-step wall times for tools/eoa_full_test_gates.sh.

The gates runner appends TSV rows (name, seconds, passed) and calls this
module at the end of a run to print a slowest-first summary and write JSON
next to the run log. Existing [eoa-gates] STEP/OK/FAIL/ALL PASSED/FAILED
lines are produced by the shell script and are not rewritten here.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Mapping, Sequence, TextIO, Union

StepTiming = Dict[str, Union[str, float, bool]]


def format_seconds(seconds: float) -> str:
    return "%.3f" % float(seconds)


def format_step_time_line(name: str, seconds: float, passed: bool) -> str:
    """Body of the per-step TIME line (shell prefixes '[eoa-gates] ')."""
    flag = "true" if passed else "false"
    return "TIME %s %ss passed=%s" % (name, format_seconds(seconds), flag)


def sort_steps_slowest_first(steps: Sequence[Mapping[str, object]]) -> List[StepTiming]:
    decorated: List[tuple] = []
    for index, raw in enumerate(steps):
        name = str(raw.get("name") or "")
        seconds = float(raw.get("seconds") or 0.0)
        passed = bool(raw.get("passed"))
        decorated.append((-seconds, index, name, seconds, passed))
    decorated.sort()
    out: List[StepTiming] = []
    for _neg, _index, name, seconds, passed in decorated:
        out.append({"name": name, "seconds": seconds, "passed": passed})
    return out


def format_summary_lines(steps: Sequence[Mapping[str, object]]) -> List[str]:
    """Human summary, slowest first. Each line is a full '[eoa-gates] ...' record."""
    ordered = sort_steps_slowest_first(steps)
    lines: List[str] = ["[eoa-gates] TIMING SUMMARY (slowest first)"]
    if not ordered:
        lines.append("[eoa-gates]   (no timed steps)")
        return lines
    for row in ordered:
        flag = "pass" if row["passed"] else "fail"
        lines.append(
            "[eoa-gates]   %8ss  %s  %s"
            % (format_seconds(float(row["seconds"])), flag, row["name"])
        )
    return lines


def parse_timing_rows(text: str) -> List[StepTiming]:
    steps: List[StepTiming] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            raise ValueError("timing row needs name, seconds, passed: %r" % raw_line)
        name = parts[0]
        seconds = float(parts[1])
        passed_token = parts[2].strip().lower()
        if passed_token not in ("true", "false", "1", "0", "pass", "fail"):
            raise ValueError("unknown passed token %r in %r" % (parts[2], raw_line))
        passed = passed_token in ("true", "1", "pass")
        steps.append({"name": name, "seconds": seconds, "passed": passed})
    return steps


def timing_payload(steps: Sequence[Mapping[str, object]]) -> Dict[str, object]:
    recorded: List[StepTiming] = []
    for raw in steps:
        recorded.append(
            {
                "name": str(raw.get("name") or ""),
                "seconds": float(raw.get("seconds") or 0.0),
                "passed": bool(raw.get("passed")),
            }
        )
    ordered = sort_steps_slowest_first(recorded)
    total = 0.0
    for row in recorded:
        total += float(row["seconds"])
    return {
        "steps": recorded,
        "sorted_by_seconds_desc": ordered,
        "total_seconds": float("%.3f" % total),
        "step_count": len(recorded),
    }


def write_timing_json(path: Path, steps: Sequence[Mapping[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = timing_payload(steps)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def emit_report(
    steps: Sequence[Mapping[str, object]],
    json_out: Path,
    stream: TextIO = sys.stdout,
) -> None:
    for line in format_summary_lines(steps):
        stream.write(line + "\n")
    write_timing_json(json_out, steps)
    stream.write("[eoa-gates] TIMING JSON %s\n" % json_out)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Format eoa-gates per-step timings.")
    parser.add_argument("--rows-file", required=True, help="TSV: name<TAB>seconds<TAB>passed")
    parser.add_argument("--json-out", required=True, help="Sidecar JSON path next to the run log")
    args = parser.parse_args(list(argv) if argv is not None else None)
    rows_path = Path(args.rows_file)
    text = rows_path.read_text(encoding="utf-8") if rows_path.exists() else ""
    steps = parse_timing_rows(text)
    emit_report(steps, Path(args.json_out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
