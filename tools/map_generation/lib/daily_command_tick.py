"""Daily theater auto-apply + command result log (beyond theater-command).

Pure planners: day tick packages, budgeted multi-province applies, command log
entries, day report, integrity. GD hooks game_day_advanced and real apply APIs.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from theater_commander import (  # type: ignore
    theater_daily_brief,
    order_queue_board,
    execute_one_order,
    apply_best_station_package,
    apply_best_assault_package,
    theater_production_auto,
    theater_supply_auto,
    theater_hh_auto_commit,
    theater_agent_auto_dispatch,
    command_integrity_gate,
    player_order_surface_strip,
)
from live_mutation import next_day_mutation_feedback, mutation_result  # type: ignore
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


def _avg(*vals: float) -> float:
    xs = [float(v) for v in vals]
    return float(sum(xs)) / max(1, len(xs))


def command_log_entry(
    domain: str = "fleet",
    order: str = "",
    ok: bool = False,
    reason: str = "",
    province_id: int = -1,
    score: float = 0.0,
    year: int = 1936,
    month: int = 1,
    day: int = 1,
) -> Dict[str, Any]:
    """Single apply result for command log."""
    status = "ok" if ok else "blocked"
    o = str(order or "").strip()
    label = "Cmd %s · %s · %s @#%d" % (status, domain, (o[:32] if o else "—"), int(province_id))
    return {
        "domain": str(domain),
        "order": o,
        "ok": bool(ok),
        "reason": str(reason or ""),
        "province_id": int(province_id),
        "score": float(score),
        "year": int(year),
        "month": int(month),
        "day": int(day),
        "summary": label,
        "label": label,
        "plain": label if o else "",
        "bbcode": "[color=#5ec8ff]▣ Cmd log[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["command_log", domain],
    }


def append_command_log(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    entry: Optional[Mapping[str, Any]] = None,
    max_entries: int = 12,
) -> Dict[str, Any]:
    """Append entry to command log trail; pure list management."""
    log: List[Dict[str, Any]] = [dict(e) for e in list(trail or []) if e]
    if entry and not entry.get("empty"):
        log.append(dict(entry))
    while len(log) > max(1, int(max_entries)):
        log.pop(0)
    if not log:
        return {"empty": True, "entries": [], "plain": "", "bbcode": "", "summary": "", "count": 0}
    lines = [str(e.get("summary", e.get("order", ""))).split("\n")[0] for e in log if e]
    label = "Command log · %d" % len(log)
    return {
        "entries": log,
        "count": len(log),
        "lines": lines,
        "summary": label,
        "label": label,
        "plain": "\n".join(lines),
        "bbcode": "\n".join(
            ["[color=#5ec8ff]── Command log ──[/color]"]
            + ["[color=#8899aa]· %s[/color]" % ln for ln in lines[-6:]]
        ),
        "empty": False,
        "integration": ["command_log"],
    }


def format_command_log_surface(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    max_lines: int = 6,
) -> Dict[str, Any]:
    """Player-visible command log surface; empty trail → empty."""
    log = list(trail or [])
    if not log:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    # Filter empty plain entries
    usable = [e for e in log if str(e.get("summary", e.get("order", ""))).strip()]
    if not usable:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    board = append_command_log(usable, None, max_entries=max(12, int(max_lines) * 2))
    lines = list(board.get("lines") or [])[-max(1, int(max_lines)) :]
    label = "Command log surface · %d" % len(lines)
    return {
        "count": len(lines),
        "lines": lines,
        "entries": usable[-max(1, int(max_lines)) :],
        "summary": label,
        "label": label,
        "plain": "\n".join(lines),
        "bbcode": "\n".join(
            ["[color=#5ec8ff]── Command results ──[/color]"]
            + ["[color=#8899aa]· %s[/color]" % ln for ln in lines]
        ),
        "empty": False,
        "integration": ["command_log", "player_surface"],
    }


def day_apply_budget(
    pending_count: int = 0,
    max_applies: int = 3,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Cap N applies per day; foul weather reduces budget."""
    w = dict(weather or {})
    precip = float(w.get("precip_intensity", 0.0) or 0.0)
    vis = float(w.get("visibility", 1.0) or 1.0)
    base = max(1, int(max_applies))
    # Storm / low vis: fewer ops per day
    if precip > 0.55 or vis < 0.4:
        base = max(1, base - 1)
    allowed = min(base, max(0, int(pending_count)))
    label = "Day apply budget · allow %d of %d pending (cap %d)" % (
        allowed,
        int(pending_count),
        base,
    )
    return {
        "cap": base,
        "pending": int(pending_count),
        "allowed": allowed,
        "score": float(allowed) / max(1.0, float(base)),
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]⏱ Budget[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["day_tick", "budget"],
    }


