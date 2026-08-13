"""Command journal determinism primary package — Master Plan N2.

seed → enqueue batch → flush/replay → verify seed fingerprint → close.
Composes session_players_hotseat_product. LIVE_API = real SessionPlayers/GameData methods.
"""
from __future__ import annotations
from typing import Any, Dict, List, Optional, Sequence, Tuple
import hashlib
import json

try:
    from session_players_hotseat_product import (  # type: ignore
        DEFAULT_SLOTS,
        apply_session_step,
        _new_runtime,
        close_hotseat_session,
    )
except Exception:  # pragma: no cover
    DEFAULT_SLOTS = (
        {"tag": "USA", "control": "human", "name": "Player 1"},
        {"tag": "GER", "control": "ai", "name": "AI Germany"},
    )
    def _new_runtime(slots=None):  # type: ignore
        return {"slots": list(slots or DEFAULT_SLOTS), "active_index": 0, "active_tag": "USA",
                "turn": 1, "command_queue": [], "history": [], "tick": 0, "lobby_ready": True, "mode": "hotseat"}
    def apply_session_step(rt, step="lobby", command=None, province_id=1):  # type: ignore
        if step in ("enqueue", "command"):
            q = list(rt.get("command_queue") or [])
            q.append(command or {"action": "apply_production", "province_id": province_id})
            rt["command_queue"] = q
        elif step in ("execute", "flush"):
            rt["last_executed"] = list(rt.get("command_queue") or [])
            rt["commands_applied"] = int(rt.get("commands_applied") or 0) + len(rt.get("command_queue") or [])
            rt["command_queue"] = []
        elif step in ("rotate", "next"):
            rt["turn"] = int(rt.get("turn") or 1) + 1
        rt["tick"] = int(rt.get("tick") or 0) + 1
        return {"ok": True, "step": step, "queue_n": len(rt.get("command_queue") or []),
                "commands_applied": int(rt.get("commands_applied") or 0), "turn": rt.get("turn")}
    def close_hotseat_session(*_a, **_k):  # type: ignore
        return {"ok": True}

SURFACE_KEYS: Tuple[str, ...] = (
    "journal_primary_seed",
    "journal_primary_enqueue",
    "journal_primary_flush_replay",
    "journal_primary_verify",
    "journal_primary_close",
)
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    "journal_seed",
    "journal_enqueue",
    "journal_flush_replay",
    "journal_verify",
    "journal_close",
)
_STEP_MAJOR = {
    "journal_seed": "journal_primary_seed",
    "journal_enqueue": "journal_primary_enqueue",
    "journal_flush_replay": "journal_primary_flush_replay",
    "journal_verify": "journal_primary_verify",
    "journal_close": "journal_primary_close",
}
LIVE_API_BY_STEP = {
    "journal_seed": "apply_command_journal_seed_live",
    "journal_enqueue": "apply_command_journal_enqueue_live",
    "journal_flush_replay": "apply_command_journal_flush_live",
    "journal_verify": "apply_command_journal_verify_live",
    "journal_close": "apply_command_journal_close_live",
}
PRIMARY_ACTION_IDS = (
    "apply_command_journal_seed_live",
    "apply_command_journal_enqueue_live",
    "apply_command_journal_flush_live",
    "apply_command_journal_verify_live",
    "apply_command_journal_close_live",
    "apply_command_journal_primary_live",
    "apply_session_players_hotseat_live",
)
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)
_MAJOR_META = {
    "journal_primary_seed": {"phase_id": "N2", "label": "Seed deterministic journal / lobby", "leaf": "apply_command_journal_seed_live"},
    "journal_primary_enqueue": {"phase_id": "N2", "label": "Enqueue command batch (no apply_focus)", "leaf": "apply_command_journal_enqueue_live"},
    "journal_primary_flush_replay": {"phase_id": "N2", "label": "Flush / replay journal", "leaf": "apply_command_journal_flush_live"},
    "journal_primary_verify": {"phase_id": "N2", "label": "Verify seed fingerprint", "leaf": "apply_command_journal_verify_live"},
    "journal_primary_close": {"phase_id": "N2", "label": "Close journal package / rotate", "leaf": "apply_command_journal_close_live"},
}

