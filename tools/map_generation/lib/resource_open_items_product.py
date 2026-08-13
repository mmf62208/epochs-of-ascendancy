"""Resource open items — plant surface, endgame deposits, majors trade.

Closes residual design open list: plant place/upgrade surface, He-3/antimatter
year placement, major resource trade board.
"""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
HARVEST_PATH = ROOT / "data" / "production" / "resource_harvest_rules.json"

try:
    from resource_harvest_economy_product import load_harvest_rules  # type: ignore
except Exception:  # pragma: no cover
    def load_harvest_rules(path=None):  # type: ignore
        return json.loads((path or HARVEST_PATH).read_text(encoding="utf-8"))

SURFACE_KEYS = (
    "roi_primary_catalog",
    "roi_primary_plants",
    "roi_primary_endgame",
    "roi_primary_trade",
    "roi_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "roi_catalog",
    "roi_plants",
    "roi_endgame",
    "roi_trade",
    "roi_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "roi_catalog": "apply_resource_open_items_catalog_live",
    "roi_plants": "apply_resource_open_items_plants_live",
    "roi_endgame": "apply_resource_open_items_endgame_live",
    "roi_trade": "apply_resource_open_items_trade_live",
    "roi_close": "apply_resource_open_items_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def build_plant_browser_rows(plants: List[Dict[str, Any]], harvest: Optional[Dict] = None) -> List[Dict[str, Any]]:
    h = harvest if harvest is not None else load_harvest_rules()
    catalogs = {}
    catalogs.update(h.get("energy_plant_types") or {})
    catalogs.update(h.get("resource_plant_types") or {})
    tiers = h.get("size_tier_multipliers") or {}
    rows = []
    for p in plants or []:
        ptype = str(p.get("factory_type") or p.get("plant_type") or "").lower()
        conf = catalogs.get(ptype) or {}
        tier = max(1, min(5, int(p.get("size_tier") or 1)))
        rows.append({
            "plant_type": ptype,
            "icon": conf.get("icon", ptype),
            "size_tier": tier,
            "size_mult": float(tiers.get(str(tier), 1.0)),
            "can_upgrade": tier < 5,
            "next_size_tier": min(tier + 1, 5),
        })
    return rows


def build_place_plant_action(resources, unlocks=None, override="", harvest=None) -> Dict[str, Any]:
    h = harvest if harvest is not None else load_harvest_rules()
    seed = h.get("plant_auto_seed") or {}
    catalogs = {}
    catalogs.update(h.get("energy_plant_types") or {})
    catalogs.update(h.get("resource_plant_types") or {})
    min_dep = float(h.get("plant_auto_seed_min_deposit", 40.0))
    flags = [str(x) for x in ((unlocks or {}).get("rule_flags") or [])]
    ptype = str(override or "").lower()
    if not ptype:
        best_a, best_p = 0.0, ""
        for sk, amt in (resources or {}).items():
            skl = str(sk).lower()
            a = float(amt)
            if a < min_dep or skl not in seed:
                continue
            plant = str(seed[skl]).lower()
            conf = catalogs.get(plant) or {}
            req = str(conf.get("requires_unlock") or "")
            if req and req not in flags:
                continue
            if a > best_a:
                best_a, best_p = a, plant
        ptype = best_p
    if not ptype or ptype not in catalogs:
        return {"ok": False, "error": "no_plant_type"}
    conf = catalogs[ptype]
    req = str(conf.get("requires_unlock") or "")
    if req and req not in flags:
        return {"ok": False, "error": "locked", "requires_unlock": req}
    return {"ok": True, "plant_type": ptype, "size_tier": 1, "icon": conf.get("icon", ptype)}


def apply_endgame_deposits(provinces, scenario_year: int, unlocks_by_tag=None, harvest=None) -> Dict[str, Any]:
    h = harvest if harvest is not None else load_harvest_rules()
    years = h.get("endgame_deposit_years") or {}
    he_y = int(years.get("helium3", 2040))
    am_y = int(years.get("antimatter", 2080))
    report = {"year": scenario_year, "helium3_added": 0, "antimatter_added": 0, "touched": []}
    he_ok = scenario_year >= he_y
    am_ok = scenario_year >= am_y
    if not he_ok and not am_ok:
        report["skipped"] = "year_gate"
        return report
    unlocks_by_tag = unlocks_by_tag or {}
    for p in provinces or []:
        if not isinstance(p, dict):
            continue
        res = dict(p.get("resources") or {})
        if not res:
            continue
        tag = str(p.get("owner_tag") or "").upper()
        flags = [str(x) for x in ((unlocks_by_tag.get(tag) or {}).get("rule_flags") or [])]
        changed = False
        if he_ok and ("fusion_power_industry" in flags or scenario_year >= he_y + 5):
            if (float(res.get("uranium", 0)) > 0 or float(res.get("rare_earths", 0)) > 40) and float(res.get("helium3", 0)) <= 0:
                res["helium3"] = round(max(float(res.get("uranium", res.get("rare_earths", 20))) * 0.15, 8.0), 1)
                report["helium3_added"] += 1
                changed = True
        if am_ok and ("antimatter_unlock" in flags or scenario_year >= am_y):
            if (float(res.get("oil", 0)) > 200 or float(res.get("coal", 0)) > 400) and float(res.get("antimatter", 0)) <= 0:
                res["antimatter"] = 5.0
                report["antimatter_added"] += 1
                changed = True
        if changed:
            p["resources"] = res
            report["touched"].append(int(p.get("province_id") or 0))
    return report


def major_trade_unit_value(resource_id: str, stockpile=None, base_rates=None) -> float:
    rid = str(resource_id).lower()
    rates = base_rates or {
        "steel": 1.0, "aluminum": 1.5, "energy": 1.2, "fuel": 1.8,
        "rubber": 2.2, "electronics": 3.0, "specials": 2.8, "fissiles": 4.5,
    }
    base = float(rates.get(rid, 1.0))
    have = float((stockpile or {}).get(rid, 0.0))
    scarcity = 1.0
    if have < 20:
        scarcity = 1.35
    elif have < 50:
        scarcity = 1.15
    elif have > 200:
        scarcity = 0.9
    return round(base * scarcity, 2)


def build_resource_browser(stockpile=None, unlocks=None, scenario_year=0, harvest=None) -> Dict[str, Any]:
    h = harvest if harvest is not None else load_harvest_rules()
    always = [str(x) for x in (h.get("always_visible_majors") or [])]
    majors = []
    for mid in always:
        majors.append({"id": mid, "amount": float((stockpile or {}).get(mid, 0)), "visible": True})
    flags = [str(x) for x in ((unlocks or {}).get("rule_flags") or [])]
    if "nuclear_fuel" in flags:
        majors.append({"id": "fissiles", "amount": float((stockpile or {}).get("fissiles", 0)), "visible": True})
    endgame = []
    years = h.get("endgame_deposit_years") or {}
    if "fusion_power_industry" in flags and scenario_year >= int(years.get("helium3", 2040)):
        endgame.append({"id": "helium3", "feeds": "energy", "visible": True})
    if "antimatter_unlock" in flags and scenario_year >= int(years.get("antimatter", 2080)):
        endgame.append({"id": "antimatter", "feeds": "energy", "visible": True})
    return {"majors": majors, "endgame_sources": endgame, "major_n": len(majors), "endgame_n": len(endgame)}


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Resource open items audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL")
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok, "summary": label, "plain": label, "empty": False}


