"""HOI strategic map product — chokes, supply hubs, resources on world_accurate.

Gates:
  - naval chokepoints exist, are sea, and cover core families (Gibraltar/Suez/…)
  - industrial hubs have elevated infrastructure (supply nodes)
  - strategic resources present for majors (oil/steel/coal floors)
  - capital↔border supply sample path uses adjacency (infra-weighted length)
"""
from __future__ import annotations

import json
from collections import Counter, deque
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
DEFAULT_SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"

CHOKE_FAMILIES = (
    "gibraltar",
    "suez",
    "malacca",
    "hormuz",
    "bospor",
    "english channel",
    "danish",
    "tsushima",
    "panama",
)

WATER = frozenset({"sea", "ocean", "water", "lake", "strait"})


def _is_water(p: dict) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER or dom in WATER or bool(p.get("is_sea"))


def _bfs_path(
    adj: Dict[str, List[int]],
    start: int,
    goal: int,
    *,
    land_only: Optional[Set[int]] = None,
    limit: int = 80,
) -> Optional[List[int]]:
    if start == goal:
        return [start]
    q = deque([(start, [start])])
    seen = {start}
    while q:
        n, path = q.popleft()
        if len(path) > limit:
            continue
        for x in adj.get(str(n)) or []:
            xi = int(x)
            if xi in seen:
                continue
            if land_only is not None and xi not in land_only:
                continue
            np = path + [xi]
            if xi == goal:
                return np
            seen.add(xi)
            q.append((xi, np))
    return None


