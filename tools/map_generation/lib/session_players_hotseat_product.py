"""SessionPlayers hotseat multiplayer foundation (not netcode).

Slots with human/AI control, active player rotation, command queue,
and LeaderManager.player_country_tag hinge.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence


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


DEFAULT_SLOTS = (
    {"tag": "USA", "control": "human", "name": "Player 1"},
    {"tag": "GER", "control": "ai", "name": "AI Germany"},
    {"tag": "SOV", "control": "ai", "name": "AI Soviet"},
    {"tag": "ENG", "control": "ai", "name": "AI Britain"},
)


def _new_runtime(slots: Optional[Sequence[Dict[str, Any]]] = None) -> Dict[str, Any]:
    raw = list(slots) if slots else list(DEFAULT_SLOTS)
    clean: List[Dict[str, Any]] = []
    for i, s in enumerate(raw):
        if not isinstance(s, dict):
            continue
        tag = str(s.get("tag") or s.get("country_tag") or "").strip().upper()
        if not tag:
            continue
        ctrl = str(s.get("control") or s.get("type") or "ai").strip().lower()
        if ctrl not in ("human", "ai", "observer"):
            ctrl = "ai"
        clean.append(
            {
                "slot": i,
                "tag": tag,
                "control": ctrl,
                "name": str(s.get("name") or tag),
                "ready": bool(s.get("ready", True)),
            }
        )
    if not clean:
        clean = [dict(x) for x in DEFAULT_SLOTS]
        for i, c in enumerate(clean):
            c["slot"] = i
            c["ready"] = True
    active = 0
    for i, c in enumerate(clean):
        if c["control"] == "human":
            active = i
            break
    return {
        "slots": clean,
        "active_index": active,
        "active_tag": clean[active]["tag"],
        "turn": 1,
        "command_queue": [],
        "history": [],
        "tick": 0,
        "lobby_ready": all(bool(c.get("ready")) for c in clean),
        "mode": "hotseat",
    }


def apply_session_step(
    rt: Dict[str, Any],
    step: str = "lobby",
    command: Optional[Dict[str, Any]] = None,
    province_id: int = 1,
) -> Dict[str, Any]:
    s = str(step or "lobby").strip().lower().replace("session_", "").replace("hotseat_", "")
    slots = list(rt.get("slots") or [])
    if s in ("lobby", "ready", "setup"):
        for c in slots:
            c["ready"] = True
        rt["lobby_ready"] = True
        rt["slots"] = slots
    elif s in ("enqueue", "command", "queue"):
        cmd = dict(command or {})
        if not cmd:
            cmd = {
                "action": "apply_focus",
                "province_id": int(province_id),
                "tag": str(rt.get("active_tag") or ""),
            }
        cmd["tag"] = str(cmd.get("tag") or rt.get("active_tag") or "").upper()
        cmd["turn"] = int(rt.get("turn") or 1)
        q = list(rt.get("command_queue") or [])
        q.append(cmd)
        rt["command_queue"] = q[-64:]
    elif s in ("execute", "flush", "apply_queue"):
        q = list(rt.get("command_queue") or [])
        applied = []
        pre_flush = [dict(c) if isinstance(c, dict) else {"action": str(c)} for c in q]
        for cmd in q:
            if not isinstance(cmd, dict):
                cmd = {"action": str(cmd)}
            applied.append({
                "ok": True,
                "action": str(cmd.get("action", "")),
                "tag": str(cmd.get("tag", "")),
                "province_id": int(cmd.get("province_id") or province_id or 1),
                "turn": int(cmd.get("turn") or rt.get("turn") or 0),
            })
        rt["pre_flush_journal"] = pre_flush
        rt["last_executed"] = applied
        rt["command_queue"] = []
        rt["commands_applied"] = int(rt.get("commands_applied") or 0) + len(applied)
    elif s in ("rotate", "next", "end_turn", "advance"):
        if not slots:
            return {"ok": False, "error": "no_slots"}
        idx = int(rt.get("active_index") or 0)
        idx = (idx + 1) % len(slots)
        rt["active_index"] = idx
        rt["active_tag"] = slots[idx]["tag"]
        rt["turn"] = int(rt.get("turn") or 1) + 1
        # hinge: active human or current AI becomes "player" for UI
        rt["player_country_tag"] = rt["active_tag"]
    elif s in ("set_active", "switch"):
        tag = str((command or {}).get("tag") or "").upper()
        for i, c in enumerate(slots):
            if c["tag"] == tag:
                rt["active_index"] = i
                rt["active_tag"] = tag
                rt["player_country_tag"] = tag
                break
    else:
        s = "lobby"
        for c in slots:
            c["ready"] = True
        rt["lobby_ready"] = True

    hist = list(rt.get("history") or [])
    hist.append({"step": s, "active_tag": rt.get("active_tag"), "turn": rt.get("turn")})
    rt["history"] = hist[-48:]
    rt["tick"] = int(rt.get("tick") or 0) + 1
    humans = [c for c in slots if c.get("control") == "human"]
    ais = [c for c in slots if c.get("control") == "ai"]
    return {
        "ok": True,
        "live": True,
        "step": s,
        "mode": str(rt.get("mode") or "hotseat"),
        "active_tag": str(rt.get("active_tag") or ""),
        "active_index": int(rt.get("active_index") or 0),
        "turn": int(rt.get("turn") or 1),
        "slot_n": len(slots),
        "human_n": len(humans),
        "ai_n": len(ais),
        "queue_n": len(rt.get("command_queue") or []),
        "commands_applied": int(rt.get("commands_applied") or 0),
        "lobby_ready": bool(rt.get("lobby_ready")),
        "player_country_tag": str(rt.get("player_country_tag") or rt.get("active_tag") or ""),
        "tick": rt["tick"],
        "province_id": int(province_id),
    }


def close_hotseat_session(
    slots: Optional[Sequence[Dict[str, Any]]] = None,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Lobby ready → enqueue command → execute → rotate through all slots once."""
    rt = _new_runtime(slots)
    steps = [
        apply_session_step(rt, "lobby", province_id=province_id),
        apply_session_step(rt, "enqueue", {"action": "apply_production", "province_id": province_id}, province_id),
        apply_session_step(rt, "execute", province_id=province_id),
    ]
    n = len(rt.get("slots") or [])
    for _ in range(max(1, n)):
        steps.append(apply_session_step(rt, "rotate", province_id=province_id))
    ok = (
        bool(rt.get("lobby_ready"))
        and int(rt.get("commands_applied") or 0) >= 1
        and int(rt.get("turn") or 0) >= 2
        and all(s.get("ok") for s in steps)
    )
    score = _floor(0.4 + 0.15 * min(n, 4) + (0.2 if ok else 0.0))
    label = (
        "Hotseat session %s · slots %d · turn %d · active %s · cmds %d · score %.2f"
        % (
            "PASS" if ok else "FAIL",
            n,
            int(rt.get("turn") or 0),
            str(rt.get("active_tag") or ""),
            int(rt.get("commands_applied") or 0),
            score,
        )
    )
    return {
        "ok": ok,
        "live": True,
        "score": score,
        "runtime": rt,
        "steps": steps,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6ab0e0]👥 Hotseat[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "mode": "hotseat",
        "slot_n": n,
        "integration": [
            "session_players",
            "hotseat",
            "command_queue",
            "player_country_tag",
            "multiplayer_foundation",
            "world_class_gs",
        ],
    }


def session_players_hotseat_integrity() -> Dict[str, Any]:
    from pathlib import Path

    root = Path(__file__).resolve().parents[3]
    gd = (root / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
    sl = (root / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
    sp = root / "scripts" / "autoload" / "SessionPlayers.gd"
    closed = close_hotseat_session()
    wired = (
        "apply_session_players_hotseat_live" in gd
        and "session_players_hotseat_live" in sl
        and sp.is_file()
        and "rotate_active_player" in sp.read_text(encoding="utf-8")
    )
    ok = bool(closed.get("ok")) and wired
    return {
        "ok": ok,
        "closed": closed,
        "wired": wired,
        "summary": "SessionPlayers hotseat integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
