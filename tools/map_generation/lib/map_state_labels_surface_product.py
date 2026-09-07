"""Stream 2: state name labels on states mapmode at operational zoom.

Pure policy + board-driven label placement (province centroids averaged per state).
Mirrors MapZoomLOD + MapPoliticalLabelsLayer state-label surface.
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
ZOOM_LOD = ROOT / "scripts" / "map" / "MapZoomLOD.gd"
LABELS = ROOT / "scripts" / "map" / "MapPoliticalLabelsLayer.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"


def show_state_labels_for_context(tier: str, map_mode: str) -> bool:
    """State names only on states mapmode at operational zoom (not strategic clutter)."""
    t = str(tier or "").strip().lower()
    m = str(map_mode or "").strip().lower()
    return m == "states" and t == "operational"


def state_label_font_px_for_tier(tier: str) -> int:
    t = str(tier or "").strip().lower()
    if t == "operational":
        return 15
    if t == "tactical":
        return 13
    return 12


def _centroid(pts: Sequence) -> Tuple[float, float]:
    xs: List[float] = []
    ys: List[float] = []
    for p in pts or []:
        if isinstance(p, (list, tuple)) and len(p) >= 2:
            xs.append(float(p[0]))
            ys.append(float(p[1]))
    if not xs:
        return 0.0, 0.0
    return sum(xs) / len(xs), sum(ys) / len(ys)


def build_state_label_rows(board_dir: str = "", max_labels: int = 80) -> List[Dict[str, Any]]:
    """Average geometry centroids per state; attach state name from province_states.json."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    base = {
        int(p["id"]): p
        for p in json.loads((d / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    }
    geo = {
        int(g["id"]): g
        for g in json.loads((d / "provinces_geometry.json").read_text(encoding="utf-8"))[
            "provinces"
        ]
    }
    mem = json.loads((d / "hierarchy_membership_1936.json").read_text(encoding="utf-8"))
    p2s = {int(k): int(v) for k, v in (mem.get("province_to_state") or {}).items()}
    names = {
        int(s.get("id") or 0): str(s.get("name") or ("State %d" % int(s.get("id") or 0)))
        for s in (json.loads((d / "province_states.json").read_text(encoding="utf-8")).get("states") or [])
    }
    water = {"sea", "ocean", "water", "lake"}
    water_d = {"sea", "strait", "lake", "ocean"}
    by_state: Dict[int, List[Tuple[float, float]]] = defaultdict(list)
    for pid, prow in base.items():
        terr = str(prow.get("terrain", "")).lower()
        dom = str(prow.get("domain", "land")).lower()
        if terr in water or dom in water_d:
            continue
        sid = int(p2s.get(pid) or 0)
        if sid <= 0:
            continue
        pts = (geo.get(pid) or {}).get("points") or []
        cx, cy = _centroid(pts)
        if cx == 0.0 and cy == 0.0 and not pts:
            continue
        by_state[sid].append((cx, cy))
    # Track Europe NUTS membership (province IDs 710000–799999) for first-session theater.
    nuts_provs_by_state: Dict[int, int] = defaultdict(int)
    for pid, sid in p2s.items():
        if 710000 <= int(pid) < 800000:
            nuts_provs_by_state[int(sid)] += 1

    rows: List[Dict[str, Any]] = []
    for sid in sorted(by_state.keys()):
        cents = by_state[sid]
        if not cents:
            continue
        ax = sum(c[0] for c in cents) / len(cents)
        ay = sum(c[1] for c in cents) / len(cents)
        rows.append(
            {
                "state_id": sid,
                "name": names.get(sid) or ("State %d" % sid),
                "cx": round(ax, 2),
                "cy": round(ay, 2),
                "province_n": len(cents),
                "is_europe_nuts": int(nuts_provs_by_state.get(sid) or 0) > 0,
                "europe_province_n": int(nuts_provs_by_state.get(sid) or 0),
            }
        )
    # Geo-balanced budget: Europe NUTS quota first, then grid fill for RoW/US.
    return select_state_labels_for_budget(rows, max_labels=max(1, int(max_labels)))


def select_state_labels_for_budget(
    rows: List[Dict[str, Any]],
    max_labels: int = 96,
    europe_quota: int = 48,
) -> List[Dict[str, Any]]:
    """Pick ≤max_labels state labels without letting RoW mega-states starve Europe.

    1) Reserve europe_quota slots for Europe NUTS states (IDs 710k provinces).
    2) Fill remaining budget via geo-grid stratification (diversity).
    3) If still under budget, fill by province_n among leftovers.
    """
    if not rows:
        return []
    budget = max(1, int(max_labels))
    eq = max(8, min(int(europe_quota), budget))
    europe = [r for r in rows if bool(r.get("is_europe_nuts"))]
    rest = [r for r in rows if not bool(r.get("is_europe_nuts"))]
    europe_sorted = sorted(
        europe,
        key=lambda r: (-int(r.get("province_n") or 0), str(r.get("name") or ""), int(r.get("state_id") or 0)),
    )
    picked: List[Dict[str, Any]] = list(europe_sorted[:eq])
    picked_ids = {int(r["state_id"]) for r in picked}
    remain = budget - len(picked)

    # Geo-grid on remaining world (and any leftover Europe)
    leftover = [r for r in rows if int(r["state_id"]) not in picked_ids]
    if remain > 0 and leftover:
        grid_pick = _geo_grid_pick(leftover, remain)
        for r in grid_pick:
            sid = int(r["state_id"])
            if sid in picked_ids:
                continue
            picked.append(r)
            picked_ids.add(sid)
            if len(picked) >= budget:
                break
        remain = budget - len(picked)

    if remain > 0:
        rest_sorted = sorted(
            [r for r in leftover if int(r["state_id"]) not in picked_ids],
            key=lambda r: (-int(r.get("province_n") or 0), int(r.get("state_id") or 0)),
        )
        for r in rest_sorted[:remain]:
            picked.append(r)

    # Stable order: Europe first then rest by name
    picked.sort(
        key=lambda r: (
            0 if r.get("is_europe_nuts") else 1,
            -int(r.get("province_n") or 0),
            str(r.get("name") or ""),
        )
    )
    return picked[:budget]


def _geo_grid_pick(rows: List[Dict[str, Any]], budget: int, cols: int = 6, row_n: int = 4) -> List[Dict[str, Any]]:
    """Take top-by-size states per world-canvas grid cell (round-robin)."""
    if not rows or budget <= 0:
        return []
    xs = [float(r.get("cx") or 0.0) for r in rows]
    ys = [float(r.get("cy") or 0.0) for r in rows]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    span_x = max(maxx - minx, 1.0)
    span_y = max(maxy - miny, 1.0)
    cells: Dict[Tuple[int, int], List[Dict[str, Any]]] = defaultdict(list)
    for r in rows:
        cx = float(r.get("cx") or 0.0)
        cy = float(r.get("cy") or 0.0)
        gx = int((cx - minx) / span_x * cols)
        gy = int((cy - miny) / span_y * row_n)
        gx = min(max(gx, 0), cols - 1)
        gy = min(max(gy, 0), row_n - 1)
        cells[(gx, gy)].append(r)
    for k in cells:
        cells[k].sort(key=lambda r: (-int(r.get("province_n") or 0), int(r.get("state_id") or 0)))
    # Round-robin per-cell heads
    out: List[Dict[str, Any]] = []
    seen: set = set()
    depth = 0
    cell_keys = sorted(cells.keys())
    while len(out) < budget and depth < 32:
        progress = False
        for ck in cell_keys:
            group = cells[ck]
            if depth >= len(group):
                continue
            r = group[depth]
            sid = int(r["state_id"])
            if sid in seen:
                continue
            seen.add(sid)
            out.append(r)
            progress = True
            if len(out) >= budget:
                break
        if not progress:
            break
        depth += 1
    return out


def europe_theater_label_count(rows: List[Dict[str, Any]]) -> int:
    return sum(1 for r in rows if bool(r.get("is_europe_nuts")))


def maginot_theater_named_hits(rows: List[Dict[str, Any]]) -> List[str]:
    """Names useful on first-session GER/FRA war path."""
    keys = (
        "alsace",
        "lorraine",
        "baden",
        "rhineland",
        "bavaria",
        "prussia",
        "silesia",
        "pomerania",
        "warsaw",
        "paris",
        "berlin",
        "ile-de-france",
        "île-de-france",
        "champagne",
        "burgundy",
        "flanders",
        "wallonia",
        "saxony",
        "hessen",
        "westphalia",
    )
    hits: List[str] = []
    for r in rows:
        n = str(r.get("name") or "").lower()
        if any(k in n for k in keys):
            hits.append(str(r.get("name") or ""))
    return hits


def build_map_state_labels_surface_product(
    board_dir: str = "",
    tier: str = "operational",
    map_mode: str = "states",
    max_labels: int = 96,
) -> Dict[str, Any]:
    show = show_state_labels_for_context(tier, map_mode)
    rows = build_state_label_rows(board_dir=board_dir, max_labels=max_labels)
    # Sample Europe state name present
    names = [str(r.get("name") or "") for r in rows]
    has_named = any(n and not n.startswith("State ") for n in names)
    eu_n = europe_theater_label_count(rows)
    mag_hits = maginot_theater_named_hits(rows)
    ok = len(rows) >= 20 and has_named and eu_n >= 12
    legend = (
        "State labels · %s @ %s · n=%d eu=%d · %s"
        % (map_mode, tier, len(rows), eu_n, "visible" if show else "hidden")
    )
    return {
        "ok": ok,
        "empty": len(rows) == 0,
        "show": show,
        "tier": tier,
        "map_mode": map_mode,
        "font_px": state_label_font_px_for_tier(tier),
        "label_n": len(rows),
        "europe_label_n": eu_n,
        "maginot_theater_names": mag_hits,
        "maginot_theater_hit_n": len(mag_hits),
        "labels": rows,
        "sample_names": names[:8],
        "has_named_states": has_named,
        "legend": legend,
        "summary": legend,
        "hotkey": "Shift+F9",
        "action": "states_mapmode_state_labels",
        "policy": "states_mode_and_operational_only+europe_quota_geo_grid",
    }


def map_state_labels_surface_integrity() -> Dict[str, Any]:
    fails: List[str] = []
    passes: List[str] = []
    # Policy pure
    if show_state_labels_for_context("operational", "states"):
        passes.append("policy_op_states")
    else:
        fails.append("policy_op_states")
    if not show_state_labels_for_context("strategic", "states"):
        passes.append("policy_hide_strategic")
    else:
        fails.append("policy_hide_strategic")
    if not show_state_labels_for_context("operational", "political"):
        passes.append("policy_hide_political")
    else:
        fails.append("policy_hide_political")

    p = build_map_state_labels_surface_product()
    if p.get("ok") and int(p.get("label_n") or 0) >= 20:
        passes.append("board_labels=%d" % int(p["label_n"]))
    else:
        fails.append("board_labels_low")
    if int(p.get("europe_label_n") or 0) >= 12:
        passes.append("europe_labels=%d" % int(p["europe_label_n"]))
    else:
        fails.append("europe_labels_low=%s" % p.get("europe_label_n"))
    if int(p.get("maginot_theater_hit_n") or 0) >= 2:
        passes.append("maginot_names=%s" % p.get("maginot_theater_names"))
    else:
        fails.append("maginot_theater_thin=%s" % p.get("maginot_theater_names"))

    lod = ZOOM_LOD.read_text(encoding="utf-8") if ZOOM_LOD.is_file() else ""
    lab = LABELS.read_text(encoding="utf-8") if LABELS.is_file() else ""
    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    for needle, blob, key in (
        ("func show_state_labels", lod, "lod_show"),
        ("_state_labels", lab, "layer_state_labels"),
        ("_build_state_labels", lab, "layer_build"),
        ("_select_state_labels_for_budget", lab, "layer_budget"),
        ("europe_nuts", lab, "layer_europe_flag"),
        ("set_map_mode_context", lab, "layer_mode_ctx"),
        ("set_map_mode_context", ren, "renderer_mode_ctx"),
        ("OPERATIONAL_MAX_ZOOM", lod, "lod_operational_band"),
        ("_schedule_political_labels_rebuild", ren, "renderer_states_rebuild"),
    ):
        if needle in blob:
            passes.append(key)
        else:
            fails.append("missing_%s" % key)
    # Europe Home (~1.3) must stay operational so Alsace/Baden/Rhineland names show.
    if "OPERATIONAL_MAX_ZOOM: float = 1.55" in lod or "OPERATIONAL_MAX_ZOOM: float = 1.55" in lod.replace("\t", " "):
        passes.append("operational_max_covers_europe_home")
    else:
        fails.append("operational_max_too_low")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "pass": passes,
        "fail": fails,
        "label_n": p.get("label_n"),
        "summary": "state_labels_surface · n=%s · %s" % (p.get("label_n"), "PASS" if ok else "FAIL"),
    }
