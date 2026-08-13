"""Ops depth beyond daily-command: multi-province live plans, order panel actions,
combat phase depth, fleet patrol depth.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from daily_command_tick import (  # type: ignore
    day_apply_budget,
    multi_province_day_plan,
    daily_theater_auto_tick,
    format_command_log_surface,
    daily_apply_integrity_gate,
    command_log_entry,
)
from theater_commander import (  # type: ignore
    execute_one_order,
    order_queue_board,
    theater_daily_brief,
    apply_best_station_package,
    apply_best_assault_package,
    theater_production_auto,
)
from combat_phase_estimate import estimate_multi_phase_combat  # type: ignore
from fleet_theater_posture import plan_fleet_theater_posture  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from integrated_theater_ops import format_campaign_strip  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def multi_province_live_plan(
    province_ids: Optional[Sequence[int]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    max_provinces: int = 4,
    country_tag: str = "GER",
) -> Dict[str, Any]:
    """Rank real coastal/front province ids for auto-apply (live set, not fixed 1..5)."""
    w = dict(weather or {})
    raw = list(province_ids or [])
    # Dedup preserve order
    seen = set()
    pids: List[int] = []
    for p in raw:
        try:
            pid = int(p)
        except (TypeError, ValueError):
            continue
        if pid < 0 or pid in seen:
            continue
        seen.add(pid)
        pids.append(pid)
    if not pids:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "count": 0,
            "top": [],
            "ranked": [],
            "country_tag": country_tag,
        }
    base = multi_province_day_plan(
        province_ids=pids, weather=w, trail=trail, max_provinces=max_provinces
    )
    # Re-score with live id diversity weight
    ranked: List[Dict[str, Any]] = []
    for item in list(base.get("ranked") or []):
        pid = int(item.get("province_id", -1))
        if pid not in seen:
            continue
        score = float(item.get("score", 0.0)) + 0.01 * (pid % 7)
        ranked.append(
            {
                "province_id": pid,
                "score": score,
                "queue_count": int(item.get("queue_count", 0)),
                "brief_score": float(item.get("brief_score", 0.0)),
                "country_tag": country_tag,
            }
        )
    ranked.sort(key=lambda x: float(x.get("score", 0.0)), reverse=True)
    top = ranked[: max(1, int(max_provinces))]
    label = "Multi-province live · top %d of %d · %s" % (
        len(top),
        len(ranked),
        country_tag,
    )
    return {
        "ranked": ranked,
        "top": top,
        "count": len(top),
        "total": len(ranked),
        "country_tag": country_tag,
        "score": float(top[0]["score"]) if top else 0.0,
        "summary": label,
        "label": label,
        "plain": "\n".join(
            [label] + ["#%d · %.2f" % (t["province_id"], t["score"]) for t in top]
        ),
        "bbcode": "[color=#5ec8ff]🗺 Live multi-prov[/color] [color=#8899aa]%s[/color]" % label,
        "empty": not top,
        "integration": ["live_provinces", "day_tick"],
    }


def multi_province_daily_tick_plan(
    province_ids: Optional[Sequence[int]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    max_applies: int = 3,
    max_provinces: int = 3,
    country_tag: str = "GER",
) -> Dict[str, Any]:
    """Day tick plan across top N live provinces with shared budget."""
    w = dict(weather or {})
    live = multi_province_live_plan(
        province_ids=province_ids,
        weather=w,
        trail=trail,
        max_provinces=max_provinces,
        country_tag=country_tag,
    )
    if live.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "count": 0,
            "ticks": [],
        }
    top = list(live.get("top") or [])
    budget = day_apply_budget(
        pending_count=len(top) * 2, max_applies=max_applies, weather=w
    )
    allowed = int(budget.get("allowed", 0))
    ticks: List[Dict[str, Any]] = []
    remaining = allowed
    for item in top:
        if remaining <= 0:
            break
        pid = int(item.get("province_id", -1))
        # Per-province tick uses shared remaining as max_applies slice
        slice_n = max(1, min(remaining, 2))
        tick = daily_theater_auto_tick(
            weather=w,
            trail=trail,
            max_applies=slice_n,
            province_ids=[pid],
        )
        ticks.append({"province_id": pid, "tick": tick, "score": _score(tick, "score")})
        remaining -= int(tick.get("count", slice_n))
    label = "Multi-province day tick · %d provinces · budget left %d" % (
        len(ticks),
        max(0, remaining),
    )
    return {
        "live": live,
        "budget": budget,
        "ticks": ticks,
        "count": len(ticks),
        "applies": sum(int((t.get("tick") or {}).get("count", 0)) for t in ticks),
        "score": _score(live, "score"),
        "summary": label,
        "label": label,
        "plain": "\n".join(
            [label]
            + [
                "#%d · tick %s"
                % (t["province_id"], (t.get("tick") or {}).get("summary", "")[:40])
                for t in ticks
            ]
        ),
        "bbcode": "[color=#5ec8ff]📅 Multi-day tick[/color] [color=#8899aa]%s[/color]" % label,
        "empty": not ticks,
        "integration": ["multi_province", "daily_tick"],
    }


def order_panel_actions(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Player-visible action rows for order command panel."""
    w = dict(weather or {})
    one = execute_one_order(weather=w, trail=trail)
    station = apply_best_station_package(weather=w)
    assault = apply_best_assault_package(weather=w)
    prod = theater_production_auto(weather=w)
    queue = order_queue_board(weather=w, trail=trail)
    actions: List[Dict[str, Any]] = []
    if not one.get("empty"):
        actions.append(
            {
                "action_id": "execute_one",
                "label": "Execute top order",
                "api": "GameData.apply_execute_one_order",
                "province_id": province_id,
                "score": _score(one, "score"),
                "order": str(one.get("order", "")),
                "enabled": True,
            }
        )
    if not station.get("empty"):
        actions.append(
            {
                "action_id": "apply_station",
                "label": "Apply best station",
                "api": "MapManager.apply_fleet_station_mutation",
                "province_id": int(station.get("province_id", province_id)),
                "score": _score(station, "score"),
                "order": str((station.get("plan") or {}).get("order", "")),
                "enabled": bool(station.get("apply_ready")),
            }
        )
    if not assault.get("empty"):
        actions.append(
            {
                "action_id": "apply_assault",
                "label": "Stage best assault",
                "api": "MapManager.apply_assault_stage_mutation",
                "province_id": int(assault.get("target_province_id", province_id)),
                "score": _score(assault, "score"),
                "order": str((assault.get("plan") or {}).get("order", "")),
                "enabled": bool(assault.get("apply_ready")),
            }
        )
    top_prod = (prod.get("top") or {}) if not prod.get("empty") else {}
    if top_prod:
        plan = top_prod.get("plan") or {}
        actions.append(
            {
                "action_id": "apply_production",
                "label": "Set production priority",
                "api": "GameData.apply_production_priority_mutation",
                "province_id": province_id,
                "score": _score(prod, "score"),
                "order": str(plan.get("order", "")),
                "enabled": bool(plan.get("apply_ready", True)),
            }
        )
    if not queue.get("empty"):
        actions.append(
            {
                "action_id": "refresh_queue",
                "label": "Refresh order queue",
                "api": "MapManager.order_queue_for_province",
                "province_id": province_id,
                "score": _score(queue, "score"),
                "order": str((queue.get("top") or {}).get("order", "")),
                "enabled": True,
            }
        )
    if not actions:
        return {"empty": True, "actions": [], "plain": "", "bbcode": "", "summary": "", "count": 0}
    actions.sort(key=lambda a: float(a.get("score", 0.0)), reverse=True)
    label = "Order panel · %d actions" % len(actions)
    lines = ["%s · %s" % (a["action_id"], a["label"]) for a in actions]
    return {
        "actions": actions,
        "count": len(actions),
        "score": float(actions[0]["score"]) if actions else 0.0,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + lines),
        "bbcode": "\n".join(
            ["[color=#5ec8ff]── Order panel ──[/color]"]
            + ["[color=#8899aa]· %s[/color]" % ln for ln in lines]
        ),
        "empty": False,
        "integration": ["order_panel", "player_surface"],
    }


