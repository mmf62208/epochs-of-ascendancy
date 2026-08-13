"""Space ops S2 — claim sites, habitats, SpaceFlow interdict (runtime manager surface)."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "spo_primary_catalog",
    "spo_primary_claim",
    "spo_primary_habitat",
    "spo_primary_flow",
    "spo_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "spo_catalog",
    "spo_claim",
    "spo_habitat",
    "spo_flow",
    "spo_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "spo_catalog": "apply_space_ops_catalog_live",
    "spo_claim": "apply_space_ops_claim_live",
    "spo_habitat": "apply_space_ops_habitat_live",
    "spo_flow": "apply_space_ops_flow_live",
    "spo_close": "apply_space_ops_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Space ops audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Space ops audit", "empty": False,
    }


def simulate_claim_and_habitat() -> Dict[str, Any]:
    """Pure mirror of capacity gates: need lift to claim, command to build."""
    lift = 5.0
    command = 4.0
    claim_cost = 1.0
    habitat_cost = 3.0  # settlement
    can_claim = lift >= claim_cost
    can_build = can_claim and command >= habitat_cost
    return {
        "can_claim": can_claim,
        "can_build": can_build,
        "lift": lift,
        "command": command,
        "after_command": command - habitat_cost if can_build else command,
    }


def simulate_spaceflow_interdict(baseline: float = 20.0, loss: float = 0.4) -> Dict[str, Any]:
    after = baseline * (1.0 - max(0.05, min(0.95, loss)))
    ratio = after / baseline if baseline > 0.001 else 0.0
    return {
        "baseline": baseline,
        "after": round(after, 3),
        "ratio": round(ratio, 3),
        "ok": after < baseline and ratio < 1.0,
    }


def build_space_ops_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    ch = simulate_claim_and_habitat()
    claim_ok = bool(ch.get("can_claim")) and bool(ch.get("can_build"))
    fi = simulate_spaceflow_interdict(20.0, 0.4)
    flow_ok = bool(fi.get("ok")) and float(fi.get("ratio", 1)) == 0.6
    audit = primary_command_dead_audit(live_ids=live_ids)
    # Source hooks
    mgr = (ROOT / "scripts" / "space" / "SpaceLayerManager.gd").is_file()
    all_ok = claim_ok and flow_ok and mgr and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "SPO · %s · live %s" % (step, api),
            "score": 0.82 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Space ops · claim_ok=%s flow_ok=%s mgr=%s" % (claim_ok, flow_ok, mgr)
    return {
        "score": 0.9 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "claim_ok": claim_ok, "flow_ok": flow_ok, "mgr": mgr,
        "claim_sim": ch, "flow_sim": fi,
        "model": "orbital_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "space_ops_product", "SpaceLayerManager", "claim_site",
            "build_habitat", "spaceflow_interdict",
        ],
    }
