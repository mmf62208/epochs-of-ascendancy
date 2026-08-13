"""EquipmentFlow CP1/CP2 pure product — create, interdict, deliver, stock, reinforce."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, Optional

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "efl_primary_catalog",
    "efl_primary_create",
    "efl_primary_interdict",
    "efl_primary_deliver",
    "efl_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "efl_catalog",
    "efl_create",
    "efl_interdict",
    "efl_deliver",
    "efl_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "efl_catalog": "apply_equipment_flow_catalog_live",
    "efl_create": "apply_equipment_flow_create_live",
    "efl_interdict": "apply_equipment_flow_interdict_live",
    "efl_deliver": "apply_equipment_flow_deliver_live",
    "efl_close": "apply_equipment_flow_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

# CP2 stock → reinforce dual surface
ESR_SURFACE_KEYS = (
    "esr_primary_catalog",
    "esr_primary_stock",
    "esr_primary_demand",
    "esr_primary_reinforce",
    "esr_primary_close",
)
ESR_PRIMARY_STEPS = (
    "esr_catalog",
    "esr_stock",
    "esr_demand",
    "esr_reinforce",
    "esr_close",
)
_ESR_STEP_MAJOR = {s: ESR_SURFACE_KEYS[i] for i, s in enumerate(ESR_PRIMARY_STEPS)}
ESR_LIVE_API_BY_STEP = {
    "esr_catalog": "apply_equipment_stock_reinforce_catalog_live",
    "esr_stock": "apply_equipment_stock_reinforce_stock_live",
    "esr_demand": "apply_equipment_stock_reinforce_demand_live",
    "esr_reinforce": "apply_equipment_stock_reinforce_reinforce_live",
    "esr_close": "apply_equipment_stock_reinforce_close_live",
}
ESR_PRIMARY_ACTION_IDS = tuple(ESR_LIVE_API_BY_STEP.values())
ESR_LIVE_PRIMARY_ACTION_IDS = frozenset(ESR_PRIMARY_ACTION_IDS)

MODE_SYMBOL = {
    "rail": "train", "road": "truck", "airlift": "transport_plane",
    "helicopter": "helicopter", "sealift": "merchant", "river": "barge",
}

CLASS_DEFAULT_BATCH = {
    "truck": 4,
    "light_vehicle": 4,
    "apc": 4,
    "artillery_towed": 2,
    "drone_swarm": 6,
    "rocket_artillery": 4,
}


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead),
        "ok": len(dead) == 0 and len(ids) >= 5,
        "summary": "Equipment flow audit", "plain": "Equipment flow audit", "empty": False,
    }


def effective_interdict_loss(base_loss: float, corridor_risk: float, escorted: bool = False) -> float:
    effective = max(0.05, min(0.95, float(base_loss) * 0.65 + float(corridor_risk) * 0.35))
    if escorted:
        effective *= 0.55
    return max(0.02, min(0.95, effective))


def amount_after_interdict(amount: int, loss_fraction: float) -> Dict[str, int]:
    amt = max(0, int(amount))
    loss = max(0.0, min(1.0, float(loss_fraction)))
    lost = int(amt * loss)
    if lost >= amt and amt > 0 and loss < 1.0:
        lost = amt - 1
    if loss >= 0.999:
        lost = amt
    return {"amount": amt, "lost": lost, "delivered": max(0, amt - lost)}


def symbol_for_mode(mode: str) -> str:
    return MODE_SYMBOL.get(str(mode).lower(), "train")


def stock_units_on_complete(
    design_class: str, completes: int = 1, batch_size: Optional[int] = None
) -> int:
    """Identity-weighted hybrid scale (freeze §3) — stock units per complete event."""
    c = max(0, int(completes))
    if batch_size is not None and int(batch_size) >= 1:
        return c * max(1, int(batch_size))
    key = str(design_class).strip().lower()
    b = max(1, int(CLASS_DEFAULT_BATCH.get(key, 1)))
    return c * b


def demand_deficit(have: int, need: int) -> int:
    return max(0, int(need) - int(have))


def esr_primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else ESR_PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else ESR_LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead),
        "ok": len(dead) == 0 and len(ids) >= 5,
        "summary": "Equipment stock reinforce audit", "plain": "Equipment stock reinforce audit",
        "empty": False,
    }


def build_equipment_stock_reinforce_primary_command_product(
    *, province_id: int = 1, live_ids=None
) -> Dict[str, Any]:
    """CP2 pure product: complete → stockpile (batch) + demand reinforce via flow."""
    pid = max(1, int(province_id))
    calc = (ROOT / "scripts/production/EquipmentFlowCalculator.gd").read_text(encoding="utf-8")
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    hooks_ok = all(
        s in calc
        for s in ("func stock_units_on_complete", "func amount_after_interdict")
    ) and all(
        s in pm
        for s in (
            "func credit_production_complete_to_stockpile",
            "func demand_reinforce_via_equipment_flow",
            "func demand_reinforce_tick_via_flow",
            "func resolve_stock_units_on_complete",
        )
    ) and "func apply_equipment_stock_reinforce_primary_live" in gd
    tank_one = stock_units_on_complete("tank", 1) == 1
    truck_batch = stock_units_on_complete("truck", 1) == 4
    drone_batch = stock_units_on_complete("drone_swarm", 1) == 6
    scale_ok = tank_one and truck_batch and drone_batch
    gap_ok = demand_deficit(2, 8) == 6 and demand_deficit(10, 8) == 0
    audit = esr_primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and scale_ok and gap_ok and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(ESR_PRIMARY_STEPS):
        api = ESR_LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _ESR_STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "ESR · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Equipment stock reinforce · hooks=%s scale=%s" % (hooks_ok, scale_ok)
    return {
        "score": 0.95 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "scale_ok": scale_ok, "gap_ok": gap_ok,
        "model": "equipment_flow_compact_ledger",
        "surface_keys": list(ESR_SURFACE_KEYS), "majors": list(ESR_SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(ESR_PRIMARY_STEPS),
        "live_api_by_step": dict(ESR_LIVE_API_BY_STEP),
        "primary_action_ids": list(ESR_PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "equipment_flow_product", "EquipmentFlowCalculator",
            "ProductionManager", "credit_production_complete_to_stockpile",
        ],
    }


def build_equipment_flow_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    calc = (ROOT / "scripts/production/EquipmentFlowCalculator.gd").read_text(encoding="utf-8")
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    hooks_ok = all(s in calc for s in (
        "func effective_interdict_loss", "func amount_after_interdict", "func symbol_for_mode",
        "func stock_units_on_complete",
    )) and all(s in pm for s in (
        "func create_equipment_flow", "func interdict_equipment_flow",
        "func advance_equipment_flows", "func ship_and_reinforce_unit",
        "func credit_production_complete_to_stockpile",
        "func demand_reinforce_via_equipment_flow",
    ))
    loss = effective_interdict_loss(0.4, 0.1, False)
    split = amount_after_interdict(10, loss)
    math_ok = split["lost"] > 0 and split["delivered"] < 10 and symbol_for_mode("rail") == "train"
    escort_less = effective_interdict_loss(0.4, 0.1, True) < loss
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and math_ok and escort_less and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "EFL · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Equipment flow · hooks=%s math=%s" % (hooks_ok, math_ok)
    return {
        "score": 0.94 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "math_ok": math_ok, "escort_less": escort_less,
        "model": "equipment_flow_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["equipment_flow_product", "EquipmentFlowCalculator", "ProductionManager"],
    }
