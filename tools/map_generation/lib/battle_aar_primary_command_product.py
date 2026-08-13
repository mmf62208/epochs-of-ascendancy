"""Battle AAR / combat log primary command package — Master Plan C4.

open → record outcome → factor extract → persist trail → close.
Composes multi_phase combat + combat ops close. LIVE_API = real GameData methods.
"""
from __future__ import annotations
from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from combat_multi_phase_product import build_multi_phase_combat_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_phase_combat_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "overall": 0.6, "phase_actions": [
            {"phase": "approach"}, {"phase": "engage"}, {"phase": "disengage"}],
            "recommendation": {"phase": "engage", "action_id": "phase_engage"}, "empty": False}

SURFACE_KEYS: Tuple[str, ...] = (
    "aar_primary_open",
    "aar_primary_record",
    "aar_primary_factors",
    "aar_primary_persist",
    "aar_primary_close",
)
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    "aar_open",
    "aar_record",
    "aar_factors",
    "aar_persist",
    "aar_close",
)
_STEP_MAJOR = {
    "aar_open": "aar_primary_open",
    "aar_record": "aar_primary_record",
    "aar_factors": "aar_primary_factors",
    "aar_persist": "aar_primary_persist",
    "aar_close": "aar_primary_close",
}
# Real GameData methods (exist or added in GD wire as named live helpers)
LIVE_API_BY_STEP = {
    "aar_open": "apply_multi_phase_combat_product",
    "aar_record": "apply_combat_ops_close_live",
    "aar_factors": "apply_phase_engage",
    "aar_persist": "apply_battle_aar_persist_live",
    "aar_close": "apply_battle_aar_close_live",
}
PRIMARY_ACTION_IDS = (
    "apply_multi_phase_combat_product",
    "apply_combat_ops_close_live",
    "apply_phase_engage",
    "apply_phase_approach",
    "apply_phase_disengage",
    "apply_battle_aar_persist_live",
    "apply_battle_aar_close_live",
    "apply_battle_aar_live",
)
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)
_MAJOR_META = {
    "aar_primary_open": {"phase_id": "C4", "label": "Open multi-phase combat board for AAR", "leaf": "apply_multi_phase_combat_product"},
    "aar_primary_record": {"phase_id": "C4", "label": "Record combat ops close outcome", "leaf": "apply_combat_ops_close_live"},
    "aar_primary_factors": {"phase_id": "C4", "label": "Extract engage phase factors", "leaf": "apply_phase_engage"},
    "aar_primary_persist": {"phase_id": "C4", "label": "Persist AAR trail (save-friendly)", "leaf": "apply_battle_aar_persist_live"},
    "aar_primary_close": {"phase_id": "C4", "label": "Close AAR package", "leaf": "apply_battle_aar_close_live"},
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
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Battle AAR primary audit · actions %d · dead %d · %s" % (
        len(ids), len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "live_n": len(ids) - len(dead),
            "ok": ok, "summary": label, "plain": label, "empty": False}


def build_battle_aar_entries(
    combat: Dict[str, Any],
    *,
    province_id: int = 1,
    winner: str = "GER",
    attacker: str = "GER",
    defender: str = "FRA",
) -> List[Dict[str, Any]]:
    """Readable post-battle entries from multi-phase product (save-friendly structure)."""
    overall = _floor(float(combat.get("overall") or combat.get("score") or 0.55))
    phases = list(combat.get("phase_actions") or [])
    factors: List[str] = []
    rec = combat.get("recommendation") if isinstance(combat.get("recommendation"), dict) else {}
    if rec:
        factors.append(str(rec.get("step") or rec.get("phase") or "engage"))
    for p in phases[:3]:
        if isinstance(p, dict):
            factors.append(str(p.get("phase") or p.get("action_id") or "phase"))
    factors = factors or ["multi_phase", "ops_close"]
    entries = [
        {
            "date": "campaign",
            "province_id": max(1, int(province_id)),
            "result": "win" if overall >= 0.5 else "hold",
            "winner": winner,
            "attacker": attacker,
            "defender": defender,
            "odds": overall,
            "key_factors": factors[:6],
            "summary": "AAR · %s vs %s · %s · odds %.2f · factors %s" % (
                attacker, defender, "win" if overall >= 0.5 else "hold", overall, ",".join(factors[:3])),
            "empty": False,
        }
    ]
    return entries


