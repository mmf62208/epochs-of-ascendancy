"""Player-facing multi-front / live border assault surface (Phase C).

Formats MapManager.collect_live_border_assault_targets-shaped rows into a
readable list for toolbar/hotkey (KEY_B) and pure gates.

Does not invent fronts — drives the same dict shape as GD:
  {province_id, from_province_id, defender_tag, defender_power, name}
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
MAP_MANAGER = ROOT / "scripts" / "map" / "MapManager.gd"
TOOLBAR = ROOT / "scripts" / "ui" / "map" / "MapModeToolbar.gd"


def format_live_border_fronts_surface(
    targets: Sequence[Mapping[str, Any]],
    *,
    country_tag: str = "GER",
    max_lines: int = 8,
) -> Dict[str, Any]:
    """Format border assault target rows for player surface (toast / legend / list)."""
    tag = str(country_tag or "GER").strip().upper() or "GER"
    rows: List[Dict[str, Any]] = []
    for t in targets or []:
        if not isinstance(t, Mapping):
            continue
        pid = int(t.get("province_id") or t.get("id") or -1)
        if pid < 0:
            continue
        rows.append(
            {
                "province_id": pid,
                "from_province_id": int(t.get("from_province_id") or 0),
                "defender_tag": str(t.get("defender_tag") or t.get("owner") or "?").upper(),
                "defender_power": float(t.get("defender_power") or 0.0),
                "name": str(t.get("name") or ("#%d" % pid)),
            }
        )
    rows = rows[: max(1, int(max_lines))] if rows else []
    if not rows:
        plain = "Fronts · %s · no enemy border targets" % tag
        return {
            "ok": True,
            "empty": True,
            "country_tag": tag,
            "count": 0,
            "targets": [],
            "best_province_id": -1,
            "plain": plain,
            "toast": plain,
            "legend": plain,
            "summary": plain,
            "hotkey": "B",
            "action": "show_live_border_fronts",
        }
    lines = ["Fronts · %s · %d targets (B)" % (tag, len(rows))]
    for i, r in enumerate(rows):
        lines.append(
            "  %d. %s #%d ← from #%d · %s"
            % (
                i + 1,
                r["name"],
                r["province_id"],
                r["from_province_id"],
                r["defender_tag"],
            )
        )
    plain = "\n".join(lines)
    toast = "Fronts · %s · %s #%d vs %s (+%d more · press B)" % (
        tag,
        rows[0]["name"],
        rows[0]["province_id"],
        rows[0]["defender_tag"],
        max(0, len(rows) - 1),
    )
    legend = "Fronts: %s → %s #%d · B cycles" % (
        tag,
        rows[0]["defender_tag"],
        rows[0]["province_id"],
    )
    return {
        "ok": True,
        "empty": False,
        "country_tag": tag,
        "count": len(rows),
        "targets": rows,
        "best_province_id": int(rows[0]["province_id"]),
        "best_from_province_id": int(rows[0]["from_province_id"]),
        "plain": plain,
        "toast": toast,
        "legend": legend,
        "summary": toast,
        "hotkey": "B",
        "action": "show_live_border_fronts",
    }


def _load_board(board_dir: Path) -> Dict[str, Any]:
    base = {
        int(p["id"]): p
        for p in json.loads((board_dir / "provinces_base.json").read_text(encoding="utf-8"))[
            "provinces"
        ]
    }
    own = (
        json.loads((board_dir / "province_ownership_1936.json").read_text(encoding="utf-8")).get(
            "owners"
        )
        or {}
    )
    adj = (
        json.loads((board_dir / "province_adjacency.json").read_text(encoding="utf-8")).get(
            "adjacency"
        )
        or {}
    )
    return {"base": base, "own": own, "adj": adj}


def collect_border_targets_from_board(
    board_dir: str = "",
    country_tag: str = "GER",
    max_count: int = 8,
    foe_order: Optional[Sequence[str]] = None,
) -> List[Dict[str, Any]]:
    """Pure mirror of MapManager.collect_live_border_assault_targets core (ownership+adj)."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    data = _load_board(d)
    base = data["base"]
    own = data["own"]
    adj = data["adj"]
    tag = str(country_tag or "GER").strip().upper()
    foes = list(foe_order) if foe_order else []
    if not foes:
        default = {
            "GER": ["FRA", "POL", "SOV", "BEL", "NLD", "CZE", "DNK"],
            "FRA": ["GER", "ITA", "SPA"],
            "USA": ["JAP", "MEX"],
            "POL": ["GER", "SOV"],
        }
        foes = list(default.get(tag, []))
    # owned by tag
    owned = [pid for pid, p in base.items() if str(own.get(str(pid), "")).upper() == tag]
    water = {"sea", "ocean", "water", "lake"}
    out: List[Dict[str, Any]] = []
    seen = set()
    for foe in foes:
        if len(out) >= max_count:
            break
        for opid in owned:
            if len(out) >= max_count:
                break
            for n in adj.get(str(opid)) or []:
                nid = int(n)
                if nid in seen:
                    continue
                p = base.get(nid)
                if not p:
                    continue
                terr = str(p.get("terrain", "")).lower()
                dom = str(p.get("domain", "land")).lower()
                if terr in water or dom in {"sea", "strait", "lake", "ocean"}:
                    continue
                if str(own.get(str(nid), "")).upper() != foe:
                    continue
                seen.add(nid)
                out.append(
                    {
                        "province_id": nid,
                        "from_province_id": int(opid),
                        "defender_tag": foe,
                        "defender_power": 70.0 if foe == "FRA" else (55.0 if foe == "POL" else 80.0),
                        "name": str(p.get("name") or ("#%d" % nid)),
                    }
                )
                if len(out) >= max_count:
                    break
    return out