def multi_province_day_plan(
    province_ids: Optional[Sequence[int]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    max_provinces: int = 3,
) -> Dict[str, Any]:
    """Rank provinces for auto-apply budget (by queue score)."""
    w = dict(weather or {})
    pids = list(province_ids or [1, 2, 3, 4, 5])
    ranked: List[Dict[str, Any]] = []
    for pid in pids:
        # Queue score is theater-global; weight by province id stability + local brief
        brief = theater_daily_brief(weather=w, trail=trail)
        queue = order_queue_board(weather=w, trail=trail)
        score = _score(queue, "score") * (0.85 + 0.03 * (int(pid) % 5))
        ranked.append(
            {
                "province_id": int(pid),
                "score": score,
                "queue_count": int(queue.get("count", 0)),
                "brief_score": _score(brief, "score"),
            }
        )
    ranked.sort(key=lambda x: float(x.get("score", 0.0)), reverse=True)
    top = ranked[: max(1, int(max_provinces))]
    label = "Multi-province day plan · top %d of %d" % (len(top), len(ranked))
    return {
        "ranked": ranked,
        "top": top,
        "count": len(top),
        "score": float(top[0]["score"]) if top else 0.0,
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + ["#%d · %.2f" % (t["province_id"], t["score"]) for t in top]),
        "bbcode": "[color=#5ec8ff]🗺 Day plan[/color] [color=#8899aa]%s[/color]" % label,
        "empty": not top,
        "integration": ["multi_province", "day_tick"],
    }


def daily_fleet_auto_apply_plan(
    weather: Optional[Mapping[str, Any]] = None,
    formation_id: str = "fleet_div",
    country_tag: str = "ENG",
) -> Dict[str, Any]:
    """Day tick fleet: apply-best station package."""
    pkg = apply_best_station_package(
        weather=weather, formation_id=formation_id, country_tag=country_tag
    )
    plan = pkg.get("plan") or {}
    label = "Daily fleet auto-apply · ready=%s · pid=%s" % (
        plan.get("apply_ready"),
        plan.get("province_id", -1),
    )
    return {
        "package": pkg,
        "plan": plan,
        "domain": "fleet",
        "api": "GameData.apply_execute_one_order / apply_fleet_station_mutation",
        "apply_ready": bool(plan.get("apply_ready")),
        "score": _score(pkg, "score"),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, str(plan.get("order", ""))),
        "bbcode": "[color=#5ec8ff]⚓ Daily fleet[/color] [color=#8899aa]%s[/color]" % label,
        "empty": bool(pkg.get("empty")),
        "integration": ["daily_apply", "fleet"],
    }


def daily_combat_auto_apply_plan(
    weather: Optional[Mapping[str, Any]] = None,
    formation_id: str = "inf_div",
    attacker_tag: str = "GER",
) -> Dict[str, Any]:
    """Day tick combat: assault stage when PRESS ready."""
    pkg = apply_best_assault_package(
        weather=weather, formation_id=formation_id, attacker_tag=attacker_tag
    )
    plan = pkg.get("plan") or {}
    execute = bool(plan.get("execute"))
    label = "Daily combat auto-apply · step=%s · exec=%s" % (
        plan.get("step", "?"),
        execute,
    )
    return {
        "package": pkg,
        "plan": plan,
        "domain": "combat",
        "api": "MapManager.apply_assault_stage_mutation",
        "apply_ready": bool(plan.get("apply_ready")),
        "execute": execute,
        "score": _score(pkg, "score"),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, str(plan.get("order", ""))),
        "bbcode": "[color=#5ec8ff]⚔ Daily combat[/color] [color=#8899aa]%s[/color]" % label,
        "empty": bool(pkg.get("empty")),
        "integration": ["daily_apply", "combat"],
    }


