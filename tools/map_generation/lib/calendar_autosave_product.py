"""Calendar autosave — month/year product cadence (AUTOSAVE-1).

Product writes rotating autosave_1..3 on game_month_advanced (default) or
game_year_advanced. The every-7-days day-advanced cadence is retired.
EOA_CALENDAR_AUTOSAVE=0 remains the hard killswitch for harnesses.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
SL_GD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"

KILLSWITCH = "EOA_CALENDAR_AUTOSAVE=0"
CADENCE_DEFAULT = "monthly"
CADENCES = ("off", "monthly", "yearly")


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


def should_calendar_autosave(cadence: str, hook: str) -> bool:
    """True when this TimeManager hook should queue a product autosave."""
    c = str(cadence or "").strip().lower()
    h = str(hook or "").strip().lower()
    if c == "off":
        return False
    if c == "monthly":
        return h == "month"
    if c == "yearly":
        return h == "year"
    return False


def build_calendar_autosave_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    if not should_calendar_autosave("off", "month") and not should_calendar_autosave("off", "year"):
        passes.append("cadence_off_quiet")
    else:
        fails.append("cadence_off_quiet")
    if should_calendar_autosave("monthly", "month") and not should_calendar_autosave("monthly", "year"):
        passes.append("cadence_monthly_month_only")
    else:
        fails.append("cadence_monthly_month_only")
    if should_calendar_autosave("yearly", "year") and not should_calendar_autosave("yearly", "month"):
        passes.append("cadence_yearly_year_only")
    else:
        fails.append("cadence_yearly_year_only")

    sl = SL_GD.read_text(encoding="utf-8") if SL_GD.is_file() else ""
    ready = extract_gd_func_body(sl, "_ready")
    if ready and "game_month_advanced" in ready and "_on_month_advanced_for_autosave" in ready:
        passes.append("sl_connects_month")
    else:
        fails.append("sl_connects_month")
    if ready and "game_year_advanced" in ready and "_on_year_advanced_for_autosave" in ready:
        passes.append("sl_connects_year")
    else:
        fails.append("sl_connects_year")
    if "func _on_month_advanced_for_autosave" in sl:
        passes.append("sl_month_hook")
    else:
        fails.append("sl_month_hook")
    year_fn = extract_gd_func_body(sl, "_on_year_advanced_for_autosave")
    if year_fn and "save_game_detailed" not in year_fn and ("_queue" in year_fn or "call_deferred" in year_fn):
        passes.append("year_hook_not_inline")
    else:
        fails.append("year_hook_not_inline")
    if "pick_rotator_slot" in sl and "autosave_1" in sl and "autosave_2" in sl and "autosave_3" in sl:
        passes.append("rotator_slots")
    else:
        fails.append("rotator_slots")
    if "EOA_CALENDAR_AUTOSAVE" in sl and KILLSWITCH.split("=")[0] in sl:
        passes.append("killswitch")
    else:
        fails.append("killswitch")
    if "LAST_PLAYED_BADGE" in sl and 'LAST PLAYED' in sl:
        passes.append("last_played_badge")
    else:
        fails.append("last_played_badge")
    if "signal save_list_changed" in sl:
        passes.append("save_list_changed")
    else:
        fails.append("save_list_changed")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "cadence_default": CADENCE_DEFAULT,
        "cadences": list(CADENCES),
        "killswitch": KILLSWITCH,
        "summary": "calendar_autosave · %s · month/year · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "month_year_autosave_rotator",
    }


def calendar_autosave_integrity() -> Dict[str, Any]:
    p = build_calendar_autosave_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
        "killswitch": p.get("killswitch"),
    }
