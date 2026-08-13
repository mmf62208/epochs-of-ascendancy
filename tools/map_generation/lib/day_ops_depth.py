"""Day-ops depth: integrated daily fleet/agent/HH applies, HH agenda product screen,
naval multi-phase combat estimate (search→detect→engage→disengage pilot).
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_ops_depth import (  # type: ignore
    fleet_multi_theater_day,
    agent_auto_dispatch_day,
    combat_air_naval_joint,
)
from hh_agenda_trail import format_hh_agenda_screen  # type: ignore
from hh_agenda_actions import pick_agenda_actions  # type: ignore
from hh_monthly_brief import format_hh_monthly_brief  # type: ignore
from agent_counterplay import counterplay_options_for_signal  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


# ---------------------------------------------------------------------------
# Naval multi-phase combat estimate (pure pilot, not full BM resolver)
# ---------------------------------------------------------------------------

NAVAL_PHASES = ("search", "detect", "engage", "disengage")


def estimate_naval_multi_phase(
    attacker_power: float = 100.0,
    defender_power: float = 80.0,
    *,
    visibility: float = 1.0,
    fuel_level: float = 0.8,
    sub_heavy: bool = False,
    chokepoint: bool = False,
    attacker_order: str = "SEARCH_PATROL",
) -> Dict[str, Any]:
    """Phased naval estimate: search → detect → engage → disengage."""
    vis = max(0.15, min(1.2, float(visibility)))
    fuel = max(0.1, min(1.2, float(fuel_level)))
    atk = max(0.0, float(attacker_power)) * (0.85 + 0.15 * fuel)
    dfn = max(0.0, float(defender_power))
    order = str(attacker_order or "SEARCH_PATROL").upper()

    # Search
    spot = 0.55 * vis
    if order in ("SEARCH_PATROL", "SEARCH_AND_DESTROY", "STRIKE"):
        spot *= 1.25
    if chokepoint:
        spot *= 1.2
    if sub_heavy:
        spot *= 0.85
    search_win = max(0.08, min(0.92, spot))

    # Detect (needs search)
    detect = search_win * (0.7 + 0.3 * vis)
    if order == "AMBUSH":
        detect *= 0.9
    detect_win = max(0.08, min(0.92, detect))

    # Engage
    ratio = (atk * detect_win) / max(dfn * 0.5 + dfn * (1.0 - detect_win) * 0.5, 1e-6)
    engage_win = max(0.05, min(0.95, 0.5 + (ratio - 1.0) * 0.22))
    if fuel < 0.4:
        engage_win *= 0.85
    if sub_heavy and order in ("ASW", "SEARCH_AND_DESTROY"):
        engage_win = min(0.95, engage_win * 1.08)

    # Disengage (easier if lost engage or low fuel)
    dis_base = 0.55 if engage_win < 0.45 else 0.35
    if fuel < 0.45:
        dis_base += 0.15
    dis_win = max(0.1, min(0.9, dis_base))

    phase_rows = [
        {
            "phase": "search",
            "win_chance": search_win,
            "label": "search · spot %.0f%%" % (search_win * 100.0),
        },
        {
            "phase": "detect",
            "win_chance": detect_win,
            "label": "detect · %.0f%%" % (detect_win * 100.0),
        },
        {
            "phase": "engage",
            "win_chance": engage_win,
            "label": "engage · win %.0f%% · ratio %.2f" % (engage_win * 100.0, ratio),
        },
        {
            "phase": "disengage",
            "win_chance": dis_win,
            "label": "disengage · %.0f%%" % (dis_win * 100.0),
        },
    ]
    overall = (search_win + detect_win + engage_win) / 3.0
    score = overall * (0.9 + 0.1 * fuel)
    label = "Naval multi-phase · overall %.0f%% · %s · fuel %.0f%%" % (
        overall * 100.0,
        order,
        fuel * 100.0,
    )
    return {
        "phases": phase_rows,
        "phase_rows": phase_rows,
        "phase_count": len(phase_rows),
        "overall": overall,
        "engage_win_chance": engage_win,
        "search_win_chance": search_win,
        "score": score,
        "attacker_power": atk,
        "defender_power": dfn,
        "visibility": vis,
        "fuel_level": fuel,
        "apply_ready": overall >= 0.35 and fuel >= 0.25,
        "actions": [
            {
                "action_id": "fleet_autonomy",
                "label": "Apply naval posture from estimate",
                "enabled": fuel >= 0.25,
            }
        ],
        "summary": label,
        "plain": "\n".join([label] + [r["label"] for r in phase_rows]),
        "bbcode": "[color=#5ec8ff]⚓ Naval multi-phase[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["search", "detect", "engage", "disengage"],
    }


# ---------------------------------------------------------------------------
# HH agenda product screen
# ---------------------------------------------------------------------------


def hh_agenda_product_screen(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    signal: Optional[Mapping[str, Any]] = None,
    *,
    year: int = 1936,
    month: int = 1,
) -> Dict[str, Any]:
    """Full product HH agenda screen: sections + picks + monthly brief + commit action.

    Empty trail → empty (honest).
    """
    t = [dict(x) for x in list(trail or []) if isinstance(x, dict)]
    if not t:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "actions": [],
            "sections": [],
        }

    counter_sum = ""
    sig = dict(signal or {})
    if sig and bool(sig.get("active", True if sig else False)):
        try:
            cp = counterplay_options_for_signal(sig, max_options=2)
            counter_sum = str(cp.get("summary", ""))
        except Exception:
            counter_sum = ""

    try:
        screen = format_hh_agenda_screen(t, max_lines=8, counterplay_summary=counter_sum)
    except TypeError:
        screen = format_hh_agenda_screen(t, max_lines=8)

    if screen.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "actions": [],
            "sections": [],
        }

    try:
        picks = pick_agenda_actions(t)
    except TypeError:
        try:
            picks = pick_agenda_actions(t, max_actions=3)  # type: ignore
        except Exception:
            picks = {"empty": True, "summary": ""}

    try:
        brief = format_hh_monthly_brief(
            t, month_label="%04d-%02d" % (int(year), int(month))
        )
    except TypeError:
        try:
            brief = format_hh_monthly_brief(t)  # type: ignore
        except Exception:
            brief = {"summary": "", "empty": True}

    sections = list(screen.get("sections") or [])
    if picks and not picks.get("empty"):
        sections.append(
            {
                "id": "picks",
                "title": "Execute picks",
                "lines": list(picks.get("lines") or [picks.get("summary", "")])[:4],
            }
        )
    if brief and not brief.get("empty"):
        sections.append(
            {
                "id": "monthly",
                "title": "Monthly brief",
                "lines": [str(brief.get("summary", brief.get("plain", "")))[:160]],
            }
        )

    score = min(1.0, 0.15 * len(t) + (0.25 if not picks.get("empty") else 0.0) + 0.2)
    label = "HH agenda product · trail %d · sections %d · score %.2f" % (
        len(t),
        len(sections),
        score,
    )
    plain_parts = [label]
    for sec in sections:
        plain_parts.append("## %s" % sec.get("title", ""))
        for ln in sec.get("lines") or []:
            if str(ln).strip():
                plain_parts.append(str(ln).strip())

    return {
        "screen": screen,
        "picks": picks,
        "brief": brief,
        "sections": sections,
        "trail_len": len(t),
        "score": score,
        "actions": [
            {
                "action_id": "apply_hh_commit",
                "label": "Commit HH agenda",
                "enabled": True,
                "api": "GameData.apply_hh_order_commit_mutation",
            },
            {
                "action_id": "apply_counterplay",
                "label": "Apply counter-intel",
                "enabled": bool(sig),
            },
        ],
        "summary": label,
        "plain": "\n".join(plain_parts),
        "bbcode": "[color=#c084fc]📜 HH product[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["agenda_screen", "picks", "monthly", "commit"],
    }


# ---------------------------------------------------------------------------
# Integrated day ops plan (fleet multi + agent auto + HH commit)
# ---------------------------------------------------------------------------


def day_ops_integrated_plan(
    theaters: Optional[Sequence[Mapping[str, Any]]] = None,
    signals: Optional[Sequence[Mapping[str, Any]]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    *,
    country_tag: str = "ENG",
    max_fleet_applies: int = 2,
    max_agent_dispatches: int = 2,
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Single day plan bundling fleet multi-theater + agent auto + HH agenda product.

    Empty theaters AND empty signals AND empty trail → empty plan.
    """
    fleet = fleet_multi_theater_day(
        theaters, country_tag=country_tag, max_applies=max_fleet_applies
    )
    agent = agent_auto_dispatch_day(
        signals, max_dispatches=max_agent_dispatches
    )
    hh = hh_agenda_product_screen(trail, (signals or [None])[0] if signals else None)
    joint = combat_air_naval_joint(weather=weather or {})

    parts_empty = (
        bool(fleet.get("empty"))
        and bool(agent.get("empty"))
        and bool(hh.get("empty"))
    )
    if parts_empty:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
        }

    apply_queue: List[Dict[str, Any]] = []
    for item in list(fleet.get("apply_queue") or []):
        if isinstance(item, dict):
            apply_queue.append(dict(item))
    for item in list(agent.get("dispatch_queue") or []):
        if isinstance(item, dict):
            apply_queue.append(dict(item))
    if hh and not hh.get("empty"):
        apply_queue.append(
            {
                "action_id": "apply_hh_commit",
                "province_id": -1,
                "score": float(hh.get("score", 0.4)),
            }
        )

    score = (
        (0.0 if fleet.get("empty") else _score(fleet, "score"))
        + (0.0 if agent.get("empty") else _score(agent, "score"))
        + (0.0 if hh.get("empty") else _score(hh, "score"))
    ) / 3.0
    label = "Day ops integrated · fleet_q %d · agent_q %d · hh %s · score %.2f" % (
        len(fleet.get("apply_queue") or []),
        len(agent.get("dispatch_queue") or []),
        "yes" if not hh.get("empty") else "no",
        score,
    )
    return {
        "fleet": fleet,
        "agent": agent,
        "hh": hh,
        "joint": joint,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "day_ops_integrated",
                "label": "Run integrated day ops",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(fleet.get("summary", "")),
                str(agent.get("summary", "")),
                str(hh.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#5ec8ff]📅 Day ops[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": ["fleet_multi", "agent_auto", "hh_agenda", "day_queue"],
    }


def day_ops_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Day ops integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
        "sole": sole,
    }