def daily_production_auto_apply_plan(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Day tick production priority auto."""
    auto = theater_production_auto(weather=weather)
    top = auto.get("top") or {}
    plan = top.get("plan") or {}
    label = "Daily prod auto-apply · %s" % plan.get("priority", "?")
    return {
        "auto": auto,
        "plan": plan,
        "domain": "production",
        "api": "ProductionManager.set_unit_priority_reinforcement",
        "apply_ready": bool(plan.get("apply_ready")),
        "score": _score(auto, "score"),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, str(plan.get("order", ""))),
        "bbcode": "[color=#5ec8ff]🏭 Daily prod[/color] [color=#8899aa]%s[/color]" % label,
        "empty": bool(auto.get("empty")),
        "sole_mult": True,
        "integration": ["daily_apply", "production"],
    }


def daily_supply_auto_apply_plan(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Day tick supply route auto."""
    auto = theater_supply_auto(weather=weather)
    top = auto.get("top") or {}
    plan = top.get("plan") or {}
    label = "Daily supply auto-apply · %s" % plan.get("priority", "?")
    return {
        "auto": auto,
        "plan": plan,
        "domain": "supply",
        "api": "GameData.apply_supply_route_mutation",
        "apply_ready": bool(plan.get("apply_ready", True)),
        "score": _score(auto, "score"),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, str(plan.get("order", ""))),
        "bbcode": "[color=#5ec8ff]📦 Daily supply[/color] [color=#8899aa]%s[/color]" % label,
        "empty": bool(auto.get("empty")),
        "sole_mult": True,
        "integration": ["daily_apply", "supply"],
    }


def daily_hh_auto_apply_plan(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Day tick HH commit; empty trail → empty/skip."""
    t = list(trail or [])
    if not t:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "domain": "hh",
            "apply_ready": False,
            "plan": {},
        }
    auto = theater_hh_auto_commit(trail=t)
    if auto.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "domain": "hh",
            "apply_ready": False,
            "plan": {},
        }
    plan = auto.get("plan") or {}
    label = "Daily HH auto-apply · score %.2f" % _score(auto, "score")
    return {
        "auto": auto,
        "plan": plan,
        "domain": "hh",
        "api": "GameData.apply_hh_order_commit_mutation",
        "apply_ready": bool(plan.get("apply_ready")),
        "score": _score(auto, "score"),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, str(plan.get("order", ""))),
        "bbcode": "[color=#5ec8ff]📜 Daily HH[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["daily_apply", "hh"],
    }


def daily_agent_auto_apply_plan(
    signal: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Day tick agent dispatch."""
    auto = theater_agent_auto_dispatch(signal=signal)
    plan = auto.get("plan") or {}
    label = "Daily agent auto-apply · score %.2f" % _score(auto, "score")
    return {
        "auto": auto,
        "plan": plan,
        "domain": "agent",
        "api": "GameData.record_agent_dispatch_mutation",
        "apply_ready": bool(plan.get("apply_ready", True)),
        "score": _score(auto, "score"),
        "summary": label,
        "label": label,
        "plain": "%s\n%s" % (label, str(plan.get("order", ""))),
        "bbcode": "[color=#5ec8ff]🕵 Daily agent[/color] [color=#8899aa]%s[/color]" % label,
        "empty": bool(auto.get("empty")),
        "integration": ["daily_apply", "agent"],
    }


def simulate_day_apply_results(
    plans: Optional[Sequence[Mapping[str, Any]]] = None,
    year: int = 1936,
    month: int = 1,
    day: int = 1,
) -> Dict[str, Any]:
    """Pure: turn apply plans into command log entries (ok if apply_ready)."""
    entries: List[Dict[str, Any]] = []
    for p in list(plans or []):
        if not p or p.get("empty"):
            continue
        plan = p.get("plan") or {}
        ok = bool(p.get("apply_ready", plan.get("apply_ready", False)))
        # Combat prep-only (non-execute) still logs as ok prep
        if p.get("domain") == "combat" and not p.get("execute") and ok:
            reason = "prep_only"
        else:
            reason = "" if ok else "not_apply_ready"
        entries.append(
            command_log_entry(
                domain=str(p.get("domain", "ops")),
                order=str(plan.get("order", p.get("summary", ""))),
                ok=ok,
                reason=reason,
                province_id=int(plan.get("province_id", -1)),
                score=_score(p, "score"),
                year=year,
                month=month,
                day=day,
            )
        )
    board = append_command_log([], None)
    for e in entries:
        board = append_command_log(board.get("entries") or [], e)
    label = "Day apply results · %d entries · ok=%d" % (
        len(entries),
        sum(1 for e in entries if e.get("ok")),
    )
    return {
        "entries": entries,
        "log": board,
        "count": len(entries),
        "ok_count": sum(1 for e in entries if e.get("ok")),
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + [str(e.get("summary", "")) for e in entries]),
        "bbcode": "[color=#5ec8ff]↻ Day results[/color] [color=#8899aa]%s[/color]" % label,
        "empty": not entries,
        "integration": ["day_tick", "command_log"],
    }


