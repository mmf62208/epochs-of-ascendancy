"""Agent campaign day: agent response · HH campaign · campaign compose.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from gameplay_loops import sole_mult_integrity  # type: ignore
from campaign_cohesion import agent_campaign_response, hh_campaign_board  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def agent_response_day(
    signal: Optional[Mapping[str, Any]] = None,
    *,
    available_agents: int = 5,
    network_strength: float = 0.35,
    loyalty: float = 0.5,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Agent campaign response → dispatch / counterplay day apply."""
    sig = dict(
        signal
        or {
            "class": "sabotage",
            "action_class": "sabotage",
            "influence": 0.6,
            "province_id": province_id,
        }
    )
    action_class = str(sig.get("action_class", sig.get("class", "sabotage")) or "sabotage")
    sig_pid = int(sig.get("province_id", province_id) or province_id)

    try:
        resp = agent_campaign_response(
            signal=sig,
            available_agents=available_agents,
            network_strength=network_strength,
            loyalty=loyalty,
        )
    except TypeError:
        try:
            resp = agent_campaign_response(sig, available_agents, network_strength, loyalty)  # type: ignore
        except Exception:
            resp = {"score": 0.5, "empty": False, "summary": "agent response stub"}

    if resp.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _score(resp, "score")
    if score > 2.0:
        score = min(1.0, score / 100.0)
    apply_ready = available_agents >= 1 and score >= 0.25

    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_agent_dispatch",
            "province_id": sig_pid,
            "score": max(0.35, score),
            "action_class": action_class,
            "enabled": apply_ready,
        },
        {
            "action_id": "apply_counterplay",
            "province_id": sig_pid,
            "score": max(0.3, score * 0.9),
            "enabled": apply_ready,
        },
    ]

    label = "Agent response day · class %s · agents %d · score %.2f" % (
        action_class,
        available_agents,
        score,
    )
    return {
        "response": resp,
        "action_class": action_class,
        "score": score,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "agent_response_day",
                "label": "Run agent response day",
                "enabled": apply_ready,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8a0ff]🕵 Agent response day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["agent_campaign", "dispatch", "counterplay"],
    }


def hh_campaign_day(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    signal: Optional[Mapping[str, Any]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    max_commits: int = 3,
    province_id: int = 1,
) -> Dict[str, Any]:
    """HH campaign board → agenda commit day apply (empty trail → empty)."""
    t = [dict(x) for x in list(trail or []) if isinstance(x, Mapping)]
    if not t:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    try:
        board = hh_campaign_board(
            trail=t, max_commits=max_commits, weather=weather, signal=signal
        )
    except TypeError:
        try:
            board = hh_campaign_board(t, max_commits)  # type: ignore
        except Exception:
            board = {"score": 0.45, "empty": False, "summary": "hh campaign stub"}

    if board.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    score = _score(board, "score")
    if score > 2.0:
        score = min(1.0, score / 100.0)
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "apply_hh_commit",
            "province_id": -1,
            "score": max(0.35, score),
            "enabled": True,
        }
    ]
    if score >= 0.5:
        apply_queue.append(
            {
                "action_id": "apply_focus",
                "province_id": province_id,
                "score": 0.4,
                "focus_id": "industrial_effort",
                "enabled": True,
            }
        )

    label = "HH campaign day · trail %d · score %.2f" % (len(t), score)
    return {
        "board": board,
        "trail_count": len(t),
        "score": score,
        "apply_ready": True,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "hh_campaign_day",
                "label": "Run HH campaign day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8a0ff]📜 HH campaign day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["hh_campaign", "hh_commit", "focus"],
    }


def agent_campaign_day(
    signal: Optional[Mapping[str, Any]] = None,
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    weather: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
    available_agents: int = 5,
) -> Dict[str, Any]:
    """Compose agent response + HH campaign into one day package."""
    sig = dict(
        signal
        or {
            "class": "sabotage",
            "action_class": "sabotage",
            "influence": 0.55,
            "province_id": province_id,
        }
    )
    t = list(trail or [{"class": "sabotage", "influence": 0.4, "month": 1}])
    w = dict(weather or {})

    agent = agent_response_day(
        signal=sig,
        available_agents=available_agents,
        province_id=province_id,
    )
    hh = hh_campaign_day(
        trail=t, signal=sig, weather=w, province_id=province_id
    )

    apply_queue: List[Dict[str, Any]] = []
    for block in (agent, hh):
        if not isinstance(block, Mapping) or block.get("empty"):
            continue
        for q in list(block.get("apply_queue") or []):
            if isinstance(q, dict) and q.get("enabled", True):
                apply_queue.append(dict(q))

    seen = set()
    deduped: List[Dict[str, Any]] = []
    for q in apply_queue:
        key = (
            str(q.get("action_id")),
            int(q.get("province_id", -1)),
            str(q.get("focus_id", "")),
        )
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    apply_queue = deduped[:8]

    a_score = 0.0 if agent.get("empty") else _score(agent, "score")
    h_score = 0.0 if hh.get("empty") else _score(hh, "score")
    n = (0 if agent.get("empty") else 1) + (0 if hh.get("empty") else 1)
    score = (a_score + h_score) / max(1, n)
    label = (
        "Agent campaign day · agent %.2f · hh %.2f · q %d"
        % (a_score, h_score, len(apply_queue))
    )
    return {
        "agent": agent,
        "hh": hh,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "agent_campaign_day",
                "label": "Run agent campaign day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(
            [
                label,
                str(agent.get("summary", "")),
                str(hh.get("summary", "")),
            ]
        ),
        "bbcode": "[color=#e8a0ff]🕵📜 Agent campaign day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": len(apply_queue) == 0 and bool(agent.get("empty")) and bool(hh.get("empty")),
        "integration": ["agent_response", "hh_campaign"],
    }


def agent_campaign_integrity(
    sea_mult: float = 1.1, weather_mult: float = 0.8, route_risk: float = 0.2
) -> Dict[str, Any]:
    sole = sole_mult_integrity(
        sea_mult=sea_mult, weather_mult=weather_mult, route_risk=route_risk
    )
    ok = bool(sole.get("integrity_ok", sole.get("ok", False)))
    return {
        "ok": ok,
        "summary": "Agent campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_agent_campaign_day_loop() -> Dict[str, Any]:
    agent = agent_response_day(
        {"action_class": "sabotage", "province_id": 7, "influence": 0.7},
        available_agents=4,
        province_id=7,
    )
    empty_hh = hh_campaign_day(trail=[], province_id=1)
    hh = hh_campaign_day(
        trail=[{"class": "economic_pressure", "influence": 0.5, "month": 1}],
        province_id=1,
    )
    day = agent_campaign_day(
        signal={"action_class": "infiltration", "province_id": 3, "influence": 0.55},
        trail=[{"class": "infiltration", "influence": 0.4}],
        province_id=3,
    )
    gate = agent_campaign_integrity()
    label = (
        "Close agent campaign · agent_q %d · empty_hh %s · day_q %d · %s"
        % (
            len(agent.get("apply_queue") or []),
            empty_hh.get("empty"),
            len(day.get("apply_queue") or []),
            "PASS" if gate.get("ok") else "FAIL",
        )
    )
    return {
        "agent": agent,
        "empty_hh": empty_hh,
        "hh": hh,
        "day": day,
        "gate": gate,
        "score": float(day.get("score", 0.0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8a0ff]✓ Close agent campaign[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
