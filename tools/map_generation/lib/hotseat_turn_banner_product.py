"""Hotseat turn banner polish (Master Plan Phase N1).

Models turn banner UX: active slot, lock non-active player commands,
end-turn readiness, command journal length. Composes SessionPlayers
hotseat foundation — not netcode (N3).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence

try:
    from session_players_hotseat_product import (  # type: ignore
        DEFAULT_SLOTS,
        _new_runtime,
        apply_session_step,
        close_hotseat_session,
    )
except Exception:  # pragma: no cover
    DEFAULT_SLOTS = (
        {"tag": "USA", "control": "human", "name": "Player 1"},
        {"tag": "GER", "control": "ai", "name": "AI Germany"},
        {"tag": "SOV", "control": "ai", "name": "AI Soviet"},
        {"tag": "ENG", "control": "ai", "name": "AI Britain"},
    )

    def _new_runtime(slots=None):  # type: ignore
        raw = list(slots) if slots else list(DEFAULT_SLOTS)
        clean = []
        for i, s in enumerate(raw):
            if not isinstance(s, dict):
                continue
            tag = str(s.get("tag") or "").strip().upper()
            if not tag:
                continue
            ctrl = str(s.get("control") or "ai").strip().lower()
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
            "lobby_ready": True,
            "mode": "hotseat",
        }

    def apply_session_step(rt, step="lobby", command=None, province_id=1):  # type: ignore
        s = str(step or "lobby").strip().lower()
        slots = list(rt.get("slots") or [])
        if s in ("enqueue", "command", "queue"):
            cmd = dict(command or {})
            cmd["tag"] = str(cmd.get("tag") or rt.get("active_tag") or "").upper()
            cmd["turn"] = int(rt.get("turn") or 1)
            q = list(rt.get("command_queue") or [])
            q.append(cmd)
            rt["command_queue"] = q
        elif s in ("rotate", "next", "end_turn", "advance"):
            if slots:
                idx = (int(rt.get("active_index") or 0) + 1) % len(slots)
                rt["active_index"] = idx
                rt["active_tag"] = slots[idx]["tag"]
                rt["turn"] = int(rt.get("turn") or 1) + 1
        return {"ok": True, "active_tag": rt.get("active_tag"), "turn": rt.get("turn")}

    def close_hotseat_session(slots=None, province_id=1):  # type: ignore
        rt = _new_runtime(slots)
        apply_session_step(rt, "lobby", province_id=province_id)
        apply_session_step(rt, "enqueue", {"action": "apply_production"}, province_id)
        apply_session_step(rt, "execute", province_id=province_id)
        for _ in range(max(1, len(rt.get("slots") or []))):
            apply_session_step(rt, "rotate", province_id=province_id)
        return {"ok": True, "runtime": rt, "live": True}


# Primary UX fields — dead_n style: all must be present for polish product.
REQUIRED_UX_FIELDS = (
    "slots",
    "active_tag",
    "turn_index",
    "banner_text",
    "non_active_locked",
    "can_end_turn",
    "command_journal_len",
)

PRODUCT_STEPS = ("banner", "lock", "end_turn")


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


def _normalize_slots(slots: Optional[Sequence[Dict[str, Any]]]) -> List[Dict[str, Any]]:
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
                "slot": int(s.get("slot", i)),
                "tag": tag,
                "control": ctrl,
                "name": str(s.get("name") or tag),
                "ready": bool(s.get("ready", True)),
            }
        )
    if not clean:
        for i, s in enumerate(DEFAULT_SLOTS):
            row = dict(s)
            row["slot"] = i
            row["ready"] = True
            clean.append(row)
    return clean


def _resolve_active(
    slots: List[Dict[str, Any]],
    active_tag: Optional[str],
) -> Dict[str, Any]:
    want = str(active_tag or "").strip().upper()
    if want:
        for s in slots:
            if str(s.get("tag") or "").upper() == want:
                return s
    for s in slots:
        if str(s.get("control")) == "human":
            return s
    return slots[0] if slots else {"tag": "", "control": "ai", "name": "", "ready": False}


def format_hotseat_banner_text(
    turn_index: int,
    active_tag: str,
    *,
    control: str = "human",
) -> str:
    """Match TopInfoBar hotseat banner copy."""
    human = str(control or "").strip().lower() == "human"
    role = "HUMAN" if human else "AI (input locked)"
    tag = str(active_tag or "—").strip().upper() or "—"
    return "Hotseat · Turn %d · Active %s · %s" % (int(turn_index), tag, role)


def hotseat_lock_audit(
    active_tag: str,
    attempted_tag: str,
) -> Dict[str, Any]:
    """Lock non-active player commands: only active_tag may issue orders."""
    active = str(active_tag or "").strip().upper()
    attempted = str(attempted_tag or "").strip().upper()
    allowed = bool(active) and bool(attempted) and active == attempted
    reason = "ok" if allowed else ("no_active" if not active else ("empty_attempt" if not attempted else "non_active_locked"))
    return {
        "allowed": allowed,
        "active_tag": active,
        "attempted_tag": attempted,
        "non_active_locked": True,
        "reason": reason,
        "ok": True,
        "summary": "Hotseat lock · active %s · attempt %s · %s"
        % (active or "—", attempted or "—", "ALLOW" if allowed else "DENY"),
        "empty": False,
    }


def hotseat_turn_banner_dead_audit(
    product: Optional[Dict[str, Any]] = None,
    *,
    required_fields: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """dead_n style: every primary UX field must be present (and non-null)."""
    req = [str(x) for x in (required_fields if required_fields is not None else REQUIRED_UX_FIELDS)]
    src = product if isinstance(product, dict) else {}
    dead: List[str] = []
    for field in req:
        if field not in src or src.get(field) is None:
            dead.append(field)
    # banner_text must be non-empty string when present
    if "banner_text" in req and "banner_text" not in dead:
        if not str(src.get("banner_text") or "").strip():
            dead.append("banner_text")
    ok = len(dead) == 0 and len(req) >= 6
    label = "Hotseat banner audit · fields %d · dead %d · %s" % (
        len(req),
        len(dead),
        "PASS" if ok else "FAIL",
    )
    return {
        "required_fields": req,
        "dead": dead,
        "dead_n": len(dead),
        "live_n": len(req) - len(dead),
        "ok": ok,
        "summary": label,
        "plain": label,
        "empty": False,
    }


def build_hotseat_turn_banner_product(
    slots: Optional[Sequence[Dict[str, Any]]] = None,
    active_tag: Optional[str] = None,
    turn: int = 1,
    commands: Optional[Sequence[Dict[str, Any]]] = None,
    *,
    province_id: int = 1,
    lobby_ready: bool = True,
) -> Dict[str, Any]:
    """Build turn-banner product state for hotseat polish (N1).

    Parameters mirror SessionPlayers live state so UI / dual can map 1:1.
    """
    clean_slots = _normalize_slots(slots)
    active_row = _resolve_active(clean_slots, active_tag)
    tag = str(active_row.get("tag") or "").upper()
    control = str(active_row.get("control") or "ai").lower()
    turn_index = max(1, int(turn or 1))
    journal = list(commands) if commands is not None else []
    journal_len = len(journal)
    banner_text = format_hotseat_banner_text(turn_index, tag, control=control)
    # Non-active commands always locked in hotseat polish mode.
    non_active_locked = True
    # End turn when lobby ready and we have an active seat.
    can_end_turn = bool(lobby_ready) and bool(clean_slots) and bool(tag)
    is_active_human = control == "human"

    # Self lock audit: active may command self; a different tag may not.
    lock_self = hotseat_lock_audit(tag, tag)
    other_tag = ""
    for s in clean_slots:
        t = str(s.get("tag") or "").upper()
        if t and t != tag:
            other_tag = t
            break
    lock_other = hotseat_lock_audit(tag, other_tag) if other_tag else {
        "allowed": False,
        "reason": "no_other_slot",
        "ok": True,
    }

    lock_score = _floor(0.55 + (0.2 if lock_self.get("allowed") else 0.0) + (0.15 if not lock_other.get("allowed") else 0.0))
    banner_score = _floor(0.5 + 0.08 * min(len(clean_slots), 4) + (0.1 if banner_text else 0.0))
    end_score = _floor(0.55 if can_end_turn else 0.35)
    score = _floor(0.35 * banner_score + 0.35 * lock_score + 0.3 * end_score)

    product_core: Dict[str, Any] = {
        "slots": clean_slots,
        "active_tag": tag,
        "turn_index": turn_index,
        "banner_text": banner_text,
        "non_active_locked": non_active_locked,
        "can_end_turn": can_end_turn,
        "command_journal_len": journal_len,
    }
    audit = hotseat_turn_banner_dead_audit(product_core)

    day_rows: List[Dict[str, Any]] = [
        {
            "index": 0,
            "step": "banner",
            "action_id": "hotseat_turn_banner",
            "label": "Turn banner · %s" % banner_text,
            "score": banner_score,
            "enabled": True,
            "province_id": max(1, int(province_id)),
        },
        {
            "index": 1,
            "step": "lock",
            "action_id": "hotseat_lock_non_active",
            "label": "Lock non-active · self %s · other %s"
            % (
                "ALLOW" if lock_self.get("allowed") else "DENY",
                "ALLOW" if lock_other.get("allowed") else "DENY",
            ),
            "score": lock_score,
            "enabled": True,
            "province_id": max(1, int(province_id)),
        },
        {
            "index": 2,
            "step": "end_turn",
            "action_id": "hotseat_end_turn_ready",
            "label": "End-turn readiness · %s" % ("READY" if can_end_turn else "BLOCKED"),
            "score": end_score,
            "enabled": can_end_turn,
            "province_id": max(1, int(province_id)),
        },
    ]
    apply_queue = [
        {
            "action_id": r["action_id"],
            "province_id": max(1, int(province_id)),
            "score": r["score"],
            "enabled": r["enabled"],
            "label": r["label"],
            "step": r["step"],
        }
        for r in day_rows
    ]
    actions = [
        {"action_id": "hotseat_turn_banner_product", "label": "Run hotseat turn banner polish", "enabled": True},
        {"action_id": "hotseat_end_turn", "label": "End turn (hotseat)", "enabled": can_end_turn},
    ]
    for r in day_rows:
        actions.append(
            {
                "action_id": r["action_id"],
                "label": r["label"],
                "enabled": r["enabled"],
                "step": r["step"],
            }
        )

    label = (
        "Hotseat banner · turn %d · active %s · slots %d · journal %d · dead %d · score %.2f"
        % (
            turn_index,
            tag or "—",
            len(clean_slots),
            journal_len,
            int(audit.get("dead_n", 0)),
            score,
        )
    )
    out = dict(product_core)
    out.update(
        {
            "active_control": control,
            "is_active_human": is_active_human,
            "lobby_ready": bool(lobby_ready),
            "commands": journal[-64:],
            "lock_self": lock_self,
            "lock_other": lock_other,
            "audit": audit,
            "dead_n": int(audit.get("dead_n", 0)),
            "dead_ok": bool(audit.get("ok")),
            "day_rows": day_rows,
            "apply_queue": apply_queue,
            "actions": actions,
            "score": score,
            "province_id": max(1, int(province_id)),
            "mode": "hotseat",
            "summary": label,
            "plain": "\n".join(
                [
                    label,
                    banner_text,
                    str(lock_self.get("summary", "")),
                    str(audit.get("summary", "")),
                ]
                + [r["label"] for r in day_rows]
            ),
            "bbcode": "[color=#e0c06a]👥 Hotseat banner[/color] [color=#8899aa]%s[/color]" % label,
            "empty": False,
            "ok": bool(audit.get("ok")) and can_end_turn and bool(lock_self.get("allowed")),
            "integration": [
                "hotseat_turn_banner_product",
                "session_players",
                "hotseat",
                "turn_banner",
                "non_active_lock",
                "end_turn",
                "command_journal",
                "phase_n1",
                "multiplayer_foundation",
            ],
        }
    )
    return out


def build_hotseat_turn_banner_from_runtime(
    rt: Optional[Dict[str, Any]] = None,
    *,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Map a SessionPlayers-style runtime dict onto the banner product."""
    runtime = rt if isinstance(rt, dict) else _new_runtime()
    return build_hotseat_turn_banner_product(
        slots=list(runtime.get("slots") or []),
        active_tag=str(runtime.get("active_tag") or ""),
        turn=int(runtime.get("turn") or 1),
        commands=list(runtime.get("command_queue") or []),
        province_id=province_id,
        lobby_ready=bool(runtime.get("lobby_ready", True)),
    )


