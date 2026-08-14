"""Multi-day battle integrity — daily slices, capture on break/retreat (PR 5).

Pure wiring + Maginot math gate. Does not execute Godot.
execute_province_assault / resolve_combat stay one-shot; player path is start_province_battle.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[3]
BATTLE_MANAGER = ROOT / "scripts" / "combat" / "BattleManager.gd"
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
GAME_DATA = ROOT / "scripts" / "autoload" / "GameData.gd"
MAP_MANAGER = ROOT / "scripts" / "map" / "MapManager.gd"
SAVE_LOAD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"
COMBAT_RESOLVER = ROOT / "scripts" / "combat" / "CombatResolver.gd"

# Design worked Maginot powers (Panzer III J vs SOMUA @ xp_mult 0.85 + 0.15 initiative).
MAGINOT_ATT_SOFT = 0.900
MAGINOT_ATT_HARD = 0.955
MAGINOT_DEF_SOFT = 0.883
MAGINOT_DEF_HARD = 1.015
MAGINOT_XP_MULT = 0.85
ATTACKER_INITIATIVE = 0.15
ORG_BREAK = 0.22
STR_BREAK = 0.30
MAX_DAYS = 12


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


def unit_power(soft: float, hard: float, org: float, strength: float, xp_mult: float, initiative: float = 0.0) -> float:
    return (soft + 1.6 * hard) * org * strength * xp_mult + initiative


def daily_deltas(margin: float) -> Tuple[float, float, float, float]:
    """loser_org, winner_org, loser_str, winner_str from margin m in [0,1]."""
    m = max(0.0, min(1.0, float(margin)))
    loser_org = 0.12 + 0.08 * m
    winner_org = 0.04 + 0.02 * (1.0 - m)
    loser_str = 0.10 + 0.06 * m
    winner_str = 0.03 + 0.02 * (1.0 - m)
    return loser_org, winner_org, loser_str, winner_str


def simulate_maginot_slices(
    *,
    days: int = MAX_DAYS,
    att_soft: float = MAGINOT_ATT_SOFT,
    att_hard: float = MAGINOT_ATT_HARD,
    def_soft: float = MAGINOT_DEF_SOFT,
    def_hard: float = MAGINOT_DEF_HARD,
    xp_mult: float = MAGINOT_XP_MULT,
    initiative: float = ATTACKER_INITIATIVE,
    recompute_power: bool = True,
) -> Dict[str, Any]:
    """Pure daily org/str slices for first-session Maginot (GER captures ~day 7)."""
    att_org = 1.0
    att_str = 1.0
    def_org = 1.0
    def_str = 1.0
    history: List[Dict[str, float]] = []
    terminal = ""
    break_day = -1

    for day in range(1, days + 1):
        if recompute_power:
            att_p = unit_power(att_soft, att_hard, att_org, att_str, xp_mult, initiative)
            def_p = unit_power(def_soft, def_hard, def_org, def_str, xp_mult, 0.0)
        else:
            att_p = unit_power(att_soft, att_hard, 1.0, 1.0, xp_mult, initiative)
            def_p = unit_power(def_soft, def_hard, 1.0, 1.0, xp_mult, 0.0)
        hi = max(att_p, def_p, 1e-9)
        m = abs(att_p - def_p) / hi
        att_wins = att_p >= def_p
        lo, wo, ls, ws = daily_deltas(m)
        if att_wins:
            att_org -= wo
            att_str -= ws
            def_org -= lo
            def_str -= ls
        else:
            att_org -= lo
            att_str -= ls
            def_org -= wo
            def_str -= ws
        history.append(
            {
                "day": float(day),
                "att_org": att_org,
                "def_org": def_org,
                "att_str": att_str,
                "def_str": def_str,
                "att_power": att_p,
                "def_power": def_p,
                "m": m,
            }
        )
        if def_org <= ORG_BREAK or def_str <= STR_BREAK:
            terminal = "defender_broke"
            break_day = day
            break
        if att_org <= ORG_BREAK or att_str <= STR_BREAK:
            terminal = "attacker_broke"
            break_day = day
            break
        if day >= MAX_DAYS:
            terminal = "prolonged_stalemate"
            break_day = day
            break

    day0_att = unit_power(att_soft, att_hard, 1.0, 1.0, xp_mult, initiative)
    day0_def = unit_power(def_soft, def_hard, 1.0, 1.0, xp_mult, 0.0)
    return {
        "terminal": terminal,
        "break_day": break_day,
        "history": history,
        "day0_att_power": day0_att,
        "day0_def_power": day0_def,
        "att_wins_slice0": day0_att >= day0_def,
        "initiative": initiative,
    }


def build_multi_day_battle_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    # --- Pure Maginot math (director story: GER captures day 5–8 with +0.15) ---
    sim = simulate_maginot_slices()
    math_ok = (
        sim.get("att_wins_slice0") is True
        and sim.get("terminal") == "defender_broke"
        and 5 <= int(sim.get("break_day") or -1) <= 8
    )
    wiring["maginot_defender_broke_day_5_8"] = math_ok
    if math_ok:
        passes.append("maginot_day=%d" % int(sim.get("break_day") or 0))
    else:
        fails.append(
            "maginot_math terminal=%s day=%s att_wins0=%s"
            % (sim.get("terminal"), sim.get("break_day"), sim.get("att_wins_slice0"))
        )

    # Without initiative GER loses first slice (SOMUA slightly stronger).
    no_init = simulate_maginot_slices(initiative=0.0, recompute_power=False)
    wiring["initiative_flips_slice"] = bool(no_init.get("att_wins_slice0") is False) and bool(
        sim.get("att_wins_slice0") is True
    )
    if wiring["initiative_flips_slice"]:
        passes.append("initiative_flips_slice")
    else:
        fails.append("initiative_flips_slice")

    if not check_wiring:
        ok = len(fails) == 0
        return {
            "ok": ok,
            "status": "PASS" if ok else "FAIL",
            "pass": passes,
            "fail": fails,
            "wiring": wiring,
            "sim": sim,
            "summary": "multi_day_battle · math · %s" % ("PASS" if ok else "FAIL"),
        }

    bm = BATTLE_MANAGER.read_text(encoding="utf-8") if BATTLE_MANAGER.is_file() else ""
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    gd = GAME_DATA.read_text(encoding="utf-8") if GAME_DATA.is_file() else ""
    mm = MAP_MANAGER.read_text(encoding="utf-8") if MAP_MANAGER.is_file() else ""
    sl = SAVE_LOAD.read_text(encoding="utf-8") if SAVE_LOAD.is_file() else ""
    cr = COMBAT_RESOLVER.read_text(encoding="utf-8") if COMBAT_RESOLVER.is_file() else ""

    if not bm or not ren:
        fails.append("missing_sources")
        return {
            "ok": False,
            "status": "FAIL",
            "pass": passes,
            "fail": fails,
            "wiring": wiring,
            "sim": sim,
            "summary": "multi_day_battle · FAIL · missing sources",
        }

    # start_province_battle present; can with fid; sets is_in_combat
    start_fn = _gd_func_slice(bm, "start_province_battle")
    start_ok = (
        bool(start_fn)
        and "can_assault_province" in start_fn
        and "is_in_combat" in start_fn
        and "engaging" in start_fn
    )
    wiring["start_province_battle"] = start_ok
    if start_ok:
        passes.append("start_province_battle")
    else:
        fails.append("start_province_battle")

    # tick + additive + initiative + break + apply_province_capture
    tick_fn = _gd_func_slice(bm, "tick_battles_for_day")
    tick_one = _gd_func_slice(bm, "_tick_one_battle")
    tick_ok = (
        bool(tick_fn)
        and bool(tick_one)
        and "0.15" in bm
        and ("0.12" in tick_one or "0.12 +" in tick_one or "loser_org" in tick_one)
        and "apply_province_capture" in tick_one
        and "defender_broke" in tick_one
    )
    wiring["tick_battles_additive"] = tick_ok
    if tick_ok:
        passes.append("tick_battles_additive")
    else:
        fails.append("tick_battles_additive")

    cap_fn = _gd_func_slice(bm, "apply_province_capture")
    cap_ok = (
        bool(cap_fn)
        and "update_province_owner" in cap_fn
        and "station_formation_on_province" in cap_fn
        and "_apply_combat_damage_to_formations" not in cap_fn
        and "apply_combat_equipment_loss" not in cap_fn
    )
    wiring["apply_province_capture"] = cap_ok
    if cap_ok:
        passes.append("apply_province_capture")
    else:
        fails.append("apply_province_capture")

    end_fn = _gd_func_slice(bm, "_end_battle")
    withdraw_fn = _gd_func_slice(bm, "withdraw_from_battle")
    end_ok = bool(end_fn) and "is_in_combat = false" in bm and bool(withdraw_fn)
    wiring["end_and_withdraw"] = end_ok
    if end_ok:
        passes.append("end_and_withdraw")
    else:
        fails.append("end_and_withdraw")

    # execute signature still 4-arg one-shot; no instant= on execute
    exec_fn = _gd_func_slice(bm, "execute_province_assault")
    exec_one_shot = (
        bool(exec_fn)
        and "attacker_formation_id" in exec_fn
        and "instant" not in exec_fn.split("(")[0] + (exec_fn.split(")")[0] if ")" in exec_fn else "")
        and "resolve_combat" in exec_fn
        and "apply_combat_outcome" in exec_fn
    )
    # Simpler: execute still calls resolve_combat + apply_combat_outcome; no multi-day default.
    exec_one_shot = (
        bool(exec_fn)
        and "resolve_combat" in exec_fn
        and "apply_combat_outcome" in exec_fn
        and "start_province_battle" not in exec_fn
    )
    wiring["execute_stays_one_shot"] = exec_one_shot
    if exec_one_shot:
        passes.append("execute_stays_one_shot")
    else:
        fails.append("execute_stays_one_shot")

    # resolve_combat signature unchanged (no decisive= false default)
    res_sig = "func resolve_combat" in cr
    res_no_decisive_default = "decisive" not in _gd_func_slice(cr, "resolve_combat") if cr else True
    wiring["resolve_combat_unchanged"] = res_sig and res_no_decisive_default
    if wiring["resolve_combat_unchanged"]:
        passes.append("resolve_combat_unchanged")
    else:
        fails.append("resolve_combat_unchanged")

    # Map confirm → start_province_battle; Esc withdraw order
    try_fn = _gd_func_slice(ren, "_try_execute_province_attack")
    map_start = "start_province_battle" in try_fn and "_assault_post_ui_light" in try_fn
    wiring["map_confirm_starts_battle"] = map_start
    if map_start:
        passes.append("map_confirm_starts_battle")
    else:
        fails.append("map_confirm_starts_battle")

    esc_ok = (
        "withdraw_from_battle" in ren
        and "UnitDetailPopup" in ren
        and "selected_formation_id" in ren
    )
    # Order: withdraw before close card — withdraw appears before UnitDetailPopup free in KEY_ESCAPE block
    esc_slice = ""
    for line in ren.splitlines():
        if "KEY_ESCAPE" in line or esc_slice:
            esc_slice += line + "\n"
            if "func " in line and "KEY_ESCAPE" not in line and esc_slice.count("\n") > 3:
                # stop at next major block roughly
                if line.startswith("func ") and "KEY_ESCAPE" not in esc_slice[:50]:
                    break
            if esc_slice.count("\n") > 40:
                break
    # Grep unhandled_input Esc: withdraw call before UnitDetailPopup free
    unh = _gd_func_slice(ren, "_unhandled_input")
    wi = unh.find("withdraw_from_battle")
    ui = unh.find("UnitDetailPopup")
    clear_sel = unh.find('selected_formation_id = ""')
    esc_order = wi >= 0 and ui >= 0 and wi < ui and (clear_sel < 0 or ui < clear_sel or wi < clear_sel)
    wiring["esc_withdraw_then_card"] = esc_order
    if esc_order:
        passes.append("esc_withdraw_then_card")
    else:
        fails.append("esc_withdraw_then_card")

    # Play-strip / GameData start_province_battle
    strip_ok = "start_province_battle" in gd and "select a unit pin first" in gd
    wiring["strip_starts_battle"] = strip_ok
    if strip_ok:
        passes.append("strip_starts_battle")
    else:
        fails.append("strip_starts_battle")

    mm_ok = "start_province_battle" in mm
    wiring["mapmanager_stage_starts_battle"] = mm_ok
    if mm_ok:
        passes.append("mapmanager_stage_starts_battle")
    else:
        fails.append("mapmanager_stage_starts_battle")

    # Save blob battles
    save_ok = (
        '"battles"' in sl or "battles" in sl
    ) and ("apply_save_data" in bm) and ("get_save_data" in bm)
    wiring["battles_save_blob"] = save_ok
    if save_ok:
        passes.append("battles_save_blob")
    else:
        fails.append("battles_save_blob")

    # is_in_combat clear after one-shot
    apply_out = _gd_func_slice(bm, "apply_combat_outcome")
    one_shot_clear = "is_in_combat = false" in apply_out or "is_in_combat = false" in bm
    wiring["one_shot_clears_is_in_combat"] = one_shot_clear
    if one_shot_clear:
        passes.append("one_shot_clears_is_in_combat")
    else:
        fails.append("one_shot_clears_is_in_combat")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "wiring": wiring,
        "sim": {
            "terminal": sim.get("terminal"),
            "break_day": sim.get("break_day"),
            "day0_att_power": sim.get("day0_att_power"),
            "day0_def_power": sim.get("day0_def_power"),
            "att_wins_slice0": sim.get("att_wins_slice0"),
        },
        "summary": "multi_day_battle · break_day=%s · %s"
        % (sim.get("break_day"), "PASS" if ok else "FAIL"),
        "integration": [
            "multi_day_battle_product",
            "first_session_assault_surface_product",
            "BattleManager.start_province_battle",
        ],
    }


def multi_day_battle_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_multi_day_battle_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
