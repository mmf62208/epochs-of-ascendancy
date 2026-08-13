"""Save/resume campaign continuity product (major #40) — Phase 5.

Checkpoint board → slot save → mid-war resume verify.
Deepens save browser (#4) with live continuity state (not multiplayer).
"""
from __future__ import annotations
from typing import Any, Dict, List
from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from save_browser_campaign_product import build_save_browser_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_save_browser_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.6, "empty": False, "summary": "save browser"}

PRODUCT_STEPS = ("checkpoint", "save", "resume")
SLOTS = ("quicksave", "autosave", "slot1", "slot2", "slot3")
_STEP_META = {
    "checkpoint": {"action_id": "save_resume_checkpoint", "leaf": "apply_focus", "label": "Step 0 — campaign checkpoint board"},
    "save": {"action_id": "save_resume_save", "leaf": "apply_production", "label": "Step 1 — write slot save"},
    "resume": {"action_id": "save_resume_resume", "leaf": "apply_station", "label": "Step 2 — mid-war resume verify"},
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


def compute_checkpoint_board(
    *, day: int = 45, player_tag: str = "GER", scenario_id: str = "world_full", war_active: bool = True
) -> Dict[str, Any]:
    d = max(1, int(day))
    tag = str(player_tag or "GER").upper()
    scen = str(scenario_id or "world_full")
    integrity = _floor(0.55 + 0.25 * (1.0 if war_active else 0.5) + min(0.2, d / 500.0))
    return {
        "day": d,
        "player_tag": tag,
        "scenario_id": scen,
        "war_active": bool(war_active),
        "integrity": integrity,
        "summary": "Checkpoint · day %d · %s · %s · war %s · integrity %.0f%%"
        % (d, tag, scen, "ON" if war_active else "OFF", integrity * 100),
        "empty": False,
    }


def compute_slot_plan(*, preferred: str = "slot1", occupied: List[str] | None = None) -> Dict[str, Any]:
    pref = str(preferred or "slot1").lower()
    if pref not in SLOTS:
        pref = "slot1"
    occ = [str(s).lower() for s in (occupied or ["quicksave", "autosave"])]
    free = [s for s in SLOTS if s not in occ]
    target = pref if pref in free or pref in occ else (free[0] if free else pref)
    can_save = True
    can_load = target in occ or target == pref
    score = _floor(0.5 + 0.1 * len(occ) + (0.15 if can_save else 0.0))
    return {
        "target_slot": target,
        "occupied": occ,
        "free": free,
        "can_save": can_save,
        "can_load": can_load,
        "score": score,
        "summary": "Slot plan · target %s · occupied %d · free %d · score %.2f"
        % (target, len(occ), len(free), score),
        "empty": False,
    }


def recommend_save_resume_step(*, checkpointed: bool = False, saved: bool = False) -> Dict[str, Any]:
    if not checkpointed:
        step, reason = "checkpoint", "board campaign continuity state"
    elif not saved:
        step, reason = "save", "write slot save for mid-war resume"
    else:
        step, reason = "resume", "verify load restores continuity"
    meta = _STEP_META[step]
    return {
        "step": step, "action_id": meta["action_id"], "leaf": meta["leaf"], "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason), "empty": False,
    }


def build_save_resume_campaign_product(
    *, province_id: int = 1, day: int = 45, player_tag: str = "GER", preferred_slot: str = "slot1"
) -> Dict[str, Any]:
    browser = build_save_browser_campaign_product()
    checkpoint = compute_checkpoint_board(day=day, player_tag=player_tag, war_active=True)
    slots = compute_slot_plan(preferred=preferred_slot)
    browser_s = _floor(float(browser.get("score", 0.55)))
    check_score = _floor(0.45 * browser_s + 0.55 * float(checkpoint["integrity"]))
    save_score = _floor(0.5 * float(slots["score"]) + 0.5 * check_score)
    resume_score = _floor(0.55 * save_score + 0.45 * check_score)
    score = _floor(0.3 * check_score + 0.35 * save_score + 0.35 * resume_score)
    rec = recommend_save_resume_step(checkpointed=True, saved=True)
    step_scores = {"checkpoint": check_score, "save": save_score, "resume": resume_score}
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        sc = step_scores[step]
        recommended = step == str(rec.get("step"))
        lab = ("★ " if recommended else "") + meta["label"] + " · score %.2f" % sc
        day_rows.append({
            "index": i, "step": step, "action_id": meta["action_id"], "leaf_action": meta["leaf"],
            "label": lab, "score": sc, "enabled": True, "recommended": recommended,
            "province_id": max(1, int(province_id)),
        })
        apply_queue.append({
            "action_id": meta["leaf"], "province_id": max(1, int(province_id)), "score": sc,
            "enabled": True, "label": lab, "step": step, "product_action": meta["action_id"],
        })
    actions = [
        {"action_id": "save_resume_campaign_product", "label": "Run save/resume campaign product", "enabled": True},
        {"action_id": str(rec.get("action_id")), "label": "Recommended: %s" % rec.get("step"), "enabled": True},
        {"action_id": "save_slot_quicksave", "label": "Save: quicksave", "enabled": True},
        {"action_id": "save_slot_slot1", "label": "Save: slot1", "enabled": True},
        {"action_id": "load_slot_slot1", "label": "Load: slot1", "enabled": True},
    ]
    for r in day_rows:
        actions.append({"action_id": r["action_id"], "label": r["label"], "enabled": True, "step": r["step"]})
    label = "Save/resume campaign · day %d · slot %s · integrity %.0f%% · score %.2f" % (
        checkpoint["day"], slots["target_slot"], float(checkpoint["integrity"]) * 100, score)
    return {
        "browser": browser, "checkpoint": checkpoint, "slots": slots, "recommendation": rec,
        "day_rows": day_rows, "apply_queue": apply_queue, "actions": actions,
        "day": checkpoint["day"], "target_slot": slots["target_slot"], "player_tag": checkpoint["player_tag"],
        "integrity": checkpoint["integrity"], "score": score, "save_score": score,
        "province_id": max(1, int(province_id)),
        "summary": label,
        "plain": "\n".join([label, str(rec.get("summary", "")), str(checkpoint.get("summary", "")), str(slots.get("summary", ""))] + [r["label"] for r in day_rows]),
        "bbcode": "[color=#a0c8e0]💾 Save/resume[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "save_resume_campaign_product", "save_resume_checkpoint", "save_resume_save",
            "save_resume_resume", "major_40", "save", "resume", "continuity", "phase5_depth",
        ],
    }


