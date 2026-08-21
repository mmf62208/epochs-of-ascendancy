"""Era-scaled province deposits → national factory feeds + develop-mine.

Painted `province_resources_layer` is 1936-baseline geology. 1918 extracts
less oil/aluminum (not yet industrialized); 2026 extracts more oil/aluminum
and drops coal's relative weight. Harvest credits HOI factory keys (oil, coal,
chromium, tungsten, steel, rubber, aluminum) so industry TOE can pay from
the same stockpile the nation harvests.

Develop expands an *existing* era-visible deposit. It does not invent oil
in a coal province.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, Mapping, Optional, Sequence

from era_infra_profile import era_band_for_year
from equipment_flow_product import can_produce, produce_to_stockpile
from map_resources_mapmode_product import resource_dominance, resources_mapmode_rgb
from resource_harvest_economy_product import (
    compute_province_daily_income,
    raw_daily_from_deposit,
    source_to_major_map,
)

ROOT = Path(__file__).resolve().parents[3]

# 1936 = 1.0 matches painted layer. Band 0 = 1918, 1 = 1936, 2 = 2026.
ERA_SCALE: Dict[str, Dict[int, float]] = {
    "coal": {0: 1.20, 1: 1.00, 2: 0.65},
    "iron": {0: 0.90, 1: 1.00, 2: 1.10},
    "steel": {0: 0.65, 1: 1.00, 2: 1.20},
    "oil": {0: 0.32, 1: 1.00, 2: 1.80},
    "rubber": {0: 0.40, 1: 1.00, 2: 0.75},
    "aluminum": {0: 0.12, 1: 1.00, 2: 1.55},
    "chromium": {0: 0.35, 1: 1.00, 2: 1.25},
    "tungsten": {0: 0.28, 1: 1.00, 2: 1.30},
    "uranium": {0: 0.00, 1: 0.08, 2: 1.00},
    "rare_earths": {0: 0.00, 1: 0.00, 2: 1.00},
}

# Keys factories pay (TOE_RESOURCE_COST) — harvest must credit these, not only majors.
FACTORY_FEED_KEYS = (
    "steel",
    "coal",
    "oil",
    "rubber",
    "aluminum",
    "chromium",
    "tungsten",
)

DEVELOP_MAX_LEVEL = 3
DEVELOP_BONUS_PER_LEVEL = 0.35
DEVELOP_STEEL_BASE = 8.0
DEVELOP_STEEL_PER_LEVEL = 4.0
OMIT_THRESHOLD = 0.25
OCCUPATION_HARVEST_MULT = 0.65
REFUEL_STOCK_PER_TENTH = 0.5

# Sample deposits used by the integrity product (1936-painted magnitudes).
BAKU_OIL = {"oil": 3.0}
RUHR_COAL = {"coal": 4.0, "steel": 2.0, "iron": 2.0}
BAUXITE = {"aluminum": 2.0}
MALAYA_RUBBER = {"rubber": 3.0}
GER_SLICE = (
    {"oil": 3.0},
    {"coal": 4.0, "steel": 3.0, "iron": 2.0},
    {"rubber": 2.0},
    {"chromium": 2.0, "tungsten": 2.0},
    {"aluminum": 2.0},
)


def era_label(year: int) -> str:
    band = era_band_for_year(int(year))
    return ("sparse_1918", "standard_1936", "dense_2026")[band]


def era_resource_scale(year: int, key: str) -> float:
    band = era_band_for_year(int(year))
    k = str(key or "").strip().lower()
    row = ERA_SCALE.get(k)
    if not row:
        return 1.0
    return float(row.get(band, 1.0))


def scale_deposits_for_year(
    resources: Optional[Mapping[str, Any]],
    year: int,
) -> Dict[str, float]:
    """1936-painted amounts → era extraction. Omits goods not yet exploited."""
    out: Dict[str, float] = {}
    if not resources:
        return out
    for raw_k, raw_v in resources.items():
        key = str(raw_k).strip().lower()
        try:
            amt = float(raw_v or 0.0)
        except (TypeError, ValueError):
            amt = 0.0
        if amt <= 0.0:
            continue
        scaled = amt * era_resource_scale(year, key)
        if scaled < OMIT_THRESHOLD:
            continue
        out[key] = round(scaled, 4)
    return out


def development_mult(level: int) -> float:
    lv = max(0, min(int(DEVELOP_MAX_LEVEL), int(level)))
    return 1.0 + DEVELOP_BONUS_PER_LEVEL * float(lv)


def apply_development(
    resources: Optional[Mapping[str, Any]],
    development: Optional[Mapping[str, Any]] = None,
) -> Dict[str, float]:
    out: Dict[str, float] = {}
    if not resources:
        return out
    dev = development or {}
    for raw_k, raw_v in resources.items():
        key = str(raw_k).strip().lower()
        try:
            amt = float(raw_v or 0.0)
        except (TypeError, ValueError):
            amt = 0.0
        if amt <= 0.0:
            continue
        try:
            lv = int(dev.get(key, 0) or 0)
        except (TypeError, ValueError):
            lv = 0
        out[key] = round(amt * development_mult(lv), 4)
    return out


def develop_cost(current_level: int = 0) -> Dict[str, float]:
    lv = max(0, min(int(DEVELOP_MAX_LEVEL), int(current_level)))
    return {"steel": DEVELOP_STEEL_BASE + DEVELOP_STEEL_PER_LEVEL * float(lv)}


def build_develop_resource_action(
    resources: Optional[Mapping[str, Any]],
    key: str = "",
    *,
    year: int = 1936,
    development: Optional[Mapping[str, Any]] = None,
    stockpile: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Expand an existing era-visible deposit. Does not invent geology."""
    scaled = scale_deposits_for_year(resources, year)
    want = str(key or "").strip().lower()
    if not want:
        dom = resource_dominance(scaled)
        want = str(dom.get("dominant") or "")
    if not want:
        return {"ok": False, "error": "no_deposit"}
    if float(scaled.get(want, 0.0) or 0.0) <= 0.0:
        return {"ok": False, "error": "not_visible", "key": want, "year": int(year)}
    dev = dict(development or {})
    try:
        cur = int(dev.get(want, 0) or 0)
    except (TypeError, ValueError):
        cur = 0
    if cur >= DEVELOP_MAX_LEVEL:
        return {"ok": False, "error": "max_level", "key": want, "level": cur}
    cost = develop_cost(cur)
    stock = stockpile or {}
    for rk, need in cost.items():
        try:
            have = float(stock.get(rk, 0.0) or 0.0)
        except (TypeError, ValueError):
            have = 0.0
        if have + 1e-9 < float(need):
            return {
                "ok": False,
                "error": "no_resources",
                "key": want,
                "cost": cost,
                "have": have,
            }
    return {
        "ok": True,
        "key": want,
        "level_before": cur,
        "level_after": cur + 1,
        "cost": cost,
        "bonus_after": development_mult(cur + 1),
        "year": int(year),
    }


