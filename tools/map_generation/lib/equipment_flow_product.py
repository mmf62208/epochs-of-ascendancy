"""EquipmentFlow CP1/CP2 pure product — create, interdict, deliver, stock, reinforce."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, Mapping, Optional

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
    toe_loop = build_toe_industry_loop_product()
    toe_ok = bool(toe_loop.get("ok"))
    all_ok = hooks_ok and scale_ok and gap_ok and audit["ok"] and toe_ok
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
        "toe_ok": toe_ok, "toe_fail": list(toe_loop.get("fail") or []),
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


# --- Designer TOE ↔ factory output ↔ stockpile ↔ reinforce (same catalog) ---

TOE_RESOURCE_COST = {
    "infantry_equipment": {"steel": 1.0, "coal": 1.0},
    "trucks": {"steel": 2.0, "rubber": 1.0, "oil": 1.0},
    "tanks": {"steel": 4.0, "oil": 1.0, "chromium": 1.0},
    "artillery": {"steel": 3.0, "tungsten": 1.0},
    "motorcycles": {"steel": 1.0, "rubber": 1.0},
    "halftracks": {"steel": 3.0, "rubber": 1.0, "oil": 1.0},
    "recon_equipment": {"steel": 1.0},
    "support_equipment": {"steel": 1.0},
    "anti_tank": {"steel": 2.0, "tungsten": 1.0},
    "anti_air": {"steel": 2.0, "aluminum": 1.0},
}

_TOE_ALIASES = {
    "truck": "trucks",
    "motorized": "trucks",
    "tank": "tanks",
    "armor": "tanks",
    "gun": "artillery",
    "guns": "artillery",
    "rifle": "infantry_equipment",
    "rifles": "infantry_equipment",
    "infantry": "infantry_equipment",
    "motorcycle": "motorcycles",
    "halftrack": "halftracks",
    "half-track": "halftracks",
    "recon": "recon_equipment",
    "engineer": "support_equipment",
    "at": "anti_tank",
    "aa": "anti_air",
}


def resolve_toe_equipment_id(raw: str) -> str:
    key = str(raw or "").strip().lower()
    if key in TOE_RESOURCE_COST:
        return key
    if key in _TOE_ALIASES:
        return _TOE_ALIASES[key]
    return key


def factory_output_keys(toe: Mapping) -> list:
    if not isinstance(toe, Mapping):
        return []
    out = []
    for k, raw in toe.items():
        try:
            n = int(raw)
        except (TypeError, ValueError):
            continue
        if n <= 0:
            continue
        out.append(resolve_toe_equipment_id(str(k)))
    return sorted(set(out))


def resource_draw_for_output(equipment_id: str, count: int = 1) -> Dict[str, float]:
    key = resolve_toe_equipment_id(equipment_id)
    n = max(0, int(count))
    base = TOE_RESOURCE_COST.get(key, {"steel": 1.0})
    return {str(r): float(v) * float(n) for r, v in base.items()}


def can_produce(resources: Mapping, equipment_id: str, count: int = 1) -> bool:
    draw = resource_draw_for_output(equipment_id, count)
    if not isinstance(resources, Mapping):
        return False
    for r, need in draw.items():
        try:
            have = float(resources.get(r, 0.0) or 0.0)
        except (TypeError, ValueError):
            have = 0.0
        if have + 1e-9 < float(need):
            return False
    return True


def produce_to_stockpile(
    resources: Mapping,
    equip_stock: Mapping,
    equipment_id: str,
    count: int = 1,
) -> Dict[str, Any]:
    """Consume strategic resources; credit TOE-key stock. Empty resources → no credit."""
    key = resolve_toe_equipment_id(equipment_id)
    n = max(0, int(count))
    res = {str(k): float(v) for k, v in (resources or {}).items()}
    stock = {str(k): int(v) for k, v in (equip_stock or {}).items()}
    before = int(stock.get(key, 0))
    if n <= 0:
        return {"ok": False, "error": "bad_count", "equipment_id": key, "added": 0, "stock_after": before, "resources": res, "stock": stock}
    if not can_produce(res, key, n):
        return {
            "ok": False,
            "error": "no_resources",
            "equipment_id": key,
            "added": 0,
            "stock_after": before,
            "resources": res,
            "stock": stock,
        }
    draw = resource_draw_for_output(key, n)
    for r, need in draw.items():
        res[r] = float(res.get(r, 0.0)) - float(need)
    stock[key] = before + n
    return {
        "ok": True,
        "equipment_id": key,
        "added": n,
        "stock_before": before,
        "stock_after": before + n,
        "resources_paid": draw,
        "resources": res,
        "stock": stock,
    }


def toe_fill_ratio(unit_stock: Mapping, toe: Mapping) -> float:
    if not isinstance(toe, Mapping) or not toe:
        return 1.0
    need = 0
    have = 0
    for k, raw in toe.items():
        try:
            n = int(raw)
        except (TypeError, ValueError):
            continue
        if n <= 0:
            continue
        need += n
        try:
            have += min(n, max(0, int((unit_stock or {}).get(k, 0))))
        except (TypeError, ValueError):
            pass
    if need <= 0:
        return 1.0
    return round(float(have) / float(need), 4)


def reinforce_from_stockpile(
    unit_stock: Mapping,
    national_equip: Mapping,
    toe: Mapping,
    share: float = 1.0,
) -> Dict[str, Any]:
    """Pull TOE keys from national/country stock into the unit. Empty stock → no fill."""
    unit = {str(k): int(v) for k, v in (unit_stock or {}).items()}
    nat = {str(k): int(v) for k, v in (national_equip or {}).items()}
    req = toe if isinstance(toe, Mapping) else {}
    try:
        sh = max(0.0, min(1.0, float(share)))
    except (TypeError, ValueError):
        sh = 1.0
    fill_before = toe_fill_ratio(unit, req)
    moved: Dict[str, int] = {}
    for k, raw in req.items():
        try:
            need = int(raw)
        except (TypeError, ValueError):
            continue
        if need <= 0:
            continue
        key = resolve_toe_equipment_id(str(k))
        have = int(unit.get(key, 0))
        gap = need - have
        if gap <= 0:
            continue
        want = max(1, int((float(gap) * 0.25 * sh) + 0.999))
        want = min(want, gap)
        pool = int(nat.get(key, 0))
        got = min(want, pool)
        if got <= 0:
            continue
        nat[key] = pool - got
        if nat[key] <= 0:
            nat.pop(key, None)
        unit[key] = have + got
        moved[key] = got
    fill_after = toe_fill_ratio(unit, req)
    return {
        "ok": True,
        "moved": moved,
        "fill_before": fill_before,
        "fill_after": fill_after,
        "unit_stock": unit,
        "national_stock": nat,
        "invented": False,
    }


def build_toe_industry_loop_product() -> Dict[str, Any]:
    """Resources → TOE-key stockpile → share-limited reinforce. Fail-closed if stock empty."""
    from unit_composition_combat_product import compose

    passes: list = []
    fails: list = []
    designed = compose(
        mobility="truck",
        armor="medium_tank",
        support="artillery",
        infantry_bns=3,
        tank_bns=1,
    )
    toe = designed.get("equipment") or {}
    keys = factory_output_keys(toe)
    need = {"infantry_equipment", "trucks", "tanks", "artillery"}
    if need.issubset(set(keys)):
        passes.append("factory_keys_match_toe")
    else:
        fails.append("factory_keys_match_toe")
    res = {"steel": 200.0, "coal": 50.0, "rubber": 40.0, "oil": 40.0, "chromium": 20.0, "tungsten": 20.0}
    stock: Dict[str, int] = {}
    for k in need:
        prod = produce_to_stockpile(res, stock, k, 8)
        res = prod.get("resources") or res
        stock = prod.get("stock") or stock
        if not bool(prod.get("ok")):
            fails.append("produce_%s" % k)
        else:
            passes.append("produce_%s" % k)
    if int(stock.get("trucks", 0)) >= 8 and int(stock.get("tanks", 0)) >= 8:
        passes.append("stockpile_credits_toe_keys")
    else:
        fails.append("stockpile_credits_toe_keys")
    empty = reinforce_from_stockpile({}, {}, toe, 1.0)
    if float(empty.get("fill_after", 1)) <= float(empty.get("fill_before", 0)) + 1e-9 and not empty.get("moved"):
        passes.append("empty_stock_no_fill")
    else:
        fails.append("empty_stock_no_fill")
    short = {k: max(0, int(v) // 5) for k, v in toe.items()}
    filled = reinforce_from_stockpile(short, stock, toe, 1.0)
    if float(filled.get("fill_after", 0)) > float(filled.get("fill_before", 0)) and filled.get("moved"):
        passes.append("stock_raises_fill")
    else:
        fails.append("stock_raises_fill")
    pm = (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8") if (ROOT / "scripts" / "autoload" / "ProductionManager.gd").is_file() else ""
    wiring = {
        "produce_api": "func produce_toe_equipment" in pm,
        "reinforce_api": "func reinforce_unit_toe_from_stockpile" in pm,
        "credit_api": "func credit_production_complete_to_stockpile" in pm,
        "save_stock": "country_equipment_stockpiles" in pm and "unit_equipment_stock" in pm,
        "required_uses_toe": "equipment_toe" in pm and "func get_formation_required_equipment" in pm,
    }
    for name, ok in wiring.items():
        (passes if ok else fails).append(name)
    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "wiring": wiring,
        "toe_keys": keys,
        "summary": "toe_industry_loop · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
    }
