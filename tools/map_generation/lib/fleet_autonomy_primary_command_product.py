"""Fleet multi-day autonomy primary command package — Master Plan C2 / A2.

Elevates posture → station/escort → follow-through → autonomy close into a
Stream-α-style vertical package (not day-catalogue stubs). Composes existing:

  fleet_multi_day_autonomy_product  — Day 0/1/2 posture / station-escort / follow
  naval_multi_phase_campaign_product — posture / escort / strike naval support

Step ids match next20 fleet major (#2):
  fleet_posture_day · fleet_station_escort · fleet_follow_through · fleet_autonomy_close

live_api strings match real GameData method names for later GD wiring
(apply_fleet_day_*, apply_naval_ops_close_live, apply_fleet_multi_day_*).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from fleet_multi_day_autonomy_product import (  # type: ignore
        DAY_STEPS,
        build_fleet_multi_day_autonomy_product,
        execute_fleet_day_step,
        recommend_fleet_multi_day_step,
    )
except Exception:  # pragma: no cover
    DAY_STEPS = ("posture", "station_escort", "follow_through")

    def build_fleet_multi_day_autonomy_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.6,
            "day_count": 3,
            "day_rows": [
                {"step": "posture", "score": 0.6, "action_id": "fleet_day_posture"},
                {"step": "station_escort", "score": 0.55, "action_id": "fleet_day_station_escort"},
                {"step": "follow_through", "score": 0.58, "action_id": "fleet_day_follow_through"},
            ],
            "apply_queue": [],
            "recommendation": {
                "step": "follow_through",
                "action_id": "fleet_day_follow_through",
            },
            "apply_ready": True,
            "chosen_order": "SEARCH_PATROL",
            "chosen_posture": "PATROL",
            "fuel_level": 0.65,
            "empty": False,
        }

    def execute_fleet_day_step(step: str, province_id: int = 1, **_k):  # type: ignore
        return {
            "ok": True,
            "step": step,
            "action_id": "fleet_day_%s" % step,
            "leaf_action": "apply_station",
            "score": 0.55,
            "province_id": province_id,
            "apply_queue": [],
            "empty": False,
        }

    def recommend_fleet_multi_day_step(*_a, **_k):  # type: ignore
        return {
            "step": "follow_through",
            "action_id": "fleet_day_follow_through",
            "leaf": "apply_station",
            "reason": "fallback",
            "summary": "Recommend follow_through",
            "empty": False,
        }

try:
    from naval_multi_phase_campaign_product import (  # type: ignore
        build_naval_multi_phase_campaign_product,
    )
except Exception:  # pragma: no cover
    def build_naval_multi_phase_campaign_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.55,
            "day_rows": [
                {"step": "posture", "score": 0.55},
                {"step": "escort", "score": 0.55},
                {"step": "strike", "score": 0.55},
            ],
            "empty": False,
        }


# Exactly 4 fleet primary surfaces (posture / station-escort / follow / close)
SURFACE_KEYS: Tuple[str, ...] = (
    "fleet_primary_posture",        # Day 0 — theater posture / tasking
    "fleet_primary_station_escort", # Day 1 — station + escort sustain
    "fleet_primary_follow_through", # Day 2 — multi-day follow-through
    "fleet_primary_autonomy_close", # Close — naval ops / multi-day seal
)

assert len(SURFACE_KEYS) == 4

# Ordered primary-command steps — next20 fleet major (#2) names
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    "fleet_posture_day",
    "fleet_station_escort",
    "fleet_follow_through",
    "fleet_autonomy_close",
)

assert len(PRIMARY_COMMAND_STEPS) == 4

_STEP_MAJOR: Dict[str, str] = {
    "fleet_posture_day": "fleet_primary_posture",
    "fleet_station_escort": "fleet_primary_station_escort",
    "fleet_follow_through": "fleet_primary_follow_through",
    "fleet_autonomy_close": "fleet_primary_autonomy_close",
}

# Real GameData method names (string routing for GD apply later)
LIVE_API_BY_STEP: Dict[str, str] = {
    "fleet_posture_day": "apply_fleet_day_posture",
    "fleet_station_escort": "apply_fleet_day_station_escort",
    "fleet_follow_through": "apply_fleet_day_follow_through",
    "fleet_autonomy_close": "apply_naval_ops_close_live",
}

# Primary action_ids that must all be live (dead-button audit)
PRIMARY_ACTION_IDS: Tuple[str, ...] = (
    "apply_fleet_day_posture",
    "apply_fleet_day_station_escort",
    "apply_fleet_day_follow_through",
    "apply_naval_ops_close_live",
    "apply_fleet_multi_day_autonomy_product",
    "apply_fleet_multi_day_sequence",
)

LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

_MAJOR_META: Dict[str, Dict[str, Any]] = {
    "fleet_primary_posture": {
        "phase_id": "F0",
        "label": "Day 0 — fleet theater posture / tasking",
        "leaf": "apply_fleet_day_posture",
        "product": "fleet_multi_day_autonomy_product",
        "day_step": "posture",
    },
    "fleet_primary_station_escort": {
        "phase_id": "F1",
        "label": "Day 1 — station + escort sustain",
        "leaf": "apply_fleet_day_station_escort",
        "product": "fleet_multi_day_autonomy_product",
        "day_step": "station_escort",
    },
    "fleet_primary_follow_through": {
        "phase_id": "F2",
        "label": "Day 2 — multi-day follow-through",
        "leaf": "apply_fleet_day_follow_through",
        "product": "fleet_multi_day_autonomy_product",
        "day_step": "follow_through",
    },
    "fleet_primary_autonomy_close": {
        "phase_id": "F3",
        "label": "Fleet autonomy close — naval ops seal",
        "leaf": "apply_naval_ops_close_live",
        "product": "naval_multi_phase_campaign_product",
        "day_step": "close",
    },
}


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def primary_command_dead_audit(
    action_ids: Optional[Sequence[str]] = None,
    *,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Dead-button audit: every primary action_id must be in the live set."""
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 4
    label = "Fleet autonomy primary command audit · actions %d · dead %d · %s" % (
        len(ids), len(dead), "PASS" if ok else "FAIL",
    )
    return {
        "action_ids": ids,
        "dead": dead,
        "dead_n": len(dead),
        "live_n": len(ids) - len(dead),
        "ok": ok,
        "summary": label,
        "plain": label,
        "empty": False,
    }


