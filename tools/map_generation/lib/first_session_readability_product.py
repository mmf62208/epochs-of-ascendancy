"""First-session readability after Begin (GER 1936).

Pass-through tip, Fill%/TOE on the selected land chip and the unit card,
and empty-land clicks that must not open a distant unit card.
The 340 chrome-spill function stays; only the open is gated to the hit disk.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
TEST_RUNNER = ROOT / "scripts" / "core" / "TestRunner.gd"

TIP_TEXT = "Select a unit, then March or Open card."


def _gd_func_slice(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    lines = src[i:].splitlines()
    out = [lines[0]]
    for line in lines[1:]:
        if line.startswith("func ") or line.startswith("static func ") or line.startswith("const "):
            break
        out.append(line)
    return "\n".join(out)


def _fill_label_block(popup: str) -> str:
    i = popup.find("fill_lbl")
    if i < 0:
        return ""
    j = popup.find("var body :=", i)
    if j < 0:
        return popup[i:]
    return popup[i:j]


def build_first_session_readability_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    runner = TEST_RUNNER.read_text(encoding="utf-8") if TEST_RUNNER.is_file() else ""

    show_fn = _gd_func_slice(ren, "show_first_session_action_tip")
    dismiss_fn = _gd_func_slice(ren, "dismiss_first_session_action_tip")
    arm_fn = _gd_func_slice(ren, "_arm_first_session_tip_dismiss_swallow")
    block_fn = _gd_func_slice(ren, "_first_session_tip_dismiss_blocks_map_pick")
    free_fn = _gd_func_slice(ren, "_free_first_session_tip_strip")
    chip_fn = _gd_func_slice(ren, "_try_open_land_chip_from_input")
    unhandled_fn = _gd_func_slice(ren, "_unhandled_input")
    input_fn = _gd_func_slice(ren, "_input")
    toast_fn = _gd_func_slice(runner, "_toast_first_session_onboarding")
    tip_ok = (
        TIP_TEXT in ren
        and "FirstSessionTipStrip" in show_fn
        and "MOUSE_FILTER_IGNORE" in show_fn
        and "TipDismiss" in show_fn
        and 'text = "×"' in show_fn
        and "BtnClose" not in show_fn
        and "EOA_FIRST_SESSION_TIP shown=1 pass_through=1" in show_fn
        and "eoa_first_session_tip_shown" in show_fn
        and "button_down.connect(_arm_first_session_tip_dismiss_swallow)" in show_fn
        and "_dismiss_inspector_and_restore_input" not in dismiss_fn
        and "_lock_close_camera" not in dismiss_fn
        and "_consume_close_press_left_gesture" not in dismiss_fn
        and "set_input_as_handled" in dismiss_fn
        and 'call_deferred("_free_first_session_tip_strip")' in dismiss_fn
        and "queue_free" not in dismiss_fn
        and "eoa_tip_dismiss_swallow_release" in arm_fn
        and "eoa_tip_dismiss_swallow_release" in block_fn
        and "queue_free" in free_fn
        and "_lock_close_camera" not in free_fn
        and "_first_session_tip_dismiss_blocks_map_pick" in chip_fn
        and "_first_session_tip_dismiss_blocks_map_pick" in unhandled_fn
        and "_clear_first_session_tip_dismiss_swallow" in input_fn
        and "show_first_session_action_tip" in toast_fn
        and "eoa_first_session_toast" in runner
    )
    wiring["begin_tip_pass_through"] = tip_ok
    (passes if tip_ok else fails).append("begin_tip_pass_through")

    popup = _gd_func_slice(ren, "_show_unit_detail_popup")
    fill_blk = _fill_label_block(popup)
    card_ok = (
        "ToeLabel" in fill_blk
        and "Fill —% · TOE —" in fill_blk
        and "vbox.add_child(fill_lbl)" in fill_blk
        and 'add_theme_font_size_override("font_size", 16)' in fill_blk
        and "AUTOWRAP_WORD" in fill_blk
        and "AUTOWRAP_OFF" not in fill_blk
        and "clip_text = false" in fill_blk
        and "FillToeBar" in fill_blk
        and "Vector2(320, 220)" in popup
        and "clip_contents = false" in popup
        and "BtnClose" in popup
        and "Vector2(76, 28)" in popup
        and popup.find("AUTOWRAP_OFF") < popup.find("fill_lbl")
    )
    wiring["fill_toe_card_readable"] = card_ok
    (passes if card_ok else fails).append("fill_toe_card_readable")

    refresh = _gd_func_slice(ren, "_refresh_selected_unit_chip")
    aabb = _gd_func_slice(ren, "_unit_counter_aabb_hit_screen")
    glyphs = _gd_func_slice(ren, "_world_in_unit_painted_glyphs")
    chip_ok = (
        "FillToeReadout" in refresh
        and "_attach_fill_toe_readout" in refresh
        and "_formation_is_player_tag" in refresh
        and 'str(ch.name) == "FillToeReadout"' in aabb
        and "FillToeReadout" not in glyphs
        and "font_size\", 14" in _gd_func_slice(ren, "_attach_fill_toe_readout")
    )
    wiring["selected_land_chip_fill_toe"] = chip_ok
    (passes if chip_ok else fails).append("selected_land_chip_fill_toe")

    land = _gd_func_slice(ren, "_try_open_land_unit_at_world")
    spill = _gd_func_slice(ren, "_nearest_player_land_formation_at_world")
    gate = _gd_func_slice(ren, "_empty_land_spill_is_on_chip")
    nearest_i = land.find("_nearest_player_land_formation_at_world")
    empty_ok = (
        nearest_i > land.find("_resolve_hex_pick_pid")
        and nearest_i > land.rfind("_player_land_formation_at_province")
        and "_empty_land_spill_is_on_chip" in land
        and "fo = _nearest_player_land_formation_at_world" not in land
        and "const CHROME_SPILL_WORLD: float = 340.0" in spill
        and "maxf(hit_r, CHROME_SPILL_WORLD)" in spill
        and "_unit_counter_hit_radius_world" in gate
        and "_formation_icon_distance" in gate
    )
    wiring["empty_land_hit_disk_only"] = empty_ok
    (passes if empty_ok else fails).append("empty_land_hit_disk_only")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "tip_text": TIP_TEXT,
        "summary": "first_session_readability · %s · fail=%s"
        % ("PASS" if ok else "FAIL", ",".join(fails) or "none"),
    }
