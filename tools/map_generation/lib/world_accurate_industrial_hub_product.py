"""HOI industrial hub map product — factory readability on world_accurate key_provinces.

Gates that scenario industrial hubs have elevated city tier + factory counts so
political/development mapmodes show power centers (Berlin, Ruhr proxies, NYC…).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
DEFAULT_SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"


def build_world_accurate_industrial_hub_product(
    board_dir: Optional[Path] = None,
    scenario_path: Optional[Path] = None,
    *,
    min_hubs: int = 24,
    min_capital_factories: int = 6,
    min_hub_factories: int = 4,
    min_capital_tier: int = 3,
) -> Dict[str, Any]:
    d = Path(board_dir or DEFAULT_DIR)
    sc_path = Path(scenario_path or DEFAULT_SCENARIO)
    sc = json.loads(sc_path.read_text(encoding="utf-8"))
    city = json.loads((d / "province_city_layer.json").read_text(encoding="utf-8")).get(
        "provinces"
    ) or {}
    eco = json.loads((d / "province_economy_layer.json").read_text(encoding="utf-8")).get(
        "provinces"
    ) or {}
    fails: List[str] = []
    passes: List[str] = []
    hubs: List[Dict[str, Any]] = []

    for c in sc.get("countries") or []:
        tag = str(c.get("tag") or "").upper()
        cap = int(c.get("capital_province_id") or 0)
        keys = [int(x) for x in (c.get("key_provinces") or []) if int(x) > 0]
        if cap and cap not in keys:
            keys = [cap] + keys
        for pid in keys:
            crow = city.get(str(pid)) or {}
            erow = eco.get(str(pid)) or {}
            tier = int(crow.get("tier") or 0)
            factories = int(erow.get("factories") or 0)
            is_cap = pid == cap
            need_f = min_capital_factories if is_cap else min_hub_factories
            need_t = min_capital_tier if is_cap else 3
            row = {
                "tag": tag,
                "province_id": pid,
                "is_capital": is_cap,
                "city_name": crow.get("city_name") or crow.get("name"),
                "tier": tier,
                "factories": factories,
                "infrastructure": int(erow.get("infrastructure") or 0),
                "industrial_hub": bool(erow.get("industrial_hub") or crow.get("hub")),
            }
            hubs.append(row)
            if factories < need_f:
                fails.append("%s:%d factories=%d need>=%d" % (tag, pid, factories, need_f))
            else:
                passes.append("%s:%d fac=%d" % (tag, pid, factories))
            if tier < need_t:
                fails.append("%s:%d tier=%d need>=%d" % (tag, pid, tier, need_t))
            else:
                passes.append("%s:%d tier=%d" % (tag, pid, tier))

    if len(hubs) < min_hubs:
        fails.append("hub_n=%d need>=%d" % (len(hubs), min_hubs))
    else:
        passes.append("hub_n=%d" % len(hubs))

    # Capitals must be industrial hubs
    for h in hubs:
        if h.get("is_capital") and not h.get("industrial_hub") and h.get("factories", 0) < min_capital_factories:
            fails.append("capital_not_hub %s" % h.get("tag"))

    ok = len(fails) == 0
    score = 0.0 if not hubs else max(0.0, min(1.0, len(passes) / max(1, len(passes) + len(fails) * 2)))
    if ok:
        score = max(score, 0.9)
    label = "Accurate industrial hubs · n=%d · %s" % (len(hubs), "PASS" if ok else "FAIL")
    return {
        "ok": ok,
        "empty": len(hubs) == 0,
        "score": score,
        "status": "PASS" if ok else "FAIL",
        "hub_n": len(hubs),
        "hubs": hubs,
        "pass": passes,
        "fail": fails,
        "summary": label,
        "plain": label + ("\nFAIL: " + " | ".join(fails) if fails else ""),
        "integration": [
            "world_accurate_industrial_hub_product",
            "mapmode",
            "factories",
            "world_accurate",
        ],
    }


def world_accurate_industrial_hub_integrity() -> Dict[str, Any]:
    p = build_world_accurate_industrial_hub_product()
    return {
        "ok": bool(p.get("ok")),
        "hub_n": p.get("hub_n"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
