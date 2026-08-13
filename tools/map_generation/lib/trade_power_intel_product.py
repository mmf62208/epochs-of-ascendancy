"""Trade power intel — national power, nuclear danger, transit attribution, spy clarity, discounts."""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
POWER_PATH = ROOT / "data" / "diplomacy" / "national_power_rules.json"

SURFACE_KEYS = (
    "tpi_primary_catalog",
    "tpi_primary_power",
    "tpi_primary_transit",
    "tpi_primary_spy",
    "tpi_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "tpi_catalog",
    "tpi_power",
    "tpi_transit",
    "tpi_spy",
    "tpi_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "tpi_catalog": "apply_trade_power_intel_catalog_live",
    "tpi_power": "apply_trade_power_intel_power_live",
    "tpi_transit": "apply_trade_power_intel_transit_live",
    "tpi_spy": "apply_trade_power_intel_spy_live",
    "tpi_close": "apply_trade_power_intel_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def load_power_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    return json.loads((path or POWER_PATH).read_text(encoding="utf-8"))


def compute_power_index(inputs: Dict[str, Any], rules: Optional[Dict] = None) -> Dict[str, Any]:
    r = rules or load_power_rules()
    w = r.get("weights") or {}
    flags = list(inputs.get("tech_flags") or [])
    conventional = (
        float(inputs.get("factories", 0)) * float(w.get("factories", 12))
        + float(inputs.get("steel", 0)) * float(w.get("steel_stock_scale", 0.02))
        + float(inputs.get("fuel", 0)) * float(w.get("fuel_stock_scale", 0.015))
        + float(inputs.get("electronics", 0)) * float(w.get("electronics_stock_scale", 0.04))
        + float(inputs.get("equipment_units", 0)) * float(w.get("equipment_units_scale", 0.08))
        + len(flags) * float(w.get("tech_flags_scale", 8))
        + float(inputs.get("naval_ports", 0)) * float(w.get("naval_basing_scale", 15))
        + float(inputs.get("trade_capacity", 0)) * float(w.get("trade_capacity_scale", 0.5))
    )
    nuke = r.get("nuclear") or {}
    nuclear_score = 0.0
    if float(inputs.get("fissiles_stock", 0)) > 0:
        nuclear_score += float(nuke.get("has_fissiles_stock_bonus", 80))
    if "nuclear_fuel" in flags:
        nuclear_score += float(nuke.get("has_nuclear_fuel_flag_bonus", 120))
    if "nuclear_warhead" in flags or "strategic_nuclear" in flags:
        nuclear_score += float(nuke.get("has_warhead_program_flag_bonus", 200))
    danger = float(nuke.get("danger_multiplier_min", 1.0))
    if nuclear_score >= 200:
        danger = float(nuke.get("danger_multiplier_full_triad", 5.0))
    elif nuclear_score >= 80 or "nuclear_fuel" in flags:
        danger = float(nuke.get("danger_multiplier_with_arsenal", 3.5))
    total = conventional + nuclear_score
    return {
        "conventional": round(conventional, 1),
        "nuclear_score": round(nuclear_score, 1),
        "nuclear_armed": nuclear_score >= 80 or "nuclear_fuel" in flags,
        "danger_multiplier": danger,
        "power_index": round(total, 1),
        "effective_threat": round(conventional * danger + nuclear_score, 1),
    }


def matchup(self_p: Dict, other_p: Dict, rules: Optional[Dict] = None) -> Dict[str, Any]:
    r = rules or load_power_rules()
    m = r.get("matchup") or {}
    self_t = max(float(self_p.get("effective_threat", 1)), 1.0)
    other_t = max(float(other_p.get("effective_threat", 1)), 1.0)
    ratio = self_t / other_t
    label = "peer"
    hopeless = outmatched = False
    if ratio < float(m.get("hopeless_ratio", 0.22)):
        label, hopeless, outmatched = "hopelessly_outmatched", True, True
    elif ratio < float(m.get("outmatched_ratio", 0.45)):
        label, outmatched = "outmatched", True
    elif ratio < float(m.get("contested_ratio", 0.75)):
        label = "contested"
    elif ratio <= float(m.get("peer_ratio", 1.15)):
        label = "peer"
    else:
        label = "dominant"
    return {
        "ratio": round(ratio, 2),
        "label": label,
        "hopeless": hopeless,
        "outmatched": outmatched,
        "nuclear_asymmetry": bool(other_p.get("nuclear_armed")) and not bool(self_p.get("nuclear_armed")),
    }


def ai_placate_delta(mu: Dict, rules: Optional[Dict] = None) -> float:
    r = rules or load_power_rules()
    ap = r.get("ai_placate") or {}
    d = 0.0
    if mu.get("hopeless"):
        d += float(ap.get("hopeless_accept_floor_bonus", -0.18))
    elif mu.get("outmatched"):
        d += float(ap.get("outmatched_accept_floor_bonus", -0.08))
    if mu.get("nuclear_asymmetry"):
        d += float(ap.get("nuclear_vs_non_accept_floor_bonus", -0.12))
    return d


def relationship_discounts(band_id: str, mfn: bool = False, years: float = 0.0, rules=None) -> Dict[str, Any]:
    r = rules or load_power_rules()
    rd = r.get("relationship_discounts") or {}
    base = rd.get(band_id) or {}
    trade = float(base.get("trade_suu_mult", 1.0))
    tech = float(base.get("tech_share_suu_mult", 1.0))
    if mfn:
        trade *= float(rd.get("mfn_extra_trade_mult", 0.95))
    if years >= float(rd.get("long_term_years_for_extra", 5)):
        extra = float(rd.get("long_term_extra_mult", 0.93))
        trade *= extra
        tech *= extra
    return {"trade_suu_mult": round(trade, 3), "tech_share_suu_mult": round(tech, 3), "long_term": years >= 5}


def attribution_plain(cause: str, province_id: int, fr: str, to: str) -> str:
    if cause == "submarine" and province_id:
        return "Submarines in province %d sank transports on the %s → %s convoy" % (province_id, fr, to)
    if cause == "air_attack" and province_id:
        return "Aircraft struck the trade corridor near province %d (%s → %s)" % (province_id, fr, to)
    if cause == "submarine":
        return "Enemy submarines attacked the %s → %s trade route" % (fr, to)
    return "Interdiction hit %s → %s" % (fr, to)


def delivery_ratio(baseline: float, now: float) -> float:
    if baseline <= 0.001:
        return 1.0
    return max(0.0, min(1.0, now / baseline))


def spy_clarity(mission: bool = False, network: bool = False, rules=None) -> float:
    r = rules or load_power_rules()
    s = r.get("spy_intel") or {}
    c = float(s.get("base_clarity", 0.35))
    if mission:
        c += float(s.get("mission_bonus", 0.4))
    if network:
        c += float(s.get("network_bonus", 0.15))
    return max(0.0, min(1.0, c))


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Trade power intel audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Trade power intel audit", "empty": False,
    }