def apply_develop_resource(
    resources: Mapping[str, Any],
    development: Mapping[str, Any],
    stockpile: Mapping[str, Any],
    key: str = "",
    *,
    year: int = 1936,
) -> Dict[str, Any]:
    action = build_develop_resource_action(
        resources, key, year=year, development=development, stockpile=stockpile
    )
    if not action.get("ok"):
        return {
            "ok": False,
            "error": action.get("error"),
            "development": dict(development or {}),
            "stockpile": dict(stockpile or {}),
            "action": action,
        }
    want = str(action["key"])
    dev = dict(development or {})
    stock = dict(stockpile or {})
    for rk, need in (action.get("cost") or {}).items():
        stock[str(rk)] = float(stock.get(rk, 0.0) or 0.0) - float(need)
    dev[want] = int(action["level_after"])
    return {
        "ok": True,
        "key": want,
        "development": dev,
        "stockpile": stock,
        "action": action,
    }


def harvest_factory_feeds(
    resources: Optional[Mapping[str, Any]],
    *,
    year: int = 1936,
    development: Optional[Mapping[str, Any]] = None,
    plants: Optional[list] = None,
    unlocks: Optional[Dict[str, Any]] = None,
    days: float = 1.0,
    occupation_mult: float = 1.0,
) -> Dict[str, float]:
    """Daily (or multi-day) factory-feed + major income from era-scaled deposits."""
    scaled = scale_deposits_for_year(resources, year)
    majors = compute_province_daily_income(scaled, plants, unlocks)
    feeds: Dict[str, float] = {str(k): float(v) for k, v in majors.items()}
    mapping = source_to_major_map()
    dev = development or {}
    major_boost: Dict[str, float] = {}
    for key, amt in scaled.items():
        try:
            lv = int(dev.get(key, 0) or 0)
        except (TypeError, ValueError):
            lv = 0
        lv_m = development_mult(lv)
        major = str(mapping.get(key, key))
        if lv_m > float(major_boost.get(major, 1.0)):
            major_boost[major] = lv_m
        if key not in FACTORY_FEED_KEYS:
            continue
        # steel/rubber/aluminum already land on the same major; oil/coal/cr/w need a factory key.
        if major == key:
            continue
        daily = raw_daily_from_deposit(amt)
        if daily <= 0.0:
            continue
        feeds[key] = float(feeds.get(key, 0.0)) + daily * 0.35 * lv_m
    for major, bm in major_boost.items():
        if major in feeds and bm > 1.0 + 1e-9:
            feeds[major] = float(feeds[major]) * bm
    d = max(0.0, float(days)) * max(0.0, float(occupation_mult))
    return {k: round(v * d, 4) for k, v in feeds.items() if v > 0.0}


