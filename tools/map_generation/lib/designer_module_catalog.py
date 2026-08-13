"""Designer module catalog — real data/modules + unit template slots.

Loads data/designers/full_module_catalog.json (or rebuilds from data/modules).
Provides domain defaults, option boards, and icon paths for full designers.
"""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

_ROOT = Path(__file__).resolve().parents[3]
_CATALOG_PATH = _ROOT / "data" / "designers" / "full_module_catalog.json"
_ICON_MAP_PATH = _ROOT / "data" / "designers" / "module_icon_map.json"

DOMAINS = ("land", "naval", "air", "space")

_cache: Optional[Dict[str, Any]] = None
_icon_cache: Optional[Dict[str, str]] = None


def load_full_module_catalog() -> Dict[str, Any]:
    global _cache
    if _cache is not None:
        return _cache
    if _CATALOG_PATH.is_file():
        _cache = json.loads(_CATALOG_PATH.read_text(encoding="utf-8"))
        return _cache
    # Minimal offline fallback
    _cache = {
        "module_n": 0,
        "domains": {
            d: {"slots": {}, "defaults": {}, "slot_n": 0, "option_total": 0, "design_template": None}
            for d in DOMAINS
        },
        "version": 0,
        "empty": True,
    }
    return _cache


def load_module_icon_map() -> Dict[str, str]:
    global _icon_cache
    if _icon_cache is not None:
        return _icon_cache
    if _ICON_MAP_PATH.is_file():
        _icon_cache = json.loads(_ICON_MAP_PATH.read_text(encoding="utf-8"))
        return _icon_cache
    _icon_cache = {}
    return _icon_cache


def module_icon_path(module_id: str) -> str:
    mid = str(module_id or "")
    imap = load_module_icon_map()
    if mid in imap:
        return str(imap[mid])
    return "res://assets/graphics/icons/modules/%s.png" % mid


def category_icon_path(slot: str) -> str:
    s = str(slot or "MainWeapon")
    return "res://assets/graphics/icons/modules/category_%s.png" % s.lower()


def domain_catalog(domain: str = "land") -> Dict[str, Any]:
    cat = load_full_module_catalog()
    dom = str(domain or "land").lower()
    if dom not in DOMAINS:
        dom = "land"
    entry = (cat.get("domains") or {}).get(dom) or {}
    return {
        "domain": dom,
        "slots": entry.get("slots") or {},
        "defaults": entry.get("defaults") or {},
        "slot_n": int(entry.get("slot_n", 0)),
        "option_total": int(entry.get("option_total", 0)),
        "design_template": entry.get("design_template"),
        "module_n_global": int(cat.get("module_n", 0)),
        "empty": bool(entry.get("slot_n", 0) < 1),
    }


def default_loadout(domain: str = "land") -> List[Dict[str, Any]]:
    """Return list of module rows for designer board (real modules)."""
    entry = domain_catalog(domain)
    rows: List[Dict[str, Any]] = []
    defaults = entry.get("defaults") or {}
    slots = entry.get("slots") or {}
    for slot, default_mid in defaults.items():
        slot_info = slots.get(slot) or {}
        options = slot_info.get("options") or []
        chosen = None
        for o in options:
            if str(o.get("module_id")) == str(default_mid):
                chosen = o
                break
        if chosen is None and options:
            chosen = options[0]
        if chosen is None:
            continue
        cost = chosen.get("cost") or {}
        cost_sum = 0.0
        if isinstance(cost, dict):
            cost_sum = sum(float(v or 0) for v in cost.values())
        rel = 0.8 + float(chosen.get("reliability_bonus", 0) or 0) - float(chosen.get("reliability_penalty", 0) or 0)
        rel = max(0.35, min(0.98, rel))
        weight = max(0.5, float(chosen.get("production_time", 20) or 20) / 10.0)
        rows.append({
            "slot": slot,
            "module_id": str(chosen.get("module_id")),
            "name": str(chosen.get("name", chosen.get("module_id"))),
            "category": str(chosen.get("category", slot)),
            "tier": int(chosen.get("tier", 1)),
            "weight": weight,
            "reliability": rel,
            "cost": max(1.0, cost_sum if cost_sum > 0 else float(chosen.get("production_time", 10) or 10) / 5.0),
            "soft_attack": float(chosen.get("soft_attack", 0) or 0),
            "hard_attack": float(chosen.get("hard_attack", 0) or 0),
            "icon": str(chosen.get("icon") or module_icon_path(str(chosen.get("module_id")))),
            "option_n": int(slot_info.get("option_n", len(options))),
        })
    return rows


def catalog_integrity() -> Dict[str, Any]:
    cat = load_full_module_catalog()
    domains = cat.get("domains") or {}
    ok_domains = 0
    issues: List[str] = []
    for d in DOMAINS:
        e = domains.get(d) or {}
        if int(e.get("slot_n", 0)) >= 3 and int(e.get("option_total", 0)) >= 12:
            ok_domains += 1
        else:
            issues.append("%s slots=%s opts=%s" % (d, e.get("slot_n"), e.get("option_total")))
    ok = ok_domains >= 4 and int(cat.get("module_n", 0)) >= 500
    return {
        "ok": ok,
        "module_n": int(cat.get("module_n", 0)),
        "ok_domains": ok_domains,
        "issues": issues,
        "summary": "Designer module catalog %s · modules %d · domains %d/4"
        % ("PASS" if ok else "FAIL", int(cat.get("module_n", 0)), ok_domains),
        "empty": False,
    }


def list_required_icon_ids() -> List[str]:
    """Category icons + all default and option module ids for designer boards."""
    ids: List[str] = []
    cat = load_full_module_catalog()
    for d, entry in (cat.get("domains") or {}).items():
        for slot, sinfo in (entry.get("slots") or {}).items():
            ids.append("category_%s" % str(slot).lower())
            for o in (sinfo.get("options") or []):
                mid = str(o.get("module_id", ""))
                if mid:
                    ids.append(mid)
    # unique preserve order
    seen = set()
    out = []
    for i in ids:
        if i not in seen:
            seen.add(i)
            out.append(i)
    return out