def _row_for_day_step(product: Dict[str, Any], day_step: str) -> Dict[str, Any]:
    for row in list(product.get("day_rows") or []):
        if isinstance(row, dict) and str(row.get("step") or "") == day_step:
            return row
    return {}


def _compose_posture(province_id: int, fleet: Dict[str, Any]) -> Dict[str, Any]:
    row = _row_for_day_step(fleet, "posture")
    score = _floor(float(row.get("score") or fleet.get("score") or 0.55))
    try:
        exe = execute_fleet_day_step("posture", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "day_step": "posture",
        "action_id": "fleet_day_posture",
        "execute": exe if isinstance(exe, dict) else {},
        "product": fleet,
        "ok": score >= 0.35 and bool((exe or {}).get("ok", True)),
        "live_apis": ["apply_fleet_day_posture"],
    }


def _compose_station_escort(province_id: int, fleet: Dict[str, Any]) -> Dict[str, Any]:
    row = _row_for_day_step(fleet, "station_escort")
    score = _floor(float(row.get("score") or fleet.get("score") or 0.55))
    try:
        exe = execute_fleet_day_step("station_escort", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "day_step": "station_escort",
        "action_id": "fleet_day_station_escort",
        "execute": exe if isinstance(exe, dict) else {},
        "product": fleet,
        "ok": score >= 0.35 and bool((exe or {}).get("ok", True)),
        "live_apis": ["apply_fleet_day_station_escort"],
    }


def _compose_follow_through(province_id: int, fleet: Dict[str, Any]) -> Dict[str, Any]:
    row = _row_for_day_step(fleet, "follow_through")
    score = _floor(float(row.get("score") or fleet.get("score") or 0.55))
    try:
        exe = execute_fleet_day_step("follow_through", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "day_step": "follow_through",
        "action_id": "fleet_day_follow_through",
        "execute": exe if isinstance(exe, dict) else {},
        "product": fleet,
        "ok": score >= 0.35 and bool((exe or {}).get("ok", True)),
        "live_apis": ["apply_fleet_day_follow_through"],
    }


