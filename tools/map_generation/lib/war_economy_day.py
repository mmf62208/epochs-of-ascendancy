"""War-economy day depth: focus+production package, multi-front assault day,
theater day command strip (inspector).
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from multi_front_assault import rank_assault_targets  # type: ignore
from focus_pick_priority import rank_focus_picks  # type: ignore
from theater_ops_polish import focus_weather_aware_score  # type: ignore
from live_mutation import production_priority_mutation  # type: ignore
from gameplay_loops import oob_factory_risk_loop, war_path_urgency  # type: ignore
from theater_day_depth import (  # type: ignore
    theater_day_cabinet_package,
    joint_combat_timeline,
    convoy_supply_day_package,
)
from product_depth import weather_mult_from  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def war_economy_day_package(
    weather: Optional[Mapping[str, Any]] = None,
    focus_id: str = "industrial_effort",
    focus_base: float = 55.0,
    line_id: str = "primary",
    unit_id: str = "primary",
    completed_focuses: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Focus wx score + production priority mutation + OOB factory risk for day apply."""
    w = dict(weather or {})
    try:
        focus = focus_weather_aware_score(focus_base, focus_id, w)
    except TypeError:
        try:
            focus = focus_weather_aware_score(
                base_score=focus_base, focus_id=focus_id, weather=w
            )  # type: ignore
        except Exception:
            focus = {"score": 0.5, "summary": "focus", "empty": False}

    focuses = [
        {"id": focus_id, "base_score": focus_base},
        {"id": "military_effort", "base_score": 48.0},
        {"id": "naval_effort", "base_score": 45.0},
    ]
    try:
        ranked = rank_focus_picks(
            focuses, completed_ids=list(completed_focuses or []), year=1936
        )
    except TypeError:
        try:
            ranked = rank_focus_picks(focuses)  # type: ignore
        except Exception:
            ranked = {"best_id": focus_id, "score": 0.5, "empty": False}

    try:
        prod = production_priority_mutation(
            weather=w, line_id=line_id, unit_id=unit_id
        )
    except TypeError:
        try:
            prod = production_priority_mutation(w, line_id, unit_id)  # type: ignore
        except Exception:
            prod = {
                "apply_ready": True,
                "score": 0.55,
                "summary": "PROD PRIORITY",
                "empty": False,
            }

    oob = oob_factory_risk_loop(weather=w, base_output=1.0)
    mult = _score(oob, "mult", "effective_output", default=1.0)
    risk = max(0.0, min(1.0, 1.0 - mult))
    focus_score = _score(focus, "score", "effective", default=0.5)
    if focus_score > 2.0:
        focus_score = min(1.0, focus_score / 100.0)
    prod_score = _score(prod, "score", default=0.55)
    if prod_score > 2.0:
        prod_score = min(1.0, prod_score / 100.0)

    score = (focus_score * 0.35 + prod_score * 0.35 + (1.0 - risk) * 0.3)
    apply_ready = bool(prod.get("apply_ready", True)) and risk < 0.85
    best_focus = str(ranked.get("best_id", ranked.get("best_focus", focus_id)))
    label = "War economy day · focus %s · prod×%.2f · risk %.0f%% · score %.2f" % (
        best_focus,
        mult,
        risk * 100.0,
        score,
    )
    return {
        "focus": focus,
        "ranked_focus": ranked,
        "production": prod,
        "oob": oob,
        "best_focus": best_focus,
        "risk": risk,
        "score": score,
        "apply_ready": apply_ready,
        "actions": [
            {
                "action_id": "apply_production",
                "label": "Set production priority",
                "enabled": apply_ready,
            },
            {
                "action_id": "apply_focus",
                "label": "Hold/advance focus %s" % best_focus,
                "enabled": True,
                "focus_id": best_focus,
            },
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🏭 War economy[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "sole_mult": True,
        "integration": ["focus_wx", "production_priority", "oob_factory"],
    }


def multi_front_assault_day(
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    attacker_power: float = 100.0,
    attacker_supply: float = 0.85,
    weather: Optional[Mapping[str, Any]] = None,
    max_targets: int = 4,
) -> Dict[str, Any]:
    """Rank multi-front assault targets for day stage-assault apply queue.

    Empty targets → empty.
    """
    w = dict(weather or {})
    wmult = weather_mult_from(w)
    raw = list(targets or [])
    if not raw:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    # Inject weather_mult if missing
    fixed: List[Dict[str, Any]] = []
    for t in raw:
        if not isinstance(t, dict):
            continue
        row = dict(t)
        if "weather_mult" not in row:
            row["weather_mult"] = wmult
        fixed.append(row)

    ranked = rank_assault_targets(
        fixed,
        attacker_power=attacker_power,
        attacker_supply=attacker_supply,
        max_targets=max_targets,
    )
    if ranked.get("empty") or not ranked.get("ranked"):
        # some APIs use "targets" key
        rows = list(ranked.get("ranked") or ranked.get("targets") or ranked.get("top") or [])
    else:
        rows = list(ranked.get("ranked") or [])

    if not rows:
        # synthesize from fixed via overall
        rows = fixed[:max_targets]

    apply_queue: List[Dict[str, Any]] = []
    for r in rows[:max_targets]:
        if not isinstance(r, dict):
            continue
        pid = int(r.get("province_id", r.get("id", -1)) or -1)
        if pid < 0:
            continue
        overall = float(r.get("overall", r.get("priority", 50.0)) or 0.0)
        if overall > 2.0:
            overall = min(1.0, overall / 100.0)
        ready = overall >= 0.35
        apply_queue.append(
            {
                "province_id": pid,
                "action_id": "apply_assault",
                "score": overall,
                "enabled": ready,
                "overall": overall,
            }
        )

    if not apply_queue:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    mean = sum(float(q.get("score", 0.0)) for q in apply_queue) / float(len(apply_queue))
    ready_n = sum(1 for q in apply_queue if q.get("enabled"))
    label = "Multi-front assault day · %d targets · ready %d · score %.2f" % (
        len(apply_queue),
        ready_n,
        mean,
    )
    return {
        "ranked": ranked,
        "apply_queue": apply_queue,
        "score": mean,
        "ready_count": ready_n,
        "actions": [
            {
                "action_id": "multi_front_assault_day",
                "label": "Stage multi-front assaults",
                "enabled": ready_n > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [label]
            + [
                "#%d overall %.0f%% ready=%s"
                % (
                    int(q["province_id"]),
                    float(q.get("overall", 0.0)) * 100.0,
                    q.get("enabled"),
                )
                for q in apply_queue[:5]
            ]
        ),
        "bbcode": "[color=#ff9a6e]⚔ Multi-front day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["rank_assault", "apply_assault", "day_queue"],
    }


def theater_day_command_strip(
    cabinet: Optional[Mapping[str, Any]] = None,
    economy: Optional[Mapping[str, Any]] = None,
    multi_front: Optional[Mapping[str, Any]] = None,
    log_lines: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Inspector/command strip composing theater day surfaces (empty if all empty)."""
    lines: List[str] = []
    for block in (cabinet, economy, multi_front):
        if not block or block.get("empty"):
            continue
        s = str(block.get("summary", block.get("label", ""))).strip()
        if s:
            lines.append(s.split("\n")[0])
    for ln in list(log_lines or [])[:3]:
        t = str(ln).strip()
        if t:
            lines.append(t)
    if not lines:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "lines": [],
            "score": 0.0,
        }
    label = "Theater day command strip · %d lines" % len(lines)
    return {
        "lines": lines,
        "count": len(lines),
        "score": min(1.0, 0.2 * len(lines)),
        "summary": label,
        "plain": "\n".join([label] + lines[:8]),
        "bbcode": "\n".join(
            ["[color=#5ec8ff]── Theater day strip ──[/color]"]
            + ["[color=#8899aa]· %s[/color]" % ln for ln in lines[:8]]
        ),
        "empty": False,
        "integration": ["cabinet", "economy", "multi_front", "log"],
    }


def war_economy_theater_day(
    weather: Optional[Mapping[str, Any]] = None,
    targets: Optional[Sequence[Mapping[str, Any]]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    signal: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Compose war economy + multi-front + cabinet into one day plan with apply queue."""
    w = dict(weather or {})
    economy = war_economy_day_package(weather=w)
    fronts = multi_front_assault_day(
        targets
        or [
            {"province_id": 10, "defender_power": 70.0},
            {"province_id": 20, "defender_power": 95.0},
            {"province_id": 30, "defender_power": 55.0},
        ],
        weather=w,
    )
    cabinet = theater_day_cabinet_package(
        weather=w, signal=signal, trail=trail or []
    )
    strip = theater_day_command_strip(cabinet, economy, fronts)

    apply_queue: List[Dict[str, Any]] = []
    for a in list(economy.get("actions") or []):
        if isinstance(a, dict) and a.get("enabled", True):
            apply_queue.append(
                {
                    "action_id": a.get("action_id"),
                    "province_id": 1,
                    "score": float(economy.get("score", 0.5)),
                    "focus_id": a.get("focus_id", "industrial_effort"),
                }
            )
    for q in list(fronts.get("apply_queue") or []):
        if isinstance(q, dict) and q.get("enabled", True):
            apply_queue.append(dict(q))
    # Cap queue
    apply_queue = apply_queue[:6]

    score = (
        _score(economy, "score")
        + (0.0 if fronts.get("empty") else _score(fronts, "score"))
        + _score(cabinet, "score")
    ) / 3.0
    label = "War-economy theater day · econ %.2f · fronts %d · strip %d" % (
        _score(economy, "score"),
        len(fronts.get("apply_queue") or []),
        int(strip.get("count", 0)),
    )
    return {
        "economy": economy,
        "multi_front": fronts,
        "cabinet": cabinet,
        "strip": strip,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "war_economy_day",
                "label": "Run war-economy theater day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(economy.get("summary", "")),
                str(fronts.get("summary", "")),
                str(strip.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]⚔🏭 War-econ day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["war_economy", "multi_front", "cabinet", "strip"],
    }


def war_economy_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "War economy integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_war_economy_day_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0}
    foul = {"precip_intensity": 0.9, "visibility": 0.25, "ground_state": "mud"}
    e_c = war_economy_day_package(weather=clear)
    e_f = war_economy_day_package(weather=foul)
    mf = multi_front_assault_day(
        [
            {"province_id": 1, "defender_power": 60.0},
            {"province_id": 2, "defender_power": 110.0},
        ],
        weather=clear,
    )
    empty_mf = multi_front_assault_day([])
    day = war_economy_theater_day(
        weather=weather or clear,
        trail=[{"class": "sabotage"}],
        signal={
            "active": True,
            "action_class": "sabotage",
            "influence": 0.55,
            "province_id": 1,
        },
    )
    gate = war_economy_integrity()
    wx_shift = abs(float(e_c["score"]) - float(e_f["score"]))
    label = "Close war-economy day · Δwx %.3f · fronts %d · empty_mf %s · %s" % (
        wx_shift,
        len(mf.get("apply_queue") or []),
        empty_mf.get("empty"),
        "PASS" if gate.get("ok") else "FAIL",
    )
    return {
        "economy_clear": e_c,
        "economy_foul": e_f,
        "multi_front": mf,
        "empty_fronts": empty_mf,
        "day": day,
        "weather_score_shift": wx_shift,
        "integrity": gate,
        "summary": label,
        "empty": False,
    }
