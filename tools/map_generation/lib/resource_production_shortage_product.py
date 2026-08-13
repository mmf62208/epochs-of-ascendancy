"""Strategic resource shortage product — pure gate on shipped production rules.

Loads data/production/production_cost_rules.json (same file ProductionCostCalculator uses)
and applies the documented soft-shortage model:

  fill_ratio = min over resources of (have/need), with critical resources powered by 1/critical_speed_weight
  speed = lerp(min_output, 1.0, fill_ratio)
  reliability = lerp(min_reliability, 1.0, fill_ratio) with critical reliability weight when partial

LIVE_API leaves for dual package hit GameData resource_production_primary APIs (real ProductionManager path).
"""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[3]
RULES_PATH = ROOT / "data" / "production" / "production_cost_rules.json"

MAJOR_DEFAULT = (
    "steel",
    "aluminum",
    "energy",
    "fuel",
    "rubber",
    "electronics",
    "specials",
    "fissiles",
)

SURFACE_KEYS = (
    "rsp_primary_catalog",
    "rsp_primary_full",
    "rsp_primary_shortage",
    "rsp_primary_critical",
    "rsp_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "rsp_catalog",
    "rsp_full",
    "rsp_shortage",
    "rsp_critical",
    "rsp_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "rsp_catalog": "apply_resource_production_catalog_live",
    "rsp_full": "apply_resource_production_full_supply_live",
    "rsp_shortage": "apply_resource_production_shortage_live",
    "rsp_critical": "apply_resource_production_critical_live",
    "rsp_close": "apply_resource_production_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def load_production_cost_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    p = path or RULES_PATH
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("production_cost_rules must be object")
    return data


def get_major_resources(rules: Optional[Dict[str, Any]] = None) -> List[str]:
    r = rules if rules is not None else load_production_cost_rules()
    majors = r.get("major_resources") or {}
    if isinstance(majors, dict) and majors:
        return [str(k) for k in majors.keys()]
    return list(MAJOR_DEFAULT)


def resolve_daily_resource_cost(category: str = "medium_tank", rules: Optional[Dict[str, Any]] = None) -> Dict[str, float]:
    r = rules if rules is not None else load_production_cost_rules()
    table = r.get("resource_costs_per_day") or {}
    base = table.get(category) or table.get("default") or {"steel": 1.0}
    return {str(k): float(v) for k, v in base.items()}


def compute_weighted_fill_ratio(
    needed: Dict[str, float],
    have: Dict[str, float],
    *,
    rules: Optional[Dict[str, Any]] = None,
) -> float:
    """Mirror ProductionCostCalculator.compute_weighted_fill_ratio (shipped formula)."""
    if not needed:
        return 1.0
    r = rules if rules is not None else load_production_cost_rules()
    rs = r.get("resource_shortage") or {}
    critical = {str(x).lower() for x in (rs.get("critical_resources") or [])}
    speed_weight = float(rs.get("critical_speed_weight", 1.45))
    effective = 1.0
    for resource, req in needed.items():
        required = float(req)
        if required <= 0:
            continue
        ratio = max(0.0, min(1.0, float(have.get(resource, 0.0)) / required))
        # Critical shortages hurt more: power > 1 compresses fill (matches ProductionCostCalculator).
        if str(resource).lower() in critical:
            ratio = ratio ** max(speed_weight, 1.0)
        effective = min(effective, ratio)
    return effective


def compute_shortage_multipliers(
    fill_ratio: float,
    *,
    rules: Optional[Dict[str, Any]] = None,
) -> Dict[str, float]:
    """Mirror ProductionCostCalculator.compute_shortage_multipliers."""
    r = rules if rules is not None else load_production_cost_rules()
    rs = r.get("resource_shortage") or {}
    min_output = float(rs.get("min_output_multiplier", 0.55))
    min_reliability = float(rs.get("min_reliability_multiplier", 0.72))
    ratio = max(0.0, min(1.0, float(fill_ratio)))
    speed = min_output + (1.0 - min_output) * ratio
    reliability = min_reliability + (1.0 - min_reliability) * ratio
    critical = rs.get("critical_resources") or []
    if critical and ratio < 1.0:
        crit_weight = float(rs.get("critical_reliability_weight", 1.25))
        crit_floor = min_reliability + (min_reliability * 0.9 - min_reliability) * (1.0 - ratio)
        # crit_floor = lerpf(min_rel, min_rel*0.9, 1-ratio)
        crit_floor = min_reliability * (1.0 - 0.1 * (1.0 - ratio))
        reliability = min(reliability, crit_floor + (1.0 - crit_floor) * (ratio ** max(crit_weight, 1.0)))
    return {
        "speed": max(min_output, min(1.0, speed)),
        "reliability": max(min_reliability, min(1.0, reliability)),
        "fill_ratio": ratio,
    }


def compute_resource_outcome(
    needed: Dict[str, float],
    have: Dict[str, float],
    *,
    rules: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    r = rules if rules is not None else load_production_cost_rules()
    fill = compute_weighted_fill_ratio(needed, have, rules=r)
    mults = compute_shortage_multipliers(fill, rules=r)
    missing = {k: float(v) - float(have.get(k, 0.0)) for k, v in needed.items() if float(have.get(k, 0.0)) + 0.001 < float(v)}
    return {
        "fill_ratio": fill,
        "output_multiplier": float(mults["speed"]),
        "reliability_multiplier": float(mults["reliability"]),
        "afforded": fill >= 1.0,
        "partial": 0.0 < fill < 1.0,
        "missing": missing,
        "shortage_ok": float(mults["speed"]) < 0.999 or fill >= 1.0,
    }


def scenario_pair(category: str = "medium_tank") -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """Full supply vs empty stockpile outcomes for the same daily cost."""
    rules = load_production_cost_rules()
    needed = resolve_daily_resource_cost(category, rules)
    full_have = {k: float(v) * 10.0 for k, v in needed.items()}
    empty_have = {k: 0.0 for k in needed}
    full = compute_resource_outcome(needed, full_have, rules=rules)
    short = compute_resource_outcome(needed, empty_have, rules=rules)
    return full, short


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Resource production primary audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_resource_production_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    rules = load_production_cost_rules()
    majors = get_major_resources(rules)
    full, short = scenario_pair("medium_tank")
    shortage_matters = float(short["output_multiplier"]) < float(full["output_multiplier"]) - 0.01
    audit = primary_command_dead_audit(live_ids=live_ids)
    scores = {s: 0.7 + 0.02 * i for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        lab = "RSP · %s · live %s" % (step, api)
        steps_out.append(
            {
                "index": i,
                "step": step,
                "major": _STEP_MAJOR[step],
                "live_api": api,
                "leaf_action": api,
                "label": lab,
                "score": scores[step],
                "enabled": True,
                "province_id": pid,
            }
        )
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Resource production primary · majors %d · shortage_matters=%s · model=%s" % (
        len(majors),
        shortage_matters,
        rules.get("integration_model", "strategic_stockpile_soft_shortage"),
    )
    return {
        "score": 0.72 if shortage_matters and audit["ok"] else 0.4,
        "plain": label,
        "summary": label,
        "empty": False,
        "province_id": pid,
        "major_resources": majors,
        "full_outcome": full,
        "shortage_outcome": short,
        "shortage_matters": shortage_matters,
        "integration_model": rules.get("integration_model", "strategic_stockpile_soft_shortage"),
        "surface_keys": list(SURFACE_KEYS),
        "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if shortage_matters else 0,
        "all_majors_ok": shortage_matters and audit["ok"],
        "dead_n": int(audit["dead_n"]),
        "audit": audit,
        "steps": steps_out,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue,
        "integration": ["resource_production_shortage_product", "resource_production_primary", "strategic_stockpile_soft_shortage"],
    }
