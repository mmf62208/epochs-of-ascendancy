"""Player factory shortage markers for the living map (exception-first).

Starved lines become a place: province id + worst missing resource + outline.
Node2D layer only — never ColorRect / Control per factory.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
LAYER = ROOT / "scripts" / "map" / "FactoryStatusLayer.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
PROD = ROOT / "scripts" / "autoload" / "ProductionManager.gd"
HUD = ROOT / "scripts" / "ui" / "HudIconLibrary.gd"
INFRA = ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd"

GLYPH_PRIORITY = (
    "oil",
    "fuel",
    "steel",
    "rubber",
    "coal",
    "aluminum",
    "chromium",
    "tungsten",
)
MAX_MARKERS = 24
GER_INDUSTRY_DEFAULT = 710300


def worst_missing_key(missing: Optional[Mapping[str, Any]]) -> str:
    if not isinstance(missing, Mapping) or not missing:
        return ""
    for key in GLYPH_PRIORITY:
        try:
            if float(missing.get(key) or 0) > 0.001:
                if key == "fuel":
                    return "oil"
                return key
        except (TypeError, ValueError):
            continue
    for key, val in missing.items():
        try:
            if float(val or 0) > 0.001:
                k = str(key).strip().lower()
                return "oil" if k in ("fuel", "petroleum", "energy") else k
        except (TypeError, ValueError):
            continue
    return ""


def outline_for_fill_ratio(fill_ratio: float) -> str:
    try:
        fill = float(fill_ratio)
    except (TypeError, ValueError):
        fill = 1.0
    if fill <= 0.05:
        return "stopped"
    if fill < 1.0:
        return "short"
    return "ok"


def factory_shortage_marker(
    *,
    pid: int,
    missing: Optional[Mapping[str, Any]] = None,
    fill_ratio: float = 1.0,
    owner_tag: str = "GER",
    player_tag: str = "GER",
) -> Dict[str, Any]:
    empty = {
        "ok": False,
        "empty": True,
        "pid": -1,
        "missing_key": "",
        "fill_ratio": 1.0,
        "outline": "ok",
        "action": "shortage",
    }
    own = str(owner_tag or "").strip().upper()
    player = str(player_tag or "").strip().upper() or "GER"
    if int(pid or 0) <= 0 or own != player:
        return empty
    key = worst_missing_key(missing)
    outline = outline_for_fill_ratio(fill_ratio)
    if not key or outline == "ok":
        return empty
    try:
        fill = float(fill_ratio)
    except (TypeError, ValueError):
        fill = 0.0
    return {
        "ok": True,
        "empty": False,
        "pid": int(pid),
        "missing_key": key,
        "fill_ratio": fill,
        "outline": outline,
        "owner_tag": own,
        "action": "shortage",
        "label": "%s short" % key,
    }


def cap_shortage_markers(
    rows: Optional[Sequence[Mapping[str, Any]]] = None,
    max_n: int = MAX_MARKERS,
) -> List[Dict[str, Any]]:
    scored: List[Dict[str, Any]] = []
    for raw in rows or []:
        if not isinstance(raw, Mapping):
            continue
        marker = factory_shortage_marker(
            pid=int(raw.get("pid") or raw.get("province_id") or 0),
            missing=raw.get("missing") if isinstance(raw.get("missing"), Mapping) else {},
            fill_ratio=float(raw.get("fill_ratio") or 0.0),
            owner_tag=str(raw.get("owner_tag") or "GER"),
            player_tag=str(raw.get("player_tag") or raw.get("owner_tag") or "GER"),
        )
        if marker.get("ok"):
            scored.append(marker)
    scored.sort(key=lambda m: (float(m.get("fill_ratio") or 0.0), int(m.get("pid") or 0)))
    cap = max(1, int(max_n or MAX_MARKERS))
    return scored[:cap]


def map_factory_shortage_surface_integrity() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    lyr = LAYER.read_text(encoding="utf-8") if LAYER.is_file() else ""
    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    prod = PROD.read_text(encoding="utf-8") if PROD.is_file() else ""
    hud = HUD.read_text(encoding="utf-8") if HUD.is_file() else ""
    if "func _draw" in lyr and "ColorRect" not in lyr and "Control" not in lyr:
        passes.append("layer_draw_no_control")
    else:
        fails.append("layer_draw_no_control")
    if "max_markers" in lyr and "HudIconLibrary" in lyr:
        passes.append("layer_budget_glyph")
    else:
        fails.append("layer_budget_glyph")
    if "production_resource_shortage" in lyr and "game_day_advanced" in lyr:
        passes.append("layer_day_or_signal")
    else:
        fails.append("layer_day_or_signal")
    if "set_process(false)" in lyr or "set_process(true)" not in lyr:
        passes.append("layer_no_pulse")
    else:
        fails.append("layer_no_pulse")
    if "_setup_factory_status_layer" in ren and "FactoryStatusLayer" in ren:
        passes.append("renderer_wires_layer")
    else:
        fails.append("renderer_wires_layer")
    if "signal production_resource_shortage" in prod:
        passes.append("prod_shortage_signal")
    else:
        fails.append("prod_shortage_signal")
    if "oil" in hud and "steel" in hud and "func resource_icon" in hud:
        passes.append("hud_resource_glyphs")
    else:
        fails.append("hud_resource_glyphs")
    sample = factory_shortage_marker(
        pid=GER_INDUSTRY_DEFAULT,
        missing={"oil": 2.0},
        fill_ratio=0.0,
        owner_tag="GER",
        player_tag="GER",
    )
    if sample.get("ok") and sample.get("missing_key") == "oil" and sample.get("outline") == "stopped":
        passes.append("oil_stopped_marker")
    else:
        fails.append("oil_stopped_marker")
    infra = INFRA.read_text(encoding="utf-8") if INFRA.is_file() else ""
    sites_i = infra.find("func rebuild_sites_layer")
    sites_slice = ""
    if sites_i >= 0:
        nxt = infra.find("\nfunc ", sites_i + 1)
        sites_slice = infra[sites_i : nxt if nxt > 0 else sites_i + 8000]
    draw_i = infra.find("func _draw(")
    draw_slice = ""
    if draw_i >= 0:
        nxt = infra.find("\nfunc ", draw_i + 1)
        draw_slice = infra[draw_i : nxt if nxt > 0 else draw_i + 2500]
    vis_i = infra.find("func _update_sub_layer_visibilities")
    vis_slice = ""
    if vis_i >= 0:
        nxt = infra.find("\nfunc ", vis_i + 1)
        vis_slice = infra[vis_i : nxt if nxt > 0 else vis_i + 2500]
    if (
        "func rebuild_sites_layer" in infra
        and "ColorRect.new()" not in sites_slice
        and "_player_industry_marks" in sites_slice
        and "PlayerIndustryMarks" in infra
        and "industry_layer" in infra
        and "class IndustryMarksDraw" in infra
        and "_draw_player_industry_marks" not in draw_slice
        and "industry_layer.visible" in vis_slice
        and "site_z" in vis_slice
        and "_pid_is_starved" in infra
    ):
        passes.append("sites_no_colorrect_starved_wins")
        passes.append("industry_marks_zoom_child")
    else:
        fails.append("sites_no_colorrect_starved_wins")
        fails.append("industry_marks_zoom_child")
    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "pass": passes,
        "fail": fails,
        "summary": "factory_shortage_surface · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
    }


def build_map_factory_shortage_surface_product() -> Dict[str, Any]:
    g = map_factory_shortage_surface_integrity()
    g["product"] = "map_factory_shortage_surface_product"
    return g