def harvest_holder_tag(owner: str = "", controller: str = "") -> str:
    c = str(controller or "").strip().upper()
    if c:
        return c
    return str(owner or "").strip().upper()


def occupation_harvest_mult(owner: str = "", controller: str = "") -> float:
    holder = harvest_holder_tag(owner, controller)
    own = str(owner or "").strip().upper()
    if not holder or not own or holder == own:
        return 1.0
    return float(OCCUPATION_HARVEST_MULT)


def harvest_by_holder(
    provinces: Sequence[Mapping[str, Any]],
    *,
    year: int = 1936,
    days: float = 1.0,
) -> Dict[str, Dict[str, float]]:
    """Controller (occupier) harvests; legal owner gets nothing while occupied."""
    by_tag: Dict[str, Dict[str, float]] = {}
    for p in provinces or []:
        if not isinstance(p, Mapping):
            continue
        holder = harvest_holder_tag(str(p.get("owner_tag") or ""), str(p.get("controller_tag") or ""))
        if not holder:
            continue
        res = p.get("resources") if isinstance(p.get("resources"), Mapping) else p
        dev = p.get("development") if isinstance(p.get("development"), Mapping) else {}
        plants = p.get("plants") if isinstance(p.get("plants"), list) else None
        occ = occupation_harvest_mult(str(p.get("owner_tag") or ""), str(p.get("controller_tag") or ""))
        inc = harvest_factory_feeds(
            res, year=year, development=dev, plants=plants, days=days, occupation_mult=occ
        )
        if holder not in by_tag:
            by_tag[holder] = {}
        merge_income(by_tag[holder], inc)
    return {t: {k: round(v, 4) for k, v in row.items()} for t, row in by_tag.items()}


def refuel_from_stockpile(
    fuel_level: float,
    fuel_use: float,
    stockpile: Optional[Mapping[str, Any]] = None,
    amount: float = 0.10,
) -> Dict[str, Any]:
    """Fill formation fuel from national fuel (then oil). Empty stock invents nothing."""
    cur = max(0.0, min(1.0, float(fuel_level)))
    use = max(0.0, float(fuel_use))
    stock = {str(k): float(v or 0.0) for k, v in (stockpile or {}).items()}
    if use <= 1e-9:
        return {
            "ok": True,
            "fuel_after": cur,
            "paid": 0.0,
            "stockpile": stock,
            "reason": "foot",
        }
    gap = min(max(0.0, float(amount)), 1.0 - cur)
    if gap <= 1e-9:
        return {
            "ok": True,
            "fuel_after": cur,
            "paid": 0.0,
            "stockpile": stock,
            "reason": "full",
        }
    need = (gap / 0.10) * float(REFUEL_STOCK_PER_TENTH)
    have = max(0.0, float(stock.get("fuel", 0.0))) + max(0.0, float(stock.get("oil", 0.0)))
    if have <= 1e-9:
        return {
            "ok": False,
            "fuel_after": cur,
            "paid": 0.0,
            "stockpile": stock,
            "error": "empty_stock",
        }
    paid = min(have, need)
    fill = paid / need if need > 0.0 else 0.0
    take_fuel = min(max(0.0, float(stock.get("fuel", 0.0))), paid)
    stock["fuel"] = max(0.0, float(stock.get("fuel", 0.0)) - take_fuel)
    rest = paid - take_fuel
    if rest > 1e-9:
        stock["oil"] = max(0.0, float(stock.get("oil", 0.0)) - rest)
    return {
        "ok": True,
        "fuel_after": round(cur + gap * fill, 4),
        "paid": round(paid, 4),
        "stockpile": stock,
        "reason": "refueled",
    }


