"""Batch pure helpers for next-20 polish pilots (operator/inspector/supply/map)."""
from __future__ import annotations

import re
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

from play_data_dir import resolve_play_data_dir  # type: ignore
from sea_zone_control import friendly_sea_zone_multipliers, combine_path_multipliers  # type: ignore
from naval_basing import compute_naval_basing, level_rank  # type: ignore

WATERS_DISTRICT_RE = re.compile(
    r"(?i)\b(Waters[-_\s]?\d+|District\s+\d+|Far\s+East\s+Theater(?:\s+\d+)?)\b"
)
THEATER_N_RE = re.compile(r"(?i)\bTheater\s+\d+\b")


def classify_soft_gazetteer_name(name: str) -> Dict[str, Any]:
    """Softer residual patterns (Waters-N / District N) beyond hard robotic gate."""
    n = str(name or "").strip()
    soft = bool(WATERS_DISTRICT_RE.search(n))
    return {
        "name": n,
        "soft_residual": soft,
        "ok": bool(n) and not soft,
    }


def audit_soft_gazetteer(names: Sequence[Any]) -> Dict[str, Any]:
    total = 0
    soft = 0
    samples: List[str] = []
    for item in names or []:
        if isinstance(item, dict):
            n = item.get("name", "")
        else:
            n = item
        c = classify_soft_gazetteer_name(str(n))
        total += 1
        if c["soft_residual"]:
            soft += 1
            if len(samples) < 15:
                samples.append(c["name"])
    return {
        "total": total,
        "soft_residual": soft,
        "ok": soft == 0 and total > 0,
        "samples": samples,
        "summary": "soft gazetteer residual=%d of %d" % (soft, total),
    }


def format_scenario_data_dir_banner(
    scenario_id: str = "world_full",
    explicit_dir: str = "",
) -> Dict[str, Any]:
    res = resolve_play_data_dir(scenario_id, explicit_dir=explicit_dir)
    warn = str(res.get("warning") or "")
    line = "Data: %s · scenario %s" % (res["data_dir"], scenario_id or "?")
    if warn:
        line += " · ⚠ %s" % warn
    elif res.get("is_default_play"):
        line += " · default play board"
    return {
        "line": line,
        "bbcode": "[color=#8899aa]%s[/color]" % line,
        "data_dir": res["data_dir"],
        "is_default_play": bool(res.get("is_default_play")),
        "warning": warn,
        "resolve": res,
    }


def inspector_section_collapse(
    sections: Sequence[Mapping[str, Any]],
    *,
    compact: bool = True,
    max_expanded: int = 3,
) -> Dict[str, Any]:
    """Decide which inspector sections start expanded vs collapsed."""
    out = []
    expanded = 0
    for i, sec in enumerate(sections or []):
        if not isinstance(sec, dict):
            continue
        kind = str(sec.get("kind", sec.get("id", "body")))
        priority = int(sec.get("priority", 50))
        # Always expand header/topline; collapse low-priority when compact
        force_open = kind in ("header", "topline", "situation", "hh", "naval")
        start_open = force_open or (not compact) or (expanded < max_expanded and priority >= 60)
        if start_open:
            expanded += 1
        out.append(
            {
                "id": str(sec.get("id", kind)),
                "kind": kind,
                "title": str(sec.get("title", kind)),
                "start_expanded": bool(start_open),
                "priority": priority,
            }
        )
    return {
        "sections": out,
        "expanded_count": expanded,
        "compact": bool(compact),
        "summary": "inspector expand %d/%d" % (expanded, len(out)),
    }


def format_slot_row_flair(
    slot: str,
    occupied: bool,
    *,
    scenario_id: str = "",
    player_tag: str = "",
    timestamp: str = "",
) -> Dict[str, Any]:
    name = str(slot or "slot").strip() or "slot"
    if occupied:
        bits = ["occupied"]
        if player_tag:
            bits.append(str(player_tag).upper())
        if scenario_id:
            bits.append(str(scenario_id))
        if timestamp:
            bits.append(str(timestamp)[:16])
        label = "%s · %s" % (name, " · ".join(bits))
        status = "occupied"
    else:
        label = "%s · empty" % name
        status = "empty"
    return {
        "slot": name,
        "occupied": bool(occupied),
        "status": status,
        "label": label,
        "bbcode": (
            "[color=#6ec8ff]%s[/color] [color=#8899aa]%s[/color]"
            % (name, "occupied" if occupied else "empty")
        ),
        "can_load": bool(occupied),
        "api_load": "load_game_detailed",
        "api_save": "save_game_detailed",
    }


def format_route_sealane_chip(
    supply_mult: float,
    trade_mult: float,
    *,
    relation: str = "neutral",
) -> Dict[str, Any]:
    rel = str(relation or "neutral")
    s = float(supply_mult)
    t = float(trade_mult)
    label = "sealanes %s · supply ×%.2f · trade ×%.2f" % (rel, s, t)
    return {
        "relation": rel,
        "supply_multiplier": s,
        "trade_multiplier": t,
        "label": label,
        "bbcode": "[color=#5ec8ff]🌊[/color] [color=#8899aa]%s[/color]" % label,
        "boosts": s > 1.0,
        "penalizes": s < 1.0 or t < 1.0,
    }


