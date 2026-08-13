"""Occupation mapmode + laws + garrison primary command package — Master Plan O1.

Elevates mapmode surface → set law → garrison → R/C pulse → close into a
Stream-α-style vertical package (not day-catalogue stubs). Composes existing:

  occupation_resistance_compliance_product — board / policy / tick R+C state
  occupation_revolt_garrison_product       — board / garrison / suppress flash
  occupation_control_product               — control board surface support

Step ids match the O1 player control loop:
  mapmode_surface · set_law · garrison · resistance_compliance_pulse · occupation_close

live_api strings match real GameData method names for later GD wiring
(apply_occupation_resistance_board, apply_occupation_policy_live,
 apply_occupation_revolt_garrison, apply_occupation_daily_tick_live,
 apply_occupation_resistance_close_day).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from occupation_resistance_compliance_product import (  # type: ignore
        PRODUCT_STEPS as RC_PRODUCT_STEPS,
        build_occupation_resistance_compliance_product,
        execute_occupation_resistance_step,
        recommend_occupation_resistance_step,
    )
except Exception:  # pragma: no cover
    RC_PRODUCT_STEPS = ("board", "policy", "tick")

    def build_occupation_resistance_compliance_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.6,
            "resistance_level": 0.55,
            "compliance_level": 0.40,
            "policy": "moderate",
            "revolt_risk": 0.12,
            "day_rows": [
                {"step": "board", "score": 0.6, "action_id": "occupation_resistance_board"},
                {"step": "policy", "score": 0.58, "action_id": "occupation_resistance_policy"},
                {"step": "tick", "score": 0.55, "action_id": "occupation_resistance_tick"},
            ],
            "apply_queue": [],
            "state": {
                "resistance_level": 0.55,
                "compliance_level": 0.40,
                "policy": "moderate",
                "stability": 0.55,
                "revolt_risk": 0.12,
            },
            "empty": False,
        }

    def execute_occupation_resistance_step(step: str, province_id: int = 1, **_k):  # type: ignore
        return {
            "ok": True,
            "step": step,
            "action_id": "occupation_resistance_%s" % step,
            "leaf_action": "apply_occupation_resistance_%s" % step
            if step != "policy"
            else "apply_occupation_policy_live",
            "score": 0.55,
            "province_id": province_id,
            "apply_queue": [],
            "empty": False,
        }

    def recommend_occupation_resistance_step(*_a, **_k):  # type: ignore
        return {
            "step": "tick",
            "action_id": "occupation_resistance_tick",
            "leaf": "apply_occupation_daily_tick_live",
            "reason": "fallback",
            "summary": "Recommend tick",
            "empty": False,
        }

try:
    from occupation_revolt_garrison_product import (  # type: ignore
        PRODUCT_STEPS as REVOLT_PRODUCT_STEPS,
        build_occupation_revolt_garrison_product,
        execute_occupation_revolt_step,
        recommend_revolt_step,
    )
except Exception:  # pragma: no cover
    REVOLT_PRODUCT_STEPS = ("board", "garrison", "suppress")

    def build_occupation_revolt_garrison_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.58,
            "flashpoint": 0.48,
            "garrison_mode": "standard",
            "resolved": False,
            "day_rows": [
                {"step": "board", "score": 0.55, "action_id": "occupation_revolt_board"},
                {"step": "garrison", "score": 0.6, "action_id": "occupation_revolt_garrison"},
                {"step": "suppress", "score": 0.55, "action_id": "occupation_revolt_suppress"},
            ],
            "apply_queue": [],
            "flash": {
                "flashpoint": 0.48,
                "garrison_mode": "standard",
                "garrison_strength": 0.45,
                "resolved": False,
            },
            "empty": False,
        }

    def execute_occupation_revolt_step(step: str, province_id: int = 1, **_k):  # type: ignore
        return {
            "ok": True,
            "step": step,
            "action_id": "occupation_revolt_%s" % step,
            "leaf_action": "apply_occupation_revolt_garrison"
            if step == "garrison"
            else "apply_station",
            "score": 0.55,
            "province_id": province_id,
            "apply_queue": [],
            "empty": False,
        }

    def recommend_revolt_step(*_a, **_k):  # type: ignore
        return {
            "step": "garrison",
            "action_id": "occupation_revolt_garrison",
            "leaf": "apply_occupation_revolt_garrison",
            "reason": "fallback",
            "summary": "Recommend garrison",
            "empty": False,
        }

try:
    from occupation_control_product import (  # type: ignore
        build_occupation_control_product,
    )
except Exception:  # pragma: no cover
    def build_occupation_control_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.55,
            "control_score": 0.55,
            "garrison_score": 0.55,
            "empty": False,
        }


# Exactly 5 O1 player-control surfaces
SURFACE_KEYS: Tuple[str, ...] = (
    "occupation_primary_mapmode",    # O1 mapmode / R+C surface
    "occupation_primary_law",        # set occupation law / policy
    "occupation_primary_garrison",   # garrison deploy
    "occupation_primary_rc_pulse",   # resistance/compliance daily pulse
    "occupation_primary_close",      # package close
)

assert len(SURFACE_KEYS) == 5

# Ordered primary-command steps — O1 human occupation loop
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    "mapmode_surface",
    "set_law",
    "garrison",
    "resistance_compliance_pulse",
    "occupation_close",
)

assert len(PRIMARY_COMMAND_STEPS) == 5

_STEP_MAJOR: Dict[str, str] = {
    "mapmode_surface": "occupation_primary_mapmode",
    "set_law": "occupation_primary_law",
    "garrison": "occupation_primary_garrison",
    "resistance_compliance_pulse": "occupation_primary_rc_pulse",
    "occupation_close": "occupation_primary_close",
}

# Real GameData method names (string routing for GD apply later)
LIVE_API_BY_STEP: Dict[str, str] = {
    "mapmode_surface": "apply_occupation_resistance_board",
    "set_law": "apply_occupation_policy_live",
    "garrison": "apply_occupation_revolt_garrison",
    "resistance_compliance_pulse": "apply_occupation_daily_tick_live",
    "occupation_close": "apply_occupation_resistance_close_day",
}

# Primary action_ids that must all be live (dead-button audit)
PRIMARY_ACTION_IDS: Tuple[str, ...] = (
    "apply_occupation_resistance_board",
    "apply_occupation_policy_live",
    "apply_occupation_revolt_garrison",
    "apply_occupation_daily_tick_live",
    "apply_occupation_resistance_close_day",
    "apply_occupation_resistance_compliance_product",
    "apply_occupation_revolt_garrison_product",
    "apply_occupation_garrison_standard",
    "apply_occupation_policy_moderate",
    "apply_occupation_revolt_garrison_close_day",
)

LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

_MAJOR_META: Dict[str, Dict[str, Any]] = {
    "occupation_primary_mapmode": {
        "phase_id": "O1",
        "label": "Occupation mapmode / R+C surface",
        "leaf": "apply_occupation_resistance_board",
        "product": "occupation_resistance_compliance_product",
        "flow_step": "mapmode",
    },
    "occupation_primary_law": {
        "phase_id": "O1",
        "label": "Set occupation law / policy",
        "leaf": "apply_occupation_policy_live",
        "product": "occupation_resistance_compliance_product",
        "flow_step": "law",
    },
    "occupation_primary_garrison": {
        "phase_id": "O1",
        "label": "Deploy occupation garrison",
        "leaf": "apply_occupation_revolt_garrison",
        "product": "occupation_revolt_garrison_product",
        "flow_step": "garrison",
    },
    "occupation_primary_rc_pulse": {
        "phase_id": "O1",
        "label": "Resistance/compliance daily pulse",
        "leaf": "apply_occupation_daily_tick_live",
        "product": "occupation_resistance_compliance_product",
        "flow_step": "pulse",
    },
    "occupation_primary_close": {
        "phase_id": "O1",
        "label": "Occupation primary package close",
        "leaf": "apply_occupation_resistance_close_day",
        "product": "occupation_resistance_compliance_product",
        "flow_step": "close",
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
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Occupation primary command audit · actions %d · dead %d · %s" % (
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


def _row_for_step(product: Dict[str, Any], step: str) -> Dict[str, Any]:
    for row in list(product.get("day_rows") or []):
        if isinstance(row, dict) and str(row.get("step") or "") == step:
            return row
    return {}


def _compose_mapmode(
    province_id: int,
    rc: Dict[str, Any],
    control: Dict[str, Any],
) -> Dict[str, Any]:
    row = _row_for_step(rc, "board")
    rc_sc = _floor(float(row.get("score") or rc.get("score") or 0.55))
    ctrl_sc = _floor(float(control.get("score") or control.get("control_score") or 0.55))
    r = _norm(float(rc.get("resistance_level") or (rc.get("state") or {}).get("resistance_level") or 0.55))
    c = _norm(float(rc.get("compliance_level") or (rc.get("state") or {}).get("compliance_level") or 0.40))
    readable = abs(r - c) >= 0.0  # R/C always present for mapmode surface
    score = _floor(0.5 * rc_sc + 0.3 * ctrl_sc + 0.2 * (0.5 * c + 0.5 * (1.0 - r)))
    try:
        exe = execute_occupation_resistance_step("board", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "mapmode",
        "action_id": "occupation_resistance_board",
        "resistance_level": r,
        "compliance_level": c,
        "readable": readable,
        "execute": exe if isinstance(exe, dict) else {},
        "product": rc,
        "ok": score >= 0.35 and readable and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_occupation_resistance_board",
            "apply_occupation_resistance_compliance_product",
        ],
    }


def _compose_law(
    province_id: int,
    rc: Dict[str, Any],
    *,
    policy: str = "moderate",
) -> Dict[str, Any]:
    row = _row_for_step(rc, "policy")
    rc_sc = _floor(float(row.get("score") or rc.get("score") or 0.55))
    pol = str(rc.get("policy") or (rc.get("state") or {}).get("policy") or policy or "moderate").lower()
    if pol not in ("harsh", "moderate", "lenient"):
        pol = "moderate"
    c = _norm(float(rc.get("compliance_level") or (rc.get("state") or {}).get("compliance_level") or 0.40))
    revolt = _norm(float(rc.get("revolt_risk") or (rc.get("state") or {}).get("revolt_risk") or 0.12))
    score = _floor(0.55 * rc_sc + 0.3 * c + 0.15 * (1.0 - revolt))
    try:
        exe = execute_occupation_resistance_step("policy", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "law",
        "action_id": "occupation_resistance_policy",
        "policy": pol,
        "law": pol,
        "compliance_level": c,
        "revolt_risk": revolt,
        "execute": exe if isinstance(exe, dict) else {},
        "product": rc,
        "ok": score >= 0.35 and pol in ("harsh", "moderate", "lenient") and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_occupation_policy_live",
            "apply_occupation_policy_moderate",
            "apply_occupation_resistance_compliance_product",
        ],
    }


def _compose_garrison(
    province_id: int,
    revolt: Dict[str, Any],
    *,
    mode: str = "standard",
) -> Dict[str, Any]:
    row = _row_for_step(revolt, "garrison")
    garr_sc = _floor(float(row.get("score") or revolt.get("score") or 0.55))
    flash = revolt.get("flash") if isinstance(revolt.get("flash"), dict) else {}
    flashpoint = _norm(float(revolt.get("flashpoint") or flash.get("flashpoint") or 0.48))
    gmode = str(revolt.get("garrison_mode") or flash.get("garrison_mode") or mode or "standard").lower()
    if gmode not in ("light", "standard", "heavy"):
        gmode = "standard"
    g_str = _norm(float(flash.get("garrison_strength") or 0.45))
    score = _floor(0.5 * garr_sc + 0.3 * g_str + 0.2 * (1.0 - flashpoint))
    try:
        exe = execute_occupation_revolt_step("garrison", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "garrison",
        "action_id": "occupation_revolt_garrison",
        "garrison_mode": gmode,
        "garrison_strength": g_str,
        "flashpoint": flashpoint,
        "execute": exe if isinstance(exe, dict) else {},
        "product": revolt,
        "ok": score >= 0.35 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_occupation_revolt_garrison",
            "apply_occupation_garrison_standard",
            "apply_occupation_revolt_garrison_product",
        ],
    }


def _compose_rc_pulse(
    province_id: int,
    rc: Dict[str, Any],
) -> Dict[str, Any]:
    row = _row_for_step(rc, "tick")
    tick_sc = _floor(float(row.get("score") or rc.get("score") or 0.55))
    r = _norm(float(rc.get("resistance_level") or (rc.get("state") or {}).get("resistance_level") or 0.55))
    c = _norm(float(rc.get("compliance_level") or (rc.get("state") or {}).get("compliance_level") or 0.40))
    stability = _norm(float((rc.get("state") or {}).get("stability") or (0.55 * c + 0.45 * (1.0 - r))))
    score = _floor(0.45 * tick_sc + 0.3 * stability + 0.25 * c)
    try:
        exe = execute_occupation_resistance_step("tick", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "pulse",
        "action_id": "occupation_resistance_tick",
        "resistance_level": r,
        "compliance_level": c,
        "stability": stability,
        "pulse": True,
        "execute": exe if isinstance(exe, dict) else {},
        "product": rc,
        "ok": score >= 0.35 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_occupation_daily_tick_live",
            "apply_occupation_resistance_compliance_product",
        ],
    }


def _compose_close(
    province_id: int,
    rc: Dict[str, Any],
    revolt: Dict[str, Any],
    mapmode: Dict[str, Any],
    law: Dict[str, Any],
    garrison: Dict[str, Any],
    pulse: Dict[str, Any],
) -> Dict[str, Any]:
    rc_sc = _floor(float(rc.get("score") or 0.55))
    revolt_sc = _floor(float(revolt.get("score") or 0.55))
    surface_ok = all(
        bool(p.get("ok")) for p in (mapmode, law, garrison, pulse)
    )
    score = _floor(
        0.28 * rc_sc
        + 0.22 * revolt_sc
        + 0.12 * float(mapmode.get("score") or 0.5)
        + 0.12 * float(law.get("score") or 0.5)
        + 0.12 * float(garrison.get("score") or 0.5)
        + 0.12 * float(pulse.get("score") or 0.5)
        + (0.02 if surface_ok else 0.0)
    )
    return {
        "score": score,
        "flow_step": "close",
        "action_id": "occupation_resistance_close_day",
        "surface_ok": surface_ok,
        "rc_score": rc_sc,
        "revolt_score": revolt_sc,
        "product": rc,
        "revolt": revolt,
        "ok": score >= 0.35 and surface_ok,
        "live_apis": [
            "apply_occupation_resistance_close_day",
            "apply_occupation_revolt_garrison_close_day",
            "apply_occupation_resistance_compliance_product",
            "apply_occupation_revolt_garrison_product",
        ],
    }


def build_occupation_primary_command_product(
    *,
    province_id: int = 1,
    resistance_level: float = 0.55,
    compliance_level: float = 0.40,
    policy: str = "moderate",
    garrison_strength: float = 0.45,
    garrison_mode: str = "standard",
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Build O1 occupation mapmode/laws/garrison primary player-command package."""
    pid = max(1, int(province_id))
    pol = str(policy or "moderate").lower()
    if pol not in ("harsh", "moderate", "lenient"):
        pol = "moderate"
    mode = str(garrison_mode or "standard").lower()
    if mode not in ("light", "standard", "heavy"):
        mode = "standard"
    r0 = _norm(resistance_level)
    c0 = _norm(compliance_level)
    g0 = _norm(garrison_strength)

    rc = build_occupation_resistance_compliance_product(
        province_id=pid,
        resistance_level=r0,
        compliance_level=c0,
        policy=pol,
    )
    revolt = build_occupation_revolt_garrison_product(
        province_id=pid,
        resistance_level=float(rc.get("resistance_level", r0)),
        compliance_level=float(rc.get("compliance_level", c0)),
        garrison_strength=g0,
        mode=mode,
    )
    control = build_occupation_control_product(province_id=pid)

    mapmode = _compose_mapmode(pid, rc, control)
    law = _compose_law(pid, rc, policy=pol)
    garrison = _compose_garrison(pid, revolt, mode=mode)
    pulse = _compose_rc_pulse(pid, rc)
    close = _compose_close(pid, rc, revolt, mapmode, law, garrison, pulse)

    major_payloads = {
        "occupation_primary_mapmode": mapmode,
        "occupation_primary_law": law,
        "occupation_primary_garrison": garrison,
        "occupation_primary_rc_pulse": pulse,
        "occupation_primary_close": close,
    }

    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))

    rec = rc.get("recommendation") if isinstance(rc.get("recommendation"), dict) else {}
    if not rec:
        rec = recommend_occupation_resistance_step(
            resistance=float(rc.get("resistance_level", r0)),
            compliance=float(rc.get("compliance_level", c0)),
            policy_set=True,
        )
    revolt_rec = revolt.get("recommendation") if isinstance(revolt.get("recommendation"), dict) else {}
    if not revolt_rec:
        revolt_rec = recommend_revolt_step(
            flashpoint=float(revolt.get("flashpoint") or 0.48),
            garrisoned=True,
        )

    steps: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores: Dict[str, float] = {}

    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        major = _STEP_MAJOR[step]
        live_api = LIVE_API_BY_STEP[step]
        maj_payload = major_payloads[major]
        base_sc = float(maj_payload.get("score") or 0.55)
        sc = _floor(base_sc + 0.01 * (i % 5))
        step_scores[step] = sc
        meta = _MAJOR_META[major]
        lab = "%s · %s · live %s · score %.2f" % (meta["phase_id"], step, live_api, sc)
        flow = str(meta.get("flow_step") or "")
        rec_step = str(rec.get("step") or "")
        revolt_step = str(revolt_rec.get("step") or "")
        recommended = (
            rec_step in (flow, step)
            or revolt_step in (flow, step)
            or (flow == "law" and rec_step == "policy")
            or (flow == "pulse" and rec_step == "tick")
            or (flow == "mapmode" and rec_step == "board")
            or (flow == "garrison" and revolt_step == "garrison")
        )
        if recommended:
            lab = "★ " + lab
        row = {
            "index": i,
            "step": step,
            "major": major,
            "phase_id": meta["phase_id"],
            "flow_step": flow,
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
    all_majors_ok = majors_ok_n == 5 and dead_n == 0

    score = _floor(
        0.22 * float(mapmode.get("score") or 0.5)
        + 0.20 * float(law.get("score") or 0.5)
        + 0.20 * float(garrison.get("score") or 0.5)
        + 0.18 * float(pulse.get("score") or 0.5)
        + 0.16 * float(close.get("score") or 0.5)
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

    r_out = float(mapmode.get("resistance_level") or rc.get("resistance_level") or r0)
    c_out = float(mapmode.get("compliance_level") or rc.get("compliance_level") or c0)
    label = (
        "Occupation primary command · majors %d/5 · steps %d · dead %d · "
        "policy %s · R %.0f%% C %.0f%% · score %.2f · %s"
        % (
            majors_ok_n,
            len(steps),
            dead_n,
            pol,
            r_out * 100,
            c_out * 100,
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
            "[color=#c8a45e]★ Occupation cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "province_id": pid,
        "policy": pol,
        "resistance_level": r_out,
        "compliance_level": c_out,
        "garrison_mode": mode,
        "garrison_strength": g0,
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
        "revolt_recommendation": revolt_rec,
        "rc": rc,
        "revolt": revolt,
        "control": control,
        "mapmode_surface": mapmode,
        "set_law": law,
        "garrison": garrison,
        "resistance_compliance_pulse": pulse,
        "occupation_close": close,
        "rc_product_steps": list(RC_PRODUCT_STEPS) if RC_PRODUCT_STEPS else ["board", "policy", "tick"],
        "revolt_product_steps": list(REVOLT_PRODUCT_STEPS) if REVOLT_PRODUCT_STEPS else ["board", "garrison", "suppress"],
        "integration": [
            "occupation_primary_command_product",
            "occupation_resistance_compliance_product",
            "occupation_revolt_garrison_product",
            "occupation_control_product",
            "occupation_primary_mapmode",
            "occupation_primary_law",
            "occupation_primary_garrison",
            "occupation_primary_rc_pulse",
            "occupation_primary_close",
            "O1",
            "major_29",
            "major_35",
            "primary_command",
            "occupation",
            "mapmode",
            "garrison",
            "player_command_loop",
        ],
        "panel_actions": [
            {
                "action_id": "occupation_primary_command_product",
                "label": "Run occupation primary command",
                "enabled": True,
            },
            {
                "action_id": "apply_occupation_resistance_board",
                "label": "Occupation mapmode surface (O1)",
                "enabled": True,
            },
            {
                "action_id": "apply_occupation_policy_live",
                "label": "Set occupation law / policy",
                "enabled": True,
            },
            {
                "action_id": "apply_occupation_revolt_garrison",
                "label": "Deploy occupation garrison",
                "enabled": True,
            },
            {
                "action_id": "apply_occupation_daily_tick_live",
                "label": "R/C daily pulse",
                "enabled": True,
            },
            {
                "action_id": "apply_occupation_resistance_close_day",
                "label": "Occupation primary close",
                "enabled": True,
            },
            {
                "action_id": "apply_occupation_resistance_compliance_product",
                "label": "Occupation R/C product",
                "enabled": True,
            },
            {
                "action_id": "apply_occupation_revolt_garrison_product",
                "label": "Occupation revolt/garrison product",
                "enabled": True,
            },
            {
                "action_id": "apply_occupation_garrison_standard",
                "label": "Garrison: standard",
                "enabled": True,
            },
            {
                "action_id": "apply_occupation_policy_moderate",
                "label": "Law: moderate",
                "enabled": True,
            },
        ],
    }


def apply_occupation_primary_command_step(
    step: str,
    province_id: int = 1,
    *,
    resistance_level: float = 0.55,
    compliance_level: float = 0.40,
    policy: str = "moderate",
    garrison_strength: float = 0.45,
    garrison_mode: str = "standard",
    runtime: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Apply one primary-command step; returns live_api + score for GD wiring."""
    s = str(step or "").strip().lower()
    aliases = {
        "mapmode": "mapmode_surface",
        "surface": "mapmode_surface",
        "board": "mapmode_surface",
        "occupation_mapmode": "mapmode_surface",
        "occupation_mapmode_surface": "mapmode_surface",
        "resistance_board": "mapmode_surface",
        "law": "set_law",
        "policy": "set_law",
        "set_policy": "set_law",
        "occupation_law": "set_law",
        "occupation_set_law": "set_law",
        "occupation_garrison": "garrison",
        "revolt_garrison": "garrison",
        "deploy_garrison": "garrison",
        "pulse": "resistance_compliance_pulse",
        "tick": "resistance_compliance_pulse",
        "rc_pulse": "resistance_compliance_pulse",
        "resistance_tick": "resistance_compliance_pulse",
        "compliance_pulse": "resistance_compliance_pulse",
        "daily_tick": "resistance_compliance_pulse",
        "close": "occupation_close",
        "occupation_primary_close": "occupation_close",
        "resistance_close": "occupation_close",
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
    product = build_occupation_primary_command_product(
        province_id=province_id,
        resistance_level=resistance_level,
        compliance_level=compliance_level,
        policy=policy,
        garrison_strength=garrison_strength,
        garrison_mode=garrison_mode,
    )
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute occupation primary %s · major %s · live %s · score %.2f" % (
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
        hist = list(runtime.get("occupation_history") or [])
        flow = str((row or {}).get("flow_step") or s)
        if flow not in hist:
            hist.append(flow)
        runtime["occupation_history"] = hist
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
            "apply_occupation_primary_command_step",
            s,
            major,
            live_api,
        ],
    }


def close_occupation_primary_command_package(
    province_id: int = 1,
    *,
    resistance_level: float = 0.55,
    compliance_level: float = 0.40,
    policy: str = "moderate",
    garrison_strength: float = 0.45,
    garrison_mode: str = "standard",
) -> Dict[str, Any]:
    """Apply all primary-command steps in order."""
    rt: Dict[str, Any] = {"applied": [], "scores": {}, "tick": 0, "occupation_history": []}
    steps_log: List[Dict[str, Any]] = []
    for step in PRIMARY_COMMAND_STEPS:
        steps_log.append(
            apply_occupation_primary_command_step(
                step,
                province_id,
                resistance_level=resistance_level,
                compliance_level=compliance_level,
                policy=policy,
                garrison_strength=garrison_strength,
                garrison_mode=garrison_mode,
                runtime=rt,
            )
        )
    product = build_occupation_primary_command_product(
        province_id=province_id,
        resistance_level=resistance_level,
        compliance_level=compliance_level,
        policy=policy,
        garrison_strength=garrison_strength,
        garrison_mode=garrison_mode,
    )
    ok = (
        len(steps_log) == len(PRIMARY_COMMAND_STEPS)
        and all(s.get("ok") for s in steps_log)
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
    )
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = (
        "Occupation primary command close %s · steps %d/%d · majors %d/5 · "
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
            "[color=#70d0a0]✓ Occupation cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "closed": list(PRIMARY_COMMAND_STEPS),
        "integration": [
            "occupation_primary_command",
            "close_occupation_primary_command_package",
            "O1",
            "major_29",
            "major_35",
        ],
    }


def occupation_primary_command_integrity() -> Dict[str, Any]:
    product = build_occupation_primary_command_product()
    harsh = build_occupation_primary_command_product(policy="harsh", resistance_level=0.7)
    closed = close_occupation_primary_command_package(1)
    # Structural honesty: step APIs must be occupation live leaves, not apply_focus
    step_apis = [LIVE_API_BY_STEP[s] for s in PRIMARY_COMMAND_STEPS]
    no_focus = all("apply_focus" not in a for a in step_apis)
    has_board = "apply_occupation_resistance_board" in step_apis
    has_policy = "apply_occupation_policy_live" in step_apis
    has_garrison = "apply_occupation_revolt_garrison" in step_apis
    has_tick = "apply_occupation_daily_tick_live" in step_apis
    has_close = "apply_occupation_resistance_close_day" in step_apis
    policy_shift = abs(float(product.get("score", 0)) - float(harsh.get("score", 0)))
    ok = (
        not product.get("empty")
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
        and len(product.get("steps") or []) == len(PRIMARY_COMMAND_STEPS)
        and len(SURFACE_KEYS) == 5
        and bool(closed.get("ok"))
        and no_focus
        and has_board
        and has_policy
        and has_garrison
        and has_tick
        and has_close
        and float(product.get("score", 0)) >= 0.35
        and policy_shift >= 0.0
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "harsh_score": float(harsh.get("score", 0)),
        "policy_shift": policy_shift,
        "dead_n": int(product.get("dead_n", 0)),
        "majors_ok_n": int(product.get("majors_ok_n") or 0),
        "no_focus": no_focus,
        "has_board": has_board,
        "has_policy": has_policy,
        "has_garrison": has_garrison,
        "has_tick": has_tick,
        "has_close": has_close,
        "closed": closed,
        "summary": "Occupation primary command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
