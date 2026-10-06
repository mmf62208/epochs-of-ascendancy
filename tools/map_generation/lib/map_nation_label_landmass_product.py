"""Pure policy: nation label sits on capital's contiguous owned landmass center.

Mirrors MapPoliticalLabelsLayer._capital_landmass_centroid selection (BFS component + weighted mean).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
LABELS_GD = ROOT / "scripts" / "map" / "MapPoliticalLabelsLayer.gd"
ZOOM_LOD_GD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"
ROAD_TIER_GD = ROOT / "scripts" / "map" / "RoadTierVisual.gd"
MENU_GD = ROOT / "scripts" / "ui" / "MainMenu.gd"
MENU_TSCN = ROOT / "scenes" / "ui" / "MainMenu.tscn"

# Mirror MapZoomLOD nation-label camera policy (LABEL-1).
NATION_LABEL_EUROPE_ZOOM = 0.40
NATION_LABEL_MID_ZOOM = 0.776
NATION_LABEL_CLOSE_ZOOM = 1.80
NATION_LABEL_FADE_START_ZOOM = 0.82
NATION_LABEL_HIDE_ZOOM = 0.98
NATION_LABEL_CITY_LABEL_ZOOM = 1.50
NATION_LABEL_EUROPE_HEIGHT_FRAC = 0.032
NATION_LABEL_MID_HEIGHT_FRAC = 0.026
NATION_LABEL_EUROPE_RATIO_BAND = (0.018, 0.045)
NATION_LABEL_MID_RATIO_BAND = (0.016, 0.038)
NATION_LABEL_CLOSE_RATIO_MAX = 0.012


def capital_landmass_centroid(
    owned_pids: List[int],
    centroids: Dict[int, Tuple[float, float]],
    neighbors: Dict[int, List[int]],
    capital_id: int,
    weights: Dict[int, float] | None = None,
) -> Tuple[float, float] | None:
    """BFS from capital through owned neighbors; return weighted centroid of that component."""
    owned: Set[int] = set(owned_pids)
    if not owned:
        return None
    seed = capital_id if capital_id in owned else next(iter(owned))
    seen: Set[int] = {seed}
    q: List[int] = [seed]
    component: List[int] = []
    while q:
        cur = q.pop(0)
        component.append(cur)
        for nid in neighbors.get(cur, []):
            if nid in seen or nid not in owned:
                continue
            if nid not in centroids:
                continue
            seen.add(nid)
            q.append(nid)
    sx = sy = wsum = 0.0
    for pid in component:
        if pid not in centroids:
            continue
        w = 1.0
        if weights and pid in weights:
            w = max(1.0, float(weights[pid]))
        cx, cy = centroids[pid]
        sx += cx * w
        sy += cy * w
        wsum += w
    if wsum <= 0:
        return None
    return (sx / wsum, sy / wsum)


def nation_label_target_frac_of_height(zoom: float) -> float:
    zz = max(float(zoom), 0.01)
    if zz <= NATION_LABEL_EUROPE_ZOOM:
        return NATION_LABEL_EUROPE_HEIGHT_FRAC
    if zz >= NATION_LABEL_HIDE_ZOOM:
        return 0.0
    if zz <= NATION_LABEL_MID_ZOOM:
        span = max(NATION_LABEL_MID_ZOOM - NATION_LABEL_EUROPE_ZOOM, 0.01)
        t = max(0.0, min(1.0, (zz - NATION_LABEL_EUROPE_ZOOM) / span))
        return NATION_LABEL_EUROPE_HEIGHT_FRAC + (
            NATION_LABEL_MID_HEIGHT_FRAC - NATION_LABEL_EUROPE_HEIGHT_FRAC
        ) * t
    span = max(NATION_LABEL_HIDE_ZOOM - NATION_LABEL_MID_ZOOM, 0.01)
    t = max(0.0, min(1.0, (zz - NATION_LABEL_MID_ZOOM) / span))
    return NATION_LABEL_MID_HEIGHT_FRAC * (1.0 - t)


def nation_label_font_px_for_camera(zoom: float, viewport_h: float) -> int:
    frac = nation_label_target_frac_of_height(zoom)
    target = frac * max(float(viewport_h), 1.0)
    if target <= 0.5 or zoom >= NATION_LABEL_HIDE_ZOOM or zoom >= NATION_LABEL_CITY_LABEL_ZOOM:
        return 0
    font_px = int(round(target / max(float(zoom), 0.08)))
    return max(10, min(96, font_px))


def nation_label_effective_screen_px(font_px: int, zoom: float, node_scale: float) -> float:
    return float(max(int(font_px), 0)) * max(float(zoom), 0.0) * max(float(node_scale), 0.0)


def nation_label_height_ratio(
    font_px: int, zoom: float, node_scale: float, viewport_h: float
) -> float:
    return nation_label_effective_screen_px(font_px, zoom, node_scale) / max(float(viewport_h), 1.0)


def nation_label_is_texture_magnified(font_px: int, zoom: float, node_scale: float) -> bool:
    if int(font_px) <= 0:
        return False
    effective = nation_label_effective_screen_px(font_px, zoom, node_scale)
    if effective <= 0.5:
        return False
    return effective > float(font_px) + 0.75 or float(node_scale) > 1.02


def _label1_bands_ok(viewport_h: float = 720.0) -> Tuple[bool, List[str], List[str]]:
    passes: List[str] = []
    fails: List[str] = []
    cases = (
        ("europe", NATION_LABEL_EUROPE_ZOOM, NATION_LABEL_EUROPE_RATIO_BAND, False),
        ("mid", NATION_LABEL_MID_ZOOM, NATION_LABEL_MID_RATIO_BAND, False),
        ("close", NATION_LABEL_CLOSE_ZOOM, (0.0, NATION_LABEL_CLOSE_RATIO_MAX), True),
    )
    for name, zoom, band, must_hide in cases:
        font_px = nation_label_font_px_for_camera(zoom, viewport_h)
        ratio = nation_label_height_ratio(font_px, zoom, 1.0, viewport_h)
        magnified = nation_label_is_texture_magnified(font_px, zoom, 1.0)
        lo, hi = band
        if must_hide and font_px != 0:
            fails.append("%s_font_not_hidden=%d" % (name, font_px))
        elif (not must_hide) and font_px <= 0:
            fails.append("%s_font_hidden" % name)
        else:
            passes.append("%s_font=%d" % (name, font_px))
        if magnified:
            fails.append("%s_texture_magnified" % name)
        else:
            passes.append("%s_not_magnified" % name)
        if lo <= ratio <= hi:
            passes.append("%s_ratio=%.4f" % (name, ratio))
        else:
            fails.append("%s_ratio=%.4f_want_%.3f..%.3f" % (name, ratio, lo, hi))
    mid_r = nation_label_height_ratio(
        nation_label_font_px_for_camera(NATION_LABEL_MID_ZOOM, viewport_h),
        NATION_LABEL_MID_ZOOM,
        1.0,
        viewport_h,
    )
    eu_r = nation_label_height_ratio(
        nation_label_font_px_for_camera(NATION_LABEL_EUROPE_ZOOM, viewport_h),
        NATION_LABEL_EUROPE_ZOOM,
        1.0,
        viewport_h,
    )
    if mid_r <= eu_r + 0.002:
        passes.append("mid_le_europe")
    else:
        fails.append("mid_larger_than_europe")
    if nation_label_is_texture_magnified(20, NATION_LABEL_MID_ZOOM, 2.5):
        passes.append("scale_2_5_detected")
    else:
        fails.append("scale_2_5_not_flagged")
    return (len(fails) == 0, passes, fails)


def build_map_nation_label_landmass_product() -> Dict[str, Any]:
    # Synthetic UK-like: capital on coast (London-like), bulk of mass inland/west.
    # Capital at (10, 0); main mass around (0, 0).
    owned = [1, 2, 3, 4, 5]
    centroids = {
        1: (10.0, 0.0),  # capital coastal pin
        2: (2.0, 0.0),
        3: (0.0, 1.0),
        4: (-1.0, 0.0),
        5: (0.0, -1.0),
    }
    neighbors = {
        1: [2],
        2: [1, 3, 4, 5],
        3: [2],
        4: [2],
        5: [2],
    }
    weights = {1: 1.0, 2: 5.0, 3: 5.0, 4: 5.0, 5: 5.0}
    c = capital_landmass_centroid(owned, centroids, neighbors, capital_id=1, weights=weights)
    passes: List[str] = []
    fails: List[str] = []
    if c is None:
        fails.append("no_centroid")
    else:
        # Must be pulled toward mass (x near 0), not stuck on capital pin x=10
        if c[0] < 5.0:
            passes.append("not_on_capital_pin_x=%.2f" % c[0])
        else:
            fails.append("still_on_capital_pin_x=%.2f" % c[0])
        if abs(c[1]) < 2.0:
            passes.append("mass_y_ok")
        else:
            fails.append("mass_y_bad")

    # Isolated overseas province should not pull capital landmass if not connected
    owned2 = [1, 2, 99]
    centroids2 = {1: (0.0, 0.0), 2: (1.0, 0.0), 99: (100.0, 100.0)}
    neighbors2 = {1: [2], 2: [1], 99: []}
    c2 = capital_landmass_centroid(owned2, centroids2, neighbors2, capital_id=1, weights=None)
    if c2 is not None and c2[0] < 50:
        passes.append("excludes_disconnected_colony")
    else:
        fails.append("included_disconnected_colony")

    gd = LABELS_GD.read_text(encoding="utf-8") if LABELS_GD.is_file() else ""
    lod = ZOOM_LOD_GD.read_text(encoding="utf-8") if ZOOM_LOD_GD.is_file() else ""
    road = ROAD_TIER_GD.read_text(encoding="utf-8") if ROAD_TIER_GD.is_file() else ""
    menu = MENU_GD.read_text(encoding="utf-8") if MENU_GD.is_file() else ""
    tscn = MENU_TSCN.read_text(encoding="utf-8") if MENU_TSCN.is_file() else ""
    if "func _capital_landmass_centroid" in gd and "_capital_landmass_centroid(" in gd:
        passes.append("gd_landmass_fn")
    else:
        fails.append("missing_gd_landmass")
    if "extends CanvasLayer" in menu and "CanvasLayer" in tscn:
        passes.append("menu_canvas_layer")
    else:
        fails.append("menu_not_overlay")
    if "save_game_detailed" in menu or "_save_to_slot" in menu:
        passes.append("menu_save_path")
    else:
        fails.append("menu_no_save")

    label1_needles = (
        "nation_label_font_px_for_camera",
        "nation_label_is_texture_magnified",
        "NATION_LABEL_MID_ZOOM",
        "PROCESS_MODE_ALWAYS",
        "seed_debug_nation_label",
        "lbl.scale = Vector2.ONE",
    )
    for needle in label1_needles:
        src = lod if needle.startswith("nation_label_") or needle.startswith("NATION_LABEL_") else gd
        if needle == "nation_label_font_px_for_camera" or needle == "nation_label_is_texture_magnified" or needle == "NATION_LABEL_MID_ZOOM":
            src = lod
        if needle in src:
            passes.append("label1_%s" % needle)
        else:
            fails.append("missing_%s" % needle)
    if "END_LABEL_ZOOM_MIN := 1.50" in road and "Köln" in road:
        passes.append("city_labels_mid_close")
    else:
        fails.append("city_label_lod_regressed")
    if "FacilityIconLayer" not in gd and "TipDismiss" not in gd:
        passes.append("label_layer_keeps_fences")
    else:
        fails.append("label_layer_touched_fences")

    bands_ok, band_pass, band_fail = _label1_bands_ok(720.0)
    passes.extend(band_pass)
    fails.extend(band_fail)
    if not bands_ok:
        fails.append("label1_bands")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "centroid": c,
        "pass": passes,
        "fail": fails,
        "summary": "nation_label_landmass · %s" % ("PASS" if ok else "FAIL"),
    }