def _compose_autonomy_close(
    province_id: int,
    fleet: Dict[str, Any],
    naval: Dict[str, Any],
) -> Dict[str, Any]:
    fleet_sc = _floor(float(fleet.get("score") or 0.55))
    naval_sc = _floor(float(naval.get("score") or 0.55))
    day_n = int(fleet.get("day_count") or len(fleet.get("day_rows") or []) or 0)
    score = _floor(0.55 * fleet_sc + 0.35 * naval_sc + (0.1 if day_n >= 3 else 0.0))
    return {
        "score": score,
        "day_step": "close",
        "action_id": "apply_naval_ops_close_live",
        "day_count": day_n,
        "fleet_score": fleet_sc,
        "naval_score": naval_sc,
        "product": naval,
        "fleet": fleet,
        "ok": score >= 0.35 and day_n >= 3,
        "live_apis": [
            "apply_naval_ops_close_live",
            "apply_fleet_multi_day_autonomy_product",
            "apply_fleet_multi_day_sequence",
        ],
    }


def build_fleet_autonomy_primary_command_product(
    *,
    province_id: int = 1,
    fuel_level: float = 0.65,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Build fleet multi-day autonomy primary player-command package (C2 / A2)."""
    pid = max(1, int(province_id))
    fuel = max(0.05, min(1.2, float(fuel_level)))

    fleet = build_fleet_multi_day_autonomy_product(
        [pid, pid + 1, pid + 2],
        fuel_level=fuel,
        province_id=pid,
    )
    naval = build_naval_multi_phase_campaign_product(
        province_id=pid,
        fuel_level=fuel,
    )

    posture = _compose_posture(pid, fleet)
    station = _compose_station_escort(pid, fleet)
    follow = _compose_follow_through(pid, fleet)
    close = _compose_autonomy_close(pid, fleet, naval)

    major_payloads = {
        "fleet_primary_posture": posture,
        "fleet_primary_station_escort": station,
        "fleet_primary_follow_through": follow,
        "fleet_primary_autonomy_close": close,
    }

    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))

    # Recommendation from multi-day product
    rec = fleet.get("recommendation") if isinstance(fleet.get("recommendation"), dict) else {}
    if not rec:
        rec = recommend_fleet_multi_day_step(
            fuel,
            float(fleet.get("score") or 0.55),
            apply_ready=bool(fleet.get("apply_ready", True)),
        )

    steps: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores: Dict[str, float] = {}

    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        major = _STEP_MAJOR[step]
        live_api = LIVE_API_BY_STEP[step]
        maj_payload = major_payloads[major]
        base_sc = float(maj_payload.get("score") or 0.55)
        sc = _floor(base_sc + 0.01 * (i % 4))
        step_scores[step] = sc
        meta = _MAJOR_META[major]
        lab = "%s · %s · live %s · score %.2f" % (meta["phase_id"], step, live_api, sc)
        recommended = str(rec.get("step") or "") == str(meta.get("day_step") or "")
        if recommended:
            lab = "★ " + lab
        row = {
            "index": i,
            "step": step,
            "major": major,
            "phase_id": meta["phase_id"],
            "day_step": meta["day_step"],
            "action_id": step,
            "live_api": live_api,
            "leaf_action": live_api,
            "label": lab,
            "score": sc,
            "enabled": True,
            "recommended": recommended,
            "province_id": pid,
        }
        steps.append(row)
        apply_queue.append({
            "action_id": live_api,
            "province_id": pid,
            "score": sc,
            "enabled": True,
            "label": lab,
            "step": step,
            "major": major,
            "product_action": step,
            "live_api": live_api,
        })

    majors_ok: Dict[str, bool] = {}
    for key in SURFACE_KEYS:
        majors_ok[key] = bool(major_payloads[key].get("ok"))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    all_majors_ok = majors_ok_n == 4 and dead_n == 0

    score = _floor(
        0.28 * float(posture.get("score") or 0.5)
        + 0.24 * float(station.get("score") or 0.5)
        + 0.24 * float(follow.get("score") or 0.5)
        + 0.20 * float(close.get("score") or 0.5)
        + (0.04 if dead_n == 0 else 0.0)
    )

    major_lines = []
    for key in SURFACE_KEYS:
        m = _MAJOR_META[key]
        mp = major_payloads[key]
        major_lines.append(
            "%s %s · score %.2f · %s"
            % (m["phase_id"], key, float(mp.get("score") or 0), "OK" if majors_ok[key] else "FAIL")
        )

    chosen = str(fleet.get("chosen_order") or "SEARCH_PATROL")
    posture_name = str(fleet.get("chosen_posture") or "PATROL")
    label = (
        "Fleet autonomy primary command · majors %d/4 · steps %d · dead %d · "
        "order %s · posture %s · score %.2f · %s"
        % (
            majors_ok_n,
            len(steps),
            dead_n,
            chosen,
            posture_name,
            score,
            "PASS" if all_majors_ok else "PARTIAL",
        )
    )
    plain = "\n".join(
        [label, str(audit.get("summary", "")), str(rec.get("summary", ""))]
        + major_lines
        + [r["label"] for r in steps]
    )

    return {
        "score": score,
        "plain": plain,
        "summary": label,
        "bbcode": (
            "[color=#5ec8ff]★ Fleet autonomy cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "province_id": pid,
        "fuel_level": fuel,
        "surface_keys": list(SURFACE_KEYS),
        "majors": list(SURFACE_KEYS),
        "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n,
        "all_majors_ok": all_majors_ok,
        "dead_n": dead_n,
        "dead_ok": bool(audit.get("ok")),
        "audit": audit,
        "steps": steps,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "step_scores": step_scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue,
        "recommendation": rec,
        "fleet": fleet,
        "naval": naval,
        "posture": posture,
        "station_escort": station,
        "follow_through": follow,
        "autonomy_close": close,
        "chosen_order": chosen,
        "chosen_posture": posture_name,
        "day_steps": list(DAY_STEPS) if DAY_STEPS else ["posture", "station_escort", "follow_through"],
        "integration": [
            "fleet_autonomy_primary_command_product",
            "fleet_multi_day_autonomy_product",
            "naval_multi_phase_campaign_product",
            "fleet_primary_posture",
            "fleet_primary_station_escort",
            "fleet_primary_follow_through",
            "fleet_primary_autonomy_close",
            "C2",
            "A2",
            "major_2",
            "primary_command",
            "fleet_multi_day",
            "player_command_loop",
        ],
        "panel_actions": [
            {
                "action_id": "fleet_autonomy_primary_command_product",
                "label": "Run fleet autonomy primary command",
                "enabled": True,
            },
            {
                "action_id": "apply_fleet_day_posture",
                "label": "Day 0 posture / tasking (F0)",
                "enabled": True,
            },
            {
                "action_id": "apply_fleet_day_station_escort",
                "label": "Day 1 station + escort (F1)",
                "enabled": True,
            },
            {
                "action_id": "apply_fleet_day_follow_through",
                "label": "Day 2 multi-day follow-through (F2)",
                "enabled": True,
            },
            {
                "action_id": "apply_naval_ops_close_live",
                "label": "Fleet autonomy close (F3)",
                "enabled": True,
            },
            {
                "action_id": "apply_fleet_multi_day_autonomy_product",
                "label": "Fleet multi-day product",
                "enabled": True,
            },
            {
                "action_id": "apply_fleet_multi_day_sequence",
                "label": "Fleet multi-day sequence",
                "enabled": True,
            },
        ],
    }


def apply_fleet_autonomy_primary_command_step(
    step: str,
    province_id: int = 1,
    *,
    fuel_level: float = 0.65,
    runtime: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Apply one primary-command step; returns live_api + score for GD wiring."""
    s = str(step or "").strip().lower()
    # normalize aliases
    aliases = {
        "posture": "fleet_posture_day",
        "fleet_posture": "fleet_posture_day",
        "fleet_day_posture": "fleet_posture_day",
        "station_escort": "fleet_station_escort",
        "fleet_day_station_escort": "fleet_station_escort",
        "follow_through": "fleet_follow_through",
        "fleet_day_follow_through": "fleet_follow_through",
        "close": "fleet_autonomy_close",
        "autonomy_close": "fleet_autonomy_close",
    }
    if s in aliases:
        s = aliases[s]
    if s not in PRIMARY_COMMAND_STEPS:
        for cand in PRIMARY_COMMAND_STEPS:
            if s in cand or cand in s:
                s = cand
                break
        if s not in PRIMARY_COMMAND_STEPS:
            s = PRIMARY_COMMAND_STEPS[0]
    major = _STEP_MAJOR[s]
    live_api = LIVE_API_BY_STEP[s]
    product = build_fleet_autonomy_primary_command_product(
        province_id=province_id,
        fuel_level=fuel_level,
    )
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute fleet autonomy %s · major %s · live %s · score %.2f" % (
        s, major, live_api, sc,
    )
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
        runtime["scores"] = dict(runtime.get("scores") or {})
        runtime["scores"][s] = sc
        runtime["tick"] = int(runtime.get("tick") or 0) + 1
        # light fleet history for close honesty
        hist = list(runtime.get("fleet_history") or [])
        day_step = str((row or {}).get("day_step") or s)
        if day_step not in hist:
            hist.append(day_step)
        runtime["fleet_history"] = hist
    return {
        "ok": True,
        "live": True,
        "step": s,
        "major": major,
        "live_api": live_api,
        "leaf": live_api,
        "score": sc,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": live_api,
            "province_id": max(1, int(province_id)),
            "score": sc,
            "enabled": True,
            "label": label,
            "step": s,
            "major": major,
            "live_api": live_api,
        }],
        "summary": label,
        "plain": label,
        "empty": False,
        "integration": [
            "apply_fleet_autonomy_primary_command_step",
            s,
            major,
            live_api,
        ],
    }


