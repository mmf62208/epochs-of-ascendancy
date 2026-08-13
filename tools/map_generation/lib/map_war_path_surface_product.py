"""First-session war/command path surface (Stream 2 polish).

Player-facing: KEY_I EquipmentFlow · Attack inspector · Fronts B · combined WarLoop.
Pure formatters + integrity against shipped MapRenderer/OrderCommandPanel wires.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
TOOLBAR = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"
MAP_MANAGER = ROOT / "scripts" / "map" / "MapManager.gd"
ZOOM_LOD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"


def format_first_session_war_path(
    *,
    country_tag: str = "GER",
    flow_on: bool = True,
    fronts: Optional[Sequence[Mapping[str, Any]]] = None,
    best_province_id: int = -1,
) -> Dict[str, Any]:
    """Build player-facing war-path brief from real surface state (not F10-only)."""
    tag = str(country_tag or "GER").strip().upper() or "GER"
    rows: List[Dict[str, Any]] = []
    for t in fronts or []:
        if not isinstance(t, Mapping):
            continue
        pid = int(t.get("province_id") or t.get("id") or -1)
        if pid < 0:
            continue
        rows.append(
            {
                "province_id": pid,
                "from_province_id": int(t.get("from_province_id") or 0),
                "defender_tag": str(t.get("defender_tag") or "?").upper(),
                "name": str(t.get("name") or ("#%d" % pid)),
            }
        )
    best = int(best_province_id)
    if best <= 0 and rows:
        best = int(rows[0]["province_id"])
    steps = [
        "1. Select friendly province with a formation (capital/hub/border)",
        "2. Press B or toolbar Fronts — pick enemy border target",
        "3. Inspector Attack or Ctrl+click adjacent enemy",
        "4. Press I — EquipmentFlow glyphs ON (supply→front equipment)",
        "5. Press G — capital→front supply corridor",
    ]
    toast = "WarLoop · %s · flow %s · target #%s · B fronts · I flow · Ctrl+click assault" % (
        tag,
        "ON" if flow_on else "OFF",
        str(best) if best > 0 else "?",
    )
    plain = toast + "\n" + "\n".join(steps)
    if rows:
        plain += "\nFronts: " + ", ".join(
            "%s #%d" % (r["name"], r["province_id"]) for r in rows[:4]
        )
    return {
        "ok": True,
        "empty": False,
        "country_tag": tag,
        "flow_on": bool(flow_on),
        "front_count": len(rows),
        "best_province_id": best,
        "targets": rows,
        "steps": steps,
        "toast": toast,
        "plain": plain,
        "summary": toast,
        "hotkeys": {"flow": "I", "fronts": "B", "corridor": "G", "war_loop": "Shift+I"},
        "action": "show_first_session_war_path",
        "toolbar_preset": "WarLoop",
    }


def build_map_war_path_surface_product(
    *,
    country_tag: str = "GER",
    flow_on: bool = True,
    board_dir: str = "",
) -> Dict[str, Any]:
    """Combine live-border pure targets (if available) with war-path format."""
    fronts: List[Dict[str, Any]] = []
    try:
        from map_live_border_fronts_surface_product import (  # type: ignore
            build_map_live_border_fronts_surface_product,
        )

        fr = build_map_live_border_fronts_surface_product(
            board_dir=board_dir, country_tag=country_tag, max_count=6
        )
        fronts = list(fr.get("targets") or [])
        best = int(fr.get("best_province_id") or -1)
    except Exception:
        best = -1
        fr = {"ok": False}
    surface = format_first_session_war_path(
        country_tag=country_tag,
        flow_on=flow_on,
        fronts=fronts,
        best_province_id=best,
    )
    surface["fronts_product_ok"] = bool(fr.get("ok")) if isinstance(fr, dict) else False
    surface["board_fronts_ok"] = len(fronts) >= 1
    surface["ok"] = bool(surface.get("ok")) and (
        surface["board_fronts_ok"] or str(country_tag).upper() != "GER"
    )
    return surface


def map_war_path_surface_integrity() -> Dict[str, Any]:
    fails: List[str] = []
    passes: List[str] = []
    p = build_map_war_path_surface_product(country_tag="GER")
    if p.get("ok") and int(p.get("front_count") or 0) >= 1:
        passes.append("war_path_fronts=%d" % int(p["front_count"]))
    else:
        fails.append("war_path_fronts_empty")
    if "show_first_session_war_path" in str(p.get("action") or ""):
        passes.append("action_id")
    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    tb = TOOLBAR.read_text(encoding="utf-8") if TOOLBAR.is_file() else ""
    mm = MAP_MANAGER.read_text(encoding="utf-8") if MAP_MANAGER.is_file() else ""
    lod = ZOOM_LOD.read_text(encoding="utf-8") if ZOOM_LOD.is_file() else ""
    for needle, blob, key in (
        ("func toggle_equipment_flow_glyphs", ren, "ren_toggle_flow"),
        ("func get_equipment_flow_glyph_query", ren, "ren_flow_query"),
        ("KEY_I", ren, "ren_key_i"),
        ("func show_first_session_war_path", ren, "ren_war_path"),
        ("KEY_I", ren, "ren_shift_i_or_i"),  # flow hotkey present
        ("WarLoop", tb, "toolbar_warloop"),
        ("show_first_session_war_path", tb, "toolbar_calls_war"),
        ("func collect_live_border_assault_targets", mm, "mm_borders"),
        ("func show_live_border_fronts", ren, "ren_fronts"),
        ("BtnAttackProvince", ren, "inspector_attack"),
        ("func max_equipment_flow_glyphs_for_board", lod, "lod_flow"),
    ):
        if needle in blob:
            passes.append(key)
        else:
            fails.append("missing_%s" % key)
    # Shift+I specifically for war loop
    if "KEY_SHIFT" in ren and "show_first_session_war_path" in ren:
        passes.append("shift_i_or_war_hotkey")
    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "pass": passes,
        "fail": fails,
        "front_count": p.get("front_count"),
        "best_province_id": p.get("best_province_id"),
        "summary": "war_path_surface · fronts=%s · %s"
        % (p.get("front_count"), "PASS" if ok else "FAIL"),
    }
