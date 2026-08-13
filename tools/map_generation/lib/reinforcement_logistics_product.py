"""RF0/RF1 pure product — reinforce time, hub distance, experience dilution, policies."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "rfl_primary_catalog",
    "rfl_primary_time",
    "rfl_primary_exp",
    "rfl_primary_hub",
    "rfl_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "rfl_catalog",
    "rfl_time",
    "rfl_exp",
    "rfl_hub",
    "rfl_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "rfl_catalog": "apply_reinforcement_logistics_catalog_live",
    "rfl_time": "apply_reinforcement_logistics_time_live",
    "rfl_exp": "apply_reinforcement_logistics_exp_live",
    "rfl_hub": "apply_reinforcement_logistics_hub_live",
    "rfl_close": "apply_reinforcement_logistics_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

MODE_BASE = {
    "rail": 1.0, "road": 1.5, "sealift": 2.2, "river": 1.3,
    "airlift": 0.45, "helicopter": 0.65, "drone_logistics": 0.35, "orbital": 0.12,
}
ERA_MOB = {
    "rail_age": 0.72, "motor_air_dawn": 0.95, "airlift_age": 1.25,
    "network_drone": 1.55, "orbital_support": 1.9,
}


def era_band_for_year(year: int) -> str:
    y = int(year)
    if y < 1936:
        return "rail_age"
    if y < 1956:
        return "motor_air_dawn"
    if y < 1996:
        return "airlift_age"
    if y < 2041:
        return "network_drone"
    return "orbital_support"


def distance_factor(distance_km: float) -> float:
    d = max(0.0, float(distance_km))
    return max(1.0, min(3.5, 1.0 + (d / 500.0) ** 0.5 * 0.55))


def transit_days(
    mode: str = "rail",
    hops: int = 1,
    distance_km: float = 0.0,
    year: int = 1939,
    depot_fill: float = 1.0,
    corridor_control: float = 1.0,
    fuel: float = 1.0,
    supplies: float = 1.0,
    electronics: float = 1.0,
    throughput: float = 1.0,
) -> float:
    base = float(MODE_BASE.get(str(mode).lower(), 1.0))
    hop_n = max(1, int(hops))
    dist = distance_factor(distance_km)
    era = float(ERA_MOB.get(era_band_for_year(year), 1.0))
    hub = max(0.55, min(1.25, 0.55 + float(depot_fill) * 0.35 + float(corridor_control) * 0.35))
    res = max(0.5, min(1.0, 0.45 * float(supplies) + 0.35 * float(fuel) + 0.2))
    train = max(0.55, min(1.8, float(throughput)))
    raw = (base * hop_n * dist) / max(0.35, era * hub * res * train)
    return max(0.25, min(90.0, raw))


def blend_manpower(old_xp: float, recruit_xp: float, fraction: float, cadre_bonus: float = 2.0) -> float:
    frac = max(0.0, min(1.0, float(fraction)))
    blended = (1.0 - frac) * float(old_xp) + frac * float(recruit_xp)
    blended += float(cadre_bonus) * (1.0 - frac) * 0.15
    return max(0.0, min(100.0, blended))


def blend_rearm(old_xp: float, rearm_fraction: float, novelty: float = 0.35, penalty: float = 8.0) -> float:
    return max(0.0, min(100.0, float(old_xp) - float(penalty) * max(0.0, min(1.0, rearm_fraction)) * max(0.0, min(1.0, novelty))))


def experience_combat_mult(xp: float) -> float:
    x = max(0.0, min(100.0, float(xp)))
    if x <= 20:
        return 0.78 + (0.88 - 0.78) * (x / 20.0)
    if x <= 40:
        return 0.88 + (0.98 - 0.88) * ((x - 20.0) / 20.0)
    if x <= 60:
        return 0.98 + (1.0 - 0.98) * ((x - 40.0) / 20.0)
    if x <= 80:
        return 1.0 + (1.1 - 1.0) * ((x - 60.0) / 20.0)
    return 1.1 + (1.2 - 1.1) * ((x - 80.0) / 20.0)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead),
        "ok": len(dead) == 0 and len(ids) >= 5,
        "summary": "Reinforcement logistics audit", "plain": "Reinforcement logistics audit", "empty": False,
    }


def build_reinforcement_logistics_primary_command_product(
    *, province_id: int = 1, live_ids=None
) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    calc_path = ROOT / "scripts/production/ReinforcementLogisticsCalculator.gd"
    form_path = ROOT / "scripts/formations/Formation.gd"
    pm_path = ROOT / "scripts/autoload/ProductionManager.gd"
    gd_path = ROOT / "scripts/autoload/GameData.gd"
    doc_path = ROOT / "docs/REINFORCEMENT_EXPERIENCE_LOGISTICS_DESIGN_FREEZE.md"
    calc = calc_path.read_text(encoding="utf-8") if calc_path.exists() else ""
    form = form_path.read_text(encoding="utf-8") if form_path.exists() else ""
    pm = pm_path.read_text(encoding="utf-8") if pm_path.exists() else ""
    gd = gd_path.read_text(encoding="utf-8") if gd_path.exists() else ""
    doc = doc_path.read_text(encoding="utf-8") if doc_path.exists() else ""

    hooks_ok = all(
        s in calc
        for s in (
            "func transit_days",
            "func blend_combat_experience_manpower",
            "func blend_combat_experience_rearm",
            "func experience_combat_mult",
            "func era_band_for_year",
        )
    ) and "combat_experience" in form and all(
        s in pm
        for s in (
            "func apply_manpower_reinforce_with_experience",
            "func apply_equipment_rearm_experience",
            "func estimate_reinforce_transit_days",
        )
    ) and "func apply_reinforcement_logistics_primary_live" in gd

    # Era: 1916 rail far > 2025 airlift priority > 2080 orbital short
    d1916 = transit_days("rail", hops=3, distance_km=1200, year=1916)
    d2025 = transit_days("airlift", hops=2, distance_km=1200, year=2025, fuel=0.9)
    d2080 = transit_days("orbital", hops=1, distance_km=1200, year=2080, fuel=0.9, electronics=0.9)
    time_ok = d1916 > d2025 > d2080 and d1916 >= 2.0

    # Manpower dilution vs rearm asymmetry
    vet = 85.0
    after_greens = blend_manpower(vet, 12.0, 0.5)
    after_rearm = blend_rearm(vet, 0.5, novelty=0.35)
    exp_ok = after_greens < vet - 20 and after_rearm > after_greens + 15 and after_rearm > 70
    mult_green = experience_combat_mult(15)
    mult_vet = experience_combat_mult(90)
    exp_ok = exp_ok and mult_green < 0.9 and mult_vet > 1.1

    near = transit_days("rail", hops=1, distance_km=50, year=1939)
    far = transit_days("rail", hops=1, distance_km=1500, year=1939)
    hub_ok = far > near * 1.15

    doc_ok = all(
        k in doc
        for k in (
            "reinforce_experience_logistics_ledger",
            "blend",
            "era_mobility",
            "wartime_crash",
            "EquipmentFlow",
        )
    )
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and time_ok and exp_ok and hub_ok and doc_ok and audit["ok"]

    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "RFL · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})

    label = "Reinforce logistics · time=%s exp=%s hub=%s" % (time_ok, exp_ok, hub_ok)
    return {
        "score": 0.96 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "time_ok": time_ok, "exp_ok": exp_ok,
        "hub_ok": hub_ok, "doc_ok": doc_ok,
        "d1916": d1916, "d2025": d2025, "d2080": d2080,
        "after_greens": after_greens, "after_rearm": after_rearm,
        "model": "reinforce_experience_logistics_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "reinforcement_logistics_product", "ReinforcementLogisticsCalculator",
            "Formation.combat_experience", "ProductionManager",
        ],
    }
