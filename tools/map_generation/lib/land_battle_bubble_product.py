"""Land battle bubble — grep/wiring gate for LandBattleBubbleLayer.

HOI-like org plate (not 3D soldiers). Director instances from MapRenderer.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
LAYER_GD = ROOT / "scripts" / "map" / "LandBattleBubbleLayer.gd"
SFX_GD = ROOT / "scripts" / "audio" / "LandBattleSfx.gd"
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


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


def _draw_path(src: str) -> str:
    chunks = [_gd_func_slice(src, "_draw"), _gd_func_slice(src, "_draw_org_plate")]
    return "\n".join(c for c in chunks if c)


def build_land_battle_bubble_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}
    src = LAYER_GD.read_text(encoding="utf-8") if LAYER_GD.is_file() else ""
    sfx = SFX_GD.read_text(encoding="utf-8") if SFX_GD.is_file() else ""
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""

    if not src:
        fails.append("missing_layer")
        return {
            "ok": False,
            "status": "FAIL",
            "pass": passes,
            "fail": fails,
            "wiring": wiring,
            "summary": "land_battle_bubble · FAIL · missing LandBattleBubbleLayer",
        }

    class_ok = "class_name LandBattleBubbleLayer" in src
    wiring["class_name"] = class_ok
    if class_ok:
        passes.append("class_name")
    else:
        fails.append("class_name")

    setup_ok = "func setup" in src
    wiring["setup"] = setup_ok
    if setup_ok:
        passes.append("setup")
    else:
        fails.append("setup")

    set_ok = "func set_battles" in src
    wiring["set_battles"] = set_ok
    if set_ok:
        passes.append("set_battles")
    else:
        fails.append("set_battles")

    clear_ok = "func clear_battles" in src
    wiring["clear_battles"] = clear_ok
    if clear_ok:
        passes.append("clear_battles")
    else:
        fails.append("clear_battles")

    draw = _draw_path(src)
    org_in_draw = bool(draw) and ("OrgBar" in draw or "att_org" in draw)
    wiring["org_in_draw"] = org_in_draw
    if org_in_draw:
        passes.append("org_in_draw")
    else:
        fails.append("org_in_draw")

    no_inspector = "show_info_panel" not in src and "inspector" not in src.lower()
    wiring["no_inspector"] = no_inspector
    if no_inspector:
        passes.append("no_inspector")
    else:
        fails.append("no_inspector")

    z_ok = "z_index = Z_BUBBLE" in src or "z_index = 25" in src
    wiring["z_high"] = z_ok
    if z_ok:
        passes.append("z_high")
    else:
        fails.append("z_high")

    if check_wiring:
        sfx_keys_ok = bool(sfx) and all(
            token in sfx
            for token in (
                "KEY_ORDER_CONFIRM",
                "KEY_DAILY_CLASH",
                "KEY_CAPTURE",
                "KEY_BOUNCE",
            )
        )
        wiring["sfx_aliases"] = sfx_keys_ok
        if sfx_keys_ok:
            passes.append("sfx_aliases")
        else:
            fails.append("sfx_aliases")

        # Existing MapRenderer keys Director must reuse (do not invent new _SFX_PATHS).
        existing = ('"confirm"', '"map"', '"achievement"', '"error"')
        paths_ok = bool(ren) and all(k in ren for k in existing) and "_SFX_PATHS" in ren
        wiring["renderer_sfx_keys"] = paths_ok
        if paths_ok:
            passes.append("renderer_sfx_keys")
        else:
            fails.append("renderer_sfx_keys")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "land_battle_bubble · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "hoi_bubble_org_bars_day_chip_no_3d",
        "sfx_director": {
            "order_confirm": "confirm",
            "daily_clash": "map",
            "capture": "achievement",
            "bounce": "error",
        },
        "integration": [
            "land_battle_bubble_product",
            "unit_multi_day_battle_product",
        ],
    }


def land_battle_bubble_integrity(*, check_wiring: bool = True) -> Dict[str, Any]:
    p = build_land_battle_bubble_product(check_wiring=check_wiring)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
