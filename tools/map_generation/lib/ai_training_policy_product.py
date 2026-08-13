"""RF6 pure product — AI training policy doctrine (cadre vs crash vs clone)."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "atp_primary_catalog",
    "atp_primary_peace",
    "atp_primary_war",
    "atp_primary_crisis",
    "atp_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "atp_catalog",
    "atp_peace",
    "atp_war",
    "atp_crisis",
    "atp_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "atp_catalog": "apply_ai_training_policy_catalog_live",
    "atp_peace": "apply_ai_training_policy_peace_live",
    "atp_war": "apply_ai_training_policy_war_live",
    "atp_crisis": "apply_ai_training_policy_crisis_live",
    "atp_close": "apply_ai_training_policy_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def ai_pick_pure(at_war: bool, strain: float, elite: bool = False, year: int = 1939, industry: float = 0.0) -> str:
    if elite and not at_war:
        return "volunteer_cadre"
    if at_war and strain >= 0.75:
        if year >= 2040 and industry >= 0.6:
            return "clone_batch_fill"
        return "wartime_crash"
    if at_war and strain >= 0.4:
        return "short_conscript" if year < 1970 else "selective_service"
    if at_war and elite:
        return "all_volunteer_force" if year >= 1973 else "volunteer_cadre"
    if year >= 2000 and not at_war:
        return "all_volunteer_force"
    if year >= 1950 and not at_war:
        return "national_service"
    return "two_year_service"


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead),
        "ok": len(dead) == 0 and len(ids) >= 5,
        "summary": "AI training policy audit", "plain": "AI training policy audit", "empty": False,
    }


def build_ai_training_policy_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
    doc = (ROOT / "docs/REINFORCEMENT_EXPERIENCE_LOGISTICS_DESIGN_FREEZE.md").read_text(encoding="utf-8")

    hooks_ok = "func ai_select_training_policy" in pm \
        and "func apply_training_policy_decision" in pm \
        and "func apply_ai_training_policy_primary_live" in gd \
        and "ai_training_policy_primary_live=1" in sl \
        and "RF6" in doc

    peace = ai_pick_pure(False, 0.1, False, 1960) == "national_service"
    war = ai_pick_pure(True, 0.85, False, 1942) == "wartime_crash"
    crisis = ai_pick_pure(True, 0.9, False, 2050, 0.8) == "clone_batch_fill"
    elite = ai_pick_pure(False, 0.1, True, 1936) == "volunteer_cadre"
    logic_ok = peace and war and crisis and elite
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and logic_ok and audit["ok"]

    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "ATP · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "AI training policy · hooks=%s logic=%s" % (hooks_ok, logic_ok)
    return {
        "score": 0.95 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "logic_ok": logic_ok,
        "model": "reinforce_experience_logistics_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["ai_training_policy_product", "ProductionManager"],
        "phase": "RF6",
    }
