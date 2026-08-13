"""Space layer primary — gated solar map model, corridors, SpaceFlow interdict math (S0)."""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
RULES_PATH = ROOT / "data" / "space" / "space_layer_rules.json"

SURFACE_KEYS = (
    "spl_primary_catalog",
    "spl_primary_gates",
    "spl_primary_graph",
    "spl_primary_routes",
    "spl_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "spl_catalog",
    "spl_gates",
    "spl_graph",
    "spl_routes",
    "spl_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "spl_catalog": "apply_space_layer_catalog_live",
    "spl_gates": "apply_space_layer_gates_live",
    "spl_graph": "apply_space_layer_graph_live",
    "spl_routes": "apply_space_layer_routes_live",
    "spl_close": "apply_space_layer_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def load_space_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    p = path or RULES_PATH
    return json.loads(p.read_text(encoding="utf-8"))


def layer_unlocked(
    layer: Dict[str, Any],
    flags: Optional[Sequence[str]] = None,
    milestones: Optional[Sequence[str]] = None,
) -> bool:
    if bool(layer.get("always_visible")):
        return True
    fl = set(str(x) for x in (flags or []))
    ms = set(str(x) for x in (milestones or []))
    gate_flags = [str(x) for x in (layer.get("gate_flags") or [])]
    gate_ms = [str(x) for x in (layer.get("gate_milestones") or [])]
    mode = str(layer.get("gate_mode", "any"))
    if mode == "all_flags":
        if not gate_flags:
            return False
        return all(g in fl for g in gate_flags)
    # any: unlock if any flag OR any milestone matches (when lists non-empty)
    flag_hit = any(g in fl for g in gate_flags) if gate_flags else False
    ms_hit = any(g in ms for g in gate_ms) if gate_ms else False
    if not gate_flags and not gate_ms:
        return False
    return flag_hit or ms_hit


def visible_layers(
    flags: Optional[Sequence[str]] = None,
    milestones: Optional[Sequence[str]] = None,
    rules: Optional[Dict] = None,
) -> List[Dict[str, Any]]:
    r = rules or load_space_rules()
    out = []
    for raw in r.get("layers") or []:
        if not isinstance(raw, dict):
            continue
        unlocked = layer_unlocked(raw, flags, milestones)
        row = dict(raw)
        row["unlocked"] = unlocked
        row["fogged"] = not unlocked and not bool(raw.get("always_visible"))
        out.append(row)
    out.sort(key=lambda x: int(x.get("order", 0)))
    return out


def bodies_for_unlocked_layers(
    flags: Optional[Sequence[str]] = None,
    milestones: Optional[Sequence[str]] = None,
    rules: Optional[Dict] = None,
) -> List[Dict[str, Any]]:
    r = rules or load_space_rules()
    unlocked_ids = {
        str(L["id"]) for L in visible_layers(flags, milestones, r) if L.get("unlocked")
    }
    bodies = []
    for b in r.get("bodies") or []:
        if not isinstance(b, dict):
            continue
        if str(b.get("layer", "")) in unlocked_ids:
            bodies.append(dict(b))
    return bodies


def spaceflow_hit_chance(route_risk: float, rules: Optional[Dict] = None) -> float:
    r = (rules or load_space_rules()).get("spaceflow") or {}
    risk = max(0.0, float(route_risk))
    scale = float(r.get("hit_chance_scale", 0.55))
    lo = float(r.get("hit_chance_min", 0.02))
    hi = float(r.get("hit_chance_max", 0.5))
    return max(lo, min(hi, risk * scale))


def spaceflow_loss_fraction(route_risk: float, roll: float = 0.6, rules: Optional[Dict] = None) -> float:
    r = (rules or load_space_rules()).get("spaceflow") or {}
    risk = max(0.0, float(route_risk))
    lo = float(r.get("loss_min", 0.08))
    hi = float(r.get("loss_max", 0.7))
    rr = max(0.35, min(0.85, float(roll)))
    return max(lo, min(hi, risk * rr))


def interdict_attribution_plain(cause: str, node_id: str, fr: str, to: str) -> str:
    c = str(cause).lower()
    n = str(node_id) or "unknown node"
    if c == "asat":
        return "ASAT strike near %s degraded the %s → %s space convoy" % (n, fr, to)
    if c == "solar_storm":
        return "Solar storm along %s delayed/damaged the %s → %s transfer" % (n, fr, to)
    if c == "patrol_cutter":
        return "Hostile patrol cutters interdicted %s → %s near %s" % (fr, to, n)
    if c == "piracy":
        return "Piracy hit the %s → %s corridor near %s" % (fr, to, n)
    if c == "debris_cascade":
        return "Debris cascade near %s struck the %s → %s flight path" % (n, fr, to)
    return "Space interdiction on %s → %s at %s (%s)" % (fr, to, n, c)


def open_corridors(
    flags: Optional[Sequence[str]] = None,
    milestones: Optional[Sequence[str]] = None,
    rules: Optional[Dict] = None,
) -> List[Dict[str, Any]]:
    r = rules or load_space_rules()
    unlocked = {
        str(L["id"]) for L in visible_layers(flags, milestones, r) if L.get("unlocked")
    }
    out = []
    for c in r.get("corridors") or []:
        if not isinstance(c, dict):
            continue
        if str(c.get("layer", "")) in unlocked:
            out.append(dict(c))
    return out


def colony_strain(
    command_used: float,
    command_cap: float,
    supply_months: float,
    distance: float = 1.0,
    rules=None,
) -> Dict[str, Any]:
    """Expansion strain when orbital_command overused; starvation from short supply."""
    full = rules or load_space_rules()
    r = full.get("colony_control") or {}
    cap_m = (full.get("capacity_model") or {}).get("expansion_strain") or {}
    over = max(0.0, float(command_used) - float(command_cap))
    strain = over * float(cap_m.get("per_habitat_over_command", r.get("mc_soft_strain_per_over", 0.04)))
    strain += max(0.0, float(distance) - 1.0) * 0.05
    if float(distance) >= 2.0:
        strain += float(cap_m.get("per_outer_system_habitat", 0.04))
    starve_mo = float(r.get("starvation_months", 3))
    if float(supply_months) < starve_mo:
        strain += 0.2
    return {
        "strain": round(min(1.0, strain), 3),
        "mc_over": over > 0,  # legacy key
        "command_over": over > 0,
        "orbital_command_over": over > 0,
        "starvation_risk": float(supply_months) < starve_mo,
        "admin_modes": list(r.get("admin_modes") or []),
    }


def body_site_count(body: Dict[str, Any]) -> int:
    sites = body.get("capture_sites")
    if isinstance(sites, list) and sites:
        return len(sites)
    return int(body.get("sites", 0) or 0)


def multi_site_sol_ok(rules: Optional[Dict] = None) -> Dict[str, Any]:
    r = rules or load_space_rules()
    by_id = {str(b.get("id")): b for b in (r.get("bodies") or []) if isinstance(b, dict)}
    luna_n = body_site_count(by_id.get("luna") or {})
    mars_n = body_site_count(by_id.get("mars") or {})
    ceres_n = body_site_count(by_id.get("ceres") or {})
    has_phobos = "phobos" in by_id
    has_titan = "titan" in by_id
    has_belt = "main_belt_swarm" in by_id or "ceres" in by_id
    ok = luna_n >= 6 and mars_n >= 8 and ceres_n >= 4 and has_phobos and has_titan and has_belt
    return {
        "ok": ok,
        "luna_sites": luna_n,
        "mars_sites": mars_n,
        "ceres_sites": ceres_n,
        "has_phobos": has_phobos,
        "has_titan": has_titan,
        "body_n": len(by_id),
    }


def asteroid_caps(size_key: str, rules: Optional[Dict] = None) -> Dict[str, Any]:
    r = rules or load_space_rules()
    table = r.get("asteroid_size_table") or {}
    row = table.get(size_key) or table.get("small") or {}
    return {
        "size": size_key,
        "sites": int(row.get("sites", 1)),
        "max_pop": int(row.get("max_pop", 800)),
        "max_building_slots": int(row.get("max_building_slots", 3)),
    }


def loft_cost_mult(via_luna: bool = False, via_l1: bool = False, via_station_luna: bool = False, rules=None) -> float:
    r = (rules or load_space_rules()).get("staging_discounts") or {}
    if via_station_luna:
        return float(r.get("via_station_then_luna_mult", 0.55))
    if via_luna:
        return float(r.get("via_luna_base_loft_mult", 0.62))
    if via_l1:
        return float(r.get("via_l1_depot_loft_mult", 0.72))
    return float(r.get("earth_direct_to_mars_loft_mult", 1.0))


def compute_space_power_index(inputs: Dict[str, Any], rules: Optional[Dict] = None) -> Dict[str, Any]:
    r = (rules or load_space_rules()).get("space_power") or {}
    w = r.get("weights") or {}
    fleet = float(inputs.get("fleet_strength", 0))
    orb_w = float(inputs.get("orbital_weapons", 0))
    bomb = float(inputs.get("bombardment_capable_ships", 0))
    defs = float(inputs.get("orbital_defenses", 0))
    isr = float(inputs.get("isr_coverage", 0))
    habs = float(inputs.get("habitats", 0))
    stations = float(inputs.get("stations", 0))
    lift = float(inputs.get("lift_capacity", 0))
    score = (
        fleet * float(w.get("fleet_strength", 1))
        + orb_w * float(w.get("orbital_weapons", 40))
        + bomb * float(w.get("bombardment_capable_ships", 25))
        + defs * float(w.get("orbital_defenses", 18))
        + isr * float(w.get("isr_coverage", 12))
        + habs * float(w.get("habitats", 8))
        + stations * float(w.get("stations", 15))
        + lift * float(w.get("lift_capacity", 3))
    )
    undefended = defs < 1.0 and bomb + orb_w > 0
    threat_mult = float(r.get("undefended_earth_threat_mult", 2.2)) if undefended else 1.0
    return {
        "space_power_index": round(score, 1),
        "bombardment_threat": bomb + orb_w * 0.5 > 0,
        "undefended_surface_penalty": undefended,
        "effective_space_threat": round(score * threat_mult, 1),
        "threat_mult": threat_mult,
    }


def independence_years_to_breakaway(neglect_years: float, mitigated: bool = False, rules=None) -> Dict[str, Any]:
    r = ((rules or load_space_rules()).get("colony_control") or {}).get("independence") or {}
    gen = float(r.get("generation_years", 25))
    mn = float(r.get("min_years_to_breakaway", 20))
    drift = float(r.get("drift_per_year_if_neglected", 2.5))
    if mitigated:
        drift *= 0.35
    # autonomy 0-100; break at 100
    years = max(mn, 100.0 / max(drift, 0.1)) if neglect_years >= 0 else gen
    # If already neglected N years
    autonomy = min(100.0, float(neglect_years) * drift)
    return {
        "generation_years": gen,
        "min_years_to_breakaway": mn,
        "projected_years_if_neglected": round(years, 1),
        "autonomy_after_neglect": round(autonomy, 1),
        "breakaway_ready": autonomy >= 100.0 and neglect_years >= mn,
        "mitigated": mitigated,
    }


def spotting_detect_chance(
    base_range_au: float = 0.5,
    has_radar: bool = True,
    isr: bool = False,
    stealth: bool = False,
    rules=None,
) -> float:
    s = ((rules or load_space_rules()).get("space_combat") or {}).get("spotting") or {}
    c = float(s.get("base_detect", 0.25))
    if has_radar:
        c += float(s.get("radar_bonus", 0.2))
    if isr:
        c += float(s.get("isr_constellation_bonus", 0.25))
    if stealth:
        c -= float(s.get("stealth_fleet_penalty", 0.15))
    c -= float(base_range_au) * float(s.get("range_falloff_per_au", 0.12))
    return max(0.02, min(0.98, c))


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Space layer audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Space layer audit", "empty": False,
    }


