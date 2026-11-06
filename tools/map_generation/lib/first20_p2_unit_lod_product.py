"""FIRST20-P2 F6 — start-zoom unit-counter LOD bands (pure).

Ink §F6: z<0.6 stack chips only; 0.6≤z<1.2 chip+letter; z≥1.2 full cards
with at most two 3 px bars. Own selected stack stays full. Default
"Division 0" names hide below z 1.2. Country labels sit above chips.

SOT: scripts/map/MapZoomLOD.gd + MapRenderer apply path.
Does not change strategic cull / Europe Home floor (map_unit_counter_lod_product).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
LOD_GD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
LABELS = ROOT / "scripts" / "map" / "MapPoliticalLabelsLayer.gd"

UNIT_LOD_STACK_MAX_ZOOM = 0.6
UNIT_LOD_FULL_MIN_ZOOM = 1.2
UNIT_LOD_STACK_CHIP_W = 22.0
UNIT_LOD_STACK_CHIP_H = 16.0
UNIT_LOD_STACK_COUNT_PX = 11
UNIT_LOD_FLEET_ANCHOR_PX = 10.0
UNIT_LOD_FULL_BAR_PX = 3.0
UNIT_LOD_FULL_BAR_MAX = 2
UNIT_LOD_CHIP_UNDER_LABEL_Z = 16
NATION_LABEL_Z = 18


def unit_lod_band(z: float) -> str:
    zz = float(z)
    if zz < UNIT_LOD_STACK_MAX_ZOOM:
        return "stack"
    if zz < UNIT_LOD_FULL_MIN_ZOOM:
        return "mid"
    return "full"


def is_default_unit_name(name: str) -> bool:
    s = str(name or "").strip()
    if not s:
        return True
    lower = s.lower()
    if lower.startswith("division "):
        rest = lower[9:].strip()
        return rest.isdigit()
    return False


def hide_default_unit_name(z: float, name: str, selected_own: bool = False) -> bool:
    if selected_own:
        return False
    if float(z) >= UNIT_LOD_FULL_MIN_ZOOM:
        return False
    return is_default_unit_name(name)


def unit_lod_mid_letter(letter: str) -> str:
    L = str(letter or "I").strip().upper() or "I"
    if L in ("A", "H"):
        return "A"
    if L == "L":
        return "L"
    return "I"


def unit_lod_policy(
    z: float,
    selected_own: bool = False,
    is_fleet: bool = False,
) -> Dict[str, Any]:
    band = unit_lod_band(z)
    full = bool(selected_own) or band == "full"
    if full:
        band_out = "full"
    else:
        band_out = band
    stack = band_out == "stack"
    mid = band_out == "mid"
    return {
        "band": band_out,
        "show_bars": full,
        "bar_count": UNIT_LOD_FULL_BAR_MAX if full else 0,
        "bar_px": UNIT_LOD_FULL_BAR_PX,
        "show_letter": full or mid,
        "show_name": full,
        "show_nato_glyph": full or mid,
        "stack_chip": stack and not is_fleet,
        "chip_w": UNIT_LOD_STACK_CHIP_W if stack else 44.0,
        "chip_h": UNIT_LOD_STACK_CHIP_H if stack else 40.0,
        "count_px": UNIT_LOD_STACK_COUNT_PX,
        "fleet_anchor": bool(is_fleet) and stack,
        "fleet_anchor_px": UNIT_LOD_FLEET_ANCHOR_PX,
        "chip_z": 28 if full else UNIT_LOD_CHIP_UNDER_LABEL_Z,
        "label_z": NATION_LABEL_Z,
    }


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


def build_first20_p2_unit_lod_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []

    if unit_lod_band(0.39) == "stack" and unit_lod_band(0.59) == "stack":
        passes.append("start_zoom_stack")
    else:
        fails.append("start_zoom_stack")
    if unit_lod_band(0.6) == "mid" and unit_lod_band(1.19) == "mid":
        passes.append("mid_letter_band")
    else:
        fails.append("mid_letter_band")
    if unit_lod_band(1.2) == "full" and unit_lod_band(2.4) == "full":
        passes.append("full_card_band")
    else:
        fails.append("full_card_band")
    if unit_lod_band(UNIT_LOD_STACK_MAX_ZOOM) != "stack":
        passes.append("stack_max_is_exclusive")
    else:
        fails.append("stack_max_is_exclusive")

    pol_start = unit_lod_policy(0.4)
    if (
        pol_start["band"] == "stack"
        and pol_start["show_bars"] is False
        and pol_start["stack_chip"] is True
        and pol_start["chip_w"] == 22.0
        and pol_start["chip_h"] == 16.0
        and pol_start["chip_z"] < pol_start["label_z"]
    ):
        passes.append("start_stack_chip_under_labels")
    else:
        fails.append("start_stack_chip_under_labels")

    pol_sel = unit_lod_policy(0.4, selected_own=True)
    if pol_sel["band"] == "full" and pol_sel["show_bars"] is True:
        passes.append("selected_own_full_at_start")
    else:
        fails.append("selected_own_full_at_start")

    pol_fleet = unit_lod_policy(0.35, is_fleet=True)
    if pol_fleet["fleet_anchor"] is True and pol_fleet["stack_chip"] is False:
        passes.append("fleet_anchor_at_start")
    else:
        fails.append("fleet_anchor_at_start")

    pol_mid = unit_lod_policy(0.8)
    if (
        pol_mid["band"] == "mid"
        and pol_mid["show_letter"] is True
        and pol_mid["show_bars"] is False
    ):
        passes.append("mid_letter_no_bars")
    else:
        fails.append("mid_letter_no_bars")

    pol_full = unit_lod_policy(1.3)
    if (
        pol_full["show_bars"] is True
        and int(pol_full["bar_count"]) == 2
        and float(pol_full["bar_px"]) == 3.0
    ):
        passes.append("full_two_3px_bars")
    else:
        fails.append("full_two_3px_bars")

    if hide_default_unit_name(0.8, "Division 0") and not hide_default_unit_name(
        1.2, "Division 0"
    ):
        passes.append("hide_division_0_below_full")
    else:
        fails.append("hide_division_0_below_full")
    if not hide_default_unit_name(0.4, "Division 0", selected_own=True):
        passes.append("selected_keeps_default_name")
    else:
        fails.append("selected_keeps_default_name")
    if not hide_default_unit_name(0.8, "1. Infanterie"):
        passes.append("real_names_stay")
    else:
        fails.append("real_names_stay")
    if unit_lod_mid_letter("H") == "A" and unit_lod_mid_letter("G") == "I":
        passes.append("mid_letter_ial")
    else:
        fails.append("mid_letter_ial")

    lod = LOD_GD.read_text(encoding="utf-8") if LOD_GD.is_file() else ""
    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    labels = LABELS.read_text(encoding="utf-8") if LABELS.is_file() else ""
    if not lod:
        fails.append("missing_lod_gd")
    if not ren:
        fails.append("missing_renderer")

    if "UNIT_LOD_STACK_MAX_ZOOM" in lod and "0.6" in lod:
        passes.append("lod_stack_const")
    else:
        fails.append("lod_stack_const")
    if "UNIT_LOD_FULL_MIN_ZOOM" in lod and "1.2" in lod:
        passes.append("lod_full_const")
    else:
        fails.append("lod_full_const")
    if "func unit_lod_band" in lod and "func unit_lod_policy" in lod:
        passes.append("lod_policy_fn")
    else:
        fails.append("lod_policy_fn")
    if "func is_default_unit_name" in lod:
        passes.append("lod_default_name_fn")
    else:
        fails.append("lod_default_name_fn")

    apply_fn = _gd_func_slice(ren, "_apply_unit_lod_to_icon")
    sync_fn = _gd_func_slice(ren, "_sync_unit_counter_lod")
    paint_fn = _gd_func_slice(ren, "_sync_unit_counter_paint")
    if apply_fn and "unit_lod_policy" in apply_fn:
        passes.append("renderer_applies_policy")
    else:
        fails.append("renderer_applies_policy")
    if sync_fn and "_apply_unit_lod_to_icon" in sync_fn:
        passes.append("renderer_syncs_lod")
    else:
        fails.append("renderer_syncs_lod")
    if "_sync_unit_counter_lod" in paint_fn:
        passes.append("paint_calls_lod")
    else:
        fails.append("paint_calls_lod")
    if "eoa_stack_n" in ren:
        passes.append("stack_count_meta")
    else:
        fails.append("stack_count_meta")
    bars_fn = _gd_func_slice(ren, "_make_unit_stat_bars")
    if "3)" in bars_fn.replace(" ", "") or "3.0)" in bars_fn.replace(" ", ""):
        if "OrgBar" in bars_fn and "StrBar" in bars_fn:
            passes.append("stat_bars_3px")
        else:
            fails.append("stat_bars_3px")
    else:
        fails.append("stat_bars_3px")
    if "NATION_LABEL_Z := 18" in labels or "NATION_LABEL_Z = 18" in labels:
        passes.append("nation_label_z_18")
    else:
        fails.append("nation_label_z_18")
    if "UNIT_LOD_CHIP_UNDER_LABEL_Z" in lod and "16" in lod:
        passes.append("chip_under_label_z")
    else:
        fails.append("chip_under_label_z")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "FIRST20-P2 F6 unit LOD · %s · fail=%s"
        % ("PASS" if ok else "FAIL", ",".join(fails) or "none"),
        "thresholds": {
            "stack_max": UNIT_LOD_STACK_MAX_ZOOM,
            "full_min": UNIT_LOD_FULL_MIN_ZOOM,
        },
        "integration": [
            "first20_p2_unit_lod_product",
            "MapZoomLOD.unit_lod_band",
            "MapRenderer._sync_unit_counter_lod",
        ],
    }


def first20_p2_unit_lod_integrity() -> Dict[str, Any]:
    p = build_first20_p2_unit_lod_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
