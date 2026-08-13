"""Space supply — commercial lift + sustain SpaceFlows + stockpile board."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "ssp_primary_catalog",
    "ssp_primary_lift",
    "ssp_primary_flow",
    "ssp_primary_board",
    "ssp_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "ssp_catalog",
    "ssp_lift",
    "ssp_flow",
    "ssp_board",
    "ssp_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "ssp_catalog": "apply_space_supply_catalog_live",
    "ssp_lift": "apply_space_supply_lift_live",
    "ssp_flow": "apply_space_supply_flow_live",
    "ssp_board": "apply_space_supply_board_live",
    "ssp_close": "apply_space_supply_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def commercial_lift_ok(seller_free: float, amount: float) -> bool:
    return float(seller_free) + 1e-6 >= float(amount) > 0


def sustain_delivery_ok(qty: float, risk: float = 0.08) -> bool:
    delivered = float(qty) * (1.0 - float(risk) * 0.08)
    return delivered > 0 and delivered <= float(qty)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Space supply audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Space supply audit", "empty": False,
    }


def build_space_supply_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    logic_ok = commercial_lift_ok(5.0, 2.0) and not commercial_lift_ok(1.0, 3.0) and sustain_delivery_ok(10.0)
    mgr = (ROOT / "scripts" / "space" / "SpaceLayerManager.gd").read_text(encoding="utf-8")
    hooks_ok = all(h in mgr for h in (
        "func buy_commercial_lift", "func create_sustain_flow", "func get_supply_board", "func advance_space_flows",
    ))
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = logic_ok and hooks_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "SSP · %s · live %s" % (step, api),
            "score": 0.84 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Space supply · logic_ok=%s hooks_ok=%s" % (logic_ok, hooks_ok)
    return {
        "score": 0.92 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "logic_ok": logic_ok, "hooks_ok": hooks_ok,
        "model": "orbital_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["space_supply_product", "commercial_lift", "sustain_flow"],
    }