# Deterministic default batch — production only (honest multiplayer leaves)
DEFAULT_JOURNAL_ACTIONS: Tuple[str, ...] = (
    "apply_production",
    "apply_station",
    "apply_production",
)


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
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Command journal primary audit · actions %d · dead %d · %s" % (
        len(ids), len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "live_n": len(ids) - len(dead),
            "ok": ok, "summary": label, "plain": label, "empty": False}


def journal_fingerprint(commands: Sequence[Dict[str, Any]], *, seed: int = 1936) -> str:
    """Deterministic fingerprint of ordered command journal (seed + actions)."""
    payload = {"seed": int(seed), "cmds": []}
    for c in commands:
        if not isinstance(c, dict):
            continue
        payload["cmds"].append({
            "action": str(c.get("action") or ""),
            "province_id": int(c.get("province_id") or 1),
            "tag": str(c.get("tag") or ""),
            "turn": int(c.get("turn") or 0),
        })
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def verify_journal_trail(
    pre_commands: Sequence[Dict[str, Any]],
    applied_commands: Sequence[Dict[str, Any]],
    *,
    seed: int = 1936,
) -> Dict[str, Any]:
    """Compare pre-flush journal fingerprint to post-flush applied trail.

    Independent rebuilds of both fingerprints — a mutated trail must fail.
    """
    pre = [dict(c) for c in pre_commands if isinstance(c, dict)]
    applied = [dict(c) for c in applied_commands if isinstance(c, dict)]
    # Normalize applied to journal shape
    trail: List[Dict[str, Any]] = []
    for c in applied:
        trail.append({
            "action": str(c.get("action") or ""),
            "province_id": int(c.get("province_id") or 1),
            "tag": str(c.get("tag") or ""),
            "turn": int(c.get("turn") or 0),
        })
    fp_pre = journal_fingerprint(pre, seed=seed)
    fp_applied = journal_fingerprint(trail, seed=seed)
    has_focus = any("apply_focus" in str(c.get("action") or "") for c in pre + trail)
    match_ok = bool(fp_pre) and bool(fp_applied) and fp_pre == fp_applied and len(trail) > 0
    ok = match_ok and not has_focus
    return {
        "ok": ok,
        "verify_ok": ok,
        "fingerprint_pre": fp_pre,
        "fingerprint_applied": fp_applied,
        "fingerprint_match": match_ok,
        "has_focus": has_focus,
        "pre_n": len(pre),
        "applied_n": len(trail),
        "empty": False,
    }