def merge_income(target: Dict[str, float], add: Mapping[str, Any]) -> Dict[str, float]:
    for k, v in (add or {}).items():
        try:
            amt = float(v or 0.0)
        except (TypeError, ValueError):
            amt = 0.0
        if amt <= 0.0:
            continue
        target[str(k)] = float(target.get(str(k), 0.0)) + amt
    return target


def harvest_nation(
    provinces: Sequence[Mapping[str, Any]],
    *,
    year: int = 1936,
    days: float = 1.0,
) -> Dict[str, float]:
    nation: Dict[str, float] = {}
    for p in provinces or []:
        if not isinstance(p, Mapping):
            continue
        res = p.get("resources") if isinstance(p.get("resources"), Mapping) else p
        dev = p.get("development") if isinstance(p.get("development"), Mapping) else {}
        plants = p.get("plants") if isinstance(p.get("plants"), list) else None
        inc = harvest_factory_feeds(
            res, year=year, development=dev, plants=plants, days=days
        )
        merge_income(nation, inc)
    return {k: round(v, 4) for k, v in nation.items()}


def icon_px_for_amount(amount: float) -> float:
    """Map overlay glyph size — richer deposits read larger."""
    a = max(0.0, float(amount))
    return max(10.0, min(22.0, 10.0 + a * 2.2))


def era_mapmode_rgb(resources: Optional[Mapping[str, Any]], year: int, **kwargs) -> tuple:
    return resources_mapmode_rgb(scale_deposits_for_year(resources, year), **kwargs)


def _ok(passes, fails, name: str, cond: bool) -> None:
    (passes if cond else fails).append(name)


