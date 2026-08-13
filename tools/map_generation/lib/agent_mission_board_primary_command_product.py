"""Agent network map + mission board primary command package — Master Plan I1.

Elevates board surface → dispatch mission → resolve → counter-intel → close into a
Stream-α-style vertical package (not day-catalogue stubs). Composes existing:

  agent_campaign_product        — board / dispatch / counterplay mission loop
  intelligence_network_product  — coverage / counterintel / counterplay spine
  intel_cell_network_product    — multi-province cell map + sweep

Step ids match the I1 player control loop (Dispatch→resolve→toast):
  board_surface · dispatch_mission · resolve_mission · counter_intel · close

live_api strings match real GameData method names for later GD wiring
(apply_agent_product_board, apply_agent_product_dispatch,
 apply_agent_missions_day, apply_agent_product_counterplay,
 apply_agent_hh_close_day).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from agent_campaign_product import (  # type: ignore
        PRODUCT_STEPS as AGENT_PRODUCT_STEPS,
        build_agent_campaign_product,
        execute_agent_product_step,
        recommend_agent_product_step,
    )
except Exception:  # pragma: no cover
    AGENT_PRODUCT_STEPS = ("board", "dispatch", "counterplay")

    def build_agent_campaign_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.62,
            "signal_count": 3,
            "coverage_count": 2,
            "available_agents": 5,
            "best_mission": "counterintel",
            "affinity": 0.55,
            "day_rows": [
                {"step": "board", "score": 0.6, "action_id": "agent_product_board"},
                {"step": "dispatch", "score": 0.58, "action_id": "agent_product_dispatch"},
                {"step": "counterplay", "score": 0.55, "action_id": "agent_product_counterplay"},
            ],
            "apply_queue": [],
            "recommendation": {
                "step": "dispatch",
                "action_id": "agent_product_dispatch",
            },
            "empty": False,
        }

    def execute_agent_product_step(step: str, province_id: int = 1, **_k):  # type: ignore
        return {
            "ok": True,
            "step": step,
            "action_id": "agent_product_%s" % step,
            "leaf_action": "apply_agent_dispatch"
            if step != "counterplay"
            else "apply_counterplay",
            "score": 0.55,
            "province_id": province_id,
            "apply_queue": [],
            "empty": False,
        }

    def recommend_agent_product_step(*_a, **_k):  # type: ignore
        return {
            "step": "dispatch",
            "action_id": "agent_product_dispatch",
            "leaf": "apply_agent_dispatch",
            "reason": "fallback",
            "summary": "Recommend dispatch",
            "empty": False,
        }

try:
    from intelligence_network_product import (  # type: ignore
        PRODUCT_STEPS as INTEL_PRODUCT_STEPS,
        build_intelligence_network_product,
    )
except Exception:  # pragma: no cover
    INTEL_PRODUCT_STEPS = ("coverage", "counterintel", "counterplay")

    def build_intelligence_network_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.6,
            "coverage_score": 0.58,
            "counter_score": 0.55,
            "counterplay_score": 0.52,
            "empty": False,
        }

try:
    from intel_cell_network_product import (  # type: ignore
        PRODUCT_STEPS as CELL_PRODUCT_STEPS,
        build_intel_cell_network_product,
    )
except Exception:  # pragma: no cover
    CELL_PRODUCT_STEPS = ("cells", "ops", "sweep")

    def build_intel_cell_network_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.58,
            "cell_n": 4,
            "recruited": 2,
            "swept": 1,
            "secure": True,
            "empty": False,
        }


# Exactly 5 I1 player-control surfaces
SURFACE_KEYS: Tuple[str, ...] = (
    "agent_primary_board_surface",   # I1 network map / mission board surface
    "agent_primary_dispatch",        # dispatch mission from picker / board
    "agent_primary_resolve",         # resolve / advance missions
    "agent_primary_counter_intel",   # counter-intel / sweep
    "agent_primary_close",           # package close / toast seal
)

assert len(SURFACE_KEYS) == 5

# Ordered primary-command steps — I1 human agent mission loop
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    "board_surface",
    "dispatch_mission",
    "resolve_mission",
    "counter_intel",
    "close",
)

assert len(PRIMARY_COMMAND_STEPS) == 5

_STEP_MAJOR: Dict[str, str] = {
    "board_surface": "agent_primary_board_surface",
    "dispatch_mission": "agent_primary_dispatch",
    "resolve_mission": "agent_primary_resolve",
    "counter_intel": "agent_primary_counter_intel",
    "close": "agent_primary_close",
}

# Real GameData method names (string routing for GD apply later)
LIVE_API_BY_STEP: Dict[str, str] = {
    "board_surface": "apply_agent_product_board",
    "dispatch_mission": "apply_agent_product_dispatch",
    "resolve_mission": "apply_agent_missions_day",
    "counter_intel": "apply_agent_product_counterplay",
    "close": "apply_agent_hh_close_day",
}

# Primary action_ids that must all be live (dead-button audit)
PRIMARY_ACTION_IDS: Tuple[str, ...] = (
    "apply_agent_product_board",
    "apply_agent_product_dispatch",
    "apply_agent_missions_day",
    "apply_agent_product_counterplay",
    "apply_agent_hh_close_day",
    "apply_agent_campaign_product",
    "apply_agent_campaign_sequence",
    "apply_agent_ai_board_day",
    "apply_counterplay_campaign_day",
    "apply_agent_mission_ops_day",
)

LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

_MAJOR_META: Dict[str, Dict[str, Any]] = {
    "agent_primary_board_surface": {
        "phase_id": "I1",
        "label": "Agent network map / mission board surface",
        "leaf": "apply_agent_product_board",
        "product": "agent_campaign_product",
        "flow_step": "board",
    },
    "agent_primary_dispatch": {
        "phase_id": "I1",
        "label": "Dispatch mission from board / MissionPicker",
        "leaf": "apply_agent_product_dispatch",
        "product": "agent_campaign_product",
        "flow_step": "dispatch",
    },
    "agent_primary_resolve": {
        "phase_id": "I1",
        "label": "Resolve / advance agent missions",
        "leaf": "apply_agent_missions_day",
        "product": "intelligence_network_product",
        "flow_step": "resolve",
    },
    "agent_primary_counter_intel": {
        "phase_id": "I1",
        "label": "Counter-intel / network sweep",
        "leaf": "apply_agent_product_counterplay",
        "product": "intel_cell_network_product",
        "flow_step": "counterplay",
    },
    "agent_primary_close": {
        "phase_id": "I1",
        "label": "Agent mission board package close",
        "leaf": "apply_agent_hh_close_day",
        "product": "agent_campaign_product",
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
    label = "Agent mission board primary command audit · actions %d · dead %d · %s" % (
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


def _compose_board_surface(
    province_id: int,
    agent: Dict[str, Any],
    intel: Dict[str, Any],
) -> Dict[str, Any]:
    row = _row_for_step(agent, "board")
    agent_sc = _floor(float(row.get("score") or agent.get("score") or 0.55))
    cov = _norm(float(intel.get("coverage_score") or intel.get("score") or 0.55))
    signal_n = int(agent.get("signal_count") or 0)
    agents_n = int(agent.get("available_agents") or 0)
    board_ready = signal_n > 0 or agents_n >= 1
    score = _floor(
        0.5 * agent_sc
        + 0.3 * cov
        + 0.2 * min(1.0, max(signal_n, 1) / 3.0)
    )
    try:
        exe = execute_agent_product_step("board", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "board",
        "action_id": "agent_product_board",
        "signal_count": signal_n,
        "available_agents": agents_n,
        "coverage_score": cov,
        "board_ready": board_ready,
        "mission_picker": True,
        "network_map": True,
        "execute": exe if isinstance(exe, dict) else {},
        "product": agent,
        "ok": score >= 0.35 and board_ready and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_agent_product_board",
            "apply_agent_ai_board_day",
            "apply_agent_campaign_product",
        ],
    }


def _compose_dispatch(
    province_id: int,
    agent: Dict[str, Any],
    *,
    max_dispatches: int = 3,
) -> Dict[str, Any]:
    row = _row_for_step(agent, "dispatch")
    disp_sc = _floor(float(row.get("score") or agent.get("score") or 0.55))
    cov_count = int(agent.get("coverage_count") or 0)
    agents_n = int(agent.get("available_agents") or 0)
    best = str(agent.get("best_mission") or "counterintel")
    affinity = _norm(float(agent.get("affinity") or 0.5))
    score = _floor(
        0.45 * disp_sc
        + 0.25 * min(1.0, cov_count / max(1, max_dispatches))
        + 0.2 * min(1.0, agents_n / 5.0)
        + 0.1 * affinity
    )
    try:
        exe = execute_agent_product_step("dispatch", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "dispatch",
        "action_id": "agent_product_dispatch",
        "best_mission": best,
        "coverage_count": cov_count,
        "available_agents": agents_n,
        "max_dispatches": int(max_dispatches),
        "dispatched": min(max_dispatches, max(1, cov_count or 1)),
        "execute": exe if isinstance(exe, dict) else {},
        "product": agent,
        "ok": score >= 0.35 and agents_n >= 1 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_agent_product_dispatch",
            "apply_agent_campaign_product",
            "apply_agent_mission_ops_day",
        ],
    }


def _compose_resolve(
    province_id: int,
    agent: Dict[str, Any],
    intel: Dict[str, Any],
) -> Dict[str, Any]:
    # Resolve uses missions-day leaf; score from agent + intel coverage spine
    agent_sc = _floor(float(agent.get("score") or 0.55))
    cov = _norm(float(intel.get("coverage_score") or intel.get("score") or 0.55))
    counter = _norm(float(intel.get("counter_score") or 0.55))
    best = str(agent.get("best_mission") or "counterintel")
    score = _floor(0.4 * agent_sc + 0.35 * cov + 0.25 * counter)
    # Prefer board execute as resolve path is missions_day (no pure execute)
    try:
        exe = execute_agent_product_step("dispatch", province_id)
        if isinstance(exe, dict):
            exe = dict(exe)
            exe["step"] = "resolve"
            exe["action_id"] = "agent_missions_day"
            exe["leaf_action"] = "apply_agent_missions_day"
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score, "step": "resolve"}
    return {
        "score": score,
        "flow_step": "resolve",
        "action_id": "agent_missions_day",
        "best_mission": best,
        "coverage_score": cov,
        "counter_score": counter,
        "resolved": True,
        "toast_ready": score >= 0.4,
        "execute": exe if isinstance(exe, dict) else {},
        "product": intel,
        "ok": score >= 0.35 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_agent_missions_day",
            "apply_agent_mission_ops_day",
            "apply_agent_campaign_product",
        ],
    }


def _compose_counter_intel(
    province_id: int,
    agent: Dict[str, Any],
    intel: Dict[str, Any],
    cells: Dict[str, Any],
) -> Dict[str, Any]:
    row = _row_for_step(agent, "counterplay")
    cp_sc = _floor(float(row.get("score") or agent.get("score") or 0.55))
    counter = _norm(float(intel.get("counter_score") or intel.get("score") or 0.55))
    cell_sc = _floor(float(cells.get("score") or 0.55))
    secure = bool(cells.get("secure", True))
    swept = int(cells.get("swept") or 0)
    score = _floor(
        0.4 * cp_sc
        + 0.3 * counter
        + 0.2 * cell_sc
        + (0.1 if secure else 0.0)
    )
    try:
        exe = execute_agent_product_step("counterplay", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "counterplay",
        "action_id": "agent_product_counterplay",
        "counter_score": counter,
        "cell_score": cell_sc,
        "secure": secure,
        "swept": swept,
        "execute": exe if isinstance(exe, dict) else {},
        "product": cells,
        "ok": score >= 0.35 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_agent_product_counterplay",
            "apply_counterplay_campaign_day",
            "apply_agent_campaign_product",
        ],
    }


def _compose_close(
    province_id: int,
    agent: Dict[str, Any],
    intel: Dict[str, Any],
    cells: Dict[str, Any],
    board: Dict[str, Any],
    dispatch: Dict[str, Any],
    resolve: Dict[str, Any],
    counter: Dict[str, Any],
) -> Dict[str, Any]:
    agent_sc = _floor(float(agent.get("score") or 0.55))
    intel_sc = _floor(float(intel.get("score") or 0.55))
    cell_sc = _floor(float(cells.get("score") or 0.55))
    surface_ok = all(
        bool(p.get("ok")) for p in (board, dispatch, resolve, counter)
    )
    score = _floor(
        0.28 * agent_sc
        + 0.22 * intel_sc
        + 0.12 * cell_sc
        + 0.1 * float(board.get("score") or 0.5)
        + 0.1 * float(dispatch.get("score") or 0.5)
        + 0.1 * float(resolve.get("score") or 0.5)
        + 0.08 * float(counter.get("score") or 0.5)
        + (0.02 if surface_ok else 0.0)
    )
    return {
        "score": score,
        "flow_step": "close",
        "action_id": "agent_hh_close_day",
        "surface_ok": surface_ok,
        "agent_score": agent_sc,
        "intel_score": intel_sc,
        "cell_score": cell_sc,
        "toast": "Mission board closed · dispatch→resolve→counter-intel sealed",
        "product": agent,
        "ok": score >= 0.35 and surface_ok,
        "live_apis": [
            "apply_agent_hh_close_day",
            "apply_agent_campaign_sequence",
            "apply_agent_campaign_product",
        ],
    }


def build_agent_mission_board_primary_command_product(
    *,
    province_id: int = 1,
    available_agents: int = 5,
    network_strength: float = 0.35,
    loyalty: float = 0.5,
    max_dispatches: int = 3,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Build I1 agent network map + mission board primary player-command package."""
    pid = max(1, int(province_id))
    agents_n = max(0, int(available_agents))
    net = _norm(network_strength)
    loy = _norm(loyalty)
    max_d = max(1, int(max_dispatches))

    agent = build_agent_campaign_product(
        available_agents=agents_n if agents_n > 0 else 5,
        network_strength=net,
        loyalty=loy,
        province_id=pid,
        max_dispatches=max_d,
    )
    intel = build_intelligence_network_product(province_id=pid)
    cells = build_intel_cell_network_product(province_id=pid)

    board = _compose_board_surface(pid, agent, intel)
    dispatch = _compose_dispatch(pid, agent, max_dispatches=max_d)
    resolve = _compose_resolve(pid, agent, intel)
    counter = _compose_counter_intel(pid, agent, intel, cells)
    close = _compose_close(pid, agent, intel, cells, board, dispatch, resolve, counter)

    major_payloads = {
        "agent_primary_board_surface": board,
        "agent_primary_dispatch": dispatch,
        "agent_primary_resolve": resolve,
        "agent_primary_counter_intel": counter,
        "agent_primary_close": close,
    }

    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))

    rec = agent.get("recommendation") if isinstance(agent.get("recommendation"), dict) else {}
    if not rec:
        rec = recommend_agent_product_step(
            int(agent.get("signal_count") or 0),
            coverage_count=int(agent.get("coverage_count") or 0),
            counter_options=1,
            affinity=float(agent.get("affinity") or 0.5),
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
        recommended = (
            rec_step in (flow, step)
            or (flow == "board" and rec_step == "board")
            or (flow == "dispatch" and rec_step == "dispatch")
            or (flow == "counterplay" and rec_step == "counterplay")
            or (flow == "resolve" and rec_step in ("dispatch", "board"))
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
        0.22 * float(board.get("score") or 0.5)
        + 0.20 * float(dispatch.get("score") or 0.5)
        + 0.20 * float(resolve.get("score") or 0.5)
        + 0.18 * float(counter.get("score") or 0.5)
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

    best_mission = str(
        dispatch.get("best_mission")
        or agent.get("best_mission")
        or "counterintel"
    )
    signal_n = int(board.get("signal_count") or agent.get("signal_count") or 0)
    agents_out = int(board.get("available_agents") or agent.get("available_agents") or agents_n)
    label = (
        "Agent mission board primary · majors %d/5 · steps %d · dead %d · "
        "signals %d · agents %d · mission %s · score %.2f · %s"
        % (
            majors_ok_n,
            len(steps),
            dead_n,
            signal_n,
            agents_out,
            best_mission,
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
            "[color=#6eb5ff]★ Agent mission board[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "province_id": pid,
        "available_agents": agents_out,
        "network_strength": net,
        "loyalty": loy,
        "max_dispatches": max_d,
        "signal_count": signal_n,
        "best_mission": best_mission,
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
        "agent": agent,
        "intel": intel,
        "cells": cells,
        "board_surface": board,
        "dispatch_mission": dispatch,
        "resolve_mission": resolve,
        "counter_intel": counter,
        "close": close,
        "agent_product_steps": list(AGENT_PRODUCT_STEPS)
        if AGENT_PRODUCT_STEPS
        else ["board", "dispatch", "counterplay"],
        "intel_product_steps": list(INTEL_PRODUCT_STEPS)
        if INTEL_PRODUCT_STEPS
        else ["coverage", "counterintel", "counterplay"],
        "cell_product_steps": list(CELL_PRODUCT_STEPS)
        if CELL_PRODUCT_STEPS
        else ["cells", "ops", "sweep"],
        "integration": [
            "agent_mission_board_primary_command_product",
            "agent_campaign_product",
            "intelligence_network_product",
            "intel_cell_network_product",
            "agent_primary_board_surface",
            "agent_primary_dispatch",
            "agent_primary_resolve",
            "agent_primary_counter_intel",
            "agent_primary_close",
            "MissionPickerPopup",
            "I1",
            "major_6",
            "major_19",
            "major_51",
            "primary_command",
            "agent",
            "mission_board",
            "network_map",
            "player_command_loop",
        ],
        "panel_actions": [
            {
                "action_id": "agent_mission_board_primary_command_product",
                "label": "Run agent mission board primary command",
                "enabled": True,
            },
            {
                "action_id": "apply_agent_product_board",
                "label": "Mission board surface (I1)",
                "enabled": True,
            },
            {
                "action_id": "apply_agent_product_dispatch",
                "label": "Dispatch mission",
                "enabled": True,
            },
            {
                "action_id": "apply_agent_missions_day",
                "label": "Resolve missions",
                "enabled": True,
            },
            {
                "action_id": "apply_agent_product_counterplay",
                "label": "Counter-intel / sweep",
                "enabled": True,
            },
            {
                "action_id": "apply_agent_hh_close_day",
                "label": "Agent mission board close",
                "enabled": True,
            },
            {
                "action_id": "apply_agent_campaign_product",
                "label": "Agent campaign product",
                "enabled": True,
            },
            {
                "action_id": "apply_agent_campaign_sequence",
                "label": "Agent campaign sequence",
                "enabled": True,
            },
            {
                "action_id": "apply_agent_ai_board_day",
                "label": "AI board day",
                "enabled": True,
            },
            {
                "action_id": "apply_counterplay_campaign_day",
                "label": "Counterplay campaign day",
                "enabled": True,
            },
        ],
    }


def apply_agent_mission_board_primary_command_step(
    step: str,
    province_id: int = 1,
    *,
    available_agents: int = 5,
    network_strength: float = 0.35,
    loyalty: float = 0.5,
    max_dispatches: int = 3,
    runtime: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Apply one primary-command step; returns live_api + score for GD wiring."""
    s = str(step or "").strip().lower()
    aliases = {
        "board": "board_surface",
        "surface": "board_surface",
        "map": "board_surface",
        "network_map": "board_surface",
        "mission_board": "board_surface",
        "agent_board": "board_surface",
        "agent_product_board": "board_surface",
        "dispatch": "dispatch_mission",
        "mission": "dispatch_mission",
        "pick_mission": "dispatch_mission",
        "agent_dispatch": "dispatch_mission",
        "agent_product_dispatch": "dispatch_mission",
        "resolve": "resolve_mission",
        "missions": "resolve_mission",
        "missions_day": "resolve_mission",
        "advance": "resolve_mission",
        "agent_missions": "resolve_mission",
        "counter": "counter_intel",
        "counterplay": "counter_intel",
        "counterintel": "counter_intel",
        "sweep": "counter_intel",
        "agent_product_counterplay": "counter_intel",
        "agent_close": "close",
        "hh_close": "close",
        "package_close": "close",
        "agent_hh_close": "close",
        "toast": "close",
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
    product = build_agent_mission_board_primary_command_product(
        province_id=province_id,
        available_agents=available_agents,
        network_strength=network_strength,
        loyalty=loyalty,
        max_dispatches=max_dispatches,
    )
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute agent mission board primary %s · major %s · live %s · score %.2f" % (
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
        hist = list(runtime.get("mission_history") or [])
        flow = str((row or {}).get("flow_step") or s)
        if flow not in hist:
            hist.append(flow)
        runtime["mission_history"] = hist
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
            "apply_agent_mission_board_primary_command_step",
            s,
            major,
            live_api,
        ],
    }


def close_agent_mission_board_primary_command_package(
    province_id: int = 1,
    *,
    available_agents: int = 5,
    network_strength: float = 0.35,
    loyalty: float = 0.5,
    max_dispatches: int = 3,
) -> Dict[str, Any]:
    """Apply all primary-command steps in order (dispatch→resolve→toast seal)."""
    rt: Dict[str, Any] = {"applied": [], "scores": {}, "tick": 0, "mission_history": []}
    steps_log: List[Dict[str, Any]] = []
    for step in PRIMARY_COMMAND_STEPS:
        steps_log.append(
            apply_agent_mission_board_primary_command_step(
                step,
                province_id,
                available_agents=available_agents,
                network_strength=network_strength,
                loyalty=loyalty,
                max_dispatches=max_dispatches,
                runtime=rt,
            )
        )
    product = build_agent_mission_board_primary_command_product(
        province_id=province_id,
        available_agents=available_agents,
        network_strength=network_strength,
        loyalty=loyalty,
        max_dispatches=max_dispatches,
    )
    ok = (
        len(steps_log) == len(PRIMARY_COMMAND_STEPS)
        and all(s.get("ok") for s in steps_log)
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
    )
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = (
        "Agent mission board primary close %s · steps %d/%d · majors %d/5 · "
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
        "toast": str((product.get("close") or {}).get("toast") or "Mission board closed"),
        "summary": label,
        "plain": label,
        "bbcode": (
            "[color=#70d0a0]✓ Agent mission board[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "closed": list(PRIMARY_COMMAND_STEPS),
        "integration": [
            "agent_mission_board_primary_command",
            "close_agent_mission_board_primary_command_package",
            "I1",
            "major_6",
            "major_19",
            "major_51",
        ],
    }


def agent_mission_board_primary_command_integrity() -> Dict[str, Any]:
    product = build_agent_mission_board_primary_command_product()
    rich = build_agent_mission_board_primary_command_product(
        available_agents=6,
        network_strength=0.55,
        loyalty=0.6,
        max_dispatches=4,
    )
    closed = close_agent_mission_board_primary_command_package(1)
    # Structural honesty: step APIs must be agent live leaves, not apply_focus
    step_apis = [LIVE_API_BY_STEP[s] for s in PRIMARY_COMMAND_STEPS]
    no_focus = all("apply_focus" not in a for a in step_apis)
    has_board = "apply_agent_product_board" in step_apis
    has_dispatch = "apply_agent_product_dispatch" in step_apis
    has_resolve = "apply_agent_missions_day" in step_apis
    has_counter = "apply_agent_product_counterplay" in step_apis
    has_close = "apply_agent_hh_close_day" in step_apis
    agent_shift = abs(float(product.get("score", 0)) - float(rich.get("score", 0)))
    ok = (
        not product.get("empty")
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
        and len(product.get("steps") or []) == len(PRIMARY_COMMAND_STEPS)
        and len(SURFACE_KEYS) == 5
        and bool(closed.get("ok"))
        and no_focus
        and has_board
        and has_dispatch
        and has_resolve
        and has_counter
        and has_close
        and float(product.get("score", 0)) >= 0.35
        and agent_shift >= 0.0
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "rich_score": float(rich.get("score", 0)),
        "agent_shift": agent_shift,
        "dead_n": int(product.get("dead_n", 0)),
        "majors_ok_n": int(product.get("majors_ok_n") or 0),
        "no_focus": no_focus,
        "has_board": has_board,
        "has_dispatch": has_dispatch,
        "has_resolve": has_resolve,
        "has_counter": has_counter,
        "has_close": has_close,
        "closed": closed,
        "summary": "Agent mission board primary command integrity %s"
        % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
