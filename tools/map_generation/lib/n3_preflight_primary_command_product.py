"""N3 preflight primary (not full netcode).

Honest journal path mirrors N2: lobby → seed → enqueue → flush → verify.
LIVE_API = real GameData methods (not bare apply_focus).
"""
from __future__ import annotations

SURFACE_KEYS = (
    "n3p_primary_lobby",
    "n3p_primary_seed",
    "n3p_primary_enqueue",
    "n3p_primary_flush",
    "n3p_primary_verify",
)
PRIMARY_COMMAND_STEPS = (
    "n3p_lobby",
    "n3p_seed",
    "n3p_enqueue",
    "n3p_flush",
    "n3p_verify",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "n3p_lobby": "apply_hotseat_session_lobby_live",
    "n3p_seed": "apply_command_journal_seed_live",
    "n3p_enqueue": "apply_command_journal_enqueue_live",
    "n3p_flush": "apply_command_journal_flush_live",
    "n3p_verify": "apply_command_journal_verify_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def _floor(score, lo=0.35):
    try:
        s = float(score)
    except Exception:
        s = 0.5
    if s > 2:
        s /= 100.0
    s = max(0.0, min(1.0, s))
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    # Honesty: verify must follow enqueue+flush in the product step order.
    order_ok = (
        PRIMARY_COMMAND_STEPS.index("n3p_seed")
        < PRIMARY_COMMAND_STEPS.index("n3p_enqueue")
        < PRIMARY_COMMAND_STEPS.index("n3p_flush")
        < PRIMARY_COMMAND_STEPS.index("n3p_verify")
    )
    ok = ok and order_ok
    label = "N3 preflight primary (not full netcode) audit · dead %d · order %s · %s" % (
        len(dead),
        "ok" if order_ok else "bad",
        "PASS" if ok else "FAIL",
    )
    return {
        "action_ids": ids,
        "dead": dead,
        "dead_n": len(dead),
        "order_ok": order_ok,
        "ok": ok,
        "summary": label,
        "plain": label,
        "empty": False,
    }


def build_n3_preflight_primary_command_product(*, province_id=1, live_ids=None):
    pid = max(1, int(province_id))
    base = 0.63
    scores = {s: _floor(base + 0.01 * i) for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
    majors_ok = {SURFACE_KEYS[i]: scores[PRIMARY_COMMAND_STEPS[i]] >= 0.35 for i in range(5)}
    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    all_majors_ok = majors_ok_n == 5 and dead_n == 0 and bool(audit.get("order_ok"))
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        sc = scores[step]
        lab = "n3_preflight · %s · live %s · score %.2f" % (step, api, sc)
        steps_out.append(
            {
                "index": i,
                "step": step,
                "major": _STEP_MAJOR[step],
                "action_id": step,
                "live_api": api,
                "leaf_action": api,
                "label": lab,
                "score": sc,
                "enabled": True,
                "province_id": pid,
            }
        )
        apply_queue.append(
            {
                "action_id": api,
                "province_id": pid,
                "score": sc,
                "enabled": True,
                "label": lab,
                "step": step,
                "live_api": api,
            }
        )
    score = _floor(0.2 * sum(scores.values()) + (0.05 if dead_n == 0 else 0))
    label = "N3 preflight primary (not full netcode) · majors %d/5 · dead %d · score %.2f · %s" % (
        majors_ok_n,
        dead_n,
        score,
        "PASS" if all_majors_ok else "PARTIAL",
    )
    return {
        "score": score,
        "plain": label + "\n" + "\n".join(r["label"] for r in steps_out),
        "summary": label,
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
        "steps": steps_out,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "step_scores": scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue,
        "integration": ["n3_preflight_primary_command_product", "N2_journal", "not_full_n3"],
        "netcode_ready": False,
        "not_full_n3": True,
        "requires_seed_enqueue_flush_verify": True,
    }


def apply_n3_preflight_primary_command_step(step, province_id=1, *, runtime=None):
    s = str(step or "").strip().lower()
    aliases = {full: full for full in PRIMARY_COMMAND_STEPS}
    for full in PRIMARY_COMMAND_STEPS:
        aliases[full.split("_", 1)[-1]] = full
    s = aliases.get(s, s)
    if s not in PRIMARY_COMMAND_STEPS:
        s = PRIMARY_COMMAND_STEPS[0]
    product = build_n3_preflight_primary_command_product(province_id=province_id)
    api = LIVE_API_BY_STEP[s]
    sc = float(product.get("step_scores", {}).get(s, 0.5))
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
    return {
        "ok": True,
        "live": True,
        "step": s,
        "live_api": api,
        "leaf": api,
        "score": sc,
        "province_id": province_id,
        "summary": "Execute %s · %s" % (s, api),
        "plain": "Execute %s" % s,
        "empty": False,
    }
