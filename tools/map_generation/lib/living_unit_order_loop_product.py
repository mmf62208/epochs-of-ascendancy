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
SCENARIO_LOADER = ROOT / "scripts" / "core" / "ScenarioLoader.gd"
FORMATION_MOVEMENT = ROOT / "scripts" / "formations" / "FormationMovement.gd"
BATTLE_MANAGER = ROOT / "scripts" / "combat" / "BattleManager.gd"
HARNESS = ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd"
GATES = ROOT / "tools" / "eoa_full_test_gates.sh"
TIME_MANAGER = ROOT / "scripts" / "autoload" / "TimeManager.gd"
MAP_MANAGER = ROOT / "scripts" / "map" / "MapManager.gd"
HOOK_GD = ROOT / "scripts" / "ui" / "PlayNextHook.gd"
LEADER_MANAGER = ROOT / "scripts" / "leaders" / "LeaderManager.gd"
STRIP_GD = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"
PEACE_WIN = ROOT / "scripts" / "ui" / "PeaceConferenceWindow.gd"
MAIN_MENU = ROOT / "scripts" / "ui" / "MainMenu.gd"
TITLE_BOOT = ROOT / "scripts" / "ui" / "LivingTitleBoot.gd"
GDATA_GD = ROOT / "scripts" / "autoload" / "GameData.gd"
INSIGHT_GD = ROOT / "scripts" / "map" / "ProvinceInsight.gd"
TOP_BAR = ROOT / "scripts" / "ui" / "TopInfoBar.gd"
AAR_GD = ROOT / "scripts" / "combat" / "LandBattleAar.gd"
LEADER_EVENT_UI = ROOT / "scripts" / "ui" / "LeaderEventUI.gd"
SAVE_LOAD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"
TECH_UNLOCK = ROOT / "scripts" / "technology" / "TechnologyUnlockRegistry.gd"
TECH_MGR = ROOT / "scripts" / "technology" / "TechnologyManager.gd"

GER_FRONT = 710173
FRA_FRONT = 710739
JAP_FRONT = 903981
CHI_FRONT = 902598
JAP_REAR = 903966
ENG_CHANNEL = 950001
ENG_NORTH_SEA = 950000
MAGINOT_REGION = 100
GER_CAPITAL = 710300


def living_clock_skips_ai_starts(tm_src: str) -> bool:
    """True when _maybe_run_ai_land_battle_starts returns before try_ai on the living clock."""
    fn = _slice(tm_src, "_maybe_run_ai_land_battle_starts")
    i = fn.find("_living_playtest_clock")
    j = fn.find("try_ai_start_land_battles")
    if j < 0:
        return True
    if i < 0:
        return False
    return i < j and "return" in fn[i:j]


