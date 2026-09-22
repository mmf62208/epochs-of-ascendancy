"""MapMode toolbar active-chip highlight — exclusive pressed state (pure).

SOT: scripts/ui/map/MapModeToolbar.gd
First-session: F2 / F9 family / toolbar click must leave only the live mode
chip pressed. Political must idle when Strain/Terrain/etc is active.

Pure mapping: active-mode id → {mode: pressed}. Wiring grep locks ButtonGroup
+ set_pressed_no_signal + idle restyle. Does not touch Esc / Command Center.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
TOOLBAR_GD = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"

# Keep in lockstep with MapModeToolbar.MODES.
TOOLBAR_MODES: List[str] = [
    "political",
    "strain",
    "vitality",
    "development",
    "supply",
    "munitions",
    "loyalty",
    "infra",
    "naval",
    "weather",
    "resources",
    "states",
    "terrain",
]


def _gd_func_slice(src: str, func_name: str) -> str:
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


def normalize_toolbar_mode(mode: str) -> str:
    m = str(mode or "").strip().lower()
    return m if m in TOOLBAR_MODES else "political"


def toolbar_pressed_state(
    active_mode: str,
    modes: Optional[Sequence[str]] = None,
) -> Dict[str, bool]:
    """Active-mode id → exclusive button pressed map (exactly one True)."""
    keys = list(modes) if modes is not None else list(TOOLBAR_MODES)
    live = normalize_toolbar_mode(active_mode)
    if live not in keys:
        live = "political" if "political" in keys else (keys[0] if keys else "political")
    return {str(k): (str(k) == live) for k in keys}


def pressed_mode_id(state: Mapping[str, Any]) -> str:
    selected = [str(k) for k, v in state.items() if bool(v)]
    if len(selected) == 1:
        return selected[0]
    return ""


def build_map_mode_toolbar_active_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    strain = toolbar_pressed_state("strain")
    if strain.get("strain") is True and strain.get("political") is False:
        if sum(1 for v in strain.values() if v) == 1:
            passes.append("f2_strain_exclusive")
        else:
            fails.append("f2_strain_not_exclusive")
    else:
        fails.append("f2_strain_political_still_pressed")

    terrain = toolbar_pressed_state("terrain")
    if terrain.get("terrain") is True and terrain.get("political") is False:
        passes.append("terrain_clears_political")
    else:
        fails.append("terrain_political_still_pressed")

    resources = toolbar_pressed_state("resources")
    if resources.get("resources") is True and not resources.get("political"):
        passes.append("f9_resources_exclusive")
    else:
        fails.append("f9_resources_political_still_pressed")

    unknown = toolbar_pressed_state("not-a-mode")
    if unknown.get("political") is True and sum(1 for v in unknown.values() if v) == 1:
        passes.append("unknown_falls_back_political")
    else:
        fails.append("unknown_fallback")

    if pressed_mode_id(toolbar_pressed_state("vitality")) == "vitality":
        passes.append("active_id_roundtrip")
    else:
        fails.append("active_id_roundtrip")

    tb = TOOLBAR_GD.read_text(encoding="utf-8") if TOOLBAR_GD.is_file() else ""
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    if not tb:
        fails.append("missing_toolbar")
    if not ren:
        fails.append("missing_renderer")

    build_fn = _gd_func_slice(tb, "_build_ui")
    set_fn = _gd_func_slice(tb, "set_mode")
    sync_fn = _gd_func_slice(tb, "_sync_mode_chip_pressed")
    style_fn = _gd_func_slice(tb, "_apply_mode_chip_idle_style")
    renderer_set = _gd_func_slice(ren, "set_map_mode")
    renderer_sync = _gd_func_slice(ren, "_sync_mapmode_toolbar")

    wiring["button_group"] = (
        "ButtonGroup" in tb
        and "allow_unpress = false" in tb
        and "button_group = _mode_group" in build_fn
    )
    wiring["toggle_mode"] = "toggle_mode = true" in build_fn
    wiring["set_pressed_no_signal"] = (
        "set_pressed_no_signal" in sync_fn and "_sync_mode_chip_pressed" in set_fn
    )
    wiring["idle_restyle"] = (
        bool(style_fn)
        and "modulate" in style_fn
        and "_apply_mode_chip_idle_style" in sync_fn
    )
    wiring["pressed_state_api"] = "func get_mode_pressed_state" in tb
    wiring["no_raw_button_pressed_assign"] = (
        "btn.button_pressed =" not in set_fn and "button_pressed =" not in sync_fn
    )
    wiring["renderer_syncs_toolbar"] = (
        "_sync_mapmode_toolbar()" in renderer_set
        and 'call("set_mode", current_map_mode, false)' in renderer_sync
    )
    for mode in TOOLBAR_MODES:
        if '"%s"' % mode not in tb:
            wiring["modes_in_sot"] = False
            break
    else:
        wiring["modes_in_sot"] = True

    for key, ok in wiring.items():
        if ok:
            passes.append("wire_%s" % key)
        else:
            fails.append("wire_%s" % key)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "modes": list(TOOLBAR_MODES),
        "summary": "MapMode toolbar active chip · %s · fail=%s"
        % ("PASS" if ok else "FAIL", ",".join(fails) or "none"),
        "integration": [
            "map_mode_toolbar_active_product",
            "MapModeToolbar.set_mode",
            "MapModeToolbar._sync_mode_chip_pressed",
            "MapRenderer._sync_mapmode_toolbar",
        ],
    }


def map_mode_toolbar_active_integrity() -> Dict[str, Any]:
    p = build_map_mode_toolbar_active_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
