"""Living unit order loop — HOI counters you can pick and order.

Wiring gate. Live proof is HeadlessWorldAccurateUnitOrderLoopTest +
EOA_UNIT_ORDER_QA=1 on TestScenario. Greps alone are not ready.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
TEST_RUNNER = ROOT / "scripts" / "core" / "TestRunner.gd"
FORMATION_MOVEMENT = ROOT / "scripts" / "formations" / "FormationMovement.gd"
BATTLE_MANAGER = ROOT / "scripts" / "combat" / "BattleManager.gd"
HARNESS = ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd"
GATES = ROOT / "tools" / "eoa_full_test_gates.sh"
TIME_MANAGER = ROOT / "scripts" / "autoload" / "TimeManager.gd"
MAP_MANAGER = ROOT / "scripts" / "map" / "MapManager.gd"
HOOK_GD = ROOT / "scripts" / "ui" / "PlayNextHook.gd"
LEADER_MANAGER = ROOT / "scripts" / "leaders" / "LeaderManager.gd"
STRIP_GD = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"

GER_FRONT = 710173
FRA_FRONT = 710739
JAP_FRONT = 903981
CHI_FRONT = 902598
JAP_REAR = 903966
ENG_CHANNEL = 950001
ENG_NORTH_SEA = 950000
MAGINOT_REGION = 100
GER_CAPITAL = 710300


def _slice(src: str, func_name: str) -> str:
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


def build_living_unit_order_loop_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    runner = TEST_RUNNER.read_text(encoding="utf-8") if TEST_RUNNER.is_file() else ""
    mv = FORMATION_MOVEMENT.read_text(encoding="utf-8") if FORMATION_MOVEMENT.is_file() else ""
    bm = BATTLE_MANAGER.read_text(encoding="utf-8") if BATTLE_MANAGER.is_file() else ""
    harness = HARNESS.read_text(encoding="utf-8") if HARNESS.is_file() else ""
    gates = GATES.read_text(encoding="utf-8") if GATES.is_file() else ""
    tm = TIME_MANAGER.read_text(encoding="utf-8") if TIME_MANAGER.is_file() else ""

    if not ren:
        fails.append("missing_map_renderer")
        return {
            "ok": False,
            "status": "FAIL",
            "pass": passes,
            "fail": fails,
            "wiring": wiring,
            "ger_front": GER_FRONT,
            "fra_front": FRA_FRONT,
            "jap_front": JAP_FRONT,
            "summary": "living_unit_order_loop · FAIL · missing MapRenderer",
        }

    park = _slice(ren, "ensure_playable_front_chips")
    park_ok = (
        bool(park)
        and str(GER_FRONT) in park
        and str(FRA_FRONT) in park
        and "stationed_province_id" in park
        and "_update_unit_icons_for_test" in park
        and "_station_world_major_oob_chips" in park
        and "_station_eng_channel_fleet" in park
        and "_station_ger_maginot_air_wing" in park
    )
    wiring["park_maginot"] = park_ok
    (passes if park_ok else fails).append("park_maginot")

    oob = _slice(ren, "_station_world_major_oob_chips")
    oob_ok = (
        bool(oob)
        and str(JAP_FRONT) in oob
        and "JAP" in oob
        and "ENG" in oob
        and "USA" in oob
        and "SOV" in oob
        and "ITA" in oob
        and "POL" in oob
        and "_station_major_land_chip" in oob
    )
    wiring["world_oob_majors"] = oob_ok
    (passes if oob_ok else fails).append("world_oob_majors")

    fleet_fn = _slice(ren, "_station_eng_channel_fleet")
    fleet_ok = (
        bool(fleet_fn)
        and str(ENG_CHANNEL) in fleet_fn
        and "naval" in fleet_fn
        and "ENG" in fleet_fn
    )
    wiring["park_channel_fleet"] = fleet_ok
    (passes if fleet_ok else fails).append("park_channel_fleet")

    sea_hop = _slice(mv, "enqueue_own_sea_hop")
    sea_ok = (
        bool(sea_hop)
        and "not a fleet" in sea_hop
        and "get_adjacent_provinces" in sea_hop
        and "false" in sea_hop
        and "find_own_land_path" not in sea_hop
        and "is_sea" in sea_hop
    )
    wiring["sea_hop_api"] = sea_ok
    (passes if sea_ok else fails).append("sea_hop_api")

    mm = MAP_MANAGER.read_text(encoding="utf-8") if MAP_MANAGER.is_file() else ""
    hook = HOOK_GD.read_text(encoding="utf-8") if HOOK_GD.is_file() else ""
    choke_fn = _slice(mm, "flag_naval_choke")
    choke_ok = (
        bool(choke_fn)
        and "has_strategic_chokepoint" in choke_fn
        and "get_chokepoint_or_river_supply_bonus" in choke_fn
        and "choke flagged" in choke_fn
    )
    g_flag = "flag_naval_choke" in _slice(ren, "_request_hang_safe_supply_corridor")
    next_choke = "choke_flag" in hook and "fleet_choke" in hook
    wiring["choke_flag"] = choke_ok and g_flag and next_choke
    (passes if wiring["choke_flag"] else fails).append("choke_flag")

    wing_fn = _slice(ren, "_station_ger_maginot_air_wing")
    lm = LEADER_MANAGER.read_text(encoding="utf-8") if LEADER_MANAGER.is_file() else ""
    strip = STRIP_GD.read_text(encoding="utf-8") if STRIP_GD.is_file() else ""
    wing_ok = (
        bool(wing_fn)
        and str(MAGINOT_REGION) in wing_fn
        and str(GER_CAPITAL) in wing_fn
        and "assign_air_wing_to_region" in wing_fn
        and "func assign_air_wing_to_region" in lm
        and "func land_battle_cas_power" in bm
        and "assigned_region_id" in _slice(bm, "_land_battle_cas")
        and "range" in strip
        and "fuel" in strip
    )
    wiring["air_region_cas"] = wing_ok
    (passes if wing_ok else fails).append("air_region_cas")

    chrome = _slice(ren, "_attach_unit_counter_chrome")
    chrome_ok = (
        bool(chrome)
        and "StrNum" in chrome
        and "_make_unit_stat_bars" in chrome
        and "OrgBar" in _slice(ren, "_make_unit_stat_bars")
    )
    wiring["chip_str_num"] = chrome_ok
    (passes if chrome_ok else fails).append("chip_str_num")

    scale = _slice(ren, "_unit_counter_scale_for_zoom")
    scale_ok = bool(scale) and "32.0" in scale and "clampf" in scale
    wiring["inverse_zoom_scale"] = scale_ok
    (passes if scale_ok else fails).append("inverse_zoom_scale")

    rebuild = _slice(ren, "_rebuild_demo_unit_icons")
    on_hex = bool(rebuild) and "province_centroids" in rebuild and ".free()" in rebuild
    wiring["chip_on_centroid"] = on_hex
    (passes if on_hex else fails).append("chip_on_centroid")

    spatial = ""
    marker = "use_spatial_picking and event is InputEventMouseButton"
    i = ren.find(marker)
    if i >= 0:
        left = ren.find("MOUSE_BUTTON_LEFT", i)
        end = ren.find("MOUSE_BUTTON_RIGHT", left if left >= 0 else i)
        spatial = ren[left if left >= 0 else i : end if end > 0 else i + 8000]
    pin_first = (
        "_try_open_unit_at_world" in spatial
        and "get_province_at_world_pos" in spatial
        and spatial.find("_try_open_unit_at_world") < spatial.find("get_province_at_world_pos")
    )
    wiring["pin_before_hex"] = pin_first
    (passes if pin_first else fails).append("pin_before_hex")

    move = _slice(ren, "_try_move_selected_unit_to_province")
    move_ok = bool(move) and "enqueue_own_land_march" in move
    wiring["click_own_land_marches"] = move_ok
    (passes if move_ok else fails).append("click_own_land_marches")

    exec_fn = _slice(ren, "_try_execute_province_attack")
    ctrl_ok = (
        "ctrl_pressed" in spatial
        and "_try_execute_province_attack" in spatial
        and "start_land_battle" in exec_fn
    )
    wiring["ctrl_click_starts_battle"] = ctrl_ok
    (passes if ctrl_ok else fails).append("ctrl_click_starts_battle")

    g_slice = ""
    gi = ren.find("KEY_G")
    if gi >= 0:
        g_slice = ren[gi : gi + 400]
    g_request = "_request_hang_safe_supply_corridor" in g_slice
    g_no_sync_bfs = (
        "highlight_corridor_capital_to_selected" not in g_slice
        and "highlight_supply_corridor" not in g_slice
        and "preview_player_route()" not in g_slice
    )
    deferred = _slice(ren, "_deferred_budgeted_supply_corridor")
    deferred_ok = (
        bool(deferred)
        and "highlight_supply_route_path" in deferred
        and "find_land_path" in deferred
        and "preview_player_route()" not in deferred
        and "highlight_supply_corridor" not in deferred
    )
    click_arm = "_corridor_click_armed" in ren
    wiring["g_hang_safe"] = g_request and g_no_sync_bfs and deferred_ok and click_arm
    (passes if wiring["g_hang_safe"] else fails).append("g_hang_safe")

    close_fn = _slice(ren, "_on_close_pressed")
    dismiss_fn = _slice(ren, "_dismiss_inspector_and_restore_input")
    pick_fn = _slice(ren, "_pick_unit_formation_at_world")
    close_ok = (
        bool(close_fn)
        and "_dismiss_inspector_and_restore_input" in close_fn
        and bool(dismiss_fn)
        and "gui_release_focus" in dismiss_fn
        and "UnitDetailPopup" in dismiss_fn
        and "hide_tooltip" in dismiss_fn
    )
    wiring["inspector_close_restores"] = close_ok
    (passes if close_ok else fails).append("inspector_close_restores")

    toggle_fn = _slice(ren, "toggle_equipment_flow_glyphs")
    i_no_setup = bool(toggle_fn) and "_setup_strategic_flow_layer" not in toggle_fn
    i_mark = "event.keycode == KEY_I and not event.ctrl_pressed"
    i_pos = ren.find(i_mark)
    i_block = ren[i_pos : i_pos + 900] if i_pos >= 0 else ""
    i_dismiss = "_dismiss_inspector_and_restore_input" in i_block
    input_fn = _slice(ren, "_input")
    esc_in_input = "KEY_ESCAPE" in input_fn and "_dismiss_inspector_and_restore_input" in input_fn
    i_in_input = "KEY_I" in input_fn and "_inspector_stack_blocking_input" in input_fn
    i_ok = i_no_setup and i_dismiss and esc_in_input and i_in_input
    wiring["i_hang_safe"] = i_ok
    (passes if i_ok else fails).append("i_hang_safe")

    owner_fn = _slice(ren, "_on_map_province_data_changed")
    post_fn = _slice(ren, "_assault_post_ui_light")
    notify_fn = _slice(bm, "_notify_map_refresh")
    tick_fn = _slice(bm, "_tick_one_open_land_battle")
    deferred_fn = _slice(bm, "_deferred_resolve_attacker_win")
    supply_fn = _slice(bm, "_land_side_supply_state")
    resolve_ok = (
        bool(owner_fn)
        and "_refresh_single_province_fill" in owner_fn
        and "owner_flip" in owner_fn
        and "_update_country_borders()" not in owner_fn
        and "_rebuild_province_mesh_layer()" not in owner_fn
        and "_schedule_political_labels_rebuild()" not in owner_fn
        and bool(post_fn)
        and "_refresh_province_fill_pids" in post_fn
        and bool(notify_fn)
        and "refresh_after_capture_light" in notify_fn
        and bool(tick_fn)
        and "execute_province_assault" in tick_fn
        and "_deferred_resolve_attacker_win" in tick_fn
        and "call_deferred" in tick_fn
        and bool(deferred_fn)
        and "_apply_attacker_win_capture_light" in deferred_fn
        and "execute_province_assault" not in deferred_fn
        and bool(_slice(bm, "_apply_attacker_win_capture_light"))
        and "update_province_owner" in _slice(bm, "_apply_attacker_win_capture_light")
        and "execute_province_assault" not in _slice(bm, "_apply_attacker_win_capture_light")
        and bool(supply_fn)
        and "_interactive_light_sim" in supply_fn
        and "is_interactive_light_sim" in _slice(bm, "_interactive_light_sim")
        and "day_emit" in tm
        and "day_ai" in tm
        and "day_battles" in tm
        and "_apply_attacker_win_capture_light" in _slice(bm, "start_land_battle")
    )
    wiring["resolve_hang_safe"] = resolve_ok
    (passes if resolve_ok else fails).append("resolve_hang_safe")

    strat_skip = bool(pick_fn) and "_unit_counters_want_visible" in pick_fn
    wiring["strategic_pick_skip"] = strat_skip
    (passes if strat_skip else fails).append("strategic_pick_skip")

    mv_ok = "func enqueue_own_land_march" in mv and "func enqueue_own_sea_hop" in mv
    bm_ok = "func start_land_battle" in bm
    wiring["march_api"] = mv_ok
    wiring["battle_api"] = bm_ok
    (passes if mv_ok else fails).append("march_api")
    (passes if bm_ok else fails).append("battle_api")

    boot = "ensure_playable_front_chips" in runner and "EOA_UNIT_ORDER_QA" in runner
    wiring["f5_boot_and_qa"] = boot
    (passes if boot else fails).append("f5_boot_and_qa")

    harness_ok = (
        bool(harness)
        and "710173" in harness
        and "710739" in harness
        and str(JAP_FRONT) in harness
        and str(CHI_FRONT) in harness
        and "JAP DemoUnitIcon pickable" in harness
        and "CHI-JAP start_land_battle opened" in harness
        and str(ENG_CHANNEL) in harness
        and "ENG fleet on sea hex" in harness
        and "ENG sea-hop ok" in harness
        and "Channel choke flagged" in harness
        and "GER wing assigned Maginot-region" in harness
        and "CAS-delta" in harness
        and "range/fuel visible" in harness
        and "enqueue_own_land_march" in harness
        and "enqueue_own_sea_hop" in harness
        and "start_land_battle" in harness
        and "ensure_playable_front_chips" in harness
        and "DemoUnitIcon" in harness
        and "formation_id" in harness
        and "RESULT=" in harness
    )
    wiring["headless_harness"] = harness_ok
    (passes if harness_ok else fails).append("headless_harness")

    gate_ok = "test_living_unit_order_loop_product" in gates
    wiring["on_official_quick"] = gate_ok
    (passes if gate_ok else fails).append("on_official_quick")

    if not check_wiring:
        ok = park_ok and move_ok
    else:
        ok = len(fails) == 0

    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "ger_front": GER_FRONT,
        "fra_front": FRA_FRONT,
        "jap_front": JAP_FRONT,
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "living_unit_order_loop · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "machine_prove_pick_march_assault_before_human_f5",
    }


def living_unit_order_loop_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_living_unit_order_loop_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
