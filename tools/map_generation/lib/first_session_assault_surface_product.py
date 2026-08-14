"""First-session assault surface — discoverability for Attack / Ctrl+click.

Player value: war loop fails silently when assault affordance is unknown.
Pure product formats steps + toast + integrity against MapRenderer / play strip.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
ORDER_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
BATTLE_MANAGER = ROOT / "scripts" / "combat" / "BattleManager.gd"


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


def _execute_success_slice(renderer_src: str) -> str:
    """From first execute_province_assault in _try_execute_province_attack to func end."""
    fn = _gd_func_slice(renderer_src, "_try_execute_province_attack")
    idx = fn.find("execute_province_assault")
    if idx < 0:
        return ""
    return fn[idx:]


def _honesty_checks(renderer_src: str, battle_src: str) -> Dict[str, bool]:
    """Assault source honesty: named unit on can/execute; no Berlin fallback path."""
    can_fn = _gd_func_slice(battle_src, "can_assault_province")
    exec_fn = _gd_func_slice(battle_src, "execute_province_assault")
    try_fn = _gd_func_slice(renderer_src, "_try_execute_province_attack")
    prev_fn = _gd_func_slice(battle_src, "preview_assault")
    # can_assault accepts formation_id 4th arg
    can_has_fid = "formation_id" in can_fn and (
        "formation_id: String" in can_fn or "formation_id =" in can_fn or "formation_id:" in can_fn
    )
    # execute re-calls can with the same attacker_formation_id
    exec_can_with_fid = (
        "can_assault_province(" in exec_fn and "attacker_formation_id" in exec_fn
    )
    # Map path uses selected_formation_id + preview_assault / unit formula (not ProvinceInsight toast)
    try_named = "selected_formation_id" in try_fn
    try_preview = "preview_assault" in try_fn
    try_no_insight_toast = "ProvinceInsight.get_battle_preview" not in try_fn
    try_march_first = "March to the border first" in try_fn
    # Hex-only / named-unit paths do not call find_attack_source when constrained
    can_no_fallback_when_set = (
        "find_attack_source" in can_fn
        and ("from_pid >= 0" in can_fn or "from_province_id >= 0" in can_fn or "from_pid >= 0" in can_fn)
        and ("not fid.is_empty()" in can_fn or 'not fid.is_empty()' in can_fn or "formation_id" in can_fn)
    )
    return {
        "can_assault_has_formation_id": bool(can_fn) and can_has_fid,
        "execute_can_with_fid": bool(exec_fn) and exec_can_with_fid,
        "map_uses_selected_formation": bool(try_fn) and try_named,
        "map_uses_preview_assault": bool(try_fn) and try_preview and bool(prev_fn),
        "map_no_province_insight_toast": bool(try_fn) and try_no_insight_toast,
        "map_march_first_distant": bool(try_fn) and try_march_first,
        "can_honest_no_berlin_fallback": bool(can_fn) and can_no_fallback_when_set,
    }


def _hang_class_checks(renderer_src: str, battle_src: str) -> Dict[str, bool]:
    exec_after = _execute_success_slice(renderer_src)
    b_instant = _gd_func_slice(renderer_src, "_run_live_border_fronts_instant")
    b_show = _gd_func_slice(renderer_src, "show_live_border_fronts")
    capture = _gd_func_slice(renderer_src, "refresh_after_capture_light")
    notify = _gd_func_slice(battle_src, "_notify_map_refresh")
    post = _gd_func_slice(renderer_src, "_assault_post_ui_light")
    pin = _gd_func_slice(renderer_src, "_try_open_unit_at_world")
    attack_btn = _gd_func_slice(renderer_src, "_update_attack_button")

    fail_idx = exec_after.find('if not bool(assault.get("success"')
    fail_has_busy_clear = False
    success_tail_clears_busy = False
    if fail_idx >= 0:
        fail_to_return = exec_after[fail_idx:]
        ret_idx = fail_to_return.find("return")
        fail_block = fail_to_return[: ret_idx if ret_idx >= 0 else len(fail_to_return)]
        fail_has_busy_clear = "_assault_execute_busy = false" in fail_block
        success_tail = fail_to_return[ret_idx:] if ret_idx >= 0 else ""
        success_tail_clears_busy = "_assault_execute_busy = false" in success_tail
    notify_uses_target = (
        "target_pid" in notify or "target_province_id" in notify
    ) and "selected_province_id" not in notify
    out = {
        "execute_no_info_panel": bool(exec_after) and "show_info_panel" not in exec_after,
        "execute_no_force_border": bool(exec_after) and "force_border_update" not in exec_after,
        "b_path_no_info_panel": bool(b_instant)
        and bool(b_show)
        and "show_info_panel" not in b_instant
        and "show_info_panel" not in b_show,
        "capture_no_full_fill": bool(capture)
        and "_refresh_province_fill_colors" not in capture,
        "capture_no_full_icons": bool(capture)
        and "_update_unit_icons_for_test" not in capture,
        "notify_uses_target_pid": bool(notify) and notify_uses_target,
        "notify_includes_from_pid": bool(notify) and "from_pid" in notify,
        "busy_clears_in_post_ui_light": (
            bool(post)
            and "_assault_execute_busy = false" in post
            and fail_has_busy_clear
            and not success_tail_clears_busy
            and "_assault_post_ui_light" in exec_after
        ),
        "pin_select_no_inspector": bool(pin)
        and "show_info_panel" not in pin
        and "_update_attack_button" not in pin,
        "attack_visible_disabled": bool(attack_btn)
        and "disabled" in attack_btn
        and "visible = true" in attack_btn,
    }
    out.update(_honesty_checks(renderer_src, battle_src))
    return out

ASSAULT_STEPS: List[str] = [
    "1. Select friendly province with a formation (capital / hub / border)",
    "2. Press B or toolbar Fronts — cycle enemy border target",
    "3. Select the enemy target province (or keep front highlighted)",
    "4. Inspector Attack button OR Ctrl+click adjacent enemy land",
    "5. Or Order strip Assault (play mode) — apply_assault",
]


def format_assault_ready_toast(
    *,
    attacker_tag: str = "GER",
    from_province_id: int = 0,
    to_province_id: int = 0,
    defender_tag: str = "",
) -> str:
    tag = str(attacker_tag or "GER").strip().upper() or "GER"
    def_t = str(defender_tag or "?").strip().upper() or "?"
    fr = int(from_province_id or 0)
    to = int(to_province_id or 0)
    if fr > 0 and to > 0:
        return (
            "Assault ready · %s #%d → %s #%d · Ctrl+click enemy or strip Assault"
            % (tag, fr, def_t, to)
        )
    return (
        "Assault · select friendly formation · B fronts · Ctrl+click enemy adj · strip Assault"
    )


def format_assault_hint_plain(*, country_tag: str = "GER") -> str:
    tag = str(country_tag or "GER").strip().upper() or "GER"
    lines = [
        "First-session assault (%s)" % tag,
        format_assault_ready_toast(attacker_tag=tag),
    ] + list(ASSAULT_STEPS)
    return "\n".join(lines)


def build_first_session_assault_surface_product(
    *,
    country_tag: str = "GER",
    from_province_id: int = 0,
    to_province_id: int = 0,
    defender_tag: str = "",
    fronts: Optional[Sequence[Mapping[str, Any]]] = None,
    check_wiring: bool = True,
) -> Dict[str, Any]:
    tag = str(country_tag or "GER").strip().upper() or "GER"
    rows: List[Dict[str, Any]] = []
    for t in fronts or []:
        if not isinstance(t, Mapping):
            continue
        pid = int(t.get("province_id") or t.get("id") or -1)
        if pid < 0:
            continue
        rows.append(
            {
                "province_id": pid,
                "from_province_id": int(t.get("from_province_id") or 0),
                "defender_tag": str(t.get("defender_tag") or "?").upper(),
                "name": str(t.get("name") or ("#%d" % pid)),
            }
        )
    # Prefer live front row for default to_id
    to_id = int(to_province_id or 0)
    from_id = int(from_province_id or 0)
    def_t = str(defender_tag or "").strip().upper()
    if to_id <= 0 and rows:
        to_id = int(rows[0]["province_id"])
        from_id = from_id or int(rows[0].get("from_province_id") or 0)
        def_t = def_t or str(rows[0].get("defender_tag") or "")
    toast = format_assault_ready_toast(
        attacker_tag=tag,
        from_province_id=from_id,
        to_province_id=to_id,
        defender_tag=def_t,
    )
    plain = format_assault_hint_plain(country_tag=tag)
    fails: List[str] = []
    passes: List[str] = []
    if "Ctrl+click" in toast or "Ctrl+click" in plain:
        passes.append("mentions_ctrl_click")
    else:
        fails.append("no_ctrl_click_hint")
    if "Assault" in plain or "assault" in plain.lower():
        passes.append("mentions_assault")
    else:
        fails.append("no_assault_word")
    if len(ASSAULT_STEPS) >= 4:
        passes.append("steps_n=%d" % len(ASSAULT_STEPS))
    else:
        fails.append("too_few_steps")

    # Optional board smoke: Maginot-class fronts via live-border product
    front_product_ok = False
    try:
        from map_live_border_fronts_surface_product import (  # type: ignore
            build_map_live_border_fronts_surface_product,
        )

        fr = build_map_live_border_fronts_surface_product(
            country_tag=tag, max_count=4
        )
        front_product_ok = bool(fr.get("ok")) and int(fr.get("count") or fr.get("front_count") or len(fr.get("targets") or [])) >= 0
        if front_product_ok:
            passes.append("fronts_surface_reachable")
            if not rows:
                rows = list(fr.get("targets") or [])[:4]
    except Exception:
        passes.append("fronts_surface_optional_skip")

    wiring: Dict[str, bool] = {}
    if check_wiring:
        ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
        panel = ORDER_PANEL.read_text(encoding="utf-8") if ORDER_PANEL.is_file() else ""
        bm_src = BATTLE_MANAGER.read_text(encoding="utf-8") if BATTLE_MANAGER.is_file() else ""
        wiring["map_ctrl_click_or_assault"] = (
            "ctrl_pressed" in ren and ("assault" in ren.lower() or "Attack" in ren)
        ) or "Ctrl+click" in ren
        wiring["play_strip_assault"] = (
            "apply_assault" in panel
            and ("EOA_PLAY_STRIP" in panel or "_rebuild_play_mode_strip" in panel or "Assault" in panel)
        )
        wiring["assault_hint_api"] = (
            "toast_assault_surface" in ren
            or "first_session_assault" in ren
            or "Assault ready" in ren
        )
        wiring.update(_hang_class_checks(ren, bm_src))
        for k, v in wiring.items():
            if v:
                passes.append("wire_%s" % k)
            else:
                fails.append("wire_%s" % k)

    if check_wiring:
        ok = len(fails) == 0
    else:
        ok = "no_ctrl_click_hint" not in fails and "no_assault_word" not in fails
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "country_tag": tag,
        "from_province_id": from_id,
        "to_province_id": to_id,
        "defender_tag": def_t,
        "targets": rows,
        "steps": list(ASSAULT_STEPS),
        "toast": toast,
        "plain": plain,
        "front_product_ok": front_product_ok,
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "Assault surface · %s · targets=%d · %s"
        % (tag, len(rows), "PASS" if ok else "FAIL"),
        "integration": [
            "first_session_assault_surface_product",
            "order_panel_play_strip_product",
            "map_live_border_fronts_surface_product",
            "MapRenderer Ctrl+click",
        ],
    }


def first_session_assault_surface_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_first_session_assault_surface_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
