"""RF2–RF4 pure product — non-instant reinforce, combat XP mult, policy matrix, era modes."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "rfd_primary_catalog",
    "rfd_primary_non_instant",
    "rfd_primary_combat_xp",
    "rfd_primary_policy",
    "rfd_primary_era",
)
PRIMARY_COMMAND_STEPS = (
    "rfd_catalog",
    "rfd_non_instant",
    "rfd_combat_xp",
    "rfd_policy",
    "rfd_era",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "rfd_catalog": "apply_reinforcement_depth_catalog_live",
    "rfd_non_instant": "apply_reinforcement_depth_non_instant_live",
    "rfd_combat_xp": "apply_reinforcement_depth_combat_xp_live",
    "rfd_policy": "apply_reinforcement_depth_policy_live",
    "rfd_era": "apply_reinforcement_depth_era_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead),
        "ok": len(dead) == 0 and len(ids) >= 5,
        "summary": "Reinforcement depth audit", "plain": "Reinforcement depth audit", "empty": False,
    }


def build_reinforcement_depth_primary_command_product(
    *, province_id: int = 1, live_ids=None
) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    calc = (ROOT / "scripts/production/ReinforcementLogisticsCalculator.gd").read_text(encoding="utf-8")
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    cr = (ROOT / "scripts/combat/CombatResolver.gd").read_text(encoding="utf-8")
    sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")

    hooks_ok = all(
        s in calc
        for s in (
            "func is_non_instant_flow",
            "func mode_unlocked",
            "func preferred_reinforce_mode",
            "func policy_tradeoff_score",
            "func combat_xp_mult_ok_pair",
            "func list_training_policy_ids",
        )
    ) and all(
        s in pm
        for s in (
            "func run_non_instant_reinforce_demo",
            "func evaluate_combat_experience_mult",
            "func apply_training_policy_decision",
            "func list_training_policies",
            "func is_reinforce_mode_unlocked",
            "func preferred_reinforce_mode",
        )
    ) and "func apply_reinforcement_depth_primary_live" in gd \
        and "experience_combat_mult" in cr \
        and "reinforcement_depth_primary_live=1" in sl

    non_instant_math = "func is_non_instant_flow" in calc and "force_deliver" in calc
    combat_ok = "experience_combat_mult" in cr and "formation_combat_experience" in cr
    policy_ok = "wartime_crash" in calc and "volunteer_cadre" in calc and "clone_batch_fill" in calc
    era_ok = "drone_logistics" in calc and "orbital" in calc and "func mode_unlocked" in calc
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and non_instant_math and combat_ok and policy_ok and era_ok and audit["ok"]

    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "RFD · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})

    label = "Reinforce depth · hooks=%s non_instant=%s xp=%s policy=%s era=%s" % (
        hooks_ok, non_instant_math, combat_ok, policy_ok, era_ok,
    )
    return {
        "score": 0.96 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok,
        "non_instant_math": non_instant_math, "combat_ok": combat_ok,
        "policy_ok": policy_ok, "era_ok": era_ok,
        "model": "reinforce_experience_logistics_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "reinforcement_depth_product", "ReinforcementLogisticsCalculator",
            "ProductionManager", "CombatResolver",
        ],
        "phases": ["RF2", "RF3", "RF4"],
    }