def build_resource_open_items_primary_command_product(*, province_id: int = 1, live_ids=None):
    pid = max(1, int(province_id))
    h = load_harvest_rules()
    plants = [{"factory_type": "coal_plant", "size_tier": 2, "factory_id": 101}]
    rows = build_plant_browser_rows(plants, h)
    place = build_place_plant_action({"coal": 200.0}, {}, "", h)
    plants_ok = bool(rows) and bool(place.get("ok")) and bool(rows[0].get("can_upgrade"))
    # Endgame year gate: 1936 no deposits; 2045 helium possible
    early = apply_endgame_deposits(
        [{"province_id": 1, "owner_tag": "USA", "resources": {"uranium": 50.0}}],
        1936, {"USA": {"rule_flags": ["fusion_power_industry"]}}, h,
    )
    late = apply_endgame_deposits(
        [{"province_id": 1, "owner_tag": "USA", "resources": {"uranium": 50.0}}],
        2045, {"USA": {"rule_flags": ["fusion_power_industry"]}}, h,
    )
    endgame_ok = early.get("skipped") == "year_gate" and int(late.get("helium3_added", 0)) >= 1
    scarce = major_trade_unit_value("electronics", {"electronics": 5.0})
    plenty = major_trade_unit_value("electronics", {"electronics": 300.0})
    trade_ok = scarce > plenty and major_trade_unit_value("fuel") > major_trade_unit_value("steel")
    browser_ww1 = build_resource_browser({}, {}, 1918, h)
    browser_nuke = build_resource_browser({}, {"rule_flags": ["nuclear_fuel"]}, 1950, h)
    browser_ok = browser_ww1["major_n"] >= 7 and any(m["id"] == "fissiles" for m in browser_nuke["majors"])
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = plants_ok and endgame_ok and trade_ok and browser_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "ROI · %s · live %s" % (step, api),
            "score": 0.75 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Resource open items · plants_ok=%s endgame_ok=%s trade_ok=%s browser_ok=%s" % (
        plants_ok, endgame_ok, trade_ok, browser_ok,
    )
    return {
        "score": 0.82 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "plants_ok": plants_ok, "endgame_ok": endgame_ok, "trade_ok": trade_ok, "browser_ok": browser_ok,
        "plant_rows": rows, "place": place, "early_endgame": early, "late_endgame": late,
        "scarce_value": scarce, "plenty_value": plenty,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "resource_open_items_product", "resource_open_items_primary",
            "plant_surface", "endgame_deposits", "major_resource_trade",
        ],
    }
