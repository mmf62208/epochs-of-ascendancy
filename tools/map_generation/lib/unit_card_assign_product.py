"""Thin unit-card commands: halt march, withdraw battle, assign leader."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


def _gd_func_slice(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    lines = src[i:].splitlines()
    out = [lines[0]]
    for line in lines[1:]:
        if line.startswith("func "):
            break
        out.append(line)
    return "\n".join(out)


def build_unit_card_assign_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    popup = _gd_func_slice(ren, "_show_unit_detail_popup")
    execute = _gd_func_slice(ren, "_try_execute_province_attack")

    halt_ok = "Halt march" in popup and "clear_march" in popup
    wiring["halt_march"] = halt_ok
    (passes if halt_ok else fails).append("halt_march")

    wd_ok = "Withdraw" in popup and "withdraw_from_land_battle" in popup
    wiring["withdraw_battle"] = wd_ok
    (passes if wd_ok else fails).append("withdraw_battle")

    wd_vis = "Withdraw ●" in popup and "Withdrawing" in popup
    wiring["withdraw_visible_state"] = wd_vis
    (passes if wd_vis else fails).append("withdraw_visible_state")

    as_ok = "Assign" in popup and "get_available_leaders" in popup
    wiring["assign_leader"] = as_ok
    (passes if as_ok else fails).append("assign_leader")

    dock_ok = "unit_card_dock" in popup
    wiring["docked_card"] = dock_ok
    (passes if dock_ok else fails).append("docked_card")

    start_ok = "start_land_battle" in execute
    wiring["confirm_starts_battle"] = start_ok
    (passes if start_ok else fails).append("confirm_starts_battle")

    stance_ok = "Press" in popup and "Hold" in popup and "set_land_battle_stance" in popup
    wiring["press_hold"] = stance_ok
    (passes if stance_ok else fails).append("press_hold")

    # Hold click must toast Stance: Hold, not the shared next_hook (Play MIXED 138a1f8a).
    hold_toast = "Stance: Hold" in popup
    wiring["hold_distinct_toast"] = hold_toast
    (passes if hold_toast else fails).append("hold_distinct_toast")

    dock_raised = (
        "UNIT_CARD_DOCK_RESERVE" in ren
        and "_dock_unit_card_in_viewport" in popup
        and "vp.y - 252" not in popup
    )
    wiring["dock_fits_1280x740"] = dock_raised
    (passes if dock_raised else fails).append("dock_fits_1280x740")

    wd_sep = "stance_row.add_child(wd_btn)" in popup
    wiring["withdraw_not_beside_halt"] = wd_sep
    (passes if wd_sep else fails).append("withdraw_not_beside_halt")

    open_latch = popup.count("_arm_unit_card_press_consume()") >= 6
    wiring["open_fight_press_latch"] = open_latch
    (passes if open_latch else fails).append("open_fight_press_latch")

    sheet = _gd_func_slice(ren, "_show_open_fight_sheet")
    start_opened = "BtnStartBattle" in sheet and 'assault.get("opened"' in sheet
    wiring["start_battle_opened_only"] = start_opened
    (passes if start_opened else fails).append("start_battle_opened_only")

    no_insp = "show_info_panel" not in execute
    wiring["execute_no_info_panel"] = no_insp
    (passes if no_insp else fails).append("execute_no_info_panel")

    ok = len(fails) == 0 if check_wiring else halt_ok
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "wiring": wiring,
        "summary": "unit_card_assign · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "halt_withdraw_assign_start_land_battle_no_inspector",
    }


def unit_card_assign_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_card_assign_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
