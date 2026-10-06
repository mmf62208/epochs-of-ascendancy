"""Chip click follows the piece Godot paints on top.

StatBars and chip text stay at z=3. NationPlate stays at z=-1.
`_unit_counter_painted_wins` ranks the hit piece by CanvasItem z
(child z included) then tree order. A face, bar, or glyph counts
only where it has ink. Land chrome and sea plates share that rank.
Land roots stay at 28. Once, at rebuild, foreign NATO sprites start
at z=4 (above bars and glyphs at z=3). A chip with no top pixel at
Home scale steps its sprite up to at most z=8. Player symbols are
z=9 and the player chip is moved to the end of its own province
node. Zoom does not reparent or slide them. Sea roots stay at 40.
Plate-interior class must not beat bars or text.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
HEADLESS = ROOT / "scripts" / "core" / "HeadlessChipDrawOrderPickTest.gd"


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


def build_chip_draw_order_pick_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    if not ren:
        fails.append("missing_map_renderer")
    wins = _gd_func_slice(ren, "_unit_counter_painted_wins")
    drawn = _gd_func_slice(ren, "_pick_drawn_land_air_body_at_world")
    pick = _gd_func_slice(ren, "_pick_unit_formation_at_world")
    land_open = _gd_func_slice(ren, "_try_open_land_unit_at_world")
    sea_pick = _gd_func_slice(ren, "_pick_sea_nation_plate_drawn_at_world")
    beats = _gd_func_slice(ren, "_drawn_land_beats_sea_plate")
    piece = _gd_func_slice(ren, "_unit_counter_top_drawn_piece")
    plate = _gd_func_slice(ren, "_make_unit_nation_plate")
    bars = _gd_func_slice(ren, "_make_unit_stat_bars")
    checks = {
        "piece_z_helper": "func _canvas_item_effective_z" in ren
        and "func _drawn_piece_is_above" in ren
        and "func _unit_counter_top_drawn_piece" in ren,
        "wins_uses_piece_z": "_unit_counter_top_drawn_piece" in wins
        and "_drawn_piece_is_above" in wins
        and "_unit_counter_painted_class" not in wins
        and "distance_squared_to" not in wins,
        "both_picks_call_wins": "_unit_counter_painted_wins" in drawn
        and "_unit_counter_painted_wins" in pick,
        "no_player_bar_override": "own_bars_fo" not in pick and "best_bar" not in drawn,
        "plate_stays_under_bars": "z_index = -1" in plate and "z_index = 3" in bars,
        "class_helper_kept": "func _unit_counter_painted_class" in ren,
        "sea_land_same_piece": "_unit_counter_top_drawn_piece" in sea_pick
        and "_unit_counter_painted_wins" in sea_pick
        and "_drawn_land_beats_sea_plate" in pick
        and "_drawn_land_beats_sea_plate" in land_open
        and "_unit_counter_painted_wins" in beats
        and "SeaNationDisk" in piece,
        "player_order_once_at_rebuild": (
            "func _order_player_land_chips_last" in ren
            and "_order_player_land_chips_last()" in _gd_func_slice(ren, "_rebuild_demo_unit_icons")
            and "z_index = 9 if player_land else 4" in _gd_func_slice(ren, "_order_player_land_chips_last")
            and "_bury_covered_land_sprites(foreign)" in _gd_func_slice(ren, "_order_player_land_chips_last")
            and "spr_z >= 8" in _gd_func_slice(ren, "_bury_covered_land_sprites")
            and "func _raise_player_land_above_covering_foreign" not in ren
            and "_raise_player_land_above_covering_foreign(zz)" not in ren
            and "eoa_raise_above_foreign" not in ren
            and "NLD_formation_1" not in ren
            and "chip_z = 34" not in ren
        ),
        "opaque_piece_ink": (
            "func _sprite_pixel_opaque" in ren
            and "_sprite_pixel_opaque" in _gd_func_slice(ren, "_unit_counter_top_sprite")
            and "func _world_in_unit_stat_bar_ink" in ren
            and "_world_in_unit_stat_bar_ink" in piece
            and "func _world_in_chip_text_glyphs" in ren
            and "_world_in_chip_text_glyphs" in _gd_func_slice(ren, "_world_in_unit_painted_glyphs")
            and "func _world_in_unit_stat_bars" in ren
        ),
        "headless_overlap": False,
    }
    if HEADLESS.is_file():
        ht = HEADLESS.read_text(encoding="utf-8")
        checks["headless_overlap"] = (
            "NLD_formation_1" in ht
            and "DNK_formation_3" in ht
            and "_pick_drawn_land_air_body_at_world" in ht
            and "_pick_unit_formation_at_world" in ht
            and "bare NLD plate" in ht
        )
    for key, ok in checks.items():
        if ok:
            passes.append(key)
        else:
            fails.append(key)
    status = "PASS" if not fails else "FAIL"
    return {
        "ok": not fails,
        "status": status,
        "pass": passes,
        "fail": fails,
        "summary": "chip_draw_order_pick · %s" % status,
    }