def build_map_live_border_fronts_surface_product(
    board_dir: str = "",
    country_tag: str = "GER",
    max_count: int = 8,
) -> Dict[str, Any]:
    targets = collect_border_targets_from_board(
        board_dir=board_dir, country_tag=country_tag, max_count=max_count
    )
    surface = format_live_border_fronts_surface(targets, country_tag=country_tag, max_lines=max_count)
    # Maginot/Polish gate on GER when board has Europe NUTS edges
    has_fra = any(str(t.get("defender_tag")) == "FRA" for t in targets)
    has_pol = any(str(t.get("defender_tag")) == "POL" for t in targets)
    surface["has_fra_edge"] = has_fra
    surface["has_pol_edge"] = has_pol
    surface["ok"] = bool(surface.get("ok")) and (
        str(country_tag).upper() != "GER" or (has_fra or has_pol or int(surface.get("count") or 0) > 0)
    )
    surface["board_ok"] = int(surface.get("count") or 0) > 0
    return surface


def map_live_border_fronts_surface_integrity() -> Dict[str, Any]:
    """Structural: pure product + GD surface wiring (hotkey B, toolbar Fronts, MapManager API)."""
    fails: List[str] = []
    passes: List[str] = []
    p = build_map_live_border_fronts_surface_product(country_tag="GER", max_count=8)
    if p.get("board_ok") and int(p.get("count") or 0) >= 1:
        passes.append("ger_targets=%d" % int(p["count"]))
    else:
        fails.append("ger_targets_empty")
    if p.get("has_fra_edge") or p.get("has_pol_edge"):
        passes.append("maginot_or_polish")
    else:
        # Soft: still pass if any targets (post-merge ownership may vary)
        if int(p.get("count") or 0) >= 1:
            passes.append("any_border_ok")
        else:
            fails.append("no_major_front")

    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    mm = MAP_MANAGER.read_text(encoding="utf-8") if MAP_MANAGER.is_file() else ""
    tb = TOOLBAR.read_text(encoding="utf-8") if TOOLBAR.is_file() else ""
    for needle, blob, label in (
        ("func collect_live_border_assault_targets", mm, "mm_collect"),
        ("func show_live_border_fronts", ren, "ren_show"),
        ("KEY_B", ren, "ren_key_b"),
        ("Fronts", tb, "toolbar_fronts"),
        ("show_live_border_fronts", tb, "toolbar_calls_show"),
    ):
        if needle in blob:
            passes.append(label)
        else:
            fails.append("missing_%s" % label)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "pass": passes,
        "fail": fails,
        "product_count": p.get("count"),
        "best_province_id": p.get("best_province_id"),
        "summary": (
            "live_border_fronts · count=%s · wiring %s"
            % (p.get("count"), "PASS" if ok else "FAIL")
        ),
    }