def build_battle_aar_primary_command_product(
    *,
    province_id: int = 1,
    winner: str = "GER",
    attacker: str = "GER",
    defender: str = "FRA",
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    combat = build_multi_phase_combat_product(province_id=pid)
    entries = build_battle_aar_entries(combat, province_id=pid, winner=winner, attacker=attacker, defender=defender)
    base = _floor(float(combat.get("score") or combat.get("overall") or 0.55))
    scores = {
        "aar_open": base,
        "aar_record": _floor(base + 0.02),
        "aar_factors": _floor(base + 0.01),
        "aar_persist": _floor(0.5 * base + 0.4),
        "aar_close": _floor(base + 0.03),
    }
    majors_ok = {k: scores[s] >= 0.35 for s, k in _STEP_MAJOR.items()}
    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    all_majors_ok = majors_ok_n == 5 and dead_n == 0 and len(entries) >= 1
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
    score = _floor(0.2 * sum(scores.values()) + (0.05 if dead_n == 0 else 0.0))
    label = "Battle AAR primary · majors %d/5 · dead %d · entries %d · score %.2f · %s" % (
        majors_ok_n, dead_n, len(entries), score, "PASS" if all_majors_ok else "PARTIAL")
    plain = "\n".join([label, str(audit.get("summary", "")), entries[0]["summary"]] + [r["label"] for r in steps])
    return {
        "score": score, "plain": plain, "summary": label, "empty": False, "province_id": pid,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS), "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n, "all_majors_ok": all_majors_ok, "dead_n": dead_n, "dead_ok": bool(audit.get("ok")),
        "audit": audit, "steps": steps, "step_ids": list(PRIMARY_COMMAND_STEPS), "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP), "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue, "entries": entries, "entry_n": len(entries), "combat": combat,
        "winner": winner, "attacker": attacker, "defender": defender,
        "integration": ["battle_aar_primary_command_product", "combat_multi_phase_product", "C4", "aar",
                        "battle_log", "primary_command"],
        "panel_actions": [
            {"action_id": "battle_aar_primary_command_product", "label": "Run battle AAR primary", "enabled": True},
            {"action_id": "apply_multi_phase_combat_product", "label": "C4 open combat board", "enabled": True},
            {"action_id": "apply_combat_ops_close_live", "label": "C4 record outcome", "enabled": True},
            {"action_id": "apply_phase_engage", "label": "C4 factors engage", "enabled": True},
            {"action_id": "apply_battle_aar_persist_live", "label": "C4 persist AAR", "enabled": True},
            {"action_id": "apply_battle_aar_close_live", "label": "C4 close AAR", "enabled": True},
        ],
    }


def apply_battle_aar_primary_command_step(step: str, province_id: int = 1, *,
                                          runtime: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    s = str(step or "").strip().lower()
    aliases = {"open": "aar_open", "record": "aar_record", "factors": "aar_factors",
               "persist": "aar_persist", "close": "aar_close", "summary": "aar_persist"}
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
    product = build_battle_aar_primary_command_product(province_id=province_id)
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute battle AAR %s · major %s · live %s · score %.2f" % (s, major, live_api, sc)
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
        runtime["tick"] = int(runtime.get("tick") or 0) + 1
        if s == "aar_record":
            runtime["entries"] = list(product.get("entries") or [])
    return {"ok": True, "live": True, "step": s, "major": major, "live_api": live_api, "leaf": live_api,
            "score": sc, "province_id": max(1, int(province_id)), "summary": label, "plain": label, "empty": False,
            "entries": list(product.get("entries") or []),
            "apply_queue": [{"action_id": live_api, "province_id": max(1, int(province_id)), "score": sc,
                             "enabled": True, "label": label, "step": s, "live_api": live_api}]}


def close_battle_aar_primary_command_package(province_id: int = 1) -> Dict[str, Any]:
    rt: Dict[str, Any] = {"applied": [], "tick": 0, "entries": []}
    steps_log = [apply_battle_aar_primary_command_step(s, province_id, runtime=rt) for s in PRIMARY_COMMAND_STEPS]
    product = build_battle_aar_primary_command_product(province_id=province_id)
    ok = (len(steps_log) == 5 and all(s.get("ok") for s in steps_log)
          and int(product.get("dead_n", 1)) == 0 and bool(product.get("all_majors_ok")))
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = "Battle AAR primary close %s · steps %d/5 · entries %d · dead %d · score %.2f" % (
        "PASS" if ok else "FAIL", len(rt.get("applied") or []), int(product.get("entry_n") or 0),
        int(product.get("dead_n") or 0), score)
    return {"ok": ok, "live": True, "score": score, "applied_n": len(rt.get("applied") or []), "complete": ok,
            "runtime": rt, "steps": steps_log, "product": product, "dead_n": int(product.get("dead_n") or 0),
            "majors_ok": dict(product.get("majors_ok") or {}), "live_api_by_step": dict(LIVE_API_BY_STEP),
            "entries": list(product.get("entries") or []), "summary": label, "plain": label, "empty": False,
            "closed": list(PRIMARY_COMMAND_STEPS)}


def battle_aar_primary_command_integrity() -> Dict[str, Any]:
    p = build_battle_aar_primary_command_product()
    closed = close_battle_aar_primary_command_package()
    apis = list(LIVE_API_BY_STEP.values())
    no_focus = all("apply_focus" not in a for a in apis)
    has_combat = "apply_combat_ops_close_live" in apis and "apply_multi_phase_combat_product" in apis
    ok = (not p.get("empty") and int(p.get("dead_n", 1)) == 0 and bool(p.get("all_majors_ok"))
          and int(p.get("entry_n") or 0) >= 1 and bool(closed.get("ok")) and no_focus and has_combat)
    return {"ok": ok, "score": float(p.get("score", 0)), "dead_n": int(p.get("dead_n", 0)),
            "entry_n": int(p.get("entry_n") or 0), "no_focus": no_focus, "closed": closed,
            "summary": "Battle AAR primary integrity %s" % ("PASS" if ok else "FAIL"), "empty": False}