def close_day_ops_loop(
    weather: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    clear = {"precip_intensity": 0.0, "visibility": 1.0}
    foul = {"precip_intensity": 0.9, "visibility": 0.25}
    n_clear = estimate_naval_multi_phase(visibility=1.0, fuel_level=0.8)
    n_foul = estimate_naval_multi_phase(visibility=0.25, fuel_level=0.8)
    n_low = estimate_naval_multi_phase(visibility=1.0, fuel_level=0.2)
    plan = day_ops_integrated_plan(
        theaters=[
            {"theater_id": "A", "province_ids": [1, 2], "fuel_level": 0.75},
            {"theater_id": "B", "province_ids": [3], "fuel_level": 0.15},
        ],
        signals=[
            {
                "active": True,
                "action_class": "sabotage",
                "influence": 0.65,
                "province_id": 1,
            }
        ],
        trail=[{"class": "sabotage", "influence": 0.55}],
        weather=weather or clear,
    )
    empty_plan = day_ops_integrated_plan([], [], [])
    hh_empty = hh_agenda_product_screen([])
    gate = day_ops_integrity()
    wx_shift = abs(float(n_clear["score"]) - float(n_foul["score"]))
    label = "Close day ops · naval Δwx %.3f · fuel_degrade %s · empty_ok %s · %s" % (
        wx_shift,
        "yes" if float(n_low["score"]) < float(n_clear["score"]) else "no",
        empty_plan.get("empty") and hh_empty.get("empty"),
        "PASS" if gate.get("ok") else "FAIL",
    )
    return {
        "naval_clear": n_clear,
        "naval_foul": n_foul,
        "naval_low_fuel": n_low,
        "plan": plan,
        "empty_plan": empty_plan,
        "hh_empty": hh_empty,
        "weather_score_shift": wx_shift,
        "integrity": gate,
        "summary": label,
        "empty": False,
    }
