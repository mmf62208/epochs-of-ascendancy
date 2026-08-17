"""Calendar autosave — every N days so a 20–60d 1936 session can resume.

Year-boundary autosave never fires before Jan 1937. This product is the
7-day contract; SaveLoadManager still keeps year + quit autosaves.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
SL_GD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"

INTERVAL_DAYS = 7
KILLSWITCH = "EOA_CALENDAR_AUTOSAVE=0"


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


def should_calendar_autosave(days_elapsed: int, interval: int = INTERVAL_DAYS) -> bool:
    day = int(days_elapsed)
    step = max(1, int(interval))
    if day <= 0:
        return False
    return day % step == 0


def next_autosave_day(days_elapsed: int, interval: int = INTERVAL_DAYS) -> int:
    day = max(0, int(days_elapsed))
    step = max(1, int(interval))
    return day + (step - (day % step))


def build_calendar_autosave_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    if not should_calendar_autosave(0) and not should_calendar_autosave(3):
        passes.append("skips_early_days")
    else:
        fails.append("skips_early_days")
    if should_calendar_autosave(7) and should_calendar_autosave(14) and should_calendar_autosave(21):
        passes.append("fires_every_seven")
    else:
        fails.append("fires_every_seven")
    if not should_calendar_autosave(8) and not should_calendar_autosave(20):
        passes.append("off_days_quiet")
    else:
        fails.append("off_days_quiet")
    if next_autosave_day(0) == 7 and next_autosave_day(7) == 14:
        passes.append("next_day_math")
    else:
        fails.append("next_day_math")

    sl = SL_GD.read_text(encoding="utf-8") if SL_GD.is_file() else ""
    if "func _on_day_advanced_for_autosave" in sl:
        passes.append("sl_day_hook")
    else:
        fails.append("sl_day_hook")
    ready = extract_gd_func_body(sl, "_ready")
    if ready and "game_day_advanced" in ready and "_on_day_advanced_for_autosave" in ready:
        passes.append("sl_connects_day")
    else:
        fails.append("sl_connects_day")
    day_fn = extract_gd_func_body(sl, "_on_day_advanced_for_autosave")
    if day_fn and "save_game_detailed" in day_fn and "autosave" in day_fn:
        passes.append("sl_writes_autosave")
    else:
        fails.append("sl_writes_autosave")
    if day_fn and "show_toast" in day_fn and "Autosaved" in day_fn:
        passes.append("sl_toast")
    else:
        fails.append("sl_toast")
    if "EOA_CALENDAR_AUTOSAVE" in sl:
        passes.append("killswitch")
    else:
        fails.append("killswitch")
    # Year + quit still exist.
    if "func _on_year_advanced_for_autosave" in sl and "NOTIFICATION_WM_CLOSE_REQUEST" in sl:
        passes.append("year_and_quit_kept")
    else:
        fails.append("year_and_quit_kept")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "interval_days": INTERVAL_DAYS,
        "killswitch": KILLSWITCH,
        "summary": "calendar_autosave · %s · every %dd · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", INTERVAL_DAYS, len(passes), len(fails)),
        "policy": "seven_day_autosave_1936_session",
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
