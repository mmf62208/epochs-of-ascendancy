"""Strategic Compact Ledger — pure trade valuation + bilateral relations model.

Mirrors data/trade/strategic_value_rules.json + data/diplomacy/relation_rules.json.
"""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
VALUE_PATH = ROOT / "data" / "trade" / "strategic_value_rules.json"
REL_PATH = ROOT / "data" / "diplomacy" / "relation_rules.json"

SURFACE_KEYS = (
    "trl_primary_catalog",
    "trl_primary_value",
    "trl_primary_relations",
    "trl_primary_flags",
    "trl_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "trl_catalog",
    "trl_value",
    "trl_relations",
    "trl_flags",
    "trl_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "trl_catalog": "apply_trade_relations_catalog_live",
    "trl_value": "apply_trade_relations_value_live",
    "trl_relations": "apply_trade_relations_relations_live",
    "trl_flags": "apply_trade_relations_flags_live",
    "trl_close": "apply_trade_relations_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def load_value_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    return json.loads((path or VALUE_PATH).read_text(encoding="utf-8"))


def load_relation_rules(path: Optional[Path] = None) -> Dict[str, Any]:
    return json.loads((path or REL_PATH).read_text(encoding="utf-8"))


def scarcity_mult(have: float, rules: Optional[Dict] = None) -> float:
    r = rules or load_value_rules()
    s = r.get("scarcity") or {}
    if have < float(s.get("empty_below", 20)):
        return float(s.get("empty_mult", 1.35))
    if have < float(s.get("tight_below", 50)):
        return float(s.get("tight_mult", 1.15))
    if have > float(s.get("ample_above", 200)):
        return float(s.get("ample_mult", 0.9))
    return 1.0


def resource_suu(resource_id: str, qty: float, stock: Optional[Dict] = None, rules=None) -> float:
    r = rules or load_value_rules()
    rid = resource_id.lower()
    if rid in ("oil", "petroleum"):
        rid = "fuel"
    base = float((r.get("resource_base_suu") or {}).get(rid, 1.0))
    crit = r.get("critical_resource_suu_weight") or {}
    if rid in crit:
        base *= float(crit[rid])
    have = float((stock or {}).get(rid, 0))
    return round(base * scarcity_mult(have, r) * max(qty, 0), 2)


def province_suu(dev=10, infra=10, has_port=True, resource_score=100, factories=2, is_choke=False, is_core=False, rules=None) -> float:
    r = rules or load_value_rules()
    p = r.get("province") or {}
    v = float(p.get("base", 400))
    v += float(dev) * float(p.get("per_dev", 25))
    v += float(infra) * float(p.get("per_infra", 20))
    if has_port:
        v += float(p.get("port_bonus", 350))
    v += float(resource_score) * float(p.get("resource_score_scale", 0.15))
    v += float(factories) * float(p.get("factory_bonus", 120))
    if is_choke:
        v += float(p.get("choke_bonus", 500))
    if is_core:
        v *= float(p.get("core_multiplier", 1.75))
    v *= float(p.get("durable_premium", 3.5))
    return round(v, 2)


def docking_suu(months=12, major_port=True, rules=None) -> float:
    r = rules or load_value_rules()
    d = r.get("docking_rights") or {}
    v = float(d.get("base_per_month", 18)) * max(months, 1)
    if major_port:
        v *= float(d.get("major_port_mult", 2))
    v *= float(d.get("sovereignty_premium", 1.4))
    return round(v, 2)


def equipment_suu(production_cost: float, qty: float = 1.0, rules=None) -> float:
    r = rules or load_value_rules()
    per = float(r.get("equipment_suu_per_production_cost", 1.0))
    fb = float(r.get("equipment_fallback_suu", 80))
    unit = production_cost if production_cost > 0 else fb
    return round(unit * per * max(qty, 0), 2)


def crs_from_vectors(vectors: Dict[str, float], rules=None) -> float:
    rr = rules or load_relation_rules()
    w = rr.get("crs_weights") or {}
    crs = 0.0
    wsum = 0.0
    for k in ("public", "elite", "military", "alignment", "trust"):
        ww = float(w.get(k, 0.2))
        crs += float(vectors.get(k, 0)) * ww
        wsum += ww
    if wsum:
        crs /= wsum
    return max(-100.0, min(100.0, crs))


def band_for_crs(crs: float, rules=None) -> Dict[str, Any]:
    rr = rules or load_relation_rules()
    for b in rr.get("bands") or []:
        if crs <= float(b.get("max_crs", 100)):
            return {"id": b.get("id"), "label": b.get("label"), "accept_floor": float(b.get("accept_floor", 0.95)), "crs": crs}
    return {"id": "neutral", "label": "Neutral", "accept_floor": 0.95, "crs": crs}


def evaluate_concerns(item_types: List[str], crs: float, visibility: str = "public", rules=None) -> Dict[str, Any]:
    rr = rules or load_relation_rules()
    flags = []
    reasons = []
    hard = False
    types = [str(t).lower() for t in item_types]
    if visibility == "black":
        flags.append("embargo_evasion")
        reasons.append("Black market path")
    if "province" in types:
        flags.append("territory_humiliation")
        if crs < 55:
            hard = True
            reasons.append("CRS too low for territory")
    if "docking_rights" in types and crs < 55:
        flags.append("basing_sovereignty")
        hard = True
        reasons.append("Basing blocked below partner band")
    if ("design" in types or "tech_share" in types) and crs < 40:
        flags.append("tech_leak_risk")
        hard = True
        reasons.append("Tech leak risk")
    return {"flags": flags, "hard_block": hard, "reasons": reasons, "crs": crs}


def acceptance_ratio(received: float, given: float) -> float:
    if given <= 0.001:
        return 99.0 if received > 0 else 1.0
    return received / given


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Trade relations ledger audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_trade_relations_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    vr = load_value_rules()
    rr = load_relation_rules()
    model_ok = vr.get("model") == "strategic_compact_ledger" and rr.get("model") == "strategic_compact_ledger"
    tank = equipment_suu(110, 1, vr)
    steel = resource_suu("steel", 100, {"steel": 50}, vr)
    peri = province_suu(8, 8, False, 50, 1, False, False, vr)
    core = province_suu(20, 20, True, 200, 4, True, True, vr)
    dock = docking_suu(12, True, vr)
    value_ok = peri > tank * 10 and core > peri and dock > steel
    vectors = {"public": 10, "elite": 15, "military": 5, "alignment": 20, "trust": 12, "dependency": 0}
    crs = crs_from_vectors(vectors, rr)
    band = band_for_crs(crs, rr)
    relations_ok = band["id"] in ("cordial", "partner", "ally_ready", "neutral") and -100 <= crs <= 100
    basing_block = evaluate_concerns(["docking_rights"], -20, "public", rr)
    tech_block = evaluate_concerns(["design"], 10, "public", rr)
    ok_deal = evaluate_concerns(["resource"], 40, "public", rr)
    flags_ok = basing_block["hard_block"] and tech_block["hard_block"] and not ok_deal["hard_block"]
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = model_ok and value_ok and relations_ok and flags_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "TRL · %s · live %s" % (step, api),
            "score": 0.76 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Trade relations ledger · value_ok=%s relations_ok=%s flags_ok=%s" % (value_ok, relations_ok, flags_ok)
    return {
        "score": 0.84 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "model": "strategic_compact_ledger",
        "value_ok": value_ok, "relations_ok": relations_ok, "flags_ok": flags_ok,
        "tank_suu": tank, "steel100_suu": steel, "peripheral_province_suu": peri,
        "core_port_province_suu": core, "docking_12m_suu": dock,
        "crs": crs, "band": band,
        "basing_block": basing_block, "tech_block": tech_block,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["trade_relations_ledger_product", "strategic_compact_ledger", "RelationsManager"],
    }