def order_panel_refresh_surface(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    log_trail: Optional[Sequence[Mapping[str, Any]]] = None,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Compose brief + queue + log + panel actions for UI refresh."""
    w = dict(weather or {})
    brief = theater_daily_brief(weather=w, trail=trail)
    queue = order_queue_board(weather=w, trail=trail)
    log = format_command_log_surface(log_trail)
    panel = order_panel_actions(weather=w, trail=trail, province_id=province_id)
    lines: List[str] = []
    for block in (brief, queue, panel, log):
        if block and not block.get("empty"):
            s = str(block.get("summary", "")).strip()
            if s:
                lines.append(s.split("\n")[0])
    if not lines:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    label = "Order panel surface · %d" % len(lines)
    return {
        "brief": brief,
        "queue": queue,
        "log": log,
        "panel": panel,
        "lines": lines,
        "count": len(lines),
        "score": _score(panel, "score", default=_score(brief, "score")),
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + lines),
        "bbcode": "\n".join(
            ["[color=#5ec8ff]── Orders ──[/color]"]
            + ["[color=#8899aa]· %s[/color]" % ln for ln in lines[:6]]
        ),
        "empty": False,
        "integration": ["order_panel", "brief", "queue", "log"],
    }


def combat_phase_depth(
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    attacker_supply: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Approach/engage/disengage phase depth scores (shipped combat_phase_estimate)."""
    w = dict(weather or {})
    # Map weather to combat mult proxy
    precip = float(w.get("precip_intensity", 0.0) or 0.0)
    vis = float(w.get("visibility", 1.0) or 1.0)
    weather_mult = max(0.35, min(1.15, 1.0 - precip * 0.35 + (vis - 1.0) * 0.2))
    est = estimate_multi_phase_combat(
        attacker_power=attacker_power,
        defender_power=defender_power,
        attacker_supply=attacker_supply,
        weather_mult=weather_mult,
    )
    score = float(
        est.get(
            "overall_attacker_win_chance",
            est.get("engage_win_chance", est.get("overall", est.get("score", 0.5))),
        )
        or 0.5
    )
    phases = est.get("phases")
    if isinstance(phases, (list, dict)):
        vals = []
        if isinstance(phases, dict):
            for v in phases.values():
                if isinstance(v, dict):
                    vals.append(float(v.get("score", v.get("win_chance", score))))
                elif isinstance(v, (int, float)):
                    vals.append(float(v))
        else:
            for v in phases:
                if isinstance(v, dict):
                    vals.append(float(v.get("score", v.get("win_chance", score))))
        if vals:
            score = sum(vals) / len(vals)
    label = "Combat phase depth · score %.2f · wx×%.2f" % (score, weather_mult)
    return {
        "estimate": est,
        "weather_mult": weather_mult,
        "score": score,
        "summary": label,
        "label": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]⚔ Phase depth[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["combat_phase", "weather"],
    }


def fleet_patrol_depth(
    province_ids: Optional[Sequence[int]] = None,
    fuel_level: float = 0.7,
    country_tag: str = "ENG",
    basing_level: str = "port",
) -> Dict[str, Any]:
    """Fleet patrol preference depth across candidate provinces (theater posture)."""
    ids = [int(p) for p in list(province_ids or [1, 2, 3]) if int(p) >= 0]
    if not ids:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "score": 0.0}
    inputs = [
        {
            "province_id": pid,
            "basing_level": basing_level,
            "fuel_level": fuel_level,
            "zone_relation": "contested" if i % 2 else "friendly",
            "can_service": basing_level in ("port", "major_base", "anchorage"),
        }
        for i, pid in enumerate(ids)
    ]
    plan = plan_fleet_theater_posture(inputs, default_fuel=fuel_level)
    # Score from best_score mean or non-empty plan
    rows = list(plan.get("provinces") or [])
    scores = [float(r.get("best_score", 0.0)) / 100.0 for r in rows if isinstance(r, dict)]
    score = sum(scores) / len(scores) if scores else (0.55 if not plan.get("empty") else 0.2)
    score = max(0.05, min(1.0, score))
    if fuel_level < 0.4:
        score = max(0.05, score * 0.75)
    label = "Fleet patrol depth · %d zones · score %.2f · fuel %.0f%% · %s" % (
        len(ids),
        score,
        fuel_level * 100.0,
        str(plan.get("dominant_posture", country_tag)),
    )
    return {
        "plan": plan,
        "province_ids": ids,
        "fuel_level": fuel_level,
        "score": float(score),
        "summary": label,
        "label": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]⚓ Patrol depth[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["fleet_theater_posture", "patrol"],
    }