def apply_result_feedback(
    before_score: float = 0.5,
    after_score: float = 0.55,
    domain: str = "fleet",
    order: str = "",
) -> Dict[str, Any]:
    """Next-day style delta on command log entries."""
    fb = next_day_mutation_feedback(
        before_score=before_score,
        after_score=after_score,
        mutation_kind=str(domain),
        order=order,
    )
    label = "Apply-result feedback · %s · %s" % (domain, fb.get("trend", "steady"))
    out = dict(fb)
    out["summary"] = label
    out["label"] = label
    out["bbcode"] = "[color=#5ec8ff]↻ Apply feedback[/color] [color=#8899aa]%s[/color]" % label
    out["integration"] = ["command_log", "feedback"]
    return out


def theater_day_report(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    log_trail: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    """Brief + log summary surface for the day."""
    brief = theater_daily_brief(weather=weather, trail=trail)
    log_surf = format_command_log_surface(log_trail)
    lines = list(brief.get("lines") or [])[:3]
    if not log_surf.get("empty"):
        lines.extend(list(log_surf.get("lines") or [])[:3])
    if not lines and brief.get("empty") and log_surf.get("empty"):
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    label = "Theater day report · brief + log · %d lines" % len(lines)
    return {
        "brief": brief,
        "log": log_surf,
        "lines": lines,
        "count": len(lines),
        "score": _score(brief, "score"),
        "summary": label,
        "label": label,
        "plain": "\n".join([label] + lines) if lines else label,
        "bbcode": "\n".join(
            ["[color=#5ec8ff]── Day report ──[/color]"]
            + ["[color=#8899aa]· %s[/color]" % ln for ln in lines]
        ),
        "empty": False,
        "integration": ["daily_brief", "command_log"],
    }


def daily_theater_auto_tick(
    weather: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    signal: Optional[Mapping[str, Any]] = None,
    max_applies: int = 3,
    year: int = 1936,
    month: int = 1,
    day: int = 1,
    province_ids: Optional[Sequence[int]] = None,
) -> Dict[str, Any]:
    """Compose full day: plans + budget + results + log + report + integrity."""
    w = dict(weather or {})
    foul = dict(w)
    foul["precip_intensity"] = max(0.7, float(foul.get("precip_intensity", 0.0) or 0.0) + 0.5)
    foul["visibility"] = min(0.35, float(foul.get("visibility", 1.0) or 1.0))

    plans = [
        daily_fleet_auto_apply_plan(weather=w),
        daily_combat_auto_apply_plan(weather=w),
        daily_production_auto_apply_plan(weather=w),
        daily_supply_auto_apply_plan(weather=w),
        daily_hh_auto_apply_plan(trail=trail),
        daily_agent_auto_apply_plan(signal=signal),
    ]
    # Drop empty HH when no trail
    plans = [p for p in plans if p and not p.get("empty")]
    budget = day_apply_budget(pending_count=len(plans), max_applies=max_applies, weather=w)
    allowed = int(budget.get("allowed", 0))
    # Prefer apply_ready + higher score
    plans_sorted = sorted(
        plans,
        key=lambda p: (1 if p.get("apply_ready") else 0, _score(p, "score")),
        reverse=True,
    )
    selected = plans_sorted[:allowed]
    results = simulate_day_apply_results(selected, year=year, month=month, day=day)
    log = format_command_log_surface(results.get("entries") or [])
    multi = multi_province_day_plan(
        province_ids=province_ids, weather=w, trail=trail, max_provinces=max_applies
    )
    report = theater_day_report(
        weather=w, trail=trail, log_trail=results.get("entries") or []
    )
    one = execute_one_order(weather=w, trail=trail)
    gate = daily_apply_integrity_gate(day_mult=1.1)

    brief_c = theater_daily_brief(weather=w, trail=trail)
    brief_f = theater_daily_brief(weather=foul, trail=trail)
    wx_shift = abs(_score(brief_c, "score") - _score(brief_f, "score"))

    label = "Daily theater auto-tick · selected %d · log %d · integrity %s" % (
        len(selected),
        int(results.get("count", 0)),
        "PASS" if gate.get("ok") else "FAIL",
    )
    return {
        "plans": plans,
        "selected": selected,
        "budget": budget,
        "results": results,
        "log": log,
        "multi": multi,
        "report": report,
        "execute_one": one,
        "integrity": gate,
        "weather_score_shift": wx_shift,
        "count": len(selected),
        "score": _avg(*[_score(p, "score") for p in selected]) if selected else 0.0,
        "summary": label,
        "label": label,
        "plain": "\n".join(
            [label]
            + [str(p.get("summary", "")) for p in selected]
            + ([str(log.get("summary", ""))] if not log.get("empty") else [])
        ),
        "bbcode": "[color=#5ec8ff]📅 Daily tick[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "day_tick",
            "budget",
            "command_log",
            "fleet",
            "combat",
            "production",
            "supply",
            "integrity",
        ],
    }