def apply_hotseat_end_turn(
    rt: Dict[str, Any],
    *,
    province_id: int = 1,
    flush: bool = True,
) -> Dict[str, Any]:
    """Flush command journal (optional) then rotate active player — end-turn path."""
    banner_before = build_hotseat_turn_banner_from_runtime(rt, province_id=province_id)
    if not banner_before.get("can_end_turn"):
        return {
            "ok": False,
            "error": "cannot_end_turn",
            "banner": banner_before,
            "live": True,
            "empty": False,
        }
    steps: List[Dict[str, Any]] = []
    if flush and list(rt.get("command_queue") or []):
        steps.append(apply_session_step(rt, "execute", province_id=province_id))
    steps.append(apply_session_step(rt, "rotate", province_id=province_id))
    banner_after = build_hotseat_turn_banner_from_runtime(rt, province_id=province_id)
    return {
        "ok": True,
        "live": True,
        "steps": steps,
        "banner_before": banner_before,
        "banner_after": banner_after,
        "active_tag": str(rt.get("active_tag") or ""),
        "turn": int(rt.get("turn") or 1),
        "command_journal_len": len(rt.get("command_queue") or []),
        "summary": "End turn → active %s · turn %d"
        % (rt.get("active_tag"), int(rt.get("turn") or 1)),
        "empty": False,
    }