def build_trade_power_intel_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    r = load_power_rules()
    small = compute_power_index({"factories": 5, "steel": 100, "fuel": 50, "tech_flags": []}, r)
    nuke = compute_power_index({
        "factories": 40, "steel": 2000, "fuel": 1500, "electronics": 400,
        "equipment_units": 500, "tech_flags": ["nuclear_fuel", "nuclear_warhead"],
        "fissiles_stock": 50,
    }, r)
    mu = matchup(small, nuke, r)
    power_ok = mu["hopeless"] and mu["nuclear_asymmetry"] and nuke["danger_multiplier"] >= 3.0
    placate = ai_placate_delta(mu, r)
    power_ok = power_ok and placate < -0.1
    disc_ally = relationship_discounts("ally_ready", True, 6, r)
    disc_neutral = relationship_discounts("neutral", False, 0, r)
    disc_ok = disc_ally["trade_suu_mult"] < disc_neutral["trade_suu_mult"]
    plain = attribution_plain("submarine", 42, "USA", "ENG")
    transit_ok = "Submarines in province 42" in plain and delivery_ratio(100, 50) == 0.5
    clarity = spy_clarity(True, True, r)
    spy_ok = clarity >= 0.55
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = power_ok and disc_ok and transit_ok and spy_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "TPI · %s · live %s" % (step, api),
            "score": 0.77 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Trade power intel · power_ok=%s transit_ok=%s spy_ok=%s disc_ok=%s" % (
        power_ok, transit_ok, spy_ok, disc_ok,
    )
    return {
        "score": 0.85 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "power_ok": power_ok, "transit_ok": transit_ok, "spy_ok": spy_ok, "disc_ok": disc_ok,
        "matchup": mu, "placate_delta": placate, "discounts_ally": disc_ally,
        "attribution_plain": plain, "spy_clarity": clarity,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "trade_power_intel_product", "national_power", "nuclear_danger",
            "transit_attribution", "spy_relation_intel", "relationship_discounts",
        ],
    }