def build_world_accurate_strategic_map_product(
    board_dir: Optional[Path] = None,
    scenario_path: Optional[Path] = None,
) -> Dict[str, Any]:
    d = Path(board_dir or DEFAULT_DIR)
    sc_path = Path(scenario_path or DEFAULT_SCENARIO)
    fails: List[str] = []
    passes: List[str] = []

    base = {
        int(p["id"]): p
        for p in json.loads((d / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    }
    adj = (
        json.loads((d / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency")
        or {}
    )
    own = (
        json.loads((d / "province_ownership_1936.json").read_text(encoding="utf-8")).get("owners")
        or {}
    )
    eco = (
        json.loads((d / "province_economy_layer.json").read_text(encoding="utf-8")).get("provinces")
        or {}
    )
    res = (
        json.loads((d / "province_resources_layer.json").read_text(encoding="utf-8")).get(
            "provinces"
        )
        or {}
    )
    choke = json.loads((d / "naval_chokepoints.json").read_text(encoding="utf-8"))
    sc = json.loads(sc_path.read_text(encoding="utf-8"))

    # --- Chokepoints ---
    choke_ids = [int(x) for x in (choke.get("chokepoint_province_ids") or [])]
    if len(choke_ids) < 15:
        fails.append("choke_n=%d" % len(choke_ids))
    else:
        passes.append("choke_n=%d" % len(choke_ids))
    names = []
    for pid in choke_ids:
        p = base.get(pid) or {}
        names.append(str(p.get("name") or "").lower())
        if not _is_water(p) and "panama" not in str(p.get("name") or "").lower():
            fails.append("choke_land %d %s" % (pid, p.get("name")))
    blob = " ".join(names)
    for fam in CHOKE_FAMILIES:
        if fam in blob:
            passes.append("choke_%s" % fam.replace(" ", "_"))
        else:
            # panama optional if missing from board
            if fam == "panama":
                passes.append("choke_panama_optional_miss")
            else:
                fails.append("choke_missing_%s" % fam.replace(" ", "_"))

    # --- Industrial supply hubs (infra) ---
    hub_infra = []
    for c in sc.get("countries") or []:
        tag = c.get("tag")
        for pid in c.get("key_provinces") or []:
            erow = eco.get(str(int(pid))) or {}
            infra = int(erow.get("infrastructure") or 0)
            hub_infra.append((tag, int(pid), infra))
            if infra < 4:
                fails.append("hub_infra_low %s:%d=%d" % (tag, pid, infra))
            else:
                passes.append("hub_infra %s:%d=%d" % (tag, pid, infra))
    if hub_infra:
        avg = sum(x[2] for x in hub_infra) / len(hub_infra)
        if avg >= 4.5:
            passes.append("hub_infra_avg=%.1f" % avg)
        else:
            fails.append("hub_infra_avg_low=%.1f" % avg)

    # --- Strategic resources by major ---
    major_res: Dict[str, Counter] = {}
    for tag in ("GER", "USA", "SOV", "ENG", "FRA", "JAP", "ITA", "POL"):
        tc = Counter()
        for pid, p in base.items():
            if own.get(str(pid)) != tag or _is_water(p):
                continue
            row = res.get(str(pid)) or {}
            for k, v in row.items():
                try:
                    if float(v) > 0:
                        tc[k] += 1
                except (TypeError, ValueError):
                    pass
        major_res[tag] = tc
        # floors: coal or steel present; oil for USA/SOV/ENG after paint
        if tc.get("coal", 0) + tc.get("steel", 0) < 10 and tag not in ("JAP",):
            # JAP may be thin land
            if tag in ("GER", "USA", "ENG", "FRA", "SOV", "ITA", "POL"):
                fails.append("%s_no_industry_resources %s" % (tag, dict(tc)))
            else:
                passes.append("%s_res_thin_ok" % tag)
        else:
            passes.append("%s_res=%s" % (tag, dict(tc)))

    # Soft oil floors when paint has run
    oil_usa = int(major_res.get("USA", Counter()).get("oil", 0))
    oil_sov = int(major_res.get("SOV", Counter()).get("oil", 0))
    if oil_usa >= 20:
        passes.append("usa_oil=%d" % oil_usa)
    elif oil_usa > 0:
        passes.append("usa_oil_partial=%d" % oil_usa)
    else:
        fails.append("usa_oil_missing")
    if oil_sov >= 5:
        passes.append("sov_oil=%d" % oil_sov)
    elif oil_sov > 0:
        passes.append("sov_oil_partial=%d" % oil_sov)
    else:
        fails.append("sov_oil_missing")

    # --- Capital to west border supply path (GER) ---
    ger_land = {
        pid
        for pid, p in base.items()
        if own.get(str(pid)) == "GER" and not _is_water(p)
    }
    path = _bfs_path(adj, 710300, 710173, land_only=ger_land, limit=40)
    if path and len(path) >= 2:
        path_infra = [int((eco.get(str(p)) or {}).get("infrastructure") or 0) for p in path]
        passes.append("ger_supply_path_len=%d mean_infra=%.1f" % (len(path), sum(path_infra) / len(path_infra)))
    else:
        fails.append("ger_supply_path_missing")

    ok = len(fails) == 0
    score = max(0.0, min(1.0, len(passes) / max(1, len(passes) + len(fails) * 2)))
    if ok:
        score = max(score, 0.88)
    label = (
        "Accurate strategic map · chokes=%d · hubs=%d · usa_oil=%d · %s"
        % (len(choke_ids), len(hub_infra), oil_usa, "PASS" if ok else "FAIL")
    )
    return {
        "ok": ok,
        "empty": False,
        "score": score,
        "status": "PASS" if ok else "FAIL",
        "choke_n": len(choke_ids),
        "hub_n": len(hub_infra),
        "major_resources": {k: dict(v) for k, v in major_res.items()},
        "ger_supply_path": path,
        "pass": passes,
        "fail": fails,
        "summary": label,
        "plain": label + ("\nFAIL: " + " | ".join(fails) if fails else ""),
        "integration": [
            "world_accurate_strategic_map_product",
            "chokepoints",
            "supply",
            "resources",
            "world_accurate",
        ],
    }


def world_accurate_strategic_map_integrity() -> Dict[str, Any]:
    p = build_world_accurate_strategic_map_product()
    return {
        "ok": bool(p.get("ok")),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