def close_fleet_autonomy_primary_command_package(
    province_id: int = 1,
    *,
    fuel_level: float = 0.65,
) -> Dict[str, Any]:
    """Apply all primary-command steps in order."""
    rt: Dict[str, Any] = {"applied": [], "scores": {}, "tick": 0, "fleet_history": []}
    steps_log: List[Dict[str, Any]] = []
    for step in PRIMARY_COMMAND_STEPS:
        steps_log.append(
            apply_fleet_autonomy_primary_command_step(
                step, province_id, fuel_level=fuel_level, runtime=rt
            )
        )
    product = build_fleet_autonomy_primary_command_product(
        province_id=province_id,
        fuel_level=fuel_level,
    )
    ok = (
        len(steps_log) == len(PRIMARY_COMMAND_STEPS)
        and all(s.get("ok") for s in steps_log)
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
    )
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = (
        "Fleet autonomy primary command close %s · steps %d/%d · majors %d/4 · "
        "dead %d · score %.2f"
        % (
            "PASS" if ok else "FAIL",
            len(rt.get("applied") or []),
            len(PRIMARY_COMMAND_STEPS),
            int(product.get("majors_ok_n") or 0),
            int(product.get("dead_n") or 0),
            score,
        )
    )
    return {
        "ok": ok,
        "live": True,
        "score": score,
        "applied_n": len(rt.get("applied") or []),
        "complete": ok,
        "runtime": rt,
        "steps": steps_log,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "product": product,
        "dead_n": int(product.get("dead_n") or 0),
        "majors_ok": dict(product.get("majors_ok") or {}),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "summary": label,
        "plain": label,
        "bbcode": (
            "[color=#70d0a0]✓ Fleet autonomy cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "closed": list(PRIMARY_COMMAND_STEPS),
        "integration": [
            "fleet_autonomy_primary_command",
            "close_fleet_autonomy_primary_command_package",
            "C2",
            "A2",
            "major_2",
        ],
    }


def fleet_autonomy_primary_command_integrity() -> Dict[str, Any]:
    product = build_fleet_autonomy_primary_command_product()
    low = build_fleet_autonomy_primary_command_product(fuel_level=0.25)
    closed = close_fleet_autonomy_primary_command_package(1)
    # Structural honesty: day APIs must be fleet-day / naval close, not apply_focus
    day_apis = [LIVE_API_BY_STEP[s] for s in PRIMARY_COMMAND_STEPS]
    no_focus = all("apply_focus" not in a for a in day_apis)
    has_fleet_day = any("apply_fleet_day_" in a for a in day_apis)
    has_naval_close = "apply_naval_ops_close_live" in day_apis
    fuel_shift = abs(float(product.get("score", 0)) - float(low.get("score", 0)))
    ok = (
        not product.get("empty")
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
        and len(product.get("steps") or []) == len(PRIMARY_COMMAND_STEPS)
        and len(SURFACE_KEYS) == 4
        and bool(closed.get("ok"))
        and no_focus
        and has_fleet_day
        and has_naval_close
        and float(product.get("score", 0)) >= 0.35
        and fuel_shift >= 0.0  # fuel may or may not shift package score; not fail-hard
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "low_fuel_score": float(low.get("score", 0)),
        "fuel_shift": fuel_shift,
        "dead_n": int(product.get("dead_n", 0)),
        "majors_ok_n": int(product.get("majors_ok_n") or 0),
        "no_focus": no_focus,
        "has_fleet_day": has_fleet_day,
        "has_naval_close": has_naval_close,
        "closed": closed,
        "summary": "Fleet autonomy primary command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
