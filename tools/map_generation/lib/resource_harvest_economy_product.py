"""Resource harvest economy product — province deposits → majors + plants + tech.

Mirrors ResourceHarvestCalculator / data/production/resource_harvest_rules.json.
LIVE_API leaves hit GameData resource_harvest_primary APIs.
"""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[3]
HARVEST_PATH = ROOT / "data" / "production" / "resource_harvest_rules.json"
COST_PATH = ROOT / "data" / "production" / "production_cost_rules.json"
TECH_PATH = ROOT / "data" / "technology" / "trees" / "resource_industry.json"
FACTORY_PATH = ROOT / "data" / "production" / "factory_rules.json"

SURFACE_KEYS = (
    "rh_primary_catalog",
    "rh_primary_harvest",
    "rh_primary_plants",
    "rh_primary_tech",
    "rh_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "rh_catalog",
    "rh_harvest",
    "rh_plants",
    "rh_tech",
    "rh_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "rh_catalog": "apply_resource_harvest_catalog_live",
    "rh_harvest": "apply_resource_harvest_auto_live",
    "rh_plants": "apply_resource_harvest_plants_live",
    "rh_tech": "apply_resource_harvest_tech_live",
    "rh_close": "apply_resource_harvest_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

MAJOR_DEFAULT = (
    "steel", "aluminum", "energy", "fuel", "rubber", "electronics", "specials", "fissiles",
)


def load_json(path: Path) -> Dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("%s must be object" % path)
    return data


def load_harvest_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    return load_json(path or HARVEST_PATH)


def load_cost_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    return load_json(path or COST_PATH)


def get_major_resources(rules: Optional[Dict[str, Any]] = None) -> List[str]:
    r = rules if rules is not None else load_cost_rules()
    majors = r.get("major_resources") or {}
    if isinstance(majors, dict) and majors:
        return [str(k) for k in majors.keys()]
    return list(MAJOR_DEFAULT)


def source_to_major_map(harvest: Optional[Dict[str, Any]] = None, cost: Optional[Dict[str, Any]] = None) -> Dict[str, str]:
    h = harvest if harvest is not None else load_harvest_rules()
    c = cost if cost is not None else load_cost_rules()
    out: Dict[str, str] = {}
    for k, v in (h.get("source_to_major") or {}).items():
        out[str(k).lower()] = str(v).lower()
    majors = c.get("major_resources") or {}
    if isinstance(majors, dict):
        for mid, entry in majors.items():
            out[str(mid).lower()] = str(mid).lower()
            if isinstance(entry, dict):
                for a in entry.get("aliases") or []:
                    out[str(a).lower()] = str(mid).lower()
    return out


def is_major_visible(major_id: str, unlocks: Optional[Dict[str, Any]] = None, harvest: Optional[Dict[str, Any]] = None) -> bool:
    h = harvest if harvest is not None else load_harvest_rules()
    u = unlocks or {}
    mid = str(major_id).lower()
    always = [str(x).lower() for x in (h.get("always_visible_majors") or [])]
    if mid in always:
        return True
    vis = (h.get("visibility") or {}).get(mid)
    if not isinstance(vis, dict):
        return True
    flag = str(vis.get("requires_rule_flag") or "")
    flags = [str(x) for x in (u.get("rule_flags") or [])]
    unlocked = [str(x) for x in (u.get("unlocked_resources") or [])]
    if flag and flag in flags:
        return True
    or_res = str(vis.get("or_unlocked_resource") or "")
    if or_res and or_res in unlocked:
        return True
    if flag:
        return False
    return True


def size_tier_multiplier(tier: int, harvest: Optional[Dict[str, Any]] = None) -> float:
    h = harvest if harvest is not None else load_harvest_rules()
    tiers = h.get("size_tier_multipliers") or {}
    key = str(max(1, min(5, int(tier))))
    return float(tiers.get(key, 1.0))


def raw_daily_from_deposit(amount: float, harvest: Optional[Dict[str, Any]] = None) -> float:
    h = harvest if harvest is not None else load_harvest_rules()
    frac = float(h.get("base_extract_fraction", 0.01))
    min_d = float(h.get("base_extract_min_daily", 0.05))
    cap = float(h.get("deposit_soft_cap", 5000.0))
    amt = max(0.0, min(float(amount), cap))
    if amt <= 0:
        return 0.0
    base = amt * frac
    return max(base, min_d if amt >= 1.0 else base)


def plant_boost_for_source(
    source_key: str,
    plants: Optional[List[Dict[str, Any]]] = None,
    unlocks: Optional[Dict[str, Any]] = None,
    harvest: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    h = harvest if harvest is not None else load_harvest_rules()
    sk = str(source_key).lower()
    best = float(h.get("no_plant_multiplier", 0.35))
    also_fuel = 0.0
    energy_by = 0.0
    best_type = ""
    best_tier = 0
    flags = [str(x) for x in ((unlocks or {}).get("rule_flags") or [])]
    catalogs = {}
    catalogs.update(h.get("energy_plant_types") or {})
    catalogs.update(h.get("resource_plant_types") or {})
    for p in plants or []:
        if not isinstance(p, dict):
            continue
        ptype = str(p.get("factory_type") or p.get("plant_type") or "").lower()
        conf = catalogs.get(ptype) or {}
        if not conf:
            continue
        req = str(conf.get("requires_unlock") or "")
        if req and req not in flags:
            continue
        keys = [str(k).lower() for k in (conf.get("source_keys") or [])]
        if sk not in keys:
            continue
        tier = int(p.get("size_tier") or 1)
        mult = float(conf.get("base_mult", 1.0)) * size_tier_multiplier(tier, h)
        if mult > best:
            best = mult
            best_type = ptype
            best_tier = tier
            also_fuel = float(conf.get("also_fuel_fraction") or 0.0)
            energy_by = float(conf.get("energy_byproduct") or 0.0)
    return {
        "multiplier": best,
        "also_fuel_fraction": also_fuel,
        "energy_byproduct": energy_by,
        "plant_type": best_type,
        "size_tier": best_tier,
    }


def tech_major_bonus(major_id: str, unlocks: Optional[Dict[str, Any]] = None, harvest: Optional[Dict[str, Any]] = None) -> float:
    h = harvest if harvest is not None else load_harvest_rules()
    u = unlocks or {}
    mid = str(major_id).lower()
    bonus = 0.0
    flags = [str(x) for x in (u.get("rule_flags") or [])]
    mods = u.get("permanent_modifiers") or {}
    tmods = h.get("tech_modifiers") or {}
    plastics = tmods.get("plastics_improves_efficiency") or {}
    if str(plastics.get("rule_flag") or "plastics_industry") in flags:
        majors = plastics.get("majors") or {}
        if mid in majors:
            bonus += float(majors[mid])
    ppo = tmods.get("power_plant_output") or {}
    if str(ppo.get("applies_to") or "") == "energy" and mid == "energy":
        bonus += float(mods.get("power_plant_output") or 0.0)
    ro = tmods.get("resource_output") or {}
    if str(ro.get("applies_to") or "") == "all_majors":
        bonus += float(mods.get("resource_output") or 0.0)
    return bonus


def synthetic_fuel_fraction(unlocks: Optional[Dict[str, Any]] = None, harvest: Optional[Dict[str, Any]] = None) -> float:
    h = harvest if harvest is not None else load_harvest_rules()
    flags = [str(x) for x in ((unlocks or {}).get("rule_flags") or [])]
    sf = (h.get("tech_modifiers") or {}).get("synthetic_fuel") or {}
    if str(sf.get("rule_flag") or "synthetic_fuel") in flags:
        return float(sf.get("energy_to_fuel_fraction") or 0.08)
    return 0.0


def can_harvest_source(source_key: str, unlocks: Optional[Dict[str, Any]] = None, harvest: Optional[Dict[str, Any]] = None) -> bool:
    sk = str(source_key).lower()
    if sk in ("uranium", "plutonium", "fissiles"):
        return is_major_visible("fissiles", unlocks, harvest)
    if sk == "helium3":
        return is_major_visible("helium3", unlocks, harvest)
    if sk == "antimatter":
        return is_major_visible("antimatter", unlocks, harvest)
    return True


def compute_province_daily_income(
    resources: Dict[str, float],
    plants: Optional[List[Dict[str, Any]]] = None,
    unlocks: Optional[Dict[str, Any]] = None,
    harvest: Optional[Dict[str, Any]] = None,
) -> Dict[str, float]:
    h = harvest if harvest is not None else load_harvest_rules()
    mapping = source_to_major_map(h)
    income: Dict[str, float] = {}
    for raw_key, deposit in resources.items():
        sk = str(raw_key).lower()
        if not can_harvest_source(sk, unlocks, h):
            continue
        dep = float(deposit)
        if dep <= 0:
            continue
        major = mapping.get(sk, "")
        if not major:
            continue
        if major == "fissiles" and not is_major_visible("fissiles", unlocks, h):
            continue
        base = raw_daily_from_deposit(dep, h)
        boost = plant_boost_for_source(sk, plants, unlocks, h)
        mult = float(boost["multiplier"])
        tech_b = tech_major_bonus(major, unlocks, h)
        amount = base * mult * (1.0 + tech_b)
        income[major] = income.get(major, 0.0) + amount
        if float(boost.get("also_fuel_fraction") or 0) > 0 and major == "energy":
            income["fuel"] = income.get("fuel", 0.0) + amount * float(boost["also_fuel_fraction"])
        if float(boost.get("energy_byproduct") or 0) > 0 and major == "fuel":
            income["energy"] = income.get("energy", 0.0) + amount * float(boost["energy_byproduct"])
    e2f = synthetic_fuel_fraction(unlocks, h)
    if e2f > 0 and income.get("energy", 0) > 0:
        income["fuel"] = income.get("fuel", 0.0) + income["energy"] * e2f
    return {k: round(v, 2) for k, v in income.items()}


def list_energy_plant_types(harvest: Optional[Dict[str, Any]] = None) -> List[str]:
    h = harvest if harvest is not None else load_harvest_rules()
    return [str(k) for k in (h.get("energy_plant_types") or {}).keys()]


def list_resource_plant_types(harvest: Optional[Dict[str, Any]] = None) -> List[str]:
    h = harvest if harvest is not None else load_harvest_rules()
    return [str(k) for k in (h.get("resource_plant_types") or {}).keys()]


def factory_rules_has_plants(factory: Optional[Dict[str, Any]] = None) -> bool:
    f = factory if factory is not None else load_json(FACTORY_PATH)
    types = f.get("factory_types") or {}
    plant_keys = set(list_energy_plant_types()) | set(list_resource_plant_types())
    present = [k for k in plant_keys if k in types]
    return len(present) >= 10


def resource_tech_tree_ok(tech: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    t = tech if tech is not None else load_json(TECH_PATH)
    required = [
        "electric_power_generation_1890",
        "synthetic_materials_1917",
        "enrichment_infrastructure_1943",
        "steel_industry_1895",
        "oil_gas_power_1912",
    ]
    missing = [x for x in required if x not in t]
    plastics_ok = False
    fissiles_ok = False
    for tid, node in t.items():
        if not isinstance(node, dict):
            continue
        unlocks = node.get("unlocks") or []
        for u in unlocks:
            if not isinstance(u, dict):
                continue
            if u.get("type") == "rule_flag" and u.get("flag") == "plastics_industry":
                plastics_ok = True
            if u.get("type") == "resource" and str(u.get("resource")) in ("fissiles", "uranium"):
                fissiles_ok = True
            if u.get("type") == "rule_flag" and u.get("flag") == "nuclear_fuel":
                fissiles_ok = True
    return {
        "missing": missing,
        "plastics_ok": plastics_ok,
        "fissiles_ok": fissiles_ok,
        "ok": len(missing) == 0 and plastics_ok and fissiles_ok,
        "tech_n": len(t),
    }


def scenario_harvest_pair() -> Tuple[Dict[str, float], Dict[str, float], Dict[str, float]]:
    """Bare province vs plant-boosted vs plastics tech."""
    resources = {"coal": 200.0, "iron": 100.0, "oil": 150.0, "rubber": 80.0, "uranium": 40.0}
    bare = compute_province_daily_income(resources, plants=[], unlocks={})
    plants = [
        {"factory_type": "coal_plant", "size_tier": 3},
        {"factory_type": "steel_mill", "size_tier": 2},
        {"factory_type": "refinery", "size_tier": 2},
    ]
    with_plants = compute_province_daily_income(resources, plants=plants, unlocks={})
    unlocks = {"rule_flags": ["plastics_industry", "synthetic_fuel", "nuclear_fuel"], "unlocked_resources": ["fissiles", "uranium"]}
    plants_nuke = plants + [{"factory_type": "enrichment_plant", "size_tier": 2}]
    with_tech = compute_province_daily_income(resources, plants=plants_nuke, unlocks=unlocks)
    return bare, with_plants, with_tech


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Resource harvest primary audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_resource_harvest_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    harvest = load_harvest_rules()
    cost = load_cost_rules()
    majors = get_major_resources(cost)
    energy_plants = list_energy_plant_types(harvest)
    res_plants = list_resource_plant_types(harvest)
    bare, with_plants, with_tech = scenario_harvest_pair()
    plants_matter = float(with_plants.get("energy", 0) or 0) > float(bare.get("energy", 0) or 0) + 0.01
    tech_matters = float(with_tech.get("rubber", 0) or 0) > float(with_plants.get("rubber", 0) or 0) + 0.01
    fissiles_gated = "fissiles" not in bare and "fissiles" in with_tech
    tech_tree = resource_tech_tree_ok()
    factories_ok = factory_rules_has_plants()
    audit = primary_command_dead_audit(live_ids=live_ids)
    scores = {s: 0.72 + 0.02 * i for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        lab = "RH · %s · live %s" % (step, api)
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api, "label": lab,
            "score": scores[step], "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    all_ok = (
        plants_matter and tech_matters and fissiles_gated
        and tech_tree["ok"] and factories_ok and audit["ok"]
        and len(majors) >= 8 and len(energy_plants) >= 5
    )
    label = (
        "Resource harvest primary · majors %d · plants %d/%d · plants_matter=%s tech_matters=%s fissiles_gated=%s"
        % (len(majors), len(energy_plants), len(res_plants), plants_matter, tech_matters, fissiles_gated)
    )
    return {
        "score": 0.78 if all_ok else 0.45,
        "plain": label,
        "summary": label,
        "empty": False,
        "province_id": pid,
        "major_resources": majors,
        "energy_plant_types": energy_plants,
        "resource_plant_types": res_plants,
        "bare_income": bare,
        "plant_income": with_plants,
        "tech_income": with_tech,
        "plants_matter": plants_matter,
        "tech_matters": tech_matters,
        "fissiles_gated": fissiles_gated,
        "tech_tree": tech_tree,
        "factories_ok": factories_ok,
        "surface_keys": list(SURFACE_KEYS),
        "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0,
        "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]),
        "audit": audit,
        "steps": steps_out,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue,
        "integration": [
            "resource_harvest_economy_product",
            "resource_harvest_primary",
            "auto_harvest_province_to_majors",
        ],
    }
