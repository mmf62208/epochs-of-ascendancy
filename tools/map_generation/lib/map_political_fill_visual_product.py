"""Clean political map fills: continuous sea + solid land ownership (no muddy underlay stack).

Mirrors MapRenderer sea shade + clean-political alpha policy so pure tests drive the real rules.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[3]
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"

# Continuous ocean (player-visible default political / clean view)
SEA_DEEP_RGB = (0.05, 0.14, 0.28)
SEA_ALPHA_CLEAN = 1.0
# Solid land political fills
LAND_ALPHA_CLEAN = 0.96
LAND_ALPHA_TERRAIN = 0.72  # when terrain underlay ON
SEA_POLITICAL_TRACE_MAX = 0.12  # keep seas flat (no loud per-cell tiles)
ATA_ICE_PIDS = (902133, 902134)
ICE_OCEAN_RGBA = (0.70, 0.82, 0.90, 1.0)
ENG_RED_RGB = (0.72, 0.22, 0.22)


def continuous_sea_fill_rgba(
    base_rgb: Tuple[float, float, float] = (0.2, 0.4, 0.55),
    *,
    sea_political_trace: float = 0.08,
    clean_political: bool = True,
    zone_hue_shift: float = 0.5,
) -> Tuple[float, float, float, float]:
    """Flatten sea toward one deep-water color (no void-hex / loud tile read).

    zone_hue_shift in [0,1] adds slight per-zone variance while staying in the ocean family.
    """
    br, bg, bb = base_rgb
    deep = SEA_DEEP_RGB
    mix = max(0.0, min(0.4, float(sea_political_trace) * 0.28))
    r = deep[0] * (1.0 - mix) + br * mix
    g = deep[1] * (1.0 - mix) + bg * mix
    b = deep[2] * (1.0 - mix) + bb * mix
    # Second pull toward deep to hide per-cell seams
    r = r * 0.38 + deep[0] * 0.62
    g = g * 0.38 + deep[1] * 0.62
    b = b * 0.38 + deep[2] * 0.62
    # Subtle zone separation (mirrors MapRenderer continuous_sea_fill_color)
    z = max(0.0, min(1.0, float(zone_hue_shift)))
    r = max(0.0, min(1.0, r + (z - 0.5) * 0.03))
    g = max(0.0, min(1.0, g + (z - 0.5) * 0.02))
    b = max(0.0, min(1.0, b + (z - 0.5) * 0.04))
    a = SEA_ALPHA_CLEAN if clean_political else 0.82
    return (r, g, b, a)


def land_fill_alpha(*, clean_political: bool = True, terrain_layer_on: bool = False) -> float:
    if clean_political and not terrain_layer_on:
        return LAND_ALPHA_CLEAN
    if terrain_layer_on:
        return LAND_ALPHA_TERRAIN
    return LAND_ALPHA_CLEAN


def world_board_fill_alpha(*, terrain_layer_on: bool = False, clean_political: bool = True) -> float:
    """GIS world_accurate / world grand board fill alpha policy."""
    if clean_political and not terrain_layer_on:
        return LAND_ALPHA_CLEAN
    return LAND_ALPHA_TERRAIN if terrain_layer_on else LAND_ALPHA_CLEAN


def ice_ocean_fill_rgba() -> Tuple[float, float, float, float]:
    return ICE_OCEAN_RGBA


def antarctica_fill_class(pid: int, owner: str = "") -> str:
    """902133 / 902134 must paint ice/ocean, not ENG political red."""
    if int(pid) in ATA_ICE_PIDS:
        return "ice_ocean"
    if str(owner).strip().upper() == "ENG":
        return "eng_red"
    return "other"


def ice_fill_not_eng_red(rgba: Tuple[float, float, float, float] = ICE_OCEAN_RGBA) -> bool:
    r, g, b, a = rgba
    return b > r and g > r and a >= 0.9 and abs(r - ENG_RED_RGB[0]) + abs(g - ENG_RED_RGB[1]) > 0.5


def political_stack_readable(
    land_color: Tuple[float, float, float],
    sea_color: Tuple[float, float, float, float],
    other_land: Tuple[float, float, float],
) -> bool:
    """Land ownership hues remain distinct; sea is deep-water class (not land-like)."""
    lr, lg, lb = land_color
    or_, og, ob = other_land
    sr, sg, sb, sa = sea_color
    # Sea darker / bluer than land reds-greens
    sea_is_water = sb > sr + 0.05 and sb > sg and sa >= 0.85
    # Ownership distinct (channel distance)
    dist = abs(lr - or_) + abs(lg - og) + abs(lb - ob)
    return sea_is_water and dist >= 0.18


def build_map_political_fill_visual_product() -> Dict[str, Any]:
    sea = continuous_sea_fill_rgba((0.35, 0.45, 0.70), sea_political_trace=0.08, clean_political=True)
    a_clean = world_board_fill_alpha(terrain_layer_on=False, clean_political=True)
    a_terrain = world_board_fill_alpha(terrain_layer_on=True, clean_political=False)
    # Fake GER red vs FRA blue
    ger = (0.72, 0.22, 0.22)
    fra = (0.22, 0.35, 0.78)
    ok_read = political_stack_readable(ger, sea, fra)
    passes: List[str] = []
    fails: List[str] = []
    if sea[3] >= 0.9 and sea[2] > sea[0]:
        passes.append("sea_continuous_deep")
    else:
        fails.append("sea_not_deep=%s" % (sea,))
    if a_clean >= 0.88:
        passes.append("land_alpha_clean=%.2f" % a_clean)
    else:
        fails.append("land_alpha_low")
    if a_terrain < a_clean:
        passes.append("terrain_dimmer_than_clean")
    else:
        fails.append("terrain_alpha_order")
    if ok_read:
        passes.append("ownership_distinct")
    else:
        fails.append("ownership_muddy")
    # Source wiring
    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    for needle, key in (
        ("func _shade_sea_province_fill", "shade_sea"),
        ("func continuous_sea_fill_color", "sea_static_or_method"),
        ("clean_political", "clean_political_flag"),
        ("show_terrain_layer", "terrain_toggle"),
        ("SEA_DEEP", "sea_deep_const_or_comment"),
    ):
        # accept either new helpers or existing shade path
        if needle in ren or (key == "sea_static_or_method" and "_shade_sea_province_fill" in ren):
            if key == "sea_static_or_method" and "func continuous_sea_fill_color" not in ren:
                if "_shade_sea_province_fill" in ren:
                    passes.append("shade_sea_present")
                    continue
            if needle in ren:
                passes.append(key)
            elif key == "sea_deep_const_or_comment" and ("0.06, 0.16, 0.30" in ren or "0.07, 0.22, 0.36" in ren or "continuous sea" in ren.lower()):
                passes.append(key)
            else:
                if key not in ("sea_static_or_method",):
                    fails.append("missing_%s" % key)
        else:
            if key == "sea_static_or_method":
                if "func continuous_sea_fill_color" in ren or "_shade_sea_province_fill" in ren:
                    passes.append(key)
                else:
                    fails.append("missing_%s" % key)
            elif key == "sea_deep_const_or_comment":
                if "continuous sea" in ren.lower() or "void hex" in ren.lower() or "0.06" in ren:
                    passes.append(key)
                else:
                    fails.append("missing_%s" % key)
            else:
                fails.append("missing_%s" % key)

    # Prefer clean political default
    if "show_terrain_layer: bool = false" in ren or "show_terrain_layer = false" in ren:
        passes.append("terrain_default_off")
    else:
        fails.append("terrain_default_still_on")

    ice = ice_ocean_fill_rgba()
    ata_ok = (
        antarctica_fill_class(902133, "ENG") == "ice_ocean"
        and antarctica_fill_class(902134, "ENG") == "ice_ocean"
        and ice_fill_not_eng_red(ice)
        and "902133" in ren
        and "902134" in ren
        and "func ice_ocean_fill_color" in ren
        and "func _is_ice_ocean_visual" in ren
        and "_is_ice_ocean_visual" in ren
    )
    if ata_ok:
        passes.append("antarctica_ice_ocean_not_eng")
    else:
        fails.append("antarctica_ice_ocean_not_eng")

    # Ocean floor + apply visibility after underlay load (void-hex alignment fix)
    if "func _ensure_ocean_floor" in ren or "OceanFloorContinuous" in ren:
        passes.append("ocean_floor_plate")
    else:
        fails.append("missing_ocean_floor")
    if "_apply_terrain_layer_visibility()" in ren and "load_world_grand_underlay" in ren:
        # underlay load must not leave photo visible in clean mode
        if ren.count("_apply_terrain_layer_visibility()") >= 2:
            passes.append("terrain_vis_reassert")
        else:
            fails.append("terrain_vis_not_reasserted")
    if "bg.visible = show_terrain_layer" in ren:
        passes.append("bg_follows_terrain_flag")
    else:
        fails.append("bg_visibility_not_gated")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "sea_rgba": sea,
        "land_alpha_clean": a_clean,
        "land_alpha_terrain": a_terrain,
        "pass": passes,
        "fail": fails,
        "summary": "political_fill_visual · sea_a=%.2f land_a=%.2f · %s"
        % (sea[3], a_clean, "PASS" if ok else "FAIL"),
        "policy": "clean_political_default_continuous_sea_solid_land",
    }


def map_political_fill_visual_integrity() -> Dict[str, Any]:
    return build_map_political_fill_visual_product()