def build_era_resource_industry_product() -> Dict[str, Any]:
    """Integrity: era amounts differ, harvest feeds factories, develop expands existing."""
    passes: list = []
    fails: list = []

    oil_18 = scale_deposits_for_year(BAKU_OIL, 1918)
    oil_36 = scale_deposits_for_year(BAKU_OIL, 1936)
    oil_26 = scale_deposits_for_year(BAKU_OIL, 2026)
    _ok(passes, fails, "oil_1918_lt_1936", float(oil_18.get("oil", 0)) < float(oil_36.get("oil", 0)))
    _ok(passes, fails, "oil_1936_lt_2026", float(oil_36.get("oil", 0)) < float(oil_26.get("oil", 0)))

    coal_18 = scale_deposits_for_year(RUHR_COAL, 1918)
    coal_26 = scale_deposits_for_year(RUHR_COAL, 2026)
    _ok(
        passes,
        fails,
        "coal_1918_gt_2026",
        float(coal_18.get("coal", 0)) > float(coal_26.get("coal", 0)),
    )

    alum_18 = scale_deposits_for_year(BAUXITE, 1918)
    alum_36 = scale_deposits_for_year(BAUXITE, 1936)
    _ok(passes, fails, "aluminum_hidden_1918", "aluminum" not in alum_18)
    _ok(passes, fails, "aluminum_present_1936", float(alum_36.get("aluminum", 0)) > 0.0)

    u_18 = scale_deposits_for_year({"uranium": 2.0}, 1918)
    u_26 = scale_deposits_for_year({"uranium": 2.0}, 2026)
    _ok(passes, fails, "uranium_hidden_1918", "uranium" not in u_18)
    _ok(passes, fails, "uranium_present_2026", float(u_26.get("uranium", 0)) > 0.5)

    rgb_18 = era_mapmode_rgb(BAKU_OIL, 1918)
    rgb_26 = era_mapmode_rgb(BAKU_OIL, 2026)
    empty = resources_mapmode_rgb({})
    _ok(passes, fails, "mapmode_oil_not_empty", rgb_18 != empty and rgb_26 != empty)
    # 2026 oil is richer → higher intensity (sum of channels).
    _ok(
        passes,
        fails,
        "mapmode_2026_oil_richer",
        sum(rgb_26) > sum(rgb_18) + 0.02,
    )
    _ok(
        passes,
        fails,
        "icon_size_scales",
        icon_px_for_amount(5.0) > icon_px_for_amount(1.0),
    )

    h18 = harvest_factory_feeds(BAKU_OIL, year=1918, days=30.0)
    h36 = harvest_factory_feeds(BAKU_OIL, year=1936, days=30.0)
    _ok(passes, fails, "harvest_credits_oil", float(h36.get("oil", 0)) > 0.0)
    _ok(
        passes,
        fails,
        "harvest_oil_era",
        float(h18.get("oil", 0)) < float(h36.get("oil", 0)),
    )

    nation_36 = harvest_nation(list(GER_SLICE), year=1936, days=365.0)
    _ok(passes, fails, "nation_has_steel", float(nation_36.get("steel", 0)) > 0.0)
    _ok(passes, fails, "nation_has_oil", float(nation_36.get("oil", 0)) > 0.0)
    _ok(passes, fails, "nation_has_rubber", float(nation_36.get("rubber", 0)) > 0.0)
    trucks_ok = can_produce(nation_36, "trucks", 1)
    _ok(passes, fails, "1936_harvest_pays_trucks", trucks_ok)
    produced = produce_to_stockpile(dict(nation_36), {}, "trucks", 1) if trucks_ok else {}
    _ok(passes, fails, "produce_trucks_from_harvest", bool(produced.get("ok")))

    nation_18 = harvest_nation(list(GER_SLICE), year=1918, days=365.0)
    _ok(
        passes,
        fails,
        "1918_less_oil_than_1936",
        float(nation_18.get("oil", 0)) < float(nation_36.get("oil", 0)),
    )

    bogus = build_develop_resource_action({"coal": 3.0}, "oil", year=1936, stockpile={"steel": 40})
    _ok(passes, fails, "cannot_invent_oil", not bool(bogus.get("ok")))
    broke = build_develop_resource_action(BAKU_OIL, "oil", year=1936, stockpile={"steel": 0})
    _ok(passes, fails, "develop_needs_steel", not bool(broke.get("ok")))
    applied = apply_develop_resource(
        BAKU_OIL, {}, {"steel": 40.0}, "oil", year=1936
    )
    _ok(passes, fails, "develop_oil_ok", bool(applied.get("ok")))
    h_dev = harvest_factory_feeds(
        BAKU_OIL,
        year=1936,
        development=applied.get("development") or {},
        days=30.0,
    )
    _ok(
        passes,
        fails,
        "develop_raises_harvest",
        float(h_dev.get("oil", 0)) > float(h36.get("oil", 0)),
    )
    hidden = build_develop_resource_action(BAUXITE, "aluminum", year=1918, stockpile={"steel": 40})
    _ok(passes, fails, "cannot_develop_hidden_1918_alum", not bool(hidden.get("ok")))

    owned = harvest_factory_feeds(BAKU_OIL, year=1936, days=30.0)
    occ = harvest_by_holder(
        [{"resources": BAKU_OIL, "owner_tag": "SOV", "controller_tag": "GER"}],
        year=1936,
        days=30.0,
    )
    _ok(passes, fails, "occupier_gets_oil", float((occ.get("GER") or {}).get("oil", 0)) > 0.0)
    _ok(passes, fails, "owner_gets_nothing_while_occupied", "SOV" not in occ)
    _ok(
        passes,
        fails,
        "occupied_oil_less_than_owned",
        float((occ.get("GER") or {}).get("oil", 0)) < float(owned.get("oil", 0)),
    )
    dry = refuel_from_stockpile(0.20, 0.40, {}, 0.10)
    _ok(passes, fails, "empty_fuel_stock_no_refill", not bool(dry.get("ok")) and abs(float(dry.get("fuel_after", 1)) - 0.20) < 1e-6)
    wet = refuel_from_stockpile(0.20, 0.40, {"fuel": 8.0}, 0.10)
    _ok(passes, fails, "stockpile_refuels", bool(wet.get("ok")) and float(wet.get("fuel_after", 0)) > 0.20)
    foot = refuel_from_stockpile(0.20, 0.0, {}, 0.10)
    _ok(passes, fails, "foot_no_fuel_draw", bool(foot.get("ok")) and str(foot.get("reason")) == "foot")

    # Wiring — shipped Godot path, not a dual package.
    rhc = (
        (ROOT / "scripts" / "production" / "ResourceHarvestCalculator.gd").read_text(encoding="utf-8")
        if (ROOT / "scripts" / "production" / "ResourceHarvestCalculator.gd").is_file()
        else ""
    )
    pm = (
        (ROOT / "scripts" / "autoload" / "ProductionManager.gd").read_text(encoding="utf-8")
        if (ROOT / "scripts" / "autoload" / "ProductionManager.gd").is_file()
        else ""
    )
    overlay = (
        (ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd").read_text(encoding="utf-8")
        if (ROOT / "scripts" / "map" / "InfrastructureOverlayLayer.gd").is_file()
        else ""
    )
    renderer = (
        (ROOT / "scripts" / "map" / "MapRenderer.gd").read_text(encoding="utf-8")
        if (ROOT / "scripts" / "map" / "MapRenderer.gd").is_file()
        else ""
    )
    hud = (
        (ROOT / "scripts" / "ui" / "HudIconLibrary.gd").read_text(encoding="utf-8")
        if (ROOT / "scripts" / "ui" / "HudIconLibrary.gd").is_file()
        else ""
    )
    harness = (
        (ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd").read_text(
            encoding="utf-8"
        )
        if (ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd").is_file()
        else ""
    )
    gates = (
        (ROOT / "tools" / "eoa_full_test_gates.sh").read_text(encoding="utf-8")
        if (ROOT / "tools" / "eoa_full_test_gates.sh").is_file()
        else ""
    )
    icons_dir = ROOT / "assets" / "graphics" / "icons" / "resources"
    wiring = {
        "gd_era_scale": "func scale_deposits_for_year" in rhc and "func era_resource_scale" in rhc,
        "gd_develop": "func build_develop_resource_action" in rhc,
        "gd_feeds": "FACTORY_FEED_KEYS" in rhc or "factory_feed" in rhc,
        "pm_harvest_year": "scale_deposits_for_year" in pm and "get_current_year" in pm,
        "pm_develop": "func develop_province_resource" in pm,
        "pm_save_dev": "province_resource_dev" in pm,
        "overlay_tex": "resource_icon" in overlay and "icon_px_for_amount" in overlay,
        "renderer_era_tint": "scale_deposits_for_year" in renderer,
        "renderer_develop_btn": "Develop" in renderer and "develop_province_resource" in renderer,
        "hud_icons": "func resource_icon" in hud and "steel" in hud,
        "icon_pngs": (icons_dir / "steel_24.png").is_file() and (icons_dir / "fuel_24.png").is_file(),
        "harness_era": "scale_deposits_for_year" in harness and "develop_province_resource" in harness,
        "harness_occupier": "controller_tag" in harness and "refuel_formation_from_stockpile" in harness,
        "gd_occupier": "func harvest_holder_tag" in rhc and "func occupation_harvest_mult" in rhc,
        "gd_refuel": "func refuel_from_stockpile" in rhc,
        "pm_controller": "controller_tag" in pm and "occupation_harvest_mult" in pm,
        "pm_refuel": "func refuel_formation_from_stockpile" in pm,
        "tm_refuel": "refuel_formation_from_stockpile"
        in (
            (ROOT / "scripts" / "autoload" / "TimeManager.gd").read_text(encoding="utf-8")
            if (ROOT / "scripts" / "autoload" / "TimeManager.gd").is_file()
            else ""
        ),
        "on_official_quick": "test_era_resource_deposits_product" in gates,
    }
    for name, ok in wiring.items():
        _ok(passes, fails, name, ok)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "wiring": wiring,
        "oil_1918": oil_18,
        "oil_1936": oil_36,
        "oil_2026": oil_26,
        "nation_1936": nation_36,
        "summary": "era_resource_industry · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "integration": [
            "era_resource_deposits_product",
            "ResourceHarvestCalculator",
            "ProductionManager",
            "map_resources_mapmode_product",
        ],
    }
