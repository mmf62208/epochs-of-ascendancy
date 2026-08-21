"""Unit counter (OOB pin) LOD policy — mirrors MapZoomLOD.show_unit_counters.

Strategic culls chips so capitals/fronts stay clickable. Operational/tactical = full chips.
Master toggle off hides all zoom tiers. Pin-first pick applies only to visible chips.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
LOD_GD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"

# Match MapZoomLOD.Tier enum order
TIER_STRATEGIC = 0
TIER_OPERATIONAL = 1
TIER_TACTICAL = 2


def show_unit_counters(tier: int, master_enabled: bool = True) -> bool:
    if not master_enabled:
        return False
    return int(tier) != TIER_STRATEGIC


def unit_counter_compact(tier: int) -> bool:
    return int(tier) == TIER_STRATEGIC


def build_map_unit_counter_lod_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    if show_unit_counters(TIER_STRATEGIC, True) is False:
        passes.append("strategic_culls")
    else:
        fails.append("strategic_still_shows")
    if unit_counter_compact(TIER_STRATEGIC) and not unit_counter_compact(
        TIER_OPERATIONAL
    ):
        passes.append("strategic_is_compact")
    else:
        fails.append("compact_policy")
    if show_unit_counters(TIER_OPERATIONAL, True) is True:
        passes.append("operational_shows")
    else:
        fails.append("operational_hides")
    if show_unit_counters(TIER_TACTICAL, True) is True:
        passes.append("tactical_shows")
    else:
        fails.append("tactical_hides")
    if show_unit_counters(TIER_TACTICAL, False) is False:
        passes.append("master_off")
    else:
        fails.append("master_off_ignored")

    lod = LOD_GD.read_text(encoding="utf-8") if LOD_GD.is_file() else ""
    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    if "func show_unit_counters" in lod:
        passes.append("lod_fn")
    else:
        fails.append("missing_lod_fn")
    if "func unit_counter_compact" in lod:
        passes.append("lod_compact_fn")
    else:
        fails.append("missing_compact_fn")
    # Slice show_unit_counters only — other LOD helpers still hide chrome at strategic.
    lod_fn_slice = ""
    _needle = "func show_unit_counters"
    _i = lod.find(_needle)
    if _i >= 0:
        _lines = lod[_i:].splitlines()
        _out = [_lines[0]]
        for _ln in _lines[1:]:
            if _ln.startswith("static func ") or _ln.startswith("func "):
                break
            _out.append(_ln)
        lod_fn_slice = "\n".join(_out)
    if "return t != Tier.STRATEGIC" in lod_fn_slice:
        passes.append("lod_strategic_cull")
    elif "return true" in lod_fn_slice:
        fails.append("lod_still_shows_strategic")
    else:
        fails.append("lod_missing_strategic_cull")
    if "func toggle_unit_counters" in ren and "toggle_unit_counters()" in ren:
        passes.append("renderer_toggle")
    else:
        fails.append("missing_toggle")
    if "Shift+U" in ren or "shift_pressed" in ren and "toggle_unit_counters" in ren:
        passes.append("hotkey_shift_u")
    else:
        fails.append("missing_hotkey")
    if "func _sync_unit_counter_visibility" in ren:
        passes.append("sync_vis")
    else:
        fails.append("missing_sync_vis")
    pick_fn = ""
    _pn = "func _pick_unit_formation_at_world"
    _pi = ren.find(_pn)
    if _pi >= 0:
        _plines = ren[_pi:].splitlines()
        _pout = [_plines[0]]
        for _ln in _plines[1:]:
            if _ln.startswith("func "):
                break
            _pout.append(_ln)
        pick_fn = "\n".join(_pout)
    if "not counter.visible" in pick_fn:
        passes.append("hidden_pins_skip_hex")
    else:
        fails.append("hidden_pins_steal_hex")
    if "_unit_counters_want_visible" in pick_fn:
        passes.append("strategic_pick_skip")
    else:
        fails.append("strategic_pick_still_hits")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "pass": passes,
        "fail": fails,
        "summary": "unit_counter_lod · %s" % ("PASS" if ok else "FAIL"),
        "policy": "strategic_cull_operational_full_master_toggle_U_hidden_pins_skip",
    }