def daily_apply_integrity_gate(
    sea_mult: float = 1.1,
    weather_mult: float = 0.8,
    route_risk: float = 0.2,
    day_mult: float = 1.0,
) -> Dict[str, Any]:
    """Sole-mult + command integrity after day mults (once)."""
    sole = sole_mult_integrity(sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk)
    cmd = command_integrity_gate(
        sea_mult=sea_mult,
        weather_mult=weather_mult,
        route_risk=route_risk,
        theater_mult=day_mult,
    )
    sole_ok = bool(sole.get("integrity_ok", False))
    cmd_ok = bool(cmd.get("ok", False))
    sole_health = float(sole.get("sole_health", 0.5)) * max(0.1, min(1.4, float(day_mult)))
    stacked = sole_health * max(0.1, min(1.4, float(day_mult)))
    day_ok = True
    if abs(float(day_mult) - 1.0) > 0.05:
        day_ok = abs(stacked - sole_health) > 0.01
    ok = sole_ok and cmd_ok and day_ok
    label = "Daily apply integrity %s (sole=%s cmd=%s day=%s)" % (
        "PASS" if ok else "FAIL",
        "ok" if sole_ok else "fail",
        "ok" if cmd_ok else "fail",
        "ok" if day_ok else "fail",
    )
    return {
        "ok": ok,
        "sole": sole,
        "command": cmd,
        "summary": label,
        "label": label,
        "bbcode": "[color=#5ec8ff]✓ Day integrity[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["sole_mult", "command_integrity", "day_mult"],
    }


def command_log_strip(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    feedback: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Inspector strip of command log + optional feedback."""
    surf = format_command_log_surface(trail)
    lines: List[str] = list(surf.get("lines") or [])
    if feedback and not feedback.get("empty"):
        lines.append(str(feedback.get("summary", "")).split("\n")[0])
    if not lines:
        return {"empty": True, "plain": "", "bbcode": "", "summary": "", "count": 0}
    strip = format_campaign_strip([{"summary": ln} for ln in lines], max_lines=6)
    label = "Command log strip · %d" % len(lines)
    bb = "\n".join(
        ["[color=#5ec8ff]── Command log ──[/color]"]
        + ["[color=#8899aa]· %s[/color]" % ln for ln in lines[:6]]
    )
    out = dict(strip) if isinstance(strip, dict) else {}
    out.update(
        {
            "count": len(lines),
            "lines": lines[:6],
            "plain": "\n".join(lines[:6]),
            "bbcode": bb,
            "summary": label,
            "label": label,
            "empty": False,
            "integration": ["command_log", "strip"],
        }
    )
    return out