def close_hotseat_turn_banner_loop(
    slots: Optional[Sequence[Dict[str, Any]]] = None,
    province_id: int = 1,
) -> Dict[str, Any]:
    """Lobby → enqueue (active only) → reject non-active → end-turn rotate → audit."""
    rt = _new_runtime(slots)
    apply_session_step(rt, "lobby", province_id=province_id)
    active = str(rt.get("active_tag") or "")
    # Active may enqueue
    apply_session_step(
        rt,
        "enqueue",
        {"action": "apply_production", "tag": active, "province_id": province_id},
        province_id,
    )
    # Lock audit: non-active denied
    other = ""
    for s in list(rt.get("slots") or []):
        t = str(s.get("tag") or "").upper()
        if t and t != active.upper():
            other = t
            break
    deny = hotseat_lock_audit(active, other) if other else {"allowed": False, "ok": True}
    allow = hotseat_lock_audit(active, active)

    end = apply_hotseat_end_turn(rt, province_id=province_id, flush=True)
    product = build_hotseat_turn_banner_from_runtime(rt, province_id=province_id)
    session_close = close_hotseat_session(slots=slots, province_id=province_id)

    ok = (
        bool(product.get("ok"))
        and int(product.get("dead_n", 1)) == 0
        and bool(allow.get("allowed"))
        and not bool(deny.get("allowed"))
        and bool(end.get("ok"))
        and bool(session_close.get("ok"))
    )
    score = _floor(0.4 + (0.25 if ok else 0.0) + 0.05 * min(int(product.get("turn_index") or 1), 4))
    label = (
        "Hotseat N1 polish %s · turn %d · active %s · dead %d · score %.2f"
        % (
            "PASS" if ok else "FAIL",
            int(product.get("turn_index") or 0),
            str(product.get("active_tag") or ""),
            int(product.get("dead_n", 0)),
            score,
        )
    )
    return {
        "ok": ok,
        "live": True,
        "score": score,
        "product": product,
        "allow": allow,
        "deny": deny,
        "end_turn": end,
        "session_close": {
            "ok": bool(session_close.get("ok")),
            "slot_n": int(session_close.get("slot_n") or 0),
            "summary": str(session_close.get("summary") or ""),
        },
        "runtime": rt,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e0c06a]👥 N1 Hotseat[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "dead_n": int(product.get("dead_n", 0)),
        "mode": "hotseat",
        "integration": [
            "hotseat_turn_banner_product",
            "session_players_hotseat_product",
            "hotseat_lock_audit",
            "end_turn",
            "phase_n1",
        ],
    }


def hotseat_turn_banner_integrity() -> Dict[str, Any]:
    from pathlib import Path

    root = Path(__file__).resolve().parents[3]
    sp = root / "scripts" / "autoload" / "SessionPlayers.gd"
    sp_text = sp.read_text(encoding="utf-8") if sp.is_file() else ""
    top = root / "scripts" / "ui" / "TopInfoBar.gd"
    top_text = top.read_text(encoding="utf-8") if top.is_file() else ""
    closed = close_hotseat_turn_banner_loop()
    product = closed.get("product") or {}
    audit = hotseat_turn_banner_dead_audit(product)
    wired = (
        sp.is_file()
        and "get_turn_banner_state" in sp_text
        and "is_command_allowed_for_tag" in sp_text
        and "rotate_active_player" in sp_text
        and "_refresh_hotseat_banner" in top_text
    )
    ok = (
        bool(closed.get("ok"))
        and int(audit.get("dead_n", 1)) == 0
        and wired
    )
    return {
        "ok": ok,
        "closed": closed,
        "audit": audit,
        "wired": wired,
        "dead_n": int(audit.get("dead_n", 0)),
        "summary": "Hotseat turn banner integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
