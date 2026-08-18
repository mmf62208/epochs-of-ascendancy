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

GER_FRONT = 710173
FRA_FRONT = 710739


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
            "summary": "living_unit_order_loop · FAIL · missing MapRenderer",
        }

    park = _slice(ren, "ensure_playable_front_chips")
    park_ok = (
        bool(park)
        and str(GER_FRONT) in park
        and str(FRA_FRONT) in park
        and "stationed_province_id" in park
        and "_update_unit_icons_for_test" in park
    )
    wiring["park_maginot"] = park_ok
    (passes if park_ok else fails).append("park_maginot")

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
    g_cheap = "KEY_G" in ren and "_toast_easy_unit_orders" in g_slice
    g_no_bfs = "highlight_corridor_capital_to_selected" not in g_slice
    wiring["g_toast_only"] = g_cheap and g_no_bfs
    (passes if wiring["g_toast_only"] else fails).append("g_toast_only")

    mv_ok = "func enqueue_own_land_march" in mv
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
        and "enqueue_own_land_march" in harness
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