def combat_phase_order_strip(
    weather: Optional[Mapping[str, Any]] = None,
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
) -> Dict[str, Any]:
    depth = combat_phase_depth(
        attacker_power=attacker_power,
        defender_power=defender_power,
        weather=weather,
    )
    assault = apply_best_assault_package(weather=weather)
    lines = [str(depth.get("summary", "")), str(assault.get("summary", ""))]
    lines = [ln for ln in lines if ln.strip()]
    label = "Combat phase strip · %d" % len(lines)
    return {
        "depth": depth,
        "assault": assault,
        "lines": lines,
        "count": len(lines),
        "score": _score(depth, "score"),
        "summary": label,
        "plain": "\n".join([label] + lines),
        "bbcode": "\n".join(
            ["[color=#5ec8ff]── Combat phases ──[/color]"]
            + ["[color=#8899aa]· %s[/color]" % ln for ln in lines]
        ),
        "empty": not lines,
        "integration": ["combat_phase", "assault"],
    }


def fleet_patrol_strip(
    province_ids: Optional[Sequence[int]] = None,
    fuel_level: float = 0.7,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    depth = fleet_patrol_depth(province_ids=province_ids, fuel_level=fuel_level)
    station = apply_best_station_package(weather=weather)
    lines = [str(depth.get("summary", "")), str(station.get("summary", ""))]
    lines = [ln for ln in lines if ln.strip()]
    label = "Fleet patrol strip · %d" % len(lines)
    return {
        "depth": depth,
        "station": station,
        "lines": lines,
        "count": len(lines),
        "score": _score(depth, "score"),
        "summary": label,
        "plain": "\n".join([label] + lines),
        "bbcode": "\n".join(
            ["[color=#5ec8ff]── Fleet patrol ──[/color]"]
            + ["[color=#8899aa]· %s[/color]" % ln for ln in lines]
        ),
        "empty": not lines,
        "integration": ["fleet_patrol", "station"],
    }


def ops_depth_integrity_gate(
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
    ops_mult: float = 1.0,
) -> Dict[str, Any]:
    sole = sole_mult_integrity(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk)
    day = daily_apply_integrity_gate(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk, day_mult=ops_mult
    )
    sole_ok = bool(sole.get("integrity_ok", False))
    day_ok = bool(day.get("ok", False))
    sole_health = float(sole.get("sole_health", 0.5)) * max(0.1, min(1.4, float(ops_mult)))
    stacked = sole_health * max(0.1, min(1.4, float(ops_mult)))
    ops_ok = True
    if abs(float(ops_mult) - 1.0) > 0.05:
        ops_ok = abs(stacked - sole_health) > 0.01
    ok = sole_ok and day_ok and ops_ok
    label = "Ops depth integrity %s (sole=%s day=%s ops=%s)" % (
        "PASS" if ok else "FAIL",
        "ok" if sole_ok else "fail",
        "ok" if day_ok else "fail",
        "ok" if ops_ok else "fail",
    )
    return {
        "ok": ok,
        "sole": sole,
        "daily": day,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]✓ Ops integrity[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["sole_mult", "daily_integrity", "ops_mult"],
    }


def close_ops_depth_loop(
    province_ids: Optional[Sequence[int]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Compose live multi-province + panel + combat/fleet depth + integrity."""
    w = dict(weather or {})
    foul = dict(w)
    foul["precip_intensity"] = max(0.7, float(foul.get("precip_intensity", 0.0) or 0.0) + 0.5)
    foul["visibility"] = min(0.35, float(foul.get("visibility", 1.0) or 1.0))
    ids = list(province_ids or [10, 20, 30, 40, 50])
    live = multi_province_live_plan(province_ids=ids, weather=w, trail=trail)
    multi = multi_province_daily_tick_plan(
        province_ids=ids, weather=w, trail=trail, max_applies=3, max_provinces=3
    )
    panel = order_panel_actions(weather=w, trail=trail, province_id=int(ids[0]))
    surface = order_panel_refresh_surface(weather=w, trail=trail, province_id=int(ids[0]))
    combat = combat_phase_depth(weather=w)
    fleet = fleet_patrol_depth(province_ids=ids[:3])
    gate = ops_depth_integrity_gate(ops_mult=1.1)
    live_f = multi_province_live_plan(province_ids=ids, weather=foul, trail=trail)
    wx_shift = abs(_score(live, "score") - _score(live_f, "score"))
    label = "Close-ops-depth · multi=%d · panel=%d · integrity %s" % (
        int(multi.get("count", 0)),
        int(panel.get("count", 0)),
        "PASS" if gate.get("ok") else "FAIL",
    )
    return {
        "live": live,
        "multi": multi,
        "panel": panel,
        "surface": surface,
        "combat": combat,
        "fleet": fleet,
        "integrity": gate,
        "weather_score_shift": wx_shift,
        "summary": label,
        "empty": False,
        "integration": [
            "live_multi",
            "order_panel",
            "combat_phase",
            "fleet_patrol",
            "integrity",
        ],
    }
