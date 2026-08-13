"""Supply hub brief — pure product ranking capital + key hubs for a front.

HOI-like logistics read: when multiple industrial/key provinces exist, pick the
best supply source for a front province by land hops (primary), path mean infra
(secondary), and soft fuel/network depth (tie-break). Used by MapRenderer
G-corridor source pick + toast brief.

Does not invent SupplyManager fuel networks — pure topology + shipped board
resource/economy layers.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Set

from map_supply_corridor_product import (  # noqa: E402
    WATER,
    bfs_land_path,
    path_mean_infra,
)

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
DEFAULT_SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"
DEFAULT_OWN = "province_ownership_1936.json"
RESOURCES_LAYER = "province_resources_layer.json"
ECONOMY_LAYER = "province_economy_layer.json"

# Maginot-facing GER land cell used for default board smoke
GER_FRONT_DEFAULT = 710173

# Strategic fuel-ish goods on province_resources_layer (HOI logistics depth soft signal)
FUEL_RESOURCE_KEYS = ("oil", "fuel", "rubber")


def _is_water(p: Mapping[str, Any]) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER or dom in WATER or bool(p.get("is_sea"))


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _as_float(v: Any, default: float = 0.0) -> float:
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def province_fuel_amount(resources: Optional[Mapping[str, Any]]) -> float:
    """Sum oil/fuel/rubber on one province resource dict."""
    if not resources:
        return 0.0
    total = 0.0
    for k in FUEL_RESOURCE_KEYS:
        total += max(0.0, _as_float(resources.get(k), 0.0))
    return total


def path_fuel_total(
    path: Sequence[int],
    resources_by_pid: Optional[Mapping[int, Mapping[str, Any]]] = None,
) -> float:
    """Raw sum of fuel-ish goods along path provinces."""
    if not path or not resources_by_pid:
        return 0.0
    return sum(province_fuel_amount(resources_by_pid.get(int(pid))) for pid in path)


def hub_depot_strength(
    hub_id: int,
    eco_by_pid: Optional[Mapping[int, Mapping[str, Any]]] = None,
) -> float:
    """Hub province factories (primary) + infrastructure (secondary) as depot strength."""
    if not eco_by_pid:
        return 0.0
    e = eco_by_pid.get(int(hub_id)) or {}
    factories = max(0.0, _as_float(e.get("factories"), 0.0))
    infra = max(0.0, _as_float(e.get("infrastructure"), 0.0))
    return factories + 0.5 * infra


def compute_fuel_score(
    path: Sequence[int],
    hub_id: int,
    *,
    resources_by_pid: Optional[Mapping[int, Mapping[str, Any]]] = None,
    eco_by_pid: Optional[Mapping[int, Mapping[str, Any]]] = None,
) -> Dict[str, float]:
    """Soft fuel/network depth from path goods + hub depot.

    Prefers province_resources_layer oil/fuel/rubber along the path; if no
    resource map is available, falls back to a weak economy factories proxy
    along the path. Hub depot always uses economy factories/infra when present.

    Returns fuel_score in roughly [0, 1], path_fuel raw sum, depot_strength.
    """
    resources_by_pid = resources_by_pid or {}
    eco_by_pid = eco_by_pid or {}
    n = max(1, len(path) if path else 1)

    if resources_by_pid:
        path_fuel = path_fuel_total(path, resources_by_pid)
    elif eco_by_pid and path:
        # No resources layer: soft economy proxy (not real oil — depth signal only)
        path_fuel = sum(
            max(0.0, _as_float((eco_by_pid.get(int(p)) or {}).get("factories"), 0.0)) * 0.1
            for p in path
        )
    else:
        path_fuel = 0.0

    depot = hub_depot_strength(hub_id, eco_by_pid)
    path_mean = path_fuel / n
    # Soft caps so a long oil corridor or mega-depot cannot invert hop ranking
    path_term = min(1.0, path_mean / 8.0)
    depot_term = min(1.0, depot / 15.0)
    fuel_score = 0.55 * path_term + 0.45 * depot_term
    return {
        "fuel_score": round(fuel_score, 4),
        "path_fuel": round(path_fuel, 2),
        "depot_strength": round(depot, 2),
    }


def collect_hub_candidates(
    sc: Mapping[str, Any],
    tag: str,
    *,
    base: Optional[Mapping[int, dict]] = None,
) -> List[Dict[str, Any]]:
    """Capital + key_provinces for tag (deduped, capital first)."""
    tag_u = str(tag or "").strip().upper()
    out: List[Dict[str, Any]] = []
    seen: Set[int] = set()
    for c in sc.get("countries") or []:
        if str(c.get("tag") or "").strip().upper() != tag_u:
            continue
        capital = int(c.get("capital_province_id") or 0)
        keys = [int(x) for x in (c.get("key_provinces") or [])]
        ordered: List[int] = []
        if capital > 0:
            ordered.append(capital)
        for k in keys:
            if k > 0 and k not in ordered:
                ordered.append(k)
        for pid in ordered:
            if pid in seen:
                continue
            seen.add(pid)
            name = ""
            if base and pid in base:
                name = str((base.get(pid) or {}).get("name") or "")
            role = "capital" if pid == capital else "key_hub"
            out.append({"province_id": pid, "role": role, "name": name or ("#%d" % pid)})
        break
    return out


def score_hub_to_front(
    adj: Mapping[str, Sequence[Any]],
    hub_id: int,
    front_id: int,
    *,
    land_only: Optional[Set[int]] = None,
    infra_by_pid: Optional[Mapping[int, float]] = None,
    resources_by_pid: Optional[Mapping[int, Mapping[str, Any]]] = None,
    eco_by_pid: Optional[Mapping[int, Mapping[str, Any]]] = None,
    limit: int = 60,
) -> Dict[str, Any]:
    """Lower hops better; higher mean infra then fuel_score better on ties."""
    path = bfs_land_path(adj, hub_id, front_id, land_only=land_only, limit=limit)
    if not path or len(path) < 1:
        return {
            "ok": False,
            "hub_id": hub_id,
            "front_id": front_id,
            "hops": -1,
            "path": [],
            "mean_infra": 0.0,
            "fuel_score": 0.0,
            "path_fuel": 0.0,
            "score": 1e9,
        }
    hops = max(0, len(path) - 1)
    mean_i = path_mean_infra(path, infra_by_pid or {})
    fuel = compute_fuel_score(
        path,
        hub_id,
        resources_by_pid=resources_by_pid,
        eco_by_pid=eco_by_pid,
    )
    fuel_s = float(fuel.get("fuel_score") or 0.0)
    path_fuel = float(fuel.get("path_fuel") or 0.0)
    # Primary: hops; secondary: high infra; tertiary: fuel (tiny weight — never invert hops)
    score = float(hops) - 0.04 * mean_i - 0.01 * fuel_s
    return {
        "ok": True,
        "hub_id": hub_id,
        "front_id": front_id,
        "hops": hops,
        "path": path,
        "mean_infra": round(mean_i, 2),
        "fuel_score": round(fuel_s, 4),
        "path_fuel": round(path_fuel, 2),
        "score": round(score, 4),
    }


def pick_best_hub(
    candidates: Sequence[Mapping[str, Any]],
    scored: Sequence[Mapping[str, Any]],
) -> Optional[Dict[str, Any]]:
    ok_rows = [dict(s) for s in scored if s.get("ok")]
    if not ok_rows:
        return None
    # score already encodes hops > mean_infra > fuel; explicit keys keep ties stable
    ok_rows.sort(
        key=lambda r: (
            float(r.get("score") or 1e9),
            int(r.get("hops") or 99),
            -float(r.get("mean_infra") or 0.0),
            -float(r.get("fuel_score") or 0.0),
        )
    )
    best = ok_rows[0]
    meta = next(
        (c for c in candidates if int(c.get("province_id") or 0) == int(best["hub_id"])),
        {},
    )
    best["role"] = meta.get("role") or "hub"
    best["name"] = meta.get("name") or ("#%d" % int(best["hub_id"]))
    return best


def format_hub_brief_toast(
    best: Mapping[str, Any],
    front_id: int,
    *,
    front_name: str = "",
) -> str:
    hops = int(best.get("hops") or 0)
    name = str(best.get("name") or best.get("hub_id"))
    role = str(best.get("role") or "hub")
    fn = front_name or ("#%d" % int(front_id))
    parts = ["Supply hub · %s (%s) → %s · %d hops" % (name, role, fn, hops)]
    if "fuel_score" in best and best.get("fuel_score") is not None:
        try:
            fs = float(best.get("fuel_score"))
            parts.append("fuel %.2f" % fs)
        except (TypeError, ValueError):
            pass
    parts.append("G corridor")
    return " · ".join(parts)


def build_map_supply_hub_brief_product(
    board_dir: str = "",
    scenario_path: str = "",
    *,
    tag: str = "GER",
    front_id: int = 0,
) -> Dict[str, Any]:
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    sc_path = Path(scenario_path) if scenario_path else DEFAULT_SCENARIO
    fails: List[str] = []
    passes: List[str] = []

    base_list = _load_json(d / "provinces_base.json")["provinces"]
    base = {int(p["id"]): p for p in base_list}
    adj = (_load_json(d / "province_adjacency.json").get("adjacency") or {})
    own = (_load_json(d / DEFAULT_OWN).get("owners") or {})
    eco_raw = (_load_json(d / ECONOMY_LAYER).get("provinces") or {})
    eco_by_pid: Dict[int, Dict[str, Any]] = {
        int(k): dict(v or {}) for k, v in eco_raw.items()
    }
    sc = _load_json(sc_path) if sc_path.is_file() else {}

    # Resources layer preferred for path fuel goods; optional if missing
    resources_by_pid: Dict[int, Dict[str, Any]] = {}
    res_path = d / RESOURCES_LAYER
    if res_path.is_file():
        res_raw = (_load_json(res_path).get("provinces") or {})
        resources_by_pid = {int(k): dict(v or {}) for k, v in res_raw.items()}
        passes.append("resources_layer_loaded")
    else:
        passes.append("resources_layer_missing_eco_fallback")

    tag_u = str(tag or "GER").strip().upper()
    front = int(front_id) if int(front_id or 0) > 0 else GER_FRONT_DEFAULT

    land_only = {
        pid
        for pid, p in base.items()
        if own.get(str(pid)) == tag_u and not _is_water(p)
    }
    if not land_only:
        # fall back: any land owned cells + all land if tag sparse
        land_only = {pid for pid, p in base.items() if not _is_water(p)}
        fails.append("tag_land_empty_used_all_land")

    infra = {
        int(k): float((v or {}).get("infrastructure") or 0) for k, v in eco_by_pid.items()
    }

    candidates = collect_hub_candidates(sc, tag_u, base=base)
    if not candidates:
        fails.append("no_hub_candidates")
    else:
        passes.append("hub_candidates_n=%d" % len(candidates))

    if front not in base:
        fails.append("front_missing=%d" % front)
    elif _is_water(base[front]):
        fails.append("front_is_water")
    else:
        passes.append("front_land")

    scored: List[Dict[str, Any]] = []
    for c in candidates:
        pid = int(c["province_id"])
        row = score_hub_to_front(
            adj,
            pid,
            front,
            land_only=land_only if land_only else None,
            infra_by_pid=infra,
            resources_by_pid=resources_by_pid or None,
            eco_by_pid=eco_by_pid or None,
        )
        row["role"] = c.get("role")
        row["name"] = c.get("name")
        scored.append(row)
        if row.get("ok"):
            passes.append(
                "hub_%d_hops=%d_fuel=%.2f"
                % (pid, int(row.get("hops") or 0), float(row.get("fuel_score") or 0))
            )
        else:
            fails.append("hub_%d_no_path" % pid)

    best = pick_best_hub(candidates, scored)
    if best is None:
        fails.append("no_reachable_hub")
    else:
        passes.append("best_hub=%d" % int(best["hub_id"]))
        # Best should be reachable with finite hops
        if int(best.get("hops") or -1) < 0:
            fails.append("best_hops_invalid")
        else:
            passes.append("best_hops=%d" % int(best["hops"]))
        if best.get("fuel_score") is not None:
            passes.append("best_fuel_score=%.4f" % float(best.get("fuel_score") or 0))

    front_name = str((base.get(front) or {}).get("name") or "")
    toast = format_hub_brief_toast(best or {}, front, front_name=front_name) if best else ""

    # Capital-only vs multi-hub: multi is the depth feature
    multi = len(candidates) >= 2
    if multi:
        passes.append("multi_hub_candidates")
    capital_id = int(candidates[0]["province_id"]) if candidates else 0
    if best and multi and int(best["hub_id"]) != capital_id:
        passes.append("best_not_always_capital")

    ok = best is not None and "no_hub_candidates" not in fails and "front_is_water" not in fails
    # Soft: tag_land_empty is warn not hard fail if path still works
    hard_fails = [f for f in fails if not f.startswith("tag_land_empty") and not f.startswith("hub_") or f == "no_reachable_hub" or f == "no_hub_candidates"]
    # simplify ok
    ok = best is not None and "no_hub_candidates" not in fails and "front_missing" not in str(fails)

    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "tag": tag_u,
        "front_id": front,
        "front_name": front_name,
        "candidates": candidates,
        "scored": scored,
        "best": best,
        "toast": toast,
        "multi_hub": multi,
        "pass": passes,
        "fail": fails,
        "summary": (
            "Supply hub brief · %s · front #%d · best=%s · hops=%s · fuel=%s · %s"
            % (
                tag_u,
                front,
                (best or {}).get("hub_id"),
                (best or {}).get("hops"),
                (best or {}).get("fuel_score"),
                "PASS" if ok else "FAIL",
            )
        ),
        "integration": [
            "map_supply_hub_brief_product",
            "map_supply_corridor_product",
            "supply_hubs",
            "m4_depth",
            "fuel_score",
            "world_accurate",
        ],
    }


def map_supply_hub_brief_integrity(
    board_dir: str = "",
    *,
    tag: str = "GER",
    front_id: int = 0,
) -> Dict[str, Any]:
    p = build_map_supply_hub_brief_product(
        board_dir=board_dir, tag=tag, front_id=front_id
    )
    return {
        "ok": bool(p.get("ok")),
        "best_hub": (p.get("best") or {}).get("hub_id"),
        "hops": (p.get("best") or {}).get("hops"),
        "fuel_score": (p.get("best") or {}).get("fuel_score"),
        "multi_hub": p.get("multi_hub"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
