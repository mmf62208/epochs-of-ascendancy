"""Out-of-combat strength trickle — battered divisions recover over days.

Org/rdy/plan already recover in TimeManager._tick_out_of_combat_recovery.
Without a strength drip, 20–60d fights leave units permanently wrecked.
In combat: no replacements. At full strength: no-op.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
TM_GD = ROOT / "scripts" / "autoload" / "TimeManager.gd"

STRENGTH_PER_DAY = 0.03
STRENGTH_MAX = 1.0


def extract_gd_func_body(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    lines = src[i:].splitlines()
    out = [lines[0]]
    for line in lines[1:]:
        if line.startswith("func ") or line.startswith("static func "):
            break
        out.append(line)
    return "\n".join(out)


def strength_delta(*, in_combat: bool, strength: float) -> float:
    if bool(in_combat):
        return 0.0
    cur = max(0.0, float(strength))
    if cur >= STRENGTH_MAX:
        return 0.0
    return min(STRENGTH_PER_DAY, STRENGTH_MAX - cur)


def apply_strength_tick(*, in_combat: bool, strength: float) -> float:
    return min(STRENGTH_MAX, max(0.0, float(strength) + strength_delta(
        in_combat=in_combat, strength=strength
    )))


def build_unit_recovery_replenish_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    if strength_delta(in_combat=True, strength=0.4) == 0.0:
        passes.append("combat_no_replenish")
    else:
        fails.append("combat_no_replenish")
    if abs(strength_delta(in_combat=False, strength=0.40) - STRENGTH_PER_DAY) < 1e-9:
        passes.append("ooC_trickle")
    else:
        fails.append("ooC_trickle")
    if strength_delta(in_combat=False, strength=1.0) == 0.0:
        passes.append("full_noop")
    else:
        fails.append("full_noop")
    near = apply_strength_tick(in_combat=False, strength=0.985)
    if abs(near - 1.0) < 1e-9:
        passes.append("clamps_to_one")
    else:
        fails.append("clamps_to_one")
    days = 0
    s = 0.40
    while s < 1.0 - 1e-9 and days < 40:
        s = apply_strength_tick(in_combat=False, strength=s)
        days += 1
    if 15 <= days <= 25:
        passes.append("weeks_not_hours")
    else:
        fails.append("weeks_not_hours")

    tm = TM_GD.read_text(encoding="utf-8") if TM_GD.is_file() else ""
    rec = extract_gd_func_body(tm, "_tick_out_of_combat_recovery")
    if rec and "strength" in rec and "is_in_combat" in rec:
        passes.append("tm_strength_tick")
    else:
        fails.append("tm_strength_tick")
    flush = extract_gd_func_body(tm, "_flush_sim_events")
    if flush and "_tick_out_of_combat_recovery" in flush:
        passes.append("tm_flush_calls_recovery")
    else:
        fails.append("tm_flush_calls_recovery")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "strength_per_day": STRENGTH_PER_DAY,
        "summary": "unit_recovery_replenish · %s · +%.2f/day ooc · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", STRENGTH_PER_DAY, len(passes), len(fails)),
        "policy": "out_of_combat_strength_trickle",
    }


def unit_recovery_replenish_integrity() -> Dict[str, Any]:
    p = build_unit_recovery_replenish_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
