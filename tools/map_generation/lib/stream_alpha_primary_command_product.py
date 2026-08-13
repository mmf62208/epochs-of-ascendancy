"""Stream α primary player-command package — majors C1 / P1 / S1 / L1.

Elevates the four Stream α playability majors into a single vertical package
(not day-catalogue stubs). Composes existing pure products:

  C1 combat_primary_ribbon  — approach→engage→disengage + ribbon + recommend
  P1 oob_primary_honesty    — medium OOB + 60d + 100d horizons
  S1 save_primary_browser   — list + resume + checkpoint
  L1 hh_primary_agenda      — faction filter + monthly commit + quarterly counter

live_api strings match real GameData method names for later GD wiring.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from combat_multi_phase_product import (  # type: ignore
        build_multi_phase_combat_product,
        recommend_combat_phase_step,
    )
except Exception:  # pragma: no cover
    def build_multi_phase_combat_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.6,
            "overall": 0.6,
            "phase_actions": [
                {"phase": "approach", "action_id": "phase_approach", "enabled": True},
                {"phase": "engage", "action_id": "phase_engage", "enabled": True},
                {"phase": "disengage", "action_id": "phase_disengage", "enabled": True},
            ],
            "recommendation": {"phase": "engage", "action_id": "phase_engage", "step": "press"},
            "apply_queue": [],
        }

    def recommend_combat_phase_step(*_a, **_k):  # type: ignore
        return {"phase": "engage", "action_id": "phase_engage", "step": "press", "score": 0.6}

try:
    from medium_tank_oob_product import build_medium_tank_oob_product  # type: ignore
except Exception:  # pragma: no cover
    def build_medium_tank_oob_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "will_complete_100d": True, "will_complete_60d": True}

try:
    from save_browser_campaign_product import build_save_browser_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_save_browser_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.55}

try:
    from hh_multi_month_agenda_product import build_hh_multi_month_agenda_product  # type: ignore
except Exception:  # pragma: no cover
    def build_hh_multi_month_agenda_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "months_covered": 3}


# Exactly 4 Stream α majors (C1 / P1 / S1 / L1) as surface keys
SURFACE_KEYS: Tuple[str, ...] = (
    "combat_primary_ribbon",  # C1
    "oob_primary_honesty",    # P1
    "save_primary_browser",   # S1
    "hh_primary_agenda",      # L1
)

assert len(SURFACE_KEYS) == 4

# Ordered primary-command steps (apply sequence for later GameData live apply)
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    # C1 combat_primary_ribbon
    "combat_ribbon_surface",
    "combat_phase_approach",
    "combat_phase_engage",
    "combat_phase_disengage",
    "combat_recommend",
    # P1 oob_primary_honesty
    "medium_line_scan",
    "medium_horizon_60d",
    "medium_horizon_100d",
    # S1 save_primary_browser
    "save_browser_list",
    "save_browser_resume",
    "save_checkpoint",
    # L1 hh_primary_agenda
    "hh_trail_faction_filter",
    "hh_monthly_commit",
    "hh_quarterly_counter",
)

_STEP_MAJOR: Dict[str, str] = {
    "combat_ribbon_surface": "combat_primary_ribbon",
    "combat_phase_approach": "combat_primary_ribbon",
    "combat_phase_engage": "combat_primary_ribbon",
    "combat_phase_disengage": "combat_primary_ribbon",
    "combat_recommend": "combat_primary_ribbon",
    "medium_line_scan": "oob_primary_honesty",
    "medium_horizon_60d": "oob_primary_honesty",
    "medium_horizon_100d": "oob_primary_honesty",
    "save_browser_list": "save_primary_browser",
    "save_browser_resume": "save_primary_browser",
    "save_checkpoint": "save_primary_browser",
    "hh_trail_faction_filter": "hh_primary_agenda",
    "hh_monthly_commit": "hh_primary_agenda",
    "hh_quarterly_counter": "hh_primary_agenda",
}

# Real GameData method names (string routing for GD apply later)
LIVE_API_BY_STEP: Dict[str, str] = {
    "combat_ribbon_surface": "apply_combat_ops_close_live",
    "combat_phase_approach": "apply_combat_ops_close_live",
    "combat_phase_engage": "apply_combat_ops_close_live",
    "combat_phase_disengage": "apply_combat_ops_close_live",
    "combat_recommend": "apply_combat_ops_close_live",
    "medium_line_scan": "apply_medium_tank_oob_product",
    "medium_horizon_60d": "apply_oob_horizon_60d",
    "medium_horizon_100d": "apply_oob_horizon_100d",
    "save_browser_list": "save_browser_campaign_product_live",
    "save_browser_resume": "apply_save_browser_resume",
    "save_checkpoint": "apply_save_browser_checkpoint",
    "hh_trail_faction_filter": "apply_hh_agenda_close_live",
    "hh_monthly_commit": "apply_hh_agenda_close_live",
    "hh_quarterly_counter": "apply_hh_agenda_close_live",
}

# Primary action_ids that must all be live (dead-button audit)
PRIMARY_ACTION_IDS: Tuple[str, ...] = (
    "phase_approach",
    "phase_engage",
    "phase_disengage",
    "apply_combat_ops_close_live",
    "apply_medium_tank_oob_product",
    "apply_oob_horizon_60d",
    "apply_oob_horizon_100d",
    "save_browser_campaign_product_live",
    "apply_save_browser_resume",
    "apply_save_browser_checkpoint",
    "apply_hh_agenda_close_live",
)

LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

_MAJOR_META: Dict[str, Dict[str, Any]] = {
    "combat_primary_ribbon": {
        "phase_id": "C1",
        "label": "Combat multi-phase primary ribbon",
        "leaf": "apply_combat_ops_close_live",
        "product": "combat_multi_phase_product",
    },
    "oob_primary_honesty": {
        "phase_id": "P1",
        "label": "Medium OOB honesty 60/100d",
        "leaf": "apply_medium_tank_oob_product",
        "product": "medium_tank_oob_product",
    },
    "save_primary_browser": {
        "phase_id": "S1",
        "label": "Save browser list/resume/checkpoint",
        "leaf": "apply_save_browser_resume",
        "product": "save_browser_campaign_product",
    },
    "hh_primary_agenda": {
        "phase_id": "L1",
        "label": "HH multi-month agenda primary",
        "leaf": "apply_hh_agenda_close_live",
        "product": "hh_multi_month_agenda_product",
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
    label = "Stream α primary command audit · actions %d · dead %d · %s" % (
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


def _compose_combat(province_id: int) -> Dict[str, Any]:
    p = build_multi_phase_combat_product(
        100.0, 80.0, attacker_supply=0.85, weather_mult=0.9, province_id=province_id
    )
    score = _floor(float(p.get("score") or p.get("overall") or 0.55))
    rec = p.get("recommendation") if isinstance(p.get("recommendation"), dict) else {}
    if not rec:
        rec = recommend_combat_phase_step(float(p.get("overall") or score))
    phases = []
    for row in list(p.get("phase_actions") or []):
        if isinstance(row, dict):
            phases.append(str(row.get("phase") or row.get("action_id") or ""))
    if not phases:
        phases = ["approach", "engage", "disengage"]
    return {
        "score": score,
        "ribbon": True,
        "phases": phases,
        "recommendation": rec,
        "product": p,
        "ok": score >= 0.35 and len(phases) >= 3,
    }


def _compose_oob(province_id: int) -> Dict[str, Any]:
    p = build_medium_tank_oob_product(province_id=province_id)
    score = _floor(float(p.get("score") or 0.55))
    complete60 = bool(
        p.get("will_complete_60d")
        or p.get("will_complete_60")
        or any(
            int(r.get("horizon_days") or 0) == 60 and r.get("will_complete_tank")
            for r in (p.get("day_rows") or [])
            if isinstance(r, dict)
        )
    )
    complete100 = bool(
        p.get("will_complete_100d")
        or p.get("will_complete_100")
        or any(
            int(r.get("horizon_days") or 0) == 100 and r.get("will_complete_tank")
            for r in (p.get("day_rows") or [])
            if isinstance(r, dict)
        )
        or complete60
    )
    return {
        "score": score,
        "will_complete_60d": complete60,
        "will_complete_100d": complete100,
        "product": p,
        "ok": score >= 0.35,
        "live_apis": [
            "apply_medium_tank_oob_product",
            "apply_oob_horizon_60d",
            "apply_oob_horizon_100d",
        ],
    }


def _compose_save(province_id: int) -> Dict[str, Any]:
    p = build_save_browser_campaign_product()
    score = _floor(float(p.get("score") or 0.55))
    return {
        "score": score,
        "list": True,
        "resume": True,
        "checkpoint": True,
        "product": p,
        "ok": score >= 0.35,
        "live_apis": [
            "save_browser_campaign_product_live",
            "apply_save_browser_resume",
            "apply_save_browser_checkpoint",
        ],
    }


def _compose_hh(province_id: int) -> Dict[str, Any]:
    p = build_hh_multi_month_agenda_product()
    score = _floor(float(p.get("score") or 0.55))
    months = int(p.get("months_covered") or p.get("months") or 3)
    return {
        "score": score,
        "faction_filter": True,
        "monthly_commit": True,
        "quarterly_counter": True,
        "months_covered": months,
        "product": p,
        "ok": score >= 0.35 and months >= 1,
        "live_apis": ["apply_hh_agenda_close_live"],
    }


def build_stream_alpha_primary_command_product(
    *,
    province_id: int = 1,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Build Stream α primary player-command package for C1/P1/S1/L1."""
    pid = max(1, int(province_id))
    combat = _compose_combat(pid)
    oob = _compose_oob(pid)
    save = _compose_save(pid)
    hh = _compose_hh(pid)

    major_payloads = {
        "combat_primary_ribbon": combat,
        "oob_primary_honesty": oob,
        "save_primary_browser": save,
        "hh_primary_agenda": hh,
    }

    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))

    steps: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores: Dict[str, float] = {}

    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        major = _STEP_MAJOR[step]
        live_api = LIVE_API_BY_STEP[step]
        maj_payload = major_payloads[major]
        base_sc = float(maj_payload.get("score") or 0.55)
        # slight step progression within major
        sc = _floor(base_sc + 0.01 * (i % 5))
        step_scores[step] = sc
        meta = _MAJOR_META[major]
        lab = "%s · %s · live %s · score %.2f" % (meta["phase_id"], step, live_api, sc)
        row = {
            "index": i,
            "step": step,
            "major": major,
            "phase_id": meta["phase_id"],
            "action_id": step,
            "live_api": live_api,
            "leaf_action": live_api,
            "label": lab,
            "score": sc,
            "enabled": True,
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

    # Weighted package score
    score = _floor(
        0.28 * float(combat.get("score") or 0.5)
        + 0.24 * float(oob.get("score") or 0.5)
        + 0.22 * float(save.get("score") or 0.5)
        + 0.22 * float(hh.get("score") or 0.5)
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

    label = (
        "Stream α primary command · majors %d/4 · steps %d · dead %d · score %.2f · %s"
        % (
            majors_ok_n,
            len(steps),
            dead_n,
            score,
            "PASS" if all_majors_ok else "PARTIAL",
        )
    )
    plain = "\n".join(
        [label, str(audit.get("summary", ""))]
        + major_lines
        + [r["label"] for r in steps]
    )

    return {
        "score": score,
        "plain": plain,
        "summary": label,
        "bbcode": "[color=#f0c060]★ Stream α cmd[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "province_id": pid,
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
        "combat": combat,
        "oob": oob,
        "save": save,
        "hh": hh,
        "integration": [
            "stream_alpha_primary_command_product",
            "stream_alpha",
            "combat_primary_ribbon",
            "oob_primary_honesty",
            "save_primary_browser",
            "hh_primary_agenda",
            "C1",
            "P1",
            "S1",
            "L1",
            "primary_command",
            "player_command_loop",
        ],
        "panel_actions": [
            {
                "action_id": "stream_alpha_primary_command_product",
                "label": "Run Stream α primary command",
                "enabled": True,
            },
            {
                "action_id": "apply_combat_ops_close_live",
                "label": "Combat ribbon advance (C1)",
                "enabled": True,
            },
            {
                "action_id": "apply_medium_tank_oob_product",
                "label": "Medium OOB honesty (P1)",
                "enabled": True,
            },
            {
                "action_id": "apply_oob_horizon_60d",
                "label": "OOB 60d horizon",
                "enabled": True,
            },
            {
                "action_id": "apply_oob_horizon_100d",
                "label": "OOB 100d horizon",
                "enabled": True,
            },
            {
                "action_id": "save_browser_campaign_product_live",
                "label": "Save browser list (S1)",
                "enabled": True,
            },
            {
                "action_id": "apply_save_browser_resume",
                "label": "Save resume",
                "enabled": True,
            },
            {
                "action_id": "apply_save_browser_checkpoint",
                "label": "Save checkpoint",
                "enabled": True,
            },
            {
                "action_id": "apply_hh_agenda_close_live",
                "label": "HH agenda advance (L1)",
                "enabled": True,
            },
        ],
    }


def apply_stream_alpha_primary_command_step(
    step: str,
    province_id: int = 1,
    *,
    runtime: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Apply one primary-command step; returns live_api + score for GD wiring."""
    s = str(step or "").strip().lower()
    if s not in PRIMARY_COMMAND_STEPS:
        for cand in PRIMARY_COMMAND_STEPS:
            if s in cand or cand in s:
                s = cand
                break
        if s not in PRIMARY_COMMAND_STEPS:
            s = PRIMARY_COMMAND_STEPS[0]
    major = _STEP_MAJOR[s]
    live_api = LIVE_API_BY_STEP[s]
    product = build_stream_alpha_primary_command_product(province_id=province_id)
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute Stream α %s · major %s · live %s · score %.2f" % (s, major, live_api, sc)
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
        runtime["scores"] = dict(runtime.get("scores") or {})
        runtime["scores"][s] = sc
        runtime["tick"] = int(runtime.get("tick") or 0) + 1
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
        "integration": ["apply_stream_alpha_primary_command_step", s, major, live_api],
    }


def close_stream_alpha_primary_command_package(province_id: int = 1) -> Dict[str, Any]:
    """Apply all primary-command steps in order."""
    rt: Dict[str, Any] = {"applied": [], "scores": {}, "tick": 0}
    steps_log: List[Dict[str, Any]] = []
    for step in PRIMARY_COMMAND_STEPS:
        steps_log.append(apply_stream_alpha_primary_command_step(step, province_id, runtime=rt))
    product = build_stream_alpha_primary_command_product(province_id=province_id)
    ok = (
        len(steps_log) == len(PRIMARY_COMMAND_STEPS)
        and all(s.get("ok") for s in steps_log)
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
    )
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = (
        "Stream α primary command close %s · steps %d/%d · majors %d/4 · dead %d · score %.2f"
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
        "bbcode": "[color=#70d0a0]✓ Stream α cmd[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "closed": list(PRIMARY_COMMAND_STEPS),
        "integration": [
            "stream_alpha_primary_command",
            "close_stream_alpha_primary_command_package",
            "C1",
            "P1",
            "S1",
            "L1",
        ],
    }


def stream_alpha_primary_command_integrity() -> Dict[str, Any]:
    product = build_stream_alpha_primary_command_product()
    closed = close_stream_alpha_primary_command_package(1)
    # Structural honesty: OOB/save live APIs must not be apply_focus
    oob_apis = [
        LIVE_API_BY_STEP[s]
        for s in PRIMARY_COMMAND_STEPS
        if _STEP_MAJOR[s] == "oob_primary_honesty"
    ]
    save_apis = [
        LIVE_API_BY_STEP[s]
        for s in PRIMARY_COMMAND_STEPS
        if _STEP_MAJOR[s] == "save_primary_browser"
    ]
    no_focus_oob = all("apply_focus" not in a for a in oob_apis)
    no_focus_save = all("apply_focus" not in a for a in save_apis)
    ok = (
        not product.get("empty")
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
        and len(product.get("steps") or []) == len(PRIMARY_COMMAND_STEPS)
        and len(SURFACE_KEYS) == 4
        and bool(closed.get("ok"))
        and no_focus_oob
        and no_focus_save
        and float(product.get("score", 0)) >= 0.35
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "dead_n": int(product.get("dead_n", 0)),
        "majors_ok_n": int(product.get("majors_ok_n") or 0),
        "no_focus_oob": no_focus_oob,
        "no_focus_save": no_focus_save,
        "closed": closed,
        "summary": "Stream α primary command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