def choke_basing_synergy_score(
    is_chokepoint: bool,
    basing_level: str,
    basing_capacity: int = 0,
) -> Dict[str, Any]:
    rank = level_rank(basing_level)
    score = float(rank * 20 + int(basing_capacity))
    if is_chokepoint:
        score += 35.0 + rank * 10.0
    return {
        "score": score,
        "is_chokepoint": bool(is_chokepoint),
        "basing_level": str(basing_level),
        "strategic": score >= 50.0,
        "summary": "choke+basing score %.1f (%s%s)"
        % (
            score,
            basing_level,
            " · choke" if is_chokepoint else "",
        ),
    }


def capital_centroid_ok(x: float, y: float) -> Dict[str, Any]:
    fx, fy = float(x), float(y)
    finite = (fx == fx) and (fy == fy) and abs(fx) != float("inf") and abs(fy) != float("inf")
    non_origin = not (abs(fx) < 1e-9 and abs(fy) < 1e-9)
    ok = finite and non_origin
    return {
        "x": fx,
        "y": fy,
        "finite": finite,
        "non_origin": non_origin,
        "ok": ok,
    }


def audit_capital_centroids(
    points: Sequence[Mapping[str, Any]],
) -> Dict[str, Any]:
    total = 0
    bad = 0
    samples: List[Any] = []
    for p in points or []:
        if not isinstance(p, dict):
            continue
        total += 1
        c = capital_centroid_ok(float(p.get("x", 0)), float(p.get("y", 0)))
        if not c["ok"]:
            bad += 1
            if len(samples) < 10:
                samples.append(p.get("id", p))
    return {
        "total": total,
        "bad": bad,
        "ok": bad == 0 and total > 0,
        "samples": samples,
        "summary": "capitals bad=%d/%d" % (bad, total),
    }


def audit_region_theater_names(names: Sequence[str]) -> Dict[str, Any]:
    residual = 0
    samples: List[str] = []
    for n in names or []:
        s = str(n)
        if THEATER_N_RE.search(s):
            residual += 1
            if len(samples) < 10:
                samples.append(s)
    return {
        "total": len(list(names or [])),
        "theater_n_residual": residual,
        "ok": residual == 0,
        "samples": samples,
        "summary": "Theater-N residual=%d" % residual,
    }


def resource_icon_budget(
    zoom: float,
    board_size: int,
    *,
    base_budget: int = 220,
    world_board_threshold: int = 2200,
) -> Dict[str, Any]:
    """Decide resource icon budget by zoom and board size (world board tighter)."""
    z = abs(float(zoom))
    n = int(board_size)
    budget = int(base_budget)
    if n >= world_board_threshold:
        budget = 180
    if z < 0.25:
        budget = min(budget, 80)
    elif z < 0.38:
        budget = min(budget, 140)
    elif z >= 0.8:
        budget = min(budget + 40, 260)
    return {
        "budget": budget,
        "zoom": z,
        "board_size": n,
        "world_board": n >= world_board_threshold,
        "summary": "icon budget %d @ zoom %.2f (n=%d)" % (budget, z, n),
    }


def audit_map_action_flair_contracts(
    source_text: str,
    *,
    required: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Structural audit that format_*_flair helpers exist in shipped source."""
    req = list(
        required
        or (
            "format_province_select_flair",
            "format_infra_project_flair",
            "format_capture_assault_flair",  # shipped name (not format_capture_flair)
            "format_hh",
        )
    )
    missing = [r for r in req if r not in (source_text or "")]
    return {
        "required": req,
        "missing": missing,
        "ok": len(missing) == 0,
        "summary": "flair contracts missing=%d" % len(missing),
    }


def parse_oob_evidence_line(line: str) -> Dict[str, Any]:
    """Parse ScenarioLoader Daily production stockpile evidence line."""
    text = str(line or "")
    out: Dict[str, Any] = {
        "raw": text,
        "total_units": None,
        "majors_grew": None,
        "majors_total": None,
        "ok": False,
    }
    m = re.search(r"total_units\s*=\s*(\d+)", text)
    if m:
        out["total_units"] = int(m.group(1))
    m2 = re.search(r"majors_grew\s*=\s*(\d+)\s*/\s*(\d+)", text)
    if m2:
        out["majors_grew"] = int(m2.group(1))
        out["majors_total"] = int(m2.group(2))
    if (
        out["total_units"] is not None
        and out["majors_grew"] is not None
        and out["majors_total"]
    ):
        out["ok"] = (
            out["total_units"] >= 1
            and out["majors_grew"] >= 1
            and out["majors_grew"] <= out["majors_total"]
        )
        out["full_majors"] = out["majors_grew"] == out["majors_total"]
    return out