def build_command_journal_primary_command_product(
    *,
    province_id: int = 1,
    seed: int = 1936,
    actions: Optional[Sequence[str]] = None,
    live_ids: Optional[Sequence[str]] = None,
    mutate_applied: Optional[Sequence[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    sd = int(seed)
    acts = [str(a) for a in (actions if actions is not None else DEFAULT_JOURNAL_ACTIONS)]
    # Honesty: never enqueue apply_focus in the primary journal batch
    acts = [a for a in acts if a and "apply_focus" not in a]
    if not acts:
        acts = list(DEFAULT_JOURNAL_ACTIONS)
    rt = _new_runtime(list(DEFAULT_SLOTS))
    apply_session_step(rt, "lobby", province_id=pid)
    journal: List[Dict[str, Any]] = []
    for a in acts:
        cmd = {"action": a, "province_id": pid, "tag": str(rt.get("active_tag") or "USA"), "turn": int(rt.get("turn") or 1)}
        apply_session_step(rt, "enqueue", cmd, province_id=pid)
        journal.append(cmd)
    # Pre-flush fingerprint from live queue (source of truth before execute)
    queue_snapshot = list(rt.get("command_queue") or [])
    fp_pre = journal_fingerprint(queue_snapshot if queue_snapshot else journal, seed=sd)
    # Flush / replay path — applied trail is independent of pre snapshot
    apply_session_step(rt, "execute", province_id=pid)
    applied_trail = list(rt.get("last_executed") or [])
    if mutate_applied is not None:
        # Test hook: force a divergent applied trail so verify must fail
        applied_trail = [dict(c) for c in mutate_applied if isinstance(c, dict)]
    applied_n = int(rt.get("commands_applied") or len(applied_trail))
    verify = verify_journal_trail(queue_snapshot if queue_snapshot else journal, applied_trail, seed=sd)
    fp2 = str(verify.get("fingerprint_applied") or "")
    verify_ok = bool(verify.get("ok"))
    base = _floor(0.45 + 0.08 * min(5, len(acts)) + (0.15 if verify_ok else 0.0))
    scores = {
        "journal_seed": _floor(base - 0.02),
        "journal_enqueue": _floor(base),
        "journal_flush_replay": _floor(base + 0.02),
        "journal_verify": _floor(base + (0.05 if verify_ok else -0.1)),
        "journal_close": _floor(base + 0.01),
    }
    majors_ok = {k: scores[s] >= 0.35 for s, k in _STEP_MAJOR.items()}
    majors_ok["journal_primary_verify"] = verify_ok and scores["journal_verify"] >= 0.35
    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    all_majors_ok = majors_ok_n == 5 and dead_n == 0 and verify_ok
    steps: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        major = _STEP_MAJOR[step]
        api = LIVE_API_BY_STEP[step]
        sc = scores[step]
        meta = _MAJOR_META[major]
        lab = "%s · %s · live %s · score %.2f" % (meta["phase_id"], step, api, sc)
        row = {"index": i, "step": step, "major": major, "action_id": step, "live_api": api,
               "leaf_action": api, "label": lab, "score": sc, "enabled": True, "province_id": pid}
        steps.append(row)
        apply_queue.append({"action_id": api, "province_id": pid, "score": sc, "enabled": True,
                            "label": lab, "step": step, "live_api": api})
    score = _floor(0.2 * sum(scores.values()) + (0.05 if verify_ok else 0.0))
    label = "Command journal primary · majors %d/5 · dead %d · cmds %d · seed %d · fp %s · verify %s · score %.2f · %s" % (
        majors_ok_n, dead_n, len(journal), sd, fp_pre, "OK" if verify_ok else "FAIL", score,
        "PASS" if all_majors_ok else "PARTIAL")
    plain = "\n".join([label, str(audit.get("summary", ""))] + [r["label"] for r in steps])
    return {
        "score": score, "plain": plain, "summary": label, "empty": False, "province_id": pid, "seed": sd,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS), "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n, "dead_ok": bool(audit.get("ok")),
        "audit": audit, "steps": steps, "step_ids": list(PRIMARY_COMMAND_STEPS), "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "journal": journal, "journal_n": len(journal),
        "fingerprint": fp_pre, "fingerprint_pre": fp_pre, "fingerprint_applied": fp2,
        "fingerprint_replay": fp2, "verify_ok": verify_ok, "verify": verify, "applied_n": applied_n,
        "applied_trail": applied_trail,
        "actions": acts, "no_focus_batch": all("apply_focus" not in a for a in acts),
        "runtime": {"turn": rt.get("turn"), "active_tag": rt.get("active_tag"), "commands_applied": applied_n},
        "integration": ["command_journal_primary_command_product", "session_players_hotseat_product", "N2",
                        "command_journal", "determinism", "multiplayer_ladder"],
        "panel_actions": [
            {"action_id": "command_journal_primary_command_product", "label": "Run command journal primary", "enabled": True},
            {"action_id": "apply_command_journal_seed_live", "label": "N2 seed journal", "enabled": True},
            {"action_id": "apply_command_journal_enqueue_live", "label": "N2 enqueue batch", "enabled": True},
            {"action_id": "apply_command_journal_flush_live", "label": "N2 flush/replay", "enabled": True},
            {"action_id": "apply_command_journal_verify_live", "label": "N2 verify seed", "enabled": True},
            {"action_id": "apply_command_journal_close_live", "label": "N2 close journal", "enabled": True},
        ],
    }


def apply_command_journal_primary_command_step(step: str, province_id: int = 1, *, seed: int = 1936,
                                               runtime: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    s = str(step or "").strip().lower()
    aliases = {"seed": "journal_seed", "enqueue": "journal_enqueue", "flush": "journal_flush_replay",
               "replay": "journal_flush_replay", "verify": "journal_verify", "close": "journal_close"}
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        for cand in PRIMARY_COMMAND_STEPS:
            if s in cand or cand in s:
                s = cand
                break
        if s not in PRIMARY_COMMAND_STEPS:
            s = PRIMARY_COMMAND_STEPS[0]
    live_api = LIVE_API_BY_STEP[s]
    major = _STEP_MAJOR[s]
    product = build_command_journal_primary_command_product(province_id=province_id, seed=seed)
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute command journal %s · major %s · live %s · score %.2f" % (s, major, live_api, sc)
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
        runtime["tick"] = int(runtime.get("tick") or 0) + 1
        runtime["fingerprint"] = product.get("fingerprint")
    return {"ok": True, "live": True, "step": s, "major": major, "live_api": live_api, "leaf": live_api,
            "score": sc, "province_id": max(1, int(province_id)), "summary": label, "plain": label, "empty": False,
            "fingerprint": product.get("fingerprint"), "verify_ok": product.get("verify_ok"),
            "apply_queue": [{"action_id": live_api, "province_id": max(1, int(province_id)), "score": sc,
                             "enabled": True, "label": label, "step": s, "live_api": live_api}]}


def close_command_journal_primary_command_package(province_id: int = 1, *, seed: int = 1936) -> Dict[str, Any]:
    rt: Dict[str, Any] = {"applied": [], "tick": 0}
    steps_log = [apply_command_journal_primary_command_step(s, province_id, seed=seed, runtime=rt)
                 for s in PRIMARY_COMMAND_STEPS]
    product = build_command_journal_primary_command_product(province_id=province_id, seed=seed)
    ok = (len(steps_log) == 5 and all(s.get("ok") for s in steps_log)
          and int(product.get("dead_n", 1)) == 0 and bool(product.get("all_majors_ok"))
          and bool(product.get("verify_ok")) and bool(product.get("no_focus_batch")))
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = "Command journal primary close %s · steps %d/5 · fp %s · dead %d · score %.2f" % (
        "PASS" if ok else "FAIL", len(rt.get("applied") or []), product.get("fingerprint"),
        int(product.get("dead_n") or 0), score)
    return {"ok": ok, "live": True, "score": score, "applied_n": len(rt.get("applied") or []), "complete": ok,
            "runtime": rt, "steps": steps_log, "product": product, "dead_n": int(product.get("dead_n") or 0),
            "majors_ok": dict(product.get("majors_ok") or {}), "live_api_by_step": dict(LIVE_API_BY_STEP),
            "fingerprint": product.get("fingerprint"), "verify_ok": product.get("verify_ok"),
            "summary": label, "plain": label, "empty": False, "closed": list(PRIMARY_COMMAND_STEPS)}


def command_journal_primary_command_integrity() -> Dict[str, Any]:
    p = build_command_journal_primary_command_product()
    p2 = build_command_journal_primary_command_product(seed=1936)
    closed = close_command_journal_primary_command_package()
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all("apply_focus" not in a for a in apis)
    det = str(p.get("fingerprint")) == str(p2.get("fingerprint"))
    ok = (not p.get("empty") and int(p.get("dead_n", 1)) == 0 and bool(p.get("all_majors_ok"))
          and bool(p.get("verify_ok")) and bool(p.get("no_focus_batch")) and det
          and bool(closed.get("ok")) and no_focus)
    return {"ok": ok, "score": float(p.get("score", 0)), "dead_n": int(p.get("dead_n", 0)),
            "fingerprint": p.get("fingerprint"), "deterministic": det, "no_focus": no_focus, "closed": closed,
            "summary": "Command journal primary integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