def living_clock_skips_occupation_ticks(tm_src: str) -> bool:
    """True when the living F5 clock never ticks occupation unrest."""
    maybe = _slice(tm_src, "_maybe_tick_occupation_unrest")
    flush = _slice(tm_src, "_flush_sim_events")
    clock = _slice(tm_src, "advance_living_playtest_days")
    if "apply_occupation_daily_tick_live" not in maybe:
        return True
    if "_maybe_tick_occupation_unrest" not in flush:
        return True
    if "occupation_tick_n" not in clock:
        return True
    i = maybe.find("_living_playtest_clock")
    j = maybe.find("apply_occupation_daily_tick_live")
    if j < 0:
        return True
    if i >= 0 and i < j and "return" in maybe[i:j]:
        return True
    return False


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
        and "_station_world_major_air_chips" in park
        and "_station_world_major_fleet_chips" in park
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
    live_choke = _slice(mm, "living_choke_state")
    choke_ok = (
        bool(choke_fn)
        and "has_strategic_chokepoint" in choke_fn
        and "get_chokepoint_or_river_supply_bonus" in choke_fn
        and "choke flagged" in choke_fn
        and bool(live_choke)
        and "off-station" in live_choke
        and "supply bite" in live_choke
        and "0.85" in live_choke
    )
    g_flag = "flag_naval_choke" in _slice(ren, "_request_hang_safe_supply_corridor")
    next_choke = (
        "choke_flag" in hook
        and "fleet_choke" in hook
        and "living_choke_state" in hook
        and "stationed_province_id" in _slice(hook, "apply")
    )
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
        and "func unassign_air_wing" in lm
        and "func land_battle_cas_power" in bm
        and "assigned_region_id" in _slice(bm, "_land_battle_cas")
        and "range" in strip
        and "fuel" in strip
        and "Unassign" in strip
        and "Assign CAS" in _slice(ren, "_show_unit_detail_popup")
        and "Unassign CAS" in _slice(ren, "_show_unit_detail_popup")
        and "assign_cas" in hook
        and "unassign_cas" in hook
        and "NEXT assign CAS" in harness
        and "NEXT unassign CAS" in harness
        and "Channel off-station supply bite" in harness
        and "NEXT stationed Channel fleet" in harness
    )
    wiring["air_region_cas"] = wing_ok
    (passes if wing_ok else fails).append("air_region_cas")

    air8 = _slice(ren, "_station_world_major_air_chips")
    nav8 = _slice(ren, "_station_world_major_fleet_chips")
    tags8 = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL")
    air8_ok = (
        bool(air8)
        and "air" in air8
        and all(t in air8 for t in tags8)
        and bool(nav8)
        and "naval" in nav8
        and all(t in nav8 for t in tags8)
        and str(ENG_CHANNEL) in nav8
        and str(GER_CAPITAL) in air8
    )
    wiring["world_oob_air_naval"] = air8_ok
    (passes if air8_ok else fails).append("world_oob_air_naval")

    gdata = GDATA_GD.read_text(encoding="utf-8") if GDATA_GD.is_file() else ""
    peace_win = PEACE_WIN.read_text(encoding="utf-8") if PEACE_WIN.is_file() else ""
    insight = INSIGHT_GD.read_text(encoding="utf-8") if INSIGHT_GD.is_file() else ""
    apply_slice = _slice(hook, "apply")
    peace_ok = (
        "func apply_peace_conference_settlement_live" in gdata
        and "apply_occupation_policy_live" in _slice(gdata, "apply_peace_conference_settlement_live")
        and "func apply_occupation_daily_tick_live" in gdata
        and "func apply_living_transfer" in peace_win
        and "func open_living_sheet" in peace_win
        and "func apply_from_sheet" in peace_win
        and "apply_peace_conference_settlement_live" in peace_win
        and "DisplayServer.get_name() == \"headless\"" in _slice(peace_win, "open_living_sheet")
        and "open_living_sheet" in apply_slice
        and "apply_peace_conference_settlement_live" not in apply_slice
        and "apply_war_goal_justify" in apply_slice
        and "war_goal_justify_day" not in apply_slice
        and "apply_war_goal_execute" in apply_slice
        and "war_goal_execute_day" not in apply_slice
        and "settle_peace" in hook
        and "occupation_unrest" in hook
        and "set_occupation_overlay_visible" in hook
        and "build_occupation_visual_chip_bbcode" in insight
        and "apply_from_sheet" in harness
        and "peace conference opened" in harness
        and "peace transfer owner" in harness
        and "occupation resistance" in harness
        and "0.65" in harness
        and "occupation unrest tick" in harness
        and "func _maybe_tick_occupation_unrest" in tm
        and "apply_occupation_daily_tick_live" in _slice(tm, "_maybe_tick_occupation_unrest")
        and not living_clock_skips_occupation_ticks(tm)
    )
    wiring["peace_occupation"] = peace_ok
    (passes if peace_ok else fails).append("peace_occupation")

    try_ai = _slice(bm, "try_ai_start_land_battles")
    follow_ai = _slice(bm, "try_ai_follow_on_after_win")
    mm_src = MAP_MANAGER.read_text(encoding="utf-8") if MAP_MANAGER.is_file() else mm
    ai_ok = (
        bool(try_ai)
        and "start_land_battle" in try_ai
        and "execute_province_assault" not in try_ai
        and "EOA_AI_LAND_BATTLES" in try_ai
        and bool(follow_ai)
        and "execute_province_assault" not in follow_ai
        and "_emergency_jap_front_seeds" in mm_src
        and str(CHI_FRONT) in mm_src
        and str(JAP_FRONT) in mm_src
        and 'tag != "JAP"' in mm_src
        and "try_ai_start_land_battles" in harness
        and "CHI-JAP AI take-land" in harness
        and "second theater owner" in harness
        and "killswitch" in harness
        and str(CHI_FRONT) in harness
    )
    wiring["ai_take_land"] = ai_ok
    (passes if ai_ok else fails).append("ai_take_land")

    tm_src = TIME_MANAGER.read_text(encoding="utf-8") if TIME_MANAGER.is_file() else ""
    top_bar = TOP_BAR.read_text(encoding="utf-8") if TOP_BAR.is_file() else ""
    runner = TEST_RUNNER.read_text(encoding="utf-8") if TEST_RUNNER.is_file() else runner
    menu = MAIN_MENU.read_text(encoding="utf-8") if MAIN_MENU.is_file() else ""
    title = TITLE_BOOT.read_text(encoding="utf-8") if TITLE_BOOT.is_file() else ""
    nation_ok = (
        "func boot_living_player" in lm
        and "LIVING_PLAYER_TAGS" in lm
        and '"ENG"' in lm
        and "func boot_living_era" in tm_src
        and "1918" in _slice(tm_src, "boot_living_era")
        and "2026" in _slice(tm_src, "boot_living_era")
        and "func open_living_surface" in top_bar
        and "func _open_living_surface" in hook
        and "unpause_only" in hook
        and "_open_living_surface" in apply_slice
        and "tech_done" in apply_slice
        and "EOA_PLAYER_TAG" in runner
        and "EOA_START_YEAR" in runner
        and 'setup_solo_play("GER")' in runner
        and "boot_living_player" in harness
        and "boot_living_era" in harness
        and "NEXT tech_done opens research" in harness
        and "NEXT shortage opens production" in harness
        and "living nation pick ENG" in harness
        and "NEXT zero-arg recommend player_tag=ENG" in harness
        and "func _living_player_tag" in hook
        and "get_player_country_tag" in _slice(hook, "_living_player_tag")
        and "recommend(_player_tag())" in ren
        and "func apply_living_campaign_pick" in menu
        and "func living_campaign_pick_facts" in menu
        and "LIVING_CC_NATIONS" in menu
        and '"GER"' in menu
        and '"ENG"' in menu
        and '"FRA"' in menu
        and '"JAP"' in menu
        and "1918" in menu
        and "2026" in menu
        and "CAMPAIGN" in menu
        and "boot_living_player" in _slice(menu, "apply_living_campaign_pick")
        and "boot_living_era" in _slice(menu, "apply_living_campaign_pick")
        and "CC campaign pick JAP 2026" in harness
        and "CC campaign pick FRA 1918" in harness
        and "CC unknown pick defaults GER 1936" in harness
        and "restored default GER Maginot player tag" in harness
        and bool(title)
        and "func should_show_living_title" in title
        and "func apply_living_title_boot" in title
        and "EOA_SKIP_TITLE" in title
        and "EOA_UNIT_ORDER_QA" in title
        and "headless" in title
        and "load_game_detailed" in title
        and "Begin ·" in title
        and '"USA"' in title
        and "func _show_living_title_boot" in runner
        and "should_show_living_title" in runner
        and "title boot skipped headless" in harness
        and "title boot new ENG 1918" in harness
    )
    wiring["nation_era_next"] = nation_ok
    (passes if nation_ok else fails).append("nation_era_next")

    map_pick_fn = _slice(title, "apply_playable_country_from_province")
    tag_fn = _slice(title, "playable_tag_from_province")
    title_pick_fn = _slice(ren, "_try_living_title_map_pick")
    map_sel_ok = (
        bool(map_pick_fn)
        and "apply_living_title_boot" in map_pick_fn
        and "playable_tag_from_province" in map_pick_fn
        and bool(tag_fn)
        and "get_province" in tag_fn
        and "owner_tag" in tag_fn
        and "LIVING_TITLE_NATIONS" in tag_fn
        and "MOUSE_FILTER_IGNORE" in title
        and "select_from_province" in title
        and bool(title_pick_fn)
        and "select_from_province" in title_pick_fn
        and "LivingTitleBoot" in title_pick_fn
        and "_try_living_title_map_pick" in _slice(ren, "_unhandled_input")
        and "map pick not playable CHI" in harness
        and "map pick FRA land" in harness
        and "map pick GER capital" in harness
        and "map pick JAP land" in harness
        and str(CHI_FRONT) in harness
        and str(FRA_FRONT) in harness
        and str(GER_CAPITAL) in harness
        and str(JAP_FRONT) in harness
        and "func living_diplomacy_from_province" in hook
        and "func send_agent_to_province" in hook
        and "func apply_living_trade" in hook
        and "establish_network" in hook
        and "create_offer" in hook
        and "apply_vector_delta" in hook
        and "map influence FRA" in harness
        and "send agent to FRA" in harness
        and "map trade FRA" in harness
        and "_toast_living_diplomacy_pick" in ren
    )
    wiring["map_country_select"] = map_sel_ok
    (passes if map_sel_ok else fails).append("map_country_select")

    clock_fn = _slice(tm_src, "advance_living_playtest_days")
    drain_fn = _slice(tm_src, "_drain_living_f5_flush")
    tick_one = _slice(bm, "_tick_one_open_land_battle")
    capture_light = _slice(bm, "_apply_attacker_win_capture_light")
    next_hex = _slice(
        AAR_GD.read_text(encoding="utf-8") if AAR_GD.is_file() else "",
        "pick_next_enemy_hex",
    )
    news_ui = LEADER_EVENT_UI.read_text(encoding="utf-8") if LEADER_EVENT_UI.is_file() else ""
    save_src = SAVE_LOAD.read_text(encoding="utf-8") if SAVE_LOAD.is_file() else ""
    clock_ok = (
        bool(clock_fn)
        and "never_execute" in clock_fn
        and "execute_province_assault" not in clock_fn
        and "advance_days(" in clock_fn
        and "_drain_living_f5_flush" in clock_fn
        and "_flush_sim_events" in drain_fn
        and "f5_flush" in clock_fn
        and "_living_playtest_clock" in tm_src
        and "_living_playtest_clock" in _slice(tm_src, "is_interactive_light_sim")
        and "day_emit" in tm_src
        and "day_battles" in tm_src
        and "game_day_advanced.emit" in tm_src
        and "_tick_open_land_battles" in tm_src
        and '"aar"' in clock_fn
        and '"news"' in clock_fn
        and "_record_land_aar" in tick_one
        and "_post_battle_news" in capture_light
        and "get_divisions_at_province" not in next_hex
        and "func _should_skip_toast_ui" in news_ui
        and "func _skip_quit_autosave" in save_src
        and "_skip_quit_autosave" in _slice(save_src, "_notification")
        and "clampi(int(days), 1, 20)" in clock_fn
        and "try_ai_start_land_battles" in _slice(tm_src, "_maybe_run_ai_land_battle_starts")
        and not living_clock_skips_ai_starts(tm_src)
        and "ai_land_started_n" in clock_fn
        and "ai_started_to_ids" in clock_fn
        and "_living_playtest_clock" in _slice(save_src, "_on_day_advanced_for_autosave")
        and "advance_living_playtest_days" in harness
        and "playtest clock advanced" in harness
        and "advanced < 20" in harness
        and "never_execute" in harness
        and "playtest clock AAR" in harness
        and "f5_flush" in harness
        and "_seed_maginot_clock_battle" in harness
        and "execute_province_assault" not in _slice(bm, "try_ai_start_land_battles")
        and "_living_playtest_clock" in mm_src
        and "func living_playtest_saveload_roundtrip" in save_src
        and "_gather_save_data" in _slice(save_src, "living_playtest_saveload_roundtrip")
        and "_apply_save_data" in _slice(save_src, "living_playtest_saveload_roundtrip")
        and "execute_province_assault" not in _slice(save_src, "living_playtest_saveload_roundtrip")
        and "living_playtest_saveload_roundtrip" in harness
        and "playtest clock save/load" in harness
        and "playtest clock AI land start" in harness
        and "ai_land_started_n" in harness
        and "occupation_tick_n" in clock_fn
        and not living_clock_skips_occupation_ticks(tm_src)
        and "playtest clock occupation unrest tick" in harness
    )
    wiring["playtest_clock"] = clock_ok
    (passes if clock_ok else fails).append("playtest_clock")

    unlock_src = TECH_UNLOCK.read_text(encoding="utf-8") if TECH_UNLOCK.is_file() else ""
    # apply_unlock is a prefix of apply_unlocks — slice on the exact signature.
    apply_i = unlock_src.find("func apply_unlock(")
    apply_fn = unlock_src[apply_i:] if apply_i >= 0 else ""
    if apply_fn:
        nxt = apply_fn.find("\nfunc ", 1)
        if nxt > 0:
            apply_fn = apply_fn[:nxt]
    module_fn = _slice(unlock_src, "_apply_module_unlock")
    unlock_ok = (
        bool(apply_fn)
        and '"module_unlock"' in apply_fn
        and "_apply_module_unlock" in apply_fn
        and apply_fn.find('"module_unlock"') < apply_fn.find("push_warning")
        and "func _apply_module_unlock" in unlock_src
        and "unlocked_equipment_modules" in module_fn
        and "module_ids" in module_fn
        and "yield_every" in _slice(
            TECH_MGR.read_text(encoding="utf-8") if TECH_MGR.is_file() else "",
            "_apply_completed_techs_in_order",
        )
        and "EOA_UNIT_ORDER_QA" in _slice(
            TECH_MGR.read_text(encoding="utf-8") if TECH_MGR.is_file() else "",
            "_apply_completed_techs_in_order",
        )
        and "UNIT ORDER QA spawn majors" in (
            SCENARIO_LOADER.read_text(encoding="utf-8") if SCENARIO_LOADER.is_file() else ""
        )
    )
    wiring["f5_boot_unlocks"] = unlock_ok
    (passes if unlock_ok else fails).append("f5_boot_unlocks")

    chrome = _slice(ren, "_attach_unit_counter_chrome")
    chrome_ok = (
        bool(chrome)
        and "StrNum" in chrome
        and "Designation" in chrome
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
    star_before = (
        "_capital_star_pid_at" in spatial
        and spatial.find("_capital_star_pid_at") < spatial.find("_try_open_unit_at_world")
    )
    wiring["capital_star_before_chip"] = star_before
    (passes if star_before else fails).append("capital_star_before_chip")

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
    input_i = ren.find("func _input")
    unh_i = ren.find("func _unhandled_input")
    input_fn = ren[input_i:unh_i] if input_i >= 0 and unh_i > input_i else ""
    gi = input_fn.find("KEY_G")
    if gi >= 0:
        g_slice = input_fn[gi : gi + 400]
    else:
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
    cheap_fn = _slice(ren, "_ensure_equipment_glyph_layer_cheap")
    i_no_setup = bool(toggle_fn) and "_setup_strategic_flow_layer" not in toggle_fn
    input_fn = _slice(ren, "_input")
    i_pos = input_fn.find("KEY_I")
    i_block = input_fn[i_pos : i_pos + 900] if i_pos >= 0 else ""
    i_dismiss = "_dismiss_inspector_and_restore_input" in i_block
    esc_in_input = "KEY_ESCAPE" in input_fn and "_dismiss_inspector_and_restore_input" in input_fn
    i_in_input = "KEY_I" in input_fn and "toggle_equipment_flow_glyphs" in input_fn
    i_cheap = (
        bool(cheap_fn)
        and "setup_budgeted" in cheap_fn
        and "_setup_strategic_flow_layer" not in cheap_fn
        and "_ensure_equipment_glyph_layer_cheap" in toggle_fn
    )
    i_ok = i_no_setup and i_dismiss and esc_in_input and i_in_input and i_cheap
    wiring["i_hang_safe"] = i_ok
    (passes if i_ok else fails).append("i_hang_safe")

    war_fn = _slice(ren, "show_first_session_war_path")
    req_fn = _slice(ren, "_request_hang_safe_warloop_flow")
    flow_fn = _slice(ren, "_deferred_budgeted_warloop_flow")
    arm_fn = _slice(ren, "_arm_budgeted_flow_layer")
    war_ok = (
        bool(war_fn)
        and "_request_hang_safe_warloop_flow" in war_fn
        and "_setup_strategic_flow_layer(" not in war_fn
        and "preview_player_route()" not in war_fn
        and bool(req_fn)
        and "call_deferred" in req_fn
        and "_deferred_budgeted_warloop_flow" in req_fn
        and "preview_player_route()" not in req_fn
        and bool(flow_fn)
        and "find_land_path" in flow_fn
        and "preview_player_route()" not in flow_fn
        and "get_contested_provinces" not in flow_fn
        and "_setup_strategic_flow_layer(" not in flow_fn
        and bool(arm_fn)
        and "setup_budgeted" in arm_fn
        and "get_contested_provinces" not in arm_fn
    )
    wiring["warloop_hang_safe"] = war_ok
    (passes if war_ok else fails).append("warloop_hang_safe")

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

    qa_fn = _slice(runner, "_run_unit_order_qa_and_quit")
    evidence_fn = _slice(runner, "_exercise_full_mapmodes_and_actions_headless")
    boot = (
        "ensure_playable_front_chips" in runner
        and "EOA_UNIT_ORDER_QA" in runner
        and "process_frame" in qa_fn
        and "skip headless map-evidence burst" in evidence_fn
        and "unit_order_qa" in runner
        and "not unit_order_qa" in runner
    )
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