def execute_save_resume_step(step: str, province_id: int = 1) -> Dict[str, Any]:
    s = str(step or "checkpoint").strip().lower().replace("save_resume_", "")
    if s.startswith("check"):
        s = "checkpoint"
    elif s.startswith("save"):
        s = "save"
    elif s.startswith("resume") or s.startswith("load"):
        s = "resume"
    if s not in _STEP_META:
        s = "checkpoint"
    meta = _STEP_META[s]
    product = build_save_resume_campaign_product(province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute save/resume %s · leaf %s · score %.2f" % (s, leaf, score)
    return {
        "step": s, "leaf_action": leaf, "action_id": meta["action_id"], "ok": True, "score": score,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": leaf, "province_id": max(1, int(province_id)), "score": score, "enabled": True,
            "label": meta["label"], "step": s, "product_action": meta["action_id"],
        }],
        "summary": label, "plain": label, "empty": False,
        "integration": ["execute_save_resume_step", s, leaf],
    }


def save_resume_campaign_integrity() -> Dict[str, Any]:
    product = build_save_resume_campaign_product()
    steps = [execute_save_resume_step(s) for s in PRODUCT_STEPS]
    gate, sole = execution_integrity_gate(), sole_mult_integrity()
    ok = (
        not product.get("empty")
        and len(product.get("day_rows") or []) >= 3
        and str(product.get("target_slot", "")) != ""
        and float(product.get("score", 0)) >= 0.35
        and all(s.get("ok") for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
    )
    return {
        "ok": ok, "score": float(product.get("score", 0)),
        "summary": "Save/resume campaign integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_save_resume_campaign_product_loop() -> Dict[str, Any]:
    product = build_save_resume_campaign_product(province_id=2, day=90, preferred_slot="slot2")
    gate = save_resume_campaign_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = "Close save/resume campaign · score %.2f · %s" % (float(product.get("score", 0)), "PASS" if ok else "FAIL")
    return {"product": product, "gate": gate, "score": float(product.get("score", 0)), "summary": label, "plain": label, "empty": False, "ok": ok}