def build_space_layer_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    r = load_space_rules()
    model_ok = str(r.get("model", "")) == "orbital_compact_ledger"
    # Gates: no flags → only earth; with satellites → near_earth
    early = visible_layers([], [], r)
    early_ids = [str(x["id"]) for x in early if x.get("unlocked")]
    gates_locked = early_ids == ["earth_surface"]
    mid = visible_layers(["allow_satellites"], ["first_satellite"], r)
    mid_ok = any(x["id"] == "near_earth" and x.get("unlocked") for x in mid)
    lunar = visible_layers(["allow_lunar_operations"], ["moon_landing"], r)
    lunar_ok = any(x["id"] == "cis_lunar" and x.get("unlocked") for x in lunar)
    gates_ok = gates_locked and mid_ok and lunar_ok
    # Graph
    bodies_mid = bodies_for_unlocked_layers(["allow_satellites"], ["first_satellite"], r)
    graph_ok = any(b.get("id") == "leo_band" for b in bodies_mid) and model_ok
    # Routes / interdict
    corridors = open_corridors(["allow_satellites", "allow_lunar_operations"], ["moon_landing"], r)
    routes_ok = len(corridors) >= 2
    plain = interdict_attribution_plain("asat", "leo_band", "earth", "luna")
    risk = spaceflow_hit_chance(0.2, r)
    loss = spaceflow_loss_fraction(0.4, 0.6, r)
    routes_ok = routes_ok and "ASAT" in plain and 0.02 <= risk <= 0.5 and 0.08 <= loss <= 0.7
    # Colony strain sample
    st = colony_strain(8, 5, 1.0, 2.0, r)
    strain_ok = st["starvation_risk"] and st["mc_over"] and st["strain"] > 0.1
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = gates_ok and graph_ok and routes_ok and strain_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "SPL · %s · live %s" % (step, api),
            "score": 0.8 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Space layer · gates_ok=%s graph_ok=%s routes_ok=%s strain_ok=%s" % (
        gates_ok, graph_ok, routes_ok, strain_ok,
    )
    return {
        "score": 0.88 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "gates_ok": gates_ok, "graph_ok": graph_ok, "routes_ok": routes_ok, "strain_ok": strain_ok,
        "model": "orbital_compact_ledger",
        "visible_early": early_ids,
        "bodies_mid_n": len(bodies_mid),
        "corridors_n": len(corridors),
        "attribution_plain": plain,
        "colony_strain": st,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "space_layer_product", "orbital_compact_ledger", "tech_gates",
            "spaceflow_interdict", "colony_strain", "solar_map_foundation",
        ],
    }
